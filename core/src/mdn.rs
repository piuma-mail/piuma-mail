//! Read receipts (message disposition notifications, RFC 8098) and the
//! priority a sender gave a message.
//!
//! A message asks for a receipt with `Disposition-Notification-To`. None
//! is ever sent on its own: the reader asks the person, and only when the
//! request is safe to answer (§2.1: the address it goes to is the one
//! the message came back from, its Return-Path). The receipt itself is a
//! `multipart/report; report-type=disposition-notification`.

use lettre::message::header::{
    ContentTransferEncoding, ContentType, Header, HeaderName, HeaderValue,
};
use lettre::message::{Body, SinglePart};
use lettre::Message;

use crate::smtp::{self, Ready, SendError};

pub use lettre::message::Mailbox;

/// "Name <email>", or the address alone without a name.
pub fn mailbox(name: &str, email: &str) -> smtp::Result<Mailbox> {
    let address = email
        .trim()
        .parse()
        .map_err(|_| SendError::Address(email.trim().to_owned()))?;
    let name = name.trim();
    Ok(Mailbox::new(
        (!name.is_empty()).then(|| name.to_owned()),
        address,
    ))
}

/// The header that asks for a receipt.
pub const REQUEST: &str = "Disposition-Notification-To";

/// What a received message asks of its reader, from its headers.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Asks {
    /// The address a read receipt should go to, when one is asked for.
    pub receipt_to: Option<String>,
    /// The address in Return-Path, when the message has one.
    pub return_path: Option<String>,
    /// The sender marked it important (`Importance: high`, `X-Priority:
    /// 1` or `2`, `Priority: urgent`).
    pub high_priority: bool,
    /// The address it was first written to (`Original-Recipient`), for
    /// the receipt.
    pub original_recipient: Option<String>,
}

impl Asks {
    /// A receipt may be offered: one is asked for, and it goes where the
    /// message came back from (RFC 8098 §2.1).
    pub fn receipt_offered(&self) -> Option<&str> {
        let to = self.receipt_to.as_deref()?;
        let back = self.return_path.as_deref()?;
        to.eq_ignore_ascii_case(back).then_some(to)
    }
}

/// What the person did with a read receipt asked for.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum Answer {
    #[default]
    Unanswered,
    Sent,
    Declined,
}

impl Answer {
    pub(crate) fn code(self) -> i64 {
        match self {
            Answer::Unanswered => 0,
            Answer::Sent => 1,
            Answer::Declined => 2,
        }
    }

    pub(crate) fn from_code(code: i64) -> Self {
        match code {
            1 => Answer::Sent,
            2 => Answer::Declined,
            _ => Answer::Unanswered,
        }
    }
}

/// A spam folder, by its usual names: mail there never offers a receipt
/// (it would tell the sender the address is read).
pub fn is_junk_mailbox(mailbox: &str) -> bool {
    let last = mailbox
        .rsplit(['/', '.'])
        .next()
        .unwrap_or(mailbox)
        .trim()
        .to_lowercase();
    [
        "junk",
        "spam",
        "junk e-mail",
        "junk email",
        "bulk mail",
        "posta indesiderata",
        "spam-verdacht",
        "courrier indésirable",
        "correo no deseado",
        "lixo eletrônico",
    ]
    .contains(&last.as_str())
}

fn raw(m: &mail_parser::Message, name: &str) -> Option<String> {
    m.headers()
        .get(name)
        .and_then(|h| std::str::from_utf8(h.raw_value()).ok())
        .map(|v| v.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|v| !v.is_empty())
}

/// The first address in a header value: "Name <a@b.c>", "<a@b.c>" or
/// "a@b.c"; "rfc822;a@b.c" for Original-Recipient.
fn address(value: &str) -> Option<String> {
    let value = value.trim();
    let value = value
        .split_once(';')
        .filter(|(kind, _)| kind.trim().eq_ignore_ascii_case("rfc822"))
        .map(|(_, a)| a)
        .unwrap_or(value);
    let first = value.split(',').next()?.trim();
    let inner = match (first.rfind('<'), first.rfind('>')) {
        (Some(a), Some(b)) if a < b => &first[a + 1..b],
        _ => first,
    };
    let inner = inner.trim();
    (inner.contains('@') && !inner.contains(char::is_whitespace)).then(|| inner.to_owned())
}

