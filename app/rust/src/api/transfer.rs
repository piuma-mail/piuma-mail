//! Settings › Import and export: mail to and from other mail apps
//! (`.mbox`, `.eml`, a ZIP of `.eml` files) and the settings file
//! ([`piuma_core::settings_file`]).
//!
//! One job runs at a time. It reports to its stream as it goes and ends
//! with a summary; [`cancel_transfer`] stops it between two messages.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use flutter_rust_bridge::frb;
use piuma_core::remote::Remote;
use piuma_core::settings_file::{self, SettingsFileError};
use piuma_core::transfer::{self, ExportFormat, ExportSource, Progress, SkipReason, Skipped};
use piuma_core::AccountId;

use super::engine::{engine, store, EngineError, ErrorKind, MessageRef};
use crate::frb_generated::StreamSink;

/// A job is running.
static RUNNING: AtomicBool = AtomicBool::new(false);
/// The running job was asked to stop.
static CANCEL: AtomicBool = AtomicBool::new(false);

/// How often progress is reported, at most.
const PROGRESS_EVERY: Duration = Duration::from_millis(120);

/// What an export writes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MailExportFormat {
    /// One `.mbox` file, as Thunderbird, Apple Mail and Gmail use.
    Mbox,
    /// A ZIP holding one `.eml` file per message.
    EmlZip,
}

/// Why something was left out.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SkipKind {
    NotMail,
    TooLarge,
    NotDownloaded,
    Gone,
    NotAFile,
    Unreadable,
    Refused,
}

/// One message, or file, left out.
#[derive(Debug, Clone)]
pub struct SkippedItem {
    /// A file name, `name.mbox #12`, or a message's subject.
    pub item: String,
    pub kind: SkipKind,
    /// What the server said, for [`SkipKind::Refused`].
    pub detail: String,
}

/// What an export did.
#[derive(Debug, Clone)]
pub struct ExportSummary {
    pub exported: u32,
    /// Rebuilt from the local copy, without attachments.
    pub rebuilt: u32,
    pub skipped: Vec<SkippedItem>,
    pub skipped_count: u32,
    pub cancelled: bool,
    /// A server could not be reached.
    pub offline: bool,
    pub path: String,
}

/// What an import did.
#[derive(Debug, Clone)]
pub struct ImportSummary {
    pub imported: u32,
    pub duplicates: u32,
    pub skipped: Vec<SkippedItem>,
    pub skipped_count: u32,
    pub cancelled: bool,
    /// Why it stopped before the end; running it again carries on.
    pub error: Option<String>,
}

/// What a job's stream hears: how far it is, then, once, how it ended
/// (one of `exported`, `imported` or `failed`).
#[derive(Debug, Clone, Default)]
pub struct TransferEvent {
    /// How far it is, 0 to 1.
    pub fraction: f64,
    /// Messages handled so far.
    pub messages: u32,
    pub exported: Option<ExportSummary>,
    pub imported: Option<ImportSummary>,
    /// It could not start or write (the file can't be made, no server).
    pub failed: Option<String>,
}

fn n(count: u64) -> u32 {
    u32::try_from(count).unwrap_or(u32::MAX)
}

fn skipped(list: Vec<Skipped>) -> Vec<SkippedItem> {
    list.into_iter()
        .map(|s| {
            let (kind, detail) = match s.reason {
                SkipReason::NotMail => (SkipKind::NotMail, String::new()),
                SkipReason::TooLarge => (SkipKind::TooLarge, String::new()),
                SkipReason::NotDownloaded => (SkipKind::NotDownloaded, String::new()),
                SkipReason::Gone => (SkipKind::Gone, String::new()),
                SkipReason::NotAFile => (SkipKind::NotAFile, String::new()),
                SkipReason::Unreadable => (SkipKind::Unreadable, String::new()),
                SkipReason::Refused(what) => (SkipKind::Refused, what),
            };
            SkippedItem {
                item: s.item,
                kind,
                detail,
            }
        })
        .collect()
}

/// Takes the one job slot, or says another job is running.
fn start_job() -> Result<(), EngineError> {
    if RUNNING.swap(true, Ordering::SeqCst) {
        return Err(EngineError::new(
            ErrorKind::Other,
            "an import or export is running",
        ));
    }
    CANCEL.store(false, Ordering::SeqCst);
    Ok(())
}

/// Sends progress at most every [`PROGRESS_EVERY`], and the last.
fn reporter(sink: &StreamSink<TransferEvent>) -> impl FnMut(Progress) + '_ {
    let mut last = Instant::now() - PROGRESS_EVERY;
    move |p: Progress| {
        if p.done >= p.total || last.elapsed() >= PROGRESS_EVERY {
            last = Instant::now();
            let _ = sink.add(TransferEvent {
                fraction: if p.total == 0 {
                    0.0
                } else {
                    (p.done as f64 / p.total as f64).min(1.0)
                },
                messages: p.messages.min(u64::from(u32::MAX)) as u32,
                ..Default::default()
            });
        }
    }
}

