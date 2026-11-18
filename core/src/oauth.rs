//! Signing in with a provider's own page (OAuth 2.0), for providers that
//! no longer take passwords from mail apps: Microsoft 365 and Outlook.com,
//! and Gmail without an app password.
//!
//! The flow is the one RFC 8252 asks of native apps: Authorization Code
//! with PKCE (RFC 7636), in the system browser, never in a web view the
//! app controls. On the desktop the browser comes back to a one-time
//! listener on `127.0.0.1` at a random port ([`Loopback`]); on Android to
//! the app's own URL scheme, which the app hands back to
//! [`Request::code_from_redirect`]. Either way the answer must carry the
//! `state` this request made, or it is refused.
//!
//! The providers are data ([`providers`], from `oauth_providers.json`):
//! another one is a new entry there, not new code in the flow. Their
//! client IDs come with the build ([`built_in_client`]) or from the person
//! (a [`Client`] of their own); a build without any keeps working, with
//! app passwords where the provider has them.
//!
//! What the keychain keeps for such an account is a [`Stored`]: the
//! provider, the client and the refresh token. Access tokens live only in
//! memory, in a [`Session`], and are renewed before they run out.

use std::collections::BTreeMap;
use std::fmt;
use std::time::{Duration, Instant};

use base64::Engine as _;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use zeroize::Zeroizing;

use crate::model::{Security, Server};

/// The SASL mechanism a provider's servers take a token with.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Mechanism {
    /// Google's and Microsoft's `XOAUTH2`.
    Xoauth2,
    /// The standard one, RFC 7628.
    Oauthbearer,
}

#[derive(Debug, Clone, Deserialize)]
struct ServerDef {
    host: String,
    port: u16,
    security: String,
}

impl ServerDef {
    fn server(&self) -> Server {
        Server {
            host: self.host.clone(),
            port: self.port,
            security: Security::from_tag(&self.security),
        }
    }
}

/// A provider that signs in with OAuth.
#[derive(Debug, Clone, Deserialize)]
pub struct Provider {
    /// `microsoft`, `google`: also the key of its client in the build.
    pub id: String,
    /// As shown in "Sign in with …".
    pub name: String,
    /// `{tenant}` is replaced with the client's tenant, or [`Self::tenant`].
    pub authorize_url: String,
    pub token_url: String,
    /// Where a refresh token is given back when the account goes (RFC
    /// 7009); none for providers without one for public clients.
    pub revoke_url: Option<String>,
    /// The default tenant, for providers that have them.
    pub tenant: Option<String>,
    pub scopes: Vec<String>,
    /// More parameters for the authorization request.
    #[serde(default)]
    pub params: BTreeMap<String, String>,
    pub mechanism: Mechanism,
    imap: ServerDef,
    smtp: ServerDef,
    /// Addresses at these domains are this provider's.
    #[serde(default)]
    pub domains: Vec<String>,
    /// Custom domains whose MX hosts end in one of these are hosted here.
    #[serde(default)]
    pub mx: Vec<String>,
    /// The redirect on Android: `{app_scheme}` is the app's own scheme,
    /// `{reversed_client_id}` the client ID backwards (Google).
    pub android_redirect: String,
    /// Whether the provider still takes app passwords, the fallback when
    /// this build has no client for it.
    #[serde(default)]
    pub app_passwords: bool,
}

/// The app's own URL scheme on Android: a reverse domain name the project
/// controls (RFC 8252 section 7.1). Not the application id itself, whose
/// `_` a URL scheme can't hold.
pub const APP_SCHEME: &str = "mail.piuma.app";

impl Provider {
    pub fn imap(&self) -> Server {
        self.imap.server()
    }

    pub fn smtp(&self) -> Server {
        self.smtp.server()
    }

    fn with_tenant(&self, url: &str, client: &Client) -> String {
        let tenant = client
            .tenant
            .as_deref()
            .filter(|t| !t.trim().is_empty())
            .or(self.tenant.as_deref())
            .unwrap_or("common");
        url.replace("{tenant}", tenant.trim())
    }

    pub fn authorize_url(&self, client: &Client) -> String {
        self.with_tenant(&self.authorize_url, client)
    }

    pub fn token_url(&self, client: &Client) -> String {
        self.with_tenant(&self.token_url, client)
    }

