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
use piuma_core::smtp::{ready, send, send_and_file, Draft, SendError, SmtpConfig};
use piuma_core::{Account, AccountId, AccountKind, Security, Server, Store};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};

/// What the fake server received.
#[derive(Default, Debug)]
struct Received {
    rcpt: Vec<String>,
    data: String,
}

/// A one-connection-at-a-time SMTP server. Password "test" logs in.
async fn smtp_sink() -> (u16, Arc<Mutex<Vec<Received>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let inbox = Arc::new(Mutex::new(Vec::new()));
    let seen = inbox.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let seen = seen.clone();
            tokio::spawn(async move { serve(tcp, seen).await });
        }
    });
    (port, inbox)
}

async fn serve(tcp: TcpStream, seen: Arc<Mutex<Vec<Received>>>) {
    let (r, mut w) = tcp.into_split();
    let mut lines = BufReader::new(r).lines();
    w.write_all(b"220 sink ESMTP\r\n").await.unwrap();
    let mut current = Received::default();
    while let Ok(Some(line)) = lines.next_line().await {
        let upper = line.to_ascii_uppercase();
        let reply: &[u8] = if upper.starts_with("EHLO") {
            b"250-sink\r\n250 AUTH PLAIN LOGIN\r\n"
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
            w.write_all(b"354 go on\r\n").await.unwrap();
            while let Ok(Some(l)) = lines.next_line().await {
                if l == "." {
                    break;
                }
                current.data.push_str(&l);
                current.data.push('\n');
            }
            seen.lock().unwrap().push(std::mem::take(&mut current));
            b"250 queued\r\n"
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
    let (port, inbox) = smtp_sink().await;
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
    let (port, inbox) = smtp_sink().await;
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
    let (port, inbox) = smtp_sink().await;

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
    let (port, inbox) = smtp_sink().await;
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
    let (port, inbox) = smtp_sink().await;
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
