//! mbox files, the format other mail apps export folders in.
//!
//! Written as mboxrd: every body line that starts with `From ` after any
//! number of `>` gets one more `>`, so reading it back gives the message
//! byte for byte. Read leniently, as Thunderbird (mboxo, with
//! `X-Mozilla-Status`), Apple Mail (an `.mbox` folder holding `mbox`),
//! Gmail Takeout (mboxrd, with `X-Gmail-Labels`) and others write it: a
//! message starts at a `From ` line that follows an empty line (or opens
//! the file) and carries a time, and one `>` comes off quoted `From `
//! lines.
//!
//! The file is untrusted: nothing in it is run, a message larger than the
//! limit is skipped without being kept in memory, and a line without an
//! end is read only up to that limit.

use std::io::{self, BufRead, Write};

use crate::model::Flags;

/// A message read from an mbox file, with CRLF line ends.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MboxEntry {
    /// 1 for the file's first message.
    pub index: usize,
    /// The message, `From ` line left out and quoting undone.
    pub raw: Vec<u8>,
    /// When its `From ` line says it arrived, Unix seconds.
    pub delivered: Option<i64>,
}

/// A message of the file that is not given.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MboxSkip {
    /// Larger than the limit.
    TooLarge { index: usize },
}

/// Reads the messages of an mbox file one at a time, never more than one
/// message (at most `max` bytes) in memory.
pub struct MboxReader<R> {
    input: R,
    max: usize,
    /// The `From ` line of the next message, already read.
    next_from: Option<Vec<u8>>,
    /// Bytes read from `input` so far.
    consumed: u64,
    index: usize,
    started: bool,
    done: bool,
}

impl<R: BufRead> MboxReader<R> {
    pub fn new(input: R, max: usize) -> Self {
        MboxReader {
            input,
            max,
            next_from: None,
            consumed: 0,
            index: 0,
            started: false,
            done: false,
        }
    }

    /// Bytes of the file read so far, for progress.
    pub fn consumed(&self) -> u64 {
        self.consumed
    }

    /// One line, its end (`\n` or `\r\n`) taken off; None at the end of
    /// the file. A line longer than `cap` keeps only its first `cap`
    /// bytes, and says so.
    fn line(&mut self, buf: &mut Vec<u8>, cap: usize) -> io::Result<Option<bool>> {
        buf.clear();
        let mut any = false;
        let mut cut = false;
        loop {
            let chunk = self.input.fill_buf()?;
            if chunk.is_empty() {
                break;
            }
            any = true;
            let (part, end) = match chunk.iter().position(|&b| b == b'\n') {
                Some(i) => (&chunk[..i], Some(i + 1)),
                None => (chunk, None),
            };
            let room = cap.saturating_sub(buf.len());
            if part.len() > room {
                cut = true;
            }
            buf.extend_from_slice(&part[..part.len().min(room)]);
            let used = end.unwrap_or(chunk.len());
            self.input.consume(used);
            self.consumed += used as u64;
            if end.is_some() {
                break;
            }
        }
        if !any {
            return Ok(None);
        }
        if buf.last() == Some(&b'\r') {
            buf.pop();
        }
        Ok(Some(cut))
    }

    /// Whether the file starts like an mbox file: its first line that is
    /// not empty is a `From ` line.
    fn start(&mut self) -> io::Result<bool> {
        self.started = true;
        let mut line = Vec::new();
        while self.line(&mut line, FROM_LINE_MAX)?.is_some() {
            if line.is_empty() {
                continue;
            }
            if separator(&line) {
                self.next_from = Some(line);
                return Ok(true);
            }
            return Ok(false);
        }
        Ok(false)
    }
}

/// Longest `From ` line looked at.
const FROM_LINE_MAX: usize = 1_000;

/// Whether a line opens a message: `From `, a sender, and a time.
fn separator(line: &[u8]) -> bool {
    line.starts_with(b"From ")
        && line.len() <= FROM_LINE_MAX
        && line
            .windows(3)
            .any(|w| w[0].is_ascii_digit() && w[1] == b':' && w[2].is_ascii_digit())
}

/// `>From `, `>>From `…: a quoted line, one `>` comes off.
fn quoted(line: &[u8]) -> bool {
    let rest = line.iter().position(|&b| b != b'>').map(|i| &line[i..]);
    line.first() == Some(&b'>') && rest.is_some_and(|r| r.starts_with(b"From "))
}

