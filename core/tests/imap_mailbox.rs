//! Managing the mailbox over IMAP, against a small server inside the test
//! that keeps its folders, messages and flags: stars, copies, deleting
//! for good in Trash and spam, Empty Trash, renaming, hiding and deleting
//! folders, a folder of the person's choice for a job, and quota. Every
//! change goes through the queue, so a renumbered folder drops it and a
//! busy server gets it later.

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use piuma_core::imap::{Connection, FolderRole, ImapConfig, Timing};
use piuma_core::model::ReplyInfo;
use piuma_core::pending::{Change, FolderChange};
use piuma_core::remote::Remote;
use piuma_core::{
    Account, AccountId, AccountKind, Flags, ListInfo, MailboxState, MessageSummary, Security,
    Server, Store,
};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;

#[derive(Default, Clone)]
struct Mailbox {
    validity: u32,
    next_uid: u32,
    subscribed: bool,
    /// Its RFC 6154 mark, as `\Trash`.
    special: Option<&'static str>,
    messages: BTreeMap<u32, BTreeSet<String>>,
}

#[derive(Default)]
struct State {
    mailboxes: BTreeMap<String, Mailbox>,
    commands: Vec<String>,
    /// Answers to give a verb before it works, in turn.
    refuse: BTreeMap<&'static str, VecDeque<&'static str>>,
}

impl State {
    fn add(&mut self, name: &str, special: Option<&'static str>, subscribed: bool, count: u32) {
        let mut m = Mailbox {
            validity: 1,
            next_uid: 1,
            subscribed,
            special,
            ..Mailbox::default()
        };
        for _ in 0..count {
            m.messages.insert(m.next_uid, BTreeSet::new());
            m.next_uid += 1;
        }
        self.mailboxes.insert(name.to_owned(), m);
    }

    fn uids(&self, name: &str) -> Vec<u32> {
        self.mailboxes[name].messages.keys().copied().collect()
    }

    fn flags(&self, name: &str, uid: u32) -> BTreeSet<String> {
        self.mailboxes[name].messages[&uid].clone()
    }

    fn sent(&self, verb: &str) -> usize {
        self.commands.iter().filter(|c| c.starts_with(verb)).count()
    }
}

/// Words of a command line, quoted strings as one.
fn words(line: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            ' ' => {}
            '"' => {
                let mut w = String::new();
                while let Some(c) = chars.next() {
                    match c {
                        '\\' => w.extend(chars.next()),
                        '"' => break,
                        c => w.push(c),
                    }
                }
                out.push(w);
            }
            '(' => {
                let mut w = String::from("(");
                for c in chars.by_ref() {
                    w.push(c);
                    if c == ')' {
                        break;
                    }
                }
                out.push(w);
            }
            c => {
                let mut w = String::from(c);
                while let Some(&c) = chars.peek() {
                    if c == ' ' {
                        break;
                    }
                    w.push(c);
                    chars.next();
                }
                out.push(w);
            }
        }
    }
    out
}

/// The uids a set names among `have`.
fn in_set(set: &str, have: &[u32]) -> Vec<u32> {
    let max = have.iter().max().copied().unwrap_or(0);
    let mut out = BTreeSet::new();
    for part in set.split(',') {
        let (a, b) = part.split_once(':').unwrap_or((part, part));
        let n = |s: &str| if s == "*" { max } else { s.parse().unwrap() };
        let (a, b) = (n(a), n(b));
        let (lo, hi) = (a.min(b), a.max(b));
        out.extend(have.iter().copied().filter(|u| (lo..=hi).contains(u)));
    }
    out.into_iter().collect()
}

async fn serve(state: Arc<Mutex<State>>) -> ImapConfig {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            tokio::spawn(session(stream, state.clone()));
        }
    });
    ImapConfig {
        host: "127.0.0.1".into(),
        port,
        security: Security::None,
        username: "me".into(),
        password: "test".into(),
    }
}

