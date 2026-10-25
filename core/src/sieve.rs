//! ManageSieve (RFC 5804): a small client for the scripts that filter mail
//! on the server, which is where the away message lives for IMAP accounts.
//!
//! Only what the away message needs: the capabilities, STARTTLS, a PLAIN
//! login with the account's IMAP user name and password, and listing,
//! reading, uploading, activating and deleting scripts.

use std::fmt;
use std::sync::Arc;
use std::time::Duration;

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::TlsConnector;

use crate::model::Security;

/// The port ManageSieve listens on.
pub const PORT: u16 = 4190;
/// How long any one step may take before the server counts as away.
const TIMEOUT: Duration = Duration::from_secs(15);
/// The longest response line or literal taken, against a runaway server.
const MAX_RESPONSE: usize = 1 << 20;

#[derive(Clone)]
pub struct SieveConfig {
    pub host: String,
    pub port: u16,
    /// `StartTls` for real servers; `None` only for local test servers.
    pub security: Security,
    pub username: String,
    pub password: String,
}

impl fmt::Debug for SieveConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SieveConfig")
            .field("host", &self.host)
            .field("port", &self.port)
            .field("security", &self.security)
            .field("username", &self.username)
            .finish_non_exhaustive()
    }
}

impl SieveConfig {
    /// The account's IMAP server and login, on the ManageSieve port.
    /// None for other accounts.
    pub fn for_account(account: &crate::model::Account, password: &str) -> Option<Self> {
        let imap = crate::imap::ImapConfig::for_account(account, password)?;
        Some(SieveConfig {
            host: imap.host,
            port: PORT,
            // ManageSieve always starts in the clear and upgrades; a test
            // server without encryption stays without.
            security: match imap.security {
                Security::None => Security::None,
                _ => Security::StartTls,
            },
            username: imap.username,
            password: imap.password,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum SieveError {
    #[error("could not reach {host}: {source}")]
    Connect {
        host: String,
        source: std::io::Error,
    },
    #[error("the filter server took too long to answer")]
    Timeout,
    #[error("secure connection failed: {0}")]
    Tls(String),
    #[error("the server rejected the user name or password")]
    Auth,
    /// No STARTTLS, no PLAIN login, or no vacation: nothing to do here.
    #[error("the server does not offer this: {0}")]
    Unsupported(String),
    /// A NO to a command, with the server's words.
    #[error("the server refused: {0}")]
    Refused(String),
    #[error("ManageSieve: {0}")]
    Protocol(String),
    #[error("ManageSieve connection: {0}")]
    Io(#[from] std::io::Error),
}

impl SieveError {
    /// The server could not be reached, rather than refused.
    pub fn is_offline(&self) -> bool {
        matches!(
            self,
            SieveError::Connect { .. } | SieveError::Timeout | SieveError::Io(_)
        )
    }
}

pub type Result<T> = std::result::Result<T, SieveError>;

/// One item of a response line.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Token {
    /// A bare word: OK, NO, ACTIVE, a number.
    Atom(String),
    /// A quoted string or a literal, unescaped.
    Str(String),
    /// A response code in parentheses, e.g. `(QUOTA/MAXSIZE)`, as written.
    Code(String),
}

impl Token {
    fn atom(&self) -> Option<&str> {
        match self {
            Token::Atom(a) => Some(a),
            _ => None,
        }
    }

    fn text(&self) -> &str {
        match self {
            Token::Atom(s) | Token::Str(s) | Token::Code(s) => s,
        }
    }
}

/// Reads one response line from the front of `buf`: its tokens and how
/// many bytes it took. None while the line (or a literal in it) is not
/// all there yet.
pub fn parse_line(buf: &[u8]) -> Result<Option<(Vec<Token>, usize)>> {
    let mut tokens = Vec::new();
    let mut i = 0;
    let bad = |what: &str| SieveError::Protocol(what.to_owned());
    loop {
        let Some(&b) = buf.get(i) else {
            return Ok(None);
        };
        match b {
            b' ' => i += 1,
            b'\r' => {
                return match buf.get(i + 1) {
                    None => Ok(None),
                    Some(b'\n') => Ok(Some((tokens, i + 2))),
                    Some(_) => Err(bad("stray CR")),
                };
            }
            b'\n' => return Ok(Some((tokens, i + 1))),
            b'"' => {
                let mut out = Vec::new();
                i += 1;
                loop {
                    match buf.get(i) {
                        None => return Ok(None),
                        Some(b'"') => {
                            i += 1;
                            break;
                        }
                        Some(b'\\') => match buf.get(i + 1) {
                            None => return Ok(None),
                            Some(&c) => {
                                out.push(c);
                                i += 2;
                            }
                        },
                        Some(b'\r' | b'\n') => return Err(bad("line break in a quoted string")),
                        Some(&c) => {
                            out.push(c);
                            i += 1;
                        }
                    }
                }
                tokens.push(Token::Str(String::from_utf8_lossy(&out).into_owned()));
            }
            b'{' => {
                let Some(close) = buf[i..].iter().position(|&c| c == b'}') else {
                    return if buf.len() - i > 24 {
                        Err(bad("unterminated literal length"))
                    } else {
                        Ok(None)
                    };
                };
                let spec =
                    std::str::from_utf8(&buf[i + 1..i + close]).map_err(|_| bad("literal"))?;
                let n: usize = spec
                    .trim_end_matches('+')
                    .parse()
                    .map_err(|_| bad("literal length"))?;
                if n > MAX_RESPONSE {
                    return Err(bad("literal too long"));
                }
                let start = i + close + 1;
                match (buf.get(start), buf.get(start + 1)) {
                    (Some(b'\r'), Some(b'\n')) => {}
                    (None, _) | (Some(b'\r'), None) => return Ok(None),
                    _ => return Err(bad("literal not followed by a line break")),
                }
                let body = start + 2;
                if buf.len() < body + n {
                    return Ok(None);
                }
                tokens.push(Token::Str(
                    String::from_utf8_lossy(&buf[body..body + n]).into_owned(),
                ));
                i = body + n;
            }
            b'(' => {
                let Some(close) = buf[i..].iter().position(|&c| c == b')') else {
                    return Ok(None);
                };
                tokens.push(Token::Code(
                    String::from_utf8_lossy(&buf[i + 1..i + close]).into_owned(),
                ));
                i += close + 1;
            }
            _ => {
                let end = buf[i..]
                    .iter()
                    .position(|&c| matches!(c, b' ' | b'\r' | b'\n' | b'(' | b'"' | b'{'))
                    .map_or(buf.len(), |p| i + p);
                if end == buf.len() {
                    return Ok(None);
                }
                tokens.push(Token::Atom(
                    String::from_utf8_lossy(&buf[i..end]).into_owned(),
                ));
                i = end;
            }
        }
    }
}

/// How a command ended.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Status {
    /// OK, NO or BYE.
    pub kind: String,
    pub code: Option<String>,
    pub text: String,
}

impl Status {
    pub fn ok(&self) -> bool {
        self.kind == "OK"
    }

    fn from_line(line: &[Token]) -> Option<Self> {
        let kind = line.first()?.atom()?.to_ascii_uppercase();
        if !matches!(kind.as_str(), "OK" | "NO" | "BYE") {
            return None;
        }
        let code = line.iter().skip(1).find_map(|t| match t {
            Token::Code(c) => Some(c.clone()),
            _ => None,
        });
        let text = line
            .iter()
            .skip(1)
            .find_map(|t| match t {
                Token::Str(s) => Some(s.clone()),
                _ => None,
            })
            .unwrap_or_default();
        Some(Status { kind, code, text })
    }
}

/// What the server says it can do.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Capabilities {
    pub implementation: String,
    /// Sieve extensions, lower case: "vacation", "date", "relational"...
    pub sieve: Vec<String>,
    /// SASL mechanisms, upper case.
    pub sasl: Vec<String>,
    pub starttls: bool,
}

impl Capabilities {
    /// From the lines before the OK of a greeting or of CAPABILITY.
    pub fn from_lines(lines: &[Vec<Token>]) -> Self {
        let mut caps = Capabilities::default();
        for line in lines {
            let Some(name) = line.first() else { continue };
            let value = line.get(1).map(Token::text).unwrap_or_default();
            match name.text().to_ascii_uppercase().as_str() {
                "IMPLEMENTATION" => caps.implementation = value.to_owned(),
                "SIEVE" => {
                    caps.sieve = value
                        .split_whitespace()
                        .map(str::to_ascii_lowercase)
                        .collect()
                }
                "SASL" => {
                    caps.sasl = value
                        .split_whitespace()
                        .map(str::to_ascii_uppercase)
                        .collect()
                }
                "STARTTLS" => caps.starttls = true,
                _ => {}
            }
        }
        caps
    }

    pub fn has(&self, extension: &str) -> bool {
        self.sieve.iter().any(|e| e == extension)
    }

    /// Whether a script can say "from this day to that day" itself
    /// (RFC 5260 `currentdate`, compared with RFC 5231 `:value`).
    pub fn dates(&self) -> bool {
        self.has("date") && self.has("relational")
    }
}

/// A script on the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Script {
    pub name: String,
    pub active: bool,
}

trait Io: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> Io for T {}

/// A logged-in ManageSieve connection.
pub struct Client {
    stream: Box<dyn Io>,
    buf: Vec<u8>,
    caps: Capabilities,
}

impl Client {
    /// Connects, upgrades to TLS, and logs in with PLAIN.
    pub async fn open(cfg: &SieveConfig) -> Result<Self> {
        tokio::time::timeout(TIMEOUT, Self::connect(cfg))
            .await
            .map_err(|_| SieveError::Timeout)?
    }

