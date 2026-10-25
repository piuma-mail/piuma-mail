//! Engine against a real IMAP server.
//!
//! Start one with `tools/test-imap-server.sh`, then:
//!     PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test
//! Without PIUMA_TEST_IMAP these tests pass without doing anything.

use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use futures::TryStreamExt;
use piuma_core::imap::{
    check_login, watch, Connection, FolderRole, ImapConfig, ImapError, Round, WatchEvent,
};
use piuma_core::pending::Change;
use piuma_core::smtp;
use piuma_core::{
    Account, AccountId, AccountKind, Flags, Folder, MailboxState, Section, Security, Server, Store,
};
use tokio::net::TcpStream;

fn server() -> Option<(String, u16)> {
    let addr = std::env::var("PIUMA_TEST_IMAP").ok()?;
    let (host, port) = addr.rsplit_once(':')?;
    Some((host.to_owned(), port.parse().ok()?))
}

/// Every test gets its own user, so its own empty mailbox.
fn config(test: &str) -> Option<ImapConfig> {
    static RUN: AtomicU32 = AtomicU32::new(0);
    let (host, port) = server()?;
    let n = RUN.fetch_add(1, Ordering::Relaxed);
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis();
    Some(ImapConfig {
        host,
        port,
        security: Security::None,
        username: format!("{test}-{stamp}-{n}"),
        password: "test".into(),
    })
}

fn store_with_account() -> (Arc<Mutex<Store>>, AccountId) {
    let store = Store::open_in_memory().unwrap();
    let id = store
        .add_account(&Account {
            id: AccountId(0),
            name: "Test".into(),
            email: "me@example.org".into(),
            sender_name: String::new(),
            color: "#2F8F83".into(),
            kind: AccountKind::Imap {
                imap: Server {
                    host: "localhost".into(),
                    port: 31143,
                    security: Security::None,
                },
                smtp: Server {
                    host: "localhost".into(),
                    port: 465,
                    security: Security::Tls,
                },
                username: "me".into(),
            },
        })
        .unwrap();
    (Arc::new(Mutex::new(store)), id)
}

/// A second, plain client that plays "the rest of the world".
struct Outside(async_imap::Session<TcpStream>);

impl Outside {
    async fn open(cfg: &ImapConfig) -> Self {
        let tcp = TcpStream::connect((cfg.host.as_str(), cfg.port))
            .await
            .unwrap();
        let mut client = async_imap::Client::new(tcp);
        client.read_response().await.unwrap();
        let mut s = client
            .login(&cfg.username, &cfg.password)
            .await
            .map_err(|(e, _)| e)
            .unwrap();
        s.select("INBOX").await.unwrap();
        Outside(s)
    }

    async fn deliver(&mut self, raw: &str, date: &str) {
        let raw = raw.replace('\n', "\r\n");
        self.0
            .append("INBOX", None, Some(&format!("\"{date}\"")), raw)
            .await
            .unwrap();
    }

    async fn store(&mut self, uid: u32, flags: &str) {
        let _: Vec<_> = self
            .0
            .uid_store(uid.to_string(), flags)
            .await
            .unwrap()
            .try_collect()
            .await
            .unwrap();
    }

    async fn expunge(&mut self) {
        let _: Vec<_> = self.0.expunge().await.unwrap().try_collect().await.unwrap();
    }
}

const PLAIN: &str = "From: Julia Reed <julia@example.org>
To: me@example.org
Subject: New website quote
Date: Mon, 12 Oct 2026 09:41:00 +0200
Content-Type: text/plain; charset=utf-8

Hi,

here is the   updated version with the changes.
> quoted older text

Julia
";

const ENCODED_MULTIPART: &str = "From: =?UTF-8?Q?Luca_Bianch=C3=AC?= <luca@example.org>
To: me@example.org
Subject: =?UTF-8?B?Uml1bmlvbmUgZGkgZ2lvdmVkw6w=?=
Date: Tue, 13 Oct 2026 15:00:00 +0200
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary=\"b1\"

--b1
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: quoted-printable

Per me va bene alle 15, porto i bozzetti =C3=A0 posto.
--b1
Content-Type: text/html; charset=utf-8
Content-Transfer-Encoding: quoted-printable

<p>Per me va bene alle 15,</p><p>porto i bozzetti =C3=A0 posto.</p>
--b1--
";

const HTML_ONLY: &str = "From: Sarah Ford <sarah@example.org>
To: me@example.org
Subject: Signed contract
Date: Wed, 14 Oct 2026 08:00:00 +0200
MIME-Version: 1.0
Content-Type: text/html; charset=utf-8

<html><body><h1>Contract</h1><p>Attached is the copy <b>signed</b> by both of us.</p></body></html>
";

const NEWSLETTER: &str = "From: Shop <hello@shop.example>\r
To: test@example.org\r
Subject: This week at the shop\r
List-Unsubscribe: <https://shop.example/unsubscribe>\r
Content-Type: text/plain; charset=utf-8\r
\r
New arrivals and a sale.\r
";

#[tokio::test]
async fn first_sync_downloads_newest_first_with_clean_rows() {
    let Some(cfg) = config("first") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside
        .deliver(ENCODED_MULTIPART, "13-Oct-2026 15:00:00 +0200")
        .await;
    outside
        .deliver(HTML_ONLY, "14-Oct-2026 08:00:00 +0200")
        .await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    let mut seen_progress = Vec::new();
    let report = conn
        .sync_mailbox(&store, account, "INBOX", |done, total| {
            seen_progress.push((done, total))
        })
        .await
        .unwrap();
    assert_eq!(report.added, 3);
    assert_eq!(seen_progress.last(), Some(&(3, 3)));
    // The first download is history, not news.
    assert!(report.arrived.is_empty());

    let rows = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 10)
        .unwrap();
    let subjects: Vec<_> = rows.iter().map(|m| m.subject.as_str()).collect();
    assert_eq!(
        subjects,
        [
            "Signed contract",
            "Riunione di giovedì",
            "New website quote"
        ]
    );
    assert_eq!(rows[1].from_name, "Luca Bianchì");
    assert_eq!(rows[1].from_email, "luca@example.org");
    assert_eq!(
        rows[1].preview,
        "Per me va bene alle 15, porto i bozzetti à posto."
    );
    assert_eq!(
        rows[2].preview,
        "Hi, here is the updated version with the changes. Julia"
    );
    assert!(
        rows[0].preview.contains("signed by both of us"),
        "{}",
        rows[0].preview
    );
    assert!(rows.iter().all(|m| !m.flags.seen));

    // A second sync with nothing new does nothing.
    let again = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert!(!again.changed(), "{again:?}");
}

