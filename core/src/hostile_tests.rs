//! Arbitrary and multi-byte-heavy text thrown at every reader of what
//! strangers send: none may panic. A fixed seed keeps a failure
//! reproducible; the pieces are chosen to land cuts inside characters,
//! open constructs that never close, and numbers that overflow.

use std::collections::HashSet;

/// xorshift64*: small, fast, and the same everywhere.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }

    fn pick<'a>(&mut self, from: &[&'a str]) -> &'a str {
        from[self.below(from.len())]
    }
}

/// Characters of one to four bytes, and ones whose case changes their
/// length (Kelvin sign, dotted capital I).
const CHARS: &[&str] = &[
    "a", "Z", "0", "9", " ", "\t", "\n", "\r\n", ":", ";", ",", ".", "-", "+", "#", "@", "&", "\\",
    "\"", "'", "(", ")", "{", "}", "<", ">", "=", "/", "%", "é", "ß", "€", "𝄞", "😀", "\u{202E}",
    "\u{200B}", "\u{FEFF}", "\u{0}", "\u{7F}", "K", "İ", "ﬀ", "Ω", "中", "ア",
];

/// Pieces of the formats the readers look for.
const PIECES: &[&str] = &[
    "cid:",
    "CID:",
    "cid",
    "cidé",
    "data:image/png;base64,",
    "url(",
    "URL(",
    "u\\72l(",
    "\\",
    "@import",
    "@\\69mport",
    "image-set(",
    "expression(",
    "http://",
    "https://",
    "mailto:",
    "<img src=\"",
    "<img src='cid:",
    "\">",
    "<a href=\"",
    "</a>",
    "<ol start=\"",
    "<ol>",
    "<li>",
    "</li>",
    "</ol>",
    "<ul>",
    "<p>",
    "<br>",
    "<pre>",
    "<style>",
    "</style>",
    "<div style=\"",
    "background:url(",
    "<table><tr><td>",
    "</td><td>",
    "width=\"",
    "height=\"",
    "4294967295",
    "18446744073709551616",
    "-1",
    "99999999999999999999",
    "2026-10-2",
    "2026-10-24T07:15",
    "T",
    "Z",
    "BEGIN:VCALENDAR\r\n",
    "BEGIN:VEVENT\r\n",
    "END:VEVENT\r\n",
    "BEGIN:VTIMEZONE\r\n",
    "END:VTIMEZONE\r\n",
    "BEGIN:STANDARD\r\n",
    "END:STANDARD\r\n",
    "DTSTART:",
    "DTSTART;TZID=",
    "DTEND:",
    "DURATION:P",
    "RRULE:FREQ=YEARLY;BYMONTH=",
    ";BYDAY=",
    "TZOFFSETTO:",
    "UID:",
    "SUMMARY:",
    "ATTENDEE;CN=\"",
    "ORGANIZER:mailto:",
    "SEQUENCE:",
    "\r\n ",
    "INBOX",
    "INBOX.",
    "&",
    "&-",
    "&AOk-",
    "&Jjo",
    "NUL",
    "con.",
    "COM1",
    "...",
    "Re: ",
    "Fwd: ",
    "R: ",
    "On ",
    " wrote:",
    "> ",
    ">>",
    "-- ",
    "\r\n\r\n",
    "Friday ",
    "10:00",
    "3 May ",
    "tomorrow",
    "domani",
    "entro il ",
    "scade il ",
    "1Z",
    "€ 12,50",
    "Totale: ",
];

fn text(rng: &mut Rng, max_pieces: usize) -> String {
    let n = rng.below(max_pieces) + 1;
    let mut s = String::new();
    for _ in 0..n {
        if rng.below(3) == 0 {
            s.push_str(rng.pick(PIECES));
        } else {
            for _ in 0..rng.below(4) + 1 {
                s.push_str(rng.pick(CHARS));
            }
        }
    }
    s
}

