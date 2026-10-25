//! What the Flutter app can ask the engine. Every function here is mirrored
//! in Dart by flutter_rust_bridge (`lib/engine/`).

use std::sync::{Arc, Mutex, OnceLock};

use flutter_rust_bridge::frb;
use piuma_core::autoconfig::{self, Source};
use piuma_core::features;
use piuma_core::files;
use piuma_core::groups::Within;
use piuma_core::imap::{self, FolderRole, ImapError, WatchEvent};
use piuma_core::invite;
use piuma_core::jmap::{self, JmapError};
use piuma_core::newsletter;
use piuma_core::notify;
use piuma_core::original;
use piuma_core::outbox::{self, Outgoing};
use piuma_core::pending::{
    Change, ARCHIVE_READ_NEWSLETTERS, ARCHIVE_UNOPENED_NEWSLETTERS, UNOPENED_ARCHIVED,
};
use piuma_core::remote::{self, Remote, RemoteError};
use piuma_core::rich;
use piuma_core::rules;
use piuma_core::signature::{self, Accent, Signature, Template};
use piuma_core::smtp::{self, Draft, SendError};
use piuma_core::store::WaitingDraft;
use piuma_core::{
    images, reading, Account, AccountId, AccountKind, Body, Folder, ListFilter, MessageSummary,
    PrivacyCounts, Query, Section, Security, Server, Store,
};

use crate::credentials;
use crate::frb_generated::StreamSink;

pub(crate) struct Engine {
    pub(crate) store: Arc<Mutex<Store>>,
    /// A second connection for what the app asks while it draws, so a
    /// sync writing never holds up a frame; none for a database in memory.
    reader: Option<Mutex<Store>>,
    pub(crate) runtime: tokio::runtime::Runtime,
}

static ENGINE: OnceLock<Engine> = OnceLock::new();

pub(crate) fn engine() -> Result<&'static Engine, EngineError> {
    ENGINE
        .get()
        .ok_or_else(|| EngineError::new(ErrorKind::NotOpen, "engine not open"))
}

pub(crate) fn store() -> Result<std::sync::MutexGuard<'static, Store>, EngineError> {
    Ok(engine()?.store.lock().unwrap_or_else(|e| e.into_inner()))
}

/// The database for reading only, for the calls the app makes while it
/// draws a frame: they don't wait for a write to finish.
pub(crate) fn reader() -> Result<std::sync::MutexGuard<'static, Store>, EngineError> {
    let engine = engine()?;
    Ok(engine
        .reader
        .as_ref()
        .unwrap_or(&engine.store)
        .lock()
        .unwrap_or_else(|e| e.into_inner()))
}

/// What went wrong, so the app can word it in the person's language.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    NotOpen,
    WrongPassword,
    Unreachable,
    InsecureConnection,
    Keychain,
    /// A recipient is not an email address; `detail` is the address.
    BadAddress,
    NoRecipients,
    /// The outgoing server refused the message.
    Rejected,
    /// A logo that is not a PNG or JPEG image.
    NotAnImage,
    /// A logo that stays over 40 KB even when shrunk.
    TooBig,
    /// Sync: the recovery phrase doesn't open the space.
    WrongPhrase,
    /// Sync: the code typed on the other device wasn't the one shown.
    WrongCode,
    /// Sync: this device isn't linked, or sync is off.
    NotLinked,
    /// Sync: the mailbox holds no space.
    NoSpace,
    /// Sync: nobody answered a pairing in time, or it was cancelled.
    Expired,
    /// Sync: a linked device said "Not me".
    Refused,
    /// Sync: the mailbox to move the space to holds another one.
    Taken,
    Other,
}

#[derive(Debug, Clone)]
pub struct EngineError {
    pub kind: ErrorKind,
    /// Technical detail for logs and bug reports.
    pub detail: String,
}

impl EngineError {
    pub(crate) fn new(kind: ErrorKind, detail: impl Into<String>) -> Self {
        let detail = detail.into();
        // Every error the app sees lands in the recent log a report can
        // carry (cleaned there).
        piuma_core::feedback::log(
            piuma_core::feedback::Level::Warn,
            "engine",
            &format!("{kind:?}: {detail}"),
        );
        EngineError { kind, detail }
    }
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}: {}", self.kind, self.detail)
    }
}

impl std::error::Error for EngineError {}

impl From<piuma_core::StoreError> for EngineError {
    fn from(e: piuma_core::StoreError) -> Self {
        EngineError::new(ErrorKind::Other, e.to_string())
    }
}

impl From<ImapError> for EngineError {
    fn from(e: ImapError) -> Self {
        let kind = match &e {
            ImapError::Auth => ErrorKind::WrongPassword,
            ImapError::Connect { .. } => ErrorKind::Unreachable,
            ImapError::Tls(_) => ErrorKind::InsecureConnection,
            _ => ErrorKind::Other,
        };
        EngineError::new(kind, e.to_string())
    }
}

impl From<JmapError> for EngineError {
    fn from(e: JmapError) -> Self {
        let kind = match &e {
            JmapError::Auth => ErrorKind::WrongPassword,
            JmapError::Connect { .. } => ErrorKind::Unreachable,
            _ => ErrorKind::Other,
        };
        EngineError::new(kind, e.to_string())
    }
}

impl From<RemoteError> for EngineError {
    fn from(e: RemoteError) -> Self {
        match e {
            RemoteError::Imap(e) => e.into(),
            RemoteError::Jmap(e) => e.into(),
            RemoteError::Store(e) => e.into(),
        }
    }
}

