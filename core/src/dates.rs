//! Days and times written in a message ("can we talk Friday at 10?"), so
//! the reader can offer to put them in a calendar.
//!
//! Plain rules in English and Italian, on this device: a day (a weekday,
//! "tomorrow", "October 24", "24/10") next to a time ("at 10", "15:30",
//! "alle 10", "3pm"). A day alone or a time alone is not enough: "see you
//! Thursday" asks for nothing.

use std::sync::LazyLock;

use regex::{Captures, Regex};

use crate::invite::{civil, days, fold, stamp};

/// A day with a time, found in some text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Found {
    /// Where the words are, in bytes of the text.
    pub start: usize,
    pub end: usize,
    /// The day, in days since 1970-01-01, as written (wall clock).
    pub day: i64,
    /// Minutes into the day.
    pub minute: u32,
}

const WEEKDAYS: &[(&str, i64)] = &[
    ("monday", 0),
    ("tuesday", 1),
    ("wednesday", 2),
    ("thursday", 3),
    ("friday", 4),
    ("saturday", 5),
    ("sunday", 6),
    ("lunedì", 0),
    ("martedì", 1),
    ("mercoledì", 2),
    ("giovedì", 3),
    ("venerdì", 4),
    ("lunedi", 0),
    ("martedi", 1),
    ("mercoledi", 2),
    ("giovedi", 3),
    ("venerdi", 4),
    ("sabato", 5),
    ("domenica", 6),
];

const MONTHS: &[(&str, u32)] = &[
    ("january", 1),
    ("february", 2),
    ("march", 3),
    ("april", 4),
    ("may", 5),
    ("june", 6),
    ("july", 7),
    ("august", 8),
    ("september", 9),
    ("october", 10),
    ("november", 11),
    ("december", 12),
    ("gennaio", 1),
    ("febbraio", 2),
    ("marzo", 3),
    ("aprile", 4),
    ("maggio", 5),
    ("giugno", 6),
    ("luglio", 7),
    ("agosto", 8),
    ("settembre", 9),
    ("ottobre", 10),
    ("novembre", 11),
    ("dicembre", 12),
    ("jan", 1),
    ("feb", 2),
    ("mar", 3),
    ("apr", 4),
    ("jun", 6),
    ("jul", 7),
    ("aug", 8),
    ("sep", 9),
    ("sept", 9),
    ("oct", 10),
    ("nov", 11),
    ("dec", 12),
    ("gen", 1),
    ("mag", 5),
    ("giu", 6),
    ("lug", 7),
    ("ago", 8),
    ("set", 9),
    ("ott", 10),
    ("dic", 12),
];

fn alternation(words: impl Iterator<Item = &'static str>) -> String {
    let mut words: Vec<&str> = words.collect();
    // Longest first, so "sept" wins over "sep".
    words.sort_by_key(|w| std::cmp::Reverse(w.len()));
    words.join("|")
}

static DAY: LazyLock<Regex> = LazyLock::new(|| {
    let weekdays = alternation(WEEKDAYS.iter().map(|(w, _)| *w));
    let months = alternation(MONTHS.iter().map(|(m, _)| *m));
    Regex::new(&format!(
        r"(?ix)\b(?:
            (?P<rel>day\ after\ tomorrow|dopodomani|tomorrow|domani|today|oggi|tonight|stasera)
          | (?:(?:next|this|questo|prossimo)\s+)?(?P<wd>{weekdays})(?:\s+(?:prossimo|next))?
            (?:,?\s+(?:the\s+)?(?P<wdd>\d{{1,2}})(?:st|nd|rd|th)?(?:\s+(?P<wdm>{months})\.?)?\b)?
          | (?P<dd>\d{{1,2}})(?:st|nd|rd|th)?\s+(?:of\s+)?(?P<dm>{months})\.?(?:\s+(?P<dy>\d{{4}}))?
          | (?P<mm>{months})\.?\s+(?P<md>\d{{1,2}})(?:st|nd|rd|th)?(?:,?\s+(?P<my>\d{{4}}))?
          | (?P<nd>\d{{1,2}})/(?P<nm>\d{{1,2}})(?:/(?P<ny>\d{{4}}|\d{{2}}))?
        )\b"
    ))
    .expect("day pattern")
});

