//! Devices & sync, as on `SyncToApprove`, `Groups` and `PairPhone`: the
//! encrypted space in a hidden folder of one mailbox, the devices linked
//! to it, and pairing a new one with a code or the recovery phrase.

use std::future::Future;
use std::sync::Mutex;
use std::time::Duration;

use flutter_rust_bridge::frb;
use piuma_core::pair_qr::{self, Invite, INVITE_TTL};
use piuma_core::remote::Remote;
use piuma_core::space::{self, Device, Key, Pairing, SpaceError};
use piuma_core::space_sync::{self, Folder, Me, Round, SyncError};
use piuma_core::store::{Held, SecretIn};
use piuma_core::{Account, AccountId, AccountKind};

use super::accounts::remove_account;
use super::engine::{
    add_checked_account, engine, reader, store, watch_account, AccountInfo, EngineError, ErrorKind,
};
use crate::credentials;

/// Where this device's secret is kept, in the keychain.
const SECRET: &str = "space-device";

// This device's own settings; `space.` ones never travel in the space.
const DEVICE: &str = "space.device";
const HOME: &str = "space.home";
/// What the old format kept of the last round; gone with it.
const SEEN: &str = "space.seen";
const DEVICES: &str = "space.devices";
const SYNCED_AT: &str = "space.synced_at";

/// One device linked to the space.
#[derive(Debug, Clone)]
pub struct SyncDevice {
    pub id: String,
    pub name: String,
    /// "laptop", "phone" or "tablet".
    pub kind: String,
    /// Unix seconds.
    pub last_seen: i64,
    pub this_device: bool,
}

/// What Settings › Devices & sync shows.
#[derive(Debug, Clone)]
pub struct SyncInfo {
    /// The address whose mailbox holds the space; None while sync is off.
    pub home: Option<String>,
    /// The last round that reached the space, in Unix seconds.
    pub synced_at: Option<i64>,
    pub devices: Vec<SyncDevice>,
    /// The last round found an older copy of the space and left it out.
    pub rollback: bool,
    /// The space was written by a newer version of Piuma: this device
    /// takes changes in but sends none until it is updated.
    pub outdated: bool,
    /// Accounts removed on another device that wait for the person here.
    pub held: Vec<HeldAccount>,
}

/// An account another device removed, kept here until the person says:
/// what would go with it.
#[derive(Debug, Clone)]
pub struct HeldAccount {
    pub account_id: i64,
    pub email: String,
    /// Emails waiting to be sent.
    pub outbox: u32,
    /// Drafts waiting to be uploaded.
    pub drafts: u32,
    /// Changes waiting for the server.
    pub pending: u32,
    /// Its mailbox holds the space.
    pub home: bool,
}

impl From<Held> for HeldAccount {
    fn from(h: Held) -> Self {
        HeldAccount {
            account_id: h.account.0,
            email: h.email,
            outbox: h.outbox,
            drafts: h.drafts,
            pending: h.pending,
            home: h.home,
        }
    }
}

/// After unlinking a device: the new recovery phrase, and the mailboxes
/// whose passwords that device still knows.
#[derive(Debug, Clone)]
pub struct UnlinkResult {
    pub phrase: String,
    /// Addresses whose password to change, so the device is locked out of
    /// the mailboxes too.
    pub exposed: Vec<String>,
}

/// A new device asking to be linked.
#[derive(Debug, Clone)]
pub struct PairAsk {
    pub id: String,
    pub name: String,
    pub kind: String,
    /// When it asked, in Unix seconds; it expires five minutes later.
    pub at: i64,
}

/// A password the app keeps itself (Android, in its Keystore): `key` as
/// the keychain names it, like `account-3`.
#[derive(Debug, Clone)]
pub struct KeptSecret {
    pub key: String,
    pub value: String,
}

