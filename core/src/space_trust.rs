//! Which copies of the sync space a device takes, by who signed them.
//!
//! A device keeps the membership log ([crate::space_log]) as it trusts it
//! ([Trust]): from where it began (the space it made, a pairing checked by
//! the code, or the recovery phrase) through every entry it took since.
//! Each copy carries the log as its writer knew it, in the clear and
//! signed; the device reads its own and the copies' together
//! ([space_log::evaluate]) and takes a copy only when its signer belongs
//! by that reading. So a removed device, or the mail provider, can't make
//! a copy count: whatever key sealed it and whatever generation it claims,
//! its writer is not a member.
//!
//! A copy older than the newest one taken is refused too, and so is one
//! that jumps too far ahead ([MAX_JUMP]).

use std::collections::{BTreeSet, HashMap, HashSet};

use serde::{Deserialize, Serialize};

use crate::space::{SealedSpace, Space, RECOVERY};
use crate::space_log::{self, Entry, Eval, Member, State, MAX_ENTRIES};

/// How far ahead of the newest generation a device took a copy may be: a
/// device writes once per change, so years of use stay well under it; a
/// forged copy claiming a huge generation to shadow the real ones doesn't.
pub const MAX_JUMP: u64 = 100_000;

/// The highest generation a copy may claim: far beyond any real use, far
/// below where counting on would overflow.
pub const MAX_GENERATION: u64 = 1 << 48;

/// What a device trusts, kept in its own database.
#[derive(Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Trust {
    /// The log's first entry, by id. Empty until the device made the
    /// space or joined it with a code or the phrase: an older build's
    /// device has none, and trusts no copy until the person confirms it.
    #[serde(default)]
    pub root: String,
    /// The log as this device took it.
    #[serde(default)]
    pub log: Vec<Entry>,
    /// Removals this device made (by entry id): each stands against a
    /// removal of this device made beside it ([space_log::evaluate]'s
    /// `own`). Removals it only took from others get no such weight.
    /// (Earlier builds kept every removal taken, as `fixed`: dropped.)
    #[serde(default)]
    pub own: BTreeSet<String>,
    /// The newest generation taken.
    #[serde(default)]
    pub generation: u64,
}

impl std::fmt::Debug for Trust {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Trust")
            .field("root", &self.root)
            .field("entries", &self.log.len())
            .field("own", &self.own.len())
            .field("generation", &self.generation)
            .finish()
    }
}

impl Trust {
    /// Trust that begins with `log`, whose first entry is `root`: a space
    /// this device made, or the log a pairing handed over.
    pub fn from_log(log: Vec<Entry>, root: &str, generation: u64) -> Trust {
        let own = BTreeSet::new();
        let e = space_log::evaluate(log, root, &own);
        Trust::adopt(root, &e, own, generation)
    }

    fn adopt(root: &str, e: &Eval, own: BTreeSet<String>, generation: u64) -> Trust {
        Trust {
            root: root.to_owned(),
            log: e.kept.clone(),
            own,
            generation,
        }
    }

    /// Whether this device ever began trusting a space.
    pub fn verified(&self) -> bool {
        !self.root.is_empty()
    }

    pub fn evaluate(&self) -> Eval {
        space_log::evaluate(self.log.iter().cloned(), &self.root, &self.own)
    }

    pub fn state(&self) -> State {
        self.evaluate().state
    }

    /// Takes in an entry this device made.
    pub fn push(&mut self, entry: Entry) -> State {
        let mut own = self.own.clone();
        if entry.removes().is_some() {
            own.insert(entry.id());
        }
        let mut log = self.log.clone();
        log.push(entry);
        let e = space_log::evaluate(log, &self.root, &own);
        *self = Trust::adopt(&self.root, &e, own, self.generation);
        e.state
    }
}

/// How a device starts reading the copies.
#[derive(Clone, Copy)]
pub enum Anchor<'a> {
    /// A linked device: from what it trusts already.
    Linked,
    /// Joining with a code: from the log the approving device handed over,
    /// with its entry adding this device (none when that log lists this
    /// device already, with these keys: `device`).
    Paired {
        log: &'a [Entry],
        entry: Option<&'a Entry>,
        device: &'a Member,
    },
    /// Joining with the recovery phrase, by its signing key: from the log
    /// of the copies it opens, whose phrase in force must be this one.
    Phrase(&'a [u8]),
}

