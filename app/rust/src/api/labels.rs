//! Labels (`LabelsToApprove`): colored words on emails, shared across
//! accounts and kept on the server as keywords.

use piuma_core::label::Label;
use piuma_core::remote::Remote;
use piuma_core::AccountId;

use crate::api::engine::{
    engine, in_conversation, inbox_row, signed_in, store, with_files, EngineError, InboxRow,
    MessageRef,
};

/// A label, with how many emails carry it.
#[derive(Debug, Clone)]
pub struct LabelInfo {
    pub id: i64,
    pub name: String,
    /// amber, teal, coral, blue or violet.
    pub color: String,
    pub keyword: String,
    pub count: u32,
}

fn info(l: Label, count: usize) -> LabelInfo {
    LabelInfo {
        id: l.id,
        name: l.name,
        color: l.color,
        keyword: l.keyword,
        count: count as u32,
    }
}

/// Every label, in order, with its count.
pub fn labels() -> Result<Vec<LabelInfo>, EngineError> {
    let store = store()?;
    let counts = store.label_counts()?;
    Ok(store
        .labels()?
        .into_iter()
        .map(|l| {
            let count = counts
                .iter()
                .find(|(id, _)| *id == l.id)
                .map_or(0, |(_, n)| *n);
            info(l, count)
        })
        .collect())
}

/// Makes a label, or finds the one with that name. An empty color takes
/// the next free one.
pub fn add_label(name: String, color: String) -> Result<LabelInfo, EngineError> {
    Ok(info(store()?.add_label(&name, &color)?, 0))
}

pub fn update_label(id: i64, name: String, color: String) -> Result<(), EngineError> {
    Ok(store()?.update_label(id, &name, &color)?)
}

/// Deletes a label: off every email, here and on the servers.
pub async fn remove_label(id: i64) -> Result<(), EngineError> {
    let accounts: Vec<i64> = {
        let store = store()?;
        store.remove_label(id)?;
        store.accounts()?.into_iter().map(|a| a.id.0).collect()
    };
    send(accounts).await;
    Ok(())
}

/// Puts a label on emails or takes it off, here at once and then on
/// their servers; offline, it waits for the next sync.
pub async fn set_label(
    messages: Vec<MessageRef>,
    keyword: String,
    add: bool,
) -> Result<(), EngineError> {
    {
        let store = store()?;
        for m in &messages {
            store.label_message(AccountId(m.account_id), &m.mailbox, m.uid, &keyword, add)?;
        }
    }
    let mut accounts: Vec<i64> = messages.iter().map(|m| m.account_id).collect();
    accounts.sort_unstable();
    accounts.dedup();
    send(accounts).await;
    Ok(())
}

/// Every email with a label, from every account and folder but the
/// trash, newest first.
pub fn labelled(keyword: String) -> Result<Vec<InboxRow>, EngineError> {
    let store = store()?;
    store
        .labelled_messages(&keyword)?
        .into_iter()
        .map(|m| {
            let row = inbox_row(&store, m);
            in_conversation(&store, with_files(&store, row))
        })
        .collect()
}

/// Whether the account's server keeps no keywords, so its labels stay on
/// this device.
#[flutter_rust_bridge::frb(sync)]
pub fn labels_local(account_id: i64) -> Result<bool, EngineError> {
    Ok(store()?.labels_local(AccountId(account_id))?)
}

/// Sends what waits for each account; what can't go now goes with the
/// next sync.
async fn send(accounts: Vec<i64>) {
    let Ok(engine) = engine() else { return };
    for account_id in accounts {
        let id = AccountId(account_id);
        let Ok((account, password)) = signed_in(id) else {
            continue;
        };
        let shared = engine.store.clone();
        engine
            .runtime
            .spawn(async move {
                if let Ok(mut conn) = Remote::open(&account, &password).await {
                    conn.send_pending(&shared, id).await.ok();
                    conn.close().await;
                }
            })
            .await
            .ok();
    }
}
