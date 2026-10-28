//! What deserves a notification: email written by people (or all of it),
//! one notice per sender, quiet at night and, if chosen, at weekends.

use mail_parser::{HeaderName, Message};

use crate::model::{AccountId, MessageSummary};
use crate::store::{Result, Store};

/// "Notify me about" in Settings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Mode {
    /// Email written by people: no newsletters, receipts or automated mail.
    #[default]
    People,
    /// Every new email in the Inbox.
    All,
    /// Nothing.
    Off,
}

impl Mode {
    pub fn tag(self) -> &'static str {
        match self {
            Mode::People => "people",
            Mode::All => "all",
            Mode::Off => "off",
        }
    }

    pub fn from_tag(tag: &str) -> Option<Mode> {
        [Mode::People, Mode::All, Mode::Off]
            .into_iter()
            .find(|m| m.tag() == tag)
    }
}

/// Minutes in a week. Local times are counted from Monday 00:00
/// ("week minutes"), so quiet hours can tell a Saturday.
pub const WEEK: u16 = 7 * 24 * 60;

/// The week minute of `minute` (after local midnight) on `weekday`, 0 for
/// Monday to 6 for Sunday.
pub fn week_minute(weekday: u8, minute: u16) -> u16 {
    (u16::from(weekday % 7) * 24 * 60 + minute % (24 * 60)) % WEEK
}

/// The local week minute at `secs` (Unix time), `utc_offset_minutes` from
/// UTC. 1 January 1970 was a Thursday.
pub fn week_minute_at(secs: i64, utc_offset_minutes: i32) -> u16 {
    let local = secs + i64::from(utc_offset_minutes) * 60;
    let day = local.div_euclid(86_400);
    let weekday = (day + 3).rem_euclid(7) as u8;
    week_minute(weekday, (local.rem_euclid(86_400) / 60) as u16)
}

/// What quiet hours do to a notice.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Quiet {
    /// Not quiet now, or an account that rings as usual.
    Ring,
    /// Shown without a sound.
    Silent,
    /// Not shown; summed up when quiet hours end.
    Hold,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Settings {
    pub mode: Mode,
    /// Quiet every night, from [Settings::quiet_from] to [Settings::quiet_to].
    pub quiet: bool,
    /// Minutes after midnight, local time.
    pub quiet_from: u16,
    pub quiet_to: u16,
    /// Quiet all day on Saturday and Sunday.
    pub weekends: bool,
    /// While quiet, no notices at all (summed up at the end) rather than
    /// notices without a sound.
    pub hold: bool,
    /// Vault: a notice on a parcel's delivery day, and before a bill is due.
    pub parcels: bool,
    pub due: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            mode: Mode::People,
            quiet: true,
            quiet_from: 22 * 60,
            quiet_to: 8 * 60,
            weekends: false,
            hold: false,
            parcels: true,
            due: true,
        }
    }
}

impl Settings {
    pub fn load(store: &Store) -> Result<Settings> {
        let d = Settings::default();
        let minutes = |key: &str, fallback: u16| -> Result<u16> {
            Ok(store
                .setting(key)?
                .and_then(|v| v.parse::<u16>().ok())
                .filter(|m| *m < 24 * 60)
                .unwrap_or(fallback))
        };
        Ok(Settings {
            mode: store
                .setting("notify.mode")?
                .and_then(|v| Mode::from_tag(&v))
                .unwrap_or(d.mode),
            quiet: store
                .setting("notify.quiet")?
                .map_or(d.quiet, |v| v == "on"),
            quiet_from: minutes("notify.quiet_from", d.quiet_from)?,
            quiet_to: minutes("notify.quiet_to", d.quiet_to)?,
            weekends: store
                .setting("notify.weekends")?
                .map_or(d.weekends, |v| v == "on"),
            hold: store
                .setting("notify.while_quiet")?
                .map_or(d.hold, |v| v == "hold"),
            parcels: store
                .setting(crate::vault::NOTIFY_PARCELS)?
                .map_or(d.parcels, |v| v == "on"),
            due: store
                .setting(crate::vault::NOTIFY_DUE)?
                .map_or(d.due, |v| v == "on"),
        })
    }