static TIME: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"(?ix)\b(?:
            (?:at|around|from|alle|all'|ore|dalle|verso\ le|h)\s*(?P<h1>\d{1,2})(?:[:.](?P<m1>\d{2}))?(?:\s*(?P<a1>[ap])\.?m\b\.?)?
          | (?P<h2>\d{1,2}):(?P<m2>\d{2})(?:\s*(?P<a2>[ap])\.?m\b\.?)?
          | (?P<h3>\d{1,2})\s*(?P<a3>[ap])\.?m\b\.?
          | (?P<noon>noon|midday|mezzogiorno)
        )",
    )
    .expect("time pattern")
});

fn lookup<T: Copy>(table: &[(&str, T)], word: &str) -> Option<T> {
    let w = word.to_lowercase();
    table.iter().find(|(name, _)| *name == w).map(|(_, v)| *v)
}

fn num<T: std::str::FromStr>(c: &Captures, name: &str) -> Option<T> {
    c.name(name)?.as_str().parse().ok()
}

/// A day of the month without a year: the first one from `reference` on.
fn next_date(month: u32, day: u32, year: Option<i32>, reference: i64) -> Option<i64> {
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    let valid = |y: i32| {
        let n = days(y, month, day);
        (civil(n) == (y, month, day)).then_some(n)
    };
    if let Some(y) = year {
        return valid(if y < 100 { 2000 + y } else { y });
    }
    let (y, _, _) = civil(reference);
    match valid(y) {
        Some(n) if n >= reference => Some(n),
        _ => valid(y + 1),
    }
}

/// The day the words name, and whether they mean the evening.
fn day_of(c: &Captures, reference: i64, weekday_only: bool) -> Option<(i64, bool)> {
    if let Some(rel) = c.name("rel") {
        let r = rel.as_str().to_lowercase();
        return Some(match r.as_str() {
            "today" | "oggi" => (reference, false),
            "tonight" | "stasera" => (reference, true),
            "tomorrow" | "domani" => (reference + 1, false),
            _ => (reference + 2, false),
        });
    }
    if let Some(wd) = c.name("wd") {
        if let Some(d) = num::<u32>(c, "wdd").filter(|_| !weekday_only) {
            let (y, m, _) = civil(reference);
            let month = c.name("wdm").and_then(|m| lookup(MONTHS, m.as_str()));
            let day = match month {
                Some(month) => next_date(month, d, None, reference)?,
                None => {
                    // "Friday 24": this month's 24th, or next month's.
                    let this = days(y, m, d);
                    if civil(this) == (y, m, d) && this >= reference {
                        this
                    } else {
                        let (ny, nm) = if m == 12 { (y + 1, 1) } else { (y, m + 1) };
                        next_date(nm, d, Some(ny), reference)?
                    }
                }
            };
            return Some((day, false));
        }
        let target = lookup(WEEKDAYS, wd.as_str())?;
        // 1970-01-01 was a Thursday.
        let today = (reference + 3).rem_euclid(7);
        let ahead = (target - today).rem_euclid(7);
        return Some((reference + if ahead == 0 { 7 } else { ahead }, false));
    }
    if let Some(m) = c.name("dm") {
        let day = next_date(
            lookup(MONTHS, m.as_str())?,
            num(c, "dd")?,
            num(c, "dy"),
            reference,
        )?;
        return Some((day, false));
    }
    if let Some(m) = c.name("mm") {
        let day = next_date(
            lookup(MONTHS, m.as_str())?,
            num(c, "md")?,
            num(c, "my"),
            reference,
        )?;
        return Some((day, false));
    }
    // Day first, as in Europe, unless that can't be.
    let (a, b): (u32, u32) = (num(c, "nd")?, num(c, "nm")?);
    let (day, month) = if b > 12 { (b, a) } else { (a, b) };
    Some((next_date(month, day, num(c, "ny"), reference)?, false))
}