/// What judging the stored copies came to.
pub struct Verdict {
    /// Indexes of the copies taken.
    pub accepted: Vec<usize>,
    /// Copies left out: older, or not signed by a member.
    pub refused: u32,
    /// Copies by a device that left, carrying the entry that says so:
    /// their entries count, their rows don't, and they are no warning.
    pub left: u32,
    /// Trust after taking them.
    pub trust: Trust,
    /// Who belongs after taking them.
    pub state: State,
    /// The whole reading, to tell who removed whom.
    pub eval: Eval,
    /// The content key and the phrase must change before writing: a
    /// removed device may know them, copies were sealed with different
    /// keys, or the phrase in force isn't settled.
    pub rotate: bool,
    /// Devices whose removals contradict each other: nothing is taken.
    pub conflict: BTreeSet<String>,
    /// The copies carry more entries than one reading takes
    /// ([space_log::MAX_UNION]): nothing is taken.
    pub overflow: bool,
}

impl Verdict {
    fn none(trust: &Trust, refused: u32) -> Verdict {
        Verdict {
            accepted: Vec::new(),
            refused,
            left: 0,
            trust: trust.clone(),
            state: State::default(),
            eval: Eval::default(),
            rotate: false,
            conflict: BTreeSet::new(),
            overflow: false,
        }
    }
}

/// A stored copy: as sealed, and opened when this device could.
pub type Stored<'a> = (&'a SealedSpace, Option<&'a Space>);

/// The log a copy carries: in the clear, or, from a build before that,
/// inside it once opened.
fn log_of<'a>((sealed, space): &Stored<'a>) -> &'a [Entry] {
    match space {
        Some(s) if !s.content.log.is_empty() => &s.content.log,
        _ => &sealed.log,
    }
}

fn sane(c: &Stored<'_>) -> bool {
    log_of(c).len() <= MAX_ENTRIES && c.1.is_none_or(|s| s.content.generation <= MAX_GENERATION)
}

