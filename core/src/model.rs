//! Data model shared by the engine and the app.

/// Local identifier of an account.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Default)]
pub struct AccountId(pub i64);

/// How a connection is protected.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Security {
    /// TLS from the first byte (IMAP 993, SMTP 465).
    Tls,
    /// Plain connection upgraded with STARTTLS (IMAP 143, SMTP 587).
    StartTls,
    /// No encryption. Only for local test servers.
    None,
}

impl Security {
    pub(crate) fn tag(self) -> &'static str {
        match self {
            Security::Tls => "tls",
            Security::StartTls => "starttls",
            Security::None => "none",
        }
    }

    pub(crate) fn from_tag(tag: &str) -> Self {
        match tag {
            "starttls" => Security::StartTls,
            "none" => Security::None,
            _ => Security::Tls,
        }
    }
}

/// Where a server lives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Server {
    pub host: String,
    pub port: u16,
    pub security: Security,
}

/// How the engine talks to the mailbox.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AccountKind {
    /// IMAP to read, SMTP to send, with one login.
    Imap {
        imap: Server,
        smtp: Server,
        username: String,
    },
    /// JMAP (RFC 8620/8621): a single session URL. The login is usually
    /// the address; empty means the password is an API token (Fastmail).
    Jmap {
        session_url: String,
        username: String,
    },
}

impl AccountKind {
    fn tag(&self) -> &'static str {
        match self {
            AccountKind::Imap { .. } => "imap",
            AccountKind::Jmap { .. } => "jmap",
        }
    }
}

/// A configured account. Passwords are not stored here: they live in the
/// system keychain.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Account {
    pub id: AccountId,
    /// Display name, e.g. "Work".
    pub name: String,
    pub email: String,
    /// The person's name in From, e.g. "Matteo Neri". May be empty.
    pub sender_name: String,
    /// Dot color, e.g. "#2F8F83".
    pub color: String,
    pub kind: AccountKind,
}

impl Account {
    pub(crate) fn kind_tag(&self) -> &'static str {
        self.kind.tag()
    }
}

/// IMAP system flags the interface shows.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Flags {
    pub seen: bool,
    pub flagged: bool,
    pub answered: bool,
}

impl Flags {
    pub(crate) fn to_bits(self) -> i64 {
        (self.seen as i64) | (self.flagged as i64) << 1 | (self.answered as i64) << 2
    }

    pub(crate) fn from_bits(bits: i64) -> Self {
        Flags {
            seen: bits & 1 != 0,
            flagged: bits & 2 != 0,
            answered: bits & 4 != 0,
        }
    }
}

/// The two halves of the inbox, as the tabs of `Main` and `Phone` show
/// them: mail people wrote, and mail machines send (receipts, alerts,
/// no-reply). `All` is the whole inbox.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Section {
    #[default]
    All,
    People,
    Notifications,
}

/// What a list keeps: one [`Section`] of it, and with `unread` only the
/// conversations with something unread (`FiltersToApprove`, variant 2).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ListFilter {
    pub section: Section,
    pub unread: bool,
}

impl From<Section> for ListFilter {
    fn from(section: Section) -> Self {
        ListFilter {
            section,
            unread: false,
        }
    }
}

/// A list the app shows, across every account: the inboxes, or the
/// folders with the same job.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Folder {
    Inbox,
    Sent,
    Archive,
    Drafts,
    /// Inbox mail sent by newsletters, read apart from the rest.
    Newsletters,
    /// Mail put away until a time, in the account's Snoozed folder.
    Snoozed,
}

impl Folder {
    /// How the database names it.
    pub fn tag(self) -> &'static str {
        match self {
            Folder::Inbox => "inbox",
            Folder::Sent => "sent",
            Folder::Archive => "archive",
            Folder::Drafts => "drafts",
            Folder::Newsletters => "newsletters",
            Folder::Snoozed => "snoozed",
        }
    }

    /// The folder a database tag names; `None` for a folder with no job.
    pub fn from_tag(tag: &str) -> Option<Folder> {
        [
            Folder::Inbox,
            Folder::Sent,
            Folder::Archive,
            Folder::Drafts,
            Folder::Newsletters,
            Folder::Snoozed,
        ]
        .into_iter()
        .find(|f| f.tag() == tag)
    }
}

/// One row of the message list: only what is needed to draw it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MessageSummary {
    pub account: AccountId,
    /// Folder name on the server, e.g. "INBOX".
    pub mailbox: String,
    /// IMAP UID, stable within the folder.
    pub uid: u32,
    pub from_name: String,
    pub from_email: String,
    /// Who it went to, as names (or addresses), comma separated.
    pub to: String,
    pub subject: String,
    /// First words of the body, already cleaned up.
    pub preview: String,
    /// Date received, Unix seconds.
    pub received_at: i64,
    pub flags: Flags,
    pub reply: ReplyInfo,
    /// Read from the headers as the message arrives. Rows read back from
    /// the store leave it empty: [`crate::Store::list_info`] has it.
    pub list: ListInfo,
}

/// What the headers say about mail sent by a machine: a newsletter's list
/// headers, or a certified-mail receipt's.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ListInfo {
    /// A newsletter: bulk mail one can leave, not a discussion list.
    pub newsletter: bool,
    /// Where to leave it: an https (or http) address, else a mailto; empty
    /// when the headers give none.
    pub unsubscribe: String,
    /// The address takes a one-click POST (RFC 8058): no page to open.
    pub one_click: bool,
    /// Bulk or automatic mail, by its headers: Precedence bulk, list or
    /// junk, or an Auto-Submitted other than "no".
    pub bulk: bool,
    /// A receipt from a certified-mail (PEC) provider, kept out of the
    /// inbox and shown in the Vault.
    pub receipt: Option<crate::pec::Receipt>,
}

/// What answering a message needs from its headers.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ReplyInfo {
    /// Message-ID, with angle brackets; empty when the message has none.
    pub message_id: String,
    /// References, space separated, oldest first.
    pub references: String,
    /// Reply-To address when it differs from From.
    pub reply_to: String,
    /// Every address it went to (To, Cc, the delivered-to mailbox),
    /// lowercase and space separated. Rows read back from the store leave
    /// it empty: [`crate::Store::recipients`] has it.
    pub recipients: String,
}

#[cfg(test)]
mod tests {
    use super::Flags;

    #[test]
    fn flags_round_trip() {
        for bits in 0..8 {
            assert_eq!(Flags::from_bits(bits).to_bits(), bits);
        }
    }
}