    /// Where the browser comes back to on Android.
    pub fn android_redirect(&self, client: &Client) -> String {
        let reversed = client
            .client_id
            .split('.')
            .rev()
            .collect::<Vec<_>>()
            .join(".");
        self.android_redirect
            .replace("{app_scheme}", APP_SCHEME)
            .replace("{reversed_client_id}", &reversed)
    }
}

/// Every provider this build knows.
pub fn providers() -> &'static [Provider] {
    static ALL: std::sync::OnceLock<Vec<Provider>> = std::sync::OnceLock::new();
    ALL.get_or_init(|| {
        serde_json::from_str(include_str!("oauth_providers.json"))
            .expect("oauth_providers.json is valid")
    })
}

pub fn provider(id: &str) -> Option<&'static Provider> {
    providers().iter().find(|p| p.id == id)
}

/// The provider of an address's own domain.
pub fn for_domain(domain: &str) -> Option<&'static Provider> {
    let domain = domain.trim().trim_end_matches('.').to_ascii_lowercase();
    providers().iter().find(|p| p.domains.contains(&domain))
}

/// The provider that hosts a custom domain, by one of its MX hosts.
pub fn for_mx(host: &str) -> Option<&'static Provider> {
    let host = host.trim_end_matches('.').to_ascii_lowercase();
    providers().iter().find(|p| {
        p.mx.iter()
            .any(|s| host == *s || host.ends_with(&format!(".{s}")))
    })
}

/// The provider whose servers these are, for an account set up by hand
/// or before sign-in with OAuth existed.
pub fn for_server(imap_host: &str) -> Option<&'static Provider> {
    providers()
        .iter()
        .find(|p| p.imap.host.eq_ignore_ascii_case(imap_host.trim()))
}

/// The app's registration with a provider.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Client {
    pub client_id: String,
    /// Google's desktop clients have one. It is not a secret for an
    /// installed app (RFC 8252 section 8.5): anyone can read it from the
    /// program, and PKCE is what protects the flow.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_secret: Option<String>,
    /// Microsoft's tenant, when not `common`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tenant: Option<String>,
}

impl fmt::Debug for Client {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Client")
            .field("client_id", &self.client_id)
            .field("tenant", &self.tenant)
            .finish_non_exhaustive()
    }
}

/// The clients this build was made with: `PIUMA_OAUTH_CLIENTS` at build
/// time, entries separated by `;` or new lines:
/// `microsoft=<id>;google=<id>;google.secret=<secret>;google.android=<id>`
/// (also `<provider>.tenant`). None is needed to build.
const BUILD_CLIENTS: Option<&str> = option_env!("PIUMA_OAUTH_CLIENTS");

/// The client this build has for a provider, if any.
pub fn built_in_client(provider: &str) -> Option<Client> {
    clients_from(
        BUILD_CLIENTS.unwrap_or(""),
        provider,
        cfg!(target_os = "android"),
    )
}

fn clients_from(config: &str, provider: &str, android: bool) -> Option<Client> {
    let mut values = BTreeMap::new();
    for entry in config.split([';', '\n']) {
        if let Some((key, value)) = entry.split_once('=') {
            let value = value.trim();
            if !value.is_empty() {
                values.insert(key.trim().to_owned(), value.to_owned());
            }
        }
    }
    let get = |suffix: &str| values.get(&format!("{provider}{suffix}")).cloned();
    // Android signs in with a client of its own type where there is one;
    // such clients have no secret.
    let (client_id, client_secret) = match (android, get(".android")) {
        (true, Some(id)) => (id, None),
        _ => (get("")?, get(".secret")),
    };
    Some(Client {
        client_id,
        client_secret,
        tenant: get(".tenant"),
    })
}

/// Why signing in on the provider's page didn't give a code.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum FlowError {
    #[error("the answer did not come from this sign-in (state mismatch)")]
    StateMismatch,
    #[error("the provider refused: {0}")]
    Denied(String),
    #[error("the answer carried no code")]
    NoCode,
    #[error("nobody signed in in time")]
    Timeout,
    #[error("the sign-in was cancelled")]
    Cancelled,
    #[error("{0}")]
    Io(String),
}

