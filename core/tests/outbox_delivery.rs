//! The outbox sends every message once, or keeps it, visibly unsent:
//! never lost, never twice. Senders that race, crashes, lost answers,
//! certificate errors and a full disk, against a scripted courier and a
//! small SMTP server inside the test.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use piuma_core::outbox::{self, Courier, Outcome, Outgoing, State};
use piuma_core::remote::AccountCourier;
use piuma_core::smtp::{ready, send, Draft, Filing, Ready, SendError, SmtpConfig};
use piuma_core::{Account, AccountId, AccountKind, Security, Server, Store};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;

fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
}

fn account(id: AccountId, smtp_port: u16, imap_port: u16, security: Security) -> Account {
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
                security,
            },
            username: "me".into(),
        },
    }
}

fn closed_port() -> u16 {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    listener.local_addr().unwrap().port()
}

fn draft(subject: &str) -> Draft {
    Draft {
        from_name: "Matteo".into(),
        from_email: "me@example.org".into(),
        to: vec!["Luca <luca@example.org>".into()],
        subject: subject.into(),
        body: "We start Monday.".into(),
        ..Draft::default()
    }
}

fn queue(store: &Mutex<Store>, id: AccountId, subject: &str, send_at: Option<i64>) -> i64 {
    let draft = draft(subject);
    let out = Outgoing {
        account: id,
        ready: ready(&draft).unwrap(),
        draft,
        saved: None,
        send_at,
        undo: false,
        redirect: false,
    };
    store.lock().unwrap().queue_outgoing(&out, now()).unwrap()
}

fn store() -> (Mutex<Store>, Account) {
    let store = Store::open_in_memory().unwrap();
    let id = store
        .add_account(&account(AccountId(0), 25, 143, Security::None))
        .unwrap();
    (Mutex::new(store), account(id, 25, 143, Security::None))
}

fn state(store: &Mutex<Store>, id: i64) -> Option<String> {
    store.lock().unwrap().outgoing_state(id).unwrap()
}

/// A courier that does what the test says, and counts.
#[derive(Clone, Default)]
struct Script {
    /// What each send answers, in order; Ok once they run out.
    sends: Arc<Mutex<VecDeque<Result<(), SendError>>>>,
    /// What each filing answers, in order; filed once they run out.
    files: Arc<Mutex<VecDeque<Filing>>>,
    /// What a check of a send that may have gone answers.
    was_sent: Option<bool>,
    /// Messages handed to the server.
    sent: Arc<Mutex<Vec<Ready>>>,
    /// Filings asked, and whether each was a retry.
    filed: Arc<Mutex<Vec<bool>>>,
    /// Holds each send until it is notified, when set.
    gate: Option<Arc<tokio::sync::Notify>>,
    /// Told when a send starts.
    started: Option<Arc<tokio::sync::Notify>>,
    /// How long each send takes.
    slow: Duration,
}

impl Courier for Script {
    async fn send(&mut self, ready: &Ready) -> Result<(), SendError> {
        if let Some(started) = &self.started {
            started.notify_one();
        }
        if let Some(gate) = &self.gate {
            gate.notified().await;
        }
        tokio::time::sleep(self.slow).await;
        let answer = self.sends.lock().unwrap().pop_front().unwrap_or(Ok(()));
        if answer.is_ok() {
            self.sent.lock().unwrap().push(ready.clone());
        }
        answer
    }

    async fn file(&mut self, _ready: &Ready, retry: bool) -> Filing {
        self.filed.lock().unwrap().push(retry);
        self.files
            .lock()
            .unwrap()
            .pop_front()
            .unwrap_or(Filing::Ours("Sent".into()))
    }

