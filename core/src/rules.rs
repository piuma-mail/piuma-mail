//! Rules: "When the sender contains @studio.it, move to Worksite". They
//! run on this device as new mail lands in the inbox, through the same
//! queue as changes made offline, so the server gets them on the next
//! round and nothing is lost without a connection.

use std::collections::HashSet;
use std::sync::Mutex;

use crate::imap::{FolderRole, SyncReport};
use crate::model::{AccountId, MessageSummary};
use crate::pending::Change;
use crate::store::{FrequentMove, Result, Store};

/// What a rule looks at.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Field {
    /// The sender's name and address.
    Sender,
    Subject,
    /// Who it went to.
    Recipient,
    /// The text: its first words as it arrives, all of it once here.
    Body,
}

/// How it compares, ignoring case.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Op {
    Contains,
    Is,
    StartsWith,
    NotContains,
}

/// What it does with a match.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Into one of the account's own folders, by its server name.
    MoveTo(String),
    Archive,
    MarkRead,
    /// Puts a label on, by its keyword. Unlike the others it doesn't end
    /// the search: the mail can still be moved by a later rule.
    Label(String),
    /// "Move to Vault": out of the inbox into Archive, and always a card
    /// in the Vault, followed there by its Message-ID.
    Vault,
}

/// One rule, as the person wrote it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rule {
    pub id: i64,
    /// The account whose mail it sorts; `None` for every account. A move
    /// is always to one account's folder, so it has one.
    pub account: Option<AccountId>,
    pub field: Field,
    pub op: Op,
    pub value: String,
    pub action: Action,
    pub enabled: bool,
    /// When it last sorted something, in Unix seconds.
    pub last_run: Option<i64>,
    /// How many emails it has sorted.
    pub matched: u32,
}

impl Field {
    pub fn tag(self) -> &'static str {
        match self {
            Field::Sender => "sender",
            Field::Subject => "subject",
            Field::Recipient => "recipient",
            Field::Body => "body",
        }
    }

    pub fn from_tag(tag: &str) -> Option<Self> {
        [Field::Sender, Field::Subject, Field::Recipient, Field::Body]
            .into_iter()
            .find(|f| f.tag() == tag)
    }
}

impl Op {
    pub fn tag(self) -> &'static str {
        match self {
            Op::Contains => "contains",
            Op::Is => "is",
            Op::StartsWith => "starts",
            Op::NotContains => "not_contains",
        }
    }

    pub fn from_tag(tag: &str) -> Option<Self> {
        [Op::Contains, Op::Is, Op::StartsWith, Op::NotContains]
            .into_iter()
            .find(|o| o.tag() == tag)
    }
}

impl Action {
    pub fn tag(&self) -> &'static str {
        match self {
            Action::MoveTo(_) => "move",
            Action::Archive => "archive",
            Action::MarkRead => "read",
            Action::Label(_) => "label",
            Action::Vault => "vault",
        }
    }

    pub fn target(&self) -> &str {
        match self {
            Action::MoveTo(mailbox) | Action::Label(mailbox) => mailbox,
            _ => "",
        }
    }

    pub fn from_tag(tag: &str, target: String) -> Option<Self> {
        Some(match tag {
            "move" if !target.is_empty() => Action::MoveTo(target),
            "archive" => Action::Archive,
            "read" => Action::MarkRead,
            "label" if !target.is_empty() => Action::Label(target),
            "vault" => Action::Vault,
            _ => return None,
        })
    }
}

impl Rule {
    /// Whether `m` is mail this rule sorts, its body read from its first
    /// words.
    pub fn matches(&self, m: &MessageSummary) -> bool {
        self.matches_text(m, &m.preview)
    }

    /// Whether `m` is mail this rule sorts, with the whole text of its
    /// body when it is here.
    pub fn matches_in(&self, store: &Store, m: &MessageSummary) -> Result<bool> {
        if self.field != Field::Body {
            return Ok(self.matches(m));
        }
        let text = store.body(m.account, &m.mailbox, m.uid)?;
        Ok(self.matches_text(m, text.as_deref().unwrap_or(&m.preview)))
    }

