//! In-app reports: a problem or an idea, sent to the project's report
//! relay (`relay/` in the repository), which opens a GitHub issue. Nothing
//! leaves the device unless the person sends it, and only what they chose:
//! the screenshot and the log each have their own switch, and the log is
//! cleaned of addresses, names, servers and subjects as it is written.
//!
//! Reports wait on disk (`<dir>/<id>/report.json`, `screenshot.png`,
//! `log.txt`) and go in the background, so they also work offline.

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock, RwLock};
use std::time::Duration;

use regex::{Captures, Regex};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Where reports go unless a build sets `PIUMA_REPORT_RELAY`. Empty: the
/// relay is off and only "Send by email instead" is offered.
pub const DEFAULT_RELAY: &str = "https://piuma-report-relay.matte-maraffio.workers.dev";

/// Where "Send by email instead" writes to.
pub const FEEDBACK_ADDRESS: &str = "piuma@matteomaraffio.com";

/// The relay this build sends to; empty when it has none.
pub fn relay_url() -> &'static str {
    option_env!("PIUMA_REPORT_RELAY").unwrap_or(DEFAULT_RELAY)
}

// ---- Log ---------------------------------------------------------------

/// How much a log line matters.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Info,
    Warn,
    Error,
}

impl Level {
    fn letter(self) -> char {
        match self {
            Level::Info => 'I',
            Level::Warn => 'W',
            Level::Error => 'E',
        }
    }
}

const LOG_LINES: usize = 300;
static LOG: Mutex<VecDeque<String>> = Mutex::new(VecDeque::new());

/// Adds a line to the recent log, cleaned before it is kept: what is in
/// memory is already what a report would carry.
pub fn log(level: Level, area: &str, message: &str) {
    let line = format!(
        "{} {} {}: {}",
        clock(crate::pending::now()),
        level.letter(),
        area,
        clean(message).replace('\n', " ⏎ ")
    );
    let mut log = LOG.lock().unwrap_or_else(|e| e.into_inner());
    if log.len() == LOG_LINES {
        log.pop_front();
    }
    log.push_back(line);
}

/// The recent log, oldest line first.
pub fn recent_log() -> String {
    let log = LOG.lock().unwrap_or_else(|e| e.into_inner());
    log.iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .join("\n")
}

/// "HH:MM:SS" in UTC.
fn clock(secs: i64) -> String {
    let s = secs.rem_euclid(86_400);
    format!("{:02}:{:02}:{:02}", s / 3600, s / 60 % 60, s % 60)
}

/// The warnings and errors of `log`, or its last lines when there were
/// none, up to 6,000 characters: what the issue shows inline.
pub fn log_excerpt(log: &str) -> String {
    let lines: Vec<&str> = log.lines().collect();
    let problems: Vec<&str> = lines
        .iter()
        .copied()
        .filter(|l| l.contains(" W ") || l.contains(" E ") || l.starts_with("Crash"))
        .collect();
    let picked = if problems.is_empty() { lines } else { problems };
    let mut out: Vec<&str> = Vec::new();
    let mut size = 0;
    for line in picked.iter().rev().take(60) {
        if size + line.len() + 1 > 6000 {
            break;
        }
        size += line.len() + 1;
        out.push(line);
    }
    out.reverse();
    out.join("\n")
}

// ---- Cleaning ----------------------------------------------------------

/// Words that name the person: account names, addresses, logins, servers.
/// The app sets them when it opens and when accounts change.
static PERSONAL: RwLock<Vec<String>> = RwLock::new(Vec::new());

/// Sets the words [`clean`] always hides.
pub fn set_personal(words: Vec<String>) {
    let mut words: Vec<String> = words
        .into_iter()
        .map(|w| w.trim().to_string())
        .filter(|w| w.chars().count() >= 3)
        .collect();
    // Longest first, so "Matteo Neri" goes before "Matteo".
    words.sort_by_key(|w| std::cmp::Reverse(w.len()));
    words.dedup();
    *PERSONAL.write().unwrap_or_else(|e| e.into_inner()) = words;
}

struct Rules {
    login: Regex,
    secret: Regex,
    bearer: Regex,
    subject: Regex,
    reply: Regex,
    search: Regex,
    mailbox_command: Regex,
    mailbox_move: Regex,
    mailbox_named: Regex,
    url: Regex,
    path: Regex,
    message_id: Regex,
    email: Regex,
    token: Regex,
    ipv4: Regex,
    ipv6: Regex,
    host: Regex,
    quoted: Regex,
}