/// JSON-LD of the kinds the Vault reads, with text in its values.
fn json_ld(rng: &mut Rng) -> String {
    let kinds = [
        "ParcelDelivery",
        "Order",
        "Invoice",
        "FlightReservation",
        "TrainReservation",
        "LodgingReservation",
        "EventReservation",
    ];
    let mut v = String::new();
    for _ in 0..3 {
        v.push_str(&text(rng, 4));
    }
    let v = serde_json::Value::String(v).to_string();
    let kind = kinds[rng.below(kinds.len())];
    format!(
        "<script type=\"application/ld+json\">{{\"@context\":\"http://schema.org\",\"@type\":\"{kind}\",\
         \"expectedArrivalUntil\":{v},\"startDate\":{v},\"checkinTime\":{v},\"paymentDueDate\":{v},\
         \"trackingNumber\":{v},\"orderNumber\":{v},\"totalPaymentDue\":{{\"price\":{v},\"priceCurrency\":{v}}},\
         \"reservationFor\":{{\"name\":{v},\"departureTime\":{v},\"startDate\":{v},\
         \"departureAirport\":{{\"iataCode\":{v}}},\"arrivalAirport\":{{\"iataCode\":{v}}}}}}}</script>"
    )
}

/// Rounds per reader: `PIUMA_FUZZ_ROUNDS` runs longer, `PIUMA_FUZZ_SEED`
/// tries other texts.
fn rounds() -> usize {
    std::env::var("PIUMA_FUZZ_ROUNDS")
        .ok()
        .and_then(|r| r.parse().ok())
        .unwrap_or(3_000)
}

fn rng(seed: u64) -> Rng {
    let extra: u64 = std::env::var("PIUMA_FUZZ_SEED")
        .ok()
        .and_then(|r| r.parse().ok())
        .unwrap_or(0);
    Rng((seed ^ extra.wrapping_mul(0x9E37_79B9_7F4A_7C15)) | 1)
}

#[test]
fn readers_of_html_and_text_never_panic() {
    let mut rng = rng(0x5EED_0001);
    for _ in 0..rounds() {
        let s = text(&mut rng, 40);
        let r = crate::reading::from_html(&s);
        let _ = crate::reading::plain_text(&r);
        let _ = crate::reading::from_text(&s);
        let _ = crate::reading::cover(&s);
        let _ = crate::reading::normalize_text(&s, true, true);
        let _ = crate::reading::normalize_text(&s, false, false);
        let _ = crate::imap::clean_preview(&s);
        let _ = crate::language::detect(&s);
        let _ = crate::dates::find(&s, 1_790_000_000);
        let _ = crate::brief::bare_subject(&s);
        let _ = crate::signature::split_quote(&s);
        let _ = crate::rich::plain(&s);
        let _ = crate::impostor::skeleton(&s);
        let _ = crate::pec::subject(&s);
    }
}

#[test]
fn the_original_view_never_panics() {
    let mut rng = rng(0x5EED_0002);
    let inline = |_: &str| Some(b"\x89PNG\r\n\x1a\n".to_vec());
    for _ in 0..rounds() {
        let s = text(&mut rng, 40);
        let _ = crate::original::original(
            &s,
            crate::reading::Options::default(),
            &inline,
            &crate::original::Loaded::new(),
        );
        let _ = crate::original::is_layout(&s);
        let styled = format!(
            "<div style=\"{}\">x</div><style>{}</style>",
            s.replace('"', "'"),
            s
        );
        let _ = crate::original::remote_images(&styled, crate::reading::Options::default());
    }
}

#[test]
fn calendar_invites_never_panic() {
    let mut rng = rng(0x5EED_0003);
    for _ in 0..rounds() {
        let s = format!(
            "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\n{}BEGIN:VEVENT\r\nUID:{}\r\nDTSTART:{}\r\n{}END:VEVENT\r\nEND:VCALENDAR\r\n",
            text(&mut rng, 20),
            text(&mut rng, 3),
            text(&mut rng, 3),
            text(&mut rng, 30),
        );
        let _ = crate::invite::parse(&s);
        let _ = crate::invite::events(&s);
        let _ = crate::invite::refresh_interval(&s);
        let _ = crate::invite::calendar_name(&s);
        let raw = text(&mut rng, 30);
        let _ = crate::invite::parse(&raw);
    }
}

