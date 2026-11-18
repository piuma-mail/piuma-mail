//! Who a message went to and who an answer goes to (Reply all, Reply to
//! list), the raw message (View source, Save as .eml, Forward as
//! attachment), Redirect, and muting a conversation.

use flutter_rust_bridge::frb;
use piuma_core::envelope::{self, Address, Envelope, ReplyMode};
use piuma_core::outbox::Outgoing;
use piuma_core::remote::Remote;
use piuma_core::{AccountId, Store};

use super::engine::{bulk_reader, engine, now_secs, send_outbox_at, store, EngineError, ErrorKind};

/// One person on a line of a message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MailAddress {
    /// May be empty.
    pub name: String,
    pub email: String,
    /// One of the person's own addresses (the account's, or an alias).
    pub you: bool,
}

fn mail_address(a: &Address, own: &[String]) -> MailAddress {
    MailAddress {
        name: a.name.clone(),
        email: a.email.clone(),
        you: envelope::is_own(&a.email, own),
    }
}

/// Who a message went to, as the reader shows it, and who each answer
/// goes to, as compose writes them (`Name <a@b.c>`).
#[derive(Debug, Clone)]
pub struct MessageEnvelope {
    pub to: Vec<MailAddress>,
    pub cc: Vec<MailAddress>,
    /// The person is on neither To nor Cc: "You were Bcc'd".
    pub bcc_you: bool,
    /// Reply: the author, every Reply-To address.
    pub reply_to: Vec<String>,
    /// Reply all: To and Cc, without the person's own addresses.
    pub reply_all_to: Vec<String>,
    pub reply_all_cc: Vec<String>,
    /// Reply to list: the List-Post address, when the list takes posts.
    pub list_post: Option<String>,
    /// The conversation is muted.
    pub muted: bool,
    /// Reply all follows a Mail-Followup-To that names people the message
    /// shows nowhere else: it opens compose, to be seen before it goes,
    /// and isn't offered where it would go at once (the quick reply, the
    /// watch, a notice).
    pub reply_all_review: bool,
}

/// What [MessageEnvelope] says, from what the store keeps.
pub(crate) fn describe(
    store: &Store,
    account: AccountId,
    mailbox: &str,
    uid: u32,
    envelope: &Envelope,
) -> Result<MessageEnvelope, EngineError> {
    let row = store
        .message(account, mailbox, uid)?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "unknown message"))?;
    let own = store.own_addresses(account)?;
    let from = Address::new(&row.from_name, &row.from_email);
    let shown = |list: &[Address]| list.iter().map(Address::display).collect::<Vec<_>>();
    let reply = envelope::reply_recipients(envelope, &from, &own, ReplyMode::Sender);
    let all = envelope::reply_recipients(envelope, &from, &own, ReplyMode::All);
    Ok(MessageEnvelope {
        to: envelope.to.iter().map(|a| mail_address(a, &own)).collect(),
        cc: envelope.cc.iter().map(|a| mail_address(a, &own)).collect(),
        bcc_you: envelope::bcc_you(envelope, &row.from_email, &own),
        reply_to: shown(&reply.to),
        reply_all_to: shown(&all.to),
        reply_all_cc: shown(&all.cc),
        list_post: (!envelope.list_post.is_empty()).then(|| envelope.list_post.clone()),
        muted: store.thread_muted(account, mailbox, uid)?,
        reply_all_review: envelope::followup_needs_review(envelope, &from),
    })
}

/// How many more people Reply all reaches than Reply, as the app counts
/// them (`MailEnvelope.others`): 0 for a blind copy, and where Reply all
/// must be seen in compose first.
pub(crate) fn others(e: &MessageEnvelope) -> u32 {
    if e.bcc_you || e.reply_all_review {
        return 0;
    }
    let bare = |a: &String| {
        envelope::bare_address(a)
            .unwrap_or_else(|| a.trim().to_owned())
            .to_lowercase()
    };
    let reply: std::collections::HashSet<String> = e.reply_to.iter().map(bare).collect();
    e.reply_all_to
        .iter()
        .chain(&e.reply_all_cc)
        .map(bare)
        .collect::<std::collections::HashSet<_>>()
        .difference(&reply)
        .count() as u32
}

