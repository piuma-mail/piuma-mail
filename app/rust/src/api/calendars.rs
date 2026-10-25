//! Connected calendars, for Settings › Calendars and the invite card:
//! CalDAV accounts and .ics feeds, which calendars count for
//! availability, and where accepted invites go.

use flutter_rust_bridge::frb;
use piuma_core::calendar::{self, CalDav, CalendarError};
use piuma_core::store::{CalendarRow, CalendarSource};
use piuma_core::{dates, invite, AccountId};

use super::engine::{now_secs, reader, store, EngineError, ErrorKind};
use crate::credentials;

/// How long events read from a server are trusted before reading again.
const FRESH: i64 = 15 * 60;
/// How far back and ahead events are kept.
const BEHIND: i64 = 86_400;
const AHEAD: i64 = 90 * 86_400;
/// A feed that doesn't say how often to read it is read daily, and none
/// more often than FRESH or less often than weekly.
const FEED_DEFAULT: i64 = 86_400;
const FEED_LONGEST: i64 = 7 * 86_400;

const DEFAULT: &str = "calendars.default";
const CONFLICTS: &str = "calendars.conflicts";
const FIND_DATES: &str = "calendars.find_dates";
/// How long an event made from a day in a message lasts.
const FOUND_LENGTH: i64 = 3600;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalendarKind {
    CalDav,
    Ics,
}

#[derive(Debug, Clone)]
pub struct CalendarInfo {
    pub id: i64,
    pub name: String,
    /// "#RRGGBB", when the server keeps one.
    pub color: Option<String>,
    pub read_only: bool,
    /// Its events count when telling whether you are free.
    pub availability: bool,
}

#[derive(Debug, Clone)]
pub struct CalendarSourceInfo {
    pub id: i64,
    pub kind: CalendarKind,
    pub name: String,
    /// The user name, or the feed's address.
    pub detail: String,
    /// The email account it shares a password with.
    pub account_id: Option<i64>,
    pub calendars: Vec<CalendarInfo>,
    /// For a feed, how often it is read again, in seconds.
    pub updates_every: Option<i64>,
}

/// An email account whose provider offers a calendar too.
#[derive(Debug, Clone)]
pub struct CalendarSuggestion {
    pub account_id: i64,
    pub email: String,
}

#[derive(Debug, Clone)]
pub struct CalendarPrefs {
    /// Where accepted invites go; None when no calendar takes events.
    pub default_calendar: Option<i64>,
    /// Invites show when you are already busy.
    pub check_conflicts: bool,
    /// Days with a time in a message's words are offered for a calendar.
    pub find_dates: bool,
}

/// A day with a time in a message's words, offered for a calendar.
#[derive(Debug, Clone)]
pub struct FoundDateInfo {
    /// The block it is in, and where in the block's text, in UTF-16 units.
    pub block: u32,
    pub start: u32,
    pub end: u32,
    /// The wall-clock time it names, written as if it were UTC.
    pub at: i64,
    /// The event's uid, to add it with [add_found_date].
    pub uid: String,
    /// The calendar it went to, once added.
    pub added_to: Option<String>,
}

/// An event that makes you busy. With `floating` the times are the
/// wall-clock time where you are, written as if they were UTC.
#[derive(Debug, Clone)]
pub struct BusyInfo {
    pub uid: String,
    pub summary: String,
    pub start: i64,
    pub end: i64,
    pub all_day: bool,
    pub floating: bool,
    pub calendar: String,
    pub color: Option<String>,
}

impl From<CalendarError> for EngineError {
    fn from(e: CalendarError) -> Self {
        let kind = match &e {
            CalendarError::WrongPassword => ErrorKind::WrongPassword,
            CalendarError::NotFound(_) | CalendarError::Connect { .. } => ErrorKind::Unreachable,
            _ => ErrorKind::Other,
        };
        EngineError::new(kind, e.to_string())
    }
}

fn info(source: &CalendarSource, calendars: &[CalendarRow]) -> CalendarSourceInfo {
    CalendarSourceInfo {
        id: source.id,
        kind: if source.kind == "ics" {
            CalendarKind::Ics
        } else {
            CalendarKind::CalDav
        },
        name: source.name.clone(),
        detail: if source.kind == "ics" {
            source.url.clone()
        } else {
            source.username.clone()
        },
        account_id: source.account.map(|a| a.0),
        updates_every: (source.kind == "ics").then(|| fresh_for(source)),
        calendars: calendars
            .iter()
            .filter(|c| c.source == source.id)
            .map(|c| CalendarInfo {
                id: c.id,
                name: c.name.clone(),
                color: c.color.clone(),
                read_only: c.read_only,
                availability: c.availability,
            })
            .collect(),
    }
}

