//! JMAP (RFC 8620, RFC 8621): the same offline-first mirror as IMAP, over
//! plain HTTPS and JSON.
//!
//! JMAP names folders and messages with strings. The cache keeps the IMAP
//! shape so the app draws every account the same way: the inbox is cached
//! as "INBOX", other folders under their JMAP id, and each message gets a
//! local number per folder (see `Store::add_jmap_ids`).

use std::collections::{HashMap, HashSet};
use std::fmt;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use mail_parser::MessageParser;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::groups;
use crate::imap::{
    attachment_data, clean_preview, parse_body, FolderRole, SyncReport, WatchEvent, FILES_LOOK,
    INBOX_BODIES, INBOX_BYTES, NEWSLETTER_BODIES, NEWSLETTER_BYTES, VAULT_BODIES, VAULT_BYTES,
    VAULT_LOOK,
};
use crate::model::{Account, AccountId, AccountKind, Flags, Folder, MessageSummary, ReplyInfo};
use crate::newsletter;
use crate::notify::{self, Arrival};
use crate::store::{Attachment, Body, MailboxState, Store, StoreError};

const USING: [&str; 3] = [
    "urn:ietf:params:jmap:core",
    "urn:ietf:params:jmap:mail",
    "urn:ietf:params:jmap:submission",
];
const MAIL: &str = "urn:ietf:params:jmap:mail";
const CORE: &str = "urn:ietf:params:jmap:core";
/// The away message (RFC 8621 section 8).
pub const VACATION: &str = "urn:ietf:params:jmap:vacationresponse";

/// Messages asked for per round trip, unless the server allows fewer.
const BATCH: usize = 250;
/// Ids asked for per Email/query page.
const QUERY_PAGE: usize = 1000;
/// The most pages one Email/query may take, so a lying `total` cannot
/// page forever: past it, the ids gathered so far stand.
const QUERY_PAGES_MAX: usize = 1000;
/// The most JSON a server response may hold: beyond this the response
/// is a protocol failure, not something to keep buffering.
const RESPONSE_MAX: usize = 32 * 1024 * 1024;
/// How long to wait for a push before looking anyway.
pub const POLL_EVERY: Duration = Duration::from_secs(5 * 60);

const SUMMARY_PROPERTIES: [&str; 18] = [
    "id",
    "blobId",
    "keywords",
    "from",
    "to",
    "cc",
    "replyTo",
    "subject",
    "preview",
    "receivedAt",
    "messageId",
    "references",
    "inReplyTo",
    "header:List-Id",
    "header:List-Unsubscribe",
    "header:List-Unsubscribe-Post",
    "header:List-Post",
    "header:Precedence",
];
/// What tells a newsletter, for mail cached before it was asked for.
const LIST_PROPERTIES: [&str; 9] = [
    "id",
    "from",
    "to",
    "cc",
    "header:List-Id",
    "header:List-Unsubscribe",
    "header:List-Unsubscribe-Post",
    "header:List-Post",
    "header:Precedence",
];
/// Asked for alongside, to tell people from machines.
const AUTO_SUBMITTED: &str = "header:Auto-Submitted";
/// The mark mailing services leave, asked for alongside too.
const FEEDBACK_ID: &str = "header:Feedback-ID";

#[derive(Clone)]
pub struct JmapConfig {
    /// Where the session object lives, e.g. https://example.com/.well-known/jmap
    pub session_url: String,
    /// Login name. Empty means `password` is an API token (Bearer).
    pub username: String,
    pub password: String,
}

impl fmt::Debug for JmapConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("JmapConfig")
            .field("session_url", &self.session_url)
            .field("username", &self.username)
            .finish_non_exhaustive()
    }
}

impl JmapConfig {
    /// The JMAP settings of an account, or None for other accounts.
    pub fn for_account(account: &Account, password: &str) -> Option<Self> {
        match &account.kind {
            AccountKind::Jmap {
                session_url,
                username,
            } => Some(JmapConfig {
                session_url: session_url.clone(),
                username: username.clone(),
                password: password.to_owned(),
            }),
            AccountKind::Imap { .. } => None,
        }
    }

    fn authorization(&self) -> String {
        use base64::Engine;
        if self.username.is_empty() {
            format!("Bearer {}", self.password)
        } else {
            let pair = format!("{}:{}", self.username, self.password);
            format!(
                "Basic {}",
                base64::engine::general_purpose::STANDARD.encode(pair)
            )
        }
    }
}

/// Where a domain publishes its JMAP session (RFC 8620 section 2.2).
pub fn well_known(email: &str) -> Option<String> {
    let domain = email.rsplit_once('@')?.1.trim();
    (!domain.is_empty()).then(|| format!("https://{domain}/.well-known/jmap"))
}

/// Whether the address's domain serves JMAP; returns its session URL.
pub async fn discover(email: &str) -> Option<String> {
    discover_at(&well_known(email)?).await
}

/// Looks for a JMAP session at `url`, following redirects. Without a
/// login, a JMAP server answers 401, or the session itself.
pub async fn discover_at(url: &str) -> Option<String> {
    let http = crate::tls::http_client()
        .timeout(Duration::from_secs(8))
        .build()
        .ok()?;
    let response = http.get(url).send().await.ok()?;
    let found = response.url().to_string();
    match response.status() {
        reqwest::StatusCode::UNAUTHORIZED => {
            let challenge = response
                .headers()
                .get(reqwest::header::WWW_AUTHENTICATE)
                .and_then(|v| v.to_str().ok())
                .unwrap_or_default()
                .to_ascii_lowercase();
            // Only a password login is offered here, not tokens alone.
            challenge.contains("basic").then_some(found)
        }
        s if s.is_success() => {
            let bytes = response.bytes().await.ok()?;
            let session: Value = serde_json::from_slice(&bytes).ok()?;
            session.get("apiUrl").is_some().then_some(found)
        }
        _ => None,
    }
}

#[derive(Debug, thiserror::Error)]
pub enum JmapError {
    #[error("could not reach {url}: {source}")]
    Connect { url: String, source: reqwest::Error },
    #[error("the server rejected the user name or password")]
    Auth,
    #[error("this account does not offer mail over JMAP")]
    NoMail,
    #[error("the message is no longer on the server")]
    Gone,
    #[error("the account has no folder for this")]
    NoFolder,
    #[error("JMAP: {0}")]
    Protocol(String),
    #[error(transparent)]
    Store(#[from] StoreError),
}

impl JmapError {
    /// The server could not be reached, rather than refused.
    pub fn is_offline(&self) -> bool {
        matches!(self, JmapError::Connect { .. })
    }
}

pub type Result<T> = std::result::Result<T, JmapError>;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Session {
    api_url: String,
    download_url: String,
    upload_url: String,
    #[serde(default)]
    event_source_url: Option<String>,
    #[serde(default)]
    primary_accounts: HashMap<String, String>,
    #[serde(default)]
    capabilities: HashMap<String, Value>,
}

/// A JMAP folder.
#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Mailbox {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub parent_id: Option<String>,
    #[serde(default)]
    pub unread_emails: u32,
    #[serde(default)]
    pub total_emails: u32,
    #[serde(default)]
    pub sort_order: u32,
}

