//! Calendar invites: the `text/calendar` part an invite carries (iCalendar,
//! RFC 5545, sent as iTIP, RFC 5546), read into what the invite card
//! shows, and the REPLY that answers it by email. There is no calendar
//! here: the answer goes to the organizer, whose calendar keeps it.

/// What the sender's calendar asks for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Method {
    /// An invite, or a change to one: it can be answered.
    Request,
    /// The event is off.
    Cancel,
    /// Someone answered an invite you sent.
    Reply,
    /// An event to look at, with nothing to answer.
    Publish,
}

/// An answer to an invite.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Answer {
    Accepted,
    Tentative,
    Declined,
}

impl Answer {
    /// The iCalendar PARTSTAT value.
    pub fn partstat(self) -> &'static str {
        match self {
            Answer::Accepted => "ACCEPTED",
            Answer::Tentative => "TENTATIVE",
            Answer::Declined => "DECLINED",
        }
    }

    pub fn from_partstat(value: &str) -> Option<Self> {
        match value.to_ascii_uppercase().as_str() {
            "ACCEPTED" => Some(Answer::Accepted),
            "TENTATIVE" => Some(Answer::Tentative),
            "DECLINED" => Some(Answer::Declined),
            _ => None,
        }
    }
}

/// Someone on the invite.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Person {
    pub name: String,
    pub email: String,
    /// What they answered, when the invite says.
    pub answer: Option<Answer>,
}

/// An event, as the invite describes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Invite {
    pub method: Method,
    pub uid: String,
    pub sequence: u32,
    pub summary: String,
    pub location: String,
    /// Unix seconds. With `floating` they are the wall-clock time where
    /// the person is, written as if it were UTC.
    pub start: i64,
    pub end: i64,
    pub all_day: bool,
    /// No time zone the invite names could be read: the times are local.
    pub floating: bool,
    /// It happens more than once (the card shows the first time).
    pub repeats: bool,
    pub organizer: Option<Person>,
    pub attendees: Vec<Person>,
    /// TRANSP:TRANSPARENT: it is in the calendar but doesn't make the
    /// person busy.
    pub transparent: bool,
}

impl Invite {
    /// The attendee with this address, if any.
    pub fn attendee(&self, email: &str) -> Option<&Person> {
        self.attendees
            .iter()
            .find(|a| a.email.eq_ignore_ascii_case(email.trim()))
    }
}

/// One content line, unfolded: `NAME;PARAM=value:VALUE`.
#[derive(Debug, Clone)]
struct Line {
    name: String,
    params: Vec<(String, String)>,
    value: String,
    /// The line as written, unfolded, to copy into a reply.
    raw: String,
}

