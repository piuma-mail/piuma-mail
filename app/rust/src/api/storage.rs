//! Settings → Storage: how much room the mail takes on this device, how
//! long whole messages are kept for reading offline, and "Clear cached
//! mail". The mail always stays on the server.

use piuma_core::AccountId;

use super::engine::{
    bulk_reader, engine, kick_maintenance, now_secs, store, EngineError, ErrorKind,
};

/// What the Storage page shows.
#[derive(Debug, Clone)]
pub struct StorageInfo {
    /// Bytes the database takes on disk, with the copy kept from before
    /// the last update.
    pub total_bytes: i64,
    /// Of which the copy kept from before the last update, let go of at
    /// the next start (or after a week).
    pub backup_bytes: i64,
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
    let store = bulk_reader()?;
    let s = store.storage()?;
    Ok(StorageInfo {
        total_bytes: (s.file + s.backup) as i64,
        backup_bytes: s.backup as i64,
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

/// Pages given back per short write while clearing cached mail: about
/// 4 MB with SQLite's 4 KB pages.
const GIVE_BACK_PAGES: u32 = 1024;

/// "Clear cached mail" for one account: lets go of every whole message
/// and picture kept for it (the list rows and drafts stay; opening a
/// message fetches it again, and search still finds its words), then gives
/// the room back to the system, a few megabytes per short write so a sync
/// gets the database in between. The first time only, the database is
/// written anew once to make that possible: that step holds it until
/// done, and is refused ([ErrorKind::DiskFull]) when the disk hasn't
/// about twice the database's size free (the cache is cleared all the
/// same; Piuma reuses the room).
pub async fn clear_cached_mail(account_id: i64) -> Result<StorageInfo, EngineError> {
    store()?.queue_clear_cached(AccountId(account_id))?;
    engine()?
        .runtime
        .spawn_blocking(|| -> Result<(), EngineError> {
            // The background work too, until nothing is left.
            while store()?.maintain()? {}
            if store()?.needs_compacting()? {
                store()?.compact()?;
            }
            while store()?.give_back_room(GIVE_BACK_PAGES)? {}
            store()?.checkpoint()?;
            Ok(())
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    storage_info()
}
