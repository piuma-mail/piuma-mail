//! Passwords live in the system keychain (Keychain on Apple systems,
//! Credential Manager on Windows, Secret Service on Linux), never in the
//! database. Android has no keychain Rust can reach: there the app keeps
//! them in the Android Keystore and hands them over at start
//! ([`remember`]); the engine only holds them in memory.

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
    EngineError {
        kind: ErrorKind::Keychain,
        detail: e.to_string(),
    }
}

pub fn save(id: AccountId, password: &str) -> Result<(), EngineError> {
    save_key(&account_key(id), password)
}

/// Forgets an account's password, when the account is removed.
pub fn forget(id: AccountId) {
    forget_key(&account_key(id));
}

pub fn load(id: AccountId) -> Result<String, EngineError> {
    load_key(&account_key(id))
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
    #[cfg(debug_assertions)]
    if let Some(memory) = test_memory() {
        return memory
            .lock()
            .unwrap()
            .get(key)
            .cloned()
            .ok_or_else(|| EngineError {
                kind: ErrorKind::Keychain,
                detail: "no password".into(),
            });
    }
    #[cfg(target_os = "android")]
    {
        held().lock().unwrap().get(key).cloned().ok_or(EngineError {
            kind: ErrorKind::Keychain,
            detail: "no password".into(),
        })
    }
    #[cfg(not(target_os = "android"))]
    entry(key)?.get_password().map_err(keychain)
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
