//! Who belongs to the sync space: a signed, ordered record of every device
//! added and removed (the membership log), carried in every copy.
//!
//! Each [Entry] names the entries it follows (`parents`, by hash), what it
//! does ([Op]), who made it and their signature. The first entry
//! (`Genesis`) is the device that made the space. From there, a device
//! that belongs (a member) adds a device it approved, removes one (an
//! unlink, or itself when sync is turned off) and replaces the recovery
//! phrase; the recovery phrase in force adds the device that came in with
//! it. Who belongs is what the entries say, applied in order: no copy and
//! no generation number can change it.
//!
//! Two devices can write at the same time, so the entries form a graph,
//! not a line. [evaluate] reads it the same way on every device:
//!
//! - An entry counts only if its author belonged in the state its own
//!   parents lead to, and its signature checks out with that author's key.
//! - A removal wins over what the removed device did without knowing of it
//!   (entries neither before nor after the removal): a device that missed
//!   its own unlink can't vouch for anyone, unlink anyone or replace the
//!   phrase on the side. The phrase likewise: what it adds at the same time
//!   as any removal or replacement doesn't count, and after a removal it
//!   adds nobody until a member replaces it.
//! - When two removals each remove the other's author and neither came
//!   first, nothing in the log tells which is genuine. A device that made
//!   one of them stands by its own ([evaluate]'s `own`): it knows it is
//!   genuine. Every other device stops ([Eval::conflict] names those
//!   devices) until the person links it again: whichever removal it
//!   happened to see first proves nothing, since the removed device can
//!   delete the other one from the folder for a while.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use serde::{Deserialize, Serialize};

use crate::space::{self, Device, Key, RECOVERY};

/// Entries a copy may carry: years of linking and unlinking stay far
/// under it. There is no compaction: a log grown past it makes every copy
/// that carries it refused.
pub const MAX_ENTRIES: usize = 4096;

/// Entries one evaluation reads, from every copy together, once repeats
/// are dropped. Past it nothing is read ([Eval::overflow]): leaving some
/// out would let whoever filled the folder choose which.
pub const MAX_UNION: usize = 2 * MAX_ENTRIES;

/// A device as the log knows it: its id and its two public keys.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Member {
    pub id: String,
    /// X25519: the content key is sealed for it.
    #[serde(with = "space::b64")]
    pub public: Vec<u8>,
    /// Ed25519: what it writes is signed with it.
    #[serde(with = "space::b64")]
    pub sign: Vec<u8>,
}

impl Member {
    pub fn of(device: &Device) -> Member {
        Member {
            id: device.id.clone(),
            public: device.public.clone(),
            sign: device.sign.clone(),
        }
    }

    fn valid(&self) -> bool {
        !self.id.is_empty()
            && self.id.len() <= 64
            && self.id != RECOVERY
            && self.public.len() == 32
            && self.sign.len() == 32
    }
}

/// Members by id.
pub type Members = BTreeMap<String, Member>;

/// What an entry does.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "lowercase")]
pub enum Op {
    /// The space begins: the device that made it, and the recovery
    /// phrase's signing key.
    Genesis {
        device: Member,
        #[serde(with = "space::b64")]
        recovery: Vec<u8>,
    },
    /// A device joins: approved by the author, or by the phrase.
    Add { device: Member },
    /// A device leaves: unlinked by the author, or the author itself.
    Remove { device: String },
    /// A new recovery phrase, by its signing key.
    Phrase {
        #[serde(with = "space::b64")]
        recovery: Vec<u8>,
    },
}

/// One signed entry of the log.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Entry {
    /// The entries this one follows, by [Entry::id], sorted.
    pub parents: Vec<String>,
    pub op: Op,
    /// The author: a device id, or [RECOVERY] for the phrase.
    pub by: String,
    #[serde(with = "space::b64")]
    pub sig: Vec<u8>,
}

impl Entry {
    /// An entry by `by`, signed with the key made from `secret` (a
    /// device's secret, or [space::recovery_signer] of the phrase).
    pub fn new(mut parents: Vec<String>, op: Op, by: &str, secret: &Key) -> Entry {
        parents.sort();
        parents.dedup();
        let mut e = Entry {
            parents,
            op,
            by: by.to_owned(),
            sig: Vec::new(),
        };
        e.sig = space::sign(secret, &e.message());
        e
    }