#[tokio::test]
async fn resync_applies_deletes_flags_and_new_mail() {
    let Some(cfg) = config("resync") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside
        .deliver(ENCODED_MULTIPART, "13-Oct-2026 15:00:00 +0200")
        .await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();

    outside.store(1, "+FLAGS (\\Seen \\Flagged)").await;
    outside.store(2, "+FLAGS (\\Deleted)").await;
    outside.expunge().await;
    outside
        .deliver(HTML_ONLY, "14-Oct-2026 08:00:00 +0200")
        .await;
    outside
        .deliver(NEWSLETTER, "14-Oct-2026 09:00:00 +0200")
        .await;

    let report = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(
        (report.added, report.removed, report.flags_changed),
        (2, 1, 1)
    );
    // What came in is news, and the headers tell people from machines.
    let mut arrived: Vec<_> = report
        .arrived
        .iter()
        .map(|a| (a.summary.subject.as_str(), a.automated))
        .collect();
    arrived.sort();
    assert_eq!(
        arrived,
        [("Signed contract", false), ("This week at the shop", true)]
    );
    let s = store.lock().unwrap();
    let mut uids = s.uids(account, "INBOX").unwrap();
    uids.sort();
    assert_eq!(uids, [1, 3, 4]);
    let first = s.message(account, "INBOX", 1).unwrap().unwrap();
    assert!(first.flags.seen && first.flags.flagged);
}

#[tokio::test]
async fn big_folders_fill_in_rounds_without_false_news() {
    let Some(cfg) = config("rounds") else { return };
    let mut outside = Outside::open(&cfg).await;
    for day in 10..15 {
        let raw = PLAIN.replace("New website quote", &format!("Old {day}"));
        outside
            .deliver(&raw, &format!("{day}-Oct-2026 09:00:00 +0200"))
            .await;
    }
    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    let round = |flags| Round { limit: 2, flags };
    let subjects = |r: &piuma_core::imap::SyncReport| {
        let mut out: Vec<_> = r
            .arrived
            .iter()
            .map(|a| a.summary.subject.clone())
            .collect();
        out.sort();
        out
    };

    // The newest two first.
    let first = conn
        .sync_round(&store, account, "INBOX", round(true), |_, _| {})
        .await
        .unwrap();
    assert_eq!((first.added, first.more), (2, 3));
    let mut uids = store.lock().unwrap().uids(account, "INBOX").unwrap();
    uids.sort();
    assert_eq!(uids, [4, 5]);

    // Mail that comes meanwhile goes first and is the only news; a flag
    // changed on a message already here waits for the round that looks.
    outside.store(5, "+FLAGS (\\Seen)").await;
    outside
        .deliver(HTML_ONLY, "16-Oct-2026 08:00:00 +0200")
        .await;
    let second = conn
        .sync_round(&store, account, "INBOX", round(false), |_, _| {})
        .await
        .unwrap();
    assert_eq!((second.added, second.more), (2, 2));
    assert_eq!(subjects(&second), ["Signed contract"]);
    let third = conn
        .sync_round(&store, account, "INBOX", round(false), |_, _| {})
        .await
        .unwrap();
    assert_eq!((third.added, third.more), (2, 0));
    assert!(third.arrived.is_empty(), "{:?}", subjects(&third));
    assert_eq!(
        store.lock().unwrap().uids(account, "INBOX").unwrap().len(),
        6
    );

    let last = conn
        .sync_round(&store, account, "INBOX", round(true), |_, _| {})
        .await
        .unwrap();
    assert_eq!((last.added, last.flags_changed), (0, 1));
    let s = store.lock().unwrap();
    assert!(s.message(account, "INBOX", 5).unwrap().unwrap().flags.seen);
}

#[tokio::test]
async fn changed_uidvalidity_rebuilds_the_cache() {
    let Some(cfg) = config("validity") else {
        return;
    };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    {
        let s = store.lock().unwrap();
        let mut state = s.mailbox_state(account, "INBOX").unwrap().unwrap();
        state.uid_validity = state.uid_validity.wrapping_add(1);
        s.set_mailbox_state(account, "INBOX", MailboxState { ..state })
            .unwrap();
    }
    let report = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert!(report.reset);
    assert_eq!(report.added, 1);
}

#[tokio::test]
async fn body_is_fetched_once_then_cached() {
    let Some(cfg) = config("body") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside
        .deliver(HTML_ONLY, "14-Oct-2026 08:00:00 +0200")
        .await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let text = conn.body(&store, account, "INBOX", 1).await.unwrap();
    assert!(
        text.contains("Attached is the copy signed by both of us."),
        "{text}"
    );
    assert_eq!(
        store.lock().unwrap().body(account, "INBOX", 1).unwrap(),
        Some(text.clone())
    );
    // The HTML is kept, for the safe reader.
    let body = conn.full_body(&store, account, "INBOX", 1).await.unwrap();
    assert_eq!(body.text, text);
    let readable = piuma_core::reading::readable(&body.text, body.html.as_deref());
    assert!(readable
        .blocks
        .iter()
        .any(|b| b.text().contains("signed by both of us")));
    // Reading must not mark the message as read on the server.
    let row = store
        .lock()
        .unwrap()
        .message(account, "INBOX", 1)
        .unwrap()
        .unwrap();
    assert!(!row.flags.seen);
}

#[tokio::test]
async fn new_mail_is_noticed_within_two_seconds() {
    let Some(cfg) = config("idle") else { return };
    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    assert!(conn.supports_idle());
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();

    let outside_cfg = cfg.clone();
    let sent = Arc::new(Mutex::new(None::<Instant>));
    let sent_at = sent.clone();
    tokio::spawn(async move {
        let mut outside = Outside::open(&outside_cfg).await;
        tokio::time::sleep(Duration::from_millis(300)).await;
        *sent_at.lock().unwrap() = Some(Instant::now());
        outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    });

    let changed = tokio::time::timeout(
        Duration::from_secs(10),
        conn.wait_for_change(Duration::from_secs(30)),
    )
    .await
    .expect("IDLE never woke up")
    .unwrap();
    assert!(changed);
    let report = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let elapsed = sent.lock().unwrap().unwrap().elapsed();
    assert_eq!(report.added, 1);
    assert!(elapsed < Duration::from_secs(2), "took {elapsed:?}");
}