/// Why the token endpoint gave no token.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum TokenError {
    /// The provider said no for good: the refresh token was revoked or
    /// expired, the client is wrong. Only signing in again helps.
    #[error("the provider refused the sign-in: {0}")]
    Rejected(String),
    /// The provider could not be reached, or was busy: try later.
    #[error("could not reach the provider: {0}")]
    Offline(String),
}

/// Random bytes, base64url without padding.
fn random(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    getrandom::fill(&mut buf).expect("system randomness");
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(buf)
}

/// RFC 7636: the S256 challenge of a verifier.
pub fn challenge(verifier: &str) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

/// One authorization request, waiting for its answer.
pub struct Request {
    /// What the browser opens.
    pub url: String,
    pub redirect_uri: String,
    pub provider: Provider,
    pub client: Client,
    state: String,
    verifier: Zeroizing<String>,
}

impl fmt::Debug for Request {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Request")
            .field("provider", &self.provider.id)
            .field("redirect_uri", &self.redirect_uri)
            .finish_non_exhaustive()
    }
}

impl Request {
    /// A new request for `login_hint`'s account, coming back to
    /// `redirect_uri`.
    pub fn new(provider: &Provider, client: &Client, login_hint: &str, redirect_uri: &str) -> Self {
        // 64 characters: within RFC 7636's 43 to 128.
        let verifier = Zeroizing::new(random(48));
        let state = random(24);
        let mut url = url::Url::parse(&provider.authorize_url(client))
            .unwrap_or_else(|_| url::Url::parse("https://invalid.invalid/").expect("valid"));
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("response_type", "code")
                .append_pair("client_id", &client.client_id)
                .append_pair("redirect_uri", redirect_uri)
                .append_pair("scope", &provider.scopes.join(" "))
                .append_pair("state", &state)
                .append_pair("code_challenge", &challenge(&verifier))
                .append_pair("code_challenge_method", "S256");
            if !login_hint.trim().is_empty() {
                q.append_pair("login_hint", login_hint.trim());
            }
            for (k, v) in &provider.params {
                q.append_pair(k, v);
            }
        }
        Request {
            url: url.to_string(),
            redirect_uri: redirect_uri.to_owned(),
            provider: provider.clone(),
            client: client.clone(),
            state,
            verifier,
        }
    }

    /// The code in the address the browser came back to. Anything without
    /// this request's `state` is refused, whatever else it carries.
    pub fn code_from_redirect(&self, address: &str) -> Result<String, FlowError> {
        let url = url::Url::parse(address).map_err(|_| FlowError::NoCode)?;
        let mut state = None;
        let mut code = None;
        let mut error = None;
        let mut description = None;
        for (k, v) in url.query_pairs() {
            match k.as_ref() {
                "state" => state = Some(v.into_owned()),
                "code" => code = Some(v.into_owned()),
                "error" => error = Some(v.into_owned()),
                "error_description" => description = Some(v.into_owned()),
                _ => {}
            }
        }
        // Constant time is not needed: the state is single use and random.
        if state.as_deref() != Some(self.state.as_str()) {
            return Err(FlowError::StateMismatch);
        }
        if let Some(error) = error {
            return Err(FlowError::Denied(match description {
                Some(d) => format!("{error}: {d}"),
                None => error,
            }));
        }
        code.filter(|c| !c.is_empty()).ok_or(FlowError::NoCode)
    }

    /// Trades the code for tokens.
    pub async fn exchange(&self, code: &str) -> Result<Grant, TokenError> {
        token_request(
            &self.provider,
            &self.client,
            &[
                ("grant_type", "authorization_code"),
                ("code", code),
                ("redirect_uri", &self.redirect_uri),
                ("code_verifier", &self.verifier),
            ],
        )
        .await
    }
}

/// The one-time listener on `127.0.0.1` the browser comes back to on the
/// desktop (RFC 8252 section 7.3). It answers only the redirect, and
/// stops after the first one or at the timeout.
pub struct Loopback {
    listener: TcpListener,
    port: u16,
}

/// How long the person has to sign in.
pub const SIGN_IN_TIME: Duration = Duration::from_secs(5 * 60);

impl Loopback {
    pub async fn bind() -> Result<Self, FlowError> {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .map_err(|e| FlowError::Io(e.to_string()))?;
        let port = listener
            .local_addr()
            .map_err(|e| FlowError::Io(e.to_string()))?
            .port();
        Ok(Loopback { listener, port })
    }