/// What `m` asks of its reader.
pub fn asks(m: &mail_parser::Message) -> Asks {
    let lower = |name| raw(m, name).map(|v| v.to_ascii_lowercase());
    let high = lower("Importance").is_some_and(|v| v.starts_with("high"))
        || lower("X-Priority")
            .and_then(|v| v.trim().chars().next())
            .is_some_and(|c| c == '1' || c == '2')
        || lower("Priority").is_some_and(|v| v.starts_with("urgent"))
        || lower("X-MSMail-Priority").is_some_and(|v| v.starts_with("high"));
    Asks {
        receipt_to: raw(m, REQUEST).as_deref().and_then(address),
        return_path: raw(m, "Return-Path").as_deref().and_then(address),
        high_priority: high,
        original_recipient: raw(m, "Original-Recipient").as_deref().and_then(address),
    }
}

/// The message a receipt answers.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Original {
    pub subject: String,
    /// With angle brackets; empty when it had none.
    pub message_id: String,
    /// The references of its thread, oldest first.
    pub references: Vec<String>,
    pub original_recipient: Option<String>,
}

macro_rules! text_header {
    ($name:ident, $header:literal) => {
        #[derive(Clone)]
        pub(crate) struct $name(pub(crate) String);

        impl Header for $name {
            fn name() -> HeaderName {
                HeaderName::new_from_ascii_str($header)
            }

            fn parse(
                s: &str,
            ) -> std::result::Result<Self, Box<dyn std::error::Error + Send + Sync>> {
                Ok(Self(s.to_owned()))
            }

            fn display(&self) -> HeaderValue {
                HeaderValue::new(Self::name(), self.0.clone())
            }
        }
    };
}

text_header!(DispositionNotificationTo, "Disposition-Notification-To");
text_header!(Importance, "Importance");
text_header!(XPriority, "X-Priority");
text_header!(AutoSubmitted, "Auto-Submitted");

