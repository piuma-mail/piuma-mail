//! The sync space between devices: opening the copies a transport holds,
//! merging them with this device's rows ([crate::space_merge]), writing
//! the result back, and pairing a new device.
//!
//! The transport only stores and lists notes ([Transport]): today the
//! hidden folder of one of the person's mailboxes ([Folder]), later a
//! self-hosted companion. What is merged, the generation and the schema
//! rule live here and in [crate::space_merge], and know nothing of IMAP.

use std::future::Future;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::feedback::{log, Level};
use crate::remote::{Remote, RemoteError};
use crate::space::{
    self, Device, Key, Note, PairAnswer, PairRequest, Pairing, SealedSpace, Space, SpaceError,
};
use crate::space_merge::{self, Guard, Local, Tables, FORMAT, SCHEMA, SECRETS};
use crate::store::Applied;
use crate::Store;

#[derive(Debug, thiserror::Error)]
pub enum SyncError {
    #[error(transparent)]
    Remote(#[from] RemoteError),
    #[error(transparent)]
    Space(#[from] SpaceError),
    #[error(transparent)]
    Store(#[from] crate::StoreError),
    /// The mailbox holds no space.
    #[error("no space in this mailbox")]
    NoSpace,
    /// Nobody answered the pairing request in time.
    #[error("the request expired")]
    Expired,
    /// A linked device answered "Not me".
    #[error("the request was refused")]
    Refused,
    /// The mailbox to move to holds a space this device can't open.
    #[error("another space is in this mailbox")]
    Taken,
    /// Every copy of the space this device can open is older than what it
    /// accepted, or sealed with a key that was replaced: someone put an
    /// old copy back. Nothing is taken in or written.
    #[error("only an older copy of the space was found")]
    Rollback,
}

pub type Result<T> = std::result::Result<T, SyncError>;

/// This device, as the space knows it, with its secret.
#[derive(Clone)]
pub struct Me {
    pub device: Device,
    pub secret: Key,
}

impl std::fmt::Debug for Me {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Me")
            .field("device", &self.device.id)
            .finish_non_exhaustive()
    }
}

/// Where the space's notes are kept. It stores and lists them; it doesn't
/// read them.
pub trait Transport: Send {
    /// Every note, oldest first, with the id to remove it by.
    fn notes(&mut self) -> impl Future<Output = Result<Vec<(String, Note)>>> + Send;
    fn put(&mut self, note: &Note) -> impl Future<Output = Result<()>> + Send;
    fn remove(&mut self, ids: &[String]) -> impl Future<Output = Result<()>> + Send;
}

/// The hidden folder of the mailbox that holds the space, over IMAP or
/// JMAP.
pub struct Folder<'a> {
    remote: &'a mut Remote,
    mailbox: String,
}

impl<'a> Folder<'a> {
    /// `mailbox` is the address the notes are from and to.
    pub fn new(remote: &'a mut Remote, mailbox: &str) -> Self {
        Folder {
            remote,
            mailbox: mailbox.to_owned(),
        }
    }
}

impl Transport for Folder<'_> {
    async fn notes(&mut self) -> Result<Vec<(String, Note)>> {
        Ok(self.remote.space_notes().await?)
    }

    async fn put(&mut self, note: &Note) -> Result<()> {
        let raw = note.to_message(&self.mailbox, space::now());
        Ok(self.remote.space_put(&raw).await?)
    }

    async fn remove(&mut self, ids: &[String]) -> Result<()> {
        Ok(self.remote.space_remove(ids).await?)
    }
}

/// Notes kept in memory, shared by clones: devices in a test, or a
/// transport's own cache.
#[derive(Clone, Default)]
pub struct Memory {
    notes: Arc<Mutex<Notes>>,
}

/// The last id given, and the notes.
type Notes = (u64, Vec<(String, Note)>);

impl Memory {
    pub fn new() -> Self {
        Self::default()
    }

    /// Every note as stored, to look at or put back.
    pub fn snapshot(&self) -> Vec<(String, Note)> {
        self.notes
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .1
            .clone()
    }
}

impl Transport for Memory {
    async fn notes(&mut self) -> Result<Vec<(String, Note)>> {
        Ok(self.snapshot())
    }

    async fn put(&mut self, note: &Note) -> Result<()> {
        let mut n = self.notes.lock().unwrap_or_else(|e| e.into_inner());
        n.0 += 1;
        let id = n.0.to_string();
        n.1.push((id, note.clone()));
        Ok(())
    }

