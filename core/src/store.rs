//! Local database (SQLite): the cache the app opens from instantly.

use std::collections::{HashMap, HashSet};
use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};

use crate::automation::{machine_address, no_reply_address};
use crate::groups::{AddressGroup, GroupAddress, Within};
use crate::label::Label;
use crate::model::{
    Account, AccountId, AccountKind, Flags, Folder, ListFilter, ListInfo, MessageSummary,
    ReplyInfo, Section, Security, Server,
};
use crate::outbox::{Outgoing, Waiting};
use crate::pec;
use crate::pending::{Change, Pending, MAX_ATTEMPTS};
use crate::rules::{Action as RuleAction, Field as RuleField, Op as RuleOp, Rule};
use crate::search::Query;
use crate::signature::{Accent, Logo, Signature, Template};
use crate::smtp::{Draft, OutgoingFile, Ready};

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("database: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("unknown account kind in database: {0}")]
    UnknownKind(String),
}

pub type Result<T> = std::result::Result<T, StoreError>;

/// Migrations in order. Never edit one: add a new one instead.
/// SQL for a snoozed message `m` (its `snooze` row `s`) waiting for a
/// reply that came: a message in its thread from someone else, newer than
/// the snooze, outside Snoozed, Sent and Drafts.
const REPLIED: &str = "(s.unless_reply IS NOT NULL AND EXISTS (
    SELECT 1 FROM message r
    WHERE r.account = m.account AND r.thread = m.thread AND r.received_at > s.unless_reply
      AND r.folder NOT IN ('snoozed', 'sent', 'drafts')
      AND lower(r.from_email) NOT IN (SELECT lower(email) FROM account WHERE id = m.account)))";

/// Keeps a message's labels, for a message that is here.
const LABELS_KEEP: &str = "INSERT INTO message_labels (account, mailbox, uid, labels)
     SELECT ?1, ?2, ?3, ?4 FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3
     ON CONFLICT (account, mailbox, uid) DO UPDATE SET labels = excluded.labels";

/// A message without labels has no row.
const LABELS_DROP: &str =
    "DELETE FROM message_labels WHERE account = ?1 AND mailbox = ?2 AND uid = ?3";

/// The setting with the recent searches, one per line.
const RECENT_SEARCHES: &str = "search.recent";

/// How many recent searches are kept.
pub const RECENT_SEARCHES_KEPT: usize = 5;

/// SQL for a message `m` written by a person: not a newsletter, not sent
/// or a draft, not from the person, and either from someone they wrote to
/// or in a conversation they replied to (unless it is list mail or from a
/// no-reply or bounce address), or neither list, bulk nor automatic mail
/// nor from a machine-looking address ([`machine_address`]), with no Vault
/// card unless a person forwarded it. A sender the person moved to People or Notifications
/// stays where they put it.
const PEOPLE: &str = "(m.newsletter = 0 AND m.from_email != ''
    AND m.folder NOT IN ('sent', 'drafts', 'newsletters')
    AND lower(m.from_email) NOT IN (SELECT lower(email) FROM account)
    AND COALESCE((SELECT s.people FROM sender_side s WHERE s.email = lower(m.from_email)),
    NOT automatic_content(m.from_name, m.subject, EXISTS (SELECT 1 FROM attachment a
        WHERE a.account = m.account AND a.mailbox = m.mailbox AND a.uid = m.uid
          AND lower(a.mime) = 'message/rfc822')) AND (EXISTS (SELECT 1 FROM written_to w WHERE w.email = lower(m.from_email))
    OR (m.unsubscribe = '' AND m.thread <> '' AND NOT no_reply_address(m.from_email)
        AND EXISTS (SELECT 1 FROM message s
            WHERE s.account = m.account AND s.thread = m.thread AND s.folder = 'sent'))
    OR (m.unsubscribe = '' AND m.bulk = 0 AND NOT machine_address(m.from_email)
        AND (forwarded(m.subject) OR NOT EXISTS (SELECT 1 FROM vault_card v
            WHERE v.account = m.account AND v.mailbox = m.mailbox AND v.uid = m.uid))))))";

/// The SQL that keeps what a [`ListFilter`] keeps of a list of messages `m`.
fn section_sql(filter: impl Into<ListFilter>) -> String {
    let filter = filter.into();
    let section = match filter.section {
        Section::All => String::new(),
        Section::People => format!(" AND {PEOPLE}"),
        Section::Notifications => format!(" AND NOT {PEOPLE}"),
    };
    if filter.unread {
        section + UNREAD_IN_THREAD
    } else {
        section
    }
}

/// Keeps conversations with an unread message in the folder of `m`.
const UNREAD_IN_THREAD: &str = " AND EXISTS (SELECT 1 FROM message u
    WHERE u.account = m.account AND u.thread = m.thread AND u.folder = m.folder
      AND u.hidden = 0 AND (u.flags & 1) = 0)";

/// Keeps who the person wrote to, from the Sent mail `?1`/`?2`/`?3` (an
/// account, a mailbox and a uid; a NULL keeps them all): the senders the
/// inbox always counts as people.
const NOTE_WRITTEN_TO: &str = "WITH RECURSIVE split(account, rest, email) AS (
        SELECT account, recipients || ' ', '' FROM message
        WHERE folder = 'sent' AND recipients <> ''
          AND (?1 IS NULL OR account = ?1) AND (?2 IS NULL OR mailbox = ?2)
          AND (?3 IS NULL OR uid = ?3)
        UNION ALL
        SELECT account, substr(rest, instr(rest, ' ') + 1), substr(rest, 1, instr(rest, ' ') - 1)
        FROM split WHERE rest <> '')
    INSERT OR IGNORE INTO written_to (account, email)
    SELECT account, lower(email) FROM split WHERE email <> ''";

const MIGRATIONS: &[&str] = &[
    r#"
    CREATE TABLE account (
        id          INTEGER PRIMARY KEY,
        name        TEXT NOT NULL,
        email       TEXT NOT NULL UNIQUE,
        color       TEXT NOT NULL,
        kind        TEXT NOT NULL,
        imap_host   TEXT,
        imap_port   INTEGER,
        smtp_host   TEXT,
        smtp_port   INTEGER,
        jmap_url    TEXT
    );
    CREATE TABLE message (
        account     INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        mailbox     TEXT NOT NULL,
        uid         INTEGER NOT NULL,
        from_name   TEXT NOT NULL,
        from_email  TEXT NOT NULL,
        subject     TEXT NOT NULL,
        preview     TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        flags       INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (account, mailbox, uid)
    );
    CREATE INDEX message_by_date ON message(mailbox, received_at DESC);
"#,
    r#"
    CREATE TABLE mailbox (
        account        INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        name           TEXT NOT NULL,
        uid_validity   INTEGER NOT NULL,
        highest_modseq INTEGER,
        PRIMARY KEY (account, name)
    );
    CREATE TABLE message_body (
        account     INTEGER NOT NULL,
        mailbox     TEXT NOT NULL,
        uid         INTEGER NOT NULL,
        text        TEXT NOT NULL,
        PRIMARY KEY (account, mailbox, uid),
        FOREIGN KEY (account, mailbox, uid) REFERENCES message(account, mailbox, uid) ON DELETE CASCADE
    );
"#,
    r#"
    -- Covers the whole ORDER BY of the unified inbox, so paging needs no sort.
    DROP INDEX message_by_date;
    CREATE INDEX message_by_date ON message(mailbox, received_at DESC, account, uid DESC);
"#,
    r#"
    ALTER TABLE account ADD COLUMN imap_security TEXT;
    ALTER TABLE account ADD COLUMN smtp_security TEXT;
    ALTER TABLE account ADD COLUMN username TEXT;
"#,
    r#"
    ALTER TABLE account ADD COLUMN sender_name TEXT NOT NULL DEFAULT '';
"#,
    r#"
    -- Headers for replies, and rows hidden while an action can be undone.
    ALTER TABLE message ADD COLUMN message_id TEXT NOT NULL DEFAULT '';
    ALTER TABLE message ADD COLUMN refs TEXT NOT NULL DEFAULT '';
    ALTER TABLE message ADD COLUMN reply_to TEXT NOT NULL DEFAULT '';
    ALTER TABLE message ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
    DROP INDEX message_by_date;
    CREATE INDEX message_by_date ON message(mailbox, hidden, received_at DESC, account, uid DESC);
"#,
    r#"
    -- Full-text search. One row per message, keyed by the message's rowid
    -- and kept in step by triggers. VACUUM can renumber rowids: run
    -- Store::rebuild_search_index after one.
    CREATE VIRTUAL TABLE message_fts USING fts5(
        subject, sender, preview, body,
        tokenize = 'unicode61 remove_diacritics 2',
        prefix = '2 3'
    );
    CREATE TRIGGER message_fts_insert AFTER INSERT ON message BEGIN
        INSERT INTO message_fts (rowid, subject, sender, preview, body)
        VALUES (new.rowid, new.subject, new.from_name || ' ' || new.from_email, new.preview,
                COALESCE((SELECT text FROM message_body
                          WHERE account = new.account AND mailbox = new.mailbox AND uid = new.uid), ''));
    END;
    CREATE TRIGGER message_fts_delete AFTER DELETE ON message BEGIN
        DELETE FROM message_fts WHERE rowid = old.rowid;
    END;
    CREATE TRIGGER message_fts_update AFTER UPDATE OF subject, from_name, from_email, preview ON message BEGIN
        UPDATE message_fts
        SET subject = new.subject, sender = new.from_name || ' ' || new.from_email, preview = new.preview
        WHERE rowid = new.rowid;
    END;
    CREATE TRIGGER message_fts_body AFTER INSERT ON message_body BEGIN
        UPDATE message_fts SET body = new.text
        WHERE rowid = (SELECT rowid FROM message
                       WHERE account = new.account AND mailbox = new.mailbox AND uid = new.uid);
    END;
    INSERT INTO message_fts (rowid, subject, sender, preview, body)
    SELECT m.rowid, m.subject, m.from_name || ' ' || m.from_email, m.preview, COALESCE(b.text, '')
    FROM message m LEFT JOIN message_body b USING (account, mailbox, uid);
"#,
    r#"
    -- Reading HTML safely. format: 0 = cached before HTML was kept (fetch
    -- again), 1 = plain text only, 2 = has HTML.
    ALTER TABLE message_body ADD COLUMN html TEXT;
    ALTER TABLE message_body ADD COLUMN format INTEGER NOT NULL DEFAULT 0;
    -- Senders whose remote images always load.
    CREATE TABLE trusted_sender (
        email    TEXT PRIMARY KEY COLLATE NOCASE,
        added_at INTEGER NOT NULL
    );
    CREATE TABLE setting (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    -- What was stopped in each message, the first time it was read. Kept
    -- when the message goes, so the 30-day totals stay true.
    CREATE TABLE privacy_log (
        account  INTEGER NOT NULL,
        mailbox  TEXT NOT NULL,
        uid      INTEGER NOT NULL,
        read_at  INTEGER NOT NULL,
        trackers INTEGER NOT NULL,
        links    INTEGER NOT NULL,
        PRIMARY KEY (account, mailbox, uid)
    );
"#,
    r#"
    -- The parts of what was stopped, for the 30-day totals.
    ALTER TABLE privacy_log ADD COLUMN pixels INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE privacy_log ADD COLUMN suspicious INTEGER NOT NULL DEFAULT 0;
"#,
    r#"
    -- Files attached to a message: what they are, not their content, which
    -- is fetched from the server when the person opens one.
    CREATE TABLE attachment (
        account  INTEGER NOT NULL,
        mailbox  TEXT NOT NULL,
        uid      INTEGER NOT NULL,
        part     INTEGER NOT NULL,
        name     TEXT NOT NULL,
        mime     TEXT NOT NULL,
        size     INTEGER NOT NULL,
        PRIMARY KEY (account, mailbox, uid, part),
        FOREIGN KEY (account, mailbox, uid) REFERENCES message(account, mailbox, uid) ON DELETE CASCADE
    );
    -- Bodies cached before attachments were listed: fetch them again.
    UPDATE message_body SET format = 0;
"#,
    r#"
    -- Which server folder of each account has which job, and the job of
    -- each message's folder, so a unified list reads one index.
    CREATE TABLE folder_role (
        account INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        role    TEXT NOT NULL,
        mailbox TEXT NOT NULL,
        PRIMARY KEY (account, role)
    );
    ALTER TABLE message ADD COLUMN folder TEXT NOT NULL DEFAULT '';
    ALTER TABLE message ADD COLUMN to_list TEXT NOT NULL DEFAULT '';
    UPDATE message SET folder = 'inbox' WHERE mailbox = 'INBOX';
    CREATE INDEX message_by_folder ON message(folder, received_at DESC, account, uid DESC);
"#,
    r#"
    -- Conversations: every message carries the Message-ID of the first
    -- message of its thread (the first References entry), so a thread is
    -- one index lookup, across folders.
    ALTER TABLE message ADD COLUMN thread TEXT NOT NULL DEFAULT '';
    UPDATE message SET thread = CASE
        WHEN refs <> '' THEN substr(refs, 1, instr(refs || ' ', ' ') - 1)
        WHEN message_id <> '' THEN message_id
        ELSE account || '/' || mailbox || '/' || uid END;
    CREATE INDEX message_by_id ON message(account, message_id);
    CREATE INDEX message_by_thread ON message(account, thread, folder, received_at DESC);
    -- A reply that only had In-Reply-To joins its parent's thread.
    UPDATE message SET thread = (
        SELECT p.thread FROM message p
        WHERE p.account = message.account AND p.message_id = message.thread
          AND p.thread <> message.thread LIMIT 1)
    WHERE EXISTS (
        SELECT 1 FROM message p
        WHERE p.account = message.account AND p.message_id = message.thread
          AND p.thread <> message.thread);
"#,
    r#"
    -- Signatures, each belonging to one account. At most one per account is
    -- for new emails and one for replies and forwards.
    CREATE TABLE signature (
        id          INTEGER PRIMARY KEY,
        account     INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        label       TEXT NOT NULL,
        template    TEXT NOT NULL,
        name        TEXT NOT NULL DEFAULT '',
        role        TEXT NOT NULL DEFAULT '',
        company     TEXT NOT NULL DEFAULT '',
        phone       TEXT NOT NULL DEFAULT '',
        website     TEXT NOT NULL DEFAULT '',
        accent      TEXT NOT NULL DEFAULT 'blue',
        logo_mime   TEXT,
        logo        BLOB,
        for_new     INTEGER NOT NULL DEFAULT 0,
        for_replies INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX signature_by_account ON signature(account);
"#,
    r#"
    -- JMAP names messages with strings, not numbers: each one gets a local
    -- number per folder, never reused, so the rest of the cache is the same
    -- for every kind of account.
    CREATE TABLE jmap_email (
        account  INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        mailbox  TEXT NOT NULL,
        uid      INTEGER NOT NULL,
        email_id TEXT NOT NULL,
        PRIMARY KEY (account, mailbox, uid),
        UNIQUE (account, mailbox, email_id)
    );
    CREATE TABLE jmap_mailbox (
        account  INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        mailbox  TEXT NOT NULL,
        next_uid INTEGER NOT NULL,
        PRIMARY KEY (account, mailbox)
    );
"#,
    r#"
    -- Changes made while the server could not be reached, sent when the
    -- connection is back.
    CREATE TABLE pending_change (
        id       INTEGER PRIMARY KEY,
        account  INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        mailbox  TEXT NOT NULL,
        uid      INTEGER NOT NULL,
        change   TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX pending_by_account ON pending_change(account, id);
"#,
    r#"
    -- Each account's own folders, in the server's tree order, and where a
    -- move while offline goes.
    CREATE TABLE account_folder (
        account    INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        mailbox    TEXT NOT NULL,
        name       TEXT NOT NULL,
        depth      INTEGER NOT NULL,
        position   INTEGER NOT NULL,
        selectable INTEGER NOT NULL,
        unread     INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (account, mailbox)
    );
    ALTER TABLE pending_change ADD COLUMN target TEXT NOT NULL DEFAULT '';
"#,
    r#"
    -- Mail sent while offline: what was written, to reopen it, and the
    -- message as built, to send it as it was.
    CREATE TABLE outbox (
        id          INTEGER PRIMARY KEY,
        account     INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        from_name   TEXT NOT NULL,
        from_email  TEXT NOT NULL,
        to_list     TEXT NOT NULL,
        cc_list     TEXT NOT NULL,
        bcc_list    TEXT NOT NULL,
        subject     TEXT NOT NULL,
        body        TEXT NOT NULL,
        in_reply_to TEXT,
        refs        TEXT NOT NULL,
        signature   INTEGER,
        message_id  TEXT NOT NULL,
        mail_from   TEXT NOT NULL,
        recipients  TEXT NOT NULL,
        raw         BLOB NOT NULL,
        saved_mailbox TEXT,
        saved_uid   INTEGER,
        queued_at   INTEGER NOT NULL,
        error       TEXT
    );
    CREATE TABLE outbox_file (
        outbox   INTEGER NOT NULL REFERENCES outbox(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        name     TEXT NOT NULL,
        mime     TEXT NOT NULL,
        data     BLOB NOT NULL,
        PRIMARY KEY (outbox, position)
    );
"#,
    r#"
    -- Newsletters: what the list headers said, and whether they were read
    -- (mail cached before this had them left out). `words` is known once
    -- the body is, for the reading time.
    ALTER TABLE message ADD COLUMN newsletter INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE message ADD COLUMN unsubscribe TEXT NOT NULL DEFAULT '';
    ALTER TABLE message ADD COLUMN one_click INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE message ADD COLUMN list_checked INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE message ADD COLUMN words INTEGER NOT NULL DEFAULT 0;
    -- Senders whose inbox mail the person moved: 'inbox' or 'newsletters'.
    CREATE TABLE sender_zone (
        email TEXT PRIMARY KEY,
        zone  TEXT NOT NULL
    );
"#,
    r#"
    -- The Vault: the card a receipt, bill, parcel or booking makes, as
    -- JSON. `vault_checked`: the message was looked at (mail cached
    -- before this is looked at a round at a time).
    ALTER TABLE message ADD COLUMN vault_checked INTEGER NOT NULL DEFAULT 0;
    CREATE TABLE vault_card (
        account INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        mailbox TEXT NOT NULL,
        uid     INTEGER NOT NULL,
        key     TEXT NOT NULL,
        data    TEXT NOT NULL,
        PRIMARY KEY (account, mailbox, uid)
    );
    CREATE TRIGGER vault_card_gone AFTER DELETE ON message BEGIN
        DELETE FROM vault_card
        WHERE account = old.account AND mailbox = old.mailbox AND uid = old.uid;
    END;
    -- Bills the person marked paid, by card key, which outlives a move.
    CREATE TABLE vault_paid (
        key     TEXT PRIMARY KEY,
        paid_at INTEGER NOT NULL
    );
"#,
    r#"
    -- Files listed from the server's outline of a message (BODYSTRUCTURE),
    -- before its body is here: `section` is the part's number there and
    -- `encoding` how it travels, so it can be fetched alone.
    -- `files_checked`: the message's files are listed.
    ALTER TABLE attachment ADD COLUMN section TEXT;
    ALTER TABLE attachment ADD COLUMN encoding TEXT;
    ALTER TABLE message ADD COLUMN files_checked INTEGER NOT NULL DEFAULT 0;
    UPDATE message SET files_checked = 1 WHERE EXISTS (
        SELECT 1 FROM message_body b WHERE b.account = message.account
            AND b.mailbox = message.mailbox AND b.uid = message.uid AND b.format > 0);
    -- Small previews of attached pictures, by file name, which outlives
    -- the part numbers changing once the body is here.
    CREATE TABLE attachment_thumb (
        account INTEGER NOT NULL,
        mailbox TEXT NOT NULL,
        uid     INTEGER NOT NULL,
        name    TEXT NOT NULL,
        data    BLOB NOT NULL,
        PRIMARY KEY (account, mailbox, uid, name),
        FOREIGN KEY (account, mailbox, uid) REFERENCES message(account, mailbox, uid) ON DELETE CASCADE
    );
"#,
    r#"
    -- Snoozed mail: when it comes back, as the server's keyword says
    -- (`snooze_until`), and as this device asked, by Message-ID, for
    -- servers that keep no keywords and for JMAP.
    ALTER TABLE message ADD COLUMN snooze_until INTEGER;
    CREATE TABLE snooze (
        account    INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        message_id TEXT NOT NULL,
        until      INTEGER NOT NULL,
        PRIMARY KEY (account, message_id)
    );
"#,
    r#"
    -- Mail sent later: when it goes.
    ALTER TABLE outbox ADD COLUMN send_at INTEGER;
"#,
    r#"
    -- Senders whose new mail makes no notification.
    CREATE TABLE muted_sender (
        email TEXT PRIMARY KEY COLLATE NOCASE
    );
"#,
    r#"
    -- Rules that sort new inbox mail on this device.
    CREATE TABLE rule (
        id INTEGER PRIMARY KEY,
        account INTEGER REFERENCES account(id) ON DELETE CASCADE,
        field TEXT NOT NULL,
        op TEXT NOT NULL,
        value TEXT NOT NULL,
        action TEXT NOT NULL,
        target TEXT NOT NULL DEFAULT '',
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_run INTEGER,
        matched INTEGER NOT NULL DEFAULT 0
    );
"#,
    r#"
    -- Invites: the calendar part a message carries, and how they were
    -- answered here. Bodies of the last 60 days are fetched again, so the
    -- invites among them show.
    ALTER TABLE message_body ADD COLUMN calendar TEXT;
    UPDATE message_body SET format = 0 WHERE EXISTS (
        SELECT 1 FROM message m WHERE m.account = message_body.account
            AND m.mailbox = message_body.mailbox AND m.uid = message_body.uid
            AND m.received_at > CAST(strftime('%s', 'now') AS INTEGER) - 60 * 86400);
    CREATE TABLE invite_answer (
        account  INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        event    TEXT NOT NULL,
        answer   TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        at       INTEGER NOT NULL,
        PRIMARY KEY (account, event)
    );
"#,
    r#"
    -- Calendars connected in Settings: where they are, which calendars
    -- they hold, and their events for the weeks ahead, to tell when you
    -- are busy. Passwords are in the system keychain.
    CREATE TABLE calendar_source (
        id       INTEGER PRIMARY KEY,
        kind     TEXT NOT NULL,
        name     TEXT NOT NULL,
        url      TEXT NOT NULL,
        username TEXT NOT NULL DEFAULT '',
        account  INTEGER REFERENCES account(id) ON DELETE SET NULL,
        synced   INTEGER
    );
    CREATE TABLE calendar (
        id           INTEGER PRIMARY KEY,
        source       INTEGER NOT NULL REFERENCES calendar_source(id) ON DELETE CASCADE,
        url          TEXT NOT NULL,
        name         TEXT NOT NULL,
        color        TEXT,
        read_only    INTEGER NOT NULL DEFAULT 0,
        availability INTEGER NOT NULL DEFAULT 1,
        UNIQUE (source, url)
    );
    CREATE TABLE calendar_event (
        calendar INTEGER NOT NULL REFERENCES calendar(id) ON DELETE CASCADE,
        uid      TEXT NOT NULL,
        start    INTEGER NOT NULL,
        end      INTEGER NOT NULL,
        all_day  INTEGER NOT NULL,
        floating INTEGER NOT NULL,
        summary  TEXT NOT NULL
    );
    CREATE INDEX calendar_event_start ON calendar_event (start);
"#,
    r#"
    -- Days found in a message's words and put in a calendar, by event uid.
    CREATE TABLE found_date (
        uid      TEXT PRIMARY KEY,
        calendar TEXT NOT NULL,
        added    INTEGER NOT NULL
    );
"#,
    r#"
    -- Vault notices already given: one of each kind per card.
    CREATE TABLE vault_notice (
        key  TEXT NOT NULL,
        tag  TEXT NOT NULL,
        at   INTEGER NOT NULL,
        PRIMARY KEY (key, tag)
    );
"#,
    r#"
    -- "If nobody replies": a snoozed message also comes back as soon as
    -- someone else writes in its thread after this time.
    ALTER TABLE snooze ADD COLUMN unless_reply INTEGER;
"#,
    r#"
    -- Senders whose new mail goes straight to Trash.
    CREATE TABLE blocked_sender (
        email TEXT PRIMARY KEY COLLATE NOCASE
    );
"#,
    r#"
    -- Pictures inside messages (`cid:`), kept with their body. Bodies
    -- cached before, that show some, are fetched again.
    CREATE TABLE inline_image (
        account INTEGER NOT NULL,
        mailbox TEXT NOT NULL,
        uid     INTEGER NOT NULL,
        cid     TEXT NOT NULL,
        mime    TEXT NOT NULL,
        data    BLOB NOT NULL,
        PRIMARY KEY (account, mailbox, uid, cid),
        FOREIGN KEY (account, mailbox, uid) REFERENCES message(account, mailbox, uid) ON DELETE CASCADE
    );
    UPDATE message_body SET format = 0 WHERE html LIKE '%cid:%';
"#,
    r#"
    -- Certified-mail (PEC) receipts, kept out of the inbox and gathered on
    -- the message they are about. Receipts cached before are fetched again.
    CREATE TABLE pec_receipt (
        account    INTEGER NOT NULL,
        mailbox    TEXT NOT NULL,
        uid        INTEGER NOT NULL,
        kind       TEXT NOT NULL,
        refers     TEXT NOT NULL,
        recipients TEXT NOT NULL,
        reason     TEXT NOT NULL,
        PRIMARY KEY (account, mailbox, uid),
        FOREIGN KEY (account, mailbox, uid) REFERENCES message(account, mailbox, uid) ON DELETE CASCADE
    );
    CREATE INDEX pec_receipt_refers ON pec_receipt (account, refers);
    DELETE FROM message
     WHERE mailbox = 'INBOX' AND lower(from_email) LIKE 'posta-certificata@%'
       AND (upper(subject) LIKE 'ACCETTAZIONE:%' OR upper(subject) LIKE 'CONSEGNA:%'
            OR upper(subject) LIKE 'PRESA IN CARICO:%' OR upper(subject) LIKE 'AVVISO DI %');
"#,
    r#"
    -- Drafts saved while the server could not be reached: the message as
    -- built, and the copy on the server it replaces, uploaded once the
    -- connection is back.
    CREATE TABLE draft_waiting (
        id              INTEGER PRIMARY KEY,
        account         INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        raw             BLOB NOT NULL,
        message_id      TEXT NOT NULL,
        earlier_account INTEGER,
        earlier_mailbox TEXT,
        earlier_uid     INTEGER,
        signature       TEXT,
        saved_at        INTEGER NOT NULL
    );
"#,
    r#"
    -- Templates the "/" of compose puts in a message: on this device, for
    -- every account. `used_at` lists the ones used last first.
    CREATE TABLE message_template (
        id      INTEGER PRIMARY KEY,
        name    TEXT NOT NULL,
        subject TEXT NOT NULL DEFAULT '',
        body    TEXT NOT NULL DEFAULT '',
        used_at INTEGER NOT NULL DEFAULT 0
    );
"#,
    r#"
    -- The account's server vouched for the domain in From (DKIM, SPF,
    -- DMARC). Bodies kept before stay unmarked.
    ALTER TABLE message_body ADD COLUMN verified INTEGER NOT NULL DEFAULT 0;
"#,
    r#"
    -- How many emails a folder holds on the server, for Rules & folders.
    ALTER TABLE account_folder ADD COLUMN total INTEGER NOT NULL DEFAULT 0;
"#,
    r#"
    -- Every address a message went to, lowercase and space separated, so
    -- replies go from the one written to. Inbox mail kept before has its
    -- headers read again, with the list headers.
    ALTER TABLE message ADD COLUMN recipients TEXT NOT NULL DEFAULT '';
    UPDATE message SET list_checked = 0 WHERE mailbox = 'INBOX';
    -- Other addresses an account sends from.
    CREATE TABLE account_alias (
        account INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        email   TEXT NOT NULL COLLATE NOCASE,
        PRIMARY KEY (account, email)
    );
    -- Groups of addresses from different accounts and domains. An address
    -- is in one group at most.
    CREATE TABLE address_group (
        id             INTEGER PRIMARY KEY,
        name           TEXT NOT NULL,
        color          TEXT NOT NULL,
        signature      INTEGER REFERENCES signature(id) ON DELETE SET NULL,
        send_from      TEXT NOT NULL DEFAULT '',
        separate_inbox INTEGER NOT NULL DEFAULT 1,
        notify         INTEGER NOT NULL DEFAULT 1,
        position       INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE group_address (
        grp      INTEGER NOT NULL REFERENCES address_group(id) ON DELETE CASCADE,
        account  INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        email    TEXT NOT NULL COLLATE NOCASE UNIQUE,
        position INTEGER NOT NULL DEFAULT 0
    );
"#,
    r#"
    -- Previews made before style sheets, invisible padding and the
    -- parser's "..." were left out: Store::clean_previews redoes them.
"#,
    r#"
    -- Who the person moved to which folder, for the rule Rules & folders
    -- suggests. Kept for 60 days.
    CREATE TABLE IF NOT EXISTS move_log (
        account INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        sender  TEXT NOT NULL COLLATE NOCASE,
        name    TEXT NOT NULL DEFAULT '',
        target  TEXT NOT NULL,
        at      INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS move_log_at ON move_log (at);
"#,
    r#"
    -- Sent mail the person stopped waiting on: Waiting leaves it out.
    CREATE TABLE IF NOT EXISTS waiting_done (
        account    INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        message_id TEXT NOT NULL,
        PRIMARY KEY (account, message_id)
    );
"#,
    r#"
    -- The order the person dragged an account's folders into, among their
    -- siblings; folders without one keep the server's order, after them.
    CREATE TABLE IF NOT EXISTS folder_order (
        account INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        mailbox TEXT NOT NULL,
        rank    INTEGER NOT NULL,
        PRIMARY KEY (account, mailbox)
    );
"#,
    r#"
    -- How often an .ics feed asks to be read again, as it says itself.
    -- Each device reads its feeds, so this stays out of the sync space.
    CREATE TABLE IF NOT EXISTS calendar_refresh (
        source INTEGER PRIMARY KEY REFERENCES calendar_source(id) ON DELETE CASCADE,
        every  INTEGER NOT NULL
    );
"#,
    r#"
    -- Labels (`LabelsToApprove`): colored words shared across accounts,
    -- kept on the server as keywords.
    CREATE TABLE IF NOT EXISTS label (
        id      INTEGER PRIMARY KEY,
        name    TEXT NOT NULL UNIQUE COLLATE NOCASE,
        color   TEXT NOT NULL,
        keyword TEXT NOT NULL UNIQUE,
        rank    INTEGER NOT NULL DEFAULT 0
    );
    -- A message's label keywords, lower case, space separated; gone with
    -- the message.
    CREATE TABLE IF NOT EXISTS message_labels (
        account INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        mailbox TEXT NOT NULL,
        uid     INTEGER NOT NULL,
        labels  TEXT NOT NULL,
        PRIMARY KEY (account, mailbox, uid)
    );
    CREATE TRIGGER IF NOT EXISTS message_labels_gone AFTER DELETE ON message
    BEGIN
        DELETE FROM message_labels
         WHERE account = old.account AND mailbox = old.mailbox AND uid = old.uid;
    END;
"#,
    r#"
    -- The Vault reads its mail again: refunds are no bills any more, and
    -- reminders about one bill share a card.
    UPDATE message SET vault_checked = 0;
"#,
    r#"
    -- Sender pictures (`PicturesToApprove`): a company's verified logo or
    -- website icon, per mail domain, as a square PNG; kind 'none' when
    -- there was nothing, so it isn't asked again too soon.
    CREATE TABLE IF NOT EXISTS sender_picture (
        domain     TEXT PRIMARY KEY,
        kind       TEXT NOT NULL,
        png        BLOB NOT NULL,
        fetched_at INTEGER NOT NULL
    );
"#,
    r#"
    -- Previews made before they followed the reader: they ran blocks
    -- together or kept raw HTML. Mail listed from now on is right at once.
    CREATE TABLE IF NOT EXISTS preview_stale (
        account INTEGER NOT NULL,
        mailbox TEXT NOT NULL,
        uid     INTEGER NOT NULL,
        PRIMARY KEY (account, mailbox, uid)
    );
    INSERT OR IGNORE INTO preview_stale (account, mailbox, uid)
        SELECT account, mailbox, uid FROM message;
    CREATE TRIGGER IF NOT EXISTS preview_stale_gone AFTER DELETE ON message
    BEGIN
        DELETE FROM preview_stale
         WHERE account = old.account AND mailbox = old.mailbox AND uid = old.uid;
    END;
"#,
    r#"
    -- Mail a rule moved to the Vault, by its Message-ID, which it keeps
    -- in the folder it lands in: it always makes a card.
    CREATE TABLE IF NOT EXISTS vault_pin (
        message_id TEXT PRIMARY KEY,
        pinned_at  INTEGER NOT NULL
    );
"#,
    r#"
    -- Previews made from a text part that carried the pictures'
    -- descriptions ("Focusrite Logo"): made again from the HTML.
    INSERT OR IGNORE INTO preview_stale (account, mailbox, uid)
        SELECT account, mailbox, uid FROM message;
"#,
    r#"
    -- The Vault reads its mail again: a payment that went through
    -- ("Payment Successful", "payment to …") is no bill to pay.
    UPDATE message SET vault_checked = 0;
"#,
    r#"
    -- Previews that kept written-out links or lines of one sign.
    INSERT OR IGNORE INTO preview_stale (account, mailbox, uid)
        SELECT account, mailbox, uid FROM message
         WHERE preview LIKE '%http%' OR preview LIKE '%www.%'
            OR preview LIKE '%===%' OR preview LIKE '%---%' OR preview LIKE '%***%';
"#,
    r#"
    -- "Remind me if nobody replies": sent mail, by Message-ID, that comes
    -- back to the top of the inbox at `at` while it waits for a reply.
    -- `noticed`: its notification was given. Kept on this device.
    CREATE TABLE IF NOT EXISTS reply_reminder (
        account    INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        message_id TEXT NOT NULL,
        at         INTEGER NOT NULL,
        noticed    INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (account, message_id)
    );
"#,
    r#"
    -- The away message (`RemindAwayPrintToApprove`): what the person set
    -- per account, as days from 1970-01-01 in the zone `zone` minutes east
    -- of UTC. The reply itself lives on the mail server; `placed` says it
    -- is there now, `device_dates` that the server can't tell dates and
    -- this device starts and ends it. Kept on this device.
    CREATE TABLE IF NOT EXISTS away_message (
        account      INTEGER PRIMARY KEY REFERENCES account(id) ON DELETE CASCADE,
        enabled      INTEGER NOT NULL DEFAULT 0,
        start_day    INTEGER,
        end_day      INTEGER,
        subject      TEXT NOT NULL DEFAULT '',
        body         TEXT NOT NULL DEFAULT '',
        zone         INTEGER NOT NULL DEFAULT 0,
        placed       INTEGER NOT NULL DEFAULT 0,
        device_dates INTEGER NOT NULL DEFAULT 0
    );
"#,
    r#"
    -- The Vault reads its mail again, a year of it: failed charges with
    -- no sum, a train's coach and seat, the post's "la spedizione … è
    -- stata consegnata", and its new kinds (sales, stays, parking,
    -- ferries, car hire, events, deadlines, gift cards, documents).
    UPDATE message SET vault_checked = 0;
"#,
    r#"
    -- Who the person wrote to, from their Sent mail: those senders are
    -- people even through a list or from info@ (`FiltersToApprove`).
    CREATE TABLE IF NOT EXISTS written_to (
        account INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
        email   TEXT NOT NULL,
        PRIMARY KEY (account, email)
    );
    CREATE INDEX IF NOT EXISTS written_to_email ON written_to (email);
    -- Senders the person moved by hand: 1 People, 0 Notifications.
    CREATE TABLE IF NOT EXISTS sender_side (
        email  TEXT PRIMARY KEY,
        people INTEGER NOT NULL
    );
"#,
    r#"
    -- Inbox mail kept before has its headers read again, for `bulk`
    -- (added by `Store::migrate`, so that this runs again safely).
    UPDATE message SET list_checked = 0 WHERE mailbox = 'INBOX';
"#,
    r#"
    -- And once more, for the marks mailing services leave (Feedback-ID…).
    UPDATE message SET list_checked = 0 WHERE mailbox = 'INBOX';
"#,
    r#"
    -- What the account's server found about the sender of a kept body,
    -- for the warning band of `ProtectionToApprove`: the domain in From
    -- failed its DMARC check, whose signature passed, and the server that
    -- sent it. Bodies kept before have none.
    CREATE TABLE IF NOT EXISTS sender_check (
        account      INTEGER NOT NULL,
        mailbox      TEXT NOT NULL,
        uid          INTEGER NOT NULL,
        dmarc_failed INTEGER NOT NULL DEFAULT 0,
        signed_by    TEXT NOT NULL DEFAULT '',
        sent_by      TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (account, mailbox, uid),
        FOREIGN KEY (account, mailbox, uid) REFERENCES message(account, mailbox, uid) ON DELETE CASCADE
    );
"#,
    r#"
    -- Re-read existing Vault cards to include the merchant's VAT number.
    UPDATE message SET vault_checked = 0
     WHERE EXISTS (SELECT 1 FROM vault_card c
        WHERE c.account = message.account AND c.mailbox = message.mailbox AND c.uid = message.uid);
"#,
    r#"
    -- Read the small automation headers once for already cached inbox mail.
    UPDATE message SET list_checked = 0 WHERE mailbox = 'INBOX';
"#,
];

/// Number of the migration that made `written_to`, filled from the Sent
/// mail already kept.
const WRITTEN_TO: usize = 54;

/// Number of the migration after which stored previews are cleaned again.
const CLEAN_PREVIEWS: usize = 38;

/// The tables the sync space carries.
const SPACE_TABLES: &[&str] = &[
    "account",
    "signature",
    "message_template",
    "address_group",
    "group_address",
    "account_alias",
    "rule",
    "calendar_source",
    "calendar",
    "label",
    "setting",
];

/// Columns the sync space leaves out: what a rule did on this device.
const SPACE_LOCAL_COLUMNS: &[(&str, &str)] = &[
    ("rule", "last_run"),
    ("rule", "matched"),
    ("calendar_source", "synced"),
];

/// Settings that stay on their device.
const LOCAL_SETTINGS: &[&str] = &[
    "hint.",
    "search.",
    "space.",
    "nightly.",
    "rules.sorted.",
    "sign_in.",
    "labels.local.",
];

/// A column value as JSON; blobs as `{"blob": base64}`.
fn to_json(v: rusqlite::types::ValueRef<'_>) -> serde_json::Value {
    use base64::Engine as _;
    use rusqlite::types::ValueRef;
    match v {
        ValueRef::Null => serde_json::Value::Null,
        ValueRef::Integer(i) => i.into(),
        ValueRef::Real(f) => f.into(),
        ValueRef::Text(t) => String::from_utf8_lossy(t).into_owned().into(),
        ValueRef::Blob(b) => serde_json::json!({
            "blob": base64::engine::general_purpose::STANDARD.encode(b)
        }),
    }
}

fn from_json(v: &serde_json::Value) -> rusqlite::types::Value {
    use base64::Engine as _;
    use rusqlite::types::Value;
    match v {
        serde_json::Value::Null => Value::Null,
        serde_json::Value::Bool(b) => Value::Integer(i64::from(*b)),
        serde_json::Value::Number(n) => n
            .as_i64()
            .map(Value::Integer)
            .or_else(|| n.as_f64().map(Value::Real))
            .unwrap_or(Value::Null),
        serde_json::Value::String(s) => Value::Text(s.clone()),
        serde_json::Value::Object(o) => o
            .get("blob")
            .and_then(|b| b.as_str())
            .and_then(|b| base64::engine::general_purpose::STANDARD.decode(b).ok())
            .map_or(Value::Null, Value::Blob),
        serde_json::Value::Array(_) => Value::Null,
    }
}

/// A template for compose's "/": a name, and the subject and text it puts
/// in a message.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MessageTemplate {
    /// 0 for one not kept yet.
    pub id: i64,
    pub name: String,
    pub subject: String,
    pub body: String,
}

/// A draft saved on this device while its server could not be reached.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WaitingDraft {
    pub id: i64,
    pub account: AccountId,
    /// The message as built, ready to append.
    pub raw: Vec<u8>,
    pub message_id: String,
    /// The copy on the server it replaces: (account, mailbox, uid).
    pub earlier: Option<(AccountId, String, u32)>,
    /// The signature picked by hand, as the draft setting keeps it.
    pub signature: Option<String>,
}

/// A connected calendar account or feed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalendarSource {
    pub id: i64,
    /// "caldav" or "ics".
    pub kind: String,
    pub name: String,
    /// The calendar home (CalDAV) or the feed's address (.ics).
    pub url: String,
    pub username: String,
    /// The email account it came with, when it shares its password.
    pub account: Option<AccountId>,
    pub synced: Option<i64>,
    /// How often a feed asks to be read again, in seconds, when it says.
    pub refresh: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalendarRow {
    pub id: i64,
    pub source: i64,
    pub url: String,
    pub name: String,
    pub color: Option<String>,
    pub read_only: bool,
    /// Its events count when telling whether you are free.
    pub availability: bool,
}

/// An event that makes you busy.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Busy {
    pub uid: String,
    pub summary: String,
    pub start: i64,
    pub end: i64,
    pub all_day: bool,
    pub floating: bool,
    /// The calendar's name and color.
    pub calendar: String,
    pub color: Option<String>,
}

/// How far back the Vault looks, in seconds: older mail makes no cards.
/// A year, so past trips and what is still under warranty stay.
pub const VAULT_SPAN: i64 = 366 * 86_400;

/// SQL for whether the message of the row is one a rule moved to the
/// Vault.
const PINNED: &str = "(message_id <> '' AND message_id IN (SELECT message_id FROM vault_pin))";

fn set_vault_checked(
    tx: &rusqlite::Transaction,
    account: AccountId,
    mailbox: &str,
    uid: u32,
) -> Result<()> {
    tx.execute(
        "UPDATE message SET vault_checked = 1 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
        params![account.0, mailbox, uid],
    )?;
    Ok(())
}

/// Reads the Vault card a message makes from its body, and keeps it (or
/// forgets the one it made before).
fn file_card(
    tx: &rusqlite::Transaction,
    account: AccountId,
    mailbox: &str,
    uid: u32,
    body: &Body,
) -> Result<()> {
    // Off, the message stays unchecked: turned on, the Vault reads it.
    if !crate::features::on(tx, crate::features::VAULT)? {
        return Ok(());
    }
    let Some((subject, from_name, message_id, received_at, folder, newsletter, pinned)) = tx
        .query_row(
            &format!(
                "SELECT subject, from_name, message_id, received_at, folder, newsletter, {PINNED}
                 FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3"
            ),
            params![account.0, mailbox, uid],
            |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, i64>(3)?,
                    r.get::<_, String>(4)?,
                    r.get::<_, bool>(5)?,
                    r.get::<_, bool>(6)?,
                ))
            },
        )
        .optional()?
    else {
        return Ok(());
    };
    let html = body.html.as_deref();
    let worth = !newsletter
        && !["sent", "drafts"].contains(&folder.as_str())
        && (crate::vault::candidate(&subject) || html.is_some_and(crate::vault::has_markup));
    // Without a Message-ID, the message's place is what names it.
    let id = if message_id.is_empty() {
        format!("{}/{mailbox}/{uid}", account.0)
    } else {
        message_id
    };
    let src = crate::vault::Source {
        subject: &subject,
        from_name: &from_name,
        message_id: &id,
        received_at,
        text: &body.text,
        html,
        attachments: &body.attachments,
    };
    let card = if pinned && folder != "drafts" {
        Some(crate::vault::extract_kept(&src))
    } else if worth {
        crate::vault::extract(&src)
    } else {
        None
    };
    match card {
        Some(card) => {
            tx.execute(
                "INSERT OR REPLACE INTO vault_card (account, mailbox, uid, key, data)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![
                    account.0,
                    mailbox,
                    uid,
                    card.key,
                    serde_json::to_string(&card).unwrap_or_default()
                ],
            )?;
        }
        None => {
            tx.execute(
                "DELETE FROM vault_card WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
            )?;
        }
    }
    set_vault_checked(tx, account, mailbox, uid)
}

/// SQL for the list an inbox message goes to: the one its sender was
/// moved to, else Newsletters for a newsletter. `email` and `newsletter`
/// are the SQL for its address and whether it is one.
/// With Newsletters turned off, everything stays in the inbox.
fn inbox_zone(email: &str, newsletter: &str) -> String {
    format!(
        "CASE WHEN {off} THEN 'inbox' ELSE
             COALESCE((SELECT zone FROM sender_zone WHERE email = lower({email})),
                      CASE WHEN {newsletter} THEN 'newsletters' ELSE 'inbox' END) END",
        off = crate::features::off_sql(crate::features::NEWSLETTERS),
    )
}

/// Files the inbox mail again after Newsletters was turned on or off.
fn refile_inbox(conn: &rusqlite::Connection) -> Result<()> {
    conn.execute(
        &format!(
            "UPDATE message SET folder = {}
             WHERE folder IN ('inbox', 'newsletters')",
            inbox_zone("from_email", "newsletter = 1")
        ),
        [],
    )?;
    Ok(())
}

/// A folder's name as people read it: Gmail keeps its own folders in
/// "[Gmail]" (or "[Google Mail]"), shown without the brackets.
fn shown_folder_name(name: String) -> String {
    match name.strip_prefix('[').and_then(|n| n.strip_suffix(']')) {
        Some(inner) if !inner.trim().is_empty() => inner.to_owned(),
        _ => name,
    }
}

/// A JSON list of strings, as the outbox keeps addresses.
fn list(json: &str) -> Vec<String> {
    serde_json::from_str(json).unwrap_or_default()
}

fn server_columns(s: &Server) -> (Option<&str>, Option<u16>, Option<&'static str>) {
    (Some(s.host.as_str()), Some(s.port), Some(s.security.tag()))
}

/// One of an account's own folders.
/// Days of hand moves kept for the rule Rules & folders suggests.
const MOVE_LOG_DAYS: i64 = 60;

/// A sender whose mail the person keeps moving to one folder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FrequentMove {
    pub account: AccountId,
    /// The address, lowercase.
    pub sender: String,
    pub name: String,
    /// The folder's server name.
    pub target: String,
    pub moves: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountFolder {
    /// What the server and the cache call it, e.g. "Clients/Acme".
    pub mailbox: String,
    /// What the person reads: the last part, e.g. "Acme".
    pub name: String,
    /// 0 at the top, 1 for a subfolder, and so on.
    pub depth: u32,
    /// False for a folder that only holds other folders.
    pub selectable: bool,
    pub unread: u32,
    /// How many emails it holds on the server.
    pub total: u32,
}

/// What the engine remembers about a server folder between syncs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MailboxState {
    /// UIDVALIDITY: when it changes, every cached UID is meaningless.
    pub uid_validity: u32,
    /// CONDSTORE HIGHESTMODSEQ, when the server supports it.
    pub highest_modseq: Option<u64>,
}

pub struct Store {
    conn: Connection,
}

/// What was stopped: trackers in all (pixels among them), links cleaned,
/// and links flagged.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PrivacyCounts {
    pub trackers: u32,
    pub links: u32,
    pub pixels: u32,
    pub suspicious: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrustedSender {
    pub email: String,
    /// The name in their latest message; may be empty.
    pub name: String,
    /// When they were trusted, in seconds since the epoch.
    pub since: i64,
}

/// A message's content, as cached.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Body {
    /// Readable text: for search, replies, and messages without HTML.
    pub text: String,
    pub html: Option<String>,
    pub attachments: Vec<Attachment>,
    /// The invite it carries: its `text/calendar` part, as written.
    pub calendar: Option<String>,
    /// Pictures the HTML shows from inside the message (`cid:`).
    pub inline: Vec<InlineImage>,
    /// What its server found about the sender, read as it is kept: see
    /// [`Store::sender_verified`].
    pub auth: crate::sender_auth::Trail,
}

/// A picture that travels inside a message, shown by its HTML as
/// `cid:<id>`.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct InlineImage {
    /// Its Content-ID, without the angle brackets.
    pub cid: String,
    pub mime: String,
    pub data: Vec<u8>,
}

/// A file attached to a message.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Attachment {
    /// Where it is in the message (the parser's part number).
    pub part: u32,
    pub name: String,
    /// Content type, like "application/pdf".
    pub mime: String,
    /// Decoded size in bytes.
    pub size: u64,
    /// The part's number in the server's outline ("2", "1.3"), for files
    /// listed before the body was here; they are fetched alone.
    pub section: Option<String>,
    /// How that part travels: "base64", "quoted-printable" or none.
    pub encoding: Option<String>,
}

/// Runs every stored preview through [`crate::imap::clean_preview`] again.
/// One that comes out empty is filled in when its message is opened.
fn clean_previews(tx: &rusqlite::Transaction) -> Result<()> {
    let changed: Vec<(i64, String)> = {
        let mut stmt = tx.prepare("SELECT rowid, preview FROM message WHERE preview != ''")?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?;
        let mut changed = Vec::new();
        for row in rows {
            let (id, preview) = row?;
            // The parser marked its cut with dots, now and then alone
            // on a line of their own.
            let cut = preview.strip_suffix("...").unwrap_or(&preview);
            let clean = crate::imap::clean_preview(cut);
            if clean != preview {
                changed.push((id, clean));
            }
        }
        changed
    };
    let mut update = tx.prepare("UPDATE message SET preview = ?2 WHERE rowid = ?1")?;
    for (id, preview) in changed {
        update.execute(params![id, preview])?;
    }
    Ok(())
}

/// The functions the SQL here calls: [`machine_address`],
/// [`no_reply_address`] and [`forwarded`].
fn functions(conn: &Connection) -> rusqlite::Result<()> {
    use rusqlite::functions::FunctionFlags;
    let flags = FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC;
    conn.create_scalar_function("machine_address", 1, flags, |ctx| {
        Ok(machine_address(&ctx.get::<String>(0).unwrap_or_default()))
    })?;
    conn.create_scalar_function("no_reply_address", 1, flags, |ctx| {
        Ok(no_reply_address(&ctx.get::<String>(0).unwrap_or_default()))
    })?;
    conn.create_scalar_function("automatic_content", 3, flags, |ctx| {
        Ok(crate::automation::content(
            &ctx.get::<String>(0)?,
            &ctx.get::<String>(1)?,
            ctx.get::<bool>(2)?,
        ))
    })?;
    conn.create_scalar_function("forwarded", 1, flags, |ctx| {
        Ok(forwarded(&ctx.get::<String>(0).unwrap_or_default()))
    })
}

impl Store {
    /// Opens (or creates) the database in a file.
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let conn = Connection::open(path)?;
        // Other connections may hold the write lock briefly, including
        // while this connection initializes or runs migrations.
        conn.busy_timeout(std::time::Duration::from_secs(2))?;
        Self::init(conn)
    }

    /// A second connection to the file [`Self::open`] opened, for reading
    /// only: with WAL it reads while the other one writes, without waiting.
    pub fn open_reader(path: impl AsRef<Path>) -> Result<Self> {
        let conn = Connection::open_with_flags(
            path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )?;
        // A checkpoint can hold readers off for a moment.
        conn.busy_timeout(std::time::Duration::from_secs(2))?;
        functions(&conn)?;
        Ok(Store { conn })
    }

    /// In-memory database, for tests.
    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self> {
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "foreign_keys", "ON")?;
        functions(&conn)?;
        let mut store = Store { conn };
        store.migrate()?;
        Ok(store)
    }

    fn migrate(&mut self) -> Result<()> {
        let current: usize = self
            .conn
            .pragma_query_value(None, "user_version", |row| row.get(0))?;
        let tx = self.conn.transaction()?;
        for (i, sql) in MIGRATIONS.iter().enumerate().skip(current) {
            tx.execute_batch(sql)?;
            tx.pragma_update(None, "user_version", i + 1)?;
        }
        // Bulk or automatic mail by Precedence and Auto-Submitted, which
        // goes to Notifications.
        let bulk: bool = tx.query_row(
            "SELECT EXISTS (SELECT 1 FROM pragma_table_info('message') WHERE name = 'bulk')",
            [],
            |r| r.get(0),
        )?;
        if !bulk {
            tx.execute_batch("ALTER TABLE message ADD COLUMN bulk INTEGER NOT NULL DEFAULT 0")?;
        }
        // Bold, italic and links of mail sent later, kept to edit it again.
        let marks: bool = tx.query_row(
            "SELECT EXISTS (SELECT 1 FROM pragma_table_info('outbox') WHERE name = 'marks')",
            [],
            |r| r.get(0),
        )?;
        if !marks {
            tx.execute_batch("ALTER TABLE outbox ADD COLUMN marks TEXT NOT NULL DEFAULT ''")?;
        }
        if current < CLEAN_PREVIEWS {
            clean_previews(&tx)?;
        }
        if current < WRITTEN_TO {
            tx.execute(
                NOTE_WRITTEN_TO,
                params![None::<i64>, None::<String>, None::<u32>],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    /// Schema version, useful for diagnostics.
    pub fn schema_version(&self) -> Result<usize> {
        Ok(self
            .conn
            .pragma_query_value(None, "user_version", |row| row.get(0))?)
    }

    /// Adds an account and returns its id. The id passed in is ignored.
    pub fn add_account(&self, account: &Account) -> Result<AccountId> {
        let none = || (None, None, None);
        let ((ih, ip, is), (sh, sp, ss), username, jmap_url) = match &account.kind {
            AccountKind::Imap {
                imap,
                smtp,
                username,
            } => (
                server_columns(imap),
                server_columns(smtp),
                Some(username.as_str()),
                None,
            ),
            AccountKind::Jmap {
                session_url,
                username,
            } => (
                none(),
                none(),
                Some(username.as_str()),
                Some(session_url.as_str()),
            ),
        };
        self.conn.execute(
            "INSERT INTO account (name, email, color, kind, imap_host, imap_port, imap_security,
                                  smtp_host, smtp_port, smtp_security, username, jmap_url, sender_name)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
            params![
                account.name,
                account.email,
                account.color,
                account.kind_tag(),
                ih,
                ip,
                is,
                sh,
                sp,
                ss,
                username,
                jmap_url,
                account.sender_name
            ],
        )?;
        Ok(AccountId(self.conn.last_insert_rowid()))
    }

    pub fn accounts(&self) -> Result<Vec<Account>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, name, email, color, kind, imap_host, imap_port, imap_security,
                    smtp_host, smtp_port, smtp_security, username, jmap_url, sender_name
             FROM account ORDER BY id",
        )?;
        let rows = stmt.query_map([], |r| {
            let server = |host: usize, port: usize, security: usize, default_port: u16| {
                Ok::<_, rusqlite::Error>(Server {
                    host: r.get::<_, Option<String>>(host)?.unwrap_or_default(),
                    port: r.get::<_, Option<u16>>(port)?.unwrap_or(default_port),
                    security: Security::from_tag(
                        r.get::<_, Option<String>>(security)?
                            .as_deref()
                            .unwrap_or("tls"),
                    ),
                })
            };
            Ok((
                AccountId(r.get(0)?),
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                server(5, 6, 7, 993)?,
                server(8, 9, 10, 465)?,
                r.get::<_, Option<String>>(11)?,
                r.get::<_, Option<String>>(12)?,
                r.get::<_, String>(13)?,
            ))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (id, name, email, color, kind, imap, smtp, username, jmap_url, sender_name) = row?;
            let kind = match kind.as_str() {
                "imap" => AccountKind::Imap {
                    imap,
                    smtp,
                    username: username.unwrap_or_else(|| email.clone()),
                },
                // Accounts from before the login was kept sign in with the
                // address.
                "jmap" => AccountKind::Jmap {
                    session_url: jmap_url.unwrap_or_default(),
                    username: username.unwrap_or_else(|| email.clone()),
                },
                other => return Err(StoreError::UnknownKind(other.to_owned())),
            };
            out.push(Account {
                id,
                name,
                email,
                sender_name,
                color,
                kind,
            });
        }
        Ok(out)
    }

    /// Changes an account's name, From name, color and servers; its
    /// address and its mail stay.
    pub fn update_account(&self, account: &Account) -> Result<()> {
        let none = || (None, None, None);
        let ((ih, ip, is), (sh, sp, ss), username, jmap_url) = match &account.kind {
            AccountKind::Imap {
                imap,
                smtp,
                username,
            } => (
                server_columns(imap),
                server_columns(smtp),
                Some(username.as_str()),
                None,
            ),
            AccountKind::Jmap {
                session_url,
                username,
            } => (
                none(),
                none(),
                Some(username.as_str()),
                Some(session_url.as_str()),
            ),
        };
        self.conn.execute(
            "UPDATE account SET name = ?1, color = ?2, kind = ?3, imap_host = ?4, imap_port = ?5,
                    imap_security = ?6, smtp_host = ?7, smtp_port = ?8, smtp_security = ?9,
                    username = ?10, jmap_url = ?11, sender_name = ?12
             WHERE id = ?13",
            params![
                account.name,
                account.color,
                account.kind_tag(),
                ih,
                ip,
                is,
                sh,
                sp,
                ss,
                username,
                jmap_url,
                account.sender_name,
                account.id.0
            ],
        )?;
        Ok(())
    }

    /// Removes an account and, through the foreign keys, all its mail.
    pub fn remove_account(&self, id: AccountId) -> Result<()> {
        self.conn
            .execute("DELETE FROM account WHERE id = ?1", params![id.0])?;
        Ok(())
    }

    pub fn account(&self, id: AccountId) -> Result<Option<Account>> {
        Ok(self.accounts()?.into_iter().find(|a| a.id == id))
    }

    /// Inserts or updates messages in a single transaction.
    pub fn upsert_messages(&mut self, messages: &[MessageSummary]) -> Result<()> {
        let mut own: HashMap<AccountId, Vec<String>> = HashMap::new();
        for m in messages {
            if bare_reply(m).is_some() && !own.contains_key(&m.account) {
                own.insert(m.account, self.own_addresses(m.account)?);
            }
        }
        let tx = self.conn.transaction()?;
        {
            let mut stmt = tx.prepare(&format!(
                "INSERT INTO message (account, mailbox, uid, from_name, from_email, subject, preview,
                                      received_at, flags, message_id, refs, reply_to, to_list,
                                      thread, newsletter, unsubscribe, one_click, list_checked,
                                      folder, recipients, bulk)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16,
                         ?17, 1,
                         CASE WHEN ?2 = 'INBOX' AND ?18 THEN 'receipts'
                              WHEN ?2 = 'INBOX' THEN {} ELSE COALESCE(
                             (SELECT role FROM folder_role WHERE account = ?1 AND mailbox = ?2),
                             '') END, ?19, ?20)
                 ON CONFLICT (account, mailbox, uid) DO UPDATE SET
                    from_name = excluded.from_name, from_email = excluded.from_email,
                    subject = excluded.subject, preview = excluded.preview,
                    received_at = excluded.received_at, flags = excluded.flags,
                    message_id = excluded.message_id, refs = excluded.refs,
                    reply_to = excluded.reply_to, to_list = excluded.to_list,
                    thread = excluded.thread, newsletter = excluded.newsletter,
                    unsubscribe = excluded.unsubscribe, one_click = excluded.one_click,
                    list_checked = 1, folder = excluded.folder,
                    recipients = excluded.recipients, bulk = excluded.bulk",
                inbox_zone("?5", "?15")
            ))?;
            let mut receipt = tx.prepare(
                "INSERT OR REPLACE INTO pec_receipt
                    (account, mailbox, uid, kind, refers, recipients, reason)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            )?;
            let mut known = tx.prepare(
                "SELECT thread FROM message WHERE account = ?1 AND message_id = ?2 LIMIT 1",
            )?;
            let mut written = tx.prepare(NOTE_WRITTEN_TO)?;
            // Messages that arrived before this one and took its id as their
            // thread (they only knew their parent) join this one's thread.
            let mut merge = tx.prepare(
                "UPDATE message SET thread = ?3 WHERE account = ?1 AND thread = ?2 AND ?2 <> ?3",
            )?;
            // Replies from clients that send no References: recent mail of
            // the account whose subject holds the reply's.
            let mut alike = tx.prepare(
                "SELECT thread, subject, from_email, recipients FROM message
                 WHERE account = ?1 AND received_at BETWEEN ?2 - ?3 AND ?2
                   AND NOT (mailbox = ?4 AND uid = ?5) AND thread IS NOT NULL
                   AND instr(lower(subject), lower(?6)) > 0
                 ORDER BY received_at DESC LIMIT 20",
            )?;
            for m in messages {
                let mut thread = thread_of(m, |id| {
                    known
                        .query_row(params![m.account.0, id], |r| r.get::<_, String>(0))
                        .optional()
                })?;
                if let Some(bare) = bare_reply(m) {
                    let found = alike
                        .query_map(
                            params![
                                m.account.0,
                                m.received_at,
                                SUBJECT_THREAD_DAYS * 86_400,
                                m.mailbox,
                                m.uid,
                                bare
                            ],
                            |r| {
                                Ok((
                                    r.get::<_, String>(0)?,
                                    r.get::<_, String>(1)?,
                                    r.get::<_, String>(2)?,
                                    r.get::<_, String>(3)?,
                                ))
                            },
                        )?
                        .filter_map(|r| r.ok())
                        .find(|(_, subject, from, to)| {
                            crate::brief::bare_subject(subject).eq_ignore_ascii_case(&bare)
                                && talked(m, from, to, &own[&m.account])
                        });
                    if let Some((t, ..)) = found {
                        thread = t;
                    }
                }
                if !m.reply.message_id.is_empty() {
                    merge.execute(params![m.account.0, m.reply.message_id, thread])?;
                }
                stmt.execute(params![
                    m.account.0,
                    m.mailbox,
                    m.uid,
                    m.from_name,
                    m.from_email,
                    m.subject,
                    m.preview,
                    m.received_at,
                    m.flags.to_bits(),
                    m.reply.message_id,
                    m.reply.references,
                    m.reply.reply_to,
                    m.to,
                    thread,
                    m.list.newsletter,
                    m.list.unsubscribe,
                    m.list.one_click,
                    m.list.receipt.is_some(),
                    m.reply.recipients,
                    m.list.bulk
                ])?;
                if !m.reply.recipients.is_empty() {
                    written.execute(params![m.account.0, m.mailbox, m.uid])?;
                }
                if let Some(r) = &m.list.receipt {
                    receipt.execute(params![
                        m.account.0,
                        m.mailbox,
                        m.uid,
                        r.kind.tag(),
                        r.refers,
                        serde_json::to_string(&r.recipients).unwrap_or_default(),
                        r.reason
                    ])?;
                }
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Hides a message from every list while an action on it can still be
    /// undone, or shows it again.
    pub fn set_hidden(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        hidden: bool,
    ) -> Result<()> {
        self.conn.execute(
            "UPDATE message SET hidden = ?4 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            params![account.0, mailbox, uid, hidden],
        )?;
        Ok(())
    }

    /// Replaces an account's folder list, in tree order, and forgets the
    /// messages of folders that are gone.
    pub fn set_account_folders(&self, account: AccountId, folders: &[AccountFolder]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        tx.execute(
            "DELETE FROM account_folder WHERE account = ?1",
            params![account.0],
        )?;
        {
            let mut stmt = tx.prepare(
                "INSERT OR REPLACE INTO account_folder
                    (account, mailbox, name, depth, position, selectable, unread, total)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            )?;
            for (i, f) in folders.iter().enumerate() {
                stmt.execute(params![
                    account.0,
                    f.mailbox,
                    f.name,
                    f.depth,
                    i as u32,
                    f.selectable,
                    f.unread,
                    f.total
                ])?;
            }
        }
        tx.execute(
            "DELETE FROM message WHERE account = ?1 AND folder = '' AND mailbox <> 'INBOX'
               AND mailbox NOT IN (SELECT mailbox FROM account_folder WHERE account = ?1)
               AND mailbox NOT IN (SELECT mailbox FROM folder_role WHERE account = ?1)",
            params![account.0],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// Lists a folder just made, after the others, until the next look at
    /// the server puts it in its place.
    pub fn add_account_folder(&self, account: AccountId, folder: &AccountFolder) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO account_folder
                (account, mailbox, name, depth, position, selectable, unread, total)
             VALUES (?1, ?2, ?3, ?4,
                     (SELECT COALESCE(MAX(position) + 1, 0) FROM account_folder WHERE account = ?1),
                     ?5, ?6, ?7)",
            params![
                account.0,
                folder.mailbox,
                folder.name,
                folder.depth,
                folder.selectable,
                folder.unread,
                folder.total
            ],
        )?;
        Ok(())
    }

    /// An account's own folders (not Inbox, Sent, Archive, Drafts, Trash
    /// or Junk), in the server's tree order, siblings in the order the
    /// person dragged them into.
    pub fn account_folders(&self, account: AccountId) -> Result<Vec<AccountFolder>> {
        let mut stmt = self.conn.prepare(
            "SELECT f.mailbox, f.name, f.depth, f.selectable, f.unread, f.total, o.rank
               FROM account_folder f
               LEFT JOIN folder_order o ON o.account = f.account AND o.mailbox = f.mailbox
              WHERE f.account = ?1 ORDER BY f.position",
        )?;
        let rows = stmt.query_map(params![account.0], |r| {
            Ok((
                AccountFolder {
                    mailbox: r.get(0)?,
                    name: shown_folder_name(r.get(1)?),
                    depth: r.get(2)?,
                    selectable: r.get(3)?,
                    unread: r.get(4)?,
                    total: r.get(5)?,
                },
                r.get::<_, Option<i64>>(6)?,
            ))
        })?;
        let rows = rows.collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(arrange(&rows))
    }

    /// Keeps the order the person gave some sibling folders (each with
    /// its subfolders under it), first to last.
    pub fn set_folder_order(&self, account: AccountId, mailboxes: &[String]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        {
            let mut stmt = tx.prepare(
                "INSERT OR REPLACE INTO folder_order (account, mailbox, rank) VALUES (?1, ?2, ?3)",
            )?;
            for (i, mailbox) in mailboxes.iter().enumerate() {
                stmt.execute(params![account.0, mailbox, i as i64])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// One server folder of one account as conversations, newest first.
    pub fn mailbox_page(
        &self,
        account: AccountId,
        mailbox: &str,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<Conversation>> {
        let mut stmt = self.conn.prepare_cached(&format!(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list,
                    m.thread,
                    (SELECT COUNT(DISTINCT CASE WHEN t.message_id <> '' THEN t.message_id
                                                ELSE t.mailbox || '/' || t.uid END)
                     FROM message t
                     WHERE t.account = m.account AND t.thread = m.thread AND t.hidden = 0
                       AND t.folder <> 'drafts')
             FROM message m
             WHERE m.account = ?1 AND m.mailbox = ?2 AND m.hidden = 0
               AND {NEWEST_IN_MAILBOX}
             ORDER BY m.received_at DESC, m.uid DESC
             LIMIT ?3 OFFSET ?4"
        ))?;
        let rows = stmt.query_map(params![account.0, mailbox, limit, offset], |r| {
            Ok(Conversation {
                latest: row_to_summary(r)?,
                thread: r.get(13)?,
                messages: r.get(14)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// How many conversations of one account's folder had their newest
    /// message there in [from, to), in seconds.
    pub fn mailbox_count_between(
        &self,
        account: AccountId,
        mailbox: &str,
        from: i64,
        to: i64,
    ) -> Result<u32> {
        Ok(self.conn.query_row(
            &format!(
                "SELECT COUNT(*) FROM message m
                 WHERE m.account = ?1 AND m.mailbox = ?2 AND m.hidden = 0
                   AND m.received_at >= ?3 AND m.received_at < ?4
                   AND {NEWEST_IN_MAILBOX}"
            ),
            params![account.0, mailbox, from, to],
            |r| r.get(0),
        )?)
    }

    /// How many conversations [`Store::mailbox_page`] lists.
    pub fn mailbox_count(&self, account: AccountId, mailbox: &str) -> Result<u32> {
        Ok(self.conn.query_row(
            &format!(
                "SELECT COUNT(*) FROM message m
                 WHERE m.account = ?1 AND m.mailbox = ?2 AND m.hidden = 0
                   AND {NEWEST_IN_MAILBOX}"
            ),
            params![account.0, mailbox],
            |r| r.get(0),
        )?)
    }

    /// Shows every hidden message again: an action that never reached the
    /// server (the app quit inside the Undo window) is simply not done.
    /// Messages moved while offline stay hidden: that move is still on
    /// its way.
    pub fn unhide_all(&self) -> Result<()> {
        self.conn.execute(
            "UPDATE message SET hidden = 0 WHERE hidden = 1 AND NOT EXISTS (
                SELECT 1 FROM pending_change p
                 WHERE p.account = message.account AND p.mailbox = message.mailbox
                   AND p.uid = message.uid AND p.change IN ('archive', 'trash', 'move'))",
            [],
        )?;
        Ok(())
    }

    /// Queues the archiving of an account's read newsletters that
    /// arrived before `before`, and hides them meanwhile. Returns how many.
    pub fn queue_newsletter_archive(
        &self,
        account: AccountId,
        before: i64,
        read: bool,
    ) -> Result<usize> {
        let tx = self.conn.unchecked_transaction()?;
        let queued = tx.execute(
            "INSERT INTO pending_change (account, mailbox, uid, change, target)
             SELECT account, mailbox, uid, 'archive', '' FROM message m
             WHERE account = ?1 AND folder = 'newsletters' AND hidden = 0 AND (flags & 1) = ?3
               AND received_at < ?2 AND NOT EXISTS (
                   SELECT 1 FROM pending_change p
                   WHERE p.account = m.account AND p.mailbox = m.mailbox AND p.uid = m.uid)",
            params![account.0, before, read as i64],
        )?;
        tx.execute(
            "UPDATE message SET hidden = 1
             WHERE account = ?1 AND folder = 'newsletters' AND hidden = 0 AND EXISTS (
                 SELECT 1 FROM pending_change p
                 WHERE p.account = message.account AND p.mailbox = message.mailbox
                   AND p.uid = message.uid AND p.change = 'archive')",
            params![account.0],
        )?;
        tx.commit()?;
        Ok(queued)
    }

    /// Every label, in the person's order.
    pub fn labels(&self) -> Result<Vec<Label>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name, color, keyword FROM label ORDER BY rank, id")?;
        let rows = stmt
            .query_map([], |r| {
                Ok(Label {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    color: r.get(2)?,
                    keyword: r.get(3)?,
                })
            })?
            .collect::<std::result::Result<_, _>>()?;
        Ok(rows)
    }

    /// The color a new label gets: the first of the five used least.
    pub fn next_label_color(&self) -> Result<&'static str> {
        let used: Vec<String> = self.labels()?.into_iter().map(|l| l.color).collect();
        let count = |c: &str| used.iter().filter(|u| *u == c).count();
        Ok(crate::label::COLORS
            .iter()
            .min_by_key(|c| count(c))
            .copied()
            .unwrap_or(crate::label::COLORS[0]))
    }

    /// Makes a label, or finds the one with that name (in any case).
    /// Its keyword comes from the name, made unique; an unknown color
    /// takes the next free one.
    pub fn add_label(&self, name: &str, color: &str) -> Result<Label> {
        let name = name.trim();
        if let Some(found) = self
            .labels()?
            .into_iter()
            .find(|l| l.name.to_lowercase() == name.to_lowercase())
        {
            return Ok(found);
        }
        let color = if crate::label::COLORS.contains(&color) {
            color
        } else {
            self.next_label_color()?
        };
        let base = crate::label::keyword_for(name);
        let taken: HashSet<String> = self.labels()?.into_iter().map(|l| l.keyword).collect();
        let keyword = (1..)
            .map(|n| {
                if n == 1 {
                    base.clone()
                } else {
                    format!("{base}_{n}")
                }
            })
            .find(|k| !taken.contains(k))
            .unwrap_or(base);
        self.conn.execute(
            "INSERT INTO label (name, color, keyword, rank)
             VALUES (?1, ?2, ?3, (SELECT COALESCE(MAX(rank), 0) + 1 FROM label))",
            params![name, color, keyword],
        )?;
        Ok(Label {
            id: self.conn.last_insert_rowid(),
            name: name.to_owned(),
            color: color.to_owned(),
            keyword,
        })
    }

    /// Renames a label or changes its color; its keyword stays, so the
    /// mail keeps it.
    pub fn update_label(&self, id: i64, name: &str, color: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE label SET name = ?2, color = CASE WHEN ?3 IN ('amber', 'teal', 'coral', 'blue', 'violet')
                                                     THEN ?3 ELSE color END
              WHERE id = ?1",
            params![id, name.trim(), color],
        )?;
        Ok(())
    }

    /// Deletes a label: it leaves every message here, and the server
    /// is told for each.
    pub fn remove_label(&self, id: i64) -> Result<()> {
        let Some(keyword) = self
            .conn
            .query_row(
                "SELECT keyword FROM label WHERE id = ?1",
                params![id],
                |r| r.get::<_, String>(0),
            )
            .optional()?
        else {
            return Ok(());
        };
        let labelled = self.labelled(&keyword)?;
        for (account, mailbox, uid) in labelled {
            self.label_message(account, &mailbox, uid, &keyword, false)?;
        }
        self.conn
            .execute("DELETE FROM label WHERE id = ?1", params![id])?;
        // Its rules have nothing left to put on.
        self.conn.execute(
            "DELETE FROM rule WHERE action = 'label' AND target = ?1",
            params![keyword],
        )?;
        Ok(())
    }

    /// The messages that carry a label's keyword.
    fn labelled(&self, keyword: &str) -> Result<Vec<(AccountId, String, u32)>> {
        let mut stmt = self.conn.prepare(
            "SELECT account, mailbox, uid FROM message_labels
              WHERE instr(' ' || labels || ' ', ' ' || ?1 || ' ') > 0",
        )?;
        let rows = stmt
            .query_map(params![keyword], |r| {
                Ok((AccountId(r.get(0)?), r.get(1)?, r.get(2)?))
            })?
            .collect::<std::result::Result<_, _>>()?;
        Ok(rows)
    }

    /// A message's label keywords.
    pub fn message_labels(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<Vec<String>> {
        let labels: Option<String> = self
            .conn
            .query_row(
                "SELECT labels FROM message_labels WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get(0),
            )
            .optional()?;
        Ok(labels
            .unwrap_or_default()
            .split_whitespace()
            .map(str::to_owned)
            .collect())
    }

    /// Puts a label on a message or takes it off: here at once, then on
    /// the server, unless the account keeps its labels on this device.
    pub fn label_message(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        keyword: &str,
        add: bool,
    ) -> Result<()> {
        let mut labels = self.message_labels(account, mailbox, uid)?;
        labels.retain(|k| k != keyword);
        if add {
            labels.push(keyword.to_owned());
        }
        self.keep_labels(account, mailbox, uid, &labels.join(" "))?;
        if !self.labels_local(account)? {
            self.queue_change(
                account,
                mailbox,
                uid,
                Change::Label {
                    keyword: keyword.to_owned(),
                    add,
                },
            )?;
        }
        Ok(())
    }

    /// What the server says each message's keywords are. Changes still
    /// waiting to be sent win, and an account whose server keeps no
    /// keywords keeps its labels as they are here.
    pub fn set_server_labels(
        &self,
        account: AccountId,
        mailbox: &str,
        keywords: &[(u32, Vec<String>)],
    ) -> Result<()> {
        if keywords.is_empty() || self.labels_local(account)? {
            return Ok(());
        }
        let tx = self.conn.unchecked_transaction()?;
        {
            let mut waiting = tx.prepare(
                "SELECT change, target FROM pending_change
                  WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND change IN ('label', 'unlabel')
                  ORDER BY id",
            )?;
            let mut keep = tx.prepare(LABELS_KEEP)?;
            let mut drop = tx.prepare(LABELS_DROP)?;
            for (uid, kws) in keywords {
                let mut labels: Vec<String> = kws
                    .iter()
                    .filter(|k| crate::label::may_be_label(k))
                    .map(|k| k.to_lowercase())
                    .collect();
                let changes = waiting
                    .query_map(params![account.0, mailbox, uid], |r| {
                        Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
                    })?
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                for (change, keyword) in changes {
                    labels.retain(|k| *k != keyword);
                    if change == "label" {
                        labels.push(keyword);
                    }
                }
                labels.sort();
                labels.dedup();
                if labels.is_empty() {
                    drop.execute(params![account.0, mailbox, uid])?;
                } else {
                    keep.execute(params![account.0, mailbox, uid, labels.join(" ")])?;
                }
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Keeps a message's label keywords, if the message is here.
    fn keep_labels(&self, account: AccountId, mailbox: &str, uid: u32, labels: &str) -> Result<()> {
        if labels.is_empty() {
            self.conn
                .execute(LABELS_DROP, params![account.0, mailbox, uid])?;
        } else {
            self.conn
                .execute(LABELS_KEEP, params![account.0, mailbox, uid, labels])?;
        }
        Ok(())
    }

    /// The account's server refuses keywords: its labels stay on this
    /// device, and what waited to be sent is dropped.
    pub fn set_labels_local(&self, account: AccountId) -> Result<()> {
        self.set_setting(&format!("labels.local.{}", account.0), "1")?;
        self.conn.execute(
            "DELETE FROM pending_change WHERE account = ?1 AND change IN ('label', 'unlabel')",
            params![account.0],
        )?;
        Ok(())
    }

    /// Remembers the account's spam folder, by its server name, or that
    /// it has none.
    pub fn set_junk_mailbox(&self, account: AccountId, mailbox: Option<&str>) -> Result<()> {
        self.set_setting(
            &format!("account.{}.junk", account.0),
            mailbox.unwrap_or_default(),
        )
    }

    /// The account's spam folder, once a sync found one.
    pub fn junk_mailbox(&self, account: AccountId) -> Result<Option<String>> {
        Ok(self
            .setting(&format!("account.{}.junk", account.0))?
            .filter(|m| !m.is_empty()))
    }

    /// Whether the account keeps its labels on this device only.
    pub fn labels_local(&self, account: AccountId) -> Result<bool> {
        Ok(self
            .setting(&format!("labels.local.{}", account.0))?
            .as_deref()
            == Some("1"))
    }

    /// Every message with a label, from every account and folder but the
    /// trash, newest first.
    pub fn labelled_messages(&self, keyword: &str) -> Result<Vec<MessageSummary>> {
        let mut stmt = self.conn.prepare(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list
               FROM message_labels ml JOIN message m USING (account, mailbox, uid)
              WHERE m.hidden = 0 AND m.folder <> 'trash'
                AND instr(' ' || ml.labels || ' ', ' ' || ?1 || ' ') > 0
              ORDER BY m.received_at DESC, m.uid DESC",
        )?;
        let rows = stmt
            .query_map(params![keyword], row_to_summary)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }

    /// How many messages carry each label, by its id, outside the trash.
    pub fn label_counts(&self) -> Result<Vec<(i64, usize)>> {
        let mut stmt = self.conn.prepare(
            "SELECT l.id, (SELECT COUNT(*) FROM message_labels ml
                             JOIN message m USING (account, mailbox, uid)
                            WHERE m.hidden = 0 AND m.folder <> 'trash'
                              AND instr(' ' || ml.labels || ' ', ' ' || l.keyword || ' ') > 0)
               FROM label l ORDER BY l.rank, l.id",
        )?;
        let rows = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get::<_, i64>(1)? as usize)))?
            .collect::<std::result::Result<_, _>>()?;
        Ok(rows)
    }

    /// Keeps a change to send when the server can be reached. A newer
    /// read or unread replaces an older one.
    pub fn queue_change(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        change: Change,
    ) -> Result<()> {
        if let Change::Seen(_) = &change {
            self.conn.execute(
                "DELETE FROM pending_change WHERE account = ?1 AND mailbox = ?2 AND uid = ?3
                   AND change IN ('seen', 'unseen')",
                params![account.0, mailbox, uid],
            )?;
        }
        if let Change::Label { keyword, .. } = &change {
            self.conn.execute(
                "DELETE FROM pending_change WHERE account = ?1 AND mailbox = ?2 AND uid = ?3
                   AND change IN ('label', 'unlabel') AND target = ?4",
                params![account.0, mailbox, uid, keyword],
            )?;
        }
        self.conn.execute(
            "INSERT INTO pending_change (account, mailbox, uid, change, target)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![account.0, mailbox, uid, change.tag(), change.target()],
        )?;
        Ok(())
    }

    /// An account's waiting changes, oldest first.
    pub fn pending_changes(&self, account: AccountId) -> Result<Vec<Pending>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, mailbox, uid, change, attempts, target FROM pending_change
              WHERE account = ?1 ORDER BY id",
        )?;
        let rows = stmt.query_map(params![account.0], |r| {
            Ok((
                r.get::<_, i64>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, u32>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, u32>(4)?,
                r.get::<_, String>(5)?,
            ))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (id, mailbox, uid, tag, attempts, target) = row?;
            if let Some(change) = Change::from_tag(&tag, target) {
                out.push(Pending {
                    id,
                    mailbox,
                    uid,
                    change,
                    attempts,
                });
            }
        }
        Ok(out)
    }

    /// Forgets changes the server now has.
    pub fn drop_changes(&self, ids: &[i64]) -> Result<()> {
        let mut stmt = self
            .conn
            .prepare("DELETE FROM pending_change WHERE id = ?1")?;
        for id in ids {
            stmt.execute(params![id])?;
        }
        Ok(())
    }

    /// Counts a failed try. After [`MAX_ATTEMPTS`] the change is given up:
    /// a message that was moved shows again, and the next sync puts its
    /// flags back to the server's.
    pub fn failed_changes(&self, ids: &[i64]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        for id in ids {
            tx.execute(
                "UPDATE pending_change SET attempts = attempts + 1 WHERE id = ?1",
                params![id],
            )?;
            tx.execute(
                "UPDATE message SET hidden = 0 WHERE EXISTS (
                    SELECT 1 FROM pending_change p
                     WHERE p.id = ?1 AND p.attempts >= ?2
                       AND p.account = message.account AND p.mailbox = message.mailbox
                       AND p.uid = message.uid AND p.change IN ('archive', 'trash', 'move'))",
                params![id, MAX_ATTEMPTS],
            )?;
            tx.execute(
                "DELETE FROM pending_change WHERE id = ?1 AND attempts >= ?2",
                params![id, MAX_ATTEMPTS],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    /// Changes a message's flags (optimistic: locally first, then on the
    /// server).
    pub fn set_flags(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        flags: Flags,
    ) -> Result<bool> {
        let n = self.conn.execute(
            "UPDATE message SET flags = ?4 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            params![account.0, mailbox, uid, flags.to_bits()],
        )?;
        Ok(n == 1)
    }

    /// Marks a message read or unread, keeping its other flags.
    pub fn set_seen(&self, account: AccountId, mailbox: &str, uid: u32, seen: bool) -> Result<()> {
        self.conn.execute(
            "UPDATE message SET flags = CASE WHEN ?4 THEN flags | 1 ELSE flags & ~1 END
             WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            params![account.0, mailbox, uid, seen],
        )?;
        Ok(())
    }

    pub fn message(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<Option<MessageSummary>> {
        Ok(self
            .conn
            .query_row(
                "SELECT account, mailbox, uid, from_name, from_email, subject, preview, received_at, flags,
                    message_id, refs, reply_to, to_list
                 FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                row_to_summary,
            )
            .optional()?)
    }

    /// The message of a folder with this Message-ID, newest first.
    pub fn uid_of(
        &self,
        account: AccountId,
        mailbox: &str,
        message_id: &str,
    ) -> Result<Option<u32>> {
        Ok(self
            .conn
            .query_row(
                "SELECT uid FROM message
                 WHERE account = ?1 AND mailbox = ?2 AND message_id = ?3
                 ORDER BY uid DESC LIMIT 1",
                params![account.0, mailbox, message_id],
                |r| r.get(0),
            )
            .optional()?)
    }

    /// The conversation a message belongs to, empty when it has none.
    pub fn thread_of(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<String> {
        Ok(self
            .conn
            .query_row(
                "SELECT thread FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get::<_, Option<String>>(0),
            )
            .optional()?
            .flatten()
            .unwrap_or_default())
    }

    /// Which of the shared folders a message is in (Sent, Archive, …),
    /// None for one of the account's own folders.
    pub fn folder_of(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<Option<Folder>> {
        Ok(self
            .conn
            .query_row(
                "SELECT folder FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get::<_, String>(0),
            )
            .optional()?
            .and_then(|tag| Folder::from_tag(&tag)))
    }

    /// A unified list: `folder` of every account, newest first.
    /// `before` is the cursor for the next page.
    pub fn unified(
        &self,
        folder: Folder,
        before: Option<i64>,
        limit: u32,
    ) -> Result<Vec<MessageSummary>> {
        let mut stmt = self.conn.prepare(
            "SELECT account, mailbox, uid, from_name, from_email, subject, preview, received_at, flags,
                    message_id, refs, reply_to, to_list
             FROM message
             WHERE folder = ?1 AND hidden = 0 AND received_at < ?2
             ORDER BY received_at DESC, account, uid DESC
             LIMIT ?3",
        )?;
        let rows = stmt.query_map(
            params![folder.tag(), before.unwrap_or(i64::MAX), limit],
            row_to_summary,
        )?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Same order as [`Store::unified`], addressed by position: what a
    /// virtualized list needs to draw any row of a 50,000-message inbox.
    pub fn unified_page(
        &self,
        folder: Folder,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<MessageSummary>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT account, mailbox, uid, from_name, from_email, subject, preview, received_at, flags,
                    message_id, refs, reply_to, to_list
             FROM message
             WHERE folder = ?1 AND hidden = 0
             ORDER BY received_at DESC, account, uid DESC
             LIMIT ?2 OFFSET ?3",
        )?;
        let rows = stmt.query_map(params![folder.tag(), limit, offset], row_to_summary)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    pub fn count(&self, folder: Folder) -> Result<u32> {
        Ok(self.conn.query_row(
            "SELECT COUNT(*) FROM message WHERE folder = ?1 AND hidden = 0",
            params![folder.tag()],
            |r| r.get(0),
        )?)
    }

    /// How many messages of `folder` arrived in [from, to), in seconds.
    pub fn count_between(&self, folder: Folder, from: i64, to: i64) -> Result<u32> {
        Ok(self.conn.query_row(
            "SELECT COUNT(*) FROM message
             WHERE folder = ?1 AND hidden = 0 AND received_at >= ?2 AND received_at < ?3",
            params![folder.tag(), from, to],
            |r| r.get(0),
        )?)
    }

    /// A unified list of conversations: one row per thread with a message
    /// in `folder`, its newest one there, newest first, addressed by
    /// position like [`Store::unified_page`].
    pub fn conversations_page(
        &self,
        folder: Folder,
        within: impl Into<Within>,
        section: impl Into<ListFilter>,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<Conversation>> {
        let within = within.into();
        let section = section_sql(section) + &within.sql();
        let mut stmt = self.conn.prepare_cached(&format!(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list,
                    m.thread,
                    (SELECT COUNT(DISTINCT CASE WHEN t.message_id <> '' THEN t.message_id
                                                ELSE t.mailbox || '/' || t.uid END)
                     FROM message t
                     WHERE t.account = m.account AND t.thread = m.thread AND t.hidden = 0
                       AND t.folder <> 'drafts')
             FROM message m
             WHERE m.folder = ?1 AND m.hidden = 0 AND (?4 IS NULL OR m.account = ?4)
               AND {NEWEST_IN_THREAD}{section}
             ORDER BY m.received_at DESC, m.account, m.uid DESC
             LIMIT ?2 OFFSET ?3"
        ))?;
        let account = within.account();
        let rows = stmt.query_map(params![folder.tag(), limit, offset, account], |r| {
            Ok(Conversation {
                latest: row_to_summary(r)?,
                thread: r.get(13)?,
                messages: r.get(14)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// How many conversations have a message in `folder`, of one account
    /// or of all.
    pub fn conversation_count(
        &self,
        folder: Folder,
        within: impl Into<Within>,
        section: impl Into<ListFilter>,
    ) -> Result<u32> {
        let within = within.into();
        let section = section_sql(section) + &within.sql();
        Ok(self.conn.query_row(
            &format!(
                "SELECT COUNT(*) FROM message m
                 WHERE m.folder = ?1 AND m.hidden = 0 AND (?2 IS NULL OR m.account = ?2)
                   AND {NEWEST_IN_THREAD}{section}"
            ),
            params![folder.tag(), within.account()],
            |r| r.get(0),
        )?)
    }

    /// How many conversations of `folder` had their newest message there
    /// in [from, to), in seconds.
    pub fn conversation_count_between(
        &self,
        folder: Folder,
        within: impl Into<Within>,
        section: impl Into<ListFilter>,
        from: i64,
        to: i64,
    ) -> Result<u32> {
        let within = within.into();
        let section = section_sql(section) + &within.sql();
        Ok(self.conn.query_row(
            &format!(
                "SELECT COUNT(*) FROM message m
                 WHERE m.folder = ?1 AND m.hidden = 0 AND m.received_at >= ?2
                   AND m.received_at < ?3 AND (?4 IS NULL OR m.account = ?4)
                   AND {NEWEST_IN_THREAD}{section}"
            ),
            params![folder.tag(), from, to, within.account()],
            |r| r.get(0),
        )?)
    }

    /// Every message of a conversation, in every folder but Drafts, oldest
    /// first, each with the job of its folder. A message stored in two
    /// folders (a copy) shows once.
    pub fn conversation(
        &self,
        account: AccountId,
        thread: &str,
    ) -> Result<Vec<(MessageSummary, Option<Folder>)>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT account, mailbox, uid, from_name, from_email, subject, preview, received_at, flags,
                    message_id, refs, reply_to, to_list, folder
             FROM message
             WHERE account = ?1 AND thread = ?2 AND hidden = 0 AND folder <> 'drafts'
             ORDER BY received_at, mailbox = 'INBOX' DESC, uid",
        )?;
        let rows = stmt.query_map(params![account.0, thread], |r| {
            Ok((
                row_to_summary(r)?,
                Folder::from_tag(&r.get::<_, String>(13)?),
            ))
        })?;
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        for row in rows {
            let row = row?;
            let id = &row.0.reply.message_id;
            if id.is_empty() || seen.insert(id.clone()) {
                out.push(row);
            }
        }
        Ok(out)
    }

    /// Remembers which server folder of an account has a job, and files
    /// the messages already cached there.
    pub fn set_folder_role(&self, account: AccountId, folder: Folder, mailbox: &str) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        tx.execute(
            "INSERT INTO folder_role (account, role, mailbox) VALUES (?1, ?2, ?3)
             ON CONFLICT (account, role) DO UPDATE SET mailbox = excluded.mailbox",
            params![account.0, folder.tag(), mailbox],
        )?;
        tx.execute(
            "UPDATE message SET folder = '' WHERE account = ?1 AND folder = ?2 AND mailbox <> ?3",
            params![account.0, folder.tag(), mailbox],
        )?;
        tx.execute(
            "UPDATE message SET folder = ?2 WHERE account = ?1 AND mailbox = ?3",
            params![account.0, folder.tag(), mailbox],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// The server folder of an account that has a job, once found.
    pub fn folder_mailbox(&self, account: AccountId, folder: Folder) -> Result<Option<String>> {
        if folder == Folder::Inbox {
            return Ok(Some("INBOX".into()));
        }
        Ok(self
            .conn
            .query_row(
                "SELECT mailbox FROM folder_role WHERE account = ?1 AND role = ?2",
                params![account.0, folder.tag()],
                |r| r.get(0),
            )
            .optional()?)
    }

    pub fn mailbox_state(&self, account: AccountId, mailbox: &str) -> Result<Option<MailboxState>> {
        Ok(self
            .conn
            .query_row(
                "SELECT uid_validity, highest_modseq FROM mailbox WHERE account = ?1 AND name = ?2",
                params![account.0, mailbox],
                |r| {
                    Ok(MailboxState {
                        uid_validity: r.get(0)?,
                        highest_modseq: r.get::<_, Option<i64>>(1)?.map(|m| m as u64),
                    })
                },
            )
            .optional()?)
    }

    pub fn set_mailbox_state(
        &self,
        account: AccountId,
        mailbox: &str,
        state: MailboxState,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT INTO mailbox (account, name, uid_validity, highest_modseq) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT (account, name) DO UPDATE SET
                uid_validity = excluded.uid_validity, highest_modseq = excluded.highest_modseq",
            params![
                account.0,
                mailbox,
                state.uid_validity,
                state.highest_modseq.map(|m| m as i64)
            ],
        )?;
        Ok(())
    }

    /// UIDs cached for one folder of one account.
    pub fn uids(&self, account: AccountId, mailbox: &str) -> Result<Vec<u32>> {
        let mut stmt = self
            .conn
            .prepare("SELECT uid FROM message WHERE account = ?1 AND mailbox = ?2")?;
        let rows = stmt.query_map(params![account.0, mailbox], |r| r.get(0))?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Forgets the given messages (they were deleted on the server).
    pub fn remove_messages(
        &mut self,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<()> {
        let tx = self.conn.transaction()?;
        {
            let mut stmt =
                tx.prepare("DELETE FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3")?;
            let mut ids = tx.prepare(
                "DELETE FROM jmap_email WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            )?;
            for uid in uids {
                stmt.execute(params![account.0, mailbox, uid])?;
                ids.execute(params![account.0, mailbox, uid])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Forgets a whole folder, e.g. when its UIDVALIDITY changed.
    pub fn clear_mailbox(&self, account: AccountId, mailbox: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM message WHERE account = ?1 AND mailbox = ?2",
            params![account.0, mailbox],
        )?;
        self.conn.execute(
            "DELETE FROM jmap_email WHERE account = ?1 AND mailbox = ?2",
            params![account.0, mailbox],
        )?;
        // Their numbers now name other messages.
        self.conn.execute(
            "DELETE FROM pending_change WHERE account = ?1 AND mailbox = ?2",
            params![account.0, mailbox],
        )?;
        Ok(())
    }

    /// The JMAP ids cached for one folder, with their local numbers.
    pub fn jmap_ids(&self, account: AccountId, mailbox: &str) -> Result<HashMap<String, u32>> {
        let mut stmt = self
            .conn
            .prepare("SELECT email_id, uid FROM jmap_email WHERE account = ?1 AND mailbox = ?2")?;
        let rows = stmt.query_map(params![account.0, mailbox], |r| Ok((r.get(0)?, r.get(1)?)))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Gives new JMAP ids of a folder their local numbers, in order.
    /// Ids that already have one keep it.
    pub fn add_jmap_ids(
        &mut self,
        account: AccountId,
        mailbox: &str,
        ids: &[String],
    ) -> Result<Vec<u32>> {
        let tx = self.conn.transaction()?;
        let mut out = Vec::with_capacity(ids.len());
        {
            let mut next: u32 = tx
                .query_row(
                    "SELECT next_uid FROM jmap_mailbox WHERE account = ?1 AND mailbox = ?2",
                    params![account.0, mailbox],
                    |r| r.get(0),
                )
                .optional()?
                .unwrap_or(1);
            let mut known = tx.prepare(
                "SELECT uid FROM jmap_email WHERE account = ?1 AND mailbox = ?2 AND email_id = ?3",
            )?;
            let mut add = tx.prepare(
                "INSERT INTO jmap_email (account, mailbox, uid, email_id) VALUES (?1, ?2, ?3, ?4)",
            )?;
            for id in ids {
                if let Some(uid) = known
                    .query_row(params![account.0, mailbox, id], |r| r.get(0))
                    .optional()?
                {
                    out.push(uid);
                    continue;
                }
                add.execute(params![account.0, mailbox, next, id])?;
                out.push(next);
                next += 1;
            }
            tx.execute(
                "INSERT INTO jmap_mailbox (account, mailbox, next_uid) VALUES (?1, ?2, ?3)
                 ON CONFLICT (account, mailbox) DO UPDATE SET next_uid = excluded.next_uid",
                params![account.0, mailbox, next],
            )?;
        }
        tx.commit()?;
        Ok(out)
    }

    /// The JMAP id behind a local number.
    pub fn jmap_id(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row(
                "SELECT email_id FROM jmap_email WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get(0),
            )
            .optional()?)
    }

    /// Applies flag changes in one transaction. Unknown UIDs are skipped.
    pub fn update_flags(
        &mut self,
        account: AccountId,
        mailbox: &str,
        changes: &[(u32, Flags)],
    ) -> Result<usize> {
        let tx = self.conn.transaction()?;
        let mut changed = 0;
        {
            let mut stmt = tx.prepare(
                "UPDATE message SET flags = ?4
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND flags != ?4",
            )?;
            for (uid, flags) in changes {
                changed += stmt.execute(params![account.0, mailbox, uid, flags.to_bits()])?;
            }
        }
        tx.commit()?;
        Ok(changed)
    }

    /// The cached text of a message.
    pub fn body(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row(
                "SELECT text FROM message_body WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get(0),
            )
            .optional()?)
    }

    /// The cached text and HTML of a message. None when it isn't cached,
    /// or was cached before HTML was kept.
    pub fn full_body(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<Option<Body>> {
        let Some(mut body) = self
            .conn
            .query_row(
                "SELECT text, html, calendar FROM message_body
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND format > 0",
                params![account.0, mailbox, uid],
                |r| {
                    Ok(Body {
                        text: r.get(0)?,
                        html: r.get(1)?,
                        calendar: r.get(2)?,
                        ..Body::default()
                    })
                },
            )
            .optional()?
        else {
            return Ok(None);
        };
        body.attachments = self.attachments(account, mailbox, uid)?;
        Ok(Some(body))
    }

    /// Whether the account's server vouched for the sender of a cached
    /// message.
    pub fn sender_verified(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT verified FROM message_body
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get(0),
            )
            .optional()?
            .unwrap_or(false))
    }

    /// Whether a cached message's sender isn't who they say, as on
    /// `ProtectionToApprove` section 2: its domain failed DMARC, imitates
    /// a domain the person gets verified mail from, or its name claims a
    /// company it doesn't send for. Addresses and domains the person has
    /// written to never imitate or borrow anything. None until the body
    /// is kept, and for every other sender.
    pub fn sender_warning(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<Option<SenderWarning>> {
        let found = self
            .conn
            .query_row(
                "SELECT m.from_name, lower(m.from_email), m.subject, b.text,
                        COALESCE(s.dmarc_failed, 0), COALESCE(s.signed_by, ''), COALESCE(s.sent_by, '')
                 FROM message m
                 JOIN message_body b
                   ON b.account = m.account AND b.mailbox = m.mailbox AND b.uid = m.uid
                 LEFT JOIN sender_check s
                   ON s.account = m.account AND s.mailbox = m.mailbox AND s.uid = m.uid
                 WHERE m.account = ?1 AND m.mailbox = ?2 AND m.uid = ?3",
                params![account.0, mailbox, uid],
                |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, String>(2)?,
                        r.get::<_, String>(3)?,
                        r.get::<_, bool>(4)?,
                        r.get::<_, String>(5)?,
                        r.get::<_, String>(6)?,
                    ))
                },
            )
            .optional()?;
        let Some((name, email, subject, text, dmarc_failed, signed_by, sent_by)) = found else {
            return Ok(None);
        };
        let Some((_, domain)) = email.rsplit_once('@') else {
            return Ok(None);
        };
        let domain = domain.trim().to_owned();
        let org = crate::sender_auth::organization(&domain);
        let mut kind = None;
        if !self.wrote_to(&email, &org)? {
            let known = self.known_domains()?;
            if let Some((like, count)) = crate::impostor::looks_like(&domain, &known) {
                kind = Some(WarningKind::LooksLike { like, count });
            } else if let Some(brand) =
                crate::impostor::claimed_brand_in_message(&name, &subject, &text, &domain)
            {
                kind = Some(WarningKind::Brand {
                    brand: brand.to_owned(),
                });
            }
        }
        if kind.is_none() && dmarc_failed {
            kind = Some(WarningKind::DmarcFailed);
        }
        let none = |s: String| (!s.is_empty()).then_some(s);
        Ok(kind.map(|kind| SenderWarning {
            kind,
            domain,
            dmarc_failed,
            signed_by: none(signed_by),
            sent_by: none(sent_by),
        }))
    }

    /// Whether `email` is one of the person's own addresses (an account or
    /// an alias) or one they have written to: never a machine, whatever
    /// its mail looks like.
    pub fn known_person(&self, email: &str) -> Result<bool> {
        Ok(self.conn.query_row(
            "SELECT EXISTS (SELECT 1 FROM written_to WHERE email = ?1)
                 OR EXISTS (SELECT 1 FROM account WHERE lower(email) = ?1)
                 OR EXISTS (SELECT 1 FROM account_alias WHERE lower(email) = ?1)",
            [email.trim().to_lowercase()],
            |r| r.get(0),
        )?)
    }

    /// Whether a stored message counts as written by a person whatever its
    /// headers say: from a [`Store::known_person`], or in a conversation
    /// the person replied to, unless it is list mail or comes from a
    /// no-reply or bounce address, as the People list does.
    pub fn person_wrote(&self, m: &MessageSummary) -> Result<bool> {
        if self.known_person(&m.from_email)? {
            return Ok(true);
        }
        if !m.list.unsubscribe.is_empty() || no_reply_address(&m.from_email) {
            return Ok(false);
        }
        Ok(self.conn.query_row(
            "SELECT EXISTS (SELECT 1 FROM message m JOIN message s
                 ON s.account = m.account AND s.thread = m.thread AND s.folder = 'sent'
                 WHERE m.account = ?1 AND m.mailbox = ?2 AND m.uid = ?3 AND m.thread <> '')",
            params![m.account.0, m.mailbox, m.uid],
            |r| r.get(0),
        )?)
    }

    /// Whether the person has written to this address, or to anyone at
    /// its organization's domain (not a shared one such as gmail.com), or
    /// sends from it.
    fn wrote_to(&self, email: &str, org: &str) -> Result<bool> {
        let own: bool = self.conn.query_row(
            "SELECT EXISTS (SELECT 1 FROM account WHERE lower(email) = ?1)
                 OR EXISTS (SELECT 1 FROM account_alias WHERE lower(email) = ?1)",
            [email],
            |r| r.get(0),
        )?;
        if own {
            return Ok(true);
        }
        let mut stmt = self.conn.prepare(
            "SELECT recipients FROM message WHERE folder = 'sent' AND hidden = 0
             ORDER BY received_at DESC LIMIT 5000",
        )?;
        let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
        for row in rows {
            for to in row?.split_whitespace() {
                let to = to.to_lowercase();
                let to_org = to
                    .rsplit_once('@')
                    .map(|(_, d)| crate::sender_auth::organization(d));
                let same_org = !crate::impostor::shared(org) && to_org.as_deref() == Some(org);
                if to == email || same_org {
                    return Ok(true);
                }
            }
        }
        Ok(false)
    }

    /// The organizations' domains the person gets verified mail from, with
    /// how many emails came from each.
    fn known_domains(&self) -> Result<Vec<(String, u32)>> {
        let mut counts: HashMap<String, (u32, bool)> = HashMap::new();
        let mut stmt = self.conn.prepare(
            "SELECT lower(m.from_email), COUNT(*), MAX(COALESCE(b.verified, 0))
             FROM message m LEFT JOIN message_body b
               ON b.account = m.account AND b.mailbox = m.mailbox AND b.uid = m.uid
             WHERE m.hidden = 0 AND m.from_email != ''
             GROUP BY lower(m.from_email)",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, u32>(1)?,
                r.get::<_, bool>(2)?,
            ))
        })?;
        for row in rows {
            let (email, n, verified) = row?;
            let Some((_, domain)) = email.rsplit_once('@') else {
                continue;
            };
            let entry = counts
                .entry(crate::sender_auth::organization(domain.trim()))
                .or_default();
            entry.0 += n;
            entry.1 |= verified;
        }
        let mut known: Vec<(String, u32)> = counts
            .into_iter()
            .filter(|(_, (_, verified))| *verified)
            .map(|(d, (n, _))| (d, n))
            .collect();
        // The busiest first: the one a look-alike most likely means.
        known.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        Ok(known)
    }

    /// A picture inside a cached message, by its Content-ID.
    pub fn inline_image(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        cid: &str,
    ) -> Result<Option<Vec<u8>>> {
        Ok(self
            .conn
            .query_row(
                "SELECT data FROM inline_image
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND cid = ?4",
                params![account.0, mailbox, uid, cid],
                |r| r.get(0),
            )
            .optional()?)
    }

    /// The files attached to a cached message, in message order.
    pub fn attachments(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
    ) -> Result<Vec<Attachment>> {
        let mut stmt = self.conn.prepare(
            "SELECT part, name, mime, size, section, encoding FROM attachment
             WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 ORDER BY part",
        )?;
        let rows = stmt.query_map(params![account.0, mailbox, uid], |r| {
            row_to_attachment(r, 0)
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// One file attached to a message, as listed.
    pub fn attachment(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        part: u32,
    ) -> Result<Option<Attachment>> {
        Ok(self
            .conn
            .query_row(
                "SELECT part, name, mime, size, section, encoding FROM attachment
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND part = ?4",
                params![account.0, mailbox, uid, part],
                |r| row_to_attachment(r, 0),
            )
            .optional()?)
    }

    /// Caches a plain-text body.
    pub fn set_body(&self, account: AccountId, mailbox: &str, uid: u32, text: &str) -> Result<()> {
        self.set_full_body(
            account,
            mailbox,
            uid,
            &Body {
                text: text.to_owned(),
                ..Body::default()
            },
        )
    }

    pub fn set_full_body(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        body: &Body,
    ) -> Result<()> {
        let (verified, checked) = match self.account(account)? {
            Some(a) => {
                let trust = crate::sender_auth::Trust::for_account(&a);
                (
                    crate::sender_auth::verified(&body.auth, &trust),
                    crate::sender_auth::checked(&body.auth, &trust),
                )
            }
            None => (false, Default::default()),
        };
        let tx = self.conn.unchecked_transaction()?;
        tx.execute(
            "INSERT OR REPLACE INTO message_body
                 (account, mailbox, uid, text, html, format, calendar, verified)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                account.0,
                mailbox,
                uid,
                body.text,
                body.html,
                if body.html.is_some() { 2 } else { 1 },
                body.calendar,
                verified,
            ],
        )?;
        tx.execute(
            "INSERT OR REPLACE INTO sender_check (account, mailbox, uid, dmarc_failed, signed_by, sent_by)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                account.0,
                mailbox,
                uid,
                checked.dmarc_failed,
                checked.signed_by.unwrap_or_default(),
                checked.sent_by.unwrap_or_default(),
            ],
        )?;
        tx.execute(
            "DELETE FROM inline_image WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            params![account.0, mailbox, uid],
        )?;
        for image in &body.inline {
            tx.execute(
                "INSERT OR REPLACE INTO inline_image (account, mailbox, uid, cid, mime, data)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![account.0, mailbox, uid, image.cid, image.mime, image.data],
            )?;
        }
        // The whole body makes the preview the reader would: a message
        // listed without one gets it, one listed from a cut part is mended.
        let preview = crate::imap::reader_preview(&body.text, body.html.as_deref());
        if !preview.is_empty() {
            tx.execute(
                "UPDATE message SET preview = ?4
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND preview != ?4",
                params![account.0, mailbox, uid, preview],
            )?;
        }
        // A newsletter's reading time.
        let newsletter: bool = tx
            .query_row(
                "SELECT newsletter FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get(0),
            )
            .optional()?
            .unwrap_or(false);
        if newsletter {
            tx.execute(
                "UPDATE message SET words = ?4 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![
                    account.0,
                    mailbox,
                    uid,
                    crate::newsletter::words(&body.text, body.html.as_deref())
                ],
            )?;
        }
        file_card(&tx, account, mailbox, uid, body)?;
        // Where the server's outline listed a file, it keeps the address
        // to fetch it alone.
        let outlined: Vec<(String, String, String, Option<String>)> = {
            let mut stmt = tx.prepare(
                "SELECT name, mime, section, encoding FROM attachment
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND section IS NOT NULL",
            )?;
            let rows = stmt.query_map(params![account.0, mailbox, uid], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))
            })?;
            rows.collect::<std::result::Result<_, _>>()?
        };
        tx.execute(
            "DELETE FROM attachment WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            params![account.0, mailbox, uid],
        )?;
        tx.execute(
            "UPDATE message SET files_checked = 1 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            params![account.0, mailbox, uid],
        )?;
        for a in &body.attachments {
            let (section, encoding) = outlined
                .iter()
                .find(|(name, mime, _, _)| *name == a.name && *mime == a.mime)
                .map(|(_, _, s, e)| (Some(s.as_str()), e.as_deref()))
                .unwrap_or_default();
            tx.execute(
                "INSERT INTO attachment (account, mailbox, uid, part, name, mime, size, section, encoding)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                params![
                    account.0,
                    mailbox,
                    uid,
                    a.part,
                    a.name,
                    a.mime,
                    a.size as i64,
                    section,
                    encoding
                ],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn is_trusted(&self, email: &str) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT 1 FROM trusted_sender WHERE email = ?1",
                params![email.trim()],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }

    pub fn is_blocked(&self, email: &str) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT 1 FROM blocked_sender WHERE email = ?1",
                params![email.trim()],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }

    pub fn is_muted(&self, email: &str) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT 1 FROM muted_sender WHERE email = ?1",
                params![email.trim()],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }

    /// Every rule, oldest first: the order they are tried in.
    pub fn rules(&self) -> Result<Vec<Rule>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, account, field, op, value, action, target, enabled, last_run, matched
             FROM rule ORDER BY id",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, i64>(0)?,
                r.get::<_, Option<i64>>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, String>(5)?,
                r.get::<_, String>(6)?,
                r.get::<_, bool>(7)?,
                r.get::<_, Option<i64>>(8)?,
                r.get::<_, u32>(9)?,
            ))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (id, account, field, op, value, action, target, enabled, last_run, matched) = row?;
            // A rule this version cannot read is left alone, not dropped.
            let (Some(field), Some(op), Some(action)) = (
                RuleField::from_tag(&field),
                RuleOp::from_tag(&op),
                RuleAction::from_tag(&action, target),
            ) else {
                continue;
            };
            out.push(Rule {
                id,
                account: account.map(AccountId),
                field,
                op,
                value,
                action,
                enabled,
                last_run,
                matched,
            });
        }
        Ok(out)
    }

    /// Adds `rule` (its id 0) or changes the one with its id. Returns the id.
    pub fn save_rule(&self, rule: &Rule) -> Result<i64> {
        let account = rule.account.map(|a| a.0);
        if rule.id == 0 {
            self.conn.execute(
                "INSERT INTO rule (account, field, op, value, action, target, enabled, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                params![
                    account,
                    rule.field.tag(),
                    rule.op.tag(),
                    rule.value.trim(),
                    rule.action.tag(),
                    rule.action.target(),
                    rule.enabled,
                    crate::pending::now(),
                ],
            )?;
            return Ok(self.conn.last_insert_rowid());
        }
        self.conn.execute(
            "UPDATE rule SET account = ?2, field = ?3, op = ?4, value = ?5, action = ?6,
                    target = ?7, enabled = ?8
             WHERE id = ?1",
            params![
                rule.id,
                account,
                rule.field.tag(),
                rule.op.tag(),
                rule.value.trim(),
                rule.action.tag(),
                rule.action.target(),
                rule.enabled,
            ],
        )?;
        Ok(rule.id)
    }

    pub fn delete_rule(&self, id: i64) -> Result<()> {
        self.conn
            .execute("DELETE FROM rule WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn set_rule_enabled(&self, id: i64, enabled: bool) -> Result<()> {
        self.conn.execute(
            "UPDATE rule SET enabled = ?2 WHERE id = ?1",
            params![id, enabled],
        )?;
        Ok(())
    }

    /// Notes that the person moved mail from these senders (address,
    /// name) to `target`, one of the account's own folders, at `now`.
    pub fn log_moves(
        &self,
        account: AccountId,
        senders: &[(String, String)],
        target: &str,
        now: i64,
    ) -> Result<()> {
        self.conn.execute(
            "DELETE FROM move_log WHERE at < ?1",
            params![now - MOVE_LOG_DAYS * 86_400],
        )?;
        let mut insert = self.conn.prepare_cached(
            "INSERT INTO move_log (account, sender, name, target, at)
             VALUES (?1, lower(?2), ?3, ?4, ?5)",
        )?;
        for (email, name) in senders {
            if !email.trim().is_empty() {
                insert.execute(params![account.0, email.trim(), name, target, now])?;
            }
        }
        Ok(())
    }

    /// Who was moved where by hand since `since`, most moves first: each
    /// account, sender and folder with the sender's latest name and the
    /// count, when there were at least `least`.
    pub fn frequent_moves(&self, since: i64, least: u32) -> Result<Vec<FrequentMove>> {
        let mut stmt = self.conn.prepare(
            "SELECT m.account, m.sender,
                    (SELECT name FROM move_log n
                     WHERE n.account = m.account AND n.sender = m.sender
                     ORDER BY n.at DESC LIMIT 1),
                    m.target, COUNT(*) AS moves
             FROM move_log m WHERE m.at >= ?1
             GROUP BY m.account, m.sender, m.target HAVING moves >= ?2
             ORDER BY moves DESC, MAX(m.at) DESC",
        )?;
        let rows = stmt.query_map(params![since, least], |r| {
            Ok(FrequentMove {
                account: AccountId(r.get(0)?),
                sender: r.get(1)?,
                name: r.get(2)?,
                target: r.get(3)?,
                moves: r.get(4)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Counts `n` more emails sorted by rule `id`, at `now`.
    pub fn rule_ran(&self, id: i64, n: u32, now: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE rule SET matched = matched + ?2, last_run = ?3 WHERE id = ?1",
            params![id, n, now],
        )?;
        Ok(())
    }

    /// When the newest message of an account's mailbox arrived.
    pub fn newest_received(&self, account: AccountId, mailbox: &str) -> Result<Option<i64>> {
        Ok(self.conn.query_row(
            "SELECT MAX(received_at) FROM message WHERE account = ?1 AND mailbox = ?2",
            params![account.0, mailbox],
            |r| r.get(0),
        )?)
    }

    /// The visible mail of an account's mailbox that arrived after `since`,
    /// oldest first.
    pub fn received_since(
        &self,
        account: AccountId,
        mailbox: &str,
        since: i64,
    ) -> Result<Vec<MessageSummary>> {
        let mut stmt = self.conn.prepare(
            "SELECT account, mailbox, uid, from_name, from_email, subject, preview, received_at, flags,
                    message_id, refs, reply_to, to_list
             FROM message
             WHERE account = ?1 AND mailbox = ?2 AND hidden = 0 AND received_at > ?3
             ORDER BY received_at, uid",
        )?;
        let rows = stmt.query_map(params![account.0, mailbox, since], row_to_summary)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// The visible mail of `mailbox` in every account, newest first.
    pub fn inbox_all(&self, mailbox: &str) -> Result<Vec<MessageSummary>> {
        let mut stmt = self.conn.prepare(
            "SELECT account, mailbox, uid, from_name, from_email, subject, preview, received_at, flags,
                    message_id, refs, reply_to, to_list
             FROM message
             WHERE mailbox = ?1 AND hidden = 0
             ORDER BY received_at DESC, account, uid DESC",
        )?;
        let rows = stmt.query_map(params![mailbox], row_to_summary)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// How an invite was answered here, by its event's UID: the answer,
    /// and the invite's SEQUENCE then.
    pub fn invite_answer(&self, account: AccountId, event: &str) -> Result<Option<(String, u32)>> {
        Ok(self
            .conn
            .query_row(
                "SELECT answer, sequence FROM invite_answer WHERE account = ?1 AND event = ?2",
                params![account.0, event],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?)
    }

    pub fn set_invite_answer(
        &self,
        account: AccountId,
        event: &str,
        answer: &str,
        sequence: u32,
        at: i64,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO invite_answer (account, event, answer, sequence, at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![account.0, event, answer, sequence, at],
        )?;
        Ok(())
    }

    /// Stops notifications for a sender's new mail, or lets them come.
    pub fn set_muted(&self, email: &str, muted: bool) -> Result<()> {
        let email = email.trim();
        if muted {
            self.conn.execute(
                "INSERT OR IGNORE INTO muted_sender (email) VALUES (?1)",
                params![email],
            )?;
        } else {
            self.conn
                .execute("DELETE FROM muted_sender WHERE email = ?1", params![email])?;
        }
        Ok(())
    }

    /// Sends a sender's new mail straight to Trash, or stops.
    pub fn set_blocked(&self, email: &str, blocked: bool) -> Result<()> {
        let email = email.trim();
        if blocked {
            self.conn.execute(
                "INSERT OR IGNORE INTO blocked_sender (email) VALUES (?1)",
                params![email],
            )?;
        } else {
            self.conn.execute(
                "DELETE FROM blocked_sender WHERE email = ?1",
                params![email],
            )?;
        }
        Ok(())
    }

    /// Trusts a sender's remote images, or stops trusting them.
    pub fn set_trusted(&self, email: &str, trusted: bool, now: i64) -> Result<()> {
        let email = email.trim();
        if trusted {
            self.conn.execute(
                "INSERT OR IGNORE INTO trusted_sender (email, added_at) VALUES (?1, ?2)",
                params![email, now],
            )?;
        } else {
            self.conn.execute(
                "DELETE FROM trusted_sender WHERE email = ?1",
                params![email],
            )?;
        }
        Ok(())
    }

    /// Trusted senders, most recent first, with the name they last wrote
    /// with.
    pub fn trusted_senders(&self) -> Result<Vec<TrustedSender>> {
        let mut stmt = self.conn.prepare(
            "SELECT t.email, t.added_at,
                    COALESCE((SELECT m.from_name FROM message m
                              WHERE lower(m.from_email) = lower(t.email) AND m.from_name <> ''
                              ORDER BY m.received_at DESC LIMIT 1), '')
             FROM trusted_sender t ORDER BY t.added_at DESC, t.email",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(TrustedSender {
                email: r.get(0)?,
                since: r.get(1)?,
                name: r.get(2)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Every signature, by account and then in the order they were made.
    pub fn signatures(&self) -> Result<Vec<Signature>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, account, label, template, name, role, company, phone, website,
                    accent, logo_mime, logo, for_new, for_replies
             FROM signature ORDER BY account, id",
        )?;
        let rows = stmt.query_map([], |r| {
            let mime: Option<String> = r.get(10)?;
            let data: Option<Vec<u8>> = r.get(11)?;
            Ok(Signature {
                id: r.get(0)?,
                account: AccountId(r.get(1)?),
                label: r.get(2)?,
                template: Template::from_tag(&r.get::<_, String>(3)?),
                name: r.get(4)?,
                role: r.get(5)?,
                company: r.get(6)?,
                phone: r.get(7)?,
                website: r.get(8)?,
                accent: Accent::from_tag(&r.get::<_, String>(9)?),
                logo: match (mime, data) {
                    (Some(mime), Some(data)) => Some(Logo { mime, data }),
                    _ => None,
                },
                for_new: r.get(12)?,
                for_replies: r.get(13)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Stores a signature, new when its id is 0, and returns its id. When
    /// it becomes the account's signature for new emails or for replies,
    /// the one that had that job loses it.
    pub fn save_signature(&mut self, s: &Signature) -> Result<i64> {
        let tx = self.conn.transaction()?;
        let (mime, data) = match &s.logo {
            Some(l) => (Some(l.mime.as_str()), Some(l.data.as_slice())),
            None => (None, None),
        };
        let id = if s.id == 0 {
            tx.execute(
                "INSERT INTO signature (account, label, template, name, role, company, phone,
                                        website, accent, logo_mime, logo, for_new, for_replies)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
                params![
                    s.account.0,
                    s.label,
                    s.template.tag(),
                    s.name,
                    s.role,
                    s.company,
                    s.phone,
                    s.website,
                    s.accent.tag(),
                    mime,
                    data,
                    s.for_new,
                    s.for_replies
                ],
            )?;
            tx.last_insert_rowid()
        } else {
            tx.execute(
                "UPDATE signature SET account = ?2, label = ?3, template = ?4, name = ?5,
                        role = ?6, company = ?7, phone = ?8, website = ?9, accent = ?10,
                        logo_mime = ?11, logo = ?12, for_new = ?13, for_replies = ?14
                 WHERE id = ?1",
                params![
                    s.id,
                    s.account.0,
                    s.label,
                    s.template.tag(),
                    s.name,
                    s.role,
                    s.company,
                    s.phone,
                    s.website,
                    s.accent.tag(),
                    mime,
                    data,
                    s.for_new,
                    s.for_replies
                ],
            )?;
            s.id
        };
        if s.for_new {
            tx.execute(
                "UPDATE signature SET for_new = 0 WHERE account = ?1 AND id <> ?2",
                params![s.account.0, id],
            )?;
        }
        if s.for_replies {
            tx.execute(
                "UPDATE signature SET for_replies = 0 WHERE account = ?1 AND id <> ?2",
                params![s.account.0, id],
            )?;
        }
        tx.commit()?;
        Ok(id)
    }

    pub fn delete_signature(&self, id: i64) -> Result<()> {
        self.conn
            .execute("DELETE FROM signature WHERE id = ?1", params![id])?;
        Ok(())
    }

    /// Keeps a message to send once the server can be reached. Returns
    /// its id in the outbox.
    pub fn queue_outgoing(&self, out: &Outgoing, queued_at: i64) -> Result<i64> {
        let json = |v: &Vec<String>| serde_json::to_string(v).unwrap_or_default();
        let d = &out.draft;
        let tx = self.conn.unchecked_transaction()?;
        tx.execute(
            "INSERT INTO outbox (account, from_name, from_email, to_list, cc_list, bcc_list,
                 subject, body, in_reply_to, refs, signature, message_id, mail_from,
                 recipients, raw, saved_mailbox, saved_uid, queued_at, send_at, marks)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16,
                 ?17, ?18, ?19, ?20)",
            params![
                out.account.0,
                d.from_name,
                d.from_email,
                json(&d.to),
                json(&d.cc),
                json(&d.bcc),
                d.subject,
                d.body,
                d.in_reply_to,
                json(&d.references),
                d.signature.as_ref().map(|s| s.id),
                out.ready.message_id,
                out.ready.from,
                json(&out.ready.recipients),
                out.ready.raw,
                out.saved.as_ref().map(|s| s.0.as_str()),
                out.saved.as_ref().map(|s| s.1),
                queued_at,
                out.send_at,
                crate::rich::encode(&d.marks).unwrap_or_default(),
            ],
        )?;
        let id = tx.last_insert_rowid();
        for (i, f) in d.files.iter().enumerate() {
            tx.execute(
                "INSERT INTO outbox_file (outbox, position, name, mime, data)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![id, i as i64, f.name, f.mime, f.data],
            )?;
        }
        tx.commit()?;
        Ok(id)
    }

    /// The outbox, oldest first: one account's, or every account's.
    pub fn outbox(&self, account: Option<AccountId>) -> Result<Vec<Waiting>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, account, to_list, subject, body, queued_at, error, send_at FROM outbox
              WHERE ?1 IS NULL OR account = ?1 ORDER BY id",
        )?;
        let rows = stmt.query_map(params![account.map(|a| a.0)], |r| {
            Ok(Waiting {
                id: r.get(0)?,
                account: AccountId(r.get(1)?),
                to: list(&r.get::<_, String>(2)?),
                subject: r.get(3)?,
                body: r.get(4)?,
                queued_at: r.get(5)?,
                error: r.get(6)?,
                send_at: r.get(7)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// A message in the outbox, whole, with its files and signature.
    pub fn outgoing(&self, id: i64) -> Result<Option<Outgoing>> {
        let row = self
            .conn
            .query_row(
                "SELECT account, from_name, from_email, to_list, cc_list, bcc_list, subject,
                        body, in_reply_to, refs, signature, message_id, mail_from,
                        recipients, raw, saved_mailbox, saved_uid, send_at, marks
                   FROM outbox WHERE id = ?1",
                params![id],
                |r| {
                    let saved = match (r.get::<_, Option<String>>(15)?, r.get(16)?) {
                        (Some(mailbox), Some(uid)) => Some((mailbox, uid)),
                        _ => None,
                    };
                    Ok((
                        AccountId(r.get(0)?),
                        Draft {
                            from_name: r.get(1)?,
                            from_email: r.get(2)?,
                            to: list(&r.get::<_, String>(3)?),
                            cc: list(&r.get::<_, String>(4)?),
                            bcc: list(&r.get::<_, String>(5)?),
                            subject: r.get(6)?,
                            body: r.get(7)?,
                            in_reply_to: r.get(8)?,
                            references: list(&r.get::<_, String>(9)?),
                            marks: crate::rich::decode(&r.get::<_, String>(18)?),
                            ..Draft::default()
                        },
                        r.get::<_, Option<i64>>(10)?,
                        Ready {
                            message_id: r.get(11)?,
                            from: r.get(12)?,
                            recipients: list(&r.get::<_, String>(13)?),
                            raw: r.get(14)?,
                        },
                        saved,
                        r.get::<_, Option<i64>>(17)?,
                    ))
                },
            )
            .optional()?;
        let Some((account, mut draft, signature, ready, saved, send_at)) = row else {
            return Ok(None);
        };
        let mut stmt = self.conn.prepare(
            "SELECT name, mime, data FROM outbox_file WHERE outbox = ?1 ORDER BY position",
        )?;
        draft.files = stmt
            .query_map(params![id], |r| {
                Ok(OutgoingFile {
                    name: r.get(0)?,
                    mime: r.get(1)?,
                    data: r.get(2)?,
                })
            })?
            .collect::<std::result::Result<_, _>>()?;
        if let Some(sid) = signature {
            draft.signature = self.signature(sid)?;
        }
        draft.date = send_at;
        Ok(Some(Outgoing {
            account,
            draft,
            ready,
            saved,
            send_at,
        }))
    }

    /// Takes a message out of the outbox: sent, or taken back to edit.
    /// Keeps a draft on this device until its server can be reached, in
    /// place of the waiting draft [replace] when given (whose server copy
    /// it then keeps replacing). Returns its id.
    pub fn keep_waiting_draft(
        &self,
        draft: &WaitingDraft,
        replace: Option<i64>,
        now: i64,
    ) -> Result<i64> {
        let (ea, em, eu) = match &draft.earlier {
            Some((a, m, u)) => (Some(a.0), Some(m.as_str()), Some(*u)),
            None => (None, None, None),
        };
        if let Some(id) = replace {
            let changed = self.conn.execute(
                "UPDATE draft_waiting SET raw = ?2, message_id = ?3, signature = ?4, saved_at = ?5
                  WHERE id = ?1",
                params![id, draft.raw, draft.message_id, draft.signature, now],
            )?;
            if changed > 0 {
                return Ok(id);
            }
        }
        self.conn.execute(
            "INSERT INTO draft_waiting (account, raw, message_id, earlier_account, earlier_mailbox,
                                        earlier_uid, signature, saved_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                draft.account.0,
                draft.raw,
                draft.message_id,
                ea,
                em,
                eu,
                draft.signature,
                now
            ],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// One draft waiting on this device.
    pub fn waiting_draft(&self, id: i64) -> Result<Option<WaitingDraft>> {
        Ok(self.waiting_drafts_where("id = ?1", id)?.pop())
    }

    /// An account's drafts waiting on this device, oldest first.
    pub fn waiting_drafts(&self, account: AccountId) -> Result<Vec<WaitingDraft>> {
        self.waiting_drafts_where("account = ?1", account.0)
    }

    fn waiting_drafts_where(&self, filter: &str, value: i64) -> Result<Vec<WaitingDraft>> {
        let mut stmt = self.conn.prepare(&format!(
            "SELECT id, account, raw, message_id, earlier_account, earlier_mailbox, earlier_uid,
                    signature
               FROM draft_waiting WHERE {filter} ORDER BY id"
        ))?;
        let rows = stmt.query_map(params![value], |r| {
            let earlier = match (
                r.get::<_, Option<i64>>(4)?,
                r.get::<_, Option<String>>(5)?,
                r.get::<_, Option<u32>>(6)?,
            ) {
                (Some(a), Some(m), Some(u)) => Some((AccountId(a), m, u)),
                _ => None,
            };
            Ok(WaitingDraft {
                id: r.get(0)?,
                account: AccountId(r.get(1)?),
                raw: r.get(2)?,
                message_id: r.get(3)?,
                earlier,
                signature: r.get(7)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Every template, the ones used last first, then by name.
    pub fn message_templates(&self) -> Result<Vec<MessageTemplate>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT id, name, subject, body FROM message_template
             ORDER BY used_at DESC, name COLLATE NOCASE, id",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(MessageTemplate {
                id: r.get(0)?,
                name: r.get(1)?,
                subject: r.get(2)?,
                body: r.get(3)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Keeps a template, a new one when its id is 0. Returns its id.
    pub fn save_message_template(&self, t: &MessageTemplate) -> Result<i64> {
        if t.id != 0 {
            let changed = self.conn.execute(
                "UPDATE message_template SET name = ?2, subject = ?3, body = ?4 WHERE id = ?1",
                params![t.id, t.name, t.subject, t.body],
            )?;
            if changed > 0 {
                return Ok(t.id);
            }
        }
        self.conn.execute(
            "INSERT INTO message_template (name, subject, body) VALUES (?1, ?2, ?3)",
            params![t.name, t.subject, t.body],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn delete_message_template(&self, id: i64) -> Result<()> {
        self.conn
            .execute("DELETE FROM message_template WHERE id = ?1", params![id])?;
        Ok(())
    }

    /// Notes that a template was just put in a message, so it lists first.
    pub fn message_template_used(&self, id: i64, now: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE message_template SET used_at = ?2 WHERE id = ?1",
            params![id, now],
        )?;
        Ok(())
    }

    /// Forgets a draft that waited on this device.
    pub fn drop_waiting_draft(&self, id: i64) -> Result<()> {
        self.conn
            .execute("DELETE FROM draft_waiting WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn drop_outgoing(&self, id: i64) -> Result<()> {
        self.conn
            .execute("DELETE FROM outbox WHERE id = ?1", params![id])?;
        Ok(())
    }

    /// Keeps why the server refused a message; it stays until the person
    /// opens or deletes it.
    pub fn refused_outgoing(&self, id: i64, reason: &str) -> Result<()> {
        self.conn.execute(
            "UPDATE outbox SET error = ?2 WHERE id = ?1",
            params![id, reason],
        )?;
        Ok(())
    }

    pub fn signature(&self, id: i64) -> Result<Option<Signature>> {
        Ok(self.signatures()?.into_iter().find(|s| s.id == id))
    }

    pub fn add_calendar_source(
        &self,
        kind: &str,
        name: &str,
        url: &str,
        username: &str,
        account: Option<AccountId>,
    ) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO calendar_source (kind, name, url, username, account)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![kind, name, url, username, account.map(|a| a.0)],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn calendar_sources(&self) -> Result<Vec<CalendarSource>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, kind, name, url, username, account, synced, every
             FROM calendar_source LEFT JOIN calendar_refresh ON source = id
             ORDER BY id",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(CalendarSource {
                id: r.get(0)?,
                kind: r.get(1)?,
                name: r.get(2)?,
                url: r.get(3)?,
                username: r.get(4)?,
                account: r.get::<_, Option<i64>>(5)?.map(AccountId),
                synced: r.get(6)?,
                refresh: r.get(7)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn delete_calendar_source(&self, id: i64) -> Result<()> {
        self.conn
            .execute("DELETE FROM calendar_source WHERE id = ?1", params![id])?;
        Ok(())
    }

    /// Keeps a source's calendars as the server lists them now: new ones
    /// are added, gone ones forgotten, the availability switch kept.
    pub fn set_calendars(
        &mut self,
        source: i64,
        calendars: &[crate::calendar::RemoteCalendar],
    ) -> Result<()> {
        let tx = self.conn.transaction()?;
        for c in calendars {
            tx.execute(
                "INSERT INTO calendar (source, url, name, color, read_only) VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT (source, url) DO UPDATE SET
                     name = excluded.name, color = excluded.color, read_only = excluded.read_only",
                params![source, c.url, c.name, c.color, c.read_only],
            )?;
        }
        let keep: Vec<&str> = calendars.iter().map(|c| c.url.as_str()).collect();
        let ids: Vec<(i64, String)> = {
            let mut stmt = tx.prepare("SELECT id, url FROM calendar WHERE source = ?1")?;
            let rows = stmt.query_map(params![source], |r| Ok((r.get(0)?, r.get(1)?)))?;
            rows.collect::<rusqlite::Result<_>>()?
        };
        for (id, url) in ids {
            if !keep.contains(&url.as_str()) {
                tx.execute("DELETE FROM calendar WHERE id = ?1", params![id])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Every connected calendar, by source, in the order they came.
    pub fn calendars(&self) -> Result<Vec<CalendarRow>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, source, url, name, color, read_only, availability FROM calendar ORDER BY source, id",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(CalendarRow {
                id: r.get(0)?,
                source: r.get(1)?,
                url: r.get(2)?,
                name: r.get(3)?,
                color: r.get(4)?,
                read_only: r.get(5)?,
                availability: r.get(6)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn set_calendar_availability(&self, id: i64, on: bool) -> Result<()> {
        self.conn.execute(
            "UPDATE calendar SET availability = ?2 WHERE id = ?1",
            params![id, on],
        )?;
        Ok(())
    }

    /// Replaces what a calendar holds; events marked free are not kept.
    pub fn set_calendar_events(
        &mut self,
        calendar: i64,
        events: &[crate::invite::Invite],
    ) -> Result<()> {
        let tx = self.conn.transaction()?;
        tx.execute(
            "DELETE FROM calendar_event WHERE calendar = ?1",
            params![calendar],
        )?;
        for e in events.iter().filter(|e| !e.transparent) {
            tx.execute(
                "INSERT INTO calendar_event (calendar, uid, start, end, all_day, floating, summary)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![calendar, e.uid, e.start, e.end, e.all_day, e.floating, e.summary],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn set_calendar_synced(&self, source: i64, at: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE calendar_source SET synced = ?2 WHERE id = ?1",
            params![source, at],
        )?;
        Ok(())
    }

    /// Keeps how often a feed asks to be read again; None forgets it.
    pub fn set_calendar_refresh(&self, source: i64, every: Option<i64>) -> Result<()> {
        match every {
            Some(every) => self.conn.execute(
                "INSERT INTO calendar_refresh (source, every) VALUES (?1, ?2)
                 ON CONFLICT (source) DO UPDATE SET every = excluded.every",
                params![source, every],
            )?,
            None => self.conn.execute(
                "DELETE FROM calendar_refresh WHERE source = ?1",
                params![source],
            )?,
        };
        Ok(())
    }

    /// The calendar a day found in a message went to, by its event uid.
    pub fn found_date(&self, uid: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row(
                "SELECT calendar FROM found_date WHERE uid = ?1",
                params![uid],
                |r| r.get(0),
            )
            .optional()?)
    }

    pub fn set_found_date(&self, uid: &str, calendar: &str, at: i64) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO found_date (uid, calendar, added) VALUES (?1, ?2, ?3)",
            params![uid, calendar, at],
        )?;
        Ok(())
    }

    /// Marks a Vault notice given; false when it already was.
    pub fn take_vault_notice(&self, key: &str, tag: &str, at: i64) -> Result<bool> {
        Ok(self.conn.execute(
            "INSERT OR IGNORE INTO vault_notice (key, tag, at) VALUES (?1, ?2, ?3)",
            params![key, tag, at],
        )? == 1)
    }

    /// The newest messages from a sender, across accounts, newest first.
    pub fn from_sender(&self, email: &str, limit: u32) -> Result<Vec<MessageSummary>> {
        let mut stmt = self.conn.prepare(
            "SELECT account, mailbox, uid, from_name, from_email, subject, preview, received_at, flags,
                message_id, refs, reply_to, to_list
             FROM message WHERE lower(from_email) = lower(?1) AND hidden = 0
             ORDER BY received_at DESC LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![email.trim(), limit], row_to_summary)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Whether a person wrote this message, as the People tab judges:
    /// no list, newsletter, Vault mail or machine address.
    pub fn by_person(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<bool> {
        Ok(self.conn.query_row(
            &format!(
                "SELECT EXISTS (SELECT 1 FROM message m
                 WHERE m.account = ?1 AND m.mailbox = ?2 AND m.uid = ?3 AND {PEOPLE})"
            ),
            params![account.0, mailbox, uid],
            |r| r.get(0),
        )?)
    }

    /// How much a sender writes since `since`: (emails, of which opened),
    /// and whether their mail goes to Newsletters.
    pub fn sender_stats(&self, email: &str, since: i64) -> Result<(u32, u32, bool)> {
        Ok(self.conn.query_row(
            "SELECT
                COUNT(*) FILTER (WHERE received_at >= ?2),
                COUNT(*) FILTER (WHERE received_at >= ?2 AND (flags & 1) = 1),
                EXISTS (SELECT 1 FROM message WHERE lower(from_email) = lower(?1)
                        AND folder = 'newsletters' AND hidden = 0)
             FROM message
             WHERE lower(from_email) = lower(?1) AND hidden = 0
               AND folder NOT IN ('sent', 'drafts')",
            params![email.trim(), since],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?)
    }

    /// The addresses a sender writes from: [email], and the others that
    /// carry the same full name (two words or more), each with how many
    /// emails came from it, the account most of them arrived in, and
    /// whether a server vouched for one of them. Most emails first.
    pub fn sender_addresses(&self, email: &str) -> Result<Vec<SenderAddress>> {
        let mut stmt = self.conn.prepare_cached(
            "WITH names AS (
                 SELECT DISTINCT lower(trim(from_name)) AS name FROM message
                 WHERE lower(from_email) = lower(?1) AND instr(trim(from_name), ' ') > 0
             )
             SELECT lower(m.from_email), m.account, COUNT(*),
                    MAX(COALESCE(b.verified, 0))
             FROM message m
             LEFT JOIN message_body b USING (account, mailbox, uid)
             WHERE m.hidden = 0 AND m.folder NOT IN ('sent', 'drafts') AND m.from_email != ''
               AND (lower(m.from_email) = lower(?1)
                    OR lower(trim(m.from_name)) IN (SELECT name FROM names))
             GROUP BY lower(m.from_email), m.account",
        )?;
        let rows = stmt
            .query_map(params![email.trim()], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    AccountId(r.get(1)?),
                    r.get::<_, u32>(2)?,
                    r.get::<_, bool>(3)?,
                ))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut out: Vec<SenderAddress> = Vec::new();
        let mut most: HashMap<String, u32> = HashMap::new();
        for (address, account, emails, verified) in rows {
            let top = most.entry(address.clone()).or_default();
            let i = match out.iter().position(|a| a.email == address) {
                Some(i) => i,
                None => {
                    out.push(SenderAddress {
                        email: address.clone(),
                        account,
                        emails: 0,
                        verified: false,
                    });
                    out.len() - 1
                }
            };
            let a = &mut out[i];
            a.emails += emails;
            a.verified |= verified;
            if emails > *top {
                *top = emails;
                a.account = account;
            }
        }
        out.sort_by(|a, b| b.emails.cmp(&a.emails).then_with(|| a.email.cmp(&b.email)));
        Ok(out)
    }

    /// When you last wrote to an address, from the sent folders.
    pub fn last_sent_to(&self, email: &str) -> Result<Option<i64>> {
        let pattern = format!("%{}%", email.trim().to_lowercase());
        Ok(self.conn.query_row(
            "SELECT max(received_at) FROM message
             WHERE folder = 'sent' AND lower(to_list) LIKE ?1",
            params![pattern],
            |r| r.get(0),
        )?)
    }

    /// The message is a newsletter (bulk mail one can leave).
    pub fn is_newsletter(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT newsletter FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get::<_, bool>(0),
            )
            .optional()?
            .unwrap_or(false))
    }

    /// Events of the calendars that count for availability, overlapping
    /// a span. Floating and all-day times are wall-clock times, so the
    /// span is widened by a day each side and the caller narrows it.
    pub fn busy(&self, from: i64, to: i64) -> Result<Vec<Busy>> {
        let mut stmt = self.conn.prepare(
            "SELECT e.uid, e.summary, e.start, e.end, e.all_day, e.floating, c.name, c.color
             FROM calendar_event e JOIN calendar c ON c.id = e.calendar
             WHERE c.availability = 1 AND e.start < ?2 + 86400 AND e.end > ?1 - 86400
             ORDER BY e.start",
        )?;
        let rows = stmt.query_map(params![from, to], |r| {
            Ok(Busy {
                uid: r.get(0)?,
                summary: r.get(1)?,
                start: r.get(2)?,
                end: r.get(3)?,
                all_day: r.get(4)?,
                floating: r.get(5)?,
                calendar: r.get(6)?,
                color: r.get(7)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn setting(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row(
                "SELECT value FROM setting WHERE key = ?1",
                params![key],
                |r| r.get(0),
            )
            .optional()?)
    }

    pub fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO setting (key, value) VALUES (?1, ?2)",
            params![key, value],
        )?;
        Ok(())
    }

    /// Turns a feature of Settings › Features on or off.
    pub fn set_feature(&self, key: &str, on: bool) -> Result<()> {
        self.set_setting(key, if on { "true" } else { crate::features::OFF })?;
        if key == crate::features::NEWSLETTERS {
            refile_inbox(&self.conn)?;
        }
        Ok(())
    }

    /// The picture kept for a mail domain, and when it was looked up.
    pub fn sender_picture(&self, domain: &str) -> Result<Option<(crate::pictures::Picture, i64)>> {
        Ok(self
            .conn
            .query_row(
                "SELECT kind, png, fetched_at FROM sender_picture WHERE domain = ?1",
                params![domain],
                |r| {
                    Ok((
                        crate::pictures::Picture {
                            kind: crate::pictures::Kind::from_tag(&r.get::<_, String>(0)?),
                            png: r.get(1)?,
                        },
                        r.get(2)?,
                    ))
                },
            )
            .optional()?)
    }

    pub fn set_sender_picture(
        &self,
        domain: &str,
        picture: &crate::pictures::Picture,
        now: i64,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO sender_picture (domain, kind, png, fetched_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![domain, picture.kind.tag(), picture.png, now],
        )?;
        Ok(())
    }

    /// Forgets every kept picture, so they are looked up again.
    pub fn clear_sender_pictures(&self) -> Result<()> {
        self.conn.execute("DELETE FROM sender_picture", [])?;
        Ok(())
    }

    /// Whether the account's server vouched for mail from this domain at
    /// least once (see [`Store::sender_verified`]).
    pub fn domain_verified(&self, domain: &str) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT 1 FROM message m
                 JOIN message_body b USING (account, mailbox, uid)
                 WHERE b.verified = 1 AND lower(m.from_email) LIKE '%@' || ?1
                 LIMIT 1",
                params![domain.to_ascii_lowercase()],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }

    pub fn remove_setting(&self, key: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM setting WHERE key = ?1", params![key])?;
        Ok(())
    }

    /// Notes what was stopped in a message, once.
    pub fn log_privacy(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        now: i64,
        counts: PrivacyCounts,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO privacy_log
             (account, mailbox, uid, read_at, trackers, links, pixels, suspicious)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                account.0,
                mailbox,
                uid,
                now,
                counts.trackers,
                counts.links,
                counts.pixels,
                counts.suspicious
            ],
        )?;
        Ok(())
    }

    /// What was stopped in messages first read since `since`.
    pub fn privacy_totals(&self, since: i64) -> Result<PrivacyCounts> {
        Ok(self.conn.query_row(
            "SELECT COALESCE(SUM(trackers), 0), COALESCE(SUM(links), 0),
                    COALESCE(SUM(pixels), 0), COALESCE(SUM(suspicious), 0)
             FROM privacy_log WHERE read_at >= ?1",
            params![since],
            |r| {
                Ok(PrivacyCounts {
                    trackers: r.get(0)?,
                    links: r.get(1)?,
                    pixels: r.get(2)?,
                    suspicious: r.get(3)?,
                })
            },
        )?)
    }

    pub fn unread_count(
        &self,
        folder: Folder,
        within: impl Into<Within>,
        section: impl Into<ListFilter>,
    ) -> Result<u32> {
        let within = within.into();
        let section = section_sql(section) + &within.sql();
        Ok(self.conn.query_row(
            &format!(
                "SELECT COUNT(*) FROM message m
                 WHERE m.folder = ?1 AND m.hidden = 0 AND (m.flags & 1) = 0
                   AND (?2 IS NULL OR m.account = ?2){section}"
            ),
            params![folder.tag(), within.account()],
            |r| r.get(0),
        )?)
    }

    /// What the list headers of one message said.
    pub fn list_info(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<ListInfo> {
        Ok(self
            .conn
            .query_row(
                "SELECT newsletter, unsubscribe, one_click, bulk FROM message
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| {
                    Ok(ListInfo {
                        newsletter: r.get(0)?,
                        unsubscribe: r.get(1)?,
                        one_click: r.get(2)?,
                        bulk: r.get(3)?,
                        receipt: None,
                    })
                },
            )
            .optional()?
            .unwrap_or_default())
    }

    /// The messages sent from PEC mailboxes, with what their receipts say,
    /// newest first; of one account, or of all.
    pub fn pec_sent(&self, account: Option<AccountId>) -> Result<Vec<pec::Sent>> {
        let mut stmt = self.conn.prepare(
            "SELECT r.account, r.mailbox, r.uid, r.kind, r.refers, r.recipients, r.reason,
                    m.subject, m.received_at
             FROM pec_receipt r
             JOIN message m ON m.account = r.account AND m.mailbox = r.mailbox AND m.uid = r.uid
             WHERE m.hidden = 0 AND (?1 IS NULL OR r.account = ?1)",
        )?;
        let rows = stmt.query_map(params![account.map(|a| a.0)], |r| {
            Ok((
                pec::Stored {
                    account: AccountId(r.get(0)?),
                    mailbox: r.get(1)?,
                    uid: r.get(2)?,
                    kind: pec::Kind::Accepted,
                    refers: r.get(4)?,
                    recipients: list(&r.get::<_, String>(5)?),
                    reason: r.get(6)?,
                    subject: r.get(7)?,
                    received_at: r.get(8)?,
                },
                r.get::<_, String>(3)?,
            ))
        })?;
        let mut receipts = Vec::new();
        for row in rows {
            let (stored, kind) = row?;
            if let Some(kind) = pec::Kind::from_tag(&kind) {
                receipts.push(pec::Stored { kind, ..stored });
            }
        }
        Ok(pec::gather(receipts))
    }

    /// Every address a message went to, as [`ReplyInfo::recipients`]:
    /// empty for mail kept before they were read.
    pub fn recipients(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<String> {
        Ok(self
            .conn
            .query_row(
                "SELECT recipients FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get(0),
            )
            .optional()?
            .unwrap_or_default())
    }

    /// Keeps the addresses mail went to, read again for mail kept before.
    pub fn set_recipients(
        &mut self,
        account: AccountId,
        mailbox: &str,
        recipients: &[(u32, String)],
    ) -> Result<()> {
        let tx = self.conn.transaction()?;
        {
            let mut stmt = tx.prepare(
                "UPDATE message SET recipients = ?4
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            )?;
            let mut written = tx.prepare(NOTE_WRITTEN_TO)?;
            for (uid, to) in recipients {
                stmt.execute(params![account.0, mailbox, uid, to])?;
                written.execute(params![account.0, mailbox, uid])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// The other addresses an account sends from, by address.
    pub fn aliases(&self, account: AccountId) -> Result<Vec<String>> {
        let mut stmt = self
            .conn
            .prepare_cached("SELECT email FROM account_alias WHERE account = ?1 ORDER BY email")?;
        let rows = stmt.query_map(params![account.0], |r| r.get(0))?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// The account's own address, then its aliases: every address it
    /// sends from.
    pub fn own_addresses(&self, account: AccountId) -> Result<Vec<String>> {
        let Some(a) = self.account(account)? else {
            return Ok(Vec::new());
        };
        let mut out = vec![a.email.to_lowercase()];
        out.extend(self.aliases(account)?.into_iter().map(|e| e.to_lowercase()));
        Ok(out)
    }

    pub fn add_alias(&self, account: AccountId, email: &str) -> Result<()> {
        let email = email.trim().to_lowercase();
        if self
            .account(account)?
            .is_some_and(|a| a.email.eq_ignore_ascii_case(&email))
        {
            return Ok(());
        }
        self.conn.execute(
            "INSERT OR IGNORE INTO account_alias (account, email) VALUES (?1, ?2)",
            params![account.0, email],
        )?;
        Ok(())
    }

    /// Forgets an alias, and takes it out of its group.
    pub fn remove_alias(&self, account: AccountId, email: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM account_alias WHERE account = ?1 AND email = ?2",
            params![account.0, email.trim()],
        )?;
        self.conn.execute(
            "DELETE FROM group_address WHERE account = ?1 AND email = ?2",
            params![account.0, email.trim()],
        )?;
        Ok(())
    }

    /// Addresses the account's Sent mail went from that are neither its own
    /// nor an alias yet, the most used first: aliases to add with a tap.
    pub fn alias_suggestions(&self, account: AccountId) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT lower(m.from_email) AS e FROM message m JOIN account a ON a.id = m.account
             WHERE m.account = ?1 AND m.folder = 'sent' AND m.from_email LIKE '%@%'
               AND lower(m.from_email) <> lower(a.email)
               AND lower(m.from_email) NOT IN
                   (SELECT lower(email) FROM account_alias WHERE account = ?1)
             GROUP BY e ORDER BY count(*) DESC, e LIMIT 5",
        )?;
        let rows = stmt.query_map(params![account.0], |r| r.get(0))?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Every group, in order, with its addresses.
    pub fn address_groups(&self) -> Result<Vec<AddressGroup>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT id, name, color, signature, send_from, separate_inbox, notify
             FROM address_group ORDER BY position, id",
        )?;
        let mut groups: Vec<AddressGroup> = stmt
            .query_map([], |r| {
                Ok(AddressGroup {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    color: r.get(2)?,
                    signature: r.get(3)?,
                    send_from: r.get(4)?,
                    separate_inbox: r.get(5)?,
                    notify: r.get(6)?,
                    addresses: Vec::new(),
                })
            })?
            .collect::<std::result::Result<_, _>>()?;
        let mut stmt = self.conn.prepare_cached(
            "SELECT account, email FROM group_address WHERE grp = ?1 ORDER BY position, rowid",
        )?;
        for g in &mut groups {
            g.addresses = stmt
                .query_map(params![g.id], |r| {
                    Ok(GroupAddress {
                        account: AccountId(r.get(0)?),
                        email: r.get(1)?,
                    })
                })?
                .collect::<std::result::Result<_, _>>()?;
        }
        Ok(groups)
    }

    /// Keeps a group, a new one (last) when its id is 0, with exactly its
    /// addresses: one taken from another group leaves that one. Returns
    /// its id.
    pub fn save_address_group(&mut self, g: &AddressGroup) -> Result<i64> {
        let tx = self.conn.transaction()?;
        let changed = if g.id != 0 {
            tx.execute(
                "UPDATE address_group SET name = ?2, color = ?3, signature = ?4, send_from = ?5,
                    separate_inbox = ?6, notify = ?7 WHERE id = ?1",
                params![
                    g.id,
                    g.name,
                    g.color,
                    g.signature,
                    g.send_from,
                    g.separate_inbox,
                    g.notify
                ],
            )?
        } else {
            0
        };
        let id = if changed > 0 {
            g.id
        } else {
            tx.execute(
                "INSERT INTO address_group
                    (name, color, signature, send_from, separate_inbox, notify, position)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6,
                         (SELECT COALESCE(MAX(position), -1) + 1 FROM address_group))",
                params![
                    g.name,
                    g.color,
                    g.signature,
                    g.send_from,
                    g.separate_inbox,
                    g.notify
                ],
            )?;
            tx.last_insert_rowid()
        };
        tx.execute("DELETE FROM group_address WHERE grp = ?1", params![id])?;
        for (i, a) in g.addresses.iter().enumerate() {
            tx.execute(
                "INSERT OR REPLACE INTO group_address (grp, account, email, position)
                 VALUES (?1, ?2, ?3, ?4)",
                params![id, a.account.0, a.email.trim().to_lowercase(), i as i64],
            )?;
        }
        tx.commit()?;
        Ok(id)
    }

    pub fn delete_address_group(&self, id: i64) -> Result<()> {
        self.conn
            .execute("DELETE FROM address_group WHERE id = ?1", params![id])?;
        Ok(())
    }

    /// Whether mail with these recipients makes notices: not when the
    /// address it was written to is in a group with notices off.
    pub fn notifies(&self, account: AccountId, recipients: &str) -> Result<bool> {
        let own = self.own_addresses(account)?;
        let Some(to) =
            crate::groups::written_to(&own, recipients).or(own.first().map(String::as_str))
        else {
            return Ok(true);
        };
        Ok(self
            .conn
            .query_row(
                "SELECT g.notify FROM group_address ga JOIN address_group g ON g.id = ga.grp
                 WHERE ga.account = ?1 AND ga.email = ?2",
                params![account.0, to],
                |r| r.get(0),
            )
            .optional()?
            .unwrap_or(true))
    }

    /// The rows the sync space carries, by table: accounts (not their
    /// mail), signatures, templates, groups, aliases and the settings
    /// that aren't this device's own.
    pub fn space_tables(&self) -> Result<serde_json::Map<String, serde_json::Value>> {
        let mut out = serde_json::Map::new();
        for table in SPACE_TABLES {
            let mut stmt = self.conn.prepare(&format!("SELECT * FROM {table}"))?;
            let names: Vec<String> = stmt.column_names().iter().map(|s| s.to_string()).collect();
            let rows = stmt
                .query_map([], |r| {
                    let mut row = serde_json::Map::new();
                    for (i, name) in names.iter().enumerate() {
                        if SPACE_LOCAL_COLUMNS.contains(&(*table, name.as_str())) {
                            continue;
                        }
                        row.insert(name.clone(), to_json(r.get_ref(i)?));
                    }
                    Ok(serde_json::Value::Object(row))
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            let rows = rows
                .into_iter()
                .filter(|row| {
                    *table != "setting"
                        || row["key"]
                            .as_str()
                            .is_some_and(|k| !LOCAL_SETTINGS.iter().any(|p| k.starts_with(p)))
                })
                .collect();
            out.insert((*table).to_owned(), serde_json::Value::Array(rows));
        }
        Ok(out)
    }

    /// Takes in what a sync space carries: accounts are matched by address
    /// (new ones are added), the other tables replaced, settings merged.
    /// Returns each account's id here by its address.
    /// The accounts on this device that `tables` (another device's space)
    /// no longer has: removed there. Only meaningful when nothing changed
    /// here since the last round, which `space_sync::round` checks.
    pub fn accounts_not_in(
        &self,
        tables: &serde_json::Map<String, serde_json::Value>,
    ) -> Result<Vec<AccountId>> {
        let theirs: HashSet<String> = tables
            .get("account")
            .and_then(|v| v.as_array())
            .into_iter()
            .flatten()
            .filter_map(|r| r.get("email")?.as_str().map(str::to_lowercase))
            .collect();
        Ok(self
            .accounts()?
            .into_iter()
            .filter(|a| !theirs.contains(&a.email.to_lowercase()))
            .map(|a| a.id)
            .collect())
    }

    pub fn take_space_tables(
        &mut self,
        tables: &serde_json::Map<String, serde_json::Value>,
    ) -> Result<HashMap<String, AccountId>> {
        let rows = |t: &str| -> Vec<serde_json::Map<String, serde_json::Value>> {
            tables
                .get(t)
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|r| r.as_object().cloned()).collect())
                .unwrap_or_default()
        };
        let tx = self.conn.transaction()?;
        let columns = |t: &str| -> Result<Vec<String>> {
            let mut stmt = tx.prepare(&format!("SELECT name FROM pragma_table_info('{t}')"))?;
            let names = stmt
                .query_map([], |r| r.get(0))?
                .collect::<std::result::Result<Vec<String>, _>>()?;
            Ok(names)
        };
        // Accounts: by address.
        let mut ids: HashMap<i64, i64> = HashMap::new();
        let mut by_email = HashMap::new();
        let account_cols = columns("account")?;
        for row in rows("account") {
            let (Some(remote), Some(email)) = (row["id"].as_i64(), row["email"].as_str()) else {
                continue;
            };
            let cols: Vec<&String> = account_cols
                .iter()
                .filter(|c| *c != "id" && row.contains_key(c.as_str()))
                .collect();
            let values: Vec<rusqlite::types::Value> =
                cols.iter().map(|c| from_json(&row[c.as_str()])).collect();
            let here: Option<i64> = tx
                .query_row(
                    "SELECT id FROM account WHERE email = ?1 COLLATE NOCASE",
                    params![email],
                    |r| r.get(0),
                )
                .optional()?;
            let id = match here {
                Some(id) => {
                    let set = cols
                        .iter()
                        .map(|c| format!("{c} = ?"))
                        .collect::<Vec<_>>()
                        .join(", ");
                    let mut params: Vec<rusqlite::types::Value> = values;
                    params.push(id.into());
                    tx.execute(
                        &format!("UPDATE account SET {set} WHERE id = ?"),
                        rusqlite::params_from_iter(params),
                    )?;
                    id
                }
                None => {
                    let names = cols
                        .iter()
                        .map(|c| c.as_str())
                        .collect::<Vec<_>>()
                        .join(", ");
                    let marks = vec!["?"; cols.len()].join(", ");
                    tx.execute(
                        &format!("INSERT INTO account ({names}) VALUES ({marks})"),
                        rusqlite::params_from_iter(values),
                    )?;
                    tx.last_insert_rowid()
                }
            };
            ids.insert(remote, id);
            by_email.insert(email.to_lowercase(), AccountId(id));
        }
        // The rest: replaced, with account ids made local. A space written
        // before rules synced has no rules: the ones here stay.
        let rules = tables.contains_key("rule");
        // The same for labels.
        let labels = tables.contains_key("label");
        let kept = |table: &str| match table {
            "rule" => !rules,
            "label" => !labels,
            _ => false,
        };
        // What each rule did here, kept across the replacement.
        let ran: Vec<(i64, Option<i64>, i64)> = {
            let mut stmt = tx.prepare("SELECT id, last_run, matched FROM rule")?;
            let rows = stmt
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
                .collect::<std::result::Result<_, _>>()?;
            rows
        };
        for table in [
            "group_address",
            "address_group",
            "account_alias",
            "signature",
            "message_template",
            "rule",
            "label",
        ] {
            if kept(table) {
                continue;
            }
            tx.execute(&format!("DELETE FROM {table}"), [])?;
        }
        for table in [
            "signature",
            "message_template",
            "address_group",
            "group_address",
            "account_alias",
            "rule",
            "label",
        ] {
            if kept(table) {
                continue;
            }
            let cols = columns(table)?;
            'rows: for mut row in rows(table) {
                if let Some(a) = row.get("account").and_then(|v| v.as_i64()) {
                    match ids.get(&a) {
                        Some(&here) => {
                            row.insert("account".into(), here.into());
                        }
                        None => continue 'rows,
                    }
                }
                let present: Vec<&String> = cols
                    .iter()
                    .filter(|c| row.contains_key(c.as_str()))
                    .collect();
                let names = present
                    .iter()
                    .map(|c| c.as_str())
                    .collect::<Vec<_>>()
                    .join(", ");
                let marks = vec!["?"; present.len()].join(", ");
                tx.execute(
                    &format!("INSERT OR REPLACE INTO {table} ({names}) VALUES ({marks})"),
                    rusqlite::params_from_iter(present.iter().map(|c| from_json(&row[c.as_str()]))),
                )?;
            }
        }
        if rules {
            let mut stmt =
                tx.prepare("UPDATE rule SET last_run = ?2, matched = ?3 WHERE id = ?1")?;
            for (id, last_run, matched) in ran {
                stmt.execute(params![id, last_run, matched])?;
            }
        }
        // Connected calendars: changed in place, so the events read here
        // stay with the calendars that are still the same.
        if tables.contains_key("calendar_source") {
            let same: HashSet<(i64, i64, String)> = rows("calendar")
                .iter()
                .filter_map(|r| {
                    Some((
                        r.get("id")?.as_i64()?,
                        r.get("source")?.as_i64()?,
                        r.get("url")?.as_str()?.to_owned(),
                    ))
                })
                .collect();
            let gone: Vec<i64> = {
                let mut stmt = tx.prepare("SELECT id, source, url FROM calendar")?;
                let here = stmt
                    .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
                    .collect::<std::result::Result<Vec<(i64, i64, String)>, _>>()?;
                here.into_iter()
                    .filter(|c| !same.contains(c))
                    .map(|c| c.0)
                    .collect()
            };
            for id in gone {
                tx.execute("DELETE FROM calendar WHERE id = ?1", params![id])?;
            }
            let sources: Vec<i64> = rows("calendar_source")
                .iter()
                .filter_map(|r| r.get("id")?.as_i64())
                .collect();
            if sources.is_empty() {
                tx.execute("DELETE FROM calendar_source", [])?;
            } else {
                let marks = vec!["?"; sources.len()].join(",");
                tx.execute(
                    &format!("DELETE FROM calendar_source WHERE id NOT IN ({marks})"),
                    rusqlite::params_from_iter(&sources),
                )?;
            }
            for table in ["calendar_source", "calendar"] {
                let cols = columns(table)?;
                for mut row in rows(table) {
                    if let Some(a) = row.get("account").and_then(|v| v.as_i64()) {
                        row.insert("account".into(), ids.get(&a).copied().into());
                    }
                    let present: Vec<&String> = cols
                        .iter()
                        .filter(|c| row.contains_key(c.as_str()))
                        .collect();
                    let names = present
                        .iter()
                        .map(|c| c.as_str())
                        .collect::<Vec<_>>()
                        .join(", ");
                    let marks = vec!["?"; present.len()].join(", ");
                    let set = present
                        .iter()
                        .filter(|c| c.as_str() != "id")
                        .map(|c| format!("{c} = excluded.{c}"))
                        .collect::<Vec<_>>()
                        .join(", ");
                    tx.execute(
                        &format!(
                            "INSERT INTO {table} ({names}) VALUES ({marks})
                             ON CONFLICT (id) DO UPDATE SET {set}"
                        ),
                        rusqlite::params_from_iter(
                            present.iter().map(|c| from_json(&row[c.as_str()])),
                        ),
                    )?;
                }
            }
        }
        for row in rows("setting") {
            if let (Some(k), Some(v)) = (row["key"].as_str(), row["value"].as_str()) {
                if !LOCAL_SETTINGS.iter().any(|p| k.starts_with(p)) {
                    tx.execute(
                        "INSERT OR REPLACE INTO setting (key, value) VALUES (?1, ?2)",
                        params![k, v],
                    )?;
                }
            }
        }
        // Newsletters may have been turned on or off on another device.
        refile_inbox(&tx)?;
        tx.commit()?;
        Ok(by_email)
    }

    /// The group an address is in, if any.
    pub fn group_of(&self, email: &str) -> Result<Option<i64>> {
        Ok(self
            .conn
            .query_row(
                "SELECT grp FROM group_address WHERE email = ?1",
                params![email.trim()],
                |r| r.get(0),
            )
            .optional()?)
    }

    /// Messages of a folder cached before their list headers were read,
    /// newest first, at most `limit`.
    pub fn unchecked_lists(
        &self,
        account: AccountId,
        mailbox: &str,
        limit: u32,
    ) -> Result<Vec<u32>> {
        let mut stmt = self.conn.prepare(
            "SELECT uid FROM message WHERE account = ?1 AND mailbox = ?2 AND list_checked = 0
             ORDER BY uid DESC LIMIT ?3",
        )?;
        let rows = stmt.query_map(params![account.0, mailbox, limit], |r| r.get(0))?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Stores what the list headers said, and files inbox mail again:
    /// newsletters leave the inbox for Newsletters.
    pub fn set_list_info(
        &mut self,
        account: AccountId,
        mailbox: &str,
        lists: &[(u32, ListInfo)],
    ) -> Result<()> {
        let tx = self.conn.transaction()?;
        {
            let mut stmt = tx.prepare(&format!(
                "UPDATE message SET newsletter = ?4, unsubscribe = ?5, one_click = ?6,
                    bulk = ?7, list_checked = 1,
                    folder = CASE WHEN folder IN ('inbox', 'newsletters') THEN {} ELSE folder END
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                inbox_zone("from_email", "?4")
            ))?;
            for (uid, list) in lists {
                stmt.execute(params![
                    account.0,
                    mailbox,
                    uid,
                    list.newsletter,
                    list.unsubscribe,
                    list.one_click,
                    list.bulk
                ])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Puts a sender's inbox mail in People or in Notifications from now
    /// on, whatever its headers say; None lets the headers decide again.
    pub fn set_sender_side(&self, email: &str, people: Option<bool>) -> Result<()> {
        match people {
            Some(people) => self.conn.execute(
                "INSERT INTO sender_side (email, people) VALUES (lower(?1), ?2)
                 ON CONFLICT (email) DO UPDATE SET people = excluded.people",
                params![email, people],
            )?,
            None => self.conn.execute(
                "DELETE FROM sender_side WHERE email = lower(?1)",
                params![email],
            )?,
        };
        Ok(())
    }

    /// Where the inbox mail of a sender goes from now on, the mail already
    /// there included: [`Folder::Inbox`] or [`Folder::Newsletters`].
    pub fn set_sender_zone(&self, email: &str, zone: Folder) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        tx.execute(
            "INSERT INTO sender_zone (email, zone) VALUES (lower(?1), ?2)
             ON CONFLICT (email) DO UPDATE SET zone = excluded.zone",
            params![email, zone.tag()],
        )?;
        tx.execute(
            "UPDATE message SET folder = ?2
             WHERE folder IN ('inbox', 'newsletters') AND lower(from_email) = lower(?1)",
            params![email, zone.tag()],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// Newsletters of an account whose body is not cached yet, newest
    /// first, at most `limit`: what to fetch for reading offline.
    pub fn newsletters_without_body(
        &self,
        account: AccountId,
        limit: u32,
    ) -> Result<Vec<(String, u32)>> {
        let mut stmt = self.conn.prepare(
            "SELECT m.mailbox, m.uid FROM message m
             WHERE m.account = ?1 AND m.folder = 'newsletters' AND NOT EXISTS (
                 SELECT 1 FROM message_body b
                 WHERE b.account = m.account AND b.mailbox = m.mailbox AND b.uid = m.uid)
             ORDER BY m.received_at DESC LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![account.0, limit], |r| Ok((r.get(0)?, r.get(1)?)))?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// The newest Inbox mail of an account's folder whose body is not
    /// cached yet, at most `limit`: fetched ahead, so opening one doesn't
    /// wait on the server.
    pub fn inbox_without_body(
        &self,
        account: AccountId,
        mailbox: &str,
        limit: u32,
    ) -> Result<Vec<u32>> {
        let mut stmt = self.conn.prepare(
            "SELECT m.uid FROM message m
             WHERE m.account = ?1 AND m.mailbox = ?2 AND m.folder = 'inbox' AND m.hidden = 0
               AND NOT EXISTS (
                 SELECT 1 FROM message_body b
                 WHERE b.account = m.account AND b.mailbox = m.mailbox AND b.uid = m.uid)
             ORDER BY m.received_at DESC LIMIT ?3",
        )?;
        let rows = stmt.query_map(params![account.0, mailbox, limit], |r| r.get(0))?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Newsletters of every account (or one), newest first, addressed by
    /// position, each with its reading time in minutes (0 until its body
    /// is known).
    pub fn newsletters_page(
        &self,
        account: Option<AccountId>,
        offset: u32,
        limit: u32,
    ) -> Result<Vec<(MessageSummary, u32)>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT account, mailbox, uid, from_name, from_email, subject, preview, received_at, flags,
                    message_id, refs, reply_to, to_list, words
             FROM message
             WHERE folder = 'newsletters' AND hidden = 0 AND (?3 IS NULL OR account = ?3)
             ORDER BY received_at DESC, account, uid DESC
             LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset, account.map(|a| a.0)], |r| {
            Ok((row_to_summary(r)?, crate::newsletter::minutes(r.get(13)?)))
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Looks at up to `limit` messages of a mailbox not looked at for the
    /// Vault yet, newest first: those whose body is here make their card
    /// now. Returns the ones worth fetching the body of.
    pub fn vault_unchecked(
        &self,
        account: AccountId,
        mailbox: &str,
        now: i64,
        limit: u32,
    ) -> Result<Vec<u32>> {
        if !crate::features::on(&self.conn, crate::features::VAULT)? {
            return Ok(Vec::new());
        }
        let tx = self.conn.unchecked_transaction()?;
        // Too old, or mail that never makes a card: nothing to look at.
        tx.execute(
            &format!(
                "UPDATE message SET vault_checked = 1
             WHERE account = ?1 AND mailbox = ?2 AND vault_checked = 0
               AND (received_at < ?3 OR folder IN ('sent', 'drafts', 'newsletters'))
               AND NOT {PINNED}",
            ),
            params![account.0, mailbox, now - VAULT_SPAN],
        )?;
        let rows: Vec<(u32, String, bool, bool)> = {
            let mut stmt = tx.prepare(&format!(
                "SELECT m.uid, m.subject, EXISTS (
                     SELECT 1 FROM message_body b WHERE b.account = m.account
                         AND b.mailbox = m.mailbox AND b.uid = m.uid AND b.format > 0),
                     {PINNED}
                 FROM message m
                 WHERE m.account = ?1 AND m.mailbox = ?2 AND m.vault_checked = 0
                 ORDER BY m.received_at DESC LIMIT ?3"
            ))?;
            let rows = stmt.query_map(params![account.0, mailbox, limit], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))
            })?;
            rows.collect::<rusqlite::Result<_>>()?
        };
        let mut wanted = Vec::new();
        for (uid, subject, cached, pinned) in rows {
            if cached {
                let body = self.full_body(account, mailbox, uid)?.unwrap_or_default();
                file_card(&tx, account, mailbox, uid, &body)?;
            } else if pinned || crate::vault::candidate(&subject) {
                wanted.push(uid);
            } else {
                // HTML with schema.org data is only seen once the body is
                // here: when it is opened, or fetched for another reason.
                set_vault_checked(&tx, account, mailbox, uid)?;
            }
        }
        tx.commit()?;
        Ok(wanted)
    }

    /// "Move to Vault": the message makes a card wherever it goes, read
    /// again now if its body is here. One without a Message-ID can't be
    /// followed into another folder; returns whether it was pinned.
    pub fn pin_to_vault(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        now: i64,
    ) -> Result<bool> {
        let tx = self.conn.unchecked_transaction()?;
        let id: Option<String> = tx
            .query_row(
                "SELECT message_id FROM message WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get(0),
            )
            .optional()?;
        let Some(id) = id.filter(|id| !id.is_empty()) else {
            return Ok(false);
        };
        tx.execute(
            "INSERT OR IGNORE INTO vault_pin (message_id, pinned_at) VALUES (?1, ?2)",
            params![id, now],
        )?;
        if let Some(body) = self.full_body(account, mailbox, uid)? {
            file_card(&tx, account, mailbox, uid, &body)?;
        }
        tx.commit()?;
        Ok(true)
    }

    /// Marks messages looked at for the Vault without a card, as when
    /// their body is too big to fetch for it.
    pub fn skip_vault(&self, account: AccountId, mailbox: &str, uids: &[u32]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        for uid in uids {
            set_vault_checked(&tx, account, mailbox, *uid)?;
        }
        tx.commit()?;
        Ok(())
    }

    /// The Vault's cards from mail received since `since`, of every
    /// account (or one), newest first, one per key (the newest email
    /// about a parcel says where it is), with the list each email is in.
    pub fn vault_cards(
        &self,
        account: Option<AccountId>,
        since: i64,
    ) -> Result<Vec<(MessageSummary, Option<Folder>, crate::vault::Card)>> {
        if !crate::features::on(&self.conn, crate::features::VAULT)? {
            return Ok(Vec::new());
        }
        let mut stmt = self.conn.prepare_cached(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list,
                    c.data, p.key IS NOT NULL, m.folder
             FROM vault_card c
             JOIN message m USING (account, mailbox, uid)
             LEFT JOIN vault_paid p ON p.key = c.key
             WHERE m.hidden = 0 AND m.received_at >= ?1 AND (?2 IS NULL OR m.account = ?2)
             ORDER BY m.received_at DESC, m.account, m.uid DESC",
        )?;
        let rows = stmt.query_map(params![since, account.map(|a| a.0)], |r| {
            Ok((
                row_to_summary(r)?,
                r.get::<_, String>(13)?,
                r.get::<_, bool>(14)?,
                Folder::from_tag(&r.get::<_, String>(15)?),
            ))
        })?;
        let mut read = Vec::new();
        for row in rows {
            let (m, data, marked, folder) = row?;
            let Ok(card) = serde_json::from_str::<crate::vault::Card>(&data) else {
                continue;
            };
            read.push((m, folder, card, marked));
        }
        // A charge that failed is settled once the same sender sends a
        // receipt after it.
        let mut receipts: std::collections::HashMap<String, i64> = Default::default();
        for (m, _, card, _) in &read {
            if card.kind == crate::vault::Kind::Bill && card.paid && card.status.is_empty() {
                let at = receipts
                    .entry(m.from_name.trim().to_lowercase())
                    .or_default();
                *at = (*at).max(m.received_at);
            }
        }
        // One card per key, the newest; older emails about it add what
        // the newest leaves out (an order's total, its return window) and
        // the day it began.
        let mut seen: std::collections::HashMap<String, usize> = Default::default();
        let mut cards: Vec<(MessageSummary, Option<Folder>, crate::vault::Card)> = Vec::new();
        for (m, folder, mut card, marked) in read {
            if let Some(&at) = seen.get(&card.key) {
                let kept = &mut cards[at].2;
                if kept.amount.is_none() && card.amount.is_some() {
                    kept.amount = card.amount;
                    kept.currency = card.currency;
                }
                if kept.return_days == 0 {
                    kept.return_days = card.return_days;
                }
                kept.first = crate::vault::Day::local(m.received_at, 0).to_string();
                continue;
            }
            seen.insert(card.key.clone(), cards.len());
            card.first = crate::vault::Day::local(m.received_at, 0).to_string();
            card.paid |= marked;
            if card.status == "failed"
                && receipts
                    .get(&m.from_name.trim().to_lowercase())
                    .is_some_and(|&at| at > m.received_at)
            {
                card.paid = true;
            }
            // Cards made before a receipt read as paid follow at once.
            if card.kind == crate::vault::Kind::Bill && !card.paid {
                card.paid = crate::vault::says_paid(&m.subject, "");
            }
            crate::vault::mend(&mut card);
            cards.push((m, folder, card));
        }
        Ok(cards)
    }

    /// Marks a bill paid, or not, by its card key.
    pub fn set_paid(&self, key: &str, paid: bool, now: i64) -> Result<()> {
        if paid {
            self.conn.execute(
                "INSERT OR REPLACE INTO vault_paid (key, paid_at) VALUES (?1, ?2)",
                params![key, now],
            )?;
        } else {
            self.conn
                .execute("DELETE FROM vault_paid WHERE key = ?1", params![key])?;
        }
        Ok(())
    }

    /// Messages of a folder whose files are not listed yet, newest first.
    /// Mail you sent or drafted lists none: the board shows what came in.
    pub fn files_unchecked(
        &self,
        account: AccountId,
        mailbox: &str,
        limit: u32,
    ) -> Result<Vec<u32>> {
        self.conn.execute(
            "UPDATE message SET files_checked = 1
             WHERE account = ?1 AND mailbox = ?2 AND files_checked = 0
               AND folder IN ('sent', 'drafts')",
            params![account.0, mailbox],
        )?;
        let mut stmt = self.conn.prepare_cached(
            "SELECT uid FROM message
             WHERE account = ?1 AND mailbox = ?2 AND files_checked = 0
             ORDER BY received_at DESC LIMIT ?3",
        )?;
        let rows = stmt.query_map(params![account.0, mailbox, limit], |r| r.get(0))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Mends up to `limit` previews made before they followed the reader,
    /// newest first: a message whose body is here is mended now. Returns
    /// the ones whose start has to be fetched again.
    pub fn previews_to_mend(
        &self,
        account: AccountId,
        mailbox: &str,
        limit: u32,
    ) -> Result<Vec<u32>> {
        let rows: Vec<(u32, bool)> = {
            let mut stmt = self.conn.prepare_cached(
                "SELECT m.uid, EXISTS (
                     SELECT 1 FROM message_body b WHERE b.account = m.account
                         AND b.mailbox = m.mailbox AND b.uid = m.uid AND b.format > 0)
                 FROM preview_stale p JOIN message m ON m.account = p.account
                     AND m.mailbox = p.mailbox AND m.uid = p.uid
                 WHERE p.account = ?1 AND p.mailbox = ?2
                 ORDER BY m.received_at DESC LIMIT ?3",
            )?;
            let rows = stmt.query_map(params![account.0, mailbox, limit], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })?;
            rows.collect::<rusqlite::Result<_>>()?
        };
        let mut here = Vec::new();
        let mut wanted = Vec::new();
        for (uid, cached) in rows {
            if cached {
                let body = self.full_body(account, mailbox, uid)?.unwrap_or_default();
                here.push((
                    uid,
                    crate::imap::reader_preview(&body.text, body.html.as_deref()),
                ));
            } else {
                wanted.push(uid);
            }
        }
        self.mend_previews(account, mailbox, &here)?;
        Ok(wanted)
    }

    /// Keeps previews made again; an empty one leaves the old in place.
    /// The messages are mended either way, so they aren't asked again.
    pub fn mend_previews(
        &self,
        account: AccountId,
        mailbox: &str,
        previews: &[(u32, String)],
    ) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        for (uid, preview) in previews {
            if !preview.is_empty() {
                tx.execute(
                    "UPDATE message SET preview = ?4
                     WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                    params![account.0, mailbox, uid, preview],
                )?;
            }
            tx.execute(
                "DELETE FROM preview_stale WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    /// Keeps the files listed from the server's outline of each message.
    /// A message whose body came meanwhile keeps the body's list.
    pub fn set_listed_files(
        &self,
        account: AccountId,
        mailbox: &str,
        listed: &[(u32, Vec<Attachment>)],
    ) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        for (uid, files) in listed {
            let open = tx.execute(
                "UPDATE message SET files_checked = 1
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND files_checked = 0",
                params![account.0, mailbox, uid],
            )?;
            if open == 0 {
                continue;
            }
            for a in files {
                tx.execute(
                    "INSERT OR IGNORE INTO attachment
                         (account, mailbox, uid, part, name, mime, size, section, encoding)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                    params![
                        account.0,
                        mailbox,
                        uid,
                        a.part,
                        a.name,
                        a.mime,
                        a.size as i64,
                        a.section,
                        a.encoding
                    ],
                )?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// The files received in every account (or one), newest first, with
    /// the message each came with and the list it is in. Mail you sent
    /// or drafted is left out.
    pub fn files(
        &self,
        account: Option<AccountId>,
        limit: u32,
    ) -> Result<Vec<(MessageSummary, Option<Folder>, Attachment)>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list,
                    a.part, a.name, a.mime, a.size, a.section, a.encoding, m.folder
             FROM attachment a
             JOIN message m USING (account, mailbox, uid)
             WHERE m.hidden = 0 AND m.folder NOT IN ('sent', 'drafts')
               AND (?1 IS NULL OR m.account = ?1)
             ORDER BY m.received_at DESC, m.account, m.uid DESC, a.part
             LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![account.map(|a| a.0), limit], |r| {
            Ok((
                row_to_summary(r)?,
                Folder::from_tag(&r.get::<_, String>(19)?),
                row_to_attachment(r, 13)?,
            ))
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// How many files a message has, and how many are pictures.
    pub fn file_count(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<(u32, u32)> {
        Ok(self.conn.query_row(
            "SELECT COUNT(*), COALESCE(SUM(mime LIKE 'image/%'), 0) FROM attachment
             WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            params![account.0, mailbox, uid],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?)
    }

    /// Whether a message carries an invite, as far as its cached body says.
    pub fn has_invite(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<bool> {
        Ok(self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM message_body
             WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND calendar IS NOT NULL)",
            params![account.0, mailbox, uid],
            |r| r.get(0),
        )?)
    }

    /// The small preview kept for an attached picture.
    pub fn thumb(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        name: &str,
    ) -> Result<Option<Vec<u8>>> {
        Ok(self
            .conn
            .query_row(
                "SELECT data FROM attachment_thumb
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND name = ?4",
                params![account.0, mailbox, uid, name],
                |r| r.get(0),
            )
            .optional()?)
    }

    pub fn set_thumb(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        name: &str,
        data: &[u8],
    ) -> Result<()> {
        self.conn.execute(
            "INSERT OR REPLACE INTO attachment_thumb (account, mailbox, uid, name, data)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![account.0, mailbox, uid, name, data],
        )?;
        Ok(())
    }

    /// Keeps when messages of a folder come back, as their keywords say.
    pub fn set_snooze_times(
        &self,
        account: AccountId,
        mailbox: &str,
        times: &[(u32, Option<i64>)],
    ) -> Result<()> {
        if times.is_empty() {
            return Ok(());
        }
        let tx = self.conn.unchecked_transaction()?;
        for (uid, until) in times {
            tx.execute(
                "UPDATE message SET snooze_until = ?4 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid, until],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    /// When a message comes back from Snoozed, as this device knows.
    pub fn snooze_until(&self, account: AccountId, mailbox: &str, uid: u32) -> Result<Option<i64>> {
        Ok(self
            .conn
            .query_row(
                "SELECT COALESCE(m.snooze_until, s.until) FROM message m
                 LEFT JOIN snooze s ON s.account = m.account AND s.message_id = m.message_id
                 WHERE m.account = ?1 AND m.mailbox = ?2 AND m.uid = ?3",
                params![account.0, mailbox, uid],
                |r| r.get(0),
            )
            .optional()?
            .flatten())
    }

    /// Snoozes messages: remembers when each comes back, by Message-ID
    /// (the move to Snoozed gives them new UIDs), and hides them until
    /// the move reaches the server.
    pub fn snooze(
        &self,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        until: i64,
    ) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        for uid in uids {
            tx.execute(
                "INSERT OR REPLACE INTO snooze (account, message_id, until)
                 SELECT account, message_id, ?4 FROM message
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND message_id != ''",
                params![account.0, mailbox, uid, until],
            )?;
            tx.execute(
                "UPDATE message SET hidden = 1, snooze_until = ?4
                 WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
                params![account.0, mailbox, uid, until],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    /// Forgets when messages were to come back, as they do.
    pub fn forget_snoozes(&self, account: AccountId, mailbox: &str, uids: &[u32]) -> Result<()> {
        for uid in uids {
            self.conn.execute(
                "DELETE FROM snooze WHERE account = ?1 AND message_id IN (
                     SELECT message_id FROM message
                     WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND message_id != '')",
                params![account.0, mailbox, uid],
            )?;
        }
        Ok(())
    }

    /// Waits for a reply too: snoozed messages also come back as soon as
    /// someone else writes in their thread after `since`.
    pub fn snooze_unless_reply(
        &self,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
        since: i64,
    ) -> Result<()> {
        for uid in uids {
            self.conn.execute(
                "UPDATE snooze SET unless_reply = ?4 WHERE account = ?1 AND message_id IN (
                     SELECT message_id FROM message
                     WHERE account = ?1 AND mailbox = ?2 AND uid = ?3 AND message_id != '')",
                params![account.0, mailbox, uid, since],
            )?;
        }
        Ok(())
    }

    /// Queues the waking of the snoozed messages whose time has come, and
    /// hides them meanwhile. Returns how many.
    pub fn queue_wakes(&self, account: AccountId, now: i64) -> Result<usize> {
        let tx = self.conn.unchecked_transaction()?;
        let queued = tx.execute(
            &format!(
                "INSERT INTO pending_change (account, mailbox, uid, change, target)
             SELECT m.account, m.mailbox, m.uid, 'wake', COALESCE(m.snooze_until, s.until)
             FROM message m
             LEFT JOIN snooze s ON s.account = m.account AND s.message_id = m.message_id
             WHERE m.account = ?1 AND m.folder = 'snoozed' AND m.hidden = 0
               AND (COALESCE(m.snooze_until, s.until) <= ?2 OR {}) AND NOT EXISTS (
                   SELECT 1 FROM pending_change p
                   WHERE p.account = m.account AND p.mailbox = m.mailbox AND p.uid = m.uid)",
                REPLIED
            ),
            params![account.0, now],
        )?;
        tx.execute(
            "UPDATE message SET hidden = 1
             WHERE account = ?1 AND folder = 'snoozed' AND hidden = 0 AND EXISTS (
                 SELECT 1 FROM pending_change p
                 WHERE p.account = message.account AND p.mailbox = message.mailbox
                   AND p.uid = message.uid AND p.change = 'wake')",
            params![account.0],
        )?;
        tx.commit()?;
        Ok(queued)
    }

    /// When the watcher must look again on its own, mail or no mail: the
    /// next snoozed message coming back, the next mail sent later, or the
    /// next reminder after `now` (so a reply that came is known by then).
    pub fn next_due(&self, account: AccountId, now: i64) -> Result<Option<i64>> {
        let send: Option<i64> = self.conn.query_row(
            "SELECT MIN(send_at) FROM outbox WHERE account = ?1 AND error IS NULL",
            params![account.0],
            |r| r.get(0),
        )?;
        let remind: Option<i64> = self.conn.query_row(
            "SELECT MIN(at) FROM reply_reminder WHERE account = ?1 AND at > ?2",
            params![account.0, now],
            |r| r.get(0),
        )?;
        Ok([self.next_wake(account)?, send, remind]
            .into_iter()
            .flatten()
            .min())
    }

    /// When the next snoozed message of an account comes back.
    pub fn next_wake(&self, account: AccountId) -> Result<Option<i64>> {
        // A reply that came brings its message back now.
        Ok(self.conn.query_row(
            &format!(
                "SELECT MIN(CASE WHEN {REPLIED} THEN 0 ELSE COALESCE(m.snooze_until, s.until) END)
                 FROM message m
                 LEFT JOIN snooze s ON s.account = m.account AND s.message_id = m.message_id
                 WHERE m.account = ?1 AND m.folder = 'snoozed' AND m.hidden = 0"
            ),
            params![account.0],
            |r| r.get(0),
        )?)
    }

    /// Snoozed messages of every account (or one), the soonest back
    /// first, with when they come back (None when no device knows).
    pub fn snoozed(
        &self,
        account: Option<AccountId>,
    ) -> Result<Vec<(MessageSummary, Option<i64>)>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list,
                    COALESCE(m.snooze_until, s.until) AS until
             FROM message m
             LEFT JOIN snooze s ON s.account = m.account AND s.message_id = m.message_id
             WHERE m.folder = 'snoozed' AND m.hidden = 0 AND (?1 IS NULL OR m.account = ?1)
             ORDER BY until IS NULL, until, m.received_at DESC",
        )?;
        let rows = stmt.query_map(params![account.map(|a| a.0)], |r| {
            Ok((row_to_summary(r)?, r.get(13)?))
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Waiting: mail you sent to people in the last [`WAITING_DAYS`] that
    /// is still the last word of its conversation, newest first. Mail to
    /// lists, machines or only yourself, short closers ("Thanks!") and
    /// mail you stopped waiting on are left out. Each keeps in
    /// `reply.recipients` only the people it waits on.
    pub fn waiting(&self, account: Option<AccountId>, now: i64) -> Result<Vec<MessageSummary>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list,
                    m.recipients
             FROM message m
             WHERE m.folder = 'sent' AND m.hidden = 0 AND m.message_id != ''
               AND m.received_at >= ?2 AND (?1 IS NULL OR m.account = ?1)
               AND NOT EXISTS (SELECT 1 FROM waiting_done d
                   WHERE d.account = m.account AND d.message_id = m.message_id)
               AND NOT EXISTS (SELECT 1 FROM message n
                   WHERE n.account = m.account AND n.thread = m.thread AND m.thread != ''
                     AND n.hidden = 0
                     AND n.folder != 'drafts' AND n.message_id != m.message_id
                     AND (n.received_at > m.received_at
                          OR (n.received_at = m.received_at AND n.folder != 'sent')))
             ORDER BY m.received_at DESC, m.uid DESC",
        )?;
        let since = now - WAITING_DAYS * 86_400;
        let rows = stmt
            .query_map(params![account.map(|a| a.0), since], |r| {
                let mut m = row_to_summary(r)?;
                m.reply.recipients = r.get(13)?;
                Ok(m)
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let mut own: HashMap<AccountId, Vec<String>> = HashMap::new();
        let mut out = Vec::new();
        for mut m in rows {
            if closer(&m.preview) || not_a_question(&m.subject) {
                continue;
            }
            if let std::collections::hash_map::Entry::Vacant(e) = own.entry(m.account) {
                e.insert(self.own_addresses(m.account)?);
            }
            let mine = &own[&m.account];
            let mut people = Vec::new();
            for a in m.reply.recipients.split_whitespace() {
                let a = a.to_lowercase();
                if !mine.contains(&a) && !machine_address(&a) && !self.is_list(&a)? {
                    people.push(a);
                }
            }
            if !people.is_empty() {
                m.reply.recipients = people.join(" ");
                out.push(m);
            }
        }
        Ok(out)
    }

    /// The address sends mail one can leave, a newsletter or a list, or
    /// is where a list takes requests to leave it.
    fn is_list(&self, email: &str) -> Result<bool> {
        Ok(self.conn.query_row(
            "SELECT EXISTS (SELECT 1 FROM message WHERE lower(from_email) = ?1
                 AND (newsletter = 1 OR unsubscribe != ''))
             OR EXISTS (SELECT 1 FROM message
                 WHERE unsubscribe != '' AND instr(lower(unsubscribe), 'mailto:' || ?1) > 0)",
            params![email],
            |r| r.get(0),
        )?)
    }

    /// Leaves sent mail out of Waiting, and forgets its reminder; the mail
    /// itself stays in Sent.
    pub fn stop_waiting(&self, account: AccountId, message_id: &str) -> Result<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO waiting_done (account, message_id) VALUES (?1, ?2)",
            params![account.0, message_id],
        )?;
        self.set_reply_reminder(account, message_id, None)
    }

    /// "Remind me if nobody replies": sent mail `message_id` comes back to
    /// the top of the inbox at `at` (Unix seconds) if it still waits for a
    /// reply then. None forgets it. Kept on this device, as Waiting is;
    /// mail not sent yet can have one too, by the Message-ID it will go
    /// with.
    pub fn set_reply_reminder(
        &self,
        account: AccountId,
        message_id: &str,
        at: Option<i64>,
    ) -> Result<()> {
        match at {
            Some(at) => self.conn.execute(
                "INSERT OR REPLACE INTO reply_reminder (account, message_id, at, noticed)
                 VALUES (?1, ?2, ?3, 0)",
                params![account.0, message_id, at],
            )?,
            None => self.conn.execute(
                "DELETE FROM reply_reminder WHERE account = ?1 AND message_id = ?2",
                params![account.0, message_id],
            )?,
        };
        Ok(())
    }

    /// When each reminder of an account (or of all) comes back, by
    /// account and Message-ID.
    pub fn reply_reminders(
        &self,
        account: Option<AccountId>,
    ) -> Result<HashMap<(AccountId, String), i64>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT account, message_id, at FROM reply_reminder
             WHERE ?1 IS NULL OR account = ?1",
        )?;
        let rows = stmt.query_map(params![account.map(|a| a.0)], |r| {
            Ok(((AccountId(r.get(0)?), r.get(1)?), r.get(2)?))
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Mail of Waiting whose reminder has come by `now`, with when: it is
    /// back at the top of the inbox, the latest back first. Mail someone
    /// answered is no longer in Waiting, so its reminder never shows.
    pub fn reminded(
        &self,
        account: Option<AccountId>,
        now: i64,
    ) -> Result<Vec<(MessageSummary, i64)>> {
        let times = self.reply_reminders(account)?;
        if times.is_empty() {
            return Ok(Vec::new());
        }
        let mut out: Vec<(MessageSummary, i64)> = self
            .waiting(account, now)?
            .into_iter()
            .filter_map(|m| {
                let at = *times.get(&(m.account, m.reply.message_id.clone()))?;
                (at <= now).then_some((m, at))
            })
            .collect();
        out.sort_by_key(|(m, at)| (std::cmp::Reverse(*at), std::cmp::Reverse(m.received_at)));
        Ok(out)
    }

    /// The reminders back by `now` that have had no notification yet,
    /// marked as given: each notifies once.
    pub fn take_reminded(&self, now: i64) -> Result<Vec<(MessageSummary, i64)>> {
        let mut out = Vec::new();
        for (m, at) in self.reminded(None, now)? {
            let marked = self.conn.execute(
                "UPDATE reply_reminder SET noticed = 1
                 WHERE account = ?1 AND message_id = ?2 AND noticed = 0",
                params![m.account.0, m.reply.message_id],
            )?;
            if marked > 0 {
                out.push((m, at));
            }
        }
        Ok(out)
    }

    /// Forgets the reminders of an account's sent mail that is no longer
    /// the last word of its conversation: someone replied, or you wrote
    /// again. Waiting leaves the same mail out. Returns how many.
    pub fn drop_answered_reminders(&self, account: AccountId) -> Result<usize> {
        Ok(self.conn.execute(
            "DELETE FROM reply_reminder WHERE account = ?1 AND EXISTS (
                 SELECT 1 FROM message m JOIN message n
                     ON n.account = m.account AND n.thread = m.thread
                 WHERE m.account = reply_reminder.account
                   AND m.message_id = reply_reminder.message_id
                   AND m.folder = 'sent' AND m.thread != '' AND n.hidden = 0
                   AND n.folder != 'drafts' AND n.message_id != m.message_id
                   AND (n.received_at > m.received_at
                        OR (n.received_at = m.received_at AND n.folder != 'sent')))",
            params![account.0],
        )?)
    }

    /// Messages matching a search, newest first, with how many match in
    /// all. Hidden messages are left out.
    pub fn search(&self, query: &Query, limit: u32) -> Result<Found> {
        if query.is_empty() {
            return Ok(Found::default());
        }
        let (sql, mut args, fts) = search_where(query, " FROM message m");
        let total: u32 = self.conn.query_row(
            &format!("SELECT COUNT(*){sql}"),
            rusqlite::params_from_iter(&args),
            |r| r.get(0),
        )?;
        let snippet = if fts {
            "snippet(message_fts, 3, char(2), char(3), '…', 14)"
        } else {
            "''"
        };
        args.push(limit.into());
        let mut stmt = self.conn.prepare(&format!(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list, {snippet},
                    EXISTS (SELECT 1 FROM attachment x
                            WHERE x.account = m.account AND x.mailbox = m.mailbox AND x.uid = m.uid)
             {sql}
             ORDER BY m.received_at DESC, m.account, m.uid DESC
             LIMIT ?{}",
            args.len()
        ))?;
        let hits = stmt
            .query_map(rusqlite::params_from_iter(&args), |r| {
                let snippet: String = r.get(13)?;
                Ok(Hit {
                    message: row_to_summary(r)?,
                    // A body snippet only says something when the body matched.
                    snippet: if snippet.contains('\u{2}') {
                        without_quote_marks(&snippet)
                    } else {
                        String::new()
                    },
                    files: r.get(14)?,
                })
            })?
            .collect::<std::result::Result<_, _>>()?;
        Ok(Found { total, hits })
    }

    /// The files of the messages a search finds, newest message first.
    pub fn search_files(
        &self,
        query: &Query,
        limit: u32,
    ) -> Result<Vec<(MessageSummary, Attachment)>> {
        if query.is_empty() {
            return Ok(Vec::new());
        }
        let (sql, mut args, _) = search_where(
            query,
            " FROM message m JOIN attachment a USING (account, mailbox, uid)",
        );
        args.push(limit.into());
        let mut stmt = self.conn.prepare(&format!(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list,
                    a.part, a.name, a.mime, a.size, a.section, a.encoding
             {sql}
             ORDER BY m.received_at DESC, m.account, m.uid DESC, a.part
             LIMIT ?{}",
            args.len()
        ))?;
        let rows = stmt.query_map(rusqlite::params_from_iter(&args), |r| {
            Ok((row_to_summary(r)?, row_to_attachment(r, 13)?))
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Senders whose name or address matches the search's words, the ones
    /// with the most messages first.
    pub fn search_people(&self, query: &Query, limit: u32) -> Result<Vec<Person>> {
        let Some(expr) = query.people_fts() else {
            return Ok(Vec::new());
        };
        let mut stmt = self.conn.prepare(&format!(
            "SELECT MAX(m.from_name), lower(m.from_email), COUNT(*)
             FROM message m JOIN message_fts ON message_fts.rowid = m.rowid
             WHERE message_fts MATCH ?1 AND m.hidden = 0 AND {PEOPLE}
             GROUP BY lower(m.from_email)
             ORDER BY COUNT(*) DESC, MAX(m.received_at) DESC
             LIMIT ?2"
        ))?;
        let people = stmt
            .query_map(params![expr, limit], |r| {
                Ok(Person {
                    name: r.get(0)?,
                    email: r.get(1)?,
                    messages: r.get(2)?,
                })
            })?
            .collect::<std::result::Result<_, _>>()?;
        Ok(people)
    }

    /// The people the person writes to most since `since` (Unix seconds),
    /// then the ones who write most, each with the account their newest
    /// message came to: the "Frequent contacts" of an empty search. Once
    /// anything sent is on the device, only people written to are listed,
    /// so shops and services that write often stay out.
    pub fn frequent_people(&self, since: i64, limit: u32) -> Result<Vec<(Person, AccountId)>> {
        let mut stmt = self.conn.prepare(&format!(
            "SELECT MAX(m.from_name), lower(m.from_email), COUNT(*),
                    (SELECT n.account FROM message n WHERE lower(n.from_email) = lower(m.from_email)
                     ORDER BY n.received_at DESC LIMIT 1),
                    MAX(m.received_at)
             FROM message m
             WHERE m.hidden = 0 AND m.received_at >= ?1 AND {PEOPLE}
             GROUP BY lower(m.from_email)"
        ))?;
        let mut people = stmt
            .query_map(params![since], |r| {
                Ok((
                    Person {
                        name: r.get(0)?,
                        email: r.get(1)?,
                        messages: r.get(2)?,
                    },
                    AccountId(r.get(3)?),
                    r.get::<_, i64>(4)?,
                ))
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        let mut written: HashMap<String, u32> = HashMap::new();
        let mut stmt = self.conn.prepare(
            "SELECT recipients FROM message
             WHERE folder = 'sent' AND hidden = 0 AND received_at >= ?1",
        )?;
        for row in stmt.query_map(params![since], |r| r.get::<_, String>(0))? {
            for email in row?.split_whitespace() {
                *written.entry(email.to_lowercase()).or_default() += 1;
            }
        }
        let to = |p: &Person| written.get(&p.email).copied().unwrap_or(0);
        if people.iter().any(|(p, _, _)| to(p) > 0) {
            people.retain(|(p, _, _)| to(p) > 0);
        }
        people.sort_by(|(a, _, a_at), (b, _, b_at)| {
            (to(b), b.messages, b_at).cmp(&(to(a), a.messages, a_at))
        });
        Ok(people
            .into_iter()
            .take(limit as usize)
            .map(|(p, account, _)| (p, account))
            .collect())
    }

    /// The people to suggest while an address is typed, as on
    /// `ComposeSuggest`: whose name or address starts with `typed` (any word
    /// of the name), first those written to, then those who wrote, the most
    /// recent first in each. Mail machines, newsletters and the person's
    /// own addresses are left out.
    pub fn suggest_recipients(&self, typed: &str, limit: usize) -> Result<Vec<Suggestion>> {
        let typed = typed.trim().to_lowercase();
        if typed.is_empty() {
            return Ok(Vec::new());
        }
        // Address -> (name, last written to, last wrote).
        let mut known: HashMap<String, (String, i64, i64)> = HashMap::new();
        let mut stmt = self.conn.prepare(&format!(
            "SELECT MAX(m.from_name), lower(m.from_email), MAX(m.received_at)
             FROM message m WHERE m.hidden = 0 AND {PEOPLE}
             GROUP BY lower(m.from_email)"
        ))?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, i64>(2)?,
            ))
        })?;
        for row in rows {
            let (name, email, at) = row?;
            known.insert(email, (name, 0, at));
        }
        let mut stmt = self.conn.prepare(
            "SELECT recipients, received_at FROM message WHERE folder = 'sent' AND hidden = 0
             ORDER BY received_at DESC LIMIT 5000",
        )?;
        let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
        for row in rows {
            let (recipients, at) = row?;
            for email in recipients.split_whitespace() {
                let entry = known.entry(email.to_lowercase()).or_default();
                entry.1 = entry.1.max(at);
            }
        }
        let own: HashSet<String> = self
            .conn
            .prepare(
                "SELECT lower(email) FROM account UNION SELECT lower(email) FROM account_alias",
            )?
            .query_map([], |r| r.get(0))?
            .collect::<rusqlite::Result<_>>()?;
        let mut found: Vec<(String, (String, i64, i64))> = known
            .into_iter()
            .filter(|(email, (name, _, _))| {
                let name = name.to_lowercase();
                !own.contains(email)
                    && !machine_address(email)
                    && (email.starts_with(&typed)
                        || name.starts_with(&typed)
                        || name
                            .split(|c: char| c.is_whitespace() || c == '.' || c == '-')
                            .any(|w| w.starts_with(&typed)))
            })
            .collect();
        // Written to first, newest first; then who wrote, newest first.
        found.sort_by(|(a_email, a), (b_email, b)| {
            ((b.1 > 0), b.1, b.2)
                .cmp(&((a.1 > 0), a.1, a.2))
                .then_with(|| a_email.cmp(b_email))
        });
        Ok(found
            .into_iter()
            .take(limit)
            .map(|(email, (name, written, _))| Suggestion {
                name,
                email,
                written_to: written > 0,
            })
            .collect())
    }

    /// What was searched lately, the newest first.
    pub fn recent_searches(&self) -> Result<Vec<String>> {
        Ok(self
            .setting(RECENT_SEARCHES)?
            .unwrap_or_default()
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(str::to_owned)
            .collect())
    }

    /// Keeps a search at the top of the recent ones (at most
    /// [`RECENT_SEARCHES_KEPT`]), or with `forget` takes it out.
    pub fn note_search(&self, query: &str, forget: bool) -> Result<()> {
        let query = query.split_whitespace().collect::<Vec<_>>().join(" ");
        let mut recent = self.recent_searches()?;
        recent.retain(|q| *q != query);
        if !forget && !query.is_empty() {
            recent.insert(0, query);
        }
        recent.truncate(RECENT_SEARCHES_KEPT);
        self.set_setting(RECENT_SEARCHES, &recent.join("\n"))
    }

    /// Forgets every recent search.
    pub fn clear_searches(&self) -> Result<()> {
        self.set_setting(RECENT_SEARCHES, "")
    }

    /// How many messages on this device a search looks through: all of
    /// them, or one account's with `account:`, or one group's with `group:`.
    pub fn indexed(&self, query: &Query) -> Result<u32> {
        let group = query
            .group
            .map_or(String::new(), |g| crate::groups::Within::Group(g).sql());
        Ok(self.conn.query_row(
            &format!(
                "SELECT COUNT(*) FROM message m
                 WHERE m.hidden = 0 AND (?1 IS NULL OR m.account IN
                    (SELECT id FROM account WHERE lower(name) = lower(?1) OR lower(email) = lower(?1))){group}"
            ),
            params![query.account],
            |r| r.get(0),
        )?)
    }

    /// Builds the search index again from the messages.
    pub fn rebuild_search_index(&self) -> Result<()> {
        self.conn.execute_batch(
            "DELETE FROM message_fts;
             INSERT INTO message_fts (rowid, subject, sender, preview, body)
             SELECT m.rowid, m.subject, m.from_name || ' ' || m.from_email, m.preview, COALESCE(b.text, '')
             FROM message m LEFT JOIN message_body b USING (account, mailbox, uid);",
        )?;
        Ok(())
    }
}

/// A search's answer.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Found {
    /// How many messages match in all; `hits` holds the newest of them.
    pub total: u32,
    pub hits: Vec<Hit>,
}

/// The FROM and WHERE of a search over `from` (which names the message
/// `m`), its arguments, and whether it matches words.
fn search_where(query: &Query, from: &str) -> (String, Vec<rusqlite::types::Value>, bool) {
    let fts = query.fts();
    let mut sql = String::from(from);
    let mut args: Vec<rusqlite::types::Value> = Vec::new();
    // Numbered placeholders, so the account filter can use its value twice.
    if let Some(expr) = &fts {
        args.push(expr.clone().into());
        sql.push_str(" JOIN message_fts ON message_fts.rowid = m.rowid WHERE message_fts MATCH ?1");
    } else {
        sql.push_str(" WHERE 1");
    }
    sql.push_str(" AND m.hidden = 0");
    if let Some(account) = &query.account {
        args.push(account.clone().into());
        let n = args.len();
        sql.push_str(&format!(
                " AND m.account IN (SELECT id FROM account WHERE lower(name) = lower(?{n}) OR lower(email) = lower(?{n}))"
            ));
    }
    if let Some(group) = query.group {
        sql.push_str(&crate::groups::Within::Group(group).sql());
    }
    if let Some(label) = &query.label {
        args.push(label.clone().into());
        sql.push_str(&format!(
            " AND EXISTS (SELECT 1 FROM message_labels ml
                     WHERE ml.account = m.account AND ml.mailbox = m.mailbox AND ml.uid = m.uid
                       AND instr(' ' || ml.labels || ' ',
                                 ' ' || (SELECT keyword FROM label WHERE name = ?{} COLLATE NOCASE) || ' ') > 0)",
            args.len()
        ));
    }
    if query.unread {
        sql.push_str(" AND (m.flags & 1) = 0");
    }
    if let Some(after) = query.after {
        args.push(after.into());
        sql.push_str(&format!(" AND m.received_at >= ?{}", args.len()));
    }
    if let Some(before) = query.before {
        args.push(before.into());
        sql.push_str(&format!(" AND m.received_at < ?{}", args.len()));
    }
    if query.attachment {
        sql.push_str(
            " AND EXISTS (SELECT 1 FROM attachment a
                     WHERE a.account = m.account AND a.mailbox = m.mailbox AND a.uid = m.uid)",
        );
    }
    if query.vault {
        sql.push_str(
            " AND EXISTS (SELECT 1 FROM vault_card v
                     WHERE v.account = m.account AND v.mailbox = m.mailbox AND v.uid = m.uid)",
        );
    }
    if query.newsletter {
        sql.push_str(" AND (m.newsletter = 1 OR m.folder = 'newsletters')");
    }
    if query.people {
        sql.push_str(&format!(" AND {PEOPLE}"));
    }
    (sql, args, fts.is_some())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hit {
    pub message: MessageSummary,
    /// Where the body matched, with each match between `\u{2}` and
    /// `\u{3}`. Empty when the body didn't match.
    pub snippet: String,
    /// Whether it came with files.
    pub files: bool,
}

/// Someone who wrote to the person.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Person {
    pub name: String,
    pub email: String,
    pub messages: u32,
}

/// Why an email's sender isn't who they say: see
/// [`Store::sender_warning`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SenderWarning {
    pub kind: WarningKind,
    /// The domain in From, as written.
    pub domain: String,
    pub dmarc_failed: bool,
    /// What its Details list: whose signature passed, and the server that
    /// sent it.
    pub signed_by: Option<String>,
    pub sent_by: Option<String>,
}

/// The band's one line, most telling first.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WarningKind {
    /// "paypa1.com looks like paypal.com", which sent `count` emails.
    LooksLike { like: String, count: u32 },
    /// "The name says PayPal, but the address is at …".
    Brand { brand: String },
    /// "This email says it's from paypal.com, but paypal.com didn't send
    /// it."
    DmarcFailed,
}

/// Someone suggested while an address is typed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Suggestion {
    pub name: String,
    /// The address, lowercase.
    pub email: String,
    /// Written to from here ("Wrote to"), or only wrote ("Wrote to you").
    pub written_to: bool,
}

/// One address a sender writes from, for their card's Addresses.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SenderAddress {
    /// Lowercase.
    pub email: String,
    /// The account most of its emails arrived in.
    pub account: AccountId,
    pub emails: u32,
    /// A server vouched for at least one of its emails.
    pub verified: bool,
}

/// A conversation as a list shows it: its newest message in the folder
/// and how many messages it has in all.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Conversation {
    pub latest: MessageSummary,
    /// The thread's key: what [`Store::conversation`] takes.
    pub thread: String,
    pub messages: u32,
}

/// Keeps `m` (aliased) only when no newer message of its thread is in the
/// same folder.
const NEWEST_IN_THREAD: &str = "NOT EXISTS (
    SELECT 1 FROM message n
    WHERE n.account = m.account AND n.thread = m.thread AND n.folder = m.folder
      AND n.hidden = 0
      AND (n.received_at > m.received_at
           OR (n.received_at = m.received_at AND n.uid > m.uid)))";

/// Like [`NEWEST_IN_THREAD`], within one server folder.
const NEWEST_IN_MAILBOX: &str = "NOT EXISTS (
    SELECT 1 FROM message n
    WHERE n.account = m.account AND n.thread = m.thread AND n.mailbox = m.mailbox
      AND n.hidden = 0
      AND (n.received_at > m.received_at
           OR (n.received_at = m.received_at AND n.uid > m.uid)))";

/// The thread a message belongs to: the thread of the first message it
/// refers to that is already stored, else the first id it refers to (the
/// start of the thread), else its own id.
/// How far back Waiting looks in Sent.
pub const WAITING_DAYS: i64 = 30;

/// Whether sent text only closes a conversation ("Thanks!", "Ok, great"):
/// a few words, all of them thanks or agreement.
fn closer(preview: &str) -> bool {
    const WORDS: &[&str] = &[
        "thanks",
        "thank",
        "you",
        "thx",
        "ty",
        "many",
        "a",
        "lot",
        "so",
        "much",
        "ok",
        "okay",
        "great",
        "perfect",
        "cheers",
        "got",
        "it",
        "sounds",
        "good",
        "noted",
        "will",
        "do",
        "grazie",
        "mille",
        "ottimo",
        "perfetto",
        "va",
        "bene",
        "benissimo",
        "ricevuto",
        "certo",
        "👍",
        "🙏",
        "best",
        "regards",
    ];
    // Previews are one line and keep the "On …, Luca wrote:" line of a
    // quote: the words before it are the reply's own.
    let mut first = preview.lines().next().unwrap_or("");
    if let Some(at) = ["wrote:", "scritto:"]
        .iter()
        .filter_map(|w| first.find(w))
        .min()
    {
        let head = &first[..at];
        let start = [" On ", " Il ", " Le "]
            .iter()
            .filter_map(|w| head.rfind(w))
            .max()
            .unwrap_or(0);
        first = &first[..start];
    }
    if let Some(at) = first.find("-- ") {
        first = &first[..at];
    }
    let words: Vec<String> = first
        .split(|c: char| c.is_whitespace() || c == ',')
        .map(|w| {
            w.trim_matches(|c: char| c.is_ascii_punctuation())
                .to_lowercase()
        })
        .filter(|w| !w.is_empty())
        .collect();
    !words.is_empty() && words.len() <= 5 && words.iter().all(|w| WORDS.contains(&w.as_str()))
}

/// Sent mail that asks nobody anything: a request to leave a list, or a
/// forward passing something on.
fn not_a_question(subject: &str) -> bool {
    let s = subject.trim().to_lowercase();
    forwarded(&s)
        || ["unsubscribe", "disiscri", "cancellami"]
            .iter()
            .any(|w| s.contains(w))
}

/// Whether a subject says a person passed something on.
fn forwarded(subject: &str) -> bool {
    let s = subject.trim_start().to_lowercase();
    ["fwd:", "fw:", "i:", "inoltro:", "tr:", "wg:", "rv:", "enc:"]
        .iter()
        .any(|p| s.starts_with(p))
}

/// How far back a reply without References looks for its conversation.
const SUBJECT_THREAD_DAYS: i64 = 60;

/// A reply's subject without "Re:", when it is a reply and says nothing
/// of what it answers: no References or In-Reply-To.
fn bare_reply(m: &MessageSummary) -> Option<String> {
    if !m.reply.references.trim().is_empty() {
        return None;
    }
    let subject = m.subject.trim();
    let lower = subject.to_lowercase();
    let reply = ["re:", "r:", "rif:", "aw:", "sv:", "antw:"]
        .iter()
        .any(|p| lower.starts_with(p));
    let bare = crate::brief::bare_subject(subject);
    (reply && !bare.is_empty()).then_some(bare)
}

/// Whether [m] and a message from [from] to [to] (addresses, space
/// separated) share someone besides the account itself ([own]).
fn talked(m: &MessageSummary, from: &str, to: &str, own: &[String]) -> bool {
    let people = |from: &str, to: &str| -> HashSet<String> {
        std::iter::once(from)
            .chain(to.split_whitespace())
            .map(str::to_lowercase)
            .filter(|a| !a.is_empty() && !own.contains(a))
            .collect()
    };
    let theirs = people(from, to);
    people(&m.from_email, &m.reply.recipients)
        .iter()
        .any(|a| theirs.contains(a))
}

fn thread_of(
    m: &MessageSummary,
    mut known: impl FnMut(&str) -> rusqlite::Result<Option<String>>,
) -> Result<String> {
    let refs: Vec<&str> = m.reply.references.split_whitespace().collect();
    for id in &refs {
        if let Some(thread) = known(id)? {
            return Ok(thread);
        }
    }
    Ok(match (refs.first(), m.reply.message_id.as_str()) {
        (Some(first), _) => (*first).to_owned(),
        (None, "") => format!("{}/{}/{}", m.account.0, m.mailbox, m.uid),
        (None, id) => id.to_owned(),
    })
}

/// An attachment from `part, name, mime, size, section, encoding` at
/// column `at`.
fn row_to_attachment(r: &rusqlite::Row<'_>, at: usize) -> rusqlite::Result<Attachment> {
    Ok(Attachment {
        part: r.get(at)?,
        name: r.get(at + 1)?,
        mime: r.get(at + 2)?,
        size: r.get::<_, i64>(at + 3)? as u64,
        section: r.get(at + 4)?,
        encoding: r.get(at + 5)?,
    })
}

fn row_to_summary(r: &rusqlite::Row<'_>) -> rusqlite::Result<MessageSummary> {
    Ok(MessageSummary {
        account: AccountId(r.get(0)?),
        mailbox: r.get(1)?,
        uid: r.get(2)?,
        from_name: r.get(3)?,
        from_email: r.get(4)?,
        subject: r.get(5)?,
        preview: r.get(6)?,
        received_at: r.get(7)?,
        flags: Flags::from_bits(r.get(8)?),
        reply: ReplyInfo {
            message_id: r.get(9)?,
            references: r.get(10)?,
            reply_to: r.get(11)?,
            recipients: String::new(),
        },
        to: r.get(12)?,
        list: ListInfo::default(),
    })
}

/// Folders in tree order, each run of siblings sorted by the rank the
/// person gave them (unranked ones after, in the server's order), every
/// folder still followed by its subfolders.
fn arrange(rows: &[(AccountFolder, Option<i64>)]) -> Vec<AccountFolder> {
    let mut out = Vec::with_capacity(rows.len());
    arrange_into(rows, &mut out);
    out
}

fn arrange_into(rows: &[(AccountFolder, Option<i64>)], out: &mut Vec<AccountFolder>) {
    let Some(top) = rows.iter().map(|(f, _)| f.depth).min() else {
        return;
    };
    // Each sibling with the folders under it, up to the next sibling.
    let mut blocks: Vec<&[(AccountFolder, Option<i64>)]> = Vec::new();
    let mut start = 0;
    for i in 1..=rows.len() {
        if i == rows.len() || rows[i].0.depth <= top {
            blocks.push(&rows[start..i]);
            start = i;
        }
    }
    blocks.sort_by_key(|b| b[0].1.map_or((1, 0), |rank| (0, rank)));
    for block in blocks {
        out.push(block[0].0.clone());
        arrange_into(&block[1..], out);
    }
}

/// A body snippet without the `>` that mark quoted replies: the body is
/// indexed as one run of words, so they show as "you! > > > >".
fn without_quote_marks(snippet: &str) -> String {
    snippet
        .split(' ')
        .filter(|w| w.is_empty() || !w.chars().all(|c| c == '>'))
        .collect::<Vec<_>>()
        .join(" ")
}

impl Store {
    /// An account's away message, as last set on this device.
    pub fn away_message(&self, account: AccountId) -> Result<Option<crate::away::Stored>> {
        Ok(self
            .away_messages()?
            .into_iter()
            .find(|(a, _)| *a == account)
            .map(|(_, s)| s))
    }

    /// Every account's away message, by account.
    pub fn away_messages(&self) -> Result<Vec<(AccountId, crate::away::Stored)>> {
        let mut stmt = self.conn.prepare_cached(
            "SELECT account, enabled, start_day, end_day, subject, body, zone, placed, device_dates
             FROM away_message ORDER BY account",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok((
                AccountId(r.get(0)?),
                crate::away::Stored {
                    message: crate::away::AwayMessage {
                        on: r.get(1)?,
                        start: r.get(2)?,
                        end: r.get(3)?,
                        subject: r.get(4)?,
                        body: r.get(5)?,
                    },
                    zone: r.get(6)?,
                    placed: r.get(7)?,
                    device_dates: r.get(8)?,
                },
            ))
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn set_away_message(&self, account: AccountId, s: &crate::away::Stored) -> Result<()> {
        let m = &s.message;
        self.conn.execute(
            "INSERT OR REPLACE INTO away_message
                (account, enabled, start_day, end_day, subject, body, zone, placed, device_dates)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                account.0,
                m.on,
                m.start,
                m.end,
                m.subject,
                m.body,
                s.zone,
                s.placed,
                s.device_dates
            ],
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {

    #[test]
    fn snippets_drop_quote_marks() {
        assert_eq!(
            without_quote_marks("Thank \u{2}you\u{3}! > > >> See you"),
            "Thank \u{2}you\u{3}! See you"
        );
    }
    use super::*;
    use std::collections::HashSet;
    use std::sync::Mutex;

    #[test]
    fn sender_pictures_are_kept_per_domain() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        store.upsert_messages(&[msg(a, 1, 100, false)]).unwrap();
        assert!(!store.domain_verified("bank.example").unwrap());
        let raw =
            b"Authentication-Results: mx.example.org; dmarc=pass header.from=bank.example\r\n\
From: <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";
        store
            .set_full_body(a, "INBOX", 1, &crate::imap::parse_body(raw))
            .unwrap();
        let from = store
            .conn
            .query_row("SELECT from_email FROM message WHERE uid = 1", [], |r| {
                r.get::<_, String>(0)
            })
            .unwrap();
        let domain = from.rsplit_once('@').unwrap().1.to_ascii_lowercase();
        assert!(store.domain_verified(&domain).unwrap());
        assert!(!store.domain_verified("other.example").unwrap());

        assert_eq!(store.sender_picture("bank.example").unwrap(), None);
        let logo = crate::pictures::Picture {
            kind: crate::pictures::Kind::Logo,
            png: vec![1, 2, 3],
        };
        store
            .set_sender_picture("bank.example", &logo, 500)
            .unwrap();
        store
            .set_sender_picture("shop.example", &crate::pictures::Picture::none(), 600)
            .unwrap();
        assert_eq!(
            store.sender_picture("bank.example").unwrap(),
            Some((logo, 500))
        );
        assert_eq!(
            store
                .sender_picture("shop.example")
                .unwrap()
                .unwrap()
                .0
                .kind,
            crate::pictures::Kind::None
        );
        store.clear_sender_pictures().unwrap();
        assert_eq!(store.sender_picture("bank.example").unwrap(), None);
    }

    #[test]
    fn a_body_keeps_whether_its_sender_is_verified() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        store
            .upsert_messages(&[msg(a, 1, 100, false), msg(a, 2, 200, false)])
            .unwrap();
        let raw =
            b"Authentication-Results: mx.example.org; dmarc=pass header.from=bank.example\r\n\
From: <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";
        store
            .set_full_body(a, "INBOX", 1, &crate::imap::parse_body(raw))
            .unwrap();
        assert!(store.sender_verified(a, "INBOX", 1).unwrap());
        // Without the server's word, or for a message not here, no mark.
        store
            .set_full_body(
                a,
                "INBOX",
                2,
                &crate::imap::parse_body(b"From: <x@bank.example>\r\n\r\nHi"),
            )
            .unwrap();
        assert!(!store.sender_verified(a, "INBOX", 2).unwrap());
        assert!(!store.sender_verified(a, "INBOX", 3).unwrap());
    }

    #[test]
    fn senders_who_arent_who_they_say_get_a_warning() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        let from = |uid: u32, name: &str, email: &str| MessageSummary {
            from_name: name.into(),
            from_email: email.into(),
            ..msg(a, uid, uid as i64 * 100, false)
        };
        store
            .upsert_messages(&[
                from(1, "Studio", "anna@ferramentabianchi.it"),
                from(2, "Studio", "luca@ferramentabianchi.it"),
                from(3, "Studio", "luca@ferramentabianchi.it"),
                from(4, "PayPal", "service@paypa1.com"),
                from(5, "PayPal", "help@fastpay-secure.example"),
                from(6, "Luca", "luca@ferramentabianci.it"),
                from(7, "Bank", "help@bank.example"),
                from(8, "PayPal", "a.friend@gmail.com"),
                from(9, "Me", "a@example.org"),
            ])
            .unwrap();
        let body = |raw: &str| crate::imap::parse_body(raw.as_bytes());
        let pass = "Authentication-Results: mx.example.org; dmarc=pass header.from=ferramentabianchi.it\r\n\
From: <luca@ferramentabianchi.it>\r\n\r\nHi";
        store.set_full_body(a, "INBOX", 1, &body(pass)).unwrap();
        // Nothing to say about the real one.
        assert_eq!(store.sender_warning(a, "INBOX", 1).unwrap(), None);
        // Nor before the body is here.
        assert_eq!(store.sender_warning(a, "INBOX", 4).unwrap(), None);
        let plain = "From: <x@y.example>\r\n\r\nHi";
        for uid in [4, 5, 6, 8] {
            store.set_full_body(a, "INBOX", uid, &body(plain)).unwrap();
        }
        let kind = |uid| {
            store
                .sender_warning(a, "INBOX", uid)
                .unwrap()
                .map(|w| w.kind)
        };
        assert_eq!(
            kind(4),
            Some(WarningKind::LooksLike {
                like: "paypal.com".into(),
                count: 0
            })
        );
        assert_eq!(
            kind(5),
            Some(WarningKind::Brand {
                brand: "PayPal".into()
            })
        );
        assert_eq!(
            kind(6),
            Some(WarningKind::LooksLike {
                like: "ferramentabianchi.it".into(),
                count: 3
            })
        );
        assert_eq!(
            kind(8),
            Some(WarningKind::Brand {
                brand: "PayPal".into()
            })
        );
        // Someone written to borrows nothing, even at a shared domain; the
        // others at a shared domain still do.
        store
            .conn
            .execute(
                "UPDATE message SET folder = 'sent', recipients = 'luca@ferramentabianci.it'
                 WHERE uid = 9",
                [],
            )
            .unwrap();
        assert_eq!(kind(6), None);
        // A failed DMARC check, from the account's own server.
        let fail =
            "Authentication-Results: mx.example.org; dmarc=fail header.from=bank.example\r\n\
Received: from mail.elsewhere.example (mail.elsewhere.example [203.0.113.9]) by mx.example.org\r\n\
From: <help@bank.example>\r\n\r\nHi";
        store.set_full_body(a, "INBOX", 7, &body(fail)).unwrap();
        let w = store.sender_warning(a, "INBOX", 7).unwrap().unwrap();
        assert_eq!(w.kind, WarningKind::DmarcFailed);
        assert_eq!(w.domain, "bank.example");
        assert_eq!(w.sent_by.as_deref(), Some("mail.elsewhere.example"));
        assert_eq!(w.signed_by, None);
        // A message cached before sender_check existed, or with a generic
        // "Servizio Clienti" sender and an Aruba banner in the body, is
        // still checked.
        store
            .upsert_messages(&[MessageSummary {
                subject: "⚠️ Ultimo avviso! Il tuo dominio sta per essere sospeso".into(),
                from_name: "Servizio Clienti".into(),
                from_email: "info@rinnovo-domini.example".into(),
                ..msg(a, 10, 1000, false)
            }])
            .unwrap();
        let phishing = "From: Servizio Clienti <info@rinnovo-domini.example>\r\n\r\naruba.it\nIl tuo dominio è stato sospeso";
        store
            .set_full_body(a, "INBOX", 10, &body(phishing))
            .unwrap();
        store
            .conn
            .execute("DELETE FROM sender_check WHERE uid = 10", [])
            .unwrap();
        assert_eq!(
            store
                .sender_warning(a, "INBOX", 10)
                .unwrap()
                .map(|w| w.kind),
            Some(WarningKind::Brand {
                brand: "Aruba".into()
            })
        );
    }

    #[test]
    fn previews_stored_before_are_cleaned_once() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        let pad = "\u{034F} \u{200C} ".repeat(20);
        let mut padded = msg(a, 1, 100, false);
        padded.preview = format!("Guarda le scelte degli altri {pad}...");
        let mut css = msg(a, 2, 200, false);
        css.preview = "blockquote:before { content: none !important; } q:befor...".into();
        store
            .upsert_messages(&[padded, css, msg(a, 3, 300, false)])
            .unwrap();
        store
            .conn
            .pragma_update(None, "user_version", CLEAN_PREVIEWS - 1)
            .unwrap();
        store.migrate().unwrap();
        let preview = |uid: u32| -> String {
            store
                .conn
                .query_row("SELECT preview FROM message WHERE uid = ?1", [uid], |r| {
                    r.get(0)
                })
                .unwrap()
        };
        assert_eq!(preview(1), "Guarda le scelte degli altri");
        assert_eq!(preview(2), "");
        assert_eq!(preview(3), "Here is the updated version");
        assert_eq!(store.schema_version().unwrap(), MIGRATIONS.len());
    }

    fn imap_account(name: &str, email: &str, color: &str) -> Account {
        Account {
            id: AccountId(0),
            name: name.into(),
            email: email.into(),
            sender_name: "Matteo Neri".into(),
            color: color.into(),
            kind: AccountKind::Imap {
                imap: Server {
                    host: "imap.example.org".into(),
                    port: 993,
                    security: Security::Tls,
                },
                smtp: Server {
                    host: "smtp.example.org".into(),
                    port: 587,
                    security: Security::StartTls,
                },
                username: email.into(),
            },
        }
    }

    fn msg(account: AccountId, uid: u32, at: i64, seen: bool) -> MessageSummary {
        MessageSummary {
            account,
            mailbox: "INBOX".into(),
            uid,
            from_name: "Julia Reed".into(),
            from_email: "julia@example.org".into(),
            to: "Matteo".into(),
            subject: format!("Message {uid}"),
            preview: "Here is the updated version".into(),
            received_at: at,
            flags: Flags {
                seen,
                ..Flags::default()
            },
            reply: ReplyInfo::default(),
            list: ListInfo::default(),
        }
    }

    #[test]
    fn replies_without_references_join_by_subject_and_people() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        let mail = |uid, at, from: &str, to: &str, subject: &str| MessageSummary {
            from_email: from.into(),
            subject: subject.into(),
            reply: ReplyInfo {
                message_id: format!("<m{uid}@example.org>"),
                recipients: to.into(),
                ..ReplyInfo::default()
            },
            ..msg(a, uid, at, true)
        };
        store
            .upsert_messages(&[
                mail(1, 100, "julia@example.org", "matteo@studio.it", "Quote"),
                // A reply from a client that sends no References.
                mail(2, 200, "matteo@studio.it", "julia@example.org", "Re: Quote"),
                mail(
                    3,
                    300,
                    "julia@example.org",
                    "matteo@studio.it",
                    "RE: re: quote",
                ),
                // Same words, other people: its own conversation.
                mail(4, 400, "anna@example.org", "matteo@studio.it", "Re: Quote"),
                // Not a reply: same subject, still its own.
                mail(5, 500, "julia@example.org", "matteo@studio.it", "Quote"),
            ])
            .unwrap();
        let thread = |store: &Store, uid| store.thread_of(a, "INBOX", uid).unwrap();
        let first = thread(&store, 1);
        assert_eq!(thread(&store, 2), first);
        assert_eq!(thread(&store, 3), first);
        assert_ne!(thread(&store, 4), first);
        assert_ne!(thread(&store, 5), first);
        // Too long after, it starts again.
        store
            .upsert_messages(&[mail(
                6,
                100 + (SUBJECT_THREAD_DAYS + 1) * 86_400 + 300,
                "matteo@studio.it",
                "julia@example.org",
                "Re: Quote",
            )])
            .unwrap();
        assert_ne!(thread(&store, 6), first);
    }

    #[test]
    fn waiting_keeps_sent_mail_nobody_answered() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let day = 86_400;
        let now = 100 * day;
        let sent = |uid, at, to: &str, preview: &str, refs: &str| MessageSummary {
            mailbox: "Sent".into(),
            from_email: "matteo@studio.it".into(),
            preview: preview.into(),
            reply: ReplyInfo {
                message_id: format!("<s{uid}@studio.it>"),
                references: refs.into(),
                recipients: to.into(),
                ..ReplyInfo::default()
            },
            ..msg(a, uid, at, true)
        };
        store
            .upsert_messages(&[
                sent(
                    1,
                    now - 5 * day,
                    "julia@example.org matteo@studio.it",
                    "Can you send the quote?",
                    "",
                ),
                sent(
                    2,
                    now - 4 * day,
                    "anna@example.org",
                    "Are we still on for Friday?",
                    "",
                ),
                sent(
                    3,
                    now - 3 * day,
                    "luca@example.org",
                    "Thanks! On Oct 2, Luca wrote: here",
                    "",
                ),
                sent(
                    4,
                    now - 2 * day,
                    "noreply@shop.example",
                    "Where is my parcel?",
                    "",
                ),
                sent(
                    5,
                    now - 2 * day,
                    "matteo@studio.it",
                    "Note to self about taxes",
                    "",
                ),
                sent(6, now - 40 * day, "paolo@example.org", "Long ago", ""),
                sent(7, now - day, "news@list.example", "Please remove me", ""),
            ])
            .unwrap();
        // Anna answered.
        store
            .upsert_messages(&[MessageSummary {
                from_email: "anna@example.org".into(),
                reply: ReplyInfo {
                    message_id: "<a1@example.org>".into(),
                    references: "<s2@studio.it>".into(),
                    ..ReplyInfo::default()
                },
                ..msg(a, 20, now - 3 * day, false)
            }])
            .unwrap();
        // The list sends newsletters.
        store
            .upsert_messages(&[MessageSummary {
                from_email: "news@list.example".into(),
                list: ListInfo {
                    unsubscribe: "https://list.example/u".into(),
                    ..ListInfo::default()
                },
                ..msg(a, 21, now - 6 * day, false)
            }])
            .unwrap();
        let uids = |store: &Store| -> Vec<u32> {
            store
                .waiting(None, now)
                .unwrap()
                .iter()
                .map(|m| m.uid)
                .collect()
        };
        assert_eq!(uids(&store), [1]);
        assert_eq!(
            store.waiting(None, now).unwrap()[0].reply.recipients,
            "julia@example.org"
        );
        // Writing again: the newer one waits instead.
        store
            .upsert_messages(&[sent(
                8,
                now - day,
                "julia@example.org",
                "Any news on the quote?",
                "<s1@studio.it>",
            )])
            .unwrap();
        assert_eq!(uids(&store), [8]);
        store.stop_waiting(a, "<s8@studio.it>").unwrap();
        assert!(uids(&store).is_empty());
        assert!(store.waiting(Some(a), now).unwrap().is_empty());
    }

    /// A store with Luca's quote in Sent, sent at `sent_at`, waiting for
    /// a reply.
    fn quote_waiting(sent_at: i64) -> (Store, AccountId) {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        store
            .upsert_messages(&[MessageSummary {
                mailbox: "Sent".into(),
                from_email: "matteo@studio.it".into(),
                subject: "Quote for the Acme site".into(),
                preview: "Here is the quote for the new site.".into(),
                reply: ReplyInfo {
                    message_id: "<q1@studio.it>".into(),
                    recipients: "luca@example.org".into(),
                    ..ReplyInfo::default()
                },
                ..msg(a, 1, sent_at, true)
            }])
            .unwrap();
        (store, a)
    }

    #[test]
    fn a_reminder_is_kept_for_waiting_mail() {
        let day = 86_400;
        let now = 100 * day;
        let (store, a) = quote_waiting(now);
        assert!(store.reply_reminders(None).unwrap().is_empty());
        store
            .set_reply_reminder(a, "<q1@studio.it>", Some(now + 3 * day))
            .unwrap();
        assert_eq!(
            store.reply_reminders(Some(a)).unwrap()[&(a, "<q1@studio.it>".to_owned())],
            now + 3 * day
        );
        // Not back yet; the watcher looks again then.
        assert!(store.reminded(None, now + day).unwrap().is_empty());
        assert_eq!(store.next_due(a, now).unwrap(), Some(now + 3 * day));
        // Picked again, the later time stands; Don't remind me forgets it.
        store
            .set_reply_reminder(a, "<q1@studio.it>", Some(now + 7 * day))
            .unwrap();
        assert_eq!(store.next_due(a, now).unwrap(), Some(now + 7 * day));
        store.set_reply_reminder(a, "<q1@studio.it>", None).unwrap();
        assert!(store.reply_reminders(None).unwrap().is_empty());
        assert_eq!(store.next_due(a, now).unwrap(), None);
        // Stop waiting forgets it too.
        store
            .set_reply_reminder(a, "<q1@studio.it>", Some(now + day))
            .unwrap();
        store.stop_waiting(a, "<q1@studio.it>").unwrap();
        assert!(store.reply_reminders(None).unwrap().is_empty());
    }

    #[test]
    fn a_reminder_comes_back_when_due_and_notifies_once() {
        let day = 86_400;
        let now = 100 * day;
        let (store, a) = quote_waiting(now);
        let at = now + 3 * day;
        store
            .set_reply_reminder(a, "<q1@studio.it>", Some(at))
            .unwrap();
        let back = store.reminded(Some(a), at).unwrap();
        assert_eq!(back.len(), 1);
        assert_eq!((back[0].0.uid, back[0].1), (1, at));
        // Only the people it waits on.
        assert_eq!(back[0].0.reply.recipients, "luca@example.org");
        // Passed, the watcher no longer waits for it.
        assert_eq!(store.next_due(a, at).unwrap(), None);
        let told = store.take_reminded(at + 60).unwrap();
        assert_eq!(told.len(), 1);
        assert!(store.take_reminded(at + 120).unwrap().is_empty());
        // It stays at the top of the inbox until someone answers.
        assert_eq!(store.reminded(None, at + day).unwrap().len(), 1);
    }

    #[test]
    fn a_reply_takes_the_reminder_away() {
        let day = 86_400;
        let now = 100 * day;
        let (mut store, a) = quote_waiting(now);
        store
            .set_reply_reminder(a, "<q1@studio.it>", Some(now + 3 * day))
            .unwrap();
        assert_eq!(store.drop_answered_reminders(a).unwrap(), 0);
        // Luca answers the next day.
        store
            .upsert_messages(&[MessageSummary {
                from_email: "luca@example.org".into(),
                reply: ReplyInfo {
                    message_id: "<l1@example.org>".into(),
                    references: "<q1@studio.it>".into(),
                    ..ReplyInfo::default()
                },
                ..msg(a, 20, now + day, false)
            }])
            .unwrap();
        assert!(store.reminded(None, now + 3 * day).unwrap().is_empty());
        assert_eq!(store.drop_answered_reminders(a).unwrap(), 1);
        assert!(store.reply_reminders(None).unwrap().is_empty());
        assert!(store.take_reminded(now + 4 * day).unwrap().is_empty());
    }

    #[test]
    fn waiting_leaves_out_leaving_lists_and_forwards() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let day = 86_400;
        let now = 100 * day;
        let sent = |uid, to: &str, subject: &str| MessageSummary {
            mailbox: "Sent".into(),
            from_email: "matteo@studio.it".into(),
            subject: subject.into(),
            preview: "Hello".into(),
            reply: ReplyInfo {
                message_id: format!("<s{uid}@studio.it>"),
                recipients: to.into(),
                ..ReplyInfo::default()
            },
            ..msg(a, uid, now - day, true)
        };
        store
            .upsert_messages(&[
                sent(1, "32.mrtvg2@unsub.shop.example", "Unsubscribe"),
                sent(2, "luca@example.org", "Fwd: the tickets"),
                sent(3, "leave-42@lists.example", "Hello"),
                sent(4, "anna@example.org", ""),
            ])
            .unwrap();
        // A list that takes requests to leave by mail.
        store
            .upsert_messages(&[MessageSummary {
                from_email: "digest@lists.example".into(),
                list: ListInfo {
                    unsubscribe: "<mailto:Leave-42@lists.example>".into(),
                    ..ListInfo::default()
                },
                ..msg(a, 20, now - 5 * day, false)
            }])
            .unwrap();
        let uids: Vec<u32> = store
            .waiting(None, now)
            .unwrap()
            .iter()
            .map(|m| m.uid)
            .collect();
        assert_eq!(uids, [4]);
    }

    #[test]
    fn a_sender_writes_from_the_addresses_with_their_name() {
        let mut store = Store::open_in_memory().unwrap();
        let work = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        let home = store
            .add_account(&imap_account("Personal", "matteo@posta.it", "#E0782F"))
            .unwrap();
        let from = |account, uid, name: &str, email: &str| MessageSummary {
            from_name: name.into(),
            from_email: email.into(),
            ..msg(account, uid, 100 + uid as i64, true)
        };
        store
            .upsert_messages(&[
                from(work, 1, "Luca Bianchi", "luca@ferramenta.it"),
                from(work, 2, "Luca Bianchi", "Luca@Ferramenta.it"),
                from(home, 3, "Luca Bianchi", "luca@ferramenta.it"),
                from(home, 4, "luca bianchi", "luca.bianchi@posta.it"),
                // One word is too common to tell people apart.
                from(home, 5, "Luca", "luca@other.example"),
            ])
            .unwrap();
        let found = store.sender_addresses("LUCA@ferramenta.it").unwrap();
        assert_eq!(
            found,
            [
                SenderAddress {
                    email: "luca@ferramenta.it".into(),
                    account: work,
                    emails: 3,
                    verified: false,
                },
                SenderAddress {
                    email: "luca.bianchi@posta.it".into(),
                    account: home,
                    emails: 1,
                    verified: false,
                },
            ]
        );
    }

    #[test]
    fn closers_only_close() {
        assert!(closer("Thanks!"));
        assert!(closer("Ok, great 👍"));
        assert!(closer(
            "Grazie mille! Il giorno lun 2 ott, Luca ha scritto: ecco"
        ));
        assert!(!closer("Thanks, can you also send the invoice?"));
        assert!(!closer(""));
    }

    #[test]
    fn senders_moved_often_suggest_a_rule() {
        use crate::rules::{self, Action, Field, Op, Rule};
        let store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        let day = 86_400;
        let now = 100 * day;
        let rail = [(
            "Info@Ferrovia.example".to_string(),
            "Ferrovia Rapida".to_string(),
        )];
        let luca = [("luca@studio.it".to_string(), "Luca".to_string())];
        // Four moves are not enough; old ones don't count.
        store.log_moves(a, &rail, "Travel", now - 40 * day).unwrap();
        for i in 0..4 {
            store.log_moves(a, &rail, "Travel", now - i * day).unwrap();
            store.log_moves(a, &luca, "Clients", now - i * day).unwrap();
        }
        assert_eq!(rules::suggestion(&store, now).unwrap(), None);
        store.log_moves(a, &rail, "Travel", now).unwrap();
        let s = rules::suggestion(&store, now).unwrap().unwrap();
        assert_eq!(
            (
                s.sender.as_str(),
                s.name.as_str(),
                s.target.as_str(),
                s.moves
            ),
            ("info@ferrovia.example", "Ferrovia Rapida", "Travel", 5)
        );

        // Not now, and the next one shows.
        store.log_moves(a, &luca, "Clients", now).unwrap();
        rules::dismiss_suggestion(&store, &s).unwrap();
        let next = rules::suggestion(&store, now).unwrap().unwrap();
        assert_eq!(next.sender, "luca@studio.it");

        // A rule on the sender covers it.
        store
            .save_rule(&Rule {
                id: 0,
                account: None,
                field: Field::Sender,
                op: Op::Contains,
                value: "@studio.it".into(),
                action: Action::MoveTo("Clients".into()),
                enabled: true,
                last_run: None,
                matched: 0,
            })
            .unwrap();
        assert_eq!(rules::suggestion(&store, now).unwrap(), None);

        // Moves older than 60 days are let go.
        store.log_moves(a, &[], "Travel", now + 61 * day).unwrap();
        assert!(store.frequent_moves(0, 1).unwrap().is_empty());
    }

    #[test]
    fn a_message_knows_its_shared_folder() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        store
            .upsert_messages(&[
                MessageSummary {
                    mailbox: "Sent".into(),
                    ..msg(a, 1, 100, true)
                },
                MessageSummary {
                    mailbox: "Clients".into(),
                    ..msg(a, 2, 100, true)
                },
            ])
            .unwrap();
        assert_eq!(store.folder_of(a, "Sent", 1).unwrap(), Some(Folder::Sent));
        assert_eq!(store.folder_of(a, "Clients", 2).unwrap(), None);
        assert_eq!(store.folder_of(a, "Sent", 9).unwrap(), None);
    }

    #[test]
    fn aliases_and_what_sent_mail_suggests() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let sent = |uid, from: &str| MessageSummary {
            mailbox: "Sent".into(),
            from_email: from.into(),
            ..msg(a, uid, 100, true)
        };
        store
            .upsert_messages(&[
                sent(1, "Matteo@studio.it"),
                sent(2, "info@studio.it"),
                sent(3, "fatture@studio.it"),
                sent(4, "Fatture@studio.it"),
            ])
            .unwrap();
        assert_eq!(
            store.alias_suggestions(a).unwrap(),
            ["fatture@studio.it", "info@studio.it"]
        );
        store.add_alias(a, " Fatture@studio.it").unwrap();
        store.add_alias(a, "matteo@studio.it").unwrap();
        assert_eq!(store.aliases(a).unwrap(), ["fatture@studio.it"]);
        assert_eq!(store.alias_suggestions(a).unwrap(), ["info@studio.it"]);
        assert_eq!(
            store.own_addresses(a).unwrap(),
            ["matteo@studio.it", "fatture@studio.it"]
        );

        let g = store
            .save_address_group(&AddressGroup {
                name: "Work".into(),
                color: "#2F8F83".into(),
                separate_inbox: true,
                notify: true,
                addresses: vec![
                    GroupAddress {
                        account: a,
                        email: "matteo@studio.it".into(),
                    },
                    GroupAddress {
                        account: a,
                        email: "fatture@studio.it".into(),
                    },
                ],
                ..Default::default()
            })
            .unwrap();
        store.remove_alias(a, "fatture@studio.it").unwrap();
        assert!(store.aliases(a).unwrap().is_empty());
        assert_eq!(store.address_groups().unwrap()[0].addresses.len(), 1);
        assert_eq!(store.group_of("MATTEO@studio.it").unwrap(), Some(g));
    }

    #[test]
    fn an_address_is_in_one_group_at_most() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        let b = store
            .add_account(&imap_account("Lumen", "matteo@lumen.design", "#C2417A"))
            .unwrap();
        let addr = |account, e: &str| GroupAddress {
            account,
            email: e.into(),
        };
        let work = AddressGroup {
            name: "Work".into(),
            color: "#2F8F83".into(),
            send_from: "matteo@lumen.design".into(),
            addresses: vec![addr(a, "matteo@studio.it"), addr(b, "matteo@lumen.design")],
            ..Default::default()
        };
        let w = store.save_address_group(&work).unwrap();
        let p = store
            .save_address_group(&AddressGroup {
                name: "Projects".into(),
                color: "#C2417A".into(),
                addresses: vec![addr(b, "matteo@lumen.design")],
                ..Default::default()
            })
            .unwrap();
        let groups = store.address_groups().unwrap();
        assert_eq!(groups.iter().map(|g| g.id).collect::<Vec<_>>(), [w, p]);
        assert_eq!(groups[0].addresses, [addr(a, "matteo@studio.it")]);
        assert_eq!(groups[0].send_from, "matteo@lumen.design");
        assert_eq!(groups[0].sender().unwrap().email, "matteo@studio.it");
        store
            .save_address_group(&AddressGroup {
                id: w,
                name: "Studio".into(),
                ..work.clone()
            })
            .unwrap();
        let groups = store.address_groups().unwrap();
        assert_eq!(groups[0].name, "Studio");
        assert!(groups[1].addresses.is_empty());
        store.delete_address_group(w).unwrap();
        assert_eq!(store.address_groups().unwrap().len(), 1);
        assert_eq!(store.group_of("matteo@studio.it").unwrap(), None);
    }

    #[test]
    fn recipients_are_suggested_as_they_are_typed() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.add_alias(a, "fatture@studio.it").unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let from = |uid, at, name: &str, email: &str| {
            let mut m = msg(a, uid, at, true);
            m.from_name = name.into();
            m.from_email = email.into();
            m
        };
        let sent = |uid, at, recipients: &str| {
            let mut m = msg(a, uid, at, true);
            m.mailbox = "Sent".into();
            m.from_email = "matteo@studio.it".into();
            m.reply.recipients = recipients.into();
            m
        };
        store
            .upsert_messages(&[
                from(1, 100, "Giulia Romano", "giulia@example.org"),
                from(2, 500, "Gianni Neri", "gianni@example.org"),
                from(3, 110, "Giorgio Bassi", "g.bassi@example.org"),
                from(4, 120, "Notifiche", "noreply@example.org"),
                from(5, 130, "Fatture", "fatture@studio.it"),
                sent(6, 200, "g.bassi@example.org gino@example.net"),
                sent(
                    7,
                    300,
                    "giulia@example.org fatture@studio.it noreply@x.example",
                ),
            ])
            .unwrap();
        let found = |typed| -> Vec<(String, bool)> {
            store
                .suggest_recipients(typed, 6)
                .unwrap()
                .into_iter()
                .map(|p| (p.email, p.written_to))
                .collect()
        };
        let e = |s: &str, w| (s.to_owned(), w);
        // Written to first, the newest first; then who wrote. Machines and
        // own addresses never.
        assert_eq!(
            found("Gi"),
            [
                e("giulia@example.org", true),
                e("g.bassi@example.org", true),
                e("gino@example.net", true),
                e("gianni@example.org", false),
            ]
        );
        // Any word of the name.
        assert_eq!(found("rom"), [e("giulia@example.org", true)]);
        assert_eq!(found("bassi"), [e("g.bassi@example.org", true)]);
        assert!(found("no").is_empty());
        assert!(found("fat").is_empty());
        assert!(found(" ").is_empty());
        assert_eq!(
            store.suggest_recipients("giu", 6).unwrap()[0].name,
            "Giulia Romano"
        );
    }

    #[test]
    fn a_group_lists_the_mail_written_to_its_addresses() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        let b = store
            .add_account(&imap_account("Home", "teo@posta.it", "#E0782F"))
            .unwrap();
        store.add_alias(a, "fatture@studio.it").unwrap();
        store.add_alias(a, "info@studio.it").unwrap();
        let to = |account, uid, recipients: &str| {
            let mut m = msg(account, uid, 100 + uid as i64, false);
            m.reply.recipients = recipients.into();
            m
        };
        store
            .upsert_messages(&[
                to(a, 1, "matteo@studio.it"),
                to(a, 2, "fatture@studio.it luca@studio.it"),
                to(a, 3, "info@studio.it"),
                to(a, 4, ""),
                to(b, 5, "teo@posta.it"),
            ])
            .unwrap();
        let addr = |account, e: &str| GroupAddress {
            account,
            email: e.into(),
        };
        let g = store
            .save_address_group(&AddressGroup {
                name: "Work".into(),
                color: "#2F8F83".into(),
                addresses: vec![addr(a, "Matteo@studio.it"), addr(a, "fatture@studio.it")],
                notify: true,
                ..Default::default()
            })
            .unwrap();
        let uids = |within: Within| {
            let mut v: Vec<u32> = store
                .conversations_page(Folder::Inbox, within, Section::All, 0, 10)
                .unwrap()
                .into_iter()
                .map(|c| c.latest.uid)
                .collect();
            v.sort();
            v
        };
        // The account's own address has what went to none of its aliases.
        assert_eq!(uids(Within::Group(g)), [1, 2, 4]);
        assert_eq!(
            uids(Within::Address {
                group: g,
                email: "fatture@studio.it".into()
            }),
            [2]
        );
        assert_eq!(
            uids(Within::Address {
                group: g,
                email: "matteo@studio.it".into()
            }),
            [1, 4]
        );
        assert_eq!(
            uids(Within::Address {
                group: g,
                email: "o'brien@studio.it".into()
            }),
            Vec::<u32>::new()
        );
        assert_eq!(
            store
                .unread_count(Folder::Inbox, Within::Group(g), Section::All)
                .unwrap(),
            3
        );
        assert_eq!(
            store
                .conversation_count(Folder::Inbox, Within::Group(g), Section::All)
                .unwrap(),
            3
        );
        // Search narrows to the group the same way.
        let found = |q: &str| {
            let mut v: Vec<u32> = store
                .search(&Query::parse(q), 10)
                .unwrap()
                .hits
                .into_iter()
                .map(|h| h.message.uid)
                .collect();
            v.sort();
            v
        };
        assert_eq!(found(&format!("group:{g}")), [1, 2, 4]);
        assert_eq!(
            store.indexed(&Query::parse(&format!("group:{g}"))).unwrap(),
            3
        );

        // A group with notices off keeps its mail quiet.
        assert!(store.notifies(a, "fatture@studio.it").unwrap());
        let mut work = store.address_groups().unwrap().remove(0);
        work.notify = false;
        store.save_address_group(&work).unwrap();
        assert!(!store.notifies(a, "fatture@studio.it").unwrap());
        assert!(!store.notifies(a, "").unwrap());
        assert!(store.notifies(a, "info@studio.it").unwrap());
        assert!(store.notifies(b, "teo@posta.it").unwrap());
    }

    #[test]
    fn the_space_tables_go_from_one_store_to_another() {
        let mut mac = Store::open_in_memory().unwrap();
        let w = mac
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        mac.add_alias(w, "fatture@studio.it").unwrap();
        mac.set_setting("notify.mode", "all").unwrap();
        mac.set_setting("hint.swipe_played", "1").unwrap();
        mac.save_address_group(&AddressGroup {
            name: "Work".into(),
            color: "#2F8F83".into(),
            notify: true,
            addresses: vec![GroupAddress {
                account: w,
                email: "fatture@studio.it".into(),
            }],
            ..Default::default()
        })
        .unwrap();
        let tables = mac.space_tables().unwrap();
        let json = serde_json::to_string(&tables).unwrap();
        assert!(!json.contains("swipe_played"));

        // The phone already has another account, so ids differ.
        let mut phone = Store::open_in_memory().unwrap();
        let p = phone
            .add_account(&imap_account("Home", "teo@posta.it", "#E0782F"))
            .unwrap();
        let ids = phone
            .take_space_tables(&serde_json::from_str(&json).unwrap())
            .unwrap();
        let here = ids["matteo@studio.it"];
        assert_ne!(here, w);
        assert_eq!(phone.accounts().unwrap().len(), 2);
        assert_eq!(phone.account(p).unwrap().unwrap().email, "teo@posta.it");
        assert_eq!(phone.aliases(here).unwrap(), ["fatture@studio.it"]);
        let groups = phone.address_groups().unwrap();
        assert_eq!(groups[0].addresses[0].account, here);
        assert_eq!(
            phone.setting("notify.mode").unwrap().as_deref(),
            Some("all")
        );
        // Taken in twice, nothing doubles.
        phone
            .take_space_tables(&serde_json::from_str(&json).unwrap())
            .unwrap();
        assert_eq!(phone.accounts().unwrap().len(), 2);
        assert_eq!(phone.address_groups().unwrap().len(), 1);
        // The phone's own account isn't in the Mac's space.
        let tables = serde_json::from_str(&json).unwrap();
        assert_eq!(phone.accounts_not_in(&tables).unwrap(), [p]);
    }

    #[test]
    fn recipients_are_kept_and_read_again() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        let mut m = msg(a, 1, 100, false);
        m.reply.recipients = "fatture@studio.it".into();
        store.upsert_messages(&[m, msg(a, 2, 200, false)]).unwrap();
        assert_eq!(
            store.recipients(a, "INBOX", 1).unwrap(),
            "fatture@studio.it"
        );
        assert_eq!(store.recipients(a, "INBOX", 2).unwrap(), "");
        store
            .set_recipients(a, "INBOX", &[(2, "info@studio.it".into())])
            .unwrap();
        assert_eq!(store.recipients(a, "INBOX", 2).unwrap(), "info@studio.it");
        assert_eq!(store.recipients(a, "INBOX", 9).unwrap(), "");
    }

    #[test]
    fn jmap_ids_get_numbers_that_are_never_reused() {
        let mut store = Store::open_in_memory().unwrap();
        let account = store
            .add_account(&imap_account("Work", "a@example.com", "#3451D1"))
            .unwrap();
        let ids = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(
            store
                .add_jmap_ids(account, "INBOX", &ids(&["Ma", "Mb"]))
                .unwrap(),
            [1, 2]
        );
        // Known ids keep their number; new ones carry on.
        assert_eq!(
            store
                .add_jmap_ids(account, "INBOX", &ids(&["Mb", "Mc"]))
                .unwrap(),
            [2, 3]
        );
        assert_eq!(
            store.jmap_id(account, "INBOX", 3).unwrap().as_deref(),
            Some("Mc")
        );
        store.remove_messages(account, "INBOX", &[3]).unwrap();
        assert_eq!(store.jmap_id(account, "INBOX", 3).unwrap(), None);
        assert_eq!(
            store.add_jmap_ids(account, "INBOX", &ids(&["Md"])).unwrap(),
            [4]
        );
        let known = store.jmap_ids(account, "INBOX").unwrap();
        assert_eq!(known.len(), 3);
        assert_eq!(known["Ma"], 1);
        // Other folders count on their own.
        assert_eq!(
            store.add_jmap_ids(account, "Mbx2", &ids(&["Ma"])).unwrap(),
            [1]
        );
    }

    #[test]
    fn keeps_an_away_message_per_account() {
        let store = Store::open_in_memory().unwrap();
        let id = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        assert_eq!(store.away_message(id).unwrap(), None);
        let mut s = crate::away::Stored {
            message: crate::away::AwayMessage {
                on: true,
                start: Some(20_388),
                end: None,
                subject: "Away".into(),
                body: "Back soon".into(),
            },
            zone: 60,
            placed: true,
            device_dates: false,
        };
        store.set_away_message(id, &s).unwrap();
        assert_eq!(store.away_message(id).unwrap(), Some(s.clone()));
        s.message.on = false;
        s.placed = false;
        store.set_away_message(id, &s).unwrap();
        assert_eq!(store.away_messages().unwrap(), [(id, s)]);
        store.remove_account(id).unwrap();
        assert!(store.away_messages().unwrap().is_empty());
    }

    #[test]
    fn vat_migration_rechecks_only_existing_cards_and_is_repeatable() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        let now = 1_792_060_200;
        let mut invoice = msg(a, 1, now, false);
        invoice.subject = "Your invoice".into();
        store
            .upsert_messages(&[invoice, msg(a, 2, now, false)])
            .unwrap();
        store
            .set_body(a, "INBOX", 1, "Invoice total: EUR 12.00")
            .unwrap();
        store.skip_vault(a, "INBOX", &[2]).unwrap();
        assert_eq!(store.vault_cards(None, now - VAULT_SPAN).unwrap().len(), 1);
        for _ in 0..2 {
            store
                .conn
                .execute_batch(
                    MIGRATIONS
                        .iter()
                        .find(|sql| sql.contains("-- Re-read existing Vault cards"))
                        .unwrap(),
                )
                .unwrap();
            let checked: Vec<(u32, bool)> = store
                .conn
                .prepare("SELECT uid, vault_checked FROM message ORDER BY uid")
                .unwrap()
                .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
                .unwrap()
                .map(|r| r.unwrap())
                .collect();
            assert_eq!(checked, [(1, false), (2, true)]);
        }
        // Cached bodies can be read again without fetching any mail.
        assert!(store
            .vault_unchecked(a, "INBOX", now, 100)
            .unwrap()
            .is_empty());
        assert_eq!(store.vault_cards(None, now - VAULT_SPAN).unwrap().len(), 1);
    }

    #[test]
    fn migrations_run_once() {
        let store = Store::open_in_memory().unwrap();
        assert_eq!(store.schema_version().unwrap(), MIGRATIONS.len());
    }

    #[test]
    fn file_connections_wait_for_brief_write_contention() {
        let dir = std::env::temp_dir().join(format!("piuma-contention-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("piuma.db");
        let first = Store::open(&path).unwrap();
        let second = Store::open(&path).unwrap();
        let reader = Store::open_reader(&path).unwrap();
        for store in [&first, &second, &reader] {
            let timeout: i64 = store
                .conn
                .pragma_query_value(None, "busy_timeout", |r| r.get(0))
                .unwrap();
            assert_eq!(timeout, 2000);
        }
        first.conn.execute_batch("BEGIN IMMEDIATE").unwrap();
        let (started, waiting) = std::sync::mpsc::channel();
        let writer = std::thread::spawn(move || {
            started.send(()).unwrap();
            second.add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
        });
        waiting.recv().unwrap();
        std::thread::sleep(std::time::Duration::from_millis(100));
        first.conn.execute_batch("COMMIT").unwrap();
        writer.join().unwrap().unwrap();
        assert_eq!(reader.accounts().unwrap().len(), 1);
        drop((first, reader));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn migrations_are_idempotent_on_reopen() {
        let dir = std::env::temp_dir().join(format!("piuma-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("piuma.db");
        {
            let store = Store::open(&path).unwrap();
            store
                .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
                .unwrap();
        }
        let store = Store::open(&path).unwrap();
        assert_eq!(store.accounts().unwrap().len(), 1);
        // Windows won't remove a database that is still open.
        drop(store);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn the_reader_reads_while_a_write_is_open() {
        let dir = std::env::temp_dir().join(format!("piuma-reader-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("piuma.db");
        let mut store = Store::open(&path).unwrap();
        store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        let reader = Store::open_reader(&path).unwrap();
        // A sync's batch in the middle of being written.
        let tx = store.conn.transaction().unwrap();
        tx.execute("DELETE FROM account", []).unwrap();
        let start = std::time::Instant::now();
        assert_eq!(reader.accounts().unwrap().len(), 1);
        assert!(start.elapsed() < std::time::Duration::from_millis(500));
        tx.commit().unwrap();
        assert!(reader.accounts().unwrap().is_empty());
        // It can't write.
        assert!(reader
            .add_account(&imap_account("Home", "b@example.org", "#2F8F83"))
            .is_err());
        drop((reader, store));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn accounts_round_trip() {
        let store = Store::open_in_memory().unwrap();
        let a = imap_account("Work", "a@example.org", "#2F8F83");
        let id = store.add_account(&a).unwrap();
        let jmap = Account {
            id: AccountId(0),
            name: "Fastmail".into(),
            email: "b@example.org".into(),
            sender_name: String::new(),
            color: "#8B5CD6".into(),
            kind: AccountKind::Jmap {
                session_url: "https://api.example.org/jmap/session".into(),
                username: String::new(),
            },
        };
        store.add_account(&jmap).unwrap();

        let all = store.accounts().unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(all[0], Account { id, ..a });
        assert_eq!(all[1].kind, jmap.kind);
    }

    #[test]
    fn unified_inbox_merges_accounts_newest_first_and_pages() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let b = store
            .add_account(&imap_account("Work", "b@example.org", "#2F8F83"))
            .unwrap();
        store
            .upsert_messages(&[
                msg(a, 1, 100, true),
                msg(b, 1, 300, false),
                msg(a, 2, 200, false),
            ])
            .unwrap();

        let page1 = store.unified(Folder::Inbox, None, 2).unwrap();
        assert_eq!(
            page1.iter().map(|m| m.received_at).collect::<Vec<_>>(),
            [300, 200]
        );
        let page2 = store.unified(Folder::Inbox, Some(200), 2).unwrap();
        assert_eq!(
            page2.iter().map(|m| m.received_at).collect::<Vec<_>>(),
            [100]
        );
        assert_eq!(
            store
                .unread_count(Folder::Inbox, None, Section::All)
                .unwrap(),
            2
        );
    }

    #[test]
    fn upsert_updates_and_flags_change() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        store.upsert_messages(&[msg(a, 7, 100, false)]).unwrap();
        let mut changed = msg(a, 7, 100, false);
        changed.subject = "New subject".into();
        store.upsert_messages(&[changed]).unwrap();
        assert_eq!(store.unified(Folder::Inbox, None, 10).unwrap().len(), 1);

        let read = Flags {
            seen: true,
            flagged: true,
            answered: false,
        };
        assert!(store.set_flags(a, "INBOX", 7, read).unwrap());
        let m = store.message(a, "INBOX", 7).unwrap().unwrap();
        assert_eq!(m.subject, "New subject");
        assert_eq!(m.flags, read);
        assert!(!store.set_flags(a, "INBOX", 99, read).unwrap());
    }

    #[test]
    fn pages_by_position_and_tracks_folder_state() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let msgs: Vec<_> = (1..=10).map(|u| msg(a, u, u as i64 * 10, false)).collect();
        store.upsert_messages(&msgs).unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 10);
        let page = store.unified_page(Folder::Inbox, 8, 5).unwrap();
        assert_eq!(page.iter().map(|m| m.uid).collect::<Vec<_>>(), [2, 1]);

        assert_eq!(store.mailbox_state(a, "INBOX").unwrap(), None);
        let state = MailboxState {
            uid_validity: 7,
            highest_modseq: Some(42),
        };
        store.set_mailbox_state(a, "INBOX", state).unwrap();
        assert_eq!(store.mailbox_state(a, "INBOX").unwrap(), Some(state));

        store.set_body(a, "INBOX", 3, "Hello").unwrap();
        store.remove_messages(a, "INBOX", &[3, 4]).unwrap();
        let mut uids = store.uids(a, "INBOX").unwrap();
        uids.sort();
        assert_eq!(uids, [1, 2, 5, 6, 7, 8, 9, 10]);
        assert_eq!(store.body(a, "INBOX", 3).unwrap(), None);

        let seen = Flags {
            seen: true,
            ..Flags::default()
        };
        let n = store
            .update_flags(a, "INBOX", &[(1, seen), (2, Flags::default()), (99, seen)])
            .unwrap();
        assert_eq!(n, 1);
        store.clear_mailbox(a, "INBOX").unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 0);
    }

    #[test]
    fn hidden_messages_leave_every_list_until_shown() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let mut m = msg(a, 1, 100, false);
        m.reply = ReplyInfo {
            message_id: "<1@x>".into(),
            references: "<0@x>".into(),
            reply_to: "list@example.org".into(),
            recipients: String::new(),
        };
        store
            .upsert_messages(&[m.clone(), msg(a, 2, 200, true)])
            .unwrap();
        assert_eq!(store.message(a, "INBOX", 1).unwrap(), Some(m.clone()));

        store.set_hidden(a, "INBOX", 1, true).unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 1);
        assert_eq!(
            store
                .unread_count(Folder::Inbox, None, Section::All)
                .unwrap(),
            0
        );
        assert_eq!(store.count_between(Folder::Inbox, 0, 1000).unwrap(), 1);
        assert_eq!(store.unified_page(Folder::Inbox, 0, 10).unwrap().len(), 1);
        // A sync that sees the message again does not bring it back.
        store.upsert_messages(&[m]).unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 1);

        store.unhide_all().unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 2);
    }

    #[test]
    fn sender_stats_count_what_came_and_was_opened() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let letter = |uid, at, seen| MessageSummary {
            from_email: "News@Lume.example".into(),
            list: ListInfo {
                newsletter: true,
                ..ListInfo::default()
            },
            ..msg(a, uid, at, seen)
        };
        store
            .upsert_messages(&[
                letter(1, 100, true),
                letter(2, 200, false),
                letter(3, 10, true),
            ])
            .unwrap();
        assert_eq!(
            store.sender_stats("news@lume.example", 50).unwrap(),
            (2, 1, true)
        );
        assert_eq!(store.sender_stats("x@y.z", 0).unwrap(), (0, 0, false));
    }

    #[test]
    fn pec_receipts_leave_the_inbox_for_the_vault() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("PEC", "matteo@pec.it", "#E0782F"))
            .unwrap();
        let receipt = |uid, at, kind, to: &str| MessageSummary {
            from_email: "posta-certificata@pec.aruba.it".into(),
            subject: "CONSEGNA: Lease renewal".into(),
            list: ListInfo {
                receipt: Some(pec::Receipt {
                    kind,
                    refers: "<lease@pec.it>".into(),
                    recipients: vec![to.into()],
                    reason: String::new(),
                }),
                ..ListInfo::default()
            },
            ..msg(a, uid, at, true)
        };
        store
            .upsert_messages(&[
                msg(a, 1, 100, false),
                receipt(2, 200, pec::Kind::Accepted, "x@pec.it"),
                receipt(3, 210, pec::Kind::Delivered, "x@pec.it"),
            ])
            .unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 1);
        let sent = store.pec_sent(None).unwrap();
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0].subject, "Lease renewal");
        assert_eq!(sent[0].stage, pec::Stage::Delivered);
        assert_eq!(sent[0].proofs, [("INBOX".to_owned(), 3)]);
        // A receipt deleted on the server goes from the card too.
        store.remove_messages(a, "INBOX", &[3]).unwrap();
        assert_eq!(
            store.pec_sent(Some(a)).unwrap()[0].stage,
            pec::Stage::Accepted
        );
    }

    #[test]
    fn newsletters_have_their_own_list() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let letter = |uid, at, seen| MessageSummary {
            from_email: "Issue@Forma.example".into(),
            list: ListInfo {
                newsletter: true,
                unsubscribe: "https://forma.example/u".into(),
                one_click: true,
                bulk: false,
                receipt: None,
            },
            ..msg(a, uid, at, seen)
        };
        let mut archived = letter(9, 50, true);
        archived.mailbox = "Archive".into();
        store
            .upsert_messages(&[
                msg(a, 1, 100, false),
                letter(2, 200, false),
                letter(3, 10, true),
                archived,
            ])
            .unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 1);
        assert_eq!(store.count(Folder::Newsletters).unwrap(), 2);
        assert_eq!(
            store
                .unread_count(Folder::Newsletters, None, Section::All)
                .unwrap(),
            1
        );
        assert_eq!(
            store.list_info(a, "INBOX", 2).unwrap().unsubscribe,
            "https://forma.example/u"
        );
        // The reading time comes with the body.
        assert_eq!(store.newsletters_page(None, 0, 10).unwrap()[0].1, 0);
        store.set_body(a, "INBOX", 2, &"word ".repeat(500)).unwrap();
        let page = store.newsletters_page(Some(a), 0, 10).unwrap();
        assert_eq!(
            page.iter()
                .map(|(m, min)| (m.uid, *min))
                .collect::<Vec<_>>(),
            [(2, 3), (3, 0)]
        );
        assert_eq!(
            store.newsletters_without_body(a, 10).unwrap(),
            [("INBOX".into(), 3)]
        );
        // Newsletters aren't Inbox mail to fetch ahead.
        assert!(store
            .inbox_without_body(a, "INBOX", 10)
            .unwrap()
            .iter()
            .all(|u| *u != 3));

        // Read ones older than the cut leave for Archive, once.
        assert_eq!(store.queue_newsletter_archive(a, 100, true).unwrap(), 1);
        assert_eq!(store.queue_newsletter_archive(a, 100, true).unwrap(), 0);
        assert_eq!(store.count(Folder::Newsletters).unwrap(), 1);
        assert_eq!(store.pending_changes(a).unwrap()[0].uid, 3);

        // A sender moved to the inbox stays there, whatever comes next.
        store
            .set_sender_zone("issue@forma.example", Folder::Inbox)
            .unwrap();
        assert_eq!(store.count(Folder::Newsletters).unwrap(), 0);
        store.upsert_messages(&[letter(4, 300, false)]).unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 3);
        // And one moved the other way follows.
        store
            .set_sender_zone("julia@example.org", Folder::Newsletters)
            .unwrap();
        assert_eq!(store.count(Folder::Newsletters).unwrap(), 1);

        // Unopened ones leave by their own cut.
        assert_eq!(store.queue_newsletter_archive(a, 50, false).unwrap(), 0);
        assert_eq!(store.queue_newsletter_archive(a, 150, false).unwrap(), 1);
        assert_eq!(store.count(Folder::Newsletters).unwrap(), 0);
    }

    #[test]
    fn a_failed_charge_is_settled_by_a_later_receipt() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let now = 1_792_060_200;
        let mail = |uid, at, subject: &str| MessageSummary {
            from_name: "Acme".into(),
            subject: subject.into(),
            reply: ReplyInfo {
                message_id: format!("<{uid}@acme.example>"),
                ..ReplyInfo::default()
            },
            ..msg(a, uid, at, false)
        };
        store
            .upsert_messages(&[
                mail(
                    1,
                    now - 3000,
                    "There was a problem with your recent payment for Acme",
                ),
                mail(2, now - 2000, "Your payment failed"),
            ])
            .unwrap();
        for uid in [1, 2] {
            store
                .set_body(
                    a,
                    "INBOX",
                    uid,
                    "Your recent Acme payment has failed. Update your card.",
                )
                .unwrap();
        }
        store.vault_unchecked(a, "INBOX", now, 100).unwrap();
        let cards = store.vault_cards(None, 0).unwrap();
        assert_eq!(cards.len(), 1);
        assert_eq!((cards[0].0.uid, cards[0].2.status.as_str()), (2, "failed"));
        assert!(!cards[0].2.paid);

        store
            .upsert_messages(&[mail(3, now - 1000, "Your Acme receipt")])
            .unwrap();
        store
            .set_body(a, "INBOX", 3, "Thank you for your payment.\nTotal: €9.99")
            .unwrap();
        store.vault_unchecked(a, "INBOX", now, 100).unwrap();
        let cards = store.vault_cards(None, 0).unwrap();
        assert_eq!(cards.len(), 2);
        assert!(cards.iter().all(|(_, _, c)| c.paid));
    }

    #[test]
    fn features_turned_off_stop_and_pick_up_again() {
        use crate::features::{NEWSLETTERS, VAULT};
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let now = 1_792_060_200;
        let letter = MessageSummary {
            from_email: "issue@forma.example".into(),
            list: ListInfo {
                newsletter: true,
                unsubscribe: "https://forma.example/u".into(),
                one_click: true,
                bulk: false,
                receipt: None,
            },
            ..msg(a, 2, now - 200, false)
        };
        let lunch = MessageSummary {
            subject: "Lunch on Friday?".into(),
            reply: ReplyInfo {
                message_id: "<1@club.example>".into(),
                ..ReplyInfo::default()
            },
            ..msg(a, 1, now - 100, false)
        };

        // Newsletters off: they stay in the inbox, new ones too.
        store.set_feature(NEWSLETTERS, false).unwrap();
        store.upsert_messages(&[letter]).unwrap();
        assert_eq!(store.count(Folder::Newsletters).unwrap(), 0);
        assert_eq!(store.count(Folder::Inbox).unwrap(), 1);
        assert!(store.newsletters_without_body(a, 10).unwrap().is_empty());
        // On again: back to their own list, unsubscribe kept.
        store.set_feature(NEWSLETTERS, true).unwrap();
        assert_eq!(store.count(Folder::Newsletters).unwrap(), 1);
        assert_eq!(store.count(Folder::Inbox).unwrap(), 0);
        assert_eq!(
            store.list_info(a, "INBOX", 2).unwrap().unsubscribe,
            "https://forma.example/u"
        );
        // A sender moved to the inbox stays there.
        store
            .set_sender_zone("issue@forma.example", Folder::Inbox)
            .unwrap();
        store.set_feature(NEWSLETTERS, false).unwrap();
        store.set_feature(NEWSLETTERS, true).unwrap();
        assert_eq!(store.count(Folder::Newsletters).unwrap(), 0);

        // Vault off: no card is read, and none is shown.
        store.set_feature(VAULT, false).unwrap();
        store.upsert_messages(&[lunch]).unwrap();
        store
            .set_body(a, "INBOX", 1, "See you at the club.")
            .unwrap();
        store.pin_to_vault(a, "INBOX", 1, now).unwrap();
        assert!(store
            .vault_unchecked(a, "INBOX", now, 100)
            .unwrap()
            .is_empty());
        assert!(store.vault_cards(None, 0).unwrap().is_empty());
        // On again: the mail already here makes its card.
        store.set_feature(VAULT, true).unwrap();
        store.vault_unchecked(a, "INBOX", now, 100).unwrap();
        assert_eq!(store.vault_cards(None, 0).unwrap().len(), 1);
        // Off hides the cards made, and keeps them.
        store.set_feature(VAULT, false).unwrap();
        assert!(store.vault_cards(None, 0).unwrap().is_empty());
        store.set_feature(VAULT, true).unwrap();
        assert_eq!(store.vault_cards(None, 0).unwrap().len(), 1);
    }

    #[test]
    fn a_parcel_keeps_its_order_total_and_first_day() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let now = 1_792_060_200;
        let mail = |uid, at, subject: &str| MessageSummary {
            from_name: "Montagna Shop".into(),
            subject: subject.into(),
            reply: ReplyInfo {
                message_id: format!("<{uid}@shop.example>"),
                ..ReplyInfo::default()
            },
            ..msg(a, uid, at, false)
        };
        store
            .upsert_messages(&[
                mail(1, now - 3 * 86_400, "Your order has shipped"),
                mail(2, now - 1000, "Your order was delivered"),
            ])
            .unwrap();
        let tracking = "Tracking number: 1Z999AA10123456784";
        store
            .set_body(
                a,
                "INBOX",
                1,
                &format!("{tracking}\nOrder total: €124.78\nFree returns for 100 days."),
            )
            .unwrap();
        store
            .set_body(
                a,
                "INBOX",
                2,
                &format!("Your parcel has been delivered.\n{tracking}"),
            )
            .unwrap();
        store.vault_unchecked(a, "INBOX", now, 100).unwrap();
        let cards = store.vault_cards(None, 0).unwrap();
        assert_eq!(cards.len(), 1);
        let card = &cards[0].2;
        assert_eq!(card.stage, crate::vault::Stage::Delivered);
        assert_eq!(card.amount, Some(12478));
        assert_eq!(card.return_days, 100);
        assert_eq!(card.first, "2026-10-12");
    }

    #[test]
    fn mail_moved_to_the_vault_keeps_its_card_in_archive() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let now = 1_792_060_200;
        let mail = |mailbox: &str, uid, id: &str| MessageSummary {
            mailbox: mailbox.into(),
            subject: "Lunch on Friday?".into(),
            reply: ReplyInfo {
                message_id: id.into(),
                ..ReplyInfo::default()
            },
            ..msg(a, uid, now - 100, false)
        };
        store
            .upsert_messages(&[mail("INBOX", 1, "<1@club.example>"), mail("INBOX", 2, "")])
            .unwrap();
        store
            .set_body(a, "INBOX", 1, "See you at the club.")
            .unwrap();
        // Nothing in it makes a card, but the rule said Vault.
        assert!(store.vault_cards(None, 0).unwrap().is_empty());
        assert!(store.pin_to_vault(a, "INBOX", 1, now).unwrap());
        // Without a Message-ID it couldn't be followed.
        assert!(!store.pin_to_vault(a, "INBOX", 2, now).unwrap());
        let cards = store.vault_cards(None, 0).unwrap();
        assert_eq!(cards.len(), 1);
        assert_eq!(cards[0].2.kind, crate::vault::Kind::Bill);
        assert!(cards[0].2.paid);
        assert_eq!(cards[0].2.title, "Lunch on Friday?");

        // Archived: the copy there is fetched whole and makes it again.
        store.remove_messages(a, "INBOX", &[1]).unwrap();
        store
            .upsert_messages(&[mail("Archive", 7, "<1@club.example>")])
            .unwrap();
        assert_eq!(store.vault_unchecked(a, "Archive", now, 100).unwrap(), [7]);
        store
            .set_body(a, "Archive", 7, "See you at the club.")
            .unwrap();
        store.vault_unchecked(a, "Archive", now, 100).unwrap();
        let cards = store.vault_cards(None, 0).unwrap();
        assert_eq!(
            cards
                .iter()
                .map(|(m, _, _)| (m.mailbox.as_str(), m.uid))
                .collect::<Vec<_>>(),
            [("Archive", 7)]
        );
    }

    #[test]
    fn the_vault_keeps_one_card_per_parcel_and_bill() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let now = 1_792_060_200;
        let mail = |uid, at, subject: &str| MessageSummary {
            subject: subject.into(),
            reply: ReplyInfo {
                message_id: format!("<{uid}@shop.example>"),
                ..ReplyInfo::default()
            },
            ..msg(a, uid, at, false)
        };
        store
            .upsert_messages(&[
                mail(1, now - 3000, "Your order has shipped"),
                mail(2, now - 2000, "Out for delivery: your order"),
                mail(3, now - 1000, "La tua bolletta di ottobre"),
                mail(4, now - 500, "Lunch on Friday?"),
                mail(5, now - 400, "Your invoice"),
                mail(6, now - VAULT_SPAN - 10, "Your old invoice"),
            ])
            .unwrap();
        // Bodies already here make their card at once; the others are
        // worth fetching, and the rest are passed over.
        store
            .set_body(
                a,
                "INBOX",
                1,
                "Shipped with DHL. Tracking number: JD0146000062",
            )
            .unwrap();
        assert_eq!(
            store.vault_unchecked(a, "INBOX", now, 100).unwrap(),
            [5, 3, 2]
        );
        // Until fetched, they wait.
        assert_eq!(
            store.vault_unchecked(a, "INBOX", now, 100).unwrap(),
            [5, 3, 2]
        );
        store
            .set_body(
                a,
                "INBOX",
                2,
                "Your parcel is out for delivery. Tracking number: JD0146000062",
            )
            .unwrap();
        store
            .set_body(
                a,
                "INBOX",
                3,
                "Totale da pagare: 64,20 €\nScadenza: 30/10/2026",
            )
            .unwrap();
        store.skip_vault(a, "INBOX", &[5]).unwrap();
        assert!(store
            .vault_unchecked(a, "INBOX", now, 100)
            .unwrap()
            .is_empty());

        let cards = store.vault_cards(None, now - VAULT_SPAN).unwrap();
        assert_eq!(
            cards
                .iter()
                .map(|(m, _, c)| (m.uid, c.kind))
                .collect::<Vec<_>>(),
            [
                (3, crate::vault::Kind::Bill),
                (2, crate::vault::Kind::Shipment)
            ]
        );
        assert_eq!(cards[1].2.stage, crate::vault::Stage::Transit);
        assert_eq!(cards[1].1, Some(Folder::Inbox));

        // Paid sticks to the bill, wherever its email goes.
        let key = cards[0].2.key.clone();
        store.set_paid(&key, true, now).unwrap();
        assert!(store.vault_cards(Some(a), 0).unwrap()[0].2.paid);
        store.set_paid(&key, false, now).unwrap();
        assert!(!store.vault_cards(Some(a), 0).unwrap()[0].2.paid);

        // A card made before payments read as paid follows its subject.
        store
            .conn
            .execute(
                "UPDATE message SET subject = '€6.10 payment to Anthropic Ireland' WHERE uid = 3",
                [],
            )
            .unwrap();
        assert!(store.vault_cards(Some(a), 0).unwrap()[0].2.paid);

        // A deleted email takes its card with it.
        store.remove_messages(a, "INBOX", &[3]).unwrap();
        assert_eq!(store.vault_cards(None, 0).unwrap().len(), 1);
        store.remove_messages(a, "INBOX", &[2]).unwrap();
        // The older email about the same parcel is what's left.
        let left = store.vault_cards(None, 0).unwrap();
        assert_eq!(
            (left[0].0.uid, left[0].2.stage),
            (1, crate::vault::Stage::Shipped)
        );
    }

    #[test]
    fn remembers_the_spam_folder_and_queues_spam_moves() {
        use crate::imap::FolderRole;
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        assert_eq!(store.junk_mailbox(a).unwrap(), None);
        store.set_junk_mailbox(a, Some("INBOX.Spam")).unwrap();
        assert_eq!(
            store.junk_mailbox(a).unwrap().as_deref(),
            Some("INBOX.Spam")
        );
        store.set_junk_mailbox(a, None).unwrap();
        assert_eq!(store.junk_mailbox(a).unwrap(), None);

        // Offline, Report spam waits as a spam move, not an archive.
        store.upsert_messages(&[msg(a, 1, 100, false)]).unwrap();
        store
            .queue_change(a, "INBOX", 1, Change::Move(FolderRole::Junk))
            .unwrap();
        let queued = store.pending_changes(a).unwrap();
        assert_eq!(queued.len(), 1);
        assert_eq!(queued[0].change, Change::Move(FolderRole::Junk));
    }

    #[test]
    fn offline_changes_wait_and_are_given_up_after_a_few_tries() {
        use crate::imap::FolderRole;
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        store
            .upsert_messages(&[msg(a, 1, 100, false), msg(a, 2, 200, false)])
            .unwrap();
        store
            .queue_change(a, "INBOX", 1, Change::Seen(true))
            .unwrap();
        store
            .queue_change(a, "INBOX", 1, Change::Seen(false))
            .unwrap();
        store.set_hidden(a, "INBOX", 2, true).unwrap();
        store
            .queue_change(a, "INBOX", 2, Change::Move(FolderRole::Archive))
            .unwrap();
        let changes: Vec<_> = store
            .pending_changes(a)
            .unwrap()
            .into_iter()
            .map(|p| (p.uid, p.change))
            .collect();
        assert_eq!(
            changes,
            [
                (1, Change::Seen(false)),
                (2, Change::Move(FolderRole::Archive))
            ]
        );

        // A move on its way keeps the message hidden after a restart.
        store.unhide_all().unwrap();
        assert_eq!(store.count(Folder::Inbox).unwrap(), 1);

        let move_id = store.pending_changes(a).unwrap()[1].id;
        for _ in 0..MAX_ATTEMPTS {
            store.failed_changes(&[move_id]).unwrap();
        }
        assert_eq!(store.pending_changes(a).unwrap().len(), 1);
        assert_eq!(store.count(Folder::Inbox).unwrap(), 2);

        let seen_id = store.pending_changes(a).unwrap()[0].id;
        store.drop_changes(&[seen_id]).unwrap();
        assert!(store.pending_changes(a).unwrap().is_empty());
    }

    #[test]
    fn a_draft_waits_on_the_device_until_it_goes() {
        let store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        let first = WaitingDraft {
            id: 0,
            account: a,
            raw: b"Subject: Mockups\r\n\r\nWe start".to_vec(),
            message_id: "<d1@example.org>".into(),
            earlier: Some((a, "Drafts".into(), 7)),
            signature: Some("none".into()),
        };
        let id = store.keep_waiting_draft(&first, None, 100).unwrap();
        // Saved again: the same row, still replacing the server's copy.
        let again = WaitingDraft {
            raw: b"Subject: Mockups\r\n\r\nWe start Monday".to_vec(),
            message_id: "<d2@example.org>".into(),
            earlier: None,
            signature: None,
            ..first.clone()
        };
        assert_eq!(store.keep_waiting_draft(&again, Some(id), 200).unwrap(), id);
        let kept = store.waiting_drafts(a).unwrap();
        assert_eq!(kept.len(), 1);
        assert_eq!(kept[0].id, id);
        assert_eq!(kept[0].raw, again.raw);
        assert_eq!(kept[0].message_id, "<d2@example.org>");
        assert_eq!(kept[0].earlier, Some((a, "Drafts".into(), 7)));
        assert_eq!(kept[0].signature, None);
        assert_eq!(store.waiting_draft(id).unwrap(), Some(kept[0].clone()));
        // A row that went meanwhile is kept anew.
        store.drop_waiting_draft(id).unwrap();
        assert_eq!(store.waiting_draft(id).unwrap(), None);
        let new = store.keep_waiting_draft(&again, Some(id), 300).unwrap();
        assert_eq!(store.waiting_drafts(a).unwrap()[0].id, new);
        store.remove_account(a).unwrap();
        assert!(store.waiting_drafts(a).unwrap().is_empty());
    }

    #[test]
    fn outbox_keeps_what_was_written_until_it_goes() {
        use crate::outbox::Outgoing;
        use crate::smtp::{ready, Draft, OutgoingFile};
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        let sig = store
            .save_signature(&Signature {
                account: a,
                label: "Work".into(),
                name: "Matteo".into(),
                ..Default::default()
            })
            .unwrap();
        let draft = Draft {
            from_name: "Matteo".into(),
            from_email: "a@example.org".into(),
            to: vec!["Luca <luca@example.org>".into()],
            bcc: vec!["sara@example.org".into()],
            subject: "Re: Mockup v3".into(),
            body: "Fine on the comments.".into(),
            in_reply_to: Some("<v3@studio.it>".into()),
            references: vec!["<v3@studio.it>".into()],
            files: vec![OutgoingFile {
                name: "notes.txt".into(),
                mime: "text/plain".into(),
                data: b"layout".to_vec(),
            }],
            signature: store.signature(sig).unwrap(),
            ..Draft::default()
        };
        let out = Outgoing {
            account: a,
            ready: ready(&draft).unwrap(),
            draft,
            saved: None,
            send_at: None,
        };
        let first = store.queue_outgoing(&out, 100).unwrap();
        let second = store.queue_outgoing(&out, 200).unwrap();
        assert_eq!(store.outgoing(first).unwrap().as_ref(), Some(&out));
        let waiting = store.outbox(Some(a)).unwrap();
        assert_eq!(
            waiting
                .iter()
                .map(|w| (w.id, w.queued_at))
                .collect::<Vec<_>>(),
            [(first, 100), (second, 200)]
        );
        assert_eq!(waiting[0].subject, "Re: Mockup v3");

        store.refused_outgoing(first, "550 no such user").unwrap();
        assert_eq!(
            store.outbox(None).unwrap()[0].error.as_deref(),
            Some("550 no such user")
        );
        store.drop_outgoing(first).unwrap();
        assert_eq!(store.outgoing(first).unwrap(), None);
        assert_eq!(store.outbox(None).unwrap().len(), 1);

        // Removing the account takes its outbox with it.
        store.remove_account(a).unwrap();
        assert!(store.outbox(None).unwrap().is_empty());
    }

    fn written(
        account: AccountId,
        uid: u32,
        at: i64,
        from: (&str, &str),
        subject: &str,
    ) -> MessageSummary {
        MessageSummary {
            from_name: from.0.into(),
            from_email: from.1.into(),
            subject: subject.into(),
            preview: String::new(),
            ..msg(account, uid, at, uid % 2 == 0)
        }
    }

    fn search_store() -> (Store, AccountId, AccountId) {
        let mut store = Store::open_in_memory().unwrap();
        let p = store
            .add_account(&imap_account("Personal", "p@example.org", "#E0782F"))
            .unwrap();
        let w = store
            .add_account(&imap_account("Work", "w@example.org", "#2F8F83"))
            .unwrap();
        let sara = ("Sara Conti", "sara@tipografialume.it");
        store
            .upsert_messages(&[
                written(w, 1, 100, sara, "Autumn catalog print quote"),
                written(w, 2, 300, sara, "Re: Print quote"),
                written(
                    p,
                    3,
                    200,
                    ("Davide Russo", "davide@officina.it"),
                    "Service quote",
                ),
                written(
                    p,
                    4,
                    400,
                    ("Giulia Romano", "giulia@posta.it"),
                    "Dinner on Friday?",
                ),
                written(w, 5, 500, ("Città Più", "avvisi@citta.it"), "Perché così"),
            ])
            .unwrap();
        store
            .set_body(
                p,
                "INBOX",
                4,
                "I booked Osteria del Ponte, bring the quotes.",
            )
            .unwrap();
        (store, p, w)
    }

    fn subjects(store: &Store, q: &str) -> Vec<String> {
        store
            .search(&Query::parse(q), 10)
            .unwrap()
            .hits
            .into_iter()
            .map(|h| h.message.subject)
            .collect()
    }

    #[test]
    fn labels_are_found_kept_and_sent() {
        let (store, p, w) = search_store();
        let worksite = store.add_label("Worksite", "amber").unwrap();
        assert_eq!(worksite.keyword, "worksite");
        // The same name finds it; a new one takes the next free color.
        assert_eq!(store.add_label("worksite", "teal").unwrap(), worksite);
        let read = store.add_label("To read", "").unwrap();
        assert_eq!(
            (read.color.as_str(), read.keyword.as_str()),
            ("teal", "to_read")
        );
        // Another name with the same keyword gets one of its own.
        assert_eq!(store.add_label("To_read", "").unwrap().keyword, "to_read_2");
        store.update_label(read.id, "Later", "nope").unwrap();
        let later = store.labels().unwrap().remove(1);
        assert_eq!(
            (later.name.as_str(), later.color.as_str()),
            ("Later", "teal")
        );
        assert_eq!(later.keyword, "to_read");

        store
            .label_message(w, "INBOX", 1, &worksite.keyword, true)
            .unwrap();
        store
            .label_message(p, "INBOX", 3, &worksite.keyword, true)
            .unwrap();
        assert_eq!(
            subjects(&store, "label:WORKSITE"),
            ["Service quote", "Autumn catalog print quote"]
        );
        assert_eq!(
            subjects(&store, "label:Worksite quote account:work"),
            ["Autumn catalog print quote"]
        );
        assert!(subjects(&store, "label:\"Later\"").is_empty());
        assert_eq!(store.label_counts().unwrap()[0], (worksite.id, 2));
        let labelled: Vec<String> = store
            .labelled_messages("worksite")
            .unwrap()
            .into_iter()
            .map(|m| m.subject)
            .collect();
        assert_eq!(labelled, ["Service quote", "Autumn catalog print quote"]);
        assert_eq!(
            store.pending_changes(w).unwrap()[0].change,
            Change::Label {
                keyword: "worksite".into(),
                add: true
            }
        );

        // The server hasn't got it yet: what waits wins, other words stay.
        store
            .set_server_labels(
                w,
                "INBOX",
                &[(1, vec!["$Forwarded".into(), "Invoices".into()])],
            )
            .unwrap();
        assert_eq!(
            store.message_labels(w, "INBOX", 1).unwrap(),
            ["invoices", "worksite"]
        );
        let sent: Vec<i64> = store
            .pending_changes(w)
            .unwrap()
            .iter()
            .map(|c| c.id)
            .collect();
        store.drop_changes(&sent).unwrap();
        store.set_server_labels(w, "INBOX", &[(1, vec![])]).unwrap();
        assert!(store.message_labels(w, "INBOX", 1).unwrap().is_empty());

        // A server that keeps no keywords: labels stay here.
        store.set_labels_local(p).unwrap();
        assert!(store.pending_changes(p).unwrap().is_empty());
        store.set_server_labels(p, "INBOX", &[(3, vec![])]).unwrap();
        assert_eq!(store.message_labels(p, "INBOX", 3).unwrap(), ["worksite"]);
        store
            .label_message(p, "INBOX", 4, &worksite.keyword, true)
            .unwrap();
        assert!(store.pending_changes(p).unwrap().is_empty());

        // Deleted: off every message, and the servers are told.
        store
            .label_message(w, "INBOX", 2, &worksite.keyword, true)
            .unwrap();
        store.remove_label(worksite.id).unwrap();
        assert!(subjects(&store, "label:worksite").is_empty());
        assert_eq!(
            store.pending_changes(w).unwrap()[0].change,
            Change::Label {
                keyword: "worksite".into(),
                add: false
            }
        );

        // The list travels in the sync space; which server keeps no
        // keywords doesn't.
        let tables = store.space_tables().unwrap();
        assert_eq!(tables["label"].as_array().unwrap().len(), 2);
        assert!(!tables["setting"]
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["key"].as_str().unwrap().starts_with("labels.local.")));
        let mut other = Store::open_in_memory().unwrap();
        other.add_label("Mine", "coral").unwrap();
        other.take_space_tables(&tables).unwrap();
        let names: Vec<String> = other
            .labels()
            .unwrap()
            .into_iter()
            .map(|l| l.name)
            .collect();
        assert_eq!(names, ["Later", "To_read"]);
    }

    #[test]
    fn search_finds_words_anywhere_newest_first() {
        let (store, _, _) = search_store();
        assert_eq!(
            subjects(&store, "quot"),
            [
                "Dinner on Friday?",
                "Re: Print quote",
                "Service quote",
                "Autumn catalog print quote"
            ]
        );
        assert_eq!(
            subjects(&store, "print QUOTE"),
            ["Re: Print quote", "Autumn catalog print quote"]
        );
        assert_eq!(subjects(&store, "osteria"), ["Dinner on Friday?"]);
        assert_eq!(
            subjects(&store, "tipografialume"),
            ["Re: Print quote", "Autumn catalog print quote"]
        );
        // Accents don't matter, either way.
        assert_eq!(subjects(&store, "perche citta"), ["Perché così"]);
        assert_eq!(subjects(&store, "così"), ["Perché così"]);
        assert!(subjects(&store, "nothing-like-this").is_empty());
        assert!(subjects(&store, "").is_empty());

        let found = store.search(&Query::parse("quote"), 2).unwrap();
        assert_eq!(found.total, 4);
        assert_eq!(found.hits.len(), 2);
        assert_eq!(
            found.hits[0].snippet,
            "I booked Osteria del Ponte, bring the \u{2}quotes\u{3}."
        );
        assert_eq!(found.hits[1].snippet, "");
    }

    #[test]
    fn kinds_of_mail_and_who_writes_most() {
        let (store, p, w) = search_store();
        store
            .set_listed_files(
                w,
                "INBOX",
                &[(
                    2,
                    vec![Attachment {
                        part: 2,
                        name: "quote.pdf".into(),
                        mime: "application/pdf".into(),
                        size: 10,
                        ..Attachment::default()
                    }],
                )],
            )
            .unwrap();
        assert_eq!(subjects(&store, "has:attachment"), ["Re: Print quote"]);
        // The files of what a search finds, and which hits have some.
        let found = store.search(&Query::parse("print"), 10).unwrap();
        assert!(found.hits.iter().any(|h| h.files));
        assert!(found.hits.iter().all(|h| h.files == (h.message.uid == 2)));
        let files = store.search_files(&Query::parse("quote"), 10).unwrap();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].0.subject, "Re: Print quote");
        assert_eq!(files[0].1.name, "quote.pdf");
        assert!(store
            .search_files(&Query::parse("dinner"), 10)
            .unwrap()
            .is_empty());
        assert_eq!(
            subjects(&store, "has:attachment dinner"),
            Vec::<String>::new()
        );
        // avvisi@ (notices) is a machine.
        assert_eq!(
            subjects(&store, "from:people"),
            [
                "Dinner on Friday?",
                "Re: Print quote",
                "Service quote",
                "Autumn catalog print quote"
            ]
        );
        assert!(subjects(&store, "in:vault").is_empty());
        assert!(subjects(&store, "in:newsletter").is_empty());

        let frequent = store.frequent_people(0, 5).unwrap();
        let names: Vec<_> = frequent.iter().map(|(f, _)| f.name.as_str()).collect();
        assert_eq!(names, ["Sara Conti", "Giulia Romano", "Davide Russo"]);
        assert_eq!(frequent[0].1, w);
        assert_eq!(frequent[1].1, p);
        assert!(store.frequent_people(450, 5).unwrap().is_empty());

        // Recent searches: newest first, no repeats, five at most.
        for q in ["quote", "from:sara  invoice", "a", "b", "c", "quote"] {
            store.note_search(q, false).unwrap();
        }
        assert_eq!(
            store.recent_searches().unwrap(),
            ["quote", "c", "b", "a", "from:sara invoice"]
        );
        store.note_search("b", true).unwrap();
        assert_eq!(store.recent_searches().unwrap().len(), 4);
        store.clear_searches().unwrap();
        assert!(store.recent_searches().unwrap().is_empty());
    }

    #[test]
    fn search_operators_narrow() {
        let (mut store, p, _) = search_store();
        assert_eq!(
            subjects(&store, "quote from:sara"),
            ["Re: Print quote", "Autumn catalog print quote"]
        );
        assert_eq!(subjects(&store, "from:davide@officina"), ["Service quote"]);
        assert_eq!(
            subjects(&store, "quote account:personal"),
            ["Dinner on Friday?", "Service quote"]
        );
        assert_eq!(
            subjects(&store, "account:w@example.org quote"),
            ["Re: Print quote", "Autumn catalog print quote"]
        );
        assert_eq!(
            subjects(&store, "is:unread quote"),
            ["Service quote", "Autumn catalog print quote"]
        );
        assert_eq!(
            subjects(&store, "is:unread"),
            ["Perché così", "Service quote", "Autumn catalog print quote"]
        );
        assert_eq!(
            subjects(&store, "quote after:1970-01-01 before:1970-01-02"),
            [
                "Dinner on Friday?",
                "Re: Print quote",
                "Service quote",
                "Autumn catalog print quote"
            ]
        );
        assert!(subjects(&store, "quote after:1970-01-02").is_empty());

        // Hidden while an action can be undone, then back.
        store.set_hidden(p, "INBOX", 3, true).unwrap();
        assert_eq!(subjects(&store, "service"), Vec::<String>::new());
        store.set_hidden(p, "INBOX", 3, false).unwrap();
        // Changes and removals reach the index.
        let mut changed = written(p, 3, 200, ("Davide Russo", "davide@officina.it"), "Tyres");
        changed.preview = "Winter set".into();
        store.upsert_messages(&[changed]).unwrap();
        assert!(subjects(&store, "service").is_empty());
        assert_eq!(subjects(&store, "winter"), ["Tyres"]);
        store.remove_messages(p, "INBOX", &[3]).unwrap();
        assert!(subjects(&store, "tyres").is_empty());
        assert_eq!(store.indexed(&Query::default()).unwrap(), 4);
        assert_eq!(store.indexed(&Query::parse("account:work")).unwrap(), 3);
    }

    #[test]
    fn rules_sort_only_mail_that_arrives_after_the_first_look() {
        use crate::rules::{self, Action, Field, Op};
        let mut store = Store::open_in_memory().unwrap();
        let work = store
            .add_account(&imap_account("Work", "a@example.org", "#3451D1"))
            .unwrap();
        store.upsert_messages(&[msg(work, 1, 100, false)]).unwrap();
        let id = store
            .save_rule(&Rule {
                id: 0,
                account: Some(work),
                field: Field::Sender,
                op: Op::Contains,
                value: " Julia ".into(),
                action: Action::MoveTo("Clients".into()),
                enabled: true,
                last_run: None,
                matched: 0,
            })
            .unwrap();
        assert_eq!(store.rules().unwrap()[0].value, "Julia");
        let store = Mutex::new(store);

        // The first look leaves what is there.
        assert!(rules::apply(&store, work).unwrap().is_empty());
        {
            let mut s = store.lock().unwrap();
            let mut other = msg(work, 3, 300, false);
            other.from_name = "Sara".into();
            other.from_email = "sara@example.org".into();
            s.upsert_messages(&[msg(work, 2, 200, false), other])
                .unwrap();
            // A blocked sender goes to Trash, whatever the rules say.
            s.set_blocked("Sara@example.org", true).unwrap();
        }
        let sorted = rules::apply(&store, work).unwrap();
        assert_eq!(
            sorted,
            HashSet::from([("INBOX".to_string(), 2), ("INBOX".to_string(), 3)])
        );
        let s = store.lock().unwrap();
        let queued = s.pending_changes(work).unwrap();
        assert_eq!(queued.len(), 2);
        let change = |uid| queued.iter().find(|p| p.uid == uid).unwrap().change.clone();
        assert_eq!(change(2), Change::MoveTo("Clients".into()));
        assert_eq!(change(3), Change::Move(crate::imap::FolderRole::Trash));
        assert_eq!(s.received_since(work, "INBOX", 0).unwrap().len(), 1);
        let rule = &s.rules().unwrap()[0];
        assert_eq!((rule.id, rule.matched), (id, 1));
        assert!(rule.last_run.is_some());

        // Turned off, or gone, it sorts nothing.
        s.set_rule_enabled(id, false).unwrap();
        assert!(!s.rules().unwrap()[0].enabled);
        s.delete_rule(id).unwrap();
        assert!(s.rules().unwrap().is_empty());
    }

    #[test]
    fn label_rules_label_and_let_the_next_rule_sort() {
        use crate::rules::{self, Action, Field, Op};
        let mut store = Store::open_in_memory().unwrap();
        let work = store
            .add_account(&imap_account("Work", "a@example.org", "#3451D1"))
            .unwrap();
        store.upsert_messages(&[msg(work, 1, 100, false)]).unwrap();
        let worksite = store.add_label("Worksite", "amber").unwrap();
        let rule = |action| Rule {
            id: 0,
            account: None,
            field: Field::Sender,
            op: Op::Contains,
            value: "julia".into(),
            action,
            enabled: true,
            last_run: None,
            matched: 0,
        };
        store
            .save_rule(&rule(Action::Label(worksite.keyword.clone())))
            .unwrap();
        store
            .save_rule(&rule(Action::MoveTo("Clients".into())))
            .unwrap();
        assert_eq!(
            store.rules().unwrap()[0].action,
            Action::Label("worksite".into())
        );
        // What is already here: the label rule would label it.
        let first = store.rules().unwrap().remove(0);
        assert_eq!(rules::existing(&store, &first, 10).unwrap().len(), 1);
        store
            .label_message(work, "INBOX", 1, "worksite", true)
            .unwrap();
        assert!(rules::existing(&store, &first, 10).unwrap().is_empty());

        let store = Mutex::new(store);
        rules::apply(&store, work).unwrap();
        store
            .lock()
            .unwrap()
            .upsert_messages(&[msg(work, 2, 200, false)])
            .unwrap();
        let sorted = rules::apply(&store, work).unwrap();
        // Moved by the second rule, labelled by the first.
        assert_eq!(sorted, HashSet::from([("INBOX".to_string(), 2)]));
        let s = store.lock().unwrap();
        assert_eq!(s.message_labels(work, "INBOX", 2).unwrap(), ["worksite"]);
        let changes: Vec<Change> = s
            .pending_changes(work)
            .unwrap()
            .into_iter()
            .filter(|p| p.uid == 2)
            .map(|p| p.change)
            .collect();
        assert!(changes.contains(&Change::MoveTo("Clients".into())));
        assert!(changes.contains(&Change::Label {
            keyword: "worksite".into(),
            add: true
        }));
        assert_eq!(s.rules().unwrap()[0].matched, 1);

        // The label gone, its rule goes too.
        s.remove_label(worksite.id).unwrap();
        let left = s.rules().unwrap();
        assert_eq!(left.len(), 1);
        assert_eq!(left[0].action, Action::MoveTo("Clients".into()));
    }

    #[test]
    fn muted_senders_ignore_case() {
        let store = Store::open_in_memory().unwrap();
        assert!(!store.is_muted("luca@studio.it").unwrap());
        store.set_muted("Luca@Studio.it ", true).unwrap();
        assert!(store.is_muted("luca@studio.it").unwrap());
        store.set_muted("luca@studio.it", false).unwrap();
        assert!(!store.is_muted("LUCA@studio.it").unwrap());
        store.set_blocked("Spam@Shop.example ", true).unwrap();
        assert!(store.is_blocked("spam@shop.example").unwrap());
        assert!(!store.is_muted("spam@shop.example").unwrap());
        store.set_blocked("spam@shop.example", false).unwrap();
        assert!(!store.is_blocked("SPAM@shop.example").unwrap());
    }

    #[test]
    fn frequent_contacts_are_the_people_written_to() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let from = |uid, name: &str, email: &str| {
            let mut m = msg(a, uid, 100 + uid as i64, true);
            m.from_name = name.into();
            m.from_email = email.into();
            m
        };
        let mut shop: Vec<_> = (1..=6)
            .map(|uid| from(uid, "WordPress", "blog@blog.example"))
            .collect();
        shop.push(from(7, "Giulia Romano", "giulia@example.org"));
        shop.push(from(8, "Sara Conti", "sara@example.org"));
        shop.push(from(9, "Sara Conti", "sara@example.org"));
        store.upsert_messages(&shop).unwrap();
        // Nothing sent yet: who writes most.
        let names = |store: &Store| -> Vec<String> {
            store
                .frequent_people(0, 5)
                .unwrap()
                .into_iter()
                .map(|(p, _)| p.name)
                .collect()
        };
        assert_eq!(names(&store), ["WordPress", "Sara Conti", "Giulia Romano"]);
        let mut sent = msg(a, 20, 200, true);
        sent.mailbox = "Sent".into();
        sent.from_email = "matteo@studio.it".into();
        sent.reply.recipients = "giulia@example.org".into();
        store.upsert_messages(&[sent]).unwrap();
        // Then only the people written to, most first.
        assert_eq!(names(&store), ["Giulia Romano"]);
    }

    #[test]
    fn search_people_by_name_or_address() {
        let (store, _, _) = search_store();
        let people = store.search_people(&Query::parse("sa"), 5).unwrap();
        assert_eq!(
            people,
            [Person {
                name: "Sara Conti".into(),
                email: "sara@tipografialume.it".into(),
                messages: 2
            }]
        );
        assert_eq!(store.search_people(&Query::parse("quote"), 5).unwrap(), []);
        assert_eq!(
            store.search_people(&Query::parse("from:sara"), 5).unwrap(),
            []
        );
    }

    #[test]
    fn search_index_rebuilds() {
        let (store, _, _) = search_store();
        store.rebuild_search_index().unwrap();
        assert_eq!(subjects(&store, "osteria"), ["Dinner on Friday?"]);
    }

    #[test]
    fn search_of_a_big_inbox_is_fast() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let msgs: Vec<_> = (1..=50_000)
            .map(|u| msg(a, u, (u % 9_000) as i64, false))
            .collect();
        let start = std::time::Instant::now();
        store.upsert_messages(&msgs).unwrap();
        eprintln!("indexed 50,000 in {:?}", start.elapsed());
        let start = std::time::Instant::now();
        let found = store.search(&Query::parse("message 4999"), 50).unwrap();
        assert_eq!(found.total, 11);
        let found = store.search(&Query::parse("updated"), 50).unwrap();
        assert_eq!(found.total, 50_000);
        eprintln!("searched in {:?}", start.elapsed());
    }

    #[test]
    fn deep_pages_of_a_big_inbox_are_fast() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let msgs: Vec<_> = (1..=50_000)
            .map(|u| msg(a, u, (u % 9_000) as i64, false))
            .collect();
        store.upsert_messages(&msgs).unwrap();
        let plan: String = store
            .conn
            .query_row(
                "EXPLAIN QUERY PLAN SELECT uid FROM message WHERE folder = 'inbox' AND hidden = 0
                 ORDER BY received_at DESC, account, uid DESC LIMIT 60 OFFSET 49000",
                [],
                |r| r.get(3),
            )
            .unwrap();
        assert!(plan.contains("message_by_folder"), "{plan}");
        assert!(!plan.contains("TEMP B-TREE"), "{plan}");
        let start = std::time::Instant::now();
        let page = store.unified_page(Folder::Inbox, 49_940, 60).unwrap();
        assert_eq!(page.len(), 60);
        eprintln!("deepest page in {:?}", start.elapsed());
        let start = std::time::Instant::now();
        let page = store
            .conversations_page(Folder::Inbox, None, Section::All, 49_940, 60)
            .unwrap();
        assert_eq!(page.len(), 60);
        eprintln!("deepest conversation page in {:?}", start.elapsed());
    }

    #[test]
    fn folders_with_a_job_are_unified_across_accounts() {
        let mut store = Store::open_in_memory().unwrap();
        let p = store
            .add_account(&imap_account("Personal", "p@example.org", "#E0782F"))
            .unwrap();
        let w = store
            .add_account(&imap_account("Work", "w@example.org", "#2F8F83"))
            .unwrap();
        let in_folder = |a, uid, at, mailbox: &str| MessageSummary {
            mailbox: mailbox.into(),
            ..msg(a, uid, at, true)
        };
        // Cached before the folder's job was known: filed when it is.
        store
            .upsert_messages(&[in_folder(p, 1, 100, "Sent")])
            .unwrap();
        assert_eq!(store.count(Folder::Sent).unwrap(), 0);
        store.set_folder_role(p, Folder::Sent, "Sent").unwrap();
        store
            .set_folder_role(w, Folder::Sent, "Sent Items")
            .unwrap();
        store
            .upsert_messages(&[
                in_folder(w, 1, 300, "Sent Items"),
                in_folder(p, 2, 200, "Sent"),
                msg(p, 1, 400, false),
            ])
            .unwrap();
        let sent: Vec<_> = store
            .unified_page(Folder::Sent, 0, 10)
            .unwrap()
            .into_iter()
            .map(|m| (m.account, m.uid))
            .collect();
        assert_eq!(sent, [(w, 1), (p, 2), (p, 1)]);
        assert_eq!(store.count(Folder::Inbox).unwrap(), 1);
        assert_eq!(
            store.unified_page(Folder::Inbox, 0, 1).unwrap()[0].to,
            "Matteo"
        );
        assert_eq!(
            store.folder_mailbox(w, Folder::Sent).unwrap().as_deref(),
            Some("Sent Items")
        );
        assert_eq!(store.folder_mailbox(w, Folder::Archive).unwrap(), None);
        // The job moves to another folder: the old one leaves the list.
        store.set_folder_role(p, Folder::Sent, "Outbox").unwrap();
        assert_eq!(store.count(Folder::Sent).unwrap(), 1);
    }

    #[test]
    fn an_account_changes_its_name_color_and_servers_but_keeps_its_mail() {
        let store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        let mut account = store.account(a).unwrap().unwrap();
        account.name = "Studio".into();
        account.sender_name = "Matteo Rossi".into();
        account.color = "#8B5CD6".into();
        account.kind = AccountKind::Imap {
            imap: Server {
                host: "mail.studio.it".into(),
                port: 143,
                security: Security::StartTls,
            },
            smtp: Server {
                host: "mail.studio.it".into(),
                port: 465,
                security: Security::Tls,
            },
            username: "matteo".into(),
        };
        store.update_account(&account).unwrap();
        assert_eq!(store.account(a).unwrap().unwrap(), account);
        assert_eq!(store.accounts().unwrap().len(), 1);
    }

    #[test]
    fn templates_keep_and_list_the_last_used_first() {
        let store = Store::open_in_memory().unwrap();
        let t = |name: &str| MessageTemplate {
            name: name.into(),
            body: format!("Text of {name}"),
            ..MessageTemplate::default()
        };
        let invoice = store.save_message_template(&t("Invoice attached")).unwrap();
        let thanks = store.save_message_template(&t("Thanks, received")).unwrap();
        let names = || -> Vec<String> {
            store
                .message_templates()
                .unwrap()
                .into_iter()
                .map(|t| t.name)
                .collect()
        };
        assert_eq!(names(), ["Invoice attached", "Thanks, received"]);
        store.message_template_used(thanks, 10).unwrap();
        assert_eq!(names(), ["Thanks, received", "Invoice attached"]);
        store
            .save_message_template(&MessageTemplate {
                id: invoice,
                subject: "Invoice for October".into(),
                ..t("Invoice attached")
            })
            .unwrap();
        assert_eq!(
            store.message_templates().unwrap()[1].subject,
            "Invoice for October"
        );
        store.delete_message_template(thanks).unwrap();
        assert_eq!(names(), ["Invoice attached"]);
    }

    #[test]
    fn automated_senders_stay_out_of_people_and_search() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "me@example.org", "#2F8F83"))
            .unwrap();
        let cases = [
            (
                "Notifications from WP <site@example.org>",
                "Site needs confirmation of the admin email",
                "",
            ),
            (
                "WordPress <site@example.net>",
                "[Site] Some plugins were updated automatically",
                "",
            ),
            (
                "Provider <service@example.org>",
                "*****SPAM***** flagged message",
                "",
            ),
            (
                "Provider <service@example.net>",
                "[SPAM] flagged message",
                "",
            ),
            (
                "Provider <service@example.com>",
                "***SPAM*** flagged message",
                "",
            ),
            ("E-invoicing <noreply@invoice.example>", "Invoice", ""),
            (
                "CMS <admin@cms.example>",
                "Site update",
                "X-Mailer: WordPress/6.8\r\n",
            ),
            (
                "CMS <admin@cms2.example>",
                "Site update",
                "X-WP-Notification: plugin-update\r\n",
            ),
            (
                "Service <hello@service.example>",
                "Notice",
                "X-Auto-Response-Suppress: All\r\n",
            ),
            (
                "Service <hello@service2.example>",
                "Notice",
                "Auto-Submitted: auto-generated\r\n",
            ),
            (
                "Service <hello@service3.example>",
                "Notice",
                "Precedence: junk\r\n",
            ),
            (
                "List <hello@list.example>",
                "Notice",
                "List-Id: <list.example>\r\n",
            ),
            (
                "Shop <hello@shop.example>",
                "Notice",
                "List-Unsubscribe: <https://shop.example/leave>\r\n",
            ),
        ];
        for (i, (sender, subject, headers)) in cases.iter().enumerate() {
            let raw = format!("From: {sender}\r\nSubject: {subject}\r\n{headers}\r\nour automatic systems flagged the attached email as SPAM");
            let parsed = mail_parser::MessageParser::default()
                .parse(raw.as_bytes())
                .unwrap();
            let from = parsed.from().unwrap().first().unwrap();
            let mut m = msg(a, i as u32 + 1, i as i64, true);
            m.from_name = from.name().unwrap_or_default().into();
            m.from_email = from.address().unwrap().into();
            m.subject = subject.to_string();
            m.list = crate::newsletter::list_info(&parsed);
            store.upsert_messages(&[m.clone()]).unwrap();
            assert!(!store.by_person(a, "INBOX", m.uid).unwrap(), "{sender}");
            let query = Query::parse(&m.from_email);
            assert!(
                store.search_people(&query, 10).unwrap().is_empty(),
                "{sender}"
            );
            assert!(crate::notify::automated(&parsed), "{sender}");
        }
        let mut person = msg(a, 100, 100, true);
        person.from_name = "Giulia Rossi".into();
        person.from_email = "giulia@example.org".into();
        person.subject = "Can you check my WordPress plugins?".into();
        store.upsert_messages(&[person]).unwrap();
        assert!(store.by_person(a, "INBOX", 100).unwrap());
        assert_eq!(
            store
                .search_people(&Query::parse("giulia"), 10)
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            store
                .conversations_page(Folder::Inbox, None, Section::Notifications, 0, 50)
                .unwrap()
                .len(),
            // Unsubscribe mail retains the existing Newsletters destination.
            cases.len() - 1
        );
    }

    #[test]
    fn attached_spam_reports_are_automatic_but_personal_forwards_are_people() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "me@example.org", "#2F8F83"))
            .unwrap();
        let mut m = msg(a, 1, 100, true);
        m.from_email = "service@provider.example".into();
        m.subject = "Spam report".into();
        store.upsert_messages(&[m.clone()]).unwrap();
        assert!(store.by_person(a, "INBOX", 1).unwrap());
        store
            .conn
            .execute(
                "INSERT INTO attachment (account, mailbox, uid, part, name, mime, size)
            VALUES (?1, 'INBOX', 1, 1, 'original.eml', 'message/rfc822', 100)",
                params![a.0],
            )
            .unwrap();
        assert!(!store.by_person(a, "INBOX", 1).unwrap());
        assert!(store
            .search_people(&Query::parse("service"), 10)
            .unwrap()
            .is_empty());
        m.subject = "Fwd: Dinner".into();
        store.upsert_messages(&[m]).unwrap();
        assert!(store.by_person(a, "INBOX", 1).unwrap());
    }

    #[test]
    fn people_you_wrote_to_bulk_mail_and_moved_senders() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let from = |uid, email: &str| {
            let mut m = msg(a, uid, 100 + uid as i64, true);
            m.from_email = email.into();
            m
        };
        // A person writing through a group, a B&B at info@ (a role address
        // alone is a person), a bank alert sent as bulk mail, an Italian
        // notice and a plain person.
        let mut group = from(1, "anna@school.example");
        group.list.unsubscribe = "mailto:leave@school.example".into();
        let bnb = from(2, "info@bnb.example");
        let mut bank = from(3, "security@bank.example");
        bank.list.bulk = true;
        let notice = from(4, "avvisi@comune.example");
        let person = from(5, "sara@example.org");
        store
            .upsert_messages(&[group, bnb, bank, notice, person])
            .unwrap();
        let people = |store: &Store| -> Vec<u32> {
            let mut uids: Vec<u32> = store
                .conversations_page(Folder::Inbox, None, Section::People, 0, 10)
                .unwrap()
                .iter()
                .map(|c| c.latest.uid)
                .collect();
            uids.sort();
            uids
        };
        assert_eq!(people(&store), [2, 5]);
        // Written to (one address in mixed case): People from then on.
        let mut sent = from(20, "matteo@studio.it");
        sent.mailbox = "Sent".into();
        sent.reply.recipients = "anna@school.example Info@BnB.example".into();
        store.upsert_messages(&[sent]).unwrap();
        assert_eq!(people(&store), [1, 2, 5]);
        // Moved by hand, either way.
        store
            .set_sender_side("Security@bank.example", Some(true))
            .unwrap();
        store
            .set_sender_side("sara@example.org", Some(false))
            .unwrap();
        assert_eq!(people(&store), [1, 2, 3]);
        assert!(!store.by_person(a, "INBOX", 5).unwrap());
        store.set_sender_side("sara@example.org", None).unwrap();
        assert_eq!(people(&store), [1, 2, 3, 5]);
    }

    #[test]
    fn role_addresses_need_another_signal() {
        use crate::notify::{self, Arrival, Settings};
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "me@studio.example", "#2F8F83"))
            .unwrap();
        let own = store
            .add_account(&imap_account("Studio", "info@recore.example", "#2F8F83"))
            .unwrap();
        store.add_alias(own, "billing@recore.example").unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let now = 1_000_000;
        let arrive = |uid: u32, raw: &str| {
            let parsed = mail_parser::MessageParser::default()
                .parse(raw.as_bytes())
                .unwrap();
            let mut m = msg(a, uid, now - 60, false);
            m.from_email = parsed
                .from()
                .unwrap()
                .first()
                .unwrap()
                .address()
                .unwrap()
                .into();
            m.subject = parsed.subject().unwrap_or_default().into();
            m.list = crate::newsletter::list_info(&parsed);
            Arrival {
                summary: m,
                automated: notify::automated(&parsed),
            }
        };
        let arrivals = [
            // A small business replying in a thread from info@.
            arrive(
                1,
                "From: Small Biz <info@smallbiz.example>\r\nSubject: Re: Quote\r\nIn-Reply-To: <q@studio.example>\r\n\r\nHere it is",
            ),
            // A shop's newsletter from info@.
            arrive(
                2,
                "From: Shop <info@shop.example>\r\nSubject: Sale\r\nList-Unsubscribe: <https://shop.example/u>\r\n\r\nSale",
            ),
            // An automatic bill from billing@.
            arrive(
                3,
                "From: Vendor <billing@vendor.example>\r\nSubject: Invoice\r\nAuto-Submitted: auto-generated\r\n\r\nDue",
            ),
            arrive(
                4,
                "From: Vendor <no-reply@vendor.example>\r\nSubject: Receipt\r\n\r\nPaid",
            ),
            // The person's own other account, automatic or not.
            arrive(
                5,
                "From: Recore <info@recore.example>\r\nSubject: Contact form\r\nAuto-Submitted: auto-generated\r\n\r\nNew message",
            ),
        ];
        store
            .upsert_messages(
                &arrivals
                    .iter()
                    .map(|a| a.summary.clone())
                    .collect::<Vec<_>>(),
            )
            .unwrap();
        let people = |store: &Store| -> Vec<u32> {
            let mut uids: Vec<u32> = store
                .conversations_page(Folder::Inbox, None, Section::People, 0, 10)
                .unwrap()
                .iter()
                .map(|c| c.latest.uid)
                .collect();
            uids.sort();
            uids
        };
        let notified = |store: &Store| -> Vec<u32> {
            let mut arrived = arrivals.to_vec();
            notify::known_people(store, &mut arrived).unwrap();
            let mut uids: Vec<u32> = notify::notices(&arrived, &Settings::default(), now)
                .iter()
                .map(|n| n.uid)
                .collect();
            uids.sort();
            uids
        };
        assert_eq!(people(&store), [1]);
        assert_eq!(
            store
                .search_people(&Query::parse("smallbiz"), 10)
                .unwrap()
                .len(),
            1
        );
        assert_eq!(notified(&store), [1, 5]);
        // Own addresses are never machines.
        for own in [
            "info@recore.example",
            "Billing@Recore.example",
            "me@studio.example",
        ] {
            assert!(store.known_person(own).unwrap(), "{own}");
        }
        assert!(!store.known_person("billing@vendor.example").unwrap());
        // Once the person writes to billing@, it is a person.
        let mut sent = msg(a, 20, now - 120, true);
        sent.mailbox = "Sent".into();
        sent.from_email = "me@studio.example".into();
        sent.reply.recipients = "Billing@Vendor.example".into();
        store.upsert_messages(&[sent]).unwrap();
        assert_eq!(people(&store), [1, 3]);
        assert_eq!(notified(&store), [1, 3, 5]);
        // A conversation the person replied to (to the hotel's Reply-To):
        // the automatic confirmation in it is a person's, a bounce is not.
        let in_thread = |uid: u32, at: i64, from: &str, references: &str| {
            let mut m = msg(a, uid, at, false);
            m.from_email = from.into();
            m.subject = "Room for Friday".into();
            m.reply.message_id = format!("<m{uid}@hotel.example>");
            m.reply.references = references.into();
            m.list.bulk = true;
            m
        };
        let request = in_thread(30, now - 600, "booking@hotel.example", "");
        let mut reply = msg(a, 31, now - 500, true);
        reply.mailbox = "Sent".into();
        reply.from_email = "me@studio.example".into();
        reply.subject = "Re: Room for Friday".into();
        reply.reply.message_id = "<r31@studio.example>".into();
        reply.reply.references = "<m30@hotel.example>".into();
        reply.reply.recipients = "desk@hotel.example".into();
        let confirmed = in_thread(
            32,
            now - 30,
            "booking@hotel.example",
            "<r31@studio.example>",
        );
        let bounce = in_thread(
            33,
            now - 20,
            "mailer-daemon@hotel.example",
            "<r31@studio.example>",
        );
        store
            .upsert_messages(&[request, reply, confirmed.clone()])
            .unwrap();
        assert_eq!(
            store.thread_of(a, "INBOX", 32).unwrap(),
            store.thread_of(a, "INBOX", 30).unwrap()
        );
        assert_eq!(people(&store), [1, 3, 32]);
        store
            .upsert_messages(std::slice::from_ref(&bounce))
            .unwrap();
        assert_eq!(people(&store), [1, 3]);
        let mut late = vec![
            Arrival {
                summary: confirmed,
                automated: true,
            },
            Arrival {
                summary: bounce,
                automated: true,
            },
        ];
        notify::known_people(&store, &mut late).unwrap();
        assert!(!late[0].automated);
        assert!(late[1].automated);
    }

    #[test]
    fn mailing_domains_and_forwarded_vault_mail() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let from = |uid, email: &str, subject: &str| {
            let mut m = msg(a, uid, 100 + uid as i64, true);
            m.from_email = email.into();
            m.subject = subject.into();
            m
        };
        // Automated mail with no list headers, then people.
        let messages = [
            from(
                1,
                "Windowsinsiderprogram@e-mails.microsoft.com",
                "Build 26100",
            ),
            from(2, "ae-daily-picks09@deals.aliexpress.com", "Picks for you"),
            from(3, "cathay-noreply@e.cathaypacific.com", "Account summary"),
            from(4, "wordpress@matteo.example", "New comment"),
            from(5, "marcello@example.org", "Fwd: Il tuo ordine SLG Store"),
            from(6, "shop@store.example", "Your order"),
            from(7, "luca@mail.example", "Dinner"),
            from(8, "orders@store.example", "Receipt"),
        ];
        store.upsert_messages(&messages).unwrap();
        // Vault cards: the forwarded order, an order from a shop he wrote
        // to and a receipt from one he didn't.
        for uid in [5, 6, 8] {
            store
                .conn
                .execute(
                    "INSERT INTO vault_card (account, mailbox, uid, key, data)
                     VALUES (?1, 'INBOX', ?2, ?3, '{}')",
                    params![a.0, uid, format!("k{uid}")],
                )
                .unwrap();
        }
        let mut sent = from(20, "matteo@studio.it", "Question");
        sent.mailbox = "Sent".into();
        sent.reply.recipients = "shop@store.example".into();
        store.upsert_messages(&[sent]).unwrap();
        let mut people: Vec<u32> = store
            .conversations_page(Folder::Inbox, None, Section::People, 0, 10)
            .unwrap()
            .iter()
            .map(|c| c.latest.uid)
            .collect();
        people.sort();
        assert_eq!(people, [5, 6, 7]);
        // The reader connection knows the same functions.
        assert!(machine_address("news@e.brand.example"));
        assert!(machine_address("sender@email2.brand.example"));
        assert!(machine_address("transaction@notice.aliexpress.com"));
        assert!(!machine_address("anna@mail.ru"));
        assert!(!machine_address("anna.rossi@mail.polimi.it"));
        assert!(forwarded("  Fwd: x") && !forwarded("Forward planning"));
    }

    #[test]
    fn written_to_is_filled_from_sent_mail_kept_before() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let mut sent = msg(a, 1, 100, true);
        sent.mailbox = "Sent".into();
        store.upsert_messages(&[sent]).unwrap();
        // Read again later, as for mail kept before the recipients were.
        store
            .set_recipients(
                a,
                "Sent",
                &[(1, "anna@school.example  luca@example.org".into())],
            )
            .unwrap();
        store.conn.execute("DELETE FROM written_to", []).unwrap();
        store
            .conn
            .execute(
                NOTE_WRITTEN_TO,
                params![None::<i64>, None::<String>, None::<u32>],
            )
            .unwrap();
        let mut written: Vec<String> = store
            .conn
            .prepare("SELECT email FROM written_to ORDER BY email")
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .map(|r| r.unwrap())
            .collect();
        written.dedup();
        assert_eq!(written, ["anna@school.example", "luca@example.org"]);
    }

    #[test]
    fn unread_keeps_conversations_with_something_unread() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "w@example.org", "#2F8F83"))
            .unwrap();
        let mut shop = msg(a, 2, 200, false);
        shop.from_email = "no-reply@shop.example".into();
        store
            .upsert_messages(&[msg(a, 1, 100, false), shop, msg(a, 3, 300, true)])
            .unwrap();
        let unread = |section| ListFilter {
            section,
            unread: true,
        };
        let uids = |filter: ListFilter| -> Vec<u32> {
            store
                .conversations_page(Folder::Inbox, None, filter, 0, 10)
                .unwrap()
                .iter()
                .map(|c| c.latest.uid)
                .collect()
        };
        assert_eq!(uids(unread(Section::All)), [2, 1]);
        assert_eq!(uids(unread(Section::People)), [1]);
        assert_eq!(uids(unread(Section::Notifications)), [2]);
        assert_eq!(
            store
                .conversation_count(Folder::Inbox, None, unread(Section::People))
                .unwrap(),
            1
        );
    }

    #[test]
    fn the_inbox_splits_into_people_and_notifications() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "w@example.org", "#2F8F83"))
            .unwrap();
        let mut shop = msg(a, 2, 200, false);
        shop.from_email = "no-reply@shop.example".into();
        let mut alert = msg(a, 3, 300, true);
        alert.from_email = "alerts@bank.example".into();
        store
            .upsert_messages(&[msg(a, 1, 100, false), shop, alert])
            .unwrap();
        let uids = |section| -> Vec<u32> {
            store
                .conversations_page(Folder::Inbox, None, section, 0, 10)
                .unwrap()
                .iter()
                .map(|c| c.latest.uid)
                .collect()
        };
        assert_eq!(uids(Section::People), [1]);
        assert_eq!(uids(Section::Notifications), [3, 2]);
        assert!(store.by_person(a, "INBOX", 1).unwrap());
        assert!(!store.by_person(a, "INBOX", 2).unwrap());
        assert_eq!(uids(Section::All), [3, 2, 1]);
        let unread = |section| store.unread_count(Folder::Inbox, Some(a), section).unwrap();
        assert_eq!(
            (unread(Section::People), unread(Section::Notifications)),
            (1, 1)
        );
        assert_eq!(
            store
                .conversation_count_between(Folder::Inbox, None, Section::Notifications, 0, 250)
                .unwrap(),
            1
        );
    }

    #[test]
    fn conversations_filter_by_account() {
        let mut store = Store::open_in_memory().unwrap();
        let p = store
            .add_account(&imap_account("Personal", "p@example.org", "#E0782F"))
            .unwrap();
        let w = store
            .add_account(&imap_account("Work", "w@example.org", "#2F8F83"))
            .unwrap();
        store
            .upsert_messages(&[
                msg(p, 1, 100, false),
                msg(w, 1, 200, true),
                msg(w, 2, 300, false),
            ])
            .unwrap();
        let uids = |account| -> Vec<_> {
            store
                .conversations_page(Folder::Inbox, account, Section::All, 0, 10)
                .unwrap()
                .iter()
                .map(|c| (c.latest.account, c.latest.uid))
                .collect()
        };
        assert_eq!(uids(None), [(w, 2), (w, 1), (p, 1)]);
        assert_eq!(uids(Some(w)), [(w, 2), (w, 1)]);
        assert_eq!(
            store
                .conversation_count(Folder::Inbox, Some(p), Section::All)
                .unwrap(),
            1
        );
        assert_eq!(
            store
                .unread_count(Folder::Inbox, Some(w), Section::All)
                .unwrap(),
            1
        );
        assert_eq!(
            store
                .unread_count(Folder::Inbox, None, Section::All)
                .unwrap(),
            2
        );
        assert_eq!(
            store
                .conversation_count_between(Folder::Inbox, Some(w), Section::All, 150, 400)
                .unwrap(),
            2
        );
    }

    #[test]
    fn replies_gather_into_one_conversation_across_folders() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "w@example.org", "#2F8F83"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let mail = |uid, at, mailbox: &str, id: &str, refs: &str| MessageSummary {
            mailbox: mailbox.into(),
            reply: ReplyInfo {
                message_id: id.into(),
                references: refs.into(),
                reply_to: String::new(),
                recipients: String::new(),
            },
            ..msg(a, uid, at, true)
        };
        store
            .upsert_messages(&[
                mail(1, 100, "INBOX", "<q1@x>", ""),
                mail(1, 200, "Sent", "<q2@x>", "<q1@x>"),
                // Only In-Reply-To, and its parent arrives later.
                mail(3, 400, "INBOX", "<q4@x>", "<q3@x>"),
                mail(4, 150, "INBOX", "<other@x>", ""),
            ])
            .unwrap();
        assert_eq!(
            store
                .conversation_count(Folder::Inbox, None, Section::All)
                .unwrap(),
            3
        );
        store
            .upsert_messages(&[mail(2, 300, "INBOX", "<q3@x>", "<q1@x> <q2@x>")])
            .unwrap();
        // The same message copied into a second folder counts once.
        store
            .set_folder_role(a, Folder::Archive, "Archive")
            .unwrap();
        store
            .upsert_messages(&[mail(9, 300, "Archive", "<q3@x>", "<q1@x> <q2@x>")])
            .unwrap();

        let inbox = store
            .conversations_page(Folder::Inbox, None, Section::All, 0, 10)
            .unwrap();
        let rows: Vec<_> = inbox.iter().map(|c| (c.latest.uid, c.messages)).collect();
        assert_eq!(rows, [(3, 4), (4, 1)]);
        assert_eq!(
            store
                .conversation_count(Folder::Inbox, None, Section::All)
                .unwrap(),
            2
        );
        assert_eq!(
            store
                .conversation_count_between(Folder::Inbox, None, Section::All, 0, 350)
                .unwrap(),
            1
        );
        let sent = store
            .conversations_page(Folder::Sent, None, Section::All, 0, 10)
            .unwrap();
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0].thread, inbox[0].thread);

        let thread: Vec<_> = store
            .conversation(a, &inbox[0].thread)
            .unwrap()
            .into_iter()
            .map(|(m, folder)| (m.mailbox, m.uid, folder))
            .collect();
        assert_eq!(
            thread,
            [
                ("INBOX".to_owned(), 1, Some(Folder::Inbox)),
                ("Sent".to_owned(), 1, Some(Folder::Sent)),
                ("INBOX".to_owned(), 2, Some(Folder::Inbox)),
                ("INBOX".to_owned(), 3, Some(Folder::Inbox)),
            ]
        );
    }

    #[test]
    fn deleting_account_removes_its_messages() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        store.upsert_messages(&[msg(a, 1, 100, false)]).unwrap();
        store
            .conn
            .execute("DELETE FROM account WHERE id = ?1", params![a.0])
            .unwrap();
        assert!(store.unified(Folder::Inbox, None, 10).unwrap().is_empty());
    }

    #[test]
    fn whole_bodies_fill_and_mend_previews() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let bare = MessageSummary {
            preview: String::new(),
            ..msg(a, 1, 100, false)
        };
        store
            .upsert_messages(&[bare, msg(a, 2, 200, false)])
            .unwrap();
        let preview = |uid: u32| -> String {
            store
                .conn
                .query_row(
                    "SELECT preview FROM message WHERE uid = ?1",
                    params![uid],
                    |r| r.get(0),
                )
                .unwrap()
        };
        let body = Body {
            text: "Ciao  Matteo,\n> old reply\necco la fattura.".into(),
            ..Body::default()
        };
        store.set_full_body(a, "INBOX", 1, &body).unwrap();
        store.set_full_body(a, "INBOX", 2, &body).unwrap();
        assert_eq!(preview(1), "Ciao Matteo, ecco la fattura.");
        // A preview listed from a cut part gives way to the whole body's.
        assert_eq!(preview(2), "Ciao Matteo, ecco la fattura.");
        let html = Body {
            text: "Your accountIf this was you".into(),
            html: Some("<p>Your account</p><p>If this was you</p>".into()),
            ..Body::default()
        };
        store.set_full_body(a, "INBOX", 2, &html).unwrap();
        assert_eq!(preview(2), "Your account If this was you");
    }

    #[test]
    fn old_previews_are_mended_once() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        store
            .upsert_messages(&[
                msg(a, 1, 100, false),
                msg(a, 2, 200, false),
                msg(a, 3, 300, false),
            ])
            .unwrap();
        // Mail listed from now on is right at once.
        assert!(store.previews_to_mend(a, "INBOX", 10).unwrap().is_empty());
        let html = Body {
            html: Some("<p>Your account</p><p>If this was you</p>".into()),
            ..Body::default()
        };
        store.set_full_body(a, "INBOX", 2, &html).unwrap();
        // As if listed before: blocks run together.
        store
            .conn
            .execute_batch(
                "UPDATE message SET preview = 'Your accountIf this was you';
                 INSERT INTO preview_stale SELECT account, mailbox, uid FROM message;",
            )
            .unwrap();
        let preview = |store: &Store, uid: u32| -> String {
            store
                .conn
                .query_row(
                    "SELECT preview FROM message WHERE uid = ?1",
                    params![uid],
                    |r| r.get(0),
                )
                .unwrap()
        };
        // The body here mends its preview now; the others are fetched.
        assert_eq!(store.previews_to_mend(a, "INBOX", 10).unwrap(), [3, 1]);
        assert_eq!(preview(&store, 2), "Your account If this was you");
        store
            .mend_previews(a, "INBOX", &[(3, "Hello there".into()), (1, String::new())])
            .unwrap();
        assert_eq!(preview(&store, 3), "Hello there");
        assert_eq!(preview(&store, 1), "Your accountIf this was you");
        assert!(store.previews_to_mend(a, "INBOX", 10).unwrap().is_empty());
    }

    #[test]
    fn files_listed_early_give_way_to_the_body() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        let mut sent = msg(a, 2, 200, false);
        sent.mailbox = "Sent".into();
        store
            .upsert_messages(&[msg(a, 1, 100, false), sent])
            .unwrap();
        assert_eq!(store.files_unchecked(a, "INBOX", 10).unwrap(), [1]);
        assert!(store.files_unchecked(a, "Sent", 10).unwrap().is_empty());
        let photo = Attachment {
            part: 0,
            name: "lake.jpg".into(),
            mime: "image/jpeg".into(),
            size: 3_800_000,
            section: Some("2".into()),
            encoding: Some("base64".into()),
        };
        store
            .set_listed_files(a, "INBOX", &[(1, vec![photo.clone()])])
            .unwrap();
        assert!(store.files_unchecked(a, "INBOX", 10).unwrap().is_empty());
        let files = store.files(None, 10).unwrap();
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].2, photo);
        assert_eq!(store.attachment(a, "INBOX", 1, 0).unwrap(), Some(photo));
        store.set_thumb(a, "INBOX", 1, "lake.jpg", b"jpeg").unwrap();
        // The body's own list replaces it, and the preview stays.
        let body = Body {
            text: "Hi".into(),
            attachments: vec![Attachment {
                part: 4,
                name: "lake.jpg".into(),
                mime: "image/jpeg".into(),
                size: 3_790_000,
                ..Default::default()
            }],
            ..Body::default()
        };
        store.set_full_body(a, "INBOX", 1, &body).unwrap();
        let files = store.files(Some(a), 10).unwrap();
        // It keeps the outline's address to fetch the file alone.
        assert_eq!(
            (files[0].2.part, files[0].2.section.as_deref()),
            (4, Some("2"))
        );
        assert_eq!(
            store.thumb(a, "INBOX", 1, "lake.jpg").unwrap().as_deref(),
            Some(&b"jpeg"[..])
        );
        // A late outline changes nothing.
        store
            .set_listed_files(a, "INBOX", &[(1, Vec::new())])
            .unwrap();
        assert_eq!(store.files(None, 10).unwrap().len(), 1);
        assert_eq!(store.file_count(a, "INBOX", 1).unwrap(), (1, 1));
        assert_eq!(store.file_count(a, "INBOX", 2).unwrap(), (0, 0));
    }

    #[test]
    fn snoozes_follow_the_message_to_its_new_folder() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        store
            .set_folder_role(a, Folder::Snoozed, "Snoozed")
            .unwrap();
        let mut first = msg(a, 1, 100, true);
        first.reply.message_id = "<m1@example.org>".into();
        store.upsert_messages(&[first.clone()]).unwrap();
        store.snooze(a, "INBOX", &[1], 5_000).unwrap();
        assert_eq!(store.unified(Folder::Inbox, None, 10).unwrap().len(), 0);

        // The server moved it, without keywords: a new UID in Snoozed.
        store.remove_messages(a, "INBOX", &[1]).unwrap();
        let mut moved = first;
        moved.mailbox = "Snoozed".into();
        moved.uid = 7;
        store.upsert_messages(&[moved]).unwrap();
        let snoozed = store.snoozed(None).unwrap();
        assert_eq!((snoozed[0].0.uid, snoozed[0].1), (7, Some(5_000)));
        assert_eq!(store.next_wake(a).unwrap(), Some(5_000));

        // Not yet, then yes.
        assert_eq!(store.queue_wakes(a, 4_999).unwrap(), 0);
        assert_eq!(store.queue_wakes(a, 5_000).unwrap(), 1);
        assert_eq!(store.queue_wakes(a, 5_001).unwrap(), 0);
        let pending = store.pending_changes(a).unwrap();
        assert_eq!(pending[0].change, Change::Wake(5_000));
        assert!(store.snoozed(None).unwrap().is_empty());
        assert_eq!(store.next_wake(a).unwrap(), None);
    }

    #[test]
    fn a_reply_brings_a_message_snoozed_unless_reply_back() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        store
            .set_folder_role(a, Folder::Snoozed, "Snoozed")
            .unwrap();
        let mut asked = msg(a, 1, 100, true);
        asked.reply.message_id = "<q@example.org>".into();
        store.upsert_messages(&[asked.clone()]).unwrap();
        store.snooze(a, "INBOX", &[1], 900_000).unwrap();
        store.snooze_unless_reply(a, "INBOX", &[1], 1_000).unwrap();
        store.remove_messages(a, "INBOX", &[1]).unwrap();
        asked.mailbox = "Snoozed".into();
        asked.uid = 7;
        store.upsert_messages(&[asked]).unwrap();
        assert_eq!(store.next_wake(a).unwrap(), Some(900_000));

        // Our own message in the thread is no reply.
        let mut mine = msg(a, 2, 2_000, true);
        mine.from_email = "A@example.org".into();
        mine.reply.message_id = "<mine@example.org>".into();
        mine.reply.references = "<q@example.org>".into();
        store.upsert_messages(&[mine]).unwrap();
        assert_eq!(store.queue_wakes(a, 2_000).unwrap(), 0);

        // Someone else's is: it comes back now.
        let mut theirs = msg(a, 3, 3_000, true);
        theirs.reply.message_id = "<r@example.org>".into();
        theirs.reply.references = "<q@example.org>".into();
        store.upsert_messages(&[theirs]).unwrap();
        assert_eq!(store.next_wake(a).unwrap(), Some(0));
        assert_eq!(store.queue_wakes(a, 3_000).unwrap(), 1);
        assert_eq!(
            store.pending_changes(a).unwrap()[0].change,
            Change::Wake(900_000)
        );
    }

    #[test]
    fn bodies_trust_settings_and_privacy_totals() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        store.upsert_messages(&[msg(a, 1, 100, false)]).unwrap();
        // Cached before HTML was kept: fetched again.
        store
            .conn
            .execute(
                "INSERT INTO message_body (account, mailbox, uid, text) VALUES (?1, 'INBOX', 1, 'old')",
                params![a.0],
            )
            .unwrap();
        assert_eq!(store.body(a, "INBOX", 1).unwrap().as_deref(), Some("old"));
        assert_eq!(store.full_body(a, "INBOX", 1).unwrap(), None);
        let pdf = Attachment {
            part: 3,
            name: "quote.pdf".into(),
            mime: "application/pdf".into(),
            size: 2_400_000,
            ..Default::default()
        };
        let mut body = Body {
            text: "Hi".into(),
            html: Some("<p>Hi</p>".into()),
            attachments: vec![pdf.clone()],
            calendar: Some("BEGIN:VCALENDAR".into()),
            inline: Vec::new(),
            auth: Default::default(),
        };
        store.set_full_body(a, "INBOX", 1, &body).unwrap();
        assert_eq!(store.full_body(a, "INBOX", 1).unwrap(), Some(body.clone()));
        assert!(store.has_invite(a, "INBOX", 1).unwrap());
        assert!(!store.has_invite(a, "INBOX", 2).unwrap());
        // Pictures inside it are kept apart, by Content-ID.
        let logo = InlineImage {
            cid: "logo@studio".into(),
            mime: "image/png".into(),
            data: b"png".to_vec(),
        };
        let with_logo = Body {
            inline: vec![logo],
            ..body.clone()
        };
        store.set_full_body(a, "INBOX", 1, &with_logo).unwrap();
        assert_eq!(
            store
                .inline_image(a, "INBOX", 1, "logo@studio")
                .unwrap()
                .as_deref(),
            Some(&b"png"[..])
        );
        assert_eq!(store.inline_image(a, "INBOX", 1, "other").unwrap(), None);
        // Caching again replaces the list.
        body.attachments.clear();
        store.set_full_body(a, "INBOX", 1, &body).unwrap();
        assert!(store.attachments(a, "INBOX", 1).unwrap().is_empty());
        body.attachments.push(pdf);
        store.set_full_body(a, "INBOX", 1, &body).unwrap();
        // They go with the message.
        store
            .conn
            .execute("DELETE FROM message WHERE uid = 1", [])
            .unwrap();
        assert!(store.attachments(a, "INBOX", 1).unwrap().is_empty());
        store.upsert_messages(&[msg(a, 1, 100, false)]).unwrap();

        assert!(!store.is_trusted("ciao@lume.example").unwrap());
        store.set_trusted("Ciao@Lume.example", true, 10).unwrap();
        store.set_trusted("sara@studio.example", true, 20).unwrap();
        assert!(store.is_trusted("ciao@lume.example").unwrap());
        let emails = |store: &Store| -> Vec<String> {
            store
                .trusted_senders()
                .unwrap()
                .into_iter()
                .map(|t| t.email)
                .collect()
        };
        assert_eq!(emails(&store), ["sara@studio.example", "Ciao@Lume.example"]);
        store.set_trusted("ciao@lume.example", false, 30).unwrap();
        assert_eq!(emails(&store), ["sara@studio.example"]);
        store.set_trusted("Julia@example.org", true, 40).unwrap();
        let first = &store.trusted_senders().unwrap()[0];
        assert_eq!((first.name.as_str(), first.since), ("Julia Reed", 40));

        assert_eq!(store.setting("privacy.images").unwrap(), None);
        store.set_setting("privacy.images", "allow").unwrap();
        assert_eq!(
            store.setting("privacy.images").unwrap().as_deref(),
            Some("allow")
        );

        let counts = |trackers, links, pixels, suspicious| PrivacyCounts {
            trackers,
            links,
            pixels,
            suspicious,
        };
        store
            .log_privacy(a, "INBOX", 1, 100, counts(3, 12, 2, 1))
            .unwrap();
        store
            .log_privacy(a, "INBOX", 1, 200, counts(3, 12, 2, 1))
            .unwrap();
        store
            .log_privacy(a, "INBOX", 2, 50, counts(1, 1, 1, 0))
            .unwrap();
        assert_eq!(store.privacy_totals(60).unwrap(), counts(3, 12, 2, 1));
        assert_eq!(store.privacy_totals(0).unwrap(), counts(4, 13, 3, 1));
    }

    #[test]
    fn signatures_keep_one_job_each_per_account() {
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "a@example.org", "#2F8F83"))
            .unwrap();
        let b = store
            .add_account(&imap_account("Personal", "b@example.org", "#E0782F"))
            .unwrap();
        let work = Signature {
            account: a,
            label: "Work".into(),
            name: "Matteo Neri".into(),
            accent: Accent::Terracotta,
            template: Template::Logo,
            logo: Some(Logo {
                mime: "image/png".into(),
                data: vec![9; 10],
            }),
            for_new: true,
            for_replies: true,
            ..Default::default()
        };
        let w = store.save_signature(&work).unwrap();
        let short = Signature {
            account: a,
            label: "Short".into(),
            name: "Matteo".into(),
            for_replies: true,
            ..Default::default()
        };
        let s = store.save_signature(&short).unwrap();
        let other = Signature {
            account: b,
            label: "Home".into(),
            for_new: true,
            ..Default::default()
        };
        store.save_signature(&other).unwrap();

        let all = store.signatures().unwrap();
        assert_eq!(all.len(), 3);
        let got = store.signature(w).unwrap().unwrap();
        assert_eq!(got.template, Template::Logo);
        assert_eq!(got.accent, Accent::Terracotta);
        assert_eq!(got.logo.unwrap().data, vec![9; 10]);
        // Short took replies from Work; the other account kept its own.
        assert!(got.for_new && !got.for_replies);
        assert!(store.signature(s).unwrap().unwrap().for_replies);
        assert!(all.iter().any(|x| x.account == b && x.for_new));

        let mut edited = store.signature(s).unwrap().unwrap();
        edited.for_new = true;
        edited.name = "Teo".into();
        store.save_signature(&edited).unwrap();
        assert!(!store.signature(w).unwrap().unwrap().for_new);
        assert_eq!(store.signature(s).unwrap().unwrap().name, "Teo");

        store.delete_signature(s).unwrap();
        assert_eq!(store.signatures().unwrap().len(), 2);
        // They go with their account.
        store.remove_account(a).unwrap();
        assert_eq!(store.signatures().unwrap().len(), 1);
    }

    #[test]
    fn calendars_keep_their_switches_and_only_busy_events() {
        use crate::calendar::RemoteCalendar;
        let mut store = Store::open_in_memory().unwrap();
        let source = store
            .add_calendar_source(
                "caldav",
                "iCloud",
                "https://cal/home/",
                "teo@icloud.com",
                None,
            )
            .unwrap();
        let cal = |url: &str, name: &str| RemoteCalendar {
            url: url.into(),
            name: name.into(),
            color: Some("#E0782F".into()),
            read_only: false,
        };
        store
            .set_calendars(
                source,
                &[
                    cal("https://cal/p/", "Personal"),
                    cal("https://cal/f/", "Family"),
                ],
            )
            .unwrap();
        let first = store.calendars().unwrap();
        assert_eq!(first.len(), 2);
        store.set_calendar_availability(first[1].id, false).unwrap();
        store
            .set_calendars(
                source,
                &[
                    cal("https://cal/p/", "Personal"),
                    cal("https://cal/f/", "Family 2"),
                ],
            )
            .unwrap();
        let again = store.calendars().unwrap();
        assert_eq!(again[1].name, "Family 2");
        assert!(!again[1].availability);

        let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:1\r\nDTSTART:20261023T133000Z\r\n\
            DTEND:20261023T143000Z\r\nSUMMARY:Dentist\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:2\r\n\
            DTSTART:20261023T100000Z\r\nDTEND:20261023T110000Z\r\nSUMMARY:Free\r\nTRANSP:TRANSPARENT\r\n\
            END:VEVENT\r\nEND:VCALENDAR\r\n";
        let events = crate::invite::events(ics);
        store.set_calendar_events(again[0].id, &events).unwrap();
        store.set_calendar_events(again[1].id, &events).unwrap();
        let busy = store.busy(1_792_750_000, 1_792_770_000).unwrap();
        assert_eq!(busy.len(), 1);
        assert_eq!(
            (busy[0].summary.as_str(), busy[0].calendar.as_str()),
            ("Dentist", "Personal")
        );

        store.delete_calendar_source(source).unwrap();
        assert!(store.calendars().unwrap().is_empty());
        assert!(store.busy(0, i64::MAX / 2).unwrap().is_empty());
    }

    #[test]
    fn a_vault_notice_is_given_once() {
        let store = Store::open_in_memory().unwrap();
        assert!(store.take_vault_notice("TRK1", "parcel", 1).unwrap());
        assert!(!store.take_vault_notice("TRK1", "parcel", 2).unwrap());
        assert!(store.take_vault_notice("TRK1", "due", 2).unwrap());
    }

    #[test]
    fn gmail_folders_read_without_brackets() {
        let store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "me@gmail.com", "#3451D1"))
            .unwrap();
        let f = |mailbox: &str, name: &str, depth, selectable| AccountFolder {
            mailbox: mailbox.into(),
            name: name.into(),
            depth,
            selectable,
            unread: 0,
            total: 0,
        };
        store
            .set_account_folders(
                a,
                &[
                    f("[Gmail]", "[Gmail]", 0, false),
                    f("[Gmail]/Spam", "Spam", 1, true),
                    f("[]", "[]", 0, true),
                ],
            )
            .unwrap();
        let names: Vec<(String, String)> = store
            .account_folders(a)
            .unwrap()
            .into_iter()
            .map(|f| (f.mailbox, f.name))
            .collect();
        assert!(names.contains(&("[Gmail]".into(), "Gmail".into())));
        assert!(names.contains(&("[Gmail]/Spam".into(), "Spam".into())));
        assert!(names.contains(&("[]".into(), "[]".into())));
    }

    #[test]
    fn dragged_folders_keep_their_order_among_siblings() {
        let store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Work", "me@work.it", "#3451D1"))
            .unwrap();
        let f = |mailbox: &str, depth| AccountFolder {
            mailbox: mailbox.into(),
            name: mailbox.rsplit('/').next().unwrap().into(),
            depth,
            selectable: true,
            unread: 0,
            total: 0,
        };
        let names = |store: &Store| -> Vec<String> {
            store
                .account_folders(a)
                .unwrap()
                .into_iter()
                .map(|f| f.mailbox)
                .collect()
        };
        store
            .set_account_folders(
                a,
                &[
                    f("Clients", 0),
                    f("Clients/Acme", 1),
                    f("Clients/Bianchi", 1),
                    f("Invoices", 0),
                    f("Travel", 0),
                ],
            )
            .unwrap();
        store
            .set_folder_order(a, &["Travel".into(), "Clients".into(), "Invoices".into()])
            .unwrap();
        store
            .set_folder_order(a, &["Clients/Bianchi".into(), "Clients/Acme".into()])
            .unwrap();
        assert_eq!(
            names(&store),
            [
                "Travel",
                "Clients",
                "Clients/Bianchi",
                "Clients/Acme",
                "Invoices"
            ]
        );
        // The next look at the server keeps it; a new folder goes after.
        store
            .set_account_folders(
                a,
                &[
                    f("Archive 2025", 0),
                    f("Clients", 0),
                    f("Clients/Acme", 1),
                    f("Clients/Bianchi", 1),
                    f("Invoices", 0),
                    f("Travel", 0),
                ],
            )
            .unwrap();
        assert_eq!(
            names(&store),
            [
                "Travel",
                "Clients",
                "Clients/Bianchi",
                "Clients/Acme",
                "Invoices",
                "Archive 2025"
            ]
        );
    }

    #[test]
    fn unopened_newsletters_leave_nightly_when_turned_on() {
        use crate::pending::{
            archive_unopened_newsletters, ARCHIVE_UNOPENED_NEWSLETTERS, NEWSLETTERS_UNOPENED,
            UNOPENED_ARCHIVED,
        };
        let mut store = Store::open_in_memory().unwrap();
        let a = store
            .add_account(&imap_account("Personal", "a@example.org", "#E0782F"))
            .unwrap();
        let letter = |uid, at, seen| MessageSummary {
            from_email: "issue@forma.example".into(),
            list: ListInfo {
                newsletter: true,
                unsubscribe: "https://forma.example/u".into(),
                one_click: true,
                bulk: false,
                receipt: None,
            },
            ..msg(a, uid, at, seen)
        };
        let day = 24 * 60 * 60;
        let now = 100 * day;
        store
            .upsert_messages(&[
                letter(1, now - NEWSLETTERS_UNOPENED - day, false),
                letter(2, now - NEWSLETTERS_UNOPENED - day, true),
                letter(3, now - day, false),
            ])
            .unwrap();
        let store = Mutex::new(store);
        // Off unless turned on.
        assert_eq!(archive_unopened_newsletters(&store, a, now).unwrap(), 0);
        store
            .lock()
            .unwrap()
            .set_setting(ARCHIVE_UNOPENED_NEWSLETTERS, "on")
            .unwrap();
        assert_eq!(archive_unopened_newsletters(&store, a, now).unwrap(), 1);
        let mut s = store.lock().unwrap();
        assert_eq!(s.pending_changes(a).unwrap()[0].uid, 1);
        assert_eq!(s.setting(UNOPENED_ARCHIVED).unwrap().as_deref(), Some("1"));
        s.upsert_messages(&[letter(4, now - NEWSLETTERS_UNOPENED - day, false)])
            .unwrap();
        drop(s);
        // Once a day.
        assert_eq!(
            archive_unopened_newsletters(&store, a, now + 3600).unwrap(),
            0
        );
        assert_eq!(
            archive_unopened_newsletters(&store, a, now + day).unwrap(),
            1
        );
        let s = store.lock().unwrap();
        assert_eq!(s.setting(UNOPENED_ARCHIVED).unwrap().as_deref(), Some("2"));
        // Kept on this device: the sync space leaves it out.
        let tables = s.space_tables().unwrap();
        let keys: Vec<&str> = tables["setting"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|r| r["key"].as_str())
            .collect();
        assert!(keys.contains(&ARCHIVE_UNOPENED_NEWSLETTERS));
        assert!(!keys.iter().any(|k| k.starts_with("nightly.")));
    }

    #[test]
    fn rules_travel_in_the_space_but_what_they_did_stays() {
        use crate::rules::{Action, Field, Op, Rule};
        let rule = |account, value: &str| Rule {
            id: 0,
            account,
            field: Field::Sender,
            op: Op::Contains,
            value: value.into(),
            action: Action::MoveTo("Clients".into()),
            enabled: true,
            last_run: None,
            matched: 0,
        };
        let mac = Store::open_in_memory().unwrap();
        let w = mac
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        let mine = mac.save_rule(&rule(Some(w), "@acme.it")).unwrap();
        mac.save_rule(&rule(None, "@studio.it")).unwrap();
        mac.set_setting("rules.sorted.1", "500").unwrap();
        let before = serde_json::to_string(&mac.space_tables().unwrap()).unwrap();
        // What a rule did here doesn't change what the space carries.
        mac.rule_ran(mine, 3, 900).unwrap();
        let tables = mac.space_tables().unwrap();
        let json = serde_json::to_string(&tables).unwrap();
        assert_eq!(json, before);
        assert!(!json.contains("rules.sorted"));

        let mut phone = Store::open_in_memory().unwrap();
        phone
            .add_account(&imap_account("Home", "teo@posta.it", "#E0782F"))
            .unwrap();
        let ids = phone
            .take_space_tables(&serde_json::from_str(&json).unwrap())
            .unwrap();
        let rules = phone.rules().unwrap();
        assert_eq!(rules.len(), 2);
        assert_eq!(rules[0].account, Some(ids["matteo@studio.it"]));
        assert_eq!(rules[1].account, None);
        assert_eq!(rules[0].matched, 0);
        // The phone's own runs survive the next round.
        phone.rule_ran(rules[0].id, 2, 1000).unwrap();
        phone
            .take_space_tables(&serde_json::from_str(&json).unwrap())
            .unwrap();
        let rules = phone.rules().unwrap();
        assert_eq!((rules[0].matched, rules[0].last_run), (2, Some(1000)));

        // A space from before rules synced leaves the phone's rules alone.
        let mut old: serde_json::Map<String, serde_json::Value> =
            serde_json::from_str(&json).unwrap();
        old.remove("rule");
        phone.take_space_tables(&old).unwrap();
        assert_eq!(phone.rules().unwrap().len(), 2);
    }

    #[test]
    fn a_feed_keeps_how_often_it_asks_to_be_read() {
        let store = Store::open_in_memory().unwrap();
        let id = store
            .add_calendar_source("ics", "Holidays", "https://h/", "", None)
            .unwrap();
        let every = |s: &Store| s.calendar_sources().unwrap()[0].refresh;
        assert_eq!(every(&store), None);
        store.set_calendar_refresh(id, Some(3600)).unwrap();
        assert_eq!(every(&store), Some(3600));
        store.set_calendar_refresh(id, None).unwrap();
        assert_eq!(every(&store), None);
    }

    #[test]
    fn connected_calendars_travel_and_keep_what_was_read_here() {
        use crate::calendar::RemoteCalendar;
        let cal = |url: &str, name: &str| RemoteCalendar {
            url: url.into(),
            name: name.into(),
            color: None,
            read_only: false,
        };
        let mut mac = Store::open_in_memory().unwrap();
        let w = mac
            .add_account(&imap_account("Work", "matteo@studio.it", "#2F8F83"))
            .unwrap();
        let icloud = mac
            .add_calendar_source(
                "caldav",
                "iCloud",
                "https://caldav.icloud.com/1/",
                "teo",
                None,
            )
            .unwrap();
        mac.set_calendars(icloud, &[cal("/home/", "Home"), cal("/work/", "Work")])
            .unwrap();
        let fm = mac
            .add_calendar_source("caldav", "Fastmail", "https://fm/", "", Some(w))
            .unwrap();
        mac.set_calendars(fm, &[cal("/fm/", "Personal")]).unwrap();
        mac.set_calendar_synced(icloud, 500).unwrap();
        let before = serde_json::to_string(&mac.space_tables().unwrap()).unwrap();
        // Reading a source again isn't a change to sync.
        mac.set_calendar_synced(icloud, 900).unwrap();
        let json = serde_json::to_string(&mac.space_tables().unwrap()).unwrap();
        assert_eq!(json, before);

        let mut phone = Store::open_in_memory().unwrap();
        phone
            .add_account(&imap_account("Home", "teo@posta.it", "#E0782F"))
            .unwrap();
        let ids = phone
            .take_space_tables(&serde_json::from_str(&json).unwrap())
            .unwrap();
        let sources = phone.calendar_sources().unwrap();
        assert_eq!(sources.len(), 2);
        assert_eq!(sources[0].synced, None);
        assert_eq!(sources[1].account, Some(ids["matteo@studio.it"]));
        assert_eq!(phone.calendars().unwrap().len(), 3);
        // What the phone read stays across the next round.
        let home = phone.calendars().unwrap()[0].id;
        phone
            .conn
            .execute(
                "INSERT INTO calendar_event (calendar, uid, start, end, all_day, floating, summary)
                 VALUES (?1, 'yoga', 10, 20, 0, 0, 'Yoga')",
                params![home],
            )
            .unwrap();
        phone.set_calendar_synced(icloud, 700).unwrap();
        // Meanwhile the Mac renamed one calendar and dropped Fastmail.
        mac.set_calendars(icloud, &[cal("/home/", "Casa"), cal("/work/", "Work")])
            .unwrap();
        mac.delete_calendar_source(fm).unwrap();
        let json = serde_json::to_string(&mac.space_tables().unwrap()).unwrap();
        phone
            .take_space_tables(&serde_json::from_str(&json).unwrap())
            .unwrap();
        let sources = phone.calendar_sources().unwrap();
        assert_eq!(sources.len(), 1);
        assert_eq!(sources[0].synced, Some(700));
        let names: Vec<String> = phone
            .calendars()
            .unwrap()
            .into_iter()
            .map(|c| c.name)
            .collect();
        assert_eq!(names, ["Casa", "Work"]);
        let events: i64 = phone
            .conn
            .query_row("SELECT COUNT(*) FROM calendar_event", [], |r| r.get(0))
            .unwrap();
        assert_eq!(events, 1);
    }

    #[test]
    fn syncing_an_empty_calendar_source_list_removes_sources_and_cached_events() {
        let mut store = Store::open_in_memory().unwrap();
        let source = store
            .add_calendar_source("ics", "Holidays", "https://h/", "", None)
            .unwrap();
        store
            .set_calendars(
                source,
                &[crate::calendar::RemoteCalendar {
                    url: "https://h/calendar".into(),
                    name: "Holidays".into(),
                    color: None,
                    read_only: true,
                }],
            )
            .unwrap();
        let calendar = store.calendars().unwrap()[0].id;
        store
            .conn
            .execute(
                "INSERT INTO calendar_event (calendar, uid, start, end, all_day, floating, summary)
             VALUES (?1, 'holiday', 10, 20, 0, 0, 'Holiday')",
                params![calendar],
            )
            .unwrap();
        store.set_calendar_refresh(source, Some(3600)).unwrap();
        let mut tables = store.space_tables().unwrap();
        // Older snapshots without calendar tables must leave local data alone.
        tables.remove("calendar_source");
        tables.remove("calendar");
        store.take_space_tables(&tables).unwrap();
        assert_eq!(store.calendar_sources().unwrap().len(), 1);
        tables.insert("calendar_source".into(), serde_json::json!([]));
        tables.insert("calendar".into(), serde_json::json!([]));
        store.take_space_tables(&tables).unwrap();
        assert!(store.calendar_sources().unwrap().is_empty());
        assert!(store.calendars().unwrap().is_empty());
        for table in ["calendar_event", "calendar_refresh"] {
            let count: i64 = store
                .conn
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |r| r.get(0))
                .unwrap();
            assert_eq!(count, 0, "{table}");
        }
        // Repeating an empty snapshot remains safe.
        store.take_space_tables(&tables).unwrap();
    }
}
