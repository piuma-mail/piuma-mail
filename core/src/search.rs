//! What the person types in the search field, understood.
//!
//! Plain words match anywhere (subject, sender, preview, body) as prefixes,
//! so "quot" finds "quote" and "quotes". Operators narrow the search:
//!
//! | Typed                         | Finds                                                   | On the server (IMAP / JMAP)          |
//! |-------------------------------|---------------------------------------------------------|--------------------------------------|
//! | `quote`                       | the word, as a prefix, anywhere                         | `TEXT` / `text`                      |
//! | `"print quote"`               | the words together, in that order                       | `TEXT` / `text`                      |
//! | `from:sara`                   | the sender's name or address                            | `FROM` / `from`                      |
//! | `from:people`                 | mail written by people, not machines or lists           | not asked (this device only)         |
//! | `to:sara`                     | a recipient's name or address (1)                       | `TO` / `to`                          |
//! | `cc:sara`                     | a recipient's address (1)                               | `CC` / `cc`                          |
//! | `bcc:sara`                    | own sent mail with Sara in Bcc: the server only (2)      | `BCC` / `bcc`                        |
//! | `subject:invoice`             | the subject                                             | `SUBJECT` / `subject`                |
//! | `account:work`                | one account, by name or address                         | picks the accounts asked             |
//! | `group:3`                     | mail written to one address group, by its id            | `TO`/`CC` its addresses              |
//! | `label:"To read"`             | mail with one label, by its name                        | `KEYWORD` / `hasKeyword`             |
//! | `in:inbox`, `in:sent`, …      | one folder: inbox, sent, archive, drafts, snoozed,     | the folders asked / `inMailbox`      |
//! | `in:clients/acme`             | trash, spam, or an own folder by name or path (`/`),   |                                      |
//! |                               | any case                                                |                                      |
//! | `in:vault`                    | mail that made a Vault card                             | not asked (this device only)         |
//! | `in:newsletter`               | newsletters                                             | has `List-Unsubscribe`               |
//! | `is:unread`, `is:read`        | read or not                                             | `UNSEEN`/`SEEN` / `$seen`            |
//! | `is:starred`, `is:flagged`    | flagged mail                                            | `FLAGGED` / `$flagged`               |
//! | `has:attachment`              | mail with files                                         | multipart/mixed (3) / `hasAttachment`|
//! | `filename:pdf`                | a file's name holds the text                            | `TEXT` / `text` (3)                  |
//! | `after:2026-09-14`            | received on that day or later (`2026/09/14` too)         | `SINCE` / `after`                    |
//! | `before:2026-10-01`           | received before that day                                | `BEFORE` / `before`                  |
//! | `larger:5M`, `smaller:200K`   | size in bytes, `K`, `M` or `G` (1024 each), `KB`, … (4) | `LARGER`/`SMALLER` / `minSize`/`maxSize` |
//! | `-word`, `-from:sara`         | leaves out what the term finds                          | `NOT` / `NOT`                        |
//! | `a OR b`                      | either term; `OR` binds tighter than the space         | `OR` / `OR`                          |
//!
//! 1. This device keeps every recipient's address together (To, Cc and
//!    the mailbox it was delivered to), so here `to:` and `cc:` both look
//!    at all of them; the server tells them apart.
//! 2. The Bcc header is only in the sender's own copy on the server, so
//!    `bcc:` finds nothing here and leaves the answer to the server.
//! 3. The server can only look for these roughly: it may find more.
//! 4. Here a message's size is its files plus its text, a little less
//!    than the server's count of the whole message.
//!
//! The parser is total: any input gives a query, nothing panics and
//! nothing is refused. Unknown operators (`foo:bar`) and values that
//! don't fit (`before:soon`, `is:important`) are searched as text; an
//! operator with nothing after it (`from:`) is left out, as it is being
//! typed. Words made only of punctuation are left out. `OR` at the start,
//! at the end or twice in a row is left out; lower-case `or` is a word.
//! Input past [`MAX_INPUT`] characters and terms past [`MAX_TERMS`] are
//! dropped.

use std::collections::HashMap;

use rusqlite::types::Value as SqlValue;
use serde_json::{json, Value};

/// Characters of input read; the rest is left out.
pub const MAX_INPUT: usize = 2000;
/// Terms kept; the rest are left out.
pub const MAX_TERMS: usize = 64;
/// Characters kept of one term.
const MAX_TERM_CHARS: usize = 256;

/// A parsed search: clauses that must all match, each a list of terms of
/// which one must match.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Query {
    pub clauses: Vec<Clause>,
}

/// Terms joined by `OR`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Clause {
    pub any: Vec<Literal>,
}

/// A term, or with `-` before it, its opposite.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Literal {
    pub term: Term,
    pub negated: bool,
}

/// One thing to look for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Term {
    /// A word or a "quoted phrase", anywhere.
    Text(String),
    From(String),
    To(String),
    Cc(String),
    Bcc(String),
    Subject(String),
    /// `from:people`.
    People,
    /// An account's name or address.
    Account(String),
    /// An address group, by its id.
    Group(i64),
    /// A label, by its name.
    Label(String),
    /// A folder, by its job (`inbox`, `sent`, …), name or path.
    Folder(String),
    /// `in:vault`.
    Vault,
    /// `in:newsletter`.
    Newsletter,
    Unread,
    Read,
    Starred,
    /// `has:attachment`.
    Attachment,
    /// A file's name holds the text.
    Filename(String),
    /// Received at or after, in seconds since the epoch (UTC).
    After(i64),
    /// Received before, in seconds since the epoch (UTC).
    Before(i64),
    /// Bigger than, in bytes.
    Larger(u64),
    /// Smaller than, in bytes.
    Smaller(u64),
}

impl Term {
    /// Whether the full-text index can answer it.
    fn fts(&self) -> Option<String> {
        match self {
            Term::Text(w) => Some(prefix(w)),
            Term::From(w) => Some(format!("sender : {}", prefix(w))),
            Term::Subject(w) => Some(format!("subject : {}", prefix(w))),
            _ => None,
        }
    }
}

impl Query {
    pub fn parse(input: &str) -> Query {
        let input = match input.char_indices().nth(MAX_INPUT) {
            Some((end, _)) => &input[..end],
            None => input,
        };
        let mut clauses: Vec<Clause> = Vec::new();
        let mut join = false;
        let mut terms = 0;
        for raw in tokens(input) {
            if raw.text == "OR" && !raw.quoted && !raw.dash {
                join = !clauses.is_empty();
                continue;
            }
            let Some(literal) = literal(raw) else {
                continue;
            };
            if terms == MAX_TERMS {
                break;
            }
            terms += 1;
            match clauses.last_mut() {
                Some(last) if join => last.any.push(literal),
                _ => clauses.push(Clause { any: vec![literal] }),
            }
            join = false;
        }
        Query { clauses }
    }

    /// A query of plain terms that must all match.
    pub fn of(terms: impl IntoIterator<Item = Term>) -> Query {
        Query {
            clauses: terms
                .into_iter()
                .map(|term| Clause {
                    any: vec![Literal {
                        term,
                        negated: false,
                    }],
                })
                .collect(),
        }
    }

    /// Nothing to search for.
    pub fn is_empty(&self) -> bool {
        self.clauses.is_empty()
    }

    /// The terms that must match, alone in their clause and not negated.
    fn required(&self) -> impl Iterator<Item = &Term> {
        self.clauses.iter().filter_map(|c| match c.any.as_slice() {
            [l] if !l.negated => Some(&l.term),
            _ => None,
        })
    }

    /// The words that must match anywhere.
    pub fn words(&self) -> Vec<&str> {
        self.required()
            .filter_map(|t| match t {
                Term::Text(w) => Some(w.as_str()),
                _ => None,
            })
            .collect()
    }

