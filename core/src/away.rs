//! The away message (`RemindAwayPrintToApprove`, section 2): an automatic
//! reply that the mail server sends, so it answers with every device off.
//!
//! IMAP accounts get a Sieve script of their own, "piuma-away" (RFC 5230
//! vacation), through ManageSieve; JMAP accounts get `VacationResponse`.
//! Each sender is answered once every 7 days, and never mailing lists,
//! bulk mail, automatic mail or no-reply addresses.
//!
//! The person's own Sieve scripts are never changed: the away script is
//! only made active when no other script is, and turning it off removes
//! only it. When the server's Sieve cannot compare dates, the dates stay
//! on the device, and the engine puts the script up on the first day and
//! takes it down after the last ([`due`]).

use serde::{Deserialize, Serialize};

use crate::invite::{civil, days};
use crate::jmap::{self, JmapConfig, JmapError, Vacation};
use crate::model::Account;
use crate::sieve::{self, SieveConfig, SieveError};

/// The script's name on the server. Only this one is ever written,
/// activated or deleted.
pub const SCRIPT: &str = "piuma-away";
/// Days before the same sender is answered again.
pub const DAYS: u32 = 7;
/// Where the script keeps what the settings page shows.
const MARK: &str = "# piuma ";

/// What the person set. Days are numbered from 1970-01-01, in the
/// person's time zone.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AwayMessage {
    pub on: bool,
    /// The first day; None from now.
    pub start: Option<i64>,
    /// The last day; None until turned off.
    pub end: Option<i64>,
    pub subject: String,
    pub body: String,
}

impl AwayMessage {
    /// Whether it answers on `today`, by its dates.
    pub fn covers(&self, today: i64) -> bool {
        self.on && self.start.is_none_or(|s| s <= today) && self.end.is_none_or(|e| e >= today)
    }
}

/// What the device keeps of an account's away message.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Stored {
    pub message: AwayMessage,
    /// Minutes east of UTC where it was set: its days are that zone's.
    pub zone: i32,
    /// It is on the server now.
    pub placed: bool,
    /// The server can't tell dates: this device starts and ends it.
    pub device_dates: bool,
}

impl Stored {
    /// Whether the inbox says it is on.
    pub fn showing(&self, today: i64) -> bool {
        self.placed && self.message.covers(today)
    }
}

/// What the engine has to do for an away message on `today`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Due {
    Nothing,
    /// Its first day came, on a server that can't tell dates.
    Place,
    /// Off, but still on the server.
    Remove,
    /// Its last day has passed: turn it off.
    End,
}

pub fn due(s: &Stored, today: i64) -> Due {
    let m = &s.message;
    if m.on && m.end.is_some_and(|e| e < today) {
        return Due::End;
    }
    if !s.device_dates {
        return Due::Nothing;
    }
    let wanted = m.on && m.start.is_none_or(|st| st <= today);
    match (wanted, s.placed) {
        (true, false) => Due::Place,
        (false, true) => Due::Remove,
        _ => Due::Nothing,
    }
}

/// Today's day number at `now` (Unix seconds) in a zone `zone` minutes
/// east of UTC.
pub fn today(now: i64, zone: i32) -> i64 {
    (now + i64::from(zone) * 60).div_euclid(86_400)
}

/// "2026-10-27".
pub fn iso(day: i64) -> String {
    let (y, m, d) = civil(day);
    format!("{y:04}-{m:02}-{d:02}")
}

/// The day of "2026-10-27", or of the date part of "2026-10-27T…".
pub fn parse_iso(s: &str) -> Option<i64> {
    let s = s.get(..10)?;
    let mut parts = s.split('-');
    let y: i32 = parts.next()?.parse().ok()?;
    let m: u32 = parts.next()?.parse().ok()?;
    let d: u32 = parts.next()?.parse().ok()?;
    if parts.next().is_some() || !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    let n = days(y, m, d);
    (civil(n) == (y, m, d)).then_some(n)
}

/// "+0200" for 120 minutes east of UTC.
fn zone_name(zone: i32) -> String {
    let sign = if zone < 0 { '-' } else { '+' };
    let z = zone.unsigned_abs();
    format!("{sign}{:02}{:02}", z / 60, z % 60)
}