    async fn remove(&mut self, ids: &[String]) -> Result<()> {
        self.notes
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .1
            .retain(|(id, _)| !ids.contains(id));
        Ok(())
    }
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}

/// The newest stored space, in this format or the old one.
fn newest(notes: &[(String, Note)]) -> Option<&SealedSpace> {
    let spaces = || {
        notes.iter().rev().filter_map(|(_, n)| match n {
            Note::Space(s) => Some(s),
            _ => None,
        })
    };
    spaces()
        .find(|s| !s.is_v1())
        .or_else(|| spaces().find(|s| s.is_v1()))
}

/// Whether the mailbox holds a space, without opening it: for "We found
/// your space".
pub async fn found(t: &mut impl Transport) -> Result<bool> {
    Ok(newest(&t.notes().await?).is_some())
}

/// The sealed space's few readable things, for "We found your space";
/// None when the mailbox holds none.
pub async fn about(t: &mut impl Transport) -> Result<Option<space::About>> {
    Ok(newest(&t.notes().await?).map(|s| s.about.clone()))
}

/// The content key this device accepted last, from its guard.
fn guarded_key(me: &Me, guard: &Guard) -> Option<Key> {
    let sealed = hex(&guard.key)?;
    let plain = space::open(&space::local_key(&me.secret, "guard"), &sealed).ok()?;
    <[u8; 32]>::try_from(plain.as_slice()).ok().map(Key)
}

fn guard_for(me: &Me, space: &Space) -> Guard {
    let sealed = space::seal(
        &space::local_key(&me.secret, "guard"),
        &space.content_key().0,
    );
    Guard {
        generation: space.content.generation,
        key: sealed.iter().map(|b| format!("{b:02x}")).collect(),
    }
}

fn hex(s: &str) -> Option<Vec<u8>> {
    if !s.len().is_multiple_of(2) || s.is_empty() {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(s.get(i..i + 2)?, 16).ok())
        .collect()
}

/// The copies of the space this device takes, merged into the newest.
struct Opened {
    space: Space,
    /// Every stored copy, to replace when writing.
    ids: Vec<String>,
    /// Copies left out as older ones.
    refused: u32,
}

/// Opens the stored copies with `open`, keeps those `guard` allows (see
/// [space_merge::acceptable]) and sealed with the newest one's key, and
/// merges their rows. A space only in the old format comes out converted.
fn open_copies(
    notes: &[(String, Note)],
    guard: &Guard,
    current: Option<&Key>,
    open: impl Fn(&SealedSpace) -> std::result::Result<Space, SpaceError>,
) -> Result<Opened> {
    let ids: Vec<String> = notes
        .iter()
        .filter(|(_, n)| matches!(n, Note::Space(_)))
        .map(|(id, _)| id.clone())
        .collect();
    let mut refused = 0;
    let mut not_linked = false;
    let mut opened = Vec::new();
    let mut v1 = Vec::new();
    for (_, note) in notes {
        let Note::Space(sealed) = note else { continue };
        if sealed.is_v1() {
            v1.push(sealed);
            continue;
        }
        match open(sealed) {
            Ok(s) => {
                if space_merge::acceptable(
                    s.content.generation,
                    &s.content_key().0,
                    &s.content.previous,
                    guard.generation,
                    current.map(|k| &k.0),
                ) {
                    opened.push(s);
                } else {
                    refused += 1;
                }
            }
            Err(SpaceError::NotLinked) => not_linked = true,
            Err(SpaceError::Newer) => return Err(SpaceError::Newer.into()),
            Err(_) => refused += 1,
        }
    }
    if opened.is_empty() {
        // Only the old format: converted, unless a newer one was accepted
        // here before (then it is an old copy put back).
        if v1.is_empty() || guard.generation > 0 || not_linked || refused > 0 {
            return Err(if not_linked {
                SpaceError::NotLinked.into()
            } else if refused > 0 || guard.generation > 0 {
                log_refused(refused.max(1));
                SyncError::Rollback
            } else {
                SyncError::NoSpace
            });
        }
        let mut last = Err(SyncError::NoSpace);
        for sealed in v1.into_iter().rev() {
            match open(sealed) {
                Ok(space) => {
                    return Ok(Opened {
                        space,
                        ids,
                        refused,
                    })
                }
                Err(e) => last = Err(e.into()),
            }
        }
        return last;
    }
    opened.sort_by_key(|s| s.content.generation);
    let mut top = opened.pop().expect("one at least");
    for other in opened {
        if other.content_key() != top.content_key() {
            // From before the key changed: what it had, the change carried.
            refused += 1;
            continue;
        }
        space_merge::merge(&mut top.content.tables, &other.content.tables);
    }
    if refused > 0 {
        log_refused(refused);
    }
    Ok(Opened {
        space: top,
        ids,
        refused,
    })
}

