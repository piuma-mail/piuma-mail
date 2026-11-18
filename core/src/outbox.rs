//! Every message sent goes through the outbox: it is written to the
//! database first, then handed to the server from there, so it goes out
//! once, or stays here, visibly unsent.
//!
//! A row moves through these states (the `state` column):
//!
//! - `queued`: waits for its time (`send_at`: Undo send, Send later) or
//!   for the server to be reachable;
//! - `sending`: claimed by one sender (`claim`), in one SQL update that
//!   only one task or process can win; never claimed again, and found
//!   after a crash it becomes `unknown` rather than going twice;
//! - `unknown`: the server may have taken it (the connection broke after
//!   the message was handed over). It is checked where the protocol
//!   allows it (JMAP, servers that file sent mail themselves), and
//!   otherwise waits for the person to decide;
//! - `unfiled`/`filing`: sent; the copy for Sent is still to file, and is
//!   tried again (the row is no longer shown);
//! - `refused`: the server refused it, or the connection could not be
//!   made secure; it keeps the reason and waits for the person.
//!
//! A sent message leaves the outbox.

use std::future::Future;
use std::sync::Mutex;

use crate::model::{Account, AccountId};
use crate::smtp::{Draft, Filing, Ready, SendError};
use crate::store::{Store, StoreError};

/// A message in the outbox, as the list shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Waiting {
    pub id: i64,
    pub account: AccountId,
    pub to: Vec<String>,
    pub subject: String,
    pub body: String,
    /// Seconds since the epoch.
    pub queued_at: i64,
    /// Why the server refused it, or why it may have gone; None while it
    /// only waits.
    pub error: Option<String>,
    /// When it is to go, in Unix seconds, for mail sent later.
    pub send_at: Option<i64>,
    pub state: State,
    /// Sent with Undo: [send_at] is the end of the Undo window, not a time
    /// the person picked.
    pub undo: bool,
}

/// Where a message in the outbox stands, as the list shows it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    /// Waits for its time or for the server.
    Waiting,
    /// On its way now.
    Sending,
    /// The server refused it; [Waiting::error] says why.
    Refused,
    /// The server may have taken it: the person checks Sent and decides.
    Unknown,
}

impl State {
    pub(crate) fn from_column(state: &str) -> Self {
        match state {
            "sending" => State::Sending,
            "refused" => State::Refused,
            "unknown" => State::Unknown,
            _ => State::Waiting,
        }
    }
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
    /// Sent with Undo: [send_at] ends the Undo window.
    pub undo: bool,
}

/// One message the server took.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sent {
    pub id: i64,
    pub message_id: String,
    pub saved: Option<(String, u32)>,
    /// Whether its copy is in Sent, filed here or by the server; when
    /// not, the outbox keeps it and files it later.
    pub filed: Filing,
}

/// What became of one message handed to [send_one].
#[derive(Debug)]
pub enum Outcome {
    Sent(Sent),
    /// It waits: the server can't be reached, didn't take it now (4xx),
    /// refused the password, or its time hasn't come.
    Waiting(SendError),
    /// Refused for good, with the reason; it stays for the person.
    Refused(String),
    /// The connection could not be made secure (a certificate that
    /// doesn't check out); it stays, refused, with the reason.
    Insecure(String),
    /// The server may have taken it; it stays, marked so.
    Unknown(String),
    /// Another sender has it right now (another task or process).
    Busy,
    /// Not in the outbox (any more): sent, taken back, or deleted.
    Gone,
}

/// What hands outbox mail to an account's servers: [crate::remote]'s for
/// real accounts, a script in tests.
pub trait Courier {
    /// Hands the message to the server.
    fn send(&mut self, ready: &Ready) -> impl Future<Output = Result<(), SendError>> + Send;

    /// Files the copy of a sent message in Sent. A [retry] first looks
    /// for a copy filed before, so none is filed twice.
    fn file(&mut self, ready: &Ready, retry: bool) -> impl Future<Output = Filing> + Send;

    /// Whether a message whose send may have gone did go: Some(true) when
    /// the server shows it sent, Some(false) when it shows it was not,
    /// None when it can't tell (most SMTP servers).
    fn was_sent(&mut self, ready: &Ready) -> impl Future<Output = Option<bool>> + Send;
}

/// How often a sender renews its claim while it works on a message: a
/// slow send (a large file, a slow uplink) stays its own however long it
/// takes.
pub const HEARTBEAT: std::time::Duration = std::time::Duration::from_secs(60);