/// Every connected calendar, by where it comes from.
#[frb(sync)]
pub fn calendar_sources() -> Result<Vec<CalendarSourceInfo>, EngineError> {
    let store = reader()?;
    let calendars = store.calendars()?;
    Ok(store
        .calendar_sources()?
        .iter()
        .map(|s| info(s, &calendars))
        .collect())
}

/// Email accounts whose provider has a calendar with the same password,
/// not connected yet.
#[frb(sync)]
pub fn calendar_suggestions() -> Result<Vec<CalendarSuggestion>, EngineError> {
    let store = reader()?;
    let linked: Vec<AccountId> = store
        .calendar_sources()?
        .iter()
        .filter_map(|s| s.account)
        .collect();
    Ok(store
        .accounts()?
        .into_iter()
        .filter(|a| calendar::offers_calendar(&a.email) && !linked.contains(&a.id))
        .map(|a| CalendarSuggestion {
            account_id: a.id.0,
            email: a.email,
        })
        .collect())
}

/// A short name for a CalDAV server: the provider's, else its host.
fn server_name(home: &str, address: &str) -> String {
    let host = calendar::host(home).unwrap_or_default();
    if host.ends_with("icloud.com") {
        "iCloud".into()
    } else if host.ends_with("fastmail.com") {
        "Fastmail".into()
    } else if address.contains('@') && !address.contains("://") {
        address.trim().to_owned()
    } else {
        host
    }
}

/// Connects a CalDAV account: an email address or a server address, the
/// user name (empty: the email address) and the password, which goes in
/// the system keychain.
pub async fn connect_caldav(
    address: String,
    username: String,
    password: String,
) -> Result<CalendarSourceInfo, EngineError> {
    let username = if username.trim().is_empty() {
        address.trim().to_owned()
    } else {
        username.trim().to_owned()
    };
    let found = CalDav::new(&username, &password)?
        .discover(&address)
        .await?;
    let name = server_name(&found.home, &address);
    let id = store()?.add_calendar_source("caldav", &name, &found.home, &username, None)?;
    if let Err(e) = credentials::save_key(&credentials::calendar_key(id), &password) {
        store()?.delete_calendar_source(id)?;
        return Err(e);
    }
    finish(id, &found.calendars).await
}

/// Connects the calendar of an email account, with its password.
pub async fn connect_account_calendar(account_id: i64) -> Result<CalendarSourceInfo, EngineError> {
    let (account, password) = super::engine::signed_in(AccountId(account_id))?;
    let found = CalDav::new(&account.email, &password)?
        .discover(&account.email)
        .await?;
    let name = server_name(&found.home, &account.email);
    let id = store()?.add_calendar_source(
        "caldav",
        &name,
        &found.home,
        &account.email,
        Some(account.id),
    )?;
    finish(id, &found.calendars).await
}

/// Subscribes to an .ics feed, read-only.
pub async fn subscribe_calendar(url: String) -> Result<CalendarSourceInfo, EngineError> {
    let url = calendar::feed_url(&url);
    let calendar::Feed {
        name,
        events,
        refresh,
    } = calendar::feed(&url).await?;
    let name = name
        .or_else(|| calendar::host(&url))
        .unwrap_or_else(|| url.clone());
    let id = {
        let mut store = store()?;
        let id = store.add_calendar_source("ics", &name, &url, "", None)?;
        store.set_calendars(
            id,
            &[calendar::RemoteCalendar {
                url: url.clone(),
                name: name.clone(),
                color: None,
                read_only: true,
            }],
        )?;
        // A feed is mostly holidays and the like: it doesn't make you
        // busy unless you say so.
        for c in store.calendars()?.iter().filter(|c| c.source == id) {
            store.set_calendar_availability(c.id, false)?;
            store.set_calendar_events(c.id, &events)?;
        }
        store.set_calendar_synced(id, now_secs())?;
        store.set_calendar_refresh(id, refresh)?;
        id
    };
    source_info(id)
}

async fn finish(
    id: i64,
    calendars: &[calendar::RemoteCalendar],
) -> Result<CalendarSourceInfo, EngineError> {
    store()?.set_calendars(id, calendars)?;
    // The events come now, so availability is right away; a failure here
    // leaves the calendars connected, to read again later.
    let _ = refresh_source(id).await;
    source_info(id)
}

fn source_info(id: i64) -> Result<CalendarSourceInfo, EngineError> {
    calendar_sources()?
        .into_iter()
        .find(|s| s.id == id)
        .ok_or(EngineError::new(ErrorKind::Other, "no such calendar"))
}

/// Disconnects a source: its calendars and events are forgotten here,
/// and stay on their server.
pub fn disconnect_calendar(source_id: i64) -> Result<(), EngineError> {
    let store = store()?;
    store.delete_calendar_source(source_id)?;
    credentials::forget_key(&credentials::calendar_key(source_id));
    if let Some(default) = default_calendar(&store)? {
        if !store.calendars()?.iter().any(|c| c.id == default) {
            store.set_setting(DEFAULT, "")?;
        }
    }
    Ok(())
}