/// Whether bytes are an mbox file, from its start.
pub fn looks_like_mbox(start: &[u8]) -> bool {
    let first = start
        .split(|&b| b == b'\n')
        .map(|l| l.strip_suffix(b"\r").unwrap_or(l))
        .find(|l| !l.is_empty());
    first.is_some_and(separator)
}

impl<R: BufRead> Iterator for MboxReader<R> {
    type Item = io::Result<Result<MboxEntry, MboxSkip>>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.done {
            return None;
        }
        if !self.started {
            match self.start() {
                Ok(true) => {}
                Ok(false) => {
                    self.done = true;
                    return Some(Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "not an mbox file",
                    )));
                }
                Err(e) => {
                    self.done = true;
                    return Some(Err(e));
                }
            }
        }
        let from = self.next_from.take()?;
        self.index += 1;
        let index = self.index;
        let mut raw = Vec::new();
        let mut too_large = false;
        // An empty line is held back: it may be the one before the next
        // `From ` line, which belongs to neither message.
        let mut blank = false;
        let mut line = Vec::new();
        loop {
            let cap = self.max.saturating_sub(raw.len()) + 1;
            let cut = match self.line(&mut line, cap) {
                Ok(Some(cut)) => cut,
                Ok(None) => {
                    self.done = true;
                    break;
                }
                Err(e) => {
                    self.done = true;
                    return Some(Err(e));
                }
            };
            if blank && separator(&line) {
                self.next_from = Some(std::mem::take(&mut line));
                break;
            }
            if too_large {
                blank = line.is_empty();
                continue;
            }
            if blank {
                raw.extend_from_slice(b"\r\n");
            }
            blank = line.is_empty();
            if blank {
                continue;
            }
            let text = if quoted(&line) { &line[1..] } else { &line[..] };
            raw.extend_from_slice(text);
            raw.extend_from_slice(b"\r\n");
            if cut || raw.len() > self.max {
                too_large = true;
                raw = Vec::new();
            }
        }
        if too_large {
            return Some(Ok(Err(MboxSkip::TooLarge { index })));
        }
        Some(Ok(Ok(MboxEntry {
            index,
            raw,
            delivered: from_line_time(&from),
        })))
    }
}

/// Writes messages into an mbox file, mboxrd style.
pub struct MboxWriter<W: Write> {
    out: W,
}

impl<W: Write> MboxWriter<W> {
    pub fn new(out: W) -> Self {
        MboxWriter { out }
    }

    /// Adds a message: a `From ` line with `sender` and `at` (Unix
    /// seconds), then `raw` with `From ` lines quoted and LF line ends.
    /// With `flags`, a message without a `Status` header gets `Status` and
    /// `X-Status`, which other mail apps read back as read, flagged and
    /// answered.
    pub fn add(
        &mut self,
        raw: &[u8],
        sender: &str,
        at: i64,
        flags: Option<Flags>,
    ) -> io::Result<()> {
        let sender: String = sender
            .chars()
            .filter(|c| !c.is_whitespace() && !c.is_control())
            .take(200)
            .collect();
        let sender = if sender.is_empty() {
            "MAILER-DAEMON".to_owned()
        } else {
            sender
        };
        writeln!(self.out, "From {sender} {}", asctime(at))?;
        if let Some(f) = flags {
            if header_value(raw, "Status").is_none() {
                let status = if f.seen { "RO" } else { "O" };
                writeln!(self.out, "Status: {status}")?;
                let mut x = String::new();
                if f.answered {
                    x.push('A');
                }
                if f.flagged {
                    x.push('F');
                }
                if !x.is_empty() {
                    writeln!(self.out, "X-Status: {x}")?;
                }
            }
        }
        let body = raw.strip_suffix(b"\n").unwrap_or(raw);
        for line in body.split(|&b| b == b'\n') {
            let line = line.strip_suffix(b"\r").unwrap_or(line);
            if line.first().is_some_and(|&b| b == b'>' || b == b'F')
                && (quoted(line) || line.starts_with(b"From "))
            {
                self.out.write_all(b">")?;
            }
            self.out.write_all(line)?;
            self.out.write_all(b"\n")?;
        }
        // The empty line between messages.
        self.out.write_all(b"\n")
    }