    pub fn save(&self, store: &Store) -> Result<()> {
        store.set_setting("notify.mode", self.mode.tag())?;
        store.set_setting("notify.quiet", if self.quiet { "on" } else { "off" })?;
        store.set_setting("notify.quiet_from", &self.quiet_from.min(1439).to_string())?;
        store.set_setting("notify.quiet_to", &self.quiet_to.min(1439).to_string())?;
        let on = |b: bool| if b { "on" } else { "off" };
        store.set_setting("notify.weekends", on(self.weekends))?;
        store.set_setting(
            "notify.while_quiet",
            if self.hold { "hold" } else { "silent" },
        )?;
        store.set_setting(crate::vault::NOTIFY_PARCELS, on(self.parcels))?;
        store.set_setting(crate::vault::NOTIFY_DUE, on(self.due))?;
        Ok(())
    }

    /// Whether Vault notices may come at `week_minute`: from 8:00, and not
    /// in the night's quiet hours, so a parcel's day doesn't start with a
    /// buzz. Quiet weekends don't hold them back (a parcel can come on a
    /// Saturday); they come without a sound.
    pub fn reminders_at(&self, week_minute: u16) -> bool {
        let minute = week_minute % (24 * 60);
        minute >= 8 * 60 && !self.night_at(minute)
    }

    /// Whether `week_minute` falls in the quiet hours: the night's, or a
    /// quiet weekend's.
    pub fn quiet_at(&self, week_minute: u16) -> bool {
        let day = (week_minute % WEEK) / (24 * 60);
        (self.weekends && day >= 5) || self.night_at(week_minute % (24 * 60))
    }

    /// What quiet hours do at `week_minute` to a notice from an account
    /// they cover (`covered`; see [`covers`]).
    pub fn quiet(&self, week_minute: u16, covered: bool) -> Quiet {
        if !covered || !self.quiet_at(week_minute) {
            Quiet::Ring
        } else if self.hold {
            Quiet::Hold
        } else {
            Quiet::Silent
        }
    }

    /// Whether `minute` (after local midnight) falls in the night's quiet
    /// hours. They can run past midnight, as 22:00 to 8:00 does.
    fn night_at(&self, minute: u16) -> bool {
        if !self.quiet || self.quiet_from == self.quiet_to {
            return false;
        }
        if self.quiet_from < self.quiet_to {
            (self.quiet_from..self.quiet_to).contains(&minute)
        } else {
            minute >= self.quiet_from || minute < self.quiet_to
        }
    }
}

fn loud_key(account: AccountId) -> String {
    format!("notify.loud.{}", account.0)
}

/// Whether quiet hours cover `account`; one switched off rings as usual.
pub fn covers(store: &Store, account: AccountId) -> Result<bool> {
    Ok(store.setting(&loud_key(account))?.as_deref() != Some("on"))
}

pub fn set_covers(store: &Store, account: AccountId, covered: bool) -> Result<()> {
    store.set_setting(&loud_key(account), if covered { "off" } else { "on" })
}

/// What came while quiet hours held notices back, for "While you were
/// away · 12 emails, 3 from people: Sara Conti, Luca Bianchi, Dad".
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Away {
    pub emails: u32,
    /// Of those, written by people.
    pub people: u32,
    /// Who, newest first, at most [`AWAY_NAMES`].
    pub names: Vec<String>,
}

/// Names the summary keeps.
pub const AWAY_NAMES: usize = 3;

impl Away {
    fn load(store: &Store) -> Result<Away> {
        let count = |key: &str| -> Result<u32> {
            Ok(store
                .setting(key)?
                .and_then(|v| v.parse().ok())
                .unwrap_or(0))
        };
        Ok(Away {
            emails: count("notify.away.emails")?,
            people: count("notify.away.people")?,
            names: store
                .setting("notify.away.names")?
                .map(|v| {
                    v.split('\n')
                        .filter(|n| !n.is_empty())
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
        })
    }

    fn save(&self, store: &Store) -> Result<()> {
        store.set_setting("notify.away.emails", &self.emails.to_string())?;
        store.set_setting("notify.away.people", &self.people.to_string())?;
        store.set_setting("notify.away.names", &self.names.join("\n"))
    }
}

/// Keeps `notice`, held back by quiet hours, for the summary.
pub fn hold(store: &Store, notice: &Notice) -> Result<()> {
    let mut away = Away::load(store)?;
    away.emails += notice.count;
    if notice.people {
        away.people += notice.count;
        away.names.retain(|n| n != &notice.sender);
        away.names.insert(0, notice.sender.clone());
        away.names.truncate(AWAY_NAMES);
    }
    away.save(store)
}

/// The summary of what was held, once quiet hours are over at
/// `week_minute`; it is then cleared. None while still quiet, or when
/// nothing came.
pub fn take_away(store: &Store, settings: &Settings, week_minute: u16) -> Result<Option<Away>> {
    if settings.quiet_at(week_minute) {
        return Ok(None);
    }
    let away = Away::load(store)?;
    if away.emails == 0 {
        return Ok(None);
    }
    Away::default().save(store)?;
    Ok(Some(away))
}

/// A message that has just arrived, with what the headers say about who
/// wrote it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Arrival {
    pub summary: MessageSummary,
    pub automated: bool,
}

/// One notification: the newest message of a sender, and how many came.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notice {
    pub account: AccountId,
    pub mailbox: String,
    /// The newest one, opened when the notice is clicked.
    pub uid: u32,
    pub sender: String,
    pub sender_email: String,
    pub subject: String,
    pub preview: String,
    pub count: u32,
    /// Written by a person, not a machine.
    pub people: bool,
}

