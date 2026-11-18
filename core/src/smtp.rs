//! SMTP: turn a draft into a message and hand it to the account's server.
//!
//! Sending is two steps: the SMTP server accepts the message, then a copy goes
//! into the account's Sent folder over IMAP (except on servers that file it
//! themselves, like Gmail). A failure in the second step never turns a sent
//! message into an error: the report says the copy is missing instead.

use std::fmt;
use std::time::Duration;

use lettre::message::header::{
    ContentTransferEncoding, ContentType, Header, HeaderName, HeaderValue,
};
use lettre::message::{Attachment, Body, Mailbox, MultiPart, SinglePart};
use lettre::transport::smtp::authentication::{Credentials, Mechanism as LettreMechanism};
use lettre::transport::smtp::client::{AsyncSmtpConnection, AsyncTokioStream};
use lettre::transport::smtp::extension::ClientId;
use lettre::Message;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf};
use tokio::net::TcpStream;

use crate::auth::{sasl_abort, sasl_initial_base64, sasl_name, Credential, Login};
use crate::oauth::{Mechanism, TokenError};

use crate::rich::{self, Mark};
use crate::signature::{self, Signature, LOGO_CID};

use crate::imap::{Connection, ImapConfig};
use crate::model::{Account, AccountKind, Security};

#[derive(Clone)]
pub struct SmtpConfig {
    pub host: String,
    pub port: u16,
    pub security: Security,
    pub username: String,
    /// The password or OAuth sign-in, and the certificates trusted.
    pub login: Login,
}

impl fmt::Debug for SmtpConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SmtpConfig")
            .field("host", &self.host)
            .field("port", &self.port)
            .field("security", &self.security)
            .field("username", &self.username)
            .finish_non_exhaustive()
    }
}

impl SmtpConfig {
    /// The SMTP settings of an account, or None for non-IMAP accounts.
    pub fn for_account(account: &Account, login: &Login) -> Option<Self> {
        match &account.kind {
            AccountKind::Imap { smtp, username, .. } => Some(SmtpConfig {
                host: smtp.host.clone(),
                port: smtp.port,
                security: smtp.security,
                username: username.clone(),
                login: login.clone(),
            }),
            AccountKind::Jmap { .. } => None,
        }
    }

    /// Servers that put a copy in Sent on their own; appending would
    /// duplicate it.
    fn files_sent_itself(&self) -> bool {
        let host = self.host.to_ascii_lowercase();
        host.ends_with("gmail.com") || host.ends_with("googlemail.com")
    }
}

/// What the person wrote.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Draft {
    pub from_name: String,
    pub from_email: String,
    pub to: Vec<String>,
    pub cc: Vec<String>,
    pub bcc: Vec<String>,
    pub subject: String,
    pub body: String,
    /// Message-ID of the message being answered, with angle brackets.
    pub in_reply_to: Option<String>,
    /// The thread so far, oldest first, with angle brackets.
    pub references: Vec<String>,
    pub files: Vec<OutgoingFile>,
    /// Added after the person's text, above any quoted message. With one,
    /// the email also gets an HTML version.
    pub signature: Option<Signature>,
    /// When it goes, in Unix seconds, for mail sent later; now when None.
    pub date: Option<i64>,
    /// An answer to an invite: the iTIP REPLY that goes beside the text,
    /// as a `text/calendar` part the organizer's calendar reads.
    pub calendar: Option<String>,
    /// Bold, italic and links over [body]; with them, or with a list or a
    /// quote in it, the email also gets an HTML version.
    pub marks: Vec<Mark>,
}

/// A file attached to a draft.
#[derive(Clone, Default, PartialEq, Eq)]
pub struct OutgoingFile {
    pub name: String,
    /// Content type, like "application/pdf".
    pub mime: String,
    pub data: Vec<u8>,
}

impl fmt::Debug for OutgoingFile {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{} ({}, {} bytes)",
            self.name,
            self.mime,
            self.data.len()
        )
    }
}

