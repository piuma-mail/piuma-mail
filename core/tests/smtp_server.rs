//! Sending against a small SMTP server that lives inside the test.
//!
//! The SMTP side always runs. Filing the copy in Sent also needs the IMAP
//! test server: start it with `tools/test-imap-server.sh`, then
//!     PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test

use std::sync::{Arc, Mutex};

use futures::TryStreamExt;
use piuma_core::imap::ImapConfig;
use piuma_core::outbox::{self, Outgoing};
use piuma_core::remote;
use piuma_core::smtp::{ready, send, send_and_file, Draft, Ready, SendError, SmtpConfig};
use piuma_core::{Account, AccountId, AccountKind, Security, Server, Store};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::tcp::OwnedReadHalf;
use tokio::net::{TcpListener, TcpStream};

/// What the fake server received.
#[derive(Default, Debug)]
struct Received {
    rcpt: Vec<String>,
    /// The message, dot-stuffing undone, one "\n" after each line.
    data: String,
    /// The message exactly as it came over the wire, dot-stuffing and
    /// line endings included, without the final ".".
    wire: Vec<u8>,
    /// Commands the server read after the message.
    after: Vec<String>,
}

/// How the fake server behaves.
#[derive(Clone, Copy)]
struct Sink {
    /// Answers DATA's content with a 451 (a greylist), taking nothing.
    defer: bool,
    /// Its reply to EHLO.
    ehlo: &'static str,
    /// Answers DATA with this instead of 354, and takes no content.
    data_reply: Option<&'static str>,
}

impl Default for Sink {
    fn default() -> Self {
        Sink {
            defer: false,
            ehlo: "250-sink\r\n250 AUTH PLAIN LOGIN\r\n",
            data_reply: None,
        }
    }
}

/// A one-connection-at-a-time SMTP server. Password "test" logs in. With
/// `defer` it answers DATA with a 451 (a greylist), so it takes nothing.
async fn smtp_sink(defer: bool) -> (u16, Arc<Mutex<Vec<Received>>>) {
    smtp_sink_with(Sink {
        defer,
        ..Sink::default()
    })
    .await
}

async fn smtp_sink_with(sink: Sink) -> (u16, Arc<Mutex<Vec<Received>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let inbox = Arc::new(Mutex::new(Vec::new()));
    let seen = inbox.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let seen = seen.clone();
            tokio::spawn(async move { serve(tcp, seen, sink).await });
        }
    });
    (port, inbox)
}

/// One line as sent, its ending included. Like many servers, it takes a
/// bare LF for the end of a line.
async fn read_line(r: &mut BufReader<OwnedReadHalf>) -> Option<Vec<u8>> {
    let mut line = Vec::new();
    match r.read_until(b'\n', &mut line).await {
        Ok(0) | Err(_) => None,
        Ok(_) => Some(line),
    }
}

fn text(line: &[u8]) -> String {
    String::from_utf8_lossy(line)
        .trim_end_matches(['\r', '\n'])
        .to_owned()
}

async fn serve(tcp: TcpStream, seen: Arc<Mutex<Vec<Received>>>, sink: Sink) {
    let (r, mut w) = tcp.into_split();
    let mut r = BufReader::new(r);
    w.write_all(b"220 sink ESMTP\r\n").await.unwrap();
    let mut current = Received::default();
    while let Some(raw) = read_line(&mut r).await {
        let line = text(&raw);
        let upper = line.to_ascii_uppercase();
        if let Some(last) = seen.lock().unwrap().last_mut() {
            last.after.push(line.clone());
        }
        let reply: &[u8] = if upper.starts_with("EHLO") {
            sink.ehlo.as_bytes()
        } else if upper.starts_with("AUTH PLAIN") {
            // base64("\0user\0test") ends with "AHRlc3Q=" for any user.
            if line.ends_with("AHRlc3Q=") {
                b"235 ok\r\n"
            } else {
                b"535 5.7.8 bad credentials\r\n"
            }
        } else if upper.starts_with("MAIL FROM") {
            current = Received::default();
            b"250 ok\r\n"
        } else if upper.starts_with("RCPT TO") {
            current.rcpt.push(line[8..].trim().to_owned());
            b"250 ok\r\n"
        } else if upper == "DATA" {
            if let Some(reply) = sink.data_reply {
                w.write_all(reply.as_bytes()).await.unwrap();
                continue;
            }
            w.write_all(b"354 go on\r\n").await.unwrap();
            while let Some(raw) = read_line(&mut r).await {
                let l = text(&raw);
                if l == "." {
                    break;
                }
                current.wire.extend_from_slice(&raw);
                current.data.push_str(l.strip_prefix('.').unwrap_or(&l));
                current.data.push('\n');
            }
            if sink.defer {
                // A greylist: not a refusal, just not now. It takes nothing.
                current = Received::default();
                b"451 4.3.2 try again later\r\n"
            } else {
                seen.lock().unwrap().push(std::mem::take(&mut current));
                b"250 queued\r\n"
            }
        } else if upper == "QUIT" {
            w.write_all(b"221 bye\r\n").await.ok();
            return;
        } else {
            b"250 ok\r\n"
        };
        w.write_all(reply).await.unwrap();
    }
}

