//! Groups and aliases, as on `Groups`: groups bring together addresses of
//! different accounts and domains, each with its color, signature and
//! sending address; aliases are other addresses an account sends from.

use flutter_rust_bridge::frb;
use piuma_core::groups::{self, AddressGroup, GroupAddress, Within};
use piuma_core::model::{Folder, Section};
use piuma_core::AccountId;

use super::engine::{reader, store, switch, EngineError, ErrorKind};

const REPLY_AS_WRITTEN: &str = "groups.reply_as_written";

/// One group, as Settings › Groups shows it.
#[derive(Debug, Clone)]
pub struct MailGroup {
    /// 0 for one not kept yet.
    pub id: i64,
    pub name: String,
    /// "#RRGGBB", one of the account colors.
    pub color: String,
    /// Its default signature; None for none.
    pub signature_id: Option<i64>,
    /// Where new emails go from; empty for the first address.
    pub send_from: String,
    /// Gets its own item in the sidebar.
    pub separate_inbox: bool,
    pub notify: bool,
    pub addresses: Vec<MailGroupAddress>,
}

#[derive(Debug, Clone)]
pub struct MailGroupAddress {
    pub account_id: i64,
    pub email: String,
}

impl From<AddressGroup> for MailGroup {
    fn from(g: AddressGroup) -> Self {
        MailGroup {
            id: g.id,
            name: g.name,
            color: g.color,
            signature_id: g.signature,
            send_from: g.send_from,
            separate_inbox: g.separate_inbox,
            notify: g.notify,
            addresses: g
                .addresses
                .into_iter()
                .map(|a| MailGroupAddress {
                    account_id: a.account.0,
                    email: a.email,
                })
                .collect(),
        }
    }
}

/// Every group, in order.
#[frb(sync)]
pub fn groups() -> Result<Vec<MailGroup>, EngineError> {
    Ok(reader()?
        .address_groups()?
        .into_iter()
        .map(MailGroup::from)
        .collect())
}

/// What is unread in a group's inbox, and in each of its addresses, in
/// the group's order: for the sidebar.
#[derive(Debug, Clone)]
pub struct GroupUnread {
    pub group_id: i64,
    pub unread: u32,
    pub addresses: Vec<u32>,
}

pub fn group_unread() -> Result<Vec<GroupUnread>, EngineError> {
    let store = store()?;
    let unread = |w| store.unread_count(Folder::Inbox, w, Section::All);
    store
        .address_groups()?
        .into_iter()
        .map(|g| {
            Ok(GroupUnread {
                group_id: g.id,
                unread: unread(Within::Group(g.id))?,
                addresses: g
                    .addresses
                    .iter()
                    .map(|a| {
                        unread(Within::Address {
                            group: g.id,
                            email: a.email.clone(),
                        })
                    })
                    .collect::<Result<_, _>>()?,
            })
        })
        .collect()
}

/// Keeps a group, a new one when its id is 0; an address taken from
/// another group leaves that one. Returns its id.
#[frb(sync)]
pub fn save_group(group: MailGroup) -> Result<i64, EngineError> {
    Ok(store()?.save_address_group(&AddressGroup {
        id: group.id,
        name: group.name.trim().to_owned(),
        color: group.color,
        signature: group.signature_id,
        send_from: group.send_from,
        separate_inbox: group.separate_inbox,
        notify: group.notify,
        addresses: group
            .addresses
            .into_iter()
            .map(|a| GroupAddress {
                account: AccountId(a.account_id),
                email: a.email,
            })
            .collect(),
    })?)
}

#[frb(sync)]
pub fn delete_group(id: i64) -> Result<(), EngineError> {
    Ok(store()?.delete_address_group(id)?)
}

/// The other addresses an account sends from.
#[frb(sync)]
pub fn aliases(account_id: i64) -> Result<Vec<String>, EngineError> {
    Ok(reader()?.aliases(AccountId(account_id))?)
}

/// Addresses the account's Sent mail went from that aren't aliases yet.
#[frb(sync)]
pub fn alias_suggestions(account_id: i64) -> Result<Vec<String>, EngineError> {
    Ok(reader()?.alias_suggestions(AccountId(account_id))?)
}

/// Adds an alias; an address that isn't one is refused.
#[frb(sync)]
pub fn add_alias(account_id: i64, email: String) -> Result<(), EngineError> {
    if !groups::valid_address(&email) {
        return Err(EngineError::new(ErrorKind::Other, "not an email address"));
    }
    Ok(store()?.add_alias(AccountId(account_id), &email)?)
}

#[frb(sync)]
pub fn remove_alias(account_id: i64, email: String) -> Result<(), EngineError> {
    Ok(store()?.remove_alias(AccountId(account_id), &email)?)
}

/// "Always reply from the address they wrote to": on unless turned off.
#[frb(sync)]
pub fn reply_as_written() -> Result<bool, EngineError> {
    switch(&*reader()?, REPLY_AS_WRITTEN)
}

#[frb(sync)]
pub fn set_reply_as_written(on: bool) -> Result<(), EngineError> {
    Ok(store()?.set_setting(REPLY_AS_WRITTEN, if on { "true" } else { "false" })?)
}

/// The address a reply to this message goes from: the one of the
/// account's own addresses it was written to, when that isn't the account's
/// own and "Always reply from the address they wrote to" is on.
#[frb(sync)]
pub fn reply_from(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<Option<String>, EngineError> {
    if !switch(&*reader()?, REPLY_AS_WRITTEN)? {
        return Ok(None);
    }
    written_to(account_id, mailbox, uid)
}

/// The alias this message was written to, if it went to one of the
/// account's aliases rather than its own address.
#[frb(sync)]
pub fn written_to(
    account_id: i64,
    mailbox: String,
    uid: u32,
) -> Result<Option<String>, EngineError> {
    let store = reader()?;
    let account = AccountId(account_id);
    let own = store.own_addresses(account)?;
    let recipients = store.recipients(account, &mailbox, uid)?;
    Ok(groups::written_to(&own, &recipients)
        .filter(|a| Some(*a) != own.first().map(String::as_str))
        .map(str::to_owned))
}
