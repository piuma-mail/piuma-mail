//! Who a message went to, and who an answer goes to.
//!
//! The headers a reply needs are read once, as the message arrives
//! ([`Envelope::from_message`] for IMAP, [`Envelope::from_jmap`] for
//! JMAP), and kept with the message. From them [`reply_recipients`] works
//! out Reply, Reply all and Reply to list; [`bcc_you`] tells when the
//! person was on none of the visible lines. The raw message is read
//! again for View source ([`header_lines`]) and for Redirect
//! ([`resend`]).

use mail_parser::{HeaderForm, MessageParser};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// One mailbox: a name, which may be empty, and an address.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Address {
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    pub email: String,
}

impl Address {
    pub fn new(name: &str, email: &str) -> Self {
        Address {
            name: name.trim().to_owned(),
            email: email.trim().trim_matches(['<', '>']).to_owned(),
        }
    }

    /// As compose writes it: `a@b.c`, or `Name <a@b.c>` with the name
    /// quoted when it holds a character that would end it.
    pub fn display(&self) -> String {
        let name = self.name.trim();
        if name.is_empty() || name.eq_ignore_ascii_case(&self.email) {
            return self.email.clone();
        }
        if name.chars().any(|c| "()<>[]:;@\\,.\"".contains(c)) {
            let escaped = name.replace('\\', "\\\\").replace('"', "\\\"");
            format!("\"{escaped}\" <{}>", self.email)
        } else {
            format!("{name} <{}>", self.email)
        }
    }

    fn is(&self, email: &str) -> bool {
        self.email.trim().eq_ignore_ascii_case(email.trim())
    }
}

/// The recipient headers of a message, as it arrived.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Envelope {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub to: Vec<Address>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub cc: Vec<Address>,
    /// Every Reply-To address, not only the first.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub reply_to: Vec<Address>,
    /// Mail-Followup-To: where the author asks Reply all to go.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub followup_to: Vec<Address>,
    /// The list's posting address, from List-Post's `mailto:`; empty when
    /// it has none (or says "NO").
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub list_post: String,
    /// It came through a mailing list (List-Id): the person can be on
    /// neither To nor Cc without being Bcc'd.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub list: bool,
}

/// The addresses of an address header, flattened out of any group.
fn addresses(list: Option<mail_parser::AddressList<'_>>) -> Vec<Address> {
    list.map(|l| {
        l.mailboxes()
            .filter_map(|m| {
                let email = m.address()?;
                email
                    .contains('@')
                    .then(|| Address::new(m.name().unwrap_or_default(), email))
            })
            .collect()
    })
    .unwrap_or_default()
}

/// The `mailto:` address of a List-Post value, without its query:
/// `<mailto:dev@lists.example.org?subject=hi>` gives the address; "NO"
/// and web addresses give none.
pub fn list_post_address(value: &str) -> Option<String> {
    let lower = value.to_ascii_lowercase();
    let at = lower.find("mailto:")? + "mailto:".len();
    let rest = &value[at..];
    let end = rest.find(['>', '?', ',', ' ']).unwrap_or(rest.len());
    let raw = rest[..end].trim();
    let address = percent_decode(raw).unwrap_or_else(|| raw.to_owned());
    let address = address.trim().to_owned();
    crate::groups::valid_address(&address).then_some(address)
}