#[derive(Debug, thiserror::Error)]
pub enum SendError {
    #[error("“{0}” is not an email address")]
    Address(String),
    #[error("add at least one recipient")]
    NoRecipients,
    #[error("could not build the message: {0}")]
    Build(String),
    #[error("could not reach {host}: {detail}")]
    Connect { host: String, detail: String },
    #[error("the server rejected the user name or password")]
    Auth,
    /// The server's certificate was refused; the person may trust it.
    #[error("{0}")]
    Certificate(Box<crate::tls::Refused>),
    #[error("the server refused the message: {0}")]
    Rejected(String),
    /// The server did not take the message now (a 4xx: greylisting, an
    /// overload); it may well take it later, so the outbox keeps it and
    /// tries again in a later batch.
    #[error("the server deferred the message: {0}")]
    Deferred(String),
}

impl SendError {
    /// The server could not be reached: the message can wait in the
    /// outbox and go once the connection is back.
    pub fn is_offline(&self) -> bool {
        matches!(self, SendError::Connect { .. })
    }

    /// Only the person can mend it: a refused sign-in or certificate.
    pub fn needs_person(&self) -> bool {
        matches!(self, SendError::Auth | SendError::Certificate(_))
    }
}

pub type Result<T> = std::result::Result<T, SendError>;

/// A message built and ready to go, as it will reach the server: built
/// once, so a message sent later keeps its Message-ID and date.
#[derive(Clone, PartialEq, Eq)]
pub struct Ready {
    pub message_id: String,
    pub from: String,
    /// Every address it goes to, Bcc included.
    pub recipients: Vec<String>,
    /// The RFC 5322 text, without Bcc.
    pub raw: Vec<u8>,
}

impl fmt::Debug for Ready {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Ready")
            .field("message_id", &self.message_id)
            .field("recipients", &self.recipients)
            .field("bytes", &self.raw.len())
            .finish_non_exhaustive()
    }
}

/// Builds a draft into the message that will go out.
pub fn ready(draft: &Draft) -> Result<Ready> {
    let message = build(draft)?;
    let envelope = message.envelope();
    Ok(Ready {
        message_id: message
            .headers()
            .get_raw("Message-ID")
            .unwrap_or_default()
            .to_owned(),
        from: envelope
            .from()
            .map(ToString::to_string)
            .unwrap_or_else(|| draft.from_email.clone()),
        recipients: envelope.to().iter().map(ToString::to_string).collect(),
        raw: message.formatted(),
    })
}

/// What happened after a successful send.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendReport {
    pub message_id: String,
    /// Folder the copy went into, or None when no copy was filed.
    pub filed_in: Option<String>,
}

/// Builds the RFC 5322 message for a draft.
pub fn build(draft: &Draft) -> Result<Message> {
    if draft.to.is_empty() && draft.cc.is_empty() && draft.bcc.is_empty() {
        return Err(SendError::NoRecipients);
    }
    assemble(draft, false)
}

/// Builds the copy of an unfinished draft kept in the Drafts folder: it
/// may have no recipients yet, an address still being typed is left out,
/// Bcc stays in, and the signature is added only when it goes.
pub fn build_unsent(draft: &Draft) -> Result<Message> {
    assemble(
        &Draft {
            signature: None,
            ..draft.clone()
        },
        true,
    )
}

