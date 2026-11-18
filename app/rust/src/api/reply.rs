//! Who a message went to and who an answer goes to (Reply all, Reply to
//! list), the raw message (View source, Save as .eml, Forward as
//! attachment), Redirect, and muting a conversation.

use flutter_rust_bridge::frb;
use piuma_core::envelope::{self, Address, Envelope, ReplyMode};
use piuma_core::remote::{self, Remote};
use piuma_core::smtp::Ready;
use piuma_core::{AccountId, Store};

use super::engine::{engine, now_secs, reader, store, EngineError, ErrorKind};
use crate::credentials;

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
        you: own.iter().any(|o| o.eq_ignore_ascii_case(a.email.trim())),
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
    })
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
    let kept = reader()?.envelope(id, &mailbox, uid)?;
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
    let store = reader()?;
    describe(&store, id, &mailbox, uid, &envelope)
}

/// The message as it came from the server, byte for byte.
async fn raw_message(id: AccountId, mailbox: String, uid: u32) -> Result<Vec<u8>, EngineError> {
    let engine = engine()?;
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = credentials::load(id)?;
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

/// Redirect (Bounce): sends the message unchanged to `to`, with
/// Resent-From, Resent-Date, Resent-To and Resent-Message-ID on top. It
/// goes from the account's address (or `from_email`, one of its aliases)
/// and a copy is filed in Sent, as any message sent.
pub async fn redirect_message(
    account_id: i64,
    mailbox: String,
    uid: u32,
    from_email: Option<String>,
    to: Vec<String>,
) -> Result<(), EngineError> {
    let id = AccountId(account_id);
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let recipients = recipients_of(&to)?;
    let raw = raw_message(id, mailbox, uid).await?;
    let from = from_email
        .filter(|f| !f.trim().is_empty())
        .unwrap_or_else(|| account.email.clone());
    let message_id = envelope::new_message_id(&from);
    let ready = Ready {
        message_id: message_id.clone(),
        from: from.clone(),
        recipients,
        raw: envelope::resend(&raw, &from, &to, now_secs(), &message_id),
    };
    let password = credentials::load(id)?;
    engine()?
        .runtime
        .spawn(async move { remote::send_ready(&account, &password, &ready).await })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    Ok(())
}

/// The bare addresses of `to` (`a@b.c` or `Name <a@b.c>`), each checked.
fn recipients_of(to: &[String]) -> Result<Vec<String>, EngineError> {
    if to.iter().all(|t| t.trim().is_empty()) {
        return Err(EngineError::new(ErrorKind::NoRecipients, ""));
    }
    to.iter()
        .filter(|t| !t.trim().is_empty())
        .map(|t| {
            let t = t.trim();
            let bare = match (t.rfind('<'), t.rfind('>')) {
                (Some(a), Some(b)) if a < b => &t[a + 1..b],
                _ => t,
            };
            let bare = bare.trim();
            if piuma_core::groups::valid_address(bare) {
                Ok(bare.to_owned())
            } else {
                Err(EngineError::new(ErrorKind::BadAddress, t))
            }
        })
        .collect()
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
    fn redirect_recipients_are_bare_and_checked() {
        assert_eq!(
            recipients_of(&["Carla <carla@x.it>".into(), " dan@x.it ".into()]).unwrap(),
            ["carla@x.it", "dan@x.it"]
        );
        assert_eq!(
            recipients_of(&["".into()]).unwrap_err().kind,
            ErrorKind::NoRecipients
        );
        assert_eq!(
            recipients_of(&["not an address".into()]).unwrap_err().kind,
            ErrorKind::BadAddress
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
