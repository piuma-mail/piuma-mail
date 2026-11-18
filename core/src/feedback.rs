//! In-app reports: a problem or an idea, sent to the project's report
//! relay (`relay/` in the repository), which opens a GitHub issue. Nothing
//! leaves the device unless the person sends it, and only what they chose:
//! the screenshot and the log each have their own switch, and the log is
//! scrubbed of addresses, names, servers, subjects, server replies and
//! quoted text as it is written. Scrubbing is a best effort: "See what's
//! sent" shows the log as it would go.
//!
//! Reports wait on disk (`<dir>/<id>/report.json`, `screenshot.png`,
//! `log.txt` and the images and videos the person attached,
//! `attachment-1.png`…) and go in the background, so they also work
//! offline.
//!
//! A fork points its build elsewhere with environment variables read at
//! build time (see CONTRIBUTING.md): `PIUMA_REPORT_RELAY`,
//! `PIUMA_FEEDBACK_ADDRESS`, `PIUMA_PRIVACY_CONTROLLER`,
//! `PIUMA_PRIVACY_CONTACT`, `PIUMA_PRIVACY_URL` and
//! `PIUMA_REPORT_FILES_DAYS`.

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock, RwLock};
use std::time::Duration;

use regex::{Captures, Regex};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

// ---- Configuration -----------------------------------------------------

/// Where reports go unless a build sets `PIUMA_REPORT_RELAY`. Empty: the
/// relay is off and only "Send by email instead" is offered. Moving the
/// relay to a project domain is a maintainer step (DNS and a Workers
/// route), then a build with the new address.
pub const DEFAULT_RELAY: &str = "https://piuma-report-relay.matte-maraffio.workers.dev";

/// Where "Send by email instead" writes to unless a build sets
/// `PIUMA_FEEDBACK_ADDRESS` (empty: no email option).
pub const DEFAULT_FEEDBACK_ADDRESS: &str = "piuma@matteomaraffio.com";

/// Who decides what happens to reports, as the privacy notice names them,
/// unless a build sets `PIUMA_PRIVACY_CONTROLLER`.
pub const DEFAULT_PRIVACY_CONTROLLER: &str = "Matteo Maraffio, maintainer of Piuma Mail";

/// The full privacy notice, unless a build sets `PIUMA_PRIVACY_URL`.
pub const DEFAULT_PRIVACY_URL: &str =
    "https://github.com/piuma-mail/piuma-mail/blob/main/PRIVACY.md";

/// Days the relay keeps attachments, as the notice says, unless a build
/// sets `PIUMA_REPORT_FILES_DAYS` (it must match the relay's
/// `RETENTION_DAYS` and its bucket's lifecycle rule).
pub const DEFAULT_FILES_DAYS: u32 = 90;

/// The relay this build sends to; empty when it has none.
pub fn relay_url() -> &'static str {
    option_env!("PIUMA_REPORT_RELAY").unwrap_or(DEFAULT_RELAY)
}

/// Where "Send by email instead" writes to; empty when this build has none.
pub fn feedback_address() -> &'static str {
    option_env!("PIUMA_FEEDBACK_ADDRESS").unwrap_or(DEFAULT_FEEDBACK_ADDRESS)
}

/// What the privacy notice in the app says about who handles reports.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Privacy {
    pub controller: String,
    /// Where to ask what is kept, or to have it erased.
    pub contact: String,
    /// The full notice.
    pub url: String,
    /// The relay's host ("…workers.dev"), empty without a relay.
    pub relay_host: String,
    pub files_days: u32,
}

pub fn privacy() -> Privacy {
    let set = |v: Option<&'static str>, default: &str| {
        v.filter(|v| !v.trim().is_empty())
            .unwrap_or(default)
            .to_string()
    };
    Privacy {
        controller: set(
            option_env!("PIUMA_PRIVACY_CONTROLLER"),
            DEFAULT_PRIVACY_CONTROLLER,
        ),
        contact: set(option_env!("PIUMA_PRIVACY_CONTACT"), feedback_address()),
        url: set(option_env!("PIUMA_PRIVACY_URL"), DEFAULT_PRIVACY_URL),
        relay_host: url::Url::parse(relay_url())
            .ok()
            .and_then(|u| u.host_str().map(str::to_string))
            .unwrap_or_default(),
        files_days: option_env!("PIUMA_REPORT_FILES_DAYS")
            .and_then(|v| v.trim().parse().ok())
            .unwrap_or(DEFAULT_FILES_DAYS),
    }
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

/// The people in the local database (correspondents' names and addresses),
/// as one pattern: there can be thousands, too many to try one by one.
static PEOPLE: RwLock<Option<Regex>> = RwLock::new(None);

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

/// Name parts that are also ordinary words in a log: a sender called
/// "Amazon Web Services" mustn't hide every "services".
const COMMON_NAME_WORDS: &[&str] = &[
    "account",
    "accounts",
    "admin",
    "alert",
    "alerts",
    "amazon",
    "apple",
    "billing",
    "calendar",
    "contact",
    "customer",
    "daily",
    "digest",
    "error",
    "github",
    "google",
    "group",
    "hello",
    "help",
    "inbox",
    "info",
    "mail",
    "mailer",
    "microsoft",
    "news",
    "newsletter",
    "noreply",
    "no-reply",
    "notification",
    "notifications",
    "office",
    "order",
    "orders",
    "people",
    "piuma",
    "reply",
    "sales",
    "security",
    "server",
    "service",
    "services",
    "shop",
    "store",
    "support",
    "sync",
    "team",
    "the",
    "update",
    "updates",
    "user",
    "weekly",
    "with",
    "from",
    "your",
];

/// Sets the people [`clean`] hides as `<person>`: correspondents' display
/// names (whole, and each part of four letters or more that isn't an
/// ordinary word) and their addresses' local parts. Addresses themselves
/// already go as `<email>`.
pub fn set_known_people(names: &[String], addresses: &[String]) {
    let mut words: Vec<String> = Vec::new();
    for name in names {
        let name = name.trim().trim_matches(|c| c == '"' || c == '\'');
        if name.chars().count() >= 3 && !name.contains('@') {
            words.push(name.to_string());
        }
        for part in name.split(|c: char| !c.is_alphanumeric() && c != '-' && c != '\'') {
            let lower = part.to_lowercase();
            if part.chars().count() >= 4
                && part.chars().next().is_some_and(char::is_uppercase)
                && !COMMON_NAME_WORDS.contains(&lower.as_str())
            {
                words.push(part.to_string());
            }
        }
    }
    for address in addresses {
        if let Some((local, _)) = address.trim().split_once('@') {
            let lower = local.to_lowercase();
            if local.chars().count() >= 4 && !COMMON_NAME_WORDS.contains(&lower.as_str()) {
                words.push(local.to_string());
            }
        }
    }
    *PEOPLE.write().unwrap_or_else(|e| e.into_inner()) = people_pattern(words);
}

