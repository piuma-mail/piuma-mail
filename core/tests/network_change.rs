//! A network change makes the IMAP watcher start over at once. A test
//! binary of its own: the change reaches every watcher in the process.
//!
//! Needs the test server: `sh tools/test-imap-server.sh`, then
//! `PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test`.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use piuma_core::imap::{watch, ImapConfig, WatchEvent};
use piuma_core::{Account, AccountId, AccountKind, Security, Server, Store};

#[tokio::test]
async fn a_new_network_brings_a_fresh_sync_at_once() {
    let Ok(addr) = std::env::var("PIUMA_TEST_IMAP") else {
        return;
    };
    let (host, port) = addr.rsplit_once(':').unwrap();
    let cfg = ImapConfig {
        host: host.into(),
        port: port.parse().unwrap(),
        security: Security::None,
        username: format!(
            "network-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis()
        ),
        password: "test".into(),
    };
    let store = Store::open_in_memory().unwrap();
    let account = store
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
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let task = tokio::spawn(watch(
        cfg,
        Arc::new(Mutex::new(store)),
        account,
        "INBOX".into(),
        move |e| {
            tx.send(e).ok();
        },
    ));
    let synced = |e: &WatchEvent| matches!(e, WatchEvent::Synced { .. });
    loop {
        let e = tokio::time::timeout(Duration::from_secs(10), rx.recv())
            .await
            .expect("no first sync")
            .unwrap();
        if synced(&e) {
            break;
        }
    }
    // In IDLE now, with nothing to report for minutes.
    tokio::time::sleep(Duration::from_millis(300)).await;
    let started = Instant::now();
    piuma_core::network::changed();
    loop {
        let e = tokio::time::timeout(Duration::from_secs(3), rx.recv())
            .await
            .expect("no sync after the network changed")
            .unwrap();
        assert!(
            !matches!(e, WatchEvent::Offline { .. }),
            "a network change is not being offline: {e:?}"
        );
        if synced(&e) {
            break;
        }
    }
    assert!(started.elapsed() < Duration::from_secs(2));
    task.abort();
}