/// Stops the running import or export between two messages. A stopped
/// export leaves no file; a stopped import keeps what it put in, and
/// running it again carries on.
#[frb(sync)]
pub fn cancel_transfer() {
    CANCEL.store(true, Ordering::SeqCst);
}

/// Whether an import or export is running.
#[frb(sync)]
pub fn transfer_running() -> bool {
    RUNNING.load(Ordering::SeqCst)
}

/// Each account's server, opened when first needed; an account whose
/// server can't be reached gives its messages from the local copy.
struct Servers {
    open: HashMap<i64, Option<Remote>>,
}

impl ExportSource for Servers {
    async fn fetch(
        &mut self,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<transfer::Fetched, String> {
        if let std::collections::hash_map::Entry::Vacant(slot) = self.open.entry(account.0) {
            let opened = async {
                let a = store().ok()?.account(account).ok()??;
                let login = crate::login::load(account).ok()?;
                Remote::open(&a, &login).await.ok()
            }
            .await;
            slot.insert(opened);
        }
        let Some(Some(remote)) = self.open.get_mut(&account.0) else {
            return Err("offline".into());
        };
        let shared = engine().map_err(|e| e.detail)?.store.clone();
        remote
            .raw_many(&shared, account, mailbox, uids)
            .await
            .map_err(|e| e.to_string())
    }
}

fn run_export(
    messages: Vec<(AccountId, String, u32)>,
    format: MailExportFormat,
    path: String,
    sink: StreamSink<TransferEvent>,
) -> Result<(), EngineError> {
    let engine = engine()?;
    start_job()?;
    let shared = engine.store.clone();
    engine.runtime.spawn(async move {
        let format = match format {
            MailExportFormat::Mbox => ExportFormat::Mbox,
            MailExportFormat::EmlZip => ExportFormat::EmlZip,
        };
        let mut servers = Servers {
            open: HashMap::new(),
        };
        let done = transfer::export(
            &mut servers,
            &shared,
            &messages,
            format,
            Path::new(&path),
            &CANCEL,
            reporter(&sink),
        )
        .await;
        for (_, remote) in servers.open.drain() {
            if let Some(r) = remote {
                r.close().await;
            }
        }
        let _ = sink.add(match done {
            Ok(r) => TransferEvent {
                exported: Some(ExportSummary {
                    exported: n(r.exported),
                    rebuilt: n(r.rebuilt),
                    skipped: skipped(r.skipped),
                    skipped_count: n(r.skipped_count),
                    cancelled: r.cancelled,
                    offline: r.offline,
                    path,
                }),
                ..Default::default()
            },
            Err(e) => TransferEvent {
                failed: Some(e.to_string()),
                ..Default::default()
            },
        });
        RUNNING.store(false, Ordering::SeqCst);
    });
    Ok(())
}

/// Exports one folder of an account into `path`: every message, oldest
/// first, from the server (or what was downloaded, without one).
pub fn export_folder(
    account_id: i64,
    mailbox: String,
    format: MailExportFormat,
    path: String,
    sink: StreamSink<TransferEvent>,
) -> Result<(), EngineError> {
    let id = AccountId(account_id);
    let mut uids = store()?.uids(id, &mailbox)?;
    uids.sort_unstable();
    let messages = uids.into_iter().map(|u| (id, mailbox.clone(), u)).collect();
    run_export(messages, format, path, sink)
}

/// Exports chosen messages, in the order given, into `path`.
pub fn export_messages(
    messages: Vec<MessageRef>,
    format: MailExportFormat,
    path: String,
    sink: StreamSink<TransferEvent>,
) -> Result<(), EngineError> {
    let messages = messages
        .into_iter()
        .map(|m| (AccountId(m.account_id), m.mailbox, m.uid))
        .collect();
    run_export(messages, format, path, sink)
}

/// How many messages a folder export writes, for the question before it.
#[frb(sync)]
pub fn export_folder_size(account_id: i64, mailbox: String) -> Result<u32, EngineError> {
    Ok(store()?.uids(AccountId(account_id), &mailbox)?.len() as u32)
}

/// Imports `.eml` and `.mbox` files (and Apple Mail `.mbox` folders) into
/// one folder of an account, skipping what it already has.
pub fn import_mail(
    account_id: i64,
    mailbox: String,
    paths: Vec<String>,
    sink: StreamSink<TransferEvent>,
) -> Result<(), EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    let account = store()?
        .account(id)?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "unknown account"))?;
    let login = crate::login::load(id)?;
    start_job()?;
    engine.runtime.spawn(async move {
        let paths: Vec<PathBuf> = paths.into_iter().map(PathBuf::from).collect();
        let event = match Remote::open(&account, &login).await {
            Err(e) => TransferEvent {
                failed: Some(EngineError::from(e).detail),
                ..Default::default()
            },
            Ok(mut remote) => {
                let report = {
                    let mut target = transfer::RemoteFolder {
                        remote: &mut remote,
                        folder: mailbox,
                    };
                    transfer::import(&mut target, &paths, &CANCEL, reporter(&sink)).await
                };
                remote.close().await;
                TransferEvent {
                    imported: Some(ImportSummary {
                        imported: n(report.imported),
                        duplicates: n(report.duplicates),
                        skipped: skipped(report.skipped),
                        skipped_count: n(report.skipped_count),
                        cancelled: report.cancelled,
                        error: report.error,
                    }),
                    ..Default::default()
                }
            }
        };
        let _ = sink.add(event);
        RUNNING.store(false, Ordering::SeqCst);
    });
    Ok(())
}

