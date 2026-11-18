//! How the devices of a sync space merge what they hold, row by row, with
//! no transport: the IMAP folder today, a self-hosted companion later.
//!
//! Every synced row (an account, a signature, a rule, a label, a synced
//! setting...) has a global id, the same on every device, and a [Stamp]:
//! a hybrid logical clock (milliseconds, a counter, the device's id). Two
//! devices that change different rows both keep their change; on the same
//! row the larger stamp wins, the same way on every device. A removed row
//! stays as a tombstone until every linked device has seen it (see
//! [horizon]), so a removal is never inferred from a row being absent.
//!
//! Stamps further ahead of a device's clock than [MAX_SKEW] are brought
//! back ([clamp]). Who may write, and which copies are taken, is
//! [crate::space_trust]'s.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

/// The space's format: how the content is laid out. A device never writes
/// a format it doesn't know, and old builds (format 1) don't read this one.
pub const FORMAT: u32 = 2;

/// The synced tables and columns this build knows ([SYNCED]). Counted up
/// when they change: a device reads a space of a newer schema (what it
/// understands of it) but never writes one.
pub const SCHEMA: u32 = 1;

/// The pseudo-table of passwords, by the global id of the account or the
/// connected calendar they belong to. Never kept in the local database:
/// [Local] keeps a keyed digest in their place.
pub const SECRETS: &str = "secret";

/// How far ahead of this device's clock a stamp may be, in milliseconds:
/// later ones are brought back to it, so a device whose clock runs ahead
/// can't win every write from then on.
pub const MAX_SKEW: i64 = 10 * 60 * 1000;

/// Tombstones are kept at least this long, in milliseconds, and until
/// every linked device has been seen since.
pub const TOMBSTONE_MIN: i64 = 30 * 86_400 * 1000;
/// ... but no longer than this, so a device left in a drawer doesn't keep
/// them forever.
pub const TOMBSTONE_MAX: i64 = 365 * 86_400 * 1000;

/// Milliseconds since 1970, by this device's clock.
pub fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as i64)
}

/// When a write happened: a hybrid logical clock. Ordered by time, then
/// counter, then device id, so two devices always agree on which is later.
#[derive(Clone, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct Stamp {
    /// Milliseconds since 1970, as the writing device's clock said, or
    /// later when it had already seen a later stamp.
    pub t: i64,
    pub c: u32,
    pub d: String,
}

impl std::fmt::Debug for Stamp {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}.{}", self.t, self.c, self.d)
    }
}

impl Stamp {
    /// The next stamp of `device`, after `last` and every stamp it saw.
    pub fn next(last: &Stamp, device: &str, now_ms: i64) -> Stamp {
        if now_ms > last.t {
            Stamp {
                t: now_ms,
                c: 0,
                d: device.to_owned(),
            }
        } else {
            Stamp {
                t: last.t,
                c: last.c.saturating_add(1),
                d: device.to_owned(),
            }
        }
    }
}

/// One synced row: its stamp, whether it was removed, and its values,
/// references to other rows by their global id. Values this build doesn't
/// know are kept as they came.
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Row {
    pub s: Stamp,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub del: bool,
    #[serde(default, skip_serializing_if = "serde_json::Map::is_empty")]
    pub v: serde_json::Map<String, Value>,
}

impl std::fmt::Debug for Row {
    // Values can be passwords: never printed.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Row({:?}{}, {} values)",
            self.s,
            if self.del { ", removed" } else { "" },
            self.v.len()
        )
    }
}

impl Row {
    /// Whether `self` is the later write of the two. Equal stamps (the
    /// same write seen twice, or a bug) fall back to the content, so every
    /// device still picks the same one.
    pub fn beats(&self, other: &Row) -> bool {
        match self.s.cmp(&other.s) {
            std::cmp::Ordering::Greater => true,
            std::cmp::Ordering::Less => false,
            std::cmp::Ordering::Equal => {
                (self.del, canonical(&self.v)) > (other.del, canonical(&other.v))
            }
        }
    }

