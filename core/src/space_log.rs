//! Who belongs to the sync space: a signed, ordered record of every device
//! added and removed (the membership log), carried sealed in every copy.
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
//! - Removals a device already took stay taken ([evaluate]'s `fixed`):
//!   a removed device can't undo its unlink by making up an older one.
//! - When two removals each remove the other's author and neither came
//!   first, nothing tells which is genuine: [Eval::conflict] names those
//!   devices and the device stops until the person links it again.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::space::{self, Device, Key, RECOVERY};

/// Entries a copy may carry: years of linking and unlinking stay far
/// under it.
pub const MAX_ENTRIES: usize = 4096;

/// Entries looked at in one evaluation, from every copy together.
const MAX_UNION: usize = 2 * MAX_ENTRIES;

/// A device as the log knows it: its id and its two public keys.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
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
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
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
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
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

    /// Whether `public` signed it. Checks that passed are remembered (by a
    /// hash of the entry and the key): a log is read again on every round.
    fn signed_by(&self, public: &[u8]) -> bool {
        use sha2::Digest as _;
        static PASSED: std::sync::Mutex<BTreeSet<[u8; 32]>> =
            std::sync::Mutex::new(BTreeSet::new());
        let mut h = sha2::Sha256::new();
        h.update(self.id());
        h.update(public);
        let tag: [u8; 32] = h.finalize().into();
        let passed = || PASSED.lock().unwrap_or_else(|e| e.into_inner());
        if passed().contains(&tag) {
            return true;
        }
        let ok = space::verify(public, &self.message(), &self.sig);
        if ok {
            let mut p = passed();
            if p.len() >= 1 << 16 {
                p.clear();
            }
            p.insert(tag);
        }
        ok
    }

    /// Parents sorted with no repeats: one way to write each entry.
    fn canonical(&self) -> bool {
        self.parents.windows(2).all(|w| w[0] < w[1])
    }

    /// The device it removes, for a removal.
    fn removes(&self) -> Option<&str> {
        match &self.op {
            Op::Remove { device } => Some(device),
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
}

impl Eval {
    /// The removals that count, for [evaluate]'s `fixed` next time.
    pub fn removals(&self) -> BTreeSet<String> {
        self.kept
            .iter()
            .filter(|e| e.removes().is_some())
            .map(Entry::id)
            .filter(|id| self.accepted.contains(id))
            .collect()
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

    /// Row `i` |= row `j`.
    fn merge(&mut self, i: usize, j: usize) {
        for w in 0..self.words {
            self.data[i * self.words + w] |= self.data[j * self.words + w];
        }
    }
}

struct Graph {
    entries: Vec<Entry>,
    ids: Vec<String>,
    parents: Vec<Vec<usize>>,
    /// `anc.has(i, j)`: j comes before i.
    anc: Bits,
}

impl Graph {
    /// `entries` that descend from `root`, in an order every device
    /// shares: parents first, then by id.
    fn build(entries: impl IntoIterator<Item = Entry>, root: &str) -> Graph {
        let mut by_id: BTreeMap<String, Entry> = BTreeMap::new();
        for e in entries {
            if by_id.len() >= MAX_UNION {
                break;
            }
            if e.canonical() {
                by_id.entry(e.id()).or_insert(e);
            }
        }
        let mut children: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
        let mut waiting: BTreeMap<&str, usize> = BTreeMap::new();
        for (id, e) in &by_id {
            waiting.insert(id, e.parents.len());
            for p in &e.parents {
                children.entry(p).or_default().push(id);
            }
        }
        let mut ready: BTreeSet<&str> = BTreeSet::new();
        if let Some(e) = by_id.get(root) {
            if e.parents.is_empty() && matches!(e.op, Op::Genesis { .. }) {
                ready.insert(root);
            }
        }
        let mut order: Vec<&str> = Vec::new();
        while let Some(id) = ready.pop_first() {
            order.push(id);
            for c in children.get(id).into_iter().flatten() {
                let w = waiting.get_mut(c).expect("every entry waits");
                *w -= 1;
                if *w == 0 {
                    ready.insert(c);
                }
            }
        }
        let index: BTreeMap<&str, usize> =
            order.iter().enumerate().map(|(i, id)| (*id, i)).collect();
        let n = order.len();
        let mut anc = Bits::new(n);
        let mut parents = Vec::with_capacity(n);
        for (i, id) in order.iter().enumerate() {
            let ps: Vec<usize> = by_id[*id]
                .parents
                .iter()
                .map(|p| index[p.as_str()])
                .collect();
            for &p in &ps {
                anc.set(i, p);
                anc.merge(i, p);
            }
            parents.push(ps);
        }
        let ids: Vec<String> = order.iter().map(|s| (*s).to_owned()).collect();
        let entries = ids.iter().map(|id| by_id[id].clone()).collect();
        Graph {
            entries,
            ids,
            parents,
            anc,
        }
    }

    fn concurrent(&self, i: usize, j: usize) -> bool {
        i != j && !self.anc.has(i, j) && !self.anc.has(j, i)
    }

    /// Who belongs after the entries `within` says, of those labelled In.
    fn fold(&self, labels: &[Label], within: impl Fn(usize) -> bool, heads: bool) -> State {
        let live: Vec<usize> = (0..self.entries.len())
            .filter(|&i| labels[i] == Label::In && within(i))
            .collect();
        let mut adds: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
        let mut removes: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
        let mut phrases: Vec<usize> = Vec::new();
        for &i in &live {
            match &self.entries[i].op {
                Op::Genesis { device, .. } => {
                    adds.entry(&device.id).or_default().push(i);
                    phrases.push(i);
                }
                Op::Add { device } => adds.entry(&device.id).or_default().push(i),
                Op::Remove { device } => removes.entry(device).or_default().push(i),
                Op::Phrase { .. } => phrases.push(i),
            }
        }
        let mut st = State::default();
        for (id, list) in &adds {
            let gone = removes.get(id).map(Vec::as_slice).unwrap_or_default();
            // An add counts if every removal of that device came before it:
            // a removal at the same time as an add wins.
            let add = list
                .iter()
                .rev()
                .find(|&&a| gone.iter().all(|&r| self.anc.has(a, r)));
            if let Some(&a) = add {
                let m = match &self.entries[a].op {
                    Op::Genesis { device, .. } | Op::Add { device } => device.clone(),
                    _ => unreachable!("adds hold adds"),
                };
                st.members.insert((*id).to_owned(), m);
            }
        }
        for id in removes.keys() {
            if !st.members.contains_key(*id) {
                st.removed.insert((*id).to_owned());
            }
        }
        let tips: Vec<usize> = phrases
            .iter()
            .copied()
            .filter(|&p| !phrases.iter().any(|&q| q != p && self.anc.has(q, p)))
            .collect();
        if let [p] = tips[..] {
            let all_removals_before = removes.values().flatten().all(|&r| self.anc.has(p, r));
            if all_removals_before {
                st.recovery = match &self.entries[p].op {
                    Op::Genesis { recovery, .. } | Op::Phrase { recovery } => {
                        Some(recovery.clone())
                    }
                    _ => None,
                };
            }
        }
        if heads {
            st.heads = live
                .iter()
                .filter(|&&i| !live.iter().any(|&j| self.anc.has(j, i)))
                .map(|&i| self.ids[i].clone())
                .collect();
            st.heads.sort();
        }
        st
    }
}

/// Whether `e` may be applied on top of `st`.
fn authorized(e: &Entry, st: &State) -> bool {
    let key = if e.by == RECOVERY {
        // The phrase only ever adds a device, and only while it stands.
        match (&e.op, &st.recovery) {
            (Op::Add { .. }, Some(k)) => k.clone(),
            _ => return false,
        }
    } else {
        match st.members.get(&e.by) {
            Some(m) => m.sign.clone(),
            None => return false,
        }
    };
    if !e.signed_by(&key) {
        return false;
    }
    match &e.op {
        Op::Genesis { .. } => false,
        Op::Add { device } => device.valid() && !st.members.contains_key(&device.id),
        Op::Remove { device } => st.members.contains_key(device),
        Op::Phrase { recovery } => recovery.len() == 32,
    }
}

/// Reads the log made of `entries` (from every copy and from this device,
/// in any order and with repeats) from its beginning `root`. `fixed` are
/// removals this device took before: they stand whatever else comes in.
pub fn evaluate(
    entries: impl IntoIterator<Item = Entry>,
    root: &str,
    fixed: &BTreeSet<String>,
) -> Eval {
    let g = Graph::build(entries, root);
    let n = g.entries.len();
    let mut labels = vec![Label::Undecided; n];
    let genesis_ok = n > 0
        && match &g.entries[0].op {
            Op::Genesis { device, recovery } => {
                g.entries[0].by == device.id
                    && device.valid()
                    && recovery.len() == 32
                    && g.entries[0].signed_by(&device.sign)
            }
            _ => false,
        };
    if !genesis_ok {
        return Eval::default();
    }
    labels[0] = Label::In;
    for i in 1..n {
        if g.entries[i].removes().is_some() && fixed.contains(&g.ids[i]) {
            labels[i] = Label::In;
        }
    }
    // What can undo each entry: removals of its author, and for the phrase
    // any removal or replacement.
    let mut removals_of: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
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
    let mut states: Vec<Option<State>> = vec![None; n];
    loop {
        let mut changed = false;
        // Settled: decided, and so is everything before it.
        let mut settled = vec![false; n];
        for i in 0..n {
            settled[i] = labels[i] != Label::Undecided && g.parents[i].iter().all(|&p| settled[p]);
        }
        for i in 1..n {
            if labels[i] != Label::Undecided || !g.parents[i].iter().all(|&p| settled[p]) {
                continue;
            }
            let e = &g.entries[i];
            let st = states[i].get_or_insert_with(|| g.fold(&labels, |j| g.anc.has(i, j), false));
            if !authorized(e, st) {
                labels[i] = Label::Out;
                changed = true;
                continue;
            }
            let against: &[usize] = if e.by == RECOVERY {
                &turns
            } else {
                removals_of
                    .get(e.by.as_str())
                    .map(Vec::as_slice)
                    .unwrap_or_default()
            };
            let against = against.iter().copied().filter(|&r| g.concurrent(i, r));
            let mut all_out = true;
            let mut any_in = false;
            for r in against {
                match labels[r] {
                    Label::In => any_in = true,
                    Label::Undecided => all_out = false,
                    Label::Out => {}
                }
            }
            if any_in {
                labels[i] = Label::Out;
                changed = true;
            } else if all_out {
                labels[i] = Label::In;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    let mut conflict = BTreeSet::new();
    for i in 0..n {
        if labels[i] == Label::Undecided {
            let e = &g.entries[i];
            if let Some(d) = e.removes() {
                conflict.insert(d.to_owned());
            }
            if e.by != RECOVERY {
                conflict.insert(e.by.clone());
            }
        }
    }
    let state = g.fold(&labels, |_| true, true);
    // What counts and everything it follows.
    let mut keep = vec![false; n];
    for i in (0..n).rev() {
        if labels[i] == Label::In {
            keep[i] = true;
        }
        if keep[i] {
            for &p in &g.parents[i] {
                keep[p] = true;
            }
        }
    }
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
        // On A, which took its removal of C, C's made-up unlink of A loses.
        let ra = after(&[&ac], remove(&a), &c);
        let fixed: BTreeSet<String> = [rc.id()].into();
        let all = [g.clone(), ab, ac, rc, cx, ra];
        let e = evaluate(all.clone(), &g.id(), &fixed);
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
}
