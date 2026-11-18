//! How every connection checks the server's certificate: the system's
//! own check, except on Android, where it needs the app to hand it Java's
//! context first; there Mozilla's list of authorities is used instead.
//!
//! Mail servers of small offices often have a certificate nobody vouches
//! for: made by the server itself, expired, or for another name. The
//! person can then trust that exact certificate for that account, by its
//! SHA-256 fingerprint ([`Pin`]). Mail connections ([`connect`]) accept a
//! pinned certificate only when it is byte for byte the one trusted; a
//! different one is refused with [`Problem::Changed`], never let through.
//! A certificate the system trusts on its own is always accepted.
//!
//! The servers of big providers (Microsoft, Google, the presets in
//! [`crate::autoconfig`]) always have a certificate an authority vouches
//! for: one that isn't means someone is in the way, so for them pins are
//! ignored and the refusal is [`Problem::Provider`], which can't be
//! trusted ([`can_pin`]).

use std::fmt;
use std::sync::{Arc, Mutex};

use tokio::io::{AsyncRead, AsyncWrite};
use tokio_rustls::rustls::client::danger::{
    HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier,
};
use tokio_rustls::rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use tokio_rustls::rustls::{
    CertificateError, ClientConfig, DigitallySignedStruct, Error as TlsError, SignatureScheme,
};
use tokio_rustls::TlsConnector;

use crate::cert::{self, CertInfo};

/// Names the cryptography every TLS connection in the process uses
/// (aws-lc-rs), before the first one. Without it rustls refuses to pick
/// when another library also brings its `ring` (Velopack on Windows), and
/// every connection panics. Safe to call any number of times.
pub fn use_one_crypto_provider() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let _ = tokio_rustls::rustls::crypto::aws_lc_rs::default_provider().install_default();
    });
}

#[cfg(not(target_os = "android"))]
pub fn client_config() -> Result<ClientConfig, String> {
    use rustls_platform_verifier::ConfigVerifierExt;
    use_one_crypto_provider();
    ClientConfig::with_platform_verifier().map_err(|e| e.to_string())
}

#[cfg(target_os = "android")]
pub fn client_config() -> Result<ClientConfig, String> {
    use_one_crypto_provider();
    let roots = tokio_rustls::rustls::RootCertStore {
        roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
    };
    Ok(ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth())
}

/// The system's verifier, as [`client_config`] uses it.
fn system_verifier() -> Result<Arc<dyn ServerCertVerifier>, String> {
    use_one_crypto_provider();
    let provider = tokio_rustls::rustls::crypto::CryptoProvider::get_default()
        .cloned()
        .unwrap_or_else(|| Arc::new(tokio_rustls::rustls::crypto::aws_lc_rs::default_provider()));
    #[cfg(not(target_os = "android"))]
    {
        rustls_platform_verifier::Verifier::new(provider)
            .map(|v| Arc::new(v) as Arc<dyn ServerCertVerifier>)
            .map_err(|e| e.to_string())
    }
    #[cfg(target_os = "android")]
    {
        let roots = tokio_rustls::rustls::RootCertStore {
            roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
        };
        tokio_rustls::rustls::client::WebPkiServerVerifier::builder_with_provider(
            Arc::new(roots),
            provider,
        )
        .build()
        .map(|v| v as Arc<dyn ServerCertVerifier>)
        .map_err(|e| e.to_string())
    }
}

/// A web client that checks certificates the same way.
pub fn http_client() -> reqwest::ClientBuilder {
    let builder = reqwest::Client::builder();
    match client_config() {
        Ok(config) => builder.tls_backend_preconfigured(config),
        Err(_) => builder,
    }
}

/// A certificate the person chose to trust for one server of an account.
#[derive(Clone, PartialEq, Eq)]
pub struct Pin {
    /// The server's host name, as in the account's settings.
    pub host: String,
    /// SHA-256 of the whole certificate.
    pub sha256: [u8; 32],
}

impl fmt::Debug for Pin {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Pin({}, {})",
            self.host,
            cert::fingerprint_text(&self.sha256)
        )
    }
}

impl Pin {
    /// The pin for `host` among `pins`, ignoring case.
    pub fn for_host<'a>(pins: &'a [Pin], host: &str) -> Option<&'a Pin> {
        pins.iter().find(|p| p.host.eq_ignore_ascii_case(host))
    }
}

