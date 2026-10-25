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
use piuma_core::space_sync::{self, Me, Round, Seen, SyncError};
use piuma_core::{Account, AccountId};

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
    Ok(SyncInfo {
        home: setting(HOME)?,
        synced_at: setting(SYNCED_AT)?.and_then(|s| s.parse().ok()),
        devices,
    })
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
    let local = space_sync::content(&engine()?.store, passwords()?, &me()?)?;
    Ok(space_sync::fingerprint(&local) != last_seen()?.local)
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

/// Keeps what this device now knows of the space.
fn remember(space: &space::Space, seen: &Seen) -> Result<(), EngineError> {
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
    set(
        SEEN,
        &format!("{}\t{}\t{}", seen.remote, seen.local, seen.touched),
    )?;
    set(SYNCED_AT, &space::now().to_string())
}

fn last_seen() -> Result<Seen, EngineError> {
    let saved = setting(SEEN)?.unwrap_or_default();
    let mut p = saved.split('\t');
    Ok(Seen {
        remote: p.next().unwrap_or_default().to_owned(),
        local: p.next().unwrap_or_default().to_owned(),
        touched: p.next().and_then(|t| t.parse().ok()).unwrap_or_default(),
    })
}

/// Keeps passwords that came in from the space and follows their
/// accounts. Returns them for the app to keep on Android.
fn took(
    passwords: Vec<(AccountId, String)>,
    space: &space::Space,
) -> Result<Vec<KeptSecret>, EngineError> {
    let mut keep = Vec::new();
    for (name, password) in &space.content.passwords {
        let Some(key) = name.strip_prefix(KEPT_KEY) else {
            continue;
        };
        credentials::save_key(key, password)?;
        if cfg!(target_os = "android") {
            keep.push(KeptSecret {
                key: key.to_owned(),
                value: password.clone(),
            });
        }
    }
    for (id, password) in passwords {
        credentials::save(id, &password)?;
        if cfg!(target_os = "android") {
            keep.push(KeptSecret {
                key: format!("account-{}", id.0),
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
        let store = &engine()?.store;
        let recovery =
            space_sync::create(&mut imap, &account.email, store, passwords()?, &me).await?;
        let space = space_sync::open(&mut imap, &me).await?;
        let seen = space_sync::seen(store, passwords()?, &me, &space)?;
        set(HOME, &account.email)?;
        remember(&space, &seen)?;
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
        let space = space_sync::relocate(&mut from, &mailbox, &mut to, &account.email, &me).await?;
        set(HOME, &account.email)?;
        // The content didn't change: what this device last saw still holds.
        remember(&space, &last_seen()?)
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
    Ok(())
}

/// One round: takes in other devices' changes or writes this one's, and
/// says who is asking to be linked. Does nothing while sync is off.
pub async fn sync_now() -> Result<SyncRound, EngineError> {
    let mut round = SyncRound {
        took: false,
        unlinked: false,
        requests: Vec::new(),
        keep: Vec::new(),
        removed: Vec::new(),
    };
    if setting(HOME)?.is_none() {
        return Ok(round);
    }
    run(async move {
        let me = me()?;
        let (mut imap, mut mailbox) = home().await?;
        let store = &engine()?.store;
        let last = last_seen()?;
        let mut done =
            space_sync::round(&mut imap, &mailbox, store, passwords()?, &me, &last).await?;
        if let Round::Moved(to) = done {
            // Another device moved the space: follow it there.
            set(HOME, &to)?;
            (imap, mailbox) = home().await?;
            done = space_sync::round(&mut imap, &mailbox, store, passwords()?, &me, &last).await?;
        }
        match done {
            Round::Unlinked => {
                off()?;
                round.unlinked = true;
                return Ok(round);
            }
            Round::Moved(_) => {
                return Err(EngineError::new(
                    ErrorKind::NoSpace,
                    "the space moved twice",
                ))
            }
            Round::Same(space, seen) | Round::Pushed(space, seen) => remember(&space, &seen)?,
            Round::Took(space, passwords, gone) => {
                for id in gone {
                    // The space's own mailbox stays while sync is on.
                    if account(id)?.email.eq_ignore_ascii_case(&mailbox) {
                        continue;
                    }
                    remove_account(id.0)?;
                    round.removed.push(id.0);
                }
                round.keep = took(passwords, &space)?;
                round.took = true;
                let seen = space_sync::seen(store, self::passwords()?, &me, &space)?;
                remember(&space, &seen)?;
            }
        }
        round.requests = asks(space_sync::requests(&mut imap).await?);
        Ok(round)
    })
    .await
}

/// Who is asking to be linked, newest first.
pub async fn sync_requests() -> Result<Vec<PairAsk>, EngineError> {
    run(async move {
        let (mut imap, _) = home().await?;
        Ok(asks(space_sync::requests(&mut imap).await?))
    })
    .await
}

/// Approves a new device with the 6 digits it shows.
pub async fn sync_approve(request_id: String, code: String) -> Result<(), EngineError> {
    run(async move {
        let me = me()?;
        let (mut imap, mailbox) = home().await?;
        let code: String = code.chars().filter(char::is_ascii_digit).collect();
        space_sync::approve_waiting(&mut imap, &mailbox, &request_id, &code, &me).await?;
        Ok(())
    })
    .await
}

/// "Not me": deletes a request.
pub async fn sync_refuse(request_id: String) -> Result<(), EngineError> {
    run(async move {
        let (mut imap, mailbox) = home().await?;
        space_sync::refuse(&mut imap, &mailbox, &request_id).await?;
        Ok(())
    })
    .await
}

/// Unlinks a device. Returns the new recovery phrase: the old one opens
/// the space no more.
pub async fn sync_unlink(device_id: String) -> Result<String, EngineError> {
    run(async move {
        let me = me()?;
        let (mut imap, mailbox) = home().await?;
        let recovery = space_sync::unlink(&mut imap, &mailbox, &device_id, &me).await?;
        let store = &engine()?.store;
        let space = space_sync::open(&mut imap, &me).await?;
        let seen = space_sync::seen(store, passwords()?, &me, &space)?;
        remember(&space, &seen)?;
        Ok(recovery.phrase())
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
        space_sync::leave(&mut imap, &mailbox, &me).await?;
        off()
    })
    .await
}

/// The recovery phrase, shown again from Devices & sync.
pub async fn sync_phrase() -> Result<String, EngineError> {
    run(async move {
        let me = me()?;
        let (mut imap, _) = home().await?;
        let space = space_sync::open(&mut imap, &me).await?;
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
        Ok(space_sync::about(&mut imap).await?.map(|a| SpaceFound {
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
fn joined(
    mailbox: &str,
    space: &space::Space,
    passwords: Vec<(AccountId, String)>,
    me: &Me,
) -> Result<Joined, EngineError> {
    let keep = took(passwords, space)?;
    let seen = space_sync::seen(&engine()?.store, self::passwords()?, me, space)?;
    set(HOME, mailbox)?;
    remember(space, &seen)?;
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
        let pairing: Pairing = if qr {
            space_sync::request_qr(&mut imap, &account.email, &code, &me).await?
        } else {
            space_sync::request(&mut imap, &account.email, &code, &me).await?
        };
        let store = &engine()?.store;
        let (space, passwords) = space_sync::join(
            &mut imap,
            &account.email,
            pairing,
            store,
            &me,
            Duration::from_secs(2),
        )
        .await?;
        joined(&account.email, &space, passwords, &me)
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
        let (space, passwords) =
            space_sync::recover(&mut imap, &account.email, &phrase, store, &me).await?;
        joined(&account.email, &space, passwords, &me)
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
        Ok(space_sync::answer_invite(&mut imap, &mailbox, &codes, &me).await?)
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

/// On a new phone: signs in to the mailbox a scanned invite names, with
/// the settings it carries, and adds the account.
pub async fn sync_add_invite_account(
    link: String,
    name: String,
    color: String,
    password: String,
) -> Result<AccountInfo, EngineError> {
    let invite = Invite::from_link(&link)
        .ok_or_else(|| EngineError::new(ErrorKind::WrongCode, "not an invite"))?;
    let account = Account {
        id: AccountId(0),
        name,
        email: invite.email,
        sender_name: String::new(),
        color,
        kind: invite.kind,
    };
    add_checked_account(account, password).await
}
