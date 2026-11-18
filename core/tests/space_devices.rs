//! Two and three devices sharing one sync space, in memory: no network.
//! Each device has its own store; the space's notes live in a shared
//! [Memory] transport, as they would in the mailbox's hidden folder.

use std::sync::Mutex;
use std::time::Duration;

use piuma_core::outbox::Outgoing;
use piuma_core::smtp::{ready, Draft};
use piuma_core::space::{self, Device, Key, Note, Space};
use piuma_core::space_merge::{self, SCHEMA};
use piuma_core::space_sync::{self, Me, Memory, Report, Round, SyncError, Transport};
use piuma_core::{Account, AccountId, AccountKind, Security, Server, Store};

const HOME: &str = "matteo@posta.it";
const WORK: &str = "matteo@studio.it";

struct Dev {
    store: Mutex<Store>,
    me: Me,
}

fn dev(name: &str) -> Dev {
    let secret = Key::generate();
    Dev {
        store: Mutex::new(Store::open_in_memory().unwrap()),
        me: Me {
            device: Device {
                id: space::new_device_id(),
                name: name.into(),
                kind: "laptop".into(),
                last_seen: 0,
                public: space::public_key(&secret),
            },
            secret,
        },
    }
}

fn account(email: &str) -> Account {
    let server = |host: &str, port| Server {
        host: host.into(),
        port,
        security: Security::Tls,
    };
    Account {
        id: AccountId(0),
        name: email.split('@').next().unwrap().into(),
        email: email.into(),
        sender_name: "Matteo".into(),
        color: "#E0782F".into(),
        kind: AccountKind::Imap {
            imap: server("imap.posta.it", 993),
            smtp: server("smtp.posta.it", 465),
            username: email.into(),
        },
    }
}

impl Dev {
    fn add(&self, email: &str) -> AccountId {
        self.store
            .lock()
            .unwrap()
            .add_account(&account(email))
            .unwrap()
    }

    fn id(&self, email: &str) -> Option<AccountId> {
        self.store
            .lock()
            .unwrap()
            .accounts()
            .unwrap()
            .into_iter()
            .find(|a| a.email == email)
            .map(|a| a.id)
    }

    fn set(&self, key: &str, value: &str) {
        self.store.lock().unwrap().set_setting(key, value).unwrap();
    }

    fn get(&self, key: &str) -> Option<String> {
        self.store.lock().unwrap().setting(key).unwrap()
    }

    /// The passwords this device has, by address.
    fn secrets(&self) -> Vec<(String, String)> {
        self.store
            .lock()
            .unwrap()
            .accounts()
            .unwrap()
            .into_iter()
            .map(|a| (a.email.clone(), format!("pw-{}", a.email)))
            .collect()
    }

    /// Stamps what changed here, as the app does a moment after a change.
    fn note(&self) {
        space_sync::dirty(&self.store, &self.secrets(), &self.me).unwrap();
    }

    async fn round(&self, t: &mut Memory) -> Report {
        match space_sync::round(t, &self.store, self.secrets(), &self.me, Some(HOME))
            .await
            .unwrap()
        {
            Round::Done(r) => {
                // Removals the merged state confirmed, as the app does.
                for id in &r.applied.remove {
                    self.store.lock().unwrap().remove_account(*id).unwrap();
                }
                *r
            }
            other => panic!("expected a round, got {other:?}"),
        }
    }
}

/// A space made by `a`, joined by the others with the recovery phrase.
async fn space(devices: &[&Dev]) -> (Memory, Key) {
    let mut t = Memory::new();
    let a = devices[0];
    let recovery = space_sync::create(&mut t, &a.store, a.secrets(), &a.me)
        .await
        .unwrap();
    for d in &devices[1..] {
        space_sync::recover(
            &mut t,
            &recovery.phrase(),
            &d.store,
            d.secrets(),
            &d.me,
            Some(HOME),
        )
        .await
        .unwrap();
    }
    for d in devices {
        d.round(&mut t).await;
    }
    (t, recovery)
}

fn spaces(t: &Memory) -> Vec<(String, Note)> {
    t.snapshot()
        .into_iter()
        .filter(|(_, n)| matches!(n, Note::Space(_)))
        .collect()
}