/// Why a server's certificate was refused, in words people can act on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Problem {
    /// Nobody the system trusts signed it, as with one the server made
    /// itself.
    Untrusted,
    /// Past its end date, or not valid yet.
    Expired,
    /// Made for another server name.
    NameMismatch,
    /// Not the certificate the person trusted for this server earlier.
    Changed,
    /// Revoked, or wrong in a way that trusting it can't fix. Also a
    /// trusted certificate that was revoked since.
    Invalid,
    /// Refused for a big provider's server, whose certificates authorities
    /// always vouch for: never trusted by hand.
    Provider,
}

impl Problem {
    /// Whether the person may choose to trust the certificate anyway.
    pub fn can_trust(self) -> bool {
        !matches!(self, Problem::Invalid | Problem::Provider)
    }
}

/// Whether a certificate may be trusted by hand for `host`: not for the
/// servers of providers the engine knows.
pub fn can_pin(host: &str) -> bool {
    !crate::autoconfig::well_known_host(host)
}

/// A refused certificate: why, and what it says, for the person to decide.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Refused {
    pub host: String,
    pub problem: Problem,
    pub cert: CertInfo,
}

impl Refused {
    /// As the app reads it: `host`, `problem` (untrusted, expired,
    /// nameMismatch, changed, invalid, provider), `fingerprint`, `subject`,
    /// `issuer` and `notAfter`.
    pub fn json(&self) -> String {
        let problem = match self.problem {
            Problem::Untrusted => "untrusted",
            Problem::Expired => "expired",
            Problem::NameMismatch => "nameMismatch",
            Problem::Changed => "changed",
            Problem::Invalid => "invalid",
            Problem::Provider => "provider",
        };
        serde_json::json!({
            "host": self.host,
            "problem": problem,
            "fingerprint": self.cert.fingerprint,
            "subject": self.cert.subject,
            "issuer": self.cert.issuer,
            "notAfter": self.cert.not_after,
        })
        .to_string()
    }
}

impl fmt::Display for Refused {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let why = match self.problem {
            Problem::Untrusted => "is not signed by a trusted authority",
            Problem::Expired => "is expired or not valid yet",
            Problem::NameMismatch => "is for another server name",
            Problem::Changed => "is not the one trusted for this account",
            Problem::Invalid => "is not valid",
            Problem::Provider => {
                "is not vouched for, and a provider's server always has one that is"
            }
        };
        write!(
            f,
            "the certificate of {} {why} (SHA-256 {})",
            self.host, self.cert.fingerprint
        )
    }
}

/// Why a secure connection failed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Failure {
    /// The certificate was refused: the person can look at it.
    Certificate(Box<Refused>),
    /// The server never finished the handshake (the watchdog's timeout).
    Stalled,
    /// Anything else: the connection broke, no common cipher…
    Other(String),
}

impl fmt::Display for Failure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Failure::Certificate(r) => r.fmt(f),
            Failure::Stalled => f.write_str("the server did not finish the secure handshake"),
            Failure::Other(e) => f.write_str(e),
        }
    }
}

/// How a rustls refusal reads to people.
pub fn problem_of(e: &CertificateError) -> Problem {
    use CertificateError as C;
    match e {
        C::UnknownIssuer | C::BadSignature => Problem::Untrusted,
        C::Expired | C::ExpiredContext { .. } | C::NotValidYet | C::NotValidYetContext { .. } => {
            Problem::Expired
        }
        C::NotValidForName | C::NotValidForNameContext { .. } => Problem::NameMismatch,
        // The platform verifiers report some refusals as their own words.
        C::Other(other) => {
            let text = other.to_string().to_ascii_lowercase();
            if text.contains("expired") {
                Problem::Expired
            } else if text.contains("name") {
                Problem::NameMismatch
            } else if text.contains("revoked") {
                Problem::Invalid
            } else {
                Problem::Untrusted
            }
        }
        _ => Problem::Invalid,
    }
}

/// The system's check, then the pin when the system says no.
#[derive(Debug)]
struct Pinned {
    system: Arc<dyn ServerCertVerifier>,
    /// Trusted certificates, by the server name they were trusted for.
    pins: Vec<Pin>,
    /// The last certificate refused, for the caller to explain.
    refused: Refusals,
}

