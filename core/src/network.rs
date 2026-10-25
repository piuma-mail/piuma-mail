//! The device's network changed (Wi-Fi to mobile data, back online): open
//! connections may be dead without knowing it, so the watchers start over
//! at once instead of waiting for a timeout.

use tokio::sync::Notify;

static CHANGED: Notify = Notify::const_new();

/// Tells every watcher that the network changed.
pub fn changed() {
    CHANGED.notify_waiters();
}

/// Waits for the next [`changed`].
pub async fn wait() {
    CHANGED.notified().await;
}
