//! Which copies of the sync space a device takes, by who signed them.
//!
//! Every device has a signing key (Ed25519, made from its own secret) and
//! signs every copy it writes. A device keeps the devices it trusts, each
//! with its signing key ([Trust]): the ones listed in the space when it
//! joined, then every device another trusted device vouched for (the
//! device that approved it, or the recovery phrase). An unlink is a signed
//! statement ([Unlink]) carried in the content: from then on, copies the
//! unlinked device signs are refused, whatever key sealed them and
//! whatever generation they claim. A copy older than the newest one taken
//! is refused too, and so is one that jumps too far ahead ([MAX_JUMP]).
//!
//! No content key chain is needed: a copy from a trusted signer is taken
//! with whatever key it was sealed with, so a device that slept through
//! any number of unlinks follows as long as it can open its own wrap.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::space::{self, Device, SealedSpace, Space, Unlink, RECOVERY};

/// How far ahead of the newest generation a device took a copy may be: a
/// device writes once per change, so years of use stay well under it; a
/// forged copy claiming a huge generation to shadow the real ones doesn't.
pub const MAX_JUMP: u64 = 100_000;

/// Signed unlinks a space keeps, the newest.
pub const KEPT_UNLINKS: usize = 64;

/// What a device trusts, kept in its own database.
#[derive(Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Trust {
    /// Device id → signing key, in hex. Empty for a device listed by the
    /// old format: its first copy signed with a key it vouches for itself
    /// sets it.
    #[serde(default)]
    pub devices: BTreeMap<String, String>,
    /// Devices unlinked by a signed statement.
    #[serde(default)]
    pub revoked: BTreeSet<String>,
    /// The recovery phrase's signing key, in hex.
    #[serde(default)]
    pub recovery: String,
    /// The newest generation taken.
    #[serde(default)]
    pub generation: u64,
}

impl std::fmt::Debug for Trust {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Trust")
            .field("devices", &self.devices.keys().collect::<Vec<_>>())
            .field("revoked", &self.revoked)
            .field("generation", &self.generation)
            .finish()
    }
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex(s: &str) -> Vec<u8> {
    (0..s.len() / 2)
        .filter_map(|i| u8::from_str_radix(s.get(2 * i..2 * i + 2)?, 16).ok())
        .collect()
}

impl Trust {
    /// Trust as a device that made the space, or took it in with a code or
    /// the phrase, starts: the devices `space` lists.
    pub fn from_space(space: &Space) -> Trust {
        Trust {
            devices: space
                .content
                .devices
                .iter()
                .map(|d| (d.id.clone(), hex(&d.sign)))
                .collect(),
            revoked: BTreeSet::new(),
            recovery: hex(&space.content.recovery_sign()),
            generation: space.content.generation,
        }
    }

    /// This device trusts itself, with its own key.
    pub fn me(&mut self, device: &Device) {
        self.revoked.remove(&device.id);
        self.devices.insert(device.id.clone(), hex(&device.sign));
    }

    fn key(&self, id: &str) -> Option<Vec<u8>> {
        self.devices.get(id).map(|k| unhex(k))
    }
}

/// What judging the stored copies came to.
pub struct Verdict {
    /// Indexes of the copies taken.
    pub accepted: Vec<usize>,
    /// Copies left out: older, from an unlinked device, unsigned or
    /// signed by a device not trusted.
    pub refused: u32,
    /// Trust after taking them.
    pub trust: Trust,
    /// Every unlink signed by a trusted device, to carry on.
    pub unlinked: Vec<Unlink>,
    /// The content key must change before writing: copies were sealed
    /// with different keys (two unlinks at once), or for a device now
    /// unlinked.
    pub rotate: bool,
}

/// The devices of `space` that `trust` takes, with their keys: those it
/// knew, and those a trusted device (or the recovery phrase) vouched for.
fn vouched(trust: &Trust, space: &Space) -> Trust {
    let mut t = trust.clone();
    let recovery = unhex(&trust.recovery);
    loop {
        let mut grew = false;
        for d in &space.content.devices {
            if t.revoked.contains(&d.id) || d.sign.is_empty() {
                continue;
            }
            let known = t.key(&d.id);
            if known.as_ref().is_some_and(|k| !k.is_empty()) {
                continue;
            }
            let message = space::vouch_message(d);
            let ok = if d.by == RECOVERY {
                !recovery.is_empty() && space::verify(&recovery, &message, &d.vouch)
            } else if d.by == d.id {
                // Listed by the old format with no key: it claims its own.
                known.is_some() && space::verify(&d.sign, &message, &d.vouch)
            } else {
                t.key(&d.by)
                    .filter(|k| !k.is_empty() && !t.revoked.contains(&d.by))
                    .is_some_and(|k| space::verify(&k, &message, &d.vouch))
            };
            if ok {
                t.devices.insert(d.id.clone(), hex(&d.sign));
                grew = true;
            }
        }
        if !grew {
            return t;
        }
    }
}