/// Where a pinned verifier leaves the certificate it refused, for the
/// connection's error to show: shared with the web clients it serves.
#[derive(Debug, Clone, Default)]
pub struct Refusals(Arc<Mutex<Option<Refused>>>);

impl Refusals {
    /// The last certificate refused, taken.
    pub fn take(&self) -> Option<Refused> {
        self.0.lock().unwrap_or_else(|e| e.into_inner()).take()
    }

    fn put(&self, refused: Refused) {
        *self.0.lock().unwrap_or_else(|e| e.into_inner()) = Some(refused);
    }
}

/// The name a connection asked for, as pins are kept.
fn name_of(server_name: &ServerName<'_>) -> String {
    match server_name {
        ServerName::DnsName(d) => d.as_ref().to_owned(),
        ServerName::IpAddress(ip) => std::net::IpAddr::from(*ip).to_string(),
        _ => String::new(),
    }
}

impl ServerCertVerifier for Pinned {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        intermediates: &[CertificateDer<'_>],
        server_name: &ServerName<'_>,
        ocsp_response: &[u8],
        now: UnixTime,
    ) -> Result<ServerCertVerified, TlsError> {
        let result = self.system.verify_server_cert(
            end_entity,
            intermediates,
            server_name,
            ocsp_response,
            now,
        );
        let error = match result {
            Ok(ok) => return Ok(ok),
            Err(e) => e,
        };
        let host = name_of(server_name);
        let TlsError::InvalidCertificate(c) = &error else {
            return Err(error);
        };
        let problem = if !can_pin(&host) {
            // A big provider's server: pins don't count.
            Problem::Provider
        } else {
            let seen = cert::sha256(end_entity.as_ref());
            match (problem_of(c), Pin::for_host(&self.pins, &host)) {
                // Revoked or broken: trusting it earlier doesn't help, and
                // trusting it again wouldn't either.
                (Problem::Invalid, _) => Problem::Invalid,
                // The exact certificate the person trusted.
                (_, Some(pin)) if crate::oauth::same(&pin.sha256, &seen) => {
                    return Ok(ServerCertVerified::assertion());
                }
                (_, Some(_)) => Problem::Changed,
                (problem, None) => problem,
            }
        };
        self.refused.put(Refused {
            host,
            problem,
            cert: CertInfo::read(end_entity.as_ref()),
        });
        Err(error)
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        self.system.verify_tls12_signature(message, cert, dss)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        self.system.verify_tls13_signature(message, cert, dss)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.system.supported_verify_schemes()
    }
}

/// A client configuration that trusts what the system trusts, and the
/// certificates in `pins` for their servers, leaving refusals in `refused`.
fn pinned_config(pins: &[Pin], refused: &Refusals) -> Result<ClientConfig, String> {
    let verifier = Arc::new(Pinned {
        system: system_verifier()?,
        pins: pins.to_vec(),
        refused: refused.clone(),
    });
    Ok(ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth())
}

/// A web client for an account's own servers (JMAP, CalDAV): the system's
/// check and the certificates the person trusted for them. A certificate
/// it refuses is left in the [`Refusals`], for the error to show.
pub fn http_client_pinned(pins: &[Pin]) -> (reqwest::ClientBuilder, Refusals) {
    let refused = Refusals::default();
    let builder = reqwest::Client::builder();
    let builder = match pinned_config(pins, &refused) {
        Ok(config) => builder.tls_backend_preconfigured(config),
        Err(_) => builder,
    };
    (builder, refused)
}