fn assemble(draft: &Draft, unsent: bool) -> Result<Message> {
    let from = mailbox(&draft.from_name, &draft.from_email)?;
    let mut b = Message::builder()
        .from(from.clone())
        .subject(draft.subject.trim())
        .date(match draft.date {
            Some(at) => std::time::UNIX_EPOCH + std::time::Duration::from_secs(at.max(0) as u64),
            None => std::time::SystemTime::now(),
        })
        .message_id(None);
    let address = |a: &String| match parse(a) {
        Err(_) if unsent => Ok(None),
        other => other.map(Some),
    };
    let mut anyone = false;
    for a in &draft.to {
        if let Some(m) = address(a)? {
            b = b.to(m);
            anyone = true;
        }
    }
    for a in &draft.cc {
        if let Some(m) = address(a)? {
            b = b.cc(m);
            anyone = true;
        }
    }
    for a in &draft.bcc {
        if let Some(m) = address(a)? {
            b = b.bcc(m);
            anyone = true;
        }
    }
    if unsent {
        b = b.keep_bcc();
        if !anyone {
            // Never sent, but the builder wants someone to send it to.
            let envelope =
                lettre::address::Envelope::new(Some(from.email.clone()), vec![from.email.clone()])
                    .map_err(|e| SendError::Build(e.to_string()))?;
            b = b.envelope(envelope);
        }
    }
    if let Some(id) = &draft.in_reply_to {
        b = b.in_reply_to(id.clone());
    }
    if !draft.references.is_empty() {
        b = b.references(draft.references.join(" "));
    }
    let body = draft.body.replace("\r\n", "\n");
    let sig = draft.signature.as_ref().filter(|s| !s.lines().is_empty());
    let formatted = rich::is_formatted(signature::split_quote(&body).0, &draft.marks);
    if let Some(marks) =
        rich::encode(&draft.marks).filter(|m| unsent && formatted && m.len() <= rich::HEADER_MAX)
    {
        b = b.header(PiumaFormat(marks));
    }
    let content = match (sig, &draft.calendar) {
        (_, Some(ics)) => Content::Rich(
            MultiPart::alternative()
                .singlepart(SinglePart::plain(body))
                .singlepart(
                    SinglePart::builder()
                        .header(
                            ContentType::parse("text/calendar; charset=utf-8; method=REPLY")
                                .map_err(|e| SendError::Build(e.to_string()))?,
                        )
                        // Its lines are folded already, so it goes as it
                        // is: calendars read a plain part best.
                        .body(
                            Body::new_with_encoding(ics.clone(), ContentTransferEncoding::EightBit)
                                .unwrap_or_else(Body::new),
                        ),
                ),
        ),
        (None, None) if !formatted => Content::Plain(body),
        (sig, None) => Content::Rich(rich_body(&body, sig, &draft.marks, unsent)),
    };
    let built = if draft.files.is_empty() {
        match content {
            Content::Plain(text) => b.header(ContentType::TEXT_PLAIN).body(text),
            Content::Rich(rich) => b.multipart(rich),
        }
    } else {
        let mixed = match content {
            Content::Plain(text) => MultiPart::mixed().singlepart(SinglePart::plain(text)),
            Content::Rich(rich) => MultiPart::mixed().multipart(rich),
        };
        let mut mixed = mixed;
        for file in &draft.files {
            let kind = ContentType::parse(&file.mime)
                .unwrap_or_else(|_| ContentType::parse("application/octet-stream").unwrap());
            mixed = mixed.singlepart(
                Attachment::new(crate::imap::file_name(&file.name)).body(file.data.clone(), kind),
            );
        }
        b.multipart(mixed)
    };
    built.map_err(|e| SendError::Build(e.to_string()))
}

enum Content {
    Plain(String),
    Rich(MultiPart),
}

/// Where a saved draft keeps its bold, italic and links.
#[derive(Clone)]
struct PiumaFormat(String);

impl Header for PiumaFormat {
    fn name() -> HeaderName {
        HeaderName::new_from_ascii_str(rich::HEADER)
    }

    fn parse(s: &str) -> std::result::Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        Ok(Self(s.to_owned()))
    }

    fn display(&self) -> HeaderValue {
        HeaderValue::new(Self::name(), self.0.clone())
    }
}