    fn matches_text(&self, m: &MessageSummary, body: &str) -> bool {
        if self.account.is_some_and(|a| a != m.account) {
            return false;
        }
        let needle = self.value.trim().to_lowercase();
        if needle.is_empty() {
            return false;
        }
        let haystacks: Vec<String> = match self.field {
            Field::Sender => vec![m.from_email.to_lowercase(), m.from_name.to_lowercase()],
            Field::Subject => vec![m.subject.to_lowercase()],
            Field::Recipient => m.to.split(',').map(|t| t.trim().to_lowercase()).collect(),
            Field::Body => vec![body.to_lowercase()],
        };
        let hit = |h: &String| match self.op {
            Op::Contains | Op::NotContains => h.contains(&needle),
            Op::Is => *h == needle,
            Op::StartsWith => h.starts_with(&needle),
        };
        let any = haystacks.iter().any(hit);
        if self.op == Op::NotContains {
            !any
        } else {
            any
        }
    }

    /// The change that does what the rule says to `m`, if it still needs
    /// doing.
    pub fn change_for(&self, m: &MessageSummary) -> Option<Change> {
        match &self.action {
            Action::MoveTo(mailbox) if *mailbox != m.mailbox => {
                Some(Change::MoveTo(mailbox.clone()))
            }
            Action::MoveTo(_) => None,
            Action::Archive | Action::Vault => Some(Change::Move(FolderRole::Archive)),
            Action::MarkRead if !m.flags.seen => Some(Change::Seen(true)),
            Action::MarkRead => None,
            Action::Label(keyword) => Some(Change::Label {
                keyword: keyword.clone(),
                add: true,
            }),
        }
    }

    /// The label this rule puts on, if it is a Label rule.
    fn label(&self) -> Option<&str> {
        match &self.action {
            Action::Label(keyword) => Some(keyword),
            _ => None,
        }
    }

    /// Whether `m` still needs what this rule does: a Label rule has
    /// nothing to do on mail that has the label.
    fn needed_on(&self, store: &Store, m: &MessageSummary) -> Result<bool> {
        Ok(match self.label() {
            Some(keyword) => !store
                .message_labels(m.account, &m.mailbox, m.uid)?
                .iter()
                .any(|k| k == keyword),
            None => self.change_for(m).is_some(),
        })
    }
}

/// The mailbox rules sort.
pub const INBOX: &str = "INBOX";

/// The setting that says up to when an account's inbox has been sorted.
fn sorted_key(account: AccountId) -> String {
    format!("rules.sorted.{}", account.0)
}

/// Hand moves that make a rule worth suggesting: this many to one
/// folder in the last [`SUGGEST_DAYS`].
pub const SUGGEST_MOVES: u32 = 5;
pub const SUGGEST_DAYS: i64 = 30;

/// The setting that keeps the suggestions answered "Not now", one
/// "account sender target" per line.
const NOT_NOW: &str = "rules.not_now";

/// "You often move emails from Ferrovia Rapida to Travel. Create a rule?":
/// the sender moved by hand most often to one folder lately, unless a
/// rule on the sender already sorts their mail or the person said Not
/// now to it.
pub fn suggestion(store: &Store, now: i64) -> Result<Option<FrequentMove>> {
    let rules = store.rules()?;
    let not_now = store.setting(NOT_NOW)?.unwrap_or_default();
    let moves = store.frequent_moves(now - SUGGEST_DAYS * 86_400, SUGGEST_MOVES)?;
    Ok(moves.into_iter().find(|m| {
        let covered = rules.iter().any(|r| {
            r.field == Field::Sender
                && r.op != Op::NotContains
                && r.account.is_none_or(|a| a == m.account)
                && !r.value.trim().is_empty()
                && m.sender.contains(&r.value.trim().to_lowercase())
        });
        !covered && !not_now.lines().any(|l| l == not_now_key(m))
    }))
}

