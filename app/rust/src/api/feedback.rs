//! In-app reports, as on `FeedbackToApprove`: the report sheet, "See
//! what's sent", Your reports and the line offered after a crash. The
//! engine keeps, cleans and sends them; the app draws.

use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use flutter_rust_bridge::frb;
use piuma_core::feedback::{self, Kind, Level, Relay, Reports, Status, Ticket, Waiting};
use piuma_core::AccountKind;

use super::engine::{engine, reader, store, EngineError, ErrorKind};

static DIR: OnceLock<PathBuf> = OnceLock::new();
/// A ticket fetched and solved when the sheet opened, for the next Send.
static PREPARED: Mutex<Option<Ticket>> = Mutex::new(None);

/// Called once the database is open: reports live next to it.
pub(crate) fn opened(db_path: &str) {
    let dir = std::path::Path::new(db_path)
        .parent()
        .map(|d| d.join("feedback"))
        .unwrap_or_else(|| "feedback".into());
    let _ = DIR.set(dir);
    refresh_personal();
}

fn reports() -> Result<Reports, EngineError> {
    DIR.get()
        .map(|d| Reports::new(d.clone()))
        .ok_or_else(|| EngineError::new(ErrorKind::NotOpen, "engine not open"))
}

fn err(e: impl std::fmt::Display) -> EngineError {
    EngineError::new(ErrorKind::Other, e.to_string())
}

/// The words a report must never carry: every account's names, address,
/// login and servers.
fn refresh_personal() {
    let Ok(store) = store() else { return };
    let Ok(accounts) = store.accounts() else {
        return;
    };
    let mut words = Vec::new();
    for a in accounts {
        words.extend([a.name, a.email, a.sender_name]);
        match a.kind {
            AccountKind::Imap {
                imap,
                smtp,
                username,
            } => words.extend([imap.host, smtp.host, username]),
            AccountKind::Jmap {
                session_url,
                username,
            } => words.extend([session_url, username]),
        }
    }
    feedback::set_personal(words);
}

const SHAKE: &str = "feedback.shake";

/// "Shake to report": shaking the phone opens the report sheet. Off at
/// first.
#[frb(sync)]
pub fn feedback_shake() -> Result<bool, EngineError> {
    Ok(reader()?.setting(SHAKE)?.as_deref() == Some("true"))
}

#[frb(sync)]
pub fn set_feedback_shake(on: bool) -> Result<(), EngineError> {
    Ok(store()?.set_setting(SHAKE, if on { "true" } else { "false" })?)
}

/// Problem or Idea.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeedbackKind {
    Problem,
    Idea,
}

/// Where a report is, for Your reports.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeedbackStatus {
    /// Its turn comes soon.
    Waiting,
    /// No connection: it goes when there is one.
    Offline,
    /// The relay took its fill for today: it goes later on its own.
    Paused,
    Sending,
    Sent,
    Failed,
    Emailed,
}