/// What a sync round did.
#[derive(Debug, Clone)]
pub struct SyncRound {
    /// Another device's changes came in.
    pub took: bool,
    /// Another device unlinked this one; sync is off here now.
    pub unlinked: bool,
    pub requests: Vec<PairAsk>,
    /// Android only: passwords that came in, for the app to keep.
    pub keep: Vec<KeptSecret>,
    /// Accounts removed on another device, so removed here too.
    pub removed: Vec<i64>,
    /// Accounts removed on another device that wait for the person here.
    pub held: Vec<HeldAccount>,
    /// An older copy of the space was found and left out.
    pub rollback: bool,
    /// The space was written by a newer version of Piuma.
    pub outdated: bool,
}

/// What "We found your space" shows before the space is open.
#[derive(Debug, Clone)]
pub struct SpaceFound {
    pub accounts: u32,
    pub groups: u32,
    pub signatures: u32,
    pub updated_at: i64,
    pub devices: Vec<SyncDevice>,
}

/// A device that just joined the space.
#[derive(Debug, Clone)]
pub struct Joined {
    /// Android only: passwords that came in, for the app to keep.
    pub keep: Vec<KeptSecret>,
}

impl From<SyncError> for EngineError {
    fn from(e: SyncError) -> Self {
        let kind = match &e {
            SyncError::Remote(_) => {
                let SyncError::Remote(e) = e else {
                    unreachable!()
                };
                return e.into();
            }
            SyncError::Space(SpaceError::Phrase | SpaceError::Sealed) => ErrorKind::WrongPhrase,
            SyncError::Space(SpaceError::Code) => ErrorKind::WrongCode,
            SyncError::Space(SpaceError::NotLinked) => ErrorKind::NotLinked,
            SyncError::NoSpace => ErrorKind::NoSpace,
            SyncError::Expired => ErrorKind::Expired,
            SyncError::Refused => ErrorKind::Refused,
            SyncError::Taken => ErrorKind::Taken,
            SyncError::Rollback => ErrorKind::Rollback,
            SyncError::Space(SpaceError::Newer) => ErrorKind::Outdated,
            _ => ErrorKind::Other,
        };
        EngineError::new(kind, e.to_string())
    }
}

/// One sync step at a time on this device.
static ONE: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// The pairing this device is waiting on, to cancel it.
static JOINING: Mutex<Option<tokio::task::AbortHandle>> = Mutex::new(None);

fn setting(key: &str) -> Result<Option<String>, EngineError> {
    Ok(store()?.setting(key)?)
}

fn set(key: &str, value: &str) -> Result<(), EngineError> {
    Ok(store()?.set_setting(key, value)?)
}

/// This device, as the space knows it; made the first time.
fn me() -> Result<Me, EngineError> {
    let secret = credentials::load_key(SECRET)
        .ok()
        .and_then(|h| Key::from_hex(&h))
        .ok_or_else(|| EngineError::new(ErrorKind::Keychain, "no device secret"))?;
    let saved = setting(DEVICE)?.unwrap_or_default();
    let mut parts = saved.splitn(3, '\t');
    let (Some(id), Some(name), Some(kind)) = (parts.next(), parts.next(), parts.next()) else {
        return Err(EngineError::new(ErrorKind::Other, "no device identity"));
    };
    Ok(Me {
        device: Device {
            id: id.to_owned(),
            name: name.to_owned(),
            kind: kind.to_owned(),
            last_seen: 0,
            public: space::public_key(&secret),
        },
        secret,
    })
}

/// Names this device for the space (at start, from what the app knows of
/// it), making its secret the first time. Returns the new secret only on
/// Android, for the app to keep in its Keystore.
#[frb(sync)]
pub fn sync_identity(name: String, kind: String) -> Result<Option<String>, EngineError> {
    let mut made = None;
    if credentials::load_key(SECRET).is_err() {
        let secret = Key::generate().to_hex();
        credentials::save_key(SECRET, &secret)?;
        made = Some(secret);
    }
    let id = match setting(DEVICE)? {
        Some(saved) => saved.split('\t').next().unwrap_or_default().to_owned(),
        None => space::new_device_id(),
    };
    let clean = |s: &str| s.replace(['\t', '\n'], " ").trim().to_owned();
    set(DEVICE, &format!("{id}\t{}\t{}", clean(&name), clean(&kind)))?;
    Ok(if cfg!(target_os = "android") {
        made
    } else {
        None
    })
}