impl Line {
    fn param(&self, name: &str) -> Option<&str> {
        self.params
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

fn lines(ics: &str) -> Vec<Line> {
    let mut unfolded: Vec<String> = Vec::new();
    for l in ics.split('\n') {
        let l = l.strip_suffix('\r').unwrap_or(l);
        match (l.strip_prefix([' ', '\t']), unfolded.last_mut()) {
            (Some(more), Some(last)) => last.push_str(more),
            _ if l.trim().is_empty() => {}
            _ => unfolded.push(l.to_owned()),
        }
    }
    unfolded
        .into_iter()
        .filter_map(|raw| parse_line(&raw))
        .collect()
}

fn parse_line(raw: &str) -> Option<Line> {
    // Split on the first ':' and the ';' that are not inside quotes.
    let mut quoted = false;
    let mut cuts = Vec::new();
    let mut colon = None;
    for (i, c) in raw.char_indices() {
        match c {
            '"' => quoted = !quoted,
            ';' if !quoted => cuts.push(i),
            ':' if !quoted => {
                colon = Some(i);
                break;
            }
            _ => {}
        }
    }
    let colon = colon?;
    let head = &raw[..colon];
    let mut parts = Vec::new();
    let mut start = 0;
    for &cut in &cuts {
        parts.push(&head[start..cut]);
        start = cut + 1;
    }
    parts.push(&head[start..]);
    let name = parts.first()?.trim().to_ascii_uppercase();
    let params = parts[1..]
        .iter()
        .filter_map(|p| {
            let (k, v) = p.split_once('=')?;
            Some((
                k.trim().to_ascii_uppercase(),
                v.trim().trim_matches('"').to_owned(),
            ))
        })
        .collect();
    Some(Line {
        name,
        params,
        value: raw[colon + 1..].to_owned(),
        raw: raw.to_owned(),
    })
}

/// A TEXT value with its escapes undone.
fn text(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next() {
            Some('n' | 'N') => out.push('\n'),
            Some(other) => out.push(other),
            None => {}
        }
    }
    out.trim().to_owned()
}

fn address(value: &str) -> String {
    let v = value.trim();
    let v = v
        .get(..7)
        .filter(|p| p.eq_ignore_ascii_case("mailto:"))
        .map_or(v, |_| &v[7..]);
    v.trim().to_owned()
}

fn person(l: &Line) -> Person {
    Person {
        name: l.param("CN").map(text).unwrap_or_default(),
        email: address(&l.value),
        answer: l.param("PARTSTAT").and_then(Answer::from_partstat),
    }
}

/// One way a zone keeps time, from when to when: its STANDARD or DAYLIGHT.
#[derive(Debug, Clone)]
struct Observance {
    /// Local wall-clock start of the first onset, as if UTC.
    start: i64,
    offset: i64,
    /// Yearly onsets: (month, week of the month or -1 for the last, weekday 0 = Sunday).
    rule: Option<(u32, i32, u32)>,
}

#[derive(Debug, Clone, Default)]
struct Zone {
    id: String,
    observances: Vec<Observance>,
}

impl Zone {
    /// The offset in effect at a local wall-clock time.
    fn offset_at(&self, local: i64) -> Option<i64> {
        let year = civil(local.div_euclid(86_400)).0;
        let mut best: Option<(i64, i64)> = None;
        for o in &self.observances {
            let onsets: Vec<i64> = match o.rule {
                None => vec![o.start],
                Some(rule) => [year - 1, year]
                    .into_iter()
                    .filter_map(|y| onset(y, rule, o.start.rem_euclid(86_400)))
                    .filter(|&at| at >= o.start)
                    .collect(),
            };
            for at in onsets {
                if at <= local && best.is_none_or(|(b, _)| at > b) {
                    best = Some((at, o.offset));
                }
            }
        }
        best.map(|(_, off)| off).or_else(|| {
            // Before every onset: the earliest one says what was there.
            self.observances
                .iter()
                .min_by_key(|o| o.start)
                .map(|o| o.offset)
        })
    }
}

/// Days since 1970-01-01 of a date.
pub(crate) fn days(year: i32, month: u32, day: u32) -> i64 {
    let (y, m) = if month <= 2 {
        (year as i64 - 1, month as i64 + 9)
    } else {
        (year as i64, month as i64 - 3)
    };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * m + 2) / 5 + day as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The (year, month, day) of a day number.
pub(crate) fn civil(n: i64) -> (i32, u32, u32) {
    let z = n + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = (yoe + era * 400 + i64::from(month <= 2)) as i32;
    (year, month, day)
}

fn days_in(year: i32, month: u32) -> u32 {
    let next = if month == 12 {
        days(year + 1, 1, 1)
    } else {
        days(year, month + 1, 1)
    };
    (next - days(year, month, 1)) as u32
}

/// The onset in `year` of a yearly rule, at `time` seconds into the day.
fn onset(year: i32, (month, week, weekday): (u32, i32, u32), time: i64) -> Option<i64> {
    if !(1..=12).contains(&month) {
        return None;
    }
    // 1970-01-01 was a Thursday (4).
    let weekday_of = |d: i64| (d + 4).rem_euclid(7) as u32;
    let day = if week > 0 {
        let first = days(year, month, 1);
        let shift = (weekday + 7 - weekday_of(first)) % 7;
        first + shift as i64 + 7 * (week as i64 - 1)
    } else {
        let last = days(year, month, days_in(year, month));
        let shift = (weekday_of(last) + 7 - weekday) % 7;
        last - shift as i64 + 7 * (week as i64 + 1)
    };
    Some(day * 86_400 + time)
}

/// "-1SU", "2SU", "SU" in a BYDAY rule.
fn by_day(value: &str) -> Option<(i32, u32)> {
    let value = value.trim();
    let split = value.len().checked_sub(2)?;
    let (week, day) = value.split_at(split);
    let weekday = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        .iter()
        .position(|d| d.eq_ignore_ascii_case(day))? as u32;
    let week = match week.trim_start_matches('+') {
        "" => 1,
        w => w.parse().ok()?,
    };
    Some((week, weekday))
}

fn rule(value: &str) -> Option<(u32, i32, u32)> {
    let mut month = None;
    let mut day = None;
    let mut yearly = false;
    for part in value.split(';') {
        let (k, v) = part.split_once('=')?;
        match k.to_ascii_uppercase().as_str() {
            "FREQ" => yearly = v.eq_ignore_ascii_case("YEARLY"),
            "BYMONTH" => month = v.parse().ok(),
            "BYDAY" => day = by_day(v),
            _ => {}
        }
    }
    let (week, weekday) = day?;
    yearly.then_some((month?, week, weekday))
}

/// "+0200", "-0530".
fn utc_offset(value: &str) -> Option<i64> {
    let v = value.trim();
    let sign = match v.as_bytes().first()? {
        b'+' => 1,
        b'-' => -1,
        _ => return None,
    };
    let digits = &v[1..];
    if digits.len() < 4 || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let h: i64 = digits[..2].parse().ok()?;
    let m: i64 = digits[2..4].parse().ok()?;
    let s: i64 = digits.get(4..6).and_then(|s| s.parse().ok()).unwrap_or(0);
    Some(sign * (h * 3600 + m * 60 + s))
}

/// A DATE or DATE-TIME as written: (wall-clock seconds as if UTC, is a
/// date, is UTC).
fn date_time(value: &str) -> Option<(i64, bool, bool)> {
    let v = value.trim();
    let num = |s: &str| -> Option<u32> {
        s.bytes()
            .all(|b| b.is_ascii_digit())
            .then(|| s.parse().ok())?
    };
    let year = num(v.get(0..4)?)? as i32;
    let month = num(v.get(4..6)?)?;
    let day = num(v.get(6..8)?)?;
    if !(1..=12).contains(&month) || day == 0 || day > days_in(year, month) {
        return None;
    }
    let date = days(year, month, day) * 86_400;
    if v.len() == 8 {
        return Some((date, true, false));
    }
    if v.as_bytes().get(8) != Some(&b'T') {
        return None;
    }
    let h = num(v.get(9..11)?)? as i64;
    let m = num(v.get(11..13)?)? as i64;
    let s = num(v.get(13..15)?)? as i64;
    let utc = v.get(15..).is_some_and(|z| z.eq_ignore_ascii_case("Z"));
    Some((date + h * 3600 + m * 60 + s, false, utc))
}

/// "PT1H30M", "P1D", "P1W".
fn duration(value: &str) -> Option<i64> {
    let v = value.trim();
    let (sign, v) = match v.strip_prefix('-') {
        Some(rest) => (-1, rest),
        None => (1, v.trim_start_matches('+')),
    };
    let v = v.strip_prefix(['P', 'p'])?;
    let mut total = 0;
    let mut n = String::new();
    for c in v.chars() {
        match c.to_ascii_uppercase() {
            'T' => {}
            d if d.is_ascii_digit() => n.push(d),
            unit => {
                let k: i64 = n.parse().ok()?;
                n.clear();
                total += k * match unit {
                    'W' => 7 * 86_400,
                    'D' => 86_400,
                    'H' => 3600,
                    'M' => 60,
                    'S' => 1,
                    _ => return None,
                };
            }
        }
    }
    Some(sign * total)
}

/// Reads the first event of an iCalendar text. None when there is none.
pub fn parse(ics: &str) -> Option<Invite> {
    let all = lines(ics);
    let zones = zones(&all);
    event_lines(&all)
        .first()
        .and_then(|e| event(&all, &zones, e))
}

/// Every event in a calendar, as a CalDAV server or an .ics feed gives
/// them; those that can't be read are left out.
pub fn events(ics: &str) -> Vec<Invite> {
    let all = lines(ics);
    let zones = zones(&all);
    event_lines(&all)
        .iter()
        .filter_map(|e| event(&all, &zones, e))
        .collect()
}

/// How often an .ics feed asks to be read again, in seconds: its
/// REFRESH-INTERVAL (RFC 7986), or the older X-PUBLISHED-TTL.
pub fn refresh_interval(ics: &str) -> Option<i64> {
    let head: Vec<Line> = lines(ics)
        .into_iter()
        .take_while(|l| !(l.name == "BEGIN" && l.value.trim().eq_ignore_ascii_case("VEVENT")))
        .collect();
    ["REFRESH-INTERVAL", "X-PUBLISHED-TTL"]
        .iter()
        .find_map(|name| head.iter().find(|l| l.name == *name))
        .and_then(|l| duration(&l.value))
        .filter(|s| *s > 0)
}

/// The calendar's name an .ics feed gives itself (X-WR-CALNAME).
pub fn calendar_name(ics: &str) -> Option<String> {
    lines(ics)
        .into_iter()
        .take_while(|l| !(l.name == "BEGIN" && l.value.trim().eq_ignore_ascii_case("VEVENT")))
        .find(|l| l.name == "X-WR-CALNAME")
        .map(|l| text(&l.value))
        .filter(|n| !n.trim().is_empty())
}

fn event(all: &[Line], zones: &[Zone], event: &[Line]) -> Option<Invite> {
    let method = all
        .iter()
        .find(|l| l.name == "METHOD")
        .map(|l| l.value.trim().to_ascii_uppercase());
    let get = |name: &str| event.iter().find(|l| l.name == name);
    let uid = get("UID").map(|l| l.value.trim().to_owned())?;
    let cancelled = get("STATUS").is_some_and(|l| l.value.trim().eq_ignore_ascii_case("CANCELLED"));
    let method = match method.as_deref() {
        Some("CANCEL") => Method::Cancel,
        _ if cancelled => Method::Cancel,
        Some("REPLY") => Method::Reply,
        Some("REQUEST") => Method::Request,
        _ => Method::Publish,
    };
    let when = |l: &Line| -> Option<(i64, bool, bool)> {
        let (local, date, utc) = date_time(&l.value)?;
        if date || utc {
            return Some((local, date, !utc && !date));
        }
        let zone = l
            .param("TZID")
            .and_then(|id| zones.iter().find(|z| z.id == id));
        match zone.and_then(|z| z.offset_at(local)) {
            Some(offset) => Some((local - offset, false, false)),
            None => Some((local, false, true)),
        }
    };
    let (start, all_day, start_floating) = get("DTSTART").and_then(when)?;
    let all_day = all_day || get("DTSTART").and_then(|l| l.param("VALUE")) == Some("DATE");
    let end = match get("DTEND").and_then(when) {
        Some((end, _, _)) => end,
        None => match get("DURATION").and_then(|l| duration(&l.value)) {
            Some(d) => start + d,
            None if all_day => start + 86_400,
            None => start,
        },
    };
    Some(Invite {
        method,
        uid,
        sequence: get("SEQUENCE")
            .and_then(|l| l.value.trim().parse().ok())
            .unwrap_or(0),
        summary: get("SUMMARY").map(|l| text(&l.value)).unwrap_or_default(),
        location: get("LOCATION").map(|l| text(&l.value)).unwrap_or_default(),
        start,
        end: end.max(start),
        all_day,
        floating: start_floating || all_day,
        repeats: get("RRULE").is_some() || get("RDATE").is_some(),
        organizer: get("ORGANIZER").map(person),
        attendees: event
            .iter()
            .filter(|l| l.name == "ATTENDEE")
            .map(person)
            .collect(),
        transparent: get("TRANSP")
            .is_some_and(|l| l.value.trim().eq_ignore_ascii_case("TRANSPARENT")),
    })
}

/// The lines inside each VEVENT, without nested components.
fn event_lines(all: &[Line]) -> Vec<Vec<Line>> {
    let mut events = Vec::new();
    let mut current: Option<Vec<Line>> = None;
    let mut depth = 0;
    for l in all {
        let begin = l.name == "BEGIN";
        let end = l.name == "END";
        let vevent = l.value.trim().eq_ignore_ascii_case("VEVENT");
        match &mut current {
            None if begin && vevent => {
                current = Some(Vec::new());
                depth = 0;
            }
            None => {}
            Some(_) if end && depth == 0 => events.extend(current.take()),
            Some(_) if begin => depth += 1,
            Some(_) if end => depth -= 1,
            Some(out) if depth == 0 => out.push(l.clone()),
            Some(_) => {}
        }
    }
    events.extend(current);
    events
}

/// A STANDARD or DAYLIGHT block being read: its onset, its offset, and the
/// yearly rule (month, weekday position, weekday) that moves it.
type ZonePart = (Option<i64>, Option<i64>, Option<(u32, i32, u32)>);

fn zones(all: &[Line]) -> Vec<Zone> {
    let mut zones = Vec::new();
    let mut zone: Option<Zone> = None;
    let mut part: Option<ZonePart> = None;
    for l in all {
        let value = l.value.trim();
        match (l.name.as_str(), value.to_ascii_uppercase().as_str()) {
            ("BEGIN", "VTIMEZONE") => zone = Some(Zone::default()),
            ("END", "VTIMEZONE") => zones.extend(zone.take()),
            ("BEGIN", "STANDARD" | "DAYLIGHT") if zone.is_some() => part = Some((None, None, None)),
            ("END", "STANDARD" | "DAYLIGHT") => {
                if let (Some(z), Some((Some(start), Some(offset), rule))) = (&mut zone, part.take())
                {
                    z.observances.push(Observance {
                        start,
                        offset,
                        rule,
                    });
                }
            }
            ("TZID", _) if part.is_none() => {
                if let Some(z) = &mut zone {
                    z.id = value.to_owned();
                }
            }
            ("DTSTART", _) => {
                if let Some(p) = &mut part {
                    p.0 = date_time(value).map(|(at, _, _)| at);
                }
            }
            ("TZOFFSETTO", _) => {
                if let Some(p) = &mut part {
                    p.1 = utc_offset(value);
                }
            }
            ("RRULE", _) => {
                if let Some(p) = &mut part {
                    p.2 = rule(value);
                }
            }
            _ => {}
        }
    }
    zones
}

/// Octets a folded line may hold: RFC 5545 allows 75, and two fewer keep
/// every line, with its CRLF, short enough to travel as plain 7bit or 8bit.
const FOLD: usize = 73;

/// Folds a content line at [`FOLD`] octets, never inside a character.
pub(crate) fn fold(line: &str) -> String {
    let mut out = String::with_capacity(line.len() + line.len() / 70 * 3);
    let mut used = 0;
    for c in line.chars() {
        let n = c.len_utf8();
        if used + n > FOLD {
            out.push_str("\r\n ");
            used = 1;
        }
        out.push(c);
        used += n;
    }
    out.push_str("\r\n");
    out
}

/// Unix seconds as an iCalendar UTC time.
pub(crate) fn stamp(unix: i64) -> String {
    let (y, m, d) = civil(unix.div_euclid(86_400));
    let s = unix.rem_euclid(86_400);
    format!(
        "{y:04}{m:02}{d:02}T{:02}{:02}{:02}Z",
        s / 3600,
        s / 60 % 60,
        s % 60
    )
}

/// The REPLY that answers an invite as `me`, to send to its organizer.
/// None when the text holds no event to answer.
pub fn reply(ics: &str, me_name: &str, me_email: &str, answer: Answer, now: i64) -> Option<String> {
    let all = lines(ics);
    let event = event_lines(&all).into_iter().next()?;
    let invite = parse(ics)?;
    invite.organizer.as_ref()?;
    let copied = [
        "UID",
        "SEQUENCE",
        "RECURRENCE-ID",
        "DTSTART",
        "DTEND",
        "DURATION",
        "SUMMARY",
        "ORGANIZER",
    ];
    // The address the invite was sent to, which may be an alias.
    let email = invite
        .attendee(me_email)
        .map(|a| a.email.clone())
        .unwrap_or_else(|| me_email.trim().to_owned());
    let mut out = String::new();
    for l in [
        "BEGIN:VCALENDAR",
        "PRODID:-//Piuma Mail//EN",
        "VERSION:2.0",
        "METHOD:REPLY",
    ] {
        out.push_str(&fold(l));
    }
    // The zones the copied times name.
    let mut inside = false;
    for l in &all {
        let begin = l.name == "BEGIN" && l.value.trim().eq_ignore_ascii_case("VTIMEZONE");
        if begin {
            inside = true;
        }
        if inside {
            out.push_str(&fold(&l.raw));
        }
        if l.name == "END" && l.value.trim().eq_ignore_ascii_case("VTIMEZONE") {
            inside = false;
        }
    }
    out.push_str(&fold("BEGIN:VEVENT"));
    for name in copied {
        if let Some(l) = event.iter().find(|l| l.name == name) {
            out.push_str(&fold(&l.raw));
        }
    }
    out.push_str(&fold(&format!("DTSTAMP:{}", stamp(now))));
    let name = me_name.trim();
    let cn = if name.is_empty() {
        String::new()
    } else {
        format!(";CN=\"{}\"", name.replace('"', "'"))
    };
    out.push_str(&fold(&format!(
        "ATTENDEE;PARTSTAT={}{cn}:mailto:{email}",
        answer.partstat()
    )));
    out.push_str(&fold("END:VEVENT"));
    out.push_str(&fold("END:VCALENDAR"));
    Some(out)
}

/// The invite as an event to keep in your own calendar: without its
/// METHOD, with your answer on your attendee line.
pub fn for_calendar(ics: &str, me_email: &str, answer: Answer) -> Option<String> {
    let invite = parse(ics)?;
    let email = invite
        .attendee(me_email)
        .map(|a| a.email.clone())
        .unwrap_or_else(|| me_email.trim().to_owned());
    let mut out = String::new();
    for l in lines(ics) {
        if l.name == "METHOD" {
            continue;
        }
        if l.name == "ATTENDEE" && address(&l.value).eq_ignore_ascii_case(&email) {
            let mut line = String::from("ATTENDEE");
            for (k, v) in &l.params {
                if k.eq_ignore_ascii_case("PARTSTAT") || k.eq_ignore_ascii_case("RSVP") {
                    continue;
                }
                if v.contains([':', ';', ',']) {
                    line.push_str(&format!(";{k}=\"{}\"", v.replace('"', "'")));
                } else {
                    line.push_str(&format!(";{k}={v}"));
                }
            }
            line.push_str(&format!(
                ";PARTSTAT={}:{}",
                answer.partstat(),
                l.value.trim()
            ));
            out.push_str(&fold(&line));
        } else {
            out.push_str(&fold(&l.raw));
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const GOOGLE: &str = "BEGIN:VCALENDAR\r\n\
PRODID:-//Google Inc//Google Calendar 70.9054//EN\r\n\
VERSION:2.0\r\n\
METHOD:REQUEST\r\n\
BEGIN:VTIMEZONE\r\n\
TZID:Europe/Rome\r\n\
BEGIN:DAYLIGHT\r\n\
TZOFFSETFROM:+0100\r\n\
TZOFFSETTO:+0200\r\n\
DTSTART:19700329T020000\r\n\
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU\r\n\
END:DAYLIGHT\r\n\
BEGIN:STANDARD\r\n\
TZOFFSETFROM:+0200\r\n\
TZOFFSETTO:+0100\r\n\
DTSTART:19701025T030000\r\n\
RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU\r\n\
END:STANDARD\r\n\
END:VTIMEZONE\r\n\
BEGIN:VEVENT\r\n\
DTSTART;TZID=Europe/Rome:20261023T150000\r\n\
DTEND;TZID=Europe/Rome:20261023T160000\r\n\
DTSTAMP:20261020T081200Z\r\n\
ORGANIZER;CN=Giulia Ferri:mailto:giulia@studioferri.it\r\n\
UID:casa-neri-42@google.com\r\n\
ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;CN=\"Neri, Matteo\";X-NUM-GUESTS=0:mailto:matteo@studio.it\r\n\
ATTENDEE;PARTSTAT=ACCEPTED;CN=Luca Conti:mailto:luca@studio.it\r\n\
SEQUENCE:2\r\n\
SUMMARY:Casa Neri project review\r\n\
LOCATION:Studio Ferri\\, via Solferino 12\r\n\
DESCRIPTION:Let's go over the boards together before sending them to the cl\r\n\
 ient.\r\n\
BEGIN:VALARM\r\n\
ACTION:DISPLAY\r\n\
TRIGGER:-P0DT0H30M0S\r\n\
END:VALARM\r\n\
END:VEVENT\r\n\
END:VCALENDAR\r\n";

    fn at(y: i32, mo: u32, d: u32, h: i64, mi: i64) -> i64 {
        days(y, mo, d) * 86_400 + h * 3600 + mi * 60
    }

    #[test]
    fn an_invite_is_read_in_its_own_time_zone() {
        let i = parse(GOOGLE).unwrap();
        assert_eq!(i.method, Method::Request);
        assert_eq!(i.uid, "casa-neri-42@google.com");
        assert_eq!(i.sequence, 2);
        assert_eq!(i.summary, "Casa Neri project review");
        assert_eq!(i.location, "Studio Ferri, via Solferino 12");
        // 15:00 in Rome in October (still summer time) is 13:00 UTC.
        assert_eq!(i.start, at(2026, 10, 23, 13, 0));
        assert_eq!(i.end, at(2026, 10, 23, 14, 0));
        assert!(!i.all_day && !i.floating && !i.repeats);
        let org = i.organizer.as_ref().unwrap();
        assert_eq!(
            (org.name.as_str(), org.email.as_str()),
            ("Giulia Ferri", "giulia@studioferri.it")
        );
        assert_eq!(i.attendees.len(), 2);
        let me = i.attendee("Matteo@Studio.it").unwrap();
        assert_eq!((me.name.as_str(), me.answer), ("Neri, Matteo", None));
        assert_eq!(i.attendees[1].answer, Some(Answer::Accepted));
    }

    #[test]
    fn winter_time_after_the_last_sunday_of_october() {
        let ics = GOOGLE.replace("20261023T150000", "20261026T150000");
        // October 25, 2026 is the last Sunday: from then on Rome is +01:00.
        assert_eq!(parse(&ics).unwrap().start, at(2026, 10, 26, 14, 0));
        let ics = GOOGLE.replace("20261023T150000", "20260328T150000");
        assert_eq!(parse(&ics).unwrap().start, at(2026, 3, 28, 14, 0));
        let ics = GOOGLE.replace("20261023T150000", "20260330T150000");
        assert_eq!(parse(&ics).unwrap().start, at(2026, 3, 30, 13, 0));
    }

    #[test]
    fn utc_dates_durations_and_cancels() {
        let ics = "BEGIN:VCALENDAR\nMETHOD:CANCEL\nBEGIN:VEVENT\nUID:a\n\
DTSTART:20261101T090000Z\nDURATION:PT1H30M\nSUMMARY:Standup\nRRULE:FREQ=DAILY\nEND:VEVENT\nEND:VCALENDAR\n";
        let i = parse(ics).unwrap();
        assert_eq!(i.method, Method::Cancel);
        assert_eq!(i.start, at(2026, 11, 1, 9, 0));
        assert_eq!(i.end, at(2026, 11, 1, 10, 30));
        assert!(i.repeats && !i.floating);

        let day = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:b\nDTSTART;VALUE=DATE:20261224\n\
SUMMARY:Holidays\nEND:VEVENT\nEND:VCALENDAR\n";
        let i = parse(day).unwrap();
        assert_eq!(i.method, Method::Publish);
        assert!(i.all_day && i.floating);
        assert_eq!(i.end - i.start, 86_400);

        let unknown = "BEGIN:VCALENDAR\nMETHOD:REQUEST\nBEGIN:VEVENT\nUID:c\n\
DTSTART;TZID=W. Europe Standard Time:20261023T150000\nEND:VEVENT\nEND:VCALENDAR\n";
        let i = parse(unknown).unwrap();
        assert!(i.floating);
        assert_eq!(i.start, at(2026, 10, 23, 15, 0));
        assert!(parse("BEGIN:VCALENDAR\nEND:VCALENDAR\n").is_none());
    }

    #[test]
    fn the_reply_answers_as_the_address_invited() {
        let now = at(2026, 10, 20, 9, 0);
        let r = reply(
            GOOGLE,
            "Matteo Neri",
            "matteo@STUDIO.it",
            Answer::Accepted,
            now,
        )
        .unwrap();
        assert!(r.contains("METHOD:REPLY\r\n"));
        assert!(r.contains("UID:casa-neri-42@google.com\r\n"));
        assert!(r.contains("SEQUENCE:2\r\n"));
        assert!(r.contains("DTSTART;TZID=Europe/Rome:20261023T150000\r\n"));
        assert!(r.contains("ORGANIZER;CN=Giulia Ferri:mailto:giulia@studioferri.it\r\n"));
        assert!(
            r.contains("ATTENDEE;PARTSTAT=ACCEPTED;CN=\"Matteo Neri\":mailto:matteo@studio.it\r\n")
        );
        assert!(r.contains("DTSTAMP:20261020T090000Z\r\n"));
        assert!(r.contains("BEGIN:VTIMEZONE\r\nTZID:Europe/Rome\r\n"));
        assert!(!r.contains("VALARM") && !r.contains("luca@"));
        assert!(r.lines().all(|l| l.len() <= FOLD));
        // Nothing to answer without an organizer.
        let none = GOOGLE.replace(
            "ORGANIZER;CN=Giulia Ferri:mailto:giulia@studioferri.it\r\n",
            "",
        );
        assert!(reply(&none, "", "m@x.it", Answer::Declined, now).is_none());
    }

    #[test]
    fn long_lines_fold_between_characters() {
        let line = format!("SUMMARY:{}", "è".repeat(60));
        let folded = fold(&line);
        assert!(folded.split("\r\n").all(|l| l.len() <= FOLD));
        let back: String = folded.split("\r\n ").collect::<Vec<_>>().join("");
        assert_eq!(back.trim_end(), line);
    }

    #[test]
    fn a_feed_says_how_often_to_read_it_again() {
        let head = |h: &str| {
            format!(
                "BEGIN:VCALENDAR\r\n{h}BEGIN:VEVENT\r\nUID:a\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
            )
        };
        assert_eq!(
            refresh_interval(&head("REFRESH-INTERVAL;VALUE=DURATION:P1D\r\n")),
            Some(86_400)
        );
        assert_eq!(
            refresh_interval(&head("X-PUBLISHED-TTL:PT6H\r\n")),
            Some(6 * 3600)
        );
        assert_eq!(refresh_interval(&head("")), None);
        assert_eq!(refresh_interval(&head("X-PUBLISHED-TTL:PT0S\r\n")), None);
    }

    #[test]
    fn a_calendar_holds_many_events_and_an_accepted_invite_loses_its_method() {
        let feed = "BEGIN:VCALENDAR\r\nX-WR-CALNAME:Italian holidays\r\n\
            BEGIN:VEVENT\r\nUID:a\r\nDTSTART;VALUE=DATE:20261101\r\nSUMMARY:All Saints\r\nTRANSP:TRANSPARENT\r\nEND:VEVENT\r\n\
            BEGIN:VEVENT\r\nUID:b\r\nDTSTART:20261208T090000Z\r\nDTEND:20261208T100000Z\r\nSUMMARY:Call\r\n\
            BEGIN:VALARM\r\nTRIGGER:-PT5M\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        let all = events(feed);
        assert_eq!(all.len(), 2);
        assert!(all[0].all_day && all[0].transparent);
        assert_eq!(all[1].summary, "Call");
        assert!(!all[1].transparent);
        assert_eq!(calendar_name(feed).as_deref(), Some("Italian holidays"));

        let invite = "BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:x\r\n\
            DTSTART:20261023T130000Z\r\nORGANIZER:mailto:giulia@example.org\r\n\
            ATTENDEE;CN=Teo;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:Teo@Example.org\r\n\
            END:VEVENT\r\nEND:VCALENDAR\r\n";
        let kept = for_calendar(invite, "teo@example.org", Answer::Accepted).unwrap();
        assert!(!kept.contains("METHOD"));
        assert!(kept.contains("ATTENDEE;CN=Teo;PARTSTAT=ACCEPTED:mailto:Teo@Example.org\r\n"));
        assert!(kept.contains("UID:x\r\n"));
    }
}
