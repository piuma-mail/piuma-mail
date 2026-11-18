//! The IMAP engine against a scripted server that misbehaves on purpose:
//! one that never greets, one that stops halfway through a message, one
//! that refuses a folder every time, one that renumbered a folder, one
//! that is busy for a while. Runs everywhere, without a real server.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use piuma_core::imap::{watch_timed, Connection, ImapConfig, ImapError, Timing, WatchEvent};
use piuma_core::model::ReplyInfo;
use piuma_core::pending::Change;
use piuma_core::remote::Remote;
use piuma_core::{
    Account, AccountId, AccountKind, Flags, Folder, ListInfo, MailboxState, MessageSummary,
    Security, Server, Store,
};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::time::Instant;

/// How the scripted server behaves.
#[derive(Clone, Default)]
struct Script {
    /// Says nothing after the connection is made.
    silent: bool,
    /// Sends its greeting one byte at a time, a byte every 100 ms, for ever.
    trickle: bool,
    /// Answers SELECT with NO.
    refuse_select: bool,
    /// UIDVALIDITY per folder; 1 when not listed.
    validity: Vec<(&'static str, u32)>,
    /// Leaves UIDVALIDITY out of its SELECT answers.
    no_validity: bool,
    /// Starts sending a whole message, then goes quiet.
    stall_body: bool,
    /// Answers to UID MOVE, in turn; OK once they run out.
    moves: Arc<Mutex<VecDeque<&'static str>>>,
}

/// What the server saw: every command, and when each login came.
#[derive(Clone, Default)]
struct Seen {
    commands: Arc<Mutex<Vec<String>>>,
    logins: Arc<Mutex<Vec<Instant>>>,
}

impl Seen {
    fn commands(&self) -> Vec<String> {
        self.commands.lock().unwrap().clone()
    }

    fn any(&self, verb: &str) -> bool {
        self.commands().iter().any(|c| c.starts_with(verb))
    }
}

async fn serve(script: Script) -> (ImapConfig, Seen) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let seen = Seen::default();
    let shared = seen.clone();
    tokio::spawn(async move {
        loop {
            let Ok((stream, _)) = listener.accept().await else {
                return;
            };
            tokio::spawn(session(stream, script.clone(), shared.clone()));
        }
    });
    let cfg = ImapConfig {
        host: "127.0.0.1".into(),
        port,
        security: Security::None,
        username: "me".into(),
        password: "test".into(),
    };
    (cfg, seen)
}