fn smtp(port: u16, password: &str) -> SmtpConfig {
    SmtpConfig {
        host: "127.0.0.1".into(),
        port,
        security: Security::None,
        username: "me".into(),
        password: password.into(),
    }
}

fn draft() -> Draft {
    Draft {
        from_name: "Matteo".into(),
        from_email: "me@example.org".into(),
        to: vec!["Luca <luca@example.org>".into()],
        bcc: vec!["sara@example.org".into()],
        subject: "Mockups approved".into(),
        body: "We start Monday.".into(),
        ..Draft::default()
    }
}

#[tokio::test]
async fn sends_to_every_recipient() {
    let (port, inbox) = smtp_sink(false).await;
    let message = ready(&draft()).unwrap();
    send(&smtp(port, "test"), &message).await.unwrap();

    let got = inbox.lock().unwrap();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].rcpt, ["<luca@example.org>", "<sara@example.org>"]);
    assert!(got[0].data.contains("Subject: Mockups approved"));
    assert!(!got[0].data.contains("sara@example.org"));
}

#[tokio::test]
async fn wrong_password_is_an_auth_error() {
    let (port, inbox) = smtp_sink(false).await;
    let message = ready(&draft()).unwrap();
    let err = send(&smtp(port, "nope"), &message).await.unwrap_err();
    assert!(matches!(err, SendError::Auth), "{err:?}");
    assert!(inbox.lock().unwrap().is_empty());
}

#[tokio::test]
async fn unreachable_server_is_a_connect_error() {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    drop(listener);
    let message = ready(&draft()).unwrap();
    let err = send(&smtp(port, "test"), &message).await.unwrap_err();
    assert!(matches!(err, SendError::Connect { .. }), "{err:?}");
}

#[tokio::test]
async fn files_a_copy_in_sent() {
    let Some(addr) = std::env::var("PIUMA_TEST_IMAP").ok() else {
        return;
    };
    let (host, imap_port) = addr.rsplit_once(':').unwrap();
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis();
    let imap = ImapConfig {
        host: host.into(),
        port: imap_port.parse().unwrap(),
        security: Security::None,
        username: format!("sender-{stamp}"),
        password: "test".into(),
    };
    let (port, inbox) = smtp_sink(false).await;

    let report = send_and_file(&smtp(port, "test"), &imap, &ready(&draft()).unwrap())
        .await
        .unwrap();
    assert_eq!(report.filed_in.as_deref(), Some("Sent"));
    assert!(report.message_id.starts_with('<'));
    assert_eq!(inbox.lock().unwrap().len(), 1);

    // The copy is there, already read.
    let tcp = TcpStream::connect((host, imap.port)).await.unwrap();
    let mut client = async_imap::Client::new(tcp);
    client.read_response().await.unwrap();
    let mut s = client
        .login(&imap.username, "test")
        .await
        .map_err(|(e, _)| e)
        .unwrap();
    s.select("Sent").await.unwrap();
    let fetched: Vec<_> = s
        .fetch("1", "(FLAGS BODY.PEEK[HEADER.FIELDS (SUBJECT MESSAGE-ID)])")
        .await
        .unwrap()
        .try_collect()
        .await
        .unwrap();
    assert_eq!(fetched.len(), 1);
    let header = String::from_utf8_lossy(fetched[0].header().unwrap()).to_string();
    assert!(header.contains("Mockups approved"));
    assert!(header.contains(&report.message_id));
    assert!(fetched[0]
        .flags()
        .any(|f| f == async_imap::types::Flag::Seen));
}

