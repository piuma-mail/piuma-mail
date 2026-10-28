//! IMAP: connect to a server, mirror one folder into the local database and
//! wait for changes with IDLE.
//!
//! The sync is offline-first: the database is the source the app draws from,
//! and every sync brings it in line with the server in three steps (forget
//! what was deleted, download what is new, refresh flags).

use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::fmt;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_imap::extensions::idle::IdleResponse;
use async_imap::imap_proto::{BodyContentCommon, BodyStructure, ContentEncoding, SectionPath};
use async_imap::types::{Fetch, Flag, NameAttribute};
use futures::TryStreamExt;
use mail_parser::{MessageParser, MimeHeaders};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::TlsConnector;

use crate::groups;
use crate::model::{AccountId, Flags, Folder, ListInfo, MessageSummary, ReplyInfo};
use crate::newsletter;
use crate::notify::{self, Arrival};
use crate::pec;
use crate::store::{Attachment, Body, InlineImage, MailboxState, Store, StoreError};

pub use crate::model::Security;

#[derive(Clone)]
pub struct ImapConfig {
    pub host: String,
    pub port: u16,
    pub security: Security,
    pub username: String,
    pub password: String,
}

impl fmt::Debug for ImapConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ImapConfig")
            .field("host", &self.host)
            .field("port", &self.port)
            .field("security", &self.security)
            .field("username", &self.username)
            .finish_non_exhaustive()
    }
}

