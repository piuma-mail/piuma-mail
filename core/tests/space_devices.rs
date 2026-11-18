//! Two and three devices sharing one sync space, in memory: no network.
//! Each device has its own store; the space's notes live in a shared
//! [Memory] transport, as they would in the mailbox's hidden folder.

use std::sync::Mutex;
use std::time::Duration;

use piuma_core::groups::AddressGroup;
use piuma_core::outbox::Outgoing;
use piuma_core::signature::Signature;
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
                sign: space::sign_public(&secret),
                by: String::new(),
                vouch: Vec::new(),
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
                undo: false,
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
    // Signed by the old phone, which still knows its own key.
    let forged = forged.seal(&c.me.device.id, &c.me.secret);
    for d in [&a, &b] {
        t.put(&Note::Space(old.clone())).await.unwrap();
        t.put(&Note::Space(forged.clone())).await.unwrap();
        let r = d.round(&mut t).await;
        assert_eq!(r.refused, 2);
        assert_eq!(d.get("appearance.theme").as_deref(), Some("light"));
    }
    // Only old copies left: refused as a whole, nothing taken, and the
    // newest copy A took goes back in their place.
    a.round(&mut t).await;
    let all: Vec<String> = spaces(&t).into_iter().map(|(id, _)| id).collect();
    t.remove(&all).await.unwrap();
    t.put(&Note::Space(old)).await.unwrap();
    t.put(&Note::Space(forged)).await.unwrap();
    assert!(matches!(
        space_sync::round(&mut t, &a.store, a.secrets(), &a.me, Some(HOME)).await,
        Err(SyncError::Rollback)
    ));
    assert_eq!(a.get("appearance.theme").as_deref(), Some("light"));
    assert_eq!(spaces(&t).len(), 1);
    let r = b.round(&mut t).await;
    assert_eq!(r.refused, 0);
    assert_eq!(b.get("appearance.theme").as_deref(), Some("light"));
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
    t.put(&Note::Space(s.seal(&a.me.device.id, &a.me.secret)))
        .await
        .unwrap();
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
    t.put(&Note::Space(s.seal(&a.me.device.id, &a.me.secret)))
        .await
        .unwrap();
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

/// The space's newest copy, opened by `d`.
async fn open(t: &mut Memory, d: &Dev) -> Space {
    space_sync::open(t, &d.store, &d.me).await.unwrap()
}

/// Replaces the stored copies with `space`, signed by `d`.
async fn replace(t: &mut Memory, space: &Space, d: &Dev) {
    let ids: Vec<String> = spaces(t).into_iter().map(|(id, _)| id).collect();
    t.put(&Note::Space(space.seal(&d.me.device.id, &d.me.secret)))
        .await
        .unwrap();
    t.remove(&ids).await.unwrap();
}

/// A copy of what the folder holds, as another view of it.
async fn fork(t: &Memory) -> Memory {
    let mut m = Memory::new();
    for (_, n) in t.snapshot() {
        m.put(&n).await.unwrap();
    }
    m
}

fn linked(t: &Memory, d: &Dev) -> Vec<String> {
    let Some((_, Note::Space(s))) = spaces(t).pop() else {
        return Vec::new();
    };
    match Space::open_as(&s, &d.me.device.id, &d.me.secret) {
        Ok(s) => s.content.devices.into_iter().map(|d| d.name).collect(),
        Err(_) => Vec::new(),
    }
}

#[tokio::test]
async fn two_devices_unlinking_at_once_lock_nobody_else_out() {
    let (a, b, e, f) = (
        dev("Mac"),
        dev("Pixel"),
        dev("Old phone"),
        dev("Old tablet"),
    );
    for d in [&a, &b, &e, &f] {
        d.add(HOME);
    }
    let (t, _) = space(&[&a, &b, &e, &f]).await;
    // A unlinks the old phone while B, from the same copy, unlinks the old
    // tablet: two copies of the same generation, with two new keys.
    let (mut ta, mut tb) = (fork(&t).await, fork(&t).await);
    space_sync::unlink(&mut ta, &a.store, &e.me.device.id, &a.me)
        .await
        .unwrap();
    space_sync::unlink(&mut tb, &b.store, &f.me.device.id, &b.me)
        .await
        .unwrap();
    let mut t = Memory::new();
    for m in [&ta, &tb] {
        for (_, n) in spaces(m) {
            t.put(&n).await.unwrap();
        }
    }
    a.set("appearance.theme", "dark");
    let r = a.round(&mut t).await;
    assert_eq!(r.refused, 0);
    assert!(r.recovery_changed);
    b.set("notify.mode", "people");
    b.round(&mut t).await;
    a.round(&mut t).await;
    for d in [&a, &b] {
        assert_eq!(d.get("appearance.theme").as_deref(), Some("dark"));
        assert_eq!(d.get("notify.mode").as_deref(), Some("people"));
    }
    let mut names = linked(&t, &a);
    names.sort();
    assert_eq!(names, ["Mac", "Pixel"]);
    // Neither unlinked device opens the space, though each knew one of
    // the two new keys.
    for d in [&e, &f] {
        assert!(matches!(
            space_sync::round(&mut t, &d.store, d.secrets(), &d.me, Some(HOME)).await,
            Ok(Round::Unlinked)
        ));
    }
}

