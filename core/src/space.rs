//! The sync space: accounts, groups, signatures and settings, encrypted on
//! the device and kept as one message in a hidden folder of one of the
//! person's own mailboxes. No server.
//!
//! The space's content is sealed with a content key (XChaCha20-Poly1305).
//! The content key is wrapped once per linked device, with a key only that
//! device holds, and once for the recovery phrase (24 words). Unlinking a
//! device makes a new content key and a new recovery phrase, so what the
//! device kept no longer opens the space.
//!
//! A new device is linked with a 6-digit code: both sides run SPAKE2 on it
//! through messages in the same folder, so the code itself never goes
//! through the mailbox and someone reading the mailbox gets one guess.

use std::time::{SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use serde::{Deserialize, Serialize};
use spake2::{Ed25519Group, Identity, Password, Spake2};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::space_merge::{self, Stamp, Tables};

/// The hidden folder the space lives in, in the mailbox that holds it.
pub const FOLDER: &str = "Piuma Sync";

/// The header that marks what a message of [FOLDER] is.
pub const HEADER: &str = "X-Piuma-Sync";

/// How long a pairing request waits for an answer, in seconds.
pub const PAIR_TTL: i64 = 5 * 60;

const MAGIC: &[u8; 4] = b"PSP1";
const PAIR_ID: &[u8] = b"piuma-mail pairing v1";

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum SpaceError {
    /// The data was changed, or the key is not the one it was sealed with.
    #[error("can't open: wrong key or damaged data")]
    Sealed,
    #[error("not a recovery phrase")]
    Phrase,
    /// The code typed on one side isn't the one the other side shows.
    #[error("the code didn't match")]
    Code,
    #[error("this device isn't linked to the space")]
    NotLinked,
    #[error("unreadable space: {0}")]
    Format(String),
    /// Written by a newer build in a format this one doesn't know.
    #[error("the space was written by a newer version of Piuma")]
    Newer,
}

pub type Result<T> = std::result::Result<T, SpaceError>;

/// 32 random bytes: a content key, a device's key or the recovery key.
#[derive(Clone, PartialEq, Eq, Zeroize, ZeroizeOnDrop)]
pub struct Key(pub [u8; 32]);

impl std::fmt::Debug for Key {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Key(…)")
    }
}

impl Key {
    pub fn generate() -> Self {
        let mut k = [0u8; 32];
        getrandom::fill(&mut k).expect("the system has randomness");
        Key(k)
    }

    /// The 24 words of a recovery key.
    pub fn phrase(&self) -> String {
        bip39::Mnemonic::from_entropy(&self.0)
            .expect("32 bytes make 24 words")
            .to_string()
    }

    /// The recovery key behind 24 words, as typed: any case, any spaces.
    pub fn from_phrase(words: &str) -> Result<Self> {
        let words = words
            .split_whitespace()
            .map(str::to_lowercase)
            .collect::<Vec<_>>()
            .join(" ");
        let m = bip39::Mnemonic::parse_normalized(&words).map_err(|_| SpaceError::Phrase)?;
        let mut entropy = m.to_entropy();
        let key = <[u8; 32]>::try_from(entropy.as_slice()).map_err(|_| SpaceError::Phrase);
        entropy.zeroize();
        key.map(Key)
    }

    /// For the keychain.
    pub fn to_hex(&self) -> String {
        self.0.iter().map(|b| format!("{b:02x}")).collect()
    }

    pub fn from_hex(hex: &str) -> Option<Self> {
        let hex = hex.trim();
        if hex.len() != 64 {
            return None;
        }
        let mut k = [0u8; 32];
        for (i, b) in k.iter_mut().enumerate() {
            *b = u8::from_str_radix(hex.get(2 * i..2 * i + 2)?, 16).ok()?;
        }
        Some(Key(k))
    }
}

/// Seals `plain` with `key`: a fresh 24-byte nonce, then the ciphertext.
pub fn seal(key: &Key, plain: &[u8]) -> Vec<u8> {
    let mut nonce = [0u8; 24];
    getrandom::fill(&mut nonce).expect("the system has randomness");
    let cipher = XChaCha20Poly1305::new((&key.0).into());
    let sealed = cipher
        .encrypt(&XNonce::from(nonce), plain)
        .expect("in-memory encryption doesn't fail");
    let mut out = Vec::with_capacity(4 + 24 + sealed.len());
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&sealed);
    out
}

pub fn open(key: &Key, sealed: &[u8]) -> Result<Vec<u8>> {
    if sealed.len() < 4 + 24 || &sealed[..4] != MAGIC {
        return Err(SpaceError::Sealed);
    }
    let nonce = XNonce::try_from(&sealed[4..28]).map_err(|_| SpaceError::Sealed)?;
    let cipher = XChaCha20Poly1305::new((&key.0).into());
    cipher
        .decrypt(&nonce, &sealed[28..])
        .map_err(|_| SpaceError::Sealed)
}

/// A device linked to the space, as Devices & sync lists it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Device {
    /// Random, made once by the device.
    pub id: String,
    /// "Matteo's MacBook", "Pixel 8".
    pub name: String,
    /// "laptop", "phone" or "tablet".
    pub kind: String,
    /// When it last wrote to or read the space, in seconds.
    pub last_seen: i64,
    /// Its public key: any linked device can seal the content key for it.
    #[serde(with = "b64")]
    pub public: Vec<u8>,
    /// The public half of its signing key (Ed25519): every copy of the
    /// space it writes, and every unlink it makes, is signed with it.
    #[serde(default, with = "b64")]
    pub sign: Vec<u8>,
    /// Who vouched for it: the linked device that approved it, [RECOVERY]
    /// when it came in with the recovery phrase, or itself for the device
    /// that made the space.
    #[serde(default)]
    pub by: String,
    /// `by`'s signature over its id and keys ([vouch_message]).
    #[serde(default, with = "b64")]
    pub vouch: Vec<u8>,
}

/// A device's signing key, made from its secret: nothing more to keep.
fn signing_key(secret: &Key) -> ed25519_dalek::SigningKey {
    ed25519_dalek::SigningKey::from_bytes(&derive(&secret.0, b"piuma-mail signing").0)
}

