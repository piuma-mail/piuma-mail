//! How the local database holds up as mail piles up: synthetic mailboxes
//! of 10,000, 100,000 and 1,000,000 messages, and how long what the app
//! asks of them takes. Slow and heavy (the largest database is about a
//! gigabyte), so run it on purpose, in release:
//!
//!     cargo test -p piuma-core --release --test scale -- --ignored --nocapture
//!
//! `PIUMA_SCALE=10000,100000` picks other sizes.

use std::time::{Duration, Instant};

use piuma_core::model::ReplyInfo;
use piuma_core::{
    Account, AccountId, AccountKind, Flags, Folder, ListInfo, MessageSummary, Query, Section,
    Security, Server, Store,
};

fn account(name: &str, email: &str) -> Account {
    let server = |host: &str, port| Server {
        host: host.into(),
        port,
        security: Security::Tls,
    };
    Account {
        id: AccountId(0),
        name: name.into(),
        email: email.into(),
        sender_name: name.into(),
        color: "#2F8F83".into(),
        kind: AccountKind::Imap {
            imap: server("imap.example.org", 993),
            smtp: server("smtp.example.org", 465),
            username: email.into(),
        },
    }
}

const DAY: i64 = 86_400;
/// The newest message's time; the mailbox spans three years before it.
const NOW: i64 = 1_790_000_000;

/// Message `i` of `n`: nine in ten in the inbox, the rest sent; one in
/// five a newsletter that takes leave requests by mail; four messages per
/// conversation; 5,000 senders.
fn message(accounts: &[AccountId], i: u32, n: u32) -> MessageSummary {
    let account = accounts[(i % accounts.len() as u32) as usize];
    let sent = i.is_multiple_of(10);
    let letter = !sent && i % 5 == 1;
    let sender = i % 5_000;
    let thread = i / 4;
    let at = NOW - (i64::from(n - i) * 3 * 365 * DAY) / i64::from(n);
    MessageSummary {
        account,
        mailbox: if sent { "Sent".into() } else { "INBOX".into() },
        uid: i + 1,
        from_name: format!("Person {sender}"),
        from_email: if sent {
            "me@example.org".into()
        } else {
            format!("person{sender}@domain{}.example", sender % 700)
        },
        to: "Me".into(),
        subject: format!(
            "Quote {thread} for the {} invoice",
            ["spring", "autumn"][i as usize % 2]
        ),
        preview: "Here is the updated version, with the numbers we spoke about".into(),
        received_at: at,
        flags: Flags {
            seen: !i.is_multiple_of(5),
            ..Flags::default()
        },
        reply: ReplyInfo {
            message_id: format!("<m{i}@example.org>"),
            references: if i.is_multiple_of(4) {
                String::new()
            } else {
                format!("<m{}@example.org>", thread * 4)
            },
            recipients: if sent {
                format!("person{sender}@domain{}.example", sender % 700)
            } else {
                "me@example.org".into()
            },
            ..ReplyInfo::default()
        },
        list: ListInfo {
            newsletter: letter,
            unsubscribe: if letter {
                format!("mailto:leave-{sender}@lists.example")
            } else {
                String::new()
            },
            ..ListInfo::default()
        },
    }
}

/// Runs `f` and returns its result and how long it took.
fn timed<T>(f: impl FnOnce() -> T) -> (T, Duration) {
    let start = Instant::now();
    let out = f();
    (out, start.elapsed())
}

fn ms(d: Duration) -> String {
    format!("{:.1}", d.as_secs_f64() * 1_000.0)
}

fn size(path: &std::path::Path) -> f64 {
    let mut total = 0;
    for suffix in ["", "-wal"] {
        let mut name = path.as_os_str().to_owned();
        name.push(suffix);
        total += std::fs::metadata(&name).map(|m| m.len()).unwrap_or(0);
    }
    total as f64 / 1_048_576.0
}