#[tokio::test]
async fn a_device_that_missed_an_unlink_is_not_taken_over() {
    let (a, b, c) = (dev("Mac"), dev("Pixel"), dev("Old phone"));
    for d in [&a, &b, &c] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b, &c]).await;
    // What the old phone keeps from before.
    let mut forged = open(&mut t, &c).await;
    // B is away; A unlinks the old phone and changes something.
    space_sync::unlink(&mut t, &a.store, &c.me.device.id, &a.me)
        .await
        .unwrap();
    a.set("appearance.theme", "light");
    a.round(&mut t).await;
    // The old phone writes, with the old key, for every device it knew,
    // claiming a generation far ahead and the same setting.
    forged.content.generation += 50;
    let theme = space_merge::natural_id(
        space_merge::spec("setting").unwrap(),
        &serde_json::json!({"key": "appearance.theme"})
            .as_object()
            .unwrap()
            .clone(),
    )
    .unwrap();
    let mut v = serde_json::Map::new();
    v.insert("key".into(), "appearance.theme".into());
    v.insert("value".into(), "forged".into());
    forged
        .content
        .tables
        .entry("setting".into())
        .or_default()
        .insert(
            theme,
            space_merge::Row {
                s: space_merge::Stamp {
                    t: space_merge::now_ms() + 1_000,
                    c: 0,
                    d: c.me.device.id.clone(),
                },
                del: false,
                v,
            },
        );
    t.put(&Note::Space(forged.seal(&c.me.device.id, &c.me.secret)))
        .await
        .unwrap();
    // B comes back: A's signed unlink keeps the old phone out, whatever its
    // copy claims.
    let r = b.round(&mut t).await;
    assert_eq!(r.refused, 1);
    assert_eq!(b.get("appearance.theme").as_deref(), Some("light"));
    // And from then on, at any generation.
    forged.content.generation += 1_000;
    t.put(&Note::Space(forged.seal(&c.me.device.id, &c.me.secret)))
        .await
        .unwrap();
    assert_eq!(b.round(&mut t).await.refused, 1);
    assert_eq!(b.get("appearance.theme").as_deref(), Some("light"));
}

#[tokio::test]
async fn a_copy_claiming_a_far_generation_is_refused_and_the_folder_heals() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b]).await;
    a.set("appearance.theme", "dark");
    a.round(&mut t).await;
    b.round(&mut t).await;
    // Even signed by a linked device, a jump past the bound is refused.
    let mut far = open(&mut t, &a).await;
    far.content.generation += space_piuma_jump();
    replace(&mut t, &far, &a).await;
    assert!(matches!(
        space_sync::round(&mut t, &b.store, b.secrets(), &b.me, Some(HOME)).await,
        Err(SyncError::Rollback)
    ));
    // B put back the newest copy it took: A reads it again.
    assert!(a.round(&mut t).await.refused == 0);
}

fn space_piuma_jump() -> u64 {
    piuma_core::space_trust::MAX_JUMP + 10
}

#[tokio::test]
async fn a_folder_left_with_an_older_copy_heals() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b]).await;
    let before = spaces(&t);
    a.set("appearance.theme", "dark");
    a.round(&mut t).await;
    // The provider serves the older copy only.
    let all: Vec<String> = spaces(&t).into_iter().map(|(id, _)| id).collect();
    t.remove(&all).await.unwrap();
    for (_, n) in before {
        t.put(&n).await.unwrap();
    }
    assert!(matches!(
        space_sync::round(&mut t, &a.store, a.secrets(), &a.me, Some(HOME)).await,
        Err(SyncError::Rollback)
    ));
    // A put its newest copy back: B takes the change.
    b.round(&mut t).await;
    assert_eq!(b.get("appearance.theme").as_deref(), Some("dark"));
}

