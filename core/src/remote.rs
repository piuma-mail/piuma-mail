//! One way to reach any account's server, IMAP or JMAP, so the app asks
//! for the same things whatever the protocol.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

use crate::auth::Login;
use crate::imap::{self, FolderRole, ImapConfig, ImapError, SyncReport, WatchEvent};
use crate::jmap::{self, JmapConfig, JmapError};
use crate::model::{Account, AccountId, AccountKind, Folder};
use crate::outbox::Courier;
use crate::search::{folder_key, InFolder, Query, Scope, ServerAsk};
use crate::smtp::{self, Draft, Ready, SendError, SendReport, SmtpConfig};
use crate::store::{Body, Store, StoreError};

#[derive(Debug, thiserror::Error)]
pub enum RemoteError {
    #[error(transparent)]
    Imap(#[from] ImapError),
    #[error(transparent)]
    Jmap(#[from] JmapError),
    #[error(transparent)]
    Store(#[from] StoreError),
}

impl RemoteError {
    /// The server refused the login.
    pub fn is_auth(&self) -> bool {
        matches!(
            self,
            RemoteError::Imap(ImapError::Auth) | RemoteError::Jmap(JmapError::Auth)
        )
    }

    /// The server's certificate was refused: the person has to look at it.
    pub fn is_certificate(&self) -> bool {
        matches!(
            self,
            RemoteError::Imap(ImapError::Certificate(_))
                | RemoteError::Jmap(JmapError::Certificate(_))
        )
    }

    /// The server could not be reached: worth keeping the change for later.
    pub fn is_offline(&self) -> bool {
        match self {
            RemoteError::Imap(e) => e.is_offline(),
            RemoteError::Jmap(e) => e.is_offline(),
            RemoteError::Store(_) => false,
        }
    }
}

pub type Result<T> = std::result::Result<T, RemoteError>;

/// Most messages a server search brings back per folder (per account
/// with JMAP).
pub const SERVER_HITS: usize = 100;
/// Folders a server search looks in per IMAP account, at most.
pub const SERVER_FOLDERS: usize = 25;

/// What a server search found in one account.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ServerFound {
    /// Where each message is kept here (folder, UID), all of them on this
    /// device now.
    pub at: Vec<(String, u32)>,
    /// Whether the server was asked anything: not for a search only this
    /// device can answer (`in:vault`), or one with only filters.
    pub asked: bool,
    /// Some of the account could not be searched fully: a folder refused,
    /// text cut to ASCII, more folders than are searched.
    pub partial: bool,
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}

/// Resolve without rewriting IDs or caching the body: a successful download
/// must not depend on a body-cache write succeeding.
pub(crate) fn resolve_historical_attachment(
    store: &Store,
    account: AccountId,
    mailbox: &str,
    uid: u32,
    file: &crate::store::Attachment,
    raw: &[u8],
) -> Result<Vec<u8>> {
    match imap::attachment_data_checked(raw, file.part, Some(file)) {
        Some(data) => Ok(data),
        None => {
            // Remembered, so later opens don't download the message again.
            // A full-body refresh may have replaced the rows while the
            // message downloaded, and then the foreign key refuses the mark:
            // the file is still gone, so that is not an error to show.
            let _ = store.mark_attachment_unavailable(account, mailbox, uid, file.part);
            Err(ImapError::Gone.into())
        }
    }
}

/// What a folder held when it was counted, for Empty to keep to: the
/// next UID then (IMAP), or the ids (JMAP).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Snapshot {
    Imap {
        uid_next: Option<u32>,
    },
    Jmap {
        ids: Vec<String>,
    },
    /// The server couldn't be counted: only these messages that are here
    /// (their uids here), never more.
    Here {
        uids: Vec<u32>,
    },
}

impl Snapshot {
    /// What Empty keeps to when the server couldn't say what it holds:
    /// the messages shown here with nothing waiting for them.
    pub fn here(store: &Mutex<Store>, account: AccountId, mailbox: &str) -> Result<Self> {
        let uids = store
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .erasable_uids(account, mailbox)?;
        Ok(Snapshot::Here { uids })
    }
}

/// A logged-in connection to an account's server.
pub enum Remote {
    Imap(imap::Connection),
    Jmap(jmap::Client),
}

impl Remote {
    pub async fn open(account: &Account, login: &Login) -> Result<Self> {
        Ok(match &account.kind {
            AccountKind::Imap { .. } => {
                let cfg = ImapConfig::for_account(account, login).expect("IMAP account");
                Remote::Imap(imap::Connection::open(&cfg).await?)
            }
            AccountKind::Jmap { .. } => {
                let cfg = JmapConfig::for_account(account, login).expect("JMAP account");
                Remote::Jmap(jmap::Client::open(&cfg).await?)
            }
        })
    }

