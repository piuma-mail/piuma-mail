//! Managing the mailbox: stars and the Starred list, deleting for good
//! and emptying Trash and spam, copying, the account's own folders
//! (rename, delete, show or hide), which folder does which job, how lists
//! are sorted, grouped and swiped, and how full each mailbox is.
//!
//! Every change to the server is queued first (`pending.rs`) and sent at
//! once when the server can be reached; offline it waits for the next
//! sync, and a change the server keeps refusing reaches the app as
//! `ChangesDropped`.

use std::collections::{BTreeMap, HashMap};
use std::sync::Mutex;

use flutter_rust_bridge::frb;
use piuma_core::imap::FolderRole;
use piuma_core::pending::Change;
use piuma_core::remote::{Remote, RemoteError, Snapshot};
use piuma_core::store::{ListSettings as CoreListSettings, Quota, SwipeAction as CoreSwipe};
use piuma_core::{AccountId, ListOrder as CoreOrder};

use crate::api::engine::{
    engine, in_conversation, inbox_row, reader, signed_in, store, with_files, EngineError,
    ErrorKind, InboxRow, MessageRef,
};

/// Stars emails, or takes their stars off: here at once, then on their
/// servers; offline, at the next sync.
pub async fn set_messages_flagged(
    messages: Vec<MessageRef>,
    flagged: bool,
) -> Result<(), EngineError> {
    store()?.queue_flags(&refs(&messages), flagged)?;
    send(accounts_of(&messages)).await;
    Ok(())
}

/// Starred emails of every account (or one), newest first, wherever they
/// are but Trash, spam and Drafts.
pub fn starred(account: Option<i64>) -> Result<Vec<InboxRow>, EngineError> {
    let store = store()?;
    let rows = store
        .starred(account.map(AccountId))?
        .into_iter()
        .map(|m| {
            let row = inbox_row(&store, m);
            in_conversation(&store, with_files(&store, row))
        })
        .collect::<Result<Vec<_>, EngineError>>()?;
    crate::api::engine::combine_rows(&store, rows)
}

/// The account's Trash, by its server name, once a sync found it.
#[frb(sync)]
pub fn trash_mailbox(account_id: i64) -> Result<Option<String>, EngineError> {
    Ok(reader()?.trash_mailbox(AccountId(account_id))?)
}

/// Whether Delete in this folder deletes for good, with no Undo: in Trash
/// and in spam.
#[frb(sync)]
pub fn deletes_for_good(account_id: i64, mailbox: String) -> Result<bool, EngineError> {
    Ok(reader()?.deletes_for_good(AccountId(account_id), &mailbox)?)
}

/// Splits messages into those Delete removes for good (in Trash or spam)
/// and the rest.
pub(crate) fn split_for_good(
    messages: Vec<MessageRef>,
) -> Result<(Vec<MessageRef>, Vec<MessageRef>), EngineError> {
    let store = store()?;
    let mut forever = Vec::new();
    let mut rest = Vec::new();
    for m in messages {
        if store.deletes_for_good(AccountId(m.account_id), &m.mailbox)? {
            forever.push(m);
        } else {
            rest.push(m);
        }
    }
    Ok((forever, rest))
}

/// Deletes emails for good, without Trash: they leave the lists at once
/// and their servers delete them now, or at the next sync when offline.
/// There is no Undo: the app asks first.
pub async fn delete_forever(messages: Vec<MessageRef>) -> Result<(), EngineError> {
    {
        let store = store()?;
        for ((account, mailbox), uids) in by_folder(&messages) {
            store.queue_erase(account, &mailbox, &uids)?;
        }
    }
    send(accounts_of(&messages)).await;
    Ok(())
}

/// How many emails a folder holds: what its server says, or what is here
/// when it can't be reached. For "Empty Trash" and "Delete folder", which
/// say how many go.
pub async fn folder_total(account_id: i64, mailbox: String) -> Result<u32, EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    let here = store()?.messages_in(id, &mailbox)?;
    let Ok((account, password)) = signed_in(id) else {
        return Ok(here);
    };
    let key = (account_id, mailbox.clone());
    let counted = engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let n = conn.count(&mailbox).await;
            conn.close().await;
            n
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    let mut counts = COUNTED.lock().unwrap_or_else(|e| e.into_inner());
    match counted {
        Ok((n, snapshot)) => {
            // What Empty, asked next, keeps to: mail that comes after
            // the person read the count stays.
            counts
                .get_or_insert_with(HashMap::new)
                .insert(key, snapshot);
            Ok(n)
        }
        Err(_) => {
            // The count shown is what is here, and so is all Empty may
            // take if the server comes back before the person confirms.
            let shared = engine.store.clone();
            let snapshot = Snapshot::here(&shared, id, &key.1)?;
            counts
                .get_or_insert_with(HashMap::new)
                .insert(key, snapshot);
            Ok(here)
        }
    }
}

