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
        getrandom::getrandom(&mut k).expect("the system has randomness");
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
    getrandom::getrandom(&mut nonce).expect("the system has randomness");
    let cipher = XChaCha20Poly1305::new((&key.0).into());
    let sealed = cipher
        .encrypt(XNonce::from_slice(&nonce), plain)
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
    let cipher = XChaCha20Poly1305::new((&key.0).into());
    cipher
        .decrypt(XNonce::from_slice(&sealed[4..28]), &sealed[28..])
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

/// What the space holds. `tables` are rows of the store's own tables, by
/// table name; `passwords` go by account address.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Content {
    /// The store's schema version that wrote the rows.
    pub schema: usize,
    pub updated_at: i64,
    /// The device that wrote it last.
    pub updated_by: String,
    pub tables: serde_json::Map<String, serde_json::Value>,
    pub passwords: Vec<(String, String)>,
    pub devices: Vec<Device>,
    /// The recovery key, so a linked device can show the phrase again.
    #[serde(default)]
    pub recovery: String,
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
    }
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

const RECOVERY: &str = "recovery";

/// The space as stored: the content key wrapped for each reader, and the
/// sealed content.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SealedSpace {
    version: u32,
    wraps: Vec<Wrap>,
    #[serde(with = "b64")]
    content: Vec<u8>,
    /// What a new device shows before it can open the space ("We found
    /// your space"). In the clear, so it carries counts and device names
    /// only.
    #[serde(default)]
    pub about: About,
}

/// The few things readable without the key: how much the space holds,
/// when it last changed, and the devices that can approve a new one.
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
    pub name: String,
    pub kind: String,
    pub last_seen: i64,
}

/// An open space: its content and the content key, kept to write it again.
#[derive(Debug, Clone)]
pub struct Space {
    pub content: Content,
    key: Key,
    recovery: Vec<u8>,
}

impl Space {
    /// A new space, readable by this device and by the recovery phrase.
    /// Returns it with the recovery key, to be shown once.
    pub fn create(device: &Device, content: Content) -> (Space, Key) {
        let key = Key::generate();
        let recovery = Key::generate();
        let mut space = Space {
            content: Content {
                recovery: recovery.to_hex(),
                ..content
            },
            recovery: seal(&recovery, &key.0),
            key,
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
    pub fn open_with(sealed: &SealedSpace, key: &Key) -> Result<Space> {
        let plain = open(key, &sealed.content)?;
        let content =
            serde_json::from_slice(&plain).map_err(|e| SpaceError::Format(e.to_string()))?;
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
        })
    }

    /// The content key, to hand to a new device while pairing.
    pub fn content_key(&self) -> &Key {
        &self.key
    }

    /// Lets one more device open the space, or marks this one as seen.
    pub fn link(&mut self, device: &Device) {
        self.content.touch(device, now());
    }

    /// Whether a device is linked.
    pub fn is_linked(&self, device_id: &str) -> bool {
        self.content.devices.iter().any(|d| d.id == device_id)
    }