async fn tick() {
    // Stamps are milliseconds: two writes in a row get different ones.
    tokio::time::sleep(Duration::from_millis(3)).await;
}

#[tokio::test]
async fn changes_to_different_rows_on_two_devices_both_stay() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    a.add(HOME);
    b.add(HOME);
    let (mut t, _) = space(&[&a, &b]).await;
    a.set("appearance.theme", "dark");
    b.set("notify.mode", "people");
    a.note();
    b.note();
    a.round(&mut t).await;
    b.round(&mut t).await;
    a.round(&mut t).await;
    for d in [&a, &b] {
        assert_eq!(d.get("appearance.theme").as_deref(), Some("dark"));
        assert_eq!(d.get("notify.mode").as_deref(), Some("people"));
    }
    // Settled: a round that changes nothing writes nothing.
    assert!(!a.round(&mut t).await.pushed);
    assert_eq!(spaces(&t).len(), 1);
}

#[tokio::test]
async fn on_the_same_row_the_later_change_wins_everywhere() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    a.add(HOME);
    b.add(HOME);
    let (mut t, _) = space(&[&a, &b]).await;
    a.set("appearance.theme", "dark");
    a.note();
    tick().await;
    b.set("appearance.theme", "light");
    b.note();
    // The later change goes first; the earlier one, written after, loses.
    b.round(&mut t).await;
    a.round(&mut t).await;
    b.round(&mut t).await;
    for d in [&a, &b] {
        assert_eq!(d.get("appearance.theme").as_deref(), Some("light"));
    }
}

#[tokio::test]
async fn an_account_added_while_another_device_writes_survives() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    a.add(HOME);
    b.add(HOME);
    let (mut t, _) = space(&[&a, &b]).await;
    // What B saw, before A added an account.
    let before = t.snapshot();

    a.add(WORK);
    a.round(&mut t).await;
    // B, still on the older copy, saves a draft and writes the space: its
    // write takes the place of A's, as two writers racing in the folder.
    b.set("draft.signature.1.Drafts.7", "3");
    b.set("notify.mode", "people");
    let mut stale = Memory::new();
    for (_, n) in &before {
        stale.put(n).await.unwrap();
    }
    b.round(&mut stale).await;
    let old: Vec<String> = t.snapshot().into_iter().map(|(id, _)| id).collect();
    t.remove(&old).await.unwrap();
    for (_, n) in spaces(&stale) {
        t.put(&n).await.unwrap();
    }

    // A's next round: the account is still there, and goes out again.
    let r = a.round(&mut t).await;
    assert!(r.applied.remove.is_empty() && r.applied.held.is_empty());
    assert!(a.id(WORK).is_some());
    assert!(r.pushed);
    b.round(&mut t).await;
    assert!(b.id(WORK).is_some());
    assert_eq!(a.get("notify.mode").as_deref(), Some("people"));
    // A draft's state never travels.
    assert_eq!(a.get("draft.signature.1.Drafts.7"), None);
}

#[tokio::test]
async fn a_removal_on_one_device_reaches_the_others() {
    let (a, b, c) = (dev("Mac"), dev("Pixel"), dev("iPad"));
    for d in [&a, &b, &c] {
        d.add(HOME);
        d.add(WORK);
    }
    let (mut t, _) = space(&[&a, &b, &c]).await;
    let w = a.id(WORK).unwrap();
    a.store.lock().unwrap().remove_account(w).unwrap();
    a.round(&mut t).await;
    let r = b.round(&mut t).await;
    assert_eq!(r.applied.remove.len(), 1);
    assert!(b.id(WORK).is_none());
    c.round(&mut t).await;
    assert!(c.id(WORK).is_none());
    // Nothing comes back.
    for d in [&a, &b, &c] {
        d.round(&mut t).await;
    }
    for d in [&a, &b, &c] {
        assert!(d.id(WORK).is_none());
        assert!(d.id(HOME).is_some());
    }
}