/// What each folder held when [`folder_total`] counted it last.
static COUNTED: Mutex<Option<HashMap<(i64, String), Snapshot>>> = Mutex::new(None);

/// Empty Trash, Empty spam: every email of the folder goes for good.
/// Online, those on the server when [`folder_total`] counted them (or,
/// when it couldn't reach the server, only the ones here); offline, the
/// ones here, at the next sync. Refused for any other folder. Returns how many went (or will).
pub async fn empty_folder(account_id: i64, mailbox: String) -> Result<u32, EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    if !store()?.deletes_for_good(id, &mailbox)? {
        return Err(EngineError::new(
            ErrorKind::Other,
            "only Trash and spam can be emptied",
        ));
    }
    let (account, password) = signed_in(id)?;
    let shared = engine.store.clone();
    let target = mailbox.clone();
    let counted = COUNTED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_mut()
        .and_then(|c| c.remove(&(account_id, mailbox.clone())));
    // Never counted on the server: only what is here goes, never
    // everything the server holds.
    let snapshot = match counted {
        Some(s) => s,
        None => Snapshot::here(&shared, id, &mailbox)?,
    };
    let emptied = engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            // What waits goes first: a message put back from Trash leaves
            // it before Trash is emptied.
            let dropped = conn.send_pending(&shared, id).await?;
            crate::api::engine::changes_dropped(id, dropped);
            let n = conn.empty(&shared, id, &target, &snapshot).await?;
            conn.close().await;
            Ok::<_, RemoteError>(n as u32)
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    match emptied {
        Ok(n) => Ok(n),
        // What is here goes when the server can be reached.
        Err(e) if e.is_offline() => {
            let store = store()?;
            // Not one put back from Trash, or waiting for anything else.
            let uids = store.erasable_uids(id, &mailbox)?;
            store.queue_erase(id, &mailbox, &uids)?;
            Ok(uids.len() as u32)
        }
        Err(e) => Err(e.into()),
    }
}

/// Copies emails to one of their account's folders; they stay where they
/// are. The copies show when that folder is next looked at.
pub async fn copy_messages_to(
    messages: Vec<MessageRef>,
    target: String,
) -> Result<(), EngineError> {
    {
        let store = store()?;
        for m in &messages {
            store.queue_change(
                AccountId(m.account_id),
                &m.mailbox,
                m.uid,
                Change::CopyTo(target.clone()),
            )?;
        }
    }
    send(accounts_of(&messages)).await;
    Ok(())
}

/// Renames one of the account's own folders. Returns its server name now,
/// which changes on IMAP (subfolders with it) and not on JMAP.
pub async fn rename_folder(
    account_id: i64,
    mailbox: String,
    name: String,
) -> Result<String, EngineError> {
    if name.trim().is_empty() {
        return Err(EngineError::new(ErrorKind::Other, "empty folder name"));
    }
    let to = store()?.rename_folder(AccountId(account_id), &mailbox, &name)?;
    send(vec![account_id]).await;
    Ok(to)
}

/// What deleting a folder takes with it: its emails and its subfolders'
/// (they go to Trash), and how many subfolders.
pub struct FolderContents {
    pub emails: u32,
    pub subfolders: u32,
    /// The inbox or a folder with a job inside it (or the folder itself),
    /// by the name people read: then it isn't deleted.
    pub protected: Option<String>,
}

#[frb(sync)]
pub fn folder_contents(account_id: i64, mailbox: String) -> Result<FolderContents, EngineError> {
    let store = reader()?;
    let id = AccountId(account_id);
    let (emails, subfolders) = store.folder_contents(id, &mailbox)?;
    Ok(FolderContents {
        emails,
        subfolders,
        protected: store.protected_inside(id, &mailbox)?,
    })
}

/// Deletes one of the account's own folders and its subfolders; their
/// emails go to Trash first. Refused for one that is or holds the inbox
/// or a folder with a job.
pub async fn delete_folder(account_id: i64, mailbox: String) -> Result<(), EngineError> {
    if store()?
        .delete_folder(AccountId(account_id), &mailbox)?
        .is_none()
    {
        return Err(EngineError::new(
            ErrorKind::Other,
            "the folder holds the inbox or a folder with a job",
        ));
    }
    send(vec![account_id]).await;
    Ok(())
}

/// Shows one of the account's own folders in the lists (subscribes to
/// it) or hides it.
pub async fn set_folder_subscribed(
    account_id: i64,
    mailbox: String,
    subscribed: bool,
) -> Result<(), EngineError> {
    store()?.subscribe_folder(AccountId(account_id), &mailbox, subscribed)?;
    send(vec![account_id]).await;
    Ok(())
}