/// The UTC time a local day starts, as JMAP writes it.
fn utc_start(day: i64, zone: i32) -> String {
    let at = day * 86_400 - i64::from(zone) * 60;
    let (date, secs) = (at.div_euclid(86_400), at.rem_euclid(86_400));
    format!(
        "{}T{:02}:{:02}:{:02}Z",
        iso(date),
        secs / 3600,
        secs / 60 % 60,
        secs % 60
    )
}

/// The local day a JMAP UTC time falls on.
fn local_day(utc: &str, zone: i32) -> Option<i64> {
    let day = parse_iso(utc)?;
    let time = utc.get(11..19)?;
    let mut hms = time.split(':').map(|p| p.parse::<i64>().ok());
    let (h, m, s) = (hms.next()??, hms.next()??, hms.next()??);
    Some(today(day * 86_400 + h * 3600 + m * 60 + s, zone))
}

/// A Sieve string: quoted, with `\` and `"` escaped, lines ending in CRLF.
fn sieve_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    let normal = s.replace("\r\n", "\n").replace('\r', "\n");
    for c in normal.chars() {
        match c {
            '"' | '\\' => {
                out.push('\\');
                out.push(c);
            }
            '\n' => out.push_str("\r\n"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn sieve_list(items: &[String]) -> String {
    let quoted: Vec<String> = items.iter().map(|s| sieve_string(s)).collect();
    format!("[{}]", quoted.join(", "))
}

/// The From addresses that never get an answer, by their local part.
const NO_REPLY: [&str; 7] = [
    "*noreply*",
    "*no-reply*",
    "*no_reply*",
    "*donotreply*",
    "*do-not-reply*",
    "mailer-daemon",
    "postmaster",
];

/// The away script (RFC 5228, RFC 5230): it answers each sender once
/// every [`DAYS`] days, from the account's own `addresses`, and leaves
/// mailing lists, bulk and automatic mail and no-reply senders alone.
/// With `dates`, the server itself keeps to the first and last day, in
/// the zone `zone` minutes east of UTC.
pub fn script(m: &AwayMessage, addresses: &[String], zone: i32, dates: bool) -> String {
    let dated = dates && (m.start.is_some() || m.end.is_some());
    let mut require = vec!["vacation"];
    if dated {
        require.extend(["date", "relational"]);
    }
    let require: Vec<String> = require.into_iter().map(str::to_owned).collect();
    let mut tests = vec![
        "not exists \"list-id\"".to_owned(),
        "not header :is \"precedence\" [\"bulk\", \"list\", \"junk\"]".to_owned(),
        "anyof (not exists \"auto-submitted\", header :is \"auto-submitted\" \"no\")".to_owned(),
        format!(
            "not address :localpart :matches \"from\" {}",
            sieve_list(&NO_REPLY.map(str::to_owned))
        ),
    ];
    let zone = sieve_string(&zone_name(zone));
    if dated {
        if let Some(start) = m.start {
            tests.push(format!(
                "currentdate :zone {zone} :value \"ge\" \"date\" \"{}\"",
                iso(start)
            ));
        }
        if let Some(end) = m.end {
            tests.push(format!(
                "currentdate :zone {zone} :value \"le\" \"date\" \"{}\"",
                iso(end)
            ));
        }
    }
    let subject: String = m
        .subject
        .chars()
        .map(|c| if c == '\r' || c == '\n' { ' ' } else { c })
        .collect();
    let mut vacation = format!("vacation :days {DAYS}");
    if !subject.trim().is_empty() {
        vacation.push_str(&format!(" :subject {}", sieve_string(subject.trim())));
    }
    let addresses: Vec<String> = addresses
        .iter()
        .map(|a| a.trim().to_lowercase())
        .filter(|a| !a.is_empty())
        .collect();
    if !addresses.is_empty() {
        vacation.push_str(&format!(" :addresses {}", sieve_list(&addresses)));
    }
    vacation.push_str(&format!(" {};", sieve_string(&m.body)));
    let mark = serde_json::to_string(m).unwrap_or_default();
    [
        "# Away message, made by Piuma Mail. Turning it off in the app deletes it.".to_owned(),
        format!("{MARK}{mark}"),
        format!("require {};", sieve_list(&require)),
        format!("if allof ({}) {{", tests.join(",\r\n          ")),
        format!("    {vacation}"),
        "}".to_owned(),
        String::new(),
    ]
    .join("\r\n")
}

/// What a script made by [`script`] says, or None for any other script.
pub fn read_script(script: &str) -> Option<AwayMessage> {
    script
        .lines()
        .find_map(|l| l.strip_prefix(MARK))
        .and_then(|json| serde_json::from_str(json.trim()).ok())
}

/// Where an account's away message lives.
#[derive(Debug, Clone)]
pub enum AwayServer {
    Sieve(SieveConfig),
    Jmap(JmapConfig),
}

impl AwayServer {
    pub fn for_account(account: &Account, password: &str) -> Self {
        match SieveConfig::for_account(account, password) {
            Some(s) => AwayServer::Sieve(s),
            None => AwayServer::Jmap(
                JmapConfig::for_account(account, password).expect("an IMAP or JMAP account"),
            ),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum AwayError {
    #[error(transparent)]
    Sieve(#[from] SieveError),
    #[error(transparent)]
    Jmap(#[from] JmapError),
}

impl AwayError {
    pub fn is_offline(&self) -> bool {
        match self {
            AwayError::Sieve(e) => e.is_offline(),
            AwayError::Jmap(e) => e.is_offline(),
        }
    }

    pub fn is_auth(&self) -> bool {
        matches!(
            self,
            AwayError::Sieve(SieveError::Auth) | AwayError::Jmap(JmapError::Auth)
        )
    }
}

pub type Result<T> = std::result::Result<T, AwayError>;

/// What the server has, on a server that takes an away message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Status {
    /// The server keeps to the dates itself.
    pub dates: bool,
    /// The away message on the server, on or off; None when it has none.
    pub message: Option<AwayMessage>,
    /// It is on the server and answering (by its dates).
    pub placed: bool,
    /// Another script of the person's is active: ours can't be.
    pub other_filters: bool,
}

/// Whether the server takes an away message, and what it has. None when
/// it does not (no ManageSieve, no vacation, or JMAP without it).
pub async fn status(server: &AwayServer, zone: i32) -> Result<Option<Status>> {
    match server {
        AwayServer::Sieve(cfg) => {
            let mut c = match sieve::Client::open(cfg).await {
                Ok(c) => c,
                Err(SieveError::Unsupported(_)) => return Ok(None),
                // No ManageSieve there: the row is simply not shown.
                Err(SieveError::Connect { .. } | SieveError::Timeout) => return Ok(None),
                Err(e) => return Err(e.into()),
            };
            if !c.capabilities().has("vacation") {
                c.logout().await;
                return Ok(None);
            }
            let dates = c.capabilities().dates();
            let scripts = c.list().await?;
            let ours = scripts.iter().find(|s| s.name == SCRIPT);
            let message = match ours {
                Some(_) => c.get(SCRIPT).await?.as_deref().and_then(read_script),
                None => None,
            };
            c.logout().await;
            Ok(Some(Status {
                dates,
                message,
                placed: ours.is_some_and(|s| s.active),
                other_filters: scripts.iter().any(|s| s.active && s.name != SCRIPT),
            }))
        }
        AwayServer::Jmap(cfg) => {
            let client = jmap::Client::open(cfg).await?;
            if !client.has_vacation() {
                return Ok(None);
            }
            let v = client.vacation().await?;
            let message = AwayMessage {
                on: v.enabled,
                start: v.from.as_deref().and_then(|f| local_day(f, zone)),
                // `toDate` is the moment after the last day.
                end: v
                    .to
                    .as_deref()
                    .and_then(|t| local_day(t, zone))
                    .map(|d| d - 1),
                subject: v.subject,
                body: v.text,
            };
            Ok(Some(Status {
                dates: true,
                placed: message.on,
                message: Some(message),
                other_filters: false,
            }))
        }
    }
}

/// How putting an away message on the server went.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// On the server and answering (by its dates, when it keeps them).
    Placed,
    /// Kept on the device until its first day, for a server that can't
    /// tell dates.
    Waiting,
    /// Off, and nothing of it is left on the server.
    Removed,
    /// Another active script: nothing was changed on the server.
    OtherFilters,
    /// The server does not take an away message.
    Unsupported,
}

/// Puts `m` on the server, or takes it off when it is off. `addresses`
/// are the account's own; `today` is in the zone `zone` minutes east of
/// UTC.
pub async fn apply(
    server: &AwayServer,
    m: &AwayMessage,
    addresses: &[String],
    zone: i32,
    today: i64,
) -> Result<(Outcome, bool)> {
    match server {
        AwayServer::Sieve(cfg) => {
            let mut c = match sieve::Client::open(cfg).await {
                Ok(c) => c,
                Err(SieveError::Unsupported(_)) => return Ok((Outcome::Unsupported, false)),
                Err(e) => return Err(e.into()),
            };
            let dates = c.capabilities().dates();
            let outcome = place_sieve(&mut c, m, addresses, zone, today).await;
            c.logout().await;
            Ok((outcome?, dates))
        }
        AwayServer::Jmap(cfg) => {
            let client = jmap::Client::open(cfg).await?;
            if !client.has_vacation() {
                return Ok((Outcome::Unsupported, true));
            }
            let vacation = Vacation {
                enabled: m.on,
                from: m.start.map(|d| utc_start(d, zone)),
                to: m.end.map(|d| utc_start(d + 1, zone)),
                subject: m.subject.trim().to_owned(),
                text: m.body.clone(),
            };
            client.set_vacation(&vacation).await?;
            Ok((
                if m.on {
                    Outcome::Placed
                } else {
                    Outcome::Removed
                },
                true,
            ))
        }
    }
}

/// Takes our script off the server, if it is there.
async fn remove_ours(c: &mut sieve::Client, ours: Option<&sieve::Script>) -> Result<()> {
    if let Some(s) = ours {
        if s.active {
            c.set_active("").await?;
        }
        c.delete(SCRIPT).await?;
    }
    Ok(())
}

async fn place_sieve(
    c: &mut sieve::Client,
    m: &AwayMessage,
    addresses: &[String],
    zone: i32,
    today: i64,
) -> Result<Outcome> {
    if !c.capabilities().has("vacation") {
        return Ok(Outcome::Unsupported);
    }
    let dates = c.capabilities().dates();
    let scripts = c.list().await?;
    let ours = scripts.iter().find(|s| s.name == SCRIPT).cloned();
    if !m.on {
        remove_ours(c, ours.as_ref()).await?;
        return Ok(Outcome::Removed);
    }
    if scripts.iter().any(|s| s.active && s.name != SCRIPT) {
        // The person's own filters are active. Joining ours to them would
        // mean rewriting their script: the server is left as it is.
        return Ok(Outcome::OtherFilters);
    }
    if !dates && m.start.is_some_and(|s| s > today) {
        // An older text of ours must not answer before the first day.
        remove_ours(c, ours.as_ref()).await?;
        return Ok(Outcome::Waiting);
    }
    if !dates && m.end.is_some_and(|e| e < today) {
        remove_ours(c, ours.as_ref()).await?;
        return Ok(Outcome::Removed);
    }
    c.put(SCRIPT, &script(m, addresses, zone, dates)).await?;
    if !ours.is_some_and(|s| s.active) {
        c.set_active(SCRIPT).await?;
    }
    Ok(Outcome::Placed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(s: &str) -> i64 {
        parse_iso(s).unwrap()
    }

    fn away() -> AwayMessage {
        AwayMessage {
            on: true,
            start: Some(day("2026-10-27")),
            end: Some(day("2026-11-02")),
            subject: "Away until 3 November".into(),
            body: "Hi, I'm away until Monday 3 November.\nFor anything urgent, write to \"studio@studio.it\".\nMatteo".into(),
        }
    }

    #[test]
    fn writes_and_reads_days() {
        assert_eq!(iso(day("2026-10-27")), "2026-10-27");
        assert_eq!(parse_iso("2026-02-30"), None);
        assert_eq!(parse_iso("2026-13-01"), None);
        assert_eq!(parse_iso("nope"), None);
        assert_eq!(day("2026-11-02T10:00:00Z"), day("2026-11-02"));
        // 23:30 UTC on the 26th is already the 27th in Rome (+01:00 then +02:00).
        let at = day("2026-10-26") * 86_400 + 23 * 3600 + 30 * 60;
        assert_eq!(today(at, 120), day("2026-10-27"));
        assert_eq!(today(at, 0), day("2026-10-26"));
        assert_eq!(today(at, -300), day("2026-10-26"));
        assert_eq!(zone_name(120), "+0200");
        assert_eq!(zone_name(-330), "-0530");
        assert_eq!(utc_start(day("2026-10-27"), 60), "2026-10-26T23:00:00Z");
        assert_eq!(
            local_day("2026-10-26T23:00:00Z", 60),
            Some(day("2026-10-27"))
        );
    }

    #[test]
    fn the_script_answers_once_a_week_and_never_lists() {
        let s = script(
            &away(),
            &["Matteo@Studio.it".into(), "m@studio.it".into()],
            60,
            true,
        );
        assert!(s.contains("require [\"vacation\", \"date\", \"relational\"];"));
        assert!(s.contains("vacation :days 7 :subject \"Away until 3 November\""));
        assert!(s.contains(":addresses [\"matteo@studio.it\", \"m@studio.it\"]"));
        assert!(s.contains("not exists \"list-id\""));
        assert!(s.contains("not header :is \"precedence\" [\"bulk\", \"list\", \"junk\"]"));
        assert!(s.contains(
            "anyof (not exists \"auto-submitted\", header :is \"auto-submitted\" \"no\")"
        ));
        assert!(s.contains("\"*noreply*\""));
        assert!(s.contains("currentdate :zone \"+0100\" :value \"ge\" \"date\" \"2026-10-27\""));
        assert!(s.contains("currentdate :zone \"+0100\" :value \"le\" \"date\" \"2026-11-02\""));
        // Quotes escaped, lines in CRLF, nothing bare.
        assert!(s.contains("write to \\\"studio@studio.it\\\".\r\nMatteo\";"));
        assert!(!s.replace("\r\n", "").contains('\n'));
        assert!(s.ends_with("}\r\n"));
        // Balanced: every opening brace closed.
        assert_eq!(s.matches('{').count(), s.matches('}').count());
    }

    #[test]
    fn without_dates_the_script_leaves_them_to_the_device() {
        let s = script(&away(), &[], 0, false);
        assert!(s.contains("require [\"vacation\"];"));
        assert!(!s.contains("currentdate"));
        assert!(!s.contains(":addresses"));
        let open = AwayMessage {
            start: None,
            end: None,
            ..away()
        };
        assert!(script(&open, &[], 0, true).contains("require [\"vacation\"];"));
    }

    #[test]
    fn a_subject_stays_on_one_line() {
        let m = AwayMessage {
            subject: "Away\r\nBcc: someone".into(),
            body: "Back \\ soon".into(),
            ..away()
        };
        let s = script(&m, &[], 0, false);
        assert!(s.contains(":subject \"Away  Bcc: someone\""));
        assert!(s.contains("\"Back \\\\ soon\";"));
    }

    #[test]
    fn reads_back_its_own_script_only() {
        let m = away();
        assert_eq!(read_script(&script(&m, &[], 60, true)), Some(m));
        assert_eq!(read_script("require \"fileinto\";\r\nkeep;\r\n"), None);
    }

    #[test]
    fn knows_what_is_due() {
        let today = day("2026-10-30");
        let mut s = Stored {
            message: away(),
            zone: 60,
            placed: true,
            device_dates: false,
        };
        assert_eq!(due(&s, today), Due::Nothing);
        assert!(s.showing(today));
        assert!(!s.showing(day("2026-10-26")));
        assert_eq!(due(&s, day("2026-11-03")), Due::End);
        s.device_dates = true;
        s.placed = false;
        assert_eq!(due(&s, day("2026-10-26")), Due::Nothing);
        assert_eq!(due(&s, day("2026-10-27")), Due::Place);
        s.placed = true;
        s.message.on = false;
        assert_eq!(due(&s, today), Due::Remove);
        assert!(!s.showing(today));
        s.message.end = None;
        s.message.on = true;
        assert_eq!(due(&s, day("2027-01-01")), Due::Nothing);
    }
}