fn rules() -> &'static Rules {
    static RULES: OnceLock<Rules> = OnceLock::new();
    RULES.get_or_init(|| {
        let re = |p: &str| Regex::new(p).expect("valid pattern");
        Rules {
            login: re(r"(?i)\b(LOGIN|AUTHENTICATE|AUTH)\b[^\n]*"),
            secret: re(r"(?i)\b(password|passwd|pass|token|secret|authorization|cookie|key)\b(\s*[=:]\s*)\S+"),
            bearer: re(r"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]+"),
            subject: re(r"(?i)\b(subject|from|to|cc|bcc)(:\s*)[^\n]*"),
            // A subject quoted without its header: "Re: Dinner on Friday".
            reply: re(r"(?i)\b(re|fwd?)(:\s*)[^\n]*"),
            // Search terms, which say what the person looks for.
            search: re(r"\b(SEARCH|X-GM-RAW)\b[^\n]*"),
            // IMAP commands (always upper case) and the mailbox they name,
            // when it isn't quoted (quoted ones go with [`Rules::quoted`]).
            mailbox_command: re(
                r#"\b(SELECT|EXAMINE|STATUS|CREATE|DELETE|RENAME|SUBSCRIBE|UNSUBSCRIBE|APPEND)\s+[^"\s:<][^:\n]*"#,
            ),
            mailbox_move: re(r#"\b(MOVE|COPY)\s+([0-9:,*]+)\s+[^"\s:<][^:\n]*"#),
            mailbox_named: re(
                r"(?i)\b(mailbox|folder)\s+\S[^:\n]*?\s+(not found|doesn't exist|does not exist|is missing)",
            ),
            url: re(r#"(?i)\b(?:https?|wss?|imaps?|smtps?)://[^\s"'<>]+"#),
            // Absolute paths: they carry the person's user name and the
            // names of their files.
            path: re(
                r#"(?:\b[A-Za-z]:[\\/]|\\\\|/(?:data|storage|sdcard|home|Users|var|private|tmp|mnt|Volumes|Library)/)[^\s"'<>]*"#,
            ),
            message_id: re(r"<[^<>\s]+@[^<>\s]+>"),
            email: re(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
            // OAuth and JWT tokens, and any long opaque string.
            token: re(r"\b(?:ya29\.|eyJ)[A-Za-z0-9._-]+|\b[A-Za-z0-9_-]{40,}"),
            ipv4: re(r"\b\d{1,3}(?:\.\d{1,3}){3}\b"),
            ipv6: re(r"(?i)\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b"),
            host: re(r"(?i)\b(?:[a-z0-9-]+\.)+([a-z]{2,})\b"),
            quoted: re(r#""[^"\n]*""#),
        }
    })
}

/// File names that look like host names but name the app's own code.
const CODE_EXTENSIONS: &[&str] = &[
    "rs", "dart", "kt", "swift", "java", "json", "png", "jpg", "jpeg", "txt", "db", "so", "dll",
    "dylib", "html", "css", "js", "toml", "yaml", "md",
];

/// Removes from `text` what could tell who the person is or what their
/// mail says: logins, secrets and tokens, subjects and addresses, links,
/// file paths, message ids, servers and IP addresses, mailbox names and
/// search terms (quoted or not) and the person's own names. What stays is what a
/// developer needs: which step failed, and how.
pub fn clean(text: &str) -> String {
    let r = rules();
    let mut s = text.to_string();
    for word in PERSONAL.read().unwrap_or_else(|e| e.into_inner()).iter() {
        s = replace_ignoring_case(&s, word, "<account>");
    }
    s = r.login.replace_all(&s, "$1 <hidden>").into_owned();
    s = r.url.replace_all(&s, "<url>").into_owned();
    s = r.path.replace_all(&s, "<path>").into_owned();
    s = r.bearer.replace_all(&s, "$1 <token>").into_owned();
    s = r.secret.replace_all(&s, "$1$2<secret>").into_owned();
    s = r.subject.replace_all(&s, "$1$2<text>").into_owned();
    s = r.reply.replace_all(&s, "$1$2<text>").into_owned();
    s = r.search.replace_all(&s, "$1 <hidden>").into_owned();
    s = r
        .mailbox_command
        .replace_all(&s, "$1 <mailbox>")
        .into_owned();
    s = r
        .mailbox_move
        .replace_all(&s, "$1 $2 <mailbox>")
        .into_owned();
    s = r
        .mailbox_named
        .replace_all(&s, "$1 <mailbox> $2")
        .into_owned();
    s = r.message_id.replace_all(&s, "<message-id>").into_owned();
    s = r.email.replace_all(&s, "<email>").into_owned();
    s = r.token.replace_all(&s, "<token>").into_owned();
    s = r.ipv4.replace_all(&s, "<ip>").into_owned();
    s = r.ipv6.replace_all(&s, "<ip>").into_owned();
    s = r
        .host
        .replace_all(&s, |c: &Captures| {
            let ext = c[1].to_ascii_lowercase();
            if CODE_EXTENSIONS.contains(&ext.as_str()) {
                c[0].to_string()
            } else {
                "<host>".to_string()
            }
        })
        .into_owned();
    r.quoted.replace_all(&s, "\"<text>\"").into_owned()
}

fn replace_ignoring_case(text: &str, word: &str, with: &str) -> String {
    match Regex::new(&format!("(?i){}", regex::escape(word))) {
        Ok(re) => re.replace_all(text, with).into_owned(),
        Err(_) => text.to_string(),
    }
}

// ---- Servers -----------------------------------------------------------

/// The IMAP capabilities a report names, in the order shown: the ones that
/// change how sync, moves and push behave.
pub const SERVER_CAPABILITIES: &[&str] = &[
    "IDLE",
    "MOVE",
    "CONDSTORE",
    "QRESYNC",
    "UIDPLUS",
    "SPECIAL-USE",
    "COMPRESS=DEFLATE",
];

/// What each IMAP server said it can do when it was last connected to,
/// this session, by [`server_key`]. Memory only: no names, just a number
/// and capabilities from [`SERVER_CAPABILITIES`].
static SERVERS: Mutex<Vec<(u64, Vec<&'static str>)>> = Mutex::new(Vec::new());

/// A number that tells one account's server from another's without
/// naming it.
pub fn server_key(host: &str, username: &str) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    host.to_ascii_lowercase().hash(&mut h);
    username.hash(&mut h);
    h.finish()
}

/// Notes what the server behind `key` can do; `has` answers for each of
/// [`SERVER_CAPABILITIES`]. Called by the IMAP connection after login.
pub fn note_server(key: u64, has: impl Fn(&str) -> bool) {
    let caps: Vec<&'static str> = SERVER_CAPABILITIES
        .iter()
        .copied()
        .filter(|c| has(c))
        .collect();
    let mut servers = SERVERS.lock().unwrap_or_else(|e| e.into_inner());
    match servers.iter_mut().find(|(k, _)| *k == key) {
        Some(entry) => entry.1 = caps,
        None => servers.push((key, caps)),
    }
}

/// The Servers line of a report: the capabilities of the servers of
/// `accounts` (by [`server_key`]) connected to this session, as
/// "IDLE MOVE (1 of 2) CONDSTORE". One that only some have says how many.
/// None when none was connected to yet; "none" when none has any.
pub fn servers_line(accounts: &[u64]) -> Option<String> {
    let servers = SERVERS.lock().unwrap_or_else(|e| e.into_inner());
    let seen: Vec<&Vec<&str>> = servers
        .iter()
        .filter(|(k, _)| accounts.contains(k))
        .map(|(_, caps)| caps)
        .collect();
    summary(&seen)
}

fn summary(seen: &[&Vec<&str>]) -> Option<String> {
    if seen.is_empty() {
        return None;
    }
    let words: Vec<String> = SERVER_CAPABILITIES
        .iter()
        .filter_map(|cap| {
            let n = seen.iter().filter(|caps| caps.contains(cap)).count();
            match n {
                0 => None,
                n if n == seen.len() => Some(cap.to_string()),
                n => Some(format!("{cap} ({n} of {})", seen.len())),
            }
        })
        .collect();
    Some(if words.is_empty() {
        "none".to_string()
    } else {
        words.join(" ")
    })
}

// ---- Reports -----------------------------------------------------------

/// What kind of report.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Problem,
    Idea,
}

/// Where a report is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    /// Waiting to go; `Report::waiting` says why.
    Queued,
    /// On its way now.
    Sending,
    /// An issue exists: `Report::issue`.
    Sent,
    /// The relay refused it, or it kept failing; it can be tried again or
    /// sent by email.
    Failed,
    /// The person sent it by email instead.
    Emailed,
}

/// Why a queued report waits.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Waiting {
    /// Its turn comes soon (the relay spaces reports out).
    Turn,
    /// No connection, or the relay could not be reached.
    Offline,
    /// The relay took its fill of reports for today.
    Paused,
}