impl From<SendError> for EngineError {
    fn from(e: SendError) -> Self {
        match e {
            SendError::Address(a) => EngineError::new(ErrorKind::BadAddress, a),
            SendError::NoRecipients => EngineError::new(ErrorKind::NoRecipients, e.to_string()),
            SendError::Auth => EngineError::new(ErrorKind::WrongPassword, e.to_string()),
            SendError::Connect { .. } => EngineError::new(ErrorKind::Unreachable, e.to_string()),
            SendError::Rejected(_) => EngineError::new(ErrorKind::Rejected, e.to_string()),
            SendError::Build(_) => EngineError::new(ErrorKind::Other, e.to_string()),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub enum ConnectionSecurity {
    Tls,
    StartTls,
    None,
}

impl From<ConnectionSecurity> for Security {
    fn from(s: ConnectionSecurity) -> Self {
        match s {
            ConnectionSecurity::Tls => Security::Tls,
            ConnectionSecurity::StartTls => Security::StartTls,
            ConnectionSecurity::None => Security::None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct AccountInfo {
    pub id: i64,
    pub name: String,
    pub email: String,
    /// The person's name in From; may be empty.
    pub sender_name: String,
    /// "#RRGGBB".
    pub color: String,
}

impl From<&Account> for AccountInfo {
    fn from(a: &Account) -> Self {
        AccountInfo {
            id: a.id.0,
            name: a.name.clone(),
            email: a.email.clone(),
            sender_name: a.sender_name.clone(),
            color: a.color.clone(),
        }
    }
}

/// One row of the unified inbox.
#[derive(Debug, Clone)]
pub struct InboxRow {
    pub account_id: i64,
    pub mailbox: String,
    pub uid: u32,
    pub from_name: String,
    pub from_email: String,
    pub subject: String,
    pub preview: String,
    /// Seconds since the Unix epoch.
    pub received_at: i64,
    pub seen: bool,
    pub flagged: bool,
    /// Message-ID, for replies; may be empty.
    pub message_id: String,
    /// References, space separated.
    pub references: String,
    /// Reply-To when it differs from the sender; may be empty.
    pub reply_to: String,
    /// Who it went to, names or addresses, comma separated.
    pub to: String,
    /// The conversation it belongs to; empty for a single message.
    pub thread: String,
    /// How many messages that conversation has (1 for a single message).
    pub messages: u32,
    /// The folder it is in, when that folder has a job.
    pub folder: Option<MailFolder>,
    /// How many files are attached, and how many of them are pictures,
    /// as far as this device has listed them; 0 in lists that don't say.
    pub files: u32,
    pub pictures: u32,
    /// It carries an invite, as far as its cached body says.
    pub invite: bool,
    /// Its labels' keywords (`LabelsToApprove`).
    pub labels: Vec<String>,
}

/// A list of every account's messages with the same job.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MailFolder {
    Inbox,
    Sent,
    Archive,
    Drafts,
    Newsletters,
    Snoozed,
}

/// A half of the inbox, as its tabs show it; `All` for the whole list.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InboxTab {
    All,
    People,
    Notifications,
}

impl From<InboxTab> for Section {
    fn from(t: InboxTab) -> Self {
        match t {
            InboxTab::All => Section::All,
            InboxTab::People => Section::People,
            InboxTab::Notifications => Section::Notifications,
        }
    }
}

/// What a list keeps: [tab], and with [unread] only the conversations
/// with something unread.
fn filter(tab: Option<InboxTab>, unread: bool) -> ListFilter {
    ListFilter {
        section: tab.map_or(Section::All, Section::from),
        unread,
    }
}

impl From<MailFolder> for Folder {
    fn from(f: MailFolder) -> Self {
        match f {
            MailFolder::Inbox => Folder::Inbox,
            MailFolder::Sent => Folder::Sent,
            MailFolder::Archive => Folder::Archive,
            MailFolder::Drafts => Folder::Drafts,
            MailFolder::Newsletters => Folder::Newsletters,
            MailFolder::Snoozed => Folder::Snoozed,
        }
    }
}

impl From<Folder> for MailFolder {
    fn from(f: Folder) -> Self {
        match f {
            Folder::Inbox => MailFolder::Inbox,
            Folder::Sent => MailFolder::Sent,
            Folder::Archive => MailFolder::Archive,
            Folder::Drafts => MailFolder::Drafts,
            Folder::Newsletters => MailFolder::Newsletters,
            Folder::Snoozed => MailFolder::Snoozed,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncEventKind {
    /// Downloading: `done` of `total` new messages.
    Progress,
    /// In line with the server; `added` and `removed` say what changed.
    Synced,
    /// The server can't be reached right now; retrying on its own.
    Offline,
    /// The password stopped working; the account needs attention.
    SignInFailed,
    /// Mail waiting in the outbox went out; `added` says how many.
    OutboxSent,
}

#[derive(Debug, Clone)]
pub struct SyncEvent {
    pub kind: SyncEventKind,
    pub account_id: i64,
    pub done: u32,
    pub total: u32,
    pub added: u32,
    pub removed: u32,
    pub reason: String,
    /// With [SyncEventKind::Synced]: what deserves a notification.
    pub notices: Vec<MailNotice>,
}

/// One notification: a sender's newest message, and how many came.
#[derive(Debug, Clone)]
pub struct MailNotice {
    pub account_id: i64,
    pub mailbox: String,
    pub uid: u32,
    pub sender: String,
    pub sender_email: String,
    pub subject: String,
    pub preview: String,
    pub count: u32,
    /// Set for a Vault notice, which the app and the service put in words.
    pub reminder: Option<VaultReminder>,
    /// Written by a person, not a machine.
    pub people: bool,
    /// Shown without a sound (quiet hours); set by [`quiet_notices`].
    pub silent: bool,
    /// Set for "While you were away", once quiet hours that held notices
    /// back are over; the app and the service put it in words.
    pub away: Option<AwayInfo>,
    /// Set for "Remind me if nobody replies": sent mail back at the top
    /// of the inbox. `sender` is who it waits on.
    pub no_reply: Option<NoReplyInfo>,
}

/// Sent mail nobody has replied to, back as its reminder asked.
#[derive(Debug, Clone)]
pub struct NoReplyInfo {
    /// Whole days, by the calendar, since it was sent.
    pub sent_days_ago: u32,
}

/// What came while quiet hours held notices back.
#[derive(Debug, Clone)]
pub struct AwayInfo {
    pub emails: u32,
    /// Of those, written by people.
    pub people: u32,
    /// Who, newest first, at most three.
    pub names: Vec<String>,
}

/// A Vault notice (`Notifications`): a parcel arriving today, or a bill
/// due soon. Its message is the card's newest email.
#[derive(Debug, Clone)]
pub struct VaultReminder {
    /// None for a parcel; days left for a bill (0: due today).
    pub due_in: Option<u32>,
    pub merchant: String,
    /// The item or the bill.
    pub title: String,
    /// "HH:MM" when the email gives one.
    pub time: String,
    /// In cents, with its ISO currency.
    pub amount: Option<i64>,
    pub currency: String,
    /// The card's key, for one notice per card.
    pub key: String,
}

impl From<notify::Notice> for MailNotice {
    fn from(n: notify::Notice) -> Self {
        MailNotice {
            account_id: n.account.0,
            mailbox: n.mailbox,
            uid: n.uid,
            sender: n.sender,
            sender_email: n.sender_email,
            subject: n.subject,
            preview: n.preview,
            count: n.count,
            reminder: None,
            people: n.people,
            silent: false,
            away: None,
            no_reply: None,
        }
    }
}

impl SyncEvent {
    fn new(kind: SyncEventKind, account_id: i64) -> Self {
        SyncEvent {
            kind,
            account_id,
            done: 0,
            total: 0,
            added: 0,
            removed: 0,
            reason: String::new(),
            notices: Vec::new(),
        }
    }
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    // The bridge logs everything on Android, and the HTML parser's debug
    // lines carry the text of the mail: only warnings reach the system log
    // in a release build, so other apps and bug reports never see a message.
    log::set_max_level(if cfg!(debug_assertions) {
        log::LevelFilter::Info
    } else {
        log::LevelFilter::Warn
    });
}

/// Opens (or creates) the local database. Call once at startup.
#[frb(sync)]
pub fn open_engine(db_path: String) -> Result<(), EngineError> {
    if ENGINE.get().is_some() {
        return Ok(());
    }
    piuma_core::tls::use_one_crypto_provider();
    let store = Store::open(&db_path)?;
    // Actions still inside their Undo window when the app quit never
    // happened: show those messages again.
    store.unhide_all()?;
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("piuma-engine")
        .enable_all()
        .build()
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    let reader = (db_path != ":memory:")
        .then(|| Store::open_reader(&db_path).ok())
        .flatten()
        .map(Mutex::new);
    let _ = ENGINE.set(Engine {
        store: Arc::new(Mutex::new(store)),
        reader,
        runtime,
    });
    let models = std::path::Path::new(&db_path)
        .parent()
        .map(|d| d.join("translation"))
        .unwrap_or_else(|| "translation".into());
    let _ = TRANSLATOR.set(piuma_core::translate::Translator::new(models));
    super::feedback::opened(&db_path);
    Ok(())
}

/// Firefox's translation models, kept next to the database.
static TRANSLATOR: OnceLock<piuma_core::translate::Translator> = OnceLock::new();
static TRANSLATE_PROGRESS: Mutex<Option<StreamSink<f64>>> = Mutex::new(None);

fn translator() -> Result<&'static piuma_core::translate::Translator, EngineError> {
    TRANSLATOR
        .get()
        .ok_or_else(|| EngineError::new(ErrorKind::NotOpen, "engine not open"))
}

/// Runs `f` on a thread that may wait on the network.
async fn blocking<T: Send + 'static>(
    f: impl FnOnce() -> T + Send + 'static,
) -> Result<T, EngineError> {
    engine()?
        .runtime
        .spawn_blocking(f)
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))
}

/// Whether `from`→`to` translates on this device with Firefox's models:
/// "installed", "supported" (downloaded first) or "unsupported".
pub async fn translate_status(from: String, to: String) -> Result<String, EngineError> {
    use piuma_core::translate::PairStatus;
    let t = translator()?;
    Ok(match blocking(move || t.status(&from, &to)).await? {
        PairStatus::Ready => "installed",
        PairStatus::Download => "supported",
        PairStatus::Unsupported => "unsupported",
    }
    .to_owned())
}

/// About how many bytes `from`→`to` still downloads.
pub async fn translate_download_size(from: String, to: String) -> Result<Option<u64>, EngineError> {
    let t = translator()?;
    blocking(move || t.download_size(&from, &to)).await
}

/// How far a pair's download is, 0 to 1, while [translate_texts] waits.
pub fn watch_translate_progress(sink: StreamSink<f64>) -> Result<(), EngineError> {
    *TRANSLATE_PROGRESS.lock().unwrap_or_else(|e| e.into_inner()) = Some(sink);
    Ok(())
}

/// A language pair downloaded for translation, as "de-en".
pub struct TranslatePair {
    pub name: String,
    pub bytes: u64,
}

/// The pairs downloaded for translation, for Settings › Appearance.
pub async fn translate_pairs() -> Result<Vec<TranslatePair>, EngineError> {
    let t = translator()?;
    Ok(blocking(move || t.downloaded_pairs())
        .await?
        .into_iter()
        .map(|(name, bytes)| TranslatePair { name, bytes })
        .collect())
}

/// Deletes a downloaded pair ("de-en"); it downloads again when used.
pub async fn remove_translate_pair(name: String) -> Result<(), EngineError> {
    let t = translator()?;
    blocking(move || t.remove(&name))
        .await?
        .map_err(|e| EngineError::new(ErrorKind::Other, e))
}

/// `texts` in `to`, one for one, downloading the pair first if needed.
pub async fn translate_texts(
    texts: Vec<String>,
    from: String,
    to: String,
) -> Result<Vec<String>, EngineError> {
    let t = translator()?;
    blocking(move || {
        t.translate(
            texts,
            &from,
            &to,
            Arc::new(|p| {
                if let Some(sink) = TRANSLATE_PROGRESS
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .as_ref()
                {
                    let _ = sink.add(p);
                }
            }),
        )
    })
    .await?
    .map_err(|e| EngineError::new(ErrorKind::Unreachable, e))
}

#[frb(sync)]
pub fn accounts() -> Result<Vec<AccountInfo>, EngineError> {
    Ok(reader()?
        .accounts()?
        .iter()
        .map(AccountInfo::from)
        .collect())
}

impl From<Security> for ConnectionSecurity {
    fn from(s: Security) -> Self {
        match s {
            Security::Tls => ConnectionSecurity::Tls,
            Security::StartTls => ConnectionSecurity::StartTls,
            Security::None => ConnectionSecurity::None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettingsSource {
    /// A provider the engine knows.
    Known,
    /// Published by the mail domain.
    Published,
    /// Usual host names that answered.
    Guessed,
}

/// Server settings found from an email address.
#[derive(Debug, Clone)]
pub struct FoundSettings {
    pub imap_host: String,
    pub imap_port: u16,
    pub imap_security: ConnectionSecurity,
    pub smtp_host: String,
    pub smtp_port: u16,
    pub smtp_security: ConnectionSecurity,
    pub username: String,
    pub source: SettingsSource,
    /// The JMAP session, when the domain serves JMAP: the account then
    /// uses it in place of IMAP and SMTP.
    pub jmap_url: Option<String>,
}

/// Looks for the server settings of an address. None means the person
/// has to enter them.
pub async fn discover_settings(email: String) -> Result<Option<FoundSettings>, EngineError> {
    let engine = engine()?;
    let (found, jmap_url) = engine
        .runtime
        .spawn(async move {
            // A provider the engine knows is set up the way it knows.
            if let Some(known) = autoconfig::known(&email) {
                return (Some(known), None);
            }
            let (found, jmap_url) =
                tokio::join!(autoconfig::discover(&email), jmap::discover(&email));
            let found = found.or_else(|| {
                let domain = email.rsplit_once('@')?.1.to_owned();
                jmap_url.as_ref().map(|_| autoconfig::Settings {
                    imap: Server {
                        host: format!("imap.{domain}"),
                        port: 993,
                        security: Security::Tls,
                    },
                    smtp: Server {
                        host: format!("smtp.{domain}"),
                        port: 465,
                        security: Security::Tls,
                    },
                    username: email.clone(),
                    source: Source::Published,
                })
            });
            (found, jmap_url)
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    Ok(found.map(|s| FoundSettings {
        jmap_url,
        imap_host: s.imap.host,
        imap_port: s.imap.port,
        imap_security: s.imap.security.into(),
        smtp_host: s.smtp.host,
        smtp_port: s.smtp.port,
        smtp_security: s.smtp.security.into(),
        username: s.username,
        source: match s.source {
            Source::Known => SettingsSource::Known,
            Source::Published => SettingsSource::Published,
            Source::Guessed => SettingsSource::Guessed,
        },
    }))
}

/// An outgoing server. Left out, the engine guesses `smtp.<domain>:465`.
#[derive(Debug, Clone)]
pub struct OutgoingServer {
    pub host: String,
    pub port: u16,
    pub security: ConnectionSecurity,
}

/// Checks the settings against the server, saves the password in the
/// system keychain and adds the account.
#[allow(clippy::too_many_arguments)]
pub async fn add_imap_account(
    name: String,
    email: String,
    sender_name: String,
    color: String,
    host: String,
    port: u16,
    security: ConnectionSecurity,
    username: String,
    password: String,
    smtp: Option<OutgoingServer>,
) -> Result<AccountInfo, EngineError> {
    let domain = email
        .rsplit_once('@')
        .map(|(_, d)| d.to_owned())
        .unwrap_or_else(|| host.clone());
    let account = Account {
        id: AccountId(0),
        name,
        email: email.clone(),
        sender_name: sender_name.trim().to_owned(),
        color,
        kind: AccountKind::Imap {
            imap: Server {
                host,
                port,
                security: security.into(),
            },
            smtp: match smtp {
                Some(s) => Server {
                    host: s.host,
                    port: s.port,
                    security: s.security.into(),
                },
                None => Server {
                    host: format!("smtp.{domain}"),
                    port: 465,
                    security: Security::Tls,
                },
            },
            username,
        },
    };
    add_checked_account(account, password).await
}

/// Checks the login against a JMAP server, saves the password in the
/// system keychain and adds the account.
pub async fn add_jmap_account(
    name: String,
    email: String,
    sender_name: String,
    color: String,
    session_url: String,
    password: String,
    api_token: bool,
) -> Result<AccountInfo, EngineError> {
    // An API token signs in on its own, without the address.
    let username = if api_token {
        String::new()
    } else {
        email.clone()
    };
    let account = Account {
        id: AccountId(0),
        name,
        email,
        sender_name: sender_name.trim().to_owned(),
        color,
        kind: AccountKind::Jmap {
            session_url,
            username,
        },
    };
    add_checked_account(account, password).await
}

/// Checks that an account signs in, then keeps it and its password.
pub(crate) async fn add_checked_account(
    account: Account,
    password: String,
) -> Result<AccountInfo, EngineError> {
    let engine = engine()?;
    let (checked, secret) = (account.clone(), password.clone());
    engine
        .runtime
        .spawn(async move { remote::check_login(&checked, &secret).await })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    let id = store()?.add_account(&account)?;
    if let Err(e) = credentials::save(id, &password) {
        store()?.remove_account(id)?;
        return Err(e);
    }
    let added = store()?.account(id)?.expect("just added");
    Ok(AccountInfo::from(&added))
}

/// Whose mail a list shows: one [address] of a [group], the group, one
/// [account], or everyone's.
fn within(account: Option<i64>, group: Option<i64>, address: Option<String>) -> Within {
    match (group, address) {
        (Some(group), Some(email)) => Within::Address { group, email },
        (Some(g), None) => Within::Group(g),
        _ => account.map(AccountId).into(),
    }
}

/// How many conversations a unified folder lists; [account] keeps one
/// account's, all when None, [group] and [address] one group's or one of
/// its addresses', [tab] one half of the inbox, and [unread] only the
/// conversations with something unread.
pub fn folder_count(
    folder: MailFolder,
    account: Option<i64>,
    group: Option<i64>,
    address: Option<String>,
    tab: Option<InboxTab>,
    unread: bool,
) -> Result<u32, EngineError> {
    Ok(store()?.conversation_count(
        folder.into(),
        within(account, group, address),
        filter(tab, unread),
    )?)
}

pub fn folder_unread(
    folder: MailFolder,
    account: Option<i64>,
    group: Option<i64>,
    address: Option<String>,
    tab: Option<InboxTab>,
) -> Result<u32, EngineError> {
    Ok(store()?.unread_count(
        folder.into(),
        within(account, group, address),
        tab.map_or(Section::All, Section::from),
    )?)
}

/// Rows `offset..offset+limit` of a unified folder, newest first: one per
/// conversation, showing its newest message there. [account] keeps one
/// account's, all when None; [unread] only conversations with something
/// unread.
#[allow(clippy::too_many_arguments)]
pub fn folder_page(
    folder: MailFolder,
    account: Option<i64>,
    group: Option<i64>,
    address: Option<String>,
    tab: Option<InboxTab>,
    unread: bool,
    offset: u32,
    limit: u32,
) -> Result<Vec<InboxRow>, EngineError> {
    let store = store()?;
    Ok(store
        .conversations_page(
            folder.into(),
            within(account, group, address),
            filter(tab, unread),
            offset,
            limit,
        )?
        .into_iter()
        .map(|c| {
            with_files(
                &store,
                InboxRow {
                    thread: c.thread,
                    messages: c.messages,
                    folder: Some(folder),
                    ..inbox_row(&store, c.latest)
                },
            )
        })
        .collect())
}

/// Every message of a conversation, oldest first.
pub fn conversation(account_id: i64, thread: String) -> Result<Vec<InboxRow>, EngineError> {
    let store = store()?;
    let messages = store.conversation(AccountId(account_id), &thread)?;
    let count = messages.len() as u32;
    Ok(messages
        .into_iter()
        .map(|(m, folder)| InboxRow {
            thread: thread.clone(),
            messages: count,
            folder: folder.map(MailFolder::from),
            ..inbox_row(&store, m)
        })
        .collect())
}

/// "In short" over a long conversation, as in `FeatureSummary`: found on
/// this device from the messages already here.
#[derive(Debug, Clone)]
pub struct ThreadBrief {
    pub points: Vec<String>,
    /// What the last message asks of you, in its own words.
    pub your_turn: Option<String>,
    /// Who asks it.
    pub asked_by: String,
    /// The messages' own words, for the device's own model to rewrite
    /// [points] from where it has one.
    pub transcript: String,
}

/// The gist of a conversation; None when it is short or plain. Messages
/// not downloaded yet count with their preview.
pub fn thread_brief(account_id: i64, thread: String) -> Result<Option<ThreadBrief>, EngineError> {
    let store = store()?;
    let messages = store.conversation(AccountId(account_id), &thread)?;
    if messages.len() < piuma_core::brief::LONG {
        return Ok(None);
    }
    let mine: Vec<String> = store
        .accounts()?
        .into_iter()
        .map(|a| a.email.to_lowercase())
        .collect();
    let mut notes = Vec::new();
    let mut lines = Vec::new();
    for (m, _) in &messages {
        let text = match store.full_body(m.account, &m.mailbox, m.uid)? {
            Some(body) => {
                piuma_core::brief::own_words(&reading::readable(&body.text, body.html.as_deref()))
            }
            None => m.preview.clone(),
        };
        let own = mine.contains(&m.from_email.to_lowercase());
        let who = if own {
            "You"
        } else {
            first_name(&m.from_name, &m.from_email)
        };
        lines.push((who.to_owned(), text.clone()));
        notes.push(piuma_core::brief::Note { mine: own, text });
    }
    let Some(brief) = piuma_core::brief::thread(&notes) else {
        return Ok(None);
    };
    let last = &messages[messages.len() - 1].0;
    Ok(Some(ThreadBrief {
        points: brief.points,
        your_turn: brief.your_turn,
        asked_by: first_name(&last.from_name, &last.from_email).to_owned(),
        transcript: piuma_core::brief::transcript(&lines, TRANSCRIPT_CHARS),
    }))
}

/// About 2,500 tokens: room for the instructions and the answer within
/// the 4,000 Gemini Nano and Apple's model take.
const TRANSCRIPT_CHARS: usize = 9000;

fn first_name<'a>(name: &'a str, email: &'a str) -> &'a str {
    if name.is_empty() {
        email.split('@').next().unwrap_or_default()
    } else {
        name.split_whitespace().next().unwrap_or_default()
    }
}

/// "In short" on a sender's card; None for someone who wrote once.
#[derive(Debug, Clone)]
pub struct SenderBriefInfo {
    pub recent: u32,
    pub topic: Option<String>,
    pub waiting: bool,
}

#[frb(sync)]
pub fn sender_brief(email: String) -> Result<Option<SenderBriefInfo>, EngineError> {
    let store = reader()?;
    let mail = store.from_sender(&email, 20)?;
    // Only a person waits for a reply: not a booking, a list, a no-reply.
    let person = match mail.first() {
        Some(m) => store.by_person(m.account, &m.mailbox, m.uid)?,
        None => false,
    };
    // One letter per message: Gmail lists the same one in the inbox and
    // in All Mail, which would count an old thread twice.
    let mut seen = std::collections::HashSet::new();
    let letters: Vec<piuma_core::brief::Letter> = mail
        .into_iter()
        .filter(|m| m.reply.message_id.is_empty() || seen.insert(m.reply.message_id.clone()))
        .map(|m| piuma_core::brief::Letter {
            subject: m.subject,
            received_at: m.received_at,
            answered: m.flags.answered,
        })
        .collect();
    let last = store.last_sent_to(&email)?;
    Ok(
        piuma_core::brief::sender(&letters, last, now_secs()).map(|b| SenderBriefInfo {
            recent: b.recent,
            topic: b.topic,
            waiting: b.waiting && person,
        }),
    )
}

/// How much a sender writes, for a newsletter's card.
#[derive(Debug, Clone)]
pub struct SenderStats {
    /// Emails in the last [SENDER_STATS_DAYS] days.
    pub recent: u32,
    /// Of those, opened.
    pub opened: u32,
    /// Their mail goes to Newsletters.
    pub in_newsletters: bool,
}

/// The days [sender_stats] looks back.
pub const SENDER_STATS_DAYS: u32 = 56;

#[frb(sync)]
pub fn sender_stats(email: String) -> Result<SenderStats, EngineError> {
    let since = now_secs() - SENDER_STATS_DAYS as i64 * 86_400;
    let (recent, opened, in_newsletters) = reader()?.sender_stats(&email, since)?;
    Ok(SenderStats {
        recent,
        opened,
        in_newsletters,
    })
}

/// One message as a list row, with its conversation, e.g. to open it from
/// a notification. None when it is gone.
pub fn message_row(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<Option<InboxRow>, EngineError> {
    let store = store()?;
    let account = AccountId(account_id);
    let Some(m) = store.message(account, &mailbox, uid)? else {
        return Ok(None);
    };
    Ok(Some(in_conversation(&store, inbox_row(&store, m))?))
}

/// [row] with the conversation and the folder it belongs to, so it opens
/// with the rest and with that folder's actions (no Reply in Sent).
pub(crate) fn in_conversation(store: &Store, row: InboxRow) -> Result<InboxRow, EngineError> {
    let account = AccountId(row.account_id);
    let folder = store
        .folder_of(account, &row.mailbox, row.uid)?
        .map(MailFolder::from)
        .or(row.folder);
    let thread = store.thread_of(account, &row.mailbox, row.uid)?;
    let messages = if thread.is_empty() {
        1
    } else {
        store.conversation(account, &thread)?.len().max(1) as u32
    };
    Ok(InboxRow {
        thread,
        messages,
        folder,
        ..row
    })
}

pub(crate) fn inbox_row(store: &Store, m: MessageSummary) -> InboxRow {
    let labels = store
        .message_labels(m.account, &m.mailbox, m.uid)
        .unwrap_or_default();
    InboxRow {
        labels,
        account_id: m.account.0,
        mailbox: m.mailbox,
        uid: m.uid,
        from_name: m.from_name,
        from_email: m.from_email,
        subject: m.subject,
        preview: m.preview,
        received_at: m.received_at,
        seen: m.flags.seen,
        flagged: m.flags.flagged,
        message_id: m.reply.message_id,
        references: m.reply.references,
        reply_to: m.reply.reply_to,
        to: m.to,
        thread: String::new(),
        messages: 1,
        folder: None,
        files: 0,
        pictures: 0,
        invite: false,
    }
}

/// [row] with the files attached to its message, and its invite.
pub(crate) fn with_files(store: &Store, row: InboxRow) -> InboxRow {
    let account = AccountId(row.account_id);
    let (files, pictures) = store
        .file_count(account, &row.mailbox, row.uid)
        .unwrap_or_default();
    let invite = store
        .has_invite(account, &row.mailbox, row.uid)
        .unwrap_or_default();
    InboxRow {
        files,
        pictures,
        invite,
        ..row
    }
}

/// Conversations per period, for the list's section headers. `edges` are
/// descending timestamps; the result has one count per pair of edges.
pub fn folder_counts_between(
    folder: MailFolder,
    account: Option<i64>,
    group: Option<i64>,
    address: Option<String>,
    tab: Option<InboxTab>,
    unread: bool,
    edges: Vec<i64>,
) -> Result<Vec<u32>, EngineError> {
    let store = store()?;
    let within = within(account, group, address);
    let section = filter(tab, unread);
    edges
        .windows(2)
        .map(|w| {
            Ok(store.conversation_count_between(
                folder.into(),
                within.clone(),
                section,
                w[1],
                w[0],
            )?)
        })
        .collect()
}

/// Starts following every account. Events stream back until the app quits.
/// Where sync events go: the app's latest `start_sync` stream.
static SYNC_SINK: Mutex<Option<Arc<StreamSink<SyncEvent>>>> = Mutex::new(None);

/// Accounts with a watcher running, so none is followed twice.
pub(crate) static WATCHED: Mutex<Vec<i64>> = Mutex::new(Vec::new());

/// How to stop each running watcher, when its account changes or goes.
static WATCHERS: Mutex<Vec<(i64, tokio::task::AbortHandle)>> = Mutex::new(Vec::new());

/// Stops following an account, if it was followed.
pub(crate) fn stop_watching(id: AccountId) {
    // Always WATCHED before WATCHERS, as in watch_account.
    let mut watched = WATCHED.lock().unwrap_or_else(|e| e.into_inner());
    let mut watchers = WATCHERS.lock().unwrap_or_else(|e| e.into_inner());
    for (_, handle) in watchers.iter().filter(|(a, _)| *a == id.0) {
        handle.abort();
    }
    watchers.retain(|(a, _)| *a != id.0);
    watched.retain(|a| *a != id.0);
}

fn emit(event: SyncEvent) {
    let sink = SYNC_SINK.lock().unwrap_or_else(|e| e.into_inner()).clone();
    if let Some(sink) = sink {
        let _ = sink.add(event);
    }
}

/// Follows every account not followed yet, and sends what happens to
/// this stream from now on. Safe to call again, after adding an account.
pub fn start_sync(sink: StreamSink<SyncEvent>) -> Result<(), EngineError> {
    *SYNC_SINK.lock().unwrap_or_else(|e| e.into_inner()) = Some(Arc::new(sink));
    for account in store()?.accounts()? {
        watch_account(account)?;
    }
    Ok(())
}

pub(crate) fn watch_account(account: Account) -> Result<(), EngineError> {
    let engine = engine()?;
    let id = account.id;
    {
        let mut watched = WATCHED.lock().unwrap_or_else(|e| e.into_inner());
        if watched.contains(&id.0) {
            return Ok(());
        }
        let password = match credentials::load(id) {
            Ok(p) => p,
            Err(_) => {
                emit(SyncEvent::new(SyncEventKind::SignInFailed, id.0));
                crate::background::sign_in_failed(id);
                return Ok(());
            }
        };
        watched.push(id.0);
        let store = engine.store.clone();
        let settings_store = engine.store.clone();
        let (outbox_account, outbox_password) = (account.clone(), password.clone());
        let task = engine.runtime.spawn(async move {
            let result = remote::watch(&account, &password, store, move |e| {
                // In touch with the server again: what waits can go.
                if let WatchEvent::Synced { .. } = &e {
                    save_waiting_drafts(outbox_account.clone(), outbox_password.clone());
                    send_outbox(outbox_account.clone(), outbox_password.clone());
                    super::away::keep_on_time(outbox_account.clone(), outbox_password.clone());
                }
                emit(match e {
                    WatchEvent::Progress { done, total, .. } => SyncEvent {
                        done: done as u32,
                        total: total as u32,
                        ..SyncEvent::new(SyncEventKind::Progress, id.0)
                    },
                    WatchEvent::Synced { report, .. } => {
                        crate::background::signed_in(id);
                        let notices = notices_for(&report.arrived, &settings_store);
                        // With Android's background service on, it shows
                        // them; the app does not.
                        crate::background::push(&notices);
                        SyncEvent {
                            added: report.added as u32,
                            removed: report.removed as u32,
                            notices,
                            ..SyncEvent::new(SyncEventKind::Synced, id.0)
                        }
                    }
                    WatchEvent::Offline { reason, .. } => SyncEvent {
                        reason,
                        ..SyncEvent::new(SyncEventKind::Offline, id.0)
                    },
                });
            })
            .await;
            WATCHED
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .retain(|a| *a != id.0);
            if result.is_err_and(|e| e.is_auth()) {
                emit(SyncEvent::new(SyncEventKind::SignInFailed, id.0));
                crate::background::sign_in_failed(id);
            }
        });
        let mut watchers = WATCHERS.lock().unwrap_or_else(|e| e.into_inner());
        watchers.retain(|(a, _)| *a != id.0);
        watchers.push((id.0, task.abort_handle()));
    }
    Ok(())
}

/// What new mail deserves a notification, by the person's settings.
pub(crate) fn notices_for(arrived: &[notify::Arrival], store: &Mutex<Store>) -> Vec<MailNotice> {
    if arrived.is_empty() {
        return Vec::new();
    }
    let store = store.lock().unwrap_or_else(|e| e.into_inner());
    let settings = notify::Settings::load(&store).unwrap_or_default();
    // Groups with notices off stay quiet.
    let arrived: Vec<notify::Arrival> = arrived
        .iter()
        .filter(|a| {
            store
                .notifies(a.summary.account, &a.summary.reply.recipients)
                .unwrap_or(true)
        })
        .cloned()
        .collect();
    notify::notices(&arrived, &settings, now_secs())
        .into_iter()
        .filter(|n| !store.is_muted(&n.sender_email).unwrap_or(false))
        .map(Into::into)
        .collect()
}

/// The reminders due now, each given once: sent mail nobody has replied
/// to, back as "Remind me" asked; and the Vault's, a parcel on its
/// delivery day, a bill within three days of its due date, as the
/// switches in Settings › Notifications allow. None before 8:00 or in the
/// night's quiet hours. First, once quiet hours that held notices back are
/// over, "While you were away". `utc_offset_minutes` says where "today"
/// is.
pub fn vault_reminders(utc_offset_minutes: i32) -> Result<Vec<MailNotice>, EngineError> {
    let now = now_secs();
    let week_minute = notify::week_minute_at(now, utc_offset_minutes);
    let store = store()?;
    let settings = notify::Settings::load(&store)?;
    let mut notices = Vec::new();
    if let Some(away) = notify::take_away(&store, &settings, week_minute)? {
        notices.push(MailNotice {
            account_id: 0,
            mailbox: "INBOX".into(),
            uid: 0,
            sender: String::new(),
            sender_email: String::new(),
            subject: String::new(),
            preview: String::new(),
            count: away.emails,
            reminder: None,
            people: false,
            silent: false,
            away: Some(AwayInfo {
                emails: away.emails,
                people: away.people,
                names: away.names,
            }),
            no_reply: None,
        });
    }
    if settings.mode == notify::Mode::Off || !settings.reminders_at(week_minute) {
        return Ok(notices);
    }
    let day = |at: i64| (at + i64::from(utc_offset_minutes) * 60).div_euclid(86_400);
    for (m, _) in store.take_reminded(now)? {
        notices.push(MailNotice {
            account_id: m.account.0,
            mailbox: m.mailbox,
            uid: m.uid,
            sender: waits_on(&m.to),
            sender_email: String::new(),
            subject: m.subject,
            preview: String::new(),
            count: 1,
            reminder: None,
            people: false,
            silent: false,
            away: None,
            no_reply: Some(NoReplyInfo {
                sent_days_ago: (day(now) - day(m.received_at)).max(0) as u32,
            }),
        });
    }
    if !(settings.parcels || settings.due) {
        return Ok(notices);
    }
    let today = piuma_core::vault::Day::local(now, utc_offset_minutes);
    for (m, _, card) in store.vault_cards(None, now - piuma_core::store::VAULT_SPAN)? {
        let Some(remind) = piuma_core::vault::remind(&card, today) else {
            continue;
        };
        let due_in = match remind {
            piuma_core::vault::Remind::Parcel if settings.parcels => None,
            piuma_core::vault::Remind::Due(days) if settings.due => Some(days as u32),
            _ => continue,
        };
        if !store.take_vault_notice(&card.key, remind.tag(), now)? {
            continue;
        }
        notices.push(MailNotice {
            account_id: m.account.0,
            mailbox: m.mailbox,
            uid: m.uid,
            sender: card.merchant.clone(),
            sender_email: String::new(),
            subject: card.title.clone(),
            preview: String::new(),
            count: 1,
            people: false,
            silent: false,
            away: None,
            no_reply: None,
            reminder: Some(VaultReminder {
                due_in,
                merchant: card.merchant,
                title: card.title,
                time: card.time,
                amount: card.amount,
                currency: card.currency,
                key: card.key,
            }),
        });
    }
    Ok(notices)
}

/// Who sent mail waits on, as a notice names them: the first person it
/// went to, by first name ("Luca" for "Luca Bianchi, Sara Conti"), or the
/// address when that is all there is.
fn waits_on(to: &str) -> String {
    let first = to.split(',').next().unwrap_or("").trim();
    if first.contains('@') {
        return first.to_owned();
    }
    first.split_whitespace().next().unwrap_or(first).to_owned()
}

/// True while Android's background service shows the notifications, so
/// the app does not show them twice.
#[frb(sync)]
pub fn native_notices() -> bool {
    crate::background::enabled()
}

/// Android only, where the app keeps passwords in the Android Keystore:
/// hands one over at start, before [`start_sync`]. Elsewhere it does
/// nothing; the engine reads the system keychain itself.
#[frb(sync)]
pub fn remember_password(account_id: i64, password: String) {
    #[cfg(target_os = "android")]
    credentials::remember(AccountId(account_id), &password);
    #[cfg(not(target_os = "android"))]
    let _ = (account_id, password);
}

/// Checks a new password for an account whose sign-in failed, saves it in
/// the system keychain and follows the account again.
pub async fn sign_in_again(account_id: i64, password: String) -> Result<(), EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    let account = store()?
        .account(id)?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "no such account"))?;
    let (checked, secret) = (account.clone(), password.clone());
    engine
        .runtime
        .spawn(async move { remote::check_login(&checked, &secret).await })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    credentials::save(id, &password)?;
    watch_account(account)
}

/// The readable text of a message. Downloads it the first time.
pub async fn message_body(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<String, EngineError> {
    let id = AccountId(account_id);
    if let Some(text) = store()?.body(id, &mailbox, uid)? {
        return Ok(text);
    }
    Ok(full_body(id, mailbox, uid).await?.text)
}

/// Text and HTML, from the cache or the server.
async fn full_body(id: AccountId, mailbox: String, uid: u32) -> Result<Body, EngineError> {
    let engine = engine()?;
    if let Some(body) = store()?.full_body(id, &mailbox, uid)? {
        return Ok(body);
    }
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
    let store = engine.store.clone();
    engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let body = conn.full_body(&store, id, &mailbox, uid).await?;
            conn.close().await;
            Ok::<_, RemoteError>(body)
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
        .map_err(EngineError::from)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlockKind {
    Paragraph,
    Heading,
    ListItem,
    Image,
    Rule,
    Code,
}

/// A run of text with one look.
#[derive(Debug, Clone)]
pub struct TextSpan {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
    pub code: bool,
    /// Already cleaned of tracking parameters. http, https or mailto.
    pub link: Option<String>,
    /// The text shows a different address than where the link goes.
    pub suspicious: bool,
}

#[derive(Debug, Clone)]
pub struct BodyImage {
    /// Remote address, empty when the image is in `data`.
    pub url: String,
    pub data: Option<Vec<u8>>,
    pub alt: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub link: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BodyBlock {
    pub kind: BlockKind,
    /// Heading level (1 large, 2 small) or list depth.
    pub level: u8,
    /// Quote depth, 0 when not quoted.
    pub quote: u8,
    pub marker: String,
    pub spans: Vec<TextSpan>,
    pub image: Option<BodyImage>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrackerKind {
    Pixel,
    Font,
    Style,
}

#[derive(Debug, Clone)]
pub struct StoppedTracker {
    pub kind: TrackerKind,
    pub host: String,
    pub count: u32,
}

/// A message made safe to read: see `piuma_core::reading`.
/// A file attached to a message.
#[derive(Debug, Clone)]
pub struct AttachmentInfo {
    /// Where it is in the message, to fetch it with [save_attachment].
    pub part_id: u32,
    pub name: String,
    pub mime: String,
    pub size: u64,
    /// Why it deserves a word before it opens, from its name.
    pub risk: Option<FileRisk>,
}

/// Why a file deserves a word before it opens (`ProtectionToApprove`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileRisk {
    /// A program or a script.
    Program,
    /// A program named like a document ("invoice.pdf.exe").
    Disguised,
    /// An Office file with macros.
    Macros,
    /// An archive locked with a password.
    Locked,
}

impl From<files::FileRisk> for FileRisk {
    fn from(r: files::FileRisk) -> Self {
        match r {
            files::FileRisk::Program => FileRisk::Program,
            files::FileRisk::Disguised => FileRisk::Disguised,
            files::FileRisk::Macros => FileRisk::Macros,
            files::FileRisk::Locked => FileRisk::Locked,
        }
    }
}

/// Why a file deserves a word before it opens, from its name.
fn file_risk(name: &str) -> Option<FileRisk> {
    files::file_risk(name).map(Into::into)
}

/// Whether a saved file is an archive locked with a password, which no
/// scanner can look into: opening it asks first.
pub async fn locked_archive(path: String) -> bool {
    std::fs::read(&path).is_ok_and(|data| files::locked_archive(&data))
}

#[derive(Debug, Clone)]
pub struct ReadableMessage {
    pub blocks: Vec<BodyBlock>,
    pub attachments: Vec<AttachmentInfo>,
    pub remote_images: u32,
    pub trackers: Vec<StoppedTracker>,
    pub links_cleaned: u32,
    /// The sender is trusted: their images load on their own.
    pub trusted: bool,
    /// Remote images wait for consent (the default).
    pub block_images: bool,
    /// The calendar invite it carries, if any.
    pub invite: Option<InviteInfo>,
    /// Days with a time in its words, offered for a calendar.
    pub dates: Vec<super::calendars::FoundDateInfo>,
    /// It was built as a layout: its original is worth a look.
    pub layout: bool,
    /// The language it is written in ("de"), when sure, for Translate.
    pub language: Option<String>,
}

/// An email as it was sent, made safe for the web view.
#[derive(Debug, Clone)]
pub struct OriginalMessage {
    pub html: String,
    /// Links whose text shows another site: the link, and that text.
    pub suspicious: Vec<SuspiciousLink>,
}

#[derive(Debug, Clone)]
pub struct SuspiciousLink {
    pub link: String,
    pub shown: String,
}

/// How many remote images an original fetches at most.
const ORIGINAL_IMAGES: usize = 60;

/// The message's original layout (`OriginalToApprove`). With
/// `load_images`, its remote images come in too, fetched by the engine.
pub async fn message_original(
    account_id: i64,
    mailbox: String,
    uid: u32,
    load_images: bool,
) -> Result<OriginalMessage, EngineError> {
    let id = AccountId(account_id);
    let body = full_body(id, mailbox.clone(), uid).await?;
    let Some(html) = body.html.filter(|h| !h.trim().is_empty()) else {
        return Err(EngineError::new(ErrorKind::Other, "no HTML to show"));
    };
    let settings = privacy_settings()?;
    let options = reading::Options {
        stop_pixels: settings.stop_pixels,
        clean_links: settings.clean_links,
        warn_links: settings.warn_links,
    };
    let mut loaded = original::Loaded::new();
    if load_images {
        let mut urls = original::remote_images(&html, options);
        urls.dedup();
        urls.truncate(ORIGINAL_IMAGES);
        // All at once, each on its own; one that fails stays a placeholder.
        let runtime = &engine()?.runtime;
        let tasks: Vec<_> = urls
            .into_iter()
            .map(|u| runtime.spawn(async move { (images::fetch(&u).await.ok(), u) }))
            .collect();
        for task in tasks {
            if let Ok((Some(bytes), url)) = task.await {
                loaded.insert(url, bytes);
            }
        }
    }
    let store = store()?;
    let made = original::original(
        &html,
        options,
        &|cid| store.inline_image(id, &mailbox, uid, cid).ok().flatten(),
        &loaded,
    );
    Ok(OriginalMessage {
        html: made.html,
        suspicious: made
            .suspicious
            .into_iter()
            .map(|(link, shown)| SuspiciousLink { link, shown })
            .collect(),
    })
}

const BLOCK_IMAGES: &str = "privacy.block_remote_images";
const STOP_PIXELS: &str = "privacy.stop_pixels";
const CLEAN_LINKS: &str = "privacy.clean_links";
const WARN_LINKS: &str = "privacy.warn_links";
const VERIFIED_SENDER: &str = "privacy.verified_sender";
const SENDER_PICTURES: &str = "privacy.sender_pictures";
const WEBSITE_ICONS: &str = "privacy.website_icons";

/// The switches of Privacy & security. All on unless turned off.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PrivacySettings {
    pub block_images: bool,
    pub stop_pixels: bool,
    pub clean_links: bool,
    pub warn_links: bool,
    /// "Show verified sender": the mark of DKIM, SPF and DMARC.
    pub verified_sender: bool,
    /// "Sender pictures": contact photos and verified company logos.
    pub sender_pictures: bool,
    /// "Website icons": for companies without a logo.
    pub website_icons: bool,
}

pub(crate) fn switch(store: &Store, key: &str) -> Result<bool, EngineError> {
    Ok(store.setting(key)?.as_deref() != Some("false"))
}

pub fn privacy_settings() -> Result<PrivacySettings, EngineError> {
    let store = store()?;
    Ok(PrivacySettings {
        block_images: switch(&store, BLOCK_IMAGES)?,
        stop_pixels: switch(&store, STOP_PIXELS)?,
        clean_links: switch(&store, CLEAN_LINKS)?,
        warn_links: switch(&store, WARN_LINKS)?,
        verified_sender: switch(&store, VERIFIED_SENDER)?,
        sender_pictures: switch(&store, SENDER_PICTURES)?,
        website_icons: switch(&store, WEBSITE_ICONS)?,
    })
}

/// Whether the sender of a message read here is verified: the account's
/// server vouched for its From. False while "Show verified sender" is off.
#[frb(sync)]
pub fn sender_verified(account_id: i64, mailbox: String, uid: u32) -> Result<bool, EngineError> {
    let store = reader()?;
    Ok(switch(&store, VERIFIED_SENDER)?
        && store.sender_verified(AccountId(account_id), &mailbox, uid)?)
}

/// Why a message's sender isn't who they say, for the reader's warning
/// band (`ProtectionToApprove` section 2).
#[derive(Debug, Clone)]
pub struct SenderWarning {
    pub kind: SenderWarningKind,
    /// The domain in From.
    pub domain: String,
    /// The domain it looks like, and how many emails came from that one.
    pub like: Option<String>,
    pub like_count: u32,
    /// The company its name claims.
    pub brand: Option<String>,
    pub dmarc_failed: bool,
    pub signed_by: Option<String>,
    pub sent_by: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SenderWarningKind {
    LooksLike,
    Brand,
    DmarcFailed,
}

/// The warning for a message's sender, or None when nothing is wrong or
/// its body isn't kept yet.
pub fn sender_warning(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<Option<SenderWarning>, EngineError> {
    use piuma_core::store::WarningKind;
    let store = reader()?;
    Ok(store
        .sender_warning(AccountId(account_id), &mailbox, uid)?
        .map(|w| {
            let (kind, like, like_count, brand) = match w.kind {
                WarningKind::LooksLike { like, count } => {
                    (SenderWarningKind::LooksLike, Some(like), count, None)
                }
                WarningKind::Brand { brand } => (SenderWarningKind::Brand, None, 0, Some(brand)),
                WarningKind::DmarcFailed => (SenderWarningKind::DmarcFailed, None, 0, None),
            };
            SenderWarning {
                kind,
                domain: w.domain,
                like,
                like_count,
                brand,
                dmarc_failed: w.dmarc_failed,
                signed_by: w.signed_by,
                sent_by: w.sent_by,
            }
        }))
}

pub fn set_privacy_settings(settings: PrivacySettings) -> Result<(), EngineError> {
    let store = store()?;
    for (key, on) in [
        (BLOCK_IMAGES, settings.block_images),
        (STOP_PIXELS, settings.stop_pixels),
        (CLEAN_LINKS, settings.clean_links),
        (WARN_LINKS, settings.warn_links),
        (VERIFIED_SENDER, settings.verified_sender),
        (SENDER_PICTURES, settings.sender_pictures),
        (WEBSITE_ICONS, settings.website_icons),
    ] {
        store.set_setting(key, if on { "true" } else { "false" })?;
    }
    Ok(())
}

/// The switches of Settings › Features. All on unless turned off.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FeatureSettings {
    pub newsletters: bool,
    pub vault: bool,
    pub attachments: bool,
    /// "In short" above long conversations.
    pub in_short: bool,
    pub translate: bool,
    /// "Add to calendar" for dates found in the text.
    pub found_dates: bool,
}

const FEATURES: [&str; 6] = [
    features::NEWSLETTERS,
    features::VAULT,
    features::ATTACHMENTS,
    features::IN_SHORT,
    features::TRANSLATE,
    features::FOUND_DATES,
];

#[frb(sync)]
pub fn feature_settings() -> Result<FeatureSettings, EngineError> {
    let store = reader()?;
    let [newsletters, vault, attachments, in_short, translate, found_dates] = FEATURES.map(|key| {
        store
            .setting(key)
            .map(|v| v.as_deref() != Some(features::OFF))
    });
    Ok(FeatureSettings {
        newsletters: newsletters?,
        vault: vault?,
        attachments: attachments?,
        in_short: in_short?,
        translate: translate?,
        found_dates: found_dates?,
    })
}

pub fn set_feature_settings(settings: FeatureSettings) -> Result<(), EngineError> {
    let before = feature_settings()?;
    let store = store()?;
    let pairs = [
        (before.newsletters, settings.newsletters),
        (before.vault, settings.vault),
        (before.attachments, settings.attachments),
        (before.in_short, settings.in_short),
        (before.translate, settings.translate),
        (before.found_dates, settings.found_dates),
    ];
    for (key, (was, on)) in FEATURES.into_iter().zip(pairs) {
        if was != on {
            store.set_feature(key, on)?;
        }
    }
    Ok(())
}

/// Settings › Rules & folders: read newsletters more than a week old leave
/// for Archive with the next sync. On unless turned off.
pub fn archive_read_newsletters() -> Result<bool, EngineError> {
    Ok(store()?.setting(ARCHIVE_READ_NEWSLETTERS)?.as_deref() != Some("off"))
}

pub fn set_archive_read_newsletters(on: bool) -> Result<(), EngineError> {
    store()?.set_setting(ARCHIVE_READ_NEWSLETTERS, if on { "on" } else { "off" })?;
    Ok(())
}

/// The nightly built-in rule of Settings › Rules & folders: newsletters
/// left unopened for 30 days leave for Archive. Off unless turned on.
pub struct UnopenedNewsletters {
    pub on: bool,
    /// How many it archived on this device, every account.
    pub archived: u32,
}

pub fn unopened_newsletters() -> Result<UnopenedNewsletters, EngineError> {
    let store = store()?;
    Ok(UnopenedNewsletters {
        on: store.setting(ARCHIVE_UNOPENED_NEWSLETTERS)?.as_deref() == Some("on"),
        archived: store
            .setting(UNOPENED_ARCHIVED)?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0),
    })
}

pub fn set_unopened_newsletters(on: bool) -> Result<(), EngineError> {
    store()?.set_setting(ARCHIVE_UNOPENED_NEWSLETTERS, if on { "on" } else { "off" })?;
    Ok(())
}

/// "Notify me about" in Settings › Notifications.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotifyMode {
    People,
    All,
    Off,
}

/// Settings › Notifications. Times are minutes after local midnight.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NotifySettings {
    pub mode: NotifyMode,
    pub quiet: bool,
    pub quiet_from: u16,
    pub quiet_to: u16,
    /// Quiet all day on Saturday and Sunday.
    pub weekends: bool,
    /// While quiet: no notices (summed up at the end), not just no sound.
    pub hold: bool,
    /// Vault: parcels on their delivery day, bills three days ahead.
    pub parcels: bool,
    pub due: bool,
}

impl From<notify::Settings> for NotifySettings {
    fn from(s: notify::Settings) -> Self {
        NotifySettings {
            mode: match s.mode {
                notify::Mode::People => NotifyMode::People,
                notify::Mode::All => NotifyMode::All,
                notify::Mode::Off => NotifyMode::Off,
            },
            quiet: s.quiet,
            quiet_from: s.quiet_from,
            quiet_to: s.quiet_to,
            weekends: s.weekends,
            hold: s.hold,
            parcels: s.parcels,
            due: s.due,
        }
    }
}

impl NotifySettings {
    fn to_core(self) -> notify::Settings {
        notify::Settings {
            mode: match self.mode {
                NotifyMode::People => notify::Mode::People,
                NotifyMode::All => notify::Mode::All,
                NotifyMode::Off => notify::Mode::Off,
            },
            quiet: self.quiet,
            quiet_from: self.quiet_from,
            quiet_to: self.quiet_to,
            weekends: self.weekends,
            hold: self.hold,
            parcels: self.parcels,
            due: self.due,
        }
    }
}

#[frb(sync)]
pub fn notify_settings() -> Result<NotifySettings, EngineError> {
    Ok(notify::Settings::load(&*reader()?)?.into())
}

#[frb(sync)]
pub fn set_notify_settings(settings: NotifySettings) -> Result<(), EngineError> {
    Ok(settings.to_core().save(&*store()?)?)
}

/// Set once the phone inbox has shown how a row swipes.
const SWIPE_HINT: &str = "hint.swipe_played";

/// Whether the phone's swipe hint is still to play. The first ask says
/// yes and marks it played, so it plays once on this device.
#[frb(sync)]
pub fn take_swipe_hint() -> Result<bool, EngineError> {
    let store = store()?;
    if store.setting(SWIPE_HINT)?.is_some() {
        return Ok(false);
    }
    store.set_setting(SWIPE_HINT, "true")?;
    Ok(true)
}

const THEME: &str = "appearance.theme";
const COMPACT: &str = "appearance.compact";
const PREVIEW_LINES: &str = "appearance.preview_lines";
const TRANSLATE_INTO: &str = "appearance.translate_into";
const LANGUAGE: &str = "appearance.language";

/// Settings › Appearance: light, dark, or as the system is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeChoice {
    Light,
    Dark,
    Automatic,
}

/// Settings › Appearance. Automatic, comfortable rows, two lines of
/// preview until changed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppearanceSettings {
    pub theme: ThemeChoice,
    pub compact: bool,
    pub preview_lines: u8,
    /// Translate's target language ("it"); None follows the app's.
    pub translate_into: Option<String>,
    /// The app's language ("it"); None follows the device's.
    pub language: Option<String>,
}

#[frb(sync)]
pub fn appearance_settings() -> Result<AppearanceSettings, EngineError> {
    let store = reader()?;
    Ok(AppearanceSettings {
        theme: match store.setting(THEME)?.as_deref() {
            Some("light") => ThemeChoice::Light,
            Some("dark") => ThemeChoice::Dark,
            _ => ThemeChoice::Automatic,
        },
        compact: store.setting(COMPACT)?.as_deref() == Some("true"),
        preview_lines: if store.setting(PREVIEW_LINES)?.as_deref() == Some("1") {
            1
        } else {
            2
        },
        translate_into: store.setting(TRANSLATE_INTO)?.filter(|l| !l.is_empty()),
        language: store.setting(LANGUAGE)?.filter(|l| !l.is_empty()),
    })
}

#[frb(sync)]
pub fn set_appearance_settings(settings: AppearanceSettings) -> Result<(), EngineError> {
    let store = store()?;
    let theme = match settings.theme {
        ThemeChoice::Light => "light",
        ThemeChoice::Dark => "dark",
        ThemeChoice::Automatic => "automatic",
    };
    store.set_setting(THEME, theme)?;
    store.set_setting(COMPACT, if settings.compact { "true" } else { "false" })?;
    let lines = if settings.preview_lines == 1 {
        "1"
    } else {
        "2"
    };
    store.set_setting(PREVIEW_LINES, lines)?;
    store.set_setting(
        TRANSLATE_INTO,
        settings.translate_into.as_deref().unwrap_or_default(),
    )?;
    store.set_setting(LANGUAGE, settings.language.as_deref().unwrap_or_default())?;
    Ok(())
}

/// `notices` as quiet hours leave them at `week_minute` (minutes since
/// Monday 00:00, local time): those of covered accounts lose their sound,
/// or, with "No notices", are kept for "While you were away" and left out.
/// Reminders (the Vault's and "Remind me"'s) are never held, only silent.
#[frb(sync)]
pub fn quiet_notices(
    notices: Vec<MailNotice>,
    week_minute: u16,
) -> Result<Vec<MailNotice>, EngineError> {
    let store = reader()?;
    let settings = notify::Settings::load(&store)?;
    let mut out = Vec::new();
    for mut n in notices {
        // Reminders came at their hour already: quiet hours only take
        // their sound.
        if n.reminder.is_some() || n.away.is_some() || n.no_reply.is_some() {
            n.silent = n.away.is_none() && settings.quiet_at(week_minute);
            out.push(n);
            continue;
        }
        let covered = notify::covers(&store, AccountId(n.account_id))?;
        match settings.quiet(week_minute, covered) {
            notify::Quiet::Ring => out.push(n),
            notify::Quiet::Silent => {
                n.silent = true;
                out.push(n);
            }
            notify::Quiet::Hold => notify::hold(
                &store,
                &notify::Notice {
                    account: AccountId(n.account_id),
                    mailbox: n.mailbox,
                    uid: n.uid,
                    sender: n.sender,
                    sender_email: n.sender_email,
                    subject: n.subject,
                    preview: n.preview,
                    count: n.count,
                    people: n.people,
                },
            )?,
        }
    }
    Ok(out)
}

/// Whether `week_minute` (minutes since Monday 00:00, local time) falls
/// in the quiet hours.
#[frb(sync)]
pub fn notify_quiet_at(week_minute: u16) -> Result<bool, EngineError> {
    Ok(notify::Settings::load(&*reader()?)?.quiet_at(week_minute))
}

/// The local week minute now, for [`quiet_notices`].
#[frb(sync)]
pub fn week_minute_now(utc_offset_minutes: i32) -> u16 {
    notify::week_minute_at(now_secs(), utc_offset_minutes)
}

/// Whether quiet hours cover an account; one switched off rings as usual.
#[frb(sync)]
pub fn notify_covers(account_id: i64) -> Result<bool, EngineError> {
    Ok(notify::covers(&*reader()?, AccountId(account_id))?)
}

#[frb(sync)]
pub fn set_notify_covers(account_id: i64, covered: bool) -> Result<(), EngineError> {
    Ok(notify::set_covers(
        &*store()?,
        AccountId(account_id),
        covered,
    )?)
}

/// What was stopped in the messages first read in the last `days` days.
#[derive(Debug, Clone, Copy)]
pub struct PrivacyStats {
    /// Every tracker, pixels included.
    pub trackers: u32,
    pub pixels: u32,
    pub links_cleaned: u32,
    pub suspicious_links: u32,
}

pub fn privacy_stats(days: u32) -> Result<PrivacyStats, EngineError> {
    let t = store()?.privacy_totals(now_secs() - i64::from(days) * 86_400)?;
    Ok(PrivacyStats {
        trackers: t.trackers,
        pixels: t.pixels,
        links_cleaned: t.links,
        suspicious_links: t.suspicious,
    })
}

#[derive(Debug, Clone)]
pub struct TrustedSenderInfo {
    pub email: String,
    /// The name in their latest message; may be empty.
    pub name: String,
    /// When they were trusted, in seconds since the epoch.
    pub since: i64,
}

pub(crate) fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// The message as blocks the app draws. Downloads it the first time.
/// `utc_offset_minutes` is where you are, to read days like "Friday".
pub async fn message_readable(
    account_id: i64,
    mailbox: String,
    uid: u32,
    utc_offset_minutes: i32,
) -> Result<ReadableMessage, EngineError> {
    let id = AccountId(account_id);
    let body = full_body(id, mailbox.clone(), uid).await?;
    let settings = privacy_settings()?;
    let mut r = reading::readable_with(
        &body.text,
        body.html.as_deref(),
        reading::Options {
            stop_pixels: settings.stop_pixels,
            clean_links: settings.clean_links,
            warn_links: settings.warn_links,
        },
    );
    let store = store()?;
    // Pictures inside the message come from its cached parts; one that
    // isn't there is left out.
    r.blocks.retain_mut(|b| {
        let Some(image) = b.image.as_mut() else {
            return true;
        };
        let Some(cid) = image.cid.take() else {
            return true;
        };
        image.data = store.inline_image(id, &mailbox, uid, &cid).ok().flatten();
        image.data.is_some()
    });
    let count = |only: Option<reading::TrackerKind>| -> u32 {
        r.trackers
            .iter()
            .filter(|t| only.is_none_or(|k| t.kind == k))
            .map(|t| t.count)
            .sum()
    };
    store.log_privacy(
        id,
        &mailbox,
        uid,
        now_secs(),
        PrivacyCounts {
            trackers: count(None),
            pixels: count(Some(reading::TrackerKind::Pixel)),
            links: r.links_cleaned,
            suspicious: r.suspicious_links,
        },
    )?;
    let message = store.message(id, &mailbox, uid)?;
    let sender = message
        .as_ref()
        .map(|m| m.from_email.clone())
        .unwrap_or_default();
    let parsed = body.calendar.as_deref().and_then(invite::parse);
    let dates = match &message {
        Some(m) => super::calendars::found_dates(
            &store,
            m,
            &r.blocks,
            parsed.as_ref().filter(|i| !i.all_day).map(|i| {
                i.start
                    + if i.floating {
                        0
                    } else {
                        i64::from(utc_offset_minutes) * 60
                    }
            }),
            utc_offset_minutes,
        )?,
        None => Vec::new(),
    };
    let invite = match parsed {
        Some(i) => Some(invite_info(&store, id, i)?),
        None => None,
    };
    Ok(ReadableMessage {
        language: piuma_core::language::of_readable(&r).map(str::to_owned),
        layout: body.html.as_deref().is_some_and(original::is_layout),
        invite,
        dates,
        trusted: !sender.is_empty() && store.is_trusted(&sender)?,
        block_images: settings.block_images,
        remote_images: r.remote_images,
        links_cleaned: r.links_cleaned,
        trackers: r
            .trackers
            .into_iter()
            .map(|t| StoppedTracker {
                kind: match t.kind {
                    reading::TrackerKind::Pixel => TrackerKind::Pixel,
                    reading::TrackerKind::Font => TrackerKind::Font,
                    reading::TrackerKind::Style => TrackerKind::Style,
                },
                host: t.host,
                count: t.count,
            })
            .collect(),
        blocks: r.blocks.into_iter().map(body_block).collect(),
        attachments: body
            .attachments
            .into_iter()
            .map(|a| AttachmentInfo {
                part_id: a.part,
                risk: file_risk(&a.name),
                name: a.name,
                mime: a.mime,
                size: a.size,
            })
            .collect(),
    })
}

/// Fetches one attachment and saves it in `folder` under a name no other
/// file there has. Returns the saved file's path.
pub async fn save_attachment(
    account_id: i64,
    mailbox: String,
    uid: u32,
    part_id: u32,
    name: String,
    folder: String,
) -> Result<String, EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
    let store = engine.store.clone();
    let data = engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let data = conn.attachment(&store, id, &mailbox, uid, part_id).await?;
            conn.close().await;
            Ok::<_, RemoteError>(data)
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    let path = files::save_new(std::path::Path::new(&folder), &name, &data)
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    Ok(path.to_string_lossy().into_owned())
}

fn body_block(b: reading::Block) -> BodyBlock {
    BodyBlock {
        kind: match b.kind {
            reading::BlockKind::Paragraph => BlockKind::Paragraph,
            reading::BlockKind::Heading => BlockKind::Heading,
            reading::BlockKind::ListItem => BlockKind::ListItem,
            reading::BlockKind::Image => BlockKind::Image,
            reading::BlockKind::Rule => BlockKind::Rule,
            reading::BlockKind::Code => BlockKind::Code,
        },
        level: b.level,
        quote: b.quote,
        marker: b.marker,
        spans: b
            .spans
            .into_iter()
            .map(|s| TextSpan {
                text: s.text,
                bold: s.bold,
                italic: s.italic,
                code: s.code,
                link: s.link,
                suspicious: s.suspicious,
            })
            .collect(),
        image: b.image.map(|i| BodyImage {
            url: i.url,
            data: i.data,
            alt: i.alt,
            width: i.width,
            height: i.height,
            link: i.link,
        }),
    }
}

/// A remote image, once the person allowed it.
pub async fn fetch_image(url: String) -> Result<Vec<u8>, EngineError> {
    engine()?
        .runtime
        .spawn(async move { images::fetch(&url).await })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
        .map_err(|e| EngineError::new(ErrorKind::Unreachable, e.to_string()))
}

/// Domains being looked up now, so a list of rows asks once.
static PICTURES_LOOKING: Mutex<Vec<String>> = Mutex::new(Vec::new());

/// A few lookups at a time, so a full inbox doesn't flood the network.
static PICTURES_AT_ONCE: tokio::sync::Semaphore = tokio::sync::Semaphore::const_new(3);

/// The picture of a company sender (`PicturesToApprove`): its verified
/// logo, or its website's icon, as a square PNG; none for people at mail
/// providers, while "Sender pictures" is off, or when there is nothing.
/// Looked up once per domain and kept on the device.
pub async fn sender_picture(email: String) -> Result<Option<Vec<u8>>, EngineError> {
    use piuma_core::pictures::{self, Kind};
    let Some(domain) = pictures::domain_for(&email) else {
        return Ok(None);
    };
    let (icons, verified) = {
        let store = store()?;
        if !switch(&store, SENDER_PICTURES)? {
            return Ok(None);
        }
        let icons = switch(&store, WEBSITE_ICONS)?;
        let shown = |p: pictures::Picture| match p.kind {
            Kind::Logo => Some(p.png),
            Kind::Icon if icons => Some(p.png),
            _ => None,
        };
        let kept = store.sender_picture(&domain)?;
        let now = now_secs();
        let fresh = kept.as_ref().is_some_and(|(p, at)| {
            let keep = if p.kind == Kind::None {
                pictures::RETRY_SECS
            } else {
                pictures::KEEP_SECS
            };
            now - at < keep
        });
        if fresh {
            return Ok(kept.and_then(|(p, _)| shown(p)));
        }
        {
            let mut looking = PICTURES_LOOKING.lock().unwrap_or_else(|e| e.into_inner());
            if looking.contains(&domain) {
                return Ok(kept.and_then(|(p, _)| shown(p)));
            }
            looking.push(domain.clone());
        }
        (icons, store.domain_verified(&domain)?)
    };
    let looked = {
        let domain = domain.clone();
        engine()?
            .runtime
            .spawn(async move {
                let _turn = PICTURES_AT_ONCE.acquire().await;
                pictures::look_up(&domain, verified, icons).await
            })
            .await
    };
    PICTURES_LOOKING
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .retain(|d| d != &domain);
    let picture = looked.map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    store()?.set_sender_picture(&domain, &picture, now_secs())?;
    Ok(match picture.kind {
        Kind::None => None,
        _ => Some(picture.png),
    })
}

/// Always load a sender's images, or stop.
pub fn set_sender_trusted(email: String, trusted: bool) -> Result<(), EngineError> {
    Ok(store()?.set_trusted(&email, trusted, now_secs())?)
}

/// Whether a sender's new mail makes no notification.
#[frb(sync)]
pub fn sender_muted(email: String) -> Result<bool, EngineError> {
    Ok(reader()?.is_muted(&email)?)
}

/// Mute a sender's notifications, or let them come again.
pub fn set_sender_muted(email: String, muted: bool) -> Result<(), EngineError> {
    Ok(store()?.set_muted(&email, muted)?)
}

/// Whether a sender's new mail goes straight to Trash.
#[frb(sync)]
pub fn sender_blocked(email: String) -> Result<bool, EngineError> {
    Ok(reader()?.is_blocked(&email)?)
}

/// Block a sender (their new mail goes to Trash, with no notice), or
/// let their mail in again.
pub fn set_sender_blocked(email: String, blocked: bool) -> Result<(), EngineError> {
    Ok(store()?.set_blocked(&email, blocked)?)
}

pub fn trusted_senders() -> Result<Vec<TrustedSenderInfo>, EngineError> {
    Ok(store()?
        .trusted_senders()?
        .into_iter()
        .map(|t| TrustedSenderInfo {
            email: t.email,
            name: t.name,
            since: t.since,
        })
        .collect())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SignatureTemplate {
    Minimal,
    Classic,
    Monogram,
    Logo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SignatureAccent {
    Blue,
    Black,
    Terracotta,
}

/// A signature, as the Signatures screen edits it.
#[derive(Debug, Clone)]
pub struct SignatureInfo {
    /// 0 for a new one.
    pub id: i64,
    pub account_id: i64,
    pub label: String,
    pub template: SignatureTemplate,
    pub name: String,
    pub role: String,
    pub company: String,
    pub phone: String,
    pub website: String,
    pub accent: SignatureAccent,
    /// PNG or JPEG, already shrunk with `shrink_signature_logo`.
    pub logo: Option<Vec<u8>>,
    pub for_new: bool,
    pub for_replies: bool,
}

impl From<Signature> for SignatureInfo {
    fn from(s: Signature) -> Self {
        SignatureInfo {
            id: s.id,
            account_id: s.account.0,
            label: s.label,
            template: match s.template {
                Template::Minimal => SignatureTemplate::Minimal,
                Template::Classic => SignatureTemplate::Classic,
                Template::Monogram => SignatureTemplate::Monogram,
                Template::Logo => SignatureTemplate::Logo,
            },
            name: s.name,
            role: s.role,
            company: s.company,
            phone: s.phone,
            website: s.website,
            accent: match s.accent {
                Accent::Blue => SignatureAccent::Blue,
                Accent::Black => SignatureAccent::Black,
                Accent::Terracotta => SignatureAccent::Terracotta,
            },
            logo: s.logo.map(|l| l.data),
            for_new: s.for_new,
            for_replies: s.for_replies,
        }
    }
}

impl SignatureInfo {
    fn to_core(&self) -> Signature {
        Signature {
            id: self.id,
            account: AccountId(self.account_id),
            label: self.label.clone(),
            template: match self.template {
                SignatureTemplate::Minimal => Template::Minimal,
                SignatureTemplate::Classic => Template::Classic,
                SignatureTemplate::Monogram => Template::Monogram,
                SignatureTemplate::Logo => Template::Logo,
            },
            name: self.name.clone(),
            role: self.role.clone(),
            company: self.company.clone(),
            phone: self.phone.clone(),
            website: self.website.clone(),
            accent: match self.accent {
                SignatureAccent::Blue => Accent::Blue,
                SignatureAccent::Black => Accent::Black,
                SignatureAccent::Terracotta => Accent::Terracotta,
            },
            logo: self
                .logo
                .as_deref()
                .and_then(|data| signature::shrink_logo(data).ok()),
            for_new: self.for_new,
            for_replies: self.for_replies,
        }
    }
}

/// Every signature, by account, oldest first.
#[frb(sync)]
pub fn signatures() -> Result<Vec<SignatureInfo>, EngineError> {
    Ok(reader()?
        .signatures()?
        .into_iter()
        .map(Into::into)
        .collect())
}

/// Stores a signature (new when its id is 0) and returns its id.
#[frb(sync)]
pub fn save_signature(signature: SignatureInfo) -> Result<i64, EngineError> {
    Ok(store()?.save_signature(&signature.to_core())?)
}

#[frb(sync)]
pub fn delete_signature(id: i64) -> Result<(), EngineError> {
    Ok(store()?.delete_signature(id)?)
}

/// A logo picked from disk, made small enough for every email.
#[frb(sync)]
pub fn shrink_signature_logo(data: Vec<u8>) -> Result<Vec<u8>, EngineError> {
    signature::shrink_logo(&data)
        .map(|l| l.data)
        .map_err(|e| match e {
            signature::LogoError::NotAnImage => {
                EngineError::new(ErrorKind::NotAnImage, e.to_string())
            }
            signature::LogoError::TooBig => EngineError::new(ErrorKind::TooBig, e.to_string()),
        })
}

/// The lines a signature shows, name first, as the email will have them.
#[frb(sync)]
pub fn signature_lines(signature: SignatureInfo) -> Vec<String> {
    signature.to_core().lines()
}

/// The plain-text version of a signature, "-- " line included.
#[frb(sync)]
pub fn signature_text(signature: SignatureInfo) -> String {
    signature.to_core().text()
}

/// A message ready to go.
#[derive(Debug, Clone)]
pub struct OutgoingMessage {
    pub account_id: i64,
    /// One of the account's aliases to send from; None (or an address that
    /// isn't the account's) sends from the account's own.
    pub from_email: Option<String>,
    pub files: Vec<OutgoingFile>,
    pub to: Vec<String>,
    pub cc: Vec<String>,
    pub bcc: Vec<String>,
    pub subject: String,
    pub body: String,
    /// Message-ID being answered, for replies.
    pub in_reply_to: Option<String>,
    pub references: Vec<String>,
    /// The signature to add, if any.
    pub signature_id: Option<i64>,
    /// [signature_id] was picked by hand (None: "No signature"), so a saved
    /// draft keeps it rather than going back to the account's own.
    pub signature_picked: bool,
    /// Its saved copy in Drafts, deleted once it is sent or saved again.
    pub draft: Option<MessageRef>,
    /// "Remind me if nobody replies": once sent, it comes back to the top
    /// of the inbox at this time (Unix seconds) if nobody has replied.
    pub remind_at: Option<i64>,
    /// Bold, italic and links over [body].
    pub marks: Vec<BodyMark>,
}

/// Bold, italic or a link over the characters `start..end` of a body
/// (counted in characters, as `String.runes` counts them).
#[derive(Debug, Clone)]
pub struct BodyMark {
    pub kind: BodyMarkKind,
    pub start: u32,
    pub end: u32,
    /// A link's address; empty for the others.
    pub url: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BodyMarkKind {
    Bold,
    Italic,
    Link,
}

fn core_marks(marks: Vec<BodyMark>) -> Vec<rich::Mark> {
    marks
        .into_iter()
        .map(|m| rich::Mark {
            kind: match m.kind {
                BodyMarkKind::Bold => rich::MarkKind::Bold,
                BodyMarkKind::Italic => rich::MarkKind::Italic,
                BodyMarkKind::Link => rich::MarkKind::Link(m.url),
            },
            start: m.start as usize,
            end: m.end as usize,
        })
        .collect()
}

fn body_marks(marks: Vec<rich::Mark>) -> Vec<BodyMark> {
    marks
        .into_iter()
        .map(|m| {
            let (kind, url) = match m.kind {
                rich::MarkKind::Bold => (BodyMarkKind::Bold, String::new()),
                rich::MarkKind::Italic => (BodyMarkKind::Italic, String::new()),
                rich::MarkKind::Link(url) => (BodyMarkKind::Link, url),
            };
            BodyMark {
                kind,
                start: m.start as u32,
                end: m.end as u32,
                url,
            }
        })
        .collect()
}

/// Where the signature picked for a saved draft is kept, on this device.
fn draft_signature_key(draft: &MessageRef) -> String {
    format!(
        "draft.signature.{}.{}.{}",
        draft.account_id, draft.mailbox, draft.uid
    )
}

#[derive(Debug, Clone)]
pub struct OutgoingFile {
    pub name: String,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct SentMessage {
    pub message_id: String,
    /// False when the copy could not be filed in Sent.
    pub filed: bool,
    /// The server could not be reached: it waits in the outbox and goes
    /// once the connection is back.
    pub queued: bool,
}

/// Sends a message from one of the accounts and files a copy in Sent.
/// When the server can't be reached, it waits in the outbox instead.
pub async fn send_message(message: OutgoingMessage) -> Result<SentMessage, EngineError> {
    let id = AccountId(message.account_id);
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
    let saved = message.draft.clone();
    let remind_at = message.remind_at;
    let draft = core_draft(&account, message)?;
    let sent = send_draft(account, password, draft, saved).await?;
    remind_sent(id, &sent.message_id, remind_at)?;
    Ok(sent)
}

/// Keeps the reminder picked in compose, by the Message-ID the mail goes
/// with.
fn remind_sent(account: AccountId, message_id: &str, at: Option<i64>) -> Result<(), EngineError> {
    if let Some(at) = at.filter(|_| !message_id.is_empty()) {
        store()?.set_reply_reminder(account, message_id, Some(at))?;
    }
    Ok(())
}

/// Sends a draft of `account`, or keeps it in the outbox when the server
/// can't be reached; its saved copy in Drafts goes once it is sent.
async fn send_draft(
    account: Account,
    password: String,
    draft: Draft,
    saved: Option<MessageRef>,
) -> Result<SentMessage, EngineError> {
    let engine = engine()?;
    let id = account.id;
    let ready = smtp::ready(&draft)?;
    let shared = engine.store.clone();
    let (to_send, sending) = (ready.clone(), account.clone());
    let sent = engine
        .runtime
        .spawn(async move {
            let report = remote::send_ready(&sending, &password, &to_send).await?;
            // Show it in Sent right away. A failure here changes nothing
            // about the send: the next look at Sent picks it up.
            if let Ok(mut conn) = Remote::open(&sending, &password).await {
                conn.sync_folders(&shared, id).await.ok();
                conn.close().await;
            }
            Ok::<_, SendError>(report)
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    let report = match sent {
        Err(e) if e.is_offline() => {
            let out = Outgoing {
                account: id,
                draft,
                saved: settle_waiting(saved)?.map(|d| (d.mailbox, d.uid)),
                ready,
                send_at: None,
            };
            let message_id = out.ready.message_id.clone();
            store()?.queue_outgoing(&out, now_secs())?;
            return Ok(SentMessage {
                message_id,
                filed: false,
                queued: true,
            });
        }
        other => other?,
    };
    // Sent: its draft goes. Left behind, it is only an extra draft.
    if let Some(saved) = settle_waiting(saved)? {
        erase_draft(saved).await.ok();
    }
    Ok(SentMessage {
        message_id: report.message_id,
        filed: report.filed_in.is_some(),
        queued: false,
    })
}

/// Keeps a message to send at `send_at` (Unix seconds), from this
/// device: it waits in the outbox, dated for then, and goes at that time,
/// or as soon as the app runs again after it. Returns its outbox id.
pub fn schedule_message(message: OutgoingMessage, send_at: i64) -> Result<i64, EngineError> {
    let id = AccountId(message.account_id);
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let saved = message.draft.clone();
    let remind_at = message.remind_at;
    let mut draft = core_draft(&account, message)?;
    draft.date = Some(send_at);
    let ready = smtp::ready(&draft)?;
    remind_sent(id, &ready.message_id, remind_at)?;
    let out = Outgoing {
        account: id,
        draft,
        saved: settle_waiting(saved)?.map(|d| (d.mailbox, d.uid)),
        ready,
        send_at: Some(send_at),
    };
    let queued = store()?.queue_outgoing(&out, now_secs())?;
    // On time while the app runs; the watchers also wait for it.
    let engine = engine()?;
    engine.runtime.spawn(async move {
        let wait = (send_at - now_secs()).max(0) as u64;
        tokio::time::sleep(std::time::Duration::from_secs(wait)).await;
        if let Ok((account, password)) = signed_in(id) {
            send_outbox(account, password);
        }
    });
    Ok(queued)
}

/// A message waiting in the outbox.
#[derive(Debug, Clone)]
pub struct OutboxItem {
    pub id: i64,
    pub account_id: i64,
    pub to: Vec<String>,
    pub subject: String,
    pub body: String,
    pub queued_at: i64,
    /// Why the server refused it; None while it only waits.
    pub error: Option<String>,
    /// When it goes, in Unix seconds, for mail sent later.
    pub send_at: Option<i64>,
}

/// The outbox, oldest first: one account's, or every account's.
pub fn outbox(account_id: Option<i64>) -> Result<Vec<OutboxItem>, EngineError> {
    Ok(store()?
        .outbox(account_id.map(AccountId))?
        .into_iter()
        .map(|w| OutboxItem {
            id: w.id,
            account_id: w.account.0,
            to: w.to,
            subject: w.subject,
            body: w.body,
            queued_at: w.queued_at,
            error: w.error,
            send_at: w.send_at,
        })
        .collect())
}

/// Takes a message back out of the outbox to edit it: it no longer goes
/// on its own.
pub fn reopen_outgoing(id: i64) -> Result<OutgoingMessage, EngineError> {
    let store = store()?;
    let out = store
        .outgoing(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "already sent"))?;
    store.drop_outgoing(id)?;
    let d = out.draft;
    Ok(OutgoingMessage {
        account_id: out.account.0,
        from_email: Some(d.from_email.clone()),
        files: d
            .files
            .into_iter()
            .map(|f| OutgoingFile {
                name: f.name,
                data: f.data,
            })
            .collect(),
        to: d.to,
        cc: d.cc,
        bcc: d.bcc,
        subject: d.subject,
        body: d.body,
        in_reply_to: d.in_reply_to,
        references: d.references,
        signature_id: d.signature.map(|s| s.id),
        signature_picked: false,
        remind_at: None,
        marks: body_marks(d.marks),
        draft: out.saved.map(|(mailbox, uid)| MessageRef {
            account_id: out.account.0,
            mailbox,
            uid,
        }),
    })
}

/// Tries the outbox of every account now, e.g. a while after a message
/// was queued, when no new mail woke the watchers.
pub fn send_outbox_now() -> Result<(), EngineError> {
    for account in store()?.accounts()? {
        if let Ok(password) = credentials::load(account.id) {
            save_waiting_drafts(account.clone(), password.clone());
            send_outbox(account, password);
        }
    }
    Ok(())
}

/// Deletes a message from the outbox without sending it.
pub fn delete_outgoing(id: i64) -> Result<(), EngineError> {
    Ok(store()?.drop_outgoing(id)?)
}

/// Accounts whose outbox is being sent, so nothing goes twice.
static SENDING: Mutex<Vec<i64>> = Mutex::new(Vec::new());

/// Sends an account's outbox, if it has anything waiting, and says so
/// with [SyncEventKind::OutboxSent] when something went.
fn send_outbox(account: Account, password: String) {
    let Ok(engine) = engine() else { return };
    let id = account.id;
    let waiting = engine
        .store
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .outbox(Some(id))
        .map(|w| w.iter().any(|w| w.error.is_none()))
        .unwrap_or(false);
    {
        let mut sending = SENDING.lock().unwrap_or_else(|e| e.into_inner());
        if !waiting || sending.contains(&id.0) {
            return;
        }
        sending.push(id.0);
    }
    let shared = engine.store.clone();
    engine.runtime.spawn(async move {
        let sent = outbox::send(&shared, &account, &password).await;
        SENDING
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|a| *a != id.0);
        let sent = sent.unwrap_or_default();
        if sent.is_empty() {
            return;
        }
        if let Ok(mut conn) = Remote::open(&account, &password).await {
            for s in &sent {
                if let Some((mailbox, uid)) = &s.saved {
                    conn.erase(&shared, id, mailbox, &[*uid]).await.ok();
                }
            }
            conn.sync_folders(&shared, id).await.ok();
            conn.close().await;
        }
        emit(SyncEvent {
            added: sent.len() as u32,
            ..SyncEvent::new(SyncEventKind::OutboxSent, id.0)
        });
    });
}

/// The engine's draft for a message being written from `account`.
fn core_draft(account: &Account, message: OutgoingMessage) -> Result<Draft, EngineError> {
    let from_email = match &message.from_email {
        Some(e) => store()?
            .own_addresses(account.id)?
            .into_iter()
            .find(|own| own.eq_ignore_ascii_case(e.trim()))
            .unwrap_or_else(|| account.email.clone()),
        None => account.email.clone(),
    };
    Ok(Draft {
        from_name: account.sender_name.clone(),
        from_email,
        to: message.to,
        cc: message.cc,
        bcc: message.bcc,
        subject: message.subject,
        body: message.body,
        in_reply_to: message.in_reply_to,
        references: message.references,
        signature: match message.signature_id {
            Some(sid) => store()?.signature(sid)?,
            None => None,
        },
        files: message
            .files
            .into_iter()
            .map(|f| smtp::OutgoingFile {
                mime: files::mime_for(&f.name).to_owned(),
                name: f.name,
                data: f.data,
            })
            .collect(),
        date: None,
        calendar: None,
        marks: core_marks(message.marks),
    })
}

/// An account and its password, to reach its server.
pub(crate) fn signed_in(id: AccountId) -> Result<(Account, String), EngineError> {
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
    Ok((account, password))
}

/// Keeps what is being written in its account's Drafts folder, in place of
/// its earlier copy (`message.draft`), even one in another account.
/// Returns where the new copy is. Offline, the draft waits on this device
/// and goes up at the next sync; the copy returned then has no mailbox.
pub async fn save_draft(message: OutgoingMessage) -> Result<MessageRef, EngineError> {
    let engine = engine()?;
    let id = AccountId(message.account_id);
    let (account, password) = signed_in(id)?;
    let waiting = message.draft.as_ref().and_then(waiting_id);
    let earlier = match waiting {
        Some(w) => store()?.waiting_draft(w)?.and_then(|d| {
            d.earlier.map(|(a, mailbox, uid)| MessageRef {
                account_id: a.0,
                mailbox,
                uid,
            })
        }),
        None => message.draft.clone(),
    };
    let picked = message.signature_picked.then(|| {
        message
            .signature_id
            .map_or_else(|| "none".to_owned(), |s| s.to_string())
    });
    let raw = smtp::build_unsent(&core_draft(&account, message)?)?;
    let message_id = raw
        .headers()
        .get_raw("Message-ID")
        .unwrap_or_default()
        .trim()
        .to_owned();
    let raw = raw.formatted();
    let shared = engine.store.clone();
    let earlier_here = earlier.as_ref().filter(|e| e.account_id == id.0).cloned();
    let (to_append, wanted) = (raw.clone(), message_id.clone());
    let saved = engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let folder = conn.append_draft(&to_append).await?;
            if let Some(e) = &earlier_here {
                conn.erase(&shared, id, &e.mailbox, &[e.uid]).await?;
            }
            lock_store(&shared).set_folder_role(id, Folder::Drafts, &folder)?;
            conn.sync_mailbox(&shared, id, &folder).await?;
            conn.close().await;
            let uid = lock_store(&shared).uid_of(id, &folder, &wanted)?;
            Ok::<_, RemoteError>((folder, uid))
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    let saved = match saved {
        Err(e) if e.is_offline() => {
            let kept = store()?.keep_waiting_draft(
                &WaitingDraft {
                    id: 0,
                    account: id,
                    raw,
                    message_id,
                    earlier: earlier.map(|e| (AccountId(e.account_id), e.mailbox, e.uid)),
                    signature: picked,
                },
                waiting,
                now_secs(),
            )?;
            return Ok(MessageRef {
                account_id: id.0,
                mailbox: String::new(),
                uid: kept as u32,
            });
        }
        other => other?,
    };
    if let Some(w) = waiting {
        store()?.drop_waiting_draft(w)?;
    }
    if let Some(e) = &earlier {
        store()?.remove_setting(&draft_signature_key(e))?;
    }
    if let Some(e) = earlier.filter(|e| e.account_id != id.0) {
        erase_draft(e).await.ok();
    }
    match saved {
        (mailbox, Some(uid)) => {
            let copy = MessageRef {
                account_id: id.0,
                mailbox,
                uid,
            };
            if let Some(picked) = picked {
                store()?.set_setting(&draft_signature_key(&copy), &picked)?;
            }
            Ok(copy)
        }
        _ => Err(EngineError::new(
            ErrorKind::Other,
            "the saved draft is not on the server",
        )),
    }
}

/// The waiting draft a copy names: it has no mailbox, and its uid is the
/// waiting row.
fn waiting_id(draft: &MessageRef) -> Option<i64> {
    draft.mailbox.is_empty().then_some(draft.uid as i64)
}

/// Forgets a draft waiting on this device, when the copy names one, and
/// gives the server copy it was to replace. Other copies come back as they are.
fn settle_waiting(draft: Option<MessageRef>) -> Result<Option<MessageRef>, EngineError> {
    let Some(draft) = draft else { return Ok(None) };
    let Some(w) = waiting_id(&draft) else {
        return Ok(Some(draft));
    };
    let store = store()?;
    let earlier = store.waiting_draft(w)?.and_then(|d| d.earlier);
    store.drop_waiting_draft(w)?;
    Ok(earlier.map(|(a, mailbox, uid)| MessageRef {
        account_id: a.0,
        mailbox,
        uid,
    }))
}

/// Accounts whose waiting drafts are going up, so nothing goes twice.
static SAVING: Mutex<Vec<i64>> = Mutex::new(Vec::new());

/// Puts the drafts that waited on this device in the account's Drafts
/// folder, each in place of its earlier copy, and says so with
/// [SyncEventKind::Synced].
fn save_waiting_drafts(account: Account, password: String) {
    let Ok(engine) = engine() else { return };
    let id = account.id;
    let waiting = lock_store(&engine.store)
        .waiting_drafts(id)
        .unwrap_or_default();
    {
        let mut saving = SAVING.lock().unwrap_or_else(|e| e.into_inner());
        if waiting.is_empty() || saving.contains(&id.0) {
            return;
        }
        saving.push(id.0);
    }
    let shared = engine.store.clone();
    engine.runtime.spawn(async move {
        let mut elsewhere = Vec::new();
        let saved = async {
            let mut conn = Remote::open(&account, &password).await?;
            let mut folder = None;
            for d in &waiting {
                let into = conn.append_draft(&d.raw).await?;
                match &d.earlier {
                    Some((a, mailbox, uid)) if *a == id => {
                        conn.erase(&shared, id, mailbox, &[*uid]).await.ok();
                    }
                    Some((a, mailbox, uid)) => elsewhere.push(MessageRef {
                        account_id: a.0,
                        mailbox: mailbox.clone(),
                        uid: *uid,
                    }),
                    None => {}
                }
                lock_store(&shared).drop_waiting_draft(d.id)?;
                folder = Some(into);
            }
            if let Some(folder) = &folder {
                lock_store(&shared).set_folder_role(id, Folder::Drafts, folder)?;
                conn.sync_mailbox(&shared, id, folder).await?;
                let store = lock_store(&shared);
                for d in &waiting {
                    let (Some(picked), Ok(Some(uid))) =
                        (&d.signature, store.uid_of(id, folder, &d.message_id))
                    else {
                        continue;
                    };
                    let copy = MessageRef {
                        account_id: id.0,
                        mailbox: folder.clone(),
                        uid,
                    };
                    store.set_setting(&draft_signature_key(&copy), picked).ok();
                }
            }
            conn.close().await;
            Ok::<_, RemoteError>(())
        }
        .await;
        SAVING
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|a| *a != id.0);
        for e in elsewhere {
            erase_draft(e).await.ok();
        }
        if saved.is_ok() {
            emit(SyncEvent::new(SyncEventKind::Synced, id.0));
        }
    });
}

/// Deletes a saved copy of a draft for good, without Trash.
/// Throws a draft away for good, as "Discard" says, rather than to Trash:
/// an autosaved copy nobody finished is no mail to keep.
pub async fn discard_draft(draft: MessageRef) -> Result<(), EngineError> {
    erase_draft(draft).await
}

async fn erase_draft(draft: MessageRef) -> Result<(), EngineError> {
    let Some(draft) = settle_waiting(Some(draft))? else {
        return Ok(());
    };
    let engine = engine()?;
    store()?.remove_setting(&draft_signature_key(&draft))?;
    let id = AccountId(draft.account_id);
    let (account, password) = signed_in(id)?;
    let shared = engine.store.clone();
    engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            conn.erase(&shared, id, &draft.mailbox, &[draft.uid])
                .await?;
            conn.close().await;
            Ok::<_, RemoteError>(())
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
        .map_err(EngineError::from)
}

/// A saved draft, to go on writing it.
pub async fn open_draft(draft: MessageRef) -> Result<OutgoingMessage, EngineError> {
    let engine = engine()?;
    let id = AccountId(draft.account_id);
    let (account, password) = signed_in(id)?;
    let (mailbox, uid) = (draft.mailbox.clone(), draft.uid);
    let shared = engine.store.clone();
    let here = match waiting_id(&draft) {
        Some(w) => store()?.waiting_draft(w)?,
        None => None,
    };
    let (raw, picked) = match here {
        Some(d) => (d.raw, d.signature),
        None => {
            let raw = engine
                .runtime
                .spawn(async move {
                    let mut conn = Remote::open(&account, &password).await?;
                    let raw = conn.raw(&shared, id, &mailbox, uid).await?;
                    conn.close().await;
                    Ok::<_, RemoteError>(raw)
                })
                .await
                .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
            (raw, store()?.setting(&draft_signature_key(&draft))?)
        }
    };
    let d = imap::parse_draft(&raw);
    Ok(OutgoingMessage {
        account_id: draft.account_id,
        from_email: Some(d.from_email.clone()).filter(|e| !e.is_empty()),
        files: d
            .files
            .into_iter()
            .map(|f| OutgoingFile {
                name: f.name,
                data: f.data,
            })
            .collect(),
        to: d.to,
        cc: d.cc,
        bcc: d.bcc,
        subject: d.subject,
        body: d.body,
        in_reply_to: d.in_reply_to,
        references: d.references,
        signature_id: picked.as_deref().and_then(|v| v.parse().ok()),
        signature_picked: picked.is_some(),
        remind_at: None,
        marks: body_marks(d.marks),
        draft: Some(draft),
    })
}

fn lock_store(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}

/// Hides a message from the lists while its action can be undone, or
/// shows it again after Undo.
#[frb(sync)]
pub fn set_message_hidden(
    account_id: i64,
    mailbox: String,
    uid: u32,
    hidden: bool,
) -> Result<(), EngineError> {
    Ok(store()?.set_hidden(AccountId(account_id), &mailbox, uid, hidden)?)
}

/// One message, as the store names it.
#[derive(Debug, Clone)]
pub struct MessageRef {
    pub account_id: i64,
    pub mailbox: String,
    pub uid: u32,
}

/// Marks messages read or unread on this device. Call
/// [`push_messages_seen`] next to tell their servers. Off the app's
/// thread: opening an email never waits for a sync writing.
pub fn set_messages_seen(messages: Vec<MessageRef>, seen: bool) -> Result<(), EngineError> {
    let store = store()?;
    for m in &messages {
        store.set_seen(AccountId(m.account_id), &m.mailbox, m.uid, seen)?;
    }
    Ok(())
}

/// Tells the servers which messages were marked read or unread. When a
/// server can't be reached the change waits and goes out once it can;
/// on any other failure they go back to how they were here, and this
/// fails.
pub async fn push_messages_seen(messages: Vec<MessageRef>, seen: bool) -> Result<(), EngineError> {
    let engine = engine()?;
    let mut by_account: std::collections::BTreeMap<i64, Vec<(String, u32)>> = Default::default();
    for m in &messages {
        by_account
            .entry(m.account_id)
            .or_default()
            .push((m.mailbox.clone(), m.uid));
    }
    let mut result = Ok(());
    for (account_id, list) in by_account {
        let id = AccountId(account_id);
        let pushed = async {
            let (account, password) = signed_in(id)?;
            let shared = engine.store.clone();
            let list = list.clone();
            engine
                .runtime
                .spawn(async move {
                    let mut by_folder: std::collections::BTreeMap<String, Vec<u32>> =
                        Default::default();
                    for (mailbox, uid) in list {
                        by_folder.entry(mailbox).or_default().push(uid);
                    }
                    let pushed = async {
                        let mut conn = Remote::open(&account, &password).await?;
                        for (mailbox, uids) in &by_folder {
                            conn.set_seen(&shared, id, mailbox, uids, seen).await?;
                        }
                        conn.close().await;
                        Ok::<_, RemoteError>(())
                    }
                    .await;
                    match pushed {
                        Err(e) if e.is_offline() => {
                            let store = shared.lock().unwrap_or_else(|e| e.into_inner());
                            for (mailbox, uids) in &by_folder {
                                for uid in uids {
                                    store.queue_change(id, mailbox, *uid, Change::Seen(seen))?;
                                }
                            }
                            Ok(())
                        }
                        other => other,
                    }
                })
                .await
                .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
                .map_err(EngineError::from)
        }
        .await;
        if let Err(e) = pushed {
            let store = store()?;
            for (mailbox, uid) in &list {
                store.set_seen(id, mailbox, *uid, !seen)?;
            }
            result = Err(e);
        }
    }
    result
}

/// Where a message goes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageAction {
    Archive,
    Delete,
    /// Report spam: to the account's spam folder, which is never made.
    Junk,
    /// Not spam: from the spam folder back to the inbox.
    NotJunk,
}

/// Moves messages to Archive, Trash or spam on their servers, one command per
/// folder. When a server can't be reached the move waits, the messages
/// stay hidden, and it goes out once it can; on any other failure the
/// messages of that account are shown again.
pub async fn apply_message_action(
    messages: Vec<MessageRef>,
    action: MessageAction,
) -> Result<(), EngineError> {
    let engine = engine()?;
    // Not spam goes to the inbox by name; the rest to a folder by role.
    let role = match action {
        MessageAction::Archive => Some(FolderRole::Archive),
        MessageAction::Delete => Some(FolderRole::Trash),
        MessageAction::Junk => Some(FolderRole::Junk),
        MessageAction::NotJunk => None,
    };
    let junk = match action {
        MessageAction::Junk => Some(true),
        MessageAction::NotJunk => Some(false),
        _ => None,
    };
    // A draft still waiting on this device is simply forgotten; the
    // server copy it was to replace goes in its place.
    let mut on_server = Vec::new();
    for m in messages {
        if waiting_id(&m).is_some() {
            on_server.extend(settle_waiting(Some(m))?);
        } else {
            on_server.push(m);
        }
    }
    let mut by_account: std::collections::BTreeMap<i64, Vec<(String, u32)>> = Default::default();
    for m in on_server {
        by_account
            .entry(m.account_id)
            .or_default()
            .push((m.mailbox, m.uid));
    }
    let mut result = Ok(());
    for (account_id, list) in by_account {
        let id = AccountId(account_id);
        let moved = async {
            let (account, password) = signed_in(id)?;
            let shared = engine.store.clone();
            let list = list.clone();
            engine
                .runtime
                .spawn(async move {
                    let mut by_folder: std::collections::BTreeMap<String, Vec<u32>> =
                        Default::default();
                    for (mailbox, uid) in list {
                        by_folder.entry(mailbox).or_default().push(uid);
                    }
                    let moved = async {
                        let mut conn = Remote::open(&account, &password).await?;
                        let mut target = None;
                        for (mailbox, uids) in &by_folder {
                            if let Some(junk) = junk {
                                // Teaching the filter is a bonus: a server
                                // that refuses it still gets the move.
                                let _ = conn.mark_junk(&shared, id, mailbox, uids, junk).await;
                            }
                            target = Some(match role {
                                Some(role) => {
                                    conn.move_messages(&shared, id, mailbox, uids, role).await?
                                }
                                None => {
                                    conn.move_to(&shared, id, mailbox, uids, "INBOX").await?;
                                    "INBOX".to_owned()
                                }
                            });
                        }
                        if let (Some(FolderRole::Archive), Some(target)) = (role, target) {
                            // Show them in Archive right away, not at the next look.
                            shared
                                .lock()
                                .unwrap_or_else(|e| e.into_inner())
                                .set_folder_role(id, Folder::Archive, &target)?;
                            conn.sync_mailbox(&shared, id, &target).await?;
                        }
                        conn.close().await;
                        Ok::<_, RemoteError>(())
                    }
                    .await;
                    match moved {
                        // Messages already moved are gone from the store,
                        // so only the rest wait.
                        Err(e) if e.is_offline() => {
                            let store = shared.lock().unwrap_or_else(|e| e.into_inner());
                            for (mailbox, uids) in &by_folder {
                                for uid in uids {
                                    if store.message(id, mailbox, *uid)?.is_some() {
                                        let change = match role {
                                            Some(role) => Change::Move(role),
                                            None => Change::MoveTo("INBOX".to_owned()),
                                        };
                                        store.queue_change(id, mailbox, *uid, change)?;
                                    }
                                }
                            }
                            Ok(())
                        }
                        other => other,
                    }
                })
                .await
                .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
                .map_err(EngineError::from)
        }
        .await;
        if let Err(e) = moved {
            let store = store()?;
            for (mailbox, uid) in &list {
                store.set_hidden(id, mailbox, *uid, false)?;
            }
            result = Err(e);
        }
    }
    result
}

/// The account's spam folder, by its server name, once a sync found one:
/// Report spam is offered only then.
#[frb(sync)]
pub fn junk_mailbox(account_id: i64) -> Result<Option<String>, EngineError> {
    Ok(reader()?.junk_mailbox(AccountId(account_id))?)
}

/// One of an account's own folders, in tree order.
#[derive(Debug, Clone)]
pub struct AccountFolderInfo {
    /// What the server calls it: pass it back to open or move to it.
    pub mailbox: String,
    pub name: String,
    pub depth: u32,
    /// False for a folder that only holds other folders.
    pub selectable: bool,
    pub unread: u32,
    /// How many emails it holds on the server.
    pub total: u32,
}

/// An account's own folders (not Inbox, Sent, Archive, Drafts, Trash or
/// spam), as last seen on its server.
pub fn account_folders(account_id: i64) -> Result<Vec<AccountFolderInfo>, EngineError> {
    Ok(store()?
        .account_folders(AccountId(account_id))?
        .into_iter()
        .map(|f| AccountFolderInfo {
            mailbox: f.mailbox,
            name: f.name,
            depth: f.depth,
            selectable: f.selectable,
            unread: f.unread,
            total: f.total,
        })
        .collect())
}

/// Keeps the order the person dragged some sibling folders into, first
/// to last; every list of the account's folders follows it.
pub fn set_folder_order(account_id: i64, mailboxes: Vec<String>) -> Result<(), EngineError> {
    store()?.set_folder_order(AccountId(account_id), &mailboxes)?;
    Ok(())
}

/// Makes a folder of the account's own, at the top of its list, on the
/// server. Returns its server name.
pub async fn create_folder(account_id: i64, name: String) -> Result<String, EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    if name.trim().is_empty() {
        return Err(EngineError::new(ErrorKind::Other, "empty folder name"));
    }
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
    let store = engine.store.clone();
    engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let made = conn.create_folder(&store, id, &name).await;
            conn.close().await;
            made
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
        .map_err(EngineError::from)
}

/// How many conversations one of an account's folders lists here.
pub fn mailbox_count(account_id: i64, mailbox: String) -> Result<u32, EngineError> {
    Ok(store()?.mailbox_count(AccountId(account_id), &mailbox)?)
}

/// Rows `offset..offset+limit` of one of an account's folders, newest
/// first, one per conversation.
pub fn mailbox_page(
    account_id: i64,
    mailbox: String,
    offset: u32,
    limit: u32,
) -> Result<Vec<InboxRow>, EngineError> {
    let store = store()?;
    Ok(store
        .mailbox_page(AccountId(account_id), &mailbox, offset, limit)?
        .into_iter()
        .map(|c| {
            with_files(
                &store,
                InboxRow {
                    thread: c.thread,
                    messages: c.messages,
                    ..inbox_row(&store, c.latest)
                },
            )
        })
        .collect())
}

/// Conversations per period in one of an account's folders, like
/// [`folder_counts_between`].
pub fn mailbox_counts_between(
    account_id: i64,
    mailbox: String,
    edges: Vec<i64>,
) -> Result<Vec<u32>, EngineError> {
    let store = store()?;
    let account = AccountId(account_id);
    edges
        .windows(2)
        .map(|w| Ok(store.mailbox_count_between(account, &mailbox, w[1], w[0])?))
        .collect()
}

/// Brings one of an account's folders up to date, the newest
/// [`imap::ROUND`] messages at a time. Returns how many are left; call
/// again while it is more than 0.
pub async fn sync_mailbox_now(account_id: i64, mailbox: String) -> Result<u32, EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    let (account, password) = signed_in(id)?;
    let shared = engine.store.clone();
    engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let more = conn.sync_round(&shared, id, &mailbox, imap::ROUND).await?;
            conn.close().await;
            Ok::<_, RemoteError>(more as u32)
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
        .map_err(EngineError::from)
}

/// Moves messages of one account to one of its own folders. When the
/// server can't be reached the move waits, the messages stay hidden, and
/// it goes out once it can; on any other failure they are shown again.
pub async fn move_messages_to(
    messages: Vec<MessageRef>,
    target: String,
) -> Result<(), EngineError> {
    let engine = engine()?;
    // A draft still waiting on this device is simply forgotten; the
    // server copy it was to replace goes in its place.
    let mut on_server = Vec::new();
    for m in messages {
        if waiting_id(&m).is_some() {
            on_server.extend(settle_waiting(Some(m))?);
        } else {
            on_server.push(m);
        }
    }
    log_moves(&on_server, &target)?;
    let mut by_account: std::collections::BTreeMap<i64, Vec<(String, u32)>> = Default::default();
    for m in on_server {
        by_account
            .entry(m.account_id)
            .or_default()
            .push((m.mailbox, m.uid));
    }
    let mut result = Ok(());
    for (account_id, list) in by_account {
        let id = AccountId(account_id);
        let moved = async {
            let (account, password) = signed_in(id)?;
            let shared = engine.store.clone();
            let (list, target) = (list.clone(), target.clone());
            engine
                .runtime
                .spawn(async move {
                    let mut by_folder: std::collections::BTreeMap<String, Vec<u32>> =
                        Default::default();
                    for (mailbox, uid) in list {
                        by_folder.entry(mailbox).or_default().push(uid);
                    }
                    let moved = async {
                        let mut conn = Remote::open(&account, &password).await?;
                        for (mailbox, uids) in &by_folder {
                            conn.move_to(&shared, id, mailbox, uids, &target).await?;
                        }
                        conn.close().await;
                        Ok::<_, RemoteError>(())
                    }
                    .await;
                    match moved {
                        Err(e) if e.is_offline() => {
                            let store = shared.lock().unwrap_or_else(|e| e.into_inner());
                            for (mailbox, uids) in &by_folder {
                                for uid in uids {
                                    if store.message(id, mailbox, *uid)?.is_some() {
                                        let change = Change::MoveTo(target.clone());
                                        store.queue_change(id, mailbox, *uid, change)?;
                                    }
                                }
                            }
                            Ok(())
                        }
                        other => other,
                    }
                })
                .await
                .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
                .map_err(EngineError::from)
        }
        .await;
        if let Err(e) = moved {
            let store = store()?;
            for (mailbox, uid) in &list {
                store.set_hidden(id, mailbox, *uid, false)?;
            }
            result = Err(e);
        }
    }
    result
}

/// A snoozed message, and when it comes back (Unix seconds; None when
/// no device of the person's knows, e.g. snoozed in another app).
pub struct SnoozedRow {
    pub row: InboxRow,
    pub until: Option<i64>,
}

/// Snoozed mail of every account (or one), the soonest back first.
pub fn snoozed(account: Option<i64>) -> Result<Vec<SnoozedRow>, EngineError> {
    let store = store()?;
    Ok(store
        .snoozed(account.map(AccountId))?
        .into_iter()
        .map(|(m, until)| SnoozedRow {
            row: InboxRow {
                folder: Some(MailFolder::Snoozed),
                ..inbox_row(&store, m)
            },
            until,
        })
        .collect())
}

/// Sent mail nobody has answered yet, and who it waits on.
pub struct WaitingRow {
    pub row: InboxRow,
    /// The people it went to, by address (not yourself, lists or
    /// machines): who Write again goes to.
    pub to: Vec<String>,
    /// "Remind me if nobody replies": when it comes back to the top of
    /// the inbox (Unix seconds), if it still waits then.
    pub remind_at: Option<i64>,
}

fn waiting_row(store: &Store, m: MessageSummary, remind_at: Option<i64>) -> WaitingRow {
    WaitingRow {
        to: m
            .reply
            .recipients
            .split_whitespace()
            .map(String::from)
            .collect(),
        remind_at,
        row: InboxRow {
            folder: Some(MailFolder::Sent),
            ..inbox_row(store, m)
        },
    }
}

/// Waiting: mail you sent to people in the last 30 days that nobody has
/// answered yet, newest first, of every account (or one).
pub fn waiting(account: Option<i64>) -> Result<Vec<WaitingRow>, EngineError> {
    let store = store()?;
    let account = account.map(AccountId);
    let times = store.reply_reminders(account)?;
    Ok(store
        .waiting(account, now_secs())?
        .into_iter()
        .map(|m| {
            let at = times.get(&(m.account, m.reply.message_id.clone())).copied();
            waiting_row(&store, m, at)
        })
        .collect())
}

/// Mail of Waiting whose reminder has come: back at the top of the inbox,
/// the latest back first, of every account (or one).
pub fn reminded(account: Option<i64>) -> Result<Vec<WaitingRow>, EngineError> {
    let store = store()?;
    Ok(store
        .reminded(account.map(AccountId), now_secs())?
        .into_iter()
        .map(|(m, at)| waiting_row(&store, m, Some(at)))
        .collect())
}

/// "Remind me if nobody replies" for sent mail: back at the top of the
/// inbox at `at` (Unix seconds) if nobody has replied by then; None
/// ("Don't remind me") forgets it. Kept on this device.
pub fn remind_me(message: MessageRef, at: Option<i64>) -> Result<(), EngineError> {
    let store = store()?;
    let id = AccountId(message.account_id);
    if let Some(m) = store.message(id, &message.mailbox, message.uid)? {
        store.set_reply_reminder(id, &m.reply.message_id, at)?;
    }
    Ok(())
}

/// Leaves sent mail out of Waiting; it stays in Sent.
pub fn stop_waiting(message: MessageRef) -> Result<(), EngineError> {
    let store = store()?;
    let id = AccountId(message.account_id);
    if let Some(m) = store.message(id, &message.mailbox, message.uid)? {
        store.stop_waiting(id, &m.reply.message_id)?;
    }
    Ok(())
}

/// Snoozes messages until `until` (Unix seconds): they leave the list at
/// once, wait in the account's Snoozed folder and come back to the inbox,
/// unread, at that time. When the server can't be reached the move waits
/// and goes out once it can; on any other failure they are shown again.
/// With `unless_reply` ("If nobody replies") they also come back as soon
/// as someone else writes in their thread.
pub async fn snooze_messages(
    messages: Vec<MessageRef>,
    until: i64,
    unless_reply: bool,
) -> Result<(), EngineError> {
    {
        let store = store()?;
        let now = now_secs();
        for m in &messages {
            let id = AccountId(m.account_id);
            store.snooze(id, &m.mailbox, &[m.uid], until)?;
            if unless_reply {
                store.snooze_unless_reply(id, &m.mailbox, &[m.uid], now)?;
            }
        }
    }
    let result = put_away(messages.clone(), Change::Snooze(until)).await;
    if result.is_err() {
        let store = store()?;
        for m in &messages {
            let id = AccountId(m.account_id);
            store.forget_snoozes(id, &m.mailbox, &[m.uid])?;
            store.set_snooze_times(id, &m.mailbox, &[(m.uid, None)])?;
            store.set_hidden(id, &m.mailbox, m.uid, false)?;
        }
    }
    result
}

/// Brings snoozed messages back to the inbox now, unread.
pub async fn wake_messages(messages: Vec<MessageRef>) -> Result<(), EngineError> {
    let mut by_until: std::collections::BTreeMap<i64, Vec<MessageRef>> = Default::default();
    {
        let store = store()?;
        for m in messages {
            let id = AccountId(m.account_id);
            let until = store
                .snooze_until(id, &m.mailbox, m.uid)?
                .unwrap_or_default();
            store.set_hidden(id, &m.mailbox, m.uid, true)?;
            by_until.entry(until).or_default().push(m);
        }
    }
    let mut result = Ok(());
    for (until, list) in by_until {
        if let Err(e) = put_away(list, Change::Wake(until)).await {
            result = Err(e);
        }
    }
    result
}

/// Sends a snooze or a wake for messages already hidden here, one account
/// at a time; offline, it waits in the queue. On any other failure the
/// account's messages are shown again and this fails.
async fn put_away(messages: Vec<MessageRef>, change: Change) -> Result<(), EngineError> {
    let engine = engine()?;
    // A draft still waiting on this device is simply forgotten; the
    // server copy it was to replace goes in its place.
    let mut on_server = Vec::new();
    for m in messages {
        if waiting_id(&m).is_some() {
            on_server.extend(settle_waiting(Some(m))?);
        } else {
            on_server.push(m);
        }
    }
    let mut by_account: std::collections::BTreeMap<i64, Vec<(String, u32)>> = Default::default();
    for m in on_server {
        by_account
            .entry(m.account_id)
            .or_default()
            .push((m.mailbox, m.uid));
    }
    let mut result = Ok(());
    for (account_id, list) in by_account {
        let id = AccountId(account_id);
        let sent = async {
            let (account, password) = signed_in(id)?;
            let shared = engine.store.clone();
            let (list, change) = (list.clone(), change.clone());
            engine
                .runtime
                .spawn(async move {
                    let mut by_folder: std::collections::BTreeMap<String, Vec<u32>> =
                        Default::default();
                    for (mailbox, uid) in list {
                        by_folder.entry(mailbox).or_default().push(uid);
                    }
                    let sent = async {
                        let mut conn = Remote::open(&account, &password).await?;
                        for (mailbox, uids) in &by_folder {
                            match change {
                                Change::Snooze(until) => {
                                    conn.snooze(&shared, id, mailbox, uids, until).await?
                                }
                                Change::Wake(until) => {
                                    conn.wake(&shared, id, mailbox, uids, until).await?
                                }
                                _ => {}
                            }
                        }
                        conn.close().await;
                        Ok::<_, RemoteError>(())
                    }
                    .await;
                    match sent {
                        Err(e) if e.is_offline() => {
                            let store = shared.lock().unwrap_or_else(|e| e.into_inner());
                            for (mailbox, uids) in &by_folder {
                                for uid in uids {
                                    if store.message(id, mailbox, *uid)?.is_some() {
                                        store.queue_change(id, mailbox, *uid, change.clone())?;
                                    }
                                }
                            }
                            Ok(())
                        }
                        other => other,
                    }
                })
                .await
                .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
                .map_err(EngineError::from)
        }
        .await;
        if let Err(e) = sent {
            let store = store()?;
            for (mailbox, uid) in &list {
                store.set_hidden(id, mailbox, *uid, false)?;
            }
            result = Err(e);
        }
    }
    result
}

/// A message found by a search.
pub struct SearchHit {
    pub row: InboxRow,
    /// Where the body matched, each match between U+0002 and U+0003; empty
    /// when the body didn't match.
    pub snippet: String,
    /// Whether it came with files.
    pub files: bool,
}

/// Someone who wrote to the person.
pub struct Contact {
    pub name: String,
    pub email: String,
    /// How many of their messages are on this device.
    pub messages: u32,
}

pub struct SearchResult {
    /// How many messages match in all; `hits` holds the newest of them.
    pub total: u32,
    pub hits: Vec<SearchHit>,
    /// Senders matching the words, most frequent first.
    pub people: Vec<Contact>,
    /// The files of the newest messages found.
    pub files: Vec<AttachedFile>,
    /// How many messages the search looked through.
    pub searched: u32,
    pub millis: u32,
}

/// Files listed under Attachments in search results at most.
const SEARCH_FILES: u32 = 6;

/// Searches every message on this device. `query` is what the person
/// typed, operators included (`from:`, `account:`, `is:unread`, `after:`,
/// `before:`, `has:attachment`, `in:vault`, `in:newsletter`,
/// `from:people`).
pub fn search(query: String, limit: u32) -> Result<SearchResult, EngineError> {
    let start = std::time::Instant::now();
    let query = Query::parse(&query);
    let store = store()?;
    let found = store.search(&query, limit)?;
    let people = store.search_people(&query, 3)?;
    let files = store.search_files(&query, SEARCH_FILES)?;
    let searched = store.indexed(&query)?;
    Ok(SearchResult {
        total: found.total,
        hits: found
            .hits
            .into_iter()
            .map(|h| {
                Ok(SearchHit {
                    row: in_conversation(&store, inbox_row(&store, h.message))?,
                    snippet: h.snippet,
                    files: h.files,
                })
            })
            .collect::<Result<_, EngineError>>()?,
        people: people
            .into_iter()
            .map(|p| Contact {
                name: p.name,
                email: p.email,
                messages: p.messages,
            })
            .collect(),
        files: files
            .into_iter()
            .map(|(m, a)| {
                Ok(AttachedFile {
                    row: in_conversation(&store, inbox_row(&store, m))?,
                    part_id: a.part,
                    risk: file_risk(&a.name),
                    name: a.name,
                    mime: a.mime,
                    size: a.size,
                })
            })
            .collect::<Result<_, EngineError>>()?,
        searched,
        millis: start.elapsed().as_millis().min(u32::MAX as u128) as u32,
    })
}

/// Someone who writes often, for "Frequent contacts".
pub struct FrequentContact {
    pub name: String,
    pub email: String,
    /// The account their newest message came to, for its dot.
    pub account_id: i64,
}

/// What an empty search shows (`SearchEmpty`).
pub struct SearchStart {
    /// The people who wrote most in the last six months.
    pub frequent: Vec<FrequentContact>,
    /// What was searched lately, newest first.
    pub recent: Vec<String>,
    /// How many messages search looks through on this device.
    pub indexed: u32,
}

/// The start of an empty search: frequent contacts, recent searches and
/// how much is indexed.
pub fn search_start() -> Result<SearchStart, EngineError> {
    const HALF_YEAR: i64 = 183 * 86_400;
    let store = store()?;
    Ok(SearchStart {
        frequent: store
            .frequent_people(now_secs() - HALF_YEAR, 8)?
            .into_iter()
            .map(|(p, account)| FrequentContact {
                name: p.name,
                email: p.email,
                account_id: account.0,
            })
            .collect(),
        recent: store.recent_searches()?,
        indexed: store.indexed(&Query::default())?,
    })
}

/// Someone suggested while an address is typed in compose.
pub struct RecipientSuggestion {
    pub name: String,
    pub email: String,
    /// Written to ("Wrote to"), or only wrote ("Wrote to you").
    pub written_to: bool,
}

/// The people to suggest while an address is typed in compose: first those
/// written to, then those who wrote, the most recent first in each.
pub fn suggest_recipients(
    typed: String,
    limit: u32,
) -> Result<Vec<RecipientSuggestion>, EngineError> {
    Ok(store()?
        .suggest_recipients(&typed, limit as usize)?
        .into_iter()
        .map(|p| RecipientSuggestion {
            name: p.name,
            email: p.email,
            written_to: p.written_to,
        })
        .collect())
}

/// Keeps a search among the recent ones, or with `forget` removes it.
pub fn note_search(query: String, forget: bool) -> Result<(), EngineError> {
    Ok(store()?.note_search(&query, forget)?)
}

/// Forgets every recent search.
pub fn clear_searches() -> Result<(), EngineError> {
    Ok(store()?.clear_searches()?)
}

/// A newsletter in the Newsletters list.
#[derive(Debug, Clone)]
pub struct NewsletterRow {
    pub row: InboxRow,
    /// Minutes to read it; 0 until its body is known.
    pub minutes: u32,
}

/// Rows `offset..offset+limit` of Newsletters, newest first. [account]
/// keeps one account's, all when None.
pub fn newsletters_page(
    account: Option<i64>,
    offset: u32,
    limit: u32,
) -> Result<Vec<NewsletterRow>, EngineError> {
    let store = store()?;
    Ok(store
        .newsletters_page(account.map(AccountId), offset, limit)?
        .into_iter()
        .map(|(m, minutes)| NewsletterRow {
            row: InboxRow {
                folder: Some(MailFolder::Newsletters),
                ..inbox_row(&store, m)
            },
            minutes,
        })
        .collect())
}

/// The address of a newsletter issue's cover: its first photo, when the
/// sender's images may load (trusted, or remote images not blocked) and
/// its body is already here. Nothing is fetched to find it.
pub async fn newsletter_cover(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<Option<String>, EngineError> {
    let id = AccountId(account_id);
    let store = reader()?;
    let Some(message) = store.message(id, &mailbox, uid)? else {
        return Ok(None);
    };
    let allowed = !switch(&store, BLOCK_IMAGES)?
        || (!message.from_email.is_empty() && store.is_trusted(&message.from_email)?);
    if !allowed {
        return Ok(None);
    }
    let Some(html) = store.full_body(id, &mailbox, uid)?.and_then(|b| b.html) else {
        return Ok(None);
    };
    Ok(reading::cover(&html))
}

/// How a newsletter can be left.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnsubscribeKind {
    /// Its headers give no way.
    None,
    /// One request, nothing to open.
    OneClick,
    /// A message to the list's address.
    Mail,
    /// A page of the sender's, in the browser.
    Page,
}

#[derive(Debug, Clone)]
pub struct Unsubscribe {
    pub kind: UnsubscribeKind,
    /// The page, or the address the message goes to.
    pub address: String,
}

/// How the list a message came from can be left.
pub fn unsubscribe_info(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<Unsubscribe, EngineError> {
    let list = store()?.list_info(AccountId(account_id), &mailbox, uid)?;
    let link = list.unsubscribe;
    Ok(if list.one_click {
        Unsubscribe {
            kind: UnsubscribeKind::OneClick,
            address: link,
        }
    } else if let Some(mail) = newsletter::mailto(&link) {
        Unsubscribe {
            kind: UnsubscribeKind::Mail,
            address: mail.to,
        }
    } else if link.is_empty() {
        Unsubscribe {
            kind: UnsubscribeKind::None,
            address: link,
        }
    } else {
        Unsubscribe {
            kind: UnsubscribeKind::Page,
            address: link,
        }
    })
}

/// Leaves the list a message came from, with one request or a message
/// to its address. A page to open is the app's to open.
pub async fn unsubscribe(account_id: i64, mailbox: String, uid: u32) -> Result<(), EngineError> {
    let list = store()?.list_info(AccountId(account_id), &mailbox, uid)?;
    if list.one_click {
        let link = list.unsubscribe.clone();
        return engine()?
            .runtime
            .spawn(async move { newsletter::one_click(&link).await })
            .await
            .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
            .map_err(|e| EngineError::new(ErrorKind::Unreachable, e.to_string()));
    }
    let Some(mail) = newsletter::mailto(&list.unsubscribe) else {
        return Err(EngineError::new(ErrorKind::Other, "no way to unsubscribe"));
    };
    send_message(OutgoingMessage {
        account_id,
        from_email: None,
        files: vec![],
        to: vec![mail.to],
        cc: vec![],
        bcc: vec![],
        subject: mail.subject,
        body: mail.body,
        in_reply_to: None,
        references: vec![],
        signature_id: None,
        signature_picked: false,
        remind_at: None,
        marks: vec![],
        draft: None,
    })
    .await?;
    Ok(())
}

/// Whether a message's sender counts as a person: People, not
/// Notifications.
#[frb(sync)]
pub fn message_by_person(account_id: i64, mailbox: String, uid: u32) -> Result<bool, EngineError> {
    Ok(reader()?.by_person(AccountId(account_id), &mailbox, uid)?)
}

/// Puts a sender's inbox mail in People ([people] true) or Notifications
/// from now on, what is there already included; None lets its headers
/// decide again.
pub fn set_sender_side(email: String, people: Option<bool>) -> Result<(), EngineError> {
    Ok(store()?.set_sender_side(&email, people)?)
}

/// Where a sender's inbox mail goes from now on, what is there already
/// included: [MailFolder::Inbox] or [MailFolder::Newsletters].
pub fn set_sender_zone(email: String, folder: MailFolder) -> Result<(), EngineError> {
    Ok(store()?.set_sender_zone(&email, folder.into())?)
}

/// What a Vault card is about.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VaultKind {
    Shipment,
    Bill,
    Flight,
    /// A table, a room, a ticket: a place on a day.
    Booking,
    /// Something you sold: to ship, on its way to the buyer, paid out.
    Sale,
    /// A date that costs you if missed: a renewal, an expiry, a fine.
    Deadline,
    /// A gift card or a voucher, with its code.
    Voucher,
    /// A payslip, a statement, a tax form: a file to keep.
    Document,
}

/// How far a parcel has come.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParcelStage {
    Ordered,
    Shipped,
    Transit,
    Delivered,
}

/// A card in the Vault, read on the device from the email it opens.
/// Only the fields of its kind are filled in.
#[derive(Debug, Clone)]
pub struct VaultCard {
    pub row: InboxRow,
    pub kind: VaultKind,
    /// What joins the emails about one thing; what Mark as paid keeps.
    pub key: String,
    /// The item, the bill, the place.
    pub title: String,
    /// The shop, the company billing, the airline.
    pub merchant: String,
    /// The merchant's VAT number, empty when unknown.
    pub vat_number: String,
    /// The day it arrives, is due, leaves or is booked for, "YYYY-MM-DD";
    /// empty when the email doesn't say.
    pub day: String,
    /// "HH:MM" on that day, or empty.
    pub time: String,
    pub carrier: String,
    pub tracking: String,
    pub stage: ParcelStage,
    pub last_scan: String,
    /// The carrier's page for the parcel, or empty: open it only when
    /// the person asks.
    pub track_url: String,
    /// In cents.
    pub amount: Option<i64>,
    /// ISO 4217, like "EUR".
    pub currency: String,
    pub paid: bool,
    pub number: String,
    pub origin: String,
    pub origin_city: String,
    pub destination: String,
    pub destination_city: String,
    pub arrives: String,
    pub seat: String,
    /// A train's coach, "4".
    pub coach: String,
    pub code: String,
    pub party: u32,
    /// A booking's "confirmed", "pending" or "cancelled"; a bill's
    /// "failed", "refund", "in", "renews" or "ending"; a parcel's
    /// "pickup"; a document's "payslip", "statement", "tax" or "contract".
    pub status: String,
    pub address: String,
    /// "train", "ferry", "bus", "stay", "parking", "car", "event",
    /// "table", or empty.
    pub travel: String,
    /// The day something ends, "YYYY-MM-DD": a check-out, a parking's or
    /// a car's return (its time in `arrives`), a pick-up point's last day,
    /// a plan's renewal or end, a voucher's expiry. Empty when none.
    pub until: String,
    /// "week", "month" or "year" for a plan; empty otherwise.
    pub period: String,
    /// The days a shop gives to send things back, 0 when unknown.
    pub return_days: u32,
    /// The day of the first email about it, "YYYY-MM-DD".
    pub first: String,
    /// The bill's PDF or the boarding pass, to fetch with [save_attachment].
    pub file: Option<u32>,
    pub file_name: String,
}

/// The Vault's cards, newest email first. [account] keeps one account's,
/// all when None.
pub fn vault_cards(account: Option<i64>) -> Result<Vec<VaultCard>, EngineError> {
    use piuma_core::vault::{Kind, Stage};
    let since = now_secs() - piuma_core::store::VAULT_SPAN;
    let store = store()?;
    Ok(store
        .vault_cards(account.map(AccountId), since)?
        .into_iter()
        .map(|(m, folder, c)| VaultCard {
            row: InboxRow {
                folder: folder.map(Into::into),
                ..inbox_row(&store, m)
            },
            kind: match c.kind {
                Kind::Shipment => VaultKind::Shipment,
                Kind::Bill => VaultKind::Bill,
                Kind::Flight => VaultKind::Flight,
                Kind::Booking => VaultKind::Booking,
                Kind::Sale => VaultKind::Sale,
                Kind::Deadline => VaultKind::Deadline,
                Kind::Voucher => VaultKind::Voucher,
                Kind::Document => VaultKind::Document,
            },
            key: c.key,
            title: c.title,
            merchant: c.merchant,
            vat_number: c.vat_number,
            day: c.day,
            time: c.time,
            carrier: c.carrier,
            tracking: c.tracking,
            track_url: c.track_url,
            stage: match c.stage {
                Stage::Ordered => ParcelStage::Ordered,
                Stage::Shipped => ParcelStage::Shipped,
                Stage::Transit => ParcelStage::Transit,
                Stage::Delivered => ParcelStage::Delivered,
            },
            last_scan: c.last_scan,
            amount: c.amount,
            currency: c.currency,
            paid: c.paid,
            number: c.number,
            origin: c.origin,
            origin_city: c.origin_city,
            destination: c.destination,
            destination_city: c.destination_city,
            arrives: c.arrives,
            seat: c.seat,
            coach: c.coach,
            code: c.code,
            party: c.party,
            status: c.status,
            address: c.address,
            travel: c.travel,
            until: c.until,
            period: c.period,
            return_days: c.return_days,
            first: c.first,
            file: c.file,
            file_name: c.file_name,
        })
        .collect())
}

/// Marks a bill paid, or not, by its card's key.
pub fn set_vault_paid(key: String, paid: bool) -> Result<(), EngineError> {
    Ok(store()?.set_paid(&key, paid, now_secs())?)
}

/// How far a message sent from a PEC mailbox has got.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PecStage {
    /// Accepted by the provider, waiting for every delivery.
    Accepted,
    /// In every certified recipient's mailbox.
    Delivered,
    /// Refused, or not delivered to someone.
    Failed,
}

/// A message sent from a PEC mailbox, with what its receipts say, for the
/// Vault.
#[derive(Debug, Clone)]
pub struct PecMessage {
    /// The receipt to open: the failure, else the newest one.
    pub row: InboxRow,
    pub subject: String,
    /// The certified recipients.
    pub recipients: Vec<String>,
    pub stage: PecStage,
    /// How many recipients have it.
    pub delivered: u32,
    /// When it was accepted, delivered to all, or failed; Unix seconds.
    pub stage_at: i64,
    /// Why it failed, in the provider's words; may be empty.
    pub reason: String,
    pub failed_to: String,
    /// The receipts worth keeping as proof, to save with
    /// [save_pec_receipts].
    pub proofs: Vec<u32>,
    /// The folder the proofs are in.
    pub proof_mailbox: String,
}

/// The messages sent from PEC mailboxes, newest receipt first. [account]
/// keeps one account's, all when None.
pub fn pec_messages(account: Option<i64>) -> Result<Vec<PecMessage>, EngineError> {
    use piuma_core::pec::Stage;
    let store = store()?;
    let mut out = Vec::new();
    for sent in store.pec_sent(account.map(AccountId))? {
        let Some((mailbox, uid)) = sent.proofs.last().cloned() else {
            continue;
        };
        let Some(m) = store.message(sent.account, &mailbox, uid)? else {
            continue;
        };
        out.push(PecMessage {
            row: inbox_row(&store, m),
            subject: sent.subject,
            recipients: sent.recipients,
            stage: match sent.stage {
                Stage::Accepted => PecStage::Accepted,
                Stage::Delivered => PecStage::Delivered,
                Stage::Failed => PecStage::Failed,
            },
            delivered: sent.delivered,
            stage_at: sent.stage_at,
            reason: sent.reason,
            failed_to: sent.failed_to,
            proofs: sent
                .proofs
                .iter()
                .filter(|(m, _)| *m == mailbox)
                .map(|(_, uid)| *uid)
                .collect(),
            proof_mailbox: mailbox,
        });
    }
    Ok(out)
}

/// Saves receipts whole (the provider's signed message, as `.eml`) in
/// `folder`, each under a name no other file there has, starting from
/// `name`. Returns the saved files' paths.
pub async fn save_pec_receipts(
    account_id: i64,
    mailbox: String,
    uids: Vec<u32>,
    name: String,
    folder: String,
) -> Result<Vec<String>, EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
    let store = engine.store.clone();
    let files = engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let mut files = Vec::new();
            for uid in uids {
                files.push(conn.raw(&store, id, &mailbox, uid).await?);
            }
            conn.close().await;
            Ok::<_, RemoteError>(files)
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    let mut paths = Vec::new();
    for data in files {
        let path = files::save_new(std::path::Path::new(&folder), &name, &data)
            .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
        paths.push(path.to_string_lossy().into_owned());
    }
    Ok(paths)
}