    async fn was_sent(&mut self, _ready: &Ready) -> Option<bool> {
        self.was_sent
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn two_senders_never_send_one_message_twice() {
    let dir = std::env::temp_dir().join(format!(
        "piuma-outbox-race-{}-{}",
        std::process::id(),
        now()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("piuma.db");
    // Two connections to one database, as two processes (the app and a
    // second instance, or the background service) would have.
    let one = Arc::new(Mutex::new(Store::open(&path).unwrap()));
    let two = Arc::new(Mutex::new(Store::open(&path).unwrap()));
    let id = one
        .lock()
        .unwrap()
        .add_account(&account(AccountId(0), 25, 143, Security::None))
        .unwrap();
    let account = account(id, 25, 143, Security::None);
    let ids: Vec<i64> = (0..5)
        .map(|i| queue(&one, id, &format!("Note {i}"), None))
        .collect();

    let script = Script {
        slow: Duration::from_millis(20),
        ..Script::default()
    };
    let mut tasks = Vec::new();
    for (store, me) in [
        (one.clone(), "one"),
        (two.clone(), "two"),
        (one.clone(), "three"),
    ] {
        let (account, mut courier) = (account.clone(), script.clone());
        tasks.push(tokio::spawn(async move {
            outbox::send(&store, &account, &mut courier, me)
                .await
                .unwrap()
        }));
    }
    let mut reported = Vec::new();
    for t in tasks {
        reported.extend(t.await.unwrap().into_iter().map(|s| s.id));
    }
    reported.sort_unstable();
    assert_eq!(reported, ids, "each message reported sent once");
    let sent = script.sent.lock().unwrap();
    assert_eq!(sent.len(), 5, "each message handed to the server once");
    let mut ids_sent: Vec<_> = sent.iter().map(|r| r.message_id.clone()).collect();
    ids_sent.sort();
    ids_sent.dedup();
    assert_eq!(ids_sent.len(), 5, "five different messages");
    assert!(one.lock().unwrap().outbox(None).unwrap().is_empty());
    drop(sent);
    drop((one, two));
    std::fs::remove_dir_all(&dir).ok();
}

#[tokio::test]
async fn a_send_cut_by_a_crash_is_never_sent_again_blindly() {
    let (store, account) = store();
    let id = queue(&store, account.id, "Plans", None);
    // A sender claimed it an hour ago and died before it could say how
    // it went: the server may have it.
    assert!(store
        .lock()
        .unwrap()
        .claim_outgoing(id, "crashed", now() - 3_600)
        .unwrap());

    let mut courier = Script::default();
    let sent = outbox::send(&store, &account, &mut courier, "me")
        .await
        .unwrap();
    assert!(sent.is_empty());
    assert!(courier.sent.lock().unwrap().is_empty(), "not sent again");
    assert_eq!(state(&store, id).as_deref(), Some("unknown"));
    let listed = store.lock().unwrap().outbox(None).unwrap();
    assert_eq!(listed[0].state, State::Unknown);
    // Nor on the next look.
    outbox::send(&store, &account, &mut courier, "me")
        .await
        .unwrap();
    assert!(courier.sent.lock().unwrap().is_empty());

    // A server that can tell (JMAP) settles it either way.
    let mut tells_sent = Script {
        was_sent: Some(true),
        ..Script::default()
    };
    outbox::send(&store, &account, &mut tells_sent, "me")
        .await
        .unwrap();
    assert!(tells_sent.sent.lock().unwrap().is_empty());
    assert_eq!(state(&store, id), None, "it went: it leaves the outbox");

    // The server says it never went, and its sender has been silent for
    // two days: it goes now, once.
    let id = queue(&store, account.id, "Plans again", None);
    assert!(store
        .lock()
        .unwrap()
        .claim_outgoing(id, "crashed", now() - 2 * 86_400)
        .unwrap());
    let mut tells_not_sent = Script {
        was_sent: Some(false),
        ..Script::default()
    };
    let sent = outbox::send(&store, &account, &mut tells_not_sent, "me")
        .await
        .unwrap();
    assert_eq!(sent.len(), 1, "it never went: it goes now, once");
    assert_eq!(tells_not_sent.sent.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn a_sender_silent_for_an_hour_may_still_finish_so_nothing_resends() {
    let (store, account) = store();
    let id = queue(&store, account.id, "Big file", None);
    // A sender claimed it an hour ago and said nothing since (a computer
    // asleep mid-send): it may wake up and finish.
    assert!(store
        .lock()
        .unwrap()
        .claim_outgoing(id, "slow", now() - 3_600)
        .unwrap());
    // Another sender, on a server that says "not sent yet".
    let mut other = Script {
        was_sent: Some(false),
        ..Script::default()
    };
    outbox::send(&store, &account, &mut other, "other")
        .await
        .unwrap();
    assert!(
        other.sent.lock().unwrap().is_empty(),
        "not sent a second time"
    );
    assert_eq!(state(&store, id).as_deref(), Some("unknown"));
    // Its sender is still known, so it can settle the row.
    assert_eq!(
        store.lock().unwrap().outgoing_claim(id).unwrap().unwrap().0,
        "slow"
    );
    // The slow sender finishes: the row goes, nothing is stranded.
    store
        .lock()
        .unwrap()
        .sent_outgoing(id, "slow", true)
        .unwrap();
    assert_eq!(state(&store, id), None);
}

#[tokio::test]
async fn a_slow_send_renews_its_claim_so_no_one_takes_it() {
    let (store, account) = store();
    let store = Arc::new(store);
    let id = queue(&store, account.id, "Big file", None);
    let gate = Arc::new(tokio::sync::Notify::new());
    let started = Arc::new(tokio::sync::Notify::new());
    let slow = Script {
        gate: Some(gate.clone()),
        started: Some(started.clone()),
        ..Script::default()
    };
    let sending = {
        let (store, mut slow) = (store.clone(), slow.clone());
        tokio::spawn(async move {
            outbox::send_one_beating(&store, id, &mut slow, "slow", Duration::from_millis(50)).await
        })
    };
    started.notified().await;
    // Minutes pass in the send (the claim made long ago)...
    store
        .lock()
        .unwrap()
        .execute_for_tests(&format!(
            "UPDATE outbox SET claimed_at = {} WHERE id = {id}",
            now() - 3_600
        ))
        .unwrap();
    // ...but the sender renews it while it works.
    tokio::time::sleep(Duration::from_millis(300)).await;
    let (_, at) = store.lock().unwrap().outgoing_claim(id).unwrap().unwrap();
    assert!(at >= now() - 5, "renewed");
    let mut other = Script {
        was_sent: Some(false),
        ..Script::default()
    };
    outbox::send(&store, &account, &mut other, "other")
        .await
        .unwrap();
    assert!(other.sent.lock().unwrap().is_empty());
    assert_eq!(state(&store, id).as_deref(), Some("sending"));
    gate.notify_one();
    assert!(matches!(sending.await.unwrap().unwrap(), Outcome::Sent(_)));
    assert_eq!(slow.sent.lock().unwrap().len(), 1);
    assert_eq!(state(&store, id), None);
}

#[tokio::test]
async fn a_message_that_went_is_never_left_to_go_again() {
    let (store, account) = store();
    let id = queue(&store, account.id, "Plans", None);
    assert!(store
        .lock()
        .unwrap()
        .claim_outgoing(id, "slow", now() - 2 * 86_400)
        .unwrap());
    // Silent for two days: taken for abandoned, and queued again...
    let mut other = Script {
        was_sent: Some(false),
        gate: Some(Arc::new(tokio::sync::Notify::new())),
        ..Script::default()
    };
    store
        .lock()
        .unwrap()
        .expire_claims(account.id, "other", now() - 600)
        .unwrap();
    store
        .lock()
        .unwrap()
        .settle_unknown(id, false, now() - 86_400)
        .unwrap();
    assert_eq!(state(&store, id).as_deref(), Some("queued"));
    // ...when the old sender comes back and says it went: it must not go
    // again.
    store
        .lock()
        .unwrap()
        .sent_outgoing(id, "slow", true)
        .unwrap();
    assert_eq!(state(&store, id), None);
    assert!(matches!(
        outbox::send_one(&store, id, &mut other, "other")
            .await
            .unwrap(),
        Outcome::Gone
    ));
}

#[tokio::test]
async fn a_fresh_claim_of_another_sender_is_left_alone() {
    let (store, account) = store();
    let id = queue(&store, account.id, "Plans", None);
    // Another process is sending it right now.
    assert!(store
        .lock()
        .unwrap()
        .claim_outgoing(id, "other", now())
        .unwrap());
    let mut courier = Script::default();
    outbox::send(&store, &account, &mut courier, "me")
        .await
        .unwrap();
    assert!(courier.sent.lock().unwrap().is_empty());
    assert_eq!(state(&store, id).as_deref(), Some("sending"));
    let mut courier = Script::default();
    assert!(matches!(
        outbox::send_one(&store, id, &mut courier, "me")
            .await
            .unwrap(),
        Outcome::Busy
    ));
}

#[tokio::test]
async fn a_full_disk_after_sending_does_not_send_again() {
    let (store, account) = store();
    let id = queue(&store, account.id, "Plans", None);
    // The disk fills up while the message goes: nothing after the claim
    // can be written.
    store
        .lock()
        .unwrap()
        .execute_for_tests(
            "CREATE TEMP TRIGGER full_delete BEFORE DELETE ON outbox
               BEGIN SELECT RAISE(ABORT, 'database or disk is full'); END;
             CREATE TEMP TRIGGER full_update BEFORE UPDATE ON outbox WHEN NEW.state <> 'sending'
               BEGIN SELECT RAISE(ABORT, 'database or disk is full'); END;",
        )
        .unwrap();
    let mut courier = Script::default();
    let sent = outbox::send(&store, &account, &mut courier, "me")
        .await
        .unwrap();
    assert_eq!(sent.len(), 1, "the server took it");
    assert_eq!(courier.sent.lock().unwrap().len(), 1);
    // The row could not be settled: it stays claimed, never queued.
    assert_eq!(state(&store, id).as_deref(), Some("sending"));
    for _ in 0..3 {
        outbox::send(&store, &account, &mut courier, "me")
            .await
            .unwrap();
    }
    assert_eq!(courier.sent.lock().unwrap().len(), 1, "sent once");

    // Space again, and the app restarted later (another sender): the
    // message shows as "may have been sent", never goes again.
    store
        .lock()
        .unwrap()
        .execute_for_tests("DROP TRIGGER full_delete; DROP TRIGGER full_update;")
        .unwrap();
    store
        .lock()
        .unwrap()
        .expire_claims(account.id, "after-restart", now() + 1)
        .unwrap();
    outbox::send(&store, &account, &mut courier, "after-restart")
        .await
        .unwrap();
    assert_eq!(courier.sent.lock().unwrap().len(), 1);
    assert_eq!(state(&store, id).as_deref(), Some("unknown"));
}

#[tokio::test]
async fn a_sent_copy_that_could_not_be_filed_is_kept_and_filed_later() {
    let (store, account) = store();
    let id = queue(&store, account.id, "Plans", None);
    let mut courier = Script::default();
    courier
        .files
        .lock()
        .unwrap()
        .push_back(Filing::Missing("APPEND failed".into()));
    let sent = outbox::send(&store, &account, &mut courier, "me")
        .await
        .unwrap();
    assert_eq!(sent.len(), 1);
    assert_eq!(sent[0].filed, Filing::Missing("APPEND failed".into()));
    // Sent: out of the list, but kept, to file its copy.
    assert!(store.lock().unwrap().outbox(None).unwrap().is_empty());
    assert_eq!(state(&store, id).as_deref(), Some("unfiled"));
    assert!(store.lock().unwrap().outgoing(id).unwrap().is_some());
    // It can't be taken back: it went.
    assert!(store.lock().unwrap().take_outgoing(id).unwrap().is_none());

    // The next look files it, checking first, and never sends it again.
    let sent = outbox::send(&store, &account, &mut courier, "me")
        .await
        .unwrap();
    assert!(sent.is_empty());
    assert_eq!(*courier.filed.lock().unwrap(), [false, true]);
    assert_eq!(courier.sent.lock().unwrap().len(), 1);
    assert_eq!(state(&store, id), None);
}

#[tokio::test]
async fn the_server_filing_sent_mail_itself_is_not_a_failure() {
    let (store, account) = store();
    let id = queue(&store, account.id, "Plans", None);
    let mut courier = Script::default();
    courier.files.lock().unwrap().push_back(Filing::Server);
    let sent = outbox::send(&store, &account, &mut courier, "me")
        .await
        .unwrap();
    assert_eq!(sent[0].filed, Filing::Server);
    assert!(sent[0].filed.done());
    assert_eq!(state(&store, id), None);
}

#[tokio::test]
async fn a_message_being_sent_can_be_neither_reopened_nor_deleted() {
    let (store, account) = store();
    let store = Arc::new(store);
    let id = queue(&store, account.id, "Plans", None);
    let gate = Arc::new(tokio::sync::Notify::new());
    let started = Arc::new(tokio::sync::Notify::new());
    let courier = Script {
        gate: Some(gate.clone()),
        started: Some(started.clone()),
        ..Script::default()
    };
    let sending = {
        let (store, mut courier) = (store.clone(), courier.clone());
        tokio::spawn(async move { outbox::send_one(&store, id, &mut courier, "me").await })
    };
    started.notified().await;
    // Mid-send: taking it back (to edit or delete it) is refused, so the
    // old version can't go while an edited one goes again.
    assert!(store.lock().unwrap().take_outgoing(id).unwrap().is_none());
    assert_eq!(state(&store, id).as_deref(), Some("sending"));
    gate.notify_one();
    assert!(matches!(sending.await.unwrap().unwrap(), Outcome::Sent(_)));
    assert_eq!(courier.sent.lock().unwrap().len(), 1);
    assert_eq!(state(&store, id), None);

    // Before its time (inside its Undo window) it can be taken back, and
    // then it doesn't go.
    let later = queue(&store, account.id, "Undo me", Some(now() + 10));
    assert!(store
        .lock()
        .unwrap()
        .take_outgoing(later)
        .unwrap()
        .is_some());
    let mut courier = Script::default();
    assert!(matches!(
        outbox::send_one(&store, later, &mut courier, "me")
            .await
            .unwrap(),
        Outcome::Gone
    ));
    assert!(courier.sent.lock().unwrap().is_empty());
}

#[tokio::test]
async fn several_messages_wait_out_their_undo_windows_together() {
    let (store, account) = store();
    let first = queue(&store, account.id, "First", Some(now() + 600));
    let second = queue(&store, account.id, "Second", Some(now() + 600));
    // Not before their time.
    let mut courier = Script::default();
    assert!(matches!(
        outbox::send_one(&store, first, &mut courier, "me")
            .await
            .unwrap(),
        Outcome::Waiting(_)
    ));
    assert!(courier.sent.lock().unwrap().is_empty());
    // Undo on the first leaves the second alone.
    assert!(store
        .lock()
        .unwrap()
        .take_outgoing(first)
        .unwrap()
        .is_some());
    assert_eq!(state(&store, second).as_deref(), Some("queued"));
}

#[tokio::test]
async fn a_late_message_is_dated_when_it_goes() {
    let (store, account) = store();
    let late = now() - 3 * 86_400;
    let id = queue(&store, account.id, "Plans", Some(late));
    let mut courier = Script::default();
    outbox::send_one(&store, id, &mut courier, "me")
        .await
        .unwrap();
    let sent = courier.sent.lock().unwrap();
    let parsed = mail_parser::MessageParser::default()
        .parse(&sent[0].raw)
        .unwrap();
    assert!(parsed.date().unwrap().to_timestamp() >= now() - 60);
}

#[tokio::test]
async fn a_refused_message_keeps_its_reason_and_the_rest_go() {
    let (store, account) = store();
    let refused = queue(&store, account.id, "One", None);
    let fine = queue(&store, account.id, "Two", None);
    let mut courier = Script::default();
    courier
        .sends
        .lock()
        .unwrap()
        .push_back(Err(SendError::Rejected("550 no such user".into())));
    let sent = outbox::send(&store, &account, &mut courier, "me")
        .await
        .unwrap();
    assert_eq!(sent.iter().map(|s| s.id).collect::<Vec<_>>(), [fine]);
    let listed = store.lock().unwrap().outbox(None).unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].id, refused);
    assert_eq!(listed[0].state, State::Refused);
    assert_eq!(listed[0].error.as_deref(), Some("550 no such user"));
}

// ---- Against an SMTP server ------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    /// Takes every message.
    Take,
    /// Reads the message, then the connection drops before its answer.
    DropAfterData,
}

/// A small SMTP server: password "test" logs in. Counts the messages it
/// read whole.
async fn smtp_server(mode: Mode) -> (u16, Arc<AtomicUsize>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let count = Arc::new(AtomicUsize::new(0));
    let seen = count.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let seen = seen.clone();
            tokio::spawn(async move { serve(tcp, seen, mode).await });
        }
    });
    (port, count)
}