/// The text with its formatting and the signature after it (above any
/// quote), in both versions: plain text, and HTML with the logo inside
/// the message. A draft kept [unsent] keeps its quote bars in the plain
/// text, so it opens again as it was written.
fn rich_body(body: &str, sig: Option<&Signature>, marks: &[Mark], unsent: bool) -> MultiPart {
    let (own, quote) = signature::split_quote(body);
    let own = own.trim_end();
    let gap = if quote.is_empty() { "" } else { "\n\n" };
    let own_text = if unsent {
        own.to_owned()
    } else {
        rich::plain(own)
    };
    let text = match sig {
        Some(sig) => format!("{own_text}\n\n{}{gap}{quote}", sig.text()),
        None => format!("{own_text}{gap}{quote}"),
    };
    let own_html = if rich::is_formatted(own, marks) {
        rich::to_html(own, marks)
    } else {
        signature::text_to_html(own)
    };
    let html = format!(
        "<div style=\"font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55\">{}{}{}</div>",
        own_html,
        sig.map(Signature::html).unwrap_or_default(),
        if quote.is_empty() {
            String::new()
        } else {
            format!(
                "<div style=\"margin-top:18px\">{}</div>",
                signature::text_to_html(quote.trim())
            )
        },
    );
    let html_part = SinglePart::html(html);
    let alternative = MultiPart::alternative().singlepart(SinglePart::plain(text));
    match sig.map(|s| (&s.logo, s.template)) {
        Some((Some(logo), signature::Template::Logo)) => {
            let kind = ContentType::parse(&logo.mime)
                .unwrap_or_else(|_| ContentType::parse("image/png").unwrap());
            alternative.multipart(MultiPart::related().singlepart(html_part).singlepart(
                Attachment::new_inline(LOGO_CID.to_string()).body(logo.data.clone(), kind),
            ))
        }
        _ => alternative.singlepart(html_part),
    }
}

fn mailbox(name: &str, email: &str) -> Result<Mailbox> {
    let addr = email
        .trim()
        .parse()
        .map_err(|_| SendError::Address(email.trim().to_owned()))?;
    let name = name.trim();
    Ok(Mailbox::new(
        (!name.is_empty()).then(|| name.to_owned()),
        addr,
    ))
}

/// Accepts "a@b.c" and "Name <a@b.c>".
fn parse(text: &str) -> Result<Mailbox> {
    text.trim()
        .parse()
        .map_err(|_| SendError::Address(text.trim().to_owned()))
}

/// Hands a message to the SMTP server.
pub async fn send(cfg: &SmtpConfig, ready: &Ready) -> Result<()> {
    let address = |a: &str| {
        a.parse::<lettre::Address>()
            .map_err(|_| SendError::Address(a.to_owned()))
    };
    let recipients = ready
        .recipients
        .iter()
        .map(|r| address(r))
        .collect::<Result<Vec<_>>>()?;
    let envelope = lettre::address::Envelope::new(Some(address(&ready.from)?), recipients)
        .map_err(|e| SendError::Build(e.to_string()))?;
    let mut conn = within(TIMEOUT, &cfg.host, connect(cfg)).await?;
    let sent = async {
        within(TIMEOUT, &cfg.host, sign_in(&mut conn, cfg)).await?;
        within(SEND_TIMEOUT, &cfg.host, async {
            conn.send(&envelope, &ready.raw)
                .await
                .map(|_| ())
                .map_err(|e| classify(&cfg.host, e))
        })
        .await
    }
    .await;
    if sent.is_ok() {
        let _ = conn.quit().await;
    } else {
        conn.abort().await;
    }
    sent
}

/// The longest wait for the server to connect, greet and sign in.
const TIMEOUT: Duration = Duration::from_secs(60);
/// The longest a message may take to go, attachments and all.
const SEND_TIMEOUT: Duration = Duration::from_secs(10 * 60);

async fn within<T>(
    limit: Duration,
    host: &str,
    work: impl std::future::Future<Output = Result<T>>,
) -> Result<T> {
    tokio::time::timeout(limit, work)
        .await
        .unwrap_or_else(|_| {
            Err(SendError::Connect {
                host: host.to_owned(),
                detail: "the server took too long to answer".into(),
            })
        })
}

/// A secure stream lettre can drive. The TLS is ours, as for IMAP, so a
/// certificate the person trusted for this server works here too, and a
/// refused one says why.
#[derive(Debug)]
struct Stream<S> {
    inner: S,
    /// Bytes to read before the stream's own: after STARTTLS the server
    /// sends no new greeting, but lettre reads one first.
    greeting: Vec<u8>,
}