#[tokio::test]
async fn idle_gives_up_on_time_while_the_server_says_still_here() {
    let Some(cfg) = config("idle-quiet") else {
        return;
    };
    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    // The test server says "Still here" every second; some servers (Aruba)
    // never report new mail, so the timeout is all that brings it in.
    let changed = tokio::time::timeout(
        Duration::from_secs(8),
        conn.wait_for_change(Duration::from_secs(3)),
    )
    .await
    .expect("IDLE waited past its timeout")
    .unwrap();
    assert!(!changed);
}

#[tokio::test]
async fn watcher_keeps_the_inbox_in_sync() {
    let Some(cfg) = config("watch") else { return };
    let (store, account) = store_with_account();
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let task = tokio::spawn(watch(
        cfg.clone(),
        store.clone(),
        account,
        "INBOX".into(),
        move |e| {
            tx.send(e).ok();
        },
    ));
    assert_eq!(next_sync(&mut rx).await.added, 0);
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    assert_eq!(next_sync(&mut rx).await.added, 1);
    assert_eq!(store.lock().unwrap().count(Folder::Inbox).unwrap(), 1);
    task.abort();
}

async fn next_sync(
    rx: &mut tokio::sync::mpsc::UnboundedReceiver<WatchEvent>,
) -> piuma_core::imap::SyncReport {
    loop {
        match tokio::time::timeout(Duration::from_secs(10), rx.recv()).await {
            Ok(Some(WatchEvent::Synced { report, .. })) => return report,
            Ok(Some(_)) => continue,
            other => panic!("no sync: {other:?}"),
        }
    }
}

#[tokio::test]
async fn wrong_password_is_reported_as_such() {
    let Some(mut cfg) = config("auth") else {
        return;
    };
    cfg.password = "nope".into();
    assert!(matches!(check_login(&cfg).await, Err(ImapError::Auth)));
}

/// Phase 1 target: a 50,000-message inbox. Slow, so run it on purpose:
///     PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test --release -- --ignored --nocapture
#[tokio::test]
#[ignore]
async fn syncs_a_50k_inbox() {
    let Some(cfg) = config("big") else { return };
    let mut outside = Outside::open(&cfg).await;
    let start = Instant::now();
    for i in 0..50_000u32 {
        let raw = PLAIN.replace("New website quote", &format!("Message number {i}"));
        let day = 1 + i % 28;
        outside
            .deliver(
                &raw,
                &format!("{day:02}-Sep-2026 09:{:02}:00 +0200", i % 60),
            )
            .await;
    }
    println!("delivered in {:?}", start.elapsed());

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    let start = Instant::now();
    let mut first_rows = None;
    let report = conn
        .sync_mailbox(&store, account, "INBOX", |done, _| {
            if first_rows.is_none() && done > 0 {
                first_rows = Some(start.elapsed());
            }
        })
        .await
        .unwrap();
    println!(
        "first rows after {:?}, full sync in {:?}",
        first_rows.unwrap(),
        start.elapsed()
    );
    assert_eq!(report.added, 50_000);

    let start = Instant::now();
    let again = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    println!("sync with nothing new in {:?}", start.elapsed());
    assert!(!again.changed());

    let s = store.lock().unwrap();
    let start = Instant::now();
    for offset in (0..50_000).step_by(5_000) {
        assert_eq!(s.unified_page(Folder::Inbox, offset, 60).unwrap().len(), 60);
    }
    println!("10 random pages of 60 rows in {:?}", start.elapsed());
}

const REPLY: &str = "From: Julia Reed <julia@example.org>
Reply-To: team@example.org
To: me@example.org
Subject: Re: New website quote
Message-ID: <r2@example.org>
In-Reply-To: <r1@example.org>
References: <r0@example.org> <r1@example.org>
Date: Thu, 15 Oct 2026 09:00:00 +0200
Content-Type: text/plain; charset=utf-8

Sounds good.
";

#[tokio::test]
async fn sync_keeps_what_a_reply_needs() {
    let Some(cfg) = config("reply") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(REPLY, "15-Oct-2026 09:00:00 +0200").await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let rows = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 10)
        .unwrap();
    assert_eq!(rows[0].reply.message_id, "<r2@example.org>");
    assert_eq!(
        rows[0].reply.references,
        "<r0@example.org> <r1@example.org>"
    );
    assert_eq!(rows[0].reply.reply_to, "team@example.org");
    assert_eq!(rows[1].reply.message_id, "");
}

async fn folder_count(outside: &mut Outside, folder: &str) -> u32 {
    let mailbox = outside.0.examine(folder).await.unwrap();
    outside.0.select("INBOX").await.unwrap();
    mailbox.exists
}

#[tokio::test]
async fn changes_made_offline_reach_the_server_before_the_sync() {
    let Some(cfg) = config("offline") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside.deliver(REPLY, "15-Oct-2026 09:00:00 +0200").await;
    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    conn.logout().await.unwrap();

    // What the app does when the server can't be reached.
    {
        let s = store.lock().unwrap();
        s.set_flags(
            account,
            "INBOX",
            1,
            Flags {
                seen: true,
                ..Flags::default()
            },
        )
        .unwrap();
        s.queue_change(account, "INBOX", 1, Change::Seen(true))
            .unwrap();
        s.set_hidden(account, "INBOX", 2, true).unwrap();
        s.queue_change(account, "INBOX", 2, Change::Move(FolderRole::Archive))
            .unwrap();
    }

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let task = tokio::spawn(watch(
        cfg.clone(),
        store.clone(),
        account,
        "INBOX".into(),
        move |e| {
            tx.send(e).ok();
        },
    ));
    next_sync(&mut rx).await;
    task.abort();

    assert!(store
        .lock()
        .unwrap()
        .pending_changes(account)
        .unwrap()
        .is_empty());
    {
        let s = store.lock().unwrap();
        assert!(s.message(account, "INBOX", 1).unwrap().unwrap().flags.seen);
        assert!(s.message(account, "INBOX", 2).unwrap().is_none());
    }
    assert_eq!(folder_count(&mut outside, "INBOX").await, 1);
    assert_eq!(folder_count(&mut outside, "Archive").await, 1);
    let fetched: Vec<_> = outside
        .0
        .uid_fetch("1", "FLAGS")
        .await
        .unwrap()
        .try_collect()
        .await
        .unwrap();
    assert!(fetched[0]
        .flags()
        .any(|f| matches!(f, async_imap::types::Flag::Seen)));
}