    /// Unlinks a device: a new content key for the others, and a new
    /// recovery phrase, returned to be shown. What the device kept no
    /// longer opens the space.
    pub fn unlink(&mut self, device_id: &str) -> Key {
        self.content.devices.retain(|d| d.id != device_id);
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

    /// Puts this device's `content` in, keeping the space's own: its
    /// devices and recovery key.
    pub fn replace(&mut self, content: Content) {
        let devices = std::mem::take(&mut self.content.devices);
        let recovery = std::mem::take(&mut self.content.recovery);
        self.content = Content {
            devices,
            recovery,
            ..content
        };
    }

    /// Seals the content for storing, its key for each linked device.
    pub fn seal(&self) -> SealedSpace {
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
        let rows = |t: &str| {
            self.content
                .tables
                .get(t)
                .and_then(|v| v.as_array())
                .map_or(0, Vec::len)
        };
        SealedSpace {
            version: 1,
            wraps,
            content: seal(&self.key, &plain),
            about: About {
                accounts: rows("account"),
                groups: rows("address_group"),
                signatures: rows("signature"),
                updated_at: self.content.updated_at,
                devices: self
                    .content
                    .devices
                    .iter()
                    .map(|d| AboutDevice {
                        name: d.name.clone(),
                        kind: d.kind.clone(),
                        last_seen: d.last_seen,
                    })
                    .collect(),
            },
        }
    }
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
    /// The device that approved, by name.
    pub by: String,
    #[serde(with = "b64")]
    spake: Vec<u8>,
    #[serde(with = "b64")]
    key: Vec<u8>,
}

/// The new device's side, kept in memory while it waits for an answer.
pub struct Pairing {
    state: Spake2<Ed25519Group>,
    pub request: PairRequest,
}

/// Six random digits, as "482615".
pub fn pair_code() -> String {
    let mut b = [0u8; 4];
    getrandom::getrandom(&mut b).expect("the system has randomness");
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
    getrandom::getrandom(&mut id).expect("the system has randomness");
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
pub fn pair_answer(code: &str, request: &PairRequest, by: &str, key: &Key) -> PairAnswer {
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
    PairAnswer {
        request: request.id.clone(),
        by: by.to_owned(),
        spake: msg,
        key: seal(&channel, &key.0),
    }
}

impl Pairing {
    /// The content key from the answer; [SpaceError::Code] when the codes
    /// on the two sides differ.
    pub fn finish(self, answer: &PairAnswer) -> Result<Key> {
        if answer.request != self.request.id {
            return Err(SpaceError::Code);
        }
        let shared = self
            .state
            .finish(&answer.spake)
            .map_err(|_| SpaceError::Code)?;
        let channel = channel_key(&shared, &self.request.id);
        unwrap(&channel, &answer.key).map_err(|_| SpaceError::Code)
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
            Note::Space(_) => "space",
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
        let tag = m.header(HEADER)?.as_text()?.trim().to_owned();
        let data = m
            .body_bytes()
            .or_else(|| m.attachment(0).map(|a| a.contents()))?;
        Some(match tag.as_str() {
            "space" => Note::Space(SealedSpace::from_bytes(data).ok()?),
            "request" => Note::Request(serde_json::from_slice(data).ok()?),
            "answer" => Note::Answer(serde_json::from_slice(data).ok()?),
            "refused" => Note::Refused(String::from_utf8(data.to_vec()).ok()?),
            "moved" => Note::Moved(String::from_utf8(data.to_vec()).ok()?),
            _ => return None,
        })
    }
}

trait BodyBytes {
    fn body_bytes(&self) -> Option<&[u8]>;
}

impl BodyBytes for mail_parser::Message<'_> {
    fn body_bytes(&self) -> Option<&[u8]> {
        self.part(0).map(|p| p.contents())
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
    getrandom::getrandom(&mut b).expect("the system has randomness");
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
            },
            secret,
        )
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

    #[test]
    fn a_space_opens_for_its_devices_and_the_phrase() {
        let (mac, mac_key) = device("mac", "MacBook");
        let content = Content {
            passwords: vec![("matteo@posta.it".into(), "secret".into())],
            ..Default::default()
        };
        let (space, recovery) = Space::create(&mac, content);
        let stored = SealedSpace::from_bytes(&space.seal().to_bytes()).unwrap();
        let opened = Space::open_as(&stored, "mac", &mac_key).unwrap();
        assert_eq!(opened.content.passwords[0].1, "secret");
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
    fn pairing_hands_the_key_over_only_with_the_same_code() {
        let (mac, _) = device("mac", "MacBook");
        let (space, _) = Space::create(&mac, Content::default());
        let (pixel, _) = device("pixel", "Pixel 8");

        let pairing = pair_start("482 615", &pixel);
        let answer = pair_answer("482615", &pairing.request, "MacBook", space.content_key());
        assert_eq!(pairing.finish(&answer).unwrap(), *space.content_key());

        let pairing = pair_start("482615", &pixel);
        let wrong = pair_answer("482616", &pairing.request, "MacBook", space.content_key());
        assert_eq!(pairing.finish(&wrong).unwrap_err(), SpaceError::Code);
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
        let before = space.seal();
        let old_key = space.content_key().clone();
        assert!(Space::open_as(&before, "pixel", &pixel_key).is_ok());

        let recovery = space.unlink("pixel");
        let stored = space.seal();
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
    fn notes_go_through_a_message() {
        let (mac, _) = device("mac", "MacBook");
        let (space, _) = Space::create(&mac, Content::default());
        let note = Note::Space(space.seal());
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