/// A file received with a message, for the Attachments board.
#[derive(Debug, Clone)]
pub struct AttachedFile {
    /// The message it came with, and the list that message is in.
    pub row: InboxRow,
    /// Where it is in the message, to fetch it with [save_attachment].
    pub part_id: u32,
    pub name: String,
    pub mime: String,
    pub size: u64,
    /// Why it deserves a word before it opens, from its name.
    pub risk: Option<FileRisk>,
}

/// Files kept on the Attachments board at most, newest first.
const BOARD_FILES: u32 = 2000;

/// The files received, newest first. [account] keeps one account's, all
/// when None.
pub fn attached_files(account: Option<i64>) -> Result<Vec<AttachedFile>, EngineError> {
    let store = store()?;
    Ok(store
        .files(account.map(AccountId), BOARD_FILES)?
        .into_iter()
        .map(|(m, folder, a)| AttachedFile {
            row: InboxRow {
                folder: folder.map(Into::into),
                ..inbox_row(&store, m)
            },
            part_id: a.part,
            risk: file_risk(&a.name),
            name: a.name,
            mime: a.mime,
            size: a.size,
        })
        .collect())
}

/// Files a sender's card lists under Attachments at most.
const SENDER_FILES: u32 = 200;

/// The files one address sent, newest first: a sender card's Attachments.
pub fn sender_files(email: String) -> Result<Vec<AttachedFile>, EngineError> {
    let query = Query::parse(&format!("from:{}", email.trim()));
    let store = store()?;
    store
        .search_files(&query, SENDER_FILES)?
        .into_iter()
        .filter(|(m, _)| m.from_email.eq_ignore_ascii_case(email.trim()))
        .map(|(m, a)| {
            Ok(AttachedFile {
                row: in_conversation(&store, inbox_row(&store, m))?,
                part_id: a.part,
                risk: file_risk(&a.name),
                name: a.name,
                mime: a.mime,
                size: a.size,
            })
        })
        .collect()
}