    /// What the author signs: the parents, the operation (with every key
    /// in it) and the author's own id.
    fn message(&self) -> Vec<u8> {
        let mut m = b"piuma-mail log v1\0".to_vec();
        m.extend(serde_json::to_vec(&(&self.parents, &self.op, &self.by)).expect("serializes"));
        m
    }

    /// The entry's name: a hash of what was signed and the signature.
    pub fn id(&self) -> String {
        use sha2::Digest as _;
        let mut h = sha2::Sha256::new();
        h.update(b"piuma-mail entry\0");
        h.update(self.message());
        h.update(&self.sig);
        h.finalize().iter().map(|b| format!("{b:02x}")).collect()
    }

    /// Whether `public` signed this entry, named `id`. Answers are
    /// remembered (by a hash of the entry and the key): a log is read
    /// again on every round, and a copy full of bad signatures shouldn't
    /// cost a check each time.
    fn signed_by(&self, id: &str, public: &[u8]) -> bool {
        use sha2::Digest as _;
        static SEEN: std::sync::Mutex<BTreeMap<[u8; 32], bool>> =
            std::sync::Mutex::new(BTreeMap::new());
        let mut h = sha2::Sha256::new();
        h.update(id);
        h.update(public);
        let tag: [u8; 32] = h.finalize().into();
        let seen = || SEEN.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(&ok) = seen().get(&tag) {
            return ok;
        }
        let ok = space::verify(public, &self.message(), &self.sig);
        let mut s = seen();
        if s.len() >= 1 << 16 {
            s.clear();
        }
        s.insert(tag, ok);
        ok
    }

    /// Whether `public` signed it (remembered, as for every check).
    pub fn verified_by(&self, public: &[u8]) -> bool {
        self.signed_by(&self.id(), public)
    }

    /// Parents sorted with no repeats: one way to write each entry.
    fn canonical(&self) -> bool {
        self.parents.windows(2).all(|w| w[0] < w[1])
    }

    /// The device it removes, for a removal.
    pub fn removes(&self) -> Option<&str> {
        match &self.op {
            Op::Remove { device } => Some(device),
            _ => None,
        }
    }

    /// The device it adds (the space's maker, for the beginning).
    fn adds(&self) -> Option<&Member> {
        match &self.op {
            Op::Genesis { device, .. } | Op::Add { device } => Some(device),
            _ => None,
        }
    }

    /// The recovery phrase it puts in force.
    fn phrase(&self) -> Option<&[u8]> {
        match &self.op {
            Op::Genesis { recovery, .. } | Op::Phrase { recovery } => Some(recovery),
            _ => None,
        }
    }
}

/// Who belongs, as a log says.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct State {
    pub members: Members,
    /// Devices removed and not added again.
    pub removed: BTreeSet<String>,
    /// The signing key of the recovery phrase in force. None after a
    /// removal until a member replaces the phrase (the removed device knew
    /// it), or while two replacements made at once both stand.
    pub recovery: Option<Vec<u8>>,
    /// The newest entries that count: a new entry follows them.
    pub heads: Vec<String>,
}

/// What reading a log came to.
#[derive(Debug, Clone, Default)]
pub struct Eval {
    pub state: State,
    /// The entries that count.
    pub accepted: BTreeSet<String>,
    /// Those entries and every one they follow, oldest first: what a copy
    /// carries on.
    pub kept: Vec<Entry>,
    /// Devices in removals that contradict each other with nothing to tell
    /// which came first. Empty when the log is clear.
    pub conflict: BTreeSet<String>,
    /// More than [MAX_UNION] entries came from the beginning: nothing was
    /// read, and nothing that relies on it may be taken.
    pub overflow: bool,
}

impl Eval {
    /// Who removed `device`, by an entry that counts (the newest such).
    pub fn removed_by(&self, device: &str) -> Option<&str> {
        self.kept
            .iter()
            .rev()
            .filter(|e| e.removes() == Some(device))
            .find(|e| self.accepted.contains(&e.id()))
            .map(|e| e.by.as_str())
    }
}