/// What the person wrote and chose, before it becomes a report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Draft {
    pub kind: Kind,
    pub title: String,
    pub description: String,
    pub include_screenshot: bool,
    pub include_log: bool,
    /// App, system, device, screen size, language, network, screen, in the
    /// order shown.
    pub device: Vec<(String, String)>,
    /// The last screens visited, "HH:MM:SS Name", oldest first.
    pub screens: Vec<String>,
}

/// A report, saved.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Report {
    pub id: String,
    pub kind: Kind,
    pub title: String,
    pub description: String,
    /// Unix seconds.
    pub created_at: i64,
    pub device: Vec<(String, String)>,
    pub screens: Vec<String>,
    pub has_screenshot: bool,
    pub has_log: bool,
    pub status: Status,
    #[serde(default)]
    pub waiting: Option<Waiting>,
    /// When to try again, Unix seconds.
    #[serde(default)]
    pub next_try: i64,
    #[serde(default)]
    pub tries: u32,
    /// The issue number once it exists.
    #[serde(default)]
    pub issue: Option<u32>,
    #[serde(default)]
    pub ticket: Option<Ticket>,
}

/// A draft cleaned and capped as it would be sent.
fn tidy(draft: &Draft) -> (String, String, Vec<(String, String)>, Vec<String>) {
    let cut = |s: &str, max: usize| s.chars().take(max).collect::<String>();
    let title = cut(
        &draft.title.split_whitespace().collect::<Vec<_>>().join(" "),
        200,
    );
    let description = cut(draft.description.trim(), 20_000);
    let device = draft
        .device
        .iter()
        .take(20)
        .map(|(k, v)| (cut(k, 40), cut(&clean(v), 200)))
        .collect();
    let screens = draft
        .screens
        .iter()
        .rev()
        .take(12)
        .rev()
        .map(|s| cut(&clean(s), 120))
        .collect();
    (title, description, device, screens)
}

/// The log a report carries: the last crash, if any, then the recent log.
pub fn report_log(dir: &Path) -> String {
    let crash = pending_crash(dir)
        .map(|c| format!("Crash (previous session)\n{c}\n\n"))
        .unwrap_or_default();
    let log = recent_log();
    let log = if log.is_empty() {
        "No log lines this session.".to_string()
    } else {
        log
    };
    // Cleaned again: names set after a line was written still go.
    clean(&format!("{crash}{log}"))
}

/// Exactly what Send would send, as text: the report, then the log if it
/// goes with it. The screenshot is shown by the app.
pub fn preview(draft: &Draft, log: Option<&str>) -> String {
    let (title, description, device, screens) = tidy(draft);
    let mut out = vec![
        format!(
            "{}: {}",
            match draft.kind {
                Kind::Problem => "Problem",
                Kind::Idea => "Idea",
            },
            title
        ),
        String::new(),
    ];
    if !description.is_empty() {
        out.push(description);
        out.push(String::new());
    }
    out.push("Device and app".into());
    out.extend(device.iter().map(|(k, v)| format!("{k}: {v}")));
    if !screens.is_empty() {
        out.push(String::new());
        out.push("Recent screens".into());
        out.extend(screens);
    }
    if let Some(log) = log {
        out.push(String::new());
        out.push("Log".into());
        out.push(log.to_string());
    }
    out.join("\n")
}

