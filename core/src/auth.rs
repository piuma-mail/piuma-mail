//! How an account proves who it is to its servers: a password, or an
//! OAuth access token sent with SASL `XOAUTH2` or `OAUTHBEARER`; and the
//! certificates the person chose to trust for its servers.
//!
//! A [`Login`] is cheap to clone and shared by every connection of an
//! account. With OAuth, each connection asks it for a token when it opens
//! ([`Login::credential`]), so a watcher that reconnects for days never
//! uses one that ran out; when a server still refuses one, the connection
//! asks for a new token once ([`Login::renew`]) and tries again, and a
//! second refusal is a refusal of the account.

use std::fmt;
use std::sync::Arc;

use base64::Engine as _;
use zeroize::Zeroizing;

use crate::oauth::{Mechanism, Session, TokenError};
use crate::tls::Pin;

#[derive(Clone)]
enum Secret {
    Password(Arc<Zeroizing<String>>),
    OAuth(Arc<Session>),
}

/// What an account signs in with.
#[derive(Clone)]
pub struct Login {
    secret: Secret,
    /// Certificates trusted for the account's servers, by host.
    pub pins: Vec<Pin>,
}

impl fmt::Debug for Login {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let kind = match &self.secret {
            Secret::Password(_) => "password",
            Secret::OAuth(_) => "oauth",
        };
        f.debug_struct("Login")
            .field("kind", &kind)
            .field("pins", &self.pins)
            .finish_non_exhaustive()
    }
}

impl From<&str> for Login {
    fn from(password: &str) -> Self {
        Login::password(password)
    }
}

impl From<String> for Login {
    fn from(password: String) -> Self {
        Login::password(&password)
    }
}

/// What one connection sends.
pub enum Credential {
    Password(Zeroizing<String>),
    Token {
        mechanism: Mechanism,
        token: Zeroizing<String>,
    },
}

impl Login {
    pub fn password(password: &str) -> Self {
        Login {
            secret: Secret::Password(Arc::new(Zeroizing::new(password.to_owned()))),
            pins: Vec::new(),
        }
    }

    pub fn oauth(session: Arc<Session>) -> Self {
        Login {
            secret: Secret::OAuth(session),
            pins: Vec::new(),
        }
    }

    pub fn with_pins(mut self, pins: Vec<Pin>) -> Self {
        self.pins = pins;
        self
    }

    /// The password, for an account that has one.
    pub fn password_text(&self) -> Option<&str> {
        match &self.secret {
            Secret::Password(p) => Some(p.as_str()),
            Secret::OAuth(_) => None,
        }
    }

    pub fn is_oauth(&self) -> bool {
        matches!(self.secret, Secret::OAuth(_))
    }

    /// The OAuth sign-in behind it, if any.
    pub fn session(&self) -> Option<&Arc<Session>> {
        match &self.secret {
            Secret::OAuth(s) => Some(s),
            Secret::Password(_) => None,
        }
    }

    /// What to send now: the password, or a token good for a while yet.
    pub async fn credential(&self) -> Result<Credential, TokenError> {
        match &self.secret {
            Secret::Password(p) => Ok(Credential::Password(Zeroizing::new(p.to_string()))),
            Secret::OAuth(s) => Ok(Credential::Token {
                mechanism: s.mechanism(),
                token: s.access_token().await?,
            }),
        }
    }

    /// After a server refused the credential: a new token, worth one more
    /// try. None for a password, which a retry can't mend.
    pub async fn renew(&self) -> Option<Result<Credential, TokenError>> {
        match &self.secret {
            Secret::Password(_) => None,
            Secret::OAuth(s) => Some(s.renew().await.map(|token| Credential::Token {
                mechanism: s.mechanism(),
                token,
            })),
        }
    }
}

/// The client's first message for `mechanism` (before base64): XOAUTH2 as
/// Google and Microsoft document it, OAUTHBEARER as RFC 7628 section 3.1.
pub fn sasl_initial(
    mechanism: Mechanism,
    user: &str,
    token: &str,
    host: &str,
    port: u16,
) -> Zeroizing<String> {
    Zeroizing::new(match mechanism {
        Mechanism::Xoauth2 => format!("user={user}\x01auth=Bearer {token}\x01\x01"),
        Mechanism::Oauthbearer => {
            // The GS2 header escapes `,` and `=` in the name (RFC 5801).
            let name = user.replace('=', "=3D").replace(',', "=2C");
            format!("n,a={name},\x01host={host}\x01port={port}\x01auth=Bearer {token}\x01\x01")
        }
    })
}