#[tokio::test]
async fn archive_and_delete_move_messages() {
    for without_move in [false, true] {
        let Some(cfg) = config("move") else { return };
        let mut outside = Outside::open(&cfg).await;
        outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
        outside.deliver(REPLY, "15-Oct-2026 09:00:00 +0200").await;

        let (store, account) = store_with_account();
        let mut conn = Connection::open(&cfg).await.unwrap();
        if without_move {
            conn.forget_move_for_tests();
        }
        conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
            .await
            .unwrap();

        let archived = conn
            .move_message(&store, account, "INBOX", 1, FolderRole::Archive)
            .await
            .unwrap();
        assert_eq!(archived, "Archive");
        let trashed = conn
            .move_message(&store, account, "INBOX", 2, FolderRole::Trash)
            .await
            .unwrap();
        assert_eq!(trashed, "Trash");

        assert_eq!(store.lock().unwrap().count(Folder::Inbox).unwrap(), 0);
        assert_eq!(
            folder_count(&mut outside, "INBOX").await,
            0,
            "{without_move}"
        );
        assert_eq!(folder_count(&mut outside, "Archive").await, 1);
        assert_eq!(folder_count(&mut outside, "Trash").await, 1);

        // A second archive reuses the folder instead of making another.
        assert_eq!(conn.folder(FolderRole::Archive).await.unwrap(), "Archive");
    }
}

#[tokio::test]
async fn attachments_are_listed_then_fetched_on_demand() {
    let Some(cfg) = config("attach") else { return };
    let draft = piuma_core::smtp::Draft {
        from_name: "Luca".into(),
        from_email: "luca@example.org".into(),
        to: vec!["me@example.org".into()],
        subject: "Mockup v3 review".into(),
        body: "Two comments inside.".into(),
        files: vec![piuma_core::smtp::OutgoingFile {
            name: "mockup-v3.pdf".into(),
            mime: "application/pdf".into(),
            data: b"%PDF-1.4 review".to_vec(),
        }],
        ..Default::default()
    };
    let raw = String::from_utf8(piuma_core::smtp::build(&draft).unwrap().formatted()).unwrap();
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(&raw, "15-Oct-2026 09:15:00 +0200").await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let body = conn.full_body(&store, account, "INBOX", 1).await.unwrap();
    assert_eq!(body.text, "Two comments inside.");
    assert_eq!(body.attachments.len(), 1);
    let pdf = &body.attachments[0];
    assert_eq!((pdf.name.as_str(), pdf.size), ("mockup-v3.pdf", 15));
    // Cached with the body: the list comes back without the server.
    assert_eq!(
        store
            .lock()
            .unwrap()
            .attachments(account, "INBOX", 1)
            .unwrap(),
        body.attachments
    );
    let data = conn.attachment("INBOX", 1, pdf.part).await.unwrap();
    assert_eq!(data, b"%PDF-1.4 review");
    assert!(conn.attachment("INBOX", 1, 0).await.is_err());
}

#[tokio::test]
async fn sent_and_archive_are_found_and_synced() {
    let Some(cfg) = config("folders") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside
        .deliver(
            "From: Julia <julia@example.org>\r\nTo: Matteo <me@example.org>\r\nSubject: Hello\r\n\r\nHi",
            "14-Oct-2026 08:00:00 +0200",
        )
        .await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    // Sent exists once something was sent.
    conn.append_sent(
        b"From: me@example.org\r\nTo: Luca Bianchi <luca@example.org>, sara@example.org\r\nSubject: Quote\r\n\r\nOK",
    )
    .await
    .unwrap();
    conn.sync_folders(&store, account).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let sent = store
        .lock()
        .unwrap()
        .unified(Folder::Sent, None, 10)
        .unwrap();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].to, "Luca Bianchi, sara@example.org");
    // No Archive folder yet: nothing is created just to look.
    assert_eq!(
        store
            .lock()
            .unwrap()
            .folder_mailbox(account, Folder::Archive)
            .unwrap(),
        None
    );
    assert_eq!(conn.find_folder(FolderRole::Archive).await.unwrap(), None);

    let archive = conn
        .move_message(&store, account, "INBOX", 1, FolderRole::Archive)
        .await
        .unwrap();
    conn.sync_folders(&store, account).await.unwrap();
    let s = store.lock().unwrap();
    assert_eq!(s.count(Folder::Inbox).unwrap(), 0);
    assert_eq!(s.count(Folder::Archive).unwrap(), 1);
    assert_eq!(
        s.folder_mailbox(account, Folder::Archive).unwrap(),
        Some(archive)
    );
}

