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
use lettre::transport::smtp::authentication::Credentials;
use lettre::Message;

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
    pub password: String,
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
    pub fn for_account(account: &Account, password: &str) -> Option<Self> {
        match &account.kind {
            AccountKind::Imap { smtp, username, .. } => Some(SmtpConfig {
                host: smtp.host.clone(),
                port: smtp.port,
                security: smtp.security,
                username: username.clone(),
                password: password.to_owned(),
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
    #[error("the server refused the message: {0}")]
    Rejected(String),
    /// The server did not take the message now (a 4xx: greylisting, an
    /// overload); it may well take it later, so the outbox keeps it and
    /// tries again in a later batch.
    #[error("the server deferred the message: {0}")]
    Deferred(String),
    /// The connection broke after the message was handed over and before
    /// the server said whether it took it: it may have gone. Never sent
    /// again without asking.
    #[error("the server may have taken the message: {0}")]
    Uncertain(String),
    /// The connection could not be made secure: a certificate that
    /// doesn't check out, or a server without encryption. Waiting won't
    /// fix it, so it shows rather than waits.
    #[error("could not make a secure connection to {host}: {detail}")]
    Tls { host: String, detail: String },
}

impl SendError {
    /// The server could not be reached: the message can wait in the
    /// outbox and go once the connection is back.
    pub fn is_offline(&self) -> bool {
        matches!(self, SendError::Connect { .. })
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

/// The message with its Date header set to `at` (Unix seconds): mail
/// sent later is dated when it actually goes. The rest stays byte for
/// byte, Message-ID included.
pub fn redate(raw: &[u8], at: i64) -> Vec<u8> {
    let mut headers = lettre::message::header::Headers::new();
    headers.set(lettre::message::header::Date::new(
        std::time::UNIX_EPOCH + Duration::from_secs(at.max(0) as u64),
    ));
    let Some(date) = headers.get_raw("Date") else {
        return raw.to_vec();
    };
    let end = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .map_or(raw.len(), |i| i + 2);
    let mut start = 0;
    while start < end {
        let line_end = raw[start..end]
            .windows(2)
            .position(|w| w == b"\r\n")
            .map_or(end, |i| start + i + 2);
        if raw[start..line_end]
            .get(..5)
            .is_some_and(|h| h.eq_ignore_ascii_case(b"date:"))
        {
            // Folded lines belong to the header.
            let mut stop = line_end;
            while stop < end && matches!(raw[stop], b' ' | b'\t') {
                stop = raw[stop..end]
                    .windows(2)
                    .position(|w| w == b"\r\n")
                    .map_or(end, |i| stop + i + 2);
            }
            let mut out = Vec::with_capacity(raw.len() + 8);
            out.extend_from_slice(&raw[..start]);
            out.extend_from_slice(format!("Date: {date}\r\n").as_bytes());
            out.extend_from_slice(&raw[stop..]);
            return out;
        }
        start = line_end;
    }
    raw.to_vec()
}

/// What happened after a successful send.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendReport {
    pub message_id: String,
    /// Whether the copy is in Sent.
    pub filed: Filing,
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
///
/// The steps are taken one by one, so a failure says how far the message
/// got: anything before the message text is sent is safe to try again,
/// while a connection lost after it, before the server's answer, leaves
/// the server holding it or not ([SendError::Uncertain]).
pub async fn send(cfg: &SmtpConfig, ready: &Ready) -> Result<()> {
    use lettre::transport::smtp::client::{AsyncSmtpConnection, TlsParameters};
    use lettre::transport::smtp::commands::{Data, Mail, Rcpt};
    use lettre::transport::smtp::extension::{
        ClientId, Extension, MailBodyParameter, MailParameter,
    };

    let address = |a: &str| {
        a.parse::<lettre::Address>()
            .map_err(|_| SendError::Address(a.to_owned()))
    };
    let recipients = ready
        .recipients
        .iter()
        .map(|r| address(r))
        .collect::<Result<Vec<_>>>()?;
    let from = address(&ready.from)?;
    crate::tls::use_one_crypto_provider();
    let host = cfg.host.as_str();
    let tls = match cfg.security {
        Security::None => None,
        Security::Tls | Security::StartTls => Some(
            TlsParameters::new(cfg.host.clone()).map_err(|e| classify(host, Step::Connect, e))?,
        ),
    };
    let hello = ClientId::default();
    let wrapper = tls.clone().filter(|_| cfg.security == Security::Tls);
    let mut conn = AsyncSmtpConnection::connect_tokio1(
        (host, cfg.port),
        Some(SMTP_TIMEOUT),
        &hello,
        wrapper,
        None,
    )
    .await
    .map_err(|e| classify(host, Step::Connect, e))?;
    if let (Security::StartTls, Some(tls)) = (cfg.security, tls) {
        conn.starttls(tls, &hello)
            .await
            .map_err(|e| classify(host, Step::Connect, e))?;
    }
    let credentials = Credentials::new(cfg.username.clone(), cfg.password.clone());
    conn.auth(
        lettre::transport::smtp::authentication::DEFAULT_MECHANISMS,
        &credentials,
    )
    .await
    .map_err(|e| classify(host, Step::Auth, e))?;
    let mut options = Vec::new();
    let wide = !ready.from.is_ascii() || ready.recipients.iter().any(|r| !r.is_ascii());
    if wide && conn.server_info().supports_feature(Extension::SmtpUtfEight) {
        options.push(MailParameter::SmtpUtfEight);
    }
    if !ready.raw.is_ascii() && conn.server_info().supports_feature(Extension::EightBitMime) {
        options.push(MailParameter::Body(MailBodyParameter::EightBitMime));
    }
    let before = async {
        conn.command(Mail::new(Some(from), options)).await?;
        for to in recipients {
            conn.command(Rcpt::new(to, Vec::new())).await?;
        }
        conn.command(Data).await
    }
    .await;
    if let Err(e) = before {
        conn.abort().await;
        return Err(classify(host, Step::Envelope, e));
    }
    // From here on the server may have the message.
    let answer = conn.message(&ready.raw).await;
    match answer {
        Ok(_) => {
            conn.quit().await.ok();
            Ok(())
        }
        Err(e) => {
            conn.abort().await;
            Err(classify(host, Step::Message, e))
        }
    }
}

/// How long one step of a conversation with the SMTP server may take.
const SMTP_TIMEOUT: Duration = Duration::from_secs(60);

/// How far a send got when it failed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Step {
    /// Reaching the server and securing the connection.
    Connect,
    Auth,
    /// MAIL, RCPT and DATA: the server has nothing to deliver yet.
    Envelope,
    /// The message itself and the server's answer to it.
    Message,
}

fn classify(host: &str, step: Step, e: lettre::transport::smtp::Error) -> SendError {
    let detail = e.to_string();
    match e.status().map(|c| c.to_string()) {
        Some(code) if code == "535" || code == "534" || code == "530" => SendError::Auth,
        // A 4xx refusal is temporary, from greylisting to a busy server.
        Some(code) if code.starts_with('4') => SendError::Deferred(detail),
        Some(_) => SendError::Rejected(detail),
        // No answer to the message: the server may have taken it.
        None if step == Step::Message => SendError::Uncertain(detail),
        None if step == Step::Connect && (e.is_tls() || tls_failure(&e) || e.is_client()) => {
            SendError::Tls {
                host: host.to_owned(),
                detail,
            }
        }
        // The server answered, but nothing it offers fits: no way to
        // sign in that waiting would fix.
        None if step == Step::Auth && e.is_client() => SendError::Rejected(detail),
        None => SendError::Connect {
            host: host.to_owned(),
            detail,
        },
    }
}

/// Whether an error comes from TLS itself (a certificate that doesn't
/// check out, a handshake that fails) rather than from the network.
pub(crate) fn tls_failure(e: &(dyn std::error::Error + 'static)) -> bool {
    let mut next = Some(e);
    while let Some(e) = next {
        if e.downcast_ref::<tokio_rustls::rustls::Error>().is_some() {
            return true;
        }
        if let Some(io) = e.downcast_ref::<std::io::Error>() {
            if let Some(inner) = io.get_ref() {
                if tls_failure(inner) {
                    return true;
                }
            }
            // rustls reports a broken handshake as invalid data.
            if io.kind() == std::io::ErrorKind::InvalidData {
                return true;
            }
        }
        next = e.source();
    }
    false
}

/// Sends a message and files a copy in Sent.
pub async fn send_and_file(
    smtp: &SmtpConfig,
    imap: &ImapConfig,
    ready: &Ready,
) -> Result<SendReport> {
    send(smtp, ready).await?;
    Ok(SendReport {
        message_id: ready.message_id.clone(),
        filed: file_sent(smtp, imap, ready, false).await,
    })
}

/// Files the copy of a message the server took in Sent, unless the server
/// does it itself. A [retry] looks first, so a copy that went in before a
/// lost answer is not filed twice.
pub async fn file_sent(smtp: &SmtpConfig, imap: &ImapConfig, ready: &Ready, retry: bool) -> Filing {
    if smtp.files_sent_itself() {
        return Filing::Server;
    }
    let filed = async {
        let mut conn = Connection::open(imap).await?;
        let there = if retry {
            conn.sent_has(&ready.message_id).await?
        } else {
            None
        };
        let folder = match there {
            Some(folder) => folder,
            None => conn.append_sent(&ready.raw).await?,
        };
        conn.logout().await.ok();
        Ok::<_, crate::imap::ImapError>(folder)
    }
    .await;
    match filed {
        Ok(folder) => Filing::Ours(folder),
        Err(e) => Filing::Missing(e.to_string()),
    }
}

/// Whether the copy of a sent message is in Sent (see [file_sent]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Filing {
    /// Filed here, in this folder.
    Ours(String),
    /// The server files sent mail itself (Gmail, JMAP).
    Server,
    /// Not filed yet; why. The outbox keeps the message and tries again.
    Missing(String),
}

impl Filing {
    /// Whether nothing is left to do for the Sent copy.
    pub fn done(&self) -> bool {
        !matches!(self, Filing::Missing(_))
    }
}

/// Whether the server files sent mail itself, so a message it took is in
/// Sent: its Message-ID there settles a send whose answer was lost.
pub fn files_sent_itself(smtp: &SmtpConfig) -> bool {
    smtp.files_sent_itself()
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
    fn a_late_message_is_dated_when_it_goes() {
        let mut d = draft();
        d.date = Some(1_700_000_000);
        let built = ready(&d).unwrap();
        let later = redate(&built.raw, 1_800_000_000);
        let parsed = mail_parser::MessageParser::default().parse(&later).unwrap();
        assert_eq!(parsed.date().unwrap().to_timestamp(), 1_800_000_000);
        let text = String::from_utf8(later.clone()).unwrap();
        assert_eq!(text.matches("Date:").count(), 1, "{text}");
        assert!(text.contains(&built.message_id));
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
