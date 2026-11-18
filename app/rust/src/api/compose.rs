//! What compose needs beside the message itself: pictures made ready to
//! go inside the text (and read from the clipboard on the desktop), the
//! writing settings, contact groups, and read receipts asked for by mail
//! being read.

use flutter_rust_bridge::frb;
use piuma_core::compose_image::{self, PrepareError};
use piuma_core::contact_groups::ContactGroup;
use piuma_core::mdn;
use piuma_core::AccountId;

use super::engine::{now_secs, reader, store, EngineError, ErrorKind};

/// A picture made ready to go inside a message.
#[derive(Debug, Clone)]
pub struct PreparedImage {
    pub mime: String,
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

impl From<compose_image::Prepared> for PreparedImage {
    fn from(p: compose_image::Prepared) -> Self {
        PreparedImage {
            mime: p.mime,
            data: p.data,
            width: p.width,
            height: p.height,
        }
    }
}

fn prepare_error(e: PrepareError) -> EngineError {
    match e {
        PrepareError::NotAnImage => EngineError::new(ErrorKind::NotAnImage, e.to_string()),
        PrepareError::TooBig => EngineError::new(ErrorKind::TooBig, e.to_string()),
    }
}

/// Makes a picture ready to go inside a message: turned the right way,
/// at most 1600 pixels on its longest side and 2 MB, without the
/// camera's metadata. [ErrorKind::NotAnImage] for anything else.
pub fn prepare_inline_image(data: Vec<u8>) -> Result<PreparedImage, EngineError> {
    compose_image::prepare(&data)
        .map(PreparedImage::from)
        .map_err(prepare_error)
}

/// The picture on the system clipboard, made ready as
/// [prepare_inline_image] makes one; None when it holds no picture, and
/// always on phones (their keyboards hand pictures to the text field).
pub fn clipboard_image() -> Result<Option<PreparedImage>, EngineError> {
    crate::clipboard::image()
        .map(|picture| compose_image::prepare_picture(picture).map(PreparedImage::from))
        .transpose()
        .map_err(prepare_error)
}

/// Settings › Writing › Replies, and the plain-text default of each
/// account.
#[derive(Debug, Clone)]
pub struct ComposeSettings {
    /// Replies are written under the quoted message instead of above.
    pub reply_below: bool,
    /// With words selected in the reader, a reply quotes only them.
    pub quote_selection: bool,
    /// The accounts (by address, lowercase) whose new messages start as
    /// plain text.
    pub plain_text_accounts: Vec<String>,
}

const REPLY_BELOW: &str = "compose.reply_below";
const QUOTE_SELECTION: &str = "compose.quote_selection";
const PLAIN_PREFIX: &str = "compose.plain.";

/// Settings › Writing › Replies. Kept by account address, so they mean
/// the same on every device.
#[frb(sync)]
pub fn compose_settings() -> Result<ComposeSettings, EngineError> {
    let store = reader()?;
    let on = |key: &str, default: bool| -> Result<bool, EngineError> {
        Ok(store.setting(key)?.map(|v| v == "true").unwrap_or(default))
    };
    let mut plain = Vec::new();
    for account in store.accounts()? {
        let email = account.email.to_lowercase();
        if on(&format!("{PLAIN_PREFIX}{email}"), false)? {
            plain.push(email);
        }
    }
    Ok(ComposeSettings {
        reply_below: on(REPLY_BELOW, false)?,
        quote_selection: on(QUOTE_SELECTION, true)?,
        plain_text_accounts: plain,
    })
}

pub fn set_compose_settings(settings: ComposeSettings) -> Result<(), EngineError> {
    let store = store()?;
    let flag = |on: bool| if on { "true" } else { "false" };
    store.set_setting(REPLY_BELOW, flag(settings.reply_below))?;
    store.set_setting(QUOTE_SELECTION, flag(settings.quote_selection))?;
    for account in store.accounts()? {
        let email = account.email.to_lowercase();
        let plain = settings
            .plain_text_accounts
            .iter()
            .any(|a| a.eq_ignore_ascii_case(&email));
        store.set_setting(&format!("{PLAIN_PREFIX}{email}"), flag(plain))?;
    }
    Ok(())
}

/// A contact group: a name for a list of addresses.
#[derive(Debug, Clone)]
pub struct ContactGroupInfo {
    /// Empty for one not kept yet.
    pub uid: String,
    pub name: String,
    pub addresses: Vec<String>,
}

/// Every contact group, by name.
#[frb(sync)]
pub fn contact_groups() -> Result<Vec<ContactGroupInfo>, EngineError> {
    Ok(reader()?
        .contact_groups()?
        .into_iter()
        .map(|g| ContactGroupInfo {
            uid: g.uid,
            name: g.name,
            addresses: g.addresses,
        })
        .collect())
}

/// Keeps a contact group, a new one when its uid is empty; addresses
/// that aren't any are left out. Returns its uid.
pub fn save_contact_group(group: ContactGroupInfo) -> Result<String, EngineError> {
    Ok(store()?.save_contact_group(
        &ContactGroup {
            uid: group.uid,
            name: group.name,
            addresses: group.addresses,
        },
        now_secs(),
    )?)
}

pub fn delete_contact_group(uid: String) -> Result<(), EngineError> {
    Ok(store()?.delete_contact_group(&uid, now_secs())?)
}

/// What a message being read asks of its reader.
#[derive(Debug, Clone)]
pub struct MessageAsks {
    /// Where a read receipt would go, when the reader should offer one.
    pub read_receipt_to: Option<String>,
    /// The sender marked it important.
    pub high_priority: bool,
}

/// What a kept message asks of its reader; nothing until its body is
/// kept.
#[frb(sync)]
pub fn message_asks(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<MessageAsks, EngineError> {
    let store = reader()?;
    let account = AccountId(account_id);
    Ok(MessageAsks {
        read_receipt_to: store.receipt_offered(account, &mailbox, uid)?,
        high_priority: store.message_asks(account, &mailbox, uid)?.0.high_priority,
    })
}

/// The person's answer to a read receipt asked for: [send] it now, or
/// not; with [never], the account never offers one to that sender
/// again. Only an offered receipt is sent, never one on its own. It goes
/// through the outbox like any message: returns true while it waits
/// there, offline or after a failed try (the Outbox shows why, and
/// deleting it there takes the answer back). Not sending takes back one
/// still waiting there.
pub async fn answer_read_receipt(
    account_id: i64,
    mailbox: String,
    uid: u32,
    send: bool,
    never: bool,
) -> Result<bool, EngineError> {
    let id = AccountId(account_id);
    if !send {
        store()?.answer_receipt(id, &mailbox, uid, mdn::Answer::Declined, never)?;
        return Ok(false);
    }
    let Some(to) = reader()?.receipt_offered(id, &mailbox, uid)? else {
        return Err(EngineError::new(ErrorKind::Other, "no receipt to send"));
    };
    let account = store()?
        .account(id)?
        .ok_or(EngineError::new(ErrorKind::Other, "unknown account"))?;
    let Some((original, written_to)) = reader()?.receipt_original(id, &mailbox, uid)? else {
        return Err(EngineError::new(ErrorKind::Other, "message gone"));
    };
    let email = written_to.unwrap_or_else(|| account.email.clone());
    let name = account.sender_name.trim();
    let from = lettre_mailbox(name, &email)?;
    let ready = mdn::report(&from, &to, &original)?;
    let message_id = ready.message_id.clone();
    // What the outbox lists and Edit would open: the receipt's words.
    let draft = piuma_core::smtp::Draft {
        from_name: name.to_owned(),
        from_email: email,
        to: vec![to],
        subject: format!("Read: {}", original.subject.trim()),
        body: mdn::summary(&original),
        ..Default::default()
    };
    let out = piuma_core::outbox::Outgoing {
        account: id,
        draft,
        ready,
        saved: None,
        send_at: None,
        undo: false,
        redirect: false,
    };
    let queued = store()?.queue_outgoing(&out, now_secs())?;
    // Answered once it is in the outbox: it goes from there, whatever this
    // try does.
    store()?.receipt_queued(id, &mailbox, uid, &message_id)?;
    Ok(receipt_waits(
        super::engine::deliver_outgoing(queued)
            .await
            .map(|d| d.kind),
    ))
}

/// Whether a receipt put in the outbox still waits there after its first
/// try. Every failure leaves it there, refused or waiting, with the reason
/// the Outbox shows: the band never asks again for a receipt already in
/// the outbox, which would go twice.
fn receipt_waits(delivery: Result<super::engine::DeliveryKind, EngineError>) -> bool {
    !matches!(delivery, Ok(super::engine::DeliveryKind::Sent))
}

fn lettre_mailbox(name: &str, email: &str) -> Result<piuma_core::mdn::Mailbox, EngineError> {
    piuma_core::mdn::mailbox(name, email).map_err(EngineError::from)
}

/// The language of text being written ("it", "de"…), for the spell
/// checker; None when there are too few words to tell.
#[frb(sync)]
pub fn text_language(text: String) -> Option<String> {
    piuma_core::language::detect(&text).map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::super::engine::DeliveryKind as K;
    use super::*;

    #[test]
    fn a_receipt_waits_in_the_outbox_after_any_failed_try() {
        assert!(!receipt_waits(Ok(K::Sent)));
        for kind in [
            K::Waiting,
            K::WrongPassword,
            K::Refused,
            K::Insecure,
            K::MaybeSent,
            K::Gone,
        ] {
            assert!(receipt_waits(Ok(kind)), "{kind:?}");
        }
        assert!(receipt_waits(Err(EngineError::new(
            ErrorKind::Other,
            "engine not open"
        ))));
    }
}