/// An address a sender writes from, for their card's Addresses.
pub struct SenderAddressRow {
    pub email: String,
    /// The account most of its emails arrived in.
    pub account_id: i64,
    pub emails: u32,
    /// A server vouched for it, and verified sender is on.
    pub verified: bool,
}

/// The addresses a sender writes from, most emails first.
pub fn sender_addresses(email: String) -> Result<Vec<SenderAddressRow>, EngineError> {
    let store = store()?;
    let shown = switch(&store, VERIFIED_SENDER)?;
    Ok(store
        .sender_addresses(&email)?
        .into_iter()
        .map(|a| SenderAddressRow {
            email: a.email,
            account_id: a.account.0,
            emails: a.emails,
            verified: shown && a.verified,
        })
        .collect())
}

/// Files fetched for previews at a time, so a full board doesn't open a
/// connection per card at once.
static THUMBS_AT_ONCE: tokio::sync::Semaphore = tokio::sync::Semaphore::const_new(2);

/// A small JPEG preview of an attached file for the Attachments board (a
/// picture, a PDF's first page, an office document's own preview),
/// fetched from the server the first time and kept. None for other files.
pub async fn attachment_thumb(
    account_id: i64,
    mailbox: String,
    uid: u32,
    part_id: u32,
) -> Result<Option<Vec<u8>>, EngineError> {
    use piuma_core::files::{self, ThumbKind};
    let engine = engine()?;
    let id = AccountId(account_id);
    let Some(file) = store()?.attachment(id, &mailbox, uid, part_id)? else {
        return Ok(None);
    };
    let Some(kind) = ThumbKind::of(&file.name, &file.mime) else {
        return Ok(None);
    };
    if file.size > kind.max_bytes() {
        return Ok(None);
    }
    let kept = || -> Result<_, EngineError> { Ok(store()?.thumb(id, &mailbox, uid, &file.name)?) };
    if let Some(kept) = kept()? {
        // Empty: the file was looked at and has no preview we can show.
        return Ok((!kept.is_empty()).then_some(kept));
    }
    let _turn = THUMBS_AT_ONCE
        .acquire()
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    // Made while this one waited its turn.
    if let Some(kept) = kept()? {
        return Ok((!kept.is_empty()).then_some(kept));
    }
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
    let store_ref = engine.store.clone();
    let mbox = mailbox.clone();
    let data = engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let data = conn.attachment(&store_ref, id, &mbox, uid, part_id).await?;
            conn.close().await;
            Ok::<_, RemoteError>(data)
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    let thumb = engine
        .runtime
        .spawn_blocking(move || files::thumbnail(&data, kind))
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    store()?.set_thumb(
        id,
        &mailbox,
        uid,
        &file.name,
        thumb.as_deref().unwrap_or_default(),
    )?;
    Ok(thumb)
}