/// An account whose servers are on this machine, at these ports.
fn account(id: AccountId, smtp_port: u16, imap_port: u16) -> Account {
    Account {
        id,
        name: "Test".into(),
        email: "me@example.org".into(),
        sender_name: String::new(),
        color: "#2F8F83".into(),
        kind: AccountKind::Imap {
            imap: Server {
                host: "127.0.0.1".into(),
                port: imap_port,
                security: Security::None,
            },
            smtp: Server {
                host: "127.0.0.1".into(),
                port: smtp_port,
                security: Security::None,
            },
            username: "me".into(),
        },
    }
}

fn closed_port() -> u16 {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    listener.local_addr().unwrap().port()
}

#[tokio::test]
async fn mail_sent_offline_waits_in_the_outbox_and_goes_later() {
    let store = Store::open_in_memory().unwrap();
    let id = store.add_account(&account(AccountId(0), 25, 143)).unwrap();
    let store = Mutex::new(store);
    let (down, no_imap) = (closed_port(), closed_port());

    // Offline: the send can't reach the server, so it waits.
    let offline = account(id, down, no_imap);
    let err = remote::send(&offline, "test", &draft()).await.unwrap_err();
    assert!(err.is_offline(), "{err:?}");
    let out = Outgoing {
        account: id,
        draft: draft(),
        ready: ready(&draft()).unwrap(),
        saved: Some(("Drafts".into(), 7)),
        send_at: None,
    };
    let queued = store.lock().unwrap().queue_outgoing(&out, 1_000).unwrap();
    assert!(outbox::send(&store, &offline, "test")
        .await
        .unwrap()
        .is_empty());
    let waiting = store.lock().unwrap().outbox(None).unwrap();
    assert_eq!(waiting.len(), 1);
    assert_eq!(waiting[0].to, ["Luca <luca@example.org>"]);
    assert_eq!(waiting[0].error, None);

    // A refused password keeps it waiting, without a reason.
    let (port, inbox) = smtp_sink(false).await;
    let online = account(id, port, no_imap);
    assert!(outbox::send(&store, &online, "nope")
        .await
        .unwrap()
        .is_empty());
    assert_eq!(store.lock().unwrap().outbox(None).unwrap()[0].error, None);

    // Back online: it goes as it was built, and leaves the outbox.
    let sent = outbox::send(&store, &online, "test").await.unwrap();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].id, queued);
    assert_eq!(sent[0].saved, Some(("Drafts".into(), 7)));
    assert!(!sent[0].filed);
    assert!(store.lock().unwrap().outbox(None).unwrap().is_empty());
    let got = inbox.lock().unwrap();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].rcpt, ["<luca@example.org>", "<sara@example.org>"]);
    assert!(got[0].data.contains(&out.ready.message_id));
}

#[tokio::test]
async fn mail_deferred_by_the_server_keeps_waiting_and_goes_later() {
    let store = Store::open_in_memory().unwrap();
    let id = store.add_account(&account(AccountId(0), 25, 143)).unwrap();
    let store = Mutex::new(store);
    let no_imap = closed_port();

    let out = Outgoing {
        account: id,
        draft: draft(),
        ready: ready(&draft()).unwrap(),
        saved: Some(("Drafts".into(), 7)),
        send_at: None,
    };
    let queued = store.lock().unwrap().queue_outgoing(&out, 1_000).unwrap();

    // A 451 (a greylist): the server is not refusing the message, it is
    // just not taking it now. It stays in the outbox, without a reason.
    let (port, _deferred) = smtp_sink(true).await;
    let deferring = account(id, port, no_imap);
    assert!(outbox::send(&store, &deferring, "test")
        .await
        .unwrap()
        .is_empty());
    let waiting = store.lock().unwrap().outbox(None).unwrap();
    assert_eq!(waiting.len(), 1);
    assert_eq!(waiting[0].id, queued);
    assert_eq!(waiting[0].error, None);

    // A server that takes it: it goes as it was built, and leaves.
    let (port, inbox) = smtp_sink(false).await;
    let online = account(id, port, no_imap);
    let sent = outbox::send(&store, &online, "test").await.unwrap();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].id, queued);
    assert_eq!(sent[0].saved, Some(("Drafts".into(), 7)));
    assert!(!sent[0].filed);
    assert!(store.lock().unwrap().outbox(None).unwrap().is_empty());
    let got = inbox.lock().unwrap();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].rcpt, ["<luca@example.org>", "<sara@example.org>"]);
    assert!(got[0].data.contains(&out.ready.message_id));
}

