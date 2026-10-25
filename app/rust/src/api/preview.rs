//! The attachment preview (`AttachPreview`): a PDF's pages drawn on this
//! device, and pictures whole.

use std::sync::{Arc, Mutex};

use piuma_core::remote::{Remote, RemoteError};
use piuma_core::{preview, AccountId};

use super::engine::{engine, store, EngineError, ErrorKind};
use crate::credentials;

/// Files fetched for a preview at most, in bytes.
const PREVIEW_MAX_BYTES: u64 = 40 * 1024 * 1024;

type Key = (i64, String, u32, u32);

/// The last file previewed, so turning its pages fetches it once.
static LAST: Mutex<Option<(Key, Arc<Vec<u8>>)>> = Mutex::new(None);

fn other(e: impl ToString) -> EngineError {
    EngineError::new(ErrorKind::Other, e.to_string())
}

async fn fetch(
    account_id: i64,
    mailbox: String,
    uid: u32,
    part_id: u32,
) -> Result<Arc<Vec<u8>>, EngineError> {
    let key = (account_id, mailbox.clone(), uid, part_id);
    if let Some((k, data)) = LAST.lock().map_err(other)?.as_ref() {
        if *k == key {
            return Ok(data.clone());
        }
    }
    let engine = engine()?;
    let id = AccountId(account_id);
    let file = store()?
        .attachment(id, &mailbox, uid, part_id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown attachment"))?;
    if file.size > PREVIEW_MAX_BYTES {
        return Err(EngineError::new(ErrorKind::Other, "too big to preview"));
    }
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
    let store_ref = engine.store.clone();
    let data = engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let data = conn
                .attachment(&store_ref, id, &mailbox, uid, part_id)
                .await?;
            conn.close().await;
            Ok::<_, RemoteError>(data)
        })
        .await
        .map_err(other)??;
    let data = Arc::new(data);
    *LAST.lock().map_err(other)? = Some((key, data.clone()));
    Ok(data)
}

/// How many pages an attached PDF has; None when it can't be drawn here
/// (damaged, or locked with a password).
pub async fn attachment_pages(
    account_id: i64,
    mailbox: String,
    uid: u32,
    part_id: u32,
) -> Result<Option<u32>, EngineError> {
    let data = fetch(account_id, mailbox, uid, part_id).await?;
    let pages = engine()?
        .runtime
        .spawn_blocking(move || preview::pages(&data))
        .await
        .map_err(other)?;
    Ok(pages.map(|n| n as u32))
}

/// Page [index] (from 0) of an attached PDF, as a PNG [width] pixels wide.
pub async fn attachment_page(
    account_id: i64,
    mailbox: String,
    uid: u32,
    part_id: u32,
    index: u32,
    width: u32,
) -> Result<Option<Vec<u8>>, EngineError> {
    let data = fetch(account_id, mailbox, uid, part_id).await?;
    engine()?
        .runtime
        .spawn_blocking(move || preview::page(&data, index as usize, width))
        .await
        .map_err(other)
}

/// An attached file whole, for a picture shown full size.
pub async fn attachment_data(
    account_id: i64,
    mailbox: String,
    uid: u32,
    part_id: u32,
) -> Result<Vec<u8>, EngineError> {
    Ok(fetch(account_id, mailbox, uid, part_id)
        .await?
        .as_ref()
        .clone())
}