/// One case-insensitive pattern for `words`, each matched as a whole word.
fn people_pattern(mut words: Vec<String>) -> Option<Regex> {
    words.sort_by(|a, b| b.len().cmp(&a.len()).then_with(|| a.cmp(b)));
    words.dedup_by(|a, b| a.eq_ignore_ascii_case(b));
    words.truncate(20_000);
    if words.is_empty() {
        return None;
    }
    let edge = |c: Option<char>| c.is_some_and(|c| c.is_alphanumeric() || c == '_');
    let alternatives: Vec<String> = words
        .iter()
        .map(|w| {
            let start = if edge(w.chars().next()) { r"\b" } else { "" };
            let end = if edge(w.chars().last()) { r"\b" } else { "" };
            format!("{start}{}{end}", regex::escape(w))
        })
        .collect();
    regex::RegexBuilder::new(&format!("(?i)(?:{})", alternatives.join("|")))
        .size_limit(256 << 20)
        .dfa_size_limit(64 << 20)
        .build()
        .ok()
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
    imap_answer: Regex,
    imap_error: Regex,
    smtp_error: Regex,
    smtp_answer: Regex,
    url: Regex,
    path: Regex,
    message_id: Regex,
    email: Regex,
    token: Regex,
    ipv4: Regex,
    ipv6: Regex,
    host: Regex,
    quoted: Regex,
    single_quoted: Regex,
    backticks: Regex,
    typographic: Regex,
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
            // A server's own words after NO, BAD or BYE ("[ALERT] Your
            // mailbox Anna Rossi is full"): the status and its code stay.
            imap_answer: re(r"\b(NO|BAD|BYE)(?:\s+\[([A-Z][A-Z0-9-]*)[^\]\n]*\])?[ \t]+[^\n<]+"),
            // async-imap's errors: "No Response: …", "Bad Response: …".
            imap_error: re(r"\b(No|Bad) Response:[^\n]*"),
            // lettre's errors: "permanent error (550): 5.1.1 …".
            smtp_error: re(r"(?i)\b(permanent|transient) error \((\d{3})\)[^\n]*"),
            // An SMTP reply with its enhanced status code.
            smtp_answer: re(r"\b([245]\d\d)[ -]([245]\.\d{1,3}\.\d{1,3})\s+[^\n]+"),
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
            quoted: re(r#""([^"\n]*)""#),
            // 'text' only where a quote opens and closes, so "doesn't"
            // and "can't … won't" stay as they are.
            single_quoted: re(r"(^|[\s(\[=:,])'([^'\n]{1,300})'"),
            backticks: re(r"`([^`\n]*)`"),
            typographic: re(r"([“«‘‹„])([^“”«»‘’‹›„\n]{1,300})([”»’›“])"),
        }
    })
}

/// File names that look like host names but name the app's own code.
const CODE_EXTENSIONS: &[&str] = &[
    "rs", "dart", "kt", "swift", "java", "json", "png", "jpg", "jpeg", "txt", "db", "so", "dll",
    "dylib", "html", "css", "js", "toml", "yaml", "md",
];

/// Type names that error messages quote: kept, they say what went wrong.
const CODE_WORDS: &[&str] = &[
    "Null", "String", "int", "double", "num", "bool", "List", "Map", "Set", "Object", "dynamic",
    "Iterable", "Future", "Stream", "None", "Some", "Ok", "Err", "Option", "Result", "Vec", "str",
    "u8", "u16", "u32", "u64", "usize", "i32", "i64", "f64",
];

/// Whether quoted text reads as code (a type or a call) rather than words:
/// no spaces, and a shape no name or subject has (`List<String>`,
/// `MailRow`, `Option::unwrap()`).
fn looks_like_code(text: &str) -> bool {
    if text.is_empty() || text.chars().any(char::is_whitespace) {
        return false;
    }
    if CODE_WORDS.contains(&text) {
        return true;
    }
    let first = text.chars().next().unwrap_or(' ');
    if !(first.is_ascii_alphabetic() || first == '_') || !text.is_ascii() {
        return false;
    }
    let camel = text.chars().any(|c| c.is_ascii_lowercase())
        && text.chars().skip(1).any(|c| c.is_ascii_uppercase());
    camel || text.contains(['<', '>', '?', '_', ':', '(', ')', '[', ']', '&'])
}

/// Removes from `text` what could tell who the person is or what their
/// mail says: logins, secrets and tokens, subjects and addresses, links,
/// file paths, message ids, servers and IP addresses, mailbox names and
/// search terms, what servers wrote back, anything quoted (unless it reads
/// as code), the person's own names and the people in their mail. What
/// stays is what a developer needs: which step failed, and how.
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
    s = r
        .imap_answer
        .replace_all(&s, |c: &Captures| match c.get(2) {
            Some(code) => format!("{} [{}] <reply>", &c[1], code.as_str()),
            None => format!("{} <reply>", &c[1]),
        })
        .into_owned();
    s = r
        .imap_error
        .replace_all(&s, "$1 Response: <reply>")
        .into_owned();
    s = r
        .smtp_error
        .replace_all(&s, "$1 error ($2): <reply>")
        .into_owned();
    s = r.smtp_answer.replace_all(&s, "$1 $2 <reply>").into_owned();
    s = r.message_id.replace_all(&s, "<message-id>").into_owned();
    s = r.email.replace_all(&s, "<email>").into_owned();
    if let Some(people) = PEOPLE.read().unwrap_or_else(|e| e.into_inner()).as_ref() {
        s = people.replace_all(&s, "<person>").into_owned();
    }
    s = r.token.replace_all(&s, "<token>").into_owned();
    s = r.ipv4.replace_all(&s, "<ip>").into_owned();
    s = r.ipv6.replace_all(&s, "<ip>").into_owned();
    s = r
        .host
        .replace_all(&s, |c: &Captures| {
            let ext = c[1].to_ascii_lowercase();
            // A last part in mixed case is code ("MailRow.fromEngine",
            // "java.lang.IllegalStateException"), never a domain.
            let mixed = c[1].chars().any(|c| c.is_ascii_lowercase())
                && c[1].chars().any(|c| c.is_ascii_uppercase());
            if mixed || CODE_EXTENSIONS.contains(&ext.as_str()) {
                c[0].to_string()
            } else {
                "<host>".to_string()
            }
        })
        .into_owned();
    let keep_code = |inner: &str| -> String {
        if looks_like_code(inner) {
            inner.to_string()
        } else {
            "<text>".to_string()
        }
    };
    s = r
        .quoted
        .replace_all(&s, |c: &Captures| format!("\"{}\"", keep_code(&c[1])))
        .into_owned();
    s = r
        .backticks
        .replace_all(&s, |c: &Captures| format!("`{}`", keep_code(&c[1])))
        .into_owned();
    s = r
        .single_quoted
        .replace_all(&s, |c: &Captures| {
            format!("{}'{}'", &c[1], keep_code(&c[2]))
        })
        .into_owned();
    r.typographic
        .replace_all(&s, |c: &Captures| {
            format!("{}{}{}", &c[1], keep_code(&c[2]), &c[3])
        })
        .into_owned()
}

fn replace_ignoring_case(text: &str, word: &str, with: &str) -> String {
    match Regex::new(&format!("(?i){}", regex::escape(word))) {
        Ok(re) => re.replace_all(text, with).into_owned(),
        Err(_) => text.to_string(),
    }
}