#[derive(Debug, thiserror::Error)]
pub enum FeedbackError {
    #[error("report storage: {0}")]
    Io(#[from] std::io::Error),
    #[error("report data: {0}")]
    Data(#[from] serde_json::Error),
    #[error("no title")]
    NoTitle,
    #[error("no such report")]
    NotFound,
}

/// The reports on this device.
pub struct Reports {
    dir: PathBuf,
}

impl Reports {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Reports { dir: dir.into() }
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    fn report_dir(&self, id: &str) -> PathBuf {
        self.dir.join(id)
    }

    /// Random, per installation; the relay only keeps an HMAC of it, to
    /// space reports out.
    pub fn install_id(&self) -> Result<String, FeedbackError> {
        let path = self.dir.join("install-id");
        if let Ok(id) = std::fs::read_to_string(&path) {
            let id = id.trim().to_string();
            if id.len() == 32 {
                return Ok(id);
            }
        }
        std::fs::create_dir_all(&self.dir)?;
        let id = random_hex(16);
        std::fs::write(&path, &id)?;
        Ok(id)
    }

    /// Saves a new report, queued, with the screenshot and the log if the
    /// person kept them on.
    pub fn submit(
        &self,
        draft: &Draft,
        screenshot: Option<&[u8]>,
        ticket: Option<Ticket>,
    ) -> Result<Report, FeedbackError> {
        let (title, description, device, screens) = tidy(draft);
        if title.is_empty() {
            return Err(FeedbackError::NoTitle);
        }
        let id = format!("{}-{}", crate::pending::now(), random_hex(4));
        let dir = self.report_dir(&id);
        std::fs::create_dir_all(&dir)?;
        let screenshot = screenshot.filter(|_| draft.include_screenshot);
        if let Some(png) = screenshot {
            std::fs::write(dir.join("screenshot.png"), png)?;
        }
        if draft.include_log {
            std::fs::write(dir.join("log.txt"), report_log(&self.dir))?;
            dismiss_crash(&self.dir);
        }
        let report = Report {
            id,
            kind: draft.kind,
            title,
            description,
            created_at: crate::pending::now(),
            device,
            screens,
            has_screenshot: screenshot.is_some(),
            has_log: draft.include_log,
            status: Status::Queued,
            waiting: Some(Waiting::Turn),
            next_try: 0,
            tries: 0,
            issue: None,
            ticket,
        };
        self.save(&report)?;
        Ok(report)
    }

    pub fn save(&self, report: &Report) -> Result<(), FeedbackError> {
        let dir = self.report_dir(&report.id);
        std::fs::create_dir_all(&dir)?;
        let tmp = dir.join("report.json.tmp");
        std::fs::write(&tmp, serde_json::to_vec_pretty(report)?)?;
        std::fs::rename(tmp, dir.join("report.json"))?;
        Ok(())
    }

    /// Every report, newest first.
    pub fn list(&self) -> Vec<Report> {
        let Ok(entries) = std::fs::read_dir(&self.dir) else {
            return Vec::new();
        };
        let mut out: Vec<Report> = entries
            .flatten()
            .filter_map(|e| std::fs::read(e.path().join("report.json")).ok())
            .filter_map(|b| serde_json::from_slice(&b).ok())
            .collect();
        out.sort_by(|a, b| b.created_at.cmp(&a.created_at).then(b.id.cmp(&a.id)));
        out
    }

    pub fn get(&self, id: &str) -> Result<Report, FeedbackError> {
        if !valid_id(id) {
            return Err(FeedbackError::NotFound);
        }
        let bytes = std::fs::read(self.report_dir(id).join("report.json"))
            .map_err(|_| FeedbackError::NotFound)?;
        Ok(serde_json::from_slice(&bytes)?)
    }

    pub fn delete(&self, id: &str) -> Result<(), FeedbackError> {
        if !valid_id(id) {
            return Err(FeedbackError::NotFound);
        }
        match std::fs::remove_dir_all(self.report_dir(id)) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.into()),
            _ => Ok(()),
        }
    }

    /// The files that go with a report: (form field, file name, type, path).
    pub fn files(
        &self,
        report: &Report,
    ) -> Vec<(&'static str, &'static str, &'static str, PathBuf)> {
        let dir = self.report_dir(&report.id);
        let mut out = Vec::new();
        if report.has_screenshot {
            out.push((
                "screenshot",
                "screenshot.png",
                "image/png",
                dir.join("screenshot.png"),
            ));
        }
        if report.has_log {
            out.push(("logs", "log.txt", "text/plain", dir.join("log.txt")));
        }
        out.retain(|f| f.3.exists());
        out
    }

    /// Puts a failed report back in the queue, to go now.
    pub fn retry(&self, id: &str) -> Result<Report, FeedbackError> {
        let mut report = self.get(id)?;
        if matches!(report.status, Status::Failed | Status::Queued) {
            report.status = Status::Queued;
            report.waiting = Some(Waiting::Turn);
            report.next_try = 0;
            report.tries = 0;
            self.save(&report)?;
        }
        Ok(report)
    }

    /// Marks a report as sent by email instead.
    pub fn mark_emailed(&self, id: &str) -> Result<Report, FeedbackError> {
        let mut report = self.get(id)?;
        if report.status != Status::Sent {
            report.status = Status::Emailed;
            report.waiting = None;
            self.save(&report)?;
        }
        Ok(report)
    }
}

/// Ids are made here: "<seconds>-<hex>". Anything else could reach outside
/// the folder.
fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 40 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