/// Counts mail from the person's own addresses, from addresses they wrote
/// to and in conversations they replied to as written by people, whatever
/// its headers say, as the People list does ([`Store::person_wrote`]).
pub fn known_people(store: &Store, arrivals: &mut [Arrival]) -> Result<()> {
    for a in arrivals.iter_mut().filter(|a| a.automated) {
        if store.person_wrote(&a.summary)? {
            a.automated = false;
        }
    }
    Ok(())
}

/// Mail older than this when it lands (catching up after a while offline)
/// is not news.
pub const RECENT_SECS: i64 = 24 * 60 * 60;

/// The notices for `arrivals`, newest sender first. Read mail, old mail
/// and, in People mode, automated mail make none.
pub fn notices(arrivals: &[Arrival], settings: &Settings, now: i64) -> Vec<Notice> {
    if settings.mode == Mode::Off {
        return Vec::new();
    }
    let mut picked: Vec<&Arrival> = arrivals
        .iter()
        .filter(|a| !a.summary.flags.seen)
        .filter(|a| now - a.summary.received_at <= RECENT_SECS)
        .filter(|a| settings.mode == Mode::All || !a.automated)
        // Certified-mail receipts go straight to the Vault.
        .filter(|a| a.summary.list.receipt.is_none())
        .collect();
    picked.sort_by_key(|a| std::cmp::Reverse((a.summary.received_at, a.summary.uid)));
    let mut out: Vec<Notice> = Vec::new();
    for a in picked {
        let m = &a.summary;
        let key = m.from_email.to_lowercase();
        if let Some(n) = out
            .iter_mut()
            .find(|n| n.account == m.account && n.sender_email.to_lowercase() == key)
        {
            n.count += 1;
            continue;
        }
        out.push(Notice {
            account: m.account,
            mailbox: m.mailbox.clone(),
            uid: m.uid,
            sender: if m.from_name.is_empty() {
                m.from_email.clone()
            } else {
                m.from_name.clone()
            },
            sender_email: m.from_email.clone(),
            subject: m.subject.clone(),
            preview: m.preview.clone(),
            count: 1,
            people: !a.automated,
        });
    }
    out
}

/// The header fields [`automated`] looks at, for an IMAP fetch.
pub const HEADER_FIELDS: &str = "LIST-ID LIST-UNSUBSCRIBE PRECEDENCE AUTO-SUBMITTED";

