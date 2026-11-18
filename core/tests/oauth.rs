//! Signing in with OAuth, end to end against servers inside the test: the
//! browser's way back to the loopback listener, the code for tokens, the
//! tokens renewed before they run out and after a server refused one, and
//! XOAUTH2 and OAUTHBEARER over IMAP and SMTP. Nothing calls a real
//! provider.

mod support;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use piuma_core::auth::Login;
use piuma_core::imap::{check_login, ImapConfig, ImapError};
use piuma_core::oauth::{
    challenge, Client, FlowError, Loopback, Mechanism, Request, Session, Stored, TokenError,
};
use piuma_core::smtp::{ready, send, Draft, SendError, SmtpConfig};
use piuma_core::Security;
use support::{imap_server, provider, smtp_server, token_server, Valid};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

fn client() -> Client {
    Client {
        client_id: "test-client".into(),
        client_secret: None,
        tenant: None,
    }
}

fn stored(refresh: &str) -> Stored {
    Stored {
        provider: "test".into(),
        client: client(),
        refresh_token: refresh.into(),
    }
}

/// A sign-in against the test's token endpoint; `kept` gets every new
/// refresh token the provider sends.
fn session(base: &str, mechanism: Mechanism, refresh: &str) -> (Arc<Session>, Arc<Mutex<Vec<String>>>) {
    let kept: Arc<Mutex<Vec<String>>> = Arc::default();
    let keep = kept.clone();
    let s = Session::with_provider(provider(base, mechanism), stored(refresh), move |s| {
        keep.lock().unwrap().push(s.refresh_token.clone())
    });
    (Arc::new(s), kept)
}

fn imap(port: u16, login: Login) -> ImapConfig {
    ImapConfig {
        host: "127.0.0.1".into(),
        port,
        security: Security::None,
        username: "me@example.org".into(),
        login,
    }
}

fn valid(token: &str) -> Valid {
    Arc::new(Mutex::new(token.into()))
}

/// The browser coming back: a GET to the loopback listener. Returns the
/// status line.
async fn browser(redirect: &str, target: &str) -> String {
    let port: u16 = redirect.rsplit(':').next().unwrap().parse().unwrap();
    let mut tcp = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
    tcp.write_all(format!("GET {target} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n").as_bytes())
        .await
        .unwrap();
    let mut reply = String::new();
    tcp.read_to_string(&mut reply).await.unwrap();
    reply.lines().next().unwrap_or("").to_owned()
}

fn query(url: &str) -> HashMap<String, String> {
    url::Url::parse(url).unwrap().query_pairs().into_owned().collect()
}

#[tokio::test]
async fn the_browser_comes_back_with_a_code_for_tokens() {
    let (base, forms) = token_server(false).await;
    let p = provider(&base, Mechanism::Xoauth2);
    let loopback = Loopback::bind().await.unwrap();
    let redirect = loopback.redirect_uri();
    assert!(redirect.starts_with("http://127.0.0.1:"));
    let request = Request::new(&p, &client(), "me@example.org", &redirect);
    let state = query(&request.url)["state"].clone();
    let asked_challenge = query(&request.url)["code_challenge"].clone();

    let waiting = tokio::spawn(async move {
        let code = loopback.wait(&request, Duration::from_secs(10)).await;
        (code, request)
    });
    // The browser also asks for an icon: not the redirect.
    assert!(browser(&redirect, "/favicon.ico").await.contains("404"));
    let status = browser(&redirect, &format!("/?code=the-code&state={state}")).await;
    assert!(status.contains("200"), "{status}");
    let (code, request) = waiting.await.unwrap();
    assert_eq!(code.unwrap(), "the-code");

    let grant = request.exchange("the-code").await.unwrap();
    assert_eq!(grant.access_token.as_str(), "access-code");
    assert_eq!(grant.refresh_token.as_deref().map(|s| s.as_str()), Some("refresh-0"));
    let form = forms.lock().unwrap()[0].clone();
    assert_eq!(form["grant_type"], "authorization_code");
    assert_eq!(form["code"], "the-code");
    assert_eq!(form["redirect_uri"], redirect);
    assert_eq!(form["client_id"], "test-client");
    // PKCE: the verifier sent now matches the challenge sent before.
    assert_eq!(challenge(&form["code_verifier"]), asked_challenge);
}

#[tokio::test]
async fn an_answer_with_another_state_is_refused() {
    let p = provider("http://127.0.0.1:9", Mechanism::Xoauth2);
    let loopback = Loopback::bind().await.unwrap();
    let redirect = loopback.redirect_uri();
    let request = Request::new(&p, &client(), "", &redirect);
    let waiting =
        tokio::spawn(async move { loopback.wait(&request, Duration::from_secs(10)).await });
    let status = browser(&redirect, "/?code=forged&state=not-this-one").await;
    assert!(status.contains("400"), "{status}");
    assert_eq!(waiting.await.unwrap(), Err(FlowError::StateMismatch));
}