#[tokio::test]
async fn read_and_unread_reach_the_server() {
    let Some(cfg) = config("seen") else { return };
    let mut outside = Outside::open(&cfg).await;
    for subject in ["One", "Two"] {
        outside
            .deliver(
                &format!("From: Julia <julia@example.org>\r\nSubject: {subject}\r\n\r\nHi"),
                "14-Oct-2026 08:00:00 +0200",
            )
            .await;
    }
    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(
        store
            .lock()
            .unwrap()
            .unread_count(Folder::Inbox, None, Section::All)
            .unwrap(),
        2
    );

    conn.set_seen("INBOX", &[1, 2], true).await.unwrap();
    conn.set_seen("INBOX", &[2], false).await.unwrap();
    // A fresh look at the server sees what was set.
    let (fresh, fresh_account) = store_with_account();
    let mut other = Connection::open(&cfg).await.unwrap();
    other
        .sync_mailbox(&fresh, fresh_account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let s = fresh.lock().unwrap();
    assert_eq!(
        s.unread_count(Folder::Inbox, None, Section::All).unwrap(),
        1
    );
    assert!(
        s.message(fresh_account, "INBOX", 1)
            .unwrap()
            .unwrap()
            .flags
            .seen
    );
}

#[tokio::test]
async fn drafts_are_kept_replaced_and_read_back() {
    let Some(cfg) = config("drafts") else { return };
    let mut outside = Outside::open(&cfg).await;
    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();

    let draft = smtp::Draft {
        from_name: "Me".into(),
        from_email: "me@example.org".into(),
        to: vec!["Luca Bianchi <luca@studio.it>".into(), "half-typed".into()],
        bcc: vec!["sara@studio.it".into()],
        subject: "Mockups approved".into(),
        body: "We start Monday.".into(),
        in_reply_to: Some("<a@example.org>".into()),
        references: vec!["<a@example.org>".into()],
        files: vec![smtp::OutgoingFile {
            name: "plan.txt".into(),
            mime: "text/plain".into(),
            data: b"step one".to_vec(),
        }],
        ..Default::default()
    };
    let first = smtp::build_unsent(&draft).unwrap().formatted();
    // No Drafts folder yet: one is made.
    let folder = conn.append_draft(&first).await.unwrap();
    assert_eq!(folder, "Drafts");
    store
        .lock()
        .unwrap()
        .set_folder_role(account, Folder::Drafts, &folder)
        .unwrap();
    conn.sync_mailbox(&store, account, &folder, |_, _| {})
        .await
        .unwrap();
    assert_eq!(store.lock().unwrap().count(Folder::Drafts).unwrap(), 1);

    let back = piuma_core::imap::parse_draft(&conn.raw(&folder, 1).await.unwrap());
    assert_eq!(back.to, vec!["Luca Bianchi <luca@studio.it>".to_owned()]);
    assert_eq!(back.bcc, vec!["sara@studio.it".to_owned()]);
    assert_eq!(back.subject, "Mockups approved");
    assert_eq!(back.body.trim(), "We start Monday.");
    assert_eq!(back.in_reply_to.as_deref(), Some("<a@example.org>"));
    assert_eq!(back.files.len(), 1);
    assert_eq!(back.files[0].data, b"step one");

    // A new version goes in, the old one goes for good: not to Trash.
    let second = smtp::build_unsent(&smtp::Draft {
        to: Vec::new(),
        bcc: Vec::new(),
        ..draft
    })
    .unwrap()
    .formatted();
    conn.append_draft(&second).await.unwrap();
    conn.erase(&store, account, &folder, &[1]).await.unwrap();
    conn.sync_mailbox(&store, account, &folder, |_, _| {})
        .await
        .unwrap();
    assert_eq!(folder_count(&mut outside, "Drafts").await, 1);
    assert_eq!(store.lock().unwrap().count(Folder::Drafts).unwrap(), 1);
    assert!(conn.find_folder(FolderRole::Trash).await.unwrap().is_none());
}

#[tokio::test]
async fn previews_reach_past_long_style_sheets_and_cut_parts() {
    let Some(cfg) = config("previews") else {
        return;
    };
    let mut outside = Outside::open(&cfg).await;
    let styles =
        "p.MsoNormal{margin:0cm;font-size:11pt;font-family:Calibri,sans-serif;}\r\n".repeat(80);
    let styled = format!(
        "From: Studio <studio@example.org>\r\nTo: me@example.org\r\nSubject: Styled\r\nMIME-Version: 1.0\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<html><head><style>{styles}</style></head><body><p>Ciao Matteo, ecco il preventivo.</p></body></html>\r\n"
    );
    outside.deliver(&styled, "14-Oct-2026 08:00:00 +0200").await;
    let lines = "Q2lhbyBNYXR0ZW8sIGVjY28gbGEgZmF0dHVyYS4=\r\n".repeat(80);
    let cut = format!(
        "From: Shop <shop@example.org>\r\nTo: me@example.org\r\nSubject: Cut\r\nMIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=\"XX\"\r\n\r\n--XX\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n{lines}--XX--\r\n"
    );
    outside.deliver(&cut, "13-Oct-2026 08:00:00 +0200").await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let rows = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 10)
        .unwrap();
    assert_eq!(rows[0].preview, "Ciao Matteo, ecco il preventivo.");
    assert!(
        rows[1].preview.starts_with("Ciao Matteo, ecco la fattura."),
        "{}",
        rows[1].preview
    );
}

#[tokio::test]
async fn previews_come_from_the_html_past_a_long_text_part() {
    let Some(cfg) = config("html-previews") else {
        return;
    };
    let mut outside = Outside::open(&cfg).await;
    // The text part senders make from their HTML: every picture's
    // description in it, longer than the start fetched for the preview.
    let text = format!(
        "Focusrite Logo\r\n\r\nNew from Focusrite: Scarlett 4th Gen.\r\n{}",
        "Shop now https://focusrite.example/scarlett?utm=newsletter\r\n".repeat(60)
    );
    let html = "<html><head><style>p{margin:0}</style></head><body>\r\n<div style=3D\"display:none\">Hidden=\r\n preheader</div>\r\n<a href=3D\"https://focusrite.example\"><img src=3D\"https://focusrite.example/logo.png\" alt=3D\"Focusrite Logo\"></a>\r\n<p>New from Focusrite: Scarlett 4th Gen. Caff=C3=A8 included.</p></body></html>\r\n";
    let message = format!(
        "From: Focusrite <news@focusrite.example>\r\nTo: me@example.org\r\nSubject: Scarlett\r\nMIME-Version: 1.0\r\nContent-Type: multipart/related; boundary=\"R\"\r\n\r\n--R\r\nContent-Type: multipart/alternative; boundary=\"A\"\r\n\r\n--A\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{text}--A\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n{html}--A--\r\n--R--\r\n"
    );
    outside
        .deliver(&message, "14-Oct-2026 08:00:00 +0200")
        .await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let rows = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 10)
        .unwrap();
    assert_eq!(
        rows[0].preview,
        "New from Focusrite: Scarlett 4th Gen. Caffè included."
    );
}

#[tokio::test]
async fn a_closed_port_counts_as_offline_and_a_bad_password_does_not() {
    let Some(mut cfg) = config("reach") else {
        return;
    };
    let mut wrong = cfg.clone();
    wrong.password = "nope".into();
    assert!(!Connection::open(&wrong).await.err().unwrap().is_offline());
    cfg.port = 1;
    assert!(Connection::open(&cfg).await.err().unwrap().is_offline());
}

#[tokio::test]
async fn own_folders_are_listed_and_take_moved_mail() {
    let Some(cfg) = config("ownfolders") else {
        return;
    };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside.deliver(REPLY, "15-Oct-2026 09:00:00 +0200").await;
    let sep = outside
        .0
        .list(Some(""), Some("INBOX"))
        .await
        .unwrap()
        .try_collect::<Vec<_>>()
        .await
        .unwrap()[0]
        .delimiter()
        .unwrap_or("/")
        .to_owned();
    let acme = format!("Clients{sep}Acme");
    for name in ["Clients", acme.as_str(), "Junk"] {
        outside.0.create(name).await.unwrap();
    }

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    conn.sync_folders(&store, account).await.unwrap();
    let folders: Vec<_> = store
        .lock()
        .unwrap()
        .account_folders(account)
        .unwrap()
        .into_iter()
        .map(|f| (f.name, f.depth, f.unread))
        .collect();
    assert_eq!(
        folders,
        [("Clients".to_owned(), 0, 0), ("Acme".to_owned(), 1, 0)]
    );

    conn.move_to(&store, account, "INBOX", &[1], &acme)
        .await
        .unwrap();
    conn.sync_folders(&store, account).await.unwrap();
    let acme_now = &store.lock().unwrap().account_folders(account).unwrap()[1];
    assert_eq!((acme_now.unread, acme_now.total), (1, 1));

    // A folder made here, with a name IMAP writes in modified UTF-7.
    let made = conn
        .create_folder(&store, account, "Città 2026")
        .await
        .unwrap();
    assert!(made.ends_with("Citt&AOA- 2026"));
    assert_eq!(
        store.lock().unwrap().account_folders(account).unwrap()[2].name,
        "Città 2026"
    );
    conn.sync_folders(&store, account).await.unwrap();
    assert!(store
        .lock()
        .unwrap()
        .account_folders(account)
        .unwrap()
        .iter()
        .any(|f| f.name == "Città 2026" && f.mailbox == made));
    conn.sync_mailbox(&store, account, &acme, |_, _| {})
        .await
        .unwrap();
    let s = store.lock().unwrap();
    assert_eq!(s.count(Folder::Inbox).unwrap(), 1);
    assert_eq!(s.mailbox_count(account, &acme).unwrap(), 1);
    let page = s.mailbox_page(account, &acme, 0, 10).unwrap();
    assert_eq!(page[0].latest.subject, "New website quote");
}