/// The public half of the signing key made from `secret`, for [Device::sign].
pub fn sign_public(secret: &Key) -> Vec<u8> {
    signing_key(secret).verifying_key().to_bytes().to_vec()
}

/// Signs `message` with the key made from `secret`.
pub fn sign(secret: &Key, message: &[u8]) -> Vec<u8> {
    use ed25519_dalek::Signer as _;
    signing_key(secret).sign(message).to_bytes().to_vec()
}

/// Whether `signature` is `public`'s over `message` (strict: no
/// malleable or weak-key signatures).
pub fn verify(public: &[u8], message: &[u8], signature: &[u8]) -> bool {
    let (Ok(public), Ok(signature)) = (
        <[u8; 32]>::try_from(public),
        <[u8; 64]>::try_from(signature),
    ) else {
        return false;
    };
    let Ok(public) = ed25519_dalek::VerifyingKey::from_bytes(&public) else {
        return false;
    };
    public
        .verify_strict(message, &ed25519_dalek::Signature::from_bytes(&signature))
        .is_ok()
}

/// What a voucher signs for a device: its id and its keys (its name and
/// kind can change).
pub fn vouch_message(d: &Device) -> Vec<u8> {
    let mut m = b"piuma-mail device\0".to_vec();
    for part in [d.id.as_bytes(), &d.public, &d.sign] {
        m.extend((part.len() as u32).to_le_bytes());
        m.extend(part);
    }
    m
}

/// `by` (holding `secret`) vouches for `device`.
pub fn vouch(device: &mut Device, by: &str, secret: &Key) {
    device.by = by.to_owned();
    device.vouch = sign(secret, &vouch_message(device));
}

/// The signing secret the recovery phrase stands for: a device that comes
/// in with the phrase vouches for itself with it.
pub fn recovery_signer(recovery: &Key) -> Key {
    derive(&recovery.0, b"piuma-mail recovery signing")
}

/// A signed statement that `device` is unlinked: copies it signs are
/// refused from then on, whatever their key or generation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Unlink {
    pub device: String,
    pub by: String,
    /// The generation of the copy it was first made in.
    pub generation: u64,
    #[serde(with = "b64")]
    pub sig: Vec<u8>,
}

impl Unlink {
    pub fn message(device: &str, by: &str, generation: u64) -> Vec<u8> {
        let mut m = b"piuma-mail unlink\0".to_vec();
        for part in [device.as_bytes(), by.as_bytes()] {
            m.extend((part.len() as u32).to_le_bytes());
            m.extend(part);
        }
        m.extend(generation.to_le_bytes());
        m
    }

    /// `by` (holding `secret`) unlinks `device`.
    pub fn new(device: &str, by: &str, generation: u64, secret: &Key) -> Unlink {
        Unlink {
            device: device.to_owned(),
            by: by.to_owned(),
            generation,
            sig: sign(secret, &Unlink::message(device, by, generation)),
        }
    }

    pub fn signed_by(&self, public: &[u8]) -> bool {
        verify(
            public,
            &Unlink::message(&self.device, &self.by, self.generation),
            &self.sig,
        )
    }
}

/// A device's own secret, kept in its keychain, and the public half the
/// space lists.
pub fn public_key(secret: &Key) -> Vec<u8> {
    x25519_dalek::PublicKey::from(&x25519_dalek::StaticSecret::from(secret.0))
        .as_bytes()
        .to_vec()
}

/// Seals `key` for the holder of `public`'s secret: a fresh key pair, its
/// public half first, then the key sealed with what the two make.
fn seal_for(public: &[u8], key: &Key) -> Vec<u8> {
    let Ok(public) = <[u8; 32]>::try_from(public) else {
        return Vec::new();
    };
    let mine = Key::generate();
    let ours = x25519_dalek::StaticSecret::from(mine.0)
        .diffie_hellman(&x25519_dalek::PublicKey::from(public));
    let mut out = public_key(&mine);
    out.extend(seal(&derive(ours.as_bytes(), b"piuma-mail wrap"), &key.0));
    out
}

fn open_for(secret: &Key, sealed: &[u8]) -> Result<Key> {
    let theirs = <[u8; 32]>::try_from(sealed.get(..32).ok_or(SpaceError::Sealed)?)
        .map_err(|_| SpaceError::Sealed)?;
    let ours = x25519_dalek::StaticSecret::from(secret.0)
        .diffie_hellman(&x25519_dalek::PublicKey::from(theirs));
    unwrap(&derive(ours.as_bytes(), b"piuma-mail wrap"), &sealed[32..])
}

fn derive(secret: &[u8], info: &[u8]) -> Key {
    let hk = hkdf::Hkdf::<sha2::Sha256>::new(None, secret);
    let mut k = [0u8; 32];
    hk.expand(info, &mut k).expect("32 bytes is a valid length");
    Key(k)
}

/// What the space holds: synced rows ([crate::space_merge]), passwords
/// among them, the linked devices and the recovery key. Sealed whole, so
/// the generation and schema are authenticated with the rest.
#[derive(Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Content {
    /// [space_merge::FORMAT] of the writer.
    pub format: u32,
    /// [space_merge::SCHEMA] of the writer.
    pub schema: u32,
    /// Counted up on every write: a device refuses one older than what it
    /// accepted.
    pub generation: u64,
    pub updated_at: i64,
    /// The device that wrote it last.
    pub updated_by: String,
    pub tables: Tables,
    pub devices: Vec<Device>,
    /// The recovery key, so a linked device can show the phrase again.
    #[serde(default)]
    pub recovery: String,
    /// Signed unlinks: copies by these devices are refused.
    #[serde(default)]
    pub unlinked: Vec<Unlink>,
    /// Tombstones stamped before this (milliseconds) were dropped: a device
    /// last merged before it takes the space's word for older rows.
    #[serde(default)]
    pub horizon: i64,
    /// What a newer build wrote that this one doesn't know: kept as it is.
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

