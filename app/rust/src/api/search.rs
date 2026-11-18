//! Search beyond this device, and searches kept under a name. The search
//! of what is here is `engine::search`.

use std::sync::Mutex;
use std::time::Duration;

use flutter_rust_bridge::frb;
use piuma_core::remote::{Remote, SERVER_HITS};
use piuma_core::{AccountId, Query};

use crate::api::engine::{
    engine, in_conversation, inbox_row, reader, store, EngineError, ErrorKind, SearchHit,
};
use crate::credentials;

/// What the servers found.
pub struct ServerSearchResult {
    /// Newest first, all on this device now; what the search here found
    /// may be among them.
    pub hits: Vec<SearchHit>,
    /// Whether any server was asked: not for a search only this device
    /// can answer (`in:vault`, `from:people`), or one of filters only.
    pub asked: bool,
    /// Accounts whose server couldn't be reached, refused or took too long.
    pub failed: u32,
    /// Some accounts could only be searched in part: a folder refused,
    /// accented text the server couldn't take, too many folders.
    pub partial: bool,
}

/// How long one account's server search may take.
const SERVER_TIME: Duration = Duration::from_secs(45);

/// The server search running, which a new one or
/// [`cancel_server_search`] stops.
static RUNNING: Mutex<Option<tokio::task::AbortHandle>> = Mutex::new(None);

fn running() -> std::sync::MutexGuard<'static, Option<tokio::task::AbortHandle>> {
    RUNNING.lock().unwrap_or_else(|e| e.into_inner())
}

/// Runs `query` on the servers of the accounts it may concern, all at
/// once, and brings the newest messages they find here (headers only;
/// a body comes when the message is opened). A search started meanwhile,
/// or [`cancel_server_search`], stops this one: it then fails.
pub async fn search_server(query: String, limit: u32) -> Result<ServerSearchResult, EngineError> {
    let engine = engine()?;
    let parsed = Query::parse(&query);
    let limit = (limit as usize).clamp(1, SERVER_HITS);
    if parsed.is_empty() || parsed.local_only() {
        return Ok(ServerSearchResult {
            hits: Vec::new(),
            asked: false,
            failed: 0,
            partial: false,
        });
    }
    let accounts: Vec<_> = store()?
        .accounts()?
        .into_iter()
        .filter(|a| {
            parsed.account().is_none_or(|n| {
                a.name.eq_ignore_ascii_case(n) || a.email.eq_ignore_ascii_case(n)
            })
        })
        .collect();
    let shared = engine.store.clone();
    let task = engine.runtime.spawn(async move {
        let mut each = tokio::task::JoinSet::new();
        for account in accounts {
            let (store, query) = (shared.clone(), parsed.clone());
            each.spawn(async move {
                let password = credentials::load(account.id).ok()?;
                let search = async {
                    let mut remote = Remote::open(&account, &password).await?;
                    let found = remote.search_server(&store, &account, &query, limit).await;
                    remote.close().await;
                    found
                };
                match tokio::time::timeout(SERVER_TIME, search).await {
                    Ok(Ok(found)) => Some((account.id, found)),
                    _ => None,
                }
            });
        }
        let mut found = Vec::new();
        let mut failed = 0;
        while let Some(done) = each.join_next().await {
            match done {
                Ok(Some(f)) => found.push(f),
                _ => failed += 1,
            }
        }
        (found, failed)
    });
    let id = task.id();
    if let Some(earlier) = running().replace(task.abort_handle()) {
        earlier.abort();
    }
    let outcome = task.await;
    {
        let mut slot = running();
        if slot.as_ref().is_some_and(|h| h.id() == id) {
            *slot = None;
        }
    }
    let (found, failed) = outcome.map_err(|e| {
        EngineError::new(
            ErrorKind::Other,
            if e.is_cancelled() {
                "server search cancelled".to_owned()
            } else {
                e.to_string()
            },
        )
    })?;
    let at: Vec<(AccountId, String, u32)> = found
        .iter()
        .flat_map(|(account, f)| {
            f.at.iter()
                .map(move |(mailbox, uid)| (*account, mailbox.clone(), *uid))
        })
        .collect();
    let store = reader()?;
    let mut hits = store.search_hits_at(&at)?;
    hits.truncate(limit);
    Ok(ServerSearchResult {
        hits: hits
            .into_iter()
            .map(|h| {
                Ok(SearchHit {
                    row: in_conversation(&store, inbox_row(&store, h.message))?,
                    snippet: h.snippet,
                    files: h.files,
                })
            })
            .collect::<Result<_, EngineError>>()?,
        asked: found.iter().any(|(_, f)| f.asked),
        failed,
        partial: found.iter().any(|(_, f)| f.partial),
    })
}

/// Stops the server search running, if one is: the person typed
/// something else or closed search.
#[frb(sync)]
pub fn cancel_server_search() {
    if let Some(task) = running().take() {
        task.abort();
    }
}

/// A search kept under a name, for the sidebar.
#[derive(Debug, Clone)]
pub struct SavedSearchInfo {
    pub id: i64,
    pub name: String,
    /// What was typed, operators included.
    pub query: String,
}

/// The saved searches, in the person's order.
pub fn saved_searches() -> Result<Vec<SavedSearchInfo>, EngineError> {
    Ok(reader()?
        .saved_searches()?
        .into_iter()
        .map(|s| SavedSearchInfo {
            id: s.id,
            name: s.name,
            query: s.query,
        })
        .collect())
}

/// Keeps a search under a name; one already under that name gets the new
/// query. Returns its id.
pub fn save_search(name: String, query: String) -> Result<i64, EngineError> {
    Ok(store()?.save_search(&name, &query)?)
}

/// Renames a saved search. False when another one has that name.
pub fn rename_saved_search(id: i64, name: String) -> Result<bool, EngineError> {
    Ok(store()?.rename_saved_search(id, &name)?)
}

/// Forgets a saved search.
pub fn delete_saved_search(id: i64) -> Result<(), EngineError> {
    Ok(store()?.delete_saved_search(id)?)
}