fn log_refused(n: u32) {
    log(
        Level::Warn,
        "space",
        &format!("refused {n} older copies of the sync space"),
    );
}

/// Opens the space as this device, as its guard allows.
async fn open_checked(t: &mut impl Transport, me: &Me, guard: &Guard) -> Result<Opened> {
    let notes = t.notes().await?;
    if !notes.iter().any(|(_, n)| matches!(n, Note::Space(_))) {
        return Err(SyncError::NoSpace);
    }
    let current = guarded_key(me, guard);
    open_copies(&notes, guard, current.as_ref(), |s| {
        Space::open_as(s, &me.device.id, &me.secret)
    })
}

/// Opens the space as this device.
pub async fn open(t: &mut impl Transport, store: &Mutex<Store>, me: &Me) -> Result<Space> {
    let guard = lock(store).space_local()?.guard;
    Ok(open_checked(t, me, &guard).await?.space)
}

/// Writes `space` and drops the copies it replaces.
async fn put(t: &mut impl Transport, space: &Space, older: &[String]) -> Result<()> {
    t.put(&Note::Space(space.seal())).await?;
    t.remove(older).await?;
    Ok(())
}

/// What a sync round did.
#[derive(Debug)]
pub struct Report {
    pub space: Space,
    /// This device's changes went to the space.
    pub pushed: bool,
    /// What another device's changes did here: passwords for the
    /// keychain, accounts added, accounts to remove now, and removals
    /// waiting for the person.
    pub applied: Applied,
    /// The space was written by a newer version: this device reads what it
    /// understands, and writes nothing until it is updated.
    pub outdated: bool,
    /// Older copies of the space left out.
    pub refused: u32,
}

#[derive(Debug)]
pub enum Round {
    Done(Box<Report>),
    /// Another device unlinked this one.
    Unlinked,
    /// Another device moved the space to this address's mailbox.
    Moved(String),
    /// The space is in a format newer than this build: nothing happens
    /// until it is updated.
    Newer,
}

/// How often a device that changes nothing still marks itself as seen,
/// for "active 2 hours ago".
const TOUCH_EVERY: i64 = 60 * 60;

/// Secrets in `doc` only as digests take the value `remote` has for the
/// same write.
fn hydrate(doc: &mut Tables, remote: &Tables) {
    let Some(theirs) = remote.get(SECRETS) else {
        return;
    };
    if let Some(mine) = doc.get_mut(SECRETS) {
        for (gid, row) in mine.iter_mut() {
            if row.del || row.v.contains_key("value") {
                continue;
            }
            if let Some(r) = theirs.get(gid).filter(|r| r.s == row.s && !r.del) {
                *row = r.clone();
            }
        }
    }
}

/// Passwords as this device keeps them: a digest in place of the value.
fn strip(doc: &mut Tables, digest: &dyn Fn(&str, &str) -> String) {
    if let Some(secrets) = doc.get_mut(SECRETS) {
        for (gid, row) in secrets.iter_mut() {
            if let Some(v) = row.v.remove("value") {
                let d = digest(gid, v.as_str().unwrap_or_default());
                row.v.insert("digest".into(), d.into());
            }
        }
    }
}

/// The rows to write: passwords this device has no value for are left to
/// the device that has them.
fn writable(doc: &Tables) -> Tables {
    let mut out = doc.clone();
    if let Some(secrets) = out.get_mut(SECRETS) {
        secrets.retain(|_, r| r.del || r.v.contains_key("value"));
    }
    out
}

fn digest_for(me: &Me) -> impl Fn(&str, &str) -> String {
    let key = space::local_key(&me.secret, "digest");
    move |gid: &str, value: &str| space::digest(&key, gid, value)
}