/// Not now: the same suggestion doesn't come back.
pub fn dismiss_suggestion(store: &Store, m: &FrequentMove) -> Result<()> {
    let mut not_now = store.setting(NOT_NOW)?.unwrap_or_default();
    if !not_now.is_empty() {
        not_now.push('\n');
    }
    not_now.push_str(&not_now_key(m));
    store.set_setting(NOT_NOW, &not_now)
}

fn not_now_key(m: &FrequentMove) -> String {
    format!("{} {} {}", m.account.0, m.sender, m.target)
}

/// Sorts the inbox mail of `account` that arrived since the last time:
/// mail from a blocked sender goes to Trash, every Label rule that
/// matches puts its label on, then the first other rule that matches
/// wins. Labelled mail stays in the inbox and still notifies. The changes wait in the queue for the
/// server; moved mail is hidden here at once and read mail shows read.
/// Returns the messages sorted, by (mailbox, uid), so they make no
/// notification.
pub fn apply(store: &Mutex<Store>, account: AccountId) -> Result<HashSet<(String, u32)>> {
    let store = store.lock().unwrap_or_else(|e| e.into_inner());
    let mut sorted = HashSet::new();
    let key = sorted_key(account);
    let since = store.setting(&key)?.and_then(|v| v.parse::<i64>().ok());
    let newest = store.newest_received(account, INBOX)?;
    let Some(since) = since else {
        // The first time: what is already here stays as it is.
        store.set_setting(&key, &newest.unwrap_or_default().to_string())?;
        return Ok(sorted);
    };
    if newest.is_none_or(|n| n <= since) {
        return Ok(sorted);
    }
    let rules: Vec<Rule> = store
        .rules()?
        .into_iter()
        .filter(|r| r.enabled && r.account.is_none_or(|a| a == account))
        .collect();
    let arrived = store.received_since(account, INBOX, since)?;
    let now = crate::pending::now();
    for m in &arrived {
        let change = if store.is_blocked(&m.from_email)? {
            Change::Move(FolderRole::Trash)
        } else {
            let mut found = None;
            for r in &rules {
                if !r.matches_in(&store, m)? {
                    continue;
                }
                if let Some(keyword) = r.label() {
                    if r.needed_on(&store, m)? {
                        store.label_message(account, &m.mailbox, m.uid, keyword, true)?;
                        store.rule_ran(r.id, 1, now)?;
                    }
                    continue;
                }
                found = Some(r);
                break;
            }
            let Some(rule) = found else {
                continue;
            };
            let Some(change) = rule.change_for(m) else {
                continue;
            };
            if rule.action == Action::Vault
                && !store.pin_to_vault(account, &m.mailbox, m.uid, now)?
            {
                // Without a Message-ID the card couldn't follow it to
                // Archive: it stays in the inbox.
                continue;
            }
            store.rule_ran(rule.id, 1, now)?;
            change
        };
        do_locally(&store, m, &change)?;
        store.queue_change(account, &m.mailbox, m.uid, change)?;
        sorted.insert((m.mailbox.clone(), m.uid));
    }
    let last = arrived.iter().map(|m| m.received_at).max().unwrap_or(since);
    store.set_setting(&key, &last.max(since).to_string())?;
    Ok(sorted)
}

/// Sorts what a sync round brought, after it: mail a rule moved or read
/// makes no notification. Returns whether anything waits for the server.
pub fn after_sync(
    store: &Mutex<Store>,
    account: AccountId,
    report: &mut SyncReport,
) -> Result<bool> {
    let sorted = apply(store, account)?;
    report
        .arrived
        .retain(|a| !sorted.contains(&(a.summary.mailbox.clone(), a.summary.uid)));
    Ok(!sorted.is_empty())
}

/// What the person sees before the server hears of it.
fn do_locally(store: &Store, m: &MessageSummary, change: &Change) -> Result<()> {
    match change {
        Change::Seen(seen) => store.set_seen(m.account, &m.mailbox, m.uid, *seen),
        _ => store.set_hidden(m.account, &m.mailbox, m.uid, true),
    }
}