impl std::fmt::Debug for Content {
    // Rows carry passwords: only counts.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Content")
            .field("format", &self.format)
            .field("schema", &self.schema)
            .field("generation", &self.generation)
            .field(
                "rows",
                &self.tables.values().map(|t| t.len()).sum::<usize>(),
            )
            .field("devices", &self.devices.len())
            .finish_non_exhaustive()
    }
}

impl Content {
    /// Marks this device as seen, adding it when new.
    pub fn touch(&mut self, device: &Device, now: i64) {
        match self.devices.iter_mut().find(|d| d.id == device.id) {
            Some(d) => {
                d.name.clone_from(&device.name);
                d.kind.clone_from(&device.kind);
                d.public.clone_from(&device.public);
                d.last_seen = now;
            }
            None => self.devices.push(Device {
                last_seen: now,
                ..device.clone()
            }),
        }
        // Its signing key and who vouched for it, once it has them.
        if let Some(d) = self.devices.iter_mut().find(|d| d.id == device.id) {
            if !device.sign.is_empty() {
                d.sign.clone_from(&device.sign);
            }
            if !device.vouch.is_empty() {
                d.by.clone_from(&device.by);
                d.vouch.clone_from(&device.vouch);
            }
        }
    }

    /// The public half of the recovery phrase's signing key, for devices
    /// that come in with the phrase.
    pub fn recovery_sign(&self) -> Vec<u8> {
        Key::from_hex(&self.recovery)
            .map(|k| sign_public(&recovery_signer(&k)))
            .unwrap_or_default()
    }

    /// Live rows of a table.
    pub fn count(&self, table: &str) -> usize {
        self.tables
            .get(table)
            .map_or(0, |t| t.values().filter(|r| !r.del).count())
    }
}

/// What the old format (version 1) held: whole tables with the writer's
/// local ids, passwords by address. Read once, to convert it.
#[derive(Deserialize)]
struct ContentV1 {
    #[serde(default)]
    updated_at: i64,
    #[serde(default)]
    updated_by: String,
    #[serde(default)]
    tables: serde_json::Map<String, serde_json::Value>,
    #[serde(default)]
    passwords: Vec<(String, String)>,
    #[serde(default)]
    devices: Vec<Device>,
    #[serde(default)]
    recovery: String,
}

/// The content key, sealed for one reader: a device by its id, or the
/// recovery phrase (`"recovery"`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct Wrap {
    #[serde(rename = "for")]
    for_: String,
    #[serde(with = "b64")]
    key: Vec<u8>,
}

/// The recovery phrase, as a reader of the content key and as a voucher.
pub const RECOVERY: &str = "recovery";

/// The space as stored: the content key wrapped for each reader, and the
/// sealed content.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SealedSpace {
    /// 1: the old format, read only to convert it; 2: [space_merge::FORMAT].
    version: u32,
    wraps: Vec<Wrap>,
    #[serde(with = "b64")]
    content: Vec<u8>,
    /// The device that wrote it, and its signature over the sealed content
    /// and the wraps ([SealedSpace::signed_message]). The old format has
    /// none.
    #[serde(default)]
    pub signer: String,
    #[serde(default, with = "b64")]
    sig: Vec<u8>,
    /// What a new device shows before it can open the space ("We found
    /// your space"). In the clear, so only counts and kinds of device: no
    /// names, which the mail provider could read.
    #[serde(default)]
    pub about: About,
}

impl SealedSpace {
    /// Written by a build before per-row sync.
    pub fn is_v1(&self) -> bool {
        self.version < 2
    }

    /// What the writer signs: the format, who it is, the sealed content
    /// (which holds the generation) and who can open it.
    fn signed_message(&self) -> Vec<u8> {
        use sha2::Digest as _;
        let mut m = b"piuma-mail space\0".to_vec();
        m.extend(self.version.to_le_bytes());
        m.extend((self.signer.len() as u32).to_le_bytes());
        m.extend(self.signer.as_bytes());
        m.extend(sha2::Sha256::digest(&self.content));
        m.extend(sha2::Sha256::digest(
            serde_json::to_vec(&self.wraps).expect("serializes"),
        ));
        m
    }

    /// Whether the writer's signature checks out with `public`.
    pub fn signed_by(&self, public: &[u8]) -> bool {
        verify(public, &self.signed_message(), &self.sig)
    }
}

/// The few things readable without the key: how much the space holds,
/// when it last changed, and the kinds of device that can approve a new
/// one.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct About {
    pub accounts: usize,
    pub groups: usize,
    pub signatures: usize,
    pub updated_at: i64,
    pub devices: Vec<AboutDevice>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AboutDevice {
    /// Empty from this format on: names stay sealed. Old spaces had them.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    pub kind: String,
    pub last_seen: i64,
}

/// An open space: its content and the content key, kept to write it again.
#[derive(Clone)]
pub struct Space {
    pub content: Content,
    key: Key,
    recovery: Vec<u8>,
    /// Opened from the old format: written back in this one.
    converted: bool,
}

impl std::fmt::Debug for Space {
    // The key and the passwords stay out.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Space")
            .field("content", &self.content)
            .field("converted", &self.converted)
            .finish_non_exhaustive()
    }
}

impl Space {
    /// A new space, readable by this device and by the recovery phrase.
    /// Returns it with the recovery key, to be shown once.
    pub fn create(device: &Device, content: Content) -> (Space, Key) {
        let key = Key::generate();
        let recovery = Key::generate();
        let mut space = Space {
            content: Content {
                format: space_merge::FORMAT,
                schema: space_merge::SCHEMA,
                recovery: recovery.to_hex(),
                ..content
            },
            recovery: seal(&recovery, &key.0),
            key,
            converted: false,
        };
        space.content.touch(device, now());
        (space, recovery)
    }

    /// Opens a stored space with this device's secret.
    pub fn open_as(sealed: &SealedSpace, device_id: &str, secret: &Key) -> Result<Space> {
        let wrap = sealed
            .wraps
            .iter()
            .find(|w| w.for_ == device_id)
            .ok_or(SpaceError::NotLinked)?;
        Self::open_with(sealed, &open_for(secret, &wrap.key)?)
    }