impl ImapConfig {
    /// The IMAP settings of an account, or None for non-IMAP accounts.
    pub fn for_account(account: &crate::model::Account, password: &str) -> Option<Self> {
        match &account.kind {
            crate::model::AccountKind::Imap { imap, username, .. } => Some(ImapConfig {
                host: imap.host.clone(),
                port: imap.port,
                security: imap.security,
                username: username.clone(),
                password: password.to_owned(),
            }),
            crate::model::AccountKind::Jmap { .. } => None,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ImapError {
    #[error("could not reach {host}: {source}")]
    Connect {
        host: String,
        source: std::io::Error,
    },
    #[error("secure connection failed: {0}")]
    Tls(String),
    #[error("the server rejected the user name or password")]
    Auth,
    #[error("the server is busy and will not accept the login just now: {0}")]
    Throttled(String),
    #[error("the server does not keep stable message ids in this folder")]
    NoUidValidity,
    #[error("IMAP: {0}")]
    Protocol(#[from] async_imap::error::Error),
    #[error(transparent)]
    Store(#[from] StoreError),
    #[error("the message or attachment is no longer on the server")]
    Gone,
    #[error("the account has no folder for this")]
    NoFolder,
}

impl ImapError {
    /// The connection could not be made or was lost, or the server is busy
    /// for now, rather than the login being refused for good.
    pub fn is_offline(&self) -> bool {
        matches!(
            self,
            ImapError::Connect { .. }
                | ImapError::Throttled(_)
                | ImapError::Protocol(
                    async_imap::error::Error::Io(_) | async_imap::error::Error::ConnectionLost
                )
        )
    }
}

pub type Result<T> = std::result::Result<T, ImapError>;

trait Io: AsyncRead + AsyncWrite + Unpin + Send + fmt::Debug {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send + fmt::Debug> Io for T {}

type Session = async_imap::Session<Box<dyn Io>>;

/// A logged-in IMAP connection and what the server can do.
pub struct Connection {
    /// Always Some, except while IDLE holds the session.
    session: Option<Session>,
    condstore: bool,
    idle: bool,
    moves: bool,
    uidplus: bool,
}

/// Messages fetched per round trip while downloading a folder.
const BATCH: usize = 250;
/// Bytes of the body fetched for the preview line.
const PREVIEW_BYTES: usize = 2048;
/// Bytes fetched again when the first ones held no words, as with HTML
/// that opens with a long style sheet.
const LONG_PREVIEW_BYTES: usize = 32 * 1024;
/// Old previews made again per folder and round.
const MEND_LOOK: u32 = 500;
/// Length of the stored preview, in characters.
const PREVIEW_CHARS: usize = 200;
/// Messages downloaded per folder before the watcher looks at the
/// others and at new mail again, so a big mailbox fills in rounds.
pub const ROUND: usize = 2000;
/// How many of the newest newsletters are kept whole, for offline reading.
pub(crate) const NEWSLETTER_BODIES: u32 = 20;
/// Bigger newsletters are fetched when opened.
pub(crate) const NEWSLETTER_BYTES: usize = 512 * 1024;
/// How many of the newest Inbox messages are kept whole, so they open
/// without a trip to the server.
pub(crate) const INBOX_BODIES: u32 = 30;
/// Bigger mail is fetched when opened.
pub(crate) const INBOX_BYTES: usize = 512 * 1024;
/// Messages looked at for the Vault per round, newest first.
pub(crate) const VAULT_LOOK: u32 = 1000;
/// Bodies fetched for the Vault per round trip.
pub(crate) const VAULT_BODIES: usize = 25;
/// Bigger mail makes its card when opened.
pub(crate) const VAULT_BYTES: usize = 512 * 1024;
/// Messages whose files are listed per round, newest first.
pub(crate) const FILES_LOOK: u32 = 2000;
/// Outlines asked for per round trip.
const FILES_BATCH: usize = 200;
/// Servers drop IDLE after 30 minutes; renew it before that.
pub const IDLE_RENEW: Duration = Duration::from_secs(25 * 60);

/// How often Sent, Archive and Drafts are brought up to date.
pub const FOLDERS_EVERY: Duration = Duration::from_secs(5 * 60);

impl Connection {
    /// Connects and logs in.
    pub async fn open(cfg: &ImapConfig) -> Result<Self> {
        let tcp = TcpStream::connect((cfg.host.as_str(), cfg.port))
            .await
            .map_err(|source| ImapError::Connect {
                host: cfg.host.clone(),
                source,
            })?;
        tcp.set_nodelay(true).ok();

        let stream: Box<dyn Io> = match cfg.security {
            Security::Tls => Box::new(tls(&cfg.host, tcp).await?),
            Security::None => Box::new(tcp),
            Security::StartTls => {
                let mut client = async_imap::Client::new(tcp);
                greeting(&mut client).await?;
                client.run_command_and_check_ok("STARTTLS", None).await?;
                Box::new(tls(&cfg.host, client.into_inner()).await?)
            }
        };
        let mut client = async_imap::Client::new(stream);
        if cfg.security != Security::StartTls {
            greeting(&mut client).await?;
        }
        let mut session = client
            .login(&cfg.username, &cfg.password)
            .await
            .map_err(|(e, _)| classify_login(e))?;
        let caps = session.capabilities().await?;
        // For reports: which of the capabilities that matter it has, by a
        // number, never its name.
        crate::feedback::note_server(crate::feedback::server_key(&cfg.host, &cfg.username), |c| {
            caps.has_str(c)
        });
        Ok(Connection {
            session: Some(session),
            condstore: caps.has_str("CONDSTORE"),
            idle: caps.has_str("IDLE"),
            moves: caps.has_str("MOVE"),
            uidplus: caps.has_str("UIDPLUS"),
        })
    }

    /// Acts as if the server had no MOVE, to test the COPY fallback.
    #[doc(hidden)]
    pub fn forget_move_for_tests(&mut self) {
        self.moves = false;
    }

    pub fn supports_idle(&self) -> bool {
        self.idle
    }

    pub async fn logout(mut self) -> Result<()> {
        self.session()?.logout().await?;
        Ok(())
    }

    fn session(&mut self) -> Result<&mut Session> {
        self.session.as_mut().ok_or(ImapError::Protocol(
            async_imap::error::Error::ConnectionLost,
        ))
    }

    /// Brings the local copy of `mailbox` in line with the server.
    /// `progress` is called after each downloaded batch with
    /// (downloaded so far, total to download).
    pub async fn sync_mailbox(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        progress: impl FnMut(usize, usize),
    ) -> Result<SyncReport> {
        self.sync_round(store, account, mailbox, Round::WHOLE, progress)
            .await
    }

    /// One round of [`Self::sync_mailbox`]: downloads at most
    /// `round.limit` new messages, newest first, and says in
    /// [`SyncReport::more`] how many are left for the next rounds.
    pub async fn sync_round(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        round: Round,
        mut progress: impl FnMut(usize, usize),
    ) -> Result<SyncReport> {
        let mut report = SyncReport::default();
        let condstore = self.condstore;
        let session = self.session()?;
        let selected = if condstore {
            session.select_condstore(mailbox).await?
        } else {
            session.select(mailbox).await?
        };
        let uid_validity = selected.uid_validity.ok_or(ImapError::NoUidValidity)?;
        if !keeps_keywords(&selected) {
            lock(store).set_labels_local(account)?;
        }

        let (prior, local) = {
            let store = lock(store);
            let mut prior = store.mailbox_state(account, mailbox)?;
            if prior.is_some_and(|p| p.uid_validity != uid_validity) {
                store.clear_mailbox(account, mailbox)?;
                report.reset = true;
                prior = None;
            }
            let local: HashSet<u32> = store.uids(account, mailbox)?.into_iter().collect();
            (prior, local)
        };

        // 1. Forget what the server no longer has.
        let server = session.uid_search("ALL").await?;
        let gone: Vec<u32> = local.difference(&server).copied().collect();
        if !gone.is_empty() {
            lock(store).remove_messages(account, mailbox, &gone)?;
            report.removed = gone.len();
        }

        // 2. Download what is new, newest first so the inbox fills from the top.
        let mut missing: Vec<u32> = server.difference(&local).copied().collect();
        missing.sort_unstable_by(|a, b| b.cmp(a));
        let total = missing.len();
        report.more = total.saturating_sub(round.limit);
        missing.truncate(round.limit);
        // News is what came after the newest message we had: older ones
        // still arriving are history being filled in.
        let newest = local.iter().max().copied();
        let news = |uid: u32| prior.is_some() && newest.is_none_or(|n| uid > n);
        for batch in missing.chunks(BATCH) {
            let (fetches, html) = fetch_heads(session, account, mailbox, batch).await?;
            let summaries: Vec<MessageSummary> = fetches
                .iter()
                .filter_map(|f| summary_with(f, account, mailbox, &html))
                .collect();
            lock(store).upsert_messages(&summaries)?;
            let times: Vec<(u32, Option<i64>)> = fetches
                .iter()
                .filter_map(|f| Some((f.uid?, snooze_until(f))))
                .filter(|(_, t)| t.is_some())
                .collect();
            lock(store).set_snooze_times(account, mailbox, &times)?;
            lock(store).set_server_labels(account, mailbox, &labels_of(&fetches))?;
            report.added += summaries.len();
            for (f, s) in fetches
                .iter()
                .filter_map(|f| Some((f, summary_with(f, account, mailbox, &html)?)))
                .filter(|(_, s)| news(s.uid))
            {
                report.arrived.push(Arrival {
                    summary: s,
                    automated: is_automated(f),
                });
            }
            progress(report.added, total);
        }

        // 3. Refresh flags of what we already had.
        // Rounds that only fill in history skip it, and keep the old
        // modseq so the round that does look misses no change.
        let kept: Vec<u32> = local.intersection(&server).copied().collect();
        if round.flags && !kept.is_empty() {
            let flags_query = match prior.and_then(|p| p.highest_modseq) {
                Some(modseq) if condstore => Some((
                    "1:*".to_owned(),
                    format!("(UID FLAGS) (CHANGEDSINCE {modseq})"),
                )),
                _ => Some((uid_set(&kept), "(UID FLAGS)".to_owned())),
            };
            if let Some((set, q)) = flags_query {
                let fetches: Vec<Fetch> = session.uid_fetch(set, q).await?.try_collect().await?;
                let changes: Vec<(u32, Flags)> = fetches
                    .iter()
                    .filter_map(|f| Some((f.uid?, flags(f))))
                    .collect();
                report.flags_changed = lock(store).update_flags(account, mailbox, &changes)?;
                let times: Vec<(u32, Option<i64>)> = fetches
                    .iter()
                    .filter_map(|f| Some((f.uid?, snooze_until(f))))
                    .collect();
                lock(store).set_snooze_times(account, mailbox, &times)?;
                lock(store).set_server_labels(account, mailbox, &labels_of(&fetches))?;
            }
        }

        // 4. Inbox mail cached before the list headers were read: read them
        // now, so newsletters move to their own list.
        if mailbox == "INBOX" {
            let unchecked = lock(store).unchecked_lists(account, mailbox, round.limit as u32)?;
            for batch in unchecked.chunks(BATCH) {
                let fetches: Vec<Fetch> = session
                    .uid_fetch(
                        uid_set(batch),
                        format!(
                            "(UID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT {} {} {} {})])",
                            notify::HEADER_FIELDS,
                            crate::automation::HEADER_FIELDS,
                            newsletter::HEADER_FIELDS,
                            groups::HEADER_FIELDS
                        ),
                    )
                    .await?
                    .try_collect()
                    .await?;
                let mut recipients = Vec::new();
                let mut lists: Vec<(u32, ListInfo)> = fetches
                    .iter()
                    .filter_map(|f| {
                        let m = MessageParser::default().parse_headers(f.header()?)?;
                        recipients.push((f.uid?, groups::recipients(&m)));
                        Some((f.uid?, newsletter::list_info(&m)))
                    })
                    .collect();
                lock(store).set_recipients(account, mailbox, &recipients)?;
                // What the server no longer answers for is not asked again.
                for uid in batch {
                    if !lists.iter().any(|(u, _)| u == uid) {
                        lists.push((*uid, ListInfo::default()));
                    }
                }
                report.filed += lists.iter().filter(|(_, l)| l.newsletter).count();
                lock(store).set_list_info(account, mailbox, &lists)?;
            }

            // 5. The newest newsletters whole, to read them offline and
            // know how long they take.
            let wanted: Vec<u32> = lock(store)
                .newsletters_without_body(account, NEWSLETTER_BODIES)?
                .into_iter()
                .filter(|(m, _)| m == mailbox)
                .map(|(_, uid)| uid)
                .collect();
            fetch_bodies(session, store, account, mailbox, &wanted, NEWSLETTER_BYTES).await?;
        }

        // 6. Mail whose subject sounds like a parcel, a bill or a trip,
        // whole, for the Vault's cards.
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or_default();
        let wanted = lock(store).vault_unchecked(account, mailbox, now, VAULT_LOOK)?;
        for batch in wanted.chunks(VAULT_BODIES) {
            let fetched =
                fetch_bodies(session, store, account, mailbox, batch, VAULT_BYTES).await?;
            let skipped: Vec<u32> = batch
                .iter()
                .filter(|u| !fetched.contains(u))
                .copied()
                .collect();
            lock(store).skip_vault(account, mailbox, &skipped)?;
            report.carded += fetched.len();
        }

        // 7. What files each message carries, from the server's outline
        // of it, for the Attachments board.
        let unlisted = lock(store).files_unchecked(account, mailbox, FILES_LOOK)?;
        for batch in unlisted.chunks(FILES_BATCH) {
            let fetches: Vec<Fetch> = session
                .uid_fetch(uid_set(batch), "(UID BODYSTRUCTURE)")
                .await?
                .try_collect()
                .await?;
            let listed: Vec<(u32, Vec<Attachment>)> = fetches
                .iter()
                .filter_map(|f| Some((f.uid?, listed_files(f.bodystructure()?))))
                .collect();
            report.listed += listed.iter().filter(|(_, files)| !files.is_empty()).count();
            lock(store).set_listed_files(account, mailbox, &listed)?;
            // What the server had no outline for has no files to list.
            let none: Vec<(u32, Vec<Attachment>)> = batch
                .iter()
                .filter(|u| !listed.iter().any(|(l, _)| l == *u))
                .map(|u| (*u, Vec::new()))
                .collect();
            lock(store).set_listed_files(account, mailbox, &none)?;
        }

        // 7b. The newest Inbox mail whole, so opening it shows the text
        // at once instead of "Loading…". After 7, so its files keep the
        // server's outline.
        if mailbox == "INBOX" {
            let wanted = lock(store).inbox_without_body(account, mailbox, INBOX_BODIES)?;
            fetch_bodies(session, store, account, mailbox, &wanted, INBOX_BYTES).await?;
        }

        // 8. Previews made before they followed the reader (blocks run
        // together, raw HTML): made again from the start of the message.
        let stale = lock(store).previews_to_mend(account, mailbox, MEND_LOOK)?;
        for batch in stale.chunks(BATCH) {
            let (fetches, html) = fetch_heads(session, account, mailbox, batch).await?;
            let mut mended: Vec<(u32, String)> = fetches
                .iter()
                .filter_map(|f| summary_with(f, account, mailbox, &html))
                .map(|s| (s.uid, s.preview))
                .collect();
            // What the server no longer answers for is not asked again.
            for uid in batch {
                if !mended.iter().any(|(u, _)| u == uid) {
                    mended.push((*uid, String::new()));
                }
            }
            lock(store).mend_previews(account, mailbox, &mended)?;
        }

        lock(store).set_mailbox_state(
            account,
            mailbox,
            MailboxState {
                uid_validity,
                highest_modseq: match prior {
                    Some(p) if !round.flags => p.highest_modseq,
                    _ => selected.highest_modseq,
                },
            },
        )?;
        Ok(report)
    }

    /// The readable text of one message, from the cache or the server.
    pub async fn body(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<String> {
        if let Some(text) = lock(store).body(account, mailbox, uid)? {
            return Ok(text);
        }
        Ok(self.full_body(store, account, mailbox, uid).await?.text)
    }

    /// Text and HTML of one message, from the cache or the server.
    pub async fn full_body(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<Body> {
        if let Some(body) = lock(store).full_body(account, mailbox, uid)? {
            return Ok(body);
        }
        let session = self.session()?;
        session.examine(mailbox).await?;
        let fetches: Vec<Fetch> = session
            .uid_fetch(uid.to_string(), "(UID BODY.PEEK[])")
            .await?
            .try_collect()
            .await?;
        let body = fetches
            .iter()
            .find_map(|f| f.body())
            .map(parse_body)
            .unwrap_or_default();
        lock(store).set_full_body(account, mailbox, uid, &body)?;
        Ok(body)
    }

    /// The content of one attachment, fetched from the server.
    pub async fn attachment(&mut self, mailbox: &str, uid: u32, part: u32) -> Result<Vec<u8>> {
        let raw = self.raw(mailbox, uid).await?;
        attachment_data(&raw, part).ok_or(ImapError::Gone)
    }

    /// One part of a message, fetched alone by its number in the
    /// server's outline, decoded.
    pub async fn section(
        &mut self,
        mailbox: &str,
        uid: u32,
        section: &str,
        encoding: Option<&str>,
    ) -> Result<Vec<u8>> {
        let path: Vec<u32> = section
            .split('.')
            .map(str::parse)
            .collect::<std::result::Result<_, _>>()
            .map_err(|_| ImapError::Gone)?;
        let session = self.session()?;
        session.examine(mailbox).await?;
        let fetches: Vec<Fetch> = session
            .uid_fetch(uid.to_string(), format!("(UID BODY.PEEK[{section}])"))
            .await?
            .try_collect()
            .await?;
        let data = fetches
            .iter()
            .find_map(|f| f.section(&SectionPath::Part(path.clone(), None)))
            .ok_or(ImapError::Gone)?;
        decode_part(data, encoding).ok_or(ImapError::Gone)
    }

    /// One whole message as the server keeps it.
    pub async fn raw(&mut self, mailbox: &str, uid: u32) -> Result<Vec<u8>> {
        let session = self.session()?;
        session.examine(mailbox).await?;
        let fetches: Vec<Fetch> = session
            .uid_fetch(uid.to_string(), "(UID BODY.PEEK[])")
            .await?
            .try_collect()
            .await?;
        fetches
            .iter()
            .find_map(|f| f.body().map(<[u8]>::to_vec))
            .ok_or(ImapError::Gone)
    }

    /// Waits on the selected folder until the server reports a change or
    /// `timeout` passes. Returns true when something changed.
    pub async fn wait_for_change(&mut self, timeout: Duration) -> Result<bool> {
        // Changes that arrived during the last commands count too.
        let idle = self.idle;
        let session = self.session()?;
        let mut pending = false;
        while session.unsolicited_responses.try_recv().is_ok() {
            pending = true;
        }
        if pending {
            return Ok(true);
        }
        if !idle {
            tokio::time::sleep(timeout.min(Duration::from_secs(60))).await;
            session.noop().await?;
            let mut changed = false;
            while session.unsolicited_responses.try_recv().is_ok() {
                changed = true;
            }
            return Ok(changed);
        }

        // IDLE takes the session by value and gives it back when done.
        let mut handle = self.session.take().expect("checked above").idle();
        let outcome = async {
            handle.init().await?;
            let (wait, stop) = handle.wait_with_timeout(timeout);
            // async-imap starts its timeout over at every line, and servers
            // say "Still here" every few minutes: without a deadline of our
            // own, a server that never reports new mail keeps us waiting
            // for ever.
            tokio::pin!(wait);
            tokio::select! {
                response = &mut wait => response,
                () = tokio::time::sleep(timeout) => {
                    drop(stop);
                    wait.await
                }
            }
        }
        .await;
        self.session = Some(handle.done().await?);
        Ok(matches!(outcome?, IdleResponse::NewData(_)))
    }

    /// The folder for a role: the one marked for it (RFC 6154), else one
    /// with a usual name, else a new folder with the first usual name.
    /// The spam folder is never made: without one, this fails.
    pub async fn folder(&mut self, role: FolderRole) -> Result<String> {
        let names = self.list().await?;
        if let Some(name) = pick_folder(&names, role) {
            return Ok(name);
        }
        if role == FolderRole::Junk {
            return Err(ImapError::NoFolder);
        }
        let name = new_folder_name(&names, role.markers().1[0]);
        self.session()?.create(&name).await?;
        Ok(name)
    }

    /// Makes a folder of the account's own, at the top, and lists it at
    /// once. Returns its server name.
    pub async fn create_folder(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        name: &str,
    ) -> Result<String> {
        let names = self.list().await?;
        let mailbox = new_folder_name(&names, &utf7_encode(name.trim()));
        self.session()?.create(&mailbox).await?;
        lock(store).add_account_folder(
            account,
            &crate::AccountFolder {
                mailbox: mailbox.clone(),
                name: name.trim().to_owned(),
                depth: 0,
                selectable: true,
                unread: 0,
                total: 0,
            },
        )?;
        Ok(mailbox)
    }

    /// The folder with a job, when the account has one.
    pub async fn find_folder(&mut self, role: FolderRole) -> Result<Option<String>> {
        let names = self.list().await?;
        Ok(pick_folder(&names, role))
    }

    async fn list(&mut self) -> Result<Vec<async_imap::types::Name>> {
        Ok(self
            .session()?
            .list(Some(""), Some("*"))
            .await?
            .try_collect()
            .await?)
    }

    /// Finds Sent, Archive and Drafts, remembers them, and brings them up
    /// to date.
    pub async fn sync_folders(&mut self, store: &Mutex<Store>, account: AccountId) -> Result<()> {
        self.sync_folders_round(store, account, Round::WHOLE)
            .await
            .map(|_| ())
    }

    /// One round of [`Self::sync_folders`]. Returns how many messages are
    /// left to download in them.
    pub async fn sync_folders_round(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        round: Round,
    ) -> Result<usize> {
        let names = self.list().await?;
        let mut skip: HashSet<String> = [FolderRole::Trash]
            .into_iter()
            .filter_map(|r| pick_folder(&names, r))
            .collect();
        // Report spam moves mail there; the app offers it only when found.
        lock(store).set_junk_mailbox(account, pick_folder(&names, FolderRole::Junk).as_deref())?;
        // The sync space's folder stays hidden.
        skip.insert(crate::space::FOLDER.to_owned());
        skip.extend(space_folder_in(&names));
        let mut more = 0;
        for (role, folder) in [
            (FolderRole::Sent, Folder::Sent),
            (FolderRole::Archive, Folder::Archive),
            (FolderRole::Drafts, Folder::Drafts),
            (FolderRole::Snoozed, Folder::Snoozed),
        ] {
            let Some(name) = pick_folder(&names, role) else {
                continue;
            };
            skip.insert(name.clone());
            lock(store).set_folder_role(account, folder, &name)?;
            more += self
                .sync_round(store, account, &name, round, |_, _| {})
                .await?
                .more;
        }
        let listed: Vec<Listed> = names
            .iter()
            .filter(|n| !n.attributes().iter().any(is_special))
            .map(|n| Listed {
                name: n.name().to_owned(),
                delimiter: n.delimiter().map(str::to_owned),
                selectable: !n.attributes().contains(&NameAttribute::NoSelect)
                    && !n
                        .attributes()
                        .iter()
                        .any(|a| matches!(a, NameAttribute::Extension(e) if e.eq_ignore_ascii_case("\\NonExistent"))),
            })
            .collect();
        let mut folders = own_folders(&listed, &skip);
        let session = self.session()?;
        for f in folders.iter_mut().filter(|f| f.selectable) {
            if let Ok(status) = session.status(&f.mailbox, "(MESSAGES UNSEEN)").await {
                f.unread = status.unseen.unwrap_or_default();
                f.total = status.exists;
            }
        }
        lock(store).set_account_folders(account, &folders)?;
        Ok(more)
    }

    /// Moves one message to the folder for `role` and forgets it locally.
    /// Returns the folder it went to.
    pub async fn move_message(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        role: FolderRole,
    ) -> Result<String> {
        self.move_messages(store, account, mailbox, &[uid], role)
            .await
    }

    /// Moves messages of one folder to Archive, Trash or spam in one command.
    /// Returns the folder they went to.
    pub async fn move_messages(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        role: FolderRole,
    ) -> Result<String> {
        let target = self.folder(role).await?;
        self.move_to(store, account, mailbox, uids, &target).await?;
        Ok(target)
    }

    /// Moves messages of one folder to `target`, by its server name, and
    /// forgets them locally.
    pub async fn move_to(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        target: &str,
    ) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let (moves, uidplus) = (self.moves, self.uidplus);
        let session = self.session()?;
        session.select(mailbox).await?;
        let set = uids
            .iter()
            .map(u32::to_string)
            .collect::<Vec<_>>()
            .join(",");
        if moves {
            session.uid_mv(&set, target).await?;
        } else {
            session.uid_copy(&set, target).await?;
            let _: Vec<_> = session
                .uid_store(&set, "+FLAGS.SILENT (\\Deleted)")
                .await?
                .try_collect()
                .await?;
            if uidplus {
                let _: Vec<_> = session.uid_expunge(&set).await?.try_collect().await?;
            } else {
                let _: Vec<_> = session.expunge().await?.try_collect().await?;
            }
        }
        lock(store).remove_messages(account, mailbox, uids)?;
        Ok(())
    }

    /// Puts messages away in Snoozed until `until` (Unix seconds), with
    /// the time as a keyword so the account's other devices know it. Mail
    /// already there just gets the new time.
    pub async fn snooze(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        until: i64,
    ) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let target = self.folder(FolderRole::Snoozed).await?;
        let session = self.session()?;
        session.select(mailbox).await?;
        let old = snooze_keywords(session, uids).await?;
        // A server without keywords keeps the time on this device only.
        if !old.is_empty() {
            if let Ok(stream) = session
                .uid_store(uid_set(uids), format!("-FLAGS.SILENT ({})", old.join(" ")))
                .await
            {
                let _: std::result::Result<Vec<_>, _> = stream.try_collect().await;
            }
        }
        if let Ok(stream) = session
            .uid_store(
                uid_set(uids),
                format!("+FLAGS.SILENT ({})", snooze_keyword(until)),
            )
            .await
        {
            let _: std::result::Result<Vec<_>, _> = stream.try_collect().await;
        }
        if mailbox == target {
            let store = lock(store);
            for uid in uids {
                store.set_hidden(account, mailbox, *uid, false)?;
            }
            return Ok(());
        }
        self.move_to(store, account, mailbox, uids, &target).await?;
        // So the Snoozed list shows them now, not at the next folder look.
        lock(store).set_folder_role(account, Folder::Snoozed, &target)?;
        self.sync_round(store, account, &target, Round::WHOLE, |_, _| {})
            .await?;
        Ok(())
    }

    /// Brings snoozed messages back to the inbox, unread, without their
    /// time.
    pub async fn wake(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        until: i64,
    ) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let session = self.session()?;
        session.select(mailbox).await?;
        let _: Vec<_> = session
            .uid_store(uid_set(uids), "-FLAGS.SILENT (\\Seen)")
            .await?
            .try_collect()
            .await?;
        // Every time keyword goes, in case another app snoozed it again.
        let mut keywords = snooze_keywords(session, uids).await?;
        keywords.push(snooze_keyword(until));
        keywords.sort();
        keywords.dedup();
        if let Ok(stream) = session
            .uid_store(
                uid_set(uids),
                format!("-FLAGS.SILENT ({})", keywords.join(" ")),
            )
            .await
        {
            let _: std::result::Result<Vec<_>, _> = stream.try_collect().await;
        }
        lock(store).forget_snoozes(account, mailbox, uids)?;
        self.move_to(store, account, mailbox, uids, "INBOX").await
    }

    /// Marks messages of one folder read or unread on the server.
    pub async fn set_seen(&mut self, mailbox: &str, uids: &[u32], seen: bool) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let session = self.session()?;
        session.select(mailbox).await?;
        let set: Vec<String> = uids.iter().map(u32::to_string).collect();
        let op = if seen {
            "+FLAGS.SILENT (\\Seen)"
        } else {
            "-FLAGS.SILENT (\\Seen)"
        };
        let _: Vec<_> = session
            .uid_store(set.join(","), op)
            .await?
            .try_collect()
            .await?;
        Ok(())
    }

    /// Puts a label's keyword on messages of one folder, or takes it off.
    /// A folder that takes no new keywords (no `\*` in its
    /// PERMANENTFLAGS) keeps the account's labels on this device instead.
    pub async fn set_keyword(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        keyword: &str,
        add: bool,
    ) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let session = self.session()?;
        let selected = session.select(mailbox).await?;
        if !keeps_keywords(&selected) {
            lock(store).set_labels_local(account)?;
            return Ok(());
        }
        let op = format!("{}FLAGS.SILENT ({keyword})", if add { "+" } else { "-" });
        let _: Vec<_> = session
            .uid_store(uid_set(uids), op)
            .await?
            .try_collect()
            .await?;
        Ok(())
    }

    /// Tells the server's spam filter what the person said: `$Junk` on
    /// spam, `$NotJunk` on mail that isn't, each taking the other off. A
    /// folder that takes no new keywords is left as it is.
    pub async fn mark_junk(&mut self, mailbox: &str, uids: &[u32], junk: bool) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let session = self.session()?;
        let selected = session.select(mailbox).await?;
        if !keeps_keywords(&selected) {
            return Ok(());
        }
        let (on, off) = if junk {
            ("$Junk", "$NotJunk")
        } else {
            ("$NotJunk", "$Junk")
        };
        for op in [
            format!("+FLAGS.SILENT ({on})"),
            format!("-FLAGS.SILENT ({off})"),
        ] {
            let _: Vec<_> = session
                .uid_store(uid_set(uids), op)
                .await?
                .try_collect()
                .await?;
        }
        Ok(())
    }

    /// Keeps a draft in the Drafts folder, made if the account has none.
    /// Returns the folder.
    pub async fn append_draft(&mut self, raw: &[u8]) -> Result<String> {
        let folder = self.folder(FolderRole::Drafts).await?;
        self.session()?
            .append(&folder, Some("(\\Seen \\Draft)"), None, raw)
            .await?;
        Ok(folder)
    }

    /// Deletes messages of one folder for good, without Trash, and forgets
    /// them locally: an earlier copy of a draft.
    pub async fn erase(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let uidplus = self.uidplus;
        let session = self.session()?;
        session.select(mailbox).await?;
        let set = uids
            .iter()
            .map(u32::to_string)
            .collect::<Vec<_>>()
            .join(",");
        let _: Vec<_> = session
            .uid_store(&set, "+FLAGS.SILENT (\\Deleted)")
            .await?
            .try_collect()
            .await?;
        if uidplus {
            let _: Vec<_> = session.uid_expunge(&set).await?.try_collect().await?;
        } else {
            let _: Vec<_> = session.expunge().await?.try_collect().await?;
        }
        lock(store).remove_messages(account, mailbox, uids)?;
        Ok(())
    }

    /// The notes in the sync space's hidden folder, oldest first, each
    /// with its uid; none while the folder isn't there.
    pub async fn space_notes(&mut self) -> Result<Vec<(u32, crate::space::Note)>> {
        let names = self.list().await?;
        let Some(folder) = space_folder_in(&names) else {
            return Ok(Vec::new());
        };
        let session = self.session()?;
        let mailbox = session.examine(&folder).await?;
        if mailbox.exists == 0 {
            return Ok(Vec::new());
        }
        let fetches: Vec<Fetch> = session
            .fetch("1:*", "(UID BODY.PEEK[])")
            .await?
            .try_collect()
            .await?;
        let mut notes: Vec<(u32, crate::space::Note)> = fetches
            .iter()
            .filter_map(|f| {
                let note = crate::space::Note::from_message(f.body()?)?;
                Some((f.uid?, note))
            })
            .collect();
        notes.sort_by_key(|(uid, _)| *uid);
        Ok(notes)
    }

    /// Adds a note to the sync space's hidden folder, made when missing.
    pub async fn space_put(&mut self, raw: &[u8]) -> Result<()> {
        let names = self.list().await?;
        let session = self.session()?;
        let folder = match space_folder_in(&names) {
            Some(f) => f,
            None => {
                let f = new_folder_name(&names, crate::space::FOLDER);
                session.create(&f).await?;
                f
            }
        };
        session.append(&folder, Some("(\\Seen)"), None, raw).await?;
        Ok(())
    }

    /// Deletes notes of the sync space's folder for good.
    pub async fn space_remove(&mut self, uids: &[u32]) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let uidplus = self.uidplus;
        let names = self.list().await?;
        let Some(folder) = space_folder_in(&names) else {
            return Ok(());
        };
        let session = self.session()?;
        session.select(&folder).await?;
        let set = uids
            .iter()
            .map(u32::to_string)
            .collect::<Vec<_>>()
            .join(",");
        let _: Vec<_> = session
            .uid_store(&set, "+FLAGS.SILENT (\\Deleted)")
            .await?
            .try_collect()
            .await?;
        if uidplus {
            let _: Vec<_> = session.uid_expunge(&set).await?.try_collect().await?;
        } else {
            let _: Vec<_> = session.expunge().await?.try_collect().await?;
        }
        Ok(())
    }

    /// Files a sent message, already marked as read. Returns the folder.
    pub async fn append_sent(&mut self, raw: &[u8]) -> Result<String> {
        let folder = self.folder(FolderRole::Sent).await?;
        self.session()?
            .append(&folder, Some("(\\Seen)"), None, raw)
            .await?;
        Ok(folder)
    }
}

/// Folders with a job, found by their RFC 6154 marker or a usual name.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FolderRole {
    Sent,
    Archive,
    Trash,
    Drafts,
    /// Mail put away until a time (`\Snoozed`, as Fastmail marks it).
    Snoozed,
    /// Spam (`\Junk`), for Report spam. Never made when missing.
    Junk,
}

