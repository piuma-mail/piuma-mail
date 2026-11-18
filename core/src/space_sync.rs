//! The sync space between devices: opening the copies a transport holds,
//! merging them with this device's rows ([crate::space_merge]), writing
//! the result back, and pairing a new device.
//!
//! The transport only stores and lists notes ([Transport]): today the
//! hidden folder of one of the person's mailboxes ([Folder]), later a
//! self-hosted companion. What is merged, the generation and the schema
//! rule live here and in [crate::space_merge], and know nothing of IMAP;
//! which copies are taken, by who signed them, in [crate::space_trust].

use std::future::Future;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::feedback::{log, Level};
use crate::remote::{Remote, RemoteError};
use crate::space::{
    self, Device, Key, Note, PairAnswer, PairRequest, Pairing, SealedSpace, Space, SpaceError,
};
use crate::space_log::{Entry, Member, Members, Op};
use crate::space_merge::{self, Local, Tables, FORMAT, SCHEMA, SECRETS};
use crate::space_trust::{self, Anchor, Trust};
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
    /// took, or not signed by a linked device: someone put an old copy
    /// back, or an unlinked device wrote one. Nothing is taken in.
    #[error("only an older copy of the space was found")]
    Rollback,
    /// This device was syncing with an older build: it trusts no copy
    /// until the person confirms it with the recovery phrase or a code.
    #[error("this device must be confirmed with the recovery phrase or a code")]
    Unverified,
    /// Two devices (these, by id) removed each other with nothing to tell
    /// which came first: nothing is taken until this device is linked
    /// again.
    #[error("two devices removed each other")]
    Conflict(Vec<String>),
    /// The space's generation can't count further.
    #[error("the space's generation is used up")]
    Generation,
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
/// None when the mailbox holds none. Unsigned and in the clear: the mail
/// provider can change them, so they decide nothing but what is shown.
pub async fn about(t: &mut impl Transport) -> Result<Option<space::About>> {
    Ok(newest(&t.notes().await?).map(|s| s.about.clone()))
}

/// This device as it writes itself in the space: with its signing key.
fn device(me: &Me) -> Device {
    Device {
        sign: space::sign_public(&me.secret),
        ..me.device.clone()
    }
}

fn b64(data: &[u8]) -> String {
    use base64::Engine as _;
    base64::engine::general_purpose::STANDARD.encode(data)
}

fn unb64(s: &str) -> Option<Vec<u8>> {
    use base64::Engine as _;
    base64::engine::general_purpose::STANDARD.decode(s).ok()
}

