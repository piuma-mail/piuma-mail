//! Passwords live in the system keychain (Keychain on Apple systems,
//! Credential Manager on Windows, Secret Service on Linux), never in the
//! database. Android has no keychain Rust can reach: there the app keeps
//! them in the Android Keystore and hands them over at start
//! ([`remember`]); the engine only holds them in memory.
//!
//! An account signed in with OAuth keeps an `oauth::Stored` here in place
//! of its password: the provider, the client and the refresh token, never
//! anywhere else. When the provider sends a new refresh token the engine
//! keeps it at once ([`keep`]); on Android the app and the background
//! service write it to the Keystore ([`claim_kept`], [`release_kept`]).

use piuma_core::AccountId;

use crate::api::engine::{EngineError, ErrorKind};

#[cfg(not(target_os = "android"))]
const SERVICE: &str = "mail.piuma";

/// On Windows a build the installer didn't put in place keeps its own
/// passwords, as it keeps its own folder (the app's `dev_copy.dart`):
/// the installer keeps `Update.exe` one folder above the program.
#[cfg(not(target_os = "android"))]
fn service() -> &'static str {
    #[cfg(target_os = "windows")]
    {
        static DEV: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
        let dev = *DEV.get_or_init(|| {
            let exe = std::env::current_exe().ok();
            let root = exe.as_deref().and_then(|e| e.parent()?.parent());
            !root.is_some_and(|dir| dir.join("Update.exe").exists())
        });
        if dev {
            return "mail.piuma.dev";
        }
    }
    SERVICE
}

/// The name a password is kept under: `account-1`, `calendar-2`.
fn account_key(id: AccountId) -> String {
    format!("account-{}", id.0)
}

pub fn calendar_key(source: i64) -> String {
    format!("calendar-{source}")
}

#[cfg(not(target_os = "android"))]
fn entry(key: &str) -> Result<keyring::Entry, EngineError> {
    keyring::Entry::new(service(), key).map_err(keychain)
}

#[cfg(not(target_os = "android"))]
fn keychain(e: keyring::Error) -> EngineError {
    let detail = e.to_string();
    let kind = if no_keyring(&e) {
        ErrorKind::NoKeyring
    } else {
        ErrorKind::Keychain
    };
    EngineError { kind, detail }
}

/// Linux without a Secret Service (no GNOME Keyring, KWallet or
/// KeePassXC answering on D-Bus, or no D-Bus session at all): passwords
/// have nowhere safe to go, and are never written to a plain file instead.
#[cfg(not(target_os = "android"))]
fn no_keyring(e: &keyring::Error) -> bool {
    if !cfg!(target_os = "linux") {
        return false;
    }
    match e {
        keyring::Error::NoStorageAccess(_) => true,
        keyring::Error::PlatformFailure(inner) => missing_service(&inner.to_string()),
        _ => false,
    }
}

/// What the Secret Service and D-Bus libraries say when nobody answers.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
fn missing_service(text: &str) -> bool {
    let text = text.to_ascii_lowercase();
    [
        "org.freedesktop.secrets",
        "serviceunknown",
        "secret service",
        "secretservice",
        "dbus",
        "d-bus",
        "no such interface",
    ]
    .iter()
    .any(|w| text.contains(w))
}

pub fn save(id: AccountId, password: &str) -> Result<(), EngineError> {
    save_key(&account_key(id), password)
}

/// Keeps a secret the engine itself got (an OAuth sign-in, a renewed
/// refresh token). On Android it also waits for the app or the background
/// service to put it in the Keystore.
pub fn keep(id: AccountId, secret: &str) -> Result<(), EngineError> {
    save(id, secret)?;
    #[cfg(target_os = "android")]
    {
        lock_kept().push(&account_key(id), secret);
        // Into the Keystore now, not at the next sync: the app is told at
        // once, and the background service wakes up for it.
        crate::api::engine::secrets_changed(id);
        crate::background::wake();
    }
    Ok(())
}

/// Android: whether [`keep`] got secrets the Keystore doesn't have yet,
/// that nobody is writing now.
pub fn has_kept() -> bool {
    #[cfg(target_os = "android")]
    {
        lock_kept().ready(std::time::Instant::now())
    }
    #[cfg(not(target_os = "android"))]
    false
}