    async fn connect(cfg: &SieveConfig) -> Result<Self> {
        let tcp = TcpStream::connect((cfg.host.as_str(), cfg.port))
            .await
            .map_err(|source| SieveError::Connect {
                host: cfg.host.clone(),
                source,
            })?;
        tcp.set_nodelay(true).ok();
        let mut client = Client {
            stream: Box::new(tcp),
            buf: Vec::new(),
            caps: Capabilities::default(),
        };
        let (lines, status) = client.response().await?;
        if !status.ok() {
            return Err(SieveError::Refused(status.text));
        }
        client.caps = Capabilities::from_lines(&lines);
        match cfg.security {
            Security::None => {}
            Security::Tls | Security::StartTls => {
                if !client.caps.starttls {
                    // A password never goes in the clear.
                    return Err(SieveError::Unsupported("STARTTLS".into()));
                }
                client.command(b"STARTTLS\r\n").await?;
                let tcp = std::mem::replace(&mut client.stream, Box::new(tokio::io::empty()));
                client.stream = Box::new(tls(&cfg.host, tcp).await?);
                client.buf.clear();
                // RFC 5804 2.2: the capabilities again, now over TLS.
                let (lines, status) = client.response().await?;
                if status.ok() {
                    client.caps = Capabilities::from_lines(&lines);
                }
            }
        }
        if !client.caps.sasl.iter().any(|m| m == "PLAIN") {
            return Err(SieveError::Unsupported("PLAIN login".into()));
        }
        let pair = format!("\0{}\0{}", cfg.username, cfg.password);
        let initial = {
            use base64::Engine;
            base64::engine::general_purpose::STANDARD.encode(pair)
        };
        let mut auth = b"AUTHENTICATE \"PLAIN\" ".to_vec();
        auth.extend_from_slice(&quoted(&initial));
        auth.extend_from_slice(b"\r\n");
        client.send(&auth).await?;
        let (_, status) = client.response().await?;
        if !status.ok() {
            return Err(SieveError::Auth);
        }
        Ok(client)
    }