/// Minutes into the day the words name. A bare hour from 1 to 7 is the
/// afternoon ("at 3"), as it is in the evening ("stasera alle 8").
fn minute_of(c: &Captures, evening: bool) -> Option<u32> {
    if c.name("noon").is_some() {
        return Some(12 * 60);
    }
    let (h, m, ap) = if let Some(h) = num::<u32>(c, "h1") {
        (h, num(c, "m1").unwrap_or(0), c.name("a1"))
    } else if let Some(h) = num::<u32>(c, "h2") {
        (h, num(c, "m2")?, c.name("a2"))
    } else {
        (num(c, "h3")?, 0, c.name("a3"))
    };
    if h > 23 || m > 59 {
        return None;
    }
    let h = match ap.map(|a| a.as_str().to_ascii_lowercase()) {
        Some(a) if h == 0 || h > 12 => return (a == "a" && h == 0).then_some(m),
        Some(a) if a == "p" => h % 12 + 12,
        Some(_) => h % 12,
        None if (1..=7).contains(&h) || (evening && h < 12) => h + 12,
        None => h,
    };
    Some(h * 60 + m)
}

/// What lies between a day and a time may only join them: spaces, commas
/// and a short word or two, never the end of a sentence.
fn joins(between: &str) -> bool {
    between.len() <= 16
        && !between.contains(['.', '?', '!', ';', '\n', ':'])
        && between.split_whitespace().count() <= 2
}

/// The days with a time in `text`, at most one per day and time. Days
/// without a year are read from `reference` on (the day it was written).
pub fn find(text: &str, reference: i64) -> Vec<Found> {
    let times: Vec<_> = TIME
        .captures_iter(text)
        .filter_map(|c| {
            let m = c.get(0)?;
            Some((m.start(), m.end(), c))
        })
        .collect();
    let mut found: Vec<Found> = Vec::new();
    let mut used_until = 0;
    for c in DAY.captures_iter(text) {
        let Some(whole) = c.get(0) else { continue };
        // "Friday 10:00" is a weekday and a time, not Friday the 10th.
        let clock = c.name("wdd").is_some_and(|d| {
            let rest = &text.as_bytes()[d.end()..];
            rest.len() > 1 && (rest[0] == b':' || rest[0] == b'.') && rest[1].is_ascii_digit()
        });
        let (m_start, m_end) = match (clock, c.name("wd")) {
            (true, Some(wd)) => (whole.start(), wd.end()),
            _ => (whole.start(), whole.end()),
        };
        let Some((day, evening)) = day_of(&c, reference, clock) else {
            continue;
        };
        // The nearest time just after the day, else just before it.
        let after = times
            .iter()
            .filter(|(s, _, _)| *s >= m_end && joins(&text[m_end..*s]))
            .min_by_key(|(s, _, _)| *s);
        let before = times
            .iter()
            .filter(|(s, e, _)| *s >= used_until && *e <= m_start && joins(&text[*e..m_start]))
            .max_by_key(|(_, e, _)| *e);
        let Some((start, end, minute)) = after.or(before).and_then(|(s, e, t)| {
            Some(((*s).min(m_start), (*e).max(m_end), minute_of(t, evening)?))
        }) else {
            continue;
        };
        if found.iter().any(|f| f.day == day && f.minute == minute) {
            continue;
        }
        used_until = end;
        found.push(Found {
            start,
            end,
            day,
            minute,
        });
    }
    found
}