fn random_hex(bytes: usize) -> String {
    let mut b = vec![0u8; bytes];
    getrandom::getrandom(&mut b).expect("the system has randomness");
    hex(&b)
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

// ---- Email instead -----------------------------------------------------

/// The report as an email the person reviews and sends from their own
/// account: subject, body and the files to attach.
pub fn email(reports: &Reports, report: &Report) -> (String, String, Vec<PathBuf>) {
    let subject = format!(
        "[Piuma {}] {}",
        match report.kind {
            Kind::Problem => "problem",
            Kind::Idea => "idea",
        },
        report.title
    );
    let mut body = vec![
        report.description.clone(),
        String::new(),
        "Device and app".into(),
    ];
    body.extend(report.device.iter().map(|(k, v)| format!("{k}: {v}")));
    if !report.screens.is_empty() {
        body.push(String::new());
        body.push("Recent screens".into());
        body.extend(report.screens.iter().cloned());
    }
    let files = reports.files(report).into_iter().map(|f| f.3).collect();
    (subject, body.join("\n"), files)
}

// ---- Crash -------------------------------------------------------------

const CRASH_FILE: &str = "last-crash.txt";

/// Keeps what the app knew when it crashed, cleaned, for the next launch to
/// offer a report. Never sent on its own.
pub fn record_crash(dir: &Path, text: &str) {
    let text: String = clean(text).chars().take(20_000).collect();
    let _ = std::fs::create_dir_all(dir);
    let _ = std::fs::write(dir.join(CRASH_FILE), text);
}

/// The crash from a previous session, if one is waiting to be reported.
pub fn pending_crash(dir: &Path) -> Option<String> {
    std::fs::read_to_string(dir.join(CRASH_FILE))
        .ok()
        .filter(|t| !t.trim().is_empty())
}

/// Forgets the waiting crash (reported, or the person said no).
pub fn dismiss_crash(dir: &Path) {
    let _ = std::fs::remove_file(dir.join(CRASH_FILE));
}

// ---- Relay -------------------------------------------------------------

/// A relay ticket: proof that the report was prepared a moment ago, solved
/// while the person writes so Send is instant.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ticket {
    pub ticket: String,
    pub seed: String,
    pub bits: u32,
    /// Not before / expiry, Unix milliseconds.
    pub nbf: i64,
    pub exp: i64,
    pub nonce: Option<String>,
}

impl Ticket {
    /// Expired, or about to.
    pub fn expired(&self, now_ms: i64) -> bool {
        now_ms > self.exp - 30_000
    }
}

/// A nonce such that sha256("seed:nonce") starts with `bits` zero bits;
/// the relay checks the same rule.
pub fn solve_pow(seed: &str, bits: u32) -> String {
    if bits == 0 {
        return "0".into();
    }
    let mut n: u64 = 0;
    loop {
        let digest = Sha256::digest(format!("{seed}:{n}").as_bytes());
        if leading_zero_bits(&digest) >= bits {
            return n.to_string();
        }
        n += 1;
    }
}

pub fn leading_zero_bits(bytes: &[u8]) -> u32 {
    let mut bits = 0;
    for b in bytes {
        if *b == 0 {
            bits += 8;
            continue;
        }
        return bits + b.leading_zeros();
    }
    bits
}

/// What the relay said about a report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Created {
        number: u32,
    },
    /// Try again in this many seconds.
    Later {
        secs: i64,
        why: Waiting,
    },
    /// This ticket already opened an issue.
    Duplicate,
    /// The relay refused the report itself; trying again won't help.
    Rejected {
        status: u16,
    },
}

#[derive(Debug, thiserror::Error)]
pub enum RelayError {
    #[error("no relay in this build")]
    Off,
    #[error("relay unreachable: {0}")]
    Network(String),
    #[error("relay error {0}")]
    Status(u16),
    #[error("relay answer: {0}")]
    Answer(String),
    #[error(transparent)]
    Feedback(#[from] FeedbackError),
}

/// The report relay.
pub struct Relay {
    base: String,
    http: reqwest::Client,
}

impl Relay {
    pub fn new(base: &str) -> Result<Relay, RelayError> {
        let base = base.trim_end_matches('/').to_string();
        if base.is_empty() {
            return Err(RelayError::Off);
        }
        let http = crate::tls::http_client()
            .timeout(Duration::from_secs(60))
            .user_agent("piuma-mail")
            .build()
            .map_err(|e| RelayError::Network(e.to_string()))?;
        Ok(Relay { base, http })
    }

    /// A fresh ticket, solved.
    pub async fn ticket(&self, install_id: &str) -> Result<Ticket, RelayError> {
        let res = self
            .http
            .post(format!("{}/challenge", self.base))
            .json(&serde_json::json!({ "installId": install_id }))
            .send()
            .await
            .map_err(|e| RelayError::Network(e.to_string()))?;
        if !res.status().is_success() {
            return Err(RelayError::Status(res.status().as_u16()));
        }
        #[derive(Deserialize)]
        struct Challenge {
            ticket: String,
            seed: String,
            bits: u32,
            nbf: i64,
            exp: i64,
        }
        let c: Challenge = res
            .json()
            .await
            .map_err(|e| RelayError::Answer(e.to_string()))?;
        let seed = c.seed.clone();
        let bits = c.bits.min(28);
        let nonce = tokio::task::spawn_blocking(move || solve_pow(&seed, bits))
            .await
            .map_err(|e| RelayError::Answer(e.to_string()))?;
        Ok(Ticket {
            ticket: c.ticket,
            seed: c.seed,
            bits: c.bits,
            nbf: c.nbf,
            exp: c.exp,
            nonce: Some(nonce),
        })
    }