    pub fn tombstone(s: Stamp) -> Row {
        Row {
            s,
            del: true,
            v: serde_json::Map::new(),
        }
    }
}

fn canonical(v: &serde_json::Map<String, Value>) -> String {
    // serde_json's map is ordered by key here (no preserve_order feature).
    serde_json::to_string(v).unwrap_or_default()
}

/// Rows by global id.
pub type Table = BTreeMap<String, Row>;
/// Tables by name.
pub type Tables = BTreeMap<String, Table>;

/// Merges `other` into `into`, row by row. Returns the rows `other` won:
/// those that changed in `into`.
///
/// Columns are only ever added, and a device writes every column it knows,
/// so a column missing from the later write was unknown to its writer: it
/// is kept from the earlier one. An older build that edits a row this way
/// never drops what a newer one put there.
pub fn merge(into: &mut Tables, other: &Tables) -> BTreeSet<(String, String)> {
    let mut won = BTreeSet::new();
    for (name, rows) in other {
        let table = into.entry(name.clone()).or_default();
        let union = name != SECRETS;
        for (gid, row) in rows {
            match table.get_mut(gid) {
                None => {
                    table.insert(gid.clone(), row.clone());
                    won.insert((name.clone(), gid.clone()));
                }
                Some(mine) if row.beats(mine) => {
                    let mut row = row.clone();
                    if union && !row.del && !mine.del {
                        for (c, v) in &mine.v {
                            row.v.entry(c.clone()).or_insert_with(|| v.clone());
                        }
                    }
                    *mine = row;
                    won.insert((name.clone(), gid.clone()));
                }
                Some(mine) => {
                    if union && !row.del && !mine.del {
                        for (c, v) in &row.v {
                            mine.v.entry(c.clone()).or_insert_with(|| v.clone());
                        }
                    }
                }
            }
        }
    }
    won
}

/// The stamp time before which tombstones can go: every linked device was
/// seen after it, and it is at least [TOMBSTONE_MIN] old. `last_seen` in
/// seconds, as devices record it.
pub fn horizon(last_seen: impl IntoIterator<Item = i64>, now_ms: i64) -> i64 {
    let oldest = last_seen
        .into_iter()
        .map(|s| s.saturating_mul(1000))
        .min()
        .unwrap_or(now_ms);
    oldest
        .min(now_ms - TOMBSTONE_MIN)
        .max(now_ms - TOMBSTONE_MAX)
}

/// Drops tombstones older than `horizon`, and passwords whose account or
/// calendar is gone.
pub fn compact(tables: &mut Tables, horizon: i64) {
    for rows in tables.values_mut() {
        rows.retain(|_, r| !(r.del && r.s.t < horizon));
    }
    let live = |gid: &str| {
        tables
            .iter()
            .filter(|(name, _)| name.as_str() != SECRETS)
            .any(|(_, rows)| rows.get(gid).is_some_and(|r| !r.del))
    };
    let orphans: Vec<String> = tables
        .get(SECRETS)
        .into_iter()
        .flatten()
        .filter(|(gid, r)| !r.del && !live(gid))
        .map(|(gid, _)| gid.clone())
        .collect();
    if let Some(secrets) = tables.get_mut(SECRETS) {
        for gid in orphans {
            secrets.remove(&gid);
        }
    }
}

/// Whether two sets of tables hold the same rows.
pub fn same(a: &Tables, b: &Tables) -> bool {
    let non_empty = |t: &Tables| -> Vec<(String, String)> {
        t.iter()
            .flat_map(|(n, rows)| {
                rows.iter().map(move |(g, r)| {
                    (
                        format!("{n}/{g}"),
                        format!("{:?}{}{}", r.s, r.del, canonical(&r.v)),
                    )
                })
            })
            .collect()
    };
    non_empty(a) == non_empty(b)
}

// ---- What is synced ------------------------------------------------------

/// How a synced table's rows get their global id.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Key {
    /// A random id, kept in `space_map` next to the local one.
    Mapped,
    /// Made from these columns (references by global id, addresses in
    /// lower case): the same row made on two devices is one row.
    Natural(&'static [&'static str]),
}

