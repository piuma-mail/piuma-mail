//! What the person types in the search field, understood.
//!
//! Plain words match anywhere (subject, sender, preview, body) as prefixes,
//! so "quot" finds "quote" and "quotes". A few operators narrow the search:
//!
//! - `from:sara` the sender's name or address
//! - `account:work` one account, by name or address
//! - `group:3` one address group, by its id
//! - `label:worksite` mail with one label, by its name
//! - `is:unread`
//! - `after:2026-09-14`, `before:2026-10-01` (days, inclusive and exclusive)
//! - `has:attachment` mail with files
//! - `in:vault` mail that made a Vault card, `in:newsletter` newsletters
//! - `from:people` mail written by people, not machines or lists
//!
//! Anything else, unknown operators included, is searched as text.

/// A parsed search.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Query {
    /// Words and "quoted phrases" to find anywhere.
    pub words: Vec<String>,
    /// Words the sender must match.
    pub from: Vec<String>,
    /// An account's name or address.
    pub account: Option<String>,
    pub unread: bool,
    /// Received at or after, in seconds since the epoch (UTC).
    pub after: Option<i64>,
    /// Received before, in seconds since the epoch (UTC).
    pub before: Option<i64>,
    /// `has:attachment`.
    pub attachment: bool,
    /// `in:vault`.
    pub vault: bool,
    /// `in:newsletter`.
    pub newsletter: bool,
    /// `from:people`.
    pub people: bool,
    /// `group:3`: the mail written to one address group.
    pub group: Option<i64>,
    /// `label:"To read"`: the mail with one label, by its name.
    pub label: Option<String>,
}

impl Query {
    pub fn parse(input: &str) -> Query {
        let mut q = Query::default();
        for token in tokens(input) {
            let Some((key, value)) = token.split_once(':') else {
                q.words.push(token);
                continue;
            };
            let value = value.trim_matches('"');
            match key.to_ascii_lowercase().as_str() {
                "from" if value.eq_ignore_ascii_case("people") => q.people = true,
                "from" if !value.is_empty() => q.from.push(value.to_owned()),
                "has"
                    if matches!(
                        value.to_ascii_lowercase().as_str(),
                        "attachment" | "attachments" | "file" | "files"
                    ) =>
                {
                    q.attachment = true
                }
                "in" if value.eq_ignore_ascii_case("vault") => q.vault = true,
                "in" if matches!(
                    value.to_ascii_lowercase().as_str(),
                    "newsletter" | "newsletters"
                ) =>
                {
                    q.newsletter = true
                }
                "account" if !value.is_empty() => q.account = Some(value.to_owned()),
                "group" if value.parse::<i64>().is_ok() => q.group = value.parse().ok(),
                "label" if !value.is_empty() => q.label = Some(value.to_owned()),
                "is" if value.eq_ignore_ascii_case("unread") => q.unread = true,
                "after" if day(value).is_some() => q.after = day(value),
                "before" if day(value).is_some() => q.before = day(value),
                _ => q.words.push(token),
            }
        }
        q.words.retain(|w| searchable(w));
        q.from.retain(|w| searchable(w));
        q
    }

    /// Nothing to search for.
    pub fn is_empty(&self) -> bool {
        self.words.is_empty()
            && self.from.is_empty()
            && self.account.is_none()
            && self.group.is_none()
            && self.label.is_none()
            && !self.unread
            && self.after.is_none()
            && self.before.is_none()
            && !self.attachment
            && !self.vault
            && !self.newsletter
            && !self.people
    }

    /// The full-text part, as an FTS5 expression; None when the search is
    /// only filters.
    pub(crate) fn fts(&self) -> Option<String> {
        let mut parts: Vec<String> = self.words.iter().map(|w| prefix(w)).collect();
        parts.extend(self.from.iter().map(|w| format!("sender : {}", prefix(w))));
        (!parts.is_empty()).then(|| parts.join(" AND "))
    }

