//! The sync space against a real IMAP server: a Mac turns sync on, a
//! phone pairs with a code, then the Mac unlinks it.
//!
//! Start one with `tools/test-imap-server.sh`, then:
//!     PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test
//! Without PIUMA_TEST_IMAP these tests pass without doing anything.

use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use piuma_core::imap::{Connection, ImapConfig};
use piuma_core::remote::Remote;
use piuma_core::space::{self, Device, Key};
use piuma_core::space_sync::{self, Folder, Me, Report, Round, SyncError};
use piuma_core::{Account, AccountId, AccountKind, Security, Server, Store};

fn config() -> Option<ImapConfig> {
    let addr = std::env::var("PIUMA_TEST_IMAP").ok()?;
    let (host, port) = addr.rsplit_once(':')?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    Some(ImapConfig {
        host: host.to_owned(),
        port: port.parse().ok()?,
        security: Security::None,
        username: format!("space-{stamp}"),
        login: "test".into(),
    })
}

fn me(name: &str, kind: &str) -> Me {
    let secret = Key::generate();
    Me {
        device: Device {
            id: space::new_device_id(),
            name: name.into(),
            kind: kind.into(),
            last_seen: 0,
            public: space::public_key(&secret),
            sign: space::sign_public(&secret),
        },
        secret,
    }
}

fn account(email: &str) -> Account {
    let server = |port| Server {
        host: "localhost".into(),
        port,
        security: Security::None,
    };
    Account {
        id: AccountId(0),
        name: "Personal".into(),
        email: email.into(),
        sender_name: "Matteo".into(),
        color: "#E0782F".into(),
        kind: AccountKind::Imap {
            imap: server(31143),
            smtp: server(465),
            username: "me".into(),
        },
    }
}

/// One round as the app runs it: removals the merged state confirmed are
/// carried out.
async fn round(
    folder: &mut Folder<'_>,
    store: &Mutex<Store>,
    pw: Vec<(String, String)>,
    me: &Me,
    home: &str,
) -> Report {
    match space_sync::round(folder, store, pw, me, Some(home))
        .await
        .unwrap()
    {
        Round::Done(r) => {
            for id in &r.applied.remove {
                store.lock().unwrap().remove_account(*id).unwrap();
            }
            *r
        }
        other => panic!("expected a round, got {other:?}"),
    }
}