/// What a rule looks at.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleField {
    Sender,
    Subject,
    Recipient,
    Body,
}

/// How a rule compares, ignoring case.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleOp {
    Contains,
    Is,
    StartsWith,
    NotContains,
}

/// What a rule does with a match.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleDo {
    /// Into `target`, one of the account's own folders.
    MoveTo,
    Archive,
    MarkRead,
    /// Puts the label whose keyword is `target` on.
    Label,
    /// "Move to Vault": into Archive, with its card always in the Vault.
    Vault,
}

/// A rule, as the person wrote it: "When the sender contains @studio.it,
/// move to Worksite".
#[derive(Debug, Clone)]
pub struct RuleInfo {
    /// 0 for a new rule.
    pub id: i64,
    /// The account whose mail it sorts; None for every account.
    pub account_id: Option<i64>,
    pub field: RuleField,
    pub op: RuleOp,
    pub value: String,
    pub action: RuleDo,
    /// The folder's server name, for a move; the label's keyword, for a
    /// label; empty otherwise.
    pub target: String,
    pub enabled: bool,
    /// When it last sorted something, in Unix seconds.
    pub last_run: Option<i64>,
    /// How many emails it has sorted.
    pub matched: u32,
}

fn rule_from(r: RuleInfo) -> Result<rules::Rule, EngineError> {
    let action = match r.action {
        RuleDo::MoveTo if r.target.is_empty() => {
            return Err(EngineError::new(ErrorKind::Other, "a move needs a folder"))
        }
        RuleDo::MoveTo => rules::Action::MoveTo(r.target),
        RuleDo::Archive => rules::Action::Archive,
        RuleDo::MarkRead => rules::Action::MarkRead,
        RuleDo::Label if r.target.is_empty() => {
            return Err(EngineError::new(
                ErrorKind::Other,
                "a label rule needs a label",
            ))
        }
        RuleDo::Label => rules::Action::Label(r.target),
        RuleDo::Vault => rules::Action::Vault,
    };
    Ok(rules::Rule {
        id: r.id,
        account: r.account_id.map(AccountId),
        field: match r.field {
            RuleField::Sender => rules::Field::Sender,
            RuleField::Subject => rules::Field::Subject,
            RuleField::Recipient => rules::Field::Recipient,
            RuleField::Body => rules::Field::Body,
        },
        op: match r.op {
            RuleOp::Contains => rules::Op::Contains,
            RuleOp::Is => rules::Op::Is,
            RuleOp::StartsWith => rules::Op::StartsWith,
            RuleOp::NotContains => rules::Op::NotContains,
        },
        value: r.value,
        action,
        enabled: r.enabled,
        last_run: r.last_run,
        matched: r.matched,
    })
}