async fn session(stream: tokio::net::TcpStream, state: Arc<Mutex<State>>) {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    write.write_all(b"* OK ready\r\n").await.unwrap();
    let mut selected: Option<String> = None;
    while let Ok(Some(line)) = lines.next_line().await {
        let w = words(&line);
        let tag = w.first().cloned().unwrap_or_default();
        let mut verb = w.get(1).cloned().unwrap_or_default().to_ascii_uppercase();
        let mut args: Vec<String> = w.iter().skip(2).cloned().collect();
        if verb == "UID" && !args.is_empty() {
            verb = format!("UID {}", args.remove(0).to_ascii_uppercase());
        }
        let reply = {
            let mut s = state.lock().unwrap();
            s.commands
                .push(format!("{verb} {}", args.join(" ")).trim().to_owned());
            let refused = s
                .refuse
                .iter_mut()
                .find(|(v, _)| verb == **v)
                .and_then(|(_, q)| q.pop_front());
            match refused {
                Some(no) => format!("{tag} {no}\r\n"),
                None => answer(&mut s, &tag, &verb, &args, &mut selected),
            }
        };
        if write.write_all(reply.as_bytes()).await.is_err() {
            return;
        }
    }
}

fn answer(
    s: &mut State,
    tag: &str,
    verb: &str,
    args: &[String],
    selected: &mut Option<String>,
) -> String {
    let ok = format!("{tag} OK done\r\n");
    let missing = format!("{tag} NO [NONEXISTENT] No such folder\r\n");
    let arg = |i: usize| args.get(i).cloned().unwrap_or_default();
    match verb {
        "CAPABILITY" => {
            format!("* CAPABILITY IMAP4rev1 MOVE UIDPLUS QUOTA\r\n{tag} OK done\r\n")
        }
        "LOGIN" => format!("{tag} OK logged in\r\n"),
        "LOGOUT" => format!("* BYE\r\n{tag} OK bye\r\n"),
        "LIST" | "LSUB" => {
            let mut out = String::new();
            for (name, m) in &s.mailboxes {
                if verb == "LSUB" && !m.subscribed {
                    continue;
                }
                let attrs = m.special.unwrap_or_default();
                out += &format!("* {verb} ({attrs}) \"/\" \"{name}\"\r\n");
            }
            out + &ok
        }
        "SELECT" | "EXAMINE" => {
            let name = arg(0);
            let Some(m) = s.mailboxes.get(&name) else {
                return missing;
            };
            *selected = Some(name);
            format!(
                "* {} EXISTS\r\n* 0 RECENT\r\n* OK [UIDVALIDITY {}] ok\r\n\
                 * OK [UIDNEXT {}] ok\r\n* FLAGS (\\Seen \\Flagged \\Deleted)\r\n\
                 * OK [PERMANENTFLAGS (\\Seen \\Flagged \\Deleted \\*)] ok\r\n\
                 {tag} OK [READ-WRITE] done\r\n",
                m.messages.len(),
                m.validity,
                m.next_uid
            )
        }
        "CLOSE" => {
            *selected = None;
            ok
        }
        "STATUS" => {
            let name = arg(0);
            let Some(m) = s.mailboxes.get(&name) else {
                return missing;
            };
            let unseen = m
                .messages
                .values()
                .filter(|f| !f.contains("\\Seen"))
                .count();
            format!(
                "* STATUS \"{name}\" (MESSAGES {} UNSEEN {unseen})\r\n{ok}",
                m.messages.len()
            )
        }
        "UID SEARCH" => {
            let have = s.uids(selected.as_deref().unwrap_or("INBOX"));
            let list: Vec<String> = have.iter().map(u32::to_string).collect();
            format!("* SEARCH {}\r\n{ok}", list.join(" "))
        }
        "UID FETCH" => ok,
        "UID STORE" => {
            let name = selected.clone().unwrap();
            let have = s.uids(&name);
            let uids = in_set(&arg(0), &have);
            let op = arg(1);
            let flags: Vec<String> = arg(2)
                .trim_matches(|c| c == '(' || c == ')')
                .split(' ')
                .filter(|f| !f.is_empty())
                .map(str::to_owned)
                .collect();
            let m = s.mailboxes.get_mut(&name).unwrap();
            for uid in uids {
                let set = m.messages.get_mut(&uid).unwrap();
                for f in &flags {
                    if op.starts_with('+') {
                        set.insert(f.clone());
                    } else {
                        set.remove(f);
                    }
                }
            }
            ok
        }
        "UID COPY" | "UID MOVE" => {
            let from = selected.clone().unwrap();
            let to = arg(1);
            if !s.mailboxes.contains_key(&to) {
                return format!("{tag} NO [TRYCREATE] No such folder\r\n");
            }
            let uids = in_set(&arg(0), &s.uids(&from));
            for uid in uids {
                let flags = s.flags(&from, uid);
                let target = s.mailboxes.get_mut(&to).unwrap();
                let new = target.next_uid;
                target.next_uid += 1;
                target.messages.insert(new, flags);
                if verb == "UID MOVE" {
                    s.mailboxes.get_mut(&from).unwrap().messages.remove(&uid);
                }
            }
            ok
        }
        "UID EXPUNGE" | "EXPUNGE" => {
            let name = selected.clone().unwrap();
            let have = s.uids(&name);
            let only = if verb == "EXPUNGE" {
                have.clone()
            } else {
                in_set(&arg(0), &have)
            };
            let m = s.mailboxes.get_mut(&name).unwrap();
            m.messages
                .retain(|uid, f| !(only.contains(uid) && f.contains("\\Deleted")));
            ok
        }
        "CREATE" => {
            s.add(&arg(0), None, false, 0);
            ok
        }
        "DELETE" => {
            if s.mailboxes.remove(&arg(0)).is_none() {
                return missing;
            }
            ok
        }
        "RENAME" => {
            let (from, to) = (arg(0), arg(1));
            if s.mailboxes.contains_key(&to) {
                return format!("{tag} NO [ALREADYEXISTS] Exists\r\n");
            }
            let names: Vec<String> = s
                .mailboxes
                .keys()
                .filter(|n| **n == from || n.starts_with(&format!("{from}/")))
                .cloned()
                .collect();
            if names.is_empty() {
                return missing;
            }
            for n in names {
                let m = s.mailboxes.remove(&n).unwrap();
                s.mailboxes.insert(format!("{to}{}", &n[from.len()..]), m);
            }
            ok
        }
        "SUBSCRIBE" | "UNSUBSCRIBE" => {
            if let Some(m) = s.mailboxes.get_mut(&arg(0)) {
                m.subscribed = verb == "SUBSCRIBE";
            }
            ok
        }
        "GETQUOTAROOT" => {
            format!("* QUOTAROOT INBOX \"\"\r\n* QUOTA \"\" (STORAGE 900 1000)\r\n{ok}")
        }
        _ => ok,
    }
}