/// The inbox mail `rule` would sort if it ran on what is already here,
/// newest first, at most `limit`.
pub fn existing(store: &Store, rule: &Rule, limit: usize) -> Result<Vec<MessageSummary>> {
    let mut out = Vec::new();
    for m in store.inbox_all(INBOX)? {
        if rule.needed_on(store, &m)? && rule.matches_in(store, &m)? {
            out.push(m);
            if out.len() >= limit {
                break;
            }
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Flags;

    fn mail(from: &str, subject: &str, to: &str) -> MessageSummary {
        MessageSummary {
            account: AccountId(1),
            mailbox: INBOX.into(),
            uid: 1,
            from_name: "Luca Bianchi".into(),
            from_email: from.into(),
            to: to.into(),
            subject: subject.into(),
            preview: String::new(),
            received_at: 0,
            flags: Flags::default(),
            reply: Default::default(),
            list: Default::default(),
        }
    }

    fn rule(field: Field, op: Op, value: &str, action: Action) -> Rule {
        Rule {
            id: 1,
            account: None,
            field,
            op,
            value: value.into(),
            action,
            enabled: true,
            last_run: None,
            matched: 0,
        }
    }

    #[test]
    fn move_to_vault_archives_and_reads_back() {
        let r = rule(Field::Subject, Op::Contains, "hi", Action::Vault);
        assert_eq!(
            r.change_for(&mail("a@b.it", "hi", "")),
            Some(Change::Move(FolderRole::Archive))
        );
        assert_eq!(
            Action::from_tag(Action::Vault.tag(), String::new()),
            Some(Action::Vault)
        );
    }

    #[test]
    fn sentences_match_ignoring_case() {
        let m = mail(
            "luca@Ferramenta.it",
            "Invoice no. 214",
            "Matteo, sara@studio.it",
        );
        let by = |field, op, value: &str| rule(field, op, value, Action::Archive).matches(&m);
        assert!(by(Field::Sender, Op::Contains, "@ferramenta.it"));
        assert!(by(Field::Sender, Op::Contains, "bianchi"));
        assert!(by(Field::Sender, Op::Is, "luca@ferramenta.it"));
        assert!(!by(Field::Sender, Op::Is, "luca"));
        assert!(by(Field::Subject, Op::StartsWith, "invoice"));
        assert!(!by(Field::Subject, Op::StartsWith, "no."));
        assert!(by(Field::Subject, Op::NotContains, "quote"));
        assert!(!by(Field::Subject, Op::NotContains, "INVOICE"));
        assert!(by(Field::Recipient, Op::Is, "sara@studio.it"));
        assert!(!by(Field::Subject, Op::Contains, "  "));
    }

    #[test]
    fn the_body_is_read_from_its_first_words() {
        let mut m = mail("a@b.it", "Hi", "");
        m.preview = "The worksite on Via Roma opens Monday".into();
        let r = rule(Field::Body, Op::Contains, "via roma", Action::Archive);
        assert!(r.matches(&m));
        assert!(!rule(Field::Body, Op::Contains, "invoice", Action::Archive).matches(&m));
        assert_eq!(Field::from_tag("body"), Some(Field::Body));
    }

    #[test]
    fn a_rule_for_one_account_leaves_the_others() {
        let m = mail("a@b.it", "Hi", "");
        let mut r = rule(Field::Subject, Op::Contains, "hi", Action::Archive);
        r.account = Some(AccountId(2));
        assert!(!r.matches(&m));
        r.account = Some(AccountId(1));
        assert!(r.matches(&m));
    }

    #[test]
    fn read_mail_needs_no_mark_as_read() {
        let mut m = mail("a@b.it", "Hi", "");
        let r = rule(Field::Subject, Op::Contains, "hi", Action::MarkRead);
        assert_eq!(r.change_for(&m), Some(Change::Seen(true)));
        m.flags.seen = true;
        assert_eq!(r.change_for(&m), None);
    }
}