    /// Runs a search on the account's server and brings the newest
    /// `limit` messages per folder (per account with JMAP) here, as
    /// headers; see [`crate::search`] for how each term is asked. IMAP
    /// looks in the inbox, the folders with a job, the account's own
    /// folders and the ones the search names, at most [`SERVER_FOLDERS`]
    /// of them; Trash and Spam only when named.
    pub async fn search_server(
        &mut self,
        store: &Mutex<Store>,
        account: &Account,
        query: &Query,
        limit: usize,
    ) -> Result<ServerFound> {
        let (labels, groups) = {
            let s = lock(store);
            let labels: HashMap<String, String> = s
                .labels()?
                .into_iter()
                .map(|l| (l.name.to_lowercase(), l.keyword))
                .collect();
            let groups: HashMap<i64, Vec<String>> = s
                .address_groups()?
                .into_iter()
                .map(|g| {
                    let mine = g
                        .addresses
                        .into_iter()
                        .filter(|a| a.account == account.id)
                        .map(|a| a.email)
                        .collect();
                    (g.id, mine)
                })
                .collect();
            (labels, groups)
        };
        let mut found = ServerFound::default();
        match self {
            Remote::Imap(conn) => {
                // Where the search's `in:` values point in this account.
                let mut named: HashMap<String, HashSet<String>> = HashMap::new();
                for f in query.folders() {
                    let key = folder_key(f);
                    let mut places: HashSet<String> = lock(store)
                        .folders_named(f)?
                        .into_iter()
                        .filter(|(a, _)| *a == account.id)
                        .map(|(_, m)| m)
                        .collect();
                    let role = match key.as_str() {
                        "trash" | "bin" | "deleted" => Some(FolderRole::Trash),
                        "spam" | "junk" => Some(FolderRole::Junk),
                        _ => None,
                    };
                    if let Some(role) = role {
                        places.extend(conn.find_folder(role).await?);
                    }
                    named.insert(key, places);
                }
                let mut folders: Vec<String> = vec!["INBOX".into()];
                {
                    let s = lock(store);
                    for f in [
                        Folder::Sent,
                        Folder::Archive,
                        Folder::Drafts,
                        Folder::Snoozed,
                    ] {
                        folders.extend(s.folder_mailbox(account.id, f)?);
                    }
                    folders.extend(
                        s.account_folders(account.id)?
                            .into_iter()
                            .filter(|f| f.selectable)
                            .map(|f| f.mailbox),
                    );
                }
                folders.extend(named.values().flatten().cloned());
                let mut seen = HashSet::new();
                folders.retain(|f| seen.insert(f.clone()));
                let mut asked = 0;
                for mailbox in folders {
                    let folder = |v: &str| {
                        if named
                            .get(&folder_key(v))
                            .is_some_and(|places| places.contains(&mailbox))
                        {
                            InFolder::Yes
                        } else {
                            InFolder::No
                        }
                    };
                    let scope = Scope {
                        account_name: &account.name,
                        account_email: &account.email,
                        labels: &labels,
                        groups: &groups,
                        folder: &folder,
                    };
                    let ServerAsk::Ask(ask) = query.for_server(&scope) else {
                        continue;
                    };
                    if asked == SERVER_FOLDERS {
                        found.partial = true;
                        break;
                    }
                    asked += 1;
                    found.asked = true;
                    match conn
                        .search_folder(store, account.id, &mailbox, &ask, limit)
                        .await
                    {
                        Ok((uids, partial)) => {
                            found.partial |= partial;
                            found
                                .at
                                .extend(uids.into_iter().map(|uid| (mailbox.clone(), uid)));
                        }
                        // A folder the server won't open or search: the
                        // others still count.
                        Err(ImapError::Protocol(
                            async_imap::error::Error::No(_) | async_imap::error::Error::Bad(_),
                        )) => found.partial = true,
                        Err(e) => return Err(e.into()),
                    }
                }
            }
            Remote::Jmap(client) => {
                let named: HashMap<String, Vec<String>> = query
                    .folders()
                    .into_iter()
                    .map(|f| (folder_key(f), client.folders_named(f)))
                    .collect();
                let folder =
                    |v: &str| InFolder::Ids(named.get(&folder_key(v)).cloned().unwrap_or_default());
                let scope = Scope {
                    account_name: &account.name,
                    account_email: &account.email,
                    labels: &labels,
                    groups: &groups,
                    folder: &folder,
                };
                if let ServerAsk::Ask(ask) = query.for_server(&scope) {
                    found.asked = true;
                    found.at = client
                        .search(store, account.id, &ask, !named.is_empty(), limit)
                        .await?;
                }
            }
        }
        Ok(found)
    }