async fn serve(tcp: impl AsyncRead + AsyncWrite + Unpin, seen: Arc<AtomicUsize>, mode: Mode) {
    let (r, mut w) = tokio::io::split(tcp);
    let mut lines = BufReader::new(r).lines();
    if w.write_all(b"220 test ESMTP\r\n").await.is_err() {
        return;
    }
    while let Ok(Some(line)) = lines.next_line().await {
        let upper = line.to_ascii_uppercase();
        let reply: &[u8] = if upper.starts_with("EHLO") {
            b"250-test\r\n250 AUTH PLAIN LOGIN\r\n"
        } else if upper.starts_with("AUTH PLAIN") {
            if line.ends_with("AHRlc3Q=") {
                b"235 ok\r\n"
            } else {
                b"535 5.7.8 bad credentials\r\n"
            }
        } else if upper == "DATA" {
            w.write_all(b"354 go on\r\n").await.unwrap();
            while let Ok(Some(l)) = lines.next_line().await {
                if l == "." {
                    break;
                }
            }
            // The server has it now, whatever the client hears.
            seen.fetch_add(1, Ordering::SeqCst);
            if mode == Mode::DropAfterData {
                return;
            }
            b"250 queued\r\n"
        } else if upper == "QUIT" {
            w.write_all(b"221 bye\r\n").await.ok();
            return;
        } else {
            b"250 ok\r\n"
        };
        if w.write_all(reply).await.is_err() {
            return;
        }
    }
}

