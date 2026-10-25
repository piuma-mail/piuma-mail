//! Changes made on this device while the server could not be reached:
//! the store keeps them, and the watcher sends them when the connection
//! is back, before it syncs, so the sync does not undo them.

use std::collections::BTreeMap;
use std::sync::Mutex;

use crate::imap::{self, FolderRole};
use crate::jmap;
use crate::model::AccountId;
use crate::store::{Store, StoreError};

/// Tries before a change is given up, e.g. for a folder deleted meanwhile.
pub const MAX_ATTEMPTS: u32 = 5;

/// Read newsletters older than this archive themselves, in seconds.
pub const NEWSLETTERS_KEPT: i64 = 7 * 24 * 60 * 60;

/// The setting that keeps read newsletters where they are: "off".
pub const ARCHIVE_READ_NEWSLETTERS: &str = "newsletters.archive_read";

/// Newsletters never opened for this long archive themselves, nightly,
/// when the person turned it on, in seconds.
pub const NEWSLETTERS_UNOPENED: i64 = 30 * 24 * 60 * 60;

/// The setting that turns that on: "on". Off unless turned on.
pub const ARCHIVE_UNOPENED_NEWSLETTERS: &str = "newsletters.archive_unopened";

/// How many newsletters that archived on this device, all accounts.
pub const UNOPENED_ARCHIVED: &str = "nightly.unopened.archived";

/// Once a day.
const NIGHTLY: i64 = 24 * 60 * 60;

/// One change to send.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Change {
    Seen(bool),
    /// Archive, Trash or spam.
    Move(FolderRole),
    /// One of the account's own folders, by its server name.
    MoveTo(String),
    /// Into the Snoozed folder until a time, in Unix seconds.
    Snooze(i64),
    /// Back from Snoozed to the inbox, unread: the time it was until.
    Wake(i64),
    /// A label's keyword put on the message, or taken off.
    Label {
        keyword: String,
        add: bool,
    },
}

impl Change {
    pub(crate) fn tag(&self) -> &'static str {
        match self {
            Change::Seen(true) => "seen",
            Change::Seen(false) => "unseen",
            Change::Move(FolderRole::Trash) => "trash",
            Change::Move(FolderRole::Junk) => "junk",
            Change::Move(_) => "archive",
            Change::MoveTo(_) => "move",
            Change::Snooze(_) => "snooze",
            Change::Wake(_) => "wake",
            Change::Label { add: true, .. } => "label",
            Change::Label { add: false, .. } => "unlabel",
        }
    }

    pub(crate) fn target(&self) -> String {
        match self {
            Change::MoveTo(target) => target.clone(),
            Change::Snooze(until) | Change::Wake(until) => until.to_string(),
            Change::Label { keyword, .. } => keyword.clone(),
            _ => String::new(),
        }
    }

    pub(crate) fn from_tag(tag: &str, target: String) -> Option<Self> {
        Some(match tag {
            "seen" => Change::Seen(true),
            "unseen" => Change::Seen(false),
            "archive" => Change::Move(FolderRole::Archive),
            "trash" => Change::Move(FolderRole::Trash),
            "junk" => Change::Move(FolderRole::Junk),
            "move" => Change::MoveTo(target),
            "snooze" => Change::Snooze(target.parse().ok()?),
            "wake" => Change::Wake(target.parse().ok()?),
            "label" => Change::Label {
                keyword: target,
                add: true,
            },
            "unlabel" => Change::Label {
                keyword: target,
                add: false,
            },
            _ => return None,
        })
    }
}

/// A change waiting in the store.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pending {
    pub id: i64,
    pub mailbox: String,
    pub uid: u32,
    pub change: Change,
    pub attempts: u32,
}

/// What a server must do to take the changes.
pub(crate) trait Server {
    type Error: From<StoreError>;
    fn offline(e: &Self::Error) -> bool;
    async fn seen(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        seen: bool,
    ) -> Result<(), Self::Error>;
    async fn moved(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        to: &Change,
    ) -> Result<(), Self::Error>;
    async fn label(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        keyword: &str,
        add: bool,
    ) -> Result<(), Self::Error>;
}

impl Server for imap::Connection {
    type Error = imap::ImapError;
    fn offline(e: &imap::ImapError) -> bool {
        e.is_offline()
    }
    async fn seen(
        &mut self,
        _: &Mutex<Store>,
        _: AccountId,
        mailbox: &str,
        uids: &[u32],
        seen: bool,
    ) -> imap::Result<()> {
        self.set_seen(mailbox, uids, seen).await
    }
    async fn moved(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        to: &Change,
    ) -> imap::Result<()> {
        match to {
            Change::MoveTo(target) => self.move_to(store, account, mailbox, uids, target).await,
            Change::Move(role) => self
                .move_messages(store, account, mailbox, uids, *role)
                .await
                .map(|_| ()),
            Change::Snooze(until) => self.snooze(store, account, mailbox, uids, *until).await,
            Change::Wake(until) => self.wake(store, account, mailbox, uids, *until).await,
            Change::Seen(_) | Change::Label { .. } => Ok(()),
        }
    }
    async fn label(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        keyword: &str,
        add: bool,
    ) -> imap::Result<()> {
        self.set_keyword(store, account, mailbox, uids, keyword, add)
            .await
    }
}