fn percent_decode(text: &str) -> Option<String> {
    let mut out = Vec::with_capacity(text.len());
    let bytes = text.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = std::str::from_utf8(bytes.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

impl Envelope {
    /// From a parsed message, or only its headers.
    pub fn from_message(m: &mail_parser::Message) -> Self {
        let headers = m.headers();
        let followup_to = headers
            .get("Mail-Followup-To")
            .map(|h| {
                let parsed = h.parse_as(HeaderForm::Addresses);
                addresses(parsed.value().as_address())
            })
            .unwrap_or_default();
        let list_post = headers
            .get("List-Post")
            .and_then(|h| list_post_address(&String::from_utf8_lossy(h.raw_value())))
            .unwrap_or_default();
        Envelope {
            to: addresses(m.to()),
            cc: addresses(m.cc()),
            reply_to: addresses(m.reply_to()),
            followup_to,
            list_post,
            list: headers.contains("List-Id"),
        }
    }

    /// From a JMAP Email with the properties [`JMAP_PROPERTIES`] adds.
    pub fn from_jmap(e: &Value) -> Self {
        let list = |v: &Value| -> Vec<Address> {
            v.as_array()
                .into_iter()
                .flatten()
                .filter_map(|a| {
                    let email = a["email"].as_str()?;
                    email
                        .contains('@')
                        .then(|| Address::new(a["name"].as_str().unwrap_or_default(), email))
                })
                .collect()
        };
        Envelope {
            to: list(&e["to"]),
            cc: list(&e["cc"]),
            reply_to: list(&e["replyTo"]),
            followup_to: list(&e[FOLLOWUP_TO]),
            list_post: e["header:List-Post"]
                .as_str()
                .and_then(list_post_address)
                .unwrap_or_default(),
            list: e["header:List-Id"].as_str().is_some_and(|v| !v.trim().is_empty()),
        }
    }

    /// From a whole raw message, for mail kept before envelopes were.
    pub fn from_raw(raw: &[u8]) -> Option<Self> {
        MessageParser::default()
            .parse_headers(raw)
            .map(|m| Self::from_message(&m))
    }

    /// As the database keeps it.
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }

    pub fn from_json(text: &str) -> Option<Self> {
        serde_json::from_str(text).ok()
    }
}

/// The JMAP property for Mail-Followup-To, as addresses.
pub const FOLLOWUP_TO: &str = "header:Mail-Followup-To:asAddresses";

/// The IMAP header fields [`Envelope::from_message`] reads beyond those
/// fetched for other reasons (To, Cc, Reply-To, List-Post, List-Id).
pub const HEADER_FIELDS: &str = "MAIL-FOLLOWUP-TO";

/// Who an answer goes to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReplyMode {
    /// Reply: the author (all of Reply-To when there is one).
    Sender,
    /// Reply all: the author and everyone on To and Cc, or the
    /// Mail-Followup-To the author asked for.
    All,
    /// Reply to list: the List-Post address.
    List,
}

/// The To and Cc of an answer.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Recipients {
    pub to: Vec<Address>,
    pub cc: Vec<Address>,
}

impl Recipients {
    /// Every address, lowercase, To first.
    pub fn emails(&self) -> Vec<String> {
        self.to
            .iter()
            .chain(&self.cc)
            .map(|a| a.email.to_lowercase())
            .collect()
    }

    pub fn is_empty(&self) -> bool {
        self.to.is_empty() && self.cc.is_empty()
    }
}

/// Who an answer to a message from `from` goes to. `own` holds the
/// person's addresses (the account's and its aliases): they are left out,
/// as are repeats, compared without case. When nobody is left on To (an
/// answer to one's own message), Cc moves up to To.
pub fn reply_recipients(
    envelope: &Envelope,
    from: &Address,
    own: &[String],
    mode: ReplyMode,
) -> Recipients {
    let author: Vec<Address> = if envelope.reply_to.is_empty() {
        vec![from.clone()]
    } else {
        envelope.reply_to.clone()
    };
    let mine = |a: &Address| own.iter().any(|o| a.is(o));
    let (to, cc): (Vec<Address>, Vec<Address>) = match mode {
        ReplyMode::Sender => {
            let to: Vec<Address> = author.iter().filter(|a| !mine(a)).cloned().collect();
            // An answer to one's own message goes to whom it went to.
            if to.is_empty() {
                (envelope.to.clone(), Vec::new())
            } else {
                (to, Vec::new())
            }
        }
        ReplyMode::All if !envelope.followup_to.is_empty() => {
            (envelope.followup_to.clone(), Vec::new())
        }
        ReplyMode::All => (
            author.iter().chain(&envelope.to).cloned().collect(),
            envelope.cc.clone(),
        ),
        ReplyMode::List if !envelope.list_post.is_empty() => {
            (vec![Address::new("", &envelope.list_post)], Vec::new())
        }
        ReplyMode::List => (author, Vec::new()),
    };
    let mut seen: Vec<String> = Vec::new();
    let mut keep = |list: Vec<Address>| -> Vec<Address> {
        let mut out: Vec<Address> = Vec::new();
        for a in list {
            if a.email.is_empty() || mine(&a) {
                continue;
            }
            let key = a.email.trim().to_lowercase();
            if seen.contains(&key) {
                // A name met later fills in one that had none.
                if let Some(kept) = out.iter_mut().find(|k| k.is(&key)) {
                    if kept.name.is_empty() {
                        kept.name = a.name;
                    }
                }
                continue;
            }
            seen.push(key);
            out.push(a);
        }
        out
    };
    let to = keep(to);
    let cc = keep(cc);
    if to.is_empty() {
        Recipients { to: cc, cc: to }
    } else {
        Recipients { to, cc }
    }
}