impl<S: AsyncRead + Unpin> AsyncRead for Stream<S> {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        if !self.greeting.is_empty() {
            let n = self.greeting.len().min(buf.remaining());
            let rest = self.greeting.split_off(n);
            buf.put_slice(&self.greeting);
            self.greeting = rest;
            return std::task::Poll::Ready(Ok(()));
        }
        std::pin::Pin::new(&mut self.inner).poll_read(cx, buf)
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for Stream<S> {
    fn poll_write(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        std::pin::Pin::new(&mut self.inner).poll_write(cx, buf)
    }

    fn poll_flush(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

impl<S> AsyncTokioStream for Stream<S>
where
    S: AsyncRead + AsyncWrite + Unpin + Send + Sync + fmt::Debug,
{
    fn peer_addr(&self) -> std::io::Result<std::net::SocketAddr> {
        Err(std::io::ErrorKind::Unsupported.into())
    }
}

fn unreachable(host: &str, detail: impl fmt::Display) -> SendError {
    SendError::Connect {
        host: host.to_owned(),
        detail: detail.to_string(),
    }
}

/// Connects, greets and, but on local test servers, encrypts.
async fn connect(cfg: &SmtpConfig) -> Result<AsyncSmtpConnection> {
    let mut tcp = TcpStream::connect((cfg.host.as_str(), cfg.port))
        .await
        .map_err(|e| unreachable(&cfg.host, e))?;
    tcp.set_nodelay(true).ok();
    let hello = ClientId::default();
    let wrap = |e: crate::tls::Failure| match e {
        crate::tls::Failure::Certificate(r) => SendError::Certificate(r),
        crate::tls::Failure::Other(e) => unreachable(&cfg.host, e),
    };
    let stream: Box<dyn AsyncTokioStream> = match cfg.security {
        Security::None => Box::new(Stream {
            inner: tcp,
            greeting: Vec::new(),
        }),
        Security::Tls => Box::new(Stream {
            inner: crate::tls::connect(&cfg.host, &cfg.login.pins, tcp)
                .await
                .map_err(wrap)?,
            greeting: Vec::new(),
        }),
        Security::StartTls => {
            // The plain part by hand, then TLS of our own (RFC 3207).
            expect(&mut tcp, &cfg.host, None, "220").await?;
            let ehlo = expect(&mut tcp, &cfg.host, Some(&format!("EHLO {hello}")), "250").await?;
            if !ehlo
                .lines()
                .any(|l| l.get(4..).is_some_and(|w| w.trim().eq_ignore_ascii_case("STARTTLS")))
            {
                // Never a password in the clear.
                return Err(unreachable(&cfg.host, "the server does not offer STARTTLS"));
            }
            expect(&mut tcp, &cfg.host, Some("STARTTLS"), "220").await?;
            Box::new(Stream {
                inner: crate::tls::connect(&cfg.host, &cfg.login.pins, tcp)
                    .await
                    .map_err(wrap)?,
                greeting: b"220 encrypted\r\n".to_vec(),
            })
        }
    };
    AsyncSmtpConnection::connect_with_transport(stream, &hello)
        .await
        .map_err(|e| classify(&cfg.host, e))
}

/// Sends `command` (if any) and reads the whole reply, which must start
/// with `code`.
async fn expect(
    tcp: &mut TcpStream,
    host: &str,
    command: Option<&str>,
    code: &str,
) -> Result<String> {
    if let Some(command) = command {
        tcp.write_all(format!("{command}\r\n").as_bytes())
            .await
            .map_err(|e| unreachable(host, e))?;
    }
    let mut reply = Vec::new();
    let mut buf = [0u8; 1024];
    loop {
        let n = tcp.read(&mut buf).await.map_err(|e| unreachable(host, e))?;
        if n == 0 {
            return Err(unreachable(host, "the server closed the connection"));
        }
        reply.extend_from_slice(&buf[..n]);
        if reply.len() > 64 * 1024 {
            return Err(unreachable(host, "the server's reply is too long"));
        }
        let text = String::from_utf8_lossy(&reply);
        // A reply ends with a line whose code is followed by a space.
        if text.ends_with("\r\n")
            && text
                .trim_end()
                .lines()
                .last()
                .is_some_and(|l| l.as_bytes().get(3) != Some(&b'-'))
        {
            return if text.starts_with(code) {
                Ok(text.into_owned())
            } else {
                Err(unreachable(host, text.trim()))
            };
        }
    }
}

/// One SMTP command line, as lettre writes its own.
struct Line<'a>(&'a str);

impl fmt::Display for Line<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}\r\n", self.0)
    }
}

