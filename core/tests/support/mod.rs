//! Small servers that live inside the tests: an OAuth token endpoint, and
//! IMAP and SMTP servers that take OAuth tokens or passwords, in the clear
//! or over TLS with a test certificate. Nothing reaches a real provider.

#![allow(dead_code)]

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use base64::Engine as _;
use piuma_core::oauth::{Mechanism, Provider};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio_rustls::rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use tokio_rustls::rustls::ServerConfig;
use tokio_rustls::TlsAcceptor;

pub const FIRST_CERT: &[u8] = include_bytes!("../fixtures/tls/first.der");
const FIRST_KEY: &[u8] = include_bytes!("../fixtures/tls/first.key.der");
pub const SECOND_CERT: &[u8] = include_bytes!("../fixtures/tls/second.der");
const SECOND_KEY: &[u8] = include_bytes!("../fixtures/tls/second.key.der");

fn b64(data: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(data)
}

fn unb64(text: &str) -> String {
    String::from_utf8_lossy(
        &base64::engine::general_purpose::STANDARD
            .decode(text.trim())
            .unwrap_or_default(),
    )
    .into_owned()
}

/// What the token endpoint was asked, form by form.
pub type Forms = Arc<Mutex<Vec<HashMap<String, String>>>>;

/// A token endpoint. A refresh token "revoked" is refused for good; any
/// other gets `access-<n>`, and with `rotate` a new refresh token too.
/// A code gets `access-code` and `refresh-0`.
pub async fn token_server(rotate: bool) -> (String, Forms) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let forms: Forms = Arc::default();
    let seen = forms.clone();
    tokio::spawn(async move {
        while let Ok((mut tcp, _)) = listener.accept().await {
            let mut data = Vec::new();
            let mut buf = [0u8; 4096];
            let body = loop {
                let n = tcp.read(&mut buf).await.unwrap_or(0);
                if n == 0 {
                    break None;
                }
                data.extend_from_slice(&buf[..n]);
                let text = String::from_utf8_lossy(&data).into_owned();
                if let Some(end) = text.find("\r\n\r\n") {
                    let length = text[..end]
                        .lines()
                        .find_map(|l| {
                            let (k, v) = l.split_once(':')?;
                            k.eq_ignore_ascii_case("content-length")
                                .then(|| v.trim().parse::<usize>().ok())?
                        })
                        .unwrap_or(0);
                    if data.len() >= end + 4 + length {
                        break Some(text[end + 4..end + 4 + length].to_owned());
                    }
                }
            };
            let Some(body) = body else { continue };
            let form: HashMap<String, String> = url::form_urlencoded::parse(body.as_bytes())
                .into_owned()
                .collect();
            let n = {
                let mut seen = seen.lock().unwrap();
                seen.push(form.clone());
                seen.len()
            };
            let (status, reply) = match form.get("grant_type").map(String::as_str) {
                Some("authorization_code") => (
                    "200 OK",
                    r#"{"access_token":"access-code","refresh_token":"refresh-0","expires_in":3600,"token_type":"Bearer"}"#.to_owned(),
                ),
                Some("refresh_token") if form.get("refresh_token").map(String::as_str) == Some("revoked") => (
                    "400 Bad Request",
                    "{\"error\":\"invalid_grant\",\"error_description\":\"AADSTS70000: revoked\\r\\nTrace ID: 1\"}".to_owned(),
                ),
                Some("refresh_token") if rotate => (
                    "200 OK",
                    format!(r#"{{"access_token":"access-{n}","refresh_token":"refresh-{n}","expires_in":"3600"}}"#),
                ),
                Some("refresh_token") => (
                    "200 OK",
                    format!(r#"{{"access_token":"access-{n}","expires_in":3600}}"#),
                ),
                _ => ("400 Bad Request", r#"{"error":"unsupported_grant_type"}"#.to_owned()),
            };
            let response = format!(
                "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{reply}",
                reply.len()
            );
            let _ = tcp.write_all(response.as_bytes()).await;
        }
    });
    (format!("http://127.0.0.1:{port}"), forms)
}

/// A provider whose endpoints are the test's own.
pub fn provider(base: &str, mechanism: Mechanism) -> Provider {
    let mechanism = match mechanism {
        Mechanism::Xoauth2 => "xoauth2",
        Mechanism::Oauthbearer => "oauthbearer",
    };
    serde_json::from_value(serde_json::json!({
        "id": "test",
        "name": "Test",
        "authorize_url": format!("{base}/authorize"),
        "token_url": format!("{base}/token"),
        "revoke_url": null,
        "tenant": null,
        "scopes": ["mail"],
        "mechanism": mechanism,
        "imap": { "host": "127.0.0.1", "port": 993, "security": "tls" },
        "smtp": { "host": "127.0.0.1", "port": 465, "security": "tls" },
        "android_redirect": "{app_scheme}://oauth",
    }))
    .unwrap()
}

/// The token a server takes now; anything else is refused.
pub type Valid = Arc<Mutex<String>>;
/// What clients sent to sign in, decoded.
pub type Seen = Arc<Mutex<Vec<String>>>;

/// The certificate a TLS server shows: the first or the second one.
pub type Shown = Arc<Mutex<&'static [u8]>>;

fn acceptor(cert: &'static [u8]) -> TlsAcceptor {
    piuma_core::tls::use_one_crypto_provider();
    let key = if cert == FIRST_CERT {
        FIRST_KEY
    } else {
        SECOND_KEY
    };
    let config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(
            vec![CertificateDer::from(cert.to_vec())],
            PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key.to_vec())),
        )
        .unwrap();
    TlsAcceptor::from(Arc::new(config))
}