    pub fn into_inner(self) -> W {
        self.out
    }
}

/// The first value of a header in the header block of `raw`, unfolded;
/// None when it has none.
pub fn header_value(raw: &[u8], name: &str) -> Option<String> {
    let mut found: Option<String> = None;
    for line in raw.split(|&b| b == b'\n') {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        if line.is_empty() {
            break;
        }
        if line[0] == b' ' || line[0] == b'\t' {
            if let Some(v) = found.as_mut() {
                v.push(' ');
                v.push_str(String::from_utf8_lossy(line).trim());
            }
            continue;
        }
        if found.is_some() {
            break;
        }
        if let Some(colon) = line.iter().position(|&b| b == b':') {
            if line[..colon].eq_ignore_ascii_case(name.as_bytes()) {
                found = Some(
                    String::from_utf8_lossy(&line[colon + 1..])
                        .trim()
                        .to_owned(),
                );
            }
        }
    }
    found
}

/// What other mail apps left in a message's headers about it: `Status` and
/// `X-Status` (mbox), `X-Mozilla-Status` (Thunderbird), `X-Gmail-Labels`
/// (Gmail Takeout). A message none of them describe counts as read, as
/// archived mail usually is.
pub fn flags_in(raw: &[u8]) -> Flags {
    let mut flags = Flags {
        seen: true,
        flagged: false,
        answered: false,
    };
    if let Some(status) = header_value(raw, "Status") {
        flags.seen = status.contains('R');
    }
    if let Some(x) = header_value(raw, "X-Status") {
        flags.flagged |= x.contains('F');
        flags.answered |= x.contains('A');
    }
    if let Some(bits) =
        header_value(raw, "X-Mozilla-Status").and_then(|v| u32::from_str_radix(v.trim(), 16).ok())
    {
        flags.seen = bits & 0x1 != 0;
        flags.answered |= bits & 0x2 != 0;
        flags.flagged |= bits & 0x4 != 0;
    }
    if let Some(labels) = header_value(raw, "X-Gmail-Labels") {
        let has = |l: &str| labels.split(',').any(|x| x.trim().eq_ignore_ascii_case(l));
        flags.seen = !has("Unread");
        flags.flagged |= has("Starred");
    }
    flags
}

/// The time of a `From ` line: `From sender Thu Nov  3 10:00:00 2026`,
/// sometimes with a zone (`+0000`) before or after the year.
fn from_line_time(line: &[u8]) -> Option<i64> {
    let text = std::str::from_utf8(line).ok()?;
    let words: Vec<&str> = text.split_whitespace().skip(2).collect();
    let month = words.iter().position(|w| month_number(w).is_some())?;
    let mon = month_number(words[month])?;
    let day: i64 = words.get(month + 1)?.parse().ok()?;
    let time = words.get(month + 2)?;
    let mut hms = time.split(':').map(|p| p.parse::<i64>().ok());
    let (h, m) = (hms.next()??, hms.next()??);
    let s = hms.next().flatten().unwrap_or(0);
    let mut year = None;
    let mut zone = 0i64;
    for w in &words[month + 3..] {
        if let Ok(y) = w.parse::<i64>() {
            if (1970..=9999).contains(&y) && w.len() == 4 {
                year = Some(y);
                continue;
            }
        }
        if let Some(z) = parse_zone(w) {
            zone = z;
        }
    }
    let year = year?;
    if !(1..=31).contains(&day) || h > 23 || m > 59 || s > 60 {
        return None;
    }
    Some(days_from_civil(year, mon, day) * 86_400 + h * 3600 + m * 60 + s - zone)
}

fn parse_zone(w: &str) -> Option<i64> {
    let (sign, digits) = match w.as_bytes().first()? {
        b'+' => (1, &w[1..]),
        b'-' => (-1, &w[1..]),
        _ => return None,
    };
    if digits.len() != 4 || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let n: i64 = digits.parse().ok()?;
    Some(sign * ((n / 100) * 3600 + (n % 100) * 60))
}

const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];
const DAYS: [&str; 7] = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"];

fn month_number(w: &str) -> Option<i64> {
    MONTHS
        .iter()
        .position(|m| m.eq_ignore_ascii_case(w))
        .map(|i| i as i64 + 1)
}