async fn session(stream: tokio::net::TcpStream, script: Script, seen: Seen) {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    if script.silent {
        // Keep the connection open, say nothing.
        while let Ok(Some(_)) = lines.next_line().await {}
        return;
    }
    if script.trickle {
        for b in b"* OK still saying hello".iter().cycle() {
            if write.write_all(&[*b]).await.is_err() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }
    write.write_all(b"* OK ready\r\n").await.unwrap();
    while let Ok(Some(line)) = lines.next_line().await {
        let mut parts = line.splitn(3, ' ');
        let tag = parts.next().unwrap_or_default().to_owned();
        let mut verb = parts.next().unwrap_or_default().to_ascii_uppercase();
        let mut rest = parts.next().unwrap_or_default().to_owned();
        if verb == "UID" {
            let mut more = rest.splitn(2, ' ');
            verb = format!(
                "UID {}",
                more.next().unwrap_or_default().to_ascii_uppercase()
            );
            rest = more.next().unwrap_or_default().to_owned();
        }
        seen.commands
            .lock()
            .unwrap()
            .push(format!("{verb} {rest}").trim().to_owned());
        let reply = match verb.as_str() {
            "CAPABILITY" => {
                format!("* CAPABILITY IMAP4rev1 MOVE UIDPLUS\r\n{tag} OK done\r\n")
            }
            "LOGIN" => {
                seen.logins.lock().unwrap().push(Instant::now());
                format!("{tag} OK logged in\r\n")
            }
            "SELECT" | "EXAMINE" if script.refuse_select => {
                format!("{tag} NO [UNAVAILABLE] Mailbox is being rebuilt\r\n")
            }
            "SELECT" | "EXAMINE" => {
                let selected = rest.trim_matches('"');
                let validity = script
                    .validity
                    .iter()
                    .find(|(m, _)| *m == selected)
                    .map_or(1, |(_, v)| *v);
                let validity = if script.no_validity {
                    String::new()
                } else {
                    format!("* OK [UIDVALIDITY {validity}] ok\r\n")
                };
                format!(
                    "* 3 EXISTS\r\n* 0 RECENT\r\n{validity}\
                     * OK [UIDNEXT 20] ok\r\n* FLAGS (\\Seen \\Deleted)\r\n\
                     * OK [PERMANENTFLAGS (\\Seen \\Deleted \\*)] ok\r\n\
                     {tag} OK [READ-WRITE] done\r\n"
                )
            }
            "LIST" => format!(
                "* LIST () \"/\" \"INBOX\"\r\n* LIST (\\Archive) \"/\" \"Archive\"\r\n\
                 * LIST (\\Trash) \"/\" \"Trash\"\r\n* LIST () \"/\" \"Projects\"\r\n\
                 {tag} OK done\r\n"
            ),
            "UID FETCH" if rest.contains("RFC822.SIZE") => {
                format!("* 1 FETCH (UID 1 RFC822.SIZE 100000)\r\n{tag} OK done\r\n")
            }
            "UID FETCH" if script.stall_body && rest.contains("BODY.PEEK[]") => {
                // A tenth of what was announced, then nothing.
                write
                    .write_all(b"* 1 FETCH (UID 1 BODY[] {100000}\r\n")
                    .await
                    .unwrap();
                write.write_all(&[b'x'; 10_000]).await.unwrap();
                std::future::pending::<()>().await;
                unreachable!()
            }
            "UID MOVE" => {
                let next = script.moves.lock().unwrap().pop_front();
                match next {
                    Some(no) => format!("{tag} {no}\r\n"),
                    None => format!("{tag} OK moved\r\n"),
                }
            }
            "UID SEARCH" => format!("* SEARCH\r\n{tag} OK done\r\n"),
            "LOGOUT" => format!("* BYE\r\n{tag} OK bye\r\n"),
            _ => format!("{tag} OK done\r\n"),
        };
        if write.write_all(reply.as_bytes()).await.is_err() {
            return;
        }
    }
}

/// Short deadlines, so the tests take a second rather than minutes.
fn quick() -> Timing {
    Timing {
        connect: Duration::from_secs(2),
        open: Duration::from_secs(2),
        handshake_stall: Duration::from_millis(300),
        command_stall: Duration::from_millis(300),
        retry_first: Duration::from_millis(100),
    }
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
                    host: "127.0.0.1".into(),
                    port: 1,
                    security: Security::None,
                },
                smtp: Server {
                    host: "127.0.0.1".into(),
                    port: 1,
                    security: Security::None,
                },
                username: "me".into(),
            },
        })
        .unwrap();
    (Arc::new(Mutex::new(store)), id)
}

fn message(account: AccountId, mailbox: &str, uid: u32) -> MessageSummary {
    MessageSummary {
        account,
        mailbox: mailbox.into(),
        uid,
        from_name: "Julia Reed".into(),
        from_email: "julia@example.org".into(),
        to: "Me".into(),
        subject: format!("Message {uid}"),
        preview: String::new(),
        received_at: 1_000 + uid as i64,
        flags: Flags::default(),
        reply: ReplyInfo::default(),
        list: ListInfo::default(),
    }
}

/// Messages stored under a folder's UIDVALIDITY, as a sync leaves them.
fn stored(store: &Mutex<Store>, account: AccountId, mailbox: &str, validity: u32, uids: &[u32]) {
    let mut s = store.lock().unwrap();
    s.upsert_messages(
        &uids
            .iter()
            .map(|u| message(account, mailbox, *u))
            .collect::<Vec<_>>(),
    )
    .unwrap();
    s.set_mailbox_state(
        account,
        mailbox,
        MailboxState {
            uid_validity: validity,
            highest_modseq: None,
        },
    )
    .unwrap();
}

#[tokio::test]
async fn a_server_that_never_greets_times_out() {
    let (cfg, _) = serve(Script {
        silent: true,
        ..Script::default()
    })
    .await;
    let started = std::time::Instant::now();
    let e = Connection::open_timed(&cfg, quick())
        .await
        .err()
        .expect("no greeting, no connection");
    assert!(matches!(e, ImapError::TimedOut), "{e}");
    // Offline: the watcher retries, the app says it can't reach it.
    assert!(e.is_offline());
    assert!(started.elapsed() < Duration::from_secs(2));
}

#[tokio::test]
async fn a_greeting_that_trickles_for_ever_still_ends() {
    let (cfg, _) = serve(Script {
        trickle: true,
        ..Script::default()
    })
    .await;
    let started = std::time::Instant::now();
    let e = Connection::open_timed(&cfg, quick())
        .await
        .err()
        .expect("never logged in");
    // Bytes keep coming, so no stall: the deadline on the whole login
    // ends it.
    assert!(matches!(e, ImapError::TimedOut), "{e}");
    assert!(started.elapsed() < Duration::from_secs(4));
}