impl FolderRole {
    fn markers(self) -> (NameAttribute<'static>, &'static [&'static str]) {
        match self {
            FolderRole::Sent => (
                NameAttribute::Sent,
                &[
                    "Sent",
                    "Sent Items",
                    "Sent Messages",
                    "INBOX.Sent",
                    "Posta inviata",
                ],
            ),
            FolderRole::Archive => (
                NameAttribute::Archive,
                &["Archive", "Archives", "INBOX.Archive", "Archivio"],
            ),
            FolderRole::Drafts => (
                NameAttribute::Drafts,
                &["Drafts", "Draft", "INBOX.Drafts", "Bozze"],
            ),
            FolderRole::Trash => (
                NameAttribute::Trash,
                &[
                    "Trash",
                    "Deleted Items",
                    "Deleted Messages",
                    "INBOX.Trash",
                    "Cestino",
                ],
            ),
            FolderRole::Snoozed => (
                NameAttribute::Extension(Cow::Borrowed("\\Snoozed")),
                &["Snoozed", "INBOX.Snoozed"],
            ),
            FolderRole::Junk => (
                NameAttribute::Junk,
                &[
                    "Junk",
                    "Spam",
                    "Junk E-mail",
                    "INBOX.Junk",
                    "INBOX.Spam",
                    "Posta indesiderata",
                ],
            ),
        }
    }
}

/// How much of a folder one sync round does.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Round {
    /// New messages to download at most.
    pub limit: usize,
    /// Whether to refresh the flags of messages already here.
    pub flags: bool,
}

impl Round {
    /// Everything at once.
    pub const WHOLE: Round = Round {
        limit: usize::MAX,
        flags: true,
    };
}

/// A folder as LIST names it.
#[derive(Debug, Clone)]
struct Listed {
    name: String,
    delimiter: Option<String>,
    selectable: bool,
}

/// Folders with a job the app already shows, or that hold no mail of
/// their own: they stay out of the account's folder list.
fn is_special(a: &NameAttribute<'_>) -> bool {
    matches!(
        a,
        NameAttribute::All
            | NameAttribute::Archive
            | NameAttribute::Drafts
            | NameAttribute::Flagged
            | NameAttribute::Junk
            | NameAttribute::Sent
            | NameAttribute::Trash
    )
}

/// Usual names of the spam folder, for servers that don't mark it.
const JUNK: &[&str] = &["Junk", "Spam", "Junk E-mail", "Posta indesiderata"];

/// The account's own folders in tree order: not the inbox, not the ones
/// in `skip`, not spam. Servers that keep everything under INBOX
/// ("INBOX.Clients") show it as a top folder; a parent the server doesn't
/// list is added, as a folder that only holds others.
fn own_folders(listed: &[Listed], skip: &HashSet<String>) -> Vec<crate::AccountFolder> {
    let mut by_path: std::collections::BTreeMap<Vec<String>, crate::AccountFolder> =
        Default::default();
    for l in listed {
        if l.name.eq_ignore_ascii_case("INBOX") || skip.contains(&l.name) {
            continue;
        }
        let mut parts: Vec<&str> = match &l.delimiter {
            Some(d) if !d.is_empty() => l.name.split(d.as_str()).collect(),
            _ => vec![l.name.as_str()],
        };
        if parts.len() > 1 && parts[0].eq_ignore_ascii_case("INBOX") {
            parts.remove(0);
        }
        if parts.len() == 1 && JUNK.iter().any(|j| j.eq_ignore_ascii_case(parts[0])) {
            continue;
        }
        let key =
            |n: usize| -> Vec<String> { parts[..n].iter().map(|p| p.to_lowercase()).collect() };
        for depth in 1..parts.len() {
            let prefix = parts[..depth].join(l.delimiter.as_deref().unwrap_or_default());
            by_path.entry(key(depth)).or_insert(crate::AccountFolder {
                mailbox: prefix,
                name: utf7_decode(parts[depth - 1]),
                depth: depth as u32 - 1,
                selectable: false,
                unread: 0,
                total: 0,
            });
        }
        by_path.insert(
            key(parts.len()),
            crate::AccountFolder {
                mailbox: l.name.clone(),
                name: utf7_decode(parts[parts.len() - 1]),
                depth: parts.len() as u32 - 1,
                selectable: l.selectable,
                unread: 0,
                total: 0,
            },
        );
    }
    by_path.into_values().collect()
}

/// The folder for a role among the account's folders: the one marked for
/// it (RFC 6154), else one with a usual name.
/// Where a new folder goes: under INBOX on servers that keep every
/// folder there ("INBOX.Snoozed"), else at the top.
/// A folder name as IMAP writes it (RFC 3501, modified UTF-7): "Città"
/// is "Citt&AOA-".
pub fn utf7_encode(name: &str) -> String {
    use base64::Engine;
    let b64 = base64::engine::general_purpose::STANDARD_NO_PAD;
    let mut out = String::new();
    let mut run: Vec<u16> = Vec::new();
    let flush = |run: &mut Vec<u16>, out: &mut String| {
        if run.is_empty() {
            return;
        }
        let bytes: Vec<u8> = run.iter().flat_map(|u| u.to_be_bytes()).collect();
        out.push('&');
        out.push_str(&b64.encode(bytes).replace('/', ","));
        out.push('-');
        run.clear();
    };
    for c in name.chars() {
        if (' '..='~').contains(&c) {
            flush(&mut run, &mut out);
            out.push(c);
            if c == '&' {
                out.push('-');
            }
        } else {
            let mut buf = [0u16; 2];
            run.extend_from_slice(c.encode_utf16(&mut buf));
        }
    }
    flush(&mut run, &mut out);
    out
}

/// A folder name from IMAP's modified UTF-7, as people read it; left as
/// it is when it isn't valid.
pub fn utf7_decode(name: &str) -> String {
    use base64::Engine;
    let b64 = base64::engine::general_purpose::STANDARD_NO_PAD;
    let mut out = String::new();
    let mut rest = name;
    while let Some(start) = rest.find('&') {
        out.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        let Some(end) = after.find('-') else {
            return name.to_owned();
        };
        let chunk = &after[..end];
        if chunk.is_empty() {
            out.push('&');
        } else {
            let Ok(bytes) = b64.decode(chunk.replace(',', "/")) else {
                return name.to_owned();
            };
            if bytes.len() % 2 != 0 {
                return name.to_owned();
            }
            let units: Vec<u16> = bytes
                .chunks(2)
                .map(|p| u16::from_be_bytes([p[0], p[1]]))
                .collect();
            match String::from_utf16(&units) {
                Ok(s) => out.push_str(&s),
                Err(_) => return name.to_owned(),
            }
        }
        rest = &after[end + 1..];
    }
    out.push_str(rest);
    out
}