/// Merges `opened` with this store, puts in what came from other devices,
/// and writes the result when it holds something the space doesn't (or
/// this device is new to it, or due to mark itself as seen).
async fn settle(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    secrets: &[(String, String)],
    me: &Me,
    home: Option<&str>,
    opened: Opened,
    mut local: Local,
) -> Result<Report> {
    let Opened {
        space: mut remote,
        ids,
        refused,
    } = opened;
    let now_ms = space_merge::now_ms();
    let digest = digest_for(me);
    lock(store).space_scan(
        &mut local,
        secrets,
        &digest,
        &me.device.id,
        now_ms,
        Some(&remote.content.tables),
    )?;
    local.observe(&remote.content.tables);
    hydrate(&mut local.doc, &remote.content.tables);
    let mut merged = local.doc.clone();
    let won = space_merge::merge(&mut merged, &remote.content.tables);
    let applied = lock(store).space_apply(&mut local, &merged, &won, home)?;
    let horizon = space_merge::horizon(remote.content.devices.iter().map(|d| d.last_seen), now_ms);
    space_merge::compact(&mut merged, horizon);
    let outdated = remote.content.schema > SCHEMA;
    let rows = writable(&merged);
    let differs = !space_merge::same(&rows, &remote.content.tables);
    let now = space::now();
    let stale = remote
        .content
        .devices
        .iter()
        .find(|d| d.id == me.device.id)
        .is_none_or(|d| now - d.last_seen >= TOUCH_EVERY);
    let pushed = !outdated && (differs || stale || ids.len() > 1 || remote.converted());
    if pushed {
        remote.content.tables = rows;
        remote.content.generation += 1;
        remote.content.format = FORMAT;
        remote.content.schema = SCHEMA;
        remote.content.updated_at = now;
        remote.content.updated_by.clone_from(&me.device.id);
        remote.link(&me.device);
        put(t, &remote, &ids).await?;
        local.unpushed = false;
    }
    local.doc = merged;
    strip(&mut local.doc, &digest);
    local.started = true;
    local.guard = guard_for(me, &remote);
    local.refused = refused;
    local.outdated = outdated;
    lock(store).set_space_local(&local)?;
    Ok(Report {
        space: remote,
        pushed,
        applied,
        outdated,
        refused,
    })
}

/// One sync round: merges this device's changes and the other devices',
/// row by row, and writes the result when the space lacks something.
/// `secrets` are this device's passwords, by account address (or
/// `secret:calendar-<id>`); `home` the address whose mailbox holds the
/// space, which is never removed by a round.
pub async fn round(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    secrets: Vec<(String, String)>,
    me: &Me,
    home: Option<&str>,
) -> Result<Round> {
    let local = lock(store).space_local()?;
    let opened = match open_checked(t, me, &local.guard).await {
        Err(SyncError::Space(SpaceError::NotLinked)) => return Ok(Round::Unlinked),
        Err(SyncError::Space(SpaceError::Newer)) => return Ok(Round::Newer),
        Err(SyncError::NoSpace) => {
            return moved_to(t)
                .await?
                .map(Round::Moved)
                .ok_or(SyncError::NoSpace)
        }
        r => r?,
    };
    Ok(Round::Done(Box::new(
        settle(t, store, &secrets, me, home, opened, local).await?,
    )))
}

/// Whether this device changed something the space doesn't have yet,
/// without going to the server. Stamps the changes as it finds them, so
/// they are ordered by when they were made, not by when a round ran.
pub fn dirty(store: &Mutex<Store>, secrets: &[(String, String)], me: &Me) -> Result<bool> {
    let mut s = lock(store);
    let mut local = s.space_local()?;
    if !local.started {
        return Ok(true);
    }
    let digest = digest_for(me);
    s.space_scan(
        &mut local,
        secrets,
        &digest,
        &me.device.id,
        space_merge::now_ms(),
        None,
    )?;
    strip(&mut local.doc, &digest);
    s.set_space_local(&local)?;
    Ok(local.unpushed)
}

/// What this device last knew of the space: a removal waiting for the
/// person, an older copy refused, a newer version's space.
pub fn state(store: &Mutex<Store>) -> Result<Local> {
    Ok(lock(store).space_local()?)
}

/// The person confirmed removing an account another device removed: the
/// next round lists it in [Applied::remove].
pub fn confirm_removal(store: &Mutex<Store>, account: crate::AccountId) -> Result<()> {
    let s = lock(store);
    let Some(gid) = s.account_gid(account)? else {
        return Ok(());
    };
    let mut local = s.space_local()?;
    if local.held.remove(&gid).is_some() {
        local.removing.insert(gid);
        s.set_space_local(&local)?;
    }
    Ok(())
}