#[tokio::test]
async fn a_phone_pairs_with_a_code_and_is_unlinked() {
    let Some(cfg) = config() else { return };
    let home = "matteo@posta.it";
    let pw = || vec![(home.to_owned(), "secret".to_owned())];
    let mac_store = Mutex::new(Store::open_in_memory().unwrap());
    {
        let s = mac_store.lock().unwrap();
        let p = s.add_account(&account(home)).unwrap();
        s.add_account(&Account {
            name: "Work".into(),
            ..account("matteo@studio.it")
        })
        .unwrap();
        s.add_alias(p, "teo@posta.it").unwrap();
        s.set_setting("notify.mode", "all").unwrap();
    }
    let mac = me("Matteo's MacBook", "laptop");
    let mut mac_imap = Remote::Imap(Connection::open(&cfg).await.unwrap());
    let mut mac_f = Folder::new(&mut mac_imap, home);
    let recovery = space_sync::create(&mut mac_f, &mac_store, pw(), &mac)
        .await
        .unwrap();
    assert_eq!(recovery.phrase().split(' ').count(), 24);
    let shown = space_sync::open(&mut mac_f, &mac_store, &mac)
        .await
        .unwrap()
        .recovery();
    assert_eq!(shown.unwrap().phrase(), recovery.phrase());

    // The phone signs in to the same mailbox and finds the space.
    let phone = me("Pixel 8", "phone");
    let phone_store = Mutex::new(Store::open_in_memory().unwrap());
    phone_store
        .lock()
        .unwrap()
        .add_account(&account(home))
        .unwrap();
    let mut phone_imap = Remote::Imap(Connection::open(&cfg).await.unwrap());
    let mut phone_f = Folder::new(&mut phone_imap, home);
    assert!(space_sync::found(&mut phone_f).await.unwrap());
    // What the provider can read names no device.
    let about = space_sync::about(&mut phone_f).await.unwrap().unwrap();
    assert!(about.devices.iter().all(|d| d.name.is_empty()));
    // It trusts nothing it finds until it pairs (or types the phrase).
    assert_eq!(
        space_sync::open(&mut phone_f, &phone_store, &phone)
            .await
            .unwrap_err()
            .to_string(),
        "this device must be confirmed with the recovery phrase or a code"
    );

    // Show code on the phone; the Mac sees the request and types it.
    let code = space::pair_code();
    let pairing = space_sync::request(&mut phone_f, &code, &phone)
        .await
        .unwrap();
    let waiting = space_sync::requests(&mut mac_f).await.unwrap();
    assert_eq!(waiting.len(), 1);
    assert_eq!(waiting[0].device.name, "Pixel 8");
    space_sync::approve(&mut mac_f, &mac_store, &waiting[0], &code, &mac)
        .await
        .unwrap();
    let joined = space_sync::join(
        &mut phone_f,
        pairing,
        &phone_store,
        pw(),
        &phone,
        Some(home),
        Duration::from_millis(50),
    )
    .await
    .unwrap();
    assert_eq!(joined.space.content.devices.len(), 2);
    {
        let s = phone_store.lock().unwrap();
        let accounts = s.accounts().unwrap();
        assert_eq!(accounts.len(), 2);
        let p = accounts.iter().find(|a| a.email == home).unwrap().id;
        assert_eq!(s.aliases(p).unwrap(), ["teo@posta.it"]);
        assert_eq!(s.setting("notify.mode").unwrap().as_deref(), Some("all"));
    }
    assert!(space_sync::requests(&mut mac_f).await.unwrap().is_empty());
    assert!(space_sync::open(&mut phone_f, &phone_store, &phone)
        .await
        .is_ok());

    // Rounds: a change on the Mac reaches the phone, and nothing bounces
    // back.
    assert!(!round(&mut mac_f, &mac_store, pw(), &mac, home).await.pushed);
    mac_store
        .lock()
        .unwrap()
        .set_setting("notify.mode", "people")
        .unwrap();
    assert!(round(&mut mac_f, &mac_store, pw(), &mac, home).await.pushed);
    let r = round(&mut phone_f, &phone_store, pw(), &phone, home).await;
    assert!(r.applied.took && r.applied.remove.is_empty());
    assert_eq!(
        phone_store
            .lock()
            .unwrap()
            .setting("notify.mode")
            .unwrap()
            .as_deref(),
        Some("people")
    );
    assert!(
        !round(&mut phone_f, &phone_store, pw(), &phone, home)
            .await
            .pushed
    );
    assert!(!round(&mut mac_f, &mac_store, pw(), &mac, home).await.pushed);
    let about = space_sync::about(&mut phone_f).await.unwrap().unwrap();
    assert_eq!((about.accounts, about.devices.len()), (2, 2));

    // An account removed on the Mac leaves the phone too.
    {
        let s = mac_store.lock().unwrap();
        let work = s
            .accounts()
            .unwrap()
            .into_iter()
            .find(|a| a.email == "matteo@studio.it")
            .unwrap();
        s.remove_account(work.id).unwrap();
    }
    assert!(round(&mut mac_f, &mac_store, pw(), &mac, home).await.pushed);
    let r = round(&mut phone_f, &phone_store, pw(), &phone, home).await;
    assert_eq!(r.applied.remove.len(), 1);
    assert!(phone_store
        .lock()
        .unwrap()
        .accounts()
        .unwrap()
        .iter()
        .all(|a| a.email != "matteo@studio.it"));
    round(&mut phone_f, &phone_store, pw(), &phone, home).await;

    // A wrong code hands nothing over.
    let other = me("Old phone", "phone");
    let pairing = space_sync::request(&mut phone_f, "111111", &other)
        .await
        .unwrap();
    let waiting = space_sync::requests(&mut mac_f).await.unwrap();
    space_sync::approve(&mut mac_f, &mac_store, &waiting[0], "222222", &mac)
        .await
        .unwrap();
    let answer = space_sync::answer(&mut phone_f, &pairing)
        .await
        .unwrap()
        .unwrap();
    assert!(pairing.finish(&answer).is_err());

    // "Not me" stops a request.
    let pairing = space_sync::request(&mut phone_f, "333333", &other)
        .await
        .unwrap();
    space_sync::refuse(&mut mac_f, &pairing.request.id)
        .await
        .unwrap();
    assert!(matches!(
        space_sync::answer(&mut phone_f, &pairing).await,
        Err(SyncError::Refused)
    ));

    // The Mac unlinks the phone: the phone can't open it any more, the old
    // phrase is gone too, and the Mac is told which passwords the phone
    // still knows.
    let gone = space_sync::unlink(&mut mac_f, &mac_store, &phone.device.id, &mac)
        .await
        .unwrap();
    assert_eq!(gone.exposed, [home]);
    assert!(space_sync::open(&mut phone_f, &phone_store, &phone)
        .await
        .is_err());
    assert!(matches!(
        space_sync::round(&mut phone_f, &phone_store, pw(), &phone, Some(home))
            .await
            .unwrap(),
        Round::Unlinked(_)
    ));
    let again = Mutex::new(Store::open_in_memory().unwrap());
    assert!(space_sync::recover(
        &mut phone_f,
        &recovery.phrase(),
        &again,
        pw(),
        &phone,
        Some(home)
    )
    .await
    .is_err());
    assert!(space_sync::recover(
        &mut phone_f,
        &gone.recovery.phrase(),
        &again,
        pw(),
        &phone,
        Some(home)
    )
    .await
    .is_ok());
    assert_eq!(again.lock().unwrap().accounts().unwrap().len(), 1);

    // The phone turns sync off: the Mac keeps the space, and on its next
    // round changes the key and the phrase the phone knew.
    assert!(!space_sync::leave(&mut phone_f, &again, &phone)
        .await
        .unwrap());
    assert!(space_sync::open(&mut phone_f, &again, &phone)
        .await
        .is_err());
    let Round::Done(r) = space_sync::round(&mut mac_f, &mac_store, pw(), &mac, Some(home))
        .await
        .unwrap()
    else {
        panic!("expected a round")
    };
    assert_eq!(r.refused, 0);
    assert!(r.recovery_changed);
    assert!(!r.space.is_linked(&phone.device.id));
    assert_ne!(r.space.recovery().unwrap().phrase(), gone.recovery.phrase());

    // The hidden folder isn't one of the account's own folders.
    drop(mac_f);
    let a = mac_store.lock().unwrap().accounts().unwrap()[0].id;
    mac_imap.sync_folders(&mac_store, a).await.unwrap();
    assert!(mac_store
        .lock()
        .unwrap()
        .account_folders(a)
        .unwrap()
        .iter()
        .all(|f| f.mailbox != space::FOLDER));

    // The last device turns sync off: the space leaves the mailbox.
    let mut mac_f = Folder::new(&mut mac_imap, home);
    assert!(space_sync::leave(&mut mac_f, &mac_store, &mac)
        .await
        .unwrap());
    assert!(!space_sync::found(&mut mac_f).await.unwrap());
}
