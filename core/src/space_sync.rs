//! The sync space over IMAP or JMAP: reading it from the hidden folder of
//! the mailbox that holds it, writing it back, and pairing a new device.
//! [crate::space] does the crypto; this moves the notes.

use std::sync::Mutex;
use std::time::Duration;

use crate::remote::{Remote, RemoteError};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::space::{
    self, Content, Device, Key, Note, PairAnswer, PairRequest, Pairing, SealedSpace, Space,
    SpaceError,
};
use crate::{AccountId, Store};

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
}

pub type Result<T> = std::result::Result<T, SyncError>;

/// This device, as the space knows it, with its secret.
#[derive(Debug, Clone)]
pub struct Me {
    pub device: Device,
    pub secret: Key,
}

/// The newest space in the folder, with its id there.
pub async fn fetch(remote: &mut Remote) -> Result<Option<(String, SealedSpace)>> {
    Ok(remote
        .space_notes()
        .await?
        .into_iter()
        .rev()
        .find_map(|(id, n)| match n {
            Note::Space(s) => Some((id, s)),
            _ => None,
        }))
}

/// Whether the mailbox holds a space, without opening it: for "We found
/// your space".
pub async fn found(remote: &mut Remote) -> Result<bool> {
    Ok(fetch(remote).await?.is_some())
}

/// Writes `space` and drops the older copies.
pub async fn put(remote: &mut Remote, mailbox: &str, space: &Space) -> Result<()> {
    let older: Vec<String> = remote
        .space_notes()
        .await?
        .into_iter()
        .filter(|(_, n)| matches!(n, Note::Space(_)))
        .map(|(id, _)| id)
        .collect();
    remote
        .space_put(&Note::Space(space.seal()).to_message(mailbox, space::now()))
        .await?;
    remote.space_remove(&older).await?;
    Ok(())
}

/// What this device's store holds, for the space; `passwords` by address.
pub fn content(store: &Mutex<Store>, passwords: Vec<(String, String)>, me: &Me) -> Result<Content> {
    let store = lock(store);
    Ok(Content {
        schema: store.schema_version()?,
        updated_at: space::now(),
        updated_by: me.device.id.clone(),
        tables: store.space_tables()?,
        passwords,
        ..Content::default()
    })
}

/// Turns sync on: a new space with this device's store. Returns the
/// recovery key, to be shown once.
pub async fn create(
    remote: &mut Remote,
    mailbox: &str,
    store: &Mutex<Store>,
    passwords: Vec<(String, String)>,
    me: &Me,
) -> Result<Key> {
    let (space, recovery) = Space::create(&me.device, content(store, passwords, me)?);
    put(remote, mailbox, &space).await?;
    Ok(recovery)
}

/// Opens the space as this device.
pub async fn open(remote: &mut Remote, me: &Me) -> Result<Space> {
    let (_, sealed) = fetch(remote).await?.ok_or(SyncError::NoSpace)?;
    Ok(Space::open_as(&sealed, &me.device.id, &me.secret)?)
}

/// Writes this device's store to the space, keeping its devices.
pub async fn push(
    remote: &mut Remote,
    mailbox: &str,
    store: &Mutex<Store>,
    passwords: Vec<(String, String)>,
    me: &Me,
) -> Result<Space> {
    let mut space = open(remote, me).await?;
    space.replace(content(store, passwords, me)?);
    space.link(&me.device);
    put(remote, mailbox, &space).await?;
    Ok(space)
}

/// Takes in what the space holds. Returns the passwords it carried, by
/// account id here, for the keychain.
pub fn take(store: &Mutex<Store>, space: &Space) -> Result<Vec<(AccountId, String)>> {
    let ids = lock(store).take_space_tables(&space.content.tables)?;
    Ok(space
        .content
        .passwords
        .iter()
        .filter_map(|(email, pw)| Some((*ids.get(&email.to_lowercase())?, pw.clone())))
        .collect())
}