pub fn set_calendar_availability(calendar_id: i64, on: bool) -> Result<(), EngineError> {
    store()?.set_calendar_availability(calendar_id, on)?;
    Ok(())
}

fn default_calendar(store: &piuma_core::Store) -> Result<Option<i64>, EngineError> {
    let calendars = store.calendars()?;
    let chosen = store
        .setting(DEFAULT)?
        .and_then(|v| v.parse::<i64>().ok())
        .filter(|id| calendars.iter().any(|c| c.id == *id && !c.read_only));
    Ok(chosen.or_else(|| calendars.iter().find(|c| !c.read_only).map(|c| c.id)))
}

#[frb(sync)]
pub fn calendar_prefs() -> Result<CalendarPrefs, EngineError> {
    let store = reader()?;
    Ok(CalendarPrefs {
        default_calendar: default_calendar(&store)?,
        check_conflicts: store.setting(CONFLICTS)?.as_deref() != Some("0"),
        find_dates: store.setting(FIND_DATES)?.as_deref() != Some("0"),
    })
}

pub fn set_find_dates(on: bool) -> Result<(), EngineError> {
    store()?.set_setting(FIND_DATES, if on { "1" } else { "0" })?;
    Ok(())
}

pub fn set_default_calendar(calendar_id: i64) -> Result<(), EngineError> {
    store()?.set_setting(DEFAULT, &calendar_id.to_string())?;
    Ok(())
}

pub fn set_check_conflicts(on: bool) -> Result<(), EngineError> {
    store()?.set_setting(CONFLICTS, if on { "1" } else { "0" })?;
    Ok(())
}

/// Android only, where the app keeps passwords in the Android Keystore:
/// hands a calendar's password over at start.
#[frb(sync)]
pub fn remember_calendar_password(source_id: i64, password: String) {
    #[cfg(target_os = "android")]
    credentials::remember_key(&credentials::calendar_key(source_id), &password);
    #[cfg(not(target_os = "android"))]
    let _ = (source_id, password);
}

fn password(source: &CalendarSource) -> Result<String, EngineError> {
    match source.account {
        Some(account) => credentials::load(account),
        None => credentials::load_key(&credentials::calendar_key(source.id)),
    }
}

/// Reads a source's events again, and its list of calendars.
async fn refresh_source(id: i64) -> Result<(), EngineError> {
    let source = store()?
        .calendar_sources()?
        .into_iter()
        .find(|s| s.id == id)
        .ok_or(EngineError::new(ErrorKind::Other, "no such calendar"))?;
    let now = now_secs();
    if source.kind == "ics" {
        let feed = calendar::feed(&source.url).await?;
        let mut store = store()?;
        for c in store.calendars()?.iter().filter(|c| c.source == id) {
            store.set_calendar_events(c.id, &feed.events)?;
        }
        store.set_calendar_synced(id, now)?;
        store.set_calendar_refresh(id, feed.refresh)?;
        return Ok(());
    }
    let dav = CalDav::new(&source.username, &password(&source)?)?;
    if let Ok(calendars) = dav.calendars(&source.url).await {
        store()?.set_calendars(id, &calendars)?;
    }
    let calendars: Vec<CalendarRow> = store()?
        .calendars()?
        .into_iter()
        .filter(|c| c.source == id)
        .collect();
    for c in calendars {
        let events = dav.events(&c.url, now - BEHIND, now + AHEAD).await?;
        store()?.set_calendar_events(c.id, &events)?;
    }
    store()?.set_calendar_synced(id, now)?;
    Ok(())
}

/// How long a source's events are trusted before reading it again.
fn fresh_for(source: &CalendarSource) -> i64 {
    match source.kind.as_str() {
        "ics" => source
            .refresh
            .unwrap_or(FEED_DEFAULT)
            .clamp(FRESH, FEED_LONGEST),
        _ => FRESH,
    }
}

/// Reads again the sources not read in the last minutes. Errors are left
/// for the next time: what was read before still counts.
pub async fn refresh_calendars() -> Result<(), EngineError> {
    let now = now_secs();
    let stale: Vec<i64> = store()?
        .calendar_sources()?
        .into_iter()
        .filter(|s| s.synced.is_none_or(|at| now - at > fresh_for(s)))
        .map(|s| s.id)
        .collect();
    for id in stale {
        let _ = refresh_source(id).await;
    }
    Ok(())
}