#[tokio::test]
async fn a_refusal_on_the_providers_page_is_reported() {
    let p = provider("http://127.0.0.1:9", Mechanism::Xoauth2);
    let loopback = Loopback::bind().await.unwrap();
    let redirect = loopback.redirect_uri();
    let request = Request::new(&p, &client(), "", &redirect);
    let state = query(&request.url)["state"].clone();
    let waiting =
        tokio::spawn(async move { loopback.wait(&request, Duration::from_secs(10)).await });
    browser(
        &redirect,
        &format!("/?error=access_denied&error_description=The+user+said+no&state={state}"),
    )
    .await;
    assert_eq!(
        waiting.await.unwrap(),
        Err(FlowError::Denied("access_denied: The user said no".into()))
    );
}

#[tokio::test]
async fn nobody_signing_in_times_out() {
    let p = provider("http://127.0.0.1:9", Mechanism::Xoauth2);
    let loopback = Loopback::bind().await.unwrap();
    let request = Request::new(&p, &client(), "", &loopback.redirect_uri());
    assert_eq!(
        loopback.wait(&request, Duration::from_millis(200)).await,
        Err(FlowError::Timeout)
    );
}

#[tokio::test]
async fn tokens_are_renewed_before_they_run_out() {
    let (base, forms) = token_server(true).await;
    let (s, kept) = session(&base, Mechanism::Xoauth2, "refresh-0");
    // Plenty of time left: no trip to the provider.
    s.seed("fresh".to_owned().into(), 3600).await;
    assert_eq!(s.access_token().await.unwrap().as_str(), "fresh");
    assert!(forms.lock().unwrap().is_empty());
    // A minute left: renewed before use.
    s.seed("almost-gone".to_owned().into(), 60).await;
    assert_eq!(s.access_token().await.unwrap().as_str(), "access-1");
    assert_eq!(forms.lock().unwrap()[0]["refresh_token"], "refresh-0");
    // Microsoft sends a new refresh token each time: it is kept.
    assert_eq!(*kept.lock().unwrap(), ["refresh-1"]);
    assert_eq!(s.stored().await.refresh_token, "refresh-1");
    // And the new one is used next.
    s.renew().await.unwrap();
    assert_eq!(forms.lock().unwrap()[1]["refresh_token"], "refresh-1");
}

#[tokio::test]
async fn a_revoked_sign_in_asks_to_sign_in_again() {
    let (base, _) = token_server(false).await;
    let (s, _) = session(&base, Mechanism::Xoauth2, "revoked");
    assert_eq!(
        s.access_token().await.unwrap_err(),
        TokenError::Rejected("invalid_grant: AADSTS70000: revoked".into())
    );
    let (port, _) = imap_server(valid("access-1"), None).await;
    let err = check_login(&imap(port, Login::oauth(s))).await.unwrap_err();
    assert!(matches!(err, ImapError::Auth), "{err:?}");
}

#[tokio::test]
async fn an_unreachable_provider_is_offline_not_a_refusal() {
    let closed = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://127.0.0.1:{}", closed.local_addr().unwrap().port());
    drop(closed);
    let (s, _) = session(&base, Mechanism::Xoauth2, "refresh-0");
    let (port, _) = imap_server(valid("access-1"), None).await;
    let err = check_login(&imap(port, Login::oauth(s))).await.unwrap_err();
    assert!(matches!(err, ImapError::TokenUnavailable(_)), "{err:?}");
    assert!(err.is_offline());
}

#[tokio::test]
async fn imap_signs_in_with_xoauth2() {
    let (base, _) = token_server(false).await;
    let (s, _) = session(&base, Mechanism::Xoauth2, "refresh-0");
    let (port, seen) = imap_server(valid("access-1"), None).await;
    check_login(&imap(port, Login::oauth(s))).await.unwrap();
    assert_eq!(
        *seen.lock().unwrap(),
        ["XOAUTH2 user=me@example.org\x01auth=Bearer access-1\x01\x01"]
    );
}

#[tokio::test]
async fn imap_signs_in_with_oauthbearer() {
    let (base, _) = token_server(false).await;
    let (s, _) = session(&base, Mechanism::Oauthbearer, "refresh-0");
    let (port, seen) = imap_server(valid("access-1"), None).await;
    check_login(&imap(port, Login::oauth(s))).await.unwrap();
    assert_eq!(
        *seen.lock().unwrap(),
        [format!(
            "OAUTHBEARER n,a=me@example.org,\x01host=127.0.0.1\x01port={port}\x01auth=Bearer access-1\x01\x01"
        )]
    );
}