#[tokio::test]
async fn an_account_with_mail_waiting_to_go_is_not_removed_without_asking() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
        d.add(WORK);
    }
    let (mut t, _) = space(&[&a, &b]).await;
    let w_b = b.id(WORK).unwrap();
    let draft = Draft {
        from_email: WORK.into(),
        to: vec!["luca@example.org".into()],
        subject: "Offer".into(),
        body: "Here it is.".into(),
        ..Draft::default()
    };
    b.store
        .lock()
        .unwrap()
        .queue_outgoing(
            &Outgoing {
                account: w_b,
                ready: ready(&draft).unwrap(),
                draft,
                saved: None,
                send_at: None,
            },
            1_000,
        )
        .unwrap();
    let w_a = a.id(WORK).unwrap();
    a.store.lock().unwrap().remove_account(w_a).unwrap();
    a.round(&mut t).await;

    let r = b.round(&mut t).await;
    assert!(r.applied.remove.is_empty());
    assert_eq!(r.applied.held.len(), 1);
    assert_eq!(r.applied.held[0].email, WORK);
    assert_eq!(r.applied.held[0].outbox, 1);
    assert!(b.id(WORK).is_some());
    // Rounds go on without removing it, bringing it back, or writing.
    assert!(!b.round(&mut t).await.pushed);
    assert!(!a.round(&mut t).await.pushed);
    assert!(b.id(WORK).is_some() && a.id(WORK).is_none());

    // The person keeps it: it comes back on the other device.
    space_sync::keep_account(&b.store, w_b).unwrap();
    b.round(&mut t).await;
    a.round(&mut t).await;
    assert!(a.id(WORK).is_some());

    // Removed again, the person confirms: it goes.
    let w_a = a.id(WORK).unwrap();
    a.store.lock().unwrap().remove_account(w_a).unwrap();
    a.round(&mut t).await;
    assert_eq!(b.round(&mut t).await.applied.held.len(), 1);
    space_sync::confirm_removal(&b.store, w_b).unwrap();
    let r = b.round(&mut t).await;
    assert_eq!(r.applied.remove, [w_b]);
    assert!(b.id(WORK).is_none());
}

#[tokio::test]
async fn the_mailbox_that_holds_the_space_is_never_removed_by_a_round() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b]).await;
    let h = a.id(HOME).unwrap();
    a.store.lock().unwrap().remove_account(h).unwrap();
    a.round(&mut t).await;
    let r = b.round(&mut t).await;
    assert!(r.applied.remove.is_empty());
    assert!(r.applied.held[0].home);
    assert!(b.id(HOME).is_some());
}

#[tokio::test]
async fn an_old_copy_put_back_after_an_unlink_is_refused() {
    let (a, b, c) = (dev("Mac"), dev("Pixel"), dev("Old phone"));
    for d in [&a, &b, &c] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b, &c]).await;
    a.set("appearance.theme", "dark");
    a.round(&mut t).await;
    b.round(&mut t).await;
    c.round(&mut t).await;
    // What the old phone keeps: a copy it can open, and its key.
    let (_, Note::Space(old)) = spaces(&t).pop().unwrap() else {
        unreachable!()
    };
    let mut forged = Space::open_as(&old, &c.me.device.id, &c.me.secret).unwrap();

    let gone = space_sync::unlink(&mut t, &a.store, &c.me.device.id, &a.me)
        .await
        .unwrap();
    assert_eq!(gone.exposed, [HOME]);
    a.set("appearance.theme", "light");
    a.round(&mut t).await;
    b.round(&mut t).await;
    assert_eq!(b.get("appearance.theme").as_deref(), Some("light"));
    // The old phone can't open what is there now.
    assert!(matches!(
        space_sync::round(&mut t, &c.store, c.secrets(), &c.me, Some(HOME)).await,
        Ok(Round::Unlinked)
    ));

    // It puts its old copy back, and a forged one with the old key, a
    // higher generation and a later change, which still names every device.
    forged.content.generation = 1_000;
    let theme = forged
        .content
        .tables
        .get_mut("setting")
        .unwrap()
        .values_mut()
        .find(|r| r.v.get("key").and_then(|k| k.as_str()) == Some("appearance.theme"))
        .unwrap();
    theme.v.insert("value".into(), "forged".into());
    theme.s.t = i64::MAX / 2;
    let forged = forged.seal();
    for d in [&a, &b] {
        t.put(&Note::Space(old.clone())).await.unwrap();
        t.put(&Note::Space(forged.clone())).await.unwrap();
        let r = d.round(&mut t).await;
        assert_eq!(r.refused, 2);
        assert_eq!(d.get("appearance.theme").as_deref(), Some("light"));
    }
    // Only old copies left: refused as a whole, nothing taken.
    let all: Vec<String> = spaces(&t).into_iter().map(|(id, _)| id).collect();
    t.remove(&all).await.unwrap();
    t.put(&Note::Space(old)).await.unwrap();
    t.put(&Note::Space(forged)).await.unwrap();
    assert!(matches!(
        space_sync::round(&mut t, &a.store, a.secrets(), &a.me, Some(HOME)).await,
        Err(SyncError::Rollback)
    ));
    assert_eq!(a.get("appearance.theme").as_deref(), Some("light"));
}