    /// Opens a stored space with the recovery phrase.
    pub fn open_recovery(sealed: &SealedSpace, recovery: &Key) -> Result<Space> {
        let wrap = sealed
            .wraps
            .iter()
            .find(|w| w.for_ == RECOVERY)
            .ok_or(SpaceError::Sealed)?;
        Self::open_with(sealed, &unwrap(recovery, &wrap.key)?)
    }

    /// Opens a stored space with its content key, as pairing hands it over.
    /// The old format comes out converted, at generation 0.
    pub fn open_with(sealed: &SealedSpace, key: &Key) -> Result<Space> {
        let plain = open(key, &sealed.content)?;
        let content = if sealed.is_v1() {
            let old: ContentV1 =
                serde_json::from_slice(&plain).map_err(|e| SpaceError::Format(e.to_string()))?;
            let stamp = Stamp {
                t: old.updated_at.saturating_mul(1000),
                c: 0,
                d: old.updated_by.clone(),
            };
            Content {
                format: space_merge::FORMAT,
                schema: space_merge::SCHEMA,
                generation: 0,
                updated_at: old.updated_at,
                updated_by: old.updated_by,
                tables: space_merge::from_v1(&old.tables, &old.passwords, &stamp),
                devices: old.devices,
                recovery: old.recovery,
                unlinked: Vec::new(),
                horizon: 0,
                extra: serde_json::Map::new(),
            }
        } else {
            let content: Content =
                serde_json::from_slice(&plain).map_err(|e| SpaceError::Format(e.to_string()))?;
            if content.format > space_merge::FORMAT {
                return Err(SpaceError::Newer);
            }
            content
        };
        let recovery = sealed
            .wraps
            .iter()
            .find(|w| w.for_ == RECOVERY)
            .map(|w| w.key.clone())
            .unwrap_or_default();
        Ok(Space {
            content,
            key: key.clone(),
            recovery,
            converted: sealed.is_v1(),
        })
    }

    /// The content key, to hand to a new device while pairing.
    pub fn content_key(&self) -> &Key {
        &self.key
    }

    /// Opened from the old format.
    pub fn converted(&self) -> bool {
        self.converted
    }

    /// Lets one more device open the space, or marks this one as seen.
    pub fn link(&mut self, device: &Device) {
        self.content.touch(device, now());
    }

    /// Whether a device is linked.
    pub fn is_linked(&self, device_id: &str) -> bool {
        self.content.devices.iter().any(|d| d.id == device_id)
    }

    /// Unlinks a device: it leaves the list, and the space gets a new
    /// content key and recovery phrase ([Space::rotate]), returned to be
    /// shown. The signed statement that keeps its copies out is the
    /// caller's ([Unlink]).
    pub fn unlink(&mut self, device_id: &str) -> Key {
        self.content.devices.retain(|d| d.id != device_id);
        self.rotate()
    }

    /// A new content key and recovery phrase: what a device that left
    /// kept no longer opens the space.
    pub fn rotate(&mut self) -> Key {
        self.key = Key::generate();
        let recovery = Key::generate();
        self.recovery = seal(&recovery, &self.key.0);
        self.content.recovery = recovery.to_hex();
        recovery
    }

    /// The recovery key, to show its phrase again.
    pub fn recovery(&self) -> Option<Key> {
        Key::from_hex(&self.content.recovery)
    }

    /// Seals the content for storing, its key for each linked device,
    /// signed by the writing device `by` (holding `secret`).
    pub fn seal(&self, by: &str, secret: &Key) -> SealedSpace {
        let mut sealed = self.seal_unsigned();
        sealed.signer = by.to_owned();
        sealed.sig = sign(secret, &sealed.signed_message());
        sealed
    }

    fn seal_unsigned(&self) -> SealedSpace {
        let plain = serde_json::to_vec(&self.content).expect("content serializes");
        let mut wraps: Vec<Wrap> = self
            .content
            .devices
            .iter()
            .map(|d| Wrap {
                for_: d.id.clone(),
                key: seal_for(&d.public, &self.key),
            })
            .collect();
        wraps.push(Wrap {
            for_: RECOVERY.into(),
            key: self.recovery.clone(),
        });
        SealedSpace {
            version: space_merge::FORMAT,
            wraps,
            content: seal(&self.key, &plain),
            signer: String::new(),
            sig: Vec::new(),
            about: About {
                accounts: self.content.count("account"),
                groups: self.content.count("address_group"),
                signatures: self.content.count("signature"),
                updated_at: self.content.updated_at,
                devices: self
                    .content
                    .devices
                    .iter()
                    .map(|d| AboutDevice {
                        name: String::new(),
                        kind: d.kind.clone(),
                        last_seen: d.last_seen,
                    })
                    .collect(),
            },
        }
    }
}

/// A space as builds before per-row sync stored it, for tests.
#[cfg(test)]
pub(crate) fn sealed_v1(devices: &[Device], key: &Key, content: &serde_json::Value) -> SealedSpace {
    SealedSpace {
        version: 1,
        wraps: devices
            .iter()
            .map(|d| Wrap {
                for_: d.id.clone(),
                key: seal_for(&d.public, key),
            })
            .collect(),
        content: seal(key, &serde_json::to_vec(content).expect("serializes")),
        about: About::default(),
        signer: String::new(),
        sig: Vec::new(),
    }
}

/// A key only this device can make from its secret, to keep things in its
/// own database: the content key it accepted last, digests of passwords.
pub fn local_key(secret: &Key, purpose: &str) -> Key {
    derive(&secret.0, format!("piuma-mail local {purpose}").as_bytes())
}

/// A keyed digest of a password, to tell whether it changed without
/// keeping it.
pub fn digest(key: &Key, name: &str, value: &str) -> String {
    let hk = hkdf::Hkdf::<sha2::Sha256>::new(Some(&key.0), value.as_bytes());
    let mut out = [0u8; 16];
    hk.expand(name.as_bytes(), &mut out)
        .expect("16 bytes is a valid length");
    out.iter().map(|b| format!("{b:02x}")).collect()
}