    /// Ends the session politely, where the protocol has one.
    pub async fn close(self) {
        if let Remote::Imap(conn) = self {
            conn.logout().await.ok();
        }
    }

    /// The notes in the sync space's hidden folder, oldest first, each
    /// with its id there; none while the folder isn't there.
    pub async fn space_notes(&mut self) -> Result<Vec<(String, crate::space::Note)>> {
        Ok(match self {
            Remote::Imap(c) => c
                .space_notes()
                .await?
                .into_iter()
                .map(|(uid, n)| (uid.to_string(), n))
                .collect(),
            Remote::Jmap(c) => c.space_notes().await?,
        })
    }

    /// Adds a note to the sync space's hidden folder, made when missing.
    pub async fn space_put(&mut self, raw: &[u8]) -> Result<()> {
        match self {
            Remote::Imap(c) => c.space_put(raw).await?,
            Remote::Jmap(c) => c.space_put(raw).await?,
        }
        Ok(())
    }

    /// Deletes notes of the sync space's folder for good, by the ids
    /// [Remote::space_notes] gave.
    pub async fn space_remove(&mut self, ids: &[String]) -> Result<()> {
        match self {
            Remote::Imap(c) => {
                let uids: Vec<u32> = ids.iter().filter_map(|i| i.parse().ok()).collect();
                c.space_remove(&uids).await?
            }
            Remote::Jmap(c) => c.space_remove(ids).await?,
        }
        Ok(())
    }

    pub async fn sync_mailbox(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
    ) -> Result<SyncReport> {
        Ok(match self {
            Remote::Imap(c) => c.sync_mailbox(store, account, mailbox, |_, _| {}).await?,
            Remote::Jmap(c) => c.sync_mailbox(store, account, mailbox, |_, _| {}).await?,
        })
    }

    /// Downloads at most `limit` new messages of one folder, newest
    /// first, and refreshes the rest. Returns how many are left.
    pub async fn sync_round(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        limit: usize,
    ) -> Result<usize> {
        Ok(match self {
            Remote::Imap(c) => {
                let round = imap::Round { limit, flags: true };
                c.sync_round(store, account, mailbox, round, |_, _| {})
                    .await?
                    .more
            }
            Remote::Jmap(c) => {
                c.sync_mailbox(store, account, mailbox, |_, _| {}).await?;
                0
            }
        })
    }

    pub async fn sync_folders(&mut self, store: &Mutex<Store>, account: AccountId) -> Result<()> {
        match self {
            Remote::Imap(c) => c.sync_folders(store, account).await?,
            Remote::Jmap(c) => c.sync_folders(store, account).await?,
        }
        Ok(())
    }