/// How a device opens the stored copies.
enum Opener<'a> {
    /// With its own wrap: a linked device.
    Me(&'a Me),
    /// With the content key a pairing handed over.
    Key(&'a Key),
    /// With the recovery phrase.
    Recovery(&'a Key),
}

impl Opener<'_> {
    fn open(&self, sealed: &SealedSpace) -> std::result::Result<Space, SpaceError> {
        match self {
            Opener::Me(me) => Space::open_as(sealed, &me.device.id, &me.secret),
            Opener::Key(key) => Space::open_with(sealed, key),
            Opener::Recovery(key) => Space::open_recovery(sealed, key),
        }
    }
}

/// The copies of the space this device takes, merged.
struct Opened {
    /// The newest copy taken, with the rows of the others merged in, the
    /// devices of all of them that still belong, and the log as this device
    /// now trusts it.
    space: Space,
    /// Every stored copy, to replace when writing.
    ids: Vec<String>,
    /// Copies left out.
    refused: u32,
    /// What this device trusts after taking them.
    trust: Trust,
    /// Who belongs after taking them.
    members: Members,
    /// The content key and recovery phrase must change before the next
    /// write: a device that left or was unlinked may know them, or two
    /// unlinks happened at once.
    rotate: bool,
    /// The newest copy taken, as stored, to put back if the folder ever
    /// holds only older ones.
    sealed: Option<SealedSpace>,
    /// This device is joining: it writes itself in whatever else changed.
    joining: bool,
    /// An older build's space, opened with the recovery phrase: it has no
    /// log yet, and this device begins one.
    convert: bool,
    /// The folder held no copy to take: this device starts from its own
    /// newest one and writes again.
    rewrite: bool,
}

/// Opens the stored copies, keeps those [space_trust::judge] takes, and
/// merges them. An older build's space (unsigned, no log) is opened only
/// with the recovery phrase, and only when the folder holds nothing newer:
/// anyone who can write to the folder could seal one for a device's own
/// wrap.
///
/// `own` is the newest copy a linked device took or wrote, from its own
/// database: when the folder holds copies it opens but none it can take
/// (older copies put back, or only copies by a device that left since), it
/// starts from that one and writes again, which puts the folder right.
fn open_copies(
    notes: &[(String, Note)],
    trust: &Trust,
    opener: Opener<'_>,
    anchor: Anchor<'_>,
    own: Option<&SealedSpace>,
) -> Result<Opened> {
    let linked = matches!(opener, Opener::Me(_));
    if linked && !trust.verified() {
        return Err(SyncError::Unverified);
    }
    let ids: Vec<String> = notes
        .iter()
        .filter(|(_, n)| matches!(n, Note::Space(_)))
        .map(|(id, _)| id.clone())
        .collect();
    let mut failed = 0;
    let mut newer = 0;
    let mut not_linked = false;
    let mut opened: Vec<(SealedSpace, Space)> = Vec::new();
    let mut v1 = Vec::new();
    for (_, note) in notes {
        let Note::Space(sealed) = note else { continue };
        if sealed.is_v1() {
            v1.push(sealed);
            continue;
        }
        newer += 1;
        match opener.open(sealed) {
            Ok(s) => opened.push((sealed.clone(), s)),
            Err(SpaceError::NotLinked) => not_linked = true,
            Err(SpaceError::Newer) => return Err(SpaceError::Newer.into()),
            Err(_) => failed += 1,
        }
    }
    let own = own
        .filter(|_| linked && !opened.is_empty())
        .and_then(|s| Some((s.clone(), opener.open(s).ok()?)));
    if opened.is_empty() {
        if matches!(opener, Opener::Recovery(_)) && newer == 0 && !v1.is_empty() {
            let mut last = SyncError::NoSpace;
            for sealed in v1.into_iter().rev() {
                match opener.open(sealed) {
                    Ok(space) => {
                        return Ok(Opened {
                            space,
                            ids,
                            refused: 0,
                            trust: Trust::default(),
                            members: Members::new(),
                            rotate: false,
                            sealed: None,
                            joining: false,
                            convert: true,
                            rewrite: false,
                        })
                    }
                    Err(e) => last = e.into(),
                }
            }
            return Err(last);
        }
        return Err(if !linked {
            if newer == 0 && v1.is_empty() {
                SyncError::NoSpace
            } else {
                SpaceError::Sealed.into()
            }
        } else if not_linked {
            SpaceError::NotLinked.into()
        } else if failed > 0 || !v1.is_empty() {
            log_refused(failed.max(1));
            SyncError::Rollback
        } else {
            SyncError::NoSpace
        });
    }
    let pairs: Vec<(&SealedSpace, &Space)> = opened.iter().map(|(a, b)| (a, b)).collect();
    let verdict = space_trust::judge(trust, anchor, &pairs);
    if !verdict.conflict.is_empty() {
        return Err(SyncError::Conflict(verdict.conflict.into_iter().collect()));
    }
    let refused = verdict.refused + failed;
    if refused > 0 {
        log_refused(refused);
    }
    let members = verdict.state.members;
    let top = verdict.accepted.iter().copied().max_by(|&a, &b| {
        let (sa, ca) = &opened[a];
        let (sb, cb) = &opened[b];
        (ca.content.generation, &sa.signer).cmp(&(cb.content.generation, &sb.signer))
    });
    let mut rotate = verdict.rotate;
    let rewrite = top.is_none();
    let (top_sealed, mut space) = match (top, own) {
        (Some(top), _) => opened[top].clone(),
        (None, Some((sealed, space))) => {
            // Its own newest copy: taken before, so trusted then; written
            // again with a new key if it was sealed for anyone gone since.
            rotate |= sealed.readers().any(|r| !members.contains_key(r))
                || Some(space.content.recovery_sign()) != verdict.state.recovery;
            (sealed, space)
        }
        (None, None) => {
            return Err(if !linked || not_linked {
                SpaceError::NotLinked.into()
            } else {
                SyncError::Rollback
            })
        }
    };
    for &i in &verdict.accepted {
        let other = &opened[i].1;
        space.content.horizon = space.content.horizon.max(other.content.horizon);
        if Some(i) == top {
            continue;
        }
        space_merge::merge(&mut space.content.tables, &other.content.tables);
        for d in &other.content.devices {
            match space.content.devices.iter_mut().find(|x| x.id == d.id) {
                Some(x) => x.last_seen = x.last_seen.max(d.last_seen),
                None => space.content.devices.push(d.clone()),
            }
        }
    }
    space
        .content
        .devices
        .retain(|d| members.contains_key(&d.id));
    space.content.log = verdict.trust.log.clone();
    Ok(Opened {
        space,
        ids,
        refused,
        trust: verdict.trust,
        members,
        rotate,
        sealed: Some(top_sealed),
        joining: false,
        convert: false,
        rewrite,
    })
}

fn log_refused(n: u32) {
    log(
        Level::Warn,
        "space",
        &format!("refused {n} copies of the sync space: older, or not signed by a linked device"),
    );
}

/// Opens the space as this device, as its trust (and its own newest copy)
/// allow.
async fn open_checked(t: &mut impl Transport, me: &Me, local: &Local) -> Result<Opened> {
    let notes = t.notes().await?;
    if !notes.iter().any(|(_, n)| matches!(n, Note::Space(_))) {
        return Err(SyncError::NoSpace);
    }
    let own = unb64(&local.last_copy).and_then(|b| SealedSpace::from_bytes(&b).ok());
    let opened = open_copies(
        &notes,
        &local.trust,
        Opener::Me(me),
        Anchor::Linked,
        own.as_ref(),
    )?;
    if !opened.members.contains_key(&me.device.id) {
        return Err(SpaceError::NotLinked.into());
    }
    Ok(opened)
}

/// Opens the space as this device.
pub async fn open(t: &mut impl Transport, store: &Mutex<Store>, me: &Me) -> Result<Space> {
    let local = lock(store).space_local()?;
    Ok(open_checked(t, me, &local).await?.space)
}

/// The generation after the newest one `trust` took and `space` claims.
fn next_generation(trust: &Trust, space: &Space) -> Result<u64> {
    trust
        .generation
        .max(space.content.generation)
        .checked_add(1)
        .filter(|g| *g <= space_trust::MAX_GENERATION)
        .ok_or(SyncError::Generation)
}

/// Seals `space` as `me` for the members `trust` names (and the recovery
/// phrase), lists this device as seen, writes it and drops the copies it
/// replaces. Returns it as stored.
async fn put(
    t: &mut impl Transport,
    space: &mut Space,
    me: &Me,
    trust: &Trust,
    older: &[String],
) -> Result<SealedSpace> {
    let members = trust.state().members;
    space.link(&device(me));
    space
        .content
        .devices
        .retain(|d| members.contains_key(&d.id));
    space.content.log = trust.log.clone();
    let sealed = space.seal_for(&me.device.id, &me.secret, &members);
    t.put(&Note::Space(sealed.clone())).await?;
    t.remove(older).await?;
    Ok(sealed)
}

/// An entry by this device, after the newest ones `trust` takes.
fn entry(trust: &Trust, op: Op, me: &Me) -> Entry {
    Entry::new(trust.state().heads, op, &me.device.id, &me.secret)
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
    /// Copies of the space left out: older, or not signed by a linked
    /// device.
    pub refused: u32,
    /// The merge changed the recovery phrase.
    pub recovery_changed: bool,
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
    /// This device trusts no copy yet (it was syncing with an older build
    /// of Piuma): nothing is taken or written until the person confirms it
    /// with the recovery phrase or a code from a linked device.
    Unverified,
    /// Two devices removed each other and nothing tells which came first
    /// (these, by id): nothing is taken or written until the person links
    /// this device again from a device they still have.
    Conflict(Vec<String>),
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
pub(crate) fn strip(doc: &mut Tables, digest: &dyn Fn(&str, &str) -> String) {
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

/// Saves `local` with its passwords as digests.
fn save(store: &Mutex<Store>, local: &Local, me: &Me) -> Result<()> {
    let mut kept = local.clone();
    strip(&mut kept.doc, &digest_for(me));
    lock(store).set_space_local(&kept)?;
    Ok(())
}

/// Merges `opened` with this store, puts in what came from other devices
/// and keeps the merged state in one transaction, then writes the result
/// when it holds something the space doesn't (or this device is new to
/// it, or due to mark itself as seen, or the key must change).
#[allow(clippy::too_many_arguments)]
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
        mut trust,
        rotate,
        sealed,
        joining,
        rewrite,
        ..
    } = opened;
    let now_ms = space_merge::now_ms();
    let digest = digest_for(me);
    // A device whose clock runs ahead wins no write for that: its stamps
    // come back to this clock's, and this device's next ones go past them.
    let clamped = space_merge::clamp(&mut remote.content.tables, now_ms + space_merge::MAX_SKEW);
    local.observe(&remote.content.tables);
    // Away since before the horizon: older rows the space no longer has
    // were removed, their tombstones gone.
    let stale = (local.started && local.last_merge < remote.content.horizon)
        .then_some(remote.content.horizon);
    lock(store).space_scan(
        &mut local,
        secrets,
        &digest,
        &me.device.id,
        now_ms,
        Some(&remote.content.tables),
        stale,
    )?;
    hydrate(&mut local.doc, &remote.content.tables);
    let mut merged = local.doc.clone();
    let won = space_merge::merge(&mut merged, &remote.content.tables);
    let horizon = space_merge::horizon(remote.content.devices.iter().map(|d| d.last_seen), now_ms)
        .max(remote.content.horizon);
    let mut kept = merged.clone();
    space_merge::compact(&mut kept, horizon);
    let outdated = remote.content.schema > SCHEMA;
    // A device that left or was unlinked may know the key and the phrase:
    // new ones, before anything is written with them.
    let rotated = rotate && !outdated;
    if rotated {
        remote.rotate();
        let phrase = entry(
            &trust,
            Op::Phrase {
                recovery: remote.content.recovery_sign(),
            },
            me,
        );
        trust.push(phrase);
    }
    local.trust = trust;
    local.started = true;
    local.last_merge = now_ms;
    local.refused = refused;
    local.outdated = outdated;
    local.conflict.clear();
    local.recovery_changed |= rotated;
    if let Some(s) = &sealed {
        local.last_copy = b64(&s.to_bytes());
    }
    local.doc = kept.clone();
    // What came in and what this device now knows of the space, together:
    // a crash after this never takes merged rows for changes made here.
    let applied = lock(store).space_apply(&mut local, &merged, &won, home, &digest)?;
    let rows = writable(&kept);
    let differs = clamped || !space_merge::same(&rows, &remote.content.tables);
    let now = space::now();
    let stale_seen = remote
        .content
        .devices
        .iter()
        .find(|d| d.id == me.device.id)
        .is_none_or(|d| now - d.last_seen >= TOUCH_EVERY);
    let pushed = !outdated
        && (joining
            || differs
            || stale_seen
            || ids.len() > 1
            || remote.converted()
            || rotated
            || rewrite);
    if pushed {
        remote.content.tables = rows;
        remote.content.generation = next_generation(&local.trust, &remote)?;
        remote.content.horizon = horizon;
        remote.content.format = FORMAT;
        remote.content.schema = SCHEMA;
        remote.content.updated_at = now;
        remote.content.updated_by.clone_from(&me.device.id);
        let sealed = put(t, &mut remote, me, &local.trust, &ids).await?;
        local.trust.generation = remote.content.generation;
        local.last_copy = b64(&sealed.to_bytes());
        local.unpushed = false;
        save(store, &local, me)?;
    }
    Ok(Report {
        space: remote,
        pushed,
        applied,
        outdated,
        refused,
        recovery_changed: local.recovery_changed,
    })
}

/// One sync round: merges this device's changes and the other devices',
/// row by row, and writes the result when the space lacks something.
/// `secrets` are this device's passwords, by account address (or
/// `secret:calendar-<id>`); `home` the address whose mailbox holds the
/// space, which is never removed by a round.
///
/// When the folder holds only copies this device refuses (older ones put
/// back, or copies from an unlinked device), it puts back the newest copy
/// it took, so the folder heals, and says [SyncError::Rollback].
pub async fn round(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    secrets: Vec<(String, String)>,
    me: &Me,
    home: Option<&str>,
) -> Result<Round> {
    let mut local = lock(store).space_local()?;
    if !local.trust.verified() {
        return Ok(Round::Unverified);
    }
    let opened = match open_checked(t, me, &local).await {
        Err(SyncError::Space(SpaceError::NotLinked)) => return Ok(Round::Unlinked),
        Err(SyncError::Space(SpaceError::Newer)) => return Ok(Round::Newer),
        Err(SyncError::NoSpace) => {
            return moved_to(t)
                .await?
                .map(Round::Moved)
                .ok_or(SyncError::NoSpace)
        }
        Err(SyncError::Rollback) => {
            heal(t, &local).await?;
            local.refused = local.refused.max(1);
            save(store, &local, me)?;
            return Err(SyncError::Rollback);
        }
        Err(SyncError::Conflict(ids)) => {
            local.conflict.clone_from(&ids);
            save(store, &local, me)?;
            return Ok(Round::Conflict(ids));
        }
        r => r?,
    };
    Ok(Round::Done(Box::new(
        settle(t, store, &secrets, me, home, opened, local).await?,
    )))
}

/// Puts back the newest copy this device took, signed by whoever wrote
/// it, in place of the refused ones.
async fn heal(t: &mut impl Transport, local: &Local) -> Result<()> {
    let Some(sealed) = unb64(&local.last_copy).and_then(|b| SealedSpace::from_bytes(&b).ok())
    else {
        return Ok(());
    };
    let refused: Vec<String> = t
        .notes()
        .await?
        .into_iter()
        .filter(|(_, n)| matches!(n, Note::Space(_)))
        .map(|(id, _)| id)
        .collect();
    t.put(&Note::Space(sealed)).await?;
    t.remove(&refused).await?;
    log(
        Level::Warn,
        "space",
        "put back the newest copy of the sync space",
    );
    Ok(())
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

/// The person saw the recovery phrase that a merge changed.
pub fn recovery_seen(store: &Mutex<Store>) -> Result<()> {
    let s = lock(store);
    let mut local = s.space_local()?;
    if local.recovery_changed {
        local.recovery_changed = false;
        s.set_space_local(&local)?;
    }
    Ok(())
}

/// The person changed the passwords an unlinked device knew.
pub fn exposed_done(store: &Mutex<Store>) -> Result<()> {
    let s = lock(store);
    let mut local = s.space_local()?;
    if !local.exposed.is_empty() {
        local.exposed.clear();
        local.exposed_device.clear();
        s.set_space_local(&local)?;
    }
    Ok(())
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
        local.removing.insert(gid.clone());
        local.confirmed.insert(gid);
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

/// Turns sync on: a new space with this device's store, its log beginning
/// with this device. Returns the recovery key, to be shown once.
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
        None,
    )?;
    let (mut space, recovery) = Space::create(
        &device(me),
        &me.secret,
        space::Content {
            generation: 1,
            updated_at: space::now(),
            updated_by: me.device.id.clone(),
            tables: writable(&local.doc),
            ..Default::default()
        },
    );
    let root = space.content.log[0].id();
    let trust = Trust::from_log(space.content.log.clone(), &root, 1);
    let older: Vec<String> = t
        .notes()
        .await?
        .into_iter()
        .filter(|(_, n)| matches!(n, Note::Space(_)))
        .map(|(id, _)| id)
        .collect();
    let sealed = put(t, &mut space, me, &trust, &older).await?;
    local.started = true;
    local.unpushed = false;
    local.last_merge = space_merge::now_ms();
    local.trust = trust;
    local.last_copy = b64(&sealed.to_bytes());
    save(store, &local, me)?;
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
    let opened = open_checked(from, me, &local).await?;
    let mut space = opened.space;
    let there = to.notes().await?;
    if let Some(sealed) = newest(&there) {
        if Space::open_as(sealed, &me.device.id, &me.secret).is_err() {
            return Err(SyncError::Taken);
        }
    }
    // What an earlier stay left there (an old copy, a note it moved on).
    let stale: Vec<String> = there.into_iter().map(|(id, _)| id).collect();
    to.remove(&stale).await?;
    space.content.generation = next_generation(&opened.trust, &space)?;
    let sealed = put(to, &mut space, me, &opened.trust, &[]).await?;
    let old: Vec<String> = from.notes().await?.into_iter().map(|(id, _)| id).collect();
    from.put(&Note::Moved(to_mailbox.to_owned())).await?;
    from.remove(&old).await?;
    local.trust = opened.trust;
    local.trust.generation = space.content.generation;
    local.last_copy = b64(&sealed.to_bytes());
    save(store, &local, me)?;
    Ok(space)
}

/// On the new device: posts a pairing request with `code` and returns
/// what waits for the answer.
pub async fn request(t: &mut impl Transport, code: &str, me: &Me) -> Result<Pairing> {
    post(t, space::pair_start(code, &device(me))).await
}

/// [request] with a scanned invite's code: the device that showed it
/// answers on its own.
pub async fn request_qr(t: &mut impl Transport, code: &str, me: &Me) -> Result<Pairing> {
    post(t, space::pair_start_qr(code, &device(me))).await
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

/// On the new device: waits for the answer, then takes the space in from
/// the log the approving device handed over, with its entry adding this
/// device. `secrets` are the passwords it has (the mailbox it signed in
/// to).
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
    let answered = pairing.finish(&answer)?;
    let key = answered.key()?;
    // The entry must add this very device, by the device that answered:
    // the request travelled in the clear, and its keys could have been
    // swapped on the way.
    let mine = Op::Add {
        device: Member::of(&device(me)),
    };
    if answered.entry.by != answered.by || answered.entry.op != mine {
        return Err(SpaceError::Code.into());
    }
    let notes = t.notes().await?;
    let opened = open_copies(
        &notes,
        &Trust::default(),
        Opener::Key(&key),
        Anchor::Paired {
            log: &answered.log,
            entry: &answered.entry,
        },
        None,
    )?;
    let report = start(t, store, &secrets, me, home, opened, None).await?;
    clean_pairing(t, &request).await?;
    Ok(report)
}

/// On a new device with the recovery phrase in place of a code: the
/// phrase in force adds it to the log. A space from an older build (no
/// log) begins one here: the phrase is what makes it trustworthy.
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
    let public = space::sign_public(&space::recovery_signer(&recovery));
    let opened = open_copies(
        &notes,
        &Trust::default(),
        Opener::Recovery(&recovery),
        Anchor::Phrase(&public),
        None,
    )?;
    start(t, store, &secrets, me, home, opened, Some(&recovery)).await
}

