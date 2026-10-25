//! Settings › Features: whole features a person can turn off. Each is on
//! unless its setting says "false", so nothing changes until someone turns
//! one off. A feature that is off does no work in the background either;
//! what it made before is kept, so turning it on again picks up from there.

/// Newsletters in their own list. Off, they stay in the inbox.
pub const NEWSLETTERS: &str = "feature.newsletters";

/// The Vault's cards: payments, parcels, trips. Off, no card is read and
/// none is shown, so none makes a notice either.
pub const VAULT: &str = "feature.vault";

/// The Attachments board. Only the app reads it: the files of each email
/// are still listed, for `has:attachment`.
pub const ATTACHMENTS: &str = "feature.attachments";

/// "In short" above long conversations.
pub const IN_SHORT: &str = "feature.in_short";

/// Translate, and the language models it downloads.
pub const TRANSLATE: &str = "feature.translate";

/// "Add to calendar" for dates found in the text.
pub const FOUND_DATES: &str = "feature.found_dates";

/// The value a feature that is off has.
pub const OFF: &str = "false";

/// SQL that is true while the feature of `key` is off.
pub(crate) fn off_sql(key: &str) -> String {
    format!("EXISTS (SELECT 1 FROM setting WHERE key = '{key}' AND value = '{OFF}')")
}

/// Whether the feature of `key` is on, in a connection to the store.
pub(crate) fn on(conn: &rusqlite::Connection, key: &str) -> rusqlite::Result<bool> {
    conn.query_row(&format!("SELECT NOT {}", off_sql(key)), [], |r| r.get(0))
}