/// Signs in with the password, or with an OAuth token: a refused token
/// gets one new one and one more try, never more.
async fn sign_in(conn: &mut AsyncSmtpConnection, cfg: &SmtpConfig) -> Result<()> {
    match cfg.login.credential().await.map_err(|e| token_error(cfg, e))? {
        Credential::Password(password) => conn
            .auth(
                &[LettreMechanism::Plain, LettreMechanism::Login],
                &Credentials::new(cfg.username.clone(), password.to_string()),
            )
            .await
            .map(|_| ())
            .map_err(|e| classify(&cfg.host, e)),
        Credential::Token { mechanism, token } => {
            match authenticate(conn, cfg, mechanism, &token).await {
                Err(SendError::Auth) => {}
                done => return done,
            }
            let Some(renewed) = cfg.login.renew().await else {
                return Err(SendError::Auth);
            };
            match renewed.map_err(|e| token_error(cfg, e))? {
                Credential::Token { mechanism, token } => {
                    authenticate(conn, cfg, mechanism, &token).await
                }
                Credential::Password(_) => Err(SendError::Auth),
            }
        }
    }
}

fn token_error(cfg: &SmtpConfig, e: TokenError) -> SendError {
    match e {
        TokenError::Rejected(_) => SendError::Auth,
        TokenError::Offline(why) => unreachable(&cfg.host, why),
    }
}

/// `AUTH XOAUTH2` or `AUTH OAUTHBEARER` with the initial response. A
/// refused token gets an error challenge (334), answered so the server
/// ends with its 535.
async fn authenticate(
    conn: &mut AsyncSmtpConnection,
    cfg: &SmtpConfig,
    mechanism: Mechanism,
    token: &str,
) -> Result<()> {
    use base64::Engine;
    let initial = sasl_initial_base64(mechanism, &cfg.username, token, &cfg.host, cfg.port);
    let command = zeroize::Zeroizing::new(format!("AUTH {} {}", sasl_name(mechanism), initial.as_str()));
    let reply = conn
        .command(Line(&command))
        .await
        .map_err(|e| classify(&cfg.host, e))?;
    if reply.has_code(235) {
        return Ok(());
    }
    if reply.has_code(334) {
        let abort = base64::engine::general_purpose::STANDARD.encode(sasl_abort(mechanism));
        return match conn.command(Line(&abort)).await {
            Err(e) => Err(classify(&cfg.host, e)),
            Ok(_) => Err(SendError::Auth),
        };
    }
    Err(SendError::Auth)
}

fn classify(host: &str, e: lettre::transport::smtp::Error) -> SendError {
    match e.status().map(|c| c.to_string()) {
        Some(code) if code == "535" || code == "534" || code == "530" => SendError::Auth,
        // A 4xx refusal is temporary, from greylisting to a busy server.
        Some(code) if code.starts_with('4') => SendError::Deferred(e.to_string()),
        Some(_) => SendError::Rejected(e.to_string()),
        None => SendError::Connect {
            host: host.to_owned(),
            detail: e.to_string(),
        },
    }
}

/// Sends a message and files a copy in Sent.
pub async fn send_and_file(
    smtp: &SmtpConfig,
    imap: &ImapConfig,
    ready: &Ready,
) -> Result<SendReport> {
    send(smtp, ready).await?;
    let filed_in = if smtp.files_sent_itself() {
        None
    } else {
        file_copy(imap, &ready.raw).await
    };
    Ok(SendReport {
        message_id: ready.message_id.clone(),
        filed_in,
    })
}

async fn file_copy(imap: &ImapConfig, raw: &[u8]) -> Option<String> {
    let mut conn = Connection::open(imap).await.ok()?;
    let folder = conn.append_sent(raw).await.ok();
    conn.logout().await.ok();
    folder
}

#[cfg(test)]
mod tests {
    use super::*;