    /// The one account asked for with `account:`, if one is.
    pub fn account(&self) -> Option<&str> {
        self.required().find_map(|t| match t {
            Term::Account(a) => Some(a.as_str()),
            _ => None,
        })
    }

    /// The one group asked for with `group:`, if one is.
    pub fn group(&self) -> Option<i64> {
        self.required().find_map(|t| match t {
            Term::Group(g) => Some(*g),
            _ => None,
        })
    }

    /// Every folder named with `in:`, as typed.
    pub fn folders(&self) -> Vec<&str> {
        let mut out: Vec<&str> = Vec::new();
        for l in self.clauses.iter().flat_map(|c| &c.any) {
            if let Term::Folder(f) = &l.term {
                if !out.iter().any(|o| o.eq_ignore_ascii_case(f)) {
                    out.push(f);
                }
            }
        }
        out
    }

    /// Whether a term only this device can answer is in it (`in:vault`,
    /// `from:people`): the server isn't asked then.
    pub fn local_only(&self) -> bool {
        self.clauses
            .iter()
            .flat_map(|c| &c.any)
            .any(|l| matches!(l.term, Term::Vault | Term::People))
    }

    /// The words, as an expression on the sender only: who the person may
    /// be looking for.
    pub(crate) fn people_fts(&self) -> Option<String> {
        let words: Vec<String> = self.words().into_iter().map(prefix).collect();
        if words.is_empty() {
            return None;
        }
        Some(format!("sender : ({})", words.join(" AND ")))
    }

    /// The FROM and WHERE of a search over `from` (which names the message
    /// `m`), its arguments, and whether it matches words through the
    /// full-text index (which `snippet()` then reads). `folders` holds
    /// where each folder named with `in:` is, by [`folder_key`].
    pub(crate) fn sql(&self, from: &str, folders: &Folders) -> Where {
        let mut args: Vec<SqlValue> = Vec::new();
        // Clauses of words only, none left out: one expression for the
        // index, which also finds the snippet.
        let mut fts: Vec<String> = Vec::new();
        let mut rest: Vec<&Clause> = Vec::new();
        for clause in &self.clauses {
            let words: Option<Vec<String>> = clause
                .any
                .iter()
                .map(|l| if l.negated { None } else { l.term.fts() })
                .collect();
            match words {
                Some(w) if w.len() == 1 => fts.push(w.into_iter().next().unwrap_or_default()),
                Some(w) => fts.push(format!("({})", w.join(" OR "))),
                None => rest.push(clause),
            }
        }
        let mut sql = String::from(from);
        let indexed = !fts.is_empty();
        if indexed {
            args.push(fts.join(" AND ").into());
            sql.push_str(
                " JOIN message_fts ON message_fts.rowid = m.rowid WHERE message_fts MATCH ?1",
            );
        } else {
            sql.push_str(" WHERE 1");
        }
        // Mail a server search brought from outside the sync (hidden 2)
        // is found too; mail hidden for an undo isn't.
        sql.push_str(" AND m.hidden IN (0, 2)");
        for clause in rest {
            let parts: Vec<String> = clause
                .any
                .iter()
                .map(|l| {
                    let c = condition(&l.term, &mut args, folders);
                    if l.negated {
                        format!("NOT ({c})")
                    } else {
                        format!("({c})")
                    }
                })
                .collect();
            sql.push_str(&format!(" AND ({})", parts.join(" OR ")));
        }
        Where {
            sql,
            args,
            fts: indexed,
        }
    }

    /// The search as a server can run it in `scope`.
    pub fn for_server(&self, scope: &Scope<'_>) -> ServerAsk {
        if self.local_only() {
            return ServerAsk::Unsupported;
        }
        let mut clauses = Vec::new();
        'clauses: for clause in &self.clauses {
            let mut any = Vec::new();
            for l in &clause.any {
                match server_key(&l.term, scope) {
                    Eval::Known(yes) => {
                        if yes != l.negated {
                            // This term holds: the whole clause does.
                            continue 'clauses;
                        }
                    }
                    Eval::Key(key, flip) => any.push(ServerLiteral {
                        key,
                        negated: l.negated != flip,
                    }),
                }
            }
            if any.is_empty() {
                return ServerAsk::Nothing;
            }
            clauses.push(any);
        }
        if clauses.is_empty() {
            // Only filters this device already applied: nothing to ask.
            return ServerAsk::Nothing;
        }
        ServerAsk::Ask(ServerQuery { clauses })
    }
}

/// Where each folder named with `in:` is: (account, mailbox) pairs by
/// [`folder_key`].
pub(crate) type Folders = HashMap<String, Vec<(i64, String)>>;

/// How `in:` values are compared.
pub fn folder_key(value: &str) -> String {
    let v = value.trim().trim_matches('/').to_lowercase();
    v.strip_prefix("inbox/").map(str::to_owned).unwrap_or(v)
}

/// A search's FROM and WHERE, see [`Query::sql`].
pub(crate) struct Where {
    pub sql: String,
    pub args: Vec<SqlValue>,
    pub fts: bool,
}

/// One term as a condition on `message m`, always true or false (never
/// NULL), so `NOT` turns it around.
fn condition(term: &Term, args: &mut Vec<SqlValue>, folders: &Folders) -> String {
    let mut arg = |v: SqlValue| {
        args.push(v);
        format!("?{}", args.len())
    };
    let like = |v: &str| SqlValue::from(format!("%{}%", escape_like(&v.to_lowercase())));
    match term {
        Term::Text(_) | Term::From(_) | Term::Subject(_) => {
            let expr = term.fts().unwrap_or_default();
            format!(
                "m.rowid IN (SELECT rowid FROM message_fts WHERE message_fts MATCH {})",
                arg(expr.into())
            )
        }
        Term::To(v) => {
            let p = arg(like(v));
            format!(
                "lower(m.to_list) LIKE {p} ESCAPE '\\' OR lower(m.recipients) LIKE {p} ESCAPE '\\'"
            )
        }
        Term::Cc(v) => format!("lower(m.recipients) LIKE {} ESCAPE '\\'", arg(like(v))),
        // Only the server's copy of sent mail has its Bcc.
        Term::Bcc(_) => "0".into(),
        Term::People => crate::store::PEOPLE.into(),
        Term::Account(a) => {
            let p = arg(a.clone().into());
            format!(
                "m.account IN (SELECT id FROM account WHERE lower(name) = lower({p}) OR lower(email) = lower({p}))"
            )
        }
        Term::Group(g) => {
            let sql = crate::groups::Within::Group(*g).sql();
            sql.trim_start()
                .strip_prefix("AND ")
                .map(str::to_owned)
                .unwrap_or(sql)
        }
        Term::Label(name) => format!(
            "EXISTS (SELECT 1 FROM message_labels ml JOIN label lb ON lb.name = {} COLLATE NOCASE
                     WHERE ml.account = m.account AND ml.mailbox = m.mailbox AND ml.uid = m.uid
                       AND instr(' ' || ml.labels || ' ', ' ' || lb.keyword || ' ') > 0)",
            arg(name.clone().into())
        ),
        Term::Folder(f) => {
            let places = folders
                .get(&folder_key(f))
                .map(Vec::as_slice)
                .unwrap_or_default();
            if places.is_empty() {
                return "0".into();
            }
            let rows: Vec<String> = places
                .iter()
                .map(|(account, mailbox)| {
                    let a = arg((*account).into());
                    let b = arg(mailbox.clone().into());
                    format!("({a}, {b})")
                })
                .collect();
            format!("(m.account, m.mailbox) IN (VALUES {})", rows.join(", "))
        }
        Term::Vault => "EXISTS (SELECT 1 FROM vault_card v
                     WHERE v.account = m.account AND v.mailbox = m.mailbox AND v.uid = m.uid)"
            .into(),
        Term::Newsletter => "m.newsletter = 1 OR m.folder = 'newsletters'".into(),
        Term::Unread => "(m.flags & 1) = 0".into(),
        Term::Read => "(m.flags & 1) = 1".into(),
        Term::Starred => "(m.flags & 2) = 2".into(),
        Term::Attachment => "EXISTS (SELECT 1 FROM attachment a
                     WHERE a.account = m.account AND a.mailbox = m.mailbox AND a.uid = m.uid)"
            .into(),
        Term::Filename(v) => format!(
            "EXISTS (SELECT 1 FROM attachment a
                     WHERE a.account = m.account AND a.mailbox = m.mailbox AND a.uid = m.uid
                       AND lower(a.name) LIKE {} ESCAPE '\\')",
            arg(like(v))
        ),
        Term::After(t) => format!("m.received_at >= {}", arg((*t).into())),
        Term::Before(t) => format!("m.received_at < {}", arg((*t).into())),
        Term::Larger(n) => format!("{SIZE} > {}", arg(clamp_size(*n).into())),
        Term::Smaller(n) => format!("{SIZE} < {}", arg(clamp_size(*n).into())),
    }
}