fn unwrap(key: &Key, wrapped: &[u8]) -> Result<Key> {
    let mut plain = open(key, wrapped)?;
    let k = <[u8; 32]>::try_from(plain.as_slice()).map_err(|_| SpaceError::Sealed);
    plain.zeroize();
    k.map(Key)
}

impl SealedSpace {
    pub fn to_bytes(&self) -> Vec<u8> {
        serde_json::to_vec(self).expect("serializes")
    }

    pub fn from_bytes(data: &[u8]) -> Result<Self> {
        serde_json::from_slice(data).map_err(|e| SpaceError::Format(e.to_string()))
    }
}

/// A new device asks to be linked: it shows [code] and posts this.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairRequest {
    pub id: String,
    pub device: Device,
    pub at: i64,
    #[serde(with = "b64")]
    spake: Vec<u8>,
    /// Made with a QR invite's code: which invite, by [invite_tag]. The
    /// device that showed it answers on its own, with that invite's code,
    /// and nobody is asked for digits.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub invite: Option<String>,
}

impl PairRequest {
    pub fn expired(&self, now: i64) -> bool {
        now - self.at > PAIR_TTL
    }

    /// Made with a QR invite's code.
    pub fn qr(&self) -> bool {
        self.invite.is_some()
    }
}

/// Names an invite's code without telling it: the device that showed
/// several (one every five minutes, or again after the panel opened
/// anew) finds which one a request was made with.
pub fn invite_tag(code: &str) -> String {
    let mut h = <sha2::Sha256 as sha2::Digest>::new();
    sha2::Digest::update(&mut h, b"piuma-mail invite tag");
    sha2::Digest::update(&mut h, normalize_code(code).as_bytes());
    sha2::Digest::finalize(h)[..8]
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// A linked device's answer: its half of SPAKE2 and the content key,
/// sealed with what the code made.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairAnswer {
    pub request: String,
    #[serde(with = "b64")]
    spake: Vec<u8>,
    /// [Answered], sealed with what the code made: the folder shows no
    /// name.
    #[serde(with = "b64")]
    key: Vec<u8>,
}

/// What an answer hands the new device: the content key, the approving
/// device (by name, to show, and id) and its signature vouching for the
/// new device.
#[derive(Serialize, Deserialize)]
pub struct Answered {
    #[serde(with = "b64")]
    key: Vec<u8>,
    pub name: String,
    pub by: String,
    #[serde(with = "b64")]
    pub vouch: Vec<u8>,
}

impl Answered {
    pub fn key(&self) -> Result<Key> {
        <[u8; 32]>::try_from(self.key.as_slice())
            .map(Key)
            .map_err(|_| SpaceError::Code)
    }
}

impl Drop for Answered {
    fn drop(&mut self) {
        self.key.zeroize();
    }
}

/// The new device's side, kept in memory while it waits for an answer.
pub struct Pairing {
    state: Spake2<Ed25519Group>,
    pub request: PairRequest,
}

/// Six random digits, as "482615".
pub fn pair_code() -> String {
    let mut b = [0u8; 4];
    getrandom::fill(&mut b).expect("the system has randomness");
    format!("{:06}", u32::from_le_bytes(b) % 1_000_000)
}

/// Starts pairing on the new device with the code it shows (or the one
/// typed from a linked device's screen).
pub fn pair_start(code: &str, device: &Device) -> Pairing {
    let (state, msg) = Spake2::<Ed25519Group>::start_symmetric(
        &Password::new(normalize_code(code).as_bytes()),
        &Identity::new(PAIR_ID),
    );
    let mut id = [0u8; 12];
    getrandom::fill(&mut id).expect("the system has randomness");
    Pairing {
        state,
        request: PairRequest {
            id: id.iter().map(|b| format!("{b:02x}")).collect(),
            device: device.clone(),
            at: now(),
            spake: msg,
            invite: None,
        },
    }
}

/// [pair_start] with a scanned invite's code.
pub fn pair_start_qr(code: &str, device: &Device) -> Pairing {
    let mut pairing = pair_start(code, device);
    pairing.request.invite = Some(invite_tag(code));
    pairing
}

/// On a linked device: answers a request with the code the person typed
/// (or the one this device showed), handing over the content key.
/// `by` is the approving device (holding `secret`); it vouches for the
/// device that asked.
pub fn pair_answer(
    code: &str,
    request: &PairRequest,
    by: &Device,
    secret: &Key,
    key: &Key,
) -> PairAnswer {
    let (state, msg) = Spake2::<Ed25519Group>::start_symmetric(
        &Password::new(normalize_code(code).as_bytes()),
        &Identity::new(PAIR_ID),
    );
    // A malformed request makes a key nobody else has: the answer opens
    // for no one.
    let shared = state
        .finish(&request.spake)
        .unwrap_or_else(|_| Key::generate().0.to_vec());
    let channel = channel_key(&shared, &request.id);
    let mut asking = request.device.clone();
    vouch(&mut asking, &by.id, secret);
    let mut payload = serde_json::to_vec(&Answered {
        key: key.0.to_vec(),
        name: by.name.clone(),
        by: by.id.clone(),
        vouch: asking.vouch,
    })
    .expect("serializes");
    let sealed = seal(&channel, &payload);
    payload.zeroize();
    PairAnswer {
        request: request.id.clone(),
        spake: msg,
        key: sealed,
    }
}

impl Pairing {
    /// The content key from the answer; [SpaceError::Code] when the codes
    /// on the two sides differ.
    pub fn finish(self, answer: &PairAnswer) -> Result<Answered> {
        if answer.request != self.request.id {
            return Err(SpaceError::Code);
        }
        let shared = self
            .state
            .finish(&answer.spake)
            .map_err(|_| SpaceError::Code)?;
        let channel = channel_key(&shared, &self.request.id);
        let mut plain = open(&channel, &answer.key).map_err(|_| SpaceError::Code)?;
        let answered = serde_json::from_slice(&plain).map_err(|_| SpaceError::Code);
        plain.zeroize();
        answered
    }
}

fn normalize_code(code: &str) -> String {
    code.chars().filter(char::is_ascii_digit).collect()
}