/// The person got the message without being on To or Cc: a blind copy.
/// Not for mail from a list, which reaches its members that way, nor for
/// the person's own mail.
pub fn bcc_you(envelope: &Envelope, from: &str, own: &[String]) -> bool {
    if own.is_empty() || envelope.list || own.iter().any(|o| o.eq_ignore_ascii_case(from.trim())) {
        return false;
    }
    !envelope
        .to
        .iter()
        .chain(&envelope.cc)
        .any(|a| own.iter().any(|o| a.is(o)))
}

/// One header of a message, for View source: its name as written and its
/// value with encoded words decoded and lines unfolded.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HeaderLine {
    pub name: String,
    pub value: String,
}

/// The headers of a raw message, in order.
pub fn header_lines(raw: &[u8]) -> Vec<HeaderLine> {
    let Some(m) = MessageParser::default().parse_headers(raw) else {
        return Vec::new();
    };
    m.headers()
        .iter()
        .map(|h| {
            let parsed = h.parse_as(HeaderForm::Text);
            let value = parsed
                .value()
                .as_text()
                .map(str::to_owned)
                .unwrap_or_else(|| String::from_utf8_lossy(h.raw_value()).into_owned());
            HeaderLine {
                name: h.raw_name().to_owned(),
                value: unfold(&value),
            }
        })
        .collect()
}

fn unfold(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Headers left out of a redirected message: they name the person's own
/// delivery, and a server seeing its own Delivered-To would take the
/// message for a loop.
const NOT_RESENT: [&str; 4] = ["delivered-to", "x-original-to", "return-path", "bcc"];

/// The message `raw` again, unchanged, with the Resent-* headers of RFC
/// 5322 (3.6.6) on top: Redirect, also called Bounce. `from` is the
/// person's address, `to` where it goes, `at` the time in Unix seconds
/// and `message_id` the new Resent-Message-ID, with angle brackets. Line
/// ends become CRLF, as SMTP wants them.
pub fn resend(raw: &[u8], from: &str, to: &[String], at: i64, message_id: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(raw.len() + 256);
    let line = |out: &mut Vec<u8>, name: &str, value: &str| {
        let value = value.replace(['\r', '\n'], " ");
        out.extend_from_slice(format!("{name}: {value}\r\n").as_bytes());
    };
    line(&mut out, "Resent-From", from);
    line(&mut out, "Resent-Date", &crate::space::rfc2822(at));
    line(&mut out, "Resent-To", &to.join(", "));
    line(&mut out, "Resent-Message-ID", message_id);
    let crlf = to_crlf(raw);
    let head_end = crlf
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .map_or(crlf.len(), |at| at + 2);
    let (head, body) = crlf.split_at(head_end);
    // Whole fields: a name line and its folded continuation lines.
    let mut skipping = false;
    for field in head.split_inclusive(|&b| b == b'\n') {
        let folded = field.first().is_some_and(|b| *b == b' ' || *b == b'\t');
        if !folded {
            let name = field
                .split(|&b| b == b':')
                .next()
                .map(|n| String::from_utf8_lossy(n).trim().to_ascii_lowercase())
                .unwrap_or_default();
            skipping = NOT_RESENT.contains(&name.as_str());
        }
        if !skipping {
            out.extend_from_slice(field);
        }
    }
    out.extend_from_slice(body);
    out
}

/// A new Message-ID for mail sent from `from`: `<random@domain>`.
pub fn new_message_id(from: &str) -> String {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).expect("the system has randomness");
    let id: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    let domain = from
        .rsplit_once('@')
        .map(|(_, d)| d.trim_matches(['>', ' ']))
        .filter(|d| !d.is_empty())
        .unwrap_or("piuma.mail");
    format!("<{id}@{domain}>")
}