#[tokio::test]
async fn a_device_on_an_older_schema_drops_nothing_it_does_not_know() {
    let (a, b) = (dev("New"), dev("Old"));
    a.add(HOME);
    b.add(HOME);
    let (mut t, _) = space(&[&a, &b]).await;
    // A newer build wrote a column and a table this one doesn't know,
    // with the same schema (an addition both can carry).
    let mut s = space_sync::open(&mut t, &a.store, &a.me).await.unwrap();
    let gid = space_merge::account_id(HOME);
    let row = s
        .content
        .tables
        .get_mut("account")
        .unwrap()
        .get_mut(&gid)
        .unwrap();
    row.v.insert("future_column".into(), "kept".into());
    // Written by the newer build, so stamped by it.
    row.s.t = space_merge::now_ms();
    let mut row = s.content.tables["account"][&gid].clone();
    row.v.clear();
    row.v.insert("anything".into(), 1.into());
    s.content
        .tables
        .entry("future_table".into())
        .or_default()
        .insert("x".into(), row);
    s.content
        .extra
        .insert("future_field".into(), serde_json::json!({"a": 1}));
    s.content.generation += 1;
    let ids: Vec<String> = spaces(&t).into_iter().map(|(id, _)| id).collect();
    t.put(&Note::Space(s.seal())).await.unwrap();
    t.remove(&ids).await.unwrap();

    // The older device changes the same account and writes.
    tick().await;
    let h = b.id(HOME).unwrap();
    let mut acc = account(HOME);
    acc.id = h;
    acc.name = "Personal".into();
    b.store.lock().unwrap().update_account(&acc).unwrap();
    b.note();
    assert!(b.round(&mut t).await.pushed);
    let s = space_sync::open(&mut t, &a.store, &a.me).await.unwrap();
    let row = &s.content.tables["account"][&gid];
    assert_eq!(row.v["name"], "Personal");
    assert_eq!(row.v["future_column"], "kept");
    assert!(s.content.tables["future_table"].contains_key("x"));
    assert_eq!(s.content.extra["future_field"]["a"], 1);

    // A newer schema: the older device reads, and writes nothing.
    let mut s = s;
    s.content.schema = SCHEMA + 1;
    s.content.generation += 1;
    let ids: Vec<String> = spaces(&t).into_iter().map(|(id, _)| id).collect();
    t.put(&Note::Space(s.seal())).await.unwrap();
    t.remove(&ids).await.unwrap();
    b.set("notify.mode", "people");
    b.note();
    let before = t.snapshot().len();
    let r = b.round(&mut t).await;
    assert!(r.outdated && !r.pushed);
    assert_eq!(t.snapshot().len(), before);
    assert!(space_sync::state(&b.store).unwrap().unpushed);
}