    pub fn redirect_uri(&self) -> String {
        format!("http://127.0.0.1:{}", self.port)
    }

    /// Waits for the browser, and answers it with a page saying to go back
    /// to the app.
    pub async fn wait(self, request: &Request, timeout: Duration) -> Result<String, FlowError> {
        tokio::time::timeout(timeout, self.serve(request))
            .await
            .unwrap_or(Err(FlowError::Timeout))
    }

    async fn serve(self, request: &Request) -> Result<String, FlowError> {
        loop {
            let (mut tcp, _) = self
                .listener
                .accept()
                .await
                .map_err(|e| FlowError::Io(e.to_string()))?;
            let mut head = Vec::new();
            let mut buf = [0u8; 2048];
            // The request line is all that matters; a slow client gets
            // a few seconds.
            let read = tokio::time::timeout(Duration::from_secs(5), async {
                while !head.windows(4).any(|w| w == b"\r\n\r\n") && head.len() < 16 * 1024 {
                    match tcp.read(&mut buf).await {
                        Ok(0) | Err(_) => break,
                        Ok(n) => head.extend_from_slice(&buf[..n]),
                    }
                }
            })
            .await;
            if read.is_err() {
                continue;
            }
            let line = String::from_utf8_lossy(&head);
            let target = line
                .lines()
                .next()
                .and_then(|l| l.strip_prefix("GET "))
                .and_then(|l| l.split(' ').next())
                .unwrap_or("");
            // Browsers also ask for /favicon.ico.
            if !(target == "/" || target.starts_with("/?")) {
                let _ = tcp
                    .write_all(
                        b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                    )
                    .await;
                continue;
            }
            let result = request.code_from_redirect(&format!("{}{target}", self.redirect_uri()));
            let (status, text) = match &result {
                Ok(_) => (
                    "200 OK",
                    "Signed in. You can close this page and go back to Piuma Mail.",
                ),
                Err(_) => (
                    "400 Bad Request",
                    "Piuma Mail could not sign in. Close this page and try again from the app.",
                ),
            };
            let body = format!(
                "<!doctype html><meta charset=utf-8><title>Piuma Mail</title><p style=\"font:16px system-ui;margin:3em\">{text}</p>"
            );
            let reply = format!(
                "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = tcp.write_all(reply.as_bytes()).await;
            let _ = tcp.shutdown().await;
            return result;
        }
    }
}

/// What the token endpoint gave.
pub struct Grant {
    pub access_token: Zeroizing<String>,
    /// Some providers send a new one with each refresh (Microsoft).
    pub refresh_token: Option<Zeroizing<String>>,
    /// Seconds the access token is good for.
    pub expires_in: u64,
}

impl fmt::Debug for Grant {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Grant")
            .field("expires_in", &self.expires_in)
            .finish_non_exhaustive()
    }
}

#[derive(Deserialize)]
struct TokenReply {
    access_token: Option<String>,
    refresh_token: Option<String>,
    expires_in: Option<serde_json::Value>,
    error: Option<String>,
    error_description: Option<String>,
}

