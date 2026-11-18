//! Which copies of the sync space a device takes, by who signed them.
//!
//! A device keeps the membership log ([crate::space_log]) as it trusts it
//! ([Trust]): from where it began (the space it made, a pairing checked by
//! the code, or the recovery phrase) through every entry it took since.
//! Each copy carries the log as its writer knew it; the device reads its
//! own and every copy's together ([space_log::evaluate]) and takes a copy
//! only when its signer belongs by that reading. So a removed device, or
//! the mail provider, can't make a copy count: whatever key sealed it and
//! whatever generation it claims, its writer is not a member.
//!
//! A copy older than the newest one taken is refused too, and so is one
//! that jumps too far ahead ([MAX_JUMP]).

use std::collections::BTreeSet;

use serde::{Deserialize, Serialize};

use crate::space::{SealedSpace, Space};
use crate::space_log::{self, Entry, Eval, State, MAX_ENTRIES};

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
    /// Removals taken: they stand whatever comes in later.
    #[serde(default)]
    pub fixed: BTreeSet<String>,
    /// The newest generation taken.
    #[serde(default)]
    pub generation: u64,
}

impl std::fmt::Debug for Trust {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Trust")
            .field("root", &self.root)
            .field("entries", &self.log.len())
            .field("generation", &self.generation)
            .finish()
    }
}

impl Trust {
    /// Trust that begins with `log`, whose first entry is `root`, read
    /// with nothing fixed: a space this device made, or the log a pairing
    /// handed over.
    pub fn from_log(log: Vec<Entry>, root: &str, generation: u64) -> Trust {
        let e = space_log::evaluate(log, root, &BTreeSet::new());
        Trust::adopt(root, &e, generation)
    }

    fn adopt(root: &str, e: &Eval, generation: u64) -> Trust {
        Trust {
            root: root.to_owned(),
            log: e.kept.clone(),
            fixed: e.removals(),
            generation,
        }
    }

    /// Whether this device ever began trusting a space.
    pub fn verified(&self) -> bool {
        !self.root.is_empty()
    }

    pub fn evaluate(&self) -> Eval {
        space_log::evaluate(self.log.iter().cloned(), &self.root, &self.fixed)
    }

    pub fn state(&self) -> State {
        self.evaluate().state
    }

    /// Takes in an entry this device made (or a pairing handed over).
    pub fn push(&mut self, entry: Entry) -> State {
        let mut log = self.log.clone();
        log.push(entry);
        let e = space_log::evaluate(log, &self.root, &self.fixed);
        let generation = self.generation;
        *self = Trust::adopt(&self.root, &e, generation);
        e.state
    }
}

/// How a device starts reading the copies.
pub enum Anchor<'a> {
    /// A linked device: from what it trusts already.
    Linked,
    /// Joining with a code: from the log the approving device handed over,
    /// with its entry adding this device.
    Paired { log: &'a [Entry], entry: &'a Entry },
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
    /// The content key and the phrase must change before writing: a
    /// removed device may know them, copies were sealed with different
    /// keys, or the phrase in force isn't settled.
    pub rotate: bool,
    /// Devices whose removals contradict each other: nothing is taken.
    pub conflict: BTreeSet<String>,
}

impl Verdict {
    fn none(trust: &Trust, refused: u32) -> Verdict {
        Verdict {
            accepted: Vec::new(),
            refused,
            left: 0,
            trust: trust.clone(),
            state: State::default(),
            rotate: false,
            conflict: BTreeSet::new(),
        }
    }
}

/// Judges the copies a device opened (`copies`, each sealed and opened)
/// against what it trusts.
pub fn judge(trust: &Trust, anchor: Anchor<'_>, copies: &[(&SealedSpace, &Space)]) -> Verdict {
    let sane = |space: &Space| {
        space.content.log.len() <= MAX_ENTRIES && space.content.generation <= MAX_GENERATION
    };
    let carried = || {
        copies
            .iter()
            .filter(|(_, s)| sane(s))
            .flat_map(|(_, s)| s.content.log.iter().cloned())
    };
    let (root, fixed, mut entries, floor): (String, BTreeSet<String>, Vec<Entry>, u64) =
        match anchor {
            Anchor::Linked => (
                trust.root.clone(),
                trust.fixed.clone(),
                trust.log.clone(),
                trust.generation,
            ),
            Anchor::Paired { log, entry } => {
                let Some(root) = space_log::roots(log).into_iter().next() else {
                    return Verdict::none(trust, copies.len() as u32);
                };
                let theirs = space_log::evaluate(log.iter().cloned(), &root, &BTreeSet::new());
                let mut entries = log.to_vec();
                entries.push(entry.clone());
                (root, theirs.removals(), entries, 0)
            }
            Anchor::Phrase(public) => {
                let all: Vec<Entry> = carried().collect();
                let root = space_log::roots(&all).into_iter().find(|r| {
                    let e = space_log::evaluate(all.iter().cloned(), r, &BTreeSet::new());
                    e.state.recovery.as_deref() == Some(public)
                });
                let Some(root) = root else {
                    return Verdict::none(trust, copies.len() as u32);
                };
                (root, BTreeSet::new(), Vec::new(), 0)
            }
        };
    entries.extend(carried());
    let eval = space_log::evaluate(entries, &root, &fixed);
    if !eval.conflict.is_empty() {
        return Verdict {
            conflict: eval.conflict.clone(),
            ..Verdict::none(trust, 0)
        };
    }
    if let Anchor::Paired { entry, .. } = anchor {
        if !eval.accepted.contains(&entry.id()) {
            return Verdict::none(trust, copies.len() as u32);
        }
    }
    let members = &eval.state.members;
    let mut accepted = Vec::new();
    let mut refused = 0;
    let mut left = 0;
    for (i, (sealed, space)) in copies.iter().enumerate() {
        let g = space.content.generation;
        let in_range = sane(space) && g >= floor && (floor == 0 || g <= floor + MAX_JUMP);
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
    let top = accepted.iter().copied().max_by(|&a, &b| {
        let (sa, ca) = copies[a];
        let (sb, cb) = copies[b];
        (ca.content.generation, &sa.signer).cmp(&(cb.content.generation, &sb.signer))
    });
    let generation = top.map_or(trust.generation, |t| {
        trust.generation.max(copies[t].1.content.generation)
    });
    let keys: BTreeSet<[u8; 32]> = accepted
        .iter()
        .map(|&i| copies[i].1.content_key().0)
        .collect();
    let rotate = keys.len() > 1
        || eval.state.recovery.is_none()
        || top.is_some_and(|t| Some(copies[t].1.content.recovery_sign()) != eval.state.recovery)
        || accepted
            .iter()
            .any(|&i| copies[i].0.readers().any(|r| !members.contains_key(r)));
    Verdict {
        accepted,
        refused,
        left,
        trust: Trust::adopt(&root, &eval, generation),
        state: eval.state,
        rotate,
        conflict: BTreeSet::new(),
    }
}

/// A copy by a device that has since left by itself (turning sync off):
/// what it wrote then was taken already, and this one is no warning.
fn leaving(eval: &Eval, sealed: &SealedSpace) -> bool {
    eval.state.removed.contains(&sealed.signer)
        && eval.kept.iter().any(|e| {
            e.by == sealed.signer
                && matches!(&e.op, space_log::Op::Remove { device } if *device == e.by)
                && eval.accepted.contains(&e.id())
        })
}
