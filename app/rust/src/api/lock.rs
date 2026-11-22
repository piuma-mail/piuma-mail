//! The app lock (Settings › Privacy & security › Lock Piuma). The app
//! draws the lock screen and keeps the timers (`app/lib/lock/`); the
//! engine hashes the PIN (`piuma_core::app_lock`) and, outside Android,
//! keeps the lock's secret in the system keychain, next to the passwords.
//! On Android the app keeps it in the Keystore itself, as it does the
//! passwords (`android_passwords.dart`).
//!
//! The secret is a small JSON the app writes: the PIN's hash and the
//! wrong tries so far, so closing the app doesn't reset the wait.

use flutter_rust_bridge::frb;
use piuma_core::app_lock;

use super::engine::{EngineError, ErrorKind};
use crate::credentials;

/// The keychain entry the lock's secret is kept under.
pub const LOCK_KEY: &str = "app-lock";

/// The hash to keep for a new PIN. Slow on purpose: off the thread that
/// draws.
pub async fn lock_hash_pin(pin: String) -> Result<String, EngineError> {
    app_lock::hash_pin(&pin).map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))
}

/// Whether [pin] is the one [kept] was made from. Slow on purpose.
pub async fn lock_verify_pin(pin: String, kept: String) -> bool {
    app_lock::verify_pin(&pin, &kept)
}

/// The lock's secret, or None when none is kept. An error when the
/// keychain can't answer now (locked, or no keyring on Linux).
#[frb(sync)]
pub fn lock_secret_load() -> Result<Option<String>, EngineError> {
    match credentials::read_secret(LOCK_KEY) {
        Ok(v) => Ok(Some(v)),
        Err(credentials::Unreadable::Absent) => Ok(None),
        Err(credentials::Unreadable::Unavailable(e)) => Err(e),
    }
}

#[frb(sync)]
pub fn lock_secret_save(value: String) -> Result<(), EngineError> {
    credentials::save_key(LOCK_KEY, &value)
}

#[frb(sync)]
pub fn lock_secret_forget() {
    credentials::forget_key(LOCK_KEY);
}