/// One secret for the Keystore: its keychain name, the value, and its
/// place in the order they came ([`Kept`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeptEntry {
    pub key: String,
    pub value: String,
    pub seq: i64,
}

/// How long a claim lasts before another writer may take the secrets
/// over, in case the first one died.
const LEASE: std::time::Duration = std::time::Duration::from_secs(30);
/// After a write that failed, the background service tries again this
/// much later, not in a loop; the app and the jobs try at their next
/// claim.
const RETRY: std::time::Duration = std::time::Duration::from_secs(30);

/// Secrets waiting for the Android Keystore. The app (Dart) and the
/// background service and jobs (Kotlin) write them: one at a time, under a
/// claim ([`Kept::claim`]), so the newest value of each key is always the
/// last one written. A secret leaves only once its writer says the write
/// went through ([`Kept::release`]), and only if nothing newer came for
/// its key meanwhile.
#[derive(Debug, Default)]
#[cfg_attr(not(target_os = "android"), allow(dead_code))]
struct Kept {
    /// The last number given to a secret or a claim.
    next: i64,
    /// The newest secret of each key, not written yet.
    waiting: std::collections::BTreeMap<String, (i64, String)>,
    /// The number of each key's newest secret, written or not.
    newest: std::collections::BTreeMap<String, i64>,
    /// The claim being written, and when it was taken.
    claim: Option<(i64, std::time::Instant)>,
    retry_at: Option<std::time::Instant>,
}

#[cfg_attr(not(target_os = "android"), allow(dead_code))]
impl Kept {
    fn push(&mut self, key: &str, value: &str) {
        self.next += 1;
        self.waiting
            .insert(key.to_owned(), (self.next, value.to_owned()));
        self.newest.insert(key.to_owned(), self.next);
        self.retry_at = None;
    }

    fn claimed(&self, now: std::time::Instant) -> bool {
        self.claim.is_some_and(|(_, at)| now < at + LEASE)
    }

    /// Something to write, that nobody is writing, and not just failed.
    fn ready(&self, now: std::time::Instant) -> bool {
        !self.waiting.is_empty() && !self.claimed(now) && self.retry_at.is_none_or(|t| now >= t)
    }

    /// The secrets to write, and the claim to name when done; None when
    /// there are none, or another writer has them now.
    fn claim(&mut self, now: std::time::Instant) -> Option<(i64, Vec<KeptEntry>)> {
        if self.waiting.is_empty() || self.claimed(now) {
            return None;
        }
        self.next += 1;
        self.claim = Some((self.next, now));
        let entries = self
            .waiting
            .iter()
            .map(|(key, (seq, value))| KeptEntry {
                key: key.clone(),
                value: value.clone(),
                seq: *seq,
            })
            .collect();
        Some((self.next, entries))
    }

    /// The writer of `claim` wrote these `(key, seq)` to the Keystore;
    /// the rest of its claim failed. `current` reads a key's value now,
    /// for a write that may have put an older value over a newer one.
    fn release(
        &mut self,
        claim: i64,
        written: &[(String, i64)],
        now: std::time::Instant,
        current: impl Fn(&str) -> Option<String>,
    ) {
        let ours = self.claim.is_some_and(|(c, _)| c == claim);
        if ours {
            self.claim = None;
        }
        for (key, seq) in written {
            if self.waiting.get(key).is_some_and(|(s, _)| s == seq) {
                self.waiting.remove(key);
            } else if !ours
                && self.newest.get(key).is_some_and(|n| n > seq)
                && !self.waiting.contains_key(key)
            {
                // A writer whose claim ran out wrote after a newer one:
                // the newest goes in again.
                if let Some(value) = current(key) {
                    self.push(key, &value);
                }
            }
        }
        if !self.waiting.is_empty() && ours {
            self.retry_at = Some(now + RETRY);
        }
    }
}

#[cfg(target_os = "android")]
fn lock_kept() -> std::sync::MutexGuard<'static, Kept> {
    static KEPT: std::sync::OnceLock<std::sync::Mutex<Kept>> = std::sync::OnceLock::new();
    KEPT.get_or_init(Default::default)
        .lock()
        .unwrap_or_else(|e| e.into_inner())
}