fn quick() -> Timing {
    Timing {
        connect: Duration::from_secs(2),
        open: Duration::from_secs(2),
        handshake_stall: Duration::from_millis(500),
        command_stall: Duration::from_millis(500),
        retry_first: Duration::from_millis(100),
    }
}

fn store_with_account() -> (Arc<Mutex<Store>>, AccountId) {
    let store = Store::open_in_memory().unwrap();
    let server = Server {
        host: "127.0.0.1".into(),
        port: 1,
        security: Security::None,
    };
    let id = store
        .add_account(&Account {
            id: AccountId(0),
            name: "Test".into(),
            email: "me@example.org".into(),
            sender_name: String::new(),
            color: "#2F8F83".into(),
            kind: AccountKind::Imap {
                imap: server.clone(),
                smtp: server,
                username: "me".into(),
            },
        })
        .unwrap();
    (Arc::new(Mutex::new(store)), id)
}

/// Messages stored as a sync leaves them, under the folder's UIDVALIDITY.
fn stored(store: &Mutex<Store>, account: AccountId, mailbox: &str, validity: u32, uids: &[u32]) {
    let mut s = store.lock().unwrap();
    let rows: Vec<MessageSummary> = uids
        .iter()
        .map(|uid| MessageSummary {
            account,
            mailbox: mailbox.into(),
            uid: *uid,
            from_name: "Julia Reed".into(),
            from_email: "julia@example.org".into(),
            to: "Me".into(),
            subject: format!("Message {uid}"),
            preview: String::new(),
            received_at: 1_000 + *uid as i64,
            flags: Flags::default(),
            reply: ReplyInfo::default(),
            list: ListInfo::default(),
        })
        .collect();
    s.upsert_messages(&rows).unwrap();
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

/// A server with an inbox of three, Trash with two, spam with one, and
/// the person's folders: Projects with a subfolder, and Old, hidden.
fn mailbox() -> Arc<Mutex<State>> {
    let mut s = State::default();
    s.add("INBOX", None, true, 3);
    s.add("Sent", Some("\\Sent"), true, 0);
    s.add("Archive", Some("\\Archive"), true, 0);
    s.add("Drafts", Some("\\Drafts"), true, 0);
    s.add("Trash", Some("\\Trash"), true, 2);
    s.add("Spam", Some("\\Junk"), true, 1);
    s.add("Projects", None, true, 2);
    s.add("Projects/2026", None, true, 1);
    s.add("Old", None, false, 4);
    Arc::new(Mutex::new(s))
}

async fn connect(cfg: &ImapConfig) -> Remote {
    Remote::Imap(Connection::open_timed(cfg, quick()).await.unwrap())
}

#[tokio::test]
async fn delete_in_trash_and_spam_is_for_good_and_nothing_comes_back() {
    let state = mailbox();
    let cfg = serve(state.clone()).await;
    let (store, a) = store_with_account();
    let mut remote = connect(&cfg).await;
    remote.sync_folders(&store, a).await.unwrap();
    {
        let s = store.lock().unwrap();
        assert_eq!(s.trash_mailbox(a).unwrap().as_deref(), Some("Trash"));
        assert!(s.deletes_for_good(a, "Trash").unwrap());
        assert!(s.deletes_for_good(a, "Spam").unwrap());
    }
    stored(&store, a, "Trash", 1, &[1, 2]);
    stored(&store, a, "Spam", 1, &[1]);
    // A Delete queued from Trash as a move (an older app, a rule) is a
    // deletion too: Trash to Trash would copy it in again.
    let Remote::Imap(mut conn) = remote else {
        unreachable!()
    };
    conn.move_messages(&store, a, "Trash", &[1], FolderRole::Trash)
        .await
        .unwrap();
    let mut remote = Remote::Imap(conn);
    // Delete in spam, queued.
    store.lock().unwrap().queue_erase(a, "Spam", &[1]).unwrap();
    assert_eq!(remote.send_pending(&store, a).await.unwrap(), 0);
    let s = state.lock().unwrap();
    assert_eq!(s.uids("Trash"), [2]);
    assert_eq!(s.mailboxes["Trash"].next_uid, 3, "nothing copied in");
    assert!(s.uids("Spam").is_empty());
    assert_eq!(s.sent("UID MOVE") + s.sent("UID COPY"), 0);
    let st = store.lock().unwrap();
    assert!(st.message(a, "Trash", 1).unwrap().is_none());
    assert!(st.message(a, "Spam", 1).unwrap().is_none());
    assert!(st.pending_changes(a).unwrap().is_empty());
}

#[tokio::test]
async fn empty_trash_deletes_all_of_it() {
    let state = mailbox();
    let cfg = serve(state.clone()).await;
    let (store, a) = store_with_account();
    stored(&store, a, "Trash", 1, &[1]);
    let mut remote = connect(&cfg).await;
    assert_eq!(remote.count("Trash").await.unwrap(), 2);
    // One not here yet goes too.
    assert_eq!(remote.empty(&store, a, "Trash").await.unwrap(), 2);
    assert!(state.lock().unwrap().uids("Trash").is_empty());
    assert_eq!(store.lock().unwrap().messages_in(a, "Trash").unwrap(), 0);
}

#[tokio::test]
async fn stars_and_copies_reach_the_server() {
    let state = mailbox();
    let cfg = serve(state.clone()).await;
    let (store, a) = store_with_account();
    stored(&store, a, "INBOX", 1, &[1, 2, 3]);
    {
        let s = store.lock().unwrap();
        s.queue_flags(&[(a, "INBOX".into(), 1), (a, "INBOX".into(), 2)], true)
            .unwrap();
        s.queue_change(a, "INBOX", 3, Change::CopyTo("Projects".into()))
            .unwrap();
    }
    let mut remote = connect(&cfg).await;
    assert_eq!(remote.send_pending(&store, a).await.unwrap(), 0);
    {
        let s = state.lock().unwrap();
        assert!(s.flags("INBOX", 1).contains("\\Flagged"));
        assert!(s.flags("INBOX", 2).contains("\\Flagged"));
        assert!(!s.flags("INBOX", 3).contains("\\Flagged"));
        // Copied, and still in the inbox.
        assert_eq!(s.uids("Projects").len(), 3);
        assert_eq!(s.uids("INBOX").len(), 3);
    }
    assert!(store
        .lock()
        .unwrap()
        .message(a, "INBOX", 3)
        .unwrap()
        .is_some());
    store
        .lock()
        .unwrap()
        .queue_flags(&[(a, "INBOX".into(), 1)], false)
        .unwrap();
    remote.send_pending(&store, a).await.unwrap();
    assert!(!state
        .lock()
        .unwrap()
        .flags("INBOX", 1)
        .contains("\\Flagged"));
    assert_eq!(store.lock().unwrap().starred(Some(a)).unwrap().len(), 1);
}

#[tokio::test]
async fn folders_are_renamed_shown_and_deleted() {
    let state = mailbox();
    let cfg = serve(state.clone()).await;
    let (store, a) = store_with_account();
    let mut remote = connect(&cfg).await;
    remote.sync_folders(&store, a).await.unwrap();
    let folders = store.lock().unwrap().account_folders(a).unwrap();
    let shown: Vec<(&str, u32, bool)> = folders
        .iter()
        .map(|f| (f.mailbox.as_str(), f.depth, f.subscribed))
        .collect();
    // Trash, spam and the folders with a job are not the person's own;
    // Old is there, hidden.
    assert_eq!(
        shown,
        [
            ("Old", 0, false),
            ("Projects", 0, true),
            ("Projects/2026", 1, true)
        ]
    );
    assert_eq!(folders[1].total, 2);
    stored(&store, a, "Projects/2026", 1, &[1]);

    // Renamed offline, with a read waiting in its subfolder: both go, in
    // that order, and the read lands under the new name.
    {
        let s = store.lock().unwrap();
        s.queue_change(a, "Projects/2026", 1, Change::Seen(true))
            .unwrap();
        assert_eq!(s.rename_folder(a, "Projects", "Plans").unwrap(), "Plans");
        s.subscribe_folder(a, "Old", true).unwrap();
    }
    assert_eq!(remote.send_pending(&store, a).await.unwrap(), 0);
    {
        let s = state.lock().unwrap();
        assert!(s.mailboxes.contains_key("Plans"));
        assert!(s.mailboxes.contains_key("Plans/2026"));
        assert!(!s.mailboxes.contains_key("Projects"));
        assert!(s.flags("Plans/2026", 1).contains("\\Seen"));
        assert!(s.mailboxes["Old"].subscribed);
    }
    assert!(store.lock().unwrap().pending_changes(a).unwrap().is_empty());

    // Deleted with its subfolder: their three emails go to Trash first.
    let contents = store.lock().unwrap().folder_contents(a, "Plans").unwrap();
    assert_eq!(contents, (3, 1));
    store.lock().unwrap().delete_folder(a, "Plans").unwrap();
    assert_eq!(remote.send_pending(&store, a).await.unwrap(), 0);
    {
        let s = state.lock().unwrap();
        assert!(!s.mailboxes.contains_key("Plans"));
        assert!(!s.mailboxes.contains_key("Plans/2026"));
        assert_eq!(s.uids("Trash").len(), 5);
    }
    remote.sync_folders(&store, a).await.unwrap();
    let names: Vec<String> = store
        .lock()
        .unwrap()
        .account_folders(a)
        .unwrap()
        .into_iter()
        .map(|f| f.mailbox)
        .collect();
    assert_eq!(names, ["Old"]);
}

#[tokio::test]
async fn a_folder_of_the_persons_choice_does_the_job() {
    let state = mailbox();
    {
        let mut s = state.lock().unwrap();
        s.add("Papierkorb", None, true, 0);
    }
    let cfg = serve(state.clone()).await;
    let (store, a) = store_with_account();
    store
        .lock()
        .unwrap()
        .set_role_choice(a, FolderRole::Trash, Some("Papierkorb"))
        .unwrap();
    stored(&store, a, "INBOX", 1, &[1]);
    let mut remote = connect(&cfg).await;
    remote.sync_folders(&store, a).await.unwrap();
    {
        let s = store.lock().unwrap();
        assert_eq!(s.trash_mailbox(a).unwrap().as_deref(), Some("Papierkorb"));
        // No longer one of the person's own folders.
        assert!(s
            .account_folders(a)
            .unwrap()
            .iter()
            .all(|f| f.mailbox != "Papierkorb"));
        assert!(s
            .server_folders(a)
            .unwrap()
            .contains(&("Papierkorb".into(), "Papierkorb".into())));
        s.set_hidden(a, "INBOX", 1, true).unwrap();
        s.queue_change(a, "INBOX", 1, Change::Move(FolderRole::Trash))
            .unwrap();
    }
    remote.send_pending(&store, a).await.unwrap();
    let s = state.lock().unwrap();
    assert_eq!(s.uids("Papierkorb"), [1]);
    assert_eq!(s.uids("Trash").len(), 2);
}

/// The server rebuilt the inbox while this device was offline: a star, a
/// copy and a deletion queued for it would land on other messages. None
/// is sent, and what they hid is back.
#[tokio::test]
async fn a_renumbered_folder_gets_none_of_the_new_kinds() {
    let state = mailbox();
    state
        .lock()
        .unwrap()
        .mailboxes
        .get_mut("INBOX")
        .unwrap()
        .validity = 2;
    let cfg = serve(state.clone()).await;
    let (store, a) = store_with_account();
    stored(&store, a, "INBOX", 1, &[1, 2, 3]);
    {
        let s = store.lock().unwrap();
        s.queue_flags(&[(a, "INBOX".into(), 1)], true).unwrap();
        s.queue_change(a, "INBOX", 2, Change::CopyTo("Projects".into()))
            .unwrap();
        s.queue_erase(a, "INBOX", &[3]).unwrap();
        assert_eq!(s.messages_in(a, "INBOX").unwrap(), 2);
    }
    let mut remote = connect(&cfg).await;
    assert_eq!(remote.send_pending(&store, a).await.unwrap(), 0);
    let s = state.lock().unwrap();
    for verb in ["UID STORE", "UID COPY", "UID EXPUNGE", "EXPUNGE"] {
        assert_eq!(s.sent(verb), 0, "{verb} sent: {:?}", s.commands);
    }
    assert_eq!(s.uids("Projects").len(), 2);
    let st = store.lock().unwrap();
    assert!(st.pending_changes(a).unwrap().is_empty());
    assert_eq!(st.messages_in(a, "INBOX").unwrap(), 3);
}

/// A busy server refuses the star, the copy, the deletion and the rename
/// twice: they wait, hidden where they hide, and go through later.
#[tokio::test]
async fn a_throttled_server_gets_them_later() {
    let state = mailbox();
    {
        let mut s = state.lock().unwrap();
        // The star and the deletion both store flags: two refusals each.
        for (verb, times) in [("UID STORE", 4), ("UID COPY", 2), ("RENAME", 2)] {
            s.refuse.insert(
                verb,
                std::iter::repeat_n("NO [THROTTLED] Slow down", times).collect(),
            );
        }
    }
    let cfg = serve(state.clone()).await;
    let (store, a) = store_with_account();
    let mut remote = connect(&cfg).await;
    remote.sync_folders(&store, a).await.unwrap();
    stored(&store, a, "INBOX", 1, &[1, 2]);
    stored(&store, a, "Trash", 1, &[1]);
    {
        let s = store.lock().unwrap();
        s.queue_flags(&[(a, "INBOX".into(), 1)], true).unwrap();
        s.queue_change(a, "INBOX", 2, Change::CopyTo("Projects".into()))
            .unwrap();
        s.queue_erase(a, "Trash", &[1]).unwrap();
        s.rename_folder(a, "Old", "Older").unwrap();
    }
    for _ in 0..2 {
        assert_eq!(remote.send_pending(&store, a).await.unwrap(), 0);
        let s = store.lock().unwrap();
        let kinds: Vec<Change> = s
            .pending_changes(a)
            .unwrap()
            .into_iter()
            .map(|p| p.change)
            .collect();
        assert!(
            kinds.contains(&Change::Flag(true)),
            "{kinds:?} {:?}",
            state.lock().unwrap().commands
        );
        assert!(kinds.contains(&Change::CopyTo("Projects".into())));
        assert!(kinds.contains(&Change::Folder(FolderChange::Rename("Older".into()))));
        assert!(s.message(a, "Trash", 1).unwrap().is_some());
        assert_eq!(s.messages_in(a, "Trash").unwrap(), 0, "still hidden");
        s.retry_changes_now(a).unwrap();
    }
    assert_eq!(remote.send_pending(&store, a).await.unwrap(), 0);
    assert!(store.lock().unwrap().pending_changes(a).unwrap().is_empty());
    let s = state.lock().unwrap();
    assert!(s.flags("INBOX", 1).contains("\\Flagged"));
    assert_eq!(s.uids("Projects").len(), 3);
    assert_eq!(s.uids("Trash"), [2]);
    assert!(s.mailboxes.contains_key("Older"));
}

#[tokio::test]
async fn the_server_says_how_full_the_mailbox_is() {
    let cfg = serve(mailbox()).await;
    let mut remote = connect(&cfg).await;
    assert_eq!(
        remote.quota().await.unwrap(),
        Some((900 * 1024, 1000 * 1024))
    );
}