/// A stack frame names code, not mail: only the person's own words, paths
/// (which carry their user name) and addresses are taken out.
fn clean_frame(line: &str) -> String {
    let r = rules();
    let mut s = line.to_string();
    for word in PERSONAL.read().unwrap_or_else(|e| e.into_inner()).iter() {
        s = replace_ignoring_case(&s, word, "<account>");
    }
    s = r.path.replace_all(&s, "<path>").into_owned();
    r.email.replace_all(&s, "<email>").into_owned()
}

/// An error or panic message, scrubbed harder than a log line: only its
/// first line (the lines after it are where parsers quote their input),
/// cleaned, at most 300 characters.
pub fn scrub_message(message: &str) -> String {
    let first = message.lines().find(|l| !l.trim().is_empty()).unwrap_or("");
    let mut out: String = clean(first.trim()).chars().take(300).collect();
    let more = message.lines().filter(|l| !l.trim().is_empty()).count();
    if more > 1 {
        out.push_str(" (…)");
    }
    out
}

/// A crash as kept for the next launch: the message scrubbed with
/// [`scrub_message`], then only the stack's frames (`#3  name
/// (package:…:12:7)`, `at …`), cleaned. Lines of the message after the
/// first, where a parser would quote what it read, are left out.
pub fn scrub_crash(text: &str) -> String {
    let frame = |l: &str| {
        let t = l.trim_start();
        (t.starts_with('#') && t[1..].starts_with(|c: char| c.is_ascii_digit()))
            || t.starts_with("at ")
            || t == "<asynchronous suspension>"
            || t.starts_with("...")
    };
    let mut out = Vec::new();
    let mut message: Vec<&str> = Vec::new();
    for line in text.lines() {
        if frame(line) {
            out.push(clean_frame(line.trim_end()));
        } else if out.is_empty() {
            message.push(line);
        }
    }
    let mut head = scrub_message(&message.join("\n"));
    if head.is_empty() {
        head = "(no message)".into();
    }
    std::iter::once(head)
        .chain(out.into_iter().take(40))
        .collect::<Vec<_>>()
        .join("\n")
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

// ---- Attachments -------------------------------------------------------

/// Images and videos the person may attach, by extension: (extension,
/// type, whether it is a video).
pub const ATTACHMENT_TYPES: &[(&str, &str, bool)] = &[
    ("png", "image/png", false),
    ("jpg", "image/jpeg", false),
    ("jpeg", "image/jpeg", false),
    ("webp", "image/webp", false),
    ("gif", "image/gif", false),
    ("mp4", "video/mp4", true),
    ("webm", "video/webm", true),
    ("mov", "video/quicktime", true),
];

/// Files a report can carry besides the screenshot and the log.
pub const MAX_ATTACHMENTS: usize = 5;
/// Per image, in bytes. The relay takes up to 10 MiB.
pub const MAX_IMAGE: u64 = 10_000_000;
/// Per video, in bytes. The relay takes up to 25 MiB.
pub const MAX_VIDEO: u64 = 25_000_000;
/// All attachments together, in bytes, leaving room for the screenshot and
/// the log under the relay's 32 MiB.
pub const MAX_ATTACHMENTS_TOTAL: u64 = 25_000_000;

/// An image or a video the person picked to go with a report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Attachment {
    /// The file's name on the device: only its extension is kept.
    pub name: String,
    pub bytes: Vec<u8>,
}

/// An attachment saved with its report: it leaves as `file`, never under
/// the name it had on the device, which could say whose it is.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SavedAttachment {
    /// "attachment-1.png", in the report's folder.
    pub file: String,
    pub mime: String,
    pub size: u64,
}

/// The type of an attachment named `name` and whether it is a video;
/// None for a kind that can't go.
pub fn attachment_type(name: &str) -> Option<(&'static str, &'static str, bool)> {
    let ext = name.rsplit_once('.')?.1.to_ascii_lowercase();
    ATTACHMENT_TYPES
        .iter()
        .find(|(e, _, _)| *e == ext)
        .map(|&(e, mime, video)| (e, mime, video))
}

/// For a saved attachment's file name, "attachment-<n>.<ext>": its form
/// field ("attachment-<n>") and its type. None for any other name.
fn saved_attachment(file: &str) -> Option<(String, &'static str)> {
    let (stem, _) = file.rsplit_once('.')?;
    let n = stem.strip_prefix("attachment-")?;
    if n.is_empty() || n.len() > 2 || !n.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let (ext, mime, _) = attachment_type(file)?;
    (file == format!("{stem}.{ext}")).then(|| (stem.to_string(), mime))
}