/// Android: the secrets [`keep`] got that the Keystore doesn't have yet,
/// by keychain name, and the claim to hand back to [`release_kept`] once
/// they are written. None when there are none, or another writer has
/// them now. Elsewhere always None: the keychain has them.
pub fn claim_kept() -> Option<(i64, Vec<KeptEntry>)> {
    #[cfg(target_os = "android")]
    {
        lock_kept().claim(std::time::Instant::now())
    }
    #[cfg(not(target_os = "android"))]
    None
}

/// Android: the writer of `claim` put these `(key, seq)` in the Keystore;
/// whatever else it claimed stays, for the next writer.
pub fn release_kept(claim: i64, written: &[(String, i64)]) {
    #[cfg(target_os = "android")]
    lock_kept().release(claim, written, std::time::Instant::now(), |key| {
        read_key(key).ok()
    });
    #[cfg(not(target_os = "android"))]
    let _ = (claim, written);
}

/// Forgets an account's password, when the account is removed.
pub fn forget(id: AccountId) {
    forget_key(&account_key(id));
}

pub fn load(id: AccountId) -> Result<String, EngineError> {
    load_key(&account_key(id))
}

/// Why a password can't be read.
#[derive(Debug)]
pub enum Unreadable {
    /// None is kept for it: only signing in again brings it back (on
    /// Android, unless the app hands it over late).
    Absent,
    /// The keychain is locked or not answering; it may be later. Never on
    /// Android, where the passwords are only held in memory.
    #[cfg_attr(target_os = "android", allow(dead_code))]
    Unavailable(EngineError),
}

/// As [`load`], telling a missing password from a keychain that can't
/// answer now.
pub fn read(id: AccountId) -> Result<String, Unreadable> {
    read_key(&account_key(id))
}

pub fn save_key(key: &str, password: &str) -> Result<(), EngineError> {
    #[cfg(debug_assertions)]
    if let Some(memory) = test_memory() {
        memory
            .lock()
            .unwrap()
            .insert(key.to_owned(), password.to_owned());
        return Ok(());
    }
    #[cfg(target_os = "android")]
    {
        remember_key(key, password);
        Ok(())
    }
    #[cfg(not(target_os = "android"))]
    entry(key)?.set_password(password).map_err(keychain)
}

/// Forgets a password, when what used it is removed.
pub fn forget_key(key: &str) {
    #[cfg(debug_assertions)]
    if let Some(memory) = test_memory() {
        memory.lock().unwrap().remove(key);
        return;
    }
    #[cfg(target_os = "android")]
    held().lock().unwrap().remove(key);
    #[cfg(not(target_os = "android"))]
    if let Ok(e) = entry(key) {
        let _ = e.delete_credential();
    }
}

pub fn load_key(key: &str) -> Result<String, EngineError> {
    read_key(key).map_err(|e| match e {
        Unreadable::Absent => EngineError {
            kind: ErrorKind::Keychain,
            detail: "no password".into(),
        },
        Unreadable::Unavailable(e) => e,
    })
}

/// As [`load_key`], telling a missing secret from a keychain that can't
/// answer now (the app lock needs both).
pub fn read_secret(key: &str) -> Result<String, Unreadable> {
    read_key(key)
}

fn read_key(key: &str) -> Result<String, Unreadable> {
    #[cfg(debug_assertions)]
    if let Some(memory) = test_memory() {
        return memory
            .lock()
            .unwrap()
            .get(key)
            .cloned()
            .ok_or(Unreadable::Absent);
    }
    #[cfg(target_os = "android")]
    {
        held()
            .lock()
            .unwrap()
            .get(key)
            .cloned()
            .ok_or(Unreadable::Absent)
    }
    #[cfg(not(target_os = "android"))]
    match entry(key).map_err(Unreadable::Unavailable)?.get_password() {
        Ok(password) => Ok(password),
        Err(keyring::Error::NoEntry) => Err(Unreadable::Absent),
        Err(e) => Err(Unreadable::Unavailable(keychain(e))),
    }
}

