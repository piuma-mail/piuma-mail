//! Email files opened from outside the app (`.eml`, `message/rfc822`):
//! a double-click in the file manager, "Open with", an Android share.
//!
//! The file is untrusted. It goes through the same parser as synced mail
//! ([`crate::imap::parse_body`]), is never written to the database, and
//! nothing in it is fetched: the reader shows it like any other message,
//! with remote images waiting for the usual consent.

use std::io::Read;
use std::path::Path;

use mail_parser::MessageParser;

use crate::store::Body;

/// Largest email file opened. Servers refuse messages well below this;
/// past it the file is not mail anyone sent.
pub const EML_MAX: u64 = 50 * 1024 * 1024;

/// Longest header value kept for showing (a subject, a name).
const HEADER_MAX: usize = 1_000;

/// Most recipients listed in To or Cc.
const RECIPIENTS_MAX: usize = 200;

#[derive(Debug, thiserror::Error)]
pub enum EmlError {
    #[error("the file can't be read: {0}")]
    Io(#[from] std::io::Error),
    #[error("the file is larger than {EML_MAX} bytes")]
    TooLarge,
    #[error("the file is not an email")]
    NotMail,
}

/// An email file, read.
#[derive(Debug, Clone, Default)]
pub struct EmlMessage {
    pub from_name: String,
    pub from_email: String,
    /// `Name <a@b.c>` or `a@b.c`, at most [`RECIPIENTS_MAX`].
    pub to: Vec<String>,
    pub cc: Vec<String>,
    pub subject: String,
    /// Seconds since the epoch, from its Date header.
    pub date: Option<i64>,
    /// Without angle brackets; empty when it has none.
    pub message_id: String,
    pub body: Body,
}

/// Reads at most [`EML_MAX`] bytes of `path`; a larger file is refused
/// without reading it all.
pub fn load(path: &Path) -> Result<Vec<u8>, EmlError> {
    let file = std::fs::File::open(path)?;
    let meta = file.metadata()?;
    if !meta.is_file() {
        return Err(EmlError::NotMail);
    }
    if meta.len() > EML_MAX {
        return Err(EmlError::TooLarge);
    }
    let mut raw = Vec::with_capacity(meta.len() as usize);
    // The size can change while it is read: never more than the cap.
    file.take(EML_MAX + 1).read_to_end(&mut raw)?;
    if raw.len() as u64 > EML_MAX {
        return Err(EmlError::TooLarge);
    }
    Ok(raw)
}

/// Reads an email file's bytes: its headers for the reader, its body
/// exactly as a synced message's.
pub fn read(raw: &[u8]) -> Result<EmlMessage, EmlError> {
    if raw.len() as u64 > EML_MAX {
        return Err(EmlError::TooLarge);
    }
    let m = MessageParser::default()
        .parse(raw)
        .ok_or(EmlError::NotMail)?;
    // Anything parses as a message with no headers: an email has at
    // least one of these.
    let mailish = m.from().is_some()
        || m.to().is_some()
        || m.subject().is_some()
        || m.date().is_some()
        || m.message_id().is_some();
    if !mailish {
        return Err(EmlError::NotMail);
    }
    let from = m.from().and_then(|a| a.first());
    let list = |a: Option<mail_parser::AddressList<'_>>| -> Vec<String> {
        a.map(|a| {
            a.mailboxes()
                .filter_map(|addr| {
                    let email = clean(addr.address()?);
                    if email.is_empty() {
                        return None;
                    }
                    Some(match addr.name().map(clean).filter(|n| !n.is_empty()) {
                        Some(name) => format!("{name} <{email}>"),
                        None => email,
                    })
                })
                .take(RECIPIENTS_MAX)
                .collect()
        })
        .unwrap_or_default()
    };
    Ok(EmlMessage {
        from_name: from.and_then(|a| a.name()).map(clean).unwrap_or_default(),
        from_email: from
            .and_then(|a| a.address())
            .map(clean)
            .unwrap_or_default(),
        to: list(m.to()),
        cc: list(m.cc()),
        subject: m.subject().map(clean).unwrap_or_default(),
        date: m.date().map(|d| d.to_timestamp()),
        message_id: m.message_id().map(clean).unwrap_or_default(),
        body: crate::imap::parse_body(raw),
    })
}