fn smtp(port: u16, security: Security) -> SmtpConfig {
    SmtpConfig {
        host: "127.0.0.1".into(),
        port,
        security,
        username: "me".into(),
        password: "test".into(),
    }
}

#[tokio::test]
async fn a_lost_answer_after_the_message_is_shown_as_may_have_been_sent() {
    let (port, taken) = smtp_server(Mode::DropAfterData).await;
    // On its own, the send says it may have gone, not "offline".
    let err = send(
        &smtp(port, Security::None),
        &ready(&draft("Plans")).unwrap(),
    )
    .await
    .unwrap_err();
    assert!(matches!(err, SendError::Uncertain(_)), "{err:?}");
    assert!(!err.is_offline());
    assert_eq!(taken.load(Ordering::SeqCst), 1);

    // Through the outbox: kept, marked, and not sent again.
    let store = Store::open_in_memory().unwrap();
    let id = store
        .add_account(&account(AccountId(0), port, closed_port(), Security::None))
        .unwrap();
    let store = Mutex::new(store);
    let online = account(id, port, closed_port(), Security::None);
    let queued = queue(&store, id, "Plans", None);
    for _ in 0..3 {
        let sent = outbox::send(
            &store,
            &online,
            &mut AccountCourier::new(&online, "test"),
            "me",
        )
        .await
        .unwrap();
        assert!(sent.is_empty());
    }
    assert_eq!(taken.load(Ordering::SeqCst), 2, "one more, only once");
    assert_eq!(state(&store, queued).as_deref(), Some("unknown"));
    let listed = store.lock().unwrap().outbox(None).unwrap();
    assert_eq!(listed[0].state, State::Unknown);
}