/// Android only: hands over this device's secret, kept in the Keystore,
/// before [sync_identity].
#[frb(sync)]
pub fn remember_sync_secret(secret: String) {
    #[cfg(target_os = "android")]
    credentials::remember_key(SECRET, &secret);
    #[cfg(not(target_os = "android"))]
    let _ = secret;
}

#[frb(sync)]
pub fn sync_info() -> Result<SyncInfo, EngineError> {
    let this = setting(DEVICE)?
        .and_then(|d| d.split('\t').next().map(str::to_owned))
        .unwrap_or_default();
    let devices = setting(DEVICES)?
        .map(|s| {
            s.lines()
                .filter_map(|line| {
                    let mut p = line.splitn(4, '\t');
                    let (id, kind, seen, name) = (p.next()?, p.next()?, p.next()?, p.next()?);
                    Some(SyncDevice {
                        this_device: id == this,
                        id: id.to_owned(),
                        name: name.to_owned(),
                        kind: kind.to_owned(),
                        last_seen: seen.parse().ok()?,
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    let home = setting(HOME)?;
    let (rollback, outdated, held) = if home.is_some() {
        let local = space_sync::state(&engine()?.store)?;
        let held = held_here(&local)?;
        (local.refused > 0, local.outdated, held)
    } else {
        (false, false, Vec::new())
    };
    Ok(SyncInfo {
        home,
        synced_at: setting(SYNCED_AT)?.and_then(|s| s.parse().ok()),
        devices,
        rollback,
        outdated,
        held,
    })
}

/// The accounts whose removal waits for the person.
fn held_here(local: &piuma_core::space_merge::Local) -> Result<Vec<HeldAccount>, EngineError> {
    let store = store()?;
    let home = setting(HOME)?;
    let mut out = Vec::new();
    for a in store.accounts()? {
        if store
            .account_gid(a.id)?
            .is_some_and(|g| local.held.contains_key(&g))
        {
            let (outbox, drafts, pending) = store.account_waiting(a.id)?;
            out.push(HeldAccount {
                account_id: a.id.0,
                home: home
                    .as_deref()
                    .is_some_and(|h| h.eq_ignore_ascii_case(&a.email)),
                email: a.email,
                outbox,
                drafts,
                pending,
            });
        }
    }
    Ok(out)
}

/// The accounts whose mailbox can hold the space: all of them, IMAP and
/// JMAP alike.
#[frb(sync)]
pub fn sync_homes() -> Result<Vec<i64>, EngineError> {
    Ok(reader()?.accounts()?.into_iter().map(|a| a.id.0).collect())
}

/// Whether this device changed something the space carries since the
/// last round, without going to the server; false while sync is off.
#[frb(sync)]
pub fn sync_dirty() -> Result<bool, EngineError> {
    if setting(HOME)?.is_none() {
        return Ok(false);
    }
    Ok(space_sync::dirty(&engine()?.store, &passwords()?, &me()?)?)
}

/// Runs `f` on the engine's runtime, one sync step at a time.
async fn run<T, F>(f: F) -> Result<T, EngineError>
where
    T: Send + 'static,
    F: Future<Output = Result<T, EngineError>> + Send + 'static,
{
    engine()?
        .runtime
        .spawn(async move {
            let _one = ONE.lock().await;
            f.await
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
}

fn account(id: AccountId) -> Result<Account, EngineError> {
    store()?
        .account(id)?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "no such account"))
}

async fn connect(account: &Account) -> Result<Remote, EngineError> {
    let password = credentials::load(account.id)?;
    Ok(Remote::open(account, &password).await?)
}

/// The mailbox that holds the space.
async fn home() -> Result<(Remote, String), EngineError> {
    let email = setting(HOME)?.ok_or_else(|| EngineError::new(ErrorKind::NotLinked, "off"))?;
    let account = store()?
        .accounts()?
        .into_iter()
        .find(|a| a.email.eq_ignore_ascii_case(&email))
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "the space's account is gone"))?;
    Ok((connect(&account).await?, email))
}

/// Every account's password this device has, by address.
fn passwords() -> Result<Vec<(String, String)>, EngineError> {
    let store = store()?;
    let mut out: Vec<(String, String)> = store
        .accounts()?
        .into_iter()
        .filter_map(|a| Some((a.email.clone(), credentials::load(a.id).ok()?)))
        .collect();
    // Connected calendars with a password of their own.
    for source in store.calendar_sources()? {
        let key = credentials::calendar_key(source.id);
        if let Ok(password) = credentials::load_key(&key) {
            out.push((format!("{KEPT_KEY}{key}"), password));
        }
    }
    Ok(out)
}

/// Marks a password in the space that isn't an account's, by its key in
/// the keychain, e.g. "secret:calendar-3".
const KEPT_KEY: &str = "secret:";

/// Keeps what this device now knows of the space: its devices, for
/// Devices & sync.
fn remember(space: &space::Space) -> Result<(), EngineError> {
    let devices: Vec<String> = space
        .content
        .devices
        .iter()
        .map(|d| {
            format!(
                "{}\t{}\t{}\t{}",
                d.id,
                d.kind,
                d.last_seen,
                d.name.replace(['\t', '\n'], " ")
            )
        })
        .collect();
    set(DEVICES, &devices.join("\n"))?;
    set(SYNCED_AT, &space::now().to_string())
}

/// Keeps passwords that came in from the space and follows their
/// accounts. Returns them for the app to keep on Android.
fn took(secrets: Vec<SecretIn>) -> Result<Vec<KeptSecret>, EngineError> {
    let mut keep = Vec::new();
    for secret in secrets {
        let (key, password) = match secret {
            SecretIn::Account(id, password) => {
                credentials::save(id, &password)?;
                (format!("account-{}", id.0), password)
            }
            SecretIn::Calendar(id, password) => {
                let key = credentials::calendar_key(id);
                credentials::save_key(&key, &password)?;
                (key, password)
            }
        };
        if cfg!(target_os = "android") {
            keep.push(KeptSecret {
                key,
                value: password,
            });
        }
    }
    for a in store()?.accounts()? {
        watch_account(a)?;
    }
    Ok(keep)
}

/// Turns sync on, with the space in `account_id`'s mailbox. Returns the
/// recovery phrase, to be shown once.
pub async fn sync_turn_on(account_id: i64) -> Result<String, EngineError> {
    let account = account(AccountId(account_id))?;
    run(async move {
        let me = me()?;
        let mut imap = connect(&account).await?;
        let mut folder = Folder::new(&mut imap, &account.email);
        let store = &engine()?.store;
        let recovery = space_sync::create(&mut folder, store, passwords()?, &me).await?;
        let space = space_sync::open(&mut folder, store, &me).await?;
        set(HOME, &account.email)?;
        super::engine::store()?.remove_setting(SEEN)?;
        remember(&space)?;
        Ok(recovery.phrase())
    })
    .await
}

/// Moves the space to `account_id`'s mailbox, from Devices & sync. The
/// other devices follow on their next round; nobody pairs again.
pub async fn sync_move(account_id: i64) -> Result<(), EngineError> {
    let account = account(AccountId(account_id))?;
    run(async move {
        let me = me()?;
        let (mut from, mailbox) = home().await?;
        if mailbox.eq_ignore_ascii_case(&account.email) {
            return Ok(());
        }
        let mut to = connect(&account).await?;
        let space = space_sync::relocate(
            &mut Folder::new(&mut from, &mailbox),
            &mut Folder::new(&mut to, &account.email),
            &account.email,
            &engine()?.store,
            &me,
        )
        .await?;
        set(HOME, &account.email)?;
        remember(&space)
    })
    .await
}

fn asks(requests: Vec<space::PairRequest>) -> Vec<PairAsk> {
    requests
        .into_iter()
        .map(|r| PairAsk {
            id: r.id,
            name: r.device.name,
            kind: r.device.kind,
            at: r.at,
        })
        .collect()
}

/// Turns sync off here, when another device unlinked this one.
fn off() -> Result<(), EngineError> {
    let s = store()?;
    for key in [HOME, SEEN, DEVICES, SYNCED_AT] {
        s.remove_setting(key)?;
    }
    s.space_forget()?;
    Ok(())
}

/// One round: merges this device's changes with the other devices', and
/// says who is asking to be linked. Does nothing while sync is off.
pub async fn sync_now() -> Result<SyncRound, EngineError> {
    let mut round = SyncRound {
        took: false,
        unlinked: false,
        requests: Vec::new(),
        keep: Vec::new(),
        removed: Vec::new(),
        held: Vec::new(),
        rollback: false,
        outdated: false,
    };
    if setting(HOME)?.is_none() {
        return Ok(round);
    }
    run(async move {
        let me = me()?;
        let (mut imap, mut mailbox) = home().await?;
        let store = &engine()?.store;
        let mut done = space_sync::round(
            &mut Folder::new(&mut imap, &mailbox),
            store,
            passwords()?,
            &me,
            Some(&mailbox),
        )
        .await;
        if let Ok(Round::Moved(to)) = done {
            // Another device moved the space: follow it there.
            set(HOME, &to)?;
            (imap, mailbox) = home().await?;
            done = space_sync::round(
                &mut Folder::new(&mut imap, &mailbox),
                store,
                passwords()?,
                &me,
                Some(&mailbox),
            )
            .await;
        }
        match done {
            Err(SyncError::Rollback) => {
                // Only an older copy is there: nothing taken in or written.
                round.rollback = true;
            }
            Err(e) => return Err(e.into()),
            Ok(Round::Unlinked) => {
                off()?;
                round.unlinked = true;
                return Ok(round);
            }
            Ok(Round::Moved(_)) => {
                return Err(EngineError::new(
                    ErrorKind::NoSpace,
                    "the space moved twice",
                ))
            }
            Ok(Round::Newer) => round.outdated = true,
            Ok(Round::Done(report)) => {
                // Removed on another device and confirmed by the merged
                // state, with nothing waiting to leave with it here.
                for id in &report.applied.remove {
                    remove_account(id.0)?;
                    round.removed.push(id.0);
                }
                round.took = report.applied.took || !round.removed.is_empty();
                round.keep = took(report.applied.secrets)?;
                round.held = report.applied.held.into_iter().map(Into::into).collect();
                round.rollback = report.refused > 0;
                round.outdated = report.outdated;
                remember(&report.space)?;
            }
        }
        round.requests = asks(space_sync::requests(&mut Folder::new(&mut imap, &mailbox)).await?);
        Ok(round)
    })
    .await
}

/// "Remove it here too": an account another device removed, which waited
/// here for mail, drafts or changes still to go, is removed now.
pub async fn sync_confirm_removal(account_id: i64) -> Result<(), EngineError> {
    run(async move {
        space_sync::confirm_removal(&engine()?.store, AccountId(account_id))?;
        remove_account(account_id)
    })
    .await
}

/// "Keep it": an account another device removed stays, and comes back on
/// the other devices with the next round.
pub async fn sync_keep_account(account_id: i64) -> Result<(), EngineError> {
    run(async move {
        Ok(space_sync::keep_account(
            &engine()?.store,
            AccountId(account_id),
        )?)
    })
    .await
}

/// Who is asking to be linked, newest first.
pub async fn sync_requests() -> Result<Vec<PairAsk>, EngineError> {
    run(async move {
        let (mut imap, mailbox) = home().await?;
        Ok(asks(
            space_sync::requests(&mut Folder::new(&mut imap, &mailbox)).await?,
        ))
    })
    .await
}

/// Approves a new device with the 6 digits it shows.
pub async fn sync_approve(request_id: String, code: String) -> Result<(), EngineError> {
    run(async move {
        let me = me()?;
        let (mut imap, mailbox) = home().await?;
        let code: String = code.chars().filter(char::is_ascii_digit).collect();
        space_sync::approve_waiting(
            &mut Folder::new(&mut imap, &mailbox),
            &engine()?.store,
            &request_id,
            &code,
            &me,
        )
        .await?;
        Ok(())
    })
    .await
}

/// "Not me": deletes a request.
pub async fn sync_refuse(request_id: String) -> Result<(), EngineError> {
    run(async move {
        let (mut imap, mailbox) = home().await?;
        space_sync::refuse(&mut Folder::new(&mut imap, &mailbox), &request_id).await?;
        Ok(())
    })
    .await
}

/// Unlinks a device. Returns the new recovery phrase (the old one opens
/// the space no more) and the mailboxes whose passwords the device still
/// knows: a new key keeps it out of the space, not out of the mailboxes.
pub async fn sync_unlink(device_id: String) -> Result<UnlinkResult, EngineError> {
    run(async move {
        let me = me()?;
        let (mut imap, mailbox) = home().await?;
        let done = space_sync::unlink(
            &mut Folder::new(&mut imap, &mailbox),
            &engine()?.store,
            &device_id,
            &me,
        )
        .await?;
        remember(&done.space)?;
        Ok(UnlinkResult {
            phrase: done.recovery.phrase(),
            exposed: done.exposed,
        })
    })
    .await
}

/// "Turn off sync on this device": leaves the space and stops syncing
/// here; accounts and mail stay. On the last device the space is deleted
/// from its mailbox.
pub async fn sync_turn_off() -> Result<(), EngineError> {
    run(async move {
        let me = me()?;
        let (mut imap, mailbox) = home().await?;
        space_sync::leave(&mut Folder::new(&mut imap, &mailbox), &engine()?.store, &me).await?;
        off()
    })
    .await
}

/// The recovery phrase, shown again from Devices & sync.
pub async fn sync_phrase() -> Result<String, EngineError> {
    run(async move {
        let me = me()?;
        let (mut imap, mailbox) = home().await?;
        let space =
            space_sync::open(&mut Folder::new(&mut imap, &mailbox), &engine()?.store, &me).await?;
        space
            .recovery()
            .map(|k| k.phrase())
            .ok_or_else(|| EngineError::new(ErrorKind::Other, "no phrase in this space"))
    })
    .await
}

/// On a new device, after signing in: whether `account_id`'s mailbox
/// holds a space, and what it says of itself.
pub async fn sync_found(account_id: i64) -> Result<Option<SpaceFound>, EngineError> {
    let account = account(AccountId(account_id))?;
    run(async move {
        let mut imap = connect(&account).await?;
        let mut folder = Folder::new(&mut imap, &account.email);
        Ok(space_sync::about(&mut folder).await?.map(|a| SpaceFound {
            accounts: a.accounts as u32,
            groups: a.groups as u32,
            signatures: a.signatures as u32,
            updated_at: a.updated_at,
            devices: a
                .devices
                .into_iter()
                .map(|d| SyncDevice {
                    id: String::new(),
                    name: d.name,
                    kind: d.kind,
                    last_seen: d.last_seen,
                    this_device: false,
                })
                .collect(),
        }))
    })
    .await
}

/// Six new digits for the new device to show.
#[frb(sync)]
pub fn sync_pair_code() -> String {
    space::pair_code()
}

/// Whether `phrase` is a recovery phrase at all (24 known words that
/// check out), before trying it.
#[frb(sync)]
pub fn sync_phrase_valid(phrase: String) -> bool {
    Key::from_phrase(&phrase).is_ok()
}

/// After a pairing or the recovery phrase: this device is in.
fn joined(mailbox: &str, report: space_sync::Report) -> Result<Joined, EngineError> {
    let keep = took(report.applied.secrets)?;
    set(HOME, mailbox)?;
    store()?.remove_setting(SEEN)?;
    remember(&report.space)?;
    Ok(Joined { keep })
}

/// On a new device: asks to be linked with `code`, shown on its screen,
/// and waits until a linked device approves it, says "Not me", or five
/// minutes pass. [sync_join_cancel] stops waiting.
pub async fn sync_join(account_id: i64, code: String) -> Result<Joined, EngineError> {
    join(account_id, code, false).await
}

/// On a new phone, after scanning a linked device's QR code (`link`) and
/// signing in to its mailbox: asks to be linked with the invite's code,
/// which that device answers on its own. [sync_join_cancel] stops waiting.
pub async fn sync_join_invite(account_id: i64, link: String) -> Result<Joined, EngineError> {
    let invite = Invite::from_link(&link)
        .ok_or_else(|| EngineError::new(ErrorKind::WrongCode, "not an invite"))?;
    join(account_id, invite.code, true).await
}

async fn join(account_id: i64, code: String, qr: bool) -> Result<Joined, EngineError> {
    let account = account(AccountId(account_id))?;
    let task = engine()?.runtime.spawn(async move {
        let me = me()?;
        let mut imap = connect(&account).await?;
        let mut folder = Folder::new(&mut imap, &account.email);
        let pairing: Pairing = if qr {
            space_sync::request_qr(&mut folder, &code, &me).await?
        } else {
            space_sync::request(&mut folder, &code, &me).await?
        };
        let store = &engine()?.store;
        let report = space_sync::join(
            &mut folder,
            pairing,
            store,
            passwords()?,
            &me,
            Some(&account.email),
            Duration::from_secs(2),
        )
        .await?;
        joined(&account.email, report)
    });
    *JOINING.lock().unwrap_or_else(|e| e.into_inner()) = Some(task.abort_handle());
    let result = task.await;
    JOINING.lock().unwrap_or_else(|e| e.into_inner()).take();
    match result {
        Ok(r) => r,
        Err(e) if e.is_cancelled() => Err(EngineError::new(ErrorKind::Expired, "cancelled")),
        Err(e) => Err(EngineError::new(ErrorKind::Other, e.to_string())),
    }
}

/// Stops waiting for a pairing.
#[frb(sync)]
pub fn sync_join_cancel() {
    if let Some(task) = JOINING.lock().unwrap_or_else(|e| e.into_inner()).take() {
        task.abort();
    }
}

/// On a new device: opens the space in `account_id`'s mailbox with the
/// recovery phrase.
pub async fn sync_recover(account_id: i64, phrase: String) -> Result<Joined, EngineError> {
    let account = account(AccountId(account_id))?;
    run(async move {
        let me = me()?;
        let mut imap = connect(&account).await?;
        let store = &engine()?.store;
        let report = space_sync::recover(
            &mut Folder::new(&mut imap, &account.email),
            &phrase,
            store,
            passwords()?,
            &me,
            Some(&account.email),
        )
        .await?;
        joined(&account.email, report)
    })
    .await
}

/// The QR code "Link a new device" shows, as on `QrPairToApprove`.
#[derive(Debug, Clone)]
pub struct SyncInvite {
    /// Modules a side, without the quiet zone.
    pub width: u32,
    /// Row by row, true for dark.
    pub modules: Vec<bool>,
    /// When a new one takes its place, in Unix seconds.
    pub expires_at: i64,
}

/// What a scanned code says, before signing in.
#[derive(Debug, Clone)]
pub struct ScannedInvite {
    /// The whole code, handed back to sign in and join.
    pub link: String,
    /// The address whose mailbox holds the space.
    pub email: String,
}

/// The codes shown, each with when it was made: the panel makes a new
/// one every five minutes, and again each time it opens, while a phone
/// may still be asking with an earlier one.
static INVITES: Mutex<Vec<(String, i64)>> = Mutex::new(Vec::new());

/// How long a code shown is still answered: it can be scanned until a
/// new one takes its place, and the request made with it waits as long
/// as any.
const INVITE_ANSWERED: i64 = INVITE_TTL + space::PAIR_TTL;

/// The codes shown lately, the expired ones dropped.
fn invites() -> std::sync::MutexGuard<'static, Vec<(String, i64)>> {
    let mut codes = INVITES.lock().unwrap_or_else(|e| e.into_inner());
    let now = space::now();
    codes.retain(|(_, at)| now - at <= INVITE_ANSWERED);
    codes
}

/// A new invite for the space's mailbox, with a new code: while it shows,
/// [sync_answer_invite] answers the phones that scan it.
#[frb(sync)]
pub fn sync_invite() -> Result<SyncInvite, EngineError> {
    let email = setting(HOME)?.ok_or_else(|| EngineError::new(ErrorKind::NotLinked, "off"))?;
    let account = store()?
        .accounts()?
        .into_iter()
        .find(|a| a.email.eq_ignore_ascii_case(&email))
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "the space's account is gone"))?;
    let invite = Invite::new(&account);
    let (width, modules) = pair_qr::qr_modules(&invite.to_link());
    let now = space::now();
    invites().push((invite.code, now));
    Ok(SyncInvite {
        width: width as u32,
        modules,
        expires_at: now + INVITE_TTL,
    })
}

/// "Link a new device" closed: its codes answer no one any more.
#[frb(sync)]
pub fn sync_invite_end() {
    invites().clear();
}

/// While "Link a new device" is open: answers the phones that scanned
/// one of its codes. Returns their names.
pub async fn sync_answer_invite() -> Result<Vec<String>, EngineError> {
    let codes: Vec<String> = invites().iter().map(|(c, _)| c.clone()).collect();
    if codes.is_empty() {
        return Ok(Vec::new());
    }
    run(async move {
        let me = me()?;
        let (mut imap, mailbox) = home().await?;
        Ok(space_sync::answer_invite(
            &mut Folder::new(&mut imap, &mailbox),
            &engine()?.store,
            &codes,
            &me,
        )
        .await?)
    })
    .await
}

/// Looks for an invite in a camera frame: one byte of light per pixel,
/// `stride` bytes a row.
#[frb(sync)]
pub fn sync_read_code(
    gray: Vec<u8>,
    width: u32,
    height: u32,
    stride: u32,
) -> Option<ScannedInvite> {
    let text = pair_qr::read_qr(&gray, width as usize, height as usize, stride as usize)?;
    let invite = Invite::from_link(&text)?;
    Some(ScannedInvite {
        link: text,
        email: invite.email,
    })
}

/// Where a scanned invite signs in, shown before the password is typed.
#[derive(Debug, Clone)]
pub struct InviteServer {
    /// The host the password goes to.
    pub host: String,
    /// It comes from the code itself, not from the address's own known or
    /// published settings: the person checks it.
    pub from_invite: bool,
}

/// The servers resolved for the last invite looked at, by its link, so
/// the sign-in uses what the person saw.
static RESOLVED: Mutex<Option<(String, AccountKind)>> = Mutex::new(None);

/// Where a scanned invite would sign in: the address's own settings when
/// it has known or published ones, the code's otherwise.
pub async fn sync_invite_server(link: String) -> Result<InviteServer, EngineError> {
    let invite = Invite::from_link(&link)
        .ok_or_else(|| EngineError::new(ErrorKind::WrongCode, "not an invite"))?;
    let resolved = engine()?
        .runtime
        .spawn(async move { pair_qr::resolve(&invite).await })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    let server = InviteServer {
        host: resolved.host(),
        from_invite: resolved.from_invite,
    };
    *RESOLVED.lock().unwrap_or_else(|e| e.into_inner()) = Some((link, resolved.kind));
    Ok(server)
}

/// On a new phone: signs in to the mailbox a scanned invite names, with
/// the servers [sync_invite_server] showed, and adds the account.
pub async fn sync_add_invite_account(
    link: String,
    name: String,
    color: String,
    password: String,
) -> Result<AccountInfo, EngineError> {
    let invite = Invite::from_link(&link)
        .ok_or_else(|| EngineError::new(ErrorKind::WrongCode, "not an invite"))?;
    let shown = RESOLVED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .take()
        .filter(|(l, _)| *l == link)
        .map(|(_, kind)| kind);
    let kind = match shown {
        Some(kind) => kind,
        None => {
            let i = invite.clone();
            engine()?
                .runtime
                .spawn(async move { pair_qr::resolve(&i).await })
                .await
                .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
                .kind
        }
    };
    let account = Account {
        id: AccountId(0),
        name,
        email: invite.email,
        sender_name: String::new(),
        color,
        kind,
    };
    add_checked_account(account, password).await
}