    /// What the server said it can do, after TLS.
    pub fn capabilities(&self) -> &Capabilities {
        &self.caps
    }

    /// The scripts on the server, and which one is active.
    pub async fn list(&mut self) -> Result<Vec<Script>> {
        let lines = self.command(b"LISTSCRIPTS\r\n").await?;
        Ok(lines
            .iter()
            .filter_map(|line| {
                let name = match line.first()? {
                    Token::Str(s) => s.clone(),
                    _ => return None,
                };
                let active = line
                    .get(1)
                    .and_then(Token::atom)
                    .is_some_and(|a| a.eq_ignore_ascii_case("ACTIVE"));
                Some(Script { name, active })
            })
            .collect())
    }

    /// A script's text, or None when there is no such script.
    pub async fn get(&mut self, name: &str) -> Result<Option<String>> {
        let mut command = b"GETSCRIPT ".to_vec();
        command.extend_from_slice(&quoted(name));
        command.extend_from_slice(b"\r\n");
        self.send(&command).await?;
        let (lines, status) = self.response().await?;
        if !status.ok() {
            // NO (NONEXISTENT), or a server that says it in words only.
            return if status.kind == "NO" {
                Ok(None)
            } else {
                Err(SieveError::Refused(status.text))
            };
        }
        Ok(lines.into_iter().flatten().find_map(|t| match t {
            Token::Str(s) => Some(s),
            _ => None,
        }))
    }