fn http() -> Result<reqwest::Client, TokenError> {
    crate::tls::http_client()
        .timeout(Duration::from_secs(20))
        .user_agent(concat!("PiumaMail/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|e| TokenError::Offline(e.to_string()))
}

/// `application/x-www-form-urlencoded`, kept out of memory when dropped:
/// it carries codes and tokens.
fn form_body(fields: &[(&str, &str)]) -> Vec<u8> {
    let body = Zeroizing::new(
        url::form_urlencoded::Serializer::new(String::new())
            .extend_pairs(fields)
            .finish(),
    );
    body.as_bytes().to_vec()
}

async fn token_request(
    provider: &Provider,
    client: &Client,
    form: &[(&str, &str)],
) -> Result<Grant, TokenError> {
    let mut fields: Vec<(&str, &str)> = form.to_vec();
    fields.push(("client_id", &client.client_id));
    if let Some(secret) = &client.client_secret {
        fields.push(("client_secret", secret));
    }
    let response = http()?
        .post(provider.token_url(client))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(form_body(&fields))
        .send()
        .await
        .map_err(|e| TokenError::Offline(e.without_url().to_string()))?;
    let status = response.status();
    let reply: TokenReply = response
        .json()
        .await
        .map_err(|e| TokenError::Offline(format!("{status}: {}", e.without_url())))?;
    match (reply.access_token, reply.error) {
        (Some(access), None) if status.is_success() => Ok(Grant {
            access_token: Zeroizing::new(access),
            refresh_token: reply.refresh_token.map(Zeroizing::new),
            expires_in: match reply.expires_in {
                Some(serde_json::Value::Number(n)) => n.as_u64().unwrap_or(3600),
                Some(serde_json::Value::String(s)) => s.parse().unwrap_or(3600),
                _ => 3600,
            },
        }),
        // A server error is not a refusal.
        _ if status.is_server_error() || status.as_u16() == 429 => {
            Err(TokenError::Offline(status.to_string()))
        }
        (_, error) => {
            let error = error.unwrap_or_else(|| status.to_string());
            Err(TokenError::Rejected(match reply.error_description {
                // Microsoft's descriptions carry trace ids on new lines.
                Some(d) => format!("{error}: {}", d.lines().next().unwrap_or("")),
                None => error,
            }))
        }
    }
}

/// A new access token from a refresh token.
pub async fn refresh(
    provider: &Provider,
    client: &Client,
    refresh_token: &str,
) -> Result<Grant, TokenError> {
    token_request(
        provider,
        client,
        &[
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh_token),
            ("scope", &provider.scopes.join(" ")),
        ],
    )
    .await
}

/// Gives a refresh token back, when the account is removed. Providers
/// without a revocation endpoint keep it until it runs out.
pub async fn revoke(provider: &Provider, client: &Client, token: &str) -> Result<(), TokenError> {
    let Some(url) = &provider.revoke_url else {
        return Ok(());
    };
    let response = http()?
        .post(url)
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(form_body(&[
            ("token", token),
            ("client_id", &client.client_id),
        ]))
        .send()
        .await
        .map_err(|e| TokenError::Offline(e.without_url().to_string()))?;
    // 400 means the token was already invalid: just as good.
    if response.status().is_success() || response.status().as_u16() == 400 {
        Ok(())
    } else {
        Err(TokenError::Offline(response.status().to_string()))
    }
}

/// What the keychain keeps for an account signed in with OAuth, in place
/// of a password.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Stored {
    pub provider: String,
    pub client: Client,
    pub refresh_token: String,
}

impl fmt::Debug for Stored {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Stored")
            .field("provider", &self.provider)
            .field("client", &self.client)
            .finish_non_exhaustive()
    }
}

/// Marks a keychain entry as a [`Stored`] rather than a password.
const STORED: &str = "piuma-oauth:";

impl Stored {
    pub fn to_secret(&self) -> Zeroizing<String> {
        Zeroizing::new(format!(
            "{STORED}{}",
            serde_json::to_string(self).expect("serializes")
        ))
    }

    pub fn from_secret(secret: &str) -> Option<Self> {
        serde_json::from_str(secret.strip_prefix(STORED)?).ok()
    }

    /// Whether a keychain entry holds one.
    pub fn is_stored(secret: &str) -> bool {
        secret.starts_with(STORED)
    }
}

/// Access tokens are renewed when they have less than this left, so a
/// connection never starts with one about to run out.
pub const RENEW_BEFORE: Duration = Duration::from_secs(5 * 60);

struct State {
    stored: Stored,
    access: Option<(Zeroizing<String>, Instant)>,
}

/// An account's sign-in with a provider, for as long as the app runs:
/// hands out access tokens, renewing them before they run out. Shared by
/// every connection of the account, so they renew once between them.
pub struct Session {
    provider: Provider,
    state: tokio::sync::Mutex<State>,
    /// Told when the provider sends a new refresh token, to keep it.
    on_change: Box<dyn Fn(&Stored) + Send + Sync>,
}

impl fmt::Debug for Session {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Session")
            .field("provider", &self.provider.id)
            .finish_non_exhaustive()
    }
}

impl Session {
    /// None for a provider this build doesn't know.
    pub fn new(
        stored: Stored,
        on_change: impl Fn(&Stored) + Send + Sync + 'static,
    ) -> Option<Self> {
        let provider = provider(&stored.provider)?.clone();
        Some(Self::with_provider(provider, stored, on_change))
    }