/// Where the space went when it left this mailbox, if it did.
async fn moved_to(remote: &mut Remote) -> Result<Option<String>> {
    Ok(remote
        .space_notes()
        .await?
        .into_iter()
        .rev()
        .find_map(|(_, n)| match n {
            Note::Moved(email) => Some(email),
            _ => None,
        }))
}

/// Moves the space from `from`'s mailbox to `to`'s: the same space, key
/// and devices, so nobody pairs again. The old folder keeps only a note
/// with the new address, for the other devices to follow.
pub async fn relocate(
    from: &mut Remote,
    from_mailbox: &str,
    to: &mut Remote,
    to_mailbox: &str,
    me: &Me,
) -> Result<Space> {
    let mut space = open(from, me).await?;
    space.link(&me.device);
    if let Some((_, there)) = fetch(to).await? {
        if Space::open_as(&there, &me.device.id, &me.secret).is_err() {
            return Err(SyncError::Taken);
        }
    }
    // What an earlier stay left there (an old copy, a note it moved on).
    let stale: Vec<String> = to
        .space_notes()
        .await?
        .into_iter()
        .map(|(id, _)| id)
        .collect();
    to.space_remove(&stale).await?;
    put(to, to_mailbox, &space).await?;
    let old: Vec<String> = from
        .space_notes()
        .await?
        .into_iter()
        .map(|(id, _)| id)
        .collect();
    from.space_put(&Note::Moved(to_mailbox.to_owned()).to_message(from_mailbox, space::now()))
        .await?;
    from.space_remove(&old).await?;
    Ok(space)
}

/// On the new device: posts a pairing request with `code` and returns
/// what waits for the answer.
pub async fn request(remote: &mut Remote, mailbox: &str, code: &str, me: &Me) -> Result<Pairing> {
    post(remote, mailbox, space::pair_start(code, &me.device)).await
}

/// [request] with a scanned invite's code: the device that showed it
/// answers on its own.
pub async fn request_qr(
    remote: &mut Remote,
    mailbox: &str,
    code: &str,
    me: &Me,
) -> Result<Pairing> {
    post(remote, mailbox, space::pair_start_qr(code, &me.device)).await
}

async fn post(remote: &mut Remote, mailbox: &str, pairing: Pairing) -> Result<Pairing> {
    remote
        .space_put(&Note::Request(pairing.request.clone()).to_message(mailbox, space::now()))
        .await?;
    Ok(pairing)
}