/// The logs of the copies signed by a device the space ever had (removed
/// or not), starting from `base` and its beginning `root`: a key counts
/// once an entry signed with a key that counts gives it (an add, by a
/// device or by a phrase in some log). A copy anyone else made, like one
/// the mail provider sealed for a public key it saw, brings nothing in,
/// however many entries it holds. Copies this device can't open count too:
/// they tell who removed it.
fn signed_logs(root: &str, base: &[Entry], copies: &[Stored<'_>]) -> Vec<Entry> {
    use space_log::Op;
    // Entries that give a key, by author, each once.
    let mut ids = HashSet::new();
    let mut giving: HashMap<&str, Vec<&Entry>> = HashMap::new();
    let mut keys: HashMap<&str, BTreeSet<&[u8]>> = HashMap::new();
    let mut learned: Vec<&str> = Vec::new();
    let sources = std::iter::once(base).chain(copies.iter().filter(|c| sane(c)).map(log_of));
    for e in sources.flatten() {
        let gives = matches!(
            e.op,
            Op::Genesis { .. } | Op::Add { .. } | Op::Phrase { .. }
        );
        if !gives || !ids.insert(e.id()) {
            continue;
        }
        match &e.op {
            Op::Genesis { device, recovery } => {
                if e.parents.is_empty() && e.id() == root && e.verified_by(&device.sign) {
                    keys.entry(&device.id).or_default().insert(&device.sign);
                    keys.entry(RECOVERY).or_default().insert(recovery);
                    learned.extend([device.id.as_str(), RECOVERY]);
                }
            }
            _ => giving.entry(&e.by).or_default().push(e),
        }
    }
    // Each author's entries, checked once a key of theirs counts.
    while let Some(author) = learned.pop() {
        let Some(list) = giving.remove(author) else {
            continue;
        };
        let mut waiting = Vec::new();
        for e in list {
            let signed = keys
                .get(author)
                .is_some_and(|ks| ks.iter().any(|k| e.verified_by(k)));
            let (who, key): (&str, &[u8]) = match &e.op {
                Op::Add { device } => (&device.id, &device.sign),
                Op::Phrase { recovery } => (RECOVERY, recovery),
                Op::Genesis { .. } | Op::Remove { .. } => continue,
            };
            if !signed {
                waiting.push(e);
            } else if keys.entry(who).or_default().insert(key) {
                learned.push(who);
            }
        }
        // Signed with a key of theirs not known yet: looked at again then.
        if !waiting.is_empty() {
            giving.insert(author, waiting);
        }
    }
    copies
        .iter()
        .filter(|c| sane(c))
        .filter(|(sealed, _)| {
            keys.get(sealed.signer.as_str())
                .is_some_and(|ks| ks.iter().any(|k| sealed.signed_by(k)))
        })
        .flat_map(|c| log_of(c).iter().cloned())
        .collect()
}

/// Judges the stored copies (`copies`, each sealed, and opened when this
/// device could) against what it trusts.
pub fn judge(trust: &Trust, anchor: Anchor<'_>, copies: &[Stored<'_>]) -> Verdict {
    let opened = || {
        copies
            .iter()
            .filter(|c| c.1.is_some() && sane(c))
            .flat_map(|c| log_of(c).iter().cloned())
    };
    let (root, own, entries, floor): (String, BTreeSet<String>, Vec<Entry>, u64) = match anchor {
        Anchor::Linked => {
            let mut entries = trust.log.clone();
            entries.extend(signed_logs(&trust.root, &trust.log, copies));
            (
                trust.root.clone(),
                trust.own.clone(),
                entries,
                trust.generation,
            )
        }
        Anchor::Paired { log, entry, .. } => {
            let Some(root) = space_log::roots(log).into_iter().next() else {
                return Verdict::none(trust, copies.len() as u32);
            };
            let mut entries = log.to_vec();
            entries.extend(entry.cloned());
            entries.extend(opened());
            (root, BTreeSet::new(), entries, 0)
        }
        Anchor::Phrase(public) => {
            let all: Vec<Entry> = opened().collect();
            let mut stop = BTreeSet::new();
            let root = space_log::roots(&all).into_iter().find(|r| {
                let e = space_log::evaluate(all.iter().cloned(), r, &BTreeSet::new());
                if stop.is_empty() {
                    stop.clone_from(&e.conflict);
                }
                e.state.recovery.as_deref() == Some(public)
            });
            let Some(root) = root else {
                // A log that stops on removals contradicting each other has
                // no phrase in force: said as such, not as the wrong words.
                return Verdict {
                    conflict: stop,
                    ..Verdict::none(trust, copies.len() as u32)
                };
            };
            (root, BTreeSet::new(), all, 0)
        }
    };
    let eval = space_log::evaluate(entries, &root, &own);
    if eval.overflow {
        return Verdict {
            overflow: true,
            ..Verdict::none(trust, copies.len() as u32)
        };
    }
    if !eval.conflict.is_empty() {
        return Verdict {
            conflict: eval.conflict.clone(),
            ..Verdict::none(trust, 0)
        };
    }
    if let Anchor::Paired { entry, device, .. } = anchor {
        let added = match entry {
            Some(e) => eval.accepted.contains(&e.id()),
            None => eval.state.members.get(&device.id) == Some(device),
        };
        if !added {
            return Verdict::none(trust, copies.len() as u32);
        }
    }
    let members = &eval.state.members;
    let mut accepted = Vec::new();
    let mut refused = 0;
    let mut left = 0;
    for (i, c) in copies.iter().enumerate() {
        let (sealed, Some(space)) = *c else {
            continue;
        };
        let g = space.content.generation;
        let in_range = sane(c) && g >= floor && (floor == 0 || g <= floor + MAX_JUMP);
        let signed = members
            .get(&sealed.signer)
            .is_some_and(|m| sealed.signed_by(&m.sign));
        if signed && in_range {
            accepted.push(i);
        } else if leaving(&eval, sealed) {
            left += 1;
        } else {
            refused += 1;
        }
    }
    let space = |i: usize| copies[i].1.expect("taken copies are open");
    let top = accepted.iter().copied().max_by(|&a, &b| {
        (space(a).content.generation, &copies[a].0.signer)
            .cmp(&(space(b).content.generation, &copies[b].0.signer))
    });
    let generation = top.map_or(trust.generation, |t| {
        trust.generation.max(space(t).content.generation)
    });
    let keys: BTreeSet<[u8; 32]> = accepted.iter().map(|&i| space(i).content_key().0).collect();
    let rotate = keys.len() > 1
        || eval.state.recovery.is_none()
        || top.is_some_and(|t| Some(space(t).content.recovery_sign()) != eval.state.recovery)
        || accepted
            .iter()
            .any(|&i| copies[i].0.readers().any(|r| !members.contains_key(r)));
    Verdict {
        accepted,
        refused,
        left,
        trust: Trust::adopt(&root, &eval, own, generation),
        state: eval.state.clone(),
        eval,
        rotate,
        conflict: BTreeSet::new(),
        overflow: false,
    }
}

/// A copy by a device that has since left by itself (turning sync off):
/// what it wrote then was taken already, and this one is no warning.
fn leaving(eval: &Eval, sealed: &SealedSpace) -> bool {
    eval.state.removed.contains(&sealed.signer)
        && eval.kept.iter().any(|e| {
            e.by == sealed.signer
                && e.removes() == Some(e.by.as_str())
                && eval.accepted.contains(&e.id())
        })
}