#[test]
fn the_vault_never_panics() {
    let mut rng = rng(0x5EED_0004);
    for _ in 0..rounds() {
        let html = format!(
            "<html><head>{}</head><body>{}</body></html>",
            json_ld(&mut rng),
            text(&mut rng, 20)
        );
        let body = text(&mut rng, 40);
        let subject = text(&mut rng, 6);
        let src = crate::vault::Source {
            subject: &subject,
            from_name: "Shop",
            message_id: "<id@x>",
            received_at: 1_790_000_000,
            text: &body,
            html: Some(&html),
            attachments: &[],
        };
        let _ = crate::vault::extract(&src);
        let _ = crate::vault::extract_kept(&src);
        let src = crate::vault::Source { html: None, ..src };
        let _ = crate::vault::extract(&src);
    }
}

#[test]
fn whole_messages_never_panic() {
    let mut rng = rng(0x5EED_0005);
    for _ in 0..rounds() / 3 {
        let raw = format!(
            "From: {}\r\nSubject: {}\r\nContent-Type: multipart/alternative; boundary=\"b\"\r\n\r\n--b\r\nContent-Type: text/plain; format=flowed; delsp=yes\r\n\r\n{}\r\n--b\r\nContent-Type: text/html\r\n\r\n{}{}\r\n--b\r\nContent-Type: text/calendar\r\n\r\n{}\r\n--b--\r\n",
            text(&mut rng, 4),
            text(&mut rng, 4),
            text(&mut rng, 20),
            json_ld(&mut rng),
            text(&mut rng, 30),
            text(&mut rng, 10),
        );
        // Unshielded: a panic here is a bug to fix, not one to hide.
        let body = crate::imap::parse_body_whole(raw.as_bytes());
        let _ = crate::imap::reader_preview(&body.text, body.html.as_deref());
        let _ = crate::newsletter::words(&body.text, body.html.as_deref());
    }
}

#[test]
fn server_names_and_replies_never_panic() {
    let mut rng = rng(0x5EED_0006);
    let none = HashSet::new();
    for _ in 0..rounds() {
        let s = text(&mut rng, 12);
        let _ = crate::imap::utf7_decode(&s);
        let _ = crate::imap::utf7_encode(&s);
        let _ = crate::imap::file_name(&s);
        let _ = crate::imap::inside_inbox(&s);
        let _ = crate::imap::is_space_folder(&s);
        let delimiter = ["/", ".", "", "é"][rng.below(4)];
        let listed = vec![
            crate::imap::Listed {
                name: s.clone(),
                delimiter: Some(delimiter.into()),
                selectable: true,
            },
            crate::imap::Listed {
                name: format!("INBOX{delimiter}{s}"),
                delimiter: Some(delimiter.into()),
                selectable: rng.below(2) == 0,
            },
        ];
        let _ = crate::imap::own_folders(&listed, &none);
        let _ = crate::files::file_risk(&s);
        let _ = crate::calendar::colour(&s);
        let _ = crate::sieve::parse_line(s.as_bytes());
        // A JMAP answer with ids and names the server chose.
        let id = text(&mut rng, 2);
        let method = ["error", s.as_str()][rng.below(2)];
        let answer = serde_json::json!({
            "methodResponses": [[method, { "type": s }, id], ["error", {}, "1"]]
        });
        let _ = crate::jmap::method_responses(&answer, ["Email/get"]);
        let kind = [s.as_str(), "text/html", "image/png"][rng.below(3)];
        let part = serde_json::json!({
            "type": kind,
            "name": s, "disposition": "attachment", "blobId": "b1", "size": 3, "cid": s,
        });
        let _ = crate::jmap::listed_files(&serde_json::json!([part, { "subParts": [part] }]));
        let email = serde_json::json!({
            "from": [{ "name": s, "email": s }], "subject": s, "preview": s,
            "receivedAt": s, "keywords": { (s.clone()): true }, "to": [{ "email": s }],
        });
        let _ = crate::jmap::summary(&email, crate::AccountId(1), "INBOX", 1);
        let mailboxes = vec![
            crate::jmap::Mailbox {
                id: "a".into(),
                name: s.clone(),
                parent_id: Some("b".into()),
                ..Default::default()
            },
            crate::jmap::Mailbox {
                id: "b".into(),
                name: s.clone(),
                parent_id: Some("a".into()),
                ..Default::default()
            },
        ];
        let _ = crate::jmap::own_folders(&mailboxes);
        let _ = crate::jmap::method_responses(&answer, ["Email/get", "Mailbox/get"]);
    }
}