/// The recipient headers of a message and who answers go to. Mail kept
/// before they were read has its headers read again, once, from the
/// server.
pub async fn message_envelope(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<MessageEnvelope, EngineError> {
    let id = AccountId(account_id);
    let kept = bulk_reader()?.envelope(id, &mailbox, uid)?;
    let envelope = match kept {
        Some(e) => e,
        None => {
            let raw = raw_message(id, mailbox.clone(), uid).await?;
            let read = Envelope::from_raw(&raw)
                .ok_or_else(|| EngineError::new(ErrorKind::Other, "unreadable message"))?;
            store()?.set_envelope(id, &mailbox, uid, &read)?;
            read
        }
    };
    let store = bulk_reader()?;
    describe(&store, id, &mailbox, uid, &envelope)
}

/// The message as it came from the server, byte for byte.
async fn raw_message(id: AccountId, mailbox: String, uid: u32) -> Result<Vec<u8>, EngineError> {
    let engine = engine()?;
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = crate::login::load(id)?;
    let shared = engine.store.clone();
    engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let raw = conn.raw(&shared, id, &mailbox, uid).await;
            conn.close().await;
            raw
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
        .map_err(EngineError::from)
}

/// The whole message, for View source, Save as .eml and Forward as
/// attachment.
pub async fn message_source(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<Vec<u8>, EngineError> {
    raw_message(AccountId(account_id), mailbox, uid).await
}

/// One header of a message, for View source.
#[derive(Debug, Clone)]
pub struct MessageHeader {
    pub name: String,
    /// Encoded words decoded, folded lines joined.
    pub value: String,
}

/// The headers of a raw message, in order.
#[frb(sync)]
pub fn message_headers(raw: Vec<u8>) -> Vec<MessageHeader> {
    envelope::header_lines(&raw)
        .into_iter()
        .map(|h| MessageHeader {
            name: h.name,
            value: h.value,
        })
        .collect()
}

/// Redirect (Bounce): the message unchanged, with Resent-From,
/// Resent-Date, Resent-To and Resent-Message-ID on top, to the bare
/// addresses of `to`. It goes through the outbox like any message: kept
/// on disk at once, sent once its Undo window (`undo_seconds`) has
/// passed, exactly once, and waiting there while the server can't be
/// reached. It goes from `from_email` when that is one of the account's
/// addresses, from the account's own otherwise; a copy is filed in Sent.
/// Returns its outbox id, to take it back ([super::engine::reopen_outgoing])
/// or wait for it ([super::engine::deliver_outgoing]).
pub async fn redirect_message(
    account_id: i64,
    mailbox: String,
    uid: u32,
    from_email: Option<String>,
    to: Vec<String>,
    undo_seconds: u32,
) -> Result<i64, EngineError> {
    let id = AccountId(account_id);
    let (own, subject) = {
        let store = store()?;
        let own = store.own_addresses(id)?;
        let subject = store
            .message(id, &mailbox, uid)?
            .map(|m| m.subject)
            .unwrap_or_default();
        (own, subject)
    };
    if own.is_empty() {
        return Err(EngineError::new(ErrorKind::Other, "unknown account"));
    }
    // A wrong address says so before the message is fetched.
    envelope::redirect(b"", &subject, from_email.as_deref(), &own, &to, 0)?;
    let raw = raw_message(id, mailbox, uid).await?;
    let now = now_secs();
    let (draft, ready) = envelope::redirect(&raw, &subject, from_email.as_deref(), &own, &to, now)?;
    let send_at = now + i64::from(undo_seconds);
    let out = Outgoing {
        account: id,
        draft,
        ready,
        saved: None,
        send_at: Some(send_at),
        undo: true,
        redirect: true,
    };
    let queued = store()?.queue_outgoing(&out, now)?;
    send_outbox_at(id, send_at)?;
    Ok(queued)
}

/// Mutes the conversation of a message, or unmutes it: new mail in it
/// arrives read and makes no notice; it stays in the inbox.
pub fn set_thread_muted(
    account_id: i64,
    mailbox: String,
    uid: u32,
    muted: bool,
) -> Result<(), EngineError> {
    Ok(store()?.set_thread_muted(AccountId(account_id), &mailbox, uid, muted)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn others_is_the_set_the_app_counts() {
        let e = MessageEnvelope {
            to: Vec::new(),
            cc: Vec::new(),
            bcc_you: false,
            reply_to: vec!["Anna <ANNA@x.it>".into()],
            reply_all_to: vec!["anna@x.it".into(), "Bo <bo@x.it>".into()],
            reply_all_cc: vec!["bo@X.it".into(), "Carla <carla@x.it>".into()],
            list_post: None,
            muted: false,
            reply_all_review: false,
        };
        assert_eq!(others(&e), 2);
        assert_eq!(
            others(&MessageEnvelope {
                bcc_you: true,
                ..e.clone()
            }),
            0
        );
        assert_eq!(
            others(&MessageEnvelope {
                reply_all_review: true,
                ..e
            }),
            0
        );
    }

    #[test]
    fn describes_what_reply_all_does() {
        let mut store = Store::open_in_memory().unwrap();
        let account = piuma_core::Account {
            id: AccountId(0),
            name: "Work".into(),
            email: "me@studio.it".into(),
            sender_name: String::new(),
            color: "#2F8F83".into(),
            kind: piuma_core::AccountKind::Imap {
                imap: piuma_core::Server {
                    host: "imap.x".into(),
                    port: 993,
                    security: piuma_core::Security::Tls,
                },
                smtp: piuma_core::Server {
                    host: "smtp.x".into(),
                    port: 587,
                    security: piuma_core::Security::StartTls,
                },
                username: "me".into(),
            },
        };
        let a = store.add_account(&account).unwrap();
        store.add_alias(a, "alias@studio.it").unwrap();
        let raw = "From: Anna <anna@x.it>\r\nTo: me@studio.it, Carla <carla@x.it>\r\n\
                   Cc: alias@studio.it, dan@x.it\r\nSubject: Plan\r\nMessage-ID: <p@x.it>\r\n\r\nHi";
        let envelope = Envelope::from_raw(raw.as_bytes()).unwrap();
        store
            .upsert_messages(&[piuma_core::MessageSummary {
                account: a,
                mailbox: "INBOX".into(),
                uid: 1,
                from_name: "Anna".into(),
                from_email: "anna@x.it".into(),
                to: "me, Carla".into(),
                subject: "Plan".into(),
                preview: "Hi".into(),
                received_at: 0,
                flags: Default::default(),
                reply: piuma_core::model::ReplyInfo {
                    message_id: "<p@x.it>".into(),
                    envelope: Some(envelope.clone()),
                    ..Default::default()
                },
                list: Default::default(),
            }])
            .unwrap();
        let e = describe(&store, a, "INBOX", 1, &envelope).unwrap();
        assert_eq!(e.reply_to, ["Anna <anna@x.it>"]);
        assert_eq!(e.reply_all_to, ["Anna <anna@x.it>", "Carla <carla@x.it>"]);
        assert_eq!(e.reply_all_cc, ["dan@x.it"]);
        assert!(!e.bcc_you);
        assert_eq!(e.to.len(), 2);
        assert!(e.to[0].you && !e.to[1].you);
        assert!(e.cc[0].you, "aliases are the person too");
        assert_eq!(e.list_post, None);
        assert!(!e.muted);
        store.set_thread_muted(a, "INBOX", 1, true).unwrap();
        assert!(describe(&store, a, "INBOX", 1, &envelope).unwrap().muted);
    }
}
