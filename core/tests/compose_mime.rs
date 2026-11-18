//! What compose's options put on the wire: lists, quotes and pictures in
//! the HTML, plain text as `format=flowed`, read receipts asked for and
//! sent, and priority. Each message goes through a small SMTP server that
//! lives inside the test, and is read back from what it received.

use std::io::Cursor;
use std::sync::{Arc, Mutex};

use lettre::message::Mailbox;
use piuma_core::compose_image::{InlineImage, PLACEHOLDER};
use piuma_core::imap::{parse_body, parse_draft};
use piuma_core::mdn;
use piuma_core::smtp::{build_unsent, ready, send, Draft, OutgoingFile, SmtpConfig};
use piuma_core::Security;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;

/// A server that takes every message and keeps what DATA carried.
async fn sink() -> (u16, Arc<Mutex<Vec<String>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let got = Arc::new(Mutex::new(Vec::new()));
    let seen = got.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let seen = seen.clone();
            tokio::spawn(async move {
                let (r, mut w) = tcp.into_split();
                let mut lines = BufReader::new(r).lines();
                w.write_all(b"220 sink ESMTP\r\n").await.unwrap();
                while let Ok(Some(line)) = lines.next_line().await {
                    let upper = line.to_ascii_uppercase();
                    let reply: &[u8] = if upper.starts_with("EHLO") {
                        b"250-sink\r\n250 AUTH PLAIN LOGIN\r\n"
                    } else if upper.starts_with("AUTH") {
                        b"235 ok\r\n"
                    } else if upper == "DATA" {
                        w.write_all(b"354 go on\r\n").await.unwrap();
                        let mut data = String::new();
                        while let Ok(Some(l)) = lines.next_line().await {
                            if l == "." {
                                break;
                            }
                            // Dot-stuffing undone, CRLF kept as the
                            // message had it.
                            data.push_str(
                                l.strip_prefix('.')
                                    .filter(|_| l.starts_with(".."))
                                    .unwrap_or(&l),
                            );
                            data.push_str("\r\n");
                        }
                        seen.lock().unwrap().push(data);
                        b"250 queued\r\n"
                    } else if upper == "QUIT" {
                        w.write_all(b"221 bye\r\n").await.ok();
                        return;
                    } else {
                        b"250 ok\r\n"
                    };
                    w.write_all(reply).await.unwrap();
                }
            });
        }
    });
    (port, got)
}

fn config(port: u16) -> SmtpConfig {
    SmtpConfig {
        host: "127.0.0.1".into(),
        port,
        security: Security::None,
        username: "me".into(),
        login: "test".into(),
    }
}

/// Sends `draft` through the sink and returns the message it received.
async fn through_smtp(draft: &Draft) -> Vec<u8> {
    let (port, got) = sink().await;
    send(&config(port), &ready(draft).unwrap()).await.unwrap();
    let got = got.lock().unwrap();
    assert_eq!(got.len(), 1);
    got[0].clone().into_bytes()
}

fn draft() -> Draft {
    Draft {
        from_name: "Matteo".into(),
        from_email: "me@example.org".into(),
        to: vec!["Luca <luca@example.org>".into()],
        subject: "Friday".into(),
        body: "Hi Luca".into(),
        ..Draft::default()
    }
}

fn photo() -> InlineImage {
    let picture = image::RgbImage::from_fn(64, 48, |x, y| image::Rgb([x as u8, y as u8, 90]));
    let mut png = Cursor::new(Vec::new());
    image::DynamicImage::ImageRgb8(picture)
        .write_to(&mut png, image::ImageFormat::Png)
        .unwrap();
    InlineImage {
        name: "terrace.png".into(),
        mime: "image/png".into(),
        data: png.into_inner(),
        ..InlineImage::default()
    }
}

#[tokio::test]
async fn lists_quotes_and_pictures_go_as_html_with_a_faithful_text() {
    let mut d = draft();
    d.body = format!(
        "Three things:\n• the terrace\n• Marco\n1. eight\n2. half past\n│ as you said\n{PLACEHOLDER}\nSee you"
    );
    d.images = vec![photo()];
    let raw = through_smtp(&d).await;
    let text = String::from_utf8_lossy(&raw);
    assert!(text.contains("multipart/alternative"), "{text}");
    assert!(text.contains("multipart/related"), "{text}");

    let parsed = mail_parser::MessageParser::default().parse(&raw).unwrap();
    let html = parsed.body_html(0).unwrap();
    assert!(html.contains("<ul style="), "{html}");
    assert!(
        html.contains("<li>the terrace</li><li>Marco</li></ul>"),
        "{html}"
    );
    assert!(html.contains("<ol style="), "{html}");
    assert!(html.contains("<blockquote style="), "{html}");
    let cid = html
        .split("src=\"cid:")
        .nth(1)
        .and_then(|rest| rest.split('"').next())
        .unwrap()
        .to_owned();
    assert!(cid.starts_with("piuma-img-0-"), "{cid}");
    assert!(html.contains("alt=\"terrace.png\""), "{html}");
    // The plain text says the same, with the picture by name.
    let plain = parsed.body_text(0).unwrap().replace("\r\n", "\n");
    assert_eq!(
        plain,
        "Three things:\n• the terrace\n• Marco\n1. eight\n2. half past\n> as you said\n[image: terrace.png]\nSee you"
    );
    // The picture travels inside, under that Content-ID, not as a file.
    let body = parse_body(&raw);
    assert!(body.attachments.is_empty(), "{:?}", body.attachments);
    assert_eq!(body.inline.len(), 1);
    assert_eq!(body.inline[0].cid, cid);
    assert_eq!(body.inline[0].data, photo().data);
}

