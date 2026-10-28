//! Piuma Mail engine.
//!
//! All the hard work lives here: protocols (IMAP, SMTP, JMAP), offline-first
//! sync, local database and search. The Flutter app only draws.

pub mod autoconfig;
pub mod automation;
pub mod away;
pub mod brief;
pub mod calendar;
pub mod dates;
pub mod features;
pub mod feedback;
pub mod files;
pub mod groups;
pub mod images;
pub mod imap;
pub mod impostor;
pub mod invite;
pub mod jmap;
pub mod label;
pub mod language;
pub mod model;
pub mod network;
pub mod newsletter;
pub mod notify;
pub mod original;
pub mod outbox;
pub mod pair_qr;
pub mod pec;
pub mod pending;
pub mod pictures;
pub mod preview;
pub mod reading;
pub mod remote;
pub mod rich;
pub mod rules;
pub mod search;
pub mod sender_auth;
pub mod sieve;
pub mod signature;
pub mod smtp;
pub mod space;
pub mod space_sync;
pub mod store;
pub mod tls;
mod tokens_g;
pub mod translate;
pub mod vault;

pub use model::{
    Account, AccountId, AccountKind, Flags, Folder, ListFilter, ListInfo, MessageSummary, Section,
    Security, Server,
};
pub use reading::Readable;
pub use search::Query;
pub use store::{
    AccountFolder, Attachment, Body, Conversation, Found, Hit, MailboxState, MessageTemplate,
    Person, PrivacyCounts, SenderAddress, Store, StoreError, TrustedSender,
};

/// Engine version, shown in the app's settings.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    #[test]
    fn version_is_set() {
        assert!(!super::version().is_empty());
    }
}