#[test]
#[ignore]
fn the_database_at_ten_thousand_to_a_million_messages() {
    let sizes: Vec<u32> = std::env::var("PIUMA_SCALE")
        .unwrap_or_else(|_| "10000,100000,1000000".into())
        .split(',')
        .filter_map(|s| s.trim().parse().ok())
        .collect();
    let mut rows = Vec::new();
    for n in sizes {
        let dir = std::env::temp_dir().join(format!("piuma-scale-{n}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let path = dir.join("piuma.db");
        let (mut store, _) = Store::open_file(&path).unwrap();
        let accounts = [
            store
                .add_account(&account("Work", "me@example.org"))
                .unwrap(),
            store
                .add_account(&account("Home", "me@home.example"))
                .unwrap(),
        ];
        for a in accounts {
            store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        }
        let (_, insert) = timed(|| {
            for start in (0..n).step_by(5_000) {
                let batch: Vec<_> = (start..(start + 5_000).min(n))
                    .map(|i| message(&accounts, i, n))
                    .collect();
                store.upsert_messages(&batch).unwrap();
            }
        });
        // Whole messages for the newest ones, as reading them leaves.
        let cached = (n / 100).min(5_000);
        for i in (n - cached)..n {
            let m = message(&accounts, i, n);
            store
                .set_body(
                    m.account,
                    &m.mailbox,
                    m.uid,
                    &"Words of a long message. ".repeat(80),
                )
                .unwrap();
        }
        store.maintain_all().unwrap();
        let reader = Store::open_reader(&path).unwrap();
        let inbox = |offset, limit| {
            reader
                .conversations_page(Folder::Inbox, None, Section::All, offset, limit)
                .unwrap()
        };
        let (count, count_first) = timed(|| {
            reader
                .conversation_count(Folder::Inbox, None, Section::All)
                .unwrap()
        });
        let (_, count_again) = timed(|| {
            reader
                .conversation_count(Folder::Inbox, None, Section::All)
                .unwrap()
        });
        let (_, unread) = timed(|| {
            reader
                .unread_count(Folder::Inbox, None, Section::All)
                .unwrap()
        });
        let (_, people) = timed(|| {
            reader
                .conversation_count(Folder::Inbox, None, Section::People)
                .unwrap()
        });
        let (first, first_page) = timed(|| inbox(0, 100));
        assert_eq!(first.len(), 100);
        // Scrolling down 50 pages one after the other: each starts where
        // the last ended.
        let (_, scroll) = timed(|| {
            for page in 1..=50u32 {
                inbox(page * 100, 100);
            }
        });
        // A jump to the middle, then the page after it.
        let middle = count / 2;
        let (_, jump) = timed(|| inbox(middle, 100));
        let (_, next) = timed(|| inbox(middle + 100, 100));
        let (found, search) = timed(|| reader.search(&Query::parse("autumn invoice"), 50).unwrap());
        assert!(found.total > 0);
        let (_, waiting) = timed(|| store.waiting(None, NOW).unwrap());
        let (_, sender) = timed(|| reader.from_sender("person42@domain42.example", 20).unwrap());
        let (_, stats) = timed(|| {
            reader
                .sender_stats("person42@domain42.example", NOW - 90 * DAY)
                .unwrap()
        });
        let newest = message(&accounts, n - 2, n);
        let (_, warning) = timed(|| {
            store
                .sender_warning(newest.account, &newest.mailbox, newest.uid)
                .unwrap()
        });
        let (_, warning_again) = timed(|| {
            store
                .sender_warning(newest.account, &newest.mailbox, newest.uid)
                .unwrap()
        });
        let (_, hide) = timed(|| {
            store
                .set_hidden(newest.account, "INBOX", newest.uid, true)
                .unwrap()
        });
        let (_, unhide) = timed(|| store.unhide_all().unwrap());
        let before = size(&path);
        let (_, clean_up) = timed(|| {
            // Keep a week: most cached bodies go.
            store.set_keep_bodies_days(Some(7)).unwrap();
            store.queue_body_clean_up(NOW).unwrap();
            store.maintain_all().unwrap();
        });
        let (_, compact) = timed(|| store.compact().unwrap());
        let after = size(&path);
        let (longest, remove) = timed(|| {
            store.start_removing_account(accounts[1]).unwrap();
            let mut longest = Duration::ZERO;
            loop {
                let (more, step) = timed(|| store.maintain().unwrap());
                longest = longest.max(step);
                if !more {
                    break;
                }
            }
            longest
        });
        rows.push(format!(
            "| {n} | {:.0} | {} / {} | {} | {} | {} | {} | {} / {} | {} | {} | {} | {} | {} / {} | {} | {} | {:.0} → {:.0} | {} | {} | {} / {} ms longest step |",
            f64::from(n) / insert.as_secs_f64(),
            ms(count_first),
            ms(count_again),
            ms(unread),
            ms(people),
            ms(first_page),
            ms(scroll / 50),
            ms(jump),
            ms(next),
            ms(search),
            ms(waiting),
            ms(sender),
            ms(stats),
            ms(warning),
            ms(warning_again),
            ms(hide),
            ms(unhide),
            before,
            after,
            ms(clean_up),
            ms(compact),
            ms(remove),
            ms(longest),
        ));
        drop((reader, store));
        let _ = std::fs::remove_dir_all(&dir);
    }
    println!(
        "| messages | stored/s | count first / again ms | unread ms | People count ms | first page ms | next page ms | jump to middle / page after ms | search ms | Waiting ms | sender's mail ms | sender stats ms | impostor check first / again ms | hide ms | unhide all ms | MB before → after clean-up | clean-up ms | compact ms | remove account |"
    );
    println!("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
    for row in rows {
        println!("{row}");
    }
}