/// Why attachments can't go as they are: the sheet checks the same rules
/// before Send.
fn check_attachments(files: &[Attachment]) -> Result<(), FeedbackError> {
    if files.len() > MAX_ATTACHMENTS {
        return Err(FeedbackError::Attachment("too many files".into()));
    }
    let mut total = 0u64;
    for f in files {
        let Some((_, _, video)) = attachment_type(&f.name) else {
            return Err(FeedbackError::Attachment("unsupported type".into()));
        };
        let size = f.bytes.len() as u64;
        if size > if video { MAX_VIDEO } else { MAX_IMAGE } {
            return Err(FeedbackError::Attachment("file too large".into()));
        }
        total += size;
    }
    if total > MAX_ATTACHMENTS_TOTAL {
        return Err(FeedbackError::Attachment("too large in all".into()));
    }
    Ok(())
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
    /// Images and videos the person attached.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attachments: Vec<SavedAttachment>,
    /// The relay refused the attachments as too large (an older relay
    /// takes less): the report goes without them, and says so.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub attachments_dropped: bool,
    /// When the person last asked to try again (Unix seconds): the report
    /// keeps trying on its own for [`GIVE_UP_AFTER`] from then, or from
    /// when it was made.
    #[serde(default)]
    pub retry_since: i64,
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
    #[error("attachment: {0}")]
    Attachment(String),
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
    /// person kept them on, and the images and videos they attached.
    pub fn submit(
        &self,
        draft: &Draft,
        screenshot: Option<&[u8]>,
        attachments: &[Attachment],
        ticket: Option<Ticket>,
    ) -> Result<Report, FeedbackError> {
        let (title, description, device, screens) = tidy(draft);
        if title.is_empty() {
            return Err(FeedbackError::NoTitle);
        }
        check_attachments(attachments)?;
        let id = format!("{}-{}", crate::pending::now(), random_hex(4));
        let dir = self.report_dir(&id);
        std::fs::create_dir_all(&dir)?;
        let screenshot = screenshot.filter(|_| draft.include_screenshot);
        if let Some(png) = screenshot {
            std::fs::write(dir.join("screenshot.png"), png)?;
        }
        let mut saved = Vec::new();
        for (i, a) in attachments.iter().enumerate() {
            let Some((ext, mime, _)) = attachment_type(&a.name) else {
                continue;
            };
            let file = format!("attachment-{}.{ext}", i + 1);
            std::fs::write(dir.join(&file), &a.bytes)?;
            saved.push(SavedAttachment {
                file,
                mime: mime.to_string(),
                size: a.bytes.len() as u64,
            });
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
            attachments: saved,
            attachments_dropped: false,
            retry_since: 0,
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

    /// The files that go with a report: the screenshot, the log, then the
    /// attachments unless the relay refused them.
    pub fn files(&self, report: &Report) -> Vec<ReportFile> {
        let dir = self.report_dir(&report.id);
        let mut out = Vec::new();
        if report.has_screenshot {
            out.push(ReportFile {
                field: "screenshot".into(),
                name: "screenshot.png".into(),
                mime: "image/png".into(),
                path: dir.join("screenshot.png"),
            });
        }
        if report.has_log {
            out.push(ReportFile {
                field: "logs".into(),
                name: "log.txt".into(),
                mime: "text/plain".into(),
                path: dir.join("log.txt"),
            });
        }
        if !report.attachments_dropped {
            for a in &report.attachments {
                // Made here, but read back from disk: only names this
                // code makes, never a path out of the folder.
                let Some((field, mime)) = saved_attachment(&a.file) else {
                    continue;
                };
                out.push(ReportFile {
                    field,
                    name: a.file.clone(),
                    mime: mime.into(),
                    path: dir.join(&a.file),
                });
            }
        }
        out.retain(|f| f.path.exists());
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
            report.retry_since = crate::pending::now();
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

/// A file that goes with a report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReportFile {
    /// The form field it is posted as: "screenshot", "logs",
    /// "attachment-1"…
    pub field: String,
    /// The name it is posted under.
    pub name: String,
    pub mime: String,
    pub path: PathBuf,
}

/// Ids are made here: "<seconds>-<hex>". Anything else could reach outside
/// the folder.
fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 40 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

fn random_hex(bytes: usize) -> String {
    let mut b = vec![0u8; bytes];
    getrandom::fill(&mut b).expect("the system has randomness");
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
    let files = reports.files(report).into_iter().map(|f| f.path).collect();
    (subject, body.join("\n"), files)
}

/// An email asking the maintainers to erase a report already sent: what
/// "Delete" in Your reports offers, since deleting on the device leaves the
/// issue where it is. Subject and body, for the privacy contact.
pub fn erasure_email(report: &Report) -> (String, String) {
    let which = match report.issue {
        Some(n) => format!("#{n}"),
        None => report.id.clone(),
    };
    let subject = format!("Erase my Piuma report {which}");
    let body = [
        format!(
            "Please erase the report I sent from the app, {which}: \"{}\", with its attachments.",
            report.title
        ),
        String::new(),
        format!("Report id on my device: {}", report.id),
    ]
    .join("\n");
    (subject, body)
}

// ---- Crash ------------------------------------------------------------

const CRASH_FILE: &str = "last-crash.txt";
/// What a crash file keeps at most: the newest entries win.
const CRASH_MAX: usize = 20_000;

/// The reports folder, for the panic hook, which has nowhere else to ask.
static CRASH_DIR: OnceLock<PathBuf> = OnceLock::new();

/// Where [`install_panic_hook`] keeps panics for the next launch.
pub fn set_crash_dir(dir: &Path) {
    let _ = CRASH_DIR.set(dir.to_path_buf());
}

/// Keeps what went wrong, scrubbed ([`scrub_crash`]), for the next launch
/// to offer a report. Never sent on its own. Several can wait: each is
/// added after the others, the same one only once, the newest kept when
/// there is too much.
pub fn record_crash(dir: &Path, text: &str) {
    record_entry(dir, &scrub_crash(text));
}

fn record_entry(dir: &Path, entry: &str) {
    let _ = std::fs::create_dir_all(dir);
    let path = dir.join(CRASH_FILE);
    let before = std::fs::read_to_string(&path).unwrap_or_default();
    if before.split("\n\n").any(|e| e.trim() == entry.trim()) {
        return;
    }
    let mut all = if before.trim().is_empty() {
        entry.to_string()
    } else {
        format!("{}\n\n{entry}", before.trim_end())
    };
    if all.len() > CRASH_MAX {
        let mut cut = all.len() - CRASH_MAX;
        while !all.is_char_boundary(cut) {
            cut += 1;
        }
        all = all[cut..].to_string();
    }
    let _ = std::fs::write(path, all);
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

/// Replaces the panic hook, flutter_rust_bridge's included, which prints
/// the whole panic message: a slicing panic quotes the mail it was
/// cutting. Each panic is logged and kept for the next launch as "Rust
/// panic at file.rs:12: <scrubbed message>". With `quiet` (release builds)
/// only "panic at file.rs:12" reaches stderr, so logcat and the system log
/// never carry mail; otherwise the previous hook runs too, for developers.
/// Call it after the bridge's own setup; a hook installed later (the
/// engine's `guard`, which notes where a panic happened) runs this one
/// after its own.
pub fn install_panic_hook(quiet: bool) {
    static HOOK: std::sync::Once = std::sync::Once::new();
    HOOK.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            let place = info
                .location()
                .map(|l| {
                    let file = l.file().rsplit(['/', '\\']).next().unwrap_or("unknown");
                    format!("{file}:{}", l.line())
                })
                .unwrap_or_else(|| "an unknown place".into());
            let payload = info.payload();
            let message = payload
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| payload.downcast_ref::<String>().cloned())
                .unwrap_or_default();
            let entry = format!("Rust panic at {place}: {}", scrub_message(&message));
            log(Level::Error, "panic", &entry);
            if let Some(dir) = CRASH_DIR.get() {
                record_entry(dir, &entry);
            }
            if quiet {
                eprintln!("panic at {place}");
            } else {
                previous(info);
            }
        }));
    });
}

const RUNNING_FILE: &str = "running";

/// The app started (desktop): if the last session never said it ended,
/// the app stopped without closing (a crash outside Dart and Rust, the
/// system killing it); that waits as a crash, to offer a report.
pub fn session_started(dir: &Path) {
    if dir.join(RUNNING_FILE).exists() {
        record_entry(
            dir,
            "The app did not close normally last time (it crashed, froze, or was stopped).",
        );
    }
    let _ = std::fs::create_dir_all(dir);
    let _ = std::fs::write(dir.join(RUNNING_FILE), crate::pending::now().to_string());
}

/// The app is closing normally.
pub fn session_ended(dir: &Path) {
    let _ = std::fs::remove_file(dir.join(RUNNING_FILE));
}

// ---- Relay -------------------------------------------------------------