/// A job a folder can do for an account.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpecialFolder {
    Sent,
    Drafts,
    Trash,
    Junk,
    Archive,
}

impl From<SpecialFolder> for FolderRole {
    fn from(f: SpecialFolder) -> Self {
        match f {
            SpecialFolder::Sent => FolderRole::Sent,
            SpecialFolder::Drafts => FolderRole::Drafts,
            SpecialFolder::Trash => FolderRole::Trash,
            SpecialFolder::Junk => FolderRole::Junk,
            SpecialFolder::Archive => FolderRole::Archive,
        }
    }
}

/// The folder doing one job for an account.
#[derive(Debug, Clone)]
pub struct SpecialFolderInfo {
    pub role: SpecialFolder,
    /// Its server name; None while no folder does that job.
    pub mailbox: Option<String>,
    /// The person chose it, rather than the server's marks or its name.
    pub chosen: bool,
}

/// Which folder does each job for an account (Sent, Drafts, Trash, spam,
/// Archive).
#[frb(sync)]
pub fn special_folders(account_id: i64) -> Result<Vec<SpecialFolderInfo>, EngineError> {
    Ok(reader()?
        .roles(AccountId(account_id))?
        .into_iter()
        .filter_map(|r| {
            let role = match r.role {
                FolderRole::Sent => SpecialFolder::Sent,
                FolderRole::Drafts => SpecialFolder::Drafts,
                FolderRole::Trash => SpecialFolder::Trash,
                FolderRole::Junk => SpecialFolder::Junk,
                FolderRole::Archive => SpecialFolder::Archive,
                FolderRole::Snoozed => return None,
            };
            Some(SpecialFolderInfo {
                role,
                mailbox: r.mailbox,
                chosen: r.chosen,
            })
        })
        .collect())
}

/// A folder on the account's server, for the person to give it a job.
#[derive(Debug, Clone)]
pub struct ServerFolder {
    pub mailbox: String,
    /// Its whole path, as people read it.
    pub name: String,
}

/// Every folder the server last listed.
#[frb(sync)]
pub fn server_folders(account_id: i64) -> Result<Vec<ServerFolder>, EngineError> {
    Ok(reader()?
        .server_folders(AccountId(account_id))?
        .into_iter()
        .map(|(mailbox, name)| ServerFolder { mailbox, name })
        .collect())
}

/// The folders that may do `role`'s job: not the inbox, and not one doing
/// another job when either is Trash or spam.
#[frb(sync)]
pub fn special_folder_options(
    account_id: i64,
    role: SpecialFolder,
) -> Result<Vec<ServerFolder>, EngineError> {
    let store = reader()?;
    let id = AccountId(account_id);
    let mut out = Vec::new();
    for (mailbox, name) in store.server_folders(id)? {
        if store.role_choice_allowed(id, role.into(), &mailbox)? {
            out.push(ServerFolder { mailbox, name });
        }
    }
    Ok(out)
}

/// Gives a job to a folder of the person's choice, or with None goes back
/// to the one the server marks or names. It wins from now on; the
/// account's folders are looked at again at once when the server can be
/// reached.
pub async fn set_special_folder(
    account_id: i64,
    role: SpecialFolder,
    mailbox: Option<String>,
) -> Result<(), EngineError> {
    let id = AccountId(account_id);
    if !store()?.set_role_choice(id, role.into(), mailbox.as_deref())? {
        return Err(EngineError::new(
            ErrorKind::Other,
            "that folder can't do this job",
        ));
    }
    let engine = engine()?;
    let Ok((account, password)) = signed_in(id) else {
        return Ok(());
    };
    let shared = engine.store.clone();
    engine
        .runtime
        .spawn(async move {
            if let Ok(mut conn) = Remote::open(&account, &password).await {
                conn.sync_folders(&shared, id).await.ok();
                conn.close().await;
            }
        })
        .await
        .ok();
    Ok(())
}

/// How a list is sorted.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ListOrder {
    Newest,
    Oldest,
    Sender,
}

/// What a swipe on a row does.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SwipeAction {
    Archive,
    Snooze,
    Delete,
    Read,
    Star,
    Move,
    Nothing,
}

/// How the lists look (Settings › Appearance): their order, conversations
/// or single emails, and what each swipe does.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ListSettings {
    pub order: ListOrder,
    pub threads: bool,
    pub swipe_right: SwipeAction,
    pub swipe_left: SwipeAction,
}

fn swipe_out(a: CoreSwipe) -> SwipeAction {
    match a {
        CoreSwipe::Archive => SwipeAction::Archive,
        CoreSwipe::Snooze => SwipeAction::Snooze,
        CoreSwipe::Delete => SwipeAction::Delete,
        CoreSwipe::Read => SwipeAction::Read,
        CoreSwipe::Star => SwipeAction::Star,
        CoreSwipe::Move => SwipeAction::Move,
        CoreSwipe::Nothing => SwipeAction::Nothing,
    }
}