/// How long a claim may go unrenewed before another sender decides its
/// sender died (a crash, a killed app). The row then becomes `unknown`,
/// never `queued`: the message may have gone before the end.
pub const STALE_CLAIM: i64 = 10 * 60;

/// How long the sender of an `unknown` message must have been silent
/// before the engine, told by the server that it never went, queues it
/// again on its own. Shorter, a sender that only stalled (a computer
/// asleep mid-send) could still finish it, and it would go twice.
pub const ABANDONED_CLAIM: i64 = 24 * 60 * 60;

/// Times a write that settles a send is tried (a full disk can refuse
/// it); failing them all, the row stays claimed and is never sent again.
const SETTLE_TRIES: u32 = 3;

/// Sends an account's waiting mail whose time has come, oldest first,
/// as `me` (a name for this sender, the same for its whole life). Also
/// files Sent copies still missing and settles messages that may have
/// gone where the server can tell. Stops at the first message that can't
/// reach the server, or a refused password, and keeps the rest; a message
/// the server refuses keeps its reason and waits for the person; one it
/// defers (a 4xx) keeps waiting and goes with a later batch.
pub async fn send(
    store: &Mutex<Store>,
    account: &Account,
    courier: &mut impl Courier,
    me: &str,
) -> Result<Vec<Sent>, StoreError> {
    let now = crate::pending::now();
    settle_unknown(store, account.id, courier, me, now).await?;
    file_missing(store, account.id, courier, me, now).await?;
    let due = lock(store).due_outgoing(account.id, now)?;
    let mut sent = Vec::new();
    for id in due {
        match send_one(store, id, courier, me).await? {
            Outcome::Sent(s) => sent.push(s),
            Outcome::Waiting(SendError::Deferred(_)) => continue,
            // Trouble with the connection itself: the next would meet it too.
            Outcome::Waiting(_) | Outcome::Insecure(_) | Outcome::Unknown(_) => break,
            Outcome::Refused(_) | Outcome::Busy | Outcome::Gone => continue,
        }
    }
    Ok(sent)
}

/// Sends one message of the outbox now, if its time has come and nobody
/// else is sending it.
pub async fn send_one(
    store: &Mutex<Store>,
    id: i64,
    courier: &mut impl Courier,
    me: &str,
) -> Result<Outcome, StoreError> {
    send_one_beating(store, id, courier, me, HEARTBEAT).await
}

/// [send_one], renewing the claim every `beat` (tests use a short one).
#[doc(hidden)]
pub async fn send_one_beating(
    store: &Mutex<Store>,
    id: i64,
    courier: &mut impl Courier,
    me: &str,
    beat: std::time::Duration,
) -> Result<Outcome, StoreError> {
    let now = crate::pending::now();
    if !lock(store).claim_outgoing(id, me, now)? {
        return Ok(match lock(store).outgoing_state(id)?.as_deref() {
            None => Outcome::Gone,
            Some("sending") | Some("filing") => Outcome::Busy,
            Some("unfiled") => Outcome::Gone,
            Some("refused") | Some("unknown") => Outcome::Gone,
            // Queued, but its time hasn't come.
            Some(_) => Outcome::Waiting(SendError::Deferred("not yet".into())),
        });
    }
    let Some(mut out) = lock(store).outgoing(id)? else {
        return Ok(Outcome::Gone);
    };
    // Mail sent later is dated when it goes.
    if out.send_at.is_some() {
        out.ready.raw = crate::smtp::redate(&out.ready.raw, now);
        lock(store).set_outgoing_raw(id, me, &out.ready.raw).ok();
    }
    // Everything until the row is settled happens under a renewed claim.
    beating(store, id, me, beat, deliver(store, id, courier, me, out)).await
}