#[tokio::test]
async fn imap_renews_a_refused_token_once() {
    let (base, forms) = token_server(false).await;
    let (s, _) = session(&base, Mechanism::Xoauth2, "refresh-0");
    // The token in hand looks good for an hour, but the server says
    // AUTHENTICATIONFAILED (revoked early, a password change…).
    s.seed("stale".to_owned().into(), 3600).await;
    let (port, seen) = imap_server(valid("access-1"), None).await;
    check_login(&imap(port, Login::oauth(s))).await.unwrap();
    let tried: Vec<_> = seen.lock().unwrap().clone();
    assert_eq!(tried.len(), 2);
    assert!(tried[0].contains("Bearer stale"));
    assert!(tried[1].contains("Bearer access-1"));
    assert_eq!(forms.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn imap_gives_up_after_the_second_refusal() {
    let (base, forms) = token_server(false).await;
    let (s, _) = session(&base, Mechanism::Xoauth2, "refresh-0");
    let (port, seen) = imap_server(valid("nothing-works"), None).await;
    let err = check_login(&imap(port, Login::oauth(s))).await.unwrap_err();
    assert!(matches!(err, ImapError::Auth), "{err:?}");
    // One token, one renewal, one more try: no loop.
    assert_eq!(seen.lock().unwrap().len(), 2);
    assert_eq!(forms.lock().unwrap().len(), 2);
}

fn smtp(port: u16, login: Login) -> SmtpConfig {
    SmtpConfig {
        host: "127.0.0.1".into(),
        port,
        security: Security::None,
        username: "me@example.org".into(),
        login,
    }
}

fn draft() -> Draft {
    Draft {
        from_email: "me@example.org".into(),
        to: vec!["luca@example.org".into()],
        subject: "Signed in with a token".into(),
        body: "Hello.".into(),
        ..Draft::default()
    }
}

#[tokio::test]
async fn smtp_sends_with_xoauth2_and_oauthbearer() {
    for (mechanism, name) in [
        (Mechanism::Xoauth2, "XOAUTH2"),
        (Mechanism::Oauthbearer, "OAUTHBEARER"),
    ] {
        let (base, _) = token_server(false).await;
        let (s, _) = session(&base, mechanism, "refresh-0");
        let (port, seen, delivered) = smtp_server(valid("access-1"), None).await;
        send(&smtp(port, Login::oauth(s)), &ready(&draft()).unwrap())
            .await
            .unwrap();
        let seen = seen.lock().unwrap().clone();
        assert_eq!(seen.len(), 1);
        assert!(seen[0].starts_with(name), "{seen:?}");
        assert!(seen[0].contains("auth=Bearer access-1\x01"));
        assert!(delivered.lock().unwrap()[0].contains("Subject: Signed in with a token"));
    }
}

#[tokio::test]
async fn smtp_renews_a_refused_token_once_then_stops() {
    let (base, forms) = token_server(false).await;
    let (s, _) = session(&base, Mechanism::Xoauth2, "refresh-0");
    s.seed("stale".to_owned().into(), 3600).await;
    let (port, seen, delivered) = smtp_server(valid("access-1"), None).await;
    let login = Login::oauth(s);
    send(&smtp(port, login.clone()), &ready(&draft()).unwrap())
        .await
        .unwrap();
    assert_eq!(seen.lock().unwrap().len(), 2);
    assert_eq!(delivered.lock().unwrap().len(), 1);

    let (port, seen, delivered) = smtp_server(valid("nothing-works"), None).await;
    let err = send(&smtp(port, login), &ready(&draft()).unwrap())
        .await
        .unwrap_err();
    assert!(matches!(err, SendError::Auth), "{err:?}");
    assert_eq!(seen.lock().unwrap().len(), 2);
    assert!(delivered.lock().unwrap().is_empty());
    // One renewal for each refusal, never more.
    assert_eq!(forms.lock().unwrap().len(), 2);
}

#[tokio::test]
async fn passwords_still_sign_in() {
    let (port, _) = imap_server(valid("unused"), None).await;
    check_login(&imap(port, "test".into())).await.unwrap();
    let err = check_login(&imap(port, "wrong".into())).await.unwrap_err();
    assert!(matches!(err, ImapError::Auth), "{err:?}");
    let (port, _, delivered) = smtp_server(valid("unused"), None).await;
    send(&smtp(port, "test".into()), &ready(&draft()).unwrap())
        .await
        .unwrap();
    assert_eq!(delivered.lock().unwrap().len(), 1);
}