/// An IMAP server. It takes the password "test", or the token in
/// `valid` with XOAUTH2 or OAUTHBEARER. With `tls`, every connection
/// starts with TLS showing that certificate.
pub async fn imap_server(valid: Valid, tls: Option<Shown>) -> (u16, Seen) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let seen: Seen = Arc::default();
    let record = seen.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let (valid, record, tls) = (valid.clone(), record.clone(), tls.clone());
            tokio::spawn(async move {
                match tls {
                    Some(shown) => {
                        let cert = *shown.lock().unwrap();
                        if let Ok(stream) = acceptor(cert).accept(tcp).await {
                            imap_session(stream, valid, record).await;
                        }
                    }
                    None => imap_session(tcp, valid, record).await,
                }
            });
        }
    });
    (port, seen)
}

async fn imap_session<S: AsyncRead + AsyncWrite + Unpin>(stream: S, valid: Valid, seen: Seen) {
    let (r, mut w) = tokio::io::split(stream);
    let mut lines = BufReader::new(r).lines();
    let caps = "IMAP4rev1 AUTH=XOAUTH2 AUTH=OAUTHBEARER";
    if w.write_all(format!("* OK [CAPABILITY {caps}] ready\r\n").as_bytes()).await.is_err() {
        return;
    }
    while let Ok(Some(line)) = lines.next_line().await {
        let mut parts = line.splitn(3, ' ');
        let tag = parts.next().unwrap_or("*").to_owned();
        let command = parts.next().unwrap_or("").to_ascii_uppercase();
        let rest = parts.next().unwrap_or("").to_owned();
        let reply = match command.as_str() {
            "CAPABILITY" => format!("* CAPABILITY {caps}\r\n{tag} OK done\r\n"),
            "LOGIN" => {
                if rest.ends_with(" test") || rest.ends_with(" \"test\"") {
                    format!("{tag} OK logged in\r\n")
                } else {
                    format!("{tag} NO [AUTHENTICATIONFAILED] Invalid credentials\r\n")
                }
            }
            "AUTHENTICATE" => {
                let _ = w.write_all(b"+ \r\n").await;
                let Ok(Some(answer)) = lines.next_line().await else {
                    return;
                };
                let decoded = unb64(&answer);
                seen.lock().unwrap().push(format!("{} {decoded}", rest.trim()));
                let token = valid.lock().unwrap().clone();
                if decoded.contains(&format!("auth=Bearer {token}\x01")) {
                    format!("{tag} OK authenticated\r\n")
                } else {
                    let error = b64(br#"{"status":"401","schemes":"bearer","scope":"mail"}"#);
                    let _ = w.write_all(format!("+ {error}\r\n").as_bytes()).await;
                    let _ = lines.next_line().await;
                    format!("{tag} NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)\r\n")
                }
            }
            "LOGOUT" => {
                let _ = w.write_all(format!("* BYE\r\n{tag} OK bye\r\n").as_bytes()).await;
                return;
            }
            _ => format!("{tag} OK\r\n"),
        };
        if w.write_all(reply.as_bytes()).await.is_err() {
            return;
        }
    }
}

/// An SMTP server that takes the password "test", or the token in
/// `valid` with AUTH XOAUTH2 or OAUTHBEARER, and keeps what it accepts.
/// With `tls`, every connection starts with TLS (port 465 style).
pub async fn smtp_server(valid: Valid, tls: Option<Shown>) -> (u16, Seen, Seen) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let seen: Seen = Arc::default();
    let delivered: Seen = Arc::default();
    let (record, mail) = (seen.clone(), delivered.clone());
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            let (valid, record, mail, tls) = (valid.clone(), record.clone(), mail.clone(), tls.clone());
            tokio::spawn(async move {
                match tls {
                    Some(shown) => {
                        let cert = *shown.lock().unwrap();
                        if let Ok(stream) = acceptor(cert).accept(tcp).await {
                            smtp_session(stream, valid, record, mail).await;
                        }
                    }
                    None => smtp_session(tcp, valid, record, mail).await,
                }
            });
        }
    });
    (port, seen, delivered)
}