fn rule_info(r: rules::Rule) -> RuleInfo {
    RuleInfo {
        id: r.id,
        account_id: r.account.map(|a| a.0),
        field: match r.field {
            rules::Field::Sender => RuleField::Sender,
            rules::Field::Subject => RuleField::Subject,
            rules::Field::Recipient => RuleField::Recipient,
            rules::Field::Body => RuleField::Body,
        },
        op: match r.op {
            rules::Op::Contains => RuleOp::Contains,
            rules::Op::Is => RuleOp::Is,
            rules::Op::StartsWith => RuleOp::StartsWith,
            rules::Op::NotContains => RuleOp::NotContains,
        },
        value: r.value,
        target: r.action.target().to_string(),
        action: match r.action {
            rules::Action::MoveTo(_) => RuleDo::MoveTo,
            rules::Action::Archive => RuleDo::Archive,
            rules::Action::MarkRead => RuleDo::MarkRead,
            rules::Action::Label(_) => RuleDo::Label,
            rules::Action::Vault => RuleDo::Vault,
        },
        enabled: r.enabled,
        last_run: r.last_run,
        matched: r.matched,
    }
}

/// Every rule, in the order they are tried: the first that matches wins.
pub fn rules() -> Result<Vec<RuleInfo>, EngineError> {
    Ok(store()?.rules()?.into_iter().map(rule_info).collect())
}

