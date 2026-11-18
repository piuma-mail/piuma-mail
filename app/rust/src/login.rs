//! What each account signs in with ([`piuma_core::Login`]): its password,
//! or its OAuth sign-in, from the keychain ([`crate::credentials`]); and
//! the server certificates the person trusted for it, from the settings
//! (`account.<id>.cert.<host>`, their SHA-256 fingerprints).
//!
//! One OAuth session per account for the whole run, so every connection
//! shares its access token and renews it once. A refresh token the
//! provider replaces is kept in the keychain at once.

use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex};

use piuma_core::cert;
use piuma_core::oauth::{Session, Stored};
use piuma_core::tls::Pin;
use piuma_core::{AccountId, AccountKind, Login};

use crate::api::engine::{reader, store, EngineError, ErrorKind};
use crate::credentials::{self, Unreadable};

fn sessions() -> &'static Mutex<HashMap<i64, Arc<Session>>> {
    static SESSIONS: std::sync::OnceLock<Mutex<HashMap<i64, Arc<Session>>>> =
        std::sync::OnceLock::new();
    SESSIONS.get_or_init(Mutex::default)
}

/// The setting that says an account signs in with a provider's page.
pub(crate) fn oauth_key(account: i64) -> String {
    format!("account.{account}.oauth")
}

/// The setting that keeps the certificate trusted for one of its servers.
pub(crate) fn cert_key(account: i64, host: &str) -> String {
    format!(
        "account.{account}.cert.{}",
        host.trim().to_ascii_lowercase()
    )
}

/// A new session for an OAuth sign-in, keeping new refresh tokens for
/// the account `id` names (set once a new account has its id).
pub(crate) fn session(id: Arc<AtomicI64>, stored: Stored) -> Option<Arc<Session>> {
    let session = Session::new(stored, move |changed| {
        let id = id.load(Ordering::Relaxed);
        // A new account without its id yet keeps it once it has one.
        if id == 0 {
            return Err("no account yet".into());
        }
        // Not kept: the session keeps the new token for this run and tries
        // again at each use. The old one stays where it was: Microsoft's
        // stay valid until they run out, Google's don't change.
        credentials::keep(AccountId(id), &changed.to_secret()).map_err(|e| {
            piuma_core::feedback::log(
                piuma_core::feedback::Level::Warn,
                "oauth",
                &format!("a renewed sign-in could not be kept yet: {:?}", e.kind),
            );
            e.detail
        })
    })?;
    Some(Arc::new(session))
}

/// Uses `session` for the account from now on.
pub(crate) fn remember_session(id: AccountId, session: Arc<Session>) {
    sessions()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .insert(id.0, session);
}

/// Forgets the account's session, when it signs in again or goes.
pub(crate) fn forget_session(id: AccountId) {
    sessions()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .remove(&id.0);
}

fn from_secret(id: AccountId, secret: &str) -> Result<Login, Unreadable> {
    let Some(stored) = Stored::from_secret(secret) else {
        return Ok(Login::password(secret));
    };
    let mut cached = sessions().lock().unwrap_or_else(|e| e.into_inner());
    if let Some(s) = cached.get(&id.0) {
        return Ok(Login::oauth(s.clone()));
    }
    // A provider this build doesn't know: only signing in again helps.
    let s = session(Arc::new(AtomicI64::new(id.0)), stored).ok_or(Unreadable::Absent)?;
    cached.insert(id.0, s.clone());
    Ok(Login::oauth(s))
}

/// The certificates trusted for the account's servers.
pub(crate) fn pins(id: AccountId) -> Vec<Pin> {
    let Ok(store) = reader() else {
        return Vec::new();
    };
    let Ok(Some(account)) = store.account(id) else {
        return Vec::new();
    };
    let hosts = match &account.kind {
        AccountKind::Imap { imap, smtp, .. } => vec![imap.host.clone(), smtp.host.clone()],
        // The session's host. An API on another host with a certificate
        // nobody vouches for is refused (the session's settings name one).
        AccountKind::Jmap { session_url, .. } => session_url
            .split("://")
            .nth(1)
            .and_then(|r| r.split(['/', ':']).next())
            .map(|h| vec![h.to_owned()])
            .unwrap_or_default(),
    };
    hosts
        .into_iter()
        .filter_map(|host| {
            let text = store.setting(&cert_key(id.0, &host)).ok()??;
            Some(Pin {
                sha256: cert::parse_fingerprint(&text)?,
                host,
            })
        })
        .collect()
}

/// Trusts a certificate for one of the account's servers, in place of
/// any trusted before for it.
pub(crate) fn trust(id: AccountId, host: &str, fingerprint: &str) -> Result<(), EngineError> {
    let sha = cert::parse_fingerprint(fingerprint)
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "not a SHA-256 fingerprint"))?;
    store()?.set_setting(&cert_key(id.0, host), &cert::fingerprint_text(&sha))?;
    Ok(())
}

/// What the account signs in with now.
pub(crate) fn load(id: AccountId) -> Result<Login, EngineError> {
    let secret = credentials::load(id)?;
    let login = from_secret(id, &secret)
        .map_err(|_| EngineError::new(ErrorKind::Keychain, "sign-in of an unknown provider"))?;
    Ok(login.with_pins(pins(id)))
}

/// As [`load`], telling a missing sign-in from a keychain that can't
/// answer now.
pub(crate) fn read(id: AccountId) -> Result<Login, Unreadable> {
    let secret = credentials::read(id)?;
    Ok(from_secret(id, &secret)?.with_pins(pins(id)))
}

/// The OAuth sign-in kept for an account, if it has one.
pub(crate) fn stored(id: AccountId) -> Option<Stored> {
    Stored::from_secret(&credentials::load(id).ok()?)
}