/// The same, base64, as SMTP and ManageSieve send it.
pub fn sasl_initial_base64(
    mechanism: Mechanism,
    user: &str,
    token: &str,
    host: &str,
    port: u16,
) -> Zeroizing<String> {
    let raw = sasl_initial(mechanism, user, token, host, port);
    Zeroizing::new(base64::engine::general_purpose::STANDARD.encode(raw.as_bytes()))
}

/// The mechanism's name on the wire.
pub fn sasl_name(mechanism: Mechanism) -> &'static str {
    match mechanism {
        Mechanism::Xoauth2 => "XOAUTH2",
        Mechanism::Oauthbearer => "OAUTHBEARER",
    }
}

/// The reply to a server's error challenge, which both mechanisms answer
/// with an empty response (XOAUTH2) or a single ^A (RFC 7628 3.2.3), for
/// the server to end with a NO.
pub fn sasl_abort(mechanism: Mechanism) -> &'static [u8] {
    match mechanism {
        Mechanism::Xoauth2 => b"",
        Mechanism::Oauthbearer => b"\x01",
    }
}

/// async-imap's side of `AUTHENTICATE`: the initial response at the first
/// challenge, the abort at any other (the server's error report).
pub(crate) struct ImapSasl {
    pub mechanism: Mechanism,
    pub initial: Zeroizing<String>,
    pub sent: bool,
}

impl async_imap::Authenticator for ImapSasl {
    type Response = Vec<u8>;

    fn process(&mut self, _challenge: &[u8]) -> Self::Response {
        if self.sent {
            return sasl_abort(self.mechanism).to_vec();
        }
        self.sent = true;
        self.initial.as_bytes().to_vec()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xoauth2_matches_the_documented_form() {
        let raw = sasl_initial(
            Mechanism::Xoauth2,
            "someone@example.com",
            "ya29.vF9dft4",
            "",
            0,
        );
        assert_eq!(
            raw.as_str(),
            "user=someone@example.com\x01auth=Bearer ya29.vF9dft4\x01\x01"
        );
        // Google's example in its XOAUTH2 documentation.
        assert_eq!(
            sasl_initial_base64(Mechanism::Xoauth2, "someone@example.com", "ya29.vF9dft4qmTc2Nvb3RlckBhdHRhdmlzdGEuY29tCg", "", 0).as_str(),
            "dXNlcj1zb21lb25lQGV4YW1wbGUuY29tAWF1dGg9QmVhcmVyIHlhMjkudkY5ZGZ0NHFtVGMyTnZiM1JsY2tCaGRIUmhkbWx6ZEdFdVkyOXRDZwEB"
        );
    }

    #[test]
    fn oauthbearer_matches_rfc_7628() {
        let raw = sasl_initial(
            Mechanism::Oauthbearer,
            "user@example.com",
            "vF9dft4qmTc2Nvb3RlckBhbHRhdmlzdGEuY29tCg==",
            "server.example.com",
            143,
        );
        assert_eq!(
            raw.as_str(),
            "n,a=user@example.com,\x01host=server.example.com\x01port=143\x01auth=Bearer vF9dft4qmTc2Nvb3RlckBhbHRhdmlzdGEuY29tCg==\x01\x01"
        );
        let odd = sasl_initial(Mechanism::Oauthbearer, "a,b=c", "t", "h", 1);
        assert!(odd.starts_with("n,a=a=2Cb=3Dc,"));
    }

    #[test]
    fn a_login_never_shows_its_secret() {
        let login = Login::from("hunter2");
        assert_eq!(login.password_text(), Some("hunter2"));
        assert!(!login.is_oauth());
        assert!(!format!("{login:?}").contains("hunter2"));
    }

    #[test]
    fn imap_authenticator_aborts_after_the_first_answer() {
        use async_imap::Authenticator;
        let mut a = ImapSasl {
            mechanism: Mechanism::Oauthbearer,
            initial: Zeroizing::new("first".into()),
            sent: false,
        };
        assert_eq!(a.process(b""), b"first");
        assert_eq!(a.process(b"{\"status\":\"invalid_token\"}"), b"\x01");
    }
}