    /// Uploads a script under `name`, replacing one of that name. The
    /// server checks it first and refuses it whole if it is wrong.
    pub async fn put(&mut self, name: &str, script: &str) -> Result<()> {
        let mut command = b"PUTSCRIPT ".to_vec();
        command.extend_from_slice(&quoted(name));
        command.extend_from_slice(format!(" {{{}+}}\r\n", script.len()).as_bytes());
        command.extend_from_slice(script.as_bytes());
        command.extend_from_slice(b"\r\n");
        self.command(&command).await.map(drop)
    }

    /// Makes `name` the active script; "" leaves none active.
    pub async fn set_active(&mut self, name: &str) -> Result<()> {
        let mut command = b"SETACTIVE ".to_vec();
        command.extend_from_slice(&quoted(name));
        command.extend_from_slice(b"\r\n");
        self.command(&command).await.map(drop)
    }

    pub async fn delete(&mut self, name: &str) -> Result<()> {
        let mut command = b"DELETESCRIPT ".to_vec();
        command.extend_from_slice(&quoted(name));
        command.extend_from_slice(b"\r\n");
        self.command(&command).await.map(drop)
    }

    pub async fn logout(mut self) {
        if self.send(b"LOGOUT\r\n").await.is_ok() {
            let _ = tokio::time::timeout(Duration::from_secs(2), self.response()).await;
        }
    }

    /// Sends a command and reads its response: the lines before OK.
    async fn command(&mut self, command: &[u8]) -> Result<Vec<Vec<Token>>> {
        self.send(command).await?;
        let (lines, status) = self.response().await?;
        if status.ok() {
            Ok(lines)
        } else {
            Err(SieveError::Refused(if status.text.is_empty() {
                status.kind
            } else {
                status.text
            }))
        }
    }

    async fn send(&mut self, bytes: &[u8]) -> Result<()> {
        tokio::time::timeout(TIMEOUT, async {
            self.stream.write_all(bytes).await?;
            self.stream.flush().await
        })
        .await
        .map_err(|_| SieveError::Timeout)??;
        Ok(())
    }

    /// Lines up to and including OK, NO or BYE.
    async fn response(&mut self) -> Result<(Vec<Vec<Token>>, Status)> {
        let mut lines = Vec::new();
        loop {
            let line = self.line().await?;
            if let Some(status) = Status::from_line(&line) {
                return Ok((lines, status));
            }
            lines.push(line);
        }
    }

    async fn line(&mut self) -> Result<Vec<Token>> {
        loop {
            if let Some((tokens, used)) = parse_line(&self.buf)? {
                self.buf.drain(..used);
                return Ok(tokens);
            }
            if self.buf.len() > MAX_RESPONSE + 64 {
                return Err(SieveError::Protocol("response too long".into()));
            }
            let mut chunk = [0u8; 4096];
            let n = tokio::time::timeout(TIMEOUT, self.stream.read(&mut chunk))
                .await
                .map_err(|_| SieveError::Timeout)??;
            if n == 0 {
                return Err(SieveError::Io(std::io::ErrorKind::UnexpectedEof.into()));
            }
            self.buf.extend_from_slice(&chunk[..n]);
        }
    }
}

/// A quoted string, as ManageSieve writes one.
pub fn quoted(s: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len() + 2);
    out.push(b'"');
    for b in s.bytes() {
        if b == b'"' || b == b'\\' {
            out.push(b'\\');
        }
        out.push(b);
    }
    out.push(b'"');
    out
}