    /// The words, as an expression on the sender only: who the person may
    /// be looking for.
    pub(crate) fn people_fts(&self) -> Option<String> {
        if self.words.is_empty() {
            return None;
        }
        let words: Vec<String> = self.words.iter().map(|w| prefix(w)).collect();
        Some(format!("sender : ({})", words.join(" AND ")))
    }
}

/// Splits on spaces, keeping "quoted phrases" (also after an operator, as
/// in `from:"Sara Conti"`) together.
fn tokens(input: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut quoted = false;
    for ch in input.chars() {
        match ch {
            '"' => {
                quoted = !quoted;
                if !quoted && !current.contains(':') {
                    out.push(std::mem::take(&mut current));
                }
            }
            c if c.is_whitespace() && !quoted => {
                if !current.is_empty() {
                    out.push(std::mem::take(&mut current));
                }
            }
            c => current.push(c),
        }
    }
    if !current.is_empty() {
        out.push(current);
    }
    out.retain(|t| !t.trim().is_empty());
    out
}

/// Words made only of punctuation give the tokenizer nothing to find.
fn searchable(word: &str) -> bool {
    word.chars().any(char::is_alphanumeric)
}

/// A quoted FTS5 string, matched as a prefix.
fn prefix(word: &str) -> String {
    format!("\"{}\"*", word.replace('"', "\"\""))
}

/// `YYYY-MM-DD` at midnight UTC, in seconds since the epoch.
fn day(s: &str) -> Option<i64> {
    let mut parts = s.splitn(3, '-');
    let y: i64 = parts.next()?.parse().ok()?;
    let m: i64 = parts.next()?.parse().ok()?;
    let d: i64 = parts.next()?.parse().ok()?;
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    // Days from civil (Howard Hinnant's algorithm).
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some((era * 146_097 + doe - 719_468) * 86_400)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_and_operators() {
        let q = Query::parse(r#"print quote from:sara is:unread account:Work after:2026-09-14"#);
        assert_eq!(q.words, ["print", "quote"]);
        assert_eq!(q.from, ["sara"]);
        assert_eq!(q.account.as_deref(), Some("Work"));
        assert!(q.unread);
        assert_eq!(q.after, Some(1_789_344_000));
        assert_eq!(q.before, None);
        assert_eq!(
            q.fts().unwrap(),
            r#""print"* AND "quote"* AND sender : "sara"*"#
        );
    }

    #[test]
    fn phrases_and_odd_input() {
        let q = Query::parse(r#" "print quote"  from:"Sara Conti" — has:photos before:soon "#);
        assert_eq!(q.words, ["print quote", "has:photos", "before:soon"]);
        assert_eq!(q.from, ["Sara Conti"]);
        assert_eq!(
            Query::parse(r#"say "hi""#).fts().unwrap(),
            r#""say"* AND "hi"*"#
        );
        assert_eq!(Query::parse(r#"a"b"#).words, ["ab"]);
        assert!(Query::parse("  — ! ").is_empty());
        assert_eq!(Query::parse("is:unread").fts(), None);
    }

    #[test]
    fn kinds_of_mail() {
        let q = Query::parse("lease has:attachment in:Vault in:newsletters from:People");
        assert_eq!(q.words, ["lease"]);
        assert!(q.from.is_empty());
        assert!(q.attachment && q.vault && q.newsletter && q.people);
        assert!(!Query::parse("has:attachment").is_empty());
        assert_eq!(Query::parse("in:vault").fts(), None);
    }

    #[test]
    fn quotes_inside_words_are_escaped() {
        let q = Query {
            words: vec![r#"o"k"#.into()],
            ..Query::default()
        };
        assert_eq!(q.fts().unwrap(), r#""o""k"*"#);
    }

    #[test]
    fn days() {
        assert_eq!(day("1970-01-01"), Some(0));
        assert_eq!(day("2026-10-01"), Some(1_790_812_800));
        assert_eq!(day("2026-13-01"), None);
        assert_eq!(day("yesterday"), None);
    }
}