async fn smtp_session<S: AsyncRead + AsyncWrite + Unpin>(
    stream: S,
    valid: Valid,
    seen: Seen,
    delivered: Seen,
) {
    let (r, mut w) = tokio::io::split(stream);
    let mut lines = BufReader::new(r).lines();
    if w.write_all(b"220 test ESMTP\r\n").await.is_err() {
        return;
    }
    let mut authed = false;
    while let Ok(Some(line)) = lines.next_line().await {
        let upper = line.to_ascii_uppercase();
        let reply: String = if upper.starts_with("EHLO") {
            "250-test\r\n250 AUTH PLAIN LOGIN XOAUTH2 OAUTHBEARER\r\n".into()
        } else if upper.starts_with("AUTH PLAIN") {
            // base64("\0user\0test") ends with "AHRlc3Q=" for any user.
            authed = line.ends_with("AHRlc3Q=");
            if authed { "235 ok\r\n" } else { "535 5.7.8 bad credentials\r\n" }.into()
        } else if upper.starts_with("AUTH XOAUTH2 ") || upper.starts_with("AUTH OAUTHBEARER ") {
            let mut words = line.split(' ');
            let mechanism = words.nth(1).unwrap_or("").to_owned();
            let decoded = unb64(words.next().unwrap_or(""));
            seen.lock().unwrap().push(format!("{mechanism} {decoded}"));
            let token = valid.lock().unwrap().clone();
            if decoded.contains(&format!("auth=Bearer {token}\x01")) {
                authed = true;
                "235 2.7.0 accepted\r\n".into()
            } else {
                let error = b64(br#"{"status":"400","schemes":"Bearer","scope":"mail"}"#);
                let _ = w.write_all(format!("334 {error}\r\n").as_bytes()).await;
                let _ = lines.next_line().await;
                "535 5.7.8 Username and Password not accepted\r\n".into()
            }
        } else if upper.starts_with("MAIL FROM") {
            if authed { "250 ok\r\n" } else { "530 5.7.0 authentication required\r\n" }.into()
        } else if upper == "DATA" {
            let _ = w.write_all(b"354 go on\r\n").await;
            let mut data = String::new();
            while let Ok(Some(l)) = lines.next_line().await {
                if l == "." {
                    break;
                }
                data.push_str(&l);
                data.push('\n');
            }
            delivered.lock().unwrap().push(data);
            "250 queued\r\n".into()
        } else if upper == "QUIT" {
            let _ = w.write_all(b"221 bye\r\n").await;
            return;
        } else {
            "250 ok\r\n".into()
        };
        if w.write_all(reply.as_bytes()).await.is_err() {
            return;
        }
    }
}