/// Adds a rule (id 0) or changes one. It sorts new inbox mail from now
/// on; returns its id.
pub fn save_rule(rule: RuleInfo) -> Result<i64, EngineError> {
    let rule = rule_from(rule)?;
    Ok(store()?.save_rule(&rule)?)
}

pub fn delete_rule(id: i64) -> Result<(), EngineError> {
    Ok(store()?.delete_rule(id)?)
}

pub fn set_rule_enabled(id: i64, enabled: bool) -> Result<(), EngineError> {
    Ok(store()?.set_rule_enabled(id, enabled)?)
}

/// The inbox mail already here that `rule` would sort, newest first, at
/// most `limit`: for "Applies to N existing emails".
pub fn rule_preview(rule: RuleInfo, limit: u32) -> Result<Vec<InboxRow>, EngineError> {
    let rule = rule_from(rule)?;
    let store = store()?;
    Ok(rules::existing(&store, &rule, limit as usize)?
        .into_iter()
        .map(|m| inbox_row(&store, m))
        .collect())
}

/// "Move to Vault" on mail already here: each keeps a card in the Vault
/// once archived. Returns the ones that can be followed there (those
/// with a Message-ID); archive only those.
pub fn pin_to_vault(messages: Vec<MessageRef>) -> Result<Vec<MessageRef>, EngineError> {
    let store = store()?;
    let now = now_secs();
    let mut pinned = Vec::new();
    for m in messages {
        if store.pin_to_vault(AccountId(m.account_id), &m.mailbox, m.uid, now)? {
            pinned.push(m);
        }
    }
    Ok(pinned)
}

