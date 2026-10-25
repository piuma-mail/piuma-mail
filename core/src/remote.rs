//! One way to reach any account's server, IMAP or JMAP, so the app asks
//! for the same things whatever the protocol.

use std::sync::{Arc, Mutex};

use crate::imap::{self, FolderRole, ImapConfig, ImapError, SyncReport, WatchEvent};
use crate::jmap::{self, JmapConfig, JmapError};
use crate::model::{Account, AccountId, AccountKind};
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

/// A logged-in connection to an account's server.
pub enum Remote {
    Imap(imap::Connection),
    Jmap(jmap::Client),
}

impl Remote {
    pub async fn open(account: &Account, password: &str) -> Result<Self> {
        Ok(match &account.kind {
            AccountKind::Imap { .. } => {
                let cfg = ImapConfig::for_account(account, password).expect("IMAP account");
                Remote::Imap(imap::Connection::open(&cfg).await?)
            }
            AccountKind::Jmap { .. } => {
                let cfg = JmapConfig::for_account(account, password).expect("JMAP account");
                Remote::Jmap(jmap::Client::open(&cfg).await?)
            }
        })
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

    /// Sends the account's waiting changes now (labels, reads, moves),
    /// as a sync round would first.
    pub async fn send_pending(&mut self, store: &Mutex<Store>, account: AccountId) -> Result<()> {
        match self {
            Remote::Imap(c) => crate::pending::send(c, store, account).await?,
            Remote::Jmap(c) => crate::pending::send(c, store, account).await?,
        }
        Ok(())
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
            Remote::Imap(c) => c.set_seen(mailbox, uids, seen).await?,
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
            Remote::Imap(c) => c.mark_junk(mailbox, uids, junk).await?,
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

    pub async fn append_draft(&mut self, raw: &[u8]) -> Result<String> {
        Ok(match self {
            Remote::Imap(c) => c.append_draft(raw).await?,
            Remote::Jmap(c) => c.append_draft(raw).await?,
        })
    }
}

/// Checks that an account's settings work.
pub async fn check_login(account: &Account, password: &str) -> Result<()> {
    Remote::open(account, password).await?.close().await;
    Ok(())
}

/// Sends a draft and files a copy in Sent (see [`send_ready`]).
pub async fn send(account: &Account, password: &str, draft: &Draft) -> smtp::Result<SendReport> {
    send_ready(account, password, &smtp::ready(draft)?).await
}

/// Sends a message already built and files a copy in Sent: over SMTP
/// for IMAP accounts, through the server itself for JMAP ones.
pub async fn send_ready(
    account: &Account,
    password: &str,
    ready: &Ready,
) -> smtp::Result<SendReport> {
    if let Some(cfg) = JmapConfig::for_account(account, password) {
        let sent = async {
            let mut client = jmap::Client::open(&cfg).await?;
            client
                .send(&ready.raw, &account.email, &ready.recipients)
                .await
        }
        .await
        .map_err(|e| match e {
            JmapError::Auth => SendError::Auth,
            JmapError::Connect { url, source } => SendError::Connect {
                host: url,
                detail: source.to_string(),
            },
            e => SendError::Rejected(e.to_string()),
        })?;
        return Ok(SendReport {
            message_id: ready.message_id.clone(),
            filed_in: Some(sent),
        });
    }
    let smtp = SmtpConfig::for_account(account, password).expect("IMAP account");
    let imap = ImapConfig::for_account(account, password).expect("IMAP account");
    smtp::send_and_file(&smtp, &imap, ready).await
}

/// Keeps an account's inbox in sync forever (see `imap::watch` and
/// `jmap::watch`). Wrong credentials end it.
pub async fn watch(
    account: &Account,
    password: &str,
    store: Arc<Mutex<Store>>,
    events: impl Fn(WatchEvent),
) -> Result<()> {
    if let Some(cfg) = JmapConfig::for_account(account, password) {
        return Ok(jmap::watch(cfg, store, account.id, events).await?);
    }
    let cfg = ImapConfig::for_account(account, password).expect("IMAP account");
    Ok(imap::watch(cfg, store, account.id, "INBOX".to_owned(), events).await?)
}