#[tokio::test]
async fn mail_sent_later_waits_for_its_time_and_is_dated_then() {
    let store = Store::open_in_memory().unwrap();
    let id = store.add_account(&account(AccountId(0), 25, 143)).unwrap();
    let store = Mutex::new(store);
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    let queue = |send_at: i64| {
        let mut draft = draft();
        draft.date = Some(send_at);
        let out = Outgoing {
            account: id,
            ready: ready(&draft).unwrap(),
            draft,
            saved: None,
            send_at: Some(send_at),
        };
        store.lock().unwrap().queue_outgoing(&out, now).unwrap()
    };
    let later = queue(now + 3600);
    let due = queue(now - 5);
    assert_eq!(
        store.lock().unwrap().next_due(id, now).unwrap(),
        Some(now - 5)
    );
    assert_eq!(
        store
            .lock()
            .unwrap()
            .outgoing(later)
            .unwrap()
            .unwrap()
            .send_at,
        Some(now + 3600)
    );

    // Only the one whose time has come goes.
    let (port, inbox) = smtp_sink(false).await;
    let online = account(id, port, closed_port());
    let sent = outbox::send(&store, &online, "test").await.unwrap();
    assert_eq!(sent.iter().map(|s| s.id).collect::<Vec<_>>(), [due]);
    let waiting = store.lock().unwrap().outbox(None).unwrap();
    assert_eq!(waiting.iter().map(|w| w.id).collect::<Vec<_>>(), [later]);
    assert_eq!(waiting[0].send_at, Some(now + 3600));
    assert_eq!(
        store.lock().unwrap().next_due(id, now).unwrap(),
        Some(now + 3600)
    );
    // Dated for when it was meant to go, not when it was written.
    let got = inbox.lock().unwrap();
    let date = got[0]
        .data
        .lines()
        .find_map(|l| l.strip_prefix("Date: "))
        .unwrap()
        .to_owned();
    let sent_at = mail_parser::DateTime::parse_rfc822(&date).unwrap();
    assert_eq!(sent_at.to_timestamp(), now - 5);
}

/// Every line of the message ends in CRLF on the wire: no bare CR or LF.
fn only_crlf(wire: &[u8]) -> bool {
    wire.iter().enumerate().all(|(i, &b)| match b {
        b'\r' => wire.get(i + 1) == Some(&b'\n'),
        b'\n' => i > 0 && wire[i - 1] == b'\r',
        _ => true,
    })
}

#[tokio::test]
async fn a_body_with_bare_line_endings_and_a_lone_dot_arrives_whole() {
    let (port, inbox) = smtp_sink(false).await;
    let mut d = draft();
    d.body = "First line\nsecond\rthird\n.\nafter the dot\n.\r\nend".into();
    send(&smtp(port, "test"), &ready(&d).unwrap())
        .await
        .unwrap();

    let got = inbox.lock().unwrap();
    assert_eq!(got.len(), 1);
    assert!(only_crlf(&got[0].wire), "{:?}", got[0].wire);
    // The lone dots went stuffed, so the server read them as text.
    assert!(got[0].wire.windows(5).any(|w| w == b"\r\n..\r"));
    assert!(
        got[0].after.iter().all(|c| c == "QUIT"),
        "{:?}",
        got[0].after
    );
    let parsed = mail_parser::MessageParser::default()
        .parse(got[0].data.as_bytes())
        .unwrap();
    assert_eq!(
        parsed
            .body_text(0)
            .unwrap()
            .replace("\r\n", "\n")
            .trim_end(),
        "First line\nsecond\nthird\n.\nafter the dot\n.\nend"
    );
}

