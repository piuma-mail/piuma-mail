//! Server search against a small IMAP server inside the test: just enough
//! of RFC 3501 to log in, open a folder, answer `UID SEARCH` (or refuse
//! its charset) and send headers, with every command written down.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use piuma_core::remote::{Remote, ServerFound};
use piuma_core::{Account, AccountId, AccountKind, Query, Security, Server, Store};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;

/// How the server behaves.
#[derive(Default, Clone)]
struct Behaviour {
    /// Offers LITERAL+ (RFC 7888).
    literal_plus: bool,
    /// Answers `NO [BADCHARSET]` to a search with a charset.
    refuse_charset: bool,
    /// Never answers a search.
    stall_search: bool,
    /// What every search finds.
    found: Vec<u32>,
    uid_validity: u32,
}

/// What the server saw.
#[derive(Default)]
struct Seen {
    commands: Vec<String>,
}

struct Mock {
    port: u16,
    seen: Arc<Mutex<Seen>>,
    searched: Arc<tokio::sync::Notify>,
}

impl Mock {
    fn commands(&self, verb: &str) -> Vec<String> {
        self.seen
            .lock()
            .unwrap()
            .commands
            .iter()
            .filter_map(|c| c.split_once(' ').map(|(_, rest)| rest.to_owned()))
            .filter(|c| c.starts_with(verb))
            .collect()
    }
}

fn message(uid: u32) -> (String, String) {
    let header = format!(
        "From: Sara Conti <sara@tipografialume.it>\r\nTo: me@example.org\r\n\
         Subject: Café order {uid}\r\nDate: Mon, 14 Sep 2026 09:00:00 +0000\r\n\
         Message-ID: <{uid}@lume.it>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
    );
    let text = format!("We loved the café, order {uid}.\r\n");
    (header, text)
}

/// The UIDs of a set like `1:3,7`.
fn uid_set(set: &str) -> Vec<u32> {
    let mut out = Vec::new();
    for part in set.split(',') {
        match part.split_once(':') {
            Some((a, b)) => {
                let (a, b): (u32, u32) = (a.parse().unwrap(), b.parse().unwrap());
                out.extend(a.min(b)..=a.max(b));
            }
            None => out.push(part.parse().unwrap()),
        }
    }
    out
}

async fn start(behaviour: Behaviour) -> Mock {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let seen = Arc::new(Mutex::new(Seen::default()));
    let searched = Arc::new(tokio::sync::Notify::new());
    let (shared, notify) = (seen.clone(), searched.clone());
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let (behaviour, seen, notify) = (behaviour.clone(), shared.clone(), notify.clone());
            tokio::spawn(async move {
                let (read, mut write) = tcp.into_split();
                let mut read = BufReader::new(read);
                write.write_all(b"* OK ready\r\n").await.unwrap();
                loop {
                    // One command, with any non-synchronizing literals in it.
                    let mut command = String::new();
                    loop {
                        let mut line = String::new();
                        if read.read_line(&mut line).await.unwrap_or(0) == 0 {
                            return;
                        }
                        let line = line.trim_end_matches(['\r', '\n']).to_owned();
                        command.push_str(&line);
                        let Some(n) = line
                            .strip_suffix("+}")
                            .and_then(|l| l.rsplit_once('{'))
                            .and_then(|(_, n)| n.parse::<usize>().ok())
                        else {
                            break;
                        };
                        let mut literal = vec![0; n];
                        read.read_exact(&mut literal).await.unwrap();
                        command.push_str("\r\n");
                        command.push_str(&String::from_utf8(literal).unwrap());
                    }
                    seen.lock().unwrap().commands.push(command.clone());
                    let (tag, rest) = command.split_once(' ').unwrap();
                    let upper = rest.to_ascii_uppercase();
                    let reply = if upper.starts_with("LOGIN") {
                        format!("{tag} OK logged in\r\n")
                    } else if upper.starts_with("CAPABILITY") {
                        let plus = if behaviour.literal_plus {
                            " LITERAL+"
                        } else {
                            ""
                        };
                        format!("* CAPABILITY IMAP4rev1{plus}\r\n{tag} OK done\r\n")
                    } else if upper.starts_with("EXAMINE") || upper.starts_with("SELECT") {
                        format!(
                            "* 3 EXISTS\r\n* 0 RECENT\r\n* OK [UIDVALIDITY {}] ok\r\n\
                             * FLAGS (\\Seen \\Flagged)\r\n{tag} OK [READ-ONLY] done\r\n",
                            behaviour.uid_validity
                        )
                    } else if upper.starts_with("UID SEARCH") {
                        notify.notify_waiters();
                        if behaviour.stall_search {
                            tokio::time::sleep(Duration::from_secs(3600)).await;
                            return;
                        }
                        if behaviour.refuse_charset && upper.contains("CHARSET") {
                            format!("{tag} NO [BADCHARSET (US-ASCII)] no such charset\r\n")
                        } else {
                            let ids: Vec<String> =
                                behaviour.found.iter().map(u32::to_string).collect();
                            format!("* SEARCH {}\r\n{tag} OK done\r\n", ids.join(" "))
                        }
                    } else if upper.starts_with("UID FETCH") {
                        let set = rest.split(' ').nth(2).unwrap();
                        let mut out = String::new();
                        for uid in uid_set(set) {
                            let (header, text) = message(uid);
                            out.push_str(&format!(
                                "* {uid} FETCH (UID {uid} FLAGS (\\Seen) \
                                 INTERNALDATE \"14-Sep-2026 09:0{}:00 +0000\" \
                                 BODY[HEADER] {{{}}}\r\n{header} BODY[TEXT]<0> {{{}}}\r\n{text})\r\n",
                                uid % 10,
                                header.len(),
                                text.len()
                            ));
                        }
                        format!("{out}{tag} OK done\r\n")
                    } else if upper.starts_with("LOGOUT") {
                        write
                            .write_all(format!("* BYE\r\n{tag} OK bye\r\n").as_bytes())
                            .await
                            .ok();
                        return;
                    } else {
                        format!("{tag} OK done\r\n")
                    };
                    if write.write_all(reply.as_bytes()).await.is_err() {
                        return;
                    }
                }
            });
        }
    });
    Mock {
        port,
        seen,
        searched,
    }
}