/// A relay ticket: proof that the report was prepared a moment ago, solved
/// while the person writes so Send is instant.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ticket {
    pub ticket: String,
    pub seed: String,
    pub bits: u32,
    /// Not before / expiry, Unix milliseconds on this device's clock (the
    /// relay's times, moved by how far the two clocks differ).
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
    /// Try again in this many seconds, with the same ticket (the relay said
    /// when: a 403, 429 or 503 with `retry-after`).
    Later {
        secs: i64,
        why: Waiting,
    },
    /// The ticket can't be used (expired, signed with a key the relay no
    /// longer has, proof of work refused: a 401, or a 403 without
    /// `retry-after`): a new ticket, after a backoff.
    Stale,
    /// This ticket was already used, or the same report is on its way.
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
            /// The relay's clock (relays before this field: none).
            #[serde(default)]
            now: Option<i64>,
        }
        let c: Challenge = res
            .json()
            .await
            .map_err(|e| RelayError::Answer(e.to_string()))?;
        // The ticket's times on this device's clock, so one that runs
        // behind or ahead neither sends too early nor waits for nothing.
        let offset = c
            .now
            .map(|relay| crate::pending::now() * 1000 - relay)
            .unwrap_or(0);
        let seed = c.seed.clone();
        let bits = c.bits.min(28);
        let nonce = tokio::task::spawn_blocking(move || solve_pow(&seed, bits))
            .await
            .map_err(|e| RelayError::Answer(e.to_string()))?;
        Ok(Ticket {
            ticket: c.ticket,
            seed: c.seed,
            bits: c.bits,
            nbf: c.nbf + offset,
            exp: c.exp + offset,
            nonce: Some(nonce),
        })
    }

    /// Posts a report with its files.
    pub async fn send(
        &self,
        install_id: &str,
        ticket: &Ticket,
        report: &Report,
        files: Vec<(ReportFile, Vec<u8>)>,
        log: Option<&str>,
    ) -> Result<Outcome, RelayError> {
        let mut device = report.device.clone();
        if report.attachments_dropped && !report.attachments.is_empty() {
            device.push((
                "Attachments".into(),
                format!(
                    "{} not sent: too large for the relay",
                    report.attachments.len()
                ),
            ));
        }
        let meta = serde_json::json!({
            "installId": install_id,
            // The same id on every try: the relay answers a report it
            // already filed with that issue rather than opening another.
            "reportId": report.id,
            "ticket": ticket.ticket,
            "powNonce": ticket.nonce,
            "kind": report.kind,
            "title": report.title,
            "description": report.description,
            "device": device
                .iter()
                .map(|(k, v)| (k.clone(), serde_json::Value::from(v.as_str())))
                .collect::<serde_json::Map<String, serde_json::Value>>(),
            "screens": report.screens,
            "logExcerpt": log.map(log_excerpt).unwrap_or_default(),
        });
        let mut total_bytes: usize = 0;
        let mut form = reqwest::multipart::Form::new().text("report", meta.to_string());
        for (file, bytes) in files {
            total_bytes += bytes.len();
            let part = reqwest::multipart::Part::bytes(bytes)
                .file_name(file.name)
                .mime_str(&file.mime)
                .map_err(|e| RelayError::Answer(e.to_string()))?;
            form = form.part(file.field, part);
        }
        // Give slow connections enough time: 60s base plus 1s per 100 KB
        // of uploaded files (capped at 5 minutes).
        let upload_timeout =
            Duration::from_secs(60 + (total_bytes / 100_000) as u64).min(Duration::from_secs(300));
        let res = self
            .http
            .post(format!("{}/report", self.base))
            .timeout(upload_timeout)
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
            // Too early for this ticket: only with the relay's word for
            // when. Any other 403, and 401, means the ticket won't work.
            403 if retry_after.is_some() => Outcome::Later {
                secs: retry_after.unwrap_or(1).clamp(1, 24 * 3600),
                why: Waiting::Turn,
            },
            401 | 403 => Outcome::Stale,
            409 => Outcome::Duplicate,
            429 => Outcome::Later {
                secs: retry_after.unwrap_or(60).clamp(1, 24 * 3600),
                why: Waiting::Turn,
            },
            503 => Outcome::Later {
                secs: retry_after.unwrap_or(6 * 3600).clamp(1, 24 * 3600),
                why: Waiting::Paused,
            },
            500..=599 => return Err(RelayError::Status(status)),
            _ => Outcome::Rejected { status },
        })
    }
}

/// How long a report keeps trying on its own, from when it was made or
/// the person last asked to try again: then it is marked failed, to send
/// again or by email.
pub const GIVE_UP_AFTER: i64 = 7 * 24 * 3600;

