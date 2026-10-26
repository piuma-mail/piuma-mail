//! Mail sent while the server could not be reached: the store keeps it,
//! built once, and it goes when the connection is back.

use std::sync::Mutex;

use crate::model::{Account, AccountId};
use crate::remote;
use crate::smtp::{Draft, Ready, SendError};
use crate::store::{Store, StoreError};

/// A message waiting in the outbox, as the list shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Waiting {
    pub id: i64,
    pub account: AccountId,
    pub to: Vec<String>,
    pub subject: String,
    pub body: String,
    /// Seconds since the epoch.
    pub queued_at: i64,
    /// Why the server refused it; None while it only waits.
    pub error: Option<String>,
    /// When it is to go, in Unix seconds, for mail sent later.
    pub send_at: Option<i64>,
}

/// A message in the outbox, whole: what was written, to reopen it, and
/// what goes to the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Outgoing {
    pub account: AccountId,
    pub draft: Draft,
    pub ready: Ready,
    /// Its copy in Drafts (mailbox, uid), deleted once it is sent.
    pub saved: Option<(String, u32)>,
    /// When it is to go, in Unix seconds, for mail sent later; as soon as
    /// the server can be reached when None.
    pub send_at: Option<i64>,
}

/// One message the server took.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sent {
    pub id: i64,
    pub saved: Option<(String, u32)>,
    /// False when the copy could not be filed in Sent.
    pub filed: bool,
}

/// Sends an account's waiting mail whose time has come, oldest first.
/// Mail sent later waits for its time. Stops at the first
/// message that can't reach the server, or a refused password, and keeps
/// the rest; a message the server refuses keeps its reason and waits for
/// the person; one it defers (a 4xx) keeps waiting without a reason and
/// goes with a later batch.
pub async fn send(
    store: &Mutex<Store>,
    account: &Account,
    password: &str,
) -> Result<Vec<Sent>, StoreError> {
    let waiting = lock(store).outbox(Some(account.id))?;
    let now = crate::pending::now();
    let mut sent = Vec::new();
    for w in waiting
        .into_iter()
        .filter(|w| w.error.is_none() && w.send_at.is_none_or(|at| at <= now))
    {
        let Some(out) = lock(store).outgoing(w.id)? else {
            continue;
        };
        match remote::send_ready(account, password, &out.ready).await {
            Ok(report) => {
                lock(store).drop_outgoing(w.id)?;
                sent.push(Sent {
                    id: w.id,
                    saved: out.saved,
                    filed: report.filed_in.is_some(),
                });
            }
            Err(e) if e.is_offline() || matches!(e, SendError::Auth) => break,
            // A 4xx: the server may take it later, so the message keeps
            // waiting, without an error, for a later batch.
            Err(SendError::Deferred(_)) => continue,
            // What the server said, as the row shows it.
            Err(SendError::Rejected(reason)) => lock(store).refused_outgoing(w.id, &reason)?,
            Err(e) => lock(store).refused_outgoing(w.id, &e.to_string())?,
        }
    }
    Ok(sent)
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}