#[tokio::test]
async fn settings_that_name_an_account_follow_it_across_devices() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    // Added in another order: the same account has another id on each.
    a.add(HOME);
    let w_a = a.add(WORK);
    let w_b = b.add(WORK);
    b.add(HOME);
    assert_ne!(w_a, w_b);
    a.set(&format!("notify.loud.{}", w_a.0), "off");
    a.set(&format!("account.{}.sign_in_alert", w_a.0), "off");
    // What only this device did stays here.
    a.set(&format!("account.{}.junk", w_a.0), "Spam");
    a.set(&format!("rules.sorted.{}", w_a.0), "0");
    let (mut t, _) = space(&[&a, &b]).await;
    b.round(&mut t).await;
    assert_eq!(
        b.get(&format!("notify.loud.{}", w_b.0)).as_deref(),
        Some("off")
    );
    assert_eq!(
        b.get(&format!("account.{}.sign_in_alert", w_b.0))
            .as_deref(),
        Some("off")
    );
    let h_b = b.id(HOME).unwrap();
    assert_eq!(b.get(&format!("notify.loud.{}", h_b.0)), None);
    assert_eq!(b.get(&format!("account.{}.junk", w_b.0)), None);
    assert_eq!(b.get(&format!("rules.sorted.{}", w_b.0)), None);
    // In the space, by global id only.
    let s = space_sync::open(&mut t, &b.store, &b.me).await.unwrap();
    let keys: Vec<String> = s.content.tables["setting"]
        .values()
        .filter(|r| !r.del)
        .map(|r| r.v["key"].as_str().unwrap().to_owned())
        .collect();
    assert!(keys.contains(&format!("notify.loud.@{}", space_merge::account_id(WORK))));
    assert!(!keys.iter().any(|k| k.chars().any(|c| c.is_ascii_digit())
        && k.starts_with("notify.loud.")
        && !k.contains('@')));
}

#[test]
fn a_removed_then_added_account_starts_clean() {
    let store = Store::open_in_memory().unwrap();
    let x = store.add_account(&account(WORK)).unwrap();
    for key in [
        format!("notify.loud.{}", x.0),
        format!("rules.sorted.{}", x.0),
        format!("account.{}.junk", x.0),
        format!("account.{}.sign_in_alert", x.0),
        format!("labels.local.{}", x.0),
        format!("sign_in.told.{}", x.0),
        format!("draft.signature.{}.Drafts.4", x.0),
    ] {
        store.set_setting(&key, "0").unwrap();
    }
    store
        .set_setting(
            "rules.not_now",
            &format!("{} a@b.c Clients\n99 d@e.f Travel", x.0),
        )
        .unwrap();
    store.remove_account(x).unwrap();
    let y = store.add_account(&account("other@posta.it")).unwrap();
    assert_ne!(x, y);
    assert!(y.0 > x.0);
    for key in [
        format!("notify.loud.{}", x.0),
        format!("rules.sorted.{}", x.0),
        format!("account.{}.junk", x.0),
        format!("draft.signature.{}.Drafts.4", x.0),
    ] {
        assert_eq!(store.setting(&key).unwrap(), None, "{key}");
    }
    assert_eq!(
        store.setting("rules.not_now").unwrap().as_deref(),
        Some("99 d@e.f Travel")
    );
    // Even the highest id is never given again.
    store.remove_account(y).unwrap();
    let z = store.add_account(&account(WORK)).unwrap();
    assert!(z.0 > y.0);
}

#[tokio::test]
async fn nothing_printed_shows_a_password() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    a.add(HOME);
    b.add(HOME);
    let (mut t, _) = space(&[&a, &b]).await;
    let r = b.round(&mut t).await;
    let s = space_sync::open(&mut t, &a.store, &a.me).await.unwrap();
    let printed = format!("{r:?} {s:?} {:?} {:?} {:?}", s.content, a.me, t.snapshot());
    assert!(!printed.contains(&format!("pw-{HOME}")), "{printed}");
    // What the device keeps in its database has no password either.
    let local = space_sync::state(&a.store).unwrap();
    let kept = serde_json::to_string(&local).unwrap();
    assert!(!kept.contains(&format!("pw-{HOME}")));
}

#[tokio::test]
async fn passwords_reach_a_new_device_and_follow_a_change() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    a.add(HOME);
    a.add(WORK);
    b.add(HOME);
    let mut t = Memory::new();
    let recovery = space_sync::create(&mut t, &a.store, a.secrets(), &a.me)
        .await
        .unwrap();
    let r = space_sync::recover(
        &mut t,
        &recovery.phrase(),
        &b.store,
        b.secrets(),
        &b.me,
        Some(HOME),
    )
    .await
    .unwrap();
    let w = b.id(WORK).unwrap();
    assert!(r.applied.secrets.iter().any(|s| matches!(
        s,
        piuma_core::store::SecretIn::Account(id, pw) if *id == w && *pw == format!("pw-{WORK}")
    )));
    assert_eq!(r.applied.added, [w]);
}