/// The person keeps an account another device removed: it is written
/// again, with its rows, and comes back on the other devices.
pub fn keep_account(store: &Mutex<Store>, account: crate::AccountId) -> Result<()> {
    let s = lock(store);
    let Some(gid) = s.account_gid(account)? else {
        return Ok(());
    };
    let mut local = s.space_local()?;
    if let Some(rows) = local.held.remove(&gid) {
        // Forgotten rows are new on the next look: stamped, they win.
        for key in rows
            .iter()
            .cloned()
            .chain([Local::key("account", &gid), Local::key(SECRETS, &gid)])
        {
            local.here.remove(&key);
            if let Some((t, g)) = key.split_once('/') {
                if let Some(table) = local.doc.get_mut(t) {
                    table.remove(g);
                }
            }
        }
        local.unpushed = true;
        s.set_space_local(&local)?;
    }
    Ok(())
}

/// Turns sync on: a new space with this device's store. Returns the
/// recovery key, to be shown once.
pub async fn create(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    secrets: Vec<(String, String)>,
    me: &Me,
) -> Result<Key> {
    let digest = digest_for(me);
    let mut local = {
        let s = lock(store);
        s.space_forget()?;
        s.space_local()?
    };
    lock(store).space_scan(
        &mut local,
        &secrets,
        &digest,
        &me.device.id,
        space_merge::now_ms(),
        None,
    )?;
    let (mut space, recovery) = Space::create(
        &me.device,
        space::Content {
            generation: 1,
            updated_at: space::now(),
            updated_by: me.device.id.clone(),
            tables: writable(&local.doc),
            ..Default::default()
        },
    );
    space.link(&me.device);
    let older: Vec<String> = t
        .notes()
        .await?
        .into_iter()
        .filter(|(_, n)| matches!(n, Note::Space(_)))
        .map(|(id, _)| id)
        .collect();
    put(t, &space, &older).await?;
    strip(&mut local.doc, &digest);
    local.started = true;
    local.unpushed = false;
    local.guard = guard_for(me, &space);
    lock(store).set_space_local(&local)?;
    Ok(recovery)
}

/// Where the space went when it left this mailbox, if it did.
async fn moved_to(t: &mut impl Transport) -> Result<Option<String>> {
    Ok(t.notes()
        .await?
        .into_iter()
        .rev()
        .find_map(|(_, n)| match n {
            Note::Moved(email) => Some(email),
            _ => None,
        }))
}

/// Moves the space from one mailbox to another: the same space, key and
/// devices, so nobody pairs again. The old folder keeps only a note with
/// the new address (`to_mailbox`), for the other devices to follow.
pub async fn relocate(
    from: &mut impl Transport,
    to: &mut impl Transport,
    to_mailbox: &str,
    store: &Mutex<Store>,
    me: &Me,
) -> Result<Space> {
    let mut local = lock(store).space_local()?;
    let mut space = open_checked(from, me, &local.guard).await?.space;
    let there = to.notes().await?;
    if let Some(sealed) = newest(&there) {
        if Space::open_as(sealed, &me.device.id, &me.secret).is_err() {
            return Err(SyncError::Taken);
        }
    }
    // What an earlier stay left there (an old copy, a note it moved on).
    let stale: Vec<String> = there.into_iter().map(|(id, _)| id).collect();
    to.remove(&stale).await?;
    space.content.generation += 1;
    space.link(&me.device);
    put(to, &space, &[]).await?;
    let old: Vec<String> = from.notes().await?.into_iter().map(|(id, _)| id).collect();
    from.put(&Note::Moved(to_mailbox.to_owned())).await?;
    from.remove(&old).await?;
    local.guard = guard_for(me, &space);
    lock(store).set_space_local(&local)?;
    Ok(space)
}

/// On the new device: posts a pairing request with `code` and returns
/// what waits for the answer.
pub async fn request(t: &mut impl Transport, code: &str, me: &Me) -> Result<Pairing> {
    post(t, space::pair_start(code, &me.device)).await
}

/// [request] with a scanned invite's code: the device that showed it
/// answers on its own.
pub async fn request_qr(t: &mut impl Transport, code: &str, me: &Me) -> Result<Pairing> {
    post(t, space::pair_start_qr(code, &me.device)).await
}

async fn post(t: &mut impl Transport, pairing: Pairing) -> Result<Pairing> {
    t.put(&Note::Request(pairing.request.clone())).await?;
    Ok(pairing)
}