    /// Posts a report with its files.
    pub async fn send(
        &self,
        install_id: &str,
        ticket: &Ticket,
        report: &Report,
        files: Vec<(&'static str, &'static str, &'static str, Vec<u8>)>,
        log: Option<&str>,
    ) -> Result<Outcome, RelayError> {
        let meta = serde_json::json!({
            "installId": install_id,
            "ticket": ticket.ticket,
            "powNonce": ticket.nonce,
            "kind": report.kind,
            "title": report.title,
            "description": report.description,
            "device": report
                .device
                .iter()
                .map(|(k, v)| (k.clone(), serde_json::Value::from(v.as_str())))
                .collect::<serde_json::Map<String, serde_json::Value>>(),
            "screens": report.screens,
            "logExcerpt": log.map(log_excerpt).unwrap_or_default(),
        });
        let mut form = reqwest::multipart::Form::new().text("report", meta.to_string());
        for (field, name, mime, bytes) in files {
            let part = reqwest::multipart::Part::bytes(bytes)
                .file_name(name)
                .mime_str(mime)
                .map_err(|e| RelayError::Answer(e.to_string()))?;
            form = form.part(field, part);
        }
        let res = self
            .http
            .post(format!("{}/report", self.base))
            .multipart(form)
            .send()
            .await
            .map_err(|e| RelayError::Network(e.to_string()))?;
        let status = res.status().as_u16();
        let retry_after = res
            .headers()
            .get("retry-after")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse::<i64>().ok());
        Ok(match status {
            201 => {
                #[derive(Deserialize)]
                struct Created {
                    number: u32,
                }
                let c: Created = res
                    .json()
                    .await
                    .map_err(|e| RelayError::Answer(e.to_string()))?;
                Outcome::Created { number: c.number }
            }
            403 => Outcome::Later {
                secs: retry_after.unwrap_or(0),
                why: Waiting::Turn,
            },
            409 => Outcome::Duplicate,
            429 => Outcome::Later {
                secs: retry_after.unwrap_or(60),
                why: Waiting::Turn,
            },
            503 => Outcome::Later {
                secs: retry_after.unwrap_or(6 * 3600),
                why: Waiting::Paused,
            },
            500..=599 => return Err(RelayError::Status(status)),
            _ => Outcome::Rejected { status },
        })
    }
}

/// Tries after which a report stops retrying on its own.
const MAX_TRIES: u32 = 6;

/// Waits between tries when the relay can't be reached: 1 min, 5 min,
/// 30 min, then 2 h.
fn backoff(tries: u32) -> i64 {
    match tries {
        0 | 1 => 60,
        2 => 300,
        3 => 1800,
        _ => 7200,
    }
}

/// Sends every queued report whose time has come. Returns how many opened
/// an issue. Safe to call often: a report not yet due is left alone.
pub async fn send_queued(reports: &Reports, relay: &Relay) -> Result<usize, RelayError> {
    let install_id = reports.install_id()?;
    let mut sent = 0;
    for mut report in reports.list() {
        let now = crate::pending::now();
        // A report left "sending" was cut off (the app closed on the way):
        // only one sender runs at a time, so it is due again.
        let cut_off = report.status == Status::Sending;
        if !(report.status == Status::Queued || cut_off) || report.next_try > now {
            continue;
        }
        report.status = Status::Sending;
        reports.save(&report)?;
        let result = send_one(reports, relay, &install_id, &mut report).await;
        match result {
            Ok(Outcome::Created { number }) => {
                report.status = Status::Sent;
                report.issue = Some(number);
                report.waiting = None;
                report.ticket = None;
                sent += 1;
            }
            Ok(Outcome::Duplicate) => {
                // The ticket was used: the issue exists, or the ticket was
                // taken by a try that died on the way. A fresh ticket next.
                report.status = Status::Queued;
                report.ticket = None;
                report.waiting = Some(Waiting::Turn);
                report.next_try = now;
                report.tries += 1;
            }
            Ok(Outcome::Later { secs, why }) => {
                report.status = Status::Queued;
                report.waiting = Some(why);
                report.next_try = now + secs.max(1);
            }
            Ok(Outcome::Rejected { status }) => {
                log(
                    Level::Warn,
                    "feedback",
                    &format!("relay refused report: {status}"),
                );
                report.status = Status::Failed;
                report.waiting = None;
                report.ticket = None;
            }
            Err(e) => {
                log(Level::Warn, "feedback", &e.to_string());
                report.tries += 1;
                report.ticket = None;
                if report.tries >= MAX_TRIES {
                    report.status = Status::Failed;
                    report.waiting = None;
                } else {
                    report.status = Status::Queued;
                    report.waiting = Some(Waiting::Offline);
                    report.next_try = now + backoff(report.tries);
                }
            }
        }
        if report.tries >= MAX_TRIES && report.status == Status::Queued {
            report.status = Status::Failed;
            report.waiting = None;
        }
        reports.save(&report)?;
    }
    Ok(sent)
}

/// When the next queued report is due, if one is: the sender waits for it
/// rather than leaving it for the next start of the app.
pub fn next_due(reports: &Reports) -> Option<i64> {
    reports
        .list()
        .iter()
        .filter(|r| r.status == Status::Queued)
        .map(|r| r.next_try)
        .min()
}

async fn send_one(
    reports: &Reports,
    relay: &Relay,
    install_id: &str,
    report: &mut Report,
) -> Result<Outcome, RelayError> {
    let now_ms = crate::pending::now() * 1000;
    let ticket = match report.ticket.take() {
        Some(t) if !t.expired(now_ms) && t.nonce.is_some() => t,
        _ => relay.ticket(install_id).await?,
    };
    if ticket.nbf > now_ms {
        let secs = (ticket.nbf - now_ms + 999) / 1000;
        report.ticket = Some(ticket);
        return Ok(Outcome::Later {
            secs,
            why: Waiting::Turn,
        });
    }
    let mut files = Vec::new();
    let mut log = None;
    for (field, name, mime, path) in reports.files(report) {
        let bytes = std::fs::read(&path).map_err(FeedbackError::from)?;
        if field == "logs" {
            log = Some(String::from_utf8_lossy(&bytes).into_owned());
        }
        files.push((field, name, mime, bytes));
    }
    let outcome = relay
        .send(install_id, &ticket, report, files, log.as_deref())
        .await;
    if matches!(outcome, Ok(Outcome::Later { .. })) {
        // Too early for this ticket: keep it, it works once its time comes.
        report.ticket = Some(ticket);
    }
    outcome
}

#[cfg(test)]
mod tests {
    use super::*;