/// A device joins: what it held before stays, and joins the space beside
/// what the space has (which wins where both have the same row).
#[allow(clippy::too_many_arguments)]
async fn start(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    secrets: &[(String, String)],
    me: &Me,
    home: Option<&str>,
    mut opened: Opened,
    phrase: Option<&Key>,
) -> Result<Report> {
    let dev = device(me);
    if opened.convert {
        let recovery = phrase.ok_or(SpaceError::Sealed)?;
        opened.space.content.recovery = recovery.to_hex();
        let genesis = Entry::new(
            Vec::new(),
            Op::Genesis {
                device: Member::of(&dev),
                recovery: space::sign_public(&space::recovery_signer(recovery)),
            },
            &me.device.id,
            &me.secret,
        );
        let root = genesis.id();
        opened.trust = Trust::from_log(vec![genesis], &root, 0);
        // The older build's devices come back one by one, each confirmed
        // with the phrase or a code.
        opened.space.content.devices.clear();
    } else if let Some(recovery) = phrase {
        let add = Entry::new(
            opened.trust.state().heads,
            Op::Add {
                device: Member::of(&dev),
            },
            space::RECOVERY,
            &space::recovery_signer(recovery),
        );
        opened.trust.push(add);
    }
    opened.members = opened.trust.state().members;
    if !opened.members.contains_key(&me.device.id) {
        return Err(if phrase.is_some() {
            SpaceError::Sealed
        } else {
            SpaceError::NotLinked
        }
        .into());
    }
    lock(store).space_forget()?;
    opened.space.link(&dev);
    opened.joining = true;
    settle(t, store, secrets, me, home, opened, Local::default()).await
}