/// On the new device: looks once for the answer to `pairing`. Some(key)
/// when it came, None while it hasn't.
pub async fn answer(t: &mut impl Transport, pairing: &Pairing) -> Result<Option<PairAnswer>> {
    let id = &pairing.request.id;
    for (_, note) in t.notes().await? {
        match note {
            Note::Answer(a) if &a.request == id => return Ok(Some(a)),
            Note::Refused(r) if &r == id => return Err(SyncError::Refused),
            _ => {}
        }
    }
    if pairing.request.expired(space::now()) {
        return Err(SyncError::Expired);
    }
    Ok(None)
}

/// On the new device: waits for the answer, then links itself and takes
/// the space in. `secrets` are the passwords it has (the mailbox it
/// signed in to).
#[allow(clippy::too_many_arguments)]
pub async fn join(
    t: &mut impl Transport,
    pairing: Pairing,
    store: &Mutex<Store>,
    secrets: Vec<(String, String)>,
    me: &Me,
    home: Option<&str>,
    every: Duration,
) -> Result<Report> {
    let answer = loop {
        if let Some(a) = answer(t, &pairing).await? {
            break a;
        }
        tokio::time::sleep(every).await;
    };
    let request = pairing.request.id.clone();
    let key = pairing.finish(&answer)?;
    let notes = t.notes().await?;
    let opened = open_copies(&notes, &Guard::default(), None, |s| {
        Space::open_with(s, &key)
    })?;
    let report = start(t, store, &secrets, me, home, opened).await?;
    clean_pairing(t, &request).await?;
    Ok(report)
}

/// On a new device with the recovery phrase in place of a code.
pub async fn recover(
    t: &mut impl Transport,
    phrase: &str,
    store: &Mutex<Store>,
    secrets: Vec<(String, String)>,
    me: &Me,
    home: Option<&str>,
) -> Result<Report> {
    let recovery = Key::from_phrase(phrase)?;
    let notes = t.notes().await?;
    if !notes.iter().any(|(_, n)| matches!(n, Note::Space(_))) {
        return Err(SyncError::NoSpace);
    }
    let opened = open_copies(&notes, &Guard::default(), None, |s| {
        Space::open_recovery(s, &recovery)
    })?;
    start(t, store, &secrets, me, home, opened).await
}

/// A device joins: what it held before stays, and joins the space beside
/// what the space has (which wins where both have the same row).
async fn start(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    secrets: &[(String, String)],
    me: &Me,
    home: Option<&str>,
    opened: Opened,
) -> Result<Report> {
    lock(store).space_forget()?;
    settle(t, store, secrets, me, home, opened, Local::default()).await
}

/// On a linked device: the pairing requests still waiting, newest first.
/// Requests made with a QR invite are left out: nobody types their code.
pub async fn requests(t: &mut impl Transport) -> Result<Vec<PairRequest>> {
    let mut waiting = waiting(t.notes().await?);
    waiting.retain(|r| !r.qr());
    Ok(waiting)
}

/// On the linked device showing QR invites: answers every request made
/// with one of `codes`, the invites it showed lately, each with its own.
/// Requests naming another invite are left alone. A request that lies
/// about its invite gets an answer only the code's holder could open, so
/// there is nothing to check first. Returns the names of the devices
/// answered.
pub async fn answer_invite(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    codes: &[String],
    me: &Me,
) -> Result<Vec<String>> {
    let notes = t.notes().await?;
    let asking: Vec<(PairRequest, &String)> = waiting(notes.clone())
        .into_iter()
        .filter_map(|r| {
            let tag = r.invite.as_deref()?;
            let code = codes.iter().find(|c| space::invite_tag(c) == tag)?;
            Some((r, code))
        })
        .collect();
    if asking.is_empty() {
        return Ok(Vec::new());
    }
    let guard = lock(store).space_local()?.guard;
    let current = guarded_key(me, &guard);
    let space = open_copies(&notes, &guard, current.as_ref(), |s| {
        Space::open_as(s, &me.device.id, &me.secret)
    })?
    .space;
    let mut names = Vec::new();
    for (r, code) in asking {
        let answer = space::pair_answer(code, &r, &me.device.name, space.content_key());
        t.put(&Note::Answer(answer)).await?;
        names.push(r.device.name);
    }
    Ok(names)
}