#[tokio::test]
async fn plain_text_goes_flowed_without_html() {
    let mut d = draft();
    let long = "This sentence is long enough that a plain-text message has to cut it somewhere along the way.";
    d.body = format!("{long}\n│ quoted line\n{PLACEHOLDER}\n\nOn Oct 12, Luca wrote:\n> Dinner?");
    d.marks = vec![piuma_core::rich::Mark {
        kind: piuma_core::rich::MarkKind::Bold,
        start: 0,
        end: 4,
    }];
    d.images = vec![photo()];
    d.files = vec![OutgoingFile {
        name: "menu.pdf".into(),
        mime: "application/pdf".into(),
        data: b"%PDF-1.4".to_vec(),
    }];
    d.plain_text = true;
    let raw = through_smtp(&d).await;
    let text = String::from_utf8_lossy(&raw);
    assert!(!text.contains("text/html"), "{text}");
    assert!(text.contains("format=flowed"), "{text}");
    let parsed = mail_parser::MessageParser::default().parse(&raw).unwrap();
    let plain = parsed.body_text(0).unwrap();
    for line in plain.lines() {
        assert!(line.chars().count() <= 78, "{line:?}");
    }
    assert!(
        plain.contains("cut it "),
        "soft breaks keep their space: {plain:?}"
    );
    // Read back as a flowed message, the long line is whole again.
    let body = parse_body(&raw);
    assert!(body.text.contains(long), "{}", body.text);
    assert!(body.text.contains("quoted line"), "{}", body.text);
    assert!(!body.text.contains('\u{FFFC}'));
    // The picture went as a file, beside the one attached.
    let mut names: Vec<_> = body.attachments.iter().map(|a| a.name.clone()).collect();
    names.sort();
    assert_eq!(
        names,
        vec!["menu.pdf".to_string(), "terrace.png".to_string()]
    );
}

#[tokio::test]
async fn asks_for_a_receipt_and_marks_priority() {
    let mut d = draft();
    d.read_receipt = true;
    d.high_priority = true;
    let raw = through_smtp(&d).await;
    let text = String::from_utf8_lossy(&raw);
    assert!(
        text.contains("Disposition-Notification-To: Matteo <me@example.org>"),
        "{text}"
    );
    assert!(text.contains("Importance: high"), "{text}");
    assert!(text.contains("X-Priority: 1 (Highest)"), "{text}");
    // As a receiver reads it.
    let asks = mdn::asks(&mail_parser::MessageParser::default().parse(&raw).unwrap());
    assert_eq!(asks.receipt_to.as_deref(), Some("me@example.org"));
    assert!(asks.high_priority);
    // Without the options, neither header.
    let plain = String::from_utf8_lossy(&through_smtp(&draft()).await).into_owned();
    assert!(!plain.contains("Disposition-Notification-To"));
    assert!(!plain.contains("Importance"));
}

#[tokio::test]
async fn a_receipt_goes_as_a_disposition_report() {
    let (port, got) = sink().await;
    let from = Mailbox::new(Some("Matteo".into()), "me@example.org".parse().unwrap());
    let receipt = mdn::report(
        &from,
        "luca@example.org",
        &mdn::Original {
            subject: "Città: plans".into(),
            message_id: "<plans@example.org>".into(),
            references: vec!["<start@example.org>".into()],
            original_recipient: None,
        },
    )
    .unwrap();
    send(&config(port), &receipt).await.unwrap();
    let raw = got.lock().unwrap()[0].clone();
    assert!(raw.contains("multipart/report; report-type=disposition-notification"));
    assert!(raw.contains("References: <start@example.org> <plans@example.org>"));
    let parsed = mail_parser::MessageParser::default()
        .parse(raw.as_bytes())
        .unwrap();
    assert!(parsed.subject().unwrap().starts_with("Read: Città"));
    assert!(parsed.body_text(0).unwrap().contains("Città: plans"));
    // The machine-readable part, 7-bit as it went.
    let fields = raw
        .split("Content-Type: message/disposition-notification")
        .nth(1)
        .expect("a disposition-notification part");
    assert!(
        fields.contains("Final-Recipient: rfc822;me@example.org"),
        "{fields}"
    );
    assert!(
        fields.contains("Original-Message-ID: <plans@example.org>"),
        "{fields}"
    );
    assert!(
        fields.contains("Disposition: manual-action/MDN-sent-manually; displayed"),
        "{fields}"
    );
}

#[test]
fn a_saved_draft_keeps_its_pictures_and_options() {
    let mut d = draft();
    d.body = format!("Look:\n{PLACEHOLDER}\nand\n{PLACEHOLDER}");
    let mut second = photo();
    second.name = "menu \"today\".png".into();
    d.images = vec![photo(), second];
    d.read_receipt = true;
    d.high_priority = true;
    let back = parse_draft(&build_unsent(&d).unwrap().formatted());
    assert_eq!(back.body.replace("\r\n", "\n"), d.body);
    assert_eq!(back.images.len(), 2);
    assert_eq!(back.images[0].name, "terrace.png");
    assert_eq!(back.images[1].name, "menu \"today\".png");
    assert_eq!(back.images[0].data, photo().data);
    assert!(back.read_receipt && back.high_priority && !back.plain_text);

    d.plain_text = true;
    let back = parse_draft(&build_unsent(&d).unwrap().formatted());
    assert!(back.plain_text);
}
