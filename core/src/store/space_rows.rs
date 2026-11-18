//! The store's side of the sync space: its synced tables as rows with
//! global ids ([crate::space_merge]), and the rows another device won,
//! put in. Local ids never leave the device; references travel as global
//! ids and come back as this device's own.

use std::collections::{BTreeMap, BTreeSet, HashMap};

use rusqlite::{params, OptionalExtension};
use serde_json::Value;

use super::{from_json, refile_inbox, to_json, Result, Store};
use crate::space_merge::{self, Key, Local, Row, Tables, SECRETS, SYNCED};
use crate::AccountId;

/// Where the space's bookkeeping is kept, in `space_state`.
const STATE: &str = "local";

/// A password that came in from another device, for the keychain.
pub enum SecretIn {
    Account(AccountId, String),
    /// A connected calendar's, by its id here.
    Calendar(i64, String),
}

impl std::fmt::Debug for SecretIn {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SecretIn::Account(id, _) => write!(f, "SecretIn::Account({}, …)", id.0),
            SecretIn::Calendar(id, _) => write!(f, "SecretIn::Calendar({id}, …)"),
        }
    }
}

/// An account another device removed that this one keeps until the
/// person says: what would go with it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Held {
    pub account: AccountId,
    pub email: String,
    /// Emails waiting in the outbox.
    pub outbox: u32,
    /// Drafts waiting to be uploaded.
    pub drafts: u32,
    /// Changes waiting for the server.
    pub pending: u32,
    /// It holds the space itself.
    pub home: bool,
}

/// What putting the merged rows in did.
#[derive(Debug, Default)]
pub struct Applied {
    /// Some row here changed.
    pub took: bool,
    pub secrets: Vec<SecretIn>,
    /// Accounts added here.
    pub added: Vec<AccountId>,
    /// Accounts the merged state removed, to remove here now.
    pub remove: Vec<AccountId>,
    /// Removals waiting for the person.
    pub held: Vec<Held>,
}

/// The local rowid of each synced row here, by "table/gid".
pub(crate) type Index = HashMap<String, i64>;

fn columns(conn: &rusqlite::Connection, table: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare("SELECT name FROM pragma_table_info(?1)")?;
    let names = stmt
        .query_map([table], |r| r.get(0))?
        .collect::<std::result::Result<Vec<String>, _>>()?;
    Ok(names)
}

impl Store {
    /// What this device keeps of the space; empty before the first round.
    pub fn space_local(&self) -> Result<Local> {
        let saved: Option<String> = self
            .conn
            .query_row(
                "SELECT value FROM space_state WHERE key = ?1",
                [STATE],
                |r| r.get(0),
            )
            .optional()?;
        Ok(saved
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default())
    }

    pub fn set_space_local(&self, local: &Local) -> Result<()> {
        let json = serde_json::to_string(local).expect("serializes");
        self.conn.execute(
            "INSERT OR REPLACE INTO space_state (key, value) VALUES (?1, ?2)",
            params![STATE, json],
        )?;
        Ok(())
    }

    /// Sync is off here: what this device kept of the space goes, so a
    /// space joined later starts afresh.
    pub fn space_forget(&self) -> Result<()> {
        self.conn
            .execute_batch("DELETE FROM space_state; DELETE FROM space_map;")?;
        Ok(())
    }