/// One synced table: how its rows are named, which columns point at other
/// synced rows, and which columns stay on the device.
#[derive(Debug, Clone, Copy)]
pub struct Spec {
    pub table: &'static str,
    pub key: Key,
    /// (column, table it points at).
    pub refs: &'static [(&'static str, &'static str)],
    /// Columns that never travel: the local id and what a device did.
    pub local: &'static [&'static str],
}

/// The synced tables, each after the tables it points at.
pub const SYNCED: &[Spec] = &[
    Spec {
        table: "account",
        key: Key::Natural(&["email"]),
        refs: &[],
        local: &["id"],
    },
    Spec {
        table: "signature",
        key: Key::Mapped,
        refs: &[("account", "account")],
        local: &["id"],
    },
    Spec {
        table: "message_template",
        key: Key::Mapped,
        refs: &[],
        // When a template was used last orders the "/" menu on the device.
        local: &["id", "used_at"],
    },
    Spec {
        table: "address_group",
        key: Key::Mapped,
        refs: &[("signature", "signature")],
        local: &["id"],
    },
    Spec {
        table: "group_address",
        key: Key::Natural(&["email"]),
        refs: &[("grp", "address_group"), ("account", "account")],
        local: &[],
    },
    Spec {
        table: "account_alias",
        key: Key::Natural(&["account", "email"]),
        refs: &[("account", "account")],
        local: &[],
    },
    Spec {
        table: "rule",
        key: Key::Mapped,
        refs: &[("account", "account")],
        local: &["id", "last_run", "matched"],
    },
    Spec {
        table: "calendar_source",
        key: Key::Mapped,
        refs: &[("account", "account")],
        local: &["id", "synced"],
    },
    Spec {
        table: "calendar",
        key: Key::Natural(&["source", "url"]),
        refs: &[("source", "calendar_source")],
        local: &["id"],
    },
    Spec {
        table: "label",
        key: Key::Natural(&["keyword"]),
        refs: &[],
        local: &["id"],
    },
    Spec {
        table: "setting",
        key: Key::Natural(&["key"]),
        refs: &[],
        local: &[],
    },
];

pub fn spec(table: &str) -> Option<&'static Spec> {
    SYNCED.iter().find(|s| s.table == table)
}