    /// With a provider of the caller's, as tests do.
    pub fn with_provider(
        provider: Provider,
        stored: Stored,
        on_change: impl Fn(&Stored) + Send + Sync + 'static,
    ) -> Self {
        Session {
            provider,
            state: tokio::sync::Mutex::new(State {
                stored,
                access: None,
            }),
            on_change: Box::new(on_change),
        }
    }

    pub fn mechanism(&self) -> Mechanism {
        self.provider.mechanism
    }

    pub fn provider(&self) -> &Provider {
        &self.provider
    }

    /// Starts with the access token sign-in just gave, good for
    /// `expires_in` seconds.
    pub async fn seed(&self, access: Zeroizing<String>, expires_in: u64) {
        self.state.lock().await.access =
            Some((access, Instant::now() + Duration::from_secs(expires_in)));
    }

    /// A token good for a while yet: the one in hand, or a new one.
    pub async fn access_token(&self) -> Result<Zeroizing<String>, TokenError> {
        let mut state = self.state.lock().await;
        if let Some((token, until)) = &state.access {
            if until.saturating_duration_since(Instant::now()) > RENEW_BEFORE {
                return Ok(token.clone());
            }
        }
        self.renew_locked(&mut state).await
    }

    /// A new token whatever the one in hand: after a server refused it.
    pub async fn renew(&self) -> Result<Zeroizing<String>, TokenError> {
        let mut state = self.state.lock().await;
        self.renew_locked(&mut state).await
    }

    async fn renew_locked(&self, state: &mut State) -> Result<Zeroizing<String>, TokenError> {
        state.access = None;
        let grant = refresh(
            &self.provider,
            &state.stored.client,
            &state.stored.refresh_token,
        )
        .await?;
        if let Some(new) = grant.refresh_token {
            if *new != state.stored.refresh_token {
                state.stored.refresh_token = new.to_string();
                (self.on_change)(&state.stored);
            }
        }
        let until = Instant::now() + Duration::from_secs(grant.expires_in);
        state.access = Some((grant.access_token.clone(), until));
        Ok(grant.access_token)
    }