/// Days since 1970-01-01 of a date of the Gregorian calendar.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The date of a day counted from 1970-01-01: (year, month, day).
fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// `Thu Nov  3 10:00:00 2026`, in UTC: the time of a `From ` line.
pub fn asctime(at: i64) -> String {
    let days = at.div_euclid(86_400);
    let secs = at.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!(
        "{} {} {:>2} {:02}:{:02}:{:02} {}",
        DAYS[days.rem_euclid(7) as usize],
        MONTHS[(m - 1) as usize],
        d,
        secs / 3600,
        secs % 3600 / 60,
        secs % 60,
        y
    )
}

/// `03-Nov-2026 10:00:00 +0000`: an IMAP date-time, for APPEND.
pub fn imap_date_time(at: i64) -> String {
    let days = at.div_euclid(86_400);
    let secs = at.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!(
        "{:02}-{}-{:04} {:02}:{:02}:{:02} +0000",
        d,
        MONTHS[(m - 1) as usize],
        y,
        secs / 3600,
        secs % 3600 / 60,
        secs % 60
    )
}

/// `2026-11-03T10:00:00Z`: a JMAP UTCDate, for Email/import.
pub fn utc_date(at: i64) -> String {
    let days = at.div_euclid(86_400);
    let secs = at.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        y,
        m,
        d,
        secs / 3600,
        secs % 3600 / 60,
        secs % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_all(data: &[u8], max: usize) -> Vec<Result<MboxEntry, MboxSkip>> {
        MboxReader::new(data, max).map(|r| r.unwrap()).collect()
    }

    #[test]
    fn dates_are_written_and_read_back() {
        // 2026-11-03 10:00:00 UTC, a Tuesday.
        let at = 1_793_700_000;
        assert_eq!(asctime(at), "Tue Nov  3 10:00:00 2026");
        assert_eq!(imap_date_time(at), "03-Nov-2026 10:00:00 +0000");
        assert_eq!(utc_date(at), "2026-11-03T10:00:00Z");
        let line = format!("From ada@example.com {}", asctime(at));
        assert_eq!(from_line_time(line.as_bytes()), Some(at));
        // Gmail Takeout writes a zone before the year.
        assert_eq!(
            from_line_time(b"From 1789@xxx Tue Nov 03 11:00:00 +0100 2026"),
            Some(at)
        );
        assert_eq!(asctime(0), "Thu Jan  1 00:00:00 1970");
    }

    #[test]
    fn mboxrd_quoting_round_trips() {
        let raw = b"From: a@example.com\r\nSubject: quoting\r\n\r\nFrom the start\r\n>From once\r\n>>From twice\r\nFromage\r\n> From spaced\r\n\r\n\r\nend\r\n";
        let mut out = MboxWriter::new(Vec::new());
        out.add(raw, "a@example.com", 0, None).unwrap();
        out.add(b"Subject: two\r\n\r\nsecond\r\n", "", 60, None)
            .unwrap();
        let file = out.into_inner();
        let text = String::from_utf8(file.clone()).unwrap();
        assert!(text.contains("\n>From the start\n"));
        assert!(text.contains("\n>>From once\n"));
        assert!(text.contains("\n>>>From twice\n"));
        assert!(text.contains("\nFromage\n"));
        assert!(text.contains("\n> From spaced\n"));
        assert!(text.contains("From MAILER-DAEMON Thu Jan  1 00:01:00 1970\n"));
        let back = read_all(&file, 1 << 20);
        assert_eq!(back.len(), 2);
        let first = back[0].clone().unwrap();
        assert_eq!(first.raw, raw.to_vec());
        assert_eq!(first.index, 1);
        assert_eq!(first.delivered, Some(0));
        assert_eq!(
            back[1].clone().unwrap().raw,
            b"Subject: two\r\n\r\nsecond\r\n".to_vec()
        );
    }

    #[test]
    fn a_from_line_in_a_paragraph_is_not_a_new_message() {
        // mboxo leaves "From " in a body unquoted: only one after an empty
        // line, with a time, starts a message.
        let file = b"From a@b Thu Jan  1 00:00:00 1970\nSubject: one\n\nwrote:\nFrom here on we go\n\nFrom me, thanks\n\nFrom b@c Thu Jan  1 00:00:01 1970\nSubject: two\n\nhi\n";
        let back = read_all(file, 1 << 20);
        assert_eq!(back.len(), 2);
        let one = String::from_utf8(back[0].clone().unwrap().raw).unwrap();
        assert!(one.contains("From here on we go\r\n"));
        assert!(one.contains("From me, thanks\r\n"));
    }

    #[test]
    fn crlf_files_and_trailing_lines() {
        let file =
            b"\r\n\r\nFrom a@b Thu Jan  1 00:00:00 1970\r\nSubject: x\r\n\r\nbody\r\n\r\n\r\n";
        let back = read_all(file, 1 << 20);
        assert_eq!(back.len(), 1);
        // One empty line ends the message; the one before it is kept.
        assert_eq!(
            back[0].clone().unwrap().raw,
            b"Subject: x\r\n\r\nbody\r\n\r\n".to_vec()
        );
    }

    #[test]
    fn too_large_messages_are_skipped_and_the_rest_read() {
        let mut file = b"From a@b Thu Jan  1 00:00:00 1970\nSubject: big\n\n".to_vec();
        file.extend(std::iter::repeat_n(b'x', 5000));
        file.extend_from_slice(b"\n\nFrom a@b Thu Jan  1 00:00:00 1970\nSubject: small\n\nok\n");
        let back = read_all(&file, 1000);
        assert_eq!(back.len(), 2);
        assert_eq!(back[0], Err(MboxSkip::TooLarge { index: 1 }));
        assert_eq!(back[1].clone().unwrap().index, 2);
    }

    #[test]
    fn what_is_not_mbox_says_so() {
        for junk in [
            &b"Subject: an eml\r\n\r\nhi"[..],
            b"",
            b"\x89PNG\r\n",
            b"From nobody\n",
        ] {
            let mut r = MboxReader::new(junk, 1000);
            assert!(r.next().unwrap().is_err(), "{junk:?}");
            assert!(r.next().is_none());
        }
        assert!(looks_like_mbox(b"\nFrom a@b Thu Jan  1 00:00:00 1970\n"));
        assert!(!looks_like_mbox(b"Received: from x\r\n"));
    }

    #[test]
    fn garbage_never_panics() {
        // Deterministic noise of every byte, lines of every length.
        let mut seed: u32 = 7;
        for round in 0..200 {
            let mut data = b"From a@b Thu Jan  1 00:00:00 1970\n".to_vec();
            for _ in 0..(round * 13) {
                seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12_345);
                let b = (seed >> 16) as u8;
                data.push(match b % 7 {
                    0 => b'\n',
                    1 => b'>',
                    _ => b,
                });
            }
            for item in MboxReader::new(&data[..], 300) {
                let _ = item;
            }
            let _ = flags_in(&data);
            let _ = from_line_time(&data);
        }
    }

    #[test]
    fn flags_from_other_apps() {
        let seen =
            |h: &str| flags_in(format!("{h}\r\nSubject: x\r\n\r\nStatus: RO\r\n").as_bytes());
        assert!(seen("X-Nothing: 1").seen);
        assert!(!seen("Status: O").seen);
        assert!(seen("Status: RO").seen);
        let f = seen("Status: O\r\nX-Status: AF");
        assert!(!f.seen && f.flagged && f.answered);
        let t = seen("X-Mozilla-Status: 0005");
        assert!(t.seen && t.flagged && !t.answered);
        assert!(!seen("X-Mozilla-Status: 0000").seen);
        let g = seen("X-Gmail-Labels: Inbox,Starred,Unread");
        assert!(!g.seen && g.flagged);
        assert!(seen("X-Gmail-Labels: Archived,\r\n Opened").seen);
    }

    #[test]
    fn written_flags_are_read_back() {
        let mut out = MboxWriter::new(Vec::new());
        let flags = Flags {
            seen: false,
            flagged: true,
            answered: true,
        };
        out.add(b"Subject: x\r\n\r\nhi\r\n", "a@b", 0, Some(flags))
            .unwrap();
        // A message that already says it is kept as it is.
        out.add(
            b"Status: RO\r\nSubject: y\r\n\r\nhi\r\n",
            "a@b",
            0,
            Some(flags),
        )
        .unwrap();
        let file = out.into_inner();
        let back = read_all(&file, 1 << 20);
        assert_eq!(flags_in(&back[0].clone().unwrap().raw), flags);
        assert!(flags_in(&back[1].clone().unwrap().raw).seen);
    }
}