/// What the person wrote and chose on the sheet.
#[derive(Debug, Clone)]
pub struct FeedbackDraft {
    pub kind: FeedbackKind,
    pub title: String,
    pub description: String,
    pub include_screenshot: bool,
    pub include_log: bool,
    /// From the app: version, system, device, screen size, language,
    /// network, the screen the report came from. The engine adds the
    /// accounts by type and what their IMAP servers can do.
    pub device: Vec<FeedbackField>,
    /// The last screens visited, "HH:MM:SS Name", oldest first.
    pub screens: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct FeedbackField {
    pub name: String,
    pub value: String,
}

/// A report in Your reports.
#[derive(Debug, Clone)]
pub struct FeedbackReport {
    pub id: String,
    pub kind: FeedbackKind,
    pub title: String,
    /// Unix seconds.
    pub created_at: i64,
    pub status: FeedbackStatus,
    /// When it is due to go, Unix seconds, while it waits.
    pub next_try: Option<i64>,
    /// The issue number once sent.
    pub issue: Option<u32>,
}

impl From<feedback::Report> for FeedbackReport {
    fn from(r: feedback::Report) -> Self {
        let status = match (r.status, r.waiting) {
            (Status::Queued, Some(Waiting::Offline)) => FeedbackStatus::Offline,
            (Status::Queued, Some(Waiting::Paused)) => FeedbackStatus::Paused,
            (Status::Queued, _) => FeedbackStatus::Waiting,
            (Status::Sending, _) => FeedbackStatus::Sending,
            (Status::Sent, _) => FeedbackStatus::Sent,
            (Status::Failed, _) => FeedbackStatus::Failed,
            (Status::Emailed, _) => FeedbackStatus::Emailed,
        };
        FeedbackReport {
            id: r.id,
            kind: match r.kind {
                Kind::Problem => FeedbackKind::Problem,
                Kind::Idea => FeedbackKind::Idea,
            },
            title: r.title,
            created_at: r.created_at,
            status,
            next_try: (r.status == Status::Queued && r.next_try > 0).then_some(r.next_try),
            issue: r.issue,
        }
    }
}

/// "See what's sent": the report as text and, when it goes, the whole log.
#[derive(Debug, Clone)]
pub struct FeedbackPreview {
    pub report: String,
    pub log: Option<String>,
}

/// A report written as an email, for "Send by email instead".
#[derive(Debug, Clone)]
pub struct FeedbackEmail {
    pub to: String,
    pub subject: String,
    pub body: String,
    /// Files to attach (screenshot, log).
    pub attachments: Vec<String>,
}

fn to_core(draft: FeedbackDraft) -> feedback::Draft {
    let mut device: Vec<(String, String)> = draft
        .device
        .into_iter()
        .map(|f| (f.name, f.value))
        .collect();
    if let Ok(accounts) = store().and_then(|s| Ok(s.accounts()?)) {
        let imap = accounts
            .iter()
            .filter(|a| matches!(a.kind, AccountKind::Imap { .. }))
            .count();
        let jmap = accounts.len() - imap;
        let mut kinds = Vec::new();
        if imap > 0 {
            kinds.push(format!("{imap} IMAP"));
        }
        if jmap > 0 {
            kinds.push(format!("{jmap} JMAP"));
        }
        if !kinds.is_empty() {
            device.push(("Accounts".into(), kinds.join(", ")));
        }
        // What the IMAP servers said they can do when connected to.
        let keys: Vec<u64> = accounts
            .iter()
            .filter_map(|a| match &a.kind {
                AccountKind::Imap { imap, username, .. } => {
                    Some(feedback::server_key(&imap.host, username))
                }
                AccountKind::Jmap { .. } => None,
            })
            .collect();
        if let Some(line) = feedback::servers_line(&keys) {
            device.push(("Servers".into(), line));
        }
    }
    feedback::Draft {
        kind: match draft.kind {
            FeedbackKind::Problem => Kind::Problem,
            FeedbackKind::Idea => Kind::Idea,
        },
        title: draft.title,
        description: draft.description,
        include_screenshot: draft.include_screenshot,
        include_log: draft.include_log,
        device,
        screens: draft.screens,
    }
}

/// Whether this build has a relay; without one only email is offered.
#[frb(sync)]
pub fn feedback_relay_enabled() -> bool {
    !feedback::relay_url().is_empty()
}

/// Where "Send by email instead" writes to; empty when this build has no
/// address.
#[frb(sync)]
pub fn feedback_address() -> String {
    feedback::FEEDBACK_ADDRESS.to_string()
}

/// Adds a line to the recent log (cleaned before it is kept). `level` is
/// "info", "warn" or "error".
#[frb(sync)]
pub fn feedback_log(level: String, area: String, message: String) {
    let level = match level.as_str() {
        "error" => Level::Error,
        "warn" => Level::Warn,
        _ => Level::Info,
    };
    feedback::log(level, &area, &message);
}

/// Keeps a crash for the next launch to offer a report. Never sent alone.
#[frb(sync)]
pub fn feedback_record_crash(text: String) {
    if let Some(dir) = DIR.get() {
        feedback::record_crash(dir, &text);
    }
}

/// Whether a crash from a previous session is waiting to be reported.
#[frb(sync)]
pub fn feedback_crash_waiting() -> bool {
    DIR.get()
        .is_some_and(|d| feedback::pending_crash(d).is_some())
}

/// The person said no to reporting the crash.
#[frb(sync)]
pub fn feedback_dismiss_crash() {
    if let Some(dir) = DIR.get() {
        feedback::dismiss_crash(dir);
    }
}

/// The sheet opened: fetch and solve a ticket while the person writes, so
/// Send is instant. Quietly does nothing offline or without a relay.
pub async fn feedback_prepare() -> Result<(), EngineError> {
    refresh_personal();
    if PREPARED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .is_some_and(|t| !t.expired(super::engine::now_secs() * 1000))
    {
        return Ok(());
    }
    let reports = reports()?;
    let Ok(relay) = Relay::new(feedback::relay_url()) else {
        return Ok(());
    };
    let install_id = reports.install_id().map_err(err)?;
    let engine = engine()?;
    let ticket = engine
        .runtime
        .spawn(async move { relay.ticket(&install_id).await })
        .await
        .map_err(err)?;
    if let Ok(ticket) = ticket {
        *PREPARED.lock().unwrap_or_else(|e| e.into_inner()) = Some(ticket);
    }
    Ok(())
}

/// "See what's sent".
#[frb(sync)]
pub fn feedback_preview(draft: FeedbackDraft) -> Result<FeedbackPreview, EngineError> {
    refresh_personal();
    let reports = reports()?;
    let draft = to_core(draft);
    let log = draft
        .include_log
        .then(|| feedback::report_log(reports.dir()));
    Ok(FeedbackPreview {
        report: feedback::preview(&draft, None),
        log,
    })
}

/// Send: saves the report and starts sending it. `screenshot` is the PNG
/// with the hidden parts already blurred; it is dropped unless the switch
/// is on.
#[frb(sync)]
pub fn feedback_submit(
    draft: FeedbackDraft,
    screenshot: Option<Vec<u8>>,
) -> Result<FeedbackReport, EngineError> {
    refresh_personal();
    let reports = reports()?;
    let ticket = PREPARED.lock().unwrap_or_else(|e| e.into_inner()).take();
    let report = reports
        .submit(&to_core(draft), screenshot.as_deref(), ticket)
        .map_err(err)?;
    feedback_send_queued();
    Ok(report.into())
}

/// Your reports, newest first.
#[frb(sync)]
pub fn feedback_reports() -> Result<Vec<FeedbackReport>, EngineError> {
    Ok(reports()?.list().into_iter().map(Into::into).collect())
}

/// Sends what is queued and due, in the background. Call at startup, when
/// the network comes back, and when Your reports opens.
#[frb(sync)]
pub fn feedback_send_queued() {
    let (Ok(engine), Ok(reports)) = (engine(), reports()) else {
        return;
    };
    let Ok(relay) = Relay::new(feedback::relay_url()) else {
        return;
    };
    static SENDING: Mutex<bool> = Mutex::new(false);
    {
        let mut busy = SENDING.lock().unwrap_or_else(|e| e.into_inner());
        if *busy {
            return;
        }
        *busy = true;
    }
    engine.runtime.spawn(async move {
        loop {
            if let Err(e) = feedback::send_queued(&reports, &relay).await {
                feedback::log(Level::Warn, "feedback", &e.to_string());
            }
            // A report waiting its turn (a few seconds after the sheet
            // opened) or a short backoff goes when due, not at the next
            // start of the app. Longer waits are left to the next start or
            // to the network coming back.
            let now = super::engine::now_secs();
            match feedback::next_due(&reports) {
                Some(due) if due - now <= 30 * 60 => {
                    let wait = (due - now).clamp(1, 30 * 60) as u64;
                    tokio::time::sleep(std::time::Duration::from_secs(wait)).await;
                }
                _ => break,
            }
        }
        *SENDING.lock().unwrap_or_else(|e| e.into_inner()) = false;
    });
}

/// Try again, for a failed report.
#[frb(sync)]
pub fn feedback_retry(id: String) -> Result<FeedbackReport, EngineError> {
    let report = reports()?.retry(&id).map_err(err)?;
    feedback_send_queued();
    Ok(report.into())
}

#[frb(sync)]
pub fn feedback_delete(id: String) -> Result<(), EngineError> {
    reports()?.delete(&id).map_err(err)
}

/// The report as an email for the composer.
#[frb(sync)]
pub fn feedback_email(id: String) -> Result<FeedbackEmail, EngineError> {
    let reports = reports()?;
    let report = reports.get(&id).map_err(err)?;
    let (subject, body, files) = feedback::email(&reports, &report);
    Ok(FeedbackEmail {
        to: feedback::FEEDBACK_ADDRESS.to_string(),
        subject,
        body,
        attachments: files
            .into_iter()
            .map(|p| p.to_string_lossy().into_owned())
            .collect(),
    })
}

/// The email went: the report is marked so and stops waiting.
#[frb(sync)]
pub fn feedback_mark_emailed(id: String) -> Result<FeedbackReport, EngineError> {
    Ok(reports()?.mark_emailed(&id).map_err(err)?.into())
}