/// The entries no other entry in `entries` follows, by id: where a new
/// entry goes, read as written (nothing checked).
pub fn tips(entries: &[Entry]) -> Vec<String> {
    let followed: BTreeSet<&str> = entries
        .iter()
        .flat_map(|e| e.parents.iter().map(String::as_str))
        .collect();
    let mut out: Vec<String> = entries
        .iter()
        .map(Entry::id)
        .filter(|id| !followed.contains(id.as_str()))
        .collect();
    out.sort();
    out.dedup();
    out
}

/// The beginnings (`Genesis` entries) among `entries`, by id.
pub fn roots(entries: &[Entry]) -> Vec<String> {
    let mut out: Vec<String> = entries
        .iter()
        .filter(|e| e.parents.is_empty() && matches!(e.op, Op::Genesis { .. }))
        .map(Entry::id)
        .collect();
    out.sort();
    out.dedup();
    out
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Label {
    Undecided,
    In,
    Out,
}

/// Ancestor sets as bits.
struct Bits {
    words: usize,
    data: Vec<u64>,
}

impl Bits {
    fn new(n: usize) -> Bits {
        let words = n.div_ceil(64);
        Bits {
            words,
            data: vec![0; words * n],
        }
    }

    fn has(&self, i: usize, j: usize) -> bool {
        self.data[i * self.words + j / 64] & (1 << (j % 64)) != 0
    }

    fn set(&mut self, i: usize, j: usize) {
        self.data[i * self.words + j / 64] |= 1 << (j % 64);
    }

    /// Row `i` |= row `j`, for `j < i`.
    fn merge(&mut self, i: usize, j: usize) {
        let w = self.words;
        let (low, high) = self.data.split_at_mut(i * w);
        for (a, b) in high[..w].iter_mut().zip(&low[j * w..(j + 1) * w]) {
            *a |= *b;
        }
    }
}

struct Graph {
    entries: Vec<Entry>,
    ids: Vec<String>,
    parents: Vec<Vec<usize>>,
    children: Vec<Vec<usize>>,
    /// `anc.has(i, j)`: j comes before i.
    anc: Bits,
}

impl Graph {
    /// `entries` that descend from `root`, in an order every device
    /// shares: parents first, then by id. None when more than [MAX_UNION]
    /// do.
    fn build(entries: impl IntoIterator<Item = Entry>, root: &str) -> Option<Graph> {
        // Every copy carries much the same log: repeats go before hashing.
        let unique: HashSet<Entry> = entries.into_iter().filter(Entry::canonical).collect();
        let all: Vec<(String, Entry)> = unique.into_iter().map(|e| (e.id(), e)).collect();
        let index: HashMap<&str, usize> = all
            .iter()
            .enumerate()
            .map(|(i, (id, _))| (id.as_str(), i))
            .collect();
        let mut waiting: Vec<usize> = Vec::with_capacity(all.len());
        let mut children: Vec<Vec<usize>> = vec![Vec::new(); all.len()];
        for (i, (_, e)) in all.iter().enumerate() {
            waiting.push(e.parents.len());
            for p in &e.parents {
                if let Some(&pi) = index.get(p.as_str()) {
                    children[pi].push(i);
                }
            }
        }
        let mut ready: BTreeSet<(&str, usize)> = BTreeSet::new();
        if let Some(&r) = index.get(root) {
            let e = &all[r].1;
            if e.parents.is_empty() && matches!(e.op, Op::Genesis { .. }) {
                ready.insert((root, r));
            }
        }
        let mut order: Vec<usize> = Vec::new();
        while let Some((_, i)) = ready.pop_first() {
            if order.len() == MAX_UNION {
                return None;
            }
            order.push(i);
            for &c in &children[i] {
                waiting[c] -= 1;
                if waiting[c] == 0 {
                    ready.insert((all[c].0.as_str(), c));
                }
            }
        }
        let n = order.len();
        let mut at = vec![usize::MAX; all.len()];
        for (k, &i) in order.iter().enumerate() {
            at[i] = k;
        }
        let mut anc = Bits::new(n);
        let mut parents = Vec::with_capacity(n);
        let mut kids = vec![Vec::new(); n];
        for (k, &i) in order.iter().enumerate() {
            let ps: Vec<usize> = all[i]
                .1
                .parents
                .iter()
                .map(|p| at[index[p.as_str()]])
                .collect();
            for &p in &ps {
                anc.set(k, p);
                anc.merge(k, p);
                kids[p].push(k);
            }
            parents.push(ps);
        }
        let mut slots: Vec<Option<(String, Entry)>> = all.into_iter().map(Some).collect();
        let (ids, entries) = order
            .iter()
            .map(|&i| slots[i].take().expect("each entry once"))
            .unzip();
        Some(Graph {
            entries,
            ids,
            parents,
            children: kids,
            anc,
        })
    }

    fn concurrent(&self, i: usize, j: usize) -> bool {
        i != j && !self.anc.has(i, j) && !self.anc.has(j, i)
    }
}

/// The entries that count so far, by kind, to read the state before any
/// entry from its ancestors alone: who belongs, and the phrase in force.
#[derive(Default)]
struct Counted<'g> {
    adds: HashMap<&'g str, Vec<usize>>,
    removes: HashMap<&'g str, Vec<usize>>,
    removals: Vec<usize>,
    phrases: Vec<usize>,
}