/// Judges the copies a device opened (`copies`, each sealed and opened)
/// against what it trusts. With nothing trusted yet (a device joining),
/// the newest copy whose signer it lists is the anchor.
pub fn judge(trust: &Trust, copies: &[(&SealedSpace, &Space)]) -> Verdict {
    let mut base = trust.clone();
    if base.devices.is_empty() {
        let anchor = copies
            .iter()
            .filter(|(sealed, space)| {
                space
                    .content
                    .devices
                    .iter()
                    .find(|d| d.id == sealed.signer)
                    .is_some_and(|d| sealed.signed_by(&d.sign))
            })
            .max_by(|a, b| {
                (a.1.content.generation, &a.0.signer).cmp(&(b.1.content.generation, &b.0.signer))
            });
        match anchor {
            Some((_, space)) => {
                base = Trust {
                    generation: 0,
                    ..Trust::from_space(space)
                }
            }
            None => {
                return Verdict {
                    accepted: Vec::new(),
                    refused: copies.len() as u32,
                    trust: trust.clone(),
                    unlinked: Vec::new(),
                    rotate: false,
                }
            }
        }
    }
    // Who signed each copy, as far as this device can tell.
    let judged: Vec<(Trust, bool)> = copies
        .iter()
        .map(|(sealed, space)| {
            let t = vouched(&base, space);
            let ok = t
                .key(&sealed.signer)
                .is_some_and(|k| !k.is_empty() && sealed.signed_by(&k));
            (t, ok)
        })
        .collect();
    // The unlinks signed by a trusted device, oldest first: a device
    // unlinked by an earlier one can't unlink anyone after.
    let mut statements: Vec<Unlink> = Vec::new();
    for ((_, space), (t, ok)) in copies.iter().zip(&judged) {
        if !ok {
            continue;
        }
        for u in &space.content.unlinked {
            let valid = t
                .key(&u.by)
                .is_some_and(|k| !k.is_empty() && u.signed_by(&k));
            if valid && !statements.contains(u) {
                statements.push(u.clone());
            }
        }
    }
    statements
        .sort_by(|a, b| (a.generation, &a.by, &a.device).cmp(&(b.generation, &b.by, &b.device)));
    let mut revoked = base.revoked.clone();
    let mut kept = Vec::new();
    for u in statements {
        if !revoked.contains(&u.by) || u.by == u.device {
            revoked.insert(u.device.clone());
            kept.push(u);
        }
    }
    let excess = kept.len().saturating_sub(KEPT_UNLINKS);
    kept.drain(..excess);
    let floor = trust.generation;
    let mut accepted = Vec::new();
    let mut refused = 0;
    for (i, ((sealed, space), (_, ok))) in copies.iter().zip(&judged).enumerate() {
        let g = space.content.generation;
        let in_range = g >= floor && (floor == 0 || g <= floor.saturating_add(MAX_JUMP));
        if *ok && !revoked.contains(&sealed.signer) && in_range {
            accepted.push(i);
        } else {
            refused += 1;
        }
    }
    let mut next = Trust {
        revoked: revoked.clone(),
        ..trust.clone()
    };
    if next.devices.is_empty() {
        next.devices = base.devices.clone();
        next.recovery = base.recovery.clone();
    }
    for &i in &accepted {
        for (id, key) in &judged[i].0.devices {
            if !key.is_empty() || !next.devices.contains_key(id) {
                next.devices.insert(id.clone(), key.clone());
            }
        }
    }
    next.devices.retain(|id, _| !revoked.contains(id));
    if let Some(&top) = accepted.iter().max_by(|a, b| {
        let (sa, ca) = (copies[**a].0, copies[**a].1);
        let (sb, cb) = (copies[**b].0, copies[**b].1);
        (ca.content.generation, &sa.signer).cmp(&(cb.content.generation, &sb.signer))
    }) {
        next.generation = next.generation.max(copies[top].1.content.generation);
        next.recovery = hex(&copies[top].1.content.recovery_sign());
    }
    let keys: BTreeSet<[u8; 32]> = accepted
        .iter()
        .map(|&i| copies[i].1.content_key().0)
        .collect();
    let rotate = keys.len() > 1
        || accepted.iter().any(|&i| {
            copies[i]
                .1
                .content
                .devices
                .iter()
                .any(|d| revoked.contains(&d.id))
        });
    Verdict {
        accepted,
        refused,
        trust: next,
        unlinked: kept,
        rotate,
    }
}
