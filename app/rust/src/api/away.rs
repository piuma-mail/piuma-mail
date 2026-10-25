//! The away message (`RemindAwayPrintToApprove`, section 2): an automatic
//! reply per account that the mail server sends (Sieve for IMAP, JMAP's
//! `VacationResponse`), so it answers with every device off. The login
//! is the account's own, from the keychain.

use std::collections::HashSet;
use std::sync::Mutex;

use flutter_rust_bridge::frb;
use piuma_core::away::{self, AwayError, AwayMessage, AwayServer, Due, Outcome, Stored};
use piuma_core::{Account, AccountId};

use super::engine::{engine, reader, store, EngineError, ErrorKind};
use crate::credentials;

/// An account's away message, with its days as "2026-10-27".
#[derive(Debug, Clone)]
pub struct AwayMessageInfo {
    pub enabled: bool,
    /// The first day; None from today.
    pub start: Option<String>,
    /// The last day; None keeps it on until it is turned off.
    pub end: Option<String>,
    pub subject: String,
    pub body: String,
}

impl From<&AwayMessage> for AwayMessageInfo {
    fn from(m: &AwayMessage) -> Self {
        AwayMessageInfo {
            enabled: m.on,
            start: m.start.map(away::iso),
            end: m.end.map(away::iso),
            subject: m.subject.clone(),
            body: m.body.clone(),
        }
    }
}

impl From<AwayMessageInfo> for AwayMessage {
    fn from(m: AwayMessageInfo) -> Self {
        AwayMessage {
            on: m.enabled,
            start: m.start.as_deref().and_then(away::parse_iso),
            end: m.end.as_deref().and_then(away::parse_iso),
            subject: m.subject,
            body: m.body,
        }
    }
}

/// How saving went.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AwaySaved {
    /// On the server as set (or kept here until its first day, for a
    /// server that can't tell dates), or off and gone from it.
    Saved,
    /// Another filter of the person's is active on the server: it can't
    /// be on alongside it, and the server was left as it was.
    OtherFilters,
    /// The server no longer takes an away message.
    Unsupported,
}

/// "Away message on for Work until Sun 2 Nov", at the top of the inbox.
#[derive(Debug, Clone)]
pub struct AwayLine {
    pub account_id: i64,
    /// The last day, "2026-11-02"; None until turned off.
    pub end: Option<String>,
}

impl From<AwayError> for EngineError {
    fn from(e: AwayError) -> Self {
        let kind = if e.is_auth() {
            ErrorKind::WrongPassword
        } else if e.is_offline() {
            ErrorKind::Unreachable
        } else {
            ErrorKind::Other
        };
        EngineError::new(kind, e.to_string())
    }
}

fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

fn account(id: i64) -> Result<Account, EngineError> {
    store()?
        .account(AccountId(id))?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "no such account"))
}

/// Runs a request to the server on the engine's runtime.
async fn on_runtime<T: Send + 'static>(
    work: impl std::future::Future<Output = Result<T, AwayError>> + Send + 'static,
) -> Result<T, EngineError> {
    engine()?
        .runtime
        .spawn(work)
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
        .map_err(EngineError::from)
}

/// The account's away message, as its server has it; None when the
/// server takes none (no ManageSieve with vacation, or JMAP without
/// `vacationresponse`), and the Settings row is not shown.
pub async fn away_message(
    account_id: i64,
    utc_offset_minutes: i32,
) -> Result<Option<AwayMessageInfo>, EngineError> {
    let a = account(account_id)?;
    let server = AwayServer::for_account(&a, &credentials::load(a.id)?);
    let zone = utc_offset_minutes;
    let Some(status) = on_runtime(async move { away::status(&server, zone).await }).await? else {
        return Ok(None);
    };
    let store = store()?;
    let stored = store.away_message(a.id)?;
    let mut s = stored.clone().unwrap_or(Stored {
        zone,
        ..Stored::default()
    });
    let waiting = s.device_dates && s.message.on && !s.placed;
    match status.message {
        // What the server has is what answers, whichever device set it.
        Some(m) if status.placed => {
            s.message = m;
            s.placed = true;
        }
        // Off there: the words set here stay for next time.
        Some(m) if stored.is_none() => {
            s.message = AwayMessage { on: false, ..m };
            s.placed = false;
        }
        _ if waiting => {}
        _ => {
            s.message.on = false;
            s.placed = false;
        }
    }
    s.device_dates = !status.dates;
    store.set_away_message(a.id, &s)?;
    Ok(Some(AwayMessageInfo::from(&s.message)))
}