/// The sync space's folder among `names`: at the top, or under INBOX on
/// servers that keep every folder there (Aruba, many cPanel hosts).
fn space_folder_in(names: &[async_imap::types::Name]) -> Option<String> {
    names
        .iter()
        .map(|n| n.name())
        .find(|name| is_space_folder(name))
        .map(str::to_owned)
}

/// "Piuma Sync", or "INBOX.Piuma Sync" and the like.
fn is_space_folder(name: &str) -> bool {
    let f = crate::space::FOLDER;
    name == f
        || (name.len() == 6 + f.len()
            && name.is_char_boundary(5)
            && name[..5].eq_ignore_ascii_case("INBOX")
            && name.ends_with(f))
}

fn new_folder_name(names: &[async_imap::types::Name], base: &str) -> String {
    let under_inbox = |n: &&async_imap::types::Name| {
        let name = n.name();
        name.len() > 6 && name[..5].eq_ignore_ascii_case("INBOX") && n.delimiter().is_some()
    };
    let others: Vec<_> = names
        .iter()
        .filter(|n| !n.name().eq_ignore_ascii_case("INBOX"))
        .collect();
    match others.first() {
        Some(first) if others.iter().all(under_inbox) => {
            format!("INBOX{}{base}", first.delimiter().unwrap_or("."))
        }
        _ => base.to_owned(),
    }
}

fn pick_folder(names: &[async_imap::types::Name], role: FolderRole) -> Option<String> {
    let listed: Vec<(&str, &[NameAttribute<'_>])> =
        names.iter().map(|n| (n.name(), n.attributes())).collect();
    pick_named(&listed, role)
}

/// [`pick_folder`] on names and their attributes.
fn pick_named(names: &[(&str, &[NameAttribute<'_>])], role: FolderRole) -> Option<String> {
    let (attribute, usual) = role.markers();
    if let Some((name, _)) = names.iter().find(|(_, a)| a.contains(&attribute)) {
        return Some((*name).to_owned());
    }
    usual.iter().find_map(|usual| {
        names
            .iter()
            .find(|(name, _)| name.eq_ignore_ascii_case(usual))
            .map(|(name, _)| (*name).to_owned())
    })
}

/// What one sync changed.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct SyncReport {
    pub added: usize,
    /// What landed since the last sync, for notifications. Empty on the
    /// first download of a folder, which is history rather than news.
    pub arrived: Vec<Arrival>,
    pub removed: usize,
    pub flags_changed: usize,
    /// The server renumbered the folder, so the cache was rebuilt.
    pub reset: bool,
    /// Messages still to download after a round that stopped at its limit.
    pub more: usize,
    /// Inbox mail found to be newsletters once its list headers were read.
    pub filed: usize,
    /// Bodies fetched for the Vault's cards.
    pub carded: usize,
    /// Messages found to carry files, for the Attachments board.
    pub listed: usize,
}

impl SyncReport {
    pub fn changed(&self) -> bool {
        self.added + self.removed + self.flags_changed + self.filed + self.carded + self.listed > 0
            || self.reset
    }
}

/// Checks that the settings work: connects, logs in and logs out.
pub async fn check_login(cfg: &ImapConfig) -> Result<()> {
    Connection::open(cfg).await?.logout().await
}

/// Events the watcher reports to the app.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WatchEvent {
    Progress {
        account: AccountId,
        done: usize,
        total: usize,
    },
    Synced {
        account: AccountId,
        report: SyncReport,
    },
    /// The connection failed; the watcher retries on its own.
    Offline { account: AccountId, reason: String },
}

/// Keeps `mailbox` of one account in sync forever: sync, wait for a change
/// with IDLE (or poll), sync again. Reconnects with a growing pause after
/// errors. Wrong credentials end the loop.
pub async fn watch(
    cfg: ImapConfig,
    store: Arc<Mutex<Store>>,
    account: AccountId,
    mailbox: String,
    events: impl Fn(WatchEvent),
) -> Result<()> {
    let mut pause = Duration::from_secs(2);
    loop {
        let session = async {
            let mut conn = Connection::open(&cfg).await?;
            pause = Duration::from_secs(2);
            let mut folders_synced: Option<std::time::Instant> = None;
            // A big mailbox comes down in rounds, the inbox first: each
            // round also takes the newest mail, and only the first one
            // after a quiet spell refreshes flags. `filled` counts what
            // earlier rounds of this download brought, for the progress.
            let (mut inbox_more, mut folders_more, mut filled) = (0, 0, 0);
            // A download that was under way before this connection (the
            // app restarted, the network came back) goes on counting
            // from what is already here, so the total stays put.
            let had = lock(&store).uids(account, &mailbox)?.len();
            let mut first = true;
            loop {
                crate::pending::send(&mut conn, &store, account).await?;
                let flags = inbox_more == 0;
                let mut report = conn
                    .sync_round(
                        &store,
                        account,
                        &mailbox,
                        Round {
                            limit: ROUND,
                            flags,
                        },
                        |done, total| {
                            let base = if first && total > ROUND { had } else { filled };
                            events(WatchEvent::Progress {
                                account,
                                done: base + done,
                                total: base + total,
                            })
                        },
                    )
                    .await?;
                if crate::rules::after_sync(&store, account, &mut report)? {
                    crate::pending::send(&mut conn, &store, account).await?;
                }
                inbox_more = report.more;
                let base = if first && inbox_more > 0 { had } else { filled };
                first = false;
                filled = if inbox_more > 0 {
                    base + report.added
                } else {
                    0
                };
                events(WatchEvent::Synced { account, report });
                if inbox_more > 0 {
                    events(WatchEvent::Progress {
                        account,
                        done: filled,
                        total: filled + inbox_more,
                    });
                }
                // The other folders change mostly through this app, so a
                // look every few minutes keeps them close enough.
                if folders_more > 0 || folders_synced.is_none_or(|t| t.elapsed() >= FOLDERS_EVERY) {
                    let round = Round {
                        limit: ROUND,
                        flags: folders_more == 0,
                    };
                    folders_more = conn.sync_folders_round(&store, account, round).await?;
                    folders_synced = Some(std::time::Instant::now());
                    // IDLE watches the selected folder.
                    conn.session()?.select(&mailbox).await?;
                }
                if inbox_more + folders_more > 0 {
                    continue;
                }
                let started = std::time::Instant::now();
                // Snoozed mail comes back, and mail sent later goes, on
                // time, mail or no mail.
                let wake = lock(&store)
                    .next_due(account, crate::pending::now())?
                    .map(|at| Duration::from_secs((at - crate::pending::now()).max(1) as u64));
                let wait = IDLE_RENEW
                    .min(FOLDERS_EVERY)
                    .min(wake.unwrap_or(IDLE_RENEW));
                while !conn.wait_for_change(wait).await? {
                    if started.elapsed() >= FOLDERS_EVERY.min(wait) {
                        break;
                    }
                }
            }
        };
        // A new network: start over on it right away, quietly.
        let result: Result<()> = tokio::select! {
            result = session => result,
            () = crate::network::wait() => {
                pause = Duration::ZERO;
                Ok(())
            }
        };
        match result {
            Err(ImapError::Auth) => return Err(ImapError::Auth),
            Err(e) => events(WatchEvent::Offline {
                account,
                reason: e.to_string(),
            }),
            Ok(()) => {}
        }
        tokio::select! {
            () = tokio::time::sleep(pause) => {}
            () = crate::network::wait() => {}
        }
        pause = (pause * 2).clamp(Duration::from_secs(2), Duration::from_secs(60));
    }
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}

async fn greeting<T>(client: &mut async_imap::Client<T>) -> Result<()>
where
    T: AsyncRead + AsyncWrite + Unpin + Send + fmt::Debug,
{
    client
        .read_response()
        .await
        .map_err(async_imap::error::Error::Io)?
        .ok_or(async_imap::error::Error::ConnectionLost)?;
    Ok(())
}

async fn tls<T>(host: &str, stream: T) -> Result<tokio_rustls::client::TlsStream<T>>
where
    T: AsyncRead + AsyncWrite + Unpin,
{
    let config = crate::tls::client_config().map_err(ImapError::Tls)?;
    let name = ServerName::try_from(host.to_owned()).map_err(|e| ImapError::Tls(e.to_string()))?;
    TlsConnector::from(Arc::new(config))
        .connect(name, stream)
        .await
        .map_err(|e| ImapError::Tls(e.to_string()))
}

/// Words that say the login failed because the credentials are wrong, the
/// only `NO` that may end the account for good.
const LOGIN_DENIED: &[&str] = &[
    "authenticationfailed",
    "authentication failed",
    "authentication failure",
    "authentication error",
    "invalid credentials",
    "invalid username or password",
    "invalid user or password",
    "wrong password",
    "bad password",
    "incorrect password",
    "no such user",
    "user not found",
    "unknown user",
];

/// Words that say the server will take the login again later: throttling,
/// maintenance, or plain busyness.
const LOGIN_BUSY: &[&str] = &[
    "throttl",
    "rate limit",
    "too many",
    "try again",
    "try later",
    "temporar",
    "maintenance",
    "unavailable",
    "overload",
    "busy",
];

/// A `NO` to LOGIN is either a final refusal of the credentials or a
/// temporary one: only the first one ends the account, the other keeps the
/// watcher alive to try again.
fn classify_login(e: async_imap::error::Error) -> ImapError {
    let async_imap::error::Error::No(text) = e else {
        return ImapError::Protocol(e);
    };
    let lowered = text.to_ascii_lowercase();
    if LOGIN_DENIED.iter().any(|w| lowered.contains(w)) {
        ImapError::Auth
    } else if LOGIN_BUSY.iter().any(|w| lowered.contains(w)) {
        ImapError::Throttled(text)
    } else {
        ImapError::Protocol(async_imap::error::Error::No(text))
    }
}

/// "1:3,7,9:10" for [1, 2, 3, 7, 9, 10].
fn uid_set(uids: &[u32]) -> String {
    let mut sorted = uids.to_vec();
    sorted.sort_unstable();
    let mut out = String::new();
    let mut i = 0;
    while i < sorted.len() {
        let start = sorted[i];
        let mut end = start;
        while i + 1 < sorted.len() && sorted[i + 1] == end + 1 {
            i += 1;
            end = sorted[i];
        }
        if !out.is_empty() {
            out.push(',');
        }
        if start == end {
            out.push_str(&start.to_string());
        } else {
            out.push_str(&format!("{start}:{end}"));
        }
        i += 1;
    }
    out
}

/// The keyword that carries a snoozed message's time to every device:
/// `$SnoozeUntil-1792310400`.
pub fn snooze_keyword(until: i64) -> String {
    format!("$SnoozeUntil-{until}")
}

/// The snooze time keywords messages of the selected folder carry.
async fn snooze_keywords(session: &mut Session, uids: &[u32]) -> Result<Vec<String>> {
    let fetched: Vec<Fetch> = session
        .uid_fetch(uid_set(uids), "FLAGS")
        .await?
        .try_collect()
        .await?;
    let mut keywords: Vec<String> = fetched
        .iter()
        .flat_map(|f| f.flags())
        .filter_map(|flag| match flag {
            Flag::Custom(k) if k.to_ascii_lowercase().starts_with("$snoozeuntil-") => {
                Some(k.into_owned())
            }
            _ => None,
        })
        .collect();
    keywords.sort();
    keywords.dedup();
    Ok(keywords)
}

/// When a message's keywords say it comes back, if it is snoozed.
fn snooze_until(f: &Fetch) -> Option<i64> {
    f.flags().find_map(|flag| match flag {
        Flag::Custom(k) => k
            .strip_prefix("$SnoozeUntil-")
            .or_else(|| k.strip_prefix("$snoozeuntil-"))
            .and_then(|t| t.parse().ok()),
        _ => None,
    })
}

/// Whether a folder takes keywords it hasn't seen yet: `\*` in its
/// PERMANENTFLAGS. A server that says nothing is taken at its word.
fn keeps_keywords(selected: &async_imap::types::Mailbox) -> bool {
    selected.permanent_flags.is_empty()
        || selected
            .permanent_flags
            .iter()
            .any(|f| matches!(f, Flag::MayCreate))
}

/// The keywords each fetched message carries, for its labels.
fn labels_of(fetches: &[Fetch]) -> Vec<(u32, Vec<String>)> {
    fetches
        .iter()
        .filter_map(|f| {
            let keywords = f
                .flags()
                .filter_map(|flag| match flag {
                    Flag::Custom(k) => Some(k.into_owned()),
                    _ => None,
                })
                .collect();
            Some((f.uid?, keywords))
        })
        .collect()
}

fn flags(f: &Fetch) -> Flags {
    let mut out = Flags::default();
    for flag in f.flags() {
        match flag {
            Flag::Seen => out.seen = true,
            Flag::Flagged => out.flagged = true,
            Flag::Answered => out.answered = true,
            _ => {}
        }
    }
    out
}

/// Turns a FETCH of headers and the start of the body into a list row.
/// Whether the fetched headers say a machine sent it.
fn is_automated(f: &Fetch) -> bool {
    MessageParser::default()
        .parse_headers(f.header().unwrap_or_default())
        .is_some_and(|m| notify::automated(&m))
}

/// A message's summary, with the preview made from its HTML part when
/// that was fetched on its own.
fn summary_with(
    f: &Fetch,
    account: AccountId,
    mailbox: &str,
    html: &HashMap<u32, String>,
) -> Option<MessageSummary> {
    let mut s = summary(f, account, mailbox)?;
    if let Some(p) = html.get(&s.uid) {
        s.preview = p.clone();
    }
    Some(s)
}

fn summary(f: &Fetch, account: AccountId, mailbox: &str) -> Option<MessageSummary> {
    let uid = f.uid?;
    let mut raw = f.header().unwrap_or_default().to_vec();
    raw.extend_from_slice(f.text().unwrap_or_default());
    let raw = close_parts(raw);
    let parsed = MessageParser::default().parse(&raw);
    let (from_name, from_email, to, subject, preview, reply, list) = match &parsed {
        Some(m) => {
            let from = m.from().and_then(|a| a.first());
            let from_email = from
                .and_then(|a| a.address())
                .unwrap_or_default()
                .to_owned();
            let to = m
                .to()
                .map(|list| {
                    list.iter()
                        .filter_map(|a| a.name().or(a.address()))
                        .collect::<Vec<_>>()
                        .join(", ")
                })
                .unwrap_or_default();
            (
                from.and_then(|a| a.name()).unwrap_or_default().to_owned(),
                from_email.clone(),
                to,
                m.subject().unwrap_or_default().to_owned(),
                preview_of(m),
                reply_info(m, &from_email),
                ListInfo {
                    receipt: pec::receipt(m),
                    ..newsletter::list_info(m)
                },
            )
        }
        None => Default::default(),
    };
    Some(MessageSummary {
        account,
        mailbox: mailbox.to_owned(),
        uid,
        from_name,
        from_email,
        to,
        subject,
        preview,
        received_at: f.internal_date().map(|d| d.timestamp()).unwrap_or_default(),
        flags: flags(f),
        reply,
        list,
    })
}

/// The start of a message, cut where the preview fetch stopped, made whole
/// again: the last partial line goes and every part still open is closed,
/// so the parser decodes its text instead of showing it raw.
fn close_parts(mut raw: Vec<u8>) -> Vec<u8> {
    let boundaries = boundaries(&raw);
    if boundaries.is_empty() {
        return raw;
    }
    if let Some(end) = raw.iter().rposition(|&b| b == b'\n') {
        raw.truncate(end + 1);
    }
    for b in boundaries.iter().rev() {
        let closer = format!("\r\n--{b}--\r\n");
        if !contains(&raw, format!("--{b}--").as_bytes()) {
            raw.extend_from_slice(closer.as_bytes());
        }
    }
    raw
}

/// True when `marker` occurs in `raw`. Every marker here begins with
/// `--`, so the scan jumps over any byte that cannot start one and
/// checks the full marker only where two dashes already matched: one
/// pass over the message, instead of a sliding window at every offset.
fn contains(raw: &[u8], marker: &[u8]) -> bool {
    if marker.is_empty() {
        return true;
    }
    if raw.len() < marker.len() {
        return false;
    }
    let last = raw.len() - marker.len();
    let mut at = 0;
    while at <= last {
        if raw[at] != b'-' || raw[at + 1] != b'-' {
            at += 1;
            continue;
        }
        let mut matched = true;
        for (j, &want) in marker.iter().enumerate() {
            if raw[at + j] != want {
                matched = false;
                break;
            }
        }
        if matched {
            return true;
        }
        at += 1;
    }
    false
}

/// Every multipart boundary declared in the message, outermost first.
fn boundaries(raw: &[u8]) -> Vec<String> {
    let text = String::from_utf8_lossy(raw);
    let lower = text.to_ascii_lowercase();
    let mut out = Vec::new();
    let mut from = 0;
    while let Some(at) = lower[from..].find("boundary=") {
        let start = from + at + "boundary=".len();
        let rest = &text[start..];
        let value = match rest.strip_prefix('"') {
            Some(quoted) => quoted.split('"').next().unwrap_or_default(),
            None => rest
                .split(|c: char| c == ';' || c.is_whitespace())
                .next()
                .unwrap_or_default(),
        };
        if !value.is_empty() && !out.iter().any(|b| b == value) {
            out.push(value.to_owned());
        }
        from = start;
    }
    out
}

/// Message-ID, References (or In-Reply-To) and a Reply-To that differs
/// from the sender.
fn reply_info(m: &mail_parser::Message, from_email: &str) -> ReplyInfo {
    let ids = |v: &mail_parser::HeaderValue| -> Vec<String> {
        match v {
            mail_parser::HeaderValue::Text(t) => vec![format!("<{t}>")],
            mail_parser::HeaderValue::TextList(l) => l.iter().map(|t| format!("<{t}>")).collect(),
            _ => Vec::new(),
        }
    };
    let mut references = ids(m.references());
    if references.is_empty() {
        references = ids(m.in_reply_to());
    }
    let reply_to = m
        .reply_to()
        .and_then(|a| a.first())
        .and_then(|a| a.address())
        .filter(|a| !a.eq_ignore_ascii_case(from_email))
        .unwrap_or_default()
        .to_owned();
    ReplyInfo {
        message_id: m
            .message_id()
            .map(|id| format!("<{id}>"))
            .unwrap_or_default(),
        references: references.join(" "),
        reply_to,
        recipients: groups::recipients(m),
    }
}

/// A message's preview: what the reader shows first. Its HTML wins, as
/// in the reader: the text parts senders make from it run its blocks
/// together ("accountIf this") and keep its markup.
fn preview_of(m: &mail_parser::Message) -> String {
    match first_html(m) {
        Some(h) => reader_preview("", Some(h)),
        // Whole, not cut by the parser: its cut ends in "...", which
        // would show as a word.
        None => m
            .body_preview(usize::MAX)
            .map(|p| clean_preview(&p))
            .unwrap_or_default(),
    }
}

/// The message's HTML, when its start reached it.
fn first_html<'a>(m: &'a mail_parser::Message) -> Option<&'a str> {
    m.html_body
        .iter()
        .find_map(|&i| match m.part(i).map(|p| &p.body) {
            Some(mail_parser::PartType::Html(h)) => Some(h.as_ref()),
            _ => None,
        })
}

/// The preview of a body as the reader draws it.
pub(crate) fn reader_preview(text: &str, html: Option<&str>) -> String {
    clean_preview(&crate::reading::plain_text(&crate::reading::readable(
        text, html,
    )))
}

/// One line of plain words: no quoted replies, no runs of spaces, no
/// style sheet and no invisible padding.
pub(crate) fn clean_preview(text: &str) -> String {
    let words = skip_style_sheet(text)
        .lines()
        .filter(|l| !l.trim_start().starts_with('>'))
        .flat_map(str::split_whitespace)
        .map(|w| w.chars().filter(|&c| !invisible(c)).collect::<String>())
        .filter(|w| !w.is_empty() && !rule_line(w) && !bare_link(w));
    let mut out = String::new();
    for w in words {
        if out.chars().count() + w.chars().count() + 1 > PREVIEW_CHARS {
            break;
        }
        if !out.is_empty() {
            out.push(' ');
        }
        out.push_str(&w);
    }
    out
}

/// A line drawn with one sign ("=====", "-----"), as text parts set off
/// their sections: nothing to read.
fn rule_line(word: &str) -> bool {
    let mut chars = word.chars();
    let first = chars.next().unwrap_or(' ');
    word.chars().count() >= 3 && !first.is_alphanumeric() && chars.all(|c| c == first)
}

/// A web address written out: text parts spell their links like this,
/// and a line of one says nothing.
fn bare_link(word: &str) -> bool {
    let w = word
        .trim_start_matches(['(', '<', '['])
        .to_ascii_lowercase();
    w.starts_with("http://") || w.starts_with("https://") || w.starts_with("www.")
}

/// Characters that take no room: marketing mail pads its hidden first
/// line with them, so the preview would wrap onto an empty line.
fn invisible(c: char) -> bool {
    matches!(
        c,
        '\u{00AD}'
            | '\u{034F}'
            | '\u{061C}'
            | '\u{115F}'
            | '\u{1160}'
            | '\u{17B4}'
            | '\u{17B5}'
            | '\u{180E}'
            | '\u{200B}'..='\u{200F}'
            | '\u{202A}'..='\u{202E}'
            | '\u{2060}'..='\u{2064}'
            | '\u{3164}'
            | '\u{FEFF}'
    )
}

/// Text parts some senders make by stripping the tags off their HTML keep
/// its style sheet (WordPress does): CSS rules at the start are skipped.
fn skip_style_sheet(text: &str) -> &str {
    let mut rest = text.trim_start();
    let mut skipped = false;
    loop {
        if let Some(comment) = rest.strip_prefix("/*") {
            match comment.find("*/") {
                Some(end) => rest = comment[end + 2..].trim_start(),
                None => return "",
            }
            continue;
        }
        let Some(open) = rest.find('{') else {
            // A selector cut where the text stopped, like "q:befor".
            let cut = skipped
                && rest.contains(':')
                && !rest.contains(char::is_whitespace)
                && looks_like_selector(rest);
            return if cut { "" } else { rest };
        };
        if !looks_like_selector(&rest[..open]) {
            return rest;
        }
        let mut depth = 0;
        let mut close = None;
        for (i, c) in rest[open..].char_indices() {
            match c {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        close = Some(open + i);
                        break;
                    }
                }
                _ => {}
            }
        }
        // A rule cut where the fetch stopped: no words came yet.
        let Some(close) = close else {
            return "";
        };
        let inside = &rest[open + 1..close];
        let nested = rest.starts_with('@') && inside.contains('{');
        if !nested && !declarations(inside) {
            return rest;
        }
        rest = rest[close + 1..].trim_start();
        skipped = true;
    }
}