fn channel_key(shared: &[u8], request: &str) -> Key {
    let hk = hkdf::Hkdf::<sha2::Sha256>::new(Some(request.as_bytes()), shared);
    let mut k = [0u8; 32];
    hk.expand(b"piuma-mail pairing key", &mut k)
        .expect("32 bytes is a valid length");
    Key(k)
}

/// What a message of [FOLDER] carries.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Note {
    Space(SealedSpace),
    Request(PairRequest),
    Answer(PairAnswer),
    /// A request the person refused on a linked device ("Not me").
    Refused(String),
    /// Left behind when the space moved to another mailbox: its address,
    /// for the other devices to follow.
    Moved(String),
}

impl Note {
    fn tag(&self) -> &'static str {
        match self {
            // Old builds read "space" only: they leave this format alone.
            Note::Space(s) if s.is_v1() => "space",
            Note::Space(_) => "space2",
            Note::Request(_) => "request",
            Note::Answer(_) => "answer",
            Note::Refused(_) => "refused",
            Note::Moved(_) => "moved",
        }
    }

    fn payload(&self) -> Vec<u8> {
        match self {
            Note::Space(s) => s.to_bytes(),
            Note::Request(r) => serde_json::to_vec(r).expect("serializes"),
            Note::Answer(a) => serde_json::to_vec(a).expect("serializes"),
            Note::Refused(id) | Note::Moved(id) => id.as_bytes().to_vec(),
        }
    }

    /// The message to append to [FOLDER], from and to `mailbox`.
    pub fn to_message(&self, mailbox: &str, at: i64) -> Vec<u8> {
        let body = base64::engine::general_purpose::STANDARD.encode(self.payload());
        let mut lines = String::new();
        for chunk in body.as_bytes().chunks(76) {
            lines.push_str(std::str::from_utf8(chunk).expect("base64 is ascii"));
            lines.push_str("\r\n");
        }
        let date = rfc2822(at);
        format!(
            "From: Piuma Mail <{mailbox}>\r\nTo: <{mailbox}>\r\nDate: {date}\r\n\
             Subject: Piuma sync ({tag})\r\n{HEADER}: {tag}\r\nMIME-Version: 1.0\r\n\
             Content-Type: application/octet-stream\r\nContent-Transfer-Encoding: base64\r\n\r\n\
             {lines}",
            tag = self.tag(),
        )
        .into_bytes()
    }

    /// Reads a message of [FOLDER]; None for anything else.
    pub fn from_message(raw: &[u8]) -> Option<Note> {
        let m = mail_parser::MessageParser::default().parse(raw)?;
        let tag = m.headers().value(HEADER)?.as_text()?.trim().to_owned();
        let data = m
            .body_bytes()
            .or_else(|| m.attachments().next().map(|a| a.decoded()))?;
        Some(match tag.as_str() {
            "space" => Note::Space(SealedSpace::from_bytes(&data).ok().filter(|s| s.is_v1())?),
            "space2" => Note::Space(SealedSpace::from_bytes(&data).ok().filter(|s| !s.is_v1())?),
            "request" => Note::Request(serde_json::from_slice(&data).ok()?),
            "answer" => Note::Answer(serde_json::from_slice(&data).ok()?),
            "refused" => Note::Refused(String::from_utf8(data.to_vec()).ok()?),
            "moved" => Note::Moved(String::from_utf8(data.to_vec()).ok()?),
            _ => return None,
        })
    }
}

trait BodyBytes {
    fn body_bytes(&self) -> Option<std::borrow::Cow<'_, [u8]>>;
}

impl BodyBytes for mail_parser::Message<'_> {
    fn body_bytes(&self) -> Option<std::borrow::Cow<'_, [u8]>> {
        self.part(0).map(|p| p.decoded())
    }
}

/// A Date header for `at` seconds, in UTC.
fn rfc2822(at: i64) -> String {
    let days = at.div_euclid(86_400);
    let secs = at.rem_euclid(86_400);
    // Howard Hinnant's civil-from-days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    const DAYS: [&str; 7] = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"];
    format!(
        "{}, {day} {} {year} {:02}:{:02}:{:02} +0000",
        DAYS[days.rem_euclid(7) as usize],
        MONTHS[(month - 1) as usize],
        secs / 3600,
        secs / 60 % 60,
        secs % 60
    )
}

/// Seconds since 1970.
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// A random id for this device, made once.
pub fn new_device_id() -> String {
    let mut b = [0u8; 9];
    getrandom::fill(&mut b).expect("the system has randomness");
    b.iter().map(|b| format!("{b:02x}")).collect()
}

mod b64 {
    use base64::Engine as _;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(v: &[u8], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&base64::engine::general_purpose::STANDARD.encode(v))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = String::deserialize(d)?;
        base64::engine::general_purpose::STANDARD
            .decode(s)
            .map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(id: &str, name: &str) -> (Device, Key) {
        let secret = Key::generate();
        (
            Device {
                id: id.into(),
                name: name.into(),
                kind: "laptop".into(),
                last_seen: 0,
                public: public_key(&secret),
                sign: sign_public(&secret),
                by: String::new(),
                vouch: Vec::new(),
            },
            secret,
        )
    }