/// The requests among `notes` still waiting, newest first.
fn waiting(notes: Vec<(String, Note)>) -> Vec<PairRequest> {
    let done: Vec<String> = notes
        .iter()
        .filter_map(|(_, n)| match n {
            Note::Answer(a) => Some(a.request.clone()),
            Note::Refused(r) => Some(r.clone()),
            _ => None,
        })
        .collect();
    let now = space::now();
    let mut waiting: Vec<PairRequest> = notes
        .into_iter()
        .filter_map(|(_, n)| match n {
            Note::Request(r) if !done.contains(&r.id) && !r.expired(now) => Some(r),
            _ => None,
        })
        .collect();
    waiting.reverse();
    waiting
}

/// On a linked device: approves the request `id`, still waiting, with the
/// code the person typed. Reads the folder once, for a quick answer.
pub async fn approve_waiting(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    id: &str,
    code: &str,
    me: &Me,
) -> Result<()> {
    let notes = t.notes().await?;
    let request = waiting(notes.clone())
        .into_iter()
        .find(|r| r.id == id)
        .ok_or(SyncError::Expired)?;
    let guard = lock(store).space_local()?.guard;
    let current = guarded_key(me, &guard);
    let space = open_copies(&notes, &guard, current.as_ref(), |s| {
        Space::open_as(s, &me.device.id, &me.secret)
    })?
    .space;
    let answer = space::pair_answer(code, &request, &me.device.name, space.content_key());
    t.put(&Note::Answer(answer)).await?;
    Ok(())
}

/// On a linked device: approves a request with the code the person typed.
pub async fn approve(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    request: &PairRequest,
    code: &str,
    me: &Me,
) -> Result<()> {
    let space = open(t, store, me).await?;
    let answer = space::pair_answer(code, request, &me.device.name, space.content_key());
    t.put(&Note::Answer(answer)).await?;
    Ok(())
}

/// On a linked device: "Not me".
pub async fn refuse(t: &mut impl Transport, request: &str) -> Result<()> {
    t.put(&Note::Refused(request.to_owned())).await?;
    Ok(())
}

/// After an unlink: the new recovery key, and the addresses whose
/// passwords the unlinked device had. A new content key keeps it out of
/// the space, but it still knows them: they should be changed.
pub struct Unlinked {
    pub recovery: Key,
    pub exposed: Vec<String>,
    pub space: Space,
}

impl std::fmt::Debug for Unlinked {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Unlinked")
            .field("exposed", &self.exposed)
            .finish_non_exhaustive()
    }
}

/// The addresses of the accounts whose passwords `space` carries.
pub fn passwords_in(space: &Space) -> Vec<String> {
    let t = &space.content.tables;
    let mut out: Vec<String> = t
        .get(SECRETS)
        .into_iter()
        .flatten()
        .filter(|(_, r)| !r.del && r.v.get("for").and_then(|v| v.as_str()) != Some("calendar"))
        .filter_map(|(gid, _)| {
            let a = t.get("account")?.get(gid).filter(|r| !r.del)?;
            Some(a.v.get("email")?.as_str()?.to_owned())
        })
        .collect();
    out.sort();
    out
}

/// Unlinks a device: a new content key and recovery phrase.
pub async fn unlink(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    device: &str,
    me: &Me,
) -> Result<Unlinked> {
    let mut local = lock(store).space_local()?;
    let opened = open_checked(t, me, &local.guard).await?;
    let mut space = opened.space;
    let exposed = passwords_in(&space);
    let recovery = space.unlink(device);
    space.content.generation += 1;
    space.content.updated_at = space::now();
    space.content.updated_by.clone_from(&me.device.id);
    space.link(&me.device);
    put(t, &space, &opened.ids).await?;
    local.guard = guard_for(me, &space);
    lock(store).set_space_local(&local)?;
    Ok(Unlinked {
        recovery,
        exposed,
        space,
    })
}

/// Turns sync off on this device: it leaves the space, whose key stays
/// with the others (this device was trusted, so nothing changes for
/// them). The last device deletes the space from the mailbox. Returns
/// whether it was the last.
pub async fn leave(t: &mut impl Transport, store: &Mutex<Store>, me: &Me) -> Result<bool> {
    let guard = lock(store).space_local()?.guard;
    let opened = open_checked(t, me, &guard).await?;
    let mut space = opened.space;
    space.content.devices.retain(|d| d.id != me.device.id);
    let last = space.content.devices.is_empty();
    if last {
        let all: Vec<String> = t.notes().await?.into_iter().map(|(id, _)| id).collect();
        t.remove(&all).await?;
    } else {
        space.content.generation += 1;
        put(t, &space, &opened.ids).await?;
    }
    lock(store).space_forget()?;
    Ok(last)
}