#[tokio::test]
async fn a_raw_message_with_bare_line_endings_is_sent_with_crlf() {
    // Like a message kept in the outbox by an older version.
    let (port, inbox) = smtp_sink(false).await;
    let message = Ready {
        message_id: "<old@example.org>".into(),
        from: "me@example.org".into(),
        recipients: vec!["luca@example.org".into()],
        raw: b"Subject: old\nMessage-ID: <old@example.org>\n\nline\n.\nafter\r.\rend\n".to_vec(),
    };
    send(&smtp(port, "test"), &message).await.unwrap();

    let got = inbox.lock().unwrap();
    assert_eq!(got.len(), 1);
    assert!(only_crlf(&got[0].wire), "{:?}", got[0].wire);
    assert_eq!(
        got[0].wire,
        b"Subject: old\r\nMessage-ID: <old@example.org>\r\n\r\nline\r\n..\r\nafter\r\n..\r\nend\r\n"
    );
    assert!(
        got[0].after.iter().all(|c| c == "QUIT"),
        "{:?}",
        got[0].after
    );
}

#[tokio::test]
async fn a_display_name_with_a_line_break_stays_on_one_line() {
    let (port, inbox) = smtp_sink(false).await;
    let mut d = draft();
    d.from_name = "Matteo\r\nX-Injected: yes".into();
    d.to = vec!["Luca\nBianchi\r <luca@example.org>".into()];
    send(&smtp(port, "test"), &ready(&d).unwrap())
        .await
        .unwrap();

    let got = inbox.lock().unwrap();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].rcpt, ["<luca@example.org>", "<sara@example.org>"]);
    assert!(only_crlf(&got[0].wire));
    let head = got[0].data.split("\n\n").next().unwrap();
    assert!(!head.lines().any(|l| l.starts_with("X-Injected")), "{head}");
    let parsed = mail_parser::MessageParser::default()
        .parse(got[0].data.as_bytes())
        .unwrap();
    assert_eq!(
        parsed.from().unwrap().first().unwrap().name(),
        Some("Matteo X-Injected: yes")
    );
    assert_eq!(
        parsed.to().unwrap().first().unwrap().name(),
        Some("Luca Bianchi")
    );
}

#[tokio::test]
async fn a_quoted_local_part_goes_to_that_exact_address() {
    let (port, inbox) = smtp_sink(false).await;
    let mut d = draft();
    d.to = vec!["D <\"d \"@example.org>".into()];
    d.bcc.clear();
    let message = ready(&d).unwrap();
    assert_eq!(message.recipients, ["\"d \"@example.org"]);
    send(&smtp(port, "test"), &message).await.unwrap();

    let got = inbox.lock().unwrap();
    assert_eq!(got.len(), 1);
    // Never rewritten to d@example.org, in the envelope or in the header.
    assert_eq!(got[0].rcpt, ["<\"d \"@example.org>"]);
    let parsed = mail_parser::MessageParser::default()
        .parse(got[0].data.as_bytes())
        .unwrap();
    assert_eq!(
        parsed.to().unwrap().first().unwrap().address(),
        Some("\"d \"@example.org")
    );
    assert!(!got[0].data.contains("<d@example.org>"));
}