    fn from_hex(parts: &[&str]) -> Vec<u8> {
        let hex = parts.concat();
        (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect()
    }

    /// What devices already keep must still open after a library update:
    /// a space sealed and a key wrapped for a device by an earlier build
    /// (chacha20poly1305 0.10, x25519-dalek 2), X25519 and HKDF as RFC 7748
    /// and RFC 5869 define them, and recovery phrases as BIP-39 defines them.
    #[test]
    fn what_earlier_builds_sealed_still_opens() {
        let key = Key([7u8; 32]);
        let sealed = from_hex(&[
            "50535031090909090909090909090909090909090909090909090909ce1b97e7",
            "1d8a0a1b9a71284f1812648e9d08f9df5b11324ff6b2ba0ae6bcf118",
        ]);
        assert_eq!(open(&key, &sealed).unwrap(), b"piuma sync space");
        let wrapped = from_hex(&[
            "50a61409b1ddd0325e9b16b700e719e9772c07000b1bd7786e907c653d20495d",
            "505350310909090909090909090909090909090909090909090909092b67b7c2",
            "9d22840028f4948491b987126591a9efd54a0c3c274254d3ba2c92f53304ac1f",
            "d29f2075095f63c9fda855c9",
        ]);
        assert_eq!(open_for(&Key([3u8; 32]), &wrapped).unwrap(), key);
        // RFC 7748, section 6.1: both public keys and the shared secret.
        let alice = <[u8; 32]>::try_from(from_hex(&[
            "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a",
        ]))
        .unwrap();
        let bob = <[u8; 32]>::try_from(from_hex(&[
            "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb",
        ]))
        .unwrap();
        let bob_public =
            from_hex(&["de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"]);
        assert_eq!(
            public_key(&Key(alice)),
            from_hex(&["8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"])
        );
        assert_eq!(public_key(&Key(bob)), bob_public);
        let shared = x25519_dalek::StaticSecret::from(alice).diffie_hellman(
            &x25519_dalek::PublicKey::from(<[u8; 32]>::try_from(bob_public).unwrap()),
        );
        assert_eq!(
            shared.as_bytes().to_vec(),
            from_hex(&["4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"])
        );
        // RFC 5869, test case 3 (no salt, no info).
        assert_eq!(
            derive(&[0x0b; 22], b"").to_hex(),
            "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d"
        );
        // BIP-39 test vectors.
        assert_eq!(
            Key([0; 32]).phrase(),
            format!("{}art", "abandon ".repeat(23))
        );
        assert_eq!(
            Key([0x7f; 32]).phrase(),
            "legal winner thank year wave sausage worth useful \
             legal winner thank year wave sausage worth useful \
             legal winner thank year wave sausage worth title"
        );
        assert_eq!(
            Key::from_phrase(&Key([0x7f; 32]).phrase()).unwrap(),
            Key([0x7f; 32])
        );
    }

    #[test]
    fn sealed_data_opens_only_with_its_key() {
        let k = Key::generate();
        let sealed = seal(&k, b"accounts");
        assert_eq!(open(&k, &sealed).unwrap(), b"accounts");
        assert_eq!(open(&Key::generate(), &sealed), Err(SpaceError::Sealed));
        let mut changed = sealed.clone();
        *changed.last_mut().unwrap() ^= 1;
        assert_eq!(open(&k, &changed), Err(SpaceError::Sealed));
    }

    #[test]
    fn a_recovery_phrase_is_24_words_and_back() {
        let k = Key::generate();
        let phrase = k.phrase();
        assert_eq!(phrase.split(' ').count(), 24);
        let typed = format!("  {}\n", phrase.to_uppercase().replace(' ', "   "));
        assert_eq!(Key::from_phrase(&typed).unwrap(), k);
        assert_eq!(
            Key::from_phrase("orbit lemon cradle"),
            Err(SpaceError::Phrase)
        );
        assert_eq!(Key::from_hex(&k.to_hex()).unwrap(), k);
    }

    fn with_password(email: &str, password: &str) -> Content {
        let mut tables = Tables::new();
        let mut v = serde_json::Map::new();
        v.insert("for".into(), "account".into());
        v.insert("value".into(), password.into());
        tables
            .entry(space_merge::SECRETS.into())
            .or_default()
            .insert(
                space_merge::account_id(email),
                space_merge::Row {
                    s: Stamp::default(),
                    del: false,
                    v,
                },
            );
        Content {
            tables,
            ..Default::default()
        }
    }

    #[test]
    fn a_space_opens_for_its_devices_and_the_phrase() {
        let (mac, mac_key) = device("mac", "MacBook");
        let (space, recovery) = Space::create(&mac, with_password("matteo@posta.it", "secret"));
        let stored = SealedSpace::from_bytes(&space.seal("mac", &Key([9; 32])).to_bytes()).unwrap();
        let opened = Space::open_as(&stored, "mac", &mac_key).unwrap();
        let gid = space_merge::account_id("Matteo@Posta.it");
        assert_eq!(
            opened.content.tables[space_merge::SECRETS][&gid].v["value"],
            "secret"
        );
        assert_eq!(opened.content.devices[0].name, "MacBook");
        assert!(Space::open_recovery(&stored, &recovery).is_ok());
        assert_eq!(
            Space::open_as(&stored, "pixel", &mac_key).unwrap_err(),
            SpaceError::NotLinked
        );
        assert_eq!(
            Space::open_as(&stored, "mac", &Key::generate()).unwrap_err(),
            SpaceError::Sealed
        );
    }

    #[test]
    fn nothing_secret_is_printed_or_left_in_the_clear() {
        let (mac, _) = device("mac", "Matteo's MacBook");
        let (space, _) = Space::create(&mac, with_password("matteo@posta.it", "hunter2-secret"));
        let printed = format!("{space:?} {:?} {:?}", space.content, space.content.tables);
        assert!(!printed.contains("hunter2-secret"), "{printed}");
        // The provider reads the stored message: no device names in it.
        let stored = String::from_utf8(space.seal("mac", &Key([9; 32])).to_bytes()).unwrap();
        assert!(!stored.contains("MacBook"));
        assert!(!stored.contains("hunter2"));
        assert_eq!(
            space.seal("mac", &Key([9; 32])).about.devices[0].kind,
            "laptop"
        );
    }

    #[test]
    fn an_old_format_space_opens_converted() {
        let (mac, mac_key) = device("mac", "MacBook");
        let key = Key::generate();
        let old = serde_json::json!({
            "schema": 60, "updated_at": 1_760_000_000, "updated_by": "mac",
            "tables": {
                "account": [{"id": 4, "name": "P", "email": "Matteo@posta.it", "color": "#000",
                              "kind": "imap"}],
                "signature": [{"id": 9, "account": 4, "label": "Work", "template": "plain"}],
                "setting": [{"key": "notify.loud.4", "value": "off"},
                            {"key": "appearance.theme", "value": "dark"}]
            },
            "passwords": [["matteo@posta.it", "pw"]],
            "devices": [mac], "recovery": ""
        });
        let wrapped = seal_for(&mac.public, &key);
        let sealed = SealedSpace {
            version: 1,
            wraps: vec![Wrap {
                for_: "mac".into(),
                key: wrapped,
            }],
            content: seal(&key, &serde_json::to_vec(&old).unwrap()),
            about: About::default(),
            signer: String::new(),
            sig: Vec::new(),
        };
        let note = Note::Space(sealed.clone());
        let raw = note.to_message("matteo@posta.it", 0);
        assert!(String::from_utf8_lossy(&raw).contains("X-Piuma-Sync: space\r\n"));
        let space = Space::open_as(&sealed, "mac", &mac_key).unwrap();
        assert!(space.converted());
        let account = space_merge::account_id("matteo@posta.it");
        let t = &space.content.tables;
        let sig = &t["signature"][&space_merge::v1_id("signature", 9)];
        assert_eq!(sig.v["account"], account.as_str());
        assert_eq!(sig.s.t, 1_760_000_000_000);
        let keys: Vec<&str> = t["setting"]
            .values()
            .map(|r| r.v["key"].as_str().unwrap())
            .collect();
        assert!(keys.contains(&format!("notify.loud.@{account}").as_str()));
        assert!(keys.contains(&"appearance.theme"));
        assert_eq!(t[space_merge::SECRETS][&account].v["value"], "pw");
        // Written back, it is the new format, which old builds don't read.
        let raw = Note::Space(space.seal("mac", &Key([9; 32]))).to_message("matteo@posta.it", 0);
        assert!(String::from_utf8_lossy(&raw).contains("X-Piuma-Sync: space2"));
    }

    #[test]
    fn pairing_hands_the_key_over_only_with_the_same_code() {
        let (mac, mac_key) = device("mac", "Matteo's MacBook");
        let (space, _) = Space::create(&mac, Content::default());
        let (pixel, _) = device("pixel", "Pixel 8");

        let pairing = pair_start("482 615", &pixel);
        let answer = pair_answer(
            "482615",
            &pairing.request,
            &mac,
            &mac_key,
            space.content_key(),
        );
        // The folder shows no name: it travels sealed with the key.
        let note =
            String::from_utf8_lossy(&Note::Answer(answer.clone()).to_message("matteo@posta.it", 0))
                .into_owned();
        assert!(!note.contains("MacBook"));
        let request = pairing.request.clone();
        let answered = pairing.finish(&answer).unwrap();
        assert_eq!(answered.key().unwrap(), *space.content_key());
        assert_eq!(answered.name, "Matteo's MacBook");
        // The Mac vouched for the Pixel with its signing key.
        let mut vouched = request.device.clone();
        vouched.by = answered.by.clone();
        vouched.vouch = answered.vouch.clone();
        assert!(verify(&mac.sign, &vouch_message(&vouched), &vouched.vouch));

        let pairing = pair_start("482615", &pixel);
        let wrong = pair_answer(
            "482616",
            &pairing.request,
            &mac,
            &mac_key,
            space.content_key(),
        );
        assert_eq!(pairing.finish(&wrong).err(), Some(SpaceError::Code));
        assert_eq!(pair_code().len(), 6);
    }

    #[test]
    fn a_new_device_links_and_an_unlinked_one_is_left_out() {
        let (mac, mac_key) = device("mac", "MacBook");
        let (mut space, old_recovery) = Space::create(&mac, Content::default());
        let (pixel, pixel_key) = device("pixel", "Pixel 8");
        let (ipad, ipad_key) = device("ipad", "iPad");
        space.link(&pixel);
        space.link(&ipad);
        assert_eq!(space.content.devices.len(), 3);
        let before = space.seal("mac", &Key([9; 32]));
        let old_key = space.content_key().clone();
        assert!(Space::open_as(&before, "pixel", &pixel_key).is_ok());

        let recovery = space.unlink("pixel");
        let stored = space.seal("mac", &Key([9; 32]));
        assert_eq!(
            Space::open_as(&stored, "pixel", &pixel_key).unwrap_err(),
            SpaceError::NotLinked
        );
        assert!(Space::open_with(&stored, &old_key).is_err());
        assert!(Space::open_recovery(&stored, &old_recovery).is_err());
        assert!(Space::open_recovery(&stored, &recovery).is_ok());
        assert!(Space::open_as(&stored, "mac", &mac_key).is_ok());
        assert_eq!(
            Space::open_as(&stored, "ipad", &ipad_key)
                .unwrap()
                .content
                .devices
                .len(),
            2
        );
    }

    #[test]
    fn a_copy_is_signed_by_its_writer() {
        let (mac, mac_key) = device("mac", "MacBook");
        let (space, _) = Space::create(&mac, Content::default());
        let sealed = space.seal("mac", &mac_key);
        assert_eq!(sealed.signer, "mac");
        assert!(sealed.signed_by(&mac.sign));
        assert!(!sealed.signed_by(&sign_public(&Key::generate())));
        // Another signer name, or other wraps, break it.
        let mut other = sealed.clone();
        other.signer = "pixel".into();
        assert!(!other.signed_by(&mac.sign));
        let mut other = sealed.clone();
        other.wraps.pop();
        assert!(!other.signed_by(&mac.sign));
        let u = Unlink::new("pixel", "mac", 7, &mac_key);
        assert!(u.signed_by(&mac.sign));
        assert!(!Unlink { generation: 8, ..u }.signed_by(&mac.sign));
    }

    #[test]
    fn notes_go_through_a_message() {
        let (mac, _) = device("mac", "MacBook");
        let (space, _) = Space::create(&mac, Content::default());
        let note = Note::Space(space.seal("mac", &Key([9; 32])));
        let raw = note.to_message("matteo@posta.it", 1_760_000_000);
        assert_eq!(Note::from_message(&raw), Some(note));
        let req = Note::Request(pair_start("1", &mac).request);
        assert_eq!(
            Note::from_message(&req.to_message("matteo@posta.it", 0)),
            Some(req)
        );
        assert_eq!(Note::from_message(b"Subject: hi\r\n\r\nhello"), None);
    }
}
