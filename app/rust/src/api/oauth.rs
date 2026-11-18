//! Signing in with a provider's own page (OAuth 2.0, `piuma_core::oauth`):
//! Microsoft 365 and Outlook.com, Gmail.
//!
//! The app asks for the page with [`begin_oauth`] and opens it in the
//! system browser (Custom Tabs on Android). On the desktop the browser
//! comes back to a one-time listener on `127.0.0.1`; on Android to the
//! app's own scheme, which `MainActivity` hands over with
//! [`deliver_oauth_redirect`]. [`add_oauth_account`] or
//! [`sign_in_again_oauth`] then waits for it, checks the answer's
//! `state`, trades the code for tokens and signs in to the mail servers.
//! One sign-in at a time; a new one cancels the one before.

use std::sync::{Arc, Mutex};

use flutter_rust_bridge::frb;
use piuma_core::oauth::{self, Client, FlowError, Loopback, Request, Stored, TokenError};
use piuma_core::{remote, Account, AccountId, AccountKind, Login};
use tokio::sync::{mpsc, Notify};

use super::engine::{
    engine, reader, stop_watching, store, watch_account, AccountInfo, EngineError, ErrorKind,
};
use super::sync::KeptSecret;
use crate::credentials;

/// A provider that signs in with its own page.
#[derive(Debug, Clone)]
pub struct OAuthProvider {
    /// `microsoft`, `google`.
    pub id: String,
    /// "Microsoft", "Google".
    pub name: String,
    /// This build has a client for it: signing in works out of the box.
    pub built_in: bool,
    /// The provider still takes app passwords, the way in without a
    /// client.
    pub app_passwords: bool,
    /// The provider has tenants (Microsoft): a client of the person's own
    /// may name one.
    pub has_tenant: bool,
    /// A client of the person's own works on this device. Not Google's on
    /// Android: its redirect scheme comes from the client ID, and the app
    /// only answers the one it was built with.
    pub own_client: bool,
    /// Its servers, for the summary.
    pub imap_host: String,
    pub smtp_host: String,
}

/// A registration of the person's own, from the account's advanced
/// settings, in place of the one this build has.
#[derive(Debug, Clone)]
pub struct OAuthClient {
    pub client_id: String,
    /// Google desktop clients only; not a secret for an installed app.
    pub client_secret: Option<String>,
    /// Microsoft only; `common` when empty.
    pub tenant: Option<String>,
}

#[frb(sync)]
pub fn oauth_providers() -> Vec<OAuthProvider> {
    oauth::providers()
        .iter()
        .map(|p| OAuthProvider {
            id: p.id.clone(),
            name: p.name.clone(),
            built_in: oauth::built_in_client(&p.id).is_some(),
            app_passwords: p.app_passwords,
            has_tenant: p.tenant.is_some(),
            own_client: p.takes_own_client(),
            imap_host: p.imap().host,
            smtp_host: p.smtp().host,
        })
        .collect()
}

/// The provider whose servers these are, for accounts set up with a
/// password before (a Gmail account with an app password).
#[frb(sync)]
pub fn oauth_provider_for_server(imap_host: String) -> Option<String> {
    oauth::for_server(&imap_host).map(|p| p.id.clone())
}

/// The provider an account signs in with, if it signs in with OAuth.
#[frb(sync)]
pub fn account_oauth(account_id: i64) -> Result<Option<String>, EngineError> {
    Ok(reader()?
        .setting(&crate::login::oauth_key(account_id))?
        .filter(|p| !p.is_empty()))
}

/// How the browser comes back.
enum WayBack {
    Loopback(Loopback),
    App(mpsc::UnboundedReceiver<String>),
}

struct Pending {
    request: Request,
    way_back: WayBack,
    /// The address the person signs in as.
    email: String,
}

static PENDING: Mutex<Option<Pending>> = Mutex::new(None);
/// Android: where [`deliver_oauth_redirect`] sends the address.
static REDIRECT: Mutex<Option<mpsc::UnboundedSender<String>>> = Mutex::new(None);
/// Ends the sign-in being waited for.
static CANCEL: Mutex<Option<Arc<Notify>>> = Mutex::new(None);

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

fn flow_error(e: FlowError) -> EngineError {
    let kind = match e {
        FlowError::Cancelled | FlowError::Timeout => ErrorKind::SignInCancelled,
        FlowError::Io(_) => ErrorKind::Other,
        _ => ErrorKind::SignInDenied,
    };
    EngineError::new(kind, e.to_string())
}

fn token_error(e: TokenError) -> EngineError {
    match e {
        TokenError::Rejected(why) => EngineError::new(ErrorKind::SignInDenied, why),
        TokenError::Offline(why) => EngineError::new(ErrorKind::Unreachable, why),
    }
}