    pub async fn full_body(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<Body> {
        Ok(match self {
            Remote::Imap(c) => c.full_body(store, account, mailbox, uid).await?,
            Remote::Jmap(c) => c.full_body(store, account, mailbox, uid).await?,
        })
    }

    pub async fn raw(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<Vec<u8>> {
        Ok(match self {
            Remote::Imap(c) => c.raw(mailbox, uid).await?,
            Remote::Jmap(c) => c.raw(store, account, mailbox, uid).await?,
        })
    }

    pub async fn attachment(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        part: u32,
    ) -> Result<Vec<u8>> {
        let listed = store
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .attachment(account, mailbox, uid, part)?;
        // Keep every ID the UI holds until the next full-body refresh.
        // Downloading one attachment must not replace its siblings' rows.
        if part & imap::LEGACY_PART_ID != 0 && listed.as_ref().is_some_and(|a| a.section.is_none())
        {
            if store
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .attachment_unavailable(account, mailbox, uid, part)?
            {
                return Err(ImapError::Gone.into());
            }
            let raw = self.raw(store, account, mailbox, uid).await?;
            let file = listed.as_ref().unwrap();
            // Parse without holding the store: a large message would block
            // every other use of it meanwhile.
            if let Some(data) = imap::attachment_data_checked(&raw, file.part, Some(file)) {
                return Ok(data);
            }
            return resolve_historical_attachment(
                &store.lock().unwrap_or_else(|e| e.into_inner()),
                account,
                mailbox,
                uid,
                file,
                &raw,
            );
        }
        Ok(match self {
            // Files listed from the outline are fetched alone.
            Remote::Imap(c) => {
                match listed.and_then(|a| a.section.clone().map(|s| (s, a.encoding))) {
                    Some((section, encoding)) => {
                        c.section(mailbox, uid, &section, encoding.as_deref())
                            .await?
                    }
                    None => c.attachment(mailbox, uid, part).await?,
                }
            }
            Remote::Jmap(c) => match listed.and_then(|a| a.section) {
                Some(blob) => c.blob(&blob).await?,
                None => c.attachment(store, account, mailbox, uid, part).await?,
            },
        })
    }

    /// Sends the account's waiting changes that are due now (labels,
    /// reads, moves), as a sync round would first. Returns how many the
    /// server kept refusing and were given up.
    pub async fn send_pending(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
    ) -> Result<usize> {
        Ok(match self {
            Remote::Imap(c) => crate::pending::send(c, store, account).await?,
            Remote::Jmap(c) => crate::pending::send(c, store, account).await?,
        })
    }

    pub async fn set_seen(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        seen: bool,
    ) -> Result<()> {
        match self {
            Remote::Imap(c) => c.set_seen(store, account, mailbox, uids, seen).await?,
            Remote::Jmap(c) => c.set_seen(store, account, mailbox, uids, seen).await?,
        }
        Ok(())
    }

    /// Tells the server's spam filter whether messages are spam. Best
    /// effort: the move that goes with it is what matters.
    pub async fn mark_junk(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        junk: bool,
    ) -> Result<()> {
        match self {
            Remote::Imap(c) => c.mark_junk(store, account, mailbox, uids, junk).await?,
            Remote::Jmap(c) => c.mark_junk(store, account, mailbox, uids, junk).await?,
        }
        Ok(())
    }

    pub async fn move_messages(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        role: FolderRole,
    ) -> Result<String> {
        Ok(match self {
            Remote::Imap(c) => c.move_messages(store, account, mailbox, uids, role).await?,
            Remote::Jmap(c) => c.move_messages(store, account, mailbox, uids, role).await?,
        })
    }

    /// Moves messages to one of the account's own folders.
    pub async fn move_to(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        target: &str,
    ) -> Result<()> {
        match self {
            Remote::Imap(c) => c.move_to(store, account, mailbox, uids, target).await?,
            Remote::Jmap(c) => c.move_to(store, account, mailbox, uids, target).await?,
        }
        Ok(())
    }

    /// Puts messages away in Snoozed until `until` (Unix seconds).
    pub async fn snooze(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        until: i64,
    ) -> Result<()> {
        match self {
            Remote::Imap(c) => c.snooze(store, account, mailbox, uids, until).await?,
            Remote::Jmap(c) => c.snooze(store, account, mailbox, uids).await?,
        }
        Ok(())
    }

    /// Brings snoozed messages back to the inbox, unread. `until` is the
    /// time they were snoozed until.
    pub async fn wake(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        until: i64,
    ) -> Result<()> {
        match self {
            Remote::Imap(c) => c.wake(store, account, mailbox, uids, until).await?,
            Remote::Jmap(c) => c.wake(store, account, mailbox, uids).await?,
        }
        Ok(())
    }

    pub async fn erase(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<()> {
        match self {
            Remote::Imap(c) => c.erase(store, account, mailbox, uids).await?,
            Remote::Jmap(c) => c.erase(store, account, mailbox, uids).await?,
        }
        Ok(())
    }

    /// Makes a folder of the account's own, at the top.
    pub async fn create_folder(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        name: &str,
    ) -> Result<String> {
        Ok(match self {
            Remote::Imap(c) => c.create_folder(store, account, name).await?,
            Remote::Jmap(c) => c.create_folder(store, account, name).await?,
        })
    }

    /// Reads which folders the person gave a job to (Sent, Drafts,
    /// Trash, spam, Archive), so this connection uses theirs.
    pub fn learn_roles(&mut self, store: &Mutex<Store>, account: AccountId) -> Result<()> {
        match self {
            Remote::Imap(c) => c.learn_roles(store, account)?,
            Remote::Jmap(c) => c.learn_roles(store, account)?,
        }
        Ok(())
    }

    /// Deletes the messages of a folder for good (Empty Trash, Empty
    /// spam), keeping to `upto`: what was there when [`Self::count`] gave
    /// it, so mail that came after stays, or, when the server couldn't be
    /// counted, only the messages that are here. Never one with a change
    /// still waiting. Returns how many went.
    pub async fn empty(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        upto: &Snapshot,
    ) -> Result<usize> {
        // A snapshot of the other protocol says nothing about this
        // server: keep to what is here.
        let fallback;
        let upto = match (&*self, upto) {
            (Remote::Imap(_), Snapshot::Jmap { .. }) | (Remote::Jmap(_), Snapshot::Imap { .. }) => {
                fallback = Snapshot::here(store, account, mailbox)?;
                &fallback
            }
            _ => upto,
        };
        Ok(match self {
            Remote::Imap(c) => {
                let limit = match upto {
                    Snapshot::Imap { uid_next } => imap::EmptyLimit::Below(*uid_next),
                    Snapshot::Here { uids } => {
                        imap::EmptyLimit::Only(uids.iter().copied().collect())
                    }
                    Snapshot::Jmap { .. } => unreachable!("replaced above"),
                };
                c.empty(store, account, mailbox, &limit).await?
            }
            Remote::Jmap(c) => {
                let only: HashSet<String> = match upto {
                    Snapshot::Jmap { ids } => ids.iter().cloned().collect(),
                    Snapshot::Here { uids } => {
                        let st = store.lock().unwrap_or_else(|e| e.into_inner());
                        let mut ids = HashSet::new();
                        for uid in uids {
                            ids.extend(st.jmap_id(account, mailbox, *uid)?);
                        }
                        ids
                    }
                    Snapshot::Imap { .. } => unreachable!("replaced above"),
                };
                c.empty(store, account, mailbox, &only).await?
            }
        })
    }

    /// How many messages a folder holds on the server, with what Empty
    /// keeps to.
    pub async fn count(&mut self, mailbox: &str) -> Result<(u32, Snapshot)> {
        Ok(match self {
            Remote::Imap(c) => {
                let (n, uid_next) = c.count(mailbox).await?;
                (n, Snapshot::Imap { uid_next })
            }
            Remote::Jmap(c) => {
                let (n, ids) = c.count(mailbox).await?;
                (n, Snapshot::Jmap { ids })
            }
        })
    }

    /// How full the mailbox is, in bytes used and allowed, when the
    /// server says.
    pub async fn quota(&mut self) -> Result<Option<(u64, u64)>> {
        Ok(match self {
            Remote::Imap(c) => c.quota().await?,
            Remote::Jmap(c) => c.quota().await?,
        })
    }

    pub async fn append_draft(&mut self, raw: &[u8]) -> Result<String> {
        Ok(match self {
            Remote::Imap(c) => c.append_draft(raw).await?,
            Remote::Jmap(c) => c.append_draft(raw).await?,
        })
    }

    /// Puts a whole message in `folder`, as read (an imported email file).
    pub async fn append_to(&mut self, folder: &str, raw: &[u8]) -> Result<()> {
        match self {
            Remote::Imap(c) => c.append_to(folder, raw).await?,
            Remote::Jmap(c) => c.append_to(folder, raw).await?,
        }
        Ok(())
    }
}

/// Checks that an account's settings work.
pub async fn check_login(account: &Account, login: &Login) -> Result<()> {
    Remote::open(account, login).await?.close().await;
    Ok(())
}

/// Sends a draft and files a copy in Sent, straight away, without the
/// outbox: for checks and tests. The app sends through [crate::outbox].
pub async fn send(account: &Account, login: &Login, draft: &Draft) -> smtp::Result<SendReport> {
    let ready = smtp::ready(draft)?;
    let mut courier = AccountCourier::new(account, login);
    courier.send(&ready).await?;
    Ok(SendReport {
        message_id: ready.message_id.clone(),
        filed: courier.file(&ready, false).await,
    })
}

/// Hands outbox mail to an account's servers: over SMTP with a copy
/// filed in Sent over IMAP, or through the JMAP server, which files it.
pub struct AccountCourier<'a> {
    account: &'a Account,
    login: &'a Login,
}

impl<'a> AccountCourier<'a> {
    pub fn new(account: &'a Account, login: &'a Login) -> Self {
        AccountCourier { account, login }
    }

    fn jmap(&self) -> Option<JmapConfig> {
        JmapConfig::for_account(self.account, self.login)
    }
}

/// A JMAP failure, as a send failure.
fn jmap_send_error(e: JmapError) -> SendError {
    match e {
        JmapError::Auth => SendError::Auth,
        JmapError::Certificate(r) => SendError::Certificate(r),
        JmapError::Uncertain(detail) => SendError::Uncertain(detail),
        // The server would take the password only unencrypted: as a
        // certificate error, shown, never waited on.
        JmapError::Insecure => SendError::Tls {
            host: String::new(),
            detail: JmapError::Insecure.to_string(),
        },
        JmapError::Connect { url, source } if smtp::tls_failure(&source) => SendError::Tls {
            host: url,
            detail: source.to_string(),
        },
        JmapError::Connect { url, source } => SendError::Connect {
            host: url,
            detail: source.to_string(),
        },
        e => SendError::Rejected(e.to_string()),
    }
}

impl Courier for AccountCourier<'_> {
    async fn send(&mut self, ready: &Ready) -> smtp::Result<()> {
        if let Some(cfg) = self.jmap() {
            let mut client = jmap::Client::open(&cfg).await.map_err(|e| match e {
                // Nothing asked yet: safe to try again.
                JmapError::Uncertain(detail) => SendError::Connect {
                    host: cfg.session_url.clone(),
                    detail,
                },
                e => jmap_send_error(e),
            })?;
            // From the address it was written from, an alias's identity
            // when the server has one (the account's otherwise).
            let from = if ready.from.trim().is_empty() {
                &self.account.email
            } else {
                &ready.from
            };
            client
                .send(&ready.raw, from, &ready.recipients, &ready.message_id)
                .await
                .map_err(jmap_send_error)?;
            return Ok(());
        }
        let smtp = SmtpConfig::for_account(self.account, self.login).expect("IMAP account");
        smtp::send(&smtp, ready).await
    }

    async fn file(&mut self, ready: &Ready, retry: bool) -> smtp::Filing {
        if self.jmap().is_some() {
            return smtp::Filing::Server;
        }
        let smtp = SmtpConfig::for_account(self.account, self.login).expect("IMAP account");
        let imap = ImapConfig::for_account(self.account, self.login).expect("IMAP account");
        smtp::file_sent(&smtp, &imap, ready, retry).await
    }

    async fn was_sent(&mut self, ready: &Ready) -> Option<bool> {
        if let Some(cfg) = self.jmap() {
            let mut client = jmap::Client::open(&cfg).await.ok()?;
            return match client.sent_state(&ready.message_id).await.ok()? {
                Some(state) => Some(state.submitted),
                None => Some(false),
            };
        }
        // In Sent, it went. Missing proves nothing on servers that don't
        // file sent mail themselves, nor on one that is slow to.
        let imap = ImapConfig::for_account(self.account, self.login)?;
        let mut conn = imap::Connection::open(&imap).await.ok()?;
        let found = conn.sent_has(&ready.message_id).await.ok()?;
        conn.logout().await.ok();
        found.map(|_| true)
    }
}

/// Keeps an account's inbox in sync forever (see `imap::watch` and
/// `jmap::watch`). Wrong credentials end it.
pub async fn watch(
    account: &Account,
    login: &Login,
    store: Arc<Mutex<Store>>,
    events: impl Fn(WatchEvent),
) -> Result<()> {
    if let Some(cfg) = JmapConfig::for_account(account, login) {
        return Ok(jmap::watch(cfg, store, account.id, events).await?);
    }
    let cfg = ImapConfig::for_account(account, login).expect("IMAP account");
    Ok(imap::watch(cfg, store, account.id, "INBOX".to_owned(), events).await?)
}