const ONE_CLICK_NEWSLETTER: &str = "From: Forma <issue@forma.example>
To: me@example.org
Subject: Forma No. 112: the quiet interface
Date: Sat, 17 Oct 2026 07:02:00 +0200
List-Unsubscribe: <mailto:leave@forma.example>, <https://forma.example/u?id=7>
List-Unsubscribe-Post: List-Unsubscribe=One-Click
MIME-Version: 1.0
Content-Type: text/html; charset=utf-8

<html><body><h1>The quiet interface</h1><p>Software that waits for you, and says only what you need to know today.</p></body></html>
";

const DISCUSSION_LIST: &str = "From: Ada <ada@example.org>
To: dev@lists.example
Subject: Re: release plan
Date: Sat, 17 Oct 2026 08:00:00 +0200
List-Id: <dev.lists.example>
List-Post: <mailto:dev@lists.example>
List-Unsubscribe: <https://lists.example/leave>
Content-Type: text/plain; charset=utf-8

Friday works for me.
";

fn subjects(store: &Mutex<Store>, folder: Folder) -> Vec<String> {
    store
        .lock()
        .unwrap()
        .unified(folder, None, 10)
        .unwrap()
        .into_iter()
        .map(|m| m.subject)
        .collect()
}

#[tokio::test]
async fn newsletters_leave_the_inbox_and_come_down_whole() {
    let Some(cfg) = config("newsletters") else {
        return;
    };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside
        .deliver(ONE_CLICK_NEWSLETTER, "17-Oct-2026 07:02:00 +0200")
        .await;
    outside
        .deliver(DISCUSSION_LIST, "17-Oct-2026 08:00:00 +0200")
        .await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    // A discussion list is people writing: it stays.
    assert_eq!(
        subjects(&store, Folder::Inbox),
        ["Re: release plan", "New website quote"]
    );
    assert_eq!(
        subjects(&store, Folder::Newsletters),
        ["Forma No. 112: the quiet interface"]
    );
    let s = store.lock().unwrap();
    let list = s.list_info(account, "INBOX", 2).unwrap();
    assert!(list.newsletter && list.one_click);
    assert_eq!(list.unsubscribe, "https://forma.example/u?id=7");
    // Already here to read offline, with its reading time.
    assert!(s.full_body(account, "INBOX", 2).unwrap().is_some());
    let page = s.newsletters_page(None, 0, 10).unwrap();
    assert_eq!(page.len(), 1);
    assert_eq!(page[0].1, 1);
    // A sender moved to the inbox stays there, new mail included.
    s.set_sender_zone("Issue@forma.example", Folder::Inbox)
        .unwrap();
    assert_eq!(s.count(Folder::Newsletters).unwrap(), 0);
    assert_eq!(s.count(Folder::Inbox).unwrap(), 3);
}

const BILL: &str = "From: EnergiaVerde <bollette@energiaverde.example>
To: me@example.org
Subject: La tua bolletta di ottobre
Message-ID: <bill-10@energiaverde.example>
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=\"m1\"

--m1
Content-Type: text/html; charset=utf-8

<html><head><script type=\"application/ld+json\">{\"@context\":\"http://schema.org\",
\"@type\":\"Invoice\",\"description\":\"Electricity bill · October\",
\"provider\":{\"@type\":\"Organization\",\"name\":\"EnergiaVerde\"},
\"totalPaymentDue\":{\"@type\":\"PriceSpecification\",\"price\":\"64.20\",\"priceCurrency\":\"EUR\"},
\"paymentDueDate\":\"2026-10-30\"}</script></head>
<body><p>La bolletta di ottobre: 64,20 euro.</p></body></html>
--m1
Content-Type: application/pdf; name=\"bolletta.pdf\"
Content-Disposition: attachment; filename=\"bolletta.pdf\"
Content-Transfer-Encoding: base64

JVBERi0xLjQK
--m1--
";

/// An IMAP date `days` days ago, for mail recent enough to make a card.
fn days_ago(days: i64) -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    // Civil date from a day number (Howard Hinnant's algorithm).
    let z = (now / 86_400 - days) + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    let name = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ][month as usize - 1];
    format!("{day:02}-{name}-{year} 09:00:00 +0000")
}

#[tokio::test]
async fn a_bill_makes_its_vault_card_with_its_pdf() {
    let Some(cfg) = config("vault") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, &days_ago(2)).await;
    outside.deliver(BILL, &days_ago(1)).await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let s = store.lock().unwrap();
    let cards = s.vault_cards(None, 0).unwrap();
    assert_eq!(cards.len(), 1);
    let (m, _, card) = &cards[0];
    assert_eq!(m.subject, "La tua bolletta di ottobre");
    assert_eq!(card.kind, piuma_core::vault::Kind::Bill);
    assert_eq!(card.title, "Electricity bill · October");
    assert_eq!((card.amount, card.currency.as_str()), (Some(6420), "EUR"));
    assert_eq!(card.day, "2026-10-30");
    assert_eq!(card.file_name, "bolletta.pdf");
    // The plain mail is kept whole too, by the Inbox read-ahead, but
    // makes no card.
    assert!(s.full_body(account, "INBOX", 1).unwrap().is_some());
}