impl Server for jmap::Client {
    type Error = jmap::JmapError;
    fn offline(e: &jmap::JmapError) -> bool {
        e.is_offline()
    }
    async fn seen(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        seen: bool,
    ) -> jmap::Result<()> {
        self.set_seen(store, account, mailbox, uids, seen).await
    }
    async fn moved(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        to: &Change,
    ) -> jmap::Result<()> {
        match to {
            Change::MoveTo(target) => self.move_to(store, account, mailbox, uids, target).await,
            Change::Move(role) => self
                .move_messages(store, account, mailbox, uids, *role)
                .await
                .map(|_| ()),
            Change::Snooze(_) => self.snooze(store, account, mailbox, uids).await,
            Change::Wake(_) => self.wake(store, account, mailbox, uids).await,
            Change::Seen(_) | Change::Label { .. } => Ok(()),
        }
    }
    async fn label(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        keyword: &str,
        add: bool,
    ) -> jmap::Result<()> {
        self.set_keyword(store, account, mailbox, uids, keyword, add)
            .await
    }
}

/// Sends an account's waiting changes, one command per folder and kind:
/// read and unread and labels first, then moves. A lost connection stops it and
/// keeps everything; a change the server refuses counts a try.
pub(crate) async fn send<S: Server>(
    server: &mut S,
    store: &Mutex<Store>,
    account: AccountId,
) -> Result<(), S::Error> {
    archive_read_newsletters(store, account)?;
    archive_unopened_newsletters(store, account, now())?;
    lock(store).queue_wakes(account, now())?;
    // A reply that came takes its reminder away.
    lock(store).drop_answered_reminders(account)?;
    let pending = lock(store).pending_changes(account)?;
    if pending.is_empty() {
        return Ok(());
    }
    // Keyed by (is a move, folder, kind, target): the change, its uids,
    // their ids.
    type Group = (Change, Vec<u32>, Vec<i64>);
    let mut groups: BTreeMap<(bool, String, &'static str, String), Group> = BTreeMap::new();
    for p in &pending {
        let is_move = !matches!(p.change, Change::Seen(_) | Change::Label { .. });
        let key = (
            is_move,
            p.mailbox.clone(),
            p.change.tag(),
            p.change.target().to_owned(),
        );
        let group = groups
            .entry(key)
            .or_insert((p.change.clone(), Vec::new(), Vec::new()));
        group.1.push(p.uid);
        group.2.push(p.id);
    }
    for ((_, mailbox, _, _), (change, uids, ids)) in groups {
        let sent = match change {
            Change::Seen(seen) => server.seen(store, account, &mailbox, &uids, seen).await,
            Change::Label { keyword, add } => {
                server
                    .label(store, account, &mailbox, &uids, &keyword, add)
                    .await
            }
            _ => server.moved(store, account, &mailbox, &uids, &change).await,
        };
        match sent {
            Ok(()) => lock(store).drop_changes(&ids)?,
            Err(e) if S::offline(&e) => return Err(e),
            Err(_) => lock(store).failed_changes(&ids)?,
        }
    }
    Ok(())
}

/// Queues the archiving of the read newsletters that are more than a
/// week old, unless the person turned it off.
fn archive_read_newsletters(store: &Mutex<Store>, account: AccountId) -> Result<(), StoreError> {
    let store = lock(store);
    if store.setting(ARCHIVE_READ_NEWSLETTERS)?.as_deref() == Some("off") {
        return Ok(());
    }
    store.queue_newsletter_archive(account, now() - NEWSLETTERS_KEPT, true)?;
    Ok(())
}

/// Once a day per account, when turned on, queues the archiving of the
/// newsletters left unopened for 30 days, and counts them.
pub(crate) fn archive_unopened_newsletters(
    store: &Mutex<Store>,
    account: AccountId,
    at: i64,
) -> Result<usize, StoreError> {
    let store = lock(store);
    if store.setting(ARCHIVE_UNOPENED_NEWSLETTERS)?.as_deref() != Some("on") {
        return Ok(0);
    }
    let ran = format!("nightly.unopened.{}", account.0);
    let last = store
        .setting(&ran)?
        .and_then(|v| v.parse::<i64>().ok())
        .unwrap_or(0);
    if at - last < NIGHTLY {
        return Ok(0);
    }
    let queued = store.queue_newsletter_archive(account, at - NEWSLETTERS_UNOPENED, false)?;
    store.set_setting(&ran, &at.to_string())?;
    if queued > 0 {
        let total = store
            .setting(UNOPENED_ARCHIVED)?
            .and_then(|v| v.parse::<usize>().ok())
            .unwrap_or(0);
        store.set_setting(UNOPENED_ARCHIVED, &(total + queued).to_string())?;
    }
    Ok(queued)
}

/// Unix seconds now.
pub(crate) fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or_default()
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}