#[tokio::test]
async fn an_ehlo_line_of_only_spaces_is_skipped() {
    let (port, inbox) = smtp_sink_with(Sink {
        ehlo: "250-sink\r\n250-   \r\n250 AUTH PLAIN LOGIN\r\n",
        ..Sink::default()
    })
    .await;
    send(&smtp(port, "test"), &ready(&draft()).unwrap())
        .await
        .unwrap();
    assert_eq!(inbox.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn a_reply_out_of_turn_is_a_protocol_error() {
    // DATA answered as if the message were already taken: nothing is
    // sent, and it is not taken for a network failure to retry on its own.
    let (port, inbox) = smtp_sink_with(Sink {
        data_reply: Some("250 ok\r\n"),
        ..Sink::default()
    })
    .await;
    let err = send(&smtp(port, "test"), &ready(&draft()).unwrap())
        .await
        .unwrap_err();
    assert!(matches!(err, SendError::Protocol(_)), "{err:?}");
    assert!(!err.is_offline());
    assert!(inbox.lock().unwrap().is_empty());
}

/// What the original of a redirect or a forward looks like on the wire.
const ORIGINAL: &str = "Delivered-To: me@example.org\r\nReturn-Path: <anna@x.it>\r\n\
From: Anna <anna@x.it>\r\nTo: me@example.org\r\nCc: Bo <bo@x.it>\r\n\
Subject: Plan for Friday\r\nMessage-ID: <plan@x.it>\r\n\
Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n\
See you at 20:30, caff=C3=A8 after.\r\n";

#[tokio::test]
async fn redirect_resends_the_message_unchanged_with_resent_headers() {
    use piuma_core::envelope;
    let (port, inbox) = smtp_sink(false).await;
    let id = envelope::new_message_id("me@example.org");
    let to = vec!["carla@example.org".to_owned()];
    let message = piuma_core::smtp::Ready {
        message_id: id.clone(),
        from: "me@example.org".into(),
        recipients: to.clone(),
        raw: envelope::resend(
            ORIGINAL.as_bytes(),
            "me@example.org",
            &to,
            1_790_000_000,
            &id,
        ),
    };
    send(&smtp(port, "test"), &message).await.unwrap();

    let got = inbox.lock().unwrap();
    assert_eq!(got.len(), 1);
    // Only the new recipient: neither the original To nor its Cc hear of it.
    assert_eq!(got[0].rcpt, ["<carla@example.org>"]);
    let data = &got[0].data;
    assert!(data.starts_with("Resent-From: me@example.org\n"), "{data}");
    assert!(data.contains("Resent-To: carla@example.org\n"), "{data}");
    assert!(
        data.contains(&format!("Resent-Message-ID: {id}\n")),
        "{data}"
    );
    assert!(data.contains("Resent-Date: "), "{data}");
    // The message itself is as it came, From and Message-ID included.
    assert!(
        data.contains("From: Anna <anna@x.it>\nTo: me@example.org\n"),
        "{data}"
    );
    assert!(data.contains("Message-ID: <plan@x.it>\n"), "{data}");
    assert!(
        data.contains("\n\nSee you at 20:30, caff=C3=A8 after.\n"),
        "{data}"
    );
    // Not the person's own delivery headers, which would look like a loop.
    assert!(!data.contains("Delivered-To"), "{data}");
    assert!(!data.contains("Return-Path"), "{data}");
}

#[tokio::test]
async fn forward_as_attachment_sends_the_original_as_message_rfc822() {
    let (port, inbox) = smtp_sink(false).await;
    let mut d = draft();
    d.bcc.clear();
    d.subject = "Fwd: Plan for Friday".into();
    d.body = String::new();
    d.files = vec![piuma_core::smtp::OutgoingFile {
        name: "Plan for Friday.eml".into(),
        mime: piuma_core::files::mime_for("Plan for Friday.eml").into(),
        data: ORIGINAL.as_bytes().to_vec(),
    }];
    send(&smtp(port, "test"), &ready(&d).unwrap())
        .await
        .unwrap();

    let got = inbox.lock().unwrap();
    let data = &got[0].data;
    assert!(data.contains("Content-Type: message/rfc822"), "{data}");
    assert!(data.contains("Content-Transfer-Encoding: 7bit"), "{data}");
    let raw = data.replace('\n', "\r\n");
    let m = mail_parser::MessageParser::default()
        .parse(raw.as_bytes())
        .unwrap();
    let inner = m.attachments().next().unwrap().nested().unwrap();
    assert_eq!(inner.subject(), Some("Plan for Friday"));
    assert_eq!(inner.message_id(), Some("plan@x.it"));
    assert_eq!(
        inner.body_text(0).unwrap().trim_end(),
        "See you at 20:30, caffè after."
    );
}