impl<'g> Counted<'g> {
    fn take(&mut self, g: &'g Graph, i: usize) {
        let e = &g.entries[i];
        if let Some(m) = e.adds() {
            self.adds.entry(m.id.as_str()).or_default().push(i);
        }
        if let Some(d) = e.removes() {
            self.removes.entry(d).or_default().push(i);
            self.removals.push(i);
        }
        if e.phrase().is_some() {
            self.phrases.push(i);
        }
    }

    /// `device` as a member before entry `at` (`at == None`: after them
    /// all). An add counts if every removal of that device came before
    /// it; of those, the one last in the shared order gives the keys.
    fn member(&self, g: &'g Graph, at: Option<usize>, device: &str) -> Option<&'g Member> {
        let before = |j: usize| at.is_none_or(|i| g.anc.has(i, j));
        let gone: Vec<usize> = self
            .removes
            .get(device)
            .into_iter()
            .flatten()
            .copied()
            .filter(|&r| before(r))
            .collect();
        // An add after every removal comes later in the shared order than
        // each of them: only those are looked at.
        let last = gone.iter().copied().max();
        let mut adds: Vec<usize> = self
            .adds
            .get(device)?
            .iter()
            .copied()
            .filter(|&a| last.is_none_or(|r| a > r) && before(a))
            .collect();
        adds.sort_unstable_by(|a, b| b.cmp(a));
        adds.into_iter()
            .find(|&a| gone.iter().all(|&r| g.anc.has(a, r)))
            .and_then(|a| g.entries[a].adds())
    }

    /// The phrase in force before entry `at` (`None`: after them all):
    /// the one replacement every other came before, and every removal
    /// too.
    fn recovery(&self, g: &'g Graph, at: Option<usize>) -> Option<&'g [u8]> {
        let before = |j: usize| at.is_none_or(|i| g.anc.has(i, j));
        let phrases: Vec<usize> = self
            .phrases
            .iter()
            .copied()
            .filter(|&p| before(p))
            .collect();
        let &last = phrases.iter().max()?;
        let alone = phrases.iter().all(|&p| p == last || g.anc.has(last, p));
        let settled = self
            .removals
            .iter()
            .all(|&r| !before(r) || g.anc.has(last, r));
        (alone && settled)
            .then(|| g.entries[last].phrase())
            .flatten()
    }
}

/// Whether entry `i` may be applied on top of the entries before it.
fn authorized(g: &Graph, counted: &Counted<'_>, i: usize) -> bool {
    let e = &g.entries[i];
    let key: &[u8] = if e.by == RECOVERY {
        // The phrase only ever adds a device, and only while it stands.
        match (&e.op, counted.recovery(g, Some(i))) {
            (Op::Add { .. }, Some(k)) => k,
            _ => return false,
        }
    } else {
        match counted.member(g, Some(i), &e.by) {
            Some(m) => &m.sign,
            None => return false,
        }
    };
    if !e.signed_by(&g.ids[i], key) {
        return false;
    }
    match &e.op {
        Op::Genesis { .. } => false,
        Op::Add { device } => device.valid() && counted.member(g, Some(i), &device.id).is_none(),
        Op::Remove { device } => counted.member(g, Some(i), device).is_some(),
        Op::Phrase { recovery } => recovery.len() == 32,
    }
}

/// Reads the log made of `entries` (from every copy and from this device,
/// in any order and with repeats) from its beginning `root`. `own` are
/// removals this device made: it knows they are genuine, so one stands
/// against a removal of this device made beside it. Nobody else's
/// removal gets that: a device can't tell a genuine one from a back-dated
/// one by which it saw first.
///
/// Each entry is read once its parents are, from what counts among its
/// ancestors; one that waits on a removal made beside it is read again
/// when that removal is decided. Entries still waiting at the end are
/// removals that contradict each other ([Eval::conflict]).
pub fn evaluate(
    entries: impl IntoIterator<Item = Entry>,
    root: &str,
    own: &BTreeSet<String>,
) -> Eval {
    let Some(g) = Graph::build(entries, root) else {
        return Eval {
            overflow: true,
            ..Eval::default()
        };
    };
    let n = g.entries.len();
    let genesis_ok = n > 0
        && match &g.entries[0].op {
            Op::Genesis { device, recovery } => {
                g.entries[0].by == device.id
                    && device.valid()
                    && recovery.len() == 32
                    && g.entries[0].signed_by(&g.ids[0], &device.sign)
            }
            _ => false,
        };
    if !genesis_ok {
        return Eval::default();
    }
    // What can undo each entry: removals of its author, and for the phrase
    // any removal or replacement.
    let mut removals_of: HashMap<&str, Vec<usize>> = HashMap::new();
    let mut turns: Vec<usize> = Vec::new();
    for (i, e) in g.entries.iter().enumerate() {
        if let Some(d) = e.removes() {
            removals_of.entry(d).or_default().push(i);
            turns.push(i);
        }
        if matches!(e.op, Op::Phrase { .. }) {
            turns.push(i);
        }
    }
    let mut labels = vec![Label::Undecided; n];
    let mut counted = Counted::default();
    labels[0] = Label::In;
    counted.take(&g, 0);
    // This device's own removals stand, whatever was made beside them.
    for i in 1..n {
        if g.entries[i].removes().is_some() && own.contains(&g.ids[i]) {
            labels[i] = Label::In;
        }
    }
    // Parents not yet read, entries ready to read, entries waiting on a
    // removal made beside them.
    let mut unread: Vec<usize> = g.parents.iter().map(Vec::len).collect();
    let mut ready: Vec<usize> = Vec::new();
    let mut waiters: Vec<Vec<usize>> = vec![Vec::new(); n];
    let mut read = vec![false; n];
    read[0] = true;
    for &c in &g.children[0] {
        unread[c] -= 1;
        if unread[c] == 0 {
            ready.push(c);
        }
    }
    while let Some(i) = ready.pop() {
        if read[i] {
            continue;
        }
        if labels[i] == Label::Undecided {
            let e = &g.entries[i];
            let against: Vec<usize> = if e.by == RECOVERY {
                &turns
            } else {
                removals_of
                    .get(e.by.as_str())
                    .map(Vec::as_slice)
                    .unwrap_or_default()
            }
            .iter()
            .copied()
            .filter(|&r| g.concurrent(i, r))
            .collect();
            let label = if against.iter().any(|&r| labels[r] == Label::In)
                || !authorized(&g, &counted, i)
            {
                Label::Out
            } else if against.iter().any(|&r| labels[r] == Label::Undecided) {
                for &r in &against {
                    if labels[r] == Label::Undecided {
                        waiters[r].push(i);
                    }
                }
                continue;
            } else {
                Label::In
            };
            labels[i] = label;
        }
        // Decided, with everything before it: its children may be read,
        // and whatever waited on it read again.
        read[i] = true;
        if labels[i] == Label::In {
            counted.take(&g, i);
        }
        ready.append(&mut waiters[i]);
        for &c in &g.children[i] {
            unread[c] -= 1;
            if unread[c] == 0 {
                ready.push(c);
            }
        }
    }
    // What still waits with everything before it read: the removals that
    // contradict each other, and what they undo (what follows them waits
    // only because they do).
    let mut conflict = BTreeSet::new();
    for i in 0..n {
        if read[i] {
            continue;
        }
        if g.parents[i].iter().all(|&p| read[p]) {
            let e = &g.entries[i];
            if let Some(d) = e.removes() {
                conflict.insert(d.to_owned());
            }
            if e.by != RECOVERY {
                conflict.insert(e.by.clone());
            }
        }
        // An own removal waiting on its parents counts for nothing yet.
        labels[i] = Label::Undecided;
    }
    // Who belongs after everything that counts, and its newest entries.
    let mut state = State::default();
    let ids: BTreeSet<&str> = counted.adds.keys().copied().collect();
    for id in ids {
        if let Some(m) = counted.member(&g, None, id) {
            state.members.insert(id.to_owned(), m.clone());
        }
    }
    for id in counted.removes.keys() {
        if !state.members.contains_key(*id) {
            state.removed.insert((*id).to_owned());
        }
    }
    state.recovery = counted.recovery(&g, None).map(<[u8]>::to_vec);
    let mut followed = vec![false; n];
    let mut keep = vec![false; n];
    for i in (0..n).rev() {
        let counts = labels[i] == Label::In;
        if counts && !followed[i] {
            state.heads.push(g.ids[i].clone());
        }
        keep[i] |= counts;
        for &p in &g.parents[i] {
            followed[p] |= counts || followed[i];
            keep[p] |= keep[i];
        }
    }
    state.heads.sort();
    Eval {
        state,
        accepted: (0..n)
            .filter(|&i| labels[i] == Label::In)
            .map(|i| g.ids[i].clone())
            .collect(),
        kept: (0..n)
            .filter(|&i| keep[i])
            .map(|i| g.entries[i].clone())
            .collect(),
        conflict,
        overflow: false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct D {
        m: Member,
        k: Key,
    }

    fn d(id: &str) -> D {
        let k = Key::generate();
        D {
            m: Member {
                id: id.into(),
                public: space::public_key(&k),
                sign: space::sign_public(&k),
            },
            k,
        }
    }

    fn phrase(k: &Key) -> Vec<u8> {
        space::sign_public(&space::recovery_signer(k))
    }

    fn start(a: &D, recovery: &Key) -> Entry {
        Entry::new(
            vec![],
            Op::Genesis {
                device: a.m.clone(),
                recovery: phrase(recovery),
            },
            &a.m.id,
            &a.k,
        )
    }

    fn after(parents: &[&Entry], op: Op, by: &D) -> Entry {
        Entry::new(
            parents.iter().map(|e| e.id()).collect(),
            op,
            &by.m.id,
            &by.k,
        )
    }

    fn add(x: &D) -> Op {
        Op::Add {
            device: x.m.clone(),
        }
    }

    fn remove(x: &D) -> Op {
        Op::Remove {
            device: x.m.id.clone(),
        }
    }

    fn ids(s: &State) -> Vec<&str> {
        s.members.keys().map(String::as_str).collect()
    }

    #[test]
    fn members_follow_the_entries_in_order() {
        let (a, b, c) = (d("a"), d("b"), d("c"));
        let r = Key::generate();
        let g = start(&a, &r);
        let ab = after(&[&g], add(&b), &a);
        let bc = after(&[&ab], add(&c), &b);
        let rc = after(&[&bc], remove(&c), &a);
        let e = evaluate([g.clone(), ab, bc, rc.clone()], &g.id(), &BTreeSet::new());
        assert_eq!(ids(&e.state), ["a", "b"]);
        assert!(e.state.removed.contains("c"));
        assert!(e.conflict.is_empty());
        // The phrase was known to the removed device: it adds nobody now.
        assert_eq!(e.state.recovery, None);
        assert_eq!(e.state.heads, [rc.id()]);
    }

    #[test]
    fn a_forged_or_altered_entry_does_not_count() {
        let (a, b, x) = (d("a"), d("b"), d("x"));
        let g = start(&a, &Key::generate());
        // Signed by x, claiming to be a.
        let mut forged = Entry::new(vec![g.id()], add(&b), "a", &x.k);
        let e = evaluate([g.clone(), forged.clone()], &g.id(), &BTreeSet::new());
        assert_eq!(ids(&e.state), ["a"]);
        // Its device swapped after signing.
        forged = after(&[&g], add(&b), &a);
        forged.op = add(&x);
        let e = evaluate([g.clone(), forged], &g.id(), &BTreeSet::new());
        assert_eq!(ids(&e.state), ["a"]);
    }

    #[test]
    fn what_a_device_does_without_knowing_it_was_removed_does_not_count() {
        let (a, b, c, x) = (d("a"), d("b"), d("c"), d("x"));
        let g = start(&a, &Key::generate());
        let ab = after(&[&g], add(&b), &a);
        let ac = after(&[&ab], add(&c), &a);
        // A unlinks C; C, from before, vouches for X and unlinks A.
        let rc = after(&[&ac], remove(&c), &a);
        let cx = after(&[&ac], add(&x), &c);
        let e = evaluate(
            [g.clone(), ab.clone(), ac.clone(), rc.clone(), cx.clone()],
            &g.id(),
            &BTreeSet::new(),
        );
        assert_eq!(ids(&e.state), ["a", "b"]);
        // On A, which made its removal of C, C's made-up unlink of A loses.
        let ra = after(&[&ac], remove(&a), &c);
        let own: BTreeSet<String> = [rc.id()].into();
        let all = [g.clone(), ab, ac, rc, cx, ra];
        let e = evaluate(all.clone(), &g.id(), &own);
        assert!(e.conflict.is_empty());
        assert_eq!(ids(&e.state), ["a", "b"]);
        // On a device that saw neither first, nothing tells which is
        // genuine: it stops.
        let e = evaluate(all, &g.id(), &BTreeSet::new());
        assert_eq!(
            e.conflict.iter().map(String::as_str).collect::<Vec<_>>(),
            ["a", "c"]
        );
    }

    #[test]
    fn the_phrase_adds_only_while_it_stands() {
        let (a, b, x, y) = (d("a"), d("b"), d("x"), d("y"));
        let old = Key::generate();
        let new = Key::generate();
        let g = start(&a, &old);
        let ab = after(&[&g], add(&b), &a);
        let by_phrase = |parents: &[&Entry], who: &D, k: &Key| {
            Entry::new(
                parents.iter().map(|e| e.id()).collect(),
                add(who),
                RECOVERY,
                &space::recovery_signer(k),
            )
        };
        // B leaves: the phrase it knew adds nobody after.
        let rb = after(&[&ab], remove(&b), &b);
        let late = by_phrase(&[&rb], &x, &old);
        // ...nor at the same time.
        let side = by_phrase(&[&ab], &y, &old);
        let e = evaluate(
            [g.clone(), ab.clone(), rb.clone(), late, side],
            &g.id(),
            &BTreeSet::new(),
        );
        assert_eq!(ids(&e.state), ["a"]);
        // A replaces it: the new one adds, the old one doesn't.
        let p = after(
            &[&rb],
            Op::Phrase {
                recovery: phrase(&new),
            },
            &a,
        );
        let ok = by_phrase(&[&p], &x, &new);
        let stale = by_phrase(&[&p], &y, &old);
        let e = evaluate([g.clone(), ab, rb, p, ok, stale], &g.id(), &BTreeSet::new());
        assert_eq!(ids(&e.state), ["a", "x"]);
    }

    #[test]
    fn two_unlinks_at_once_both_stand_and_the_phrase_must_change() {
        let (a, b, e1, f) = (d("a"), d("b"), d("e"), d("f"));
        let g = start(&a, &Key::generate());
        let ab = after(&[&g], add(&b), &a);
        let ae = after(&[&ab], add(&e1), &a);
        let af = after(&[&ae], add(&f), &a);
        let re = after(&[&af], remove(&e1), &a);
        let pa = after(
            &[&re],
            Op::Phrase {
                recovery: phrase(&Key::generate()),
            },
            &a,
        );
        let rf = after(&[&af], remove(&f), &b);
        let pb = after(
            &[&rf],
            Op::Phrase {
                recovery: phrase(&Key::generate()),
            },
            &b,
        );
        let e = evaluate(
            [g.clone(), ab, ae, af, re, pa, rf, pb],
            &g.id(),
            &BTreeSet::new(),
        );
        assert!(e.conflict.is_empty());
        assert_eq!(ids(&e.state), ["a", "b"]);
        assert_eq!(e.state.recovery, None);
        assert_eq!(e.state.heads.len(), 2);
    }

    /// The removed device deletes the genuine unlink from the folder and
    /// puts its own, back-dated, in its place: a device that sees that one
    /// first takes it (it can't know better), but once it sees the genuine
    /// one too it stops, whatever it did in between. Only the device that
    /// made the genuine removal goes on.
    #[test]
    fn a_back_dated_removal_seen_first_is_not_taken_for_genuine() {
        let (a, b, c) = (d("a"), d("b"), d("c"));
        let g = start(&a, &Key::generate());
        let ab = after(&[&g], add(&b), &a);
        let ac = after(&[&ab], add(&c), &a);
        let rc = after(&[&ac], remove(&c), &a);
        let ra = after(&[&ac], remove(&a), &c);
        let none = BTreeSet::new();
        let first = evaluate(
            [g.clone(), ab.clone(), ac.clone(), ra.clone()],
            &g.id(),
            &none,
        );
        assert_eq!(ids(&first.state), ["b", "c"]);
        // B wrote after it (a new phrase, as a device does after a removal).
        let pb = after(
            &[&ra],
            Op::Phrase {
                recovery: phrase(&Key::generate()),
            },
            &b,
        );
        let mut log = first.kept.clone();
        log.push(pb.clone());
        let all = [g.clone(), ab, ac, rc.clone(), ra, pb];
        let e = evaluate(log.into_iter().chain(all.clone()), &g.id(), &none);
        assert_eq!(
            e.conflict.iter().map(String::as_str).collect::<Vec<_>>(),
            ["a", "c"]
        );
        // A stands by its own.
        let e = evaluate(all, &g.id(), &[rc.id()].into());
        assert!(e.conflict.is_empty());
        assert_eq!(ids(&e.state), ["a", "b"]);
    }

    /// A log as long as a copy may carry, beside a removed device's branch
    /// as long again, reads in well under a second, and faster again from
    /// signatures already checked. (Signature crates are optimised in debug
    /// builds too, see the workspace's Cargo.toml: unoptimised, each check
    /// takes milliseconds.)
    #[test]
    fn a_full_log_reads_quickly() {
        let (a, x) = (d("a"), d("x"));
        let g = start(&a, &Key::generate());
        let mut log = vec![g.clone()];
        let p = phrase(&Key::generate());
        for i in 1..MAX_ENTRIES {
            let op = match i % 3 {
                1 => add(&x),
                2 => remove(&x),
                _ => Op::Phrase {
                    recovery: p.clone(),
                },
            };
            log.push(after(&[log.last().expect("one")], op, &a));
        }
        // A removed device's side branch, as long again: none of it counts.
        let (b, c) = (d("b"), d("c"));
        let ab = after(&[&g], add(&b), &a);
        let ac = after(&[&ab], add(&c), &a);
        let rc = after(&[&ac], remove(&c), &a);
        let mut side = vec![ac.clone()];
        for _ in 1..MAX_ENTRIES - 3 {
            let op = Op::Phrase {
                recovery: p.clone(),
            };
            side.push(after(&[side.last().expect("one")], op, &c));
        }
        let all: Vec<Entry> = log
            .iter()
            .cloned()
            .chain([ab, rc.clone()])
            .chain(side)
            .collect();
        for round in 0..2 {
            let t = std::time::Instant::now();
            let e = evaluate(all.iter().cloned(), &g.id(), &BTreeSet::new());
            let took = t.elapsed().as_secs_f64();
            eprintln!("round {round}: {} entries in {took:.2} s", all.len());
            assert!(took < 5.0, "{took} s");
            assert!(!e.overflow && e.conflict.is_empty());
            assert_eq!(ids(&e.state), ["a", "b"]);
            assert!(e.accepted.contains(&rc.id()));
            assert_eq!(e.accepted.len(), MAX_ENTRIES + 3);
        }
    }

    /// Past [MAX_UNION] entries nothing is read: none is left out silently,
    /// which would let whoever filled the folder choose which.
    #[test]
    fn too_many_entries_are_an_error_not_a_cut() {
        let a = d("a");
        let g = start(&a, &Key::generate());
        let mut log = vec![g.clone()];
        for _ in 0..MAX_UNION {
            // Unsigned: too many is found before any signature is checked.
            let e = Entry {
                parents: vec![log.last().expect("one").id()],
                op: Op::Phrase {
                    recovery: vec![0; 32],
                },
                by: "a".into(),
                sig: Vec::new(),
            };
            log.push(e);
        }
        let e = evaluate(log.clone(), &g.id(), &BTreeSet::new());
        assert!(e.overflow);
        assert!(e.accepted.is_empty() && e.state.members.is_empty());
        log.truncate(MAX_UNION);
        let e = evaluate(log, &g.id(), &BTreeSet::new());
        assert!(!e.overflow);
        assert_eq!(ids(&e.state), ["a"]);
    }
}