/// Android: the passwords the app handed over, for this run.
#[cfg(target_os = "android")]
fn held() -> &'static std::sync::Mutex<std::collections::HashMap<String, String>> {
    use std::collections::HashMap;
    use std::sync::{Mutex, OnceLock};
    static HELD: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();
    HELD.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Android: keeps an account's password in memory for this run.
#[cfg(target_os = "android")]
pub fn remember(id: AccountId, password: &str) {
    remember_key(&account_key(id), password);
}

/// Android: keeps any password in memory for this run.
#[cfg(target_os = "android")]
pub fn remember_key(key: &str, password: &str) {
    held()
        .lock()
        .unwrap()
        .insert(key.to_owned(), password.to_owned());
}

/// Debug builds only: with PIUMA_TEST_MEMORY_KEYCHAIN set, passwords stay
/// in memory, so end-to-end tests run on machines without a keychain.
#[cfg(debug_assertions)]
fn test_memory() -> Option<&'static std::sync::Mutex<std::collections::HashMap<String, String>>> {
    use std::collections::HashMap;
    use std::sync::{Mutex, OnceLock};
    static MEMORY: OnceLock<Mutex<HashMap<String, String>>> = OnceLock::new();
    std::env::var_os("PIUMA_TEST_MEMORY_KEYCHAIN")?;
    Some(MEMORY.get_or_init(|| Mutex::new(HashMap::new())))
}

#[cfg(test)]
mod tests {
    #[test]
    fn a_missing_secret_service_is_told_apart() {
        for text in [
            "The name org.freedesktop.secrets was not provided by any .service files",
            "D-Bus error: org.freedesktop.DBus.Error.ServiceUnknown",
            "Unable to autolaunch a dbus-daemon without a $DISPLAY for X11",
        ] {
            assert!(super::missing_service(text), "{text}");
        }
        assert!(!super::missing_service("Prompt dismissed"));
    }
}

#[cfg(test)]
mod kept_tests {
    use super::*;
    use std::time::{Duration, Instant};

    fn written(entries: &[KeptEntry]) -> Vec<(String, i64)> {
        entries.iter().map(|e| (e.key.clone(), e.seq)).collect()
    }

    #[test]
    fn a_secret_stays_until_its_write_went_through() {
        let now = Instant::now();
        let mut kept = Kept::default();
        kept.push("account-1", "first");
        let (claim, entries) = kept.claim(now).unwrap();
        assert_eq!(entries[0].value, "first");
        // Claimed: nobody else gets it meanwhile.
        assert!(kept.claim(now).is_none());
        assert!(!kept.ready(now));
        // The write failed: it stays, and is tried again later, not in a
        // loop.
        kept.release(claim, &[], now, |_| None);
        assert!(!kept.ready(now));
        assert!(kept.ready(now + RETRY));
        let (claim, entries) = kept.claim(now).unwrap();
        kept.release(claim, &written(&entries), now, |_| None);
        assert!(kept.claim(now).is_none());
    }

    #[test]
    fn the_newest_secret_of_a_key_is_the_last_one_written() {
        let now = Instant::now();
        let mut kept = Kept::default();
        kept.push("account-1", "old");
        let (claim, entries) = kept.claim(now).unwrap();
        // A newer one comes while the old one is written.
        kept.push("account-1", "new");
        kept.release(claim, &written(&entries), now, |_| None);
        let (claim, entries) = kept.claim(now).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].value, "new");
        kept.release(claim, &written(&entries), now, |_| None);
        assert!(kept.claim(now).is_none());
    }

    #[test]
    fn a_late_writer_after_its_claim_ran_out_does_not_win() {
        let now = Instant::now();
        let mut kept = Kept::default();
        kept.push("account-1", "old");
        let (slow, old) = kept.claim(now).unwrap();
        kept.push("account-1", "new");
        // The slow writer's claim runs out; another writes the newest.
        let later = now + LEASE + Duration::from_secs(1);
        let (fast, new) = kept.claim(later).unwrap();
        assert_eq!(new[0].value, "new");
        kept.release(fast, &written(&new), later, |_| None);
        // Then the slow one's old write lands: the newest goes in again.
        kept.release(slow, &written(&old), later, |_| Some("new".into()));
        let (_, again) = kept.claim(later).unwrap();
        assert_eq!(again[0].value, "new");
    }
}