/// On a linked device: the pairing requests still waiting, newest first.
/// Requests made with a QR invite are left out: nobody types their code.
pub async fn requests(t: &mut impl Transport) -> Result<Vec<PairRequest>> {
    let mut waiting = waiting(t.notes().await?);
    waiting.retain(|r| !r.qr());
    Ok(waiting)
}

/// The space as this device's trust allows, to hand a new device: the
/// content key, and the log to start from.
async fn to_hand_over(t: &mut impl Transport, store: &Mutex<Store>, me: &Me) -> Result<Opened> {
    let local = lock(store).space_local()?;
    open_checked(t, me, &local).await
}

/// This device's answer to `request` with `code`: the content key, its
/// signed entry adding the device that asked, and the log it trusts.
fn answer_with(opened: &Opened, request: &PairRequest, code: &str, me: &Me) -> PairAnswer {
    let add = entry(
        &opened.trust,
        Op::Add {
            device: Member::of(&request.device),
        },
        me,
    );
    space::pair_answer(
        code,
        request,
        &device(me),
        opened.space.content_key(),
        add,
        opened.trust.log.clone(),
    )
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
    let asking: Vec<(PairRequest, &String)> = waiting(notes)
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
    let opened = to_hand_over(t, store, me).await?;
    let mut names = Vec::new();
    for (r, code) in asking {
        t.put(&Note::Answer(answer_with(&opened, &r, code, me)))
            .await?;
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
/// code the person typed, and adds the device that asked to the log.
pub async fn approve_waiting(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    id: &str,
    code: &str,
    me: &Me,
) -> Result<()> {
    let request = waiting(t.notes().await?)
        .into_iter()
        .find(|r| r.id == id)
        .ok_or(SyncError::Expired)?;
    approve(t, store, &request, code, me).await
}

/// On a linked device: approves a request with the code the person typed.
pub async fn approve(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    request: &PairRequest,
    code: &str,
    me: &Me,
) -> Result<()> {
    let opened = to_hand_over(t, store, me).await?;
    t.put(&Note::Answer(answer_with(&opened, request, code, me)))
        .await?;
    Ok(())
}

/// On a linked device: "Not me".
pub async fn refuse(t: &mut impl Transport, request: &str) -> Result<()> {
    t.put(&Note::Refused(request.to_owned())).await?;
    Ok(())
}

/// After an unlink: the new recovery key, and the addresses whose
/// passwords the unlinked device had. A new content key keeps it out of
/// the space, but it still knows them: they should be changed, the
/// mailbox that holds the space first (until then the device can still
/// write to its folder).
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

/// Unlinks a device: a signed log entry removing it, a new content key
/// and recovery phrase (and the entry naming the new phrase). Devices &
/// sync keeps asking for the passwords it knew to be changed until the
/// person says they were ([exposed_done]).
pub async fn unlink(
    t: &mut impl Transport,
    store: &Mutex<Store>,
    device_id: &str,
    me: &Me,
) -> Result<Unlinked> {
    let mut local = lock(store).space_local()?;
    let opened = open_checked(t, me, &local).await?;
    let mut trust = opened.trust;
    let mut space = opened.space;
    let exposed = passwords_in(&space);
    let name = space
        .content
        .devices
        .iter()
        .find(|d| d.id == device_id)
        .map(|d| d.name.clone())
        .unwrap_or_default();
    if opened.members.contains_key(device_id) && device_id != me.device.id {
        let remove = entry(
            &trust,
            Op::Remove {
                device: device_id.to_owned(),
            },
            me,
        );
        trust.push(remove);
    }
    let recovery = space.unlink(device_id);
    let phrase = entry(
        &trust,
        Op::Phrase {
            recovery: space.content.recovery_sign(),
        },
        me,
    );
    trust.push(phrase);
    space.content.generation = next_generation(&trust, &space)?;
    space.content.updated_at = space::now();
    space.content.updated_by.clone_from(&me.device.id);
    let sealed = put(t, &mut space, me, &trust, &opened.ids).await?;
    trust.generation = space.content.generation;
    local.trust = trust;
    local.last_copy = b64(&sealed.to_bytes());
    local.recovery_changed = false;
    if !exposed.is_empty() {
        local.exposed.clone_from(&exposed);
        local.exposed_device = name;
    }
    save(store, &local, me)?;
    Ok(Unlinked {
        recovery,
        exposed,
        space,
    })
}

/// Turns sync off on this device: it leaves with a signed log entry
/// removing itself, carried by one more copy next to the others. The first
/// remaining device that sees it changes the key and the phrase this
/// device knew. The last device deletes the space from the mailbox.
/// Returns whether it was the last.
///
/// A device that trusts nothing (an older build's, waiting to be
/// confirmed), stopped by removals that contradict each other, or whose
/// saved state is unreadable, writes nothing: it forgets the space here.
pub async fn leave(t: &mut impl Transport, store: &Mutex<Store>, me: &Me) -> Result<bool> {
    let saved = lock(store).space_local();
    let local = match saved {
        Ok(l) if l.trust.verified() && l.conflict.is_empty() => l,
        Ok(_) | Err(crate::StoreError::SpaceState(_)) => {
            lock(store).space_forget()?;
            return Ok(false);
        }
        Err(e) => return Err(e.into()),
    };
    let opened = match open_checked(t, me, &local).await {
        Ok(o) => o,
        Err(SyncError::Conflict(_) | SyncError::Space(SpaceError::NotLinked)) => {
            lock(store).space_forget()?;
            return Ok(false);
        }
        Err(e) => return Err(e),
    };
    let mut trust = opened.trust;
    let mut space = opened.space;
    let mut others = opened.members.clone();
    others.remove(&me.device.id);
    let last = others.is_empty();
    if last {
        let all: Vec<String> = t.notes().await?.into_iter().map(|(id, _)| id).collect();
        t.remove(&all).await?;
    } else {
        let gone = entry(
            &trust,
            Op::Remove {
                device: me.device.id.clone(),
            },
            me,
        );
        trust.push(gone);
        space.content.log = trust.log.clone();
        space.content.devices.retain(|d| d.id != me.device.id);
        space.content.generation = next_generation(&trust, &space)?;
        // The other copies stay: this one only carries the entry, and the
        // next device to write replaces them all.
        let sealed = space.seal_for(&me.device.id, &me.secret, &others);
        t.put(&Note::Space(sealed)).await?;
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
                sign: space::sign_public(&secret),
            },
            secret,
        }
    }

    /// An updated build over an old build's space: it trusts nothing it
    /// finds (anyone with the mailbox could have sealed a copy for its
    /// wrap) until the recovery phrase opens it; then it is converted once,
    /// written in the new format with a log beginning here, the old copy
    /// gone, and nothing here lost or doubled.
    #[tokio::test]
    async fn the_old_format_is_converted_once_from_the_phrase() {
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
        let phrase = Key::generate();
        let old = serde_json::json!({
            "schema": 60, "updated_at": 1_760_000_000, "updated_by": "mac",
            "tables": {
                "account": [{"id": 9, "name": "Personal", "email": "matteo@posta.it",
                              "color": "#E0782F", "kind": "imap", "sender_name": ""}],
                "setting": [{"key": "notify.mode", "value": "all"},
                            {"key": "notify.loud.9", "value": "off"}]
            },
            "passwords": [["matteo@posta.it", "pw"]],
            "devices": [me.device], "recovery": phrase.to_hex()
        });
        let v1 = || {
            Note::Space(space::sealed_v1(
                std::slice::from_ref(&me.device),
                &key,
                &old,
                Some(&phrase),
            ))
        };
        let mut t = Memory::new();
        t.put(&v1()).await.unwrap();
        let before = t.snapshot();
        let secrets = vec![("matteo@posta.it".to_owned(), "pw".to_owned())];
        // Its own wrap opens it, but so would one anyone made: nothing is
        // taken or written.
        assert!(matches!(
            round(&mut t, &store, secrets.clone(), &me, None).await,
            Ok(Round::Unverified)
        ));
        assert_eq!(t.snapshot(), before);
        assert!(matches!(
            open(&mut t, &store, &me).await,
            Err(SyncError::Unverified)
        ));
        let r = recover(&mut t, &phrase.phrase(), &store, secrets.clone(), &me, None)
            .await
            .unwrap();
        assert!(r.pushed);
        let notes = t.snapshot();
        assert_eq!(notes.len(), 1);
        let Note::Space(s) = &notes[0].1 else {
            panic!("expected the space")
        };
        assert!(!s.is_v1());
        assert_eq!(s.readers().collect::<Vec<_>>(), ["mac"]);
        assert_eq!(lock(&store).accounts().unwrap().len(), 1);
        // The old space's setting for its account 9 is this device's own.
        assert_eq!(
            lock(&store)
                .setting(&format!("notify.loud.{}", id.0))
                .unwrap()
                .as_deref(),
            Some("off")
        );
        // The same phrase stays: other devices confirm with it.
        let opened = open(&mut t, &store, &me).await.unwrap();
        assert_eq!(opened.recovery(), Some(phrase.clone()));
        // Settled: at most one more write (columns the old space lacked,
        // filled from here), then none.
        round(&mut t, &store, secrets.clone(), &me, None)
            .await
            .unwrap();
        let Round::Done(r) = round(&mut t, &store, secrets, &me, None).await.unwrap() else {
            panic!("expected a round")
        };
        assert!(!r.pushed);
        // An old copy put back after it is left out, and goes.
        t.put(&v1()).await.unwrap();
        let Round::Done(r) = round(&mut t, &store, Vec::new(), &me, None).await.unwrap() else {
            panic!("expected a round")
        };
        assert_eq!(r.refused, 0);
        assert_eq!(t.snapshot().len(), 1);
    }

    /// Saved trust that doesn't read is an error, never a fresh start.
    #[tokio::test]
    async fn damaged_trust_is_an_error_not_an_empty_state() {
        let me = me();
        let store = Mutex::new(Store::open_in_memory().unwrap());
        let mut t = Memory::new();
        create(&mut t, &store, Vec::new(), &me).await.unwrap();
        lock(&store).set_space_state_raw("{\"trust\": 7").unwrap();
        assert!(matches!(
            round(&mut t, &store, Vec::new(), &me, None).await,
            Err(SyncError::Store(crate::StoreError::SpaceState(_)))
        ));
        // Turning sync off still works: the state goes, nothing is written.
        let before = t.snapshot();
        assert!(!leave(&mut t, &store, &me).await.unwrap());
        assert_eq!(t.snapshot(), before);
        assert!(!state(&store).unwrap().trust.verified());
    }

    /// The generation never wraps around.
    #[test]
    fn the_generation_stops_counting_instead_of_wrapping() {
        let me = me();
        let (mut space, _) = Space::create(&me.device, &me.secret, space::Content::default());
        let trust = Trust {
            generation: u64::MAX,
            ..Trust::default()
        };
        assert!(matches!(
            next_generation(&trust, &space),
            Err(SyncError::Generation)
        ));
        space.content.generation = space_trust::MAX_GENERATION;
        assert!(matches!(
            next_generation(&Trust::default(), &space),
            Err(SyncError::Generation)
        ));
    }
}