/// A header value as it may be shown: one line, no control characters,
/// no direction overrides, at most [`HEADER_MAX`] characters.
fn clean(text: &str) -> String {
    text.chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .filter(|&c| !crate::bidi::is_bidi_override(c) && !crate::bidi::is_bidi_mark(c))
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(HEADER_MAX)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const PLAIN: &str = "From: Ada Lovelace <ada@example.com>\r\n\
To: Bob <bob@example.com>, carol@example.com\r\n\
Cc: dan@example.com\r\n\
Subject: Notes on the engine\r\n\
Date: Tue, 3 Nov 2026 10:00:00 +0000\r\n\
Message-ID: <note-1@example.com>\r\n\
Content-Type: text/plain; charset=utf-8\r\n\
\r\n\
The engine weaves algebraic patterns.\r\n";

    #[test]
    fn an_email_file_reads_like_synced_mail() {
        let m = read(PLAIN.as_bytes()).unwrap();
        assert_eq!(m.from_name, "Ada Lovelace");
        assert_eq!(m.from_email, "ada@example.com");
        assert_eq!(m.to, ["Bob <bob@example.com>", "carol@example.com"]);
        assert_eq!(m.cc, ["dan@example.com"]);
        assert_eq!(m.subject, "Notes on the engine");
        assert_eq!(m.message_id, "note-1@example.com");
        assert!(m.date.is_some());
        assert_eq!(m.body.text, "The engine weaves algebraic patterns.");
        // The very same parse as a synced message's body.
        assert_eq!(m.body, crate::imap::parse_body(PLAIN.as_bytes()));
    }

    #[test]
    fn something_that_is_not_mail_is_refused() {
        assert!(matches!(read(b""), Err(EmlError::NotMail)));
        assert!(matches!(
            read(b"\x7fELF\x02\x01\x01\0\0\0\0\0\0\0\0\0\x03\0>\0"),
            Err(EmlError::NotMail)
        ));
        assert!(matches!(
            read(b"just some words\nand more words\n"),
            Err(EmlError::NotMail)
        ));
    }

    #[test]
    fn a_huge_file_is_refused_before_it_is_parsed() {
        let dir = std::env::temp_dir().join(format!("piuma-eml-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("huge.eml");
        let file = std::fs::File::create(&path).unwrap();
        // Sparse: no real disk is used.
        file.set_len(EML_MAX + 1).unwrap();
        assert!(matches!(load(&path), Err(EmlError::TooLarge)));
        std::fs::write(&path, PLAIN).unwrap();
        assert_eq!(load(&path).unwrap(), PLAIN.as_bytes());
        assert!(load(&dir).is_err());
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn hostile_headers_are_tamed_for_showing() {
        let raw = format!(
            "From: \"Bank\u{202E}gro.evil\" <x@evil.example>\r\n\
Subject: =?utf-8?q?Hello=0D=0ABcc=3A_victim=40example=2Ecom?= {}\r\n\
To: {}\r\n\
\r\n\
hi\r\n",
            "A".repeat(5_000),
            (0..1_000)
                .map(|i| format!("p{i}@example.com"))
                .collect::<Vec<_>>()
                .join(", "),
        );
        let m = read(raw.as_bytes()).unwrap();
        assert!(!m.from_name.contains('\u{202E}'));
        assert!(!m.subject.contains('\r') && !m.subject.contains('\n'));
        assert!(m.subject.chars().count() <= HEADER_MAX);
        assert_eq!(m.to.len(), RECIPIENTS_MAX);
    }

    #[test]
    fn scripts_and_remote_content_never_run_or_load() {
        let raw = "From: a@example.com\r\n\
Subject: html\r\n\
Content-Type: text/html; charset=utf-8\r\n\
\r\n\
<p>Hi<script>alert(1)</script></p>\
<img src=\"https://tracker.example/p.gif\" width=1 height=1>\
<img src=\"https://cdn.example/photo.jpg\">\
<a href=\"javascript:alert(2)\">click</a>\r\n";
        let m = read(raw.as_bytes()).unwrap();
        let r = crate::reading::readable(&m.body.text, m.body.html.as_deref());
        let text = crate::reading::plain_text(&r);
        assert!(!text.contains("alert(1)"));
        for b in &r.blocks {
            for s in &b.spans {
                assert!(
                    s.link
                        .as_deref()
                        .is_none_or(|l| !l.to_ascii_lowercase().starts_with("javascript:")),
                    "{:?}",
                    s.link
                );
            }
        }
        // The photo waits for consent; the pixel is stopped.
        assert_eq!(r.remote_images, 1);
    }

    #[test]
    fn deeply_nested_and_broken_mime_does_not_bring_it_down() {
        let mut raw = String::from("From: a@example.com\r\nSubject: nest\r\n");
        for i in 0..400 {
            raw.push_str(&format!(
                "Content-Type: multipart/mixed; boundary=\"b{i}\"\r\n\r\n--b{i}\r\n"
            ));
        }
        raw.push_str("Content-Type: text/plain\r\n\r\ninner\r\n");
        let m = read(raw.as_bytes()).unwrap();
        assert_eq!(m.from_email, "a@example.com");
        // A part that says base64 and isn't, an attachment with a path
        // for a name.
        let raw = "From: a@example.com\r\n\
Content-Type: multipart/mixed; boundary=x\r\n\
\r\n\
--x\r\n\
Content-Type: text/plain\r\n\
\r\n\
see file\r\n\
--x\r\n\
Content-Type: application/octet-stream; name=\"../../.bashrc\"\r\n\
Content-Disposition: attachment; filename=\"../../.bashrc\"\r\n\
Content-Transfer-Encoding: base64\r\n\
\r\n\
!!!not base64!!!\r\n\
--x--\r\n";
        let m = read(raw.as_bytes()).unwrap();
        assert_eq!(m.body.attachments.len(), 1);
        // Saving it goes through files::save_new, which keeps only a name.
        let dir = std::env::temp_dir().join(format!("piuma-eml-save-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let saved = crate::files::save_new(&dir, &m.body.attachments[0].name, b"x").unwrap();
        assert_eq!(saved.parent(), Some(dir.as_path()));
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