impl Mailbox {
    /// The name the cache knows it by.
    pub fn local(&self) -> String {
        if self.role.as_deref() == Some("inbox") {
            "INBOX".into()
        } else {
            self.id.clone()
        }
    }
}

/// The away message of a JMAP account (`VacationResponse`). Dates are
/// UTC, as "2026-10-27T00:00:00Z"; the reply goes out from `from` until
/// before `to`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Vacation {
    pub enabled: bool,
    pub from: Option<String>,
    pub to: Option<String>,
    pub subject: String,
    pub text: String,
}

/// A logged-in JMAP account.
pub struct Client {
    http: reqwest::Client,
    config: JmapConfig,
    authorization: String,
    api_url: String,
    download_url: String,
    upload_url: String,
    event_source_url: Option<String>,
    account_id: String,
    max_get: usize,
    mailboxes: Vec<Mailbox>,
    /// What the session says the server can do.
    capabilities: HashSet<String>,
}

impl Client {
    /// Reads the session object, which is also the login check.
    pub async fn open(cfg: &JmapConfig) -> Result<Self> {
        let http = crate::tls::http_client()
            .timeout(Duration::from_secs(60))
            .build()
            .map_err(|e| JmapError::Protocol(e.to_string()))?;
        let authorization = cfg.authorization();
        let response = http
            .get(&cfg.session_url)
            .header(reqwest::header::AUTHORIZATION, &authorization)
            .send()
            .await
            .map_err(|source| JmapError::Connect {
                url: cfg.session_url.clone(),
                source,
            })?;
        let session: Session = read_json(response).await?;
        let account_id = session
            .primary_accounts
            .get(MAIL)
            .cloned()
            .ok_or(JmapError::NoMail)?;
        let max_get = session
            .capabilities
            .get(CORE)
            .and_then(|c| c.get("maxObjectsInGet"))
            .and_then(Value::as_u64)
            .map_or(BATCH, |m| (m as usize).clamp(1, BATCH));
        let capabilities = session.capabilities.keys().cloned().collect();
        let base = url::Url::parse(&cfg.session_url).ok();
        // Servers may give these relative to the session.
        let absolute = |u: String| match &base {
            Some(b) => b.join(&u).map(|j| j.to_string()).unwrap_or(u),
            None => u,
        };
        // A template's braces must survive joining.
        let template = |u: String| absolute(u).replace("%7B", "{").replace("%7D", "}");
        let mut client = Client {
            http,
            config: cfg.clone(),
            authorization,
            api_url: absolute(session.api_url),
            download_url: template(session.download_url),
            upload_url: template(session.upload_url),
            event_source_url: session.event_source_url.map(template),
            account_id,
            max_get,
            mailboxes: Vec::new(),
            capabilities,
        };
        client.refresh_mailboxes().await?;
        Ok(client)
    }

    /// Whether the server keeps an away message (RFC 8621 section 8).
    pub fn has_vacation(&self) -> bool {
        self.capabilities.contains(VACATION)
    }

    /// The account's away message, as the server keeps it.
    pub async fn vacation(&self) -> Result<Vacation> {
        let [got] = self
            .call_using(
                &[CORE, VACATION],
                [(
                    "VacationResponse/get",
                    json!({ "accountId": self.account_id, "ids": ["singleton"] }),
                )],
            )
            .await?;
        let found = got["list"]
            .as_array()
            .and_then(|l| l.first())
            .cloned()
            .unwrap_or(Value::Null);
        Ok(Vacation {
            enabled: found["isEnabled"].as_bool().unwrap_or(false),
            from: found["fromDate"].as_str().map(str::to_owned),
            to: found["toDate"].as_str().map(str::to_owned),
            subject: found["subject"].as_str().unwrap_or_default().to_owned(),
            text: found["textBody"].as_str().unwrap_or_default().to_owned(),
        })
    }

    /// Replaces the account's away message. The server answers each
    /// sender once in a while, and not mailing lists, by its own rules.
    pub async fn set_vacation(&self, vacation: &Vacation) -> Result<()> {
        let [got] = self
            .call_using(
                &[CORE, VACATION],
                [(
                    "VacationResponse/set",
                    json!({ "accountId": self.account_id, "update": { "singleton": {
                        "isEnabled": vacation.enabled,
                        "fromDate": vacation.from,
                        "toDate": vacation.to,
                        "subject": vacation.subject,
                        "textBody": vacation.text,
                        "htmlBody": null,
                    } } }),
                )],
            )
            .await?;
        if got["updated"].get("singleton").is_none() {
            return Err(not_done(&got, "notUpdated"));
        }
        Ok(())
    }

    /// The account's folders, as last read.
    pub fn mailboxes(&self) -> &[Mailbox] {
        &self.mailboxes
    }

    /// Reads the folder list again.
    pub async fn refresh_mailboxes(&mut self) -> Result<()> {
        let [got] = self
            .call([(
                "Mailbox/get",
                json!({ "accountId": self.account_id, "ids": null,
                        "properties": ["id", "name", "role", "parentId", "unreadEmails", "totalEmails", "sortOrder"] }),
            )])
            .await?;
        self.mailboxes = serde_json::from_value(got["list"].clone())
            .map_err(|e| JmapError::Protocol(e.to_string()))?;
        Ok(())
    }

    /// The folder with a job, when the account has one.
    pub fn find_folder(&self, role: FolderRole) -> Option<&Mailbox> {
        find_role(&self.mailboxes, role)
    }

    /// The folder for a role, made if the account has none. Returns its
    /// local name. The spam folder is never made: without one, this fails.
    pub async fn folder(&mut self, role: FolderRole) -> Result<String> {
        if let Some(m) = self.find_folder(role) {
            return Ok(m.local());
        }
        if role == FolderRole::Junk {
            return Err(JmapError::NoFolder);
        }
        let [created] = self
            .call([(
                "Mailbox/set",
                json!({ "accountId": self.account_id, "create": { "new": {
                    "name": role_label(role), "role": role_name(role) } } }),
            )])
            .await?;
        let id = created["created"]["new"]["id"]
            .as_str()
            .ok_or_else(|| not_done(&created, "notCreated"))?
            .to_owned();
        self.mailboxes.push(Mailbox {
            id: id.clone(),
            name: role_label(role).into(),
            role: Some(role_name(role).into()),
            ..Mailbox::default()
        });
        Ok(id)
    }

    /// Makes a folder of the account's own, at the top, and lists it at
    /// once. Returns its local name.
    pub async fn create_folder(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        name: &str,
    ) -> Result<String> {
        let [created] = self
            .call([(
                "Mailbox/set",
                json!({ "accountId": self.account_id, "create": { "new": {
                    "name": name.trim(), "parentId": null } } }),
            )])
            .await?;
        let id = created["created"]["new"]["id"]
            .as_str()
            .ok_or_else(|| not_done(&created, "notCreated"))?
            .to_owned();
        self.mailboxes.push(Mailbox {
            id: id.clone(),
            name: name.trim().to_owned(),
            ..Mailbox::default()
        });
        lock(store).set_account_folders(account, &own_folders(&self.mailboxes))?;
        Ok(id)
    }

