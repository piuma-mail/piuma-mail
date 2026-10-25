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
use piuma_core::space_sync::{self, Me, Round, SyncError};
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
        password: "test".into(),
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

#[tokio::test]
async fn a_phone_pairs_with_a_code_and_is_unlinked() {
    let Some(cfg) = config() else { return };
    let home = "matteo@posta.it";
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
    let recovery = space_sync::create(
        &mut mac_imap,
        home,
        &mac_store,
        vec![(home.into(), "secret".into())],
        &mac,
    )
    .await
    .unwrap();
    assert_eq!(recovery.phrase().split(' ').count(), 24);
    let shown = space_sync::open(&mut mac_imap, &mac)
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
    assert!(space_sync::found(&mut phone_imap).await.unwrap());
    assert_eq!(
        space_sync::open(&mut phone_imap, &phone)
            .await
            .unwrap_err()
            .to_string(),
        "this device isn't linked to the space"
    );

    // Show code on the phone; the Mac sees the request and types it.
    let code = space::pair_code();
    let pairing = space_sync::request(&mut phone_imap, home, &code, &phone)
        .await
        .unwrap();
    let waiting = space_sync::requests(&mut mac_imap).await.unwrap();
    assert_eq!(waiting.len(), 1);
    assert_eq!(waiting[0].device.name, "Pixel 8");
    space_sync::approve(&mut mac_imap, home, &waiting[0], &code, &mac)
        .await
        .unwrap();
    let (space, passwords) = space_sync::join(
        &mut phone_imap,
        home,
        pairing,
        &phone_store,
        &phone,
        Duration::from_millis(50),
    )
    .await
    .unwrap();
    assert_eq!(space.content.devices.len(), 2);
    {
        let s = phone_store.lock().unwrap();
        let accounts = s.accounts().unwrap();
        assert_eq!(accounts.len(), 2);
        let p = accounts.iter().find(|a| a.email == home).unwrap().id;
        assert_eq!(passwords, [(p, "secret".to_owned())]);
        assert_eq!(s.aliases(p).unwrap(), ["teo@posta.it"]);
        assert_eq!(s.setting("notify.mode").unwrap().as_deref(), Some("all"));
    }
    assert!(space_sync::requests(&mut mac_imap)
        .await
        .unwrap()
        .is_empty());
    assert!(space_sync::open(&mut phone_imap, &phone).await.is_ok());

    // Rounds: a change on the Mac reaches the phone, and nothing bounces
    // back.
    let pw = || vec![(home.to_owned(), "secret".to_owned())];
    let mac_space = space_sync::open(&mut mac_imap, &mac).await.unwrap();
    let mut mac_seen = space_sync::seen(&mac_store, pw(), &mac, &mac_space).unwrap();
    assert_eq!(mac_seen.remote, mac_seen.local);
    let mut phone_seen = space_sync::seen(&phone_store, pw(), &phone, &space).unwrap();
    macro_rules! round {
        ($imap:expr, $store:expr, $me:expr, $seen:expr) => {
            space_sync::round($imap, home, $store, pw(), $me, $seen)
        };
    }
    assert!(matches!(
        round!(&mut mac_imap, &mac_store, &mac, &mac_seen)
            .await
            .unwrap(),
        Round::Same(..)
    ));
    mac_store
        .lock()
        .unwrap()
        .set_setting("notify.mode", "people")
        .unwrap();
    let Round::Pushed(_, seen) = round!(&mut mac_imap, &mac_store, &mac, &mac_seen)
        .await
        .unwrap()
    else {
        panic!("expected a push")
    };
    mac_seen = seen;
    let Round::Took(space, _, gone) = round!(&mut phone_imap, &phone_store, &phone, &phone_seen)
        .await
        .unwrap()
    else {
        panic!("expected the phone to take the change")
    };
    assert!(gone.is_empty());
    phone_seen = space_sync::seen(&phone_store, pw(), &phone, &space).unwrap();
    assert_eq!(
        phone_store
            .lock()
            .unwrap()
            .setting("notify.mode")
            .unwrap()
            .as_deref(),
        Some("people")
    );
    assert!(matches!(
        round!(&mut phone_imap, &phone_store, &phone, &phone_seen)
            .await
            .unwrap(),
        Round::Same(..)
    ));
    assert!(matches!(
        round!(&mut mac_imap, &mac_store, &mac, &mac_seen)
            .await
            .unwrap(),
        Round::Same(..)
    ));
    let about = space_sync::about(&mut phone_imap).await.unwrap().unwrap();
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
    let Round::Pushed(..) = round!(&mut mac_imap, &mac_store, &mac, &mac_seen)
        .await
        .unwrap()
    else {
        panic!("expected a push")
    };
    let Round::Took(space, _, gone) = round!(&mut phone_imap, &phone_store, &phone, &phone_seen)
        .await
        .unwrap()
    else {
        panic!("expected the phone to take the removal")
    };
    let work_here = phone_store
        .lock()
        .unwrap()
        .accounts()
        .unwrap()
        .into_iter()
        .find(|a| a.email == "matteo@studio.it")
        .unwrap()
        .id;
    assert_eq!(gone, [work_here]);
    phone_store
        .lock()
        .unwrap()
        .remove_account(work_here)
        .unwrap();
    phone_seen = space_sync::seen(&phone_store, pw(), &phone, &space).unwrap();
    assert!(matches!(
        round!(&mut phone_imap, &phone_store, &phone, &phone_seen)
            .await
            .unwrap(),
        Round::Same(..)
    ));

    // A wrong code hands nothing over.
    let other = me("Old phone", "phone");
    let pairing = space_sync::request(&mut phone_imap, home, "111111", &other)
        .await
        .unwrap();
    let waiting = space_sync::requests(&mut mac_imap).await.unwrap();
    space_sync::approve(&mut mac_imap, home, &waiting[0], "222222", &mac)
        .await
        .unwrap();
    let answer = space_sync::answer(&mut phone_imap, &pairing)
        .await
        .unwrap()
        .unwrap();
    assert!(pairing.finish(&answer).is_err());

    // "Not me" stops a request.
    let pairing = space_sync::request(&mut phone_imap, home, "333333", &other)
        .await
        .unwrap();
    space_sync::refuse(&mut mac_imap, home, &pairing.request.id)
        .await
        .unwrap();
    assert!(matches!(
        space_sync::answer(&mut phone_imap, &pairing).await,
        Err(SyncError::Refused)
    ));

    // The Mac unlinks the phone: the phone can't open it any more, and the
    // old phrase is gone too.
    let fresh = space_sync::unlink(&mut mac_imap, home, &phone.device.id, &mac)
        .await
        .unwrap();
    assert!(space_sync::open(&mut phone_imap, &phone).await.is_err());
    assert!(matches!(
        round!(&mut phone_imap, &phone_store, &phone, &phone_seen)
            .await
            .unwrap(),
        Round::Unlinked
    ));
    let again = Mutex::new(Store::open_in_memory().unwrap());
    assert!(
        space_sync::recover(&mut phone_imap, home, &recovery.phrase(), &again, &phone)
            .await
            .is_err()
    );
    assert!(
        space_sync::recover(&mut phone_imap, home, &fresh.phrase(), &again, &phone)
            .await
            .is_ok()
    );
    assert_eq!(again.lock().unwrap().accounts().unwrap().len(), 1);

    // The phone turns sync off: the Mac keeps the space and the phrase.
    assert!(!space_sync::leave(&mut phone_imap, home, &phone)
        .await
        .unwrap());
    assert!(space_sync::open(&mut phone_imap, &phone).await.is_err());
    let left = space_sync::open(&mut mac_imap, &mac).await.unwrap();
    assert!(!left.is_linked(&phone.device.id));
    assert_eq!(left.recovery().unwrap().phrase(), fresh.phrase());

    // The hidden folder isn't one of the account's own folders.
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
    assert!(space_sync::leave(&mut mac_imap, home, &mac).await.unwrap());
    assert!(!space_sync::found(&mut mac_imap).await.unwrap());
}