#[tokio::test]
async fn mail_cached_before_newsletters_is_filed_again() {
    let Some(cfg) = config("refile") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside
        .deliver(ONE_CLICK_NEWSLETTER, "17-Oct-2026 07:02:00 +0200")
        .await;

    let dir = std::env::temp_dir().join(format!("piuma-refile-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("mail.db");
    let _ = std::fs::remove_file(&path);
    let (memory, _) = store_with_account();
    let account = Store::open(&path)
        .unwrap()
        .add_account(&memory.lock().unwrap().accounts().unwrap()[0])
        .unwrap();
    let store = Mutex::new(Store::open(&path).unwrap());
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    // As an older version left it: everything in the inbox, unread headers.
    rusqlite::Connection::open(&path)
        .unwrap()
        .execute_batch(
            "UPDATE message SET folder = 'inbox', newsletter = 0, list_checked = 0;
             DELETE FROM message_body;",
        )
        .unwrap();
    assert_eq!(subjects(&store, Folder::Newsletters), Vec::<String>::new());

    let report = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(report.filed, 1);
    assert!(report.changed());
    assert_eq!(subjects(&store, Folder::Inbox), ["New website quote"]);
    assert_eq!(
        subjects(&store, Folder::Newsletters),
        ["Forma No. 112: the quiet interface"]
    );
    // Asked once only.
    let again = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(again.filed, 0);
    std::fs::remove_dir_all(&dir).ok();
}

const FILES: &str = "From: Dad <dad@example.org>
To: me@example.org
Subject: Photos from the lake
Message-ID: <lake-1@example.org>
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=\"o1\"

--o1
Content-Type: multipart/related; boundary=\"r1\"

--r1
Content-Type: text/html; charset=utf-8

<p>Here they are <img src=\"cid:logo@x\"></p>
--r1
Content-Type: image/png; name=\"logo.png\"
Content-ID: <logo@x>
Content-Transfer-Encoding: base64

iVBORw0KGgo=
--r1--
--o1
Content-Type: text/plain; charset=utf-8; name=\"notes.txt\"
Content-Disposition: attachment; filename=\"notes.txt\"
Content-Transfer-Encoding: quoted-printable

Caf=C3=A8 at 9
--o1
Content-Type: image/jpeg; name=\"=?utf-8?Q?Lago_d=27Iseo.jpg?=\"
Content-Disposition: attachment; filename*=utf-8''Lago%20d%27Iseo.jpg
Content-Transfer-Encoding: base64

/9j/4AAQ
--o1
Content-Type: message/rfc822
Content-Disposition: attachment

From: Mum <mum@example.org>
Subject: =?utf-8?Q?Ricetta_t=C3=A0?=

Flour and water.
--o1
Content-Type: application/pkcs7-signature; name=\"smime.p7s\"
Content-Transfer-Encoding: base64

AAAA
--o1--
";

#[tokio::test]
async fn the_newest_inbox_mail_is_kept_whole() {
    let Some(cfg) = config("readahead") else {
        return;
    };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, &days_ago(2)).await;
    outside.deliver(FILES, &days_ago(1)).await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    // Opening either shows its text at once, without asking the server.
    let s = store.lock().unwrap();
    assert!(s.full_body(account, "INBOX", 1).unwrap().is_some());
    assert!(s.full_body(account, "INBOX", 2).unwrap().is_some());
}

#[tokio::test]
async fn files_are_listed_from_the_outline() {
    let Some(cfg) = config("files") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, &days_ago(2)).await;
    outside.deliver(FILES, &days_ago(1)).await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    let report = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(report.listed, 1);
    let files = store.lock().unwrap().files(None, 100).unwrap();
    // The Inbox read-ahead then kept it whole, and its own list took over:
    // the same files.
    let listed: Vec<(&str, &str)> = files
        .iter()
        .map(|(_, _, a)| (a.name.as_str(), a.mime.as_str()))
        .collect();
    assert_eq!(
        listed,
        [
            ("notes.txt", "text/plain"),
            ("Lago d'Iseo.jpg", "image/jpeg"),
            ("Ricetta tà.eml", "message/rfc822"),
        ]
    );
    assert_eq!(files[0].0.subject, "Photos from the lake");
    assert!(store
        .lock()
        .unwrap()
        .full_body(account, "INBOX", 2)
        .unwrap()
        .is_some());
    // A file listed this way comes alone, decoded.
    assert_eq!(
        conn.section("INBOX", 2, "2", Some("quoted-printable"))
            .await
            .unwrap(),
        "Cafè at 9".as_bytes()
    );
    assert_eq!(
        conn.section("INBOX", 2, "3", Some("base64")).await.unwrap(),
        [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
    );
    // The next sync asks for nothing again.
    let report = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(report.listed, 0);
}

#[tokio::test]
async fn snoozed_mail_waits_on_the_server_and_comes_back_on_time() {
    let Some(cfg) = config("snooze") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside.store(1, "+FLAGS (\\Seen)").await;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let later = now + 3600;
    store
        .lock()
        .unwrap()
        .snooze(account, "INBOX", &[1], later)
        .unwrap();
    conn.snooze(&store, account, "INBOX", &[1], later)
        .await
        .unwrap();
    assert_eq!(folder_count(&mut outside, "INBOX").await, 0);
    assert_eq!(folder_count(&mut outside, "Snoozed").await, 1);
    let mine = store.lock().unwrap().snoozed(None).unwrap();
    assert_eq!(mine[0].1, Some(later));
    conn.logout().await.unwrap();

    // Another device sees it snoozed, and until when.
    let (other, other_account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_folders(&other, other_account).await.unwrap();
    let snoozed = other.lock().unwrap().snoozed(None).unwrap();
    assert_eq!(snoozed.len(), 1);
    assert_eq!(snoozed[0].0.subject, "New website quote");
    assert_eq!(snoozed[0].1, Some(later));
    assert_eq!(
        other.lock().unwrap().next_wake(other_account).unwrap(),
        Some(later)
    );

    // Snoozed again from there, it stays put with the new time.
    let uid = snoozed[0].0.uid;
    other
        .lock()
        .unwrap()
        .snooze(other_account, "Snoozed", &[uid], later + 60)
        .unwrap();
    conn.snooze(&other, other_account, "Snoozed", &[uid], later + 60)
        .await
        .unwrap();
    conn.sync_folders(&other, other_account).await.unwrap();
    let snoozed = other.lock().unwrap().snoozed(None).unwrap();
    assert_eq!((snoozed[0].0.uid, snoozed[0].1), (uid, Some(later + 60)));

    // Its time comes: the watcher brings it back, unread, without the
    // keyword.
    other
        .lock()
        .unwrap()
        .set_snooze_times(other_account, "Snoozed", &[(uid, Some(now - 1))])
        .unwrap();
    conn.logout().await.unwrap();
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let task = tokio::spawn(watch(
        cfg.clone(),
        other.clone(),
        other_account,
        "INBOX".into(),
        move |e| {
            tx.send(e).ok();
        },
    ));
    let deadline = Instant::now() + Duration::from_secs(20);
    while subjects(&other, Folder::Inbox).is_empty() {
        assert!(
            Instant::now() < deadline,
            "the snoozed mail never came back"
        );
        tokio::time::timeout(Duration::from_secs(5), rx.recv())
            .await
            .ok();
    }
    task.abort();
    assert!(other.lock().unwrap().snoozed(None).unwrap().is_empty());
    assert_eq!(folder_count(&mut outside, "Snoozed").await, 0);
    assert_eq!(folder_count(&mut outside, "INBOX").await, 1);
    let fetched: Vec<_> = outside
        .0
        .uid_fetch("1:*", "FLAGS")
        .await
        .unwrap()
        .try_collect()
        .await
        .unwrap();
    assert!(!fetched[0].flags().any(|f| matches!(
        f,
        async_imap::types::Flag::Seen | async_imap::types::Flag::Custom(_)
    )));
}

const PEC_ACCEPTED: &str = "From: Per conto di: me@example.org <posta-certificata@pec.example.it>
To: me@example.org
Subject: ACCETTAZIONE: Lease renewal 2027
Date: Mon, 19 Oct 2026 09:12:00 +0200
X-Ricevuta: accettazione
X-Riferimento-Message-ID: <lease-2027@example.org>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Ricevuta di accettazione

Il giorno 19/10/2026 alle ore 09:12:00 (+0200) il messaggio
\"Lease renewal 2027\" proveniente da \"me@example.org\"
ed indirizzato a:
studio.rossi@pec.it (\"posta certificata\")
Il messaggio è stato accettato dal sistema ed inoltrato.
";

const PEC_DELIVERED: &str =
    "From: Per conto di: studio.rossi@pec.it <posta-certificata@pec.example.it>
To: me@example.org
Subject: CONSEGNA: Lease renewal 2027
Date: Mon, 19 Oct 2026 09:12:04 +0200
X-Ricevuta: avvenuta-consegna
X-Riferimento-Message-ID: <lease-2027@example.org>
MIME-Version: 1.0
Content-Type: text/plain; charset=utf-8

Ricevuta di avvenuta consegna

Il giorno 19/10/2026 alle ore 09:12:04 (+0200) il messaggio
\"Lease renewal 2027\" proveniente da \"me@example.org\"
ed indirizzato a \"studio.rossi@pec.it\"
è stato consegnato nella casella di destinazione.
";

#[tokio::test]
async fn pec_receipts_leave_the_inbox_and_gather_per_message() {
    let Some(cfg) = config("pec") else {
        return;
    };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside
        .deliver(PEC_ACCEPTED, "19-Oct-2026 09:12:00 +0200")
        .await;
    outside
        .deliver(PEC_DELIVERED, "19-Oct-2026 09:12:04 +0200")
        .await;

    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    let report = conn
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(report.added, 3);
    assert_eq!(subjects(&store, Folder::Inbox), ["New website quote"]);
    let sent = store.lock().unwrap().pec_sent(None).unwrap();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].subject, "Lease renewal 2027");
    assert_eq!(sent[0].refers, "<lease-2027@example.org>");
    assert_eq!(sent[0].recipients, ["studio.rossi@pec.it"]);
    assert_eq!(sent[0].stage, piuma_core::pec::Stage::Delivered);
    assert_eq!(sent[0].proofs, [("INBOX".to_owned(), 3)]);
    // The receipt is the provider's signed message, saved whole.
    let raw = conn.raw("INBOX", 3).await.unwrap();
    assert!(String::from_utf8_lossy(&raw).contains("X-Ricevuta: avvenuta-consegna"));
}

#[tokio::test]
async fn labels_are_keywords_on_the_server() {
    let Some(cfg) = config("labels") else { return };
    let mut outside = Outside::open(&cfg).await;
    outside.deliver(PLAIN, "12-Oct-2026 09:41:00 +0200").await;
    outside.deliver(REPLY, "15-Oct-2026 09:00:00 +0200").await;
    let (store, account) = store_with_account();
    let mut conn = Connection::open(&cfg).await.unwrap();
    conn.sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    conn.logout().await.unwrap();

    let worksite = {
        let s = store.lock().unwrap();
        let worksite = s.add_label("Worksite", "amber").unwrap();
        s.label_message(account, "INBOX", 1, &worksite.keyword, true)
            .unwrap();
        worksite
    };
    // Another app puts a word of its own on the second one.
    let _: Vec<_> = outside
        .0
        .uid_store("2", "+FLAGS.SILENT (invoices $Forwarded)")
        .await
        .unwrap()
        .try_collect()
        .await
        .unwrap();

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let task = tokio::spawn(watch(
        cfg.clone(),
        store.clone(),
        account,
        "INBOX".into(),
        move |e| {
            tx.send(e).ok();
        },
    ));
    next_sync(&mut rx).await;
    task.abort();

    {
        let s = store.lock().unwrap();
        assert!(s.pending_changes(account).unwrap().is_empty());
        assert!(!s.labels_local(account).unwrap());
        assert_eq!(s.message_labels(account, "INBOX", 1).unwrap(), ["worksite"]);
        assert_eq!(s.message_labels(account, "INBOX", 2).unwrap(), ["invoices"]);
    }
    let fetched: Vec<_> = outside
        .0
        .uid_fetch("1", "FLAGS")
        .await
        .unwrap()
        .try_collect()
        .await
        .unwrap();
    assert!(fetched[0]
        .flags()
        .any(|f| matches!(f, async_imap::types::Flag::Custom(k) if k == "worksite")));

    // Taken off here, then on the server.
    store.lock().unwrap().remove_label(worksite.id).unwrap();
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let task = tokio::spawn(watch(
        cfg.clone(),
        store.clone(),
        account,
        "INBOX".into(),
        move |e| {
            tx.send(e).ok();
        },
    ));
    next_sync(&mut rx).await;
    task.abort();
    let fetched: Vec<_> = outside
        .0
        .uid_fetch("1", "FLAGS")
        .await
        .unwrap()
        .try_collect()
        .await
        .unwrap();
    assert!(!fetched[0]
        .flags()
        .any(|f| matches!(f, async_imap::types::Flag::Custom(k) if k == "worksite")));
    assert!(store
        .lock()
        .unwrap()
        .message_labels(account, "INBOX", 1)
        .unwrap()
        .is_empty());
}