/// Whether the inside of a rule reads as `property: value;` pairs.
fn declarations(s: &str) -> bool {
    s.split(';')
        .map(str::trim)
        .filter(|d| !d.is_empty())
        .all(|d| {
            d.split_once(':').is_some_and(|(name, _)| {
                let name = name.trim();
                !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
            })
        })
}

/// Whether text before a `{` reads as CSS selectors (or an @ rule).
fn looks_like_selector(s: &str) -> bool {
    let s = s.trim();
    !s.is_empty()
        && s.len() <= 300
        && s.chars().all(|c| {
            c.is_ascii_alphanumeric()
                || c.is_ascii_whitespace()
                || ".#:,>*-_[]=\"'()@%+~/".contains(c)
        })
}

/// Text and HTML of a whole message. Messages with only HTML get their
/// text from the safe reading of it.
/// Fetches and caches the bodies of `uids` that are at most `max_bytes`;
/// returns the ones cached.
/// The headers and the start of each message, enough to list it: a
/// longer start for those whose first bytes held no words (HTML with a
/// long style sheet, a big first part).
async fn fetch_heads(
    session: &mut Session,
    account: AccountId,
    mailbox: &str,
    uids: &[u32],
) -> Result<(Vec<Fetch>, HashMap<u32, String>)> {
    let query = |bytes: usize| {
        format!(
            "(UID FLAGS INTERNALDATE BODYSTRUCTURE BODY.PEEK[HEADER.FIELDS (FROM REPLY-TO SUBJECT DATE MESSAGE-ID REFERENCES IN-REPLY-TO MIME-VERSION CONTENT-TYPE CONTENT-TRANSFER-ENCODING {} {} {} {} {})] BODY.PEEK[TEXT]<0.{bytes}>)",
            notify::HEADER_FIELDS,
            crate::automation::HEADER_FIELDS,
            newsletter::HEADER_FIELDS,
            pec::HEADER_FIELDS,
            groups::HEADER_FIELDS
        )
    };
    let mut fetches: Vec<Fetch> = session
        .uid_fetch(uid_set(uids), query(PREVIEW_BYTES))
        .await?
        .try_collect()
        .await?;
    let wordless: Vec<u32> = fetches
        .iter()
        .filter(|f| f.text().is_some_and(|t| t.len() >= PREVIEW_BYTES))
        .filter(|f| summary(f, account, mailbox).is_some_and(|s| s.preview.is_empty()))
        .filter_map(|f| f.uid)
        .collect();
    if !wordless.is_empty() {
        let longer: Vec<Fetch> = session
            .uid_fetch(uid_set(&wordless), query(LONG_PREVIEW_BYTES))
            .await?
            .try_collect()
            .await?;
        fetches.retain(|f| f.uid.is_none_or(|u| !wordless.contains(&u)));
        fetches.extend(longer);
    }
    let previews = html_previews(session, &fetches).await?;
    Ok((fetches, previews))
}

/// Previews made from the HTML part of messages whose start held only
/// their text part. Senders make that text from the HTML with every
/// picture's description in it ("Focusrite Logo", "User avatar"), so it
/// isn't what the reader shows first.
async fn html_previews(session: &mut Session, fetches: &[Fetch]) -> Result<HashMap<u32, String>> {
    // One command per section: most messages keep their HTML in the same one.
    let mut wanted: HashMap<String, Vec<(u32, HtmlPart)>> = HashMap::new();
    for f in fetches {
        let (Some(uid), Some(structure)) = (f.uid, f.bodystructure()) else {
            continue;
        };
        let Some(part) = html_part(structure, &mut Vec::new()) else {
            continue;
        };
        let mut raw = f.header().unwrap_or_default().to_vec();
        raw.extend_from_slice(f.text().unwrap_or_default());
        let reached = MessageParser::default()
            .parse(&close_parts(raw))
            .is_some_and(|m| first_html(&m).is_some());
        if !reached {
            wanted
                .entry(part.section.clone())
                .or_default()
                .push((uid, part));
        }
    }
    let mut out = HashMap::new();
    for (section, parts) in wanted {
        let Ok(path) = section
            .split('.')
            .map(str::parse)
            .collect::<std::result::Result<Vec<u32>, _>>()
        else {
            continue;
        };
        let mut ask: Vec<u32> = parts.iter().map(|(u, _)| *u).collect();
        // Longer when the start was all style sheet, as with the text.
        for bytes in [HTML_PREVIEW_BYTES, LONG_PREVIEW_BYTES] {
            if ask.is_empty() {
                break;
            }
            let fetched: Vec<Fetch> = session
                .uid_fetch(
                    uid_set(&ask),
                    format!("(UID BODY.PEEK[{section}]<0.{bytes}>)"),
                )
                .await?
                .try_collect()
                .await?;
            ask.clear();
            for f in &fetched {
                let Some(uid) = f.uid else { continue };
                let Some(data) = f.section(&SectionPath::Part(path.clone(), None)) else {
                    continue;
                };
                let Some((_, part)) = parts.iter().find(|(u, _)| *u == uid) else {
                    continue;
                };
                let cut = data.len() >= bytes;
                let preview = reader_preview("", Some(&part.decode(data, cut)));
                if !preview.is_empty() {
                    out.insert(uid, preview);
                } else if cut {
                    ask.push(uid);
                }
            }
        }
    }
    Ok(out)
}