#[tokio::test]
async fn a_message_that_stops_halfway_times_out() {
    let (cfg, _) = serve(Script {
        stall_body: true,
        ..Script::default()
    })
    .await;
    let mut conn = Connection::open_timed(&cfg, quick()).await.unwrap();
    let started = std::time::Instant::now();
    let e = conn.raw("INBOX", 1).await.unwrap_err();
    assert!(matches!(e, ImapError::TimedOut), "{e}");
    assert!(started.elapsed() < Duration::from_secs(2));
}

/// A folder the server refuses on every try (a store error, a reply that
/// can't be read would do the same) fails right after a login that
/// worked: the logins come further and further apart, not every 2 s.
#[tokio::test]
async fn a_folder_refused_every_time_spaces_the_logins_out() {
    let (cfg, seen) = serve(Script {
        refuse_select: true,
        ..Script::default()
    })
    .await;
    let (store, account) = store_with_account();
    let offline = Arc::new(Mutex::new(0));
    let counted = offline.clone();
    let task = tokio::spawn(watch_timed(
        cfg,
        store,
        account,
        "INBOX".into(),
        move |e| {
            if let WatchEvent::Offline { .. } = e {
                *counted.lock().unwrap() += 1;
            }
        },
        quick(),
    ));
    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    while seen.logins.lock().unwrap().len() < 5 {
        assert!(std::time::Instant::now() < deadline, "too few logins");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    task.abort();
    let logins = seen.logins.lock().unwrap().clone();
    let gaps: Vec<f64> = logins
        .windows(2)
        .map(|w| (w[1] - w[0]).as_secs_f64())
        .collect();
    // 100, 200, 400, 800 ms, each spread by up to 20 %: every gap is more
    // than 1.3 times the one before.
    for pair in gaps.windows(2) {
        assert!(pair[1] > pair[0] * 1.3, "{gaps:?}");
    }
    assert!(gaps[0] >= 0.08, "{gaps:?}");
    assert!(*offline.lock().unwrap() >= 4);
}

/// The server rebuilt the inbox while this device was offline: the moves
/// and the read change queued for it, and an erase, would land on other
/// messages. None is sent, the queue for that folder is dropped, and the
/// messages they had hidden are back.
#[tokio::test]
async fn a_renumbered_folder_gets_none_of_the_queued_changes() {
    let (cfg, seen) = serve(Script {
        validity: vec![("INBOX", 2), ("Drafts", 6)],
        ..Script::default()
    })
    .await;
    let (store, account) = store_with_account();
    stored(&store, account, "INBOX", 1, &[1, 2, 3]);
    stored(&store, account, "Drafts", 5, &[4]);
    {
        use piuma_core::imap::FolderRole;
        let s = store.lock().unwrap();
        for (uid, change) in [
            (1, Change::Move(FolderRole::Trash)),
            (2, Change::Move(FolderRole::Archive)),
            (3, Change::MoveTo("Projects".into())),
        ] {
            s.set_hidden(account, "INBOX", uid, true).unwrap();
            s.queue_change(account, "INBOX", uid, change).unwrap();
        }
        s.queue_change(account, "INBOX", 3, Change::Seen(true))
            .unwrap();
        assert_eq!(s.count(Folder::Inbox).unwrap(), 0);
    }
    let conn = Connection::open_timed(&cfg, quick()).await.unwrap();
    let mut remote = Remote::Imap(conn);
    assert_eq!(remote.send_pending(&store, account).await.unwrap(), 0);
    let Remote::Imap(mut conn) = remote else {
        unreachable!()
    };
    // An earlier copy of a draft, erased for good: not under these
    // numbers.
    let e = conn
        .erase(&store, account, "Drafts", &[4])
        .await
        .unwrap_err();
    assert!(matches!(e, ImapError::Renumbered), "{e}");

    for verb in [
        "UID MOVE",
        "UID COPY",
        "UID STORE",
        "UID EXPUNGE",
        "EXPUNGE",
    ] {
        assert!(!seen.any(verb), "{verb} sent: {:?}", seen.commands());
    }
    let s = store.lock().unwrap();
    assert!(s.pending_changes(account).unwrap().is_empty());
    assert_eq!(s.count(Folder::Inbox).unwrap(), 3);
}

/// A server that answers THROTTLED five times in a row, then takes the
/// move: the move waits, stays queued and hidden, and goes through.
#[tokio::test]
async fn a_busy_server_gets_the_move_once_it_takes_it() {
    let (cfg, seen) = serve(Script {
        moves: Arc::new(Mutex::new(
            std::iter::repeat_n("NO [THROTTLED] Too many commands, slow down", 5).collect(),
        )),
        ..Script::default()
    })
    .await;
    let (store, account) = store_with_account();
    stored(&store, account, "INBOX", 1, &[1]);
    {
        let s = store.lock().unwrap();
        s.set_hidden(account, "INBOX", 1, true).unwrap();
        s.queue_change(
            account,
            "INBOX",
            1,
            Change::Move(piuma_core::imap::FolderRole::Trash),
        )
        .unwrap();
    }
    let mut remote = Remote::Imap(Connection::open_timed(&cfg, quick()).await.unwrap());
    for attempt in 1..=5 {
        assert_eq!(remote.send_pending(&store, account).await.unwrap(), 0);
        let s = store.lock().unwrap();
        let waiting = s.pending_changes(account).unwrap();
        assert_eq!(waiting.len(), 1, "kept after {attempt} refusals");
        assert_eq!(waiting[0].attempts, attempt);
        // Not tried again at once: its wait has to pass.
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;
        assert!(s.due_changes(account, now).unwrap().is_empty());
        assert_eq!(s.count(Folder::Inbox).unwrap(), 0, "still hidden");
        // As if the wait were over.
        s.retry_changes_now(account).unwrap();
    }
    assert_eq!(remote.send_pending(&store, account).await.unwrap(), 0);
    let moves = seen
        .commands()
        .into_iter()
        .filter(|c| c.starts_with("UID MOVE"))
        .count();
    assert_eq!(moves, 6);
    let s = store.lock().unwrap();
    assert!(s.pending_changes(account).unwrap().is_empty());
    // Gone to Trash on the server, and from the inbox here.
    assert!(s.message(account, "INBOX", 1).unwrap().is_none());
}

/// A move the server refuses for good (the folder is gone) is given up
/// after a few tries, the message comes back, and the person is told.
#[tokio::test]
async fn a_move_refused_for_good_is_given_up_and_counted() {
    let (cfg, _) = serve(Script {
        moves: Arc::new(Mutex::new(
            std::iter::repeat_n("NO [TRYCREATE] No such folder", 10).collect(),
        )),
        ..Script::default()
    })
    .await;
    let (store, account) = store_with_account();
    stored(&store, account, "INBOX", 1, &[1]);
    {
        let s = store.lock().unwrap();
        s.set_hidden(account, "INBOX", 1, true).unwrap();
        s.queue_change(account, "INBOX", 1, Change::MoveTo("Projects".into()))
            .unwrap();
    }
    let mut remote = Remote::Imap(Connection::open_timed(&cfg, quick()).await.unwrap());
    let mut dropped = 0;
    for _ in 0..piuma_core::pending::REFUSED_ATTEMPTS {
        dropped += remote.send_pending(&store, account).await.unwrap();
        store.lock().unwrap().retry_changes_now(account).unwrap();
    }
    assert_eq!(dropped, 1);
    let s = store.lock().unwrap();
    assert!(s.pending_changes(account).unwrap().is_empty());
    assert_eq!(s.count(Folder::Inbox).unwrap(), 1);
}

/// A SELECT answer without UIDVALIDITY can't vouch for the stored numbers:
/// nothing is sent, but nothing is thrown away either. The queued move
/// counts a try, stays queued and hidden, and follows the usual rules.
#[tokio::test]
async fn a_folder_answer_without_uidvalidity_touches_and_drops_nothing() {
    let (cfg, seen) = serve(Script {
        no_validity: true,
        ..Script::default()
    })
    .await;
    let (store, account) = store_with_account();
    stored(&store, account, "INBOX", 1, &[1, 2]);
    stored(&store, account, "Drafts", 5, &[4]);
    {
        let s = store.lock().unwrap();
        s.set_hidden(account, "INBOX", 1, true).unwrap();
        s.queue_change(
            account,
            "INBOX",
            1,
            Change::Move(piuma_core::imap::FolderRole::Trash),
        )
        .unwrap();
    }
    let conn = Connection::open_timed(&cfg, quick()).await.unwrap();
    let mut remote = Remote::Imap(conn);
    assert_eq!(remote.send_pending(&store, account).await.unwrap(), 0);
    let Remote::Imap(mut conn) = remote else {
        unreachable!()
    };
    let e = conn
        .erase(&store, account, "Drafts", &[4])
        .await
        .unwrap_err();
    assert!(matches!(e, ImapError::NoUidValidity), "{e}");

    for verb in [
        "UID MOVE",
        "UID COPY",
        "UID STORE",
        "UID EXPUNGE",
        "EXPUNGE",
    ] {
        assert!(!seen.any(verb), "{verb} sent: {:?}", seen.commands());
    }
    let s = store.lock().unwrap();
    let waiting = s.pending_changes(account).unwrap();
    assert_eq!(waiting.len(), 1);
    assert_eq!(waiting[0].attempts, 1);
    // Still hidden: its move is still on its way.
    assert_eq!(s.count(Folder::Inbox).unwrap(), 1);
    // The stored numbers are kept for the next sync to check.
    assert!(s.message(account, "Drafts", 4).unwrap().is_some());
}