fn hash_id(parts: &[&str]) -> String {
    let mut h = Sha256::new();
    for p in parts {
        h.update((p.len() as u64).to_le_bytes());
        h.update(p.as_bytes());
    }
    h.finalize()[..12]
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// A row's global id from its natural key, with references already
/// global; None when a key column is missing.
pub fn natural_id(spec: &Spec, values: &serde_json::Map<String, Value>) -> Option<String> {
    let Key::Natural(cols) = spec.key else {
        return None;
    };
    let mut parts = vec![spec.table.to_owned()];
    for c in cols {
        let v = values.get(*c)?;
        let s = match v {
            Value::String(s) if *c == "email" => s.trim().to_lowercase(),
            Value::String(s) => s.clone(),
            Value::Null => return None,
            other => other.to_string(),
        };
        parts.push(s);
    }
    let refs: Vec<&str> = parts.iter().map(String::as_str).collect();
    Some(hash_id(&refs))
}

/// An account's global id: from its address, so the same mailbox added on
/// two devices is one account.
pub fn account_id(email: &str) -> String {
    let mut v = serde_json::Map::new();
    v.insert("email".into(), email.into());
    natural_id(spec("account").expect("account is synced"), &v).expect("email given")
}

/// A random global id, for [Key::Mapped] rows.
pub fn new_id() -> String {
    let mut b = [0u8; 12];
    getrandom::fill(&mut b).expect("the system has randomness");
    b.iter().map(|b| format!("{b:02x}")).collect()
}

/// The global id a row of the old format (one whole content, local ids)
/// gets: the same on every device that took that content, where the rows
/// kept the space's ids.
pub fn v1_id(table: &str, id: i64) -> String {
    hash_id(&["v1", table, &id.to_string()])
}

// ---- Settings ------------------------------------------------------------

/// Settings that stay on their device: hints, searches, the space's own
/// bookkeeping, what ran here, per-device notices and draft state.
const LOCAL_SETTINGS: &[&str] = &[
    "hint.",
    "search.",
    "space.",
    "nightly.",
    "rules.sorted.",
    "rules.not_now",
    "sign_in.",
    "labels.local.",
    "draft.",
    "calendars.default",
    "storage.",
    "account_restored.",
];

/// Settings that name an account and travel, by the account's global id:
/// (prefix, suffix) around the id. `account.<id>.oauth` names the provider
/// an account signs in with (no token: those stay in each device's
/// keychain), so another device asks to sign in with that provider rather
/// than for a password. The certificates trusted for an account
/// (`account.<id>.cert.<host>`) stay on their device.
const ACCOUNT_SETTINGS: &[(&str, &str)] = &[
    ("account.", ".sign_in_alert"),
    ("account.", ".oauth"),
    ("notify.loud.", ""),
];

/// Marks a global id where a local one stood in a setting's key.
const GLOBAL: char = '@';

/// The local account id in `key`, for a setting of [ACCOUNT_SETTINGS].
fn account_in(key: &str) -> Option<(&'static str, &'static str, &str)> {
    ACCOUNT_SETTINGS.iter().find_map(|(pre, suf)| {
        let id = key.strip_prefix(pre)?.strip_suffix(suf)?;
        (!id.is_empty() && !id.contains('.')).then_some((*pre, *suf, id))
    })
}

/// A local setting's key as the space carries it, or None when it stays
/// here: per-device settings, and any other that names a local account.
pub fn setting_out(key: &str, account_gid: impl Fn(i64) -> Option<String>) -> Option<String> {
    if LOCAL_SETTINGS.iter().any(|p| key.starts_with(p)) {
        return None;
    }
    if let Some((pre, suf, id)) = account_in(key) {
        let gid = account_gid(id.parse().ok()?)?;
        return Some(format!("{pre}{GLOBAL}{gid}{suf}"));
    }
    // Anything else under "account." names a local id: it stays.
    if key.starts_with("account.") {
        return None;
    }
    Some(key.to_owned())
}

/// A key from the space as this device keeps it, or None when it names an
/// account this device doesn't have (or stays on its device).
pub fn setting_in(key: &str, account_local: impl Fn(&str) -> Option<i64>) -> Option<String> {
    if LOCAL_SETTINGS.iter().any(|p| key.starts_with(p)) {
        return None;
    }
    if let Some((pre, suf, id)) = account_in(key) {
        let gid = id.strip_prefix(GLOBAL)?;
        return Some(format!("{pre}{}{suf}", account_local(gid)?));
    }
    if key.starts_with("account.") {
        return None;
    }
    Some(key.to_owned())
}

/// Every setting key that names `account` on this device, local or
/// synced, by (prefix, suffix): removing the account removes them.
pub const ACCOUNT_KEYS: &[(&str, &str)] = &[
    ("account.", ".%"),
    ("notify.loud.", ""),
    ("rules.sorted.", ""),
    ("labels.local.", ""),
    ("nightly.unopened.", ""),
    ("sign_in.told.", ""),
    ("draft.signature.", ".%"),
];

// ---- The old format ------------------------------------------------------

/// Turns the old format's tables (whole rows, the writer's local ids) and
/// passwords (by address) into rows of this format, all stamped as the old
/// content's last write.
pub fn from_v1(
    tables: &serde_json::Map<String, Value>,
    passwords: &[(String, String)],
    stamp: &Stamp,
) -> Tables {
    let mut out = Tables::new();
    // Old local id -> global id, by table.
    let mut ids: BTreeMap<&str, BTreeMap<i64, String>> = BTreeMap::new();
    for spec in SYNCED {
        let rows = tables
            .get(spec.table)
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        for row in rows {
            let Some(mut row) = row.as_object().cloned() else {
                continue;
            };
            let old_id = row.get("id").and_then(Value::as_i64);
            if spec.table == "setting" {
                let Some(key) = row.get("key").and_then(Value::as_str) else {
                    continue;
                };
                let accounts = ids.get("account");
                let Some(key) = setting_out(key, |id| accounts?.get(&id).cloned()) else {
                    continue;
                };
                row.insert("key".into(), key.into());
            }
            let mut ok = true;
            for (col, target) in spec.refs {
                match row.get(*col).and_then(Value::as_i64) {
                    None => {}
                    Some(id) => match ids.get(target).and_then(|m| m.get(&id)) {
                        Some(gid) => {
                            row.insert((*col).into(), gid.clone().into());
                        }
                        None => ok = false,
                    },
                }
            }
            if !ok {
                continue;
            }
            for col in spec.local {
                row.remove(*col);
            }
            let gid = match spec.key {
                Key::Natural(_) => natural_id(spec, &row),
                Key::Mapped => old_id.map(|id| v1_id(spec.table, id)),
            };
            let Some(gid) = gid else { continue };
            if let Some(id) = old_id {
                ids.entry(spec.table).or_default().insert(id, gid.clone());
            }
            out.entry(spec.table.to_owned()).or_default().insert(
                gid,
                Row {
                    s: stamp.clone(),
                    del: false,
                    v: row,
                },
            );
        }
    }
    let accounts: BTreeMap<String, String> = out
        .get("account")
        .into_iter()
        .flatten()
        .filter_map(|(gid, r)| Some((r.v.get("email")?.as_str()?.to_lowercase(), gid.clone())))
        .collect();
    for (name, value) in passwords {
        let (gid, kind) = if let Some(key) = name.strip_prefix("secret:calendar-") {
            let Some(gid) = key
                .parse()
                .ok()
                .and_then(|id: i64| ids.get("calendar_source")?.get(&id).cloned())
            else {
                continue;
            };
            (gid, "calendar")
        } else {
            let Some(gid) = accounts.get(&name.to_lowercase()) else {
                continue;
            };
            (gid.clone(), "account")
        };
        let mut v = serde_json::Map::new();
        v.insert("for".into(), kind.into());
        v.insert("value".into(), value.clone().into());
        out.entry(SECRETS.to_owned()).or_default().insert(
            gid,
            Row {
                s: stamp.clone(),
                del: false,
                v,
            },
        );
    }
    out
}

// ---- What each device keeps ----------------------------------------------

/// What this device keeps of the space, in its own database: the rows as
/// last merged (passwords as digests), which of them are in its tables,
/// its clock, and what it accepted last.
#[derive(Clone, Default, Serialize, Deserialize)]
pub struct Local {
    /// The merged rows; passwords carry `digest` in place of `value`.
    #[serde(default)]
    pub doc: Tables,
    /// "table/gid" of the rows in this device's tables.
    #[serde(default)]
    pub here: BTreeSet<String>,
    /// The columns of each table at the last look, to catch up on columns
    /// an update added.
    #[serde(default)]
    pub columns: BTreeMap<String, Vec<String>>,
    #[serde(default)]
    pub clock: Stamp,
    /// The membership log as this device trusts it and the newest
    /// generation it took ([crate::space_trust]).
    #[serde(default)]
    pub trust: crate::space_trust::Trust,
    /// The newest copy this device took or wrote, as stored (sealed and
    /// signed, in base64): put back when the folder holds only older ones.
    #[serde(default)]
    pub last_copy: String,
    /// When this device last merged, in milliseconds: before the space's
    /// horizon, it takes the space's word for older rows.
    #[serde(default)]
    pub last_merge: i64,
    /// A merge changed the content key and the recovery phrase (two unlinks
    /// at once): the person writes the new phrase down.
    #[serde(default)]
    pub recovery_changed: bool,
    /// Accounts another device removed that this one keeps until the
    /// person says (mail waiting to go out, drafts, queued changes), with
    /// their rows whose removal waits too ("table/gid").
    #[serde(default)]
    pub held: BTreeMap<String, BTreeSet<String>>,
    /// Accounts another device removed, to remove here.
    #[serde(default)]
    pub removing: BTreeSet<String>,
    /// Of those, the ones the person said to remove (Remove here): they go
    /// whatever still waits.
    #[serde(default)]
    pub confirmed: BTreeSet<String>,
    /// Changes made here that the space doesn't have yet.
    #[serde(default)]
    pub unpushed: bool,
    /// Whether this device ever merged: until then, what it holds joins
    /// the space without taking the place of what the space has.
    #[serde(default)]
    pub started: bool,
    /// Copies of the space refused as older, at the last round.
    #[serde(default)]
    pub refused: u32,
    /// The space's schema is newer than this build's: it reads, but
    /// doesn't write.
    #[serde(default)]
    pub outdated: bool,
    /// Devices (by id) that removed each other at the last round, with
    /// nothing to tell which came first: this device stopped syncing until
    /// it is linked again.
    #[serde(default)]
    pub conflict: Vec<String>,
    /// The device (by id) that unlinked this one, at the last round: sync
    /// stopped here, and what this device trusts stays until the person
    /// links it again or turns sync off.
    #[serde(default)]
    pub unlinked: String,
    /// After this device unlinked another, or was the first to see one
    /// turn sync off: the mailboxes whose passwords that device knew, until
    /// the person says they changed them.
    #[serde(default)]
    pub exposed: Vec<String>,
    /// That device's name (names, when several), for the same notice.
    #[serde(default)]
    pub exposed_device: String,
    /// Rows to put in again for columns an update added ("table/gid"),
    /// between a look and the merge.
    #[serde(skip)]
    pub catchup: BTreeSet<String>,
}

impl Local {
    pub fn key(table: &str, gid: &str) -> String {
        format!("{table}/{gid}")
    }

    /// Takes the time of `rows` in, so this device's next stamps come
    /// after them.
    pub fn observe(&mut self, rows: &Tables) {
        for row in rows.values().flat_map(|t| t.values()) {
            if (row.s.t, row.s.c) > (self.clock.t, self.clock.c) {
                self.clock = Stamp {
                    t: row.s.t,
                    c: row.s.c,
                    d: self.clock.d.clone(),
                };
            }
        }
    }

    pub fn tick(&mut self, device: &str, now_ms: i64) -> Stamp {
        let s = Stamp::next(&self.clock, device, now_ms);
        self.clock = s.clone();
        s
    }
}

/// Brings stamps later than `limit` (this device's clock plus
/// [MAX_SKEW]) back to it. Returns whether any moved.
pub fn clamp(tables: &mut Tables, limit: i64) -> bool {
    let mut moved = false;
    for row in tables.values_mut().flat_map(|t| t.values_mut()) {
        if row.s.t > limit {
            row.s.t = limit;
            moved = true;
        }
    }
    moved
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(t: i64, d: &str, v: &str) -> Row {
        let mut m = serde_json::Map::new();
        m.insert("v".into(), v.into());
        Row {
            s: Stamp {
                t,
                c: 0,
                d: d.into(),
            },
            del: false,
            v: m,
        }
    }

    #[test]
    fn the_later_write_wins_the_same_way_everywhere() {
        let a = row(10, "a", "x");
        let b = row(10, "b", "y");
        assert!(b.beats(&a) && !a.beats(&b));
        let mut one = Tables::new();
        one.entry("t".into())
            .or_default()
            .insert("1".into(), a.clone());
        let mut two = Tables::new();
        two.entry("t".into())
            .or_default()
            .insert("1".into(), b.clone());
        let mut x = one.clone();
        merge(&mut x, &two);
        let mut y = two.clone();
        merge(&mut y, &one);
        assert!(same(&x, &y));
        assert_eq!(x["t"]["1"].v["v"], "y");
        // A column the later writer didn't know stays.
        let mut newer = row(5, "a", "x");
        newer.v.insert("future".into(), "kept".into());
        let mut one = Tables::new();
        one.entry("t".into()).or_default().insert("1".into(), newer);
        let mut two = Tables::new();
        two.entry("t".into())
            .or_default()
            .insert("1".into(), row(10, "b", "y"));
        let mut x = one.clone();
        merge(&mut x, &two);
        let mut y = two.clone();
        merge(&mut y, &one);
        assert!(same(&x, &y));
        assert_eq!(
            (&x["t"]["1"].v["v"], &x["t"]["1"].v["future"]),
            (&"y".into(), &"kept".into())
        );
    }

    #[test]
    fn the_clock_moves_past_what_it_saw() {
        let s = Stamp::next(&Stamp::default(), "a", 100);
        assert_eq!((s.t, s.c), (100, 0));
        // A clock that went back still makes later stamps.
        let s2 = Stamp::next(&s, "a", 50);
        assert!(s2 > s);
        let mut l = Local::default();
        let mut far = Tables::new();
        far.entry("t".into())
            .or_default()
            .insert("1".into(), row(5_000, "b", "z"));
        l.observe(&far);
        assert!(l.tick("a", 100).t >= 5_000);
    }

    #[test]
    fn tombstones_wait_for_every_device() {
        let now = 400 * 86_400 * 1000;
        // A device seen 40 days ago holds them back.
        let seen = now / 1000 - 40 * 86_400;
        assert_eq!(horizon([seen, now / 1000], now), seen * 1000);
        // None older than 30 days goes, a year is the most.
        assert_eq!(horizon([now / 1000], now), now - TOMBSTONE_MIN);
        assert_eq!(horizon([0], now), now - TOMBSTONE_MAX);
        let mut t = Tables::new();
        t.entry("t".into())
            .or_default()
            .insert("old".into(), Row::tombstone(Stamp::default()));
        t.entry("t".into()).or_default().insert(
            "new".into(),
            Row::tombstone(Stamp {
                t: now,
                ..Stamp::default()
            }),
        );
        compact(&mut t, now - 1);
        assert_eq!(t["t"].keys().collect::<Vec<_>>(), ["new"]);
    }

    #[test]
    fn settings_name_accounts_by_their_global_id() {
        let gid = |id: i64| (id == 3).then(|| "abc".to_owned());
        assert_eq!(
            setting_out("notify.loud.3", gid).as_deref(),
            Some("notify.loud.@abc")
        );
        assert_eq!(
            setting_out("account.3.sign_in_alert", gid).as_deref(),
            Some("account.@abc.sign_in_alert")
        );
        assert_eq!(
            setting_out("account.3.oauth", gid).as_deref(),
            Some("account.@abc.oauth")
        );
        // Device-local, or an account this build doesn't know to translate.
        assert_eq!(setting_out("account.3.junk", gid), None);
        assert_eq!(setting_out("account.3.cert.imap.example.org", gid), None);
        assert_eq!(setting_out("draft.signature.3.Drafts.9", gid), None);
        assert_eq!(setting_out("rules.sorted.3", gid), None);
        assert_eq!(setting_out("notify.loud.4", gid), None);
        assert_eq!(
            setting_out("appearance.theme", gid).as_deref(),
            Some("appearance.theme")
        );
        let local = |g: &str| (g == "abc").then_some(7);
        assert_eq!(
            setting_in("notify.loud.@abc", local).as_deref(),
            Some("notify.loud.7")
        );
        assert_eq!(setting_in("notify.loud.@zzz", local), None);
        // An old device's local id never lands on another account here.
        assert_eq!(setting_in("notify.loud.3", local), None);
    }

    #[test]
    fn a_clock_far_ahead_is_brought_back() {
        let mut t = Tables::new();
        t.entry("t".into())
            .or_default()
            .insert("1".into(), row(10_000_000, "a", "x"));
        t.entry("t".into())
            .or_default()
            .insert("2".into(), row(5, "a", "y"));
        assert!(clamp(&mut t, 1_000));
        assert_eq!((t["t"]["1"].s.t, t["t"]["2"].s.t), (1_000, 5));
        assert!(!clamp(&mut t, 1_000));
    }
}
