//! An account's details, as on `FeaturesToApprove`: its name, color and
//! From name, its servers, the sign-in alert, and removing it.

use flutter_rust_bridge::frb;
use piuma_core::{AccountId, AccountKind, Server};

use super::calendars::disconnect_calendar;
use super::engine::{
    engine, reader, stop_watching, store, watch_account, AccountInfo, ConnectionSecurity,
    EngineError, ErrorKind, OutgoingServer,
};
use crate::credentials;
use piuma_core::remote;

/// Where an account reads and sends its mail.
#[derive(Debug, Clone)]
pub struct AccountServers {
    /// Incoming (IMAP); for a JMAP account, its session's host.
    pub imap: OutgoingServer,
    /// Outgoing (SMTP); empty for a JMAP account.
    pub smtp: OutgoingServer,
    pub username: String,
    /// The JMAP session, for a JMAP account.
    pub jmap_url: Option<String>,
}

fn server(s: &Server) -> OutgoingServer {
    OutgoingServer {
        host: s.host.clone(),
        port: s.port,
        security: s.security.into(),
    }
}

fn account(id: i64) -> Result<piuma_core::Account, EngineError> {
    store()?
        .account(AccountId(id))?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "no such account"))
}

#[frb(sync)]
pub fn account_servers(account_id: i64) -> Result<AccountServers, EngineError> {
    Ok(match account(account_id)?.kind {
        AccountKind::Imap {
            imap,
            smtp,
            username,
        } => AccountServers {
            imap: server(&imap),
            smtp: server(&smtp),
            username,
            jmap_url: None,
        },
        AccountKind::Jmap { session_url, .. } => {
            let host = session_url
                .split("://")
                .nth(1)
                .and_then(|r| r.split('/').next())
                .unwrap_or_default()
                .to_owned();
            let blank = |host: String| OutgoingServer {
                host,
                port: 443,
                security: ConnectionSecurity::Tls,
            };
            AccountServers {
                imap: blank(host),
                smtp: blank(String::new()),
                username: String::new(),
                jmap_url: Some(session_url),
            }
        }
    })
}

/// Changes an account's name, From name and color.
#[frb(sync)]
pub fn update_account(
    account_id: i64,
    name: String,
    sender_name: String,
    color: String,
) -> Result<AccountInfo, EngineError> {
    let mut a = account(account_id)?;
    a.name = name.trim().to_owned();
    a.sender_name = sender_name.trim().to_owned();
    a.color = color;
    store()?.update_account(&a)?;
    Ok(AccountInfo::from(&a))
}

/// Checks new servers with the account's password, keeps them, and
/// follows the account through them from now on.
pub async fn set_account_servers(
    account_id: i64,
    servers: AccountServers,
) -> Result<(), EngineError> {
    let engine = engine()?;
    let mut a = account(account_id)?;
    let AccountKind::Imap { .. } = a.kind else {
        return Err(EngineError::new(ErrorKind::Other, "not an IMAP account"));
    };
    let into = |s: OutgoingServer| Server {
        host: s.host.trim().to_owned(),
        port: s.port,
        security: s.security.into(),
    };
    a.kind = AccountKind::Imap {
        imap: into(servers.imap),
        smtp: into(servers.smtp),
        username: servers.username.trim().to_owned(),
    };
    let password = credentials::load(a.id)?;
    let checked = a.clone();
    engine
        .runtime
        .spawn(async move { remote::check_login(&checked, &password).await })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    store()?.update_account(&a)?;
    stop_watching(a.id);
    watch_account(a)
}

/// Removes an account from this device: its mail here, its password and
/// the calendars that used it. Its mail stays on the server.
#[frb(sync)]
pub fn remove_account(account_id: i64) -> Result<(), EngineError> {
    let id = AccountId(account_id);
    stop_watching(id);
    crate::background::forget(id);
    let sources: Vec<i64> = store()?
        .calendar_sources()?
        .into_iter()
        .filter(|s| s.account == Some(id))
        .map(|s| s.id)
        .collect();
    for source in sources {
        disconnect_calendar(source)?;
    }
    let store = store()?;
    store.remove_account(id)?;
    // An account added later may get the same id.
    store.set_setting(&alert_key(account_id), "")?;
    store.set_setting(&format!("sign_in.told.{account_id}"), "")?;
    drop(store);
    credentials::forget(id);
    Ok(())
}

fn alert_key(account_id: i64) -> String {
    format!("account.{account_id}.sign_in_alert")
}

/// "Tell me when it can't sign in": on unless turned off.
#[frb(sync)]
pub fn sign_in_alert(account_id: i64) -> Result<bool, EngineError> {
    Ok(reader()?.setting(&alert_key(account_id))?.as_deref() != Some("off"))
}

#[frb(sync)]
pub fn set_sign_in_alert(account_id: i64, enabled: bool) -> Result<(), EngineError> {
    store()?.set_setting(&alert_key(account_id), if enabled { "on" } else { "off" })?;
    Ok(())
}