#[tokio::test]
async fn a_clock_far_ahead_does_not_win_every_write() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b]).await;
    a.set("appearance.theme", "dark");
    a.round(&mut t).await;
    // A's clock is a year ahead: its row says so.
    let mut s = open(&mut t, &a).await;
    for r in s.content.tables.get_mut("setting").unwrap().values_mut() {
        r.s.t += 365 * 86_400 * 1000;
    }
    s.content.generation += 1;
    replace(&mut t, &s, &a).await;
    // B changes the same setting afterwards: its change wins.
    tick().await;
    b.set("appearance.theme", "light");
    b.round(&mut t).await;
    a.round(&mut t).await;
    for d in [&a, &b] {
        assert_eq!(d.get("appearance.theme").as_deref(), Some("light"));
    }
    // No stamp in the space is far ahead any more.
    let limit = space_merge::now_ms() + space_merge::MAX_SKEW;
    let s = open(&mut t, &a).await;
    assert!(s
        .content
        .tables
        .values()
        .flat_map(|t| t.values())
        .all(|r| r.s.t <= limit));
}

#[tokio::test]
async fn a_device_away_past_the_horizon_brings_no_removed_row_back() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    b.set("appearance.theme", "dark");
    let (mut t, _) = space(&[&b, &a]).await;
    assert_eq!(a.get("appearance.theme").as_deref(), Some("dark"));
    // B goes away. A removes the setting; long after, the tombstone is
    // dropped and the space records the horizon.
    a.store
        .lock()
        .unwrap()
        .remove_setting("appearance.theme")
        .unwrap();
    a.round(&mut t).await;
    let mut s = open(&mut t, &a).await;
    for table in s.content.tables.values_mut() {
        table.retain(|_, r| !r.del);
    }
    s.content.horizon = space_merge::now_ms();
    s.content.generation += 1;
    replace(&mut t, &s, &a).await;
    // B comes back: it removes the setting instead of writing it back.
    tick().await;
    b.round(&mut t).await;
    a.round(&mut t).await;
    assert_eq!(b.get("appearance.theme"), None);
    assert_eq!(a.get("appearance.theme"), None);
}

/// A folder that takes nothing new: the device stops between putting
/// rows in and writing.
struct Broken(Memory);

impl Transport for Broken {
    async fn notes(&mut self) -> space_sync::Result<Vec<(String, Note)>> {
        self.0.notes().await
    }

    async fn put(&mut self, _: &Note) -> space_sync::Result<()> {
        Err(SyncError::NoSpace)
    }

    async fn remove(&mut self, ids: &[String]) -> space_sync::Result<()> {
        self.0.remove(ids).await
    }
}

#[tokio::test]
async fn stopping_between_taking_rows_in_and_writing_loses_nothing() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b]).await;
    a.set("appearance.theme", "dark");
    a.round(&mut t).await;
    // B takes A's change in, then can't write (killed, offline).
    b.set("notify.mode", "people");
    let mut broken = Broken(t.clone());
    assert!(
        space_sync::round(&mut broken, &b.store, b.secrets(), &b.me, Some(HOME))
            .await
            .is_err()
    );
    assert_eq!(b.get("appearance.theme").as_deref(), Some("dark"));
    // Next time, what came from A is not taken for B's own change.
    b.round(&mut t).await;
    let s = open(&mut t, &a).await;
    let theme = s.content.tables["setting"]
        .values()
        .find(|r| r.v.get("key").and_then(|k| k.as_str()) == Some("appearance.theme"))
        .unwrap();
    assert_eq!(theme.s.d, a.me.device.id);
    a.round(&mut t).await;
    assert_eq!(a.get("notify.mode").as_deref(), Some("people"));
}

#[tokio::test]
async fn a_device_away_through_many_unlinks_still_follows() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let (mut t, mut phrase) = space(&[&a, &b]).await;
    // B is away while twenty devices come and are unlinked, each changing
    // the key.
    for i in 0..20 {
        let x = dev(&format!("Phone {i}"));
        x.add(HOME);
        space_sync::recover(
            &mut t,
            &phrase.phrase(),
            &x.store,
            x.secrets(),
            &x.me,
            Some(HOME),
        )
        .await
        .unwrap();
        phrase = space_sync::unlink(&mut t, &a.store, &x.me.device.id, &a.me)
            .await
            .unwrap()
            .recovery;
    }
    a.set("appearance.theme", "dark");
    a.round(&mut t).await;
    let r = b.round(&mut t).await;
    assert_eq!(r.refused, 0);
    assert_eq!(b.get("appearance.theme").as_deref(), Some("dark"));
}