async fn tls<T>(host: &str, stream: T) -> Result<tokio_rustls::client::TlsStream<T>>
where
    T: AsyncRead + AsyncWrite + Unpin,
{
    let config = crate::tls::client_config().map_err(SieveError::Tls)?;
    let name = ServerName::try_from(host.to_owned()).map_err(|e| SieveError::Tls(e.to_string()))?;
    TlsConnector::from(Arc::new(config))
        .connect(name, stream)
        .await
        .map_err(|e| SieveError::Tls(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn all(input: &[u8]) -> Vec<Vec<Token>> {
        let mut out = Vec::new();
        let mut at = 0;
        while let Some((line, used)) = parse_line(&input[at..]).unwrap() {
            out.push(line);
            at += used;
        }
        assert_eq!(at, input.len(), "left over: {:?}", &input[at..]);
        out
    }

    #[test]
    fn reads_a_greeting() {
        let lines = all(b"\"IMPLEMENTATION\" \"Dovecot Pigeonhole\"\r\n\
            \"SIEVE\" \"fileinto reject envelope vacation date relational\"\r\n\
            \"NOTIFY\" \"mailto\"\r\n\
            \"SASL\" \"\"\r\n\
            \"STARTTLS\"\r\n\
            \"VERSION\" \"1.0\"\r\n\
            OK \"Dovecot ready.\"\r\n");
        assert_eq!(lines.len(), 7);
        let status = Status::from_line(&lines[6]).unwrap();
        assert!(status.ok());
        assert_eq!(status.text, "Dovecot ready.");
        let caps = Capabilities::from_lines(&lines[..6]);
        assert_eq!(caps.implementation, "Dovecot Pigeonhole");
        assert!(caps.starttls);
        assert!(caps.has("vacation"));
        assert!(caps.dates());
        assert!(caps.sasl.is_empty());

        let after = all(b"\"SIEVE\" \"Vacation\"\r\n\"SASL\" \"plain login\"\r\nOK\r\n");
        let caps = Capabilities::from_lines(&after[..2]);
        assert!(caps.has("vacation"));
        assert!(!caps.dates());
        assert_eq!(caps.sasl, ["PLAIN", "LOGIN"]);
        assert!(!caps.starttls);
    }

    #[test]
    fn reads_literals_and_escapes() {
        let lines = all(b"\"summer \\\"script\\\"\" ACTIVE\r\n{11}\r\nwith\r\nbreak\r\n{6+}\r\nplain!\r\nOK\r\n");
        assert_eq!(
            lines[0],
            [
                Token::Str("summer \"script\"".into()),
                Token::Atom("ACTIVE".into())
            ]
        );
        assert_eq!(lines[1], [Token::Str("with\r\nbreak".into())]);
        assert_eq!(lines[2], [Token::Str("plain!".into())]);
        assert!(Status::from_line(&lines[3]).unwrap().ok());
    }

    #[test]
    fn waits_for_the_whole_line() {
        assert_eq!(parse_line(b"OK \"Hal").unwrap(), None);
        assert_eq!(parse_line(b"OK").unwrap(), None);
        assert_eq!(parse_line(b"{10}\r\nabc").unwrap(), None);
        assert_eq!(parse_line(b"{10").unwrap(), None);
        assert_eq!(parse_line(b"OK\r").unwrap(), None);
        assert!(parse_line(b"{x}\r\n").is_err());
    }

    #[test]
    fn reads_refusals_with_codes() {
        let lines = all(b"NO (NONEXISTENT) \"There is no script by that name\"\r\n");
        let status = Status::from_line(&lines[0]).unwrap();
        assert_eq!(status.kind, "NO");
        assert_eq!(status.code.as_deref(), Some("NONEXISTENT"));
        assert_eq!(status.text, "There is no script by that name");

        let lines = all(b"NO (QUOTA/MAXSIZE) {12}\r\nToo big, sir\r\n");
        let status = Status::from_line(&lines[0]).unwrap();
        assert_eq!(status.code.as_deref(), Some("QUOTA/MAXSIZE"));
        assert_eq!(status.text, "Too big, sir");

        let lines = all(b"BYE \"Too many errors\"\r\n");
        assert!(!Status::from_line(&lines[0]).unwrap().ok());
        assert_eq!(Status::from_line(&[Token::Str("OK".into())]), None);
    }

    #[test]
    fn quotes_names() {
        assert_eq!(quoted("piuma-away"), b"\"piuma-away\"");
        assert_eq!(quoted("a\"b\\c"), b"\"a\\\"b\\\\c\"");
    }

    #[test]
    fn follows_the_imap_login() {
        let account = crate::model::Account {
            id: crate::AccountId(1),
            name: "Work".into(),
            email: "matteo@studio.it".into(),
            sender_name: String::new(),
            color: String::new(),
            kind: crate::AccountKind::Imap {
                imap: crate::Server {
                    host: "mail.studio.it".into(),
                    port: 993,
                    security: Security::Tls,
                },
                smtp: crate::Server {
                    host: "mail.studio.it".into(),
                    port: 465,
                    security: Security::Tls,
                },
                username: "matteo".into(),
            },
        };
        let cfg = SieveConfig::for_account(&account, "pw").unwrap();
        assert_eq!(cfg.host, "mail.studio.it");
        assert_eq!(cfg.port, 4190);
        assert_eq!(cfg.security, Security::StartTls);
        assert_eq!(cfg.username, "matteo");
        assert_eq!(cfg.password, "pw");
        assert!(!format!("{cfg:?}").contains("pw"));
    }
}