/// Notes who was moved to `target` by hand, for the rule Rules & folders
/// suggests.
fn log_moves(messages: &[MessageRef], target: &str) -> Result<(), EngineError> {
    let store = store()?;
    let mut by_account: std::collections::BTreeMap<i64, Vec<(String, String)>> = Default::default();
    for m in messages {
        if let Some(found) = store.message(AccountId(m.account_id), &m.mailbox, m.uid)? {
            by_account
                .entry(m.account_id)
                .or_default()
                .push((found.from_email, found.from_name));
        }
    }
    let now = now_secs();
    for (account, senders) in by_account {
        store.log_moves(AccountId(account), &senders, target, now)?;
    }
    Ok(())
}

/// "You often move emails from Ferrovia Rapida to Travel. Create a rule?"
#[derive(Debug, Clone)]
pub struct RuleSuggestion {
    pub account_id: i64,
    /// The sender's address, lowercase.
    pub sender: String,
    pub name: String,
    /// The folder's server name.
    pub target: String,
    /// How many times in the last month.
    pub moves: u32,
}

/// The rule worth suggesting now, if any.
pub fn rule_suggestion() -> Result<Option<RuleSuggestion>, EngineError> {
    let now = now_secs();
    Ok(rules::suggestion(&*store()?, now)?.map(|m| RuleSuggestion {
        account_id: m.account.0,
        sender: m.sender,
        name: m.name,
        target: m.target,
        moves: m.moves,
    }))
}

/// Not now: the same suggestion doesn't come back.
pub fn dismiss_rule_suggestion(suggestion: RuleSuggestion) -> Result<(), EngineError> {
    let m = piuma_core::store::FrequentMove {
        account: AccountId(suggestion.account_id),
        sender: suggestion.sender,
        name: suggestion.name,
        target: suggestion.target,
        moves: suggestion.moves,
    };
    Ok(rules::dismiss_suggestion(&*store()?, &m)?)
}

/// What an invite's calendar asks for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InviteMethod {
    /// An invite, or a change to one: it can be answered.
    Request,
    /// The event is off.
    Cancel,
    /// Someone answered an invite you sent.
    Reply,
    /// An event to look at, with nothing to answer.
    Publish,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InviteAnswer {
    Accepted,
    Tentative,
    Declined,
}

#[derive(Debug, Clone)]
pub struct InvitePerson {
    pub name: String,
    pub email: String,
    pub answer: Option<InviteAnswer>,
}

/// A calendar invite, as the card in the reader shows it.
#[derive(Debug, Clone)]
pub struct InviteInfo {
    pub method: InviteMethod,
    /// The event's UID, the same in your calendar once accepted.
    pub uid: String,
    pub summary: String,
    pub location: String,
    /// Unix seconds. With `floating`, the wall-clock time where the
    /// person is, written as if it were UTC.
    pub start: i64,
    pub end: i64,
    pub all_day: bool,
    pub floating: bool,
    /// It happens more than once; the card shows the first time.
    pub repeats: bool,
    pub organizer: Option<InvitePerson>,
    pub attendees: Vec<InvitePerson>,
    /// How you answered: here, or as the invite says.
    pub answer: Option<InviteAnswer>,
    /// You sent it: there is nothing to answer.
    pub yours: bool,
}

fn answer_info(a: invite::Answer) -> InviteAnswer {
    match a {
        invite::Answer::Accepted => InviteAnswer::Accepted,
        invite::Answer::Tentative => InviteAnswer::Tentative,
        invite::Answer::Declined => InviteAnswer::Declined,
    }
}

fn person_info(p: invite::Person) -> InvitePerson {
    InvitePerson {
        name: p.name,
        email: p.email,
        answer: p.answer.map(answer_info),
    }
}

fn invite_info(store: &Store, id: AccountId, i: invite::Invite) -> Result<InviteInfo, EngineError> {
    let me = store.account(id)?.map(|a| a.email).unwrap_or_default();
    let answered_here = store
        .invite_answer(id, &i.uid)?
        .and_then(|(a, _)| invite::Answer::from_partstat(&a));
    let answer = answered_here.or_else(|| i.attendee(&me).and_then(|p| p.answer));
    let yours = i
        .organizer
        .as_ref()
        .is_some_and(|o| o.email.eq_ignore_ascii_case(&me));
    Ok(InviteInfo {
        method: match i.method {
            invite::Method::Request => InviteMethod::Request,
            invite::Method::Cancel => InviteMethod::Cancel,
            invite::Method::Reply => InviteMethod::Reply,
            invite::Method::Publish => InviteMethod::Publish,
        },
        uid: i.uid,
        summary: i.summary,
        location: i.location,
        start: i.start,
        end: i.end,
        all_day: i.all_day,
        floating: i.floating,
        repeats: i.repeats,
        organizer: i.organizer.map(person_info),
        attendees: i.attendees.into_iter().map(person_info).collect(),
        answer: answer.map(answer_info),
        yours,
    })
}

/// Answers the invite a message carries: the organizer gets the reply
/// their calendar reads, with `subject` and `text` for people, and the
/// answer is kept here. Offline, it waits in the outbox.
pub async fn answer_invite(
    account_id: i64,
    mailbox: String,
    uid: u32,
    answer: InviteAnswer,
    subject: String,
    text: String,
) -> Result<InviteSent, EngineError> {
    let id = AccountId(account_id);
    let body = full_body(id, mailbox.clone(), uid).await?;
    let ics = body.calendar.ok_or(EngineError::new(
        ErrorKind::Other,
        "no invite in this message",
    ))?;
    let event = invite::parse(&ics).ok_or(EngineError::new(
        ErrorKind::Other,
        "the invite can't be read",
    ))?;
    let organizer = event.organizer.clone().ok_or(EngineError::new(
        ErrorKind::Other,
        "the invite has no organizer",
    ))?;
    let (account, password) = signed_in(id)?;
    let answer = match answer {
        InviteAnswer::Accepted => invite::Answer::Accepted,
        InviteAnswer::Tentative => invite::Answer::Tentative,
        InviteAnswer::Declined => invite::Answer::Declined,
    };
    let reply = invite::reply(
        &ics,
        &account.sender_name,
        &account.email,
        answer,
        now_secs(),
    )
    .ok_or(EngineError::new(
        ErrorKind::Other,
        "the invite can't be answered",
    ))?;
    let replying_to = store()?.message(id, &mailbox, uid)?.map(|m| m.reply);
    let to = if organizer.name.trim().is_empty() {
        organizer.email.clone()
    } else {
        format!("{} <{}>", organizer.name.trim(), organizer.email)
    };
    let draft = Draft {
        from_name: account.sender_name.clone(),
        from_email: account.email.clone(),
        to: vec![to],
        subject,
        body: text,
        in_reply_to: replying_to
            .as_ref()
            .map(|r| r.message_id.clone())
            .filter(|m| !m.is_empty()),
        references: replying_to
            .map(|r| {
                r.references
                    .split_whitespace()
                    .map(str::to_owned)
                    .chain(Some(r.message_id).filter(|m| !m.is_empty()))
                    .collect()
            })
            .unwrap_or_default(),
        calendar: Some(reply),
        ..Draft::default()
    };
    let email = account.email.clone();
    let sent = send_draft(account, password, draft, None).await?;
    store()?.set_invite_answer(
        id,
        &event.uid,
        answer.partstat(),
        event.sequence,
        now_secs(),
    )?;
    let added_to = match answer {
        invite::Answer::Declined => None,
        _ => super::calendars::add_invite(&ics, &email, answer).await,
    };
    Ok(InviteSent {
        queued: sent.queued,
        added_to,
    })
}

/// What answering an invite did.
#[derive(Debug, Clone)]
pub struct InviteSent {
    /// The reply waits in the outbox, to go once the connection is back.
    pub queued: bool,
    /// The calendar the event was put in, if any.
    pub added_to: Option<String>,
}