    /// What the keychain keeps now.
    pub async fn stored(&self) -> Stored {
        self.state.lock().await.stored.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_providers_are_valid_data() {
        let ms = provider("microsoft").unwrap();
        assert_eq!(ms.imap().host, "outlook.office365.com");
        assert_eq!(
            ms.smtp(),
            Server {
                host: "smtp.office365.com".into(),
                port: 587,
                security: Security::StartTls,
            }
        );
        assert!(ms.scopes.iter().any(|s| s == "offline_access"));
        let google = provider("google").unwrap();
        assert_eq!(google.scopes, ["https://mail.google.com/"]);
        assert!(google.revoke_url.is_some());
        assert!(google.app_passwords && !ms.app_passwords);
    }

    #[test]
    fn finds_providers_by_domain_mx_and_server() {
        assert_eq!(for_domain("Hotmail.it").unwrap().id, "microsoft");
        assert_eq!(for_domain("gmail.com").unwrap().id, "google");
        assert!(for_domain("studio.it").is_none());
        assert_eq!(
            for_mx("studio-it.mail.protection.outlook.com.").unwrap().id,
            "microsoft"
        );
        assert_eq!(for_mx("ASPMX.L.GOOGLE.COM").unwrap().id, "google");
        assert!(for_mx("mx.notoutlook.com").is_none());
        assert_eq!(for_server("IMAP.gmail.com").unwrap().id, "google");
    }

    #[test]
    fn tenants_fill_the_endpoints() {
        let ms = provider("microsoft").unwrap();
        let mut client = Client {
            client_id: "id".into(),
            client_secret: None,
            tenant: None,
        };
        assert!(ms.token_url(&client).contains("/common/oauth2/"));
        client.tenant = Some("organizations".into());
        assert!(ms.authorize_url(&client).contains("/organizations/oauth2/"));
    }

    #[test]
    fn build_clients_are_read_per_provider_and_platform() {
        let config = "microsoft=ms-id; google=g-id.apps.googleusercontent.com\ngoogle.secret=not-secret;google.android=a-id.apps.googleusercontent.com";
        let ms = clients_from(config, "microsoft", false).unwrap();
        assert_eq!(ms.client_id, "ms-id");
        assert_eq!(ms.client_secret, None);
        let desktop = clients_from(config, "google", false).unwrap();
        assert_eq!(desktop.client_secret.as_deref(), Some("not-secret"));
        let android = clients_from(config, "google", true).unwrap();
        assert_eq!(android.client_id, "a-id.apps.googleusercontent.com");
        assert_eq!(android.client_secret, None);
        assert_eq!(
            provider("google").unwrap().android_redirect(&android),
            "com.googleusercontent.apps.a-id:/oauth2redirect"
        );
        assert_eq!(
            provider("microsoft").unwrap().android_redirect(&ms),
            "mail.piuma.app://oauth"
        );
        assert!(clients_from("", "microsoft", false).is_none());
        assert!(clients_from("microsoft=", "microsoft", false).is_none());
    }

    #[test]
    fn pkce_challenge_matches_rfc_7636() {
        // RFC 7636, appendix B.
        assert_eq!(
            challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        );
    }

    #[test]
    fn a_request_asks_for_what_rfc_8252_wants() {
        let p = provider("microsoft").unwrap();
        let client = Client {
            client_id: "app".into(),
            client_secret: None,
            tenant: None,
        };
        let r = Request::new(p, &client, "me@outlook.com", "http://127.0.0.1:5000");
        let url = url::Url::parse(&r.url).unwrap();
        let q: BTreeMap<_, _> = url.query_pairs().into_owned().collect();
        assert_eq!(q["response_type"], "code");
        assert_eq!(q["code_challenge_method"], "S256");
        assert_eq!(q["code_challenge"], challenge(&r.verifier));
        assert_eq!(q["login_hint"], "me@outlook.com");
        assert_eq!(q["redirect_uri"], "http://127.0.0.1:5000");
        assert!(q["scope"].contains("IMAP.AccessAsUser.All"));
        assert_eq!(q["state"].len(), 32);
        assert!(r.verifier.len() >= 43);
        // Two requests never share a state or a verifier.
        let other = Request::new(p, &client, "", "http://127.0.0.1:5000");
        assert_ne!(other.state, r.state);
        assert_ne!(*other.verifier, *r.verifier);
        assert!(!format!("{r:?}").contains(&r.state));
    }

    #[test]
    fn redirects_without_this_state_are_refused() {
        let p = provider("google").unwrap();
        let client = Client {
            client_id: "app".into(),
            client_secret: None,
            tenant: None,
        };
        let r = Request::new(p, &client, "", "mail.piuma.app://oauth");
        let state = r.state.clone();
        assert_eq!(
            r.code_from_redirect(&format!("mail.piuma.app://oauth?code=abc&state={state}")),
            Ok("abc".into())
        );
        assert_eq!(
            r.code_from_redirect("mail.piuma.app://oauth?code=abc&state=other"),
            Err(FlowError::StateMismatch)
        );
        assert_eq!(
            r.code_from_redirect("mail.piuma.app://oauth?code=abc"),
            Err(FlowError::StateMismatch)
        );
        assert_eq!(
            r.code_from_redirect(&format!(
                "mail.piuma.app://oauth?error=access_denied&error_description=No&state={state}"
            )),
            Err(FlowError::Denied("access_denied: No".into()))
        );
        assert_eq!(
            r.code_from_redirect(&format!("mail.piuma.app://oauth?state={state}")),
            Err(FlowError::NoCode)
        );
    }

    #[test]
    fn stored_sign_ins_are_told_from_passwords_and_hide_their_token() {
        let stored = Stored {
            provider: "google".into(),
            client: Client {
                client_id: "id".into(),
                client_secret: Some("s".into()),
                tenant: None,
            },
            refresh_token: "refresh-me".into(),
        };
        let secret = stored.to_secret();
        assert!(Stored::is_stored(&secret));
        assert_eq!(Stored::from_secret(&secret), Some(stored.clone()));
        assert!(!Stored::is_stored("hunter2"));
        assert_eq!(Stored::from_secret("hunter2"), None);
        let shown = format!("{stored:?}");
        assert!(!shown.contains("refresh-me") && !shown.contains("\"s\""));
    }
}