/// Hands a claimed message to the server and settles its row.
async fn deliver(
    store: &Mutex<Store>,
    id: i64,
    courier: &mut impl Courier,
    me: &str,
    out: Outgoing,
) -> Result<Outcome, StoreError> {
    let result = courier.send(&out.ready).await;
    let outcome = match result {
        Ok(()) => {
            let filed = courier.file(&out.ready, false).await;
            settle(|| lock(store).sent_outgoing(id, me, filed.done())).await;
            Outcome::Sent(Sent {
                id,
                message_id: out.ready.message_id.clone(),
                saved: out.saved.clone(),
                filed,
            })
        }
        Err(SendError::Uncertain(detail)) => match courier.was_sent(&out.ready).await {
            Some(true) => {
                settle(|| lock(store).sent_outgoing(id, me, true)).await;
                Outcome::Sent(Sent {
                    id,
                    message_id: out.ready.message_id.clone(),
                    saved: out.saved.clone(),
                    filed: Filing::Server,
                })
            }
            Some(false) => {
                settle(|| lock(store).release_outgoing(id, me)).await;
                Outcome::Waiting(SendError::Connect {
                    host: String::new(),
                    detail,
                })
            }
            None => {
                settle(|| lock(store).uncertain_outgoing(id, me, &detail)).await;
                Outcome::Unknown(detail)
            }
        },
        Err(e @ (SendError::Connect { .. } | SendError::Auth | SendError::Deferred(_))) => {
            settle(|| lock(store).release_outgoing(id, me)).await;
            Outcome::Waiting(e)
        }
        Err(SendError::Rejected(reason)) => {
            settle(|| lock(store).refused_outgoing(id, me, &reason)).await;
            Outcome::Refused(reason)
        }
        Err(e @ SendError::Tls { .. }) => {
            let reason = e.to_string();
            settle(|| lock(store).refused_outgoing(id, me, &reason)).await;
            Outcome::Insecure(reason)
        }
        Err(e) => {
            let reason = e.to_string();
            settle(|| lock(store).refused_outgoing(id, me, &reason)).await;
            Outcome::Refused(reason)
        }
    };
    Ok(outcome)
}

/// Files the Sent copies still missing, for messages already sent.
async fn file_missing(
    store: &Mutex<Store>,
    account: AccountId,
    courier: &mut impl Courier,
    me: &str,
    now: i64,
) -> Result<(), StoreError> {
    let unfiled = lock(store).unfiled_outgoing(account)?;
    for id in unfiled {
        if !lock(store).claim_unfiled(id, me, now)? {
            continue;
        }
        let Some(out) = lock(store).outgoing(id)? else {
            continue;
        };
        let filed = courier.file(&out.ready, true).await;
        settle(|| lock(store).sent_outgoing(id, me, filed.done())).await;
    }
    Ok(())
}

/// Settles messages that may have gone: claims left by a sender that
/// died become `unknown`, and those the server can tell about are
/// marked sent or go back in the queue.
async fn settle_unknown(
    store: &Mutex<Store>,
    account: AccountId,
    courier: &mut impl Courier,
    me: &str,
    now: i64,
) -> Result<(), StoreError> {
    lock(store).expire_claims(account, me, now - STALE_CLAIM)?;
    let unknown = lock(store).unknown_outgoing(account)?;
    for id in unknown {
        let Some(out) = lock(store).outgoing(id)? else {
            continue;
        };
        match courier.was_sent(&out.ready).await {
            Some(true) => {
                lock(store).settle_unknown(id, true)?;
            }
            Some(false) => {
                lock(store).settle_unknown(id, false, now - ABANDONED_CLAIM)?;
            }
            None => {}
        }
    }
    Ok(())
}

/// Runs `work`, renewing the claim `me` holds on message `id` every `beat`
/// meanwhile, so no other sender takes it for abandoned.
async fn beating<T>(
    store: &Mutex<Store>,
    id: i64,
    me: &str,
    beat: std::time::Duration,
    work: impl Future<Output = T>,
) -> T {
    tokio::pin!(work);
    let mut tick = tokio::time::interval(beat);
    // The first tick is now; the claim was just made.
    tick.tick().await;
    loop {
        tokio::select! {
            done = &mut work => return done,
            _ = tick.tick() => {
                lock(store).touch_claim(id, me, crate::pending::now()).ok();
            }
        }
    }
}

/// Runs a write that settles a send, a few times: it must not be lost,
/// and a full disk may refuse it for a moment. When it can't be written
/// at all the row stays claimed, so it is never sent again; a later
/// sender finds the claim stale and shows the message as unknown.
async fn settle(mut write: impl FnMut() -> Result<(), StoreError>) {
    for attempt in 0..SETTLE_TRIES {
        match write() {
            Ok(()) => return,
            Err(e) => {
                crate::feedback::log(
                    crate::feedback::Level::Warn,
                    "outbox",
                    &format!("settling a send failed: {e}"),
                );
                if attempt + 1 < SETTLE_TRIES {
                    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                }
            }
        }
    }
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}