fn account(port: u16) -> Account {
    Account {
        id: AccountId(0),
        name: "Work".into(),
        email: "me@example.org".into(),
        sender_name: String::new(),
        color: "#2F8F83".into(),
        kind: AccountKind::Imap {
            imap: Server {
                host: "127.0.0.1".into(),
                port,
                security: Security::None,
            },
            smtp: Server {
                host: "127.0.0.1".into(),
                port: 1,
                security: Security::None,
            },
            username: "me".into(),
        },
    }
}

fn store_with(port: u16) -> (Arc<Mutex<Store>>, Account) {
    let store = Store::open_in_memory().unwrap();
    let mut a = account(port);
    a.id = store.add_account(&a).unwrap();
    (Arc::new(Mutex::new(store)), a)
}

async fn search(store: &Arc<Mutex<Store>>, a: &Account, q: &str) -> ServerFound {
    let mut remote = Remote::open(a, &"secret".into()).await.unwrap();
    let found = remote
        .search_server(store, a, &Query::parse(q), 100)
        .await
        .unwrap();
    remote.close().await;
    found
}

#[tokio::test]
async fn operators_reach_the_server_as_imap_criteria() {
    let mock = start(Behaviour {
        found: vec![],
        uid_validity: 7,
        ..Behaviour::default()
    })
    .await;
    let (store, a) = store_with(mock.port);
    let found = search(
        &store,
        &a,
        r#"from:sara -is:read subject:"q3 report" larger:1k before:2026-10-01 a OR b"#,
    )
    .await;
    assert!(found.asked);
    assert!(found.at.is_empty());
    assert_eq!(
        mock.commands("UID SEARCH"),
        [
            r#"UID SEARCH FROM "sara" NOT (SEEN) SUBJECT "q3 report" LARGER 1024 BEFORE 1-Oct-2026 OR (TEXT "a") (TEXT "b")"#
        ]
    );
    // Folders are only opened to read, never selected.
    assert_eq!(mock.commands("EXAMINE"), [r#"EXAMINE "INBOX""#]);
    assert!(mock.commands("SELECT").is_empty());

    // Terms only this device knows, or only filters: nothing asked.
    let found = search(&store, &a, "in:vault lease").await;
    assert!(!found.asked);
    let found = search(&store, &a, "account:me@example.org").await;
    assert!(!found.asked);
    let found = search(&store, &a, "account:other x").await;
    assert!(!found.asked);
    assert_eq!(mock.commands("UID SEARCH").len(), 1);
}

#[tokio::test]
async fn found_mail_is_fetched_as_headers_kept_and_marked() {
    let mock = start(Behaviour {
        found: vec![2, 5, 9],
        uid_validity: 7,
        ..Behaviour::default()
    })
    .await;
    let (store, a) = store_with(mock.port);
    let found = search(&store, &a, "order").await;
    assert_eq!(
        found.at,
        [
            ("INBOX".to_owned(), 9),
            ("INBOX".to_owned(), 5),
            ("INBOX".to_owned(), 2)
        ]
    );
    assert!(!found.partial);
    assert_eq!(mock.commands("UID FETCH").len(), 1);
    // Now on this device: searchable and listed.
    let local = store
        .lock()
        .unwrap()
        .search(&Query::parse("café order"), 10)
        .unwrap();
    assert_eq!(local.total, 3);
    assert_eq!(local.hits[0].message.subject, "Café order 9");
    assert_eq!(local.hits[0].message.from_email, "sara@tipografialume.it");

    // A second search fetches only what isn't here yet.
    let mock2 = start(Behaviour {
        found: vec![5, 11],
        uid_validity: 7,
        ..Behaviour::default()
    })
    .await;
    let mut b = a.clone();
    if let AccountKind::Imap { imap, .. } = &mut b.kind {
        imap.port = mock2.port;
    }
    let found = search(&store, &b, "order").await;
    assert_eq!(found.at.len(), 2);
    let fetches = mock2.commands("UID FETCH");
    assert_eq!(fetches.len(), 1);
    assert!(fetches[0].starts_with("UID FETCH 11 "), "{}", fetches[0]);

    // The folder renumbered on the server: what the search kept goes,
    // since those numbers now name other messages.
    let mock3 = start(Behaviour {
        found: vec![],
        uid_validity: 8,
        ..Behaviour::default()
    })
    .await;
    if let AccountKind::Imap { imap, .. } = &mut b.kind {
        imap.port = mock3.port;
    }
    search(&store, &b, "order").await;
    assert_eq!(
        store
            .lock()
            .unwrap()
            .search(&Query::parse("order"), 10)
            .unwrap()
            .total,
        0
    );
}

#[tokio::test]
async fn a_refused_charset_falls_back_to_ascii() {
    let mock = start(Behaviour {
        refuse_charset: true,
        found: vec![3],
        uid_validity: 7,
        ..Behaviour::default()
    })
    .await;
    let (store, a) = store_with(mock.port);
    let found = search(&store, &a, "café from:sara").await;
    assert_eq!(
        mock.commands("UID SEARCH"),
        [
            r#"UID SEARCH CHARSET UTF-8 TEXT "café" FROM "sara""#,
            r#"UID SEARCH TEXT "caf" FROM "sara""#,
        ]
    );
    assert_eq!(found.at, [("INBOX".to_owned(), 3)]);
    assert!(found.partial, "the answer may hold more than asked");

    // Nothing ASCII left to ask: no second try, nothing found.
    let found = search(&store, &a, "日本").await;
    assert_eq!(mock.commands("UID SEARCH").len(), 3);
    assert!(found.at.is_empty() && found.partial);

    // ASCII only: no charset, nothing refused.
    let found = search(&store, &a, "invoice").await;
    assert_eq!(
        mock.commands("UID SEARCH").last().unwrap(),
        r#"UID SEARCH TEXT "invoice""#
    );
    assert!(!found.partial);
}

#[tokio::test]
async fn utf8_goes_as_a_literal_where_the_server_takes_one() {
    let mock = start(Behaviour {
        literal_plus: true,
        found: vec![1],
        uid_validity: 7,
        ..Behaviour::default()
    })
    .await;
    let (store, a) = store_with(mock.port);
    let found = search(&store, &a, "città").await;
    assert_eq!(
        mock.commands("UID SEARCH"),
        ["UID SEARCH CHARSET UTF-8 TEXT {6+}\r\ncittà"]
    );
    assert_eq!(found.at.len(), 1);
}

#[tokio::test]
async fn a_search_dropped_midway_stops_and_keeps_nothing() {
    let mock = start(Behaviour {
        stall_search: true,
        found: vec![1],
        uid_validity: 7,
        ..Behaviour::default()
    })
    .await;
    let (store, a) = store_with(mock.port);
    let searched = mock.searched.notified();
    let (s, acc) = (store.clone(), a.clone());
    let task = tokio::spawn(async move {
        let mut remote = Remote::open(&acc, &"secret".into()).await.unwrap();
        remote
            .search_server(&s, &acc, &Query::parse("order"), 100)
            .await
    });
    tokio::time::timeout(Duration::from_secs(10), searched)
        .await
        .expect("the search reached the server");
    // The person typed something else.
    task.abort();
    let ended = tokio::time::timeout(Duration::from_secs(5), task)
        .await
        .expect("the search stops at once");
    assert!(ended.unwrap_err().is_cancelled());
    assert_eq!(
        store
            .lock()
            .unwrap()
            .search(&Query::parse("order"), 10)
            .unwrap()
            .total,
        0
    );
}