fn client_of(provider: &oauth::Provider, own: Option<OAuthClient>) -> Result<Client, EngineError> {
    match own.filter(|c| !c.client_id.trim().is_empty()) {
        Some(_) if !provider.takes_own_client() => Err(EngineError::new(
            ErrorKind::SignInUnavailable,
            format!(
                "a {} client of your own can't sign in on this device",
                provider.name
            ),
        )),
        Some(c) => Ok(Client {
            client_id: c.client_id.trim().to_owned(),
            client_secret: c
                .client_secret
                .map(|s| s.trim().to_owned())
                .filter(|s| !s.is_empty()),
            tenant: c
                .tenant
                .map(|t| t.trim().to_owned())
                .filter(|t| !t.is_empty()),
        }),
        None => oauth::built_in_client(&provider.id).ok_or_else(|| {
            EngineError::new(
                ErrorKind::SignInUnavailable,
                format!("this build has no {} client", provider.name),
            )
        }),
    }
}

/// Starts signing in to `provider` as `email`, with the person's own
/// client or the build's. Returns the address to open in the browser.
pub async fn begin_oauth(
    provider: String,
    email: String,
    client: Option<OAuthClient>,
) -> Result<String, EngineError> {
    let provider = oauth::provider(&provider)
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "unknown provider"))?;
    let client = client_of(provider, client)?;
    cancel_oauth();
    let way_back = if cfg!(target_os = "android") {
        let (tx, rx) = mpsc::unbounded_channel();
        *lock(&REDIRECT) = Some(tx);
        (provider.android_redirect(&client), WayBack::App(rx))
    } else {
        // The listener needs the engine's runtime.
        let loopback = engine()?
            .runtime
            .spawn(Loopback::bind())
            .await
            .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
            .map_err(flow_error)?;
        (loopback.redirect_uri(), WayBack::Loopback(loopback))
    };
    let (redirect, way_back) = way_back;
    let request = Request::new(provider, &client, &email, &redirect);
    let url = request.url.clone();
    *lock(&PENDING) = Some(Pending {
        request,
        way_back,
        email: email.trim().to_owned(),
    });
    Ok(url)
}

/// Android: the address the browser came back to, from `MainActivity`.
/// Ignored unless a sign-in waits for it; its `state` is checked before
/// anything else is read from it.
#[frb(sync)]
pub fn deliver_oauth_redirect(url: String) -> bool {
    match lock(&REDIRECT).as_ref() {
        Some(tx) => tx.send(url).is_ok(),
        None => false,
    }
}

/// Stops the sign-in under way, if any.
#[frb(sync)]
pub fn cancel_oauth() {
    lock(&PENDING).take();
    lock(&REDIRECT).take();
    if let Some(cancel) = lock(&CANCEL).take() {
        cancel.notify_one();
    }
}

/// The first address handed over with this sign-in's `state`. Others (an
/// old sign-in's, or one any app opened) are dropped and the wait goes on,
/// as on the desktop's loopback.
async fn app_redirect(
    request: &Request,
    mut rx: mpsc::UnboundedReceiver<String>,
) -> Result<String, FlowError> {
    while let Some(url) = rx.recv().await {
        match request.code_from_redirect(&url) {
            Err(FlowError::StateMismatch) => continue,
            done => return done,
        }
    }
    Err(FlowError::Cancelled)
}

/// What a finished sign-in gave: the account's login and what the
/// keychain keeps.
struct SignedIn {
    stored: Stored,
    session: Arc<oauth::Session>,
    /// The account the session keeps new refresh tokens for.
    id: Arc<std::sync::atomic::AtomicI64>,
}