/// Sets the account's away message on its server, and keeps it here.
pub async fn set_away_message(
    account_id: i64,
    message: AwayMessageInfo,
    utc_offset_minutes: i32,
) -> Result<AwaySaved, EngineError> {
    let a = account(account_id)?;
    let m = AwayMessage::from(message);
    let saved = place(&a, &credentials::load(a.id)?, m, utc_offset_minutes).await?;
    Ok(saved)
}

/// "Turn off", from the line in the inbox.
pub async fn turn_off_away_message(account_id: i64) -> Result<(), EngineError> {
    let a = account(account_id)?;
    let Some(s) = store()?.away_message(a.id)? else {
        return Ok(());
    };
    let m = AwayMessage {
        on: false,
        ..s.message
    };
    place(&a, &credentials::load(a.id)?, m, s.zone).await?;
    Ok(())
}

async fn place(
    a: &Account,
    password: &str,
    m: AwayMessage,
    zone: i32,
) -> Result<AwaySaved, EngineError> {
    let addresses = store()?.own_addresses(a.id)?;
    let server = AwayServer::for_account(a, password);
    let today = away::today(now(), zone);
    let wanted = m.clone();
    let (outcome, dates) =
        on_runtime(async move { away::apply(&server, &wanted, &addresses, zone, today).await })
            .await?;
    let (on, placed) = match outcome {
        Outcome::Placed => (m.on, true),
        Outcome::Waiting => (m.on, false),
        Outcome::Removed => (false, false),
        Outcome::OtherFilters | Outcome::Unsupported => (false, false),
    };
    store()?.set_away_message(
        a.id,
        &Stored {
            message: AwayMessage { on, ..m },
            zone,
            placed,
            device_dates: !dates,
        },
    )?;
    Ok(match outcome {
        Outcome::OtherFilters => AwaySaved::OtherFilters,
        Outcome::Unsupported => AwaySaved::Unsupported,
        _ => AwaySaved::Saved,
    })
}

/// The away messages answering now, one line per account at most.
#[frb(sync)]
pub fn away_lines() -> Result<Vec<AwayLine>, EngineError> {
    let now = now();
    Ok(reader()?
        .away_messages()?
        .into_iter()
        .filter(|(_, s)| s.showing(away::today(now, s.zone)))
        .map(|(account, s)| AwayLine {
            account_id: account.0,
            end: s.message.end.map(away::iso),
        })
        .collect())
}

/// Accounts with a change to their away message on the way.
static BUSY: Mutex<Option<HashSet<i64>>> = Mutex::new(None);

/// Keeps an away message to its days, each time the account is in touch
/// with its server: it ends after its last day, and on a server that
/// can't tell dates it starts on its first.
pub(crate) fn keep_on_time(account: Account, password: String) {
    let Ok(Some(s)) = store().and_then(|s| Ok(s.away_message(account.id)?)) else {
        return;
    };
    let wanted = match away::due(&s, away::today(now(), s.zone)) {
        Due::Nothing => return,
        Due::Place => s.message.clone(),
        Due::Remove | Due::End => AwayMessage {
            on: false,
            ..s.message.clone()
        },
    };
    {
        let mut busy = BUSY.lock().unwrap_or_else(|e| e.into_inner());
        if !busy.get_or_insert_with(HashSet::new).insert(account.id.0) {
            return;
        }
    }
    let Ok(engine) = engine() else { return };
    engine.runtime.spawn(async move {
        let _ = place(&account, &password, wanted, s.zone).await;
        if let Some(busy) = BUSY.lock().unwrap_or_else(|e| e.into_inner()).as_mut() {
            busy.remove(&account.id.0);
        }
    });
}