/// Drops a finished pairing's notes, and any expired request.
async fn clean_pairing(t: &mut impl Transport, request: &str) -> Result<()> {
    let now = space::now();
    let gone: Vec<String> = t
        .notes()
        .await?
        .into_iter()
        .filter(|(_, n)| match n {
            Note::Request(r) => r.id == request || r.expired(now),
            Note::Answer(a) => a.request == request,
            Note::Refused(r) => r == request,
            Note::Space(_) | Note::Moved(_) => false,
        })
        .map(|(id, _)| id)
        .collect();
    t.remove(&gone).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Account, AccountKind, Security, Server};

    fn me() -> Me {
        let secret = Key::generate();
        Me {
            device: Device {
                id: "mac".into(),
                name: "MacBook".into(),
                kind: "laptop".into(),
                last_seen: 0,
                public: space::public_key(&secret),
            },
            secret,
        }
    }

    /// The first round of an updated build over an old build's space:
    /// converted once, written in the new format, the old copy gone, and
    /// nothing here lost or doubled.
    #[tokio::test]
    async fn the_old_format_is_converted_once() {
        let me = me();
        let store = Mutex::new(Store::open_in_memory().unwrap());
        let server = |host: &str| Server {
            host: host.into(),
            port: 993,
            security: Security::Tls,
        };
        let id = lock(&store)
            .add_account(&Account {
                id: crate::AccountId(0),
                name: "Personal".into(),
                email: "matteo@posta.it".into(),
                sender_name: String::new(),
                color: "#E0782F".into(),
                kind: AccountKind::Imap {
                    imap: server("imap.posta.it"),
                    smtp: server("smtp.posta.it"),
                    username: "matteo@posta.it".into(),
                },
            })
            .unwrap();
        lock(&store).set_setting("notify.mode", "all").unwrap();
        let key = Key::generate();
        let old = serde_json::json!({
            "schema": 60, "updated_at": 1_760_000_000, "updated_by": "mac",
            "tables": {
                "account": [{"id": 9, "name": "Personal", "email": "matteo@posta.it",
                              "color": "#E0782F", "kind": "imap", "sender_name": ""}],
                "setting": [{"key": "notify.mode", "value": "all"},
                            {"key": "notify.loud.9", "value": "off"}]
            },
            "passwords": [["matteo@posta.it", "pw"]],
            "devices": [me.device], "recovery": ""
        });
        let mut t = Memory::new();
        t.put(&Note::Space(space::sealed_v1(
            std::slice::from_ref(&me.device),
            &key,
            &old,
        )))
        .await
        .unwrap();
        let secrets = vec![("matteo@posta.it".to_owned(), "pw".to_owned())];
        let Round::Done(r) = round(&mut t, &store, secrets.clone(), &me, None)
            .await
            .unwrap()
        else {
            panic!("expected a round")
        };
        assert!(r.pushed);
        let notes = t.snapshot();
        assert_eq!(notes.len(), 1);
        let Note::Space(s) = &notes[0].1 else {
            panic!("expected the space")
        };
        assert!(!s.is_v1());
        assert_eq!(lock(&store).accounts().unwrap().len(), 1);
        // The old space's setting for its account 9 is this device's own.
        assert_eq!(
            lock(&store)
                .setting(&format!("notify.loud.{}", id.0))
                .unwrap()
                .as_deref(),
            Some("off")
        );
        // Settled: at most one more write (columns the old space lacked,
        // filled from here), then none.
        round(&mut t, &store, secrets.clone(), &me, None)
            .await
            .unwrap();
        let Round::Done(r) = round(&mut t, &store, secrets, &me, None).await.unwrap() else {
            panic!("expected a round")
        };
        assert!(!r.pushed);
        // An old copy put back after it is refused.
        t.put(&Note::Space(space::sealed_v1(
            std::slice::from_ref(&me.device),
            &key,
            &old,
        )))
        .await
        .unwrap();
        let Round::Done(r) = round(&mut t, &store, Vec::new(), &me, None).await.unwrap() else {
            panic!("expected a round")
        };
        assert_eq!(r.refused, 0);
        assert_eq!(t.snapshot().len(), 1);
    }
}