/// Waits between tries when the relay can't be reached or refuses the
/// ticket: 1 min, 5 min, 30 min, 2 h, then every 6 h. Tries happen while
/// the app is open (the next start and the network coming back count).
fn backoff(tries: u32) -> i64 {
    match tries {
        0 | 1 => 60,
        2 => 300,
        3 => 1800,
        4 => 7200,
        _ => 6 * 3600,
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
            Ok(Outcome::Duplicate) | Ok(Outcome::Stale) => {
                // The ticket was used (by a try whose answer was lost: the
                // relay hands back that issue when the report comes again)
                // or can't be used. A fresh ticket, after a backoff, so a
                // relay that keeps refusing is never asked in a loop.
                report.status = Status::Queued;
                report.ticket = None;
                report.waiting = Some(Waiting::Turn);
                report.tries += 1;
                report.next_try = now + backoff(report.tries);
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
                // If repeatedly failing (e.g. upload timeouts or network issues),
                // drop heavy attachments after half the attempts so the words still arrive.
                if !report.attachments.is_empty()
                    && !report.attachments_dropped
                    && report.tries >= 3
                {
                    log(
                        Level::Warn,
                        "feedback",
                        &format!(
                            "repeated delivery failure (try {}); retrying without {} attachments",
                            report.tries,
                            report.attachments.len()
                        ),
                    );
                    report.attachments_dropped = true;
                }
                report.status = Status::Queued;
                report.waiting = Some(Waiting::Offline);
                report.next_try = now + backoff(report.tries);
            }
        }
        if report.status == Status::Queued
            && now - report.created_at.max(report.retry_since) >= GIVE_UP_AFTER
        {
            log(
                Level::Warn,
                "feedback",
                "report not delivered after 7 days; marked failed",
            );
            report.status = Status::Failed;
            report.waiting = None;
            report.ticket = None;
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
    let read = |report: &Report| -> Result<_, RelayError> {
        let mut files = Vec::new();
        let mut log = None;
        for file in reports.files(report) {
            let bytes = std::fs::read(&file.path).map_err(FeedbackError::from)?;
            if file.field == "logs" {
                log = Some(String::from_utf8_lossy(&bytes).into_owned());
            }
            files.push((file, bytes));
        }
        Ok((files, log))
    };
    let (files, log) = read(report)?;
    let mut outcome = relay
        .send(install_id, &ticket, report, files, log.as_deref())
        .await;
    if matches!(outcome, Ok(Outcome::Rejected { status: 413 }))
        && !report.attachments.is_empty()
        && !report.attachments_dropped
    {
        // Too large for this relay (an older one takes less): the words
        // matter more than the files, so they go without them. The relay
        // refuses the size before it uses the ticket.
        log_line_dropped(report.attachments.len());
        report.attachments_dropped = true;
        let (files, log) = read(report)?;
        outcome = relay
            .send(install_id, &ticket, report, files, log.as_deref())
            .await;
    }
    if matches!(outcome, Ok(Outcome::Later { .. })) {
        // Too early for this ticket: keep it, it works once its time comes.
        report.ticket = Some(ticket);
    }
    outcome
}

fn log_line_dropped(n: usize) {
    log(
        Level::Warn,
        "feedback",
        &format!("relay refused {n} attachments as too large; sending without them"),
    );
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
                "SELECT <mailbox>: NO <reply>",
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
        let r = reports.submit(&d, Some(&[1, 2, 3]), &[], None).unwrap();
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
        let r = reports.submit(&d, Some(&[1, 2, 3]), &[], None).unwrap();
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
            reports.submit(&d, None, &[], None),
            Err(FeedbackError::NoTitle)
        ));
    }

    #[tokio::test]
    async fn a_report_cut_off_while_sending_goes_again() {
        let reports = Reports::new(temp_dir("cutoff"));
        let mut r = reports.submit(&draft(), None, &[], None).unwrap();
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
        let r = reports.submit(&draft(), None, &[], None).unwrap();
        let (subject, body, files) = email(&reports, &r);
        assert_eq!(subject, "[Piuma problem] Inbox stops syncing");
        assert!(body.starts_with("After sleep\n\nDevice and app\nApp: 0.1.0 (120)"));
        assert_eq!(files.len(), 1);
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    fn file(name: &str, len: usize) -> Attachment {
        Attachment {
            name: name.into(),
            bytes: vec![7; len],
        }
    }

    #[test]
    fn attachments_wait_with_the_report() {
        let reports = Reports::new(temp_dir("attach"));
        let files = [file("Anna's cat.JPG", 3), file("screen recording.mov", 5)];
        let r = reports.submit(&draft(), None, &files, None).unwrap();
        assert_eq!(
            r.attachments,
            vec![
                SavedAttachment {
                    file: "attachment-1.jpg".into(),
                    mime: "image/jpeg".into(),
                    size: 3,
                },
                SavedAttachment {
                    file: "attachment-2.mov".into(),
                    mime: "video/quicktime".into(),
                    size: 5,
                },
            ]
        );
        // Kept on disk, and back after a restart.
        let again = reports.get(&r.id).unwrap();
        assert_eq!(again, r);
        let sent = reports.files(&again);
        let fields: Vec<_> = sent.iter().map(|f| f.field.as_str()).collect();
        assert_eq!(fields, ["logs", "attachment-1", "attachment-2"]);
        assert_eq!(std::fs::read(&sent[2].path).unwrap(), vec![7; 5]);
        // The device's file names never leave.
        assert!(sent.iter().all(|f| !f.name.contains("Anna")));
        // Too large for the relay: only the report and the log go.
        let mut dropped = again.clone();
        dropped.attachments_dropped = true;
        assert_eq!(reports.files(&dropped).len(), 1);
        // A name this code didn't make is never read.
        let mut odd = again.clone();
        odd.attachments[0].file = "../report.json".into();
        odd.attachments[1].file = "attachment-2.exe".into();
        assert_eq!(reports.files(&odd).len(), 1);
        // A report saved before attachments existed still reads.
        let path = reports.dir().join(&r.id).join("report.json");
        let mut json: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        json.as_object_mut().unwrap().remove("attachments");
        std::fs::write(&path, json.to_string()).unwrap();
        assert!(reports.get(&r.id).unwrap().attachments.is_empty());
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    #[test]
    fn attachments_keep_to_the_limits() {
        let reports = Reports::new(temp_dir("limits"));
        let refused = |files: &[Attachment]| {
            matches!(
                reports.submit(&draft(), None, files, None),
                Err(FeedbackError::Attachment(_))
            )
        };
        assert!(refused(&[file("notes.pdf", 1)]));
        assert!(refused(&[file("no extension", 1)]));
        assert!(refused(&[file("big.png", MAX_IMAGE as usize + 1)]));
        assert!(refused(&[file("long.mp4", MAX_VIDEO as usize + 1)]));
        assert!(refused(&vec![file("a.gif", 1); MAX_ATTACHMENTS + 1]));
        assert!(refused(&[
            file("a.png", MAX_IMAGE as usize),
            file("b.png", MAX_IMAGE as usize),
            file("c.png", MAX_IMAGE as usize),
        ]));
        // Nothing refused is kept.
        assert!(reports.list().is_empty());
        assert!(!refused(&[
            file("a.webp", MAX_IMAGE as usize),
            file("b.webm", 1)
        ]));
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    /// What a scripted relay answers: the status line with any extra
    /// header lines ("403 Forbidden\r\nretry-after: 5"), and the JSON body.
    type Answer = (String, String);

    /// A relay on localhost. `challenge` answers `POST /challenge`;
    /// `answer` gets each report's body and says what to reply. Returns
    /// its address and the report bodies it saw.
    async fn scripted_relay(
        challenge: String,
        answer: impl Fn(&str) -> Answer + Send + Sync + 'static,
    ) -> (String, std::sync::Arc<Mutex<Vec<String>>>) {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = std::sync::Arc::new(Mutex::new(Vec::new()));
        let kept = seen.clone();
        let answer = std::sync::Arc::new(answer);
        tokio::spawn(async move {
            loop {
                let Ok((mut sock, _)) = listener.accept().await else {
                    return;
                };
                let seen = kept.clone();
                let answer = answer.clone();
                let challenge = challenge.clone();
                tokio::spawn(async move {
                    let mut buf = Vec::new();
                    let mut chunk = [0u8; 64 * 1024];
                    // Headers, then as much body as they announce.
                    let (head, body_at) = loop {
                        let n = sock.read(&mut chunk).await.unwrap_or(0);
                        if n == 0 {
                            return;
                        }
                        buf.extend_from_slice(&chunk[..n]);
                        if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                            break (String::from_utf8_lossy(&buf[..i]).to_lowercase(), i + 4);
                        }
                    };
                    let length: usize = head
                        .lines()
                        .find_map(|l| l.strip_prefix("content-length:"))
                        .and_then(|v| v.trim().parse().ok())
                        .unwrap_or(0);
                    while buf.len() < body_at + length {
                        let n = sock.read(&mut chunk).await.unwrap_or(0);
                        if n == 0 {
                            break;
                        }
                        buf.extend_from_slice(&chunk[..n]);
                    }
                    let body = String::from_utf8_lossy(&buf[body_at..]).into_owned();
                    let (status, reply) = if head.starts_with("post /challenge") {
                        ("200 OK".to_string(), challenge)
                    } else {
                        seen.lock().unwrap().push(body.clone());
                        answer(&body)
                    };
                    let reply = format!(
                        "HTTP/1.1 {status}\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{reply}",
                        reply.len()
                    );
                    let _ = sock.write_all(reply.as_bytes()).await;
                });
            }
        });
        (base, seen)
    }

    /// A ticket that is good now and for a long while.
    const OPEN_TICKET: &str = r#"{"ticket":"t","seed":"s","bits":0,"nbf":0,"exp":99999999999999}"#;

    /// A relay on localhost that answers like an older one: 413 for a
    /// report with attachments, an issue for one without.
    async fn small_relay() -> (String, std::sync::Arc<Mutex<Vec<String>>>) {
        scripted_relay(OPEN_TICKET.into(), |body| {
            if body.contains("name=\"attachment-1\"") {
                (
                    "413 Payload Too Large".into(),
                    r#"{"error":"too large"}"#.into(),
                )
            } else {
                ("201 Created".into(), r#"{"url":"u","number":7}"#.into())
            }
        })
        .await
    }

    #[tokio::test]
    async fn an_older_relay_gets_the_words_without_the_files() {
        let (base, seen) = small_relay().await;
        let reports = Reports::new(temp_dir("older"));
        let r = reports
            .submit(&draft(), None, &[file("clip.mp4", 64)], None)
            .unwrap();
        let relay = Relay::new(&base).unwrap();
        assert_eq!(send_queued(&reports, &relay).await.unwrap(), 1);
        let after = reports.get(&r.id).unwrap();
        assert_eq!(after.status, Status::Sent);
        assert_eq!(after.issue, Some(7));
        assert!(after.attachments_dropped);
        let seen = seen.lock().unwrap();
        assert_eq!(seen.len(), 2);
        assert!(!seen[1].contains("attachment-1"));
        assert!(seen[1].contains("1 not sent: too large for the relay"));
        drop(seen);
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    /// A relay on localhost that returns 500 when attachments are sent,
    /// simulating persistent network or upload failures.
    async fn failing_attachments_relay() -> (String, std::sync::Arc<Mutex<Vec<String>>>) {
        scripted_relay(OPEN_TICKET.into(), |body| {
            if body.contains("name=\"attachment-1\"") {
                (
                    "500 Internal Server Error".into(),
                    r#"{"error":"simulated failure"}"#.into(),
                )
            } else {
                ("201 Created".into(), r#"{"url":"u","number":8}"#.into())
            }
        })
        .await
    }

    #[tokio::test]
    async fn repeated_delivery_failures_drop_attachments_so_words_arrive() {
        let (base, seen) = failing_attachments_relay().await;
        let reports = Reports::new(temp_dir("repeated-failures"));
        let r = reports
            .submit(&draft(), None, &[file("clip.mp4", 64)], None)
            .unwrap();
        let relay = Relay::new(&base).unwrap();

        for expected_tries in 1..=3 {
            let _ = send_queued(&reports, &relay).await;
            let mut rep = reports.get(&r.id).unwrap();
            assert_eq!(rep.tries, expected_tries);
            assert_eq!(rep.status, Status::Queued);
            if expected_tries < 3 {
                assert!(!rep.attachments_dropped);
            } else {
                assert!(rep.attachments_dropped);
            }
            rep.next_try = 0;
            reports.save(&rep).unwrap();
        }

        assert_eq!(send_queued(&reports, &relay).await.unwrap(), 1);
        let after = reports.get(&r.id).unwrap();
        assert_eq!(after.status, Status::Sent);
        assert_eq!(after.issue, Some(8));
        assert!(after.attachments_dropped);
        let seen = seen.lock().unwrap();
        assert_eq!(seen.len(), 4);
        assert!(!seen[3].contains("attachment-1"));
        drop(seen);
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
    /// Log lines as the engine and the app write them when things go wrong,
    /// with what must not survive.
    #[test]
    fn realistic_logs_keep_the_step_and_lose_the_person() {
        set_known_people(
            &[
                "Giulia Bianchi".into(),
                "Amazon Web Services".into(),
                "Lia".into(),
            ],
            &[
                "giulia.bianchi@example.org".into(),
                "info@shop.example".into(),
            ],
        );
        let cases = [
            (
                "imap: fetch body failed: NO [ALERT] Mailbox of Giulia Bianchi is over quota",
                "imap: fetch body failed: NO [ALERT] <reply>",
            ),
            (
                "imap: No Response: [NONEXISTENT] Unknown Mailbox: Giulia/Taxes 2026 (Failure)",
                "imap: No Response: <reply>",
            ),
            (
                "smtp: permanent error (550): 5.1.1 <giulia.bianchi@example.org>: Recipient address rejected",
                "smtp: permanent error (550): <reply>",
            ),
            (
                "smtp: 552 5.2.2 The mailbox of Giulia is full, try again later",
                "smtp: 552 5.2.2 <reply>",
            ),
            (
                "reader: render failed for message from Giulia Bianchi (giulia.bianchi)",
                "reader: render failed for message from <person> (<person>)",
            ),
            (
                "notify: shown for Bianchi, services restarted",
                "notify: shown for <person>, services restarted",
            ),
            (
                "Exception: Could not open “Contract for Via Roma 12”",
                "Exception: Could not open “<text>”",
            ),
            (
                "FormatException: Invalid date 'giovedì 12 marzo'",
                "FormatException: Invalid date '<text>'",
            ),
            (
                "type 'Null' is not a subtype of type 'String' in type cast",
                "type 'Null' is not a subtype of type 'String' in type cast",
            ),
            (
                "called `Option::unwrap()` on a `None` value",
                "called `Option::unwrap()` on a `None` value",
            ),
            (
                "byte index 5 is not a char boundary; it is inside 'é' (bytes 4..6) of `Caffè con Giulia`",
                "byte index 5 is not a char boundary; it is inside '<text>' (bytes 4..6) of `<text>`",
            ),
            ("sync: can't reach server, won't retry", "sync: can't reach server, won't retry"),
            ("status 503 from relay", "status 503 from relay"),
            // A short name never hides part of another word.
            ("Reliability check passed", "Reliability check passed"),
        ];
        for (input, want) in cases {
            assert_eq!(clean(input), want, "{input}");
        }
        set_known_people(&[], &[]);
        assert_eq!(clean("Giulia Bianchi"), "Giulia Bianchi");
    }

    #[test]
    fn crashes_keep_the_first_line_and_the_frames() {
        let dart = "FormatException: Unexpected character (at character 7)\n\
                    Dear Anna, the meeting is moved\n      ^\n\n\
                    #0      _parse (package:piuma/mail/dates.dart:120:7)\n\
                    #1      MailRow.fromEngine (package:piuma/mail/mail_source.dart:88:12)\n\
                    <asynchronous suspension>";
        let kept = scrub_crash(dart);
        assert_eq!(
            kept,
            "FormatException: Unexpected character (at character 7) (…)\n\
             #0      _parse (package:piuma/mail/dates.dart:120:7)\n\
             #1      MailRow.fromEngine (package:piuma/mail/mail_source.dart:88:12)\n\
             <asynchronous suspension>"
        );
        assert!(!kept.contains("Anna"));
        // Kotlin and Java frames count as frames too.
        let kotlin = "java.lang.IllegalStateException: bad 'Mario Rossi'\n    at mail.piuma.Files.open(Files.kt:40)";
        assert_eq!(
            scrub_crash(kotlin),
            "java.lang.IllegalStateException: bad '<text>'\n    at mail.piuma.Files.open(Files.kt:40)"
        );
    }

    #[test]
    fn crashes_add_up_once_each_and_stay_small() {
        let dir = temp_dir("crashes");
        record_crash(&dir, "StateError: one");
        record_crash(&dir, "StateError: two");
        record_crash(&dir, "StateError: one");
        assert_eq!(
            pending_crash(&dir).unwrap(),
            "StateError: one\n\nStateError: two"
        );
        for i in 0..2000 {
            record_crash(&dir, &format!("StateError: number {i} {}", "x ".repeat(20).trim_end()));
        }
        let all = pending_crash(&dir).unwrap();
        assert!(all.len() <= CRASH_MAX);
        assert!(all.ends_with(&format!("number 1999 {}", "x ".repeat(20).trim_end())));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn panics_leave_the_place_and_never_the_mail() {
        let dir = temp_dir("panic");
        set_crash_dir(&dir);
        // Not quiet in tests: the harness still shows failed assertions.
        install_panic_hook(false);
        let text = "Caffè con Giulia, venerdì";
        // What a slicing panic says: it quotes the text it was cutting.
        let _ = std::panic::catch_unwind(|| {
            panic!("byte index 4 is not a char boundary; it is inside 'è' (bytes 3..5) of `{text}`")
        });
        let crash = pending_crash(CRASH_DIR.get().unwrap()).unwrap_or_default();
        let entry = crash
            .split("\n\n")
            .find(|e| e.starts_with("Rust panic at feedback.rs:"))
            .expect("the panic is kept");
        assert!(
            !entry.contains("Giulia") && !entry.contains("Caff"),
            "{entry}"
        );
        assert!(recent_log().contains("Rust panic at feedback.rs:"));
        assert!(!recent_log().contains("Giulia"));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn a_session_that_never_ended_waits_as_a_crash() {
        let dir = temp_dir("session");
        session_started(&dir);
        session_ended(&dir);
        session_started(&dir);
        assert!(pending_crash(&dir).is_none());
        // Killed: no session_ended, then the next start.
        session_started(&dir);
        assert!(pending_crash(&dir)
            .unwrap()
            .contains("did not close normally"));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn the_build_names_who_handles_reports() {
        let p = privacy();
        assert!(!p.controller.is_empty());
        assert_eq!(p.contact, feedback_address());
        assert!(p.url.starts_with("https://"));
        assert_eq!(p.files_days, DEFAULT_FILES_DAYS);
        if relay_url() == DEFAULT_RELAY {
            assert_eq!(
                p.relay_host,
                "piuma-report-relay.matte-maraffio.workers.dev"
            );
        }
    }

    #[test]
    fn erasure_names_the_issue() {
        let reports = Reports::new(temp_dir("erase"));
        let mut r = reports.submit(&draft(), None, &[], None).unwrap();
        r.issue = Some(42);
        let (subject, body) = erasure_email(&r);
        assert_eq!(subject, "Erase my Piuma report #42");
        assert!(body.contains("\"Inbox stops syncing\""));
        assert!(body.contains(&r.id));
        let _ = std::fs::remove_dir_all(reports.dir());
    }

    /// A report sent to `answer`, once; returns it as saved after the try
    /// and how many uploads the relay saw.
    async fn one_try(
        challenge: &str,
        answer: impl Fn(&str) -> Answer + Send + Sync + 'static,
    ) -> (Report, usize, String) {
        let (base, seen) = scripted_relay(challenge.into(), answer).await;
        let reports = Reports::new(temp_dir("try"));
        let r = reports.submit(&draft(), None, &[], None).unwrap();
        let relay = Relay::new(&base).unwrap();
        let _ = send_queued(&reports, &relay).await;
        let after = reports.get(&r.id).unwrap();
        let seen = seen.lock().unwrap();
        let first = seen.first().cloned().unwrap_or_default();
        let n = seen.len();
        drop(seen);
        let _ = std::fs::remove_dir_all(reports.dir());
        (after, n, first)
    }

    #[tokio::test]
    async fn a_ticket_that_cannot_work_is_dropped_never_retried_in_a_loop() {
        for status in ["403 Forbidden", "401 Unauthorized"] {
            let (after, uploads, _) = one_try(OPEN_TICKET, move |_| {
                (status.into(), r#"{"error":"expired"}"#.into())
            })
            .await;
            assert_eq!(uploads, 1, "{status}");
            assert_eq!(after.status, Status::Queued);
            assert_eq!(after.ticket, None, "{status}");
            assert_eq!(after.tries, 1);
            assert!(after.next_try >= crate::pending::now() + 59, "{status}");
        }
    }

    #[tokio::test]
    async fn too_early_with_retry_after_keeps_the_ticket() {
        let (after, uploads, _) = one_try(OPEN_TICKET, |_| {
            (
                "403 Forbidden\r\nretry-after: 40".into(),
                r#"{"error":"early"}"#.into(),
            )
        })
        .await;
        assert_eq!(uploads, 1);
        assert!(after.ticket.is_some());
        assert_eq!(after.tries, 0);
        assert!(after.next_try >= crate::pending::now() + 39);
    }

    #[tokio::test]
    async fn every_try_carries_the_report_id() {
        let (after, _, body) = one_try(OPEN_TICKET, |_| {
            (
                "201 Created".into(),
                r#"{"url":"u","number":9,"existing":true}"#.into(),
            )
        })
        .await;
        assert_eq!(after.status, Status::Sent);
        assert_eq!(after.issue, Some(9));
        assert!(
            body.contains(&format!("\"reportId\":\"{}\"", after.id)),
            "{body}"
        );
    }

    #[tokio::test]
    async fn ticket_times_follow_the_relay_clock() {
        // The relay's clock is an hour ahead of this device's.
        let now = crate::pending::now() * 1000;
        let ahead = now + 3_600_000;
        let challenge = format!(
            r#"{{"ticket":"t","seed":"s","bits":0,"nbf":{},"exp":{},"now":{ahead}}}"#,
            ahead + 5_000,
            ahead + 1_805_000
        );
        let (base, _) = scripted_relay(challenge, |_| ("201 Created".into(), "{}".into())).await;
        let t = Relay::new(&base)
            .unwrap()
            .ticket("0123456789abcdef0123456789abcdef")
            .await
            .unwrap();
        let wait = t.nbf - now;
        assert!((4_000..=6_000).contains(&wait), "waits {wait} ms");
        assert!(!t.expired(now));
    }

    #[tokio::test]
    async fn a_report_stops_trying_after_a_week_and_again_after_retry() {
        let (base, _) = scripted_relay(OPEN_TICKET.into(), |_| {
            ("401 Unauthorized".into(), r#"{"error":"ticket"}"#.into())
        })
        .await;
        let reports = Reports::new(temp_dir("week"));
        let mut r = reports.submit(&draft(), None, &[], None).unwrap();
        r.created_at -= GIVE_UP_AFTER - 3600;
        reports.save(&r).unwrap();
        let relay = Relay::new(&base).unwrap();
        send_queued(&reports, &relay).await.unwrap();
        assert_eq!(reports.get(&r.id).unwrap().status, Status::Queued);
        let mut r = reports.get(&r.id).unwrap();
        r.created_at -= 7200;
        r.next_try = 0;
        reports.save(&r).unwrap();
        send_queued(&reports, &relay).await.unwrap();
        assert_eq!(reports.get(&r.id).unwrap().status, Status::Failed);
        // Try again: another week from now.
        assert_eq!(reports.retry(&r.id).unwrap().status, Status::Queued);
        send_queued(&reports, &relay).await.unwrap();
        assert_eq!(reports.get(&r.id).unwrap().status, Status::Queued);
        let _ = std::fs::remove_dir_all(reports.dir());
    }
}