/// What makes you busy around a span (Unix seconds), from the calendars
/// that count for availability, read again first if they are stale.
/// Floating and all-day times are widened by a day: the app narrows them
/// with your time zone.
pub async fn busy_between(start: i64, end: i64) -> Result<Vec<BusyInfo>, EngineError> {
    refresh_calendars().await?;
    Ok(store()?
        .busy(start, end)?
        .into_iter()
        .map(|b| BusyInfo {
            uid: b.uid,
            summary: b.summary,
            start: b.start,
            end: b.end,
            all_day: b.all_day,
            floating: b.floating,
            calendar: b.calendar,
            color: b.color,
        })
        .collect())
}

/// Puts an accepted invite in the calendar chosen for invites. Gives that
/// calendar's name, or None when there is none or the server refused.
/// The days with a time in a message, when there is a calendar to put
/// them in and the person wants them offered. Days already past, and the
/// time of the invite it carries, are left out; three at most.
pub(crate) fn found_dates(
    store: &piuma_core::Store,
    message: &piuma_core::model::MessageSummary,
    blocks: &[piuma_core::reading::Block],
    // Wall clock, like the days found.
    invite_start: Option<i64>,
    utc_offset_minutes: i32,
) -> Result<Vec<FoundDateInfo>, EngineError> {
    if store.setting(FIND_DATES)?.as_deref() == Some("0")
        || default_calendar(store)?.is_none()
        || store.is_newsletter(message.account, &message.mailbox, message.uid)?
    {
        return Ok(Vec::new());
    }
    let offset = i64::from(utc_offset_minutes) * 60;
    let reference = (message.received_at + offset).div_euclid(86_400);
    let now = now_secs() + offset;
    let key = if message.reply.message_id.is_empty() {
        format!("{}/{}/{}", message.account.0, message.mailbox, message.uid)
    } else {
        message.reply.message_id.clone()
    };
    let mut out: Vec<FoundDateInfo> = Vec::new();
    for (i, block) in blocks.iter().enumerate() {
        let text = block.text();
        for f in dates::find(&text, reference) {
            let at = f.day * 86_400 + i64::from(f.minute) * 60;
            if at < now || invite_start == Some(at) || out.iter().any(|o| o.at == at) {
                continue;
            }
            let uid = format!("piuma-found-{:016x}-{at}", fnv(&key));
            let utf16 = |byte: usize| text[..byte].encode_utf16().count() as u32;
            out.push(FoundDateInfo {
                block: i as u32,
                start: utf16(f.start),
                end: utf16(f.end),
                at,
                added_to: store.found_date(&uid)?,
                uid,
            });
            if out.len() == 3 {
                return Ok(out);
            }
        }
    }
    Ok(out)
}

/// A short, stable fingerprint, so the same day in the same message is
/// always the same event.
fn fnv(text: &str) -> u64 {
    text.bytes().fold(0xcbf2_9ce4_8422_2325, |h, b| {
        (h ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
    })
}

/// Puts a day found in a message in the calendar that takes invites, for
/// an hour, and gives the calendar's name. `start` is in UTC.
pub async fn add_found_date(
    uid: String,
    summary: String,
    start: i64,
) -> Result<String, EngineError> {
    let (source, calendar) = {
        let store = store()?;
        let id = default_calendar(&store)?.ok_or(EngineError::new(
            ErrorKind::Other,
            "no calendar takes events",
        ))?;
        let calendar = store
            .calendars()?
            .into_iter()
            .find(|c| c.id == id)
            .ok_or(EngineError::new(ErrorKind::Other, "no such calendar"))?;
        let source = store
            .calendar_sources()?
            .into_iter()
            .find(|s| s.id == calendar.source && s.kind == "caldav")
            .ok_or(EngineError::new(
                ErrorKind::Other,
                "the calendar is read-only",
            ))?;
        (source, calendar)
    };
    let ics = dates::event(&uid, &summary, start, start + FOUND_LENGTH, now_secs());
    let dav = CalDav::new(&source.username, &password(&source)?)?;
    dav.add(&calendar.url, &uid, &ics).await?;
    store()?.set_found_date(&uid, &calendar.name, now_secs())?;
    let _ = refresh_source(source.id).await;
    Ok(calendar.name)
}

pub(crate) async fn add_invite(
    ics: &str,
    me_email: &str,
    answer: invite::Answer,
) -> Option<String> {
    let (source, calendar) = {
        let store = store().ok()?;
        let id = default_calendar(&store).ok()??;
        let calendar = store.calendars().ok()?.into_iter().find(|c| c.id == id)?;
        let source = store
            .calendar_sources()
            .ok()?
            .into_iter()
            .find(|s| s.id == calendar.source && s.kind == "caldav")?;
        (source, calendar)
    };
    let event = invite::parse(ics)?;
    let kept = invite::for_calendar(ics, me_email, answer)?;
    let dav = CalDav::new(&source.username, &password(&source).ok()?).ok()?;
    dav.add(&calendar.url, &event.uid, &kept).await.ok()?;
    let _ = refresh_source(source.id).await;
    Some(calendar.name)
}