    fn draft() -> Draft {
        Draft {
            from_name: "Matteo".into(),
            from_email: "matteo@example.org".into(),
            to: vec!["Luca Bianchi <luca@example.org>".into()],
            subject: "Mockups approved".into(),
            body: "Hi Luca,\r\nwe start Monday.".into(),
            ..Draft::default()
        }
    }

    #[test]
    fn an_invite_answer_carries_its_calendar_part() {
        let ics =
            "BEGIN:VCALENDAR\r\nMETHOD:REPLY\r\nBEGIN:VEVENT\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
                .to_string();
        let raw = String::from_utf8(
            build(&Draft {
                calendar: Some(ics),
                ..draft()
            })
            .unwrap()
            .formatted(),
        )
        .unwrap();
        assert!(raw.contains("multipart/alternative"));
        assert!(raw.contains("text/calendar; charset=utf-8; method=REPLY"));
        assert!(raw.contains("\r\nMETHOD:REPLY\r\n"));
        let body = crate::imap::parse_body(raw.as_bytes());
        assert!(body.text.contains("we start Monday."));
        assert!(body.calendar.unwrap().contains("METHOD:REPLY"));
    }

    #[test]
    fn builds_a_plain_text_message() {
        let raw = String::from_utf8(build(&draft()).unwrap().formatted()).unwrap();
        assert!(raw.contains("From: Matteo <matteo@example.org>"));
        assert!(raw.contains("To: \"Luca Bianchi\" <luca@example.org>"));
        assert!(raw.contains("Subject: Mockups approved"));
        assert!(raw.contains("Message-ID: <"));
        assert!(raw.contains("text/plain; charset=utf-8"));
        assert!(raw.contains("we start Monday."));
    }

    #[test]
    fn replies_carry_the_thread() {
        let mut d = draft();
        d.in_reply_to = Some("<b@x>".into());
        d.references = vec!["<a@x>".into(), "<b@x>".into()];
        let raw = String::from_utf8(build(&d).unwrap().formatted()).unwrap();
        assert!(raw.contains("In-Reply-To: <b@x>"));
        assert!(raw.contains("References: <a@x> <b@x>"));
    }

    #[test]
    fn bcc_stays_out_of_the_headers() {
        let mut d = draft();
        d.bcc = vec!["hidden@example.org".into()];
        let m = build(&d).unwrap();
        let raw = String::from_utf8(m.formatted()).unwrap();
        assert!(!raw.contains("hidden@example.org"));
        assert!(m
            .envelope()
            .to()
            .iter()
            .any(|a| a.to_string() == "hidden@example.org"));
    }

    #[test]
    fn carries_attached_files() {
        let mut d = draft();
        d.files = vec![OutgoingFile {
            name: "mockup-v3.pdf".into(),
            mime: "application/pdf".into(),
            data: b"%PDF-1.4".to_vec(),
        }];
        let raw = build(&d).unwrap().formatted();
        let body = crate::imap::parse_body(&raw);
        assert!(body.text.contains("Hi"), "{}", body.text);
        assert_eq!(body.attachments.len(), 1);
        assert_eq!(body.attachments[0].name, "mockup-v3.pdf");
        assert_eq!(body.attachments[0].mime, "application/pdf");
        assert_eq!(
            crate::imap::attachment_data(&raw, body.attachments[0].part).unwrap(),
            b"%PDF-1.4"
        );
    }

    #[test]
    fn a_signature_adds_an_html_version() {
        let mut d = draft();
        d.body = "Thanks!\n\nOn Oct 12, Luca wrote:\n> Here they are\n>\n> Luca".into();
        d.signature = Some(Signature {
            name: "Matteo Neri".into(),
            company: "Studio Lumen".into(),
            website: "studiolumen.it".into(),
            ..Default::default()
        });
        let raw = build(&d).unwrap().formatted();
        let text = String::from_utf8_lossy(&raw);
        assert!(text.contains("multipart/alternative"));
        let parsed = mail_parser::MessageParser::default().parse(&raw).unwrap();
        let plain = parsed.body_text(0).unwrap().replace("\r\n", "\n");
        assert!(
            plain.contains("Thanks!\n\n-- \nMatteo Neri\nStudio Lumen\nstudiolumen.it\n\nOn Oct 12, Luca wrote:\n> Here they are"),
            "{plain}"
        );
        let html = parsed.body_html(0).unwrap();
        let sig_at = html.find("piuma-signature").unwrap();
        assert!(html.find("Thanks!").unwrap() < sig_at);
        assert!(html.find("Here they are").unwrap() > sig_at);
        assert!(!html.contains("cid:"));
    }