fn swipe_in(a: SwipeAction) -> CoreSwipe {
    match a {
        SwipeAction::Archive => CoreSwipe::Archive,
        SwipeAction::Snooze => CoreSwipe::Snooze,
        SwipeAction::Delete => CoreSwipe::Delete,
        SwipeAction::Read => CoreSwipe::Read,
        SwipeAction::Star => CoreSwipe::Star,
        SwipeAction::Move => CoreSwipe::Move,
        SwipeAction::Nothing => CoreSwipe::Nothing,
    }
}

#[frb(sync)]
pub fn list_settings() -> Result<ListSettings, EngineError> {
    let s = reader()?.list_settings()?;
    Ok(ListSettings {
        order: match s.order {
            CoreOrder::Newest => ListOrder::Newest,
            CoreOrder::Oldest => ListOrder::Oldest,
            CoreOrder::Sender => ListOrder::Sender,
        },
        threads: s.threads,
        swipe_right: swipe_out(s.swipe_right),
        swipe_left: swipe_out(s.swipe_left),
    })
}

#[frb(sync)]
pub fn set_list_settings(settings: ListSettings) -> Result<(), EngineError> {
    store()?.set_list_settings(CoreListSettings {
        order: match settings.order {
            ListOrder::Newest => CoreOrder::Newest,
            ListOrder::Oldest => CoreOrder::Oldest,
            ListOrder::Sender => CoreOrder::Sender,
        },
        threads: settings.threads,
        swipe_right: swipe_in(settings.swipe_right),
        swipe_left: swipe_in(settings.swipe_left),
    })?;
    Ok(())
}

/// How full a mailbox is, in bytes, as its server last said.
#[derive(Debug, Clone, Copy)]
pub struct QuotaInfo {
    pub used: u64,
    pub limit: u64,
    /// When the server said so, in Unix seconds.
    pub at: i64,
}

fn quota_info(q: Quota) -> QuotaInfo {
    QuotaInfo {
        used: q.used,
        limit: q.limit,
        at: q.at,
    }
}

/// How full the account's mailbox was when its server last said; None
/// when it never said (not every server does).
#[frb(sync)]
pub fn account_quota(account_id: i64) -> Result<Option<QuotaInfo>, EngineError> {
    Ok(reader()?.quota(AccountId(account_id))?.map(quota_info))
}

/// Asks the server how full the mailbox is, keeps the answer and returns
/// it; offline, what it said last.
pub async fn refresh_quota(account_id: i64) -> Result<Option<QuotaInfo>, EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    let (account, password) = signed_in(id)?;
    let asked = engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let q = conn.quota().await;
            conn.close().await;
            q
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    let store = store()?;
    match asked {
        Ok(found) => {
            let quota = found.map(|(used, limit)| Quota {
                used,
                limit,
                at: crate::api::engine::now_secs(),
            });
            store.set_quota(id, quota)?;
            Ok(quota.map(quota_info))
        }
        Err(e) if e.is_offline() => Ok(store.quota(id)?.map(quota_info)),
        Err(e) => Err(e.into()),
    }
}

fn refs(messages: &[MessageRef]) -> Vec<(AccountId, String, u32)> {
    messages
        .iter()
        .map(|m| (AccountId(m.account_id), m.mailbox.clone(), m.uid))
        .collect()
}

fn by_folder(messages: &[MessageRef]) -> BTreeMap<(AccountId, String), Vec<u32>> {
    let mut out: BTreeMap<(AccountId, String), Vec<u32>> = BTreeMap::new();
    for m in messages {
        out.entry((AccountId(m.account_id), m.mailbox.clone()))
            .or_default()
            .push(m.uid);
    }
    out
}

fn accounts_of(messages: &[MessageRef]) -> Vec<i64> {
    let mut accounts: Vec<i64> = messages.iter().map(|m| m.account_id).collect();
    accounts.sort_unstable();
    accounts.dedup();
    accounts
}

/// Sends what waits for each account now; what can't go waits for the
/// next sync.
async fn send(accounts: Vec<i64>) {
    let Ok(engine) = engine() else { return };
    for account_id in accounts {
        let id = AccountId(account_id);
        let Ok((account, password)) = signed_in(id) else {
            continue;
        };
        let shared = engine.store.clone();
        engine
            .runtime
            .spawn(async move {
                if let Ok(mut conn) = Remote::open(&account, &password).await {
                    if let Ok(dropped) = conn.send_pending(&shared, id).await {
                        crate::api::engine::changes_dropped(id, dropped);
                    }
                    conn.close().await;
                }
            })
            .await
            .ok();
    }
}