/// Whether a message was sent by a machine: a mailing list or newsletter,
/// bulk mail, an automatic reply, or a no-reply address.
pub fn automated(m: &Message) -> bool {
    let has = |name: HeaderName| m.header(name).is_some();
    let text = |name: &str| {
        m.header_raw(name)
            .map(|v| v.trim().to_ascii_lowercase())
            .unwrap_or_default()
    };
    if has(HeaderName::ListId) || has(HeaderName::ListUnsubscribe) {
        return true;
    }
    if matches!(text("Precedence").as_str(), "bulk" | "list" | "junk") {
        return true;
    }
    let submitted = text("Auto-Submitted");
    if !submitted.is_empty() && submitted != "no" {
        return true;
    }
    let from = m
        .from()
        .and_then(|a| a.first())
        .and_then(|a| a.address())
        .unwrap_or_default()
        .to_ascii_lowercase();
    crate::automation::headers(m)
        || crate::automation::message(m)
        || crate::automation::machine_address(&from)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Flags, ReplyInfo};
    use mail_parser::MessageParser;

    fn parse(raw: &str) -> bool {
        automated(&MessageParser::default().parse(raw.as_bytes()).unwrap())
    }

    #[test]
    fn people_and_machines() {
        assert!(!parse(
            "From: Giulia <giulia@posta.it>\r\nSubject: Dinner\r\n\r\nHi"
        ));
        assert!(parse(
            "From: Shop <hello@shop.it>\r\nList-Unsubscribe: <https://shop.it/u>\r\n\r\nSale"
        ));
        assert!(parse("From: List <a@b.it>\r\nList-Id: <dev.b.it>\r\n\r\nx"));
        assert!(parse("From: a@b.it\r\nPrecedence: bulk\r\n\r\nx"));
        assert!(parse(
            "From: a@b.it\r\nAuto-Submitted: auto-replied\r\n\r\nx"
        ));
        assert!(!parse("From: a@b.it\r\nAuto-Submitted: no\r\n\r\nx"));
        assert!(parse("From: Bank <no-reply@bank.it>\r\n\r\nx"));
        assert!(parse("From: Courier <do_not_reply@courier.it>\r\n\r\nx"));
        assert!(!parse("From: Nora <nora@studio.it>\r\n\r\nx"));
    }

    #[test]
    fn quiet_hours_run_past_midnight() {
        let s = Settings::default();
        assert!(s.quiet_at(23 * 60));
        assert!(s.quiet_at(0));
        assert!(s.quiet_at(7 * 60 + 59));
        assert!(!s.quiet_at(8 * 60));
        assert!(!s.quiet_at(21 * 60 + 59));
        let day = Settings {
            quiet_from: 13 * 60,
            quiet_to: 14 * 60,
            ..s
        };
        assert!(day.quiet_at(13 * 60 + 30));
        assert!(!day.quiet_at(14 * 60));
        assert!(!Settings { quiet: false, ..s }.quiet_at(23 * 60));
    }

    #[test]
    fn weekends_are_quiet_all_day_when_chosen() {
        let saturday_noon = week_minute(5, 12 * 60);
        let sunday_late = week_minute(6, 21 * 60);
        let monday_noon = week_minute(0, 12 * 60);
        let s = Settings::default();
        assert!(!s.quiet_at(saturday_noon));
        let w = Settings {
            weekends: true,
            ..s
        };
        assert!(w.quiet_at(saturday_noon));
        assert!(w.quiet_at(sunday_late));
        assert!(!w.quiet_at(monday_noon));
        // Sunday night runs into Monday morning with the night's hours.
        assert!(w.quiet_at(week_minute(0, 7 * 60)));
        // Weekends alone, nights off.
        let only = Settings { quiet: false, ..w };
        assert!(only.quiet_at(saturday_noon));
        assert!(!only.quiet_at(week_minute(2, 23 * 60)));
    }

    #[test]
    fn week_minutes_from_unix_time() {
        // 2026-10-17 was a Saturday; 10:00 UTC is 12:00 in Rome (UTC+2).
        let secs = 1_792_231_200;
        assert_eq!(week_minute_at(secs, 120), week_minute(5, 12 * 60));
        assert_eq!(week_minute_at(secs, 0), week_minute(5, 10 * 60));
        // Behind UTC, still Friday night.
        assert_eq!(
            week_minute_at(secs - 10 * 3600, -120),
            week_minute(4, 22 * 60)
        );
    }

    #[test]
    fn quiet_rings_silent_or_holds() {
        let night = week_minute(2, 23 * 60);
        let day = week_minute(2, 12 * 60);
        let s = Settings::default();
        assert_eq!(s.quiet(day, true), Quiet::Ring);
        assert_eq!(s.quiet(night, true), Quiet::Silent);
        assert_eq!(s.quiet(night, false), Quiet::Ring);
        let hold = Settings { hold: true, ..s };
        assert_eq!(hold.quiet(night, true), Quiet::Hold);
    }

    #[test]
    fn held_notices_are_summed_up_once_quiet_ends() {
        let store = Store::open_in_memory().unwrap();
        let s = Settings {
            hold: true,
            ..Settings::default()
        };
        let night = week_minute(2, 23 * 60);
        let morning = week_minute(3, 8 * 60);
        let notice = |sender: &str, count: u32, people: bool| Notice {
            account: AccountId(1),
            mailbox: "INBOX".into(),
            uid: 1,
            sender: sender.into(),
            sender_email: String::new(),
            subject: String::new(),
            preview: String::new(),
            count,
            people,
        };
        assert_eq!(take_away(&store, &s, morning).unwrap(), None);
        for n in [
            notice("Dad", 1, true),
            notice("Shop", 8, false),
            notice("Luca Bianchi", 1, true),
            notice("Sara Conti", 1, true),
            notice("Dad", 1, true),
        ] {
            hold(&store, &n).unwrap();
        }
        assert_eq!(take_away(&store, &s, night).unwrap(), None, "still quiet");
        assert_eq!(
            take_away(&store, &s, morning).unwrap(),
            Some(Away {
                emails: 12,
                people: 4,
                names: vec!["Dad".into(), "Sara Conti".into(), "Luca Bianchi".into()],
            })
        );
        assert_eq!(take_away(&store, &s, morning).unwrap(), None, "given once");
    }

    #[test]
    fn accounts_can_ring_as_usual() {
        let store = Store::open_in_memory().unwrap();
        assert!(covers(&store, AccountId(2)).unwrap());
        set_covers(&store, AccountId(2), false).unwrap();
        assert!(!covers(&store, AccountId(2)).unwrap());
        assert!(covers(&store, AccountId(3)).unwrap());
        set_covers(&store, AccountId(2), true).unwrap();
        assert!(covers(&store, AccountId(2)).unwrap());
    }

    fn arrival(uid: u32, from: &str, at: i64, automated: bool) -> Arrival {
        Arrival {
            summary: MessageSummary {
                account: AccountId(1),
                mailbox: "INBOX".into(),
                uid,
                from_name: from.split('@').next().unwrap().into(),
                from_email: from.into(),
                to: String::new(),
                subject: format!("Message {uid}"),
                preview: String::new(),
                received_at: at,
                flags: Flags::default(),
                reply: ReplyInfo::default(),
                list: Default::default(),
            },
            automated,
        }
    }

    #[test]
    fn certified_mail_receipts_give_no_notice() {
        let now = 1_000_000;
        let mut receipt = arrival(1, "posta-certificata@pec.it", now - 60, false);
        receipt.summary.list.receipt = Some(crate::pec::Receipt {
            kind: crate::pec::Kind::Delivered,
            refers: "<a@pec.it>".into(),
            recipients: Vec::new(),
            reason: String::new(),
        });
        assert!(notices(&[receipt], &Settings::default(), now).is_empty());
    }

    #[test]
    fn one_notice_per_sender_newest_first() {
        let now = 1_000_000;
        let arrivals = [
            arrival(1, "sara@studio.it", now - 600, false),
            arrival(2, "giulia@posta.it", now - 60, false),
            arrival(3, "Sara@studio.it", now - 300, false),
            arrival(4, "news@shop.it", now - 30, true),
            arrival(5, "old@posta.it", now - RECENT_SECS - 1, false),
        ];
        let people = notices(&arrivals, &Settings::default(), now);
        assert_eq!(
            people.iter().map(|n| (n.uid, n.count)).collect::<Vec<_>>(),
            [(2, 1), (3, 2)]
        );
        let all = Settings {
            mode: Mode::All,
            ..Settings::default()
        };
        assert_eq!(notices(&arrivals, &all, now)[0].uid, 4);
        let off = Settings {
            mode: Mode::Off,
            ..Settings::default()
        };
        assert!(notices(&arrivals, &off, now).is_empty());

        let mut read = arrival(6, "luca@studio.it", now, false);
        read.summary.flags.seen = true;
        assert!(notices(&[read], &Settings::default(), now).is_empty());
    }

    #[test]
    fn settings_round_trip() {
        let store = Store::open_in_memory().unwrap();
        assert_eq!(Settings::load(&store).unwrap(), Settings::default());
        let s = Settings {
            mode: Mode::All,
            quiet: false,
            quiet_from: 23 * 60 + 30,
            quiet_to: 7 * 60,
            weekends: true,
            hold: true,
            parcels: false,
            due: true,
        };
        s.save(&store).unwrap();
        assert_eq!(Settings::load(&store).unwrap(), s);
    }

    #[test]
    fn vault_notices_wait_for_the_morning() {
        let s = Settings::default();
        assert!(!s.reminders_at(7 * 60 + 59));
        assert!(s.reminders_at(8 * 60));
        assert!(!s.reminders_at(22 * 60 + 5));
        let late = Settings {
            quiet_to: 9 * 60,
            ..s
        };
        assert!(!late.reminders_at(8 * 60 + 30));
        let weekends = Settings {
            weekends: true,
            ..s
        };
        assert!(weekends.reminders_at(week_minute(5, 10 * 60)));
    }
}