#[tokio::test]
async fn a_link_to_a_row_removed_elsewhere_is_left_empty() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    let h = a.add(HOME);
    b.add(HOME);
    let sig = a
        .store
        .lock()
        .unwrap()
        .save_signature(&Signature {
            account: h,
            label: "Work".into(),
            name: "Matteo".into(),
            ..Signature::default()
        })
        .unwrap();
    let (mut t, _) = space(&[&a, &b]).await;
    // A removes the signature; B, not knowing yet, makes a group with it.
    a.store.lock().unwrap().delete_signature(sig).unwrap();
    a.round(&mut t).await;
    let on_b = b.store.lock().unwrap().signatures().unwrap()[0].id;
    b.store
        .lock()
        .unwrap()
        .save_address_group(&AddressGroup {
            name: "Clients".into(),
            color: "#2F8F83".into(),
            signature: Some(on_b),
            notify: true,
            ..AddressGroup::default()
        })
        .unwrap();
    b.note();
    b.round(&mut t).await;
    a.round(&mut t).await;
    let groups = a.store.lock().unwrap().address_groups().unwrap();
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0].signature, None);
}

#[tokio::test]
async fn a_device_nobody_vouched_for_is_not_heard() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b]).await;
    a.round(&mut t).await;
    // Someone with the content key (not a linked device) adds itself and
    // writes: no linked device vouched for it.
    let x = dev("Stranger");
    let mut s = open(&mut t, &a).await;
    s.link(&x.me.device);
    s.content.generation += 1;
    s.content
        .extra
        .insert("note".into(), "from a stranger".into());
    t.put(&Note::Space(s.seal(&x.me.device.id, &x.me.secret)))
        .await
        .unwrap();
    let r = b.round(&mut t).await;
    assert_eq!(r.refused, 1);
    assert!(!r.space.content.extra.contains_key("note"));
}

#[tokio::test]
async fn a_label_removed_elsewhere_takes_its_rules_along() {
    use piuma_core::rules::{Action, Field, Op, Rule};
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let label = a
        .store
        .lock()
        .unwrap()
        .add_label("Clients", "coral")
        .unwrap();
    let (mut t, _) = space(&[&a, &b]).await;
    // While A removes the label, B makes a rule that puts it on.
    a.store.lock().unwrap().remove_label(label.id).unwrap();
    a.round(&mut t).await;
    b.store
        .lock()
        .unwrap()
        .save_rule(&Rule {
            id: 0,
            account: None,
            field: Field::Sender,
            op: Op::Contains,
            value: "@acme.it".into(),
            action: Action::Label(label.keyword.clone()),
            enabled: true,
            last_run: None,
            matched: 0,
        })
        .unwrap();
    // B's rule goes with the label there; the removal reaches A next.
    b.round(&mut t).await;
    a.round(&mut t).await;
    b.round(&mut t).await;
    a.round(&mut t).await;
    for d in [&a, &b] {
        let s = d.store.lock().unwrap();
        assert!(s.labels().unwrap().is_empty());
        assert!(s.rules().unwrap().is_empty());
    }
}

#[tokio::test]
async fn the_same_label_made_on_two_devices_is_one() {
    let (a, b) = (dev("Mac"), dev("Pixel"));
    for d in [&a, &b] {
        d.add(HOME);
    }
    let (mut t, _) = space(&[&a, &b]).await;
    a.store.lock().unwrap().add_label("Work", "coral").unwrap();
    b.store.lock().unwrap().add_label("work", "teal").unwrap();
    a.round(&mut t).await;
    b.round(&mut t).await;
    a.round(&mut t).await;
    for d in [&a, &b] {
        let labels = d.store.lock().unwrap().labels().unwrap();
        assert_eq!(labels.len(), 1);
    }
    let (la, lb) = (
        a.store.lock().unwrap().labels().unwrap()[0].clone(),
        b.store.lock().unwrap().labels().unwrap()[0].clone(),
    );
    assert_eq!((la.name, la.color), (lb.name, lb.color));
}