/// The text of an event to put in a calendar, in UTC.
pub fn event(uid: &str, summary: &str, start: i64, end: i64, now: i64) -> String {
    let summary: String = summary
        .chars()
        .flat_map(|c| match c {
            '\\' => vec!['\\', '\\'],
            ';' => vec!['\\', ';'],
            ',' => vec!['\\', ','],
            '\n' => vec!['\\', 'n'],
            '\r' => vec![],
            c => vec![c],
        })
        .collect();
    let mut ics = String::from(
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Piuma Mail//EN\r\nBEGIN:VEVENT\r\n",
    );
    for line in [
        format!("UID:{uid}"),
        format!("DTSTAMP:{}", stamp(now)),
        format!("DTSTART:{}", stamp(start)),
        format!("DTEND:{}", stamp(end)),
        format!("SUMMARY:{summary}"),
    ] {
        ics.push_str(&fold(&line));
    }
    ics.push_str("END:VEVENT\r\nEND:VCALENDAR\r\n");
    ics
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Wednesday, October 14, 2026.
    fn wednesday() -> i64 {
        days(2026, 10, 14)
    }

    fn one(text: &str) -> (String, (i32, u32, u32), String) {
        let f = find(text, wednesday());
        assert_eq!(f.len(), 1, "{text}: {f:?}");
        let f = f[0];
        (
            text[f.start..f.end].to_owned(),
            civil(f.day),
            format!("{:02}:{:02}", f.minute / 60, f.minute % 60),
        )
    }

    #[test]
    fn a_weekday_with_a_time() {
        assert_eq!(
            one("For the materials, can we talk Friday at 10? Then we close it."),
            ("Friday at 10".into(), (2026, 10, 16), "10:00".into())
        );
        assert_eq!(
            one("Ci sentiamo venerdì alle 15:30 per chiudere."),
            ("venerdì alle 15:30".into(), (2026, 10, 16), "15:30".into())
        );
        // The same weekday is next week's.
        assert_eq!(one("Wednesday 9am works").1, (2026, 10, 21));
        assert_eq!(one("at 3 on Monday?").2, "15:00");
        assert_eq!(one("at 3 on Monday?").0, "at 3 on Monday");
    }

    #[test]
    fn named_days_and_dates() {
        assert_eq!(one("tomorrow at noon").1, (2026, 10, 15));
        assert_eq!(one("stasera alle 8 da me").2, "20:00");
        assert_eq!(
            one("Delivery on October 28 at 9:15."),
            ("October 28 at 9:15".into(), (2026, 10, 28), "09:15".into())
        );
        assert_eq!(one("il 24 ottobre alle 18").1, (2026, 10, 24));
        // A date that has passed this year is next year's.
        assert_eq!(one("Jan 12, 4pm").1, (2027, 1, 12));
        assert_eq!(one("il 3/11 alle 10").1, (2026, 11, 3));
        assert_eq!(one("Friday 24 at 10").1, (2026, 10, 24));
        assert_eq!(
            one("Friday 10:00 works"),
            ("Friday 10:00".into(), (2026, 10, 16), "10:00".into())
        );
    }

    #[test]
    fn a_day_or_a_time_alone_is_not_enough() {
        for text in [
            "See you Thursday,",
            "It costs 10.30 euros.",
            "Call me at 10.",
            "On Friday. At 10 I have another call.",
            "We met in May 2024 at the fair.",
            "Version 2.0 is out on 10/40.",
        ] {
            assert!(find(text, wednesday()).is_empty(), "{text}");
        }
    }

    #[test]
    fn each_day_and_time_once() {
        let f = find(
            "Friday at 10 is fine. So, Friday at 10 then, and Monday at 9:30.",
            wednesday(),
        );
        assert_eq!(f.len(), 2);
        assert_eq!(f[1].minute, 9 * 60 + 30);
    }

    #[test]
    fn an_event_for_the_calendar() {
        let ics = event(
            "found-1",
            "Re: boards, Casa Neri",
            1_792_000_000,
            1_792_003_600,
            0,
        );
        assert!(ics.contains("SUMMARY:Re: boards\\, Casa Neri\r\n"));
        assert!(ics.contains("DTSTART:20261014T174640Z\r\n"));
        assert!(crate::invite::parse(&ics).is_some());
    }
}