/// Bytes of the HTML part fetched for the preview line.
const HTML_PREVIEW_BYTES: usize = 8 * 1024;

/// Where a message keeps its HTML, from the server's outline.
#[derive(Debug, Clone, PartialEq)]
struct HtmlPart {
    section: String,
    charset: Option<String>,
    encoding: Option<&'static str>,
}

impl HtmlPart {
    /// The start of the part as text. A cut one ends on a whole line, so
    /// no encoded character is split.
    fn decode(&self, data: &[u8], cut: bool) -> String {
        let data = match data.iter().rposition(|&b| b == b'\n') {
            Some(end) if cut && self.encoding.is_some() => &data[..end + 1],
            _ => data,
        };
        let mut raw = format!(
            "Content-Type: text/html; charset=\"{}\"\r\n",
            self.charset
                .as_deref()
                .unwrap_or("utf-8")
                .replace(['"', '\\', '\r', '\n'], "")
        );
        if let Some(e) = self.encoding {
            raw.push_str(&format!("Content-Transfer-Encoding: {e}\r\n"));
        }
        raw.push_str("\r\n");
        let mut raw = raw.into_bytes();
        raw.extend_from_slice(data);
        MessageParser::default()
            .parse(&raw)
            .and_then(|m| m.body_html(0).map(|h| h.into_owned()))
            .unwrap_or_default()
    }
}

/// The first HTML part that is the message's own text: not attached and
/// not inside a forwarded message.
fn html_part(part: &BodyStructure<'_>, path: &mut Vec<u32>) -> Option<HtmlPart> {
    match part {
        BodyStructure::Multipart { bodies, .. } => {
            for (i, body) in bodies.iter().enumerate() {
                path.push(i as u32 + 1);
                let found = html_part(body, path);
                path.pop();
                if found.is_some() {
                    return found;
                }
            }
            None
        }
        BodyStructure::Text { common, other, .. } => {
            let attached = common
                .disposition
                .as_ref()
                .is_some_and(|d| d.ty.eq_ignore_ascii_case("attachment"));
            if attached || !common.ty.subtype.eq_ignore_ascii_case("html") {
                return None;
            }
            // A message that is HTML alone: its start already held it.
            if path.is_empty() {
                return None;
            }
            Some(HtmlPart {
                section: path
                    .iter()
                    .map(u32::to_string)
                    .collect::<Vec<_>>()
                    .join("."),
                charset: common
                    .ty
                    .params
                    .as_deref()
                    .unwrap_or_default()
                    .iter()
                    .find(|(k, _)| k.eq_ignore_ascii_case("charset"))
                    .map(|(_, v)| v.to_string()),
                encoding: match &other.transfer_encoding {
                    ContentEncoding::Base64 => Some("base64"),
                    ContentEncoding::QuotedPrintable => Some("quoted-printable"),
                    _ => None,
                },
            })
        }
        _ => None,
    }
}

async fn fetch_bodies(
    session: &mut Session,
    store: &Mutex<Store>,
    account: AccountId,
    mailbox: &str,
    uids: &[u32],
    max_bytes: usize,
) -> Result<Vec<u32>> {
    if uids.is_empty() {
        return Ok(Vec::new());
    }
    let sizes: Vec<Fetch> = session
        .uid_fetch(uid_set(uids), "(UID RFC822.SIZE)")
        .await?
        .try_collect()
        .await?;
    let small: Vec<u32> = sizes
        .iter()
        .filter(|f| f.size.is_some_and(|n| n as usize <= max_bytes))
        .filter_map(|f| f.uid)
        .collect();
    if small.is_empty() {
        return Ok(Vec::new());
    }
    let fetches: Vec<Fetch> = session
        .uid_fetch(uid_set(&small), "(UID BODY.PEEK[])")
        .await?
        .try_collect()
        .await?;
    let mut cached = Vec::new();
    for f in &fetches {
        if let (Some(uid), Some(raw)) = (f.uid, f.body()) {
            lock(store).set_full_body(account, mailbox, uid, &parse_body(raw))?;
            cached.push(uid);
        }
    }
    Ok(cached)
}

pub fn parse_body(raw: &[u8]) -> Body {
    let Some(m) = MessageParser::default().parse(raw) else {
        return Body::default();
    };
    // mail-parser offers text as HTML (and HTML as text) when a message
    // lacks one of them: look at what the parts really are.
    let html = m
        .html_body
        .iter()
        .find_map(|&i| match m.part(i).map(|p| &p.body) {
            Some(mail_parser::PartType::Html(h)) => Some(h.to_string()),
            _ => None,
        });
    let text_part = m.text_body.iter().find_map(|&i| {
        m.part(i)
            .filter(|p| matches!(p.body, mail_parser::PartType::Text(_)))
    });
    let text = match (text_part, &html) {
        (Some(part), _) => {
            let kind = part.content_type();
            let parameter = |name, value| {
                kind.and_then(|k| k.attribute(name))
                    .is_some_and(|v| v.eq_ignore_ascii_case(value))
            };
            let mail_parser::PartType::Text(text) = &part.body else {
                unreachable!()
            };
            crate::reading::normalize_text(
                text,
                parameter("format", "flowed"),
                parameter("delsp", "yes"),
            )
        }
        (None, Some(h)) => crate::reading::plain_text(&crate::reading::from_html(h)),
        _ => String::new(),
    };
    let attachments = attachments(&m, html.as_deref());
    let inline = html
        .as_deref()
        .map(|h| inline_images(&m, h))
        .unwrap_or_default();
    Body {
        // Leading spaces can protect literal quote markers in flowed text.
        text: text.trim_matches(['\r', '\n']).to_owned(),
        html,
        attachments,
        calendar: calendar(&m),
        inline,
        auth: crate::sender_auth::trail(&m, raw),
    }
}

/// Largest picture kept from inside a message, and all of them together.
const INLINE_MAX: usize = 2_000_000;
const INLINE_TOTAL: usize = 8_000_000;

/// The pictures `html` shows from inside the message (`cid:`), as long
/// as they are images and not too big.
fn inline_images(m: &mail_parser::Message, html: &str) -> Vec<InlineImage> {
    let mut out = Vec::new();
    let mut total = 0;
    for part in &m.parts {
        let Some(cid) = part.content_id().map(|c| c.trim_matches(['<', '>']).trim()) else {
            continue;
        };
        if cid.is_empty() || !html.contains(&format!("cid:{cid}")) {
            continue;
        }
        let Some(kind) = part.content_type() else {
            continue;
        };
        if !kind.ctype().eq_ignore_ascii_case("image") {
            continue;
        }
        let data = part.contents();
        if data.is_empty() || data.len() > INLINE_MAX || total + data.len() > INLINE_TOTAL {
            continue;
        }
        total += data.len();
        out.push(InlineImage {
            cid: cid.to_owned(),
            mime: format!(
                "image/{}",
                kind.subtype().unwrap_or("png").to_ascii_lowercase()
            ),
            data: data.to_vec(),
        });
    }
    out
}