/// The receipt for `original`, from `from` (the address it was read at)
/// to `to`, the address the request named: sent by hand, "displayed".
pub fn report(from: &Mailbox, to: &str, original: &Original) -> smtp::Result<Ready> {
    let to: Mailbox = to
        .trim()
        .parse()
        .map_err(|_| SendError::Address(to.trim().to_owned()))?;
    let subject = format!("Read: {}", original.subject.trim());
    let boundary = format!(
        "piuma-mdn-{}",
        crate::compose_image::new_cid(0)
            .trim_start_matches(crate::compose_image::CID_PREFIX)
            .replace(['@', '-'], "")
    );
    let me = from.email.to_string();
    let human = format!(
        "This is a receipt for the message you sent to {me}, \"{}\".\r\n\
         \r\n\
         It was shown on the recipient's screen. This does not guarantee \
         that the message was read or understood.\r\n",
        original.subject.trim()
    );
    // Header values read from the message: no line break may get into
    // the fields written here.
    let field = |v: &str| v.replace(['\r', '\n'], "");
    let me = field(&me);
    let mut machine = String::from("Reporting-UA: Piuma Mail\r\n");
    if let Some(r) = &original.original_recipient {
        machine.push_str(&format!("Original-Recipient: rfc822;{}\r\n", field(r)));
    }
    machine.push_str(&format!("Final-Recipient: rfc822;{me}\r\n"));
    if !original.message_id.is_empty() {
        machine.push_str(&format!(
            "Original-Message-ID: {}\r\n",
            field(&original.message_id)
        ));
    }
    machine.push_str("Disposition: manual-action/MDN-sent-manually; displayed\r\n");
    // The text part encoded as lettre encodes any part, so the report
    // itself stays 7-bit.
    let text = SinglePart::builder()
        .header(ContentType::TEXT_PLAIN)
        .header(ContentTransferEncoding::QuotedPrintable)
        .body(human)
        .formatted();
    let mut body =
        format!("This is a multi-part message in MIME format.\r\n--{boundary}\r\n").into_bytes();
    body.extend_from_slice(&text);
    body.extend_from_slice(
        format!(
            "\r\n--{boundary}\r\n\
             Content-Type: message/disposition-notification\r\n\
             Content-Transfer-Encoding: 7bit\r\n\
             \r\n\
             {machine}\
             --{boundary}--\r\n"
        )
        .as_bytes(),
    );
    let kind = ContentType::parse(&format!(
        "multipart/report; report-type=disposition-notification; boundary=\"{boundary}\""
    ))
    .map_err(|e| SendError::Build(e.to_string()))?;
    let mut b = Message::builder()
        .from(from.clone())
        .to(to)
        .subject(subject)
        .date_now()
        .message_id(None)
        .header(AutoSubmitted("auto-replied".into()));
    if !original.message_id.is_empty() {
        b = b.in_reply_to(original.message_id.clone());
        let mut refs = original.references.clone();
        if !refs.contains(&original.message_id) {
            refs.push(original.message_id.clone());
        }
        b = b.references(refs.join(" "));
    }
    let message = b
        .header(kind)
        .body(Body::dangerous_pre_encoded(
            body,
            ContentTransferEncoding::SevenBit,
        ))
        .map_err(|e| SendError::Build(e.to_string()))?;
    Ok(smtp::ready_from(&message, &me))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(raw: &str) -> Asks {
        asks(
            &mail_parser::MessageParser::default()
                .parse(raw.as_bytes())
                .unwrap(),
        )
    }

    #[test]
    fn reads_what_a_message_asks() {
        let a = parse(
            "Return-Path: <luca@example.org>\r\n\
             From: Luca <luca@example.org>\r\n\
             Disposition-Notification-To: Luca Bianchi <Luca@Example.org>\r\n\
             X-Priority: 1 (Highest)\r\n\
             Subject: Hi\r\n\r\nbody",
        );
        assert_eq!(a.receipt_to.as_deref(), Some("Luca@Example.org"));
        assert_eq!(a.return_path.as_deref(), Some("luca@example.org"));
        assert!(a.high_priority);
        assert_eq!(a.receipt_offered(), Some("Luca@Example.org"));
    }

    #[test]
    fn no_receipt_where_it_would_go_elsewhere() {
        let a = parse(
            "Return-Path: <bounces@list.example>\r\n\
             Disposition-Notification-To: tracker@elsewhere.example\r\n\
             Subject: Hi\r\n\r\nbody",
        );
        assert_eq!(a.receipt_offered(), None);
        // Nor without a Return-Path to compare with.
        let b = parse("Disposition-Notification-To: a@b.it\r\nSubject: x\r\n\r\nbody");
        assert_eq!(b.receipt_offered(), None);
        assert!(!b.high_priority);
    }

    #[test]
    fn spam_folders_by_name() {
        assert!(is_junk_mailbox("Junk"));
        assert!(is_junk_mailbox("[Gmail]/Spam"));
        assert!(is_junk_mailbox("INBOX.spam"));
        assert!(!is_junk_mailbox("INBOX"));
        assert!(!is_junk_mailbox("Spam reports archive"));
    }

    #[test]
    fn priority_in_its_usual_spellings() {
        assert!(parse("Importance: High\r\n\r\nx").high_priority);
        assert!(parse("Priority: urgent\r\n\r\nx").high_priority);
        assert!(!parse("Importance: normal\r\nX-Priority: 3\r\n\r\nx").high_priority);
    }

    #[test]
    fn the_receipt_is_a_disposition_report() {
        let from = Mailbox::new(Some("Matteo".into()), "matteo@example.org".parse().unwrap());
        let ready = report(
            &from,
            "luca@example.org",
            &Original {
                subject: "Mockups".into(),
                message_id: "<abc@example.org>".into(),
                references: vec![],
                original_recipient: Some("matteo@example.org".into()),
            },
        )
        .unwrap();
        assert_eq!(ready.recipients, vec!["luca@example.org".to_string()]);
        let raw = String::from_utf8(ready.raw.clone()).unwrap();
        assert!(raw.contains("Subject: Read: Mockups"), "{raw}");
        assert!(raw.contains("In-Reply-To: <abc@example.org>"), "{raw}");
        assert!(
            raw.contains("multipart/report; report-type=disposition-notification"),
            "{raw}"
        );
        assert!(raw.contains("Content-Type: message/disposition-notification"));
        assert!(raw.contains("Disposition: manual-action/MDN-sent-manually; displayed"));
        assert!(raw.contains("Original-Message-ID: <abc@example.org>"));
        assert!(raw.contains("Final-Recipient: rfc822;matteo@example.org"));
        assert!(raw.contains("Auto-Submitted: auto-replied"));
        // Mail readers see it as a report with a text part.
        let parsed = mail_parser::MessageParser::default()
            .parse(&ready.raw)
            .unwrap();
        assert!(parsed
            .body_text(0)
            .unwrap()
            .contains("receipt for the message"));
    }
}