/// On the new device: looks once for the answer to `pairing`. Some(key)
/// when it came, None while it hasn't.
pub async fn answer(remote: &mut Remote, pairing: &Pairing) -> Result<Option<PairAnswer>> {
    let id = &pairing.request.id;
    for (_, note) in remote.space_notes().await? {
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
/// the space in. Returns the space and the passwords it carried.
pub async fn join(
    remote: &mut Remote,
    mailbox: &str,
    pairing: Pairing,
    store: &Mutex<Store>,
    me: &Me,
    every: Duration,
) -> Result<(Space, Vec<(AccountId, String)>)> {
    let answer = loop {
        if let Some(a) = answer(remote, &pairing).await? {
            break a;
        }
        tokio::time::sleep(every).await;
    };
    let request = pairing.request.id.clone();
    let key = pairing.finish(&answer)?;
    let (_, sealed) = fetch(remote).await?.ok_or(SyncError::NoSpace)?;
    let space = Space::open_with(&sealed, &key)?;
    let space = link_and_take(remote, mailbox, space, store, me).await?;
    clean_pairing(remote, &request).await?;
    Ok(space)
}

/// On a new device with the recovery phrase in place of a code.
pub async fn recover(
    remote: &mut Remote,
    mailbox: &str,
    phrase: &str,
    store: &Mutex<Store>,
    me: &Me,
) -> Result<(Space, Vec<(AccountId, String)>)> {
    let recovery = Key::from_phrase(phrase)?;
    let (_, sealed) = fetch(remote).await?.ok_or(SyncError::NoSpace)?;
    let space = Space::open_recovery(&sealed, &recovery)?;
    link_and_take(remote, mailbox, space, store, me).await
}

async fn link_and_take(
    remote: &mut Remote,
    mailbox: &str,
    mut space: Space,
    store: &Mutex<Store>,
    me: &Me,
) -> Result<(Space, Vec<(AccountId, String)>)> {
    let passwords = take(store, &space)?;
    space.link(&me.device);
    put(remote, mailbox, &space).await?;
    Ok((space, passwords))
}

/// On a linked device: the pairing requests still waiting, newest first.
/// Requests made with a QR invite are left out: nobody types their code.
pub async fn requests(remote: &mut Remote) -> Result<Vec<PairRequest>> {
    let mut waiting = waiting(remote.space_notes().await?);
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
    remote: &mut Remote,
    mailbox: &str,
    codes: &[String],
    me: &Me,
) -> Result<Vec<String>> {
    let notes = remote.space_notes().await?;
    let Some(sealed) = notes.iter().rev().find_map(|(_, n)| match n {
        Note::Space(s) => Some(s.clone()),
        _ => None,
    }) else {
        return Err(SyncError::NoSpace);
    };
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
    let space = Space::open_as(&sealed, &me.device.id, &me.secret)?;
    let mut names = Vec::new();
    for (r, code) in asking {
        let answer = space::pair_answer(code, &r, &me.device.name, space.content_key());
        remote
            .space_put(&Note::Answer(answer).to_message(mailbox, space::now()))
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
/// code the person typed. Reads the folder once, for a quick answer.
pub async fn approve_waiting(
    remote: &mut Remote,
    mailbox: &str,
    id: &str,
    code: &str,
    me: &Me,
) -> Result<()> {
    let notes = remote.space_notes().await?;
    let sealed = notes
        .iter()
        .rev()
        .find_map(|(_, n)| match n {
            Note::Space(s) => Some(s.clone()),
            _ => None,
        })
        .ok_or(SyncError::NoSpace)?;
    let request = waiting(notes)
        .into_iter()
        .find(|r| r.id == id)
        .ok_or(SyncError::Expired)?;
    let space = Space::open_as(&sealed, &me.device.id, &me.secret)?;
    let answer = space::pair_answer(code, &request, &me.device.name, space.content_key());
    remote
        .space_put(&Note::Answer(answer).to_message(mailbox, space::now()))
        .await?;
    Ok(())
}

/// On a linked device: approves a request with the code the person typed.
pub async fn approve(
    remote: &mut Remote,
    mailbox: &str,
    request: &PairRequest,
    code: &str,
    me: &Me,
) -> Result<()> {
    let space = open(remote, me).await?;
    let answer = space::pair_answer(code, request, &me.device.name, space.content_key());
    remote
        .space_put(&Note::Answer(answer).to_message(mailbox, space::now()))
        .await?;
    Ok(())
}

/// On a linked device: "Not me".
pub async fn refuse(remote: &mut Remote, mailbox: &str, request: &str) -> Result<()> {
    remote
        .space_put(&Note::Refused(request.to_owned()).to_message(mailbox, space::now()))
        .await?;
    Ok(())
}

/// Unlinks a device; returns the new recovery key, to be shown.
pub async fn unlink(remote: &mut Remote, mailbox: &str, device: &str, me: &Me) -> Result<Key> {
    let mut space = open(remote, me).await?;
    let recovery = space.unlink(device);
    space.link(&me.device);
    put(remote, mailbox, &space).await?;
    Ok(recovery)
}

/// Turns sync off on this device: it leaves the space, whose key stays
/// with the others (this device was trusted, so nothing changes for
/// them). The last device deletes the space from the mailbox. Returns
/// whether it was the last.
pub async fn leave(remote: &mut Remote, mailbox: &str, me: &Me) -> Result<bool> {
    let mut space = open(remote, me).await?;
    space.content.devices.retain(|d| d.id != me.device.id);
    if !space.content.devices.is_empty() {
        put(remote, mailbox, &space).await?;
        return Ok(false);
    }
    let all: Vec<String> = remote
        .space_notes()
        .await?
        .into_iter()
        .map(|(id, _)| id)
        .collect();
    remote.space_remove(&all).await?;
    Ok(true)
}

/// Drops a finished pairing's notes, and any expired request.
async fn clean_pairing(remote: &mut Remote, request: &str) -> Result<()> {
    let now = space::now();
    let gone: Vec<String> = remote
        .space_notes()
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
    remote.space_remove(&gone).await?;
    Ok(())
}

/// What this device last saw of the space, kept in its own settings:
/// fingerprints of what the space and this store held then, and when this
/// device last marked itself as seen.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Seen {
    pub remote: String,
    pub local: String,
    pub touched: i64,
}

/// How often a device that changes nothing still marks itself as seen,
/// for "active 2 hours ago".
const TOUCH_EVERY: i64 = 60 * 60;

/// A fingerprint of what a content carries, without who wrote it when.
pub fn fingerprint(content: &Content) -> String {
    let mut h = Sha256::new();
    h.update(serde_json::to_vec(&content.tables).expect("serializes"));
    h.update(serde_json::to_vec(&content.passwords).expect("serializes"));
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// What this store holds now, as [Seen] after `space` was written or
/// taken in.
pub fn seen(
    store: &Mutex<Store>,
    passwords: Vec<(String, String)>,
    me: &Me,
    space: &Space,
) -> Result<Seen> {
    Ok(Seen {
        remote: fingerprint(&space.content),
        local: fingerprint(&content(store, passwords, me)?),
        touched: space::now(),
    })
}

/// What a sync round did.
#[derive(Debug)]
pub enum Round {
    /// Nothing changed on either side.
    Same(Space, Seen),
    /// This device's changes went to the space.
    Pushed(Space, Seen),
    /// Another device's changes came in; the passwords they carried are
    /// for the keychain, the accounts removed there are to remove here,
    /// then [seen] says what to keep.
    Took(Space, Vec<(AccountId, String)>, Vec<AccountId>),
    /// Another device unlinked this one.
    Unlinked,
    /// Another device moved the space to this address's mailbox.
    Moved(String),
}

/// One sync round: takes in another device's changes when this one has
/// none, writes this one's when it has. When both changed, this device's
/// win (the whole content is last-writer-wins).
pub async fn round(
    remote: &mut Remote,
    mailbox: &str,
    store: &Mutex<Store>,
    passwords: Vec<(String, String)>,
    me: &Me,
    last: &Seen,
) -> Result<Round> {
    let mut space = match open(remote, me).await {
        Err(SyncError::Space(SpaceError::NotLinked)) => return Ok(Round::Unlinked),
        Err(SyncError::NoSpace) => {
            return moved_to(remote)
                .await?
                .map(Round::Moved)
                .ok_or(SyncError::NoSpace)
        }
        r => r?,
    };
    let local = content(store, passwords, me)?;
    let fp = fingerprint(&local);
    let now = space::now();
    let mine = fp != last.local;
    let theirs = fingerprint(&space.content) != last.remote;
    if theirs && !mine {
        // Nothing changed here, so an account the space lacks was removed
        // on another device, not added on this one.
        let gone = lock(store).accounts_not_in(&space.content.tables)?;
        let passwords = take(store, &space)?;
        return Ok(Round::Took(space, passwords, gone));
    }
    if mine {
        space.replace(local);
    }
    if mine || now - last.touched >= TOUCH_EVERY {
        space.link(&me.device);
        put(remote, mailbox, &space).await?;
    }
    let seen = Seen {
        remote: fingerprint(&space.content),
        local: fp,
        touched: if mine || now - last.touched >= TOUCH_EVERY {
            now
        } else {
            last.touched
        },
    };
    Ok(if mine {
        Round::Pushed(space, seen)
    } else {
        Round::Same(space, seen)
    })
}

/// The sealed space's few readable things, for "We found your space";
/// None when the mailbox holds none.
pub async fn about(remote: &mut Remote) -> Result<Option<space::About>> {
    Ok(fetch(remote).await?.map(|(_, s)| s.about))
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}