    fn draft() -> Draft {
        Draft {
            kind: Kind::Problem,
            title: "  Inbox   stops syncing ".into(),
            description: "After sleep".into(),
            include_screenshot: false,
            include_log: true,
            device: vec![("App".into(), "0.1.0 (120)".into())],
            screens: vec!["21:30:12 Inbox".into()],
        }
    }

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("piuma-feedback-{name}-{}", random_hex(4)));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    #[test]
    fn cleaning_hides_people_servers_and_secrets() {
        let cases = [
            ("LOGIN matteo secret123", "LOGIN <hidden>"),
            ("password=hunter2 next", "password=<secret> next"),
            (
                "Authorization: Bearer abc.def",
                "Authorization: <secret> <token>",
            ),
            ("from anna@example.com", "from <email>"),
            ("id <abc123@mail.example.com> gone", "id <message-id> gone"),
            (
                "connect imap.example.com:993 failed",
                "connect <host>:993 failed",
            ),
            ("dial 192.168.1.20 refused", "dial <ip> refused"),
            ("dial 2001:db8:0:1::1 refused", "dial <ip>::1 refused"),
            ("SELECT \"Bills 2026\"", "SELECT \"<text>\""),
            ("Subject: Your payslip", "Subject: <text>"),
            ("see https://host.example/x?token=1", "see <url>"),
            (
                "panic at core/src/imap.rs:120",
                "panic at core/src/imap.rs:120",
            ),
            ("sync took 12:30:45 ms", "sync took 12:30:45 ms"),
            (
                "SELECT Bills 2026: NO Mailbox doesn't exist",
                "SELECT <mailbox>: NO Mailbox doesn't exist",
            ),
            (
                "UID MOVE 1:4 Work/Clients: NO",
                "UID MOVE 1:4 <mailbox>: NO",
            ),
            (
                "mailbox Work/Clients Rossi not found",
                "mailbox <mailbox> not found",
            ),
            ("SEARCH failed for electricity bill", "SEARCH <hidden>"),
            ("X-GM-RAW receipt amazon", "X-GM-RAW <hidden>"),
            (
                "message Re: Dinner on Friday from Anna not parsed",
                "message Re: <text>",
            ),
            (
                "file C:\\Users\\anna\\AppData\\Roaming\\store.db locked",
                "file <path> locked",
            ),
            (
                "open /data/user/0/app/files/anna/Lease.pdf failed",
                "open <path> failed",
            ),
            (
                "at file:///H:/work/app/lib/main.dart:12",
                "at file:///<path>",
            ),
            (
                "refresh failed: invalid_grant ya29.a0AfB_byC1234567890",
                "refresh failed: invalid_grant <token>",
            ),
            ("status 503 from relay", "status 503 from relay"),
        ];
        for (input, want) in cases {
            assert_eq!(clean(input), want, "{input}");
        }
    }

    #[test]
    fn personal_words_go_whatever_their_case() {
        set_personal(vec!["Matteo Neri".into(), "matteo".into(), "x".into()]);
        assert_eq!(
            clean("hello MATTEO NERI and Matteo"),
            "hello <account> and <account>"
        );
        set_personal(Vec::new());
    }

    #[test]
    fn the_log_keeps_cleaned_lines_and_a_cap() {
        for i in 0..(LOG_LINES + 5) {
            log(
                Level::Info,
                "test",
                &format!("line {i} for bob@example.com"),
            );
        }
        log(Level::Error, "imap", "boom");
        let all = recent_log();
        assert_eq!(all.lines().count(), LOG_LINES);
        assert!(!all.contains("bob@example.com"));
        assert!(all.ends_with(" E imap: boom"));
        let excerpt = log_excerpt(&all);
        assert!(excerpt
            .lines()
            .all(|l| l.contains(" E ") || l.contains(" W ")));
    }

    #[test]
    fn excerpt_falls_back_to_recent_activity() {
        let log = (0..100)
            .map(|i| format!("00:00:00 I a: {i}"))
            .collect::<Vec<_>>()
            .join("\n");
        let excerpt = log_excerpt(&log);
        assert_eq!(excerpt.lines().count(), 60);
        assert!(excerpt.ends_with(": 99"));
    }