/// Waits for the browser, trades the code, and checks `account` signs in
/// with the token.
async fn finish(account: Account, email: &str) -> Result<SignedIn, EngineError> {
    let pending = lock(&PENDING)
        .take()
        .filter(|p| p.email.eq_ignore_ascii_case(email.trim()))
        .ok_or_else(|| EngineError::new(ErrorKind::SignInCancelled, "no sign-in under way"))?;
    let cancel = Arc::new(Notify::new());
    *lock(&CANCEL) = Some(cancel.clone());
    let engine = engine()?;
    let pins = crate::login::pins(account.id);
    engine
        .runtime
        .spawn(async move {
            let Pending {
                request, way_back, ..
            } = pending;
            let code = tokio::select! {
                code = async {
                    match way_back {
                        WayBack::Loopback(l) => l.wait(&request, oauth::SIGN_IN_TIME).await,
                        WayBack::App(rx) => {
                            tokio::time::timeout(oauth::SIGN_IN_TIME, app_redirect(&request, rx))
                                .await
                                .unwrap_or(Err(FlowError::Timeout))
                        }
                    }
                } => code,
                () = cancel.notified() => Err(FlowError::Cancelled),
            }
            .map_err(flow_error)?;
            let grant = request.exchange(&code).await.map_err(token_error)?;
            let refresh = grant.refresh_token.as_ref().ok_or_else(|| {
                EngineError::new(
                    ErrorKind::SignInDenied,
                    "the provider gave no refresh token",
                )
            })?;
            let stored = Stored {
                provider: request.provider.id.clone(),
                client: request.client.clone(),
                refresh_token: refresh.to_string(),
            };
            let id = Arc::new(std::sync::atomic::AtomicI64::new(account.id.0));
            let session = crate::login::session(id.clone(), stored.clone())
                .ok_or_else(|| EngineError::new(ErrorKind::Other, "unknown provider"))?;
            session
                .seed(grant.access_token.clone(), grant.expires_in)
                .await;
            let login = Login::oauth(session.clone()).with_pins(pins);
            remote::check_login(&account, &login).await?;
            Ok(SignedIn {
                stored,
                session,
                id,
            })
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
}

/// Finishes the sign-in [`begin_oauth`] started and adds the account,
/// with the provider's servers.
pub async fn add_oauth_account(
    provider: String,
    name: String,
    email: String,
    sender_name: String,
    color: String,
) -> Result<AccountInfo, EngineError> {
    let p = oauth::provider(&provider)
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "unknown provider"))?;
    let account = Account {
        id: AccountId(0),
        name,
        email: email.trim().to_owned(),
        sender_name: sender_name.trim().to_owned(),
        color,
        kind: AccountKind::Imap {
            imap: p.imap(),
            smtp: p.smtp(),
            username: email.trim().to_owned(),
        },
    };
    let signed = finish(account.clone(), &email).await?;
    let id = store()?.add_account(&account)?;
    if let Err(e) = credentials::keep(id, &signed.stored.to_secret()) {
        store()?.remove_account(id)?;
        return Err(e);
    }
    store()?.set_setting(&crate::login::oauth_key(id.0), &p.id)?;
    signed.id.store(id.0, std::sync::atomic::Ordering::Relaxed);
    crate::login::remember_session(id, signed.session);
    let added = store()?
        .account(id)?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "just added"))?;
    Ok(AccountInfo::from(&added))
}

/// Finishes the sign-in [`begin_oauth`] started for an account whose
/// sign-in stopped working, and follows it again.
pub async fn sign_in_again_oauth(account_id: i64) -> Result<(), EngineError> {
    let id = AccountId(account_id);
    let account = store()?
        .account(id)?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "no such account"))?;
    let email = match &account.kind {
        AccountKind::Imap { username, .. } => username.clone(),
        AccountKind::Jmap { .. } => account.email.clone(),
    };
    let provider = lock(&PENDING)
        .as_ref()
        .map(|p| p.request.provider.id.clone())
        .unwrap_or_default();
    let signed = finish(account.clone(), &email).await?;
    credentials::keep(id, &signed.stored.to_secret())?;
    store()?.set_setting(&crate::login::oauth_key(account_id), &provider)?;
    crate::login::remember_session(id, signed.session);
    stop_watching(id);
    watch_account(account)
}

/// Android: secrets the engine got since the last call (an OAuth sign-in,
/// a refresh token the provider replaced), for the Keystore. Elsewhere
/// always empty: the system keychain already has them.
#[frb(sync)]
pub fn take_new_secrets() -> Vec<KeptSecret> {
    credentials::take_kept()
        .into_iter()
        .map(|(key, value)| KeptSecret { key, value })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_app_redirect_with_another_state_is_dropped_and_the_wait_goes_on() {
        let p = oauth::provider("microsoft").unwrap();
        let client = Client {
            client_id: "test".into(),
            client_secret: None,
            tenant: None,
        };
        let request = Request::new(p, &client, "", "mail.piuma.app://oauth");
        // URL-safe base64: as written in the address.
        let state = request.url.split("state=").nth(1).unwrap();
        let state = state.split('&').next().unwrap().to_owned();
        let (tx, rx) = mpsc::unbounded_channel();
        tx.send("mail.piuma.app://oauth?code=forged&state=nope".into())
            .unwrap();
        tx.send("mail.piuma.app://oauth?code=forged".into())
            .unwrap();
        tx.send(format!("mail.piuma.app://oauth?code=real&state={state}"))
            .unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        assert_eq!(
            runtime.block_on(app_redirect(&request, rx)),
            Ok("real".into())
        );
        // Nothing more will come: cancelled, not hung.
        let (tx, rx) = mpsc::unbounded_channel::<String>();
        drop(tx);
        assert_eq!(
            runtime.block_on(app_redirect(&request, rx)),
            Err(FlowError::Cancelled)
        );
    }
}