    #[test]
    fn formatting_adds_an_html_version() {
        let mut d = draft();
        d.body =
            "Friday works:\n• the terrace\n│ as you said\n\nOn Oct 12, Giulia wrote:\n> Dinner?"
                .into();
        d.marks = vec![Mark {
            kind: rich::MarkKind::Bold,
            start: 0,
            end: 6,
        }];
        let raw = build(&d).unwrap().formatted();
        let parsed = mail_parser::MessageParser::default().parse(&raw).unwrap();
        let plain = parsed.body_text(0).unwrap().replace("\r\n", "\n");
        assert_eq!(
            plain,
            "Friday works:\n• the terrace\n> as you said\n\nOn Oct 12, Giulia wrote:\n> Dinner?"
        );
        let html = parsed.body_html(0).unwrap();
        assert!(html.contains("<b>Friday</b> works:"), "{html}");
        assert!(html.contains("<li>the terrace</li>"), "{html}");
        assert!(html.contains("as you said</blockquote>"), "{html}");
        assert!(html.contains("Dinner?"), "{html}");
        // Sent mail doesn't carry the draft's marks.
        assert!(!String::from_utf8_lossy(&raw).contains(rich::HEADER));
    }

    #[test]
    fn a_draft_keeps_its_formatting() {
        let mut d = draft();
        d.body = "Friday works\n│ as you said".into();
        d.marks = vec![Mark {
            kind: rich::MarkKind::Link("https://trattoria.it/menu".into()),
            start: 0,
            end: 6,
        }];
        let raw = build_unsent(&d).unwrap().formatted();
        let back = crate::imap::parse_draft(&raw);
        assert_eq!(
            back.body.replace("\r\n", "\n"),
            "Friday works\n│ as you said"
        );
        assert_eq!(back.marks, d.marks);
    }

    #[test]
    fn plain_mail_stays_plain() {
        let mut d = draft();
        d.body = "1. eight\n2. half past".into();
        let raw = String::from_utf8(build(&d).unwrap().formatted()).unwrap();
        assert!(!raw.contains("text/html"));
    }

    #[test]
    fn a_logo_travels_inside_the_message() {
        let mut d = draft();
        d.files = vec![OutgoingFile {
            name: "notes.txt".into(),
            mime: "text/plain".into(),
            data: b"notes".to_vec(),
        }];
        d.signature = Some(Signature {
            name: "Matteo Neri".into(),
            template: signature::Template::Logo,
            logo: Some(signature::Logo {
                mime: "image/png".into(),
                data: vec![0x89, b'P', b'N', b'G'],
            }),
            ..Default::default()
        });
        let raw = build(&d).unwrap().formatted();
        let text = String::from_utf8_lossy(&raw);
        assert!(text.contains("multipart/related"));
        assert!(text.contains(&format!("Content-ID: <{LOGO_CID}>")));
        let parsed = mail_parser::MessageParser::default().parse(&raw).unwrap();
        assert!(parsed
            .body_html(0)
            .unwrap()
            .contains(&format!("cid:{LOGO_CID}")));
        // The logo is not listed as an attachment; the file still is.
        let body = crate::imap::parse_body(&raw);
        assert_eq!(body.attachments.len(), 1, "{:?}", body.attachments);
        assert_eq!(body.attachments[0].name, "notes.txt");
    }

    #[test]
    fn rejects_bad_drafts() {
        let mut d = draft();
        d.to = vec!["not an address".into()];
        assert!(matches!(build(&d), Err(SendError::Address(a)) if a == "not an address"));
        d.to.clear();
        assert!(matches!(build(&d), Err(SendError::NoRecipients)));
    }
}