    #[test]
    fn reports_round_trip_on_disk() {
        let reports = Reports::new(temp_dir("store"));
        let mut d = draft();
        d.include_screenshot = true;
        let r = reports.submit(&d, Some(&[1, 2, 3]), None).unwrap();
        assert_eq!(r.title, "Inbox stops syncing");
        assert_eq!(r.status, Status::Queued);
        assert!(r.has_screenshot && r.has_log);
        assert_eq!(reports.files(&r).len(), 2);
        assert_eq!(reports.list(), vec![r.clone()]);
        assert_eq!(reports.mark_emailed(&r.id).unwrap().status, Status::Emailed);
        reports.delete(&r.id).unwrap();
        assert!(reports.list().is_empty());
        assert!(reports.get("../etc").is_err());
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    #[test]
    fn switches_off_means_nothing_saved() {
        let reports = Reports::new(temp_dir("off"));
        let mut d = draft();
        d.include_log = false;
        let r = reports.submit(&d, Some(&[1, 2, 3]), None).unwrap();
        assert!(!r.has_screenshot && !r.has_log);
        assert!(reports.files(&r).is_empty());
        assert!(!reports.dir().join(&r.id).join("screenshot.png").exists());
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    #[test]
    fn a_title_is_needed() {
        let reports = Reports::new(temp_dir("title"));
        let mut d = draft();
        d.title = "   ".into();
        assert!(matches!(
            reports.submit(&d, None, None),
            Err(FeedbackError::NoTitle)
        ));
    }

    #[tokio::test]
    async fn a_report_cut_off_while_sending_goes_again() {
        let reports = Reports::new(temp_dir("cutoff"));
        let mut r = reports.submit(&draft(), None, None).unwrap();
        r.status = Status::Sending;
        reports.save(&r).unwrap();
        // Nothing listens there: the try fails and the report waits its
        // next turn instead of staying "sending" for good.
        let relay = Relay::new("http://127.0.0.1:9").unwrap();
        send_queued(&reports, &relay).await.unwrap();
        let after = reports.get(&r.id).unwrap();
        assert_eq!((after.status, after.tries), (Status::Queued, 1));
        assert_eq!(next_due(&reports), Some(after.next_try));
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    #[test]
    fn install_id_stays() {
        let reports = Reports::new(temp_dir("install"));
        let a = reports.install_id().unwrap();
        assert_eq!(a.len(), 32);
        assert_eq!(reports.install_id().unwrap(), a);
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    #[test]
    fn a_crash_waits_once() {
        let dir = temp_dir("crash");
        assert!(pending_crash(&dir).is_none());
        record_crash(&dir, "Null check at reader for anna@example.com");
        let crash = pending_crash(&dir).unwrap();
        assert!(crash.contains("<email>"));
        assert!(report_log(&dir).starts_with("Crash (previous session)"));
        dismiss_crash(&dir);
        assert!(pending_crash(&dir).is_none());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn preview_is_what_goes() {
        let text = preview(&draft(), Some("00:00:00 E x: y"));
        assert!(text.starts_with(
            "Problem: Inbox stops syncing\n\nAfter sleep\n\nDevice and app\nApp: 0.1.0 (120)"
        ));
        assert!(text.contains("Recent screens\n21:30:12 Inbox"));
        assert!(text.ends_with("Log\n00:00:00 E x: y"));
        assert!(!preview(&draft(), None).contains("\nLog\n"));
    }

    #[test]
    fn pow_matches_the_relay_rule() {
        let nonce = solve_pow("abc", 12);
        let digest = Sha256::digest(format!("abc:{nonce}").as_bytes());
        assert!(leading_zero_bits(&digest) >= 12);
        assert_eq!(leading_zero_bits(&[0, 0x0f]), 12);
        assert_eq!(leading_zero_bits(&[0x80]), 0);
    }

    #[test]
    fn email_carries_the_report() {
        let reports = Reports::new(temp_dir("email"));
        let r = reports.submit(&draft(), None, None).unwrap();
        let (subject, body, files) = email(&reports, &r);
        assert_eq!(subject, "[Piuma problem] Inbox stops syncing");
        assert!(body.starts_with("After sleep\n\nDevice and app\nApp: 0.1.0 (120)"));
        assert_eq!(files.len(), 1);
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    #[test]
    fn servers_say_what_they_can_do_and_who_cannot() {
        let both = vec!["IDLE", "MOVE", "CONDSTORE"];
        let one = vec!["IDLE", "CONDSTORE", "UIDPLUS"];
        assert_eq!(summary(&[]), None);
        assert_eq!(summary(&[&both]).as_deref(), Some("IDLE MOVE CONDSTORE"));
        assert_eq!(
            summary(&[&both, &one]).as_deref(),
            Some("IDLE MOVE (1 of 2) CONDSTORE UIDPLUS (1 of 2)")
        );
        assert_eq!(summary(&[&vec![]]).as_deref(), Some("none"));

        // Noted by key; only the accounts asked about count, and a server
        // noted again replaces what it said before.
        let a = server_key("imap.example.com", "anna");
        let b = server_key("IMAP.example.com", "bruno");
        assert_ne!(a, b);
        assert_eq!(a, server_key("IMAP.EXAMPLE.COM", "anna"));
        note_server(a, |c| c == "MOVE");
        note_server(a, |c| ["IDLE", "MOVE", "QRESYNC", "XLIST"].contains(&c));
        note_server(b, |c| c == "IDLE" || c == "COMPRESS=DEFLATE");
        assert_eq!(
            servers_line(&[a, b]).as_deref(),
            Some("IDLE MOVE (1 of 2) QRESYNC (1 of 2) COMPRESS=DEFLATE (1 of 2)")
        );
        assert_eq!(servers_line(&[a]).as_deref(), Some("IDLE MOVE QRESYNC"));
        assert_eq!(servers_line(&[42]), None);

        // The line goes through cleaning untouched.
        let line = servers_line(&[a, b]).unwrap();
        assert_eq!(clean(&line), line);
    }
}