#[tokio::test]
async fn an_answer_before_the_message_is_safe_to_try_again() {
    // A server that can't be reached: the message never left.
    let err = send(
        &smtp(closed_port(), Security::None),
        &ready(&draft("Plans")).unwrap(),
    )
    .await
    .unwrap_err();
    assert!(err.is_offline(), "{err:?}");
}

/// An SMTP server over TLS whose certificate nobody signed.
async fn untrusted_tls_server() -> (u16, Arc<AtomicUsize>) {
    use tokio_rustls::rustls;
    let cert = rustls::pki_types::CertificateDer::from(
        include_bytes!("fixtures/self-signed-cert.der").to_vec(),
    );
    let key = rustls::pki_types::PrivateKeyDer::Pkcs8(
        include_bytes!("fixtures/self-signed-key.der")
            .to_vec()
            .into(),
    );
    // Both cryptography libraries are built into the tests (see tls.rs):
    // name one.
    let config = rustls::ServerConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .unwrap()
    .with_no_client_auth()
    .with_single_cert(vec![cert], key)
    .unwrap();
    let acceptor = tokio_rustls::TlsAcceptor::from(Arc::new(config));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let count = Arc::new(AtomicUsize::new(0));
    let seen = count.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let (acceptor, seen) = (acceptor.clone(), seen.clone());
            tokio::spawn(async move {
                if let Ok(tls) = acceptor.accept(tcp).await {
                    serve(tls, seen, Mode::Take).await;
                }
            });
        }
    });
    (port, count)
}