/// A saved draft, back in the shape it is written in: its recipients,
/// text, thread and files. From, Date and Message-ID are made again when
/// it is saved or sent.
pub fn parse_draft(raw: &[u8]) -> crate::smtp::Draft {
    let Some(m) = MessageParser::default().parse(raw) else {
        return crate::smtp::Draft::default();
    };
    let list = |a: Option<&mail_parser::Address>| -> Vec<String> {
        a.map(|a| {
            a.iter()
                .filter_map(|addr| {
                    let email = addr.address()?;
                    Some(match addr.name().filter(|n| !n.trim().is_empty()) {
                        Some(name) => format!("{name} <{email}>"),
                        None => email.to_owned(),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
    };
    let reply = reply_info(&m, "");
    let body = parse_body(raw);
    let files = body
        .attachments
        .iter()
        .filter_map(|a| {
            Some(crate::smtp::OutgoingFile {
                name: a.name.clone(),
                mime: a.mime.clone(),
                data: m.part(a.part)?.contents().to_vec(),
            })
        })
        .collect();
    crate::smtp::Draft {
        from_email: m
            .from()
            .and_then(|a| a.first())
            .and_then(|a| a.address())
            .unwrap_or_default()
            .to_owned(),
        to: list(m.to()),
        cc: list(m.cc()),
        bcc: list(m.bcc()),
        subject: m.subject().unwrap_or_default().to_owned(),
        body: m.body_text(0).map(|t| t.into_owned()).unwrap_or_default(),
        in_reply_to: match m.in_reply_to() {
            mail_parser::HeaderValue::Text(t) => Some(format!("<{t}>")),
            mail_parser::HeaderValue::TextList(l) => l.last().map(|t| format!("<{t}>")),
            _ => None,
        },
        references: reply
            .references
            .split_whitespace()
            .map(str::to_owned)
            .collect(),
        files,
        marks: m
            .header_raw(crate::rich::HEADER)
            .map(crate::rich::decode)
            .unwrap_or_default(),
        ..Default::default()
    }
}

/// The files attached to a message. Images the HTML shows inline
/// (`cid:`) are part of the message, not attachments.
/// The invite a message carries: its first `text/calendar` part (inline,
/// as calendars send it, or as an .ics file) that holds an event.
fn calendar(m: &mail_parser::Message) -> Option<String> {
    m.parts.iter().find_map(|part| {
        let kind = part.content_type()?;
        let sub = kind.subtype().unwrap_or_default();
        let ics = (kind.ctype().eq_ignore_ascii_case("text")
            && sub.eq_ignore_ascii_case("calendar"))
            || (kind.ctype().eq_ignore_ascii_case("application")
                && sub.eq_ignore_ascii_case("ics"));
        if !ics {
            return None;
        }
        let text = String::from_utf8_lossy(part.contents()).into_owned();
        text.contains("BEGIN:VEVENT").then_some(text)
    })
}

fn attachments(m: &mail_parser::Message, html: Option<&str>) -> Vec<Attachment> {
    m.attachments
        .iter()
        .filter_map(|&id| {
            let part = m.part(id)?;
            let shown = match (part.content_id(), html) {
                (Some(cid), Some(html)) => {
                    html.contains(&format!("cid:{}", cid.trim_matches(['<', '>'])))
                }
                _ => false,
            };
            if shown {
                return None;
            }
            let mime = part
                .content_type()
                .map(|c| match c.subtype() {
                    Some(sub) => format!("{}/{}", c.ctype(), sub),
                    None => c.ctype().to_owned(),
                })
                .unwrap_or_else(|| "application/octet-stream".into())
                .to_ascii_lowercase();
            // Signatures are not files, as in the server's outline.
            if matches!(
                mime.rsplit('/').next(),
                Some("pkcs7-signature" | "x-pkcs7-signature" | "pgp-signature" | "pgp-encrypted")
            ) {
                return None;
            }
            let name = match part.attachment_name() {
                Some(n) if !n.trim().is_empty() => file_name(n),
                _ => match part.message() {
                    Some(inner) => {
                        let subject = file_name(inner.subject().unwrap_or("message"));
                        format!("{subject}.eml")
                    }
                    None => "attachment".into(),
                },
            };
            Some(Attachment {
                part: id,
                name,
                mime,
                size: part.len() as u64,
                ..Default::default()
            })
        })
        .collect()
}

/// The files a message carries, read from the server's outline of it
/// (BODYSTRUCTURE) so they are known before the body is here. Text the
/// message reads as, pictures an HTML part shows (`cid:` parts of a
/// multipart/related) and signatures are not files.
pub fn listed_files(structure: &BodyStructure<'_>) -> Vec<Attachment> {
    let mut files = Vec::new();
    walk_parts(structure, &mut Vec::new(), false, &mut files);
    files
}

fn walk_parts(
    part: &BodyStructure<'_>,
    path: &mut Vec<u32>,
    related: bool,
    files: &mut Vec<Attachment>,
) {
    let (common, other, subject) = match part {
        BodyStructure::Multipart { common, bodies, .. } => {
            let related = common.ty.subtype.eq_ignore_ascii_case("related");
            for (i, body) in bodies.iter().enumerate() {
                path.push(i as u32 + 1);
                walk_parts(body, path, related, files);
                path.pop();
            }
            return;
        }
        BodyStructure::Basic { common, other, .. } | BodyStructure::Text { common, other, .. } => {
            (common, other, None)
        }
        BodyStructure::Message {
            common,
            other,
            envelope,
            ..
        } => (
            common,
            other,
            Some(envelope.subject.as_deref().unwrap_or_default()),
        ),
    };
    let ty = common.ty.ty.to_ascii_lowercase();
    let sub = common.ty.subtype.to_ascii_lowercase();
    let attached = common
        .disposition
        .as_ref()
        .is_some_and(|d| d.ty.eq_ignore_ascii_case("attachment"));
    let name = part_name(common);
    let file = match (ty.as_str(), sub.as_str()) {
        (_, "pkcs7-signature" | "x-pkcs7-signature" | "pgp-signature" | "pgp-encrypted") => false,
        ("text", "plain" | "html") => attached,
        ("text", _) => attached || name.is_some(),
        _ if related && other.id.is_some() && !attached => false,
        _ => true,
    };
    if !file {
        return;
    }
    let name = match (name, subject) {
        (Some(n), _) => n,
        (None, Some(subject)) => {
            let subject = decode_header_text(subject);
            format!(
                "{}.eml",
                file_name(if subject.is_empty() {
                    "message"
                } else {
                    &subject
                })
            )
        }
        (None, None) => "attachment".into(),
    };
    let encoding = match &other.transfer_encoding {
        ContentEncoding::Base64 => Some("base64"),
        ContentEncoding::QuotedPrintable => Some("quoted-printable"),
        _ => None,
    };
    let octets = other.octets as u64;
    files.push(Attachment {
        part: files.len() as u32,
        name,
        mime: format!("{ty}/{sub}"),
        // Base64 carries 57 bytes in each 78-byte line.
        size: if encoding == Some("base64") {
            octets * 57 / 78
        } else {
            octets
        },
        section: Some(if path.is_empty() {
            "1".into()
        } else {
            path.iter()
                .map(u32::to_string)
                .collect::<Vec<_>>()
                .join(".")
        }),
        encoding: encoding.map(str::to_owned),
    });
}

/// A part's file name from its parameters, decoded as the header would
/// be (RFC 2047 words, RFC 2231 continuations and charsets).
fn part_name(common: &BodyContentCommon<'_>) -> Option<String> {
    let mut head = format!("Content-Type: {}/{}", common.ty.ty, common.ty.subtype);
    push_params(&mut head, common.ty.params.as_deref());
    if let Some(d) = &common.disposition {
        head.push_str("\r\nContent-Disposition: ");
        head.push_str(&d.ty);
        push_params(&mut head, d.params.as_deref());
    }
    head.push_str("\r\n\r\n.");
    let m = MessageParser::default().parse(head.as_bytes())?;
    let name = m.part(0)?.attachment_name()?;
    (!name.trim().is_empty()).then(|| file_name(name))
}

fn push_params(head: &mut String, params: Option<&[(Cow<'_, str>, Cow<'_, str>)]>) {
    for (key, value) in params.unwrap_or_default() {
        let value: String = value.chars().filter(|c| !c.is_control()).collect();
        if key.ends_with('*') {
            head.push_str(&format!("; {key}={value}"));
        } else {
            head.push_str(&format!("; {key}=\"{}\"", value.replace(['"', '\\'], "")));
        }
    }
}

/// Header text with its encoded words decoded.
fn decode_header_text(raw: &[u8]) -> String {
    let mut head = b"Subject: ".to_vec();
    head.extend(raw.iter().filter(|b| !b.is_ascii_control()));
    head.extend_from_slice(b"\r\n\r\n.");
    MessageParser::default()
        .parse(&head[..])
        .and_then(|m| m.subject().map(str::to_owned))
        .unwrap_or_default()
}

/// The decoded content of a part fetched alone.
pub fn decode_part(data: &[u8], encoding: Option<&str>) -> Option<Vec<u8>> {
    use mail_parser::decoders::{base64::base64_decode, quoted_printable::quoted_printable_decode};
    match encoding {
        Some("base64") => base64_decode(data),
        Some("quoted-printable") => quoted_printable_decode(data),
        _ => Some(data.to_vec()),
    }
}

/// A name that is safe as a file name: no folders, no control characters.
pub fn file_name(name: &str) -> String {
    let base = name.rsplit(['/', '\\']).next().unwrap_or(name);
    let clean: String = base
        .chars()
        .map(|c| match c {
            c if c.is_control() => '_',
            ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            c => c,
        })
        .collect();
    let clean = clean.trim().trim_start_matches('.').trim();
    if clean.is_empty() {
        "attachment".into()
    } else {
        clean.chars().take(120).collect()
    }
}

/// The decoded content of one attachment part of a whole message.
pub fn attachment_data(raw: &[u8], part: u32) -> Option<Vec<u8>> {
    let m = MessageParser::default().parse(raw)?;
    if !m.attachments.contains(&part) {
        return None;
    }
    Some(m.part(part)?.contents().to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn folder_names_in_modified_utf7() {
        assert_eq!(utf7_encode("Città"), "Citt&AOA-");
        assert_eq!(utf7_encode("Tom & Jerry"), "Tom &- Jerry");
        assert_eq!(utf7_encode("日本語"), "&ZeVnLIqe-");
        for name in [
            "Città",
            "Tom & Jerry",
            "日本語",
            "Quotes 2026",
            "Caffè & tè",
        ] {
            assert_eq!(utf7_decode(&utf7_encode(name)), name);
        }
        assert_eq!(utf7_decode("Broken &AOA"), "Broken &AOA");
    }

    #[test]
    fn finds_the_spam_folder_by_its_marker_or_name() {
        let none: &[NameAttribute<'_>] = &[];
        let junk: &[NameAttribute<'_>] = &[NameAttribute::Junk];
        // The marker wins over a usual name.
        let marked = [("Spam", none), ("[Gmail]/Spam", junk), ("INBOX", none)];
        assert_eq!(
            pick_named(&marked, FolderRole::Junk).as_deref(),
            Some("[Gmail]/Spam")
        );
        for name in ["Junk", "spam", "INBOX.Spam", "Posta indesiderata"] {
            let named = [("INBOX", none), (name, none)];
            assert_eq!(pick_named(&named, FolderRole::Junk).as_deref(), Some(name));
        }
        let plain = [("INBOX", none), ("Clients", none), ("Trash", none)];
        assert_eq!(pick_named(&plain, FolderRole::Junk), None);
    }

    #[test]
    fn the_sync_folder_can_live_under_inbox() {
        assert!(is_space_folder("Piuma Sync"));
        assert!(is_space_folder("INBOX.Piuma Sync"));
        assert!(is_space_folder("INBOX/Piuma Sync"));
        assert!(!is_space_folder("INBOX.Clients.Piuma Sync"));
        assert!(!is_space_folder("Piuma Syncs"));
    }

    #[test]
    fn own_folders_keep_the_tree_and_leave_out_the_rest() {
        let l = |name: &str, d: &str, selectable: bool| Listed {
            name: name.into(),
            delimiter: Some(d.into()),
            selectable,
        };
        let skip: HashSet<String> = ["INBOX.Sent".to_owned()].into();
        let listed = [
            l("INBOX", ".", true),
            l("INBOX.Sent", ".", true),
            l("INBOX.Spam", ".", true),
            l("INBOX.projects", ".", true),
            l("INBOX.Clients.Acme", ".", true),
            l("INBOX.Clients", ".", true),
            l("Old/2019/Q1", "/", true),
        ];
        let got: Vec<_> = own_folders(&listed, &skip)
            .into_iter()
            .map(|f| (f.mailbox, f.name, f.depth, f.selectable))
            .collect();
        let row = |m: &str, n: &str, d: u32, s: bool| (m.to_owned(), n.to_owned(), d, s);
        assert_eq!(
            got,
            [
                row("INBOX.Clients", "Clients", 0, true),
                row("INBOX.Clients.Acme", "Acme", 1, true),
                row("Old", "Old", 0, false),
                row("Old/2019", "2019", 1, false),
                row("Old/2019/Q1", "Q1", 2, true),
                row("INBOX.projects", "projects", 0, true),
            ]
        );
    }

    fn readable_plain(parameters: &str, text: &str) -> crate::reading::Readable {
        let raw = format!("Content-Type: text/plain{parameters}\r\n\r\n{text}");
        let body = parse_body(raw.as_bytes());
        assert!(body.html.is_none());
        crate::reading::readable(&body.text, body.html.as_deref())
    }

    #[test]
    fn plain_text_lists_are_separate_from_the_intro_and_each_other() {
        use crate::reading::BlockKind;
        let r = readable_plain("", concat!(
            "The following plugins were updated automatically to the latest version:\r\n",
            "- CookieYes | GDPR Cookie Consent (from version 3.5.7 to 3.5.8) : https://wordpress.org/plugins/cookie-law-info/\r\n",
            "* Another plugin\r\n• A third plugin\r\n1. Check the site\r\n",
            "\r\nEverything is up to date.\r\n\r\nThanks,\r\nWordPress"
        ));
        assert_eq!(r.blocks.len(), 7);
        assert_eq!(r.blocks[0].kind, BlockKind::Paragraph);
        assert!(r.blocks[0].text().ends_with("version:"));
        for (block, marker) in r.blocks[1..5].iter().zip(["-", "*", "•", "1."]) {
            assert_eq!(block.kind, BlockKind::ListItem);
            assert_eq!(block.marker, marker);
        }
        assert!(r.blocks[1].text().starts_with("CookieYes | GDPR"));
        assert_eq!(
            r.blocks[1].spans.last().unwrap().link.as_deref(),
            Some("https://wordpress.org/plugins/cookie-law-info/")
        );
        assert_eq!(r.blocks[5].text(), "Everything is up to date.");
        assert_eq!(r.blocks[6].text(), "Thanks,\nWordPress");
    }

    #[test]
    fn plain_text_reflows_long_prose_but_preserves_short_and_blank_lines() {
        let first = "This is ordinary hard-wrapped prose which reaches the usual mail width";
        let r = readable_plain(
            "",
            &format!("{first}\r\nand continues here.\r\n\r\nShort line\r\nNext line"),
        );
        assert_eq!(r.blocks.len(), 2);
        assert_eq!(r.blocks[0].text(), format!("{first} and continues here."));
        assert_eq!(r.blocks[1].text(), "Short line\nNext line");
    }

    #[test]
    fn flowed_text_joins_only_soft_breaks_and_keeps_fixed_lists() {
        let r = readable_plain(
            "; format=FLOWED",
            "Intro \r\ncontinued:\r\n- One\r\n- Two\r\n\r\nNew paragraph\r\nFixed break",
        );
        assert_eq!(r.blocks.len(), 4);
        assert_eq!(r.blocks[0].text(), "Intro continued:");
        assert_eq!(r.blocks[1].text(), "One");
        assert_eq!(r.blocks[2].text(), "Two");
        assert_eq!(r.blocks[3].text(), "New paragraph\nFixed break");
    }

    #[test]
    fn flowed_text_handles_delsp_stuffing_quotes_and_signature() {
        let r = readable_plain(
            "; format=flowed; delsp=yes",
            concat!(
                "A long wo \r\nrd\r\n From here\r\n",
                "> quoted \r\n> words\r\n>> deeper \r\n> changed depth\r\n",
                "-- \r\nSignature"
            ),
        );
        assert_eq!(r.blocks[0].text(), "A long word\nFrom here");
        assert_eq!(r.blocks[1].text(), "quotedwords");
        assert_eq!(r.blocks[1].quote, 1);
        assert_eq!(r.blocks[2].text(), "deeper");
        assert_eq!(r.blocks[2].quote, 2);
        assert_eq!(r.blocks[3].text(), "changed depth");
        assert_eq!(r.blocks[4].text(), "--\nSignature");
        let r = readable_plain("; format=flowed", "Before \r\n-- \r\nName");
        assert_eq!(r.blocks[0].text(), "Before\n--\nName");
    }

    #[test]
    fn flowed_stuffed_quote_markers_remain_literal_text() {
        let r = readable_plain("; format=flowed", " >literal\r\n>  >quoted literal");
        assert_eq!(r.blocks.len(), 2);
        assert_eq!(r.blocks[0].quote, 0);
        assert_eq!(r.blocks[0].text(), ">literal");
        assert_eq!(r.blocks[1].quote, 1);
        assert_eq!(r.blocks[1].text(), ">quoted literal");
    }

    #[test]
    fn flowed_parameters_belong_to_the_selected_mime_part() {
        let raw = concat!(
            "Content-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\n",
            "Content-Type: text/plain; format=flowed; delsp=yes\r\n",
            "Content-Transfer-Encoding: quoted-printable\r\n\r\n",
            "A wo=20\r\nrd\r\n\r\nParagraph\r\n--x--\r\n"
        );
        let body = parse_body(raw.as_bytes());
        let r = crate::reading::readable(&body.text, body.html.as_deref());
        assert_eq!(r.blocks[0].text(), "A word");
        assert_eq!(r.blocks[1].text(), "Paragraph");
    }

    #[test]
    fn bodies_keep_html_and_text() {
        let both = b"From: a@b.c\r\nContent-Type: multipart/alternative; boundary=x\r\n\r\n--x\r\nContent-Type: text/plain\r\n\r\nHello plain\r\n--x\r\nContent-Type: text/html\r\n\r\n<p>Hello <b>html</b></p>\r\n--x--\r\n";
        let b = parse_body(both);
        assert_eq!(b.text, "Hello plain");
        assert!(b.html.unwrap().contains("<b>html</b>"));

        let html_only =
            b"From: a@b.c\r\nContent-Type: text/html\r\n\r\n<style>p{}</style><p>One</p><p>Two</p>";
        let b = parse_body(html_only);
        assert_eq!(b.text, "One\n\nTwo");
        assert!(b.html.is_some());

        let text_only = b"From: a@b.c\r\nContent-Type: text/plain\r\n\r\nJust text";
        assert_eq!(
            Body {
                auth: Default::default(),
                ..parse_body(text_only)
            },
            Body {
                text: "Just text".into(),
                ..Body::default()
            }
        );
    }

    #[test]
    fn pictures_inside_the_html_are_kept() {
        let raw = concat!(
            "From: a@b.c\r\n",
            "Content-Type: multipart/related; boundary=\"r\"\r\n\r\n",
            "--r\r\n",
            "Content-Type: text/html\r\n\r\n",
            "<p>Hi <img src=\"cid:logo@studio\"></p>\r\n",
            "--r\r\n",
            "Content-Type: image/png\r\n",
            "Content-ID: <logo@studio>\r\n",
            "Content-Transfer-Encoding: base64\r\n\r\n",
            "cG5n\r\n",
            "--r\r\n",
            "Content-Type: image/png\r\n",
            "Content-ID: <unused@studio>\r\n",
            "Content-Transfer-Encoding: base64\r\n\r\n",
            "cG5n\r\n",
            "--r--\r\n",
        );
        let b = parse_body(raw.as_bytes());
        assert_eq!(
            b.inline,
            [InlineImage {
                cid: "logo@studio".into(),
                mime: "image/png".into(),
                data: b"png".to_vec(),
            }]
        );
        // The one the HTML doesn't show stays an attachment.
        assert_eq!(b.attachments.len(), 1);
    }

    #[test]
    fn an_invite_keeps_its_calendar_part() {
        let raw = concat!(
            "From: g@studio.it\r\nSubject: Invite\r\n",
            "Content-Type: multipart/mixed; boundary=m\r\n\r\n",
            "--m\r\nContent-Type: multipart/alternative; boundary=a\r\n\r\n",
            "--a\r\nContent-Type: text/plain\r\n\r\nSee you Thursday\r\n",
            "--a\r\nContent-Type: text/calendar; charset=UTF-8; method=REQUEST\r\n\r\n",
            "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:x\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            "--a--\r\n",
            "--m\r\nContent-Type: application/ics; name=\"invite.ics\"\r\n",
            "Content-Disposition: attachment; filename=\"invite.ics\"\r\n\r\n",
            "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:x\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
            "--m--\r\n",
        )
        .as_bytes();
        let b = parse_body(raw);
        assert_eq!(b.text, "See you Thursday");
        assert!(b.calendar.unwrap().contains("UID:x"));
        assert!(b.attachments.iter().any(|a| a.name == "invite.ics"));
        assert_eq!(parse_body(b"Subject: x\r\n\r\nHi").calendar, None);
    }

    #[test]
    fn attachments_are_listed_and_fetched() {
        let raw = concat!(
            "From: a@b.c\r\nSubject: Quote\r\n",
            "Content-Type: multipart/mixed; boundary=m\r\n\r\n",
            "--m\r\nContent-Type: multipart/related; boundary=r\r\n\r\n",
            "--r\r\nContent-Type: text/html\r\n\r\n<p>Hi <img src=\"cid:logo@x\"></p>\r\n",
            "--r\r\nContent-Type: image/png\r\nContent-ID: <logo@x>\r\n",
            "Content-Transfer-Encoding: base64\r\n\r\niVBORw==\r\n",
            "--r--\r\n",
            "--m\r\nContent-Type: application/pdf; name=\"q.pdf\"\r\n",
            "Content-Disposition: attachment; filename=\"../../Quote: final.pdf\"\r\n",
            "Content-Transfer-Encoding: base64\r\n\r\nJVBERi0xLjQ=\r\n",
            "--m\r\nContent-Type: message/rfc822\r\n\r\n",
            "From: x@y.z\r\nSubject: Earlier/notes\r\n\r\nOld text\r\n",
            "--m--\r\n",
        )
        .as_bytes();
        let b = parse_body(raw);
        let names: Vec<_> = b.attachments.iter().map(|a| a.name.as_str()).collect();
        assert_eq!(names, ["Quote_ final.pdf", "notes.eml"]);
        let pdf = &b.attachments[0];
        assert_eq!(pdf.mime, "application/pdf");
        assert_eq!(pdf.size, 8);
        assert_eq!(
            attachment_data(raw, pdf.part).as_deref(),
            Some(&b"%PDF-1.4"[..])
        );
        assert_eq!(b.attachments[1].mime, "message/rfc822");
        // Only attachment parts can be read this way.
        assert_eq!(attachment_data(raw, 0), None);
    }

    #[test]
    fn file_names_stay_in_their_folder() {
        assert_eq!(file_name("..\\..\\boot.ini"), "boot.ini");
        assert_eq!(file_name("/etc/passwd"), "passwd");
        assert_eq!(file_name("..."), "attachment");
        assert_eq!(file_name(".hidden"), "hidden");
        assert_eq!(file_name("a\u{0}b?.txt"), "a_b_.txt");
    }

    #[test]
    fn uid_sets_compress_runs() {
        assert_eq!(uid_set(&[10, 9, 7, 3, 2, 1]), "1:3,7,9:10");
        assert_eq!(uid_set(&[5]), "5");
    }

    #[test]
    fn previews_of_cut_parts_are_decoded() {
        let preview = |head: &str, text: &str| {
            let mut raw = head.as_bytes().to_vec();
            raw.extend_from_slice(&text.as_bytes()[..text.len().min(PREVIEW_BYTES)]);
            let raw = close_parts(raw);
            MessageParser::default()
                .parse(&raw)
                .and_then(|m| m.body_preview(PREVIEW_CHARS * 2))
                .map(|p| clean_preview(&p))
                .unwrap_or_default()
        };
        let head = "Subject: a\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"YY\"\r\n\r\n";
        let b64 = "Q2lhbyBNYXR0ZW8sIGVjY28gbGEgZmF0dHVyYS4=\r\n".repeat(80);
        let text = format!(
            "--YY\r\nContent-Type: multipart/alternative; boundary=XX\r\n\r\n--XX\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n{b64}--XX--\r\n--YY--\r\n"
        );
        assert!(preview(head, &text).starts_with("Ciao Matteo, ecco la fattura."));
        let qp = "Ciao Matteo, =C3=A8 tutto ok.\r\n".repeat(100);
        let text = format!(
            "--YY\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n{qp}--YY--\r\n"
        );
        assert!(preview(head, &text).starts_with("Ciao Matteo, è tutto ok."));
        // Whole messages are left as they are.
        let whole = b"Subject: a\r\n\r\nHello".to_vec();
        assert_eq!(close_parts(whole.clone()), whole);
    }

    #[test]
    fn previews_come_from_the_html_as_the_reader_shows_it() {
        let raw = concat!(
            "From: Shop <shop@example.com>\r\n",
            "Subject: Hi\r\n",
            "Content-Type: multipart/alternative; boundary=\"b\"\r\n\r\n",
            "--b\r\nContent-Type: text/plain\r\n\r\n",
            "<!--[if !mso]><!--> [View in Your browser](https://x.example.com/v)\r\n",
            "--b\r\nContent-Type: text/html\r\n\r\n",
            "<html><body><!--[if !mso]><!--><p>Your account</p><p>If this was you, relax.</p>",
            "</body></html>\r\n--b--\r\n",
        );
        let m = MessageParser::default().parse(raw.as_bytes()).unwrap();
        assert_eq!(preview_of(&m), "Your account If this was you, relax.");
    }

    #[test]
    fn cut_html_parts_are_decoded_whole_lines_only() {
        let part = HtmlPart {
            section: "1.2".into(),
            charset: Some("iso-8859-1".into()),
            encoding: Some("quoted-printable"),
        };
        let data = b"<p>Caff=E8 pronto.</p>\r\n<p>Altro=E";
        assert_eq!(part.decode(data, true).trim(), "<p>Caff\u{e8} pronto.</p>");
        assert!(part.decode(b"<p>Fine</p>", false).contains("Fine"));
    }

    #[test]
    fn previews_drop_lines_drawn_with_one_sign() {
        assert_eq!(
            clean_preview("==========\nAmazon Music\n----------\nNew this week ***"),
            "Amazon Music New this week"
        );
        assert_eq!(clean_preview("Wait... 3-2-1 -> go"), "Wait... 3-2-1 -> go");
        assert_eq!(
            clean_preview(
                "Watch it here: https://shotdeck.example/v?id=12&utm=x <www.shotdeck.example> now"
            ),
            "Watch it here: now"
        );
    }

    #[test]
    fn previews_drop_quotes_and_extra_space() {
        let text = "Hi Julia,\n\n  the new   version is attached.\n> old reply\nThanks";
        assert_eq!(
            clean_preview(text),
            "Hi Julia, the new version is attached. Thanks"
        );
        let long = "word ".repeat(100);
        assert!(clean_preview(&long).chars().count() <= PREVIEW_CHARS);
    }

    #[test]
    fn previews_skip_style_sheets() {
        let text = "blockquote:before { content: none !important; }\n\
                    blockquote:after { content: none !important; } q:before, q:after { quotes: none; }\n\
                    @media only screen and (max-width: 600px) { .wrap { width: 100% !important; } }\n\
                    /* footer */ Wordfence activity for your site.";
        assert_eq!(clean_preview(text), "Wordfence activity for your site.");
        // Cut inside a rule: nothing to show yet.
        assert_eq!(clean_preview("p { margin: 0; } td { padding"), "");
        // Braces in words stay.
        assert_eq!(
            clean_preview("Hi {name}, your code is {1234}"),
            "Hi {name}, your code is {1234}"
        );
        assert_eq!(
            clean_preview("Note: the total {see below: 12 EUR}"),
            "Note: the total {see below: 12 EUR}"
        );
    }

    #[test]
    fn previews_drop_invisible_padding() {
        let pad = "\u{034F}\u{200C}\u{00A0}".repeat(150);
        let text = format!("Guarda le scelte degli altri {pad}");
        assert_eq!(clean_preview(&text), "Guarda le scelte degli altri");
        // A long part is not cut with dots that would read as a word.
        let raw = format!(
            "Subject: a\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n7% di sconto {pad} {}",
            "parola ".repeat(80)
        );
        let m = MessageParser::default().parse(raw.as_bytes()).unwrap();
        let preview = clean_preview(&m.body_preview(usize::MAX).unwrap());
        assert!(preview.starts_with("7% di sconto parola"), "{preview}");
        assert!(!preview.contains("..."), "{preview}");
    }

    #[test]
    fn a_throttled_login_is_offline_not_a_rejection() {
        assert!(ImapError::Throttled("busy".into()).is_offline());
        assert!(!ImapError::Auth.is_offline());
        assert_eq!(
            ImapError::Throttled("try again later".into()).to_string(),
            "the server is busy and will not accept the login just now: try again later"
        );
    }

    #[test]
    fn the_login_reply_says_denied_or_busy() {
        let no = |t: &str| async_imap::error::Error::No(t.to_owned());
        // Only wrong credentials end the account for good.
        for t in [
            "AUTHENTICATIONFAILED",
            "Invalid username or password",
            "No such user",
            "wrong password",
            "Authentication failed (temporary error)",
            "Unknown user",
        ] {
            assert!(matches!(classify_login(no(t)), ImapError::Auth), "{t}");
        }
        // A server that will take the login again later.
        for t in [
            "Too many login attempts. Please try again in a few minutes.",
            "Rate limit exceeded, try later",
            "Server is down for maintenance",
            "Service temporarily unavailable",
            "Internal error: overload",
            "System busy",
        ] {
            assert!(
                matches!(classify_login(no(t)), ImapError::Throttled(_)),
                "{t}"
            );
        }
        // Anything else stays a protocol problem, as does any non-NO error.
        assert!(matches!(
            classify_login(no("Bogus reason")),
            ImapError::Protocol(_)
        ));
        assert!(matches!(
            classify_login(async_imap::error::Error::ConnectionLost),
            ImapError::Protocol(_)
        ));
    }

    /// The quadratic pass, as it used to be, to prove the linear one does
    /// the same byte for byte.
    fn close_parts_slow(mut raw: Vec<u8>) -> Vec<u8> {
        let boundaries = boundaries(&raw);
        if boundaries.is_empty() {
            return raw;
        }
        if let Some(end) = raw.iter().rposition(|&b| b == b'\n') {
            raw.truncate(end + 1);
        }
        for b in boundaries.iter().rev() {
            let closer = format!("\r\n--{b}--\r\n");
            let open = format!("--{b}--");
            if !raw.windows(open.len()).any(|w| w == open.as_bytes()) {
                raw.extend_from_slice(closer.as_bytes());
            }
        }
        raw
    }

    #[test]
    fn the_marker_scan_is_byte_identical_to_the_old_window() {
        let raw = b"no dashes here at all";
        assert!(!contains(raw, b"--aa--"));
        assert!(contains(b"x--aa--y", b"--aa--"));
        // Near misses do not count, and the marker must fit whole.
        assert!(!contains(b"x--aa-x", b"--aa--"));
        assert!(!contains(b"--aa-", b"--aa--"));
        assert!(contains(b"--aa--", b"--aa--"));
        assert!(contains(b"anything", b""));
    }

    #[test]
    fn the_boundary_scan_keeps_the_old_output() {
        // Nested parts, cut in the middle of a line: both boundaries are
        // still open.
        let nested = format!(
            concat!(
                "From: Shop <shop@example.com>\r\n",
                "Subject: Hi\r\n",
                "Content-Type: multipart/mixed; boundary=\"aa\"\r\n\r\n",
                "--aa\r\n",
                "Content-Type: multipart/alternative; boundary=bb\r\n\r\n",
                "--bb\r\nContent-Type: text/plain\r\n\r\nPlain text part\r\n",
                "--bb\r\nContent-Type: text/html\r\n\r\n",
                "<html><body><p>first line</p>\r\n",
                "<p>second line with a long run {}",
            ),
            "word ".repeat(2000)
        );
        // One boundary already closed, the other not: only the open one
        // gets a closer, and the one appended earlier is seen by the
        // later check.
        let half_closed = format!(
            concat!(
                "Subject: a\r\n",
                "Content-Type: multipart/mixed; boundary=aa\r\n\r\n",
                "--aa\r\n",
                "Content-Type: multipart/alternative; boundary=bb\r\n\r\n",
                "--bb\r\nContent-Type: text/plain\r\n\r\nHi\r\n--bb--\r\n",
                "--aa\r\nContent-Type: text/html\r\n\r\n",
                "<html><body><p>line</p>\r\n",
                "<p>cut mid {}",
            ),
            "dash ".repeat(2000)
        );
        // Dashes that only look like a boundary: the closer is still due.
        let lookalike = format!(
            concat!(
                "Subject: a\r\n",
                "Content-Type: multipart/mixed; boundary=aa\r\n\r\n",
                "--aa\r\n",
                "Content-Type: multipart/alternative; boundary=bb\r\n\r\n",
                "--bb\r\nContent-Type: text/plain\r\n\r\n",
                "dashes --bb- and --bb-x here {}\r\n",
                "--aa\r\nsecond part, cut",
            ),
            "filler ".repeat(2000)
        );
        for body in [nested, half_closed, lookalike] {
            let raw = body.into_bytes();
            assert_eq!(close_parts_slow(raw.clone()), close_parts(raw));
        }
        // And the nested one does get both closers, inner first.
        let whole = format!(
            concat!(
                "Subject: a\r\nContent-Type: multipart/mixed; boundary=aa\r\n\r\n",
                "--aa\r\nContent-Type: multipart/alternative; boundary=bb\r\n\r\n",
                "--bb\r\nContent-Type: text/plain\r\n\r\nHi\r\n--bb--\r\n",
                "--aa\r\nContent-Type: text/html\r\n\r\n<html><body><p>line</p>\r\n",
                "<p>open {}",
            ),
            "filler ".repeat(2000)
        );
        assert!(close_parts(whole.into_bytes()).ends_with(b"\r\n--aa--\r\n"));
    }
}
