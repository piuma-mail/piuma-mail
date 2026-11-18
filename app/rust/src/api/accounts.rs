//! An account's details, as on `FeaturesToApprove`: its name, color and
//! From name, its servers, the sign-in alert, and removing it.

use flutter_rust_bridge::frb;
use piuma_core::{AccountId, AccountKind, Server};

use super::calendars::disconnect_calendar;
use super::engine::{
    bulk_reader, engine, pins_of, reader, stop_watching, store, watch_account, AccountInfo,
    ConnectionSecurity, EngineError, ErrorKind, OutgoingServer, TrustedCertificate,
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
/// follows the account through them from now on. `trusted` are
/// certificates the person chose to trust for the new servers, after a
/// [ErrorKind::Certificate]: kept only once the check went through.
///
/// An account that signs in with a provider's page keeps that provider's
/// servers, over TLS: its token never goes anywhere else.
pub async fn set_account_servers(
    account_id: i64,
    servers: AccountServers,
    trusted: Vec<TrustedCertificate>,
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
    let (imap, smtp) = (into(servers.imap), into(servers.smtp));
    let login = crate::login::load(a.id)?;
    if let Some(session) = login.session() {
        let provider = session.provider();
        for server in [&imap, &smtp] {
            if !provider.serves(&server.host) || server.security == piuma_core::Security::None {
                return Err(EngineError::new(
                    ErrorKind::OAuthServers,
                    format!(
                        "an account that signs in with {} keeps its servers, over TLS",
                        provider.name
                    ),
                ));
            }
        }
    }
    let hosts = [imap.host.clone(), smtp.host.clone()];
    let new_pins = crate::login::for_hosts(pins_of(&trusted), &hosts);
    let pins = crate::login::with_new(a.id, &hosts, &new_pins);
    a.kind = AccountKind::Imap {
        imap,
        smtp,
        username: servers.username.trim().to_owned(),
    };
    let login = login.with_pins(pins);
    let checked = a.clone();
    engine
        .runtime
        .spawn(async move { remote::check_login(&checked, &login).await })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))??;
    // Only now, for servers the account uses.
    crate::login::trust_all(a.id, &new_pins)?;
    store()?.update_account(&a)?;
    stop_watching(a.id);
    watch_account(a)
}

/// A message written in an account that hasn't gone yet: removing the
/// account waits until each is sent, saved on the server or deleted.
#[derive(Debug, Clone)]
pub struct UnsentMessage {
    /// The outbox message's id ([super::engine::retry_outgoing],
    /// [super::engine::delete_outgoing]), or the waiting draft's
    /// ([save_waiting_drafts_now], [delete_waiting_draft]).
    pub id: i64,
    /// A draft waiting on this device to be saved on the server, rather
    /// than mail in the outbox.
    pub draft: bool,
    pub to: Vec<String>,
    pub subject: String,
    /// The server refused it (outbox only).
    pub refused: bool,
    /// On its way now (outbox only): it can't be deleted.
    pub sending: bool,
    /// When it was queued or saved, in Unix seconds.
    pub at: i64,
}

/// What removing an account waits on: its outbox mail that hasn't gone
/// (not the mail the server took, nor what may have gone) and its drafts
/// waiting on this device, outbox first.
pub fn account_unsent(account_id: i64) -> Result<Vec<UnsentMessage>, EngineError> {
    Ok(bulk_reader()?
        .unsent_mail(AccountId(account_id))?
        .into_iter()
        .map(|u| UnsentMessage {
            id: u.id,
            draft: u.draft,
            to: u.to,
            subject: u.subject,
            refused: u.state == Some(piuma_core::outbox::State::Refused),
            sending: u.state == Some(piuma_core::outbox::State::Sending),
            at: u.at,
        })
        .collect())
}

/// Tries now to save an account's drafts waiting on this device on its
/// server; [super::engine::SyncEventKind::Synced] follows when they went.
pub fn save_waiting_drafts_now(account_id: i64) -> Result<(), EngineError> {
    let account = account(account_id)?;
    let password = crate::login::load(account.id)?;
    super::engine::save_waiting_drafts(account, password);
    Ok(())
}

/// Deletes a draft waiting on this device without saving it on the
/// server; a copy saved there before stays.
pub fn delete_waiting_draft(id: i64) -> Result<(), EngineError> {
    store()?.drop_waiting_draft(id)?;
    Ok(())
}

/// Removes an account from this device: its mail here, its password and
/// the calendars that used it. Its mail stays on the server. The account
/// leaves every list at once; its messages are removed in the background,
/// a few thousand at a time (and the removal goes on at the next start if
/// the app stops first), so nothing waits on it. Refused
/// ([ErrorKind::Unsent]) while mail written in it hasn't gone
/// ([account_unsent]): nothing unsent is ever removed with it.
pub fn remove_account(account_id: i64) -> Result<(), EngineError> {
    let id = AccountId(account_id);
    let removed = account(account_id)?;
    // First, in one write that checks for unsent mail: nothing is undone
    // (watching, calendars, passwords) when it is refused.
    store()?.start_removing_account(id)?;
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
    // At once, though the account's row goes only with the last step of
    // the removal (which removes every setting that names it).
    store.set_setting(&alert_key(account_id), "")?;
    store.set_setting(&format!("sign_in.told.{account_id}"), "")?;
    store.set_setting(&crate::login::oauth_key(account_id), "")?;
    drop(store);
    crate::login::untrust(id, &crate::login::hosts_of(&removed))?;
    credentials::forget(id);
    crate::login::forget_session(id);
    // The refresh token is not revoked: Google's revocation removes the
    // whole grant of the app's project for the person ("Revocation removes
    // all OAuth 2.0 scopes previously granted to a project, invalidating
    // any issued access or refresh tokens", developers.google.com/identity/
    // protocols/oauth2/native-app#tokenrevoke), which would sign out every
    // other device of theirs, and Google documents no way to revoke only
    // this device's token. Forgetting it here is enough: it never leaves
    // the keychain, and the person can remove the app's access from their
    // Google Account. Microsoft's run out on their own.
    super::engine::kick_maintenance();
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