    /// The JMAP id of a cached folder.
    fn remote(&self, local: &str) -> Result<String> {
        self.mailboxes
            .iter()
            .find(|m| m.local() == local)
            .map(|m| m.id.clone())
            .ok_or_else(|| JmapError::Protocol(format!("no folder {local}")))
    }

    /// Brings the local copy of one folder in line with the server, in the
    /// same three steps as IMAP. `progress` gets (downloaded, to download).
    pub async fn sync_mailbox(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        mut progress: impl FnMut(usize, usize),
    ) -> Result<SyncReport> {
        let mut report = SyncReport::default();
        let remote = self.remote(mailbox)?;
        let (prior, local) = {
            let store = lock(store);
            (
                store.mailbox_state(account, mailbox)?,
                store.jmap_ids(account, mailbox)?,
            )
        };
        let server = self.query_ids(&remote).await?;
        let on_server: HashSet<&String> = server.iter().collect();

        // 1. Forget what the server no longer has.
        let gone: Vec<u32> = local
            .iter()
            .filter(|(id, _)| !on_server.contains(id))
            .map(|(_, uid)| *uid)
            .collect();
        if !gone.is_empty() {
            lock(store).remove_messages(account, mailbox, &gone)?;
            report.removed = gone.len();
        }

        // 2. Download what is new; the query is newest first.
        let missing: Vec<String> = server
            .iter()
            .filter(|id| !local.contains_key(*id))
            .cloned()
            .collect();
        let news = prior.is_some();
        for batch in missing.chunks(self.max_get) {
            let emails = self.get_emails(batch, &SUMMARY_PROPERTIES).await?;
            let ids: Vec<String> = emails.iter().filter_map(email_id).collect();
            let uids = lock(store).add_jmap_ids(account, mailbox, &ids)?;
            let numbered: HashMap<&str, u32> = ids.iter().map(String::as_str).zip(uids).collect();
            let found: Vec<(MessageSummary, bool)> = emails
                .iter()
                .filter_map(|e| {
                    let uid = *numbered.get(e["id"].as_str()?)?;
                    Some((summary(e, account, mailbox, uid), automated(e)))
                })
                .collect();
            let summaries: Vec<MessageSummary> = found.iter().map(|(s, _)| s.clone()).collect();
            lock(store).upsert_messages(&summaries)?;
            let labels: Vec<(u32, Vec<String>)> = emails
                .iter()
                .filter_map(|e| Some((*numbered.get(e["id"].as_str()?)?, keywords(e))))
                .collect();
            lock(store).set_server_labels(account, mailbox, &labels)?;
            report.added += summaries.len();
            if news {
                report.arrived.extend(
                    found
                        .into_iter()
                        .map(|(summary, automated)| Arrival { summary, automated }),
                );
            }
            progress(report.added, missing.len());
        }

        // 3. Refresh flags of what we already had.
        let kept: Vec<(String, u32)> = local
            .into_iter()
            .filter(|(id, _)| on_server.contains(id))
            .collect();
        let mut changes = Vec::new();
        let mut labels = Vec::new();
        for batch in kept.chunks(self.max_get) {
            let ids: Vec<String> = batch.iter().map(|(id, _)| id.clone()).collect();
            let uids: HashMap<&str, u32> =
                batch.iter().map(|(id, uid)| (id.as_str(), *uid)).collect();
            for e in self.get_emails(&ids, &["id", "keywords"]).await? {
                if let Some(uid) = e["id"].as_str().and_then(|id| uids.get(id)) {
                    changes.push((*uid, flags(&e)));
                    labels.push((*uid, keywords(&e)));
                }
            }
        }
        report.flags_changed = lock(store).update_flags(account, mailbox, &changes)?;
        lock(store).set_server_labels(account, mailbox, &labels)?;

        // 4. Inbox mail cached before the list headers were read: read them
        // now, so newsletters move to their own list.
        if mailbox == "INBOX" {
            let unchecked = lock(store).unchecked_lists(account, mailbox, QUERY_PAGE as u32)?;
            for batch in self
                .named(store, account, mailbox, &unchecked)?
                .chunks(self.max_get)
            {
                let ids: Vec<String> = batch.iter().map(|(_, id)| id.clone()).collect();
                let emails = self.get_emails(&ids, &LIST_PROPERTIES).await?;
                let recipients: Vec<(u32, String)> = batch
                    .iter()
                    .filter_map(|(uid, id)| {
                        let e = emails.iter().find(|e| e["id"].as_str() == Some(id))?;
                        Some((*uid, groups::recipients_json(e)))
                    })
                    .collect();
                lock(store).set_recipients(account, mailbox, &recipients)?;
                let lists: Vec<(u32, crate::model::ListInfo)> = batch
                    .iter()
                    .map(|(uid, id)| {
                        let list = emails
                            .iter()
                            .find(|e| e["id"].as_str() == Some(id))
                            .and_then(headers)
                            .map(|m| newsletter::list_info(&m))
                            .unwrap_or_default();
                        (*uid, list)
                    })
                    .collect();
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
            self.fetch_bodies(store, account, mailbox, &wanted, NEWSLETTER_BYTES)
                .await?;
        }

        // 6. Mail whose subject sounds like a parcel, a bill or a trip,
        // whole, for the Vault's cards.
        let now = crate::pending::now();
        let wanted = lock(store).vault_unchecked(account, mailbox, now, VAULT_LOOK)?;
        for batch in wanted.chunks(VAULT_BODIES) {
            let fetched = self
                .fetch_bodies(store, account, mailbox, batch, VAULT_BYTES)
                .await?;
            let skipped: Vec<u32> = batch
                .iter()
                .filter(|u| !fetched.contains(u))
                .copied()
                .collect();
            lock(store).skip_vault(account, mailbox, &skipped)?;
            report.carded += fetched.len();
        }

        // 7. What files each message carries, from the server's list of
        // its parts, for the Attachments board.
        let unlisted = lock(store).files_unchecked(account, mailbox, FILES_LOOK)?;
        for batch in self
            .named(store, account, mailbox, &unlisted)?
            .chunks(self.max_get)
        {
            let ids: Vec<String> = batch.iter().map(|(_, id)| id.clone()).collect();
            let emails = self.get_emails(&ids, &["id", "attachments"]).await?;
            // What the server no longer answers for has no files to list.
            let listed: Vec<(u32, Vec<Attachment>)> = batch
                .iter()
                .map(|(uid, id)| {
                    let files = emails
                        .iter()
                        .find(|e| e["id"].as_str() == Some(id))
                        .map(|e| listed_files(&e["attachments"]))
                        .unwrap_or_default();
                    (*uid, files)
                })
                .collect();
            report.listed += listed.iter().filter(|(_, files)| !files.is_empty()).count();
            lock(store).set_listed_files(account, mailbox, &listed)?;
        }

        // 7b. The newest Inbox mail whole, so opening it shows the text
        // at once instead of "Loading…". After 7, so its files keep the
        // server's outline.
        if mailbox == "INBOX" {
            let wanted = lock(store).inbox_without_body(account, mailbox, INBOX_BODIES)?;
            self.fetch_bodies(store, account, mailbox, &wanted, INBOX_BYTES)
                .await?;
        }

        lock(store).set_mailbox_state(
            account,
            mailbox,
            MailboxState {
                uid_validity: 1,
                highest_modseq: None,
            },
        )?;
        Ok(report)
    }

    /// Finds Sent, Archive and Drafts, remembers them, and brings them up
    /// to date.
    pub async fn sync_folders(&mut self, store: &Mutex<Store>, account: AccountId) -> Result<()> {
        self.refresh_mailboxes().await?;
        for (role, folder) in [
            (FolderRole::Sent, Folder::Sent),
            (FolderRole::Archive, Folder::Archive),
            (FolderRole::Drafts, Folder::Drafts),
            (FolderRole::Snoozed, Folder::Snoozed),
        ] {
            let Some(name) = self.find_folder(role).map(Mailbox::local) else {
                continue;
            };
            lock(store).set_folder_role(account, folder, &name)?;
            self.sync_mailbox(store, account, &name, |_, _| {}).await?;
        }
        // Report spam moves mail to the junk role; offered only when found.
        let junk = self.find_folder(FolderRole::Junk).map(Mailbox::local);
        lock(store).set_junk_mailbox(account, junk.as_deref())?;
        lock(store).set_account_folders(account, &own_folders(&self.mailboxes))?;
        Ok(())
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
        let body = parse_body(&self.raw(store, account, mailbox, uid).await?);
        lock(store).set_full_body(account, mailbox, uid, &body)?;
        Ok(body)
    }

    /// The content of one attachment, fetched from the server.
    pub async fn attachment(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        part: u32,
    ) -> Result<Vec<u8>> {
        let raw = self.raw(store, account, mailbox, uid).await?;
        attachment_data(&raw, part).ok_or(JmapError::Gone)
    }

    /// One whole message as the server keeps it.
    pub async fn raw(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<Vec<u8>> {
        let id = self.email(store, account, mailbox, uid)?;
        let emails = self.get_emails(&[id], &["id", "blobId"]).await?;
        let blob = emails
            .first()
            .and_then(|e| e["blobId"].as_str())
            .ok_or(JmapError::Gone)?
            .to_owned();
        self.download(&blob).await
    }

    /// Marks messages of one folder read or unread on the server.
    pub async fn set_seen(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        seen: bool,
    ) -> Result<()> {
        let patch = json!({ "keywords/$seen": if seen { json!(true) } else { Value::Null } });
        self.update(store, account, mailbox, uids, patch).await
    }

    /// Puts a label's keyword on messages of one folder, or takes it off.
    pub async fn set_keyword(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        keyword: &str,
        add: bool,
    ) -> Result<()> {
        let patch =
            json!({ format!("keywords/{keyword}"): if add { json!(true) } else { Value::Null } });
        self.update(store, account, mailbox, uids, patch).await
    }

    /// Tells the server's spam filter what the person said: `$junk` on
    /// spam, `$notjunk` on mail that isn't (RFC 8621), each taking the
    /// other off.
    pub async fn mark_junk(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        junk: bool,
    ) -> Result<()> {
        let (on, off) = if junk {
            ("$junk", "$notjunk")
        } else {
            ("$notjunk", "$junk")
        };
        let patch =
            json!({ format!("keywords/{on}"): true, format!("keywords/{off}"): Value::Null });
        self.update(store, account, mailbox, uids, patch).await
    }

    /// Moves messages of one folder to the folder for `role` and forgets
    /// them locally. Returns the folder they went to.
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

    /// Puts messages away in Snoozed. When they come back is kept on this
    /// device only: JMAP has no place for it every client reads.
    pub async fn snooze(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<()> {
        let target = self.folder(FolderRole::Snoozed).await?;
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
        self.sync_mailbox(store, account, &target, |_, _| {})
            .await?;
        Ok(())
    }

    /// Brings snoozed messages back to the inbox, unread.
    pub async fn wake(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<()> {
        self.set_seen(store, account, mailbox, uids, false).await?;
        lock(store).forget_snoozes(account, mailbox, uids)?;
        self.move_to(store, account, mailbox, uids, "INBOX").await
    }

    /// Moves messages of one folder to `target`, by its local name, and
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
        let (from, to) = (self.remote(mailbox)?, self.remote(target)?);
        let patch = json!({ format!("mailboxIds/{from}"): null, format!("mailboxIds/{to}"): true });
        self.update(store, account, mailbox, uids, patch).await?;
        lock(store).remove_messages(account, mailbox, uids)?;
        Ok(())
    }

    /// Deletes messages for good, without Trash, and forgets them locally:
    /// an earlier copy of a draft.
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
        let ids = self.emails(store, account, mailbox, uids)?;
        let [done] = self
            .call([(
                "Email/set",
                json!({ "accountId": self.account_id, "destroy": ids }),
            )])
            .await?;
        if let Some(failed) = done["notDestroyed"]
            .as_object()
            .filter(|f| f.values().any(|e| e["type"].as_str() != Some("notFound")))
        {
            return Err(JmapError::Protocol(format!("not deleted: {failed:?}")));
        }
        lock(store).remove_messages(account, mailbox, uids)?;
        Ok(())
    }

    /// The sync space's hidden folder, when the account has one.
    fn space_folder(&self) -> Option<String> {
        self.mailboxes
            .iter()
            .find(|m| is_space(m))
            .map(|m| m.id.clone())
    }

    /// The notes in the sync space's hidden folder, oldest first, each
    /// with its email id; none while the folder isn't there.
    pub async fn space_notes(&mut self) -> Result<Vec<(String, crate::space::Note)>> {
        self.refresh_mailboxes().await?;
        let Some(folder) = self.space_folder() else {
            return Ok(Vec::new());
        };
        let ids = self.query_ids(&folder).await?;
        let mut found: HashMap<String, crate::space::Note> = HashMap::new();
        for chunk in ids.chunks(self.max_get) {
            for e in self.get_emails(chunk, &["id", "blobId"]).await? {
                let (Some(id), Some(blob)) = (email_id(&e), e["blobId"].as_str()) else {
                    continue;
                };
                let raw = match self.download(blob).await {
                    Err(JmapError::Gone) => continue,
                    r => r?,
                };
                if let Some(note) = crate::space::Note::from_message(&raw) {
                    found.insert(id, note);
                }
            }
        }
        // The server lists newest first.
        let notes = ids
            .into_iter()
            .rev()
            .filter_map(|id| found.remove(&id).map(|n| (id, n)))
            .collect();
        Ok(notes)
    }

    /// Adds a note to the sync space's hidden folder, made when missing.
    pub async fn space_put(&mut self, raw: &[u8]) -> Result<()> {
        self.refresh_mailboxes().await?;
        let folder = match self.space_folder() {
            Some(f) => f,
            None => {
                let [created] = self
                    .call([(
                        "Mailbox/set",
                        json!({ "accountId": self.account_id, "create": { "new": {
                            "name": crate::space::FOLDER, "parentId": null } } }),
                    )])
                    .await?;
                let id = created["created"]["new"]["id"]
                    .as_str()
                    .ok_or_else(|| not_done(&created, "notCreated"))?
                    .to_owned();
                self.mailboxes.push(Mailbox {
                    id: id.clone(),
                    name: crate::space::FOLDER.into(),
                    ..Mailbox::default()
                });
                id
            }
        };
        self.import(raw, &folder, &["$seen"]).await?;
        Ok(())
    }

    /// Deletes notes of the sync space's folder for good.
    pub async fn space_remove(&mut self, ids: &[String]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }
        let [done] = self
            .call([(
                "Email/set",
                json!({ "accountId": self.account_id, "destroy": ids }),
            )])
            .await?;
        if let Some(failed) = done["notDestroyed"]
            .as_object()
            .filter(|f| f.values().any(|e| e["type"].as_str() != Some("notFound")))
        {
            return Err(JmapError::Protocol(format!("not deleted: {failed:?}")));
        }
        Ok(())
    }

    /// Keeps a draft in the Drafts folder, made if the account has none.
    /// Returns the folder.
    pub async fn append_draft(&mut self, raw: &[u8]) -> Result<String> {
        let folder = self.folder(FolderRole::Drafts).await?;
        self.import(raw, &folder, &["$draft", "$seen"]).await?;
        Ok(folder)
    }

    /// Sends a message from `from` to `recipients` and files it in Sent.
    /// Returns the Sent folder.
    pub async fn send(&mut self, raw: &[u8], from: &str, recipients: &[String]) -> Result<String> {
        let sent = self.folder(FolderRole::Sent).await?;
        let drafts = self.folder(FolderRole::Drafts).await?;
        let identity = self.identity(from).await?;
        // The message waits in Drafts and moves to Sent once it is out, so
        // a failed send leaves it where the person can find it.
        let email = self.import(raw, &drafts, &["$draft", "$seen"]).await?;
        let rcpt: Vec<Value> = recipients.iter().map(|r| json!({ "email": r })).collect();
        let (drafts_id, sent_id) = (self.remote(&drafts)?, self.remote(&sent)?);
        let [submitted] = self
            .call([(
                "EmailSubmission/set",
                json!({
                    "accountId": self.account_id,
                    "create": { "send": {
                        "identityId": identity, "emailId": email,
                        "envelope": { "mailFrom": { "email": from }, "rcptTo": rcpt },
                    } },
                    "onSuccessUpdateEmail": { "#send": {
                        format!("mailboxIds/{drafts_id}"): null,
                        format!("mailboxIds/{sent_id}"): true,
                        "keywords/$draft": null,
                    } },
                }),
            )])
            .await?;
        if submitted["created"]["send"].is_null() {
            return Err(not_done(&submitted, "notCreated"));
        }
        Ok(sent)
    }

    /// Waits until the server reports a change or `timeout` passes, over
    /// the push channel when there is one. Returns true when something
    /// changed.
    pub async fn wait_for_change(&mut self, timeout: Duration) -> Result<bool> {
        let Some(url) = self.event_source_url.clone() else {
            tokio::time::sleep(timeout).await;
            return Ok(true);
        };
        let url = url
            .replace("{types}", "Email,Mailbox")
            .replace("{closeafter}", "state")
            .replace("{ping}", "60");
        let wait = async {
            let mut response = self
                .http
                .get(&url)
                .header(reqwest::header::AUTHORIZATION, &self.authorization)
                .header(reqwest::header::ACCEPT, "text/event-stream")
                .timeout(timeout + Duration::from_secs(5))
                .send()
                .await
                .map_err(|source| JmapError::Connect {
                    url: url.clone(),
                    source,
                })?;
            check_status(&response)?;
            let mut seen = String::new();
            while let Some(chunk) = response
                .chunk()
                .await
                .map_err(|e| JmapError::Protocol(e.to_string()))?
            {
                seen.push_str(&String::from_utf8_lossy(&chunk));
                if seen.lines().any(|l| l.trim() == "event: state") {
                    return Ok(true);
                }
                // Keep only the line being written.
                if let Some(i) = seen.rfind('\n') {
                    seen.drain(..=i);
                }
            }
            Ok(false)
        };
        match tokio::time::timeout(timeout, wait).await {
            Ok(changed) => changed,
            Err(_) => Ok(false),
        }
    }

    async fn update(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        patch: Value,
    ) -> Result<()> {
        if uids.is_empty() {
            return Ok(());
        }
        let ids = self.emails(store, account, mailbox, uids)?;
        let update: serde_json::Map<String, Value> =
            ids.into_iter().map(|id| (id, patch.clone())).collect();
        let [done] = self
            .call([(
                "Email/set",
                json!({ "accountId": self.account_id, "update": update }),
            )])
            .await?;
        if done["notUpdated"]
            .as_object()
            .is_some_and(|f| !f.is_empty())
        {
            return Err(not_done(&done, "notUpdated"));
        }
        Ok(())
    }

    /// Uploads a message and files it in one folder. Returns its id.
    async fn import(&mut self, raw: &[u8], folder: &str, keywords: &[&str]) -> Result<String> {
        let blob = self.upload(raw).await?;
        let mailbox = self.remote(folder)?;
        let keywords: serde_json::Map<String, Value> = keywords
            .iter()
            .map(|k| (k.to_string(), json!(true)))
            .collect();
        let [imported] = self
            .call([(
                "Email/import",
                json!({ "accountId": self.account_id, "emails": { "new": {
                    "blobId": blob, "mailboxIds": { mailbox: true }, "keywords": keywords } } }),
            )])
            .await?;
        imported["created"]["new"]["id"]
            .as_str()
            .map(str::to_owned)
            .ok_or_else(|| not_done(&imported, "notCreated"))
    }

    /// The identity that sends as `from`, else the first one.
    async fn identity(&mut self, from: &str) -> Result<String> {
        let [got] = self
            .call([(
                "Identity/get",
                json!({ "accountId": self.account_id, "ids": null }),
            )])
            .await?;
        let list = got["list"].as_array().cloned().unwrap_or_default();
        list.iter()
            .find(|i| {
                i["email"]
                    .as_str()
                    .is_some_and(|e| e.eq_ignore_ascii_case(from))
            })
            .or(list.first())
            .and_then(|i| i["id"].as_str())
            .map(str::to_owned)
            .ok_or_else(|| JmapError::Protocol("no identity to send as".into()))
    }

    /// Every message id in one folder, newest first; past the page cap
    /// the ids gathered so far stand, in case the server lies about
    /// its `total`.
    async fn query_ids(&mut self, mailbox: &str) -> Result<Vec<String>> {
        let mut ids = Vec::new();
        for _ in 0..QUERY_PAGES_MAX {
            let [page] = self
                .call([(
                    "Email/query",
                    json!({
                        "accountId": self.account_id,
                        "filter": { "inMailbox": mailbox },
                        "sort": [{ "property": "receivedAt", "isAscending": false }],
                        "position": ids.len(),
                        "limit": QUERY_PAGE,
                        "calculateTotal": true,
                    }),
                )])
                .await?;
            let got: Vec<String> = page["ids"]
                .as_array()
                .map(|a| {
                    a.iter()
                        .filter_map(|v| v.as_str().map(str::to_owned))
                        .collect()
                })
                .unwrap_or_default();
            let total = page["total"].as_u64().map(|t| t as usize);
            let done = got.is_empty() || total.is_none_or(|t| ids.len() + got.len() >= t);
            ids.extend(got);
            if done {
                return Ok(ids);
            }
        }
        Ok(ids)
    }

    async fn get_emails(&mut self, ids: &[String], properties: &[&str]) -> Result<Vec<Value>> {
        let mut properties: Vec<&str> = properties.to_vec();
        if properties.contains(&"header:Precedence") {
            properties.push(AUTO_SUBMITTED);
            properties.push(FEEDBACK_ID);
        }
        let [got] = self
            .call([(
                "Email/get",
                json!({ "accountId": self.account_id, "ids": ids, "properties": properties }),
            )])
            .await?;
        Ok(got["list"].as_array().cloned().unwrap_or_default())
    }

    fn email(
        &self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<String> {
        lock(store)
            .jmap_id(account, mailbox, uid)?
            .ok_or(JmapError::Gone)
    }

    fn emails(
        &self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<Vec<String>> {
        let store = lock(store);
        uids.iter()
            .map(|&uid| store.jmap_id(account, mailbox, uid)?.ok_or(JmapError::Gone))
            .collect()
    }

    /// Messages of a folder with their JMAP ids; ones forgotten meanwhile
    /// are left out.
    fn named(
        &self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<Vec<(u32, String)>> {
        let store = lock(store);
        let mut named = Vec::new();
        for &uid in uids {
            if let Some(id) = store.jmap_id(account, mailbox, uid)? {
                named.push((uid, id));
            }
        }
        Ok(named)
    }

    /// Downloads and keeps the bodies of the messages up to `max_bytes`.
    /// Returns those now here.
    async fn fetch_bodies(
        &mut self,
        store: &Mutex<Store>,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        max_bytes: usize,
    ) -> Result<Vec<u32>> {
        let named = self.named(store, account, mailbox, uids)?;
        if named.is_empty() {
            return Ok(Vec::new());
        }
        let ids: Vec<String> = named.iter().map(|(_, id)| id.clone()).collect();
        let emails = self.get_emails(&ids, &["id", "blobId", "size"]).await?;
        let mut cached = Vec::new();
        for (uid, id) in &named {
            let Some(e) = emails.iter().find(|e| e["id"].as_str() == Some(id)) else {
                continue;
            };
            let (Some(blob), Some(size)) = (e["blobId"].as_str(), e["size"].as_u64()) else {
                continue;
            };
            if size as usize > max_bytes {
                continue;
            }
            match self.download(blob).await {
                Ok(raw) => {
                    lock(store).set_full_body(account, mailbox, *uid, &parse_body(&raw))?;
                    cached.push(*uid);
                }
                Err(JmapError::Gone) => {}
                Err(e) => return Err(e),
            }
        }
        Ok(cached)
    }

    /// One part of a message by its blob, as listed before the body was
    /// here: JMAP hands it decoded.
    pub async fn blob(&self, blob: &str) -> Result<Vec<u8>> {
        self.download(blob).await
    }

    async fn download(&self, blob: &str) -> Result<Vec<u8>> {
        let url = self
            .download_url
            .replace("{accountId}", &encode(&self.account_id))
            .replace("{blobId}", &encode(blob))
            .replace("{name}", "message.eml")
            .replace("{type}", "message%2Frfc822");
        let response = self
            .http
            .get(&url)
            .header(reqwest::header::AUTHORIZATION, &self.authorization)
            .send()
            .await
            .map_err(|source| JmapError::Connect { url, source })?;
        if response.status() == reqwest::StatusCode::NOT_FOUND {
            return Err(JmapError::Gone);
        }
        check_status(&response)?;
        Ok(response
            .bytes()
            .await
            .map_err(|e| JmapError::Protocol(e.to_string()))?
            .to_vec())
    }

    async fn upload(&self, raw: &[u8]) -> Result<String> {
        let url = self
            .upload_url
            .replace("{accountId}", &encode(&self.account_id));
        let response = self
            .http
            .post(&url)
            .header(reqwest::header::AUTHORIZATION, &self.authorization)
            .header(reqwest::header::CONTENT_TYPE, "message/rfc822")
            .body(raw.to_vec())
            .send()
            .await
            .map_err(|source| JmapError::Connect { url, source })?;
        let uploaded: Value = read_json(response).await?;
        uploaded["blobId"]
            .as_str()
            .map(str::to_owned)
            .ok_or_else(|| JmapError::Protocol("upload gave no blob".into()))
    }

    /// Sends method calls in one request and returns each one's answer,
    /// in order. A method error fails the whole call.
    async fn call<const N: usize>(&self, calls: [(&str, Value); N]) -> Result<[Value; N]> {
        self.call_using(&USING, calls).await
    }

    async fn call_using<const N: usize>(
        &self,
        using: &[&str],
        calls: [(&str, Value); N],
    ) -> Result<[Value; N]> {
        let method_calls: Vec<Value> = calls
            .iter()
            .enumerate()
            .map(|(i, (name, args))| json!([name, args, i.to_string()]))
            .collect();
        let response = self
            .http
            .post(&self.api_url)
            .header(reqwest::header::AUTHORIZATION, &self.authorization)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(json!({ "using": using, "methodCalls": method_calls }).to_string())
            .send()
            .await
            .map_err(|source| JmapError::Connect {
                url: self.api_url.clone(),
                source,
            })?;
        let answer: Value = read_json(response).await?;
        let mut out: [Value; N] = std::array::from_fn(|_| Value::Null);
        for r in answer["methodResponses"].as_array().into_iter().flatten() {
            let (Some(name), Some(i)) = (
                r[0].as_str(),
                r[2].as_str().and_then(|i| i.parse::<usize>().ok()),
            ) else {
                continue;
            };
            if name == "error" {
                let kind = r[1]["type"].as_str().unwrap_or("unknown");
                return Err(JmapError::Protocol(format!("{}: {kind}", calls[i].0)));
            }
            if i < N && out[i].is_null() {
                out[i] = r[1].clone();
            }
        }
        if out.iter().any(Value::is_null) {
            return Err(JmapError::Protocol("missing method response".into()));
        }
        Ok(out)
    }

    /// The settings it was opened with.
    pub fn config(&self) -> &JmapConfig {
        &self.config
    }
}

/// Checks that the settings work.
pub async fn check_login(cfg: &JmapConfig) -> Result<()> {
    Client::open(cfg).await.map(|_| ())
}

/// Keeps the inbox of one account in sync forever: sync, wait for a push
/// (or a while), sync again. Reconnects with a growing pause after errors.
/// Wrong credentials end the loop.
pub async fn watch(
    cfg: JmapConfig,
    store: Arc<Mutex<Store>>,
    account: AccountId,
    events: impl Fn(WatchEvent),
) -> Result<()> {
    let mut pause = Duration::from_secs(2);
    loop {
        let result: Result<()> = async {
            let mut client = Client::open(&cfg).await?;
            pause = Duration::from_secs(2);
            let mut folders_synced: Option<std::time::Instant> = None;
            loop {
                crate::pending::send(&mut client, &store, account).await?;
                if folders_synced.is_none_or(|t| t.elapsed() >= crate::imap::FOLDERS_EVERY) {
                    client.sync_folders(&store, account).await?;
                    folders_synced = Some(std::time::Instant::now());
                }
                let mut report = client
                    .sync_mailbox(&store, account, "INBOX", |done, total| {
                        events(WatchEvent::Progress {
                            account,
                            done,
                            total,
                        })
                    })
                    .await?;
                if crate::rules::after_sync(&store, account, &mut report)? {
                    crate::pending::send(&mut client, &store, account).await?;
                }
                events(WatchEvent::Synced { account, report });
                // Snoozed mail comes back, and mail sent later goes, on
                // time.
                let due = lock(&store)
                    .next_due(account, crate::pending::now())?
                    .map(|at| Duration::from_secs((at - crate::pending::now()).max(1) as u64));
                client
                    .wait_for_change(POLL_EVERY.min(due.unwrap_or(POLL_EVERY)))
                    .await?;
            }
        }
        .await;
        match result {
            Err(JmapError::Auth) => return Err(JmapError::Auth),
            Err(e) => events(WatchEvent::Offline {
                account,
                reason: e.to_string(),
            }),
            Ok(()) => {}
        }
        tokio::time::sleep(pause).await;
        pause = (pause * 2).min(Duration::from_secs(60));
    }
}

/// The account's own folders in tree order: those with no role, under
/// their parents, by the server's sort order then name.
fn own_folders(mailboxes: &[Mailbox]) -> Vec<crate::AccountFolder> {
    fn add(
        mailboxes: &[Mailbox],
        parent: Option<&str>,
        depth: u32,
        out: &mut Vec<crate::AccountFolder>,
    ) {
        let mut children: Vec<&Mailbox> = mailboxes
            .iter()
            .filter(|m| m.parent_id.as_deref() == parent && m.role.is_none() && !is_space(m))
            .collect();
        children.sort_by(|a, b| {
            (a.sort_order, a.name.to_lowercase()).cmp(&(b.sort_order, b.name.to_lowercase()))
        });
        for m in children {
            out.push(crate::AccountFolder {
                mailbox: m.local(),
                name: m.name.clone(),
                depth,
                selectable: true,
                unread: m.unread_emails,
                total: m.total_emails,
            });
            if depth < 16 {
                add(mailboxes, Some(&m.id), depth + 1, out);
            }
        }
    }
    let mut out = Vec::new();
    add(mailboxes, None, 0, &mut out);
    out
}

/// The sync space's folder, which stays hidden.
fn is_space(m: &Mailbox) -> bool {
    m.parent_id.is_none() && m.role.is_none() && m.name == crate::space::FOLDER
}

/// The mailbox with `role`'s job, when there is one.
fn find_role(mailboxes: &[Mailbox], role: FolderRole) -> Option<&Mailbox> {
    let name = role_name(role);
    mailboxes.iter().find(|m| m.role.as_deref() == Some(name))
}

fn role_name(role: FolderRole) -> &'static str {
    match role {
        FolderRole::Sent => "sent",
        FolderRole::Archive => "archive",
        FolderRole::Trash => "trash",
        FolderRole::Drafts => "drafts",
        FolderRole::Snoozed => "snoozed",
        FolderRole::Junk => "junk",
    }
}

fn role_label(role: FolderRole) -> &'static str {
    match role {
        FolderRole::Sent => "Sent",
        FolderRole::Archive => "Archive",
        FolderRole::Trash => "Trash",
        FolderRole::Drafts => "Drafts",
        FolderRole::Snoozed => "Snoozed",
        FolderRole::Junk => "Junk",
    }
}

fn email_id(e: &Value) -> Option<String> {
    e["id"].as_str().map(str::to_owned)
}

fn flags(e: &Value) -> Flags {
    let has = |k: &str| e["keywords"][k].as_bool() == Some(true);
    Flags {
        seen: has("$seen"),
        flagged: has("$flagged"),
        answered: has("$answered"),
    }
}

/// The keywords a message carries, for its labels.
fn keywords(e: &Value) -> Vec<String> {
    e["keywords"]
        .as_object()
        .into_iter()
        .flatten()
        .filter(|(_, on)| on.as_bool() == Some(true))
        .map(|(k, _)| k.clone())
        .collect()
}

/// The first address of a JMAP address list: (name, email).
fn first_address(list: &Value) -> (String, String) {
    let first = &list[0];
    (
        first["name"].as_str().unwrap_or_default().to_owned(),
        first["email"].as_str().unwrap_or_default().to_owned(),
    )
}

fn ids(list: &Value) -> Vec<String> {
    list.as_array()
        .into_iter()
        .flatten()
        .filter_map(|v| v.as_str().map(|id| format!("<{id}>")))
        .collect()
}

fn summary(e: &Value, account: AccountId, mailbox: &str, uid: u32) -> MessageSummary {
    let (from_name, from_email) = first_address(&e["from"]);
    let to = e["to"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|a| {
            a["name"]
                .as_str()
                .filter(|n| !n.is_empty())
                .or(a["email"].as_str())
        })
        .collect::<Vec<_>>()
        .join(", ");
    let mut references = ids(&e["references"]);
    if references.is_empty() {
        references = ids(&e["inReplyTo"]);
    }
    let (_, reply_to) = first_address(&e["replyTo"]);
    MessageSummary {
        account,
        mailbox: mailbox.to_owned(),
        uid,
        from_name,
        to,
        subject: e["subject"].as_str().unwrap_or_default().to_owned(),
        preview: clean_preview(e["preview"].as_str().unwrap_or_default()),
        received_at: e["receivedAt"]
            .as_str()
            .and_then(mail_parser::DateTime::parse_rfc3339)
            .map(|d| d.to_timestamp())
            .unwrap_or_default(),
        flags: flags(e),
        list: headers(e)
            .map(|m| newsletter::list_info(&m))
            .unwrap_or_default(),
        reply: ReplyInfo {
            message_id: ids(&e["messageId"]).into_iter().next().unwrap_or_default(),
            references: references.join(" "),
            reply_to: if reply_to.eq_ignore_ascii_case(&from_email) {
                String::new()
            } else {
                reply_to
            },
            recipients: groups::recipients_json(e),
        },
        from_email,
    }
}

/// The files in an Email's `attachments`, as the Attachments board lists
/// them before the body is here. Each keeps its blob, to be fetched alone.
fn listed_files(parts: &Value) -> Vec<Attachment> {
    let mut files = Vec::new();
    for p in parts.as_array().into_iter().flatten() {
        let mime = p["type"].as_str().unwrap_or_default().to_ascii_lowercase();
        let attached = p["disposition"]
            .as_str()
            .is_some_and(|d| d.eq_ignore_ascii_case("attachment"));
        let name = p["name"].as_str().filter(|n| !n.is_empty());
        let file = match mime.split_once('/').unwrap_or((mime.as_str(), "")) {
            (_, "pkcs7-signature" | "x-pkcs7-signature" | "pgp-signature" | "pgp-encrypted") => {
                false
            }
            ("text", "plain" | "html") => attached,
            ("text", _) => attached || name.is_some(),
            // A picture shown inside the message, not a file sent with it.
            _ => attached || p["cid"].as_str().is_none(),
        };
        let Some(blob) = p["blobId"].as_str().filter(|_| file) else {
            continue;
        };
        files.push(Attachment {
            part: files.len() as u32,
            name: match name {
                Some(n) => n.to_owned(),
                None if mime == "message/rfc822" => "message.eml".into(),
                None => "attachment".into(),
            },
            mime,
            size: p["size"].as_u64().unwrap_or_default(),
            section: Some(blob.to_owned()),
            encoding: None,
        });
    }
    files
}

/// Whether a machine sent it, judged from the same headers as for IMAP.
fn automated(e: &Value) -> bool {
    headers(e).is_some_and(|m| notify::automated(&m))
}

/// The headers [`notify::automated`] and [`newsletter::list_info`] read,
/// as a message.
fn headers(e: &Value) -> Option<mail_parser::Message<'static>> {
    let mut head = String::new();
    let (_, from) = first_address(&e["from"]);
    head.push_str(&format!("From: <{from}>\r\n"));
    for (name, key) in [
        ("List-Id", "header:List-Id"),
        ("List-Unsubscribe", "header:List-Unsubscribe"),
        ("List-Unsubscribe-Post", "header:List-Unsubscribe-Post"),
        ("List-Post", "header:List-Post"),
        ("Precedence", "header:Precedence"),
        ("Auto-Submitted", AUTO_SUBMITTED),
        ("Feedback-ID", FEEDBACK_ID),
    ] {
        if let Some(v) = e[key].as_str() {
            head.push_str(&format!("{name}:{v}\r\n"));
        }
    }
    head.push_str("\r\n");
    MessageParser::default()
        .parse_headers(head.as_bytes())
        .map(|m| m.into_owned())
}

fn not_done(answer: &Value, key: &str) -> JmapError {
    let kind = answer[key]
        .as_object()
        .and_then(|m| m.values().next())
        .and_then(|e| e["type"].as_str())
        .unwrap_or("refused");
    JmapError::Protocol(kind.to_owned())
}

fn check_status(response: &reqwest::Response) -> Result<()> {
    match response.status() {
        s if s == reqwest::StatusCode::UNAUTHORIZED || s == reqwest::StatusCode::FORBIDDEN => {
            Err(JmapError::Auth)
        }
        s if !s.is_success() => Err(JmapError::Protocol(format!("HTTP {s}"))),
        _ => Ok(()),
    }
}

/// A response body above the cap is refused before it is parsed.
fn check_size(bytes: &[u8]) -> Result<()> {
    if bytes.len() > RESPONSE_MAX {
        Err(JmapError::Protocol(format!(
            "body of {} bytes exceeds the {}-byte limit",
            bytes.len(),
            RESPONSE_MAX
        )))
    } else {
        Ok(())
    }
}

async fn read_json<T: serde::de::DeserializeOwned>(response: reqwest::Response) -> Result<T> {
    check_status(&response)?;
    let bytes = response
        .bytes()
        .await
        .map_err(|e| JmapError::Protocol(e.to_string()))?;
    check_size(&bytes)?;
    serde_json::from_slice(&bytes).map_err(|e| JmapError::Protocol(e.to_string()))
}

/// Percent-encodes a value for a URL template.
fn encode(value: &str) -> String {
    url::form_urlencoded::byte_serialize(value.as_bytes()).collect()
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_the_well_known_session() {
        assert_eq!(
            well_known("matteo@fastmail.com").as_deref(),
            Some("https://fastmail.com/.well-known/jmap")
        );
        assert_eq!(well_known("nobody"), None);
    }

    #[test]
    fn logs_in_with_a_password_or_a_token() {
        let mut cfg = JmapConfig {
            session_url: String::new(),
            username: "a@b.c".into(),
            password: "pw".into(),
        };
        assert_eq!(cfg.authorization(), "Basic YUBiLmM6cHc=");
        cfg.username.clear();
        assert_eq!(cfg.authorization(), "Bearer pw");
        assert!(!format!("{cfg:?}").contains("pw"));
    }

    #[test]
    fn reads_a_message_row() {
        let e = json!({
            "id": "M1", "keywords": { "$seen": true, "$flagged": true },
            "from": [{ "name": "Julia Reed", "email": "julia@example.org" }],
            "to": [{ "name": null, "email": "matteo@example.com" }, { "name": "Ana", "email": "ana@x.y" }],
            "replyTo": [{ "email": "desk@example.org" }],
            "subject": "Plans", "preview": "> old\nSee you at  ten",
            "receivedAt": "2026-10-16T09:30:00Z",
            "messageId": ["b@x"], "references": null, "inReplyTo": ["a@x"],
        });
        let s = summary(&e, AccountId(3), "INBOX", 7);
        assert_eq!(
            (s.from_name.as_str(), s.from_email.as_str()),
            ("Julia Reed", "julia@example.org")
        );
        assert_eq!(s.to, "matteo@example.com, Ana");
        assert_eq!(s.preview, "See you at ten");
        assert_eq!(s.received_at, 1_792_143_000);
        assert!(s.flags.seen && s.flags.flagged && !s.flags.answered);
        assert_eq!(s.reply.message_id, "<b@x>");
        assert_eq!(s.reply.references, "<a@x>");
        assert_eq!(s.reply.reply_to, "desk@example.org");
    }

    #[test]
    fn finds_the_junk_role() {
        let mailbox = |id: &str, role: Option<&str>| Mailbox {
            id: id.into(),
            name: id.into(),
            role: role.map(str::to_owned),
            ..Mailbox::default()
        };
        let mut mailboxes = vec![
            mailbox("m1", Some("inbox")),
            mailbox("m2", None),
            mailbox("m3", Some("junk")),
        ];
        let junk = find_role(&mailboxes, FolderRole::Junk).map(Mailbox::local);
        assert_eq!(junk.as_deref(), Some("m3"));
        // Spam stays out of the account's own folders.
        assert_eq!(own_folders(&mailboxes).len(), 1);
        mailboxes.pop();
        assert!(find_role(&mailboxes, FolderRole::Junk).is_none());
    }

    #[test]
    fn tells_lists_from_people() {
        let person = json!({ "from": [{ "email": "julia@example.org" }] });
        assert!(!automated(&person));
        let list = json!({ "from": [{ "email": "news@shop.it" }],
                           "header:List-Unsubscribe": " <mailto:u@shop.it>" });
        assert!(automated(&list));
    }

    #[test]
    fn refuses_a_body_over_the_limit() {
        // At the limit the body still passes, and so does a small one.
        assert!(check_size(b"{}").is_ok());
        assert!(check_size(&vec![0u8; RESPONSE_MAX]).is_ok());

        // One byte over is a protocol failure, naming the limit.
        let over = vec![0u8; RESPONSE_MAX + 1];
        let err = check_size(&over).unwrap_err();
        assert!(matches!(
            err,
            JmapError::Protocol(msg)
                if msg == format!(
                    "body of {} bytes exceeds the {}-byte limit",
                    RESPONSE_MAX + 1,
                    RESPONSE_MAX
                )
        ));
    }
}