    /// The synced rows here, as the space carries them, with their rowids.
    /// `secrets` are passwords by account address, or by
    /// `secret:calendar-<id>`. On the first look (`first`), rows not yet
    /// named take the name the old format gave them.
    pub(crate) fn space_rows(
        &self,
        secrets: &[(String, String)],
        first: bool,
    ) -> Result<(Tables, Index)> {
        let mut out = Tables::new();
        let mut index = Index::new();
        // rowid -> gid, by table, for references.
        let mut gids: HashMap<&str, HashMap<i64, String>> = HashMap::new();
        for spec in SYNCED {
            let cols = columns(&self.conn, spec.table)?;
            if cols.is_empty() {
                continue;
            }
            let mapped: HashMap<i64, String> = if spec.key == Key::Mapped {
                let mut stmt = self
                    .conn
                    .prepare("SELECT local, gid FROM space_map WHERE tbl = ?1")?;
                let rows = stmt
                    .query_map([spec.table], |r| {
                        Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
                    })?
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                rows.into_iter()
                    .filter_map(|(l, g)| Some((l.parse().ok()?, g)))
                    .collect()
            } else {
                HashMap::new()
            };
            let mut stmt = self
                .conn
                .prepare(&format!("SELECT rowid, * FROM {}", spec.table))?;
            let names: Vec<String> = stmt.column_names().map(|s| s.to_string()).collect();
            let rows = stmt
                .query_map([], |r| {
                    let rowid: i64 = r.get(0)?;
                    let mut v = serde_json::Map::new();
                    for (i, name) in names.iter().enumerate().skip(1) {
                        v.insert(name.clone(), to_json(r.get_ref(i)?));
                    }
                    Ok((rowid, v))
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            drop(stmt);
            let mut seen = HashMap::new();
            'rows: for (rowid, mut v) in rows {
                for col in spec.local {
                    v.remove(*col);
                }
                for (col, target) in spec.refs {
                    if let Some(id) = v.get(*col).and_then(Value::as_i64) {
                        match gids.get(target).and_then(|m| m.get(&id)) {
                            Some(g) => {
                                v.insert((*col).into(), g.clone().into());
                            }
                            // Points at a row that doesn't travel.
                            None => continue 'rows,
                        }
                    }
                }
                if spec.table == "setting" {
                    let key = v.get("key").and_then(Value::as_str).unwrap_or_default();
                    let accounts = gids.get("account");
                    let Some(key) = space_merge::setting_out(key, |id| accounts?.get(&id).cloned())
                    else {
                        continue;
                    };
                    v.insert("key".into(), key.into());
                }
                let gid = match spec.key {
                    Key::Natural(_) => match space_merge::natural_id(spec, &v) {
                        Some(g) => g,
                        None => continue,
                    },
                    Key::Mapped => match mapped.get(&rowid) {
                        Some(g) => g.clone(),
                        None => {
                            let g = if first {
                                space_merge::v1_id(spec.table, rowid)
                            } else {
                                space_merge::new_id()
                            };
                            self.conn.execute(
                                "INSERT OR REPLACE INTO space_map (tbl, local, gid)
                                 VALUES (?1, ?2, ?3)",
                                params![spec.table, rowid.to_string(), g],
                            )?;
                            g
                        }
                    },
                };
                seen.insert(rowid, gid.clone());
                index.insert(Local::key(spec.table, &gid), rowid);
                out.entry(spec.table.to_owned()).or_default().insert(
                    gid,
                    Row {
                        s: space_merge::Stamp::default(),
                        del: false,
                        v,
                    },
                );
            }
            if spec.key == Key::Mapped {
                // Rows gone since: their names go with them.
                for (local, _) in mapped.iter().filter(|(l, _)| !seen.contains_key(l)) {
                    self.conn.execute(
                        "DELETE FROM space_map WHERE tbl = ?1 AND local = ?2",
                        params![spec.table, local.to_string()],
                    )?;
                }
            }
            gids.insert(spec.table, seen);
        }
        // Passwords, by their account's or calendar's global id.
        let accounts: HashMap<String, String> = out
            .get("account")
            .into_iter()
            .flatten()
            .filter_map(|(g, r)| Some((r.v.get("email")?.as_str()?.to_lowercase(), g.clone())))
            .collect();
        for (name, value) in secrets {
            let (gid, kind) = match name.strip_prefix("secret:calendar-") {
                Some(id) => {
                    let Some(g) = id
                        .parse::<i64>()
                        .ok()
                        .and_then(|id| gids.get("calendar_source")?.get(&id).cloned())
                    else {
                        continue;
                    };
                    (g, "calendar")
                }
                None => match accounts.get(&name.to_lowercase()) {
                    Some(g) => (g.clone(), "account"),
                    None => continue,
                },
            };
            let mut v = serde_json::Map::new();
            v.insert("for".into(), kind.into());
            v.insert("value".into(), value.clone().into());
            out.entry(SECRETS.to_owned()).or_default().insert(
                gid,
                Row {
                    s: space_merge::Stamp::default(),
                    del: false,
                    v,
                },
            );
        }
        Ok((out, index))
    }

    /// Looks at the synced rows here and stamps what changed since the
    /// last look: new and changed rows, and tombstones for rows removed
    /// here. Passwords are compared by `digest(gid, value)`; their removal
    /// is never inferred (an account's removal removes them). A change made
    /// here goes on top of the newest version `remote` (the space) has of
    /// the row. Before the first merge, rows the space already has are left
    /// to it. With `stale_before` (this device last merged before the
    /// space's horizon), a row stamped before it that the space no longer
    /// has was removed elsewhere, its tombstone dropped since: it is
    /// removed here too, not written back. Returns whether anything
    /// changed.
    #[allow(clippy::too_many_arguments)]
    pub fn space_scan(
        &mut self,
        local: &mut Local,
        secrets: &[(String, String)],
        digest: &dyn Fn(&str, &str) -> String,
        device: &str,
        now_ms: i64,
        remote: Option<&Tables>,
        stale_before: Option<i64>,
    ) -> Result<bool> {
        let adopt = remote.filter(|_| !local.started);
        let (rows, _) = self.space_rows(secrets, !local.started)?;
        // Accounts whose removal waits (for the person, or to be carried
        // out), with their password and rows: neither stamped nor removed.
        let held: BTreeSet<String> = local
            .held
            .iter()
            .flat_map(|(a, rows)| {
                [Local::key("account", a), Local::key(SECRETS, a)]
                    .into_iter()
                    .chain(rows.iter().cloned())
            })
            .chain(
                local
                    .removing
                    .iter()
                    .flat_map(|a| [Local::key("account", a), Local::key(SECRETS, a)]),
            )
            .collect();
        // Columns an update added: their values come from the space, not
        // from the defaults here.
        let mut fresh: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        for spec in SYNCED {
            let now = columns(&self.conn, spec.table)?;
            if let Some(before) = local.columns.get(spec.table) {
                let new: BTreeSet<String> = now
                    .iter()
                    .filter(|c| !before.contains(c))
                    .cloned()
                    .collect();
                if !new.is_empty() {
                    fresh.insert(spec.table.to_owned(), new);
                }
            }
            local.columns.insert(spec.table.to_owned(), now);
        }
        let mut changed = false;
        let mut present = BTreeSet::new();
        for (table, table_rows) in &rows {
            for (gid, row) in table_rows {
                let key = Local::key(table, gid);
                present.insert(key.clone());
                if held.contains(&key) {
                    continue;
                }
                let doc = local.doc.entry(table.clone()).or_default();
                let prev = doc.get(gid).cloned();
                if table == SECRETS {
                    let value = row
                        .v
                        .get("value")
                        .and_then(Value::as_str)
                        .unwrap_or_default();
                    let mine = digest(gid, value);
                    let known = prev.as_ref().filter(|p| !p.del).and_then(|p| {
                        p.v.get("digest")
                            .and_then(Value::as_str)
                            .map(str::to_owned)
                            .or_else(|| Some(digest(gid, p.v.get("value")?.as_str()?)))
                    });
                    local.here.insert(key);
                    match (prev, known) {
                        (Some(mut p), Some(d)) if d == mine => {
                            // The same: the value is here to write.
                            p.v = row.v.clone();
                            doc.insert(gid.clone(), p);
                        }
                        _ if !local.started
                            && adopt.is_some_and(|a| {
                                a.get(table)
                                    .and_then(|t| t.get(gid))
                                    .is_some_and(|r| !r.del)
                            }) => {}
                        _ => {
                            let s = local.tick(device, now_ms);
                            let doc = local.doc.entry(table.clone()).or_default();
                            doc.insert(
                                gid.clone(),
                                Row {
                                    s,
                                    del: false,
                                    v: row.v.clone(),
                                },
                            );
                            changed = true;
                        }
                    }
                    continue;
                }
                let new_cols = fresh.get(table);
                // Rows made here since the last merge are new, not stale.
                let last_merge = local.last_merge;
                let gone_there = |p: &Row| {
                    stale_before.is_some_and(|h| p.s.t < h && p.s.t <= last_merge)
                        && remote.is_some_and(|r| r.get(table).and_then(|t| t.get(gid)).is_none())
                };
                match prev {
                    Some(p) if !p.del && gone_there(&p) => {
                        local
                            .doc
                            .entry(table.clone())
                            .or_default()
                            .insert(gid.clone(), Row::tombstone(p.s));
                        local.here.insert(key);
                    }
                    Some(mut p) if !p.del => {
                        if local.here.contains(&key)
                            && new_cols.is_some_and(|c| c.iter().any(|c| p.v.contains_key(c)))
                        {
                            local.catchup.insert(key.clone());
                        }
                        let differs = row.v.iter().any(|(c, val)| {
                            !new_cols.is_some_and(|n| n.contains(c))
                                && p.v.get(c).is_some_and(|old| old != val)
                        });
                        let missing: Vec<(String, Value)> = row
                            .v
                            .iter()
                            .filter(|(c, _)| !p.v.contains_key(*c))
                            .map(|(c, v)| (c.clone(), v.clone()))
                            .collect();
                        if differs {
                            // Only the columns changed here go on top of the
                            // newest version known, which keeps what another
                            // device (or a newer version) changed beside them.
                            let edited: Vec<(String, Value)> = row
                                .v
                                .iter()
                                .filter(|(c, val)| {
                                    !new_cols.is_some_and(|n| n.contains(*c))
                                        && p.v.get(*c).is_some_and(|old| old != *val)
                                })
                                .map(|(c, v)| (c.clone(), v.clone()))
                                .collect();
                            if let Some(newer) = remote
                                .and_then(|r| r.get(table)?.get(gid))
                                .filter(|r| !r.del && r.beats(&p))
                            {
                                p.v = newer.v.clone();
                            }
                            for (c, v) in missing {
                                p.v.entry(c).or_insert(v);
                            }
                            p.v.extend(edited);
                            p.s = local.tick(device, now_ms);
                            changed = true;
                        } else {
                            // Columns the space didn't have: filled in
                            // without counting as a change.
                            p.v.extend(missing);
                        }
                        local
                            .doc
                            .entry(table.clone())
                            .or_default()
                            .insert(gid.clone(), p);
                        local.here.insert(key);
                    }
                    _ => {
                        if !local.started
                            && adopt.is_some_and(|a| {
                                a.get(table)
                                    .and_then(|t| t.get(gid))
                                    .is_some_and(|r| !r.del)
                            })
                        {
                            // The space's version goes in on merge.
                            continue;
                        }
                        let s = local.tick(device, now_ms);
                        local.doc.entry(table.clone()).or_default().insert(
                            gid.clone(),
                            Row {
                                s,
                                del: false,
                                v: row.v.clone(),
                            },
                        );
                        local.here.insert(key);
                        changed = true;
                    }
                }
            }
        }
        // Rows that were here and are gone: removed on this device.
        let gone: Vec<String> = local
            .here
            .iter()
            .filter(|k| !present.contains(*k))
            .cloned()
            .collect();
        for key in gone {
            local.here.remove(&key);
            let Some((table, gid)) = key.split_once('/') else {
                continue;
            };
            if table == SECRETS {
                continue;
            }
            if table == "account" {
                local.removing.remove(gid);
                local.held.remove(gid);
            }
            for rows in local.held.values_mut() {
                rows.remove(&key);
            }
            let live = local
                .doc
                .get(table)
                .and_then(|t| t.get(gid))
                .is_some_and(|r| !r.del);
            if live {
                let s = local.tick(device, now_ms);
                local
                    .doc
                    .entry(table.to_owned())
                    .or_default()
                    .insert(gid.to_owned(), Row::tombstone(s));
                changed = true;
            }
        }
        // An account removed here takes its passwords along.
        let dead: Vec<String> = local
            .doc
            .get(SECRETS)
            .into_iter()
            .flatten()
            .filter(|(gid, r)| {
                !r.del
                    && local
                        .doc
                        .iter()
                        .filter(|(t, _)| t.as_str() != SECRETS)
                        .any(|(_, rows)| rows.get(*gid).is_some_and(|o| o.del))
            })
            .map(|(gid, _)| gid.clone())
            .collect();
        for gid in dead {
            let s = local.tick(device, now_ms);
            local
                .doc
                .entry(SECRETS.to_owned())
                .or_default()
                .insert(gid, Row::tombstone(s));
            changed = true;
        }
        local.unpushed |= changed;
        Ok(changed)
    }

    /// What is waiting to leave with an account: the outbox, drafts not
    /// yet uploaded, changes not yet sent to the server.
    pub fn account_waiting(&self, account: AccountId) -> Result<(u32, u32, u32)> {
        let count = |table: &str| -> Result<u32> {
            Ok(self.conn.query_row(
                &format!("SELECT COUNT(*) FROM {table} WHERE account = ?1"),
                [account.0],
                |r| r.get(0),
            )?)
        };
        Ok((
            count("outbox")?,
            count("draft_waiting")?,
            count("pending_change")?,
        ))
    }

    /// Puts in the rows of `merged` this device doesn't hold as they are:
    /// those another device `won`, those that couldn't go in before (a row
    /// whose account wasn't here yet), and removals. An account is removed
    /// only through the bookkeeping in `local` (see [Applied::remove]),
    /// and never while mail waits to leave with it, or when it holds the
    /// space (`home`): the person is asked. `local` is saved in the same
    /// transaction (its passwords as `digest`s), so what came in and what
    /// this device knows of the space never part.
    pub fn space_apply(
        &mut self,
        local: &mut Local,
        merged: &Tables,
        won: &BTreeSet<(String, String)>,
        home: Option<&str>,
        digest: &dyn Fn(&str, &str) -> String,
    ) -> Result<Applied> {
        let (_, mut index) = self.space_rows(&[], false)?;
        let mut out = Applied::default();
        let tx = self.conn.transaction()?;
        let mut settings = false;
        // Removals first, last table first.
        for spec in SYNCED.iter().rev() {
            let Some(rows) = merged.get(spec.table) else {
                continue;
            };
            for (gid, _) in rows.iter().filter(|(_, r)| r.del) {
                let key = Local::key(spec.table, gid);
                let Some(&rowid) = index.get(&key) else {
                    continue;
                };
                if spec.table == "account" {
                    if local.removing.contains(gid) || local.held.contains_key(gid) {
                        continue;
                    }
                    let email: String =
                        tx.query_row("SELECT email FROM account WHERE id = ?1", [rowid], |r| {
                            r.get(0)
                        })?;
                    let waiting = |t: &str| -> Result<u32> {
                        Ok(tx.query_row(
                            &format!("SELECT COUNT(*) FROM {t} WHERE account = ?1"),
                            [rowid],
                            |r| r.get(0),
                        )?)
                    };
                    let is_home = home.is_some_and(|h| h.eq_ignore_ascii_case(&email));
                    let busy =
                        waiting("outbox")? + waiting("draft_waiting")? + waiting("pending_change")?;
                    if is_home || busy > 0 {
                        local.held.entry(gid.clone()).or_default();
                    } else {
                        local.removing.insert(gid.clone());
                    }
                    continue;
                }
                // A row of an account whose removal waits waits with it.
                let account = spec
                    .refs
                    .iter()
                    .find(|(_, t)| *t == "account")
                    .map(|(c, _)| *c);
                if let Some(col) = account {
                    let owner: Option<i64> = tx
                        .query_row(
                            &format!("SELECT {col} FROM {} WHERE rowid = ?1", spec.table),
                            [rowid],
                            |r| r.get(0),
                        )
                        .optional()?
                        .flatten();
                    let owner = owner.and_then(|id| {
                        index
                            .iter()
                            .find(|(k, v)| **v == id && k.starts_with("account/"))
                            .map(|(k, _)| k["account/".len()..].to_owned())
                    });
                    if let Some(owner) = owner {
                        if let Some(rows) = local.held.get_mut(&owner) {
                            rows.insert(key);
                            continue;
                        }
                        if local.removing.contains(&owner) {
                            continue;
                        }
                    }
                }
                if spec.table == "label" {
                    // As removing it here: its rules have nothing left to
                    // put on (their removal travels from here as well).
                    let keyword: Option<String> = tx
                        .query_row("SELECT keyword FROM label WHERE rowid = ?1", [rowid], |r| {
                            r.get(0)
                        })
                        .optional()?;
                    if let Some(k) = keyword {
                        tx.execute(
                            "DELETE FROM rule WHERE action = 'label' AND target = ?1",
                            [k],
                        )?;
                    }
                }
                tx.execute(
                    &format!("DELETE FROM {} WHERE rowid = ?1", spec.table),
                    [rowid],
                )?;
                if spec.key == Key::Mapped {
                    tx.execute(
                        "DELETE FROM space_map WHERE tbl = ?1 AND local = ?2",
                        params![spec.table, rowid.to_string()],
                    )?;
                }
                settings |= spec.table == "setting";
                index.remove(&key);
                local.here.remove(&key);
                out.took = true;
            }
        }
        // Then what is new or changed, first table first.
        for spec in SYNCED {
            let Some(rows) = merged.get(spec.table) else {
                continue;
            };
            let cols = columns(&tx, spec.table)?;
            let required: Vec<String> = {
                let mut stmt =
                    tx.prepare("SELECT name FROM pragma_table_info(?1) WHERE \"notnull\" = 1")?;
                let names = stmt
                    .query_map([spec.table], |r| r.get(0))?
                    .collect::<std::result::Result<Vec<String>, _>>()?;
                names
            };
            for (gid, row) in rows.iter().filter(|(_, r)| !r.del) {
                let key = Local::key(spec.table, gid);
                let wanted = won.contains(&(spec.table.to_owned(), gid.clone()))
                    || !local.here.contains(&key)
                    || local.catchup.contains(&key);
                if !wanted {
                    continue;
                }
                if spec.table == "account" {
                    // Written again since its removal: it stays.
                    local.removing.remove(gid);
                    local.held.remove(gid);
                }
                let mut values: Vec<(String, rusqlite::types::Value)> = Vec::new();
                let mut ok = true;
                for c in &cols {
                    if spec.local.contains(&c.as_str()) {
                        continue;
                    }
                    let Some(v) = row.v.get(c) else { continue };
                    if let Some((_, target)) = spec.refs.iter().find(|(rc, _)| rc == c) {
                        match v.as_str() {
                            None => values.push((c.clone(), rusqlite::types::Value::Null)),
                            Some(g) => match index.get(&Local::key(target, g)) {
                                Some(&id) => values.push((c.clone(), id.into())),
                                // Gone, or not here yet: an optional link
                                // is left empty, a required one waits.
                                None if !required.contains(c) => {
                                    values.push((c.clone(), rusqlite::types::Value::Null))
                                }
                                None => {
                                    ok = false;
                                    break;
                                }
                            },
                        }
                        continue;
                    }
                    if spec.table == "setting" && c == "key" {
                        let accounts = &index;
                        let k = space_merge::setting_in(v.as_str().unwrap_or_default(), |g| {
                            accounts.get(&Local::key("account", g)).copied()
                        });
                        match k {
                            Some(k) => values.push((c.clone(), k.into())),
                            None => {
                                ok = false;
                                break;
                            }
                        }
                        continue;
                    }
                    values.push((c.clone(), from_json(v)));
                }
                if !ok || values.is_empty() {
                    continue;
                }
                let names: Vec<&str> = values.iter().map(|(c, _)| c.as_str()).collect();
                let done = match index.get(&key) {
                    Some(&rowid) => {
                        let set = names
                            .iter()
                            .map(|c| format!("{c} = ?"))
                            .collect::<Vec<_>>()
                            .join(", ");
                        let mut params: Vec<rusqlite::types::Value> =
                            values.iter().map(|(_, v)| v.clone()).collect();
                        params.push(rowid.into());
                        tx.execute(
                            &format!("UPDATE {} SET {set} WHERE rowid = ?", spec.table),
                            rusqlite::params_from_iter(params),
                        )
                        .map(|_| rowid)
                    }
                    None => {
                        let mut names = names.clone();
                        let mut params: Vec<rusqlite::types::Value> =
                            values.iter().map(|(_, v)| v.clone()).collect();
                        if spec.table == "account" {
                            // A new id, never one a removed account had.
                            let id: i64 = tx.query_row(
                                "SELECT MAX(COALESCE((SELECT MAX(id) FROM account), 0),
                                            COALESCE((SELECT next FROM account_id_floor), 0)) + 1",
                                [],
                                |r| r.get(0),
                            )?;
                            names.push("id");
                            params.push(id.into());
                        }
                        let verb = match spec.table {
                            // One setting by key.
                            "setting" => "INSERT OR REPLACE",
                            _ => "INSERT",
                        };
                        let marks = vec!["?"; names.len()].join(", ");
                        let sql = format!(
                            "{verb} INTO {} ({}) VALUES ({marks})",
                            spec.table,
                            names.join(", ")
                        );
                        let mut done = tx
                            .execute(&sql, rusqlite::params_from_iter(params.clone()))
                            .map(|_| tx.last_insert_rowid());
                        // Another label here has the name (by another
                        // keyword): both stay, this one as "Work (2)".
                        if done.is_err() && spec.table == "label" {
                            if let Some(i) = names.iter().position(|n| *n == "name") {
                                let base = row.v.get("name").and_then(Value::as_str).unwrap_or("");
                                for n in 2..10 {
                                    params[i] = format!("{base} ({n})").into();
                                    done = tx
                                        .execute(&sql, rusqlite::params_from_iter(params.clone()))
                                        .map(|_| tx.last_insert_rowid());
                                    if done.is_ok() {
                                        break;
                                    }
                                }
                            }
                        }
                        done
                    }
                };
                // A row this version can't take (a column it lacks a value
                // for): it stays in the space, for a later version.
                let Ok(rowid) = done else { continue };
                if spec.key == Key::Mapped {
                    tx.execute(
                        "INSERT OR REPLACE INTO space_map (tbl, local, gid) VALUES (?1, ?2, ?3)",
                        params![spec.table, rowid.to_string(), gid],
                    )?;
                }
                if spec.table == "account" && !index.contains_key(&key) {
                    out.added.push(AccountId(rowid));
                }
                index.insert(key.clone(), rowid);
                local.here.insert(key);
                settings |= spec.table == "setting";
                out.took = true;
            }
        }
        local.catchup.clear();
        // Passwords: for the keychain, once their account or calendar is here.
        for (gid, row) in merged.get(SECRETS).into_iter().flatten() {
            let key = Local::key(SECRETS, gid);
            if row.del
                || !(won.contains(&(SECRETS.to_owned(), gid.clone())) || !local.here.contains(&key))
            {
                continue;
            }
            let Some(value) = row.v.get("value").and_then(Value::as_str) else {
                continue;
            };
            let secret = match row.v.get("for").and_then(Value::as_str) {
                Some("calendar") => index
                    .get(&Local::key("calendar_source", gid))
                    .map(|&id| SecretIn::Calendar(id, value.to_owned())),
                _ => index
                    .get(&Local::key("account", gid))
                    .map(|&id| SecretIn::Account(AccountId(id), value.to_owned())),
            };
            if let Some(s) = secret {
                out.secrets.push(s);
                local.here.insert(key);
                out.took = true;
            }
        }
        if settings {
            // Newsletters may have been turned on or off on another device.
            refile_inbox(&tx)?;
        }
        // What this device now knows of the space goes with what came in.
        let mut kept = local.clone();
        crate::space_sync::strip(&mut kept.doc, digest);
        tx.execute(
            "INSERT OR REPLACE INTO space_state (key, value) VALUES (?1, ?2)",
            params![STATE, serde_json::to_string(&kept).expect("serializes")],
        )?;
        tx.commit()?;
        for gid in &local.removing {
            if let Some(&id) = index.get(&Local::key("account", gid)) {
                out.remove.push(AccountId(id));
            }
        }
        for gid in local.held.keys() {
            let Some(&id) = index.get(&Local::key("account", gid)) else {
                continue;
            };
            let email: String =
                self.conn
                    .query_row("SELECT email FROM account WHERE id = ?1", [id], |r| {
                        r.get(0)
                    })?;
            let (outbox, drafts, pending) = self.account_waiting(AccountId(id))?;
            out.held.push(Held {
                account: AccountId(id),
                home: home.is_some_and(|h| h.eq_ignore_ascii_case(&email)),
                email,
                outbox,
                drafts,
                pending,
            });
        }
        Ok(out)
    }

    /// The global id of an account here.
    pub fn account_gid(&self, account: AccountId) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row(
                "SELECT email FROM account WHERE id = ?1",
                [account.0],
                |r| r.get::<_, String>(0),
            )
            .optional()?
            .map(|e| space_merge::account_id(&e)))
    }
}