/// A message's size on this device: its files and its text (the body when
/// kept, else the preview).
const SIZE: &str = "(COALESCE((SELECT SUM(a.size) FROM attachment a
        WHERE a.account = m.account AND a.mailbox = m.mailbox AND a.uid = m.uid), 0)
    + COALESCE((SELECT length(b.text) FROM message_body b
        WHERE b.account = m.account AND b.mailbox = m.mailbox AND b.uid = m.uid), length(m.preview)))";

fn clamp_size(n: u64) -> i64 {
    i64::try_from(n).unwrap_or(i64::MAX)
}

fn escape_like(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        if matches!(c, '%' | '_' | '\\') {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

/// A piece of input between spaces, with what its quotes and punctuation
/// meant.
#[derive(Default)]
struct Raw {
    text: String,
    /// Where the first `:` outside quotes is, in bytes.
    colon: Option<usize>,
    /// It began with a `-` outside quotes (taken out of `text`).
    dash: bool,
    /// Some of it was quoted.
    quoted: bool,
}

/// Splits on spaces, keeping "quoted phrases" (also after an operator, as
/// in `from:"Sara Conti"`) together. A quote left open runs to the end.
fn tokens(input: &str) -> Vec<Raw> {
    fn push(out: &mut Vec<Raw>, current: &mut Raw) {
        let raw = std::mem::take(current);
        if !raw.text.trim().is_empty() {
            out.push(raw);
        }
    }
    let mut out = Vec::new();
    let mut current = Raw::default();
    let mut quoted = false;
    for ch in input.chars() {
        match ch {
            '"' => {
                quoted = !quoted;
                current.quoted = true;
                // A closing quote ends a phrase, unless an operator holds it.
                if !quoted && current.colon.is_none() {
                    push(&mut out, &mut current);
                }
            }
            c if c.is_whitespace() && !quoted => push(&mut out, &mut current),
            // Control characters can't be searched for.
            c if c.is_control() => {}
            c => {
                if !quoted
                    && c == '-'
                    && current.text.is_empty()
                    && !current.quoted
                    && !current.dash
                {
                    current.dash = true;
                    continue;
                }
                if current.text.chars().count() >= MAX_TERM_CHARS + 16 {
                    continue;
                }
                if !quoted && c == ':' && current.colon.is_none() && !current.quoted {
                    current.colon = Some(current.text.len());
                }
                current.text.push(c);
            }
        }
    }
    push(&mut out, &mut current);
    out
}

/// What an operator's value made of it.
enum Operator {
    Term(Term),
    /// Nothing typed after it yet.
    Ignore,
    /// Not an operator after all: a word.
    Word,
}

fn literal(raw: Raw) -> Option<Literal> {
    let negated = raw.dash;
    let text = cut(raw.text.trim());
    let term = match raw.colon {
        Some(i) if i < raw.text.len() && raw.text.is_char_boundary(i) => {
            let key = &raw.text[..i];
            let value = cut(raw.text[i + 1..].trim());
            if !key.is_empty() && key.chars().all(|c| c.is_ascii_alphabetic() || c == '_') {
                match operator(&key.to_ascii_lowercase(), &value) {
                    Operator::Term(t) => t,
                    Operator::Ignore => return None,
                    Operator::Word => Term::Text(text),
                }
            } else {
                Term::Text(text)
            }
        }
        _ => Term::Text(text),
    };
    if let Term::Text(t) = &term {
        if !searchable(t) {
            return None;
        }
    }
    Some(Literal { term, negated })
}

fn cut(s: &str) -> String {
    s.chars().take(MAX_TERM_CHARS).collect()
}

fn operator(key: &str, value: &str) -> Operator {
    use Operator::{Ignore, Word};
    let known = matches!(
        key,
        "from"
            | "to"
            | "cc"
            | "bcc"
            | "subject"
            | "account"
            | "group"
            | "label"
            | "in"
            | "is"
            | "has"
            | "filename"
            | "after"
            | "before"
            | "larger"
            | "smaller"
    );
    if !known {
        return Word;
    }
    if value.is_empty() {
        return Ignore;
    }
    let v = value.to_lowercase();
    let text = |make: fn(String) -> Term| {
        if searchable(value) {
            Operator::Term(make(value.to_owned()))
        } else {
            Ignore
        }
    };
    match key {
        "from" if v == "people" => Operator::Term(Term::People),
        "from" => text(Term::From),
        "to" => text(Term::To),
        "cc" => text(Term::Cc),
        "bcc" => text(Term::Bcc),
        "subject" => text(Term::Subject),
        "filename" => text(Term::Filename),
        "account" => Operator::Term(Term::Account(value.to_owned())),
        "label" => Operator::Term(Term::Label(value.to_owned())),
        "group" => value
            .parse::<i64>()
            .map_or(Word, |g| Operator::Term(Term::Group(g))),
        "in" => Operator::Term(match v.as_str() {
            "vault" => Term::Vault,
            "newsletter" | "newsletters" => Term::Newsletter,
            _ => Term::Folder(value.to_owned()),
        }),
        "is" => match v.as_str() {
            "unread" => Operator::Term(Term::Unread),
            "read" => Operator::Term(Term::Read),
            "starred" | "flagged" => Operator::Term(Term::Starred),
            _ => Word,
        },
        "has" => match v.as_str() {
            "attachment" | "attachments" | "file" | "files" => Operator::Term(Term::Attachment),
            _ => Word,
        },
        "after" => day(value).map_or(Word, |d| Operator::Term(Term::After(d))),
        "before" => day(value).map_or(Word, |d| Operator::Term(Term::Before(d))),
        "larger" => size(value).map_or(Word, |n| Operator::Term(Term::Larger(n))),
        "smaller" => size(value).map_or(Word, |n| Operator::Term(Term::Smaller(n))),
        _ => Word,
    }
}

/// The largest number JMAP takes (RFC 8620, `UnsignedInt`).
const JMAP_MAX_INT: u64 = (1 << 53) - 1;

/// Words made only of punctuation give the tokenizer nothing to find.
fn searchable(word: &str) -> bool {
    word.chars().any(char::is_alphanumeric)
}

/// A quoted FTS5 string, matched as a prefix.
fn prefix(word: &str) -> String {
    format!("\"{}\"*", word.replace('"', "\"\""))
}

/// `YYYY-MM-DD` (or `YYYY/MM/DD`) at midnight UTC, in seconds since the
/// epoch.
fn day(s: &str) -> Option<i64> {
    let mut parts = s.splitn(3, ['-', '/']);
    let y: i64 = parts.next()?.parse().ok()?;
    let m: i64 = parts.next()?.parse().ok()?;
    let d: i64 = parts.next()?.parse().ok()?;
    if !(1..=9999).contains(&y) || !(1..=12).contains(&m) || d < 1 {
        return None;
    }
    let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    let last = match m {
        2 if leap => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    };
    // `before:2026-02-31` is a typo, searched as text, not March 3.
    if d > last {
        return None;
    }
    Some(days_from_civil(y, m, d) * 86_400)
}

/// Days since 1970-01-01 (Howard Hinnant's algorithm).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The day of `secs` (UTC), as (year, month, day).
fn civil(secs: i64) -> (i64, u32, u32) {
    let z = secs.div_euclid(86_400) + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

/// A size: a number of bytes, or with `K`, `M` or `G` (1024 each, `KB`,
/// `KiB` too), a decimal point or comma allowed.
fn size(s: &str) -> Option<u64> {
    let s = s.trim().to_ascii_lowercase();
    let split = s
        .find(|c: char| !(c.is_ascii_digit() || c == '.' || c == ','))
        .unwrap_or(s.len());
    let (number, unit) = s.split_at(split);
    let unit: u64 = match unit {
        "" | "b" => 1,
        "k" | "kb" | "kib" => 1 << 10,
        "m" | "mb" | "mib" => 1 << 20,
        "g" | "gb" | "gib" => 1 << 30,
        _ => return None,
    };
    let number: f64 = number.replace(',', ".").parse().ok()?;
    let bytes = number * unit as f64;
    (bytes.is_finite() && bytes >= 0.0 && bytes < u64::MAX as f64).then_some(bytes as u64)
}

/// What a server is told for one term, in [`Query::for_server`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Key {
    Text(String),
    From(String),
    To(String),
    Cc(String),
    Bcc(String),
    Subject(String),
    Seen,
    Flagged,
    /// Received on that day or later (seconds since the epoch, a midnight).
    Since(i64),
    /// Received before that day.
    Before(i64),
    Larger(u64),
    Smaller(u64),
    Keyword(String),
    /// The message has this header.
    Header(&'static str),
    Attachment,
    /// Sent to one of these addresses (To or Cc).
    Recipients(Vec<String>),
    /// In one of these folders (JMAP ids).
    InMailbox(Vec<String>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerLiteral {
    pub key: Key,
    pub negated: bool,
}

/// A search a server can run: clauses that must all match, each a list
/// of which one must.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerQuery {
    pub clauses: Vec<Vec<ServerLiteral>>,
}

/// What to ask a server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServerAsk {
    Ask(ServerQuery),
    /// Nothing there can match, or there is nothing to ask beyond what
    /// this device already filtered.
    Nothing,
    /// It holds a term only this device knows (`in:vault`).
    Unsupported,
}

/// Where a server search runs, to answer the terms about accounts,
/// groups, labels and folders there.
pub struct Scope<'a> {
    pub account_name: &'a str,
    pub account_email: &'a str,
    /// Label keywords, by lower-case name.
    pub labels: &'a HashMap<String, String>,
    /// This account's addresses in each group, by group id.
    pub groups: &'a HashMap<i64, Vec<String>>,
    /// Whether an `in:` value names where the search runs.
    pub folder: &'a (dyn Fn(&str) -> InFolder + Send + Sync),
}

/// An `in:` value, where a server search runs.
pub enum InFolder {
    /// The folder searched is that one (IMAP, one folder at a time).
    Yes,
    No,
    /// These folders (JMAP ids), the server checks.
    Ids(Vec<String>),
}

enum Eval {
    Known(bool),
    /// The key, and whether it says the opposite of the term.
    Key(Key, bool),
}

fn server_key(term: &Term, scope: &Scope<'_>) -> Eval {
    let key = |k: Key| Eval::Key(k, false);
    match term {
        Term::Text(w) | Term::Filename(w) => key(Key::Text(w.clone())),
        Term::From(w) => key(Key::From(w.clone())),
        Term::To(w) => key(Key::To(w.clone())),
        Term::Cc(w) => key(Key::Cc(w.clone())),
        Term::Bcc(w) => key(Key::Bcc(w.clone())),
        Term::Subject(w) => key(Key::Subject(w.clone())),
        Term::Unread => Eval::Key(Key::Seen, true),
        Term::Read => key(Key::Seen),
        Term::Starred => key(Key::Flagged),
        Term::Attachment => key(Key::Attachment),
        Term::Newsletter => key(Key::Header("List-Unsubscribe")),
        Term::After(t) => key(Key::Since(*t)),
        Term::Before(t) => key(Key::Before(*t)),
        Term::Larger(n) => key(Key::Larger(*n)),
        Term::Smaller(n) => key(Key::Smaller(*n)),
        Term::Account(a) => Eval::Known(
            scope.account_name.eq_ignore_ascii_case(a)
                || scope.account_email.eq_ignore_ascii_case(a),
        ),
        Term::Group(g) => match scope.groups.get(g) {
            Some(addresses) if !addresses.is_empty() => key(Key::Recipients(addresses.clone())),
            _ => Eval::Known(false),
        },
        Term::Label(name) => match scope.labels.get(&name.to_lowercase()) {
            Some(k) => key(Key::Keyword(k.clone())),
            None => Eval::Known(false),
        },
        Term::Folder(f) => match (scope.folder)(f) {
            InFolder::Yes => Eval::Known(true),
            InFolder::No => Eval::Known(false),
            InFolder::Ids(ids) if ids.is_empty() => Eval::Known(false),
            InFolder::Ids(ids) => key(Key::InMailbox(ids)),
        },
        // Never reached: Query::for_server stops at them first.
        Term::Vault | Term::People => Eval::Known(false),
    }
}

impl ServerQuery {
    /// Whether some text in it needs UTF-8.
    pub fn needs_utf8(&self) -> bool {
        self.literals().any(|l| match &l.key {
            Key::Text(s)
            | Key::From(s)
            | Key::To(s)
            | Key::Cc(s)
            | Key::Bcc(s)
            | Key::Subject(s) => !s.is_ascii(),
            Key::Recipients(list) => list.iter().any(|s| !s.is_ascii()),
            _ => false,
        })
    }

    fn literals(&self) -> impl Iterator<Item = &ServerLiteral> {
        self.clauses.iter().flatten()
    }

    /// The same search with only ASCII text, for servers that refuse
    /// `CHARSET UTF-8`. What it finds is never less than the search
    /// itself would, and may be more (the answer is then partial):
    ///
    /// - a text looked for keeps its longest ASCII run ("café" looks for
    ///   "caf", which IMAP finds inside "café");
    /// - a text left out ("-café") is dropped with its clause instead:
    ///   leaving out "caf" would leave out "café" and more;
    /// - an address with other letters is dropped from a list left out,
    ///   which then leaves out less.
    ///
    /// None when the server can't be asked: a text looked for that has no
    /// ASCII at all ("日本") would match anything, and a search with
    /// nothing left to ask would bring every message.
    pub fn ascii(&self) -> Option<ServerQuery> {
        fn run(s: &str) -> Option<String> {
            s.split(|c: char| !c.is_ascii() || c.is_ascii_control())
                .map(str::trim)
                .filter(|r| r.chars().any(|c| c.is_ascii_alphanumeric()))
                .max_by_key(|r| r.len())
                .map(str::to_owned)
        }
        let mut clauses = Vec::new();
        'clauses: for clause in &self.clauses {
            let mut any = Vec::new();
            for l in clause {
                let text = |s: &String, key: fn(String) -> Key| {
                    if s.is_ascii() {
                        Some(Some(key(s.clone())))
                    } else if l.negated {
                        // Dropped: the clause may hold for anything.
                        Some(None)
                    } else {
                        run(s).map(|r| Some(key(r)))
                    }
                };
                let key = match &l.key {
                    Key::Text(s) => text(s, Key::Text),
                    Key::From(s) => text(s, Key::From),
                    Key::To(s) => text(s, Key::To),
                    Key::Cc(s) => text(s, Key::Cc),
                    Key::Bcc(s) => text(s, Key::Bcc),
                    Key::Subject(s) => text(s, Key::Subject),
                    Key::Recipients(list) if list.iter().all(|a| a.is_ascii()) => {
                        Some(Some(Key::Recipients(list.clone())))
                    }
                    Key::Recipients(list) if l.negated => {
                        let list: Vec<String> =
                            list.iter().filter(|a| a.is_ascii()).cloned().collect();
                        Some((!list.is_empty()).then_some(Key::Recipients(list)))
                    }
                    // Looking for addresses the server can't be asked for.
                    Key::Recipients(_) => None,
                    k => Some(Some(k.clone())),
                };
                match key {
                    Some(Some(key)) => any.push(ServerLiteral {
                        key,
                        negated: l.negated,
                    }),
                    Some(None) => continue 'clauses,
                    None => return None,
                }
            }
            clauses.push(any);
        }
        (!clauses.is_empty()).then_some(ServerQuery { clauses })
    }

    /// The criteria of an IMAP `UID SEARCH` (RFC 3501 section 6.4.4),
    /// after `CHARSET UTF-8` when [`Self::needs_utf8`]. With `literal_plus`
    /// (RFC 7888) non-ASCII text goes as a literal that needs no
    /// continuation; otherwise as a quoted string, which servers that
    /// take UTF-8 read too.
    pub fn imap(&self, literal_plus: bool) -> String {
        let string = |s: &str| imap_string(s, literal_plus);
        let key = |k: &Key| -> String {
            match k {
                Key::Text(s) => format!("TEXT {}", string(s)),
                Key::From(s) => format!("FROM {}", string(s)),
                Key::To(s) => format!("TO {}", string(s)),
                Key::Cc(s) => format!("CC {}", string(s)),
                Key::Bcc(s) => format!("BCC {}", string(s)),
                Key::Subject(s) => format!("SUBJECT {}", string(s)),
                Key::Seen => "SEEN".into(),
                Key::Flagged => "FLAGGED".into(),
                Key::Since(t) => format!("SINCE {}", imap_date(*t)),
                Key::Before(t) => format!("BEFORE {}", imap_date(*t)),
                Key::Larger(n) => format!("LARGER {}", n.min(&u64::from(u32::MAX))),
                Key::Smaller(n) => format!("SMALLER {}", n.min(&u64::from(u32::MAX))),
                Key::Keyword(k) => format!("KEYWORD {}", imap_atom(k)),
                Key::Header(name) => format!("HEADER {name} \"\""),
                Key::Attachment => "HEADER Content-Type \"multipart/mixed\"".into(),
                Key::Recipients(list) => imap_or(
                    list.iter()
                        .flat_map(|a| [format!("TO {}", string(a)), format!("CC {}", string(a))])
                        .collect(),
                ),
                // JMAP only; an IMAP search runs in one folder.
                Key::InMailbox(_) => "ALL".into(),
            }
        };
        let literal = |l: &ServerLiteral| {
            let k = key(&l.key);
            if l.negated {
                format!("NOT ({k})")
            } else {
                k
            }
        };
        let parts: Vec<String> = self
            .clauses
            .iter()
            .map(|c| imap_or(c.iter().map(literal).collect()))
            .collect();
        let criteria = parts.join(" ");
        if self.needs_utf8() {
            format!("CHARSET UTF-8 {criteria}")
        } else {
            criteria
        }
    }

    /// The `filter` of a JMAP `Email/query` (RFC 8621 section 4.4.1).
    pub fn jmap(&self) -> Value {
        fn any(conditions: Vec<Value>, operator: &str) -> Value {
            if conditions.len() == 1 {
                conditions.into_iter().next().unwrap_or(Value::Null)
            } else {
                json!({ "operator": operator, "conditions": conditions })
            }
        }
        let key = |k: &Key| -> Value {
            match k {
                Key::Text(s) => json!({ "text": s }),
                Key::From(s) => json!({ "from": s }),
                Key::To(s) => json!({ "to": s }),
                Key::Cc(s) => json!({ "cc": s }),
                Key::Bcc(s) => json!({ "bcc": s }),
                Key::Subject(s) => json!({ "subject": s }),
                Key::Seen => json!({ "hasKeyword": "$seen" }),
                Key::Flagged => json!({ "hasKeyword": "$flagged" }),
                Key::Since(t) => json!({ "after": utc_date(*t) }),
                Key::Before(t) => json!({ "before": utc_date(*t) }),
                // JMAP's UnsignedInt stops at 2^53 - 1.
                Key::Larger(n) => json!({ "minSize": n.saturating_add(1).min(JMAP_MAX_INT) }),
                Key::Smaller(n) => json!({ "maxSize": (*n).min(JMAP_MAX_INT) }),
                Key::Keyword(k) => json!({ "hasKeyword": k }),
                Key::Header(name) => json!({ "header": [name] }),
                Key::Attachment => json!({ "hasAttachment": true }),
                Key::Recipients(list) => any(
                    list.iter()
                        .flat_map(|a| [json!({ "to": a }), json!({ "cc": a })])
                        .collect(),
                    "OR",
                ),
                Key::InMailbox(ids) => any(
                    ids.iter().map(|id| json!({ "inMailbox": id })).collect(),
                    "OR",
                ),
            }
        };
        let literal = |l: &ServerLiteral| {
            let k = key(&l.key);
            if l.negated {
                json!({ "operator": "NOT", "conditions": [k] })
            } else {
                k
            }
        };
        any(
            self.clauses
                .iter()
                .map(|c| any(c.iter().map(literal).collect(), "OR"))
                .collect(),
            "AND",
        )
    }
}

/// `OR a OR b c`, each part in parentheses.
fn imap_or(mut parts: Vec<String>) -> String {
    match parts.len() {
        0 => "ALL".into(),
        1 => parts.pop().unwrap_or_default(),
        _ => {
            let first = parts.remove(0);
            format!("OR ({first}) ({})", imap_or(parts))
        }
    }
}

/// A string for an IMAP command: quoted, or a non-synchronizing literal.
/// Line breaks and NUL can't be searched for and are left out.
fn imap_string(s: &str, literal_plus: bool) -> String {
    let clean: String = s
        .chars()
        .filter(|c| !matches!(c, '\r' | '\n' | '\0'))
        .collect();
    if !clean.is_ascii() && literal_plus {
        return format!("{{{}+}}\r\n{clean}", clean.len());
    }
    let mut out = String::with_capacity(clean.len() + 2);
    out.push('"');
    for c in clean.chars() {
        if matches!(c, '"' | '\\') {
            out.push('\\');
        }
        out.push(c);
    }
    out.push('"');
    out
}

/// A keyword as an IMAP atom: characters an atom can't hold are left out.
fn imap_atom(k: &str) -> String {
    let atom: String = k
        .chars()
        .filter(|c| {
            c.is_ascii_graphic() && !matches!(c, '(' | ')' | '{' | '%' | '*' | '"' | '\\' | ']')
        })
        .collect();
    if atom.is_empty() {
        "$none".into()
    } else {
        atom
    }
}

/// "14-Sep-2026".
fn imap_date(secs: i64) -> String {
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let (y, m, d) = civil(secs);
    let month = MONTHS.get(m.saturating_sub(1) as usize).unwrap_or(&"Jan");
    format!("{d}-{month}-{y:04}")
}

/// "2026-09-14T00:00:00Z".
fn utc_date(secs: i64) -> String {
    let (y, m, d) = civil(secs);
    let rest = secs.rem_euclid(86_400);
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}Z",
        rest / 3600,
        rest / 60 % 60,
        rest % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::Store;

    fn terms(q: &Query) -> Vec<(Term, bool)> {
        q.clauses
            .iter()
            .flat_map(|c| c.any.iter().map(|l| (l.term.clone(), l.negated)))
            .collect()
    }

    fn one(input: &str) -> Term {
        let q = Query::parse(input);
        assert_eq!(q.clauses.len(), 1, "{input}: {q:?}");
        assert_eq!(q.clauses[0].any.len(), 1, "{input}: {q:?}");
        q.clauses[0].any[0].term.clone()
    }

    fn fts(q: &Query) -> Option<String> {
        let w = q.sql(" FROM message m", &Folders::new());
        w.fts.then(|| w.args[0].clone()).map(|v| match v {
            SqlValue::Text(t) => t,
            other => panic!("{other:?}"),
        })
    }

    #[test]
    fn words_and_operators() {
        let q = Query::parse(r#"print quote from:sara is:unread account:Work after:2026-09-14"#);
        assert_eq!(q.words(), ["print", "quote"]);
        assert_eq!(q.account(), Some("Work"));
        assert_eq!(
            terms(&q),
            [
                (Term::Text("print".into()), false),
                (Term::Text("quote".into()), false),
                (Term::From("sara".into()), false),
                (Term::Unread, false),
                (Term::Account("Work".into()), false),
                (Term::After(1_789_344_000), false),
            ]
        );
        assert_eq!(
            fts(&q).unwrap(),
            r#""print"* AND "quote"* AND sender : "sara"*"#
        );
    }

    #[test]
    fn every_operator() {
        assert_eq!(one("from:sara"), Term::From("sara".into()));
        assert_eq!(one("FROM:People"), Term::People);
        assert_eq!(
            one("to:luca@example.org"),
            Term::To("luca@example.org".into())
        );
        assert_eq!(one("cc:anna"), Term::Cc("anna".into()));
        assert_eq!(one("bcc:boss"), Term::Bcc("boss".into()));
        assert_eq!(one("subject:invoice"), Term::Subject("invoice".into()));
        assert_eq!(
            one(r#"subject:"q3 report""#),
            Term::Subject("q3 report".into())
        );
        assert_eq!(one("account:Work"), Term::Account("Work".into()));
        assert_eq!(one("group:3"), Term::Group(3));
        assert_eq!(one(r#"label:"To read""#), Term::Label("To read".into()));
        assert_eq!(one("in:Inbox"), Term::Folder("Inbox".into()));
        assert_eq!(one("in:Clients/Acme"), Term::Folder("Clients/Acme".into()));
        assert_eq!(one("in:vault"), Term::Vault);
        assert_eq!(one("in:Newsletters"), Term::Newsletter);
        assert_eq!(one("is:unread"), Term::Unread);
        assert_eq!(one("is:READ"), Term::Read);
        assert_eq!(one("is:starred"), Term::Starred);
        assert_eq!(one("is:flagged"), Term::Starred);
        assert_eq!(one("has:attachment"), Term::Attachment);
        assert_eq!(one("has:files"), Term::Attachment);
        assert_eq!(one("filename:pdf"), Term::Filename("pdf".into()));
        assert_eq!(one("after:2026-10-01"), Term::After(1_790_812_800));
        assert_eq!(one("after:2026/10/01"), Term::After(1_790_812_800));
        assert_eq!(one("before:1970-01-02"), Term::Before(86_400));
        // Days a month doesn't have are text, not the next month.
        assert_eq!(
            one("before:2026-02-31"),
            Term::Text("before:2026-02-31".into())
        );
        assert_eq!(
            one("after:2026-04-31"),
            Term::Text("after:2026-04-31".into())
        );
        assert_eq!(
            one("before:2023-02-29"),
            Term::Text("before:2023-02-29".into())
        );
        assert_eq!(one("before:2024-02-29"), Term::Before(1_709_164_800));
        assert_eq!(one("larger:5M"), Term::Larger(5 << 20));
        assert_eq!(one("larger:1.5mb"), Term::Larger(1_572_864));
        assert_eq!(one("smaller:200K"), Term::Smaller(200 << 10));
        assert_eq!(one("smaller:2GiB"), Term::Smaller(2 << 30));
        assert_eq!(one("larger:300"), Term::Larger(300));
        assert_eq!(one("larger:0,5k"), Term::Larger(512));
    }

    #[test]
    fn negation_and_or() {
        let q = Query::parse("invoice -paid from:sara OR from:luca -is:read");
        assert_eq!(q.clauses.len(), 4);
        assert_eq!(
            q.clauses[2].any,
            [
                Literal {
                    term: Term::From("sara".into()),
                    negated: false
                },
                Literal {
                    term: Term::From("luca".into()),
                    negated: false
                },
            ]
        );
        assert!(q.clauses[1].any[0].negated);
        assert_eq!(q.clauses[3].any[0].term, Term::Read);
        assert!(q.clauses[3].any[0].negated);
        // Only "invoice" must be there for the people list.
        assert_eq!(q.words(), ["invoice"]);
        // A chain of ORs is one clause.
        assert_eq!(Query::parse("a OR b OR c").clauses[0].any.len(), 3);
        // Negated phrases.
        assert_eq!(
            terms(&Query::parse(r#"-"print quote""#)),
            [(Term::Text("print quote".into()), true)]
        );
        // OR alone, at the ends, twice, or in lower case.
        assert!(Query::parse("OR").is_empty());
        assert_eq!(Query::parse("OR a OR").clauses.len(), 1);
        assert_eq!(Query::parse("a OR OR b").clauses.len(), 1);
        assert_eq!(Query::parse("a or b").clauses.len(), 3);
        // A quoted "OR" is a word.
        assert_eq!(Query::parse(r#"a "OR" b"#).clauses.len(), 3);
        // Dashes: alone, doubled, inside words.
        assert!(Query::parse("-").is_empty());
        assert_eq!(
            terms(&Query::parse("--x")),
            [(Term::Text("-x".into()), true)]
        );
        assert_eq!(
            terms(&Query::parse("e-mail")),
            [(Term::Text("e-mail".into()), false)]
        );
    }

    #[test]
    fn odd_input() {
        let q = Query::parse(r#" "print quote"  from:"Sara Conti" — has:photos before:soon "#);
        assert_eq!(q.words(), ["print quote", "has:photos", "before:soon"]);
        assert_eq!(q.clauses[1].any[0].term, Term::From("Sara Conti".into()));
        assert_eq!(
            fts(&Query::parse(r#"say "hi""#)).unwrap(),
            r#""say"* AND "hi"*"#
        );
        assert_eq!(Query::parse(r#"a"b"#).words(), ["ab"]);
        assert!(Query::parse("  — ! ").is_empty());
        assert_eq!(fts(&Query::parse("is:unread")), None);
        // Unbalanced quotes run to the end.
        assert_eq!(
            Query::parse(r#"say "hello there"#).words(),
            ["say", "hello there"]
        );
        assert_eq!(
            terms(&Query::parse(r#"from:"Sara"#)),
            [(Term::From("Sara".into()), false)]
        );
        assert!(Query::parse(r#"""#).is_empty());
        assert!(Query::parse(r#""""""#).is_empty());
        // Empty values: left out, as being typed.
        for empty in [
            "from:",
            "to:",
            "in:",
            "is:",
            "larger:",
            "label:",
            "subject:\"\"",
            "from: ",
        ] {
            assert!(Query::parse(empty).is_empty(), "{empty}");
        }
        assert!(Query::parse("from:—").is_empty());
        // Unknown operators and values that don't fit are words.
        assert_eq!(Query::parse("foo:bar").words(), ["foo:bar"]);
        assert_eq!(Query::parse("is:important").words(), ["is:important"]);
        assert_eq!(Query::parse("larger:huge").words(), ["larger:huge"]);
        assert_eq!(Query::parse("larger:5X").words(), ["larger:5X"]);
        assert_eq!(
            Query::parse("after:2026-13-01").words(),
            ["after:2026-13-01"]
        );
        assert_eq!(Query::parse("group:x").words(), ["group:x"]);
        assert_eq!(Query::parse("10:30").words(), ["10:30"]);
        assert_eq!(Query::parse("https://x.org").words(), ["https://x.org"]);
        assert_eq!(Query::parse(r#""a:b""#).words(), ["a:b"]);
        // Unicode, in words and values.
        assert_eq!(Query::parse("città").words(), ["città"]);
        assert_eq!(one("from:Zoë"), Term::From("Zoë".into()));
        assert_eq!(
            one("in:Ārchīvio/2026"),
            Term::Folder("Ārchīvio/2026".into())
        );
        assert_eq!(Query::parse("日本語 メール").words(), ["日本語", "メール"]);
        assert_eq!(one("subject:😀ok"), Term::Subject("😀ok".into()));
        assert!(Query::parse("😀 🎉").is_empty());
    }

    #[test]
    fn long_input_is_cut() {
        let long = "word ".repeat(10_000);
        let q = Query::parse(&long);
        assert_eq!(q.clauses.len(), MAX_TERMS);
        let one_word = "x".repeat(100_000);
        let q = Query::parse(&one_word);
        let Term::Text(w) = &q.clauses[0].any[0].term else {
            panic!()
        };
        assert_eq!(w.chars().count(), MAX_TERM_CHARS);
        let multibyte = "é".repeat(5_000);
        assert_eq!(Query::parse(&multibyte).clauses.len(), 1);
        let ors = "a OR ".repeat(5_000);
        let q = Query::parse(&ors);
        assert_eq!(q.clauses.len(), 1);
        assert!(q.clauses[0].any.len() <= MAX_TERMS);
    }

    #[test]
    fn quotes_inside_words_are_escaped() {
        let q = Query::of([Term::Text(r#"o"k"#.into())]);
        assert_eq!(fts(&q).unwrap(), r#""o""k"*"#);
    }

    #[test]
    fn index_expression_with_or() {
        let q = Query::parse("quote OR invoice subject:march");
        assert_eq!(
            fts(&q).unwrap(),
            r#"("quote"* OR "invoice"*) AND subject : "march"*"#
        );
        // A clause with something besides words goes in the WHERE.
        let q = Query::parse("quote OR is:unread -lunch");
        assert_eq!(fts(&q), None);
        let w = q.sql(" FROM message m", &Folders::new());
        assert!(w.sql.contains("NOT (m.rowid IN"), "{}", w.sql);
        assert!(w.sql.contains("OR ((m.flags & 1) = 0)"), "{}", w.sql);
    }

    #[test]
    fn days_and_sizes() {
        assert_eq!(day("1970-01-01"), Some(0));
        assert_eq!(day("2026-10-01"), Some(1_790_812_800));
        assert_eq!(day("2026-13-01"), None);
        assert_eq!(day("0-01-01"), None);
        assert_eq!(day("99999-01-01"), None);
        assert_eq!(day("yesterday"), None);
        assert_eq!(civil(1_790_812_800), (2026, 10, 1));
        assert_eq!(civil(0), (1970, 1, 1));
        assert_eq!(civil(-86_400), (1969, 12, 31));
        assert_eq!(imap_date(1_789_344_000), "14-Sep-2026");
        assert_eq!(utc_date(1_789_344_000 + 3_723), "2026-09-14T01:02:03Z");
        assert_eq!(size("10"), Some(10));
        assert_eq!(size("1k"), Some(1024));
        assert_eq!(size("1KiB"), Some(1024));
        assert_eq!(size("k"), None);
        assert_eq!(size("1.2.3m"), None);
        assert_eq!(size("-1"), None);
        assert_eq!(size("99999999999999999999999g"), None);
    }

    fn scope_with<'a>(
        labels: &'a HashMap<String, String>,
        groups: &'a HashMap<i64, Vec<String>>,
        folder: &'a (dyn Fn(&str) -> InFolder + Send + Sync),
    ) -> Scope<'a> {
        Scope {
            account_name: "Work",
            account_email: "me@studio.it",
            labels,
            groups,
            folder,
        }
    }

    fn imap_of(input: &str) -> Option<String> {
        let labels: HashMap<String, String> = [("to read".to_owned(), "to_read".to_owned())].into();
        let groups: HashMap<i64, Vec<String>> = [(3, vec!["team@studio.it".to_owned()])].into();
        let folder = |f: &str| {
            if folder_key(f) == "archive" {
                InFolder::Yes
            } else {
                InFolder::No
            }
        };
        match Query::parse(input).for_server(&scope_with(&labels, &groups, &folder)) {
            ServerAsk::Ask(q) => Some(q.imap(false)),
            _ => None,
        }
    }

    #[test]
    fn imap_criteria() {
        assert_eq!(imap_of("quote").unwrap(), r#"TEXT "quote""#);
        assert_eq!(
            imap_of(r#"from:sara to:luca cc:anna bcc:boss subject:"q3 report""#).unwrap(),
            r#"FROM "sara" TO "luca" CC "anna" BCC "boss" SUBJECT "q3 report""#
        );
        assert_eq!(
            imap_of("is:unread is:read is:starred has:attachment in:newsletter").unwrap(),
            r#"NOT (SEEN) SEEN FLAGGED HEADER Content-Type "multipart/mixed" HEADER List-Unsubscribe """#
        );
        assert_eq!(
            imap_of("after:2026-09-14 before:2026-10-01 larger:1k smaller:2M").unwrap(),
            "SINCE 14-Sep-2026 BEFORE 1-Oct-2026 LARGER 1024 SMALLER 2097152"
        );
        assert_eq!(
            imap_of(r#"label:"To read" filename:pdf"#).unwrap(),
            r#"KEYWORD to_read TEXT "pdf""#
        );
        assert_eq!(
            imap_of("group:3 x").unwrap(),
            r#"OR (TO "team@studio.it") (CC "team@studio.it") TEXT "x""#
        );
        assert_eq!(
            imap_of("a OR b OR -c").unwrap(),
            r#"OR (TEXT "a") (OR (TEXT "b") (NOT (TEXT "c")))"#
        );
        assert_eq!(
            imap_of(r#"say \"hi""#).unwrap(),
            r#"TEXT "say" TEXT "\\hi""#
        );
        // Account, folder and label answered here.
        assert_eq!(imap_of("account:work x").unwrap(), r#"TEXT "x""#);
        assert_eq!(imap_of("account:home x"), None);
        assert_eq!(imap_of("in:archive x").unwrap(), r#"TEXT "x""#);
        assert_eq!(imap_of("in:inbox x"), None);
        assert_eq!(imap_of("-in:archive x"), None);
        assert_eq!(imap_of("in:inbox OR y").unwrap(), r#"TEXT "y""#);
        assert_eq!(imap_of("label:nope x"), None);
        assert_eq!(imap_of("group:9 x"), None);
        // Filters only: nothing to ask; this device's own terms: not asked.
        assert_eq!(imap_of("account:work in:archive"), None);
        assert_eq!(imap_of("in:vault x"), None);
        assert_eq!(imap_of("from:people x"), None);
        // UTF-8 and quotes.
        assert_eq!(imap_of("città").unwrap(), "CHARSET UTF-8 TEXT \"città\"");
        assert_eq!(imap_of(r#"o\k"#).unwrap(), r#"TEXT "o\\k""#);
    }

    #[test]
    fn imap_literals_and_ascii_fallback() {
        let labels = HashMap::new();
        let groups = HashMap::new();
        let folder = |_: &str| InFolder::No;
        let ServerAsk::Ask(q) =
            Query::parse("café from:Zoë 日本").for_server(&scope_with(&labels, &groups, &folder))
        else {
            panic!()
        };
        assert!(q.needs_utf8());
        assert_eq!(
            q.imap(true),
            "CHARSET UTF-8 TEXT {5+}\r\ncafé FROM {4+}\r\nZoë TEXT {6+}\r\n日本"
        );
        // A text looked for with no ASCII at all can't be asked for: the
        // rest alone would bring far more than was looked for.
        assert_eq!(q.ascii(), None);
        let ascii_of = |s: &str| {
            let ServerAsk::Ask(q) =
                Query::parse(s).for_server(&scope_with(&labels, &groups, &folder))
            else {
                panic!("{s}")
            };
            q.ascii().map(|a| a.imap(true))
        };
        assert_eq!(
            ascii_of("café from:Zoë").as_deref(),
            Some(r#"TEXT "caf" FROM "Zo""#)
        );
        assert_eq!(ascii_of("日本"), None);
        assert_eq!(ascii_of("日本 is:unread"), None);
        assert_eq!(ascii_of("日本 OR invoice"), None);
        // A text left out is dropped, not cut: leaving out "caf" would
        // leave out more than "café".
        assert_eq!(ascii_of("-café is:unread").as_deref(), Some("NOT (SEEN)"));
        assert_eq!(ascii_of("-café"), None);
        assert_eq!(
            ascii_of("invoice -from:Zoë").as_deref(),
            Some(r#"TEXT "invoice""#)
        );
        assert_eq!(ascii_of("invoice OR -subject:café"), None);
        assert_eq!(
            ascii_of("is:unread (invoice OR -subject:café)").as_deref(),
            Some("NOT (SEEN)")
        );
        // Line breaks never reach the server.
        let q = Query::of([Term::Text("a\r\nLOGOUT".into())]);
        let ServerAsk::Ask(q) = q.for_server(&scope_with(&labels, &groups, &folder)) else {
            panic!()
        };
        assert_eq!(q.imap(false), r#"TEXT "aLOGOUT""#);
    }

    #[test]
    fn jmap_filter() {
        let labels: HashMap<String, String> = [("to read".to_owned(), "to_read".to_owned())].into();
        let groups = HashMap::new();
        let folder = |f: &str| {
            if folder_key(f) == "archive" {
                InFolder::Ids(vec!["mb-archive".into()])
            } else {
                InFolder::Ids(vec![])
            }
        };
        let scope = scope_with(&labels, &groups, &folder);
        let ask = |s: &str| match Query::parse(s).for_server(&scope) {
            ServerAsk::Ask(q) => q.jmap(),
            other => panic!("{other:?}"),
        };
        assert_eq!(ask("quote"), json!({ "text": "quote" }));
        assert_eq!(
            ask("from:sara -is:read"),
            json!({ "operator": "AND", "conditions": [
                { "from": "sara" },
                { "operator": "NOT", "conditions": [{ "hasKeyword": "$seen" }] },
            ]})
        );
        assert_eq!(
            ask("is:unread"),
            json!({ "operator": "NOT", "conditions": [{ "hasKeyword": "$seen" }] })
        );
        assert_eq!(
            ask("a OR in:archive"),
            json!({ "operator": "OR", "conditions": [
                { "text": "a" }, { "inMailbox": "mb-archive" },
            ]})
        );
        assert_eq!(
            ask(
                r#"after:2026-09-14 larger:1k smaller:2k has:attachment label:"to read" in:newsletter"#
            ),
            json!({ "operator": "AND", "conditions": [
                { "after": "2026-09-14T00:00:00Z" },
                { "minSize": 1025 },
                { "maxSize": 2048 },
                { "hasAttachment": true },
                { "hasKeyword": "to_read" },
                { "header": ["List-Unsubscribe"] },
            ]})
        );
        // Sizes past what JMAP's numbers hold are clamped.
        assert_eq!(
            ask("larger:99999999G smaller:99999999G"),
            json!({ "operator": "AND", "conditions": [
                { "minSize": 9_007_199_254_740_991_u64 },
                { "maxSize": 9_007_199_254_740_991_u64 },
            ]})
        );
        assert_eq!(
            Query::parse("in:nowhere x").for_server(&scope),
            ServerAsk::Nothing
        );
        assert_eq!(
            Query::parse("in:vault x").for_server(&scope),
            ServerAsk::Unsupported
        );
    }

    /// A tiny random generator, so the property test needs no crate.
    struct Rng(u64);

    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            self.0
        }

        fn pick<'a>(&mut self, from: &[&'a str]) -> &'a str {
            from[(self.next() % from.len() as u64) as usize]
        }
    }

    fn random_query(rng: &mut Rng) -> String {
        const PIECES: &[&str] = &[
            "a",
            "quote",
            "\"",
            "\"",
            ":",
            "-",
            "--",
            " ",
            " ",
            "  ",
            "OR",
            "or",
            "from:",
            "to:",
            "cc:",
            "bcc:",
            "subject:",
            "in:",
            "is:",
            "has:",
            "label:",
            "account:",
            "group:",
            "after:",
            "before:",
            "larger:",
            "smaller:",
            "filename:",
            "unread",
            "read",
            "starred",
            "attachment",
            "vault",
            "people",
            "inbox",
            "Clients/Acme",
            "2026-09-14",
            "2026/13/40",
            "5M",
            "1.5k",
            "-1",
            "99999999999999999999999",
            "é",
            "città",
            "日本",
            "😀",
            "\u{0}",
            "\r\n",
            "\t",
            "\\",
            "'",
            "%",
            "_",
            "*",
            "(",
            ")",
            "NEAR",
            "AND",
            "NOT",
            "^",
            "{",
            "}",
            "+",
            "\u{2}",
            "\u{200b}",
            "ß",
            "İ",
            "ﬃ",
            "²",
            "Ⅻ",
            "\u{301}",
            "ǅ",
        ];
        let n = rng.next() % 24;
        (0..n).map(|_| rng.pick(PIECES)).collect()
    }

    /// Whatever is typed, parsing, the local search and the server
    /// translations neither panic nor fail.
    #[test]
    fn never_panics_never_fails() {
        let store = Store::open_in_memory().unwrap();
        store.rebuild_search_index().unwrap();
        let labels: HashMap<String, String> = [("a".to_owned(), "a".to_owned())].into();
        let groups: HashMap<i64, Vec<String>> = [(1, vec!["é@x.it".to_owned()])].into();
        let yes = |_: &str| InFolder::Yes;
        let ids = |_: &str| InFolder::Ids(vec!["x".into()]);
        let mut rng = Rng(0x9e37_79b9_7f4a_7c15);
        for round in 0..20_000 {
            let input = random_query(&mut rng);
            let q = Query::parse(&input);
            assert!(terms(&q).len() <= MAX_TERMS);
            for clause in &q.clauses {
                assert!(!clause.any.is_empty(), "{input:?}");
            }
            for folder in [&yes as &(dyn Fn(&str) -> InFolder + Send + Sync), &ids] {
                if let ServerAsk::Ask(s) = q.for_server(&scope_with(&labels, &groups, folder)) {
                    let criteria = s.imap(round % 2 == 0);
                    assert!(!criteria.contains('\n') || criteria.contains("+}\r\n"));
                    let _ = s.jmap();
                    let _ = s.ascii().map(|a| a.imap(false));
                }
            }
            // The database takes every query; a few thousand are enough.
            if round % 5 == 0 {
                store
                    .search(&q, 5)
                    .unwrap_or_else(|e| panic!("{input:?}: {e}"));
                store
                    .search_files(&q, 5)
                    .unwrap_or_else(|e| panic!("{input:?}: {e}"));
                store
                    .search_people(&q, 5)
                    .unwrap_or_else(|e| panic!("{input:?}: {e}"));
            }
        }
    }
}