// ------------------------------------------------------------ settings

/// An account from a settings file, to fill the add-account form; the
/// password is asked for there.
#[derive(Debug, Clone)]
pub struct AccountPreset {
    pub email: String,
    pub name: String,
    pub sender_name: String,
    /// `#RRGGBB`, or empty.
    pub color: String,
    pub jmap: bool,
    pub username: String,
    pub imap_host: String,
    pub imap_port: u16,
    pub imap_starttls: bool,
    pub smtp_host: String,
    pub smtp_port: u16,
    pub smtp_starttls: bool,
    pub jmap_url: String,
    /// This device has an account with this address already.
    pub added: bool,
}

/// What a settings file holds.
#[derive(Debug, Clone)]
pub struct SettingsFileInfo {
    pub accounts: Vec<AccountPreset>,
    pub signatures: u32,
    pub appearance: bool,
}

/// What applying a settings file did.
#[derive(Debug, Clone)]
pub struct AppliedSettings {
    pub signatures_added: u32,
    /// Signatures of accounts not added yet: applying the file again after
    /// adding them brings them in.
    pub signatures_waiting: u32,
}

fn settings_error(e: SettingsFileError) -> EngineError {
    match e {
        SettingsFileError::Store(s) => s.into(),
        // Made by a newer Piuma: this one is out of date for it.
        SettingsFileError::Newer(_) => EngineError::new(ErrorKind::Outdated, e.to_string()),
        _ => EngineError::new(ErrorKind::Other, e.to_string()),
    }
}

fn read_settings(path: &str) -> Result<settings_file::SettingsFile, EngineError> {
    let path = Path::new(path);
    let meta = std::fs::symlink_metadata(path)
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    if !meta.file_type().is_file() {
        return Err(EngineError::new(ErrorKind::Other, "not a plain file"));
    }
    if meta.len() > settings_file::FILE_MAX {
        return Err(settings_error(SettingsFileError::TooLarge));
    }
    let data =
        std::fs::read(path).map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    settings_file::read(&data).map_err(settings_error)
}

/// Writes the settings file at `path`: accounts without passwords,
/// signatures, appearance. Never through a link.
pub fn export_settings(path: String) -> Result<(), EngineError> {
    let text = {
        let store = store()?;
        settings_file::write(&settings_file::collect(&store)?)
    };
    let path = Path::new(&path);
    if std::fs::symlink_metadata(path).is_ok_and(|m| !m.file_type().is_file()) {
        return Err(EngineError::new(ErrorKind::Other, "not a plain file"));
    }
    let _ = std::fs::remove_file(path);
    use std::io::Write;
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    file.write_all(text.as_bytes())
        .and_then(|_| file.sync_all())
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))
}

/// What the settings file at `path` holds, checked.
pub fn read_settings_file(path: String) -> Result<SettingsFileInfo, EngineError> {
    let file = read_settings(&path)?;
    let mine = store()?.accounts()?;
    Ok(SettingsFileInfo {
        accounts: file
            .accounts
            .iter()
            .map(|a| {
                let imap = a.imap.clone().unwrap_or_default();
                let smtp = a.smtp.clone().unwrap_or_default();
                AccountPreset {
                    added: mine.iter().any(|m| m.email.eq_ignore_ascii_case(&a.email)),
                    email: a.email.clone(),
                    name: a.name.clone(),
                    sender_name: a.sender_name.clone(),
                    color: a.color.clone(),
                    jmap: a.kind == "jmap",
                    username: a.username.clone(),
                    imap_starttls: imap.security == "starttls",
                    imap_host: imap.host,
                    imap_port: imap.port,
                    smtp_starttls: smtp.security == "starttls",
                    smtp_host: smtp.host,
                    smtp_port: smtp.port,
                    jmap_url: a.jmap_url.clone().unwrap_or_default(),
                }
            })
            .collect(),
        signatures: file.signatures.len() as u32,
        appearance: file.appearance.is_some(),
    })
}

/// Applies the settings file at `path`: its signatures for the accounts
/// this device has and, when `appearance`, its appearance. Safe to call
/// again once more accounts are added.
pub fn apply_settings_file(path: String, appearance: bool) -> Result<AppliedSettings, EngineError> {
    let file = read_settings(&path)?;
    let mut store = store()?;
    if appearance {
        if let Some(a) = &file.appearance {
            settings_file::apply_appearance(&store, a)?;
        }
    }
    let (signatures_added, signatures_waiting) =
        settings_file::apply_signatures(&mut store, &file)?;
    Ok(AppliedSettings {
        signatures_added,
        signatures_waiting,
    })
}
