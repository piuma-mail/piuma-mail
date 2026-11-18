//! Settings → Storage: how much room the mail takes on this device, how
//! long whole messages are kept for reading offline, and "Clear cached
//! mail". The mail always stays on the server.

use piuma_core::AccountId;

use super::engine::{engine, kick_maintenance, now_secs, reader, store, EngineError, ErrorKind};

/// What the Storage page shows.
#[derive(Debug, Clone)]
pub struct StorageInfo {
    /// Bytes the database takes on disk.
    pub total_bytes: i64,
    /// Of which free, given back to the system as the app goes.
    pub free_bytes: i64,
    pub accounts: Vec<AccountStorageInfo>,
    /// How many days whole messages are kept; None keeps them for good.
    pub keep_days: Option<u32>,
}

/// One account's part of [`StorageInfo`].
#[derive(Debug, Clone)]
pub struct AccountStorageInfo {
    pub account_id: i64,
    pub messages: i64,
    /// Bytes of the whole messages and their pictures kept for reading
    /// offline: what "Clear cached mail" gives back.
    pub cached_bytes: i64,
}

/// How much room the mail takes. Reads every cached body's length, so it
/// runs off the thread that draws.
pub fn storage_info() -> Result<StorageInfo, EngineError> {
    let store = reader()?;
    let s = store.storage()?;
    Ok(StorageInfo {
        total_bytes: s.file as i64,
        free_bytes: s.free as i64,
        accounts: s
            .accounts
            .into_iter()
            .map(|a| AccountStorageInfo {
                account_id: a.account.0,
                messages: a.messages as i64,
                cached_bytes: (a.bodies + a.pictures) as i64,
            })
            .collect(),
        keep_days: store.keep_bodies_days()?,
    })
}

/// Keeps whole messages for `days` days (None: for good); older ones are
/// let go of in the background and fetched again when opened.
pub fn set_keep_days(days: Option<u32>) -> Result<(), EngineError> {
    let store = store()?;
    store.set_keep_bodies_days(days)?;
    store.queue_body_clean_up(now_secs())?;
    drop(store);
    kick_maintenance();
    Ok(())
}

/// "Clear cached mail" for one account: lets go of every whole message
/// and picture kept for it (the list rows and drafts stay; opening a
/// message fetches it again), then gives the room back to the system.
/// Takes a while on a big mailbox; each step is a short write, but the
/// last one, the database written anew, holds it until done.
pub async fn clear_cached_mail(account_id: i64) -> Result<StorageInfo, EngineError> {
    store()?.queue_clear_cached(AccountId(account_id))?;
    engine()?
        .runtime
        .spawn_blocking(|| -> Result<(), EngineError> {
            // The background work too, until nothing is left.
            while store()?.maintain()? {}
            store()?.compact()?;
            Ok(())
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    storage_info()
}