/// Every lone LF becomes CRLF.
fn to_crlf(raw: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(raw.len() + raw.len() / 40);
    let mut last = 0u8;
    for &b in raw {
        if b == b'\n' && last != b'\r' {
            out.push(b'\r');
        }
        out.push(b);
        last = b;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn own() -> Vec<String> {
        vec!["me@studio.it".into(), "matteo@alias.example".into()]
    }

    fn a(name: &str, email: &str) -> Address {
        Address::new(name, email)
    }

    fn envelope(raw: &str) -> Envelope {
        Envelope::from_message(&MessageParser::default().parse(raw.as_bytes()).unwrap())
    }

    fn emails(list: &[Address]) -> Vec<&str> {
        list.iter().map(|a| a.email.as_str()).collect()
    }

    #[test]
    fn reads_every_reply_to_address() {
        let e = envelope(
            "From: Anna <anna@x.it>\r\nReply-To: desk@x.it, Bo <bo@x.it>\r\n\
             To: me@studio.it, Carla <carla@x.it>\r\nCc: dan@x.it\r\nSubject: s\r\n\r\nbody",
        );
        assert_eq!(emails(&e.reply_to), ["desk@x.it", "bo@x.it"]);
        assert_eq!(e.reply_to[1].name, "Bo");
        assert_eq!(emails(&e.to), ["me@studio.it", "carla@x.it"]);
        assert_eq!(emails(&e.cc), ["dan@x.it"]);
        assert!(!e.list);
        let to = reply_recipients(&e, &a("Anna", "anna@x.it"), &own(), ReplyMode::Sender);
        assert_eq!(emails(&to.to), ["desk@x.it", "bo@x.it"]);
        assert!(to.cc.is_empty());
    }

    #[test]
    fn reply_all_leaves_out_the_person_and_repeats() {
        let e = envelope(
            "From: Anna <anna@x.it>\r\n\
             To: ME@Studio.it, Carla <carla@x.it>, anna@x.it\r\n\
             Cc: Matteo <matteo@ALIAS.example>, CARLA@x.it, Dan <dan@x.it>\r\n\
             Subject: s\r\n\r\nbody",
        );
        let all = reply_recipients(&e, &a("Anna", "anna@x.it"), &own(), ReplyMode::All);
        assert_eq!(emails(&all.to), ["anna@x.it", "carla@x.it"]);
        assert_eq!(all.to[0].name, "Anna");
        assert_eq!(emails(&all.cc), ["dan@x.it"]);
    }

    #[test]
    fn reply_all_keeps_every_reply_to() {
        let e = envelope(
            "From: Anna <anna@x.it>\r\nReply-To: desk@x.it, bo@x.it\r\n\
             To: me@studio.it, carla@x.it\r\nSubject: s\r\n\r\nbody",
        );
        let all = reply_recipients(&e, &a("Anna", "anna@x.it"), &own(), ReplyMode::All);
        assert_eq!(emails(&all.to), ["desk@x.it", "bo@x.it", "carla@x.it"]);
    }

    #[test]
    fn mail_followup_to_decides_reply_all() {
        let e = envelope(
            "From: Anna <anna@x.it>\r\nMail-Followup-To: dev@lists.example.org, me@studio.it\r\n\
             To: dev@lists.example.org\r\nCc: carla@x.it\r\n\
             List-Id: Dev <dev.lists.example.org>\r\n\
             List-Post: <mailto:dev@lists.example.org?subject=hi>\r\nSubject: s\r\n\r\nbody",
        );
        assert_eq!(emails(&e.followup_to), ["dev@lists.example.org", "me@studio.it"]);
        assert_eq!(e.list_post, "dev@lists.example.org");
        assert!(e.list);
        let all = reply_recipients(&e, &a("Anna", "anna@x.it"), &own(), ReplyMode::All);
        assert_eq!(emails(&all.to), ["dev@lists.example.org"]);
        assert!(all.cc.is_empty());
        // Reply still goes to the author alone.
        let one = reply_recipients(&e, &a("Anna", "anna@x.it"), &own(), ReplyMode::Sender);
        assert_eq!(emails(&one.to), ["anna@x.it"]);
        let list = reply_recipients(&e, &a("Anna", "anna@x.it"), &own(), ReplyMode::List);
        assert_eq!(emails(&list.to), ["dev@lists.example.org"]);
    }

    #[test]
    fn list_post_reads_mailto_only() {
        assert_eq!(
            list_post_address("<mailto:dev@lists.example.org>").as_deref(),
            Some("dev@lists.example.org")
        );
        assert_eq!(
            list_post_address(" <https://x.org/post>, <MAILTO:a%2Bb@x.org?subject=x>").as_deref(),
            Some("a+b@x.org")
        );
        assert_eq!(list_post_address("NO"), None);
        assert_eq!(list_post_address("<https://x.org/post>"), None);
    }

    #[test]
    fn answering_ones_own_message_goes_to_its_recipients() {
        let e = envelope(
            "From: Me <me@studio.it>\r\nTo: carla@x.it\r\nCc: dan@x.it\r\nSubject: s\r\n\r\nbody",
        );
        let from = a("Me", "me@studio.it");
        let one = reply_recipients(&e, &from, &own(), ReplyMode::Sender);
        assert_eq!(emails(&one.to), ["carla@x.it"]);
        let all = reply_recipients(&e, &from, &own(), ReplyMode::All);
        assert_eq!(emails(&all.to), ["carla@x.it"]);
        assert_eq!(emails(&all.cc), ["dan@x.it"]);
        // Only Cc left: it moves up to To.
        let e = envelope("From: me@studio.it\r\nTo: me@studio.it\r\nCc: dan@x.it\r\n\r\nbody");
        let all = reply_recipients(&e, &from, &own(), ReplyMode::All);
        assert_eq!(emails(&all.to), ["dan@x.it"]);
        assert!(all.cc.is_empty());
    }

    #[test]
    fn tells_a_blind_copy() {
        let e = envelope("From: anna@x.it\r\nTo: carla@x.it\r\nSubject: s\r\n\r\nbody");
        assert!(bcc_you(&e, "anna@x.it", &own()));
        let e = envelope("From: anna@x.it\r\nTo: carla@x.it\r\nCc: Matteo@Alias.example\r\n\r\nb");
        assert!(!bcc_you(&e, "anna@x.it", &own()));
        // A list's members are on neither line.
        let e = envelope("From: anna@x.it\r\nTo: dev@l.org\r\nList-Id: <dev.l.org>\r\n\r\nb");
        assert!(!bcc_you(&e, "anna@x.it", &own()));
        // One's own mail.
        let e = envelope("From: me@studio.it\r\nTo: carla@x.it\r\n\r\nb");
        assert!(!bcc_you(&e, "me@studio.it", &own()));
    }

    #[test]
    fn reads_the_jmap_shape() {
        let e = Envelope::from_jmap(&serde_json::json!({
            "to": [{ "name": "Carla", "email": "carla@x.it" }],
            "cc": [{ "name": null, "email": "dan@x.it" }],
            "replyTo": [{ "email": "desk@x.it" }, { "email": "bo@x.it" }],
            FOLLOWUP_TO: [{ "email": "dev@l.org" }],
            "header:List-Post": " <mailto:dev@l.org>",
            "header:List-Id": " <dev.l.org>",
        }));
        assert_eq!(emails(&e.to), ["carla@x.it"]);
        assert_eq!(e.to[0].name, "Carla");
        assert_eq!(emails(&e.cc), ["dan@x.it"]);
        assert_eq!(emails(&e.reply_to), ["desk@x.it", "bo@x.it"]);
        assert_eq!(emails(&e.followup_to), ["dev@l.org"]);
        assert_eq!(e.list_post, "dev@l.org");
        assert!(e.list);
        assert_eq!(Envelope::from_json(&e.to_json()), Some(e));
    }

    #[test]
    fn displays_names_safely() {
        assert_eq!(a("", "x@y.it").display(), "x@y.it");
        assert_eq!(a("Anna Bo", "x@y.it").display(), "Anna Bo <x@y.it>");
        assert_eq!(a("Bo, Anna", "x@y.it").display(), "\"Bo, Anna\" <x@y.it>");
    }

    #[test]
    fn header_lines_decode_and_unfold() {
        let lines = header_lines(
            b"Subject: =?utf-8?q?Caff=C3=A8?=\r\nX-Long: one\r\n two\r\nTo: a@b.it\r\n\r\nbody",
        );
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0].name, "Subject");
        assert_eq!(lines[0].value, "Caffè");
        assert_eq!(lines[1].value, "one two");
    }

    #[test]
    fn resend_adds_resent_headers_and_keeps_the_message() {
        let raw = b"Delivered-To: me@studio.it\nFrom: anna@x.it\nTo: me@studio.it\n\
                    Return-Path: <anna@x.it>\nSubject: s\nX-Folded: a\n b\n\nbody\nline\n";
        let out = resend(raw, "me@studio.it", &["carla@x.it".into()], 0, "<r1@studio.it>");
        let text = String::from_utf8(out).unwrap();
        assert!(text.starts_with(
            "Resent-From: me@studio.it\r\nResent-Date: Thu, 1 Jan 1970 00:00:00 +0000\r\n\
             Resent-To: carla@x.it\r\nResent-Message-ID: <r1@studio.it>\r\nFrom: anna@x.it\r\n"
        ));
        assert!(!text.contains("Delivered-To"));
        assert!(!text.contains("Return-Path"));
        assert!(text.contains("X-Folded: a\r\n b\r\n"));
        assert!(text.ends_with("\r\n\r\nbody\r\nline\r\n"));
        let m = MessageParser::default().parse(text.as_bytes()).unwrap();
        assert_eq!(m.headers().resent_to().unwrap().first().unwrap().address(), Some("carla@x.it"));
        assert_eq!(m.from().unwrap().first().unwrap().address(), Some("anna@x.it"));
    }

    #[test]
    fn new_ids_use_the_senders_domain() {
        let id = new_message_id("me@studio.it");
        assert!(id.starts_with('<') && id.ends_with("@studio.it>"));
        assert_ne!(id, new_message_id("me@studio.it"));
    }
}