#[tokio::test]
async fn a_certificate_error_shows_and_does_not_wait_as_offline() {
    let (port, taken) = untrusted_tls_server().await;
    let err = send(&smtp(port, Security::Tls), &ready(&draft("Plans")).unwrap())
        .await
        .unwrap_err();
    assert!(matches!(err, SendError::Tls { .. }), "{err:?}");
    assert!(!err.is_offline());

    let store = Store::open_in_memory().unwrap();
    let id = store
        .add_account(&account(AccountId(0), port, closed_port(), Security::Tls))
        .unwrap();
    let store = Mutex::new(store);
    let secure = account(id, port, closed_port(), Security::Tls);
    let first = queue(&store, id, "One", None);
    let second = queue(&store, id, "Two", None);
    let sent = outbox::send(
        &store,
        &secure,
        &mut AccountCourier::new(&secure, "test"),
        "me",
    )
    .await
    .unwrap();
    assert!(sent.is_empty());
    assert_eq!(taken.load(Ordering::SeqCst), 0);
    let listed = store.lock().unwrap().outbox(None).unwrap();
    assert_eq!(listed[0].id, first);
    assert_eq!(listed[0].state, State::Refused, "shown, with its reason");
    assert!(
        listed[0].error.as_deref().unwrap().contains("secure"),
        "{:?}",
        listed[0].error
    );
    // The next message meets the same server: it waits, untouched.
    assert_eq!(listed[1].id, second);
    assert_eq!(listed[1].state, State::Waiting);
}