/// Opens TLS over `stream` to `host`, trusting the certificate in `pins`
/// for it, if any, besides the system's own check.
pub async fn connect<T>(
    host: &str,
    pins: &[Pin],
    stream: T,
) -> Result<tokio_rustls::client::TlsStream<T>, Failure>
where
    T: AsyncRead + AsyncWrite + Unpin,
{
    let refused = Refusals::default();
    let config = pinned_config(pins, &refused).map_err(Failure::Other)?;
    let name = ServerName::try_from(host.to_owned()).map_err(|e| Failure::Other(e.to_string()))?;
    TlsConnector::from(Arc::new(config))
        .connect(name, stream)
        .await
        .map_err(|e| {
            match refused.take() {
                Some(refused) => Failure::Certificate(Box::new(refused)),
                // A handshake the server never finished is no certificate
                // problem.
                None if crate::watchdog::stalled(&e) => Failure::Stalled,
                None => Failure::Other(e.to_string()),
            }
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    // The tests build rustls with `ring` as well as aws-lc-rs (see the
    // dev-dependencies), as on Windows, where Velopack adds it.
    #[test]
    fn connections_work_with_two_crypto_libraries_built_in() {
        assert!(super::client_config().is_ok());
        assert!(super::http_client().build().is_ok());
        assert!(super::system_verifier().is_ok());
    }

    #[test]
    fn refusals_read_as_what_people_can_act_on() {
        use CertificateError as C;
        assert_eq!(problem_of(&C::UnknownIssuer), Problem::Untrusted);
        assert_eq!(problem_of(&C::Expired), Problem::Expired);
        assert_eq!(problem_of(&C::NotValidYet), Problem::Expired);
        assert_eq!(problem_of(&C::NotValidForName), Problem::NameMismatch);
        assert_eq!(problem_of(&C::Revoked), Problem::Invalid);
        assert!(!Problem::Invalid.can_trust());
        assert!(!Problem::Provider.can_trust());
        assert!(Problem::Changed.can_trust());
    }

    /// A system check that always says `no`.
    #[derive(Debug)]
    struct Refuses(CertificateError);

    impl ServerCertVerifier for Refuses {
        fn verify_server_cert(
            &self,
            _: &CertificateDer<'_>,
            _: &[CertificateDer<'_>],
            _: &ServerName<'_>,
            _: &[u8],
            _: UnixTime,
        ) -> Result<ServerCertVerified, TlsError> {
            Err(TlsError::InvalidCertificate(self.0.clone()))
        }

        fn verify_tls12_signature(
            &self,
            _: &[u8],
            _: &CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, TlsError> {
            Ok(HandshakeSignatureValid::assertion())
        }

        fn verify_tls13_signature(
            &self,
            _: &[u8],
            _: &CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, TlsError> {
            Ok(HandshakeSignatureValid::assertion())
        }

        fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
            Vec::new()
        }
    }

    /// What the pinned check makes of `system`'s refusal of a certificate
    /// trusted for `host`: accepted (None), or the problem shown.
    fn verdict(system: CertificateError, host: &str) -> Option<Problem> {
        let der = include_bytes!("../tests/fixtures/tls/first.der");
        let refused = Refusals::default();
        let pinned = Pinned {
            system: Arc::new(Refuses(system)),
            pins: vec![Pin {
                host: host.into(),
                sha256: cert::sha256(der),
            }],
            refused: refused.clone(),
        };
        let name = ServerName::try_from(host.to_owned()).unwrap();
        match pinned.verify_server_cert(
            &CertificateDer::from(der.to_vec()),
            &[],
            &name,
            &[],
            UnixTime::now(),
        ) {
            Ok(_) => None,
            Err(_) => Some(refused.take().unwrap().problem),
        }
    }

    #[test]
    fn a_trusted_certificate_revoked_since_is_invalid_not_changed() {
        // Self-signed and trusted: in.
        assert_eq!(
            verdict(CertificateError::UnknownIssuer, "mail.studio.it"),
            None
        );
        // Revoked since: invalid, which can't be trusted again.
        let revoked = verdict(CertificateError::Revoked, "mail.studio.it");
        assert_eq!(revoked, Some(Problem::Invalid));
        assert!(!revoked.unwrap().can_trust());
        // A big provider's server: the pin doesn't count.
        assert_eq!(
            verdict(CertificateError::UnknownIssuer, "imap.gmail.com"),
            Some(Problem::Provider)
        );
    }

    #[test]
    fn big_providers_servers_are_never_pinned() {
        assert!(!can_pin("outlook.office365.com"));
        assert!(!can_pin("imap.gmail.com"));
        assert!(!can_pin("smtp.mail.me.com"));
        assert!(can_pin("mail.studio.it"));
        assert!(can_pin("localhost"));
    }

    #[test]
    fn pins_match_their_host_only() {
        let pins = [Pin {
            host: "Mail.Studio.it".into(),
            sha256: [1; 32],
        }];
        assert!(Pin::for_host(&pins, "mail.studio.it").is_some());
        assert!(Pin::for_host(&pins, "smtp.studio.it").is_none());
        assert!(!format!("{:?}", pins[0]).is_empty());
    }
}
