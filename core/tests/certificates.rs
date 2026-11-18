//! A server with a certificate nobody vouches for: refused with what it
//! says, accepted once the person trusts that exact certificate, and
//! refused again, never quietly, when the server shows another one.

mod support;

use std::sync::{Arc, Mutex};

use piuma_core::auth::Login;
use piuma_core::cert::{self, CertInfo};
use piuma_core::imap::{check_login, ImapConfig, ImapError};
use piuma_core::jmap::{Client, JmapConfig, JmapError};
use piuma_core::smtp::{ready, send, Draft, SendError, SmtpConfig};
use piuma_core::tls::{Pin, Problem};
use piuma_core::Security;
use support::{https_401, imap_server, smtp_server, Shown, FIRST_CERT, SECOND_CERT};

fn imap(port: u16, pins: Vec<Pin>) -> ImapConfig {
    ImapConfig {
        host: "localhost".into(),
        port,
        security: Security::Tls,
        username: "me".into(),
        login: Login::from("test").with_pins(pins),
    }
}

fn pin(der: &[u8]) -> Pin {
    Pin {
        host: "localhost".into(),
        sha256: cert::sha256(der),
    }
}

fn shown(cert: &'static [u8]) -> Shown {
    Arc::new(Mutex::new(cert))
}

#[tokio::test]
async fn a_self_signed_certificate_is_trusted_only_as_it_was() {
    let showing = shown(FIRST_CERT);
    let (port, _) = imap_server(Arc::default(), Some(showing.clone())).await;

    // Unknown: refused, with what the person needs to decide.
    let err = check_login(&imap(port, vec![])).await.unwrap_err();
    let ImapError::Certificate(refused) = err else {
        panic!("{err:?}");
    };
    assert_eq!(refused.problem, Problem::Untrusted);
    assert_eq!(refused.host, "localhost");
    assert_eq!(refused.cert, CertInfo::read(FIRST_CERT));
    assert_eq!(refused.cert.subject, "CN=localhost, O=Piuma Test");
    assert!(!err_is_offline(&ImapError::Certificate(refused.clone())));

    // Trusted, by its fingerprint: in.
    check_login(&imap(port, vec![pin(FIRST_CERT)]))
        .await
        .unwrap();

    // A pin for another server changes nothing here.
    let elsewhere = Pin {
        host: "mail.example.org".into(),
        sha256: cert::sha256(FIRST_CERT),
    };
    assert!(check_login(&imap(port, vec![elsewhere])).await.is_err());

    // The server now shows another certificate: refused, said so.
    *showing.lock().unwrap() = SECOND_CERT;
    let err = check_login(&imap(port, vec![pin(FIRST_CERT)]))
        .await
        .unwrap_err();
    let ImapError::Certificate(refused) = err else {
        panic!("{err:?}");
    };
    assert_eq!(refused.problem, Problem::Changed);
    assert_eq!(
        refused.cert.fingerprint,
        CertInfo::read(SECOND_CERT).fingerprint
    );
    assert!(refused.to_string().contains("not the one trusted"));
}

fn err_is_offline(e: &ImapError) -> bool {
    e.is_offline()
}

fn smtp(port: u16, pins: Vec<Pin>) -> SmtpConfig {
    SmtpConfig {
        host: "localhost".into(),
        port,
        security: Security::Tls,
        username: "me".into(),
        login: Login::from("test").with_pins(pins),
    }
}

#[tokio::test]
async fn smtp_follows_the_same_trust() {
    let showing = shown(FIRST_CERT);
    let (port, _, delivered) = smtp_server(Arc::default(), Some(showing.clone())).await;
    let message = ready(&Draft {
        from_email: "me@example.org".into(),
        to: vec!["luca@example.org".into()],
        subject: "Over a pinned certificate".into(),
        ..Draft::default()
    })
    .unwrap();

    let err = send(&smtp(port, vec![]), &message).await.unwrap_err();
    let SendError::Certificate(refused) = err else {
        panic!("{err:?}");
    };
    assert_eq!(refused.problem, Problem::Untrusted);
    assert!(delivered.lock().unwrap().is_empty());

    send(&smtp(port, vec![pin(FIRST_CERT)]), &message)
        .await
        .unwrap();
    assert_eq!(delivered.lock().unwrap().len(), 1);

    *showing.lock().unwrap() = SECOND_CERT;
    let err = send(&smtp(port, vec![pin(FIRST_CERT)]), &message)
        .await
        .unwrap_err();
    assert!(
        matches!(&err, SendError::Certificate(r) if r.problem == Problem::Changed),
        "{err:?}"
    );
    assert!(err.needs_person() && !err.is_offline());
    assert_eq!(delivered.lock().unwrap().len(), 1);
}

#[tokio::test]
async fn jmap_follows_the_same_trust() {
    let showing = shown(FIRST_CERT);
    let port = https_401(showing.clone()).await;
    let cfg = |pins| JmapConfig {
        session_url: format!("https://localhost:{port}/jmap/session"),
        username: "me".into(),
        password: "test".into(),
        pins,
    };
    let err = Client::open(&cfg(vec![])).await.err().unwrap();
    assert!(
        matches!(&err, JmapError::Certificate(r) if r.problem == Problem::Untrusted),
        "{err:?}"
    );
    // Trusted: the TLS goes through, and the server's own answer comes.
    let err = Client::open(&cfg(vec![pin(FIRST_CERT)]))
        .await
        .err()
        .unwrap();
    assert!(matches!(err, JmapError::Auth), "{err:?}");
    *showing.lock().unwrap() = SECOND_CERT;
    let err = Client::open(&cfg(vec![pin(FIRST_CERT)]))
        .await
        .err()
        .unwrap();
    assert!(
        matches!(&err, JmapError::Certificate(r) if r.problem == Problem::Changed),
        "{err:?}"
    );
}
