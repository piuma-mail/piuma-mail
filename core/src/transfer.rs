//! Moving mail to and from other mail apps.
//!
//! Export writes a folder, or chosen messages, into one `.mbox` file
//! (mboxrd, see [`crate::mbox`]) or a ZIP of `.eml` files, a message at a
//! time: nothing is held in memory but the message being written. Each
//! message comes whole from its server; with no server in reach, a
//! message whose text was downloaded is rebuilt from the local copy
//! (without its attachments) and one never downloaded is left out, and
//! the report says so.
//!
//! Import reads `.eml` and `.mbox` files (an Apple Mail `.mbox` folder
//! too) and puts each message into the folder the person picked with
//! APPEND (IMAP) or Email/import (JMAP), with the flags other apps left in
//! it and the time it arrived. A message whose Message-ID the folder
//! already has is skipped, so running an import again after it stopped
//! only adds what is missing; a message without a Message-ID gets one made
//! from its bytes, so it is recognised the next time too. What is not mail,
//! is too large for the server, or is refused is skipped and listed, never
//! a reason to stop.
//!
//! Files are untrusted: they go through the engine's parser, nothing in
//! them runs, links are not followed, and an exported file only ever goes
//! where the person chose, marked as come from the internet like a saved
//! attachment.

use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

use base64::Engine as _;
use mail_parser::MessageParser;
use sha2::{Digest, Sha256};

use crate::mbox::{self, MboxReader, MboxSkip, MboxWriter};
use crate::model::{AccountId, Flags};
use crate::remote::Remote;
use crate::store::Store;

/// Most skipped messages listed one by one in a report; the rest are
/// counted.
pub const SKIPPED_LISTED: usize = 200;

/// Messages fetched from the server per round trip of an export.
const EXPORT_BATCH: usize = 100;

/// Why a message, or a file, was left out.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SkipReason {
    /// It does not read as an email (or the file is neither `.eml` nor
    /// mbox).
    NotMail,
    /// Larger than the server, or the app, takes.
    TooLarge,
    /// Its text was never downloaded and the server can't be reached.
    NotDownloaded,
    /// The server is gone or keeps no body for it.
    Gone,
    /// A link, or something else that is not a plain file: not followed.
    NotAFile,
    /// The file can't be read.
    Unreadable,
    /// The server refused it, with what it said.
    Refused(String),
}

/// A message, or a whole file, left out, and why.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Skipped {
    /// The file's name, `name.mbox #12` for a message of an mbox file, or
    /// a message's subject in an export.
    pub item: String,
    pub reason: SkipReason,
}

/// How far a job is: messages for an export, bytes read for an import.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Progress {
    pub done: u64,
    pub total: u64,
    /// Messages handled so far (written, imported or skipped).
    pub messages: u64,
}

/// What an import did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ImportReport {
    pub imported: u64,
    /// Already in the folder (same Message-ID), or twice in the files.
    pub duplicates: u64,
    /// At most [`SKIPPED_LISTED`], in order.
    pub skipped: Vec<Skipped>,
    /// Every skipped message, listed or not.
    pub skipped_count: u64,
    pub cancelled: bool,
    /// What stopped it before the end (the server went away, the
    /// folder can't be read); running it again carries on.
    pub error: Option<String>,
}

/// What an export did.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ExportReport {
    pub exported: u64,
    /// Of those, rebuilt from the local copy without the server: text
    /// and HTML only.
    pub rebuilt: u64,
    pub skipped: Vec<Skipped>,
    pub skipped_count: u64,
    pub cancelled: bool,
    /// The server could not be reached for some or all of it.
    pub offline: bool,
}

fn note_skip(list: &mut Vec<Skipped>, count: &mut u64, item: String, reason: SkipReason) {
    *count += 1;
    if list.len() < SKIPPED_LISTED {
        list.push(Skipped { item, reason });
    }
}

// ---------------------------------------------------------------- import

/// A file to import, as recognised.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImportFile {
    Eml(PathBuf),
    Mbox(PathBuf),
}

/// A plain file at `path`, never a link: its length.
fn plain_file(path: &Path) -> Result<u64, SkipReason> {
    let meta = fs::symlink_metadata(path).map_err(|_| SkipReason::Unreadable)?;
    if !meta.file_type().is_file() {
        return Err(SkipReason::NotAFile);
    }
    Ok(meta.len())
}

/// What kind of file `path` is: an email file, an mbox file, or an Apple
/// Mail `.mbox` folder (which keeps its messages in `mbox` inside).
/// Links are never followed.
pub fn recognise(path: &Path) -> Result<ImportFile, SkipReason> {
    let meta = fs::symlink_metadata(path).map_err(|_| SkipReason::Unreadable)?;
    if meta.file_type().is_dir() {
        let inner = path.join("mbox");
        plain_file(&inner)?;
        return Ok(ImportFile::Mbox(inner));
    }
    plain_file(path)?;
    let mut start = [0u8; 4096];
    let mut file = File::open(path).map_err(|_| SkipReason::Unreadable)?;
    let mut n = 0;
    while n < start.len() {
        match file.read(&mut start[n..]) {
            Ok(0) => break,
            Ok(k) => n += k,
            Err(_) => return Err(SkipReason::Unreadable),
        }
    }
    if mbox::looks_like_mbox(&start[..n]) {
        Ok(ImportFile::Mbox(path.to_owned()))
    } else {
        Ok(ImportFile::Eml(path.to_owned()))
    }
}

/// A message ready for the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Prepared {
    /// CRLF line ends, with a Message-ID.
    pub raw: Vec<u8>,
    /// Without angle brackets.
    pub message_id: String,
    pub flags: Flags,
    /// When it arrived, Unix seconds, when known.
    pub at: Option<i64>,
}

/// Bare LF line ends become CRLF, as servers want them.
fn crlf(raw: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(raw.len() + raw.len() / 32);
    let mut prev = 0u8;
    for &b in raw {
        if b == b'\n' && prev != b'\r' {
            out.push(b'\r');
        }
        out.push(b);
        prev = b;
    }
    out
}

/// Reads one message from a file for the server: it must read as mail
/// and fit `limit` bytes. `delivered` is the time an mbox `From ` line
/// gives; else the Date header's is used.
pub fn prepare(raw: &[u8], delivered: Option<i64>, limit: u64) -> Result<Prepared, SkipReason> {
    if raw.len() as u64 > limit {
        return Err(SkipReason::TooLarge);
    }
    let read = crate::guard::shielded(
        "import",
        || None,
        || {
            let m = MessageParser::default().parse_headers(raw)?;
            let mailish = m.from().is_some()
                || m.to().is_some()
                || m.subject().is_some()
                || m.date().is_some()
                || m.message_id().is_some();
            mailish.then(|| {
                (
                    m.message_id().map(crate::imap::bare_message_id),
                    m.date().map(|d| d.to_timestamp()),
                )
            })
        },
    );
    let Some((id, date)) = read else {
        return Err(SkipReason::NotMail);
    };
    let flags = mbox::flags_in(raw);
    let mut raw = crlf(raw);
    let message_id = match id.filter(|i| !i.is_empty() && !i.contains(['\r', '\n'])) {
        Some(id) => id,
        None => {
            // Made from the bytes, so the same message gets the same one
            // when imported again.
            let digest = Sha256::digest(&raw);
            let hex: String = digest[..16].iter().map(|b| format!("{b:02x}")).collect();
            let id = format!("{hex}@import.piuma.invalid");
            let mut with = format!("Message-ID: <{id}>\r\n").into_bytes();
            with.extend_from_slice(&raw);
            raw = with;
            id
        }
    };
    if raw.len() as u64 > limit {
        return Err(SkipReason::TooLarge);
    }
    Ok(Prepared {
        raw,
        message_id,
        flags,
        at: delivered.or(date).filter(|&t| t > 0),
    })
}

/// The file name shown for `path`.
fn shown(path: &Path) -> String {
    let p = if path.file_name().is_some_and(|n| n == "mbox") {
        path.parent().unwrap_or(path)
    } else {
        path
    };
    p.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// Where the messages of an import go.
pub trait ImportTarget {
    /// The Message-IDs the folder has, without angle brackets.
    fn existing(
        &mut self,
    ) -> impl std::future::Future<Output = Result<HashSet<String>, String>> + Send;
    /// The largest message it takes.
    fn limit(&self) -> u64;
    /// Puts one message in; Err(true, what) when it can't go on at all,
    /// Err(false, what) when only this message was refused.
    fn put(
        &mut self,
        message: &Prepared,
    ) -> impl std::future::Future<Output = Result<(), (bool, String)>> + Send;
}

/// A folder of an account on its server.
pub struct RemoteFolder<'a> {
    pub remote: &'a mut Remote,
    pub folder: String,
}

impl ImportTarget for RemoteFolder<'_> {
    async fn existing(&mut self) -> Result<HashSet<String>, String> {
        self.remote
            .message_ids(&self.folder)
            .await
            .map_err(|e| e.to_string())
    }

    fn limit(&self) -> u64 {
        let app = crate::guard::MESSAGE_MAX as u64;
        self.remote.append_limit().map_or(app, |n| n.min(app))
    }

    async fn put(&mut self, m: &Prepared) -> Result<(), (bool, String)> {
        self.remote
            .append_message(&self.folder, &m.raw, m.flags, m.at)
            .await
            .map_err(|e| (e.is_offline() || e.is_auth(), e.to_string()))
    }
}

/// Refusals in a row after which the server is taken to be gone.
const REFUSED_IN_A_ROW: u32 = 5;

/// Imports `paths` into `target`. `progress` hears after every message;
/// `cancel` stops it between two messages.
pub async fn import(
    target: &mut impl ImportTarget,
    paths: &[PathBuf],
    cancel: &AtomicBool,
    mut progress: impl FnMut(Progress),
) -> ImportReport {
    let mut report = ImportReport::default();
    let mut seen = match target.existing().await {
        Ok(ids) => ids,
        Err(e) => {
            report.error = Some(e);
            return report;
        }
    };
    let limit = target.limit();
    let total: u64 = paths
        .iter()
        .filter_map(|p| recognise(p).ok())
        .map(|f| match f {
            ImportFile::Eml(p) | ImportFile::Mbox(p) => plain_file(&p).unwrap_or(0),
        })
        .sum();
    let mut at = Progress {
        done: 0,
        total,
        messages: 0,
    };
    let mut refused = 0u32;
    // One message: Ok(true) when the import must stop.
    macro_rules! one {
        ($item:expr, $raw:expr, $delivered:expr) => {{
            at.messages += 1;
            match prepare($raw, $delivered, limit) {
                Err(reason) => {
                    note_skip(
                        &mut report.skipped,
                        &mut report.skipped_count,
                        $item,
                        reason,
                    );
                    false
                }
                Ok(m) if seen.contains(&m.message_id) => {
                    report.duplicates += 1;
                    false
                }
                Ok(m) => match target.put(&m).await {
                    Ok(()) => {
                        refused = 0;
                        seen.insert(m.message_id);
                        report.imported += 1;
                        false
                    }
                    Err((fatal, what)) => {
                        refused += 1;
                        if fatal || refused >= REFUSED_IN_A_ROW {
                            report.error = Some(what);
                            true
                        } else {
                            note_skip(
                                &mut report.skipped,
                                &mut report.skipped_count,
                                $item,
                                SkipReason::Refused(what),
                            );
                            false
                        }
                    }
                },
            }
        }};
    }
    'files: for path in paths {
        if cancel.load(Ordering::Relaxed) {
            report.cancelled = true;
            break;
        }
        let name = shown(path);
        let file = match recognise(path) {
            Ok(f) => f,
            Err(reason) => {
                note_skip(&mut report.skipped, &mut report.skipped_count, name, reason);
                continue;
            }
        };
        let base = at.done;
        match file {
            ImportFile::Eml(p) => {
                let size = plain_file(&p).unwrap_or(0);
                let raw = match crate::eml::load(&p) {
                    Ok(raw) => raw,
                    Err(crate::eml::EmlError::TooLarge) => {
                        at.messages += 1;
                        note_skip(
                            &mut report.skipped,
                            &mut report.skipped_count,
                            name,
                            SkipReason::TooLarge,
                        );
                        at.done = base + size;
                        progress(at);
                        continue;
                    }
                    Err(_) => {
                        note_skip(
                            &mut report.skipped,
                            &mut report.skipped_count,
                            name,
                            SkipReason::Unreadable,
                        );
                        at.done = base + size;
                        progress(at);
                        continue;
                    }
                };
                let stop = one!(name, &raw, None);
                at.done = base + size;
                progress(at);
                if stop {
                    break 'files;
                }
            }
            ImportFile::Mbox(p) => {
                let Ok(f) = File::open(&p) else {
                    note_skip(
                        &mut report.skipped,
                        &mut report.skipped_count,
                        name,
                        SkipReason::Unreadable,
                    );
                    continue;
                };
                let max = usize::try_from(limit).unwrap_or(usize::MAX);
                let mut reader = MboxReader::new(BufReader::with_capacity(1 << 16, f), max);
                loop {
                    if cancel.load(Ordering::Relaxed) {
                        report.cancelled = true;
                        break 'files;
                    }
                    let Some(next) = reader.next() else { break };
                    let stop = match next {
                        Err(e) => {
                            let reason = if e.kind() == io::ErrorKind::InvalidData {
                                SkipReason::NotMail
                            } else {
                                SkipReason::Unreadable
                            };
                            note_skip(
                                &mut report.skipped,
                                &mut report.skipped_count,
                                name.clone(),
                                reason,
                            );
                            false
                        }
                        Ok(Err(MboxSkip::TooLarge { index })) => {
                            at.messages += 1;
                            note_skip(
                                &mut report.skipped,
                                &mut report.skipped_count,
                                format!("{name} #{index}"),
                                SkipReason::TooLarge,
                            );
                            false
                        }
                        Ok(Ok(entry)) => {
                            one!(
                                format!("{name} #{}", entry.index),
                                &entry.raw,
                                entry.delivered
                            )
                        }
                    };
                    at.done = base + reader.consumed();
                    progress(at);
                    if stop {
                        break 'files;
                    }
                }
            }
        }
    }
    report
}

// ---------------------------------------------------------------- export

/// What an export writes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportFormat {
    /// One `.mbox` file (mboxrd).
    Mbox,
    /// A ZIP with one `.eml` file per message.
    EmlZip,
}

/// Messages of one folder as fetched: each uid with its bytes, or None.
pub type Fetched = Vec<(u32, Option<Vec<u8>>)>;

/// Where an export's messages come from: the server when it can be
/// reached, the local copy when not.
pub trait ExportSource {
    /// Whole messages of one folder of `account`, each uid with its
    /// bytes or None. Err when its server can't be reached (any more).
    fn fetch(
        &mut self,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> impl std::future::Future<Output = Result<Fetched, String>> + Send;
}

/// One account's server.
pub struct RemoteSource<'a> {
    pub remote: &'a mut Remote,
    pub store: &'a Mutex<Store>,
}

impl ExportSource for RemoteSource<'_> {
    async fn fetch(
        &mut self,
        account: AccountId,
        mailbox: &str,
        uids: &[u32],
    ) -> Result<Fetched, String> {
        self.remote
            .raw_many(self.store, account, mailbox, uids)
            .await
            .map_err(|e| e.to_string())
    }
}

/// No server: everything comes from the local copy.
pub struct Offline;

impl ExportSource for Offline {
    async fn fetch(&mut self, _: AccountId, _: &str, _: &[u32]) -> Result<Fetched, String> {
        Err("offline".into())
    }
}

/// A file name for a ZIP entry: the message's number, then its subject
/// with only safe characters, so no entry can name a folder or leave the
/// archive (ZIP slip) whatever the subject says.
pub fn entry_name(n: u64, subject: &str) -> String {
    let mut safe = String::new();
    for c in subject.chars() {
        let keep = c.is_alphanumeric() || " -_,()[]&+'".contains(c);
        let c = if keep { c } else { '_' };
        if c == '_' && safe.ends_with('_') {
            continue;
        }
        safe.push(c);
        if safe.chars().count() >= 60 {
            break;
        }
    }
    let safe = safe.trim_matches(|c: char| c == ' ' || c == '_' || c == '.');
    let safe = if safe.is_empty() { "message" } else { safe };
    format!("{n:05} {safe}.eml")
}

/// RFC 2047 for a header value that is not plain ASCII.
fn encoded_word(text: &str) -> String {
    let text: String = text.chars().filter(|c| !c.is_control()).collect();
    if text.is_ascii() {
        return text;
    }
    // Short pieces, each a whole number of characters.
    let mut out = Vec::new();
    let mut piece = String::new();
    for c in text.chars() {
        if piece.len() + c.len_utf8() > 45 {
            out.push(std::mem::take(&mut piece));
        }
        piece.push(c);
    }
    out.push(piece);
    out.iter()
        .map(|p| {
            format!(
                "=?utf-8?b?{}?=",
                base64::engine::general_purpose::STANDARD.encode(p)
            )
        })
        .collect::<Vec<_>>()
        .join("\r\n ")
}

fn mailbox(name: &str, email: &str) -> String {
    let email: String = email
        .chars()
        .filter(|c| !c.is_whitespace() && !c.is_control() && !"<>\"".contains(*c))
        .collect();
    let name = name.trim();
    if name.is_empty() {
        return email;
    }
    let name = if name.is_ascii() {
        format!("\"{}\"", name.replace(['"', '\\'], ""))
    } else {
        encoded_word(name)
    };
    format!("{name} <{email}>")
}

fn base64_lines(data: &[u8]) -> String {
    let all = base64::engine::general_purpose::STANDARD.encode(data);
    let mut out = String::with_capacity(all.len() + all.len() / 38);
    for chunk in all.as_bytes().chunks(76) {
        out.push_str(std::str::from_utf8(chunk).unwrap_or_default());
        out.push_str("\r\n");
    }
    out
}

/// A message rebuilt from the local copy, when the server can't give it:
/// its headers as kept, its text and HTML, no attachments. None when its
/// text was never downloaded.
pub fn rebuild(store: &Store, account: AccountId, mailbox_name: &str, uid: u32) -> Option<Vec<u8>> {
    let m = store.message(account, mailbox_name, uid).ok()??;
    let body = store.full_body(account, mailbox_name, uid).ok()??;
    let envelope = store.envelope(account, mailbox_name, uid).ok().flatten();
    let mut h = String::new();
    h.push_str(&format!(
        "From: {}\r\n",
        mailbox(&m.from_name, &m.from_email)
    ));
    if let Some(e) = &envelope {
        for (name, list) in [("To", &e.to), ("Cc", &e.cc)] {
            if !list.is_empty() {
                let all: Vec<String> = list.iter().map(|a| mailbox(&a.name, &a.email)).collect();
                h.push_str(&format!("{name}: {}\r\n", all.join(",\r\n ")));
            }
        }
    }
    h.push_str(&format!("Subject: {}\r\n", encoded_word(&m.subject)));
    h.push_str(&format!(
        "Date: {}\r\n",
        crate::space::rfc2822(m.received_at)
    ));
    let id = crate::imap::bare_message_id(&m.reply.message_id);
    if !id.is_empty() && !id.contains(['\r', '\n']) {
        h.push_str(&format!("Message-ID: <{id}>\r\n"));
    }
    h.push_str("MIME-Version: 1.0\r\n");
    h.push_str("X-Piuma-Rebuilt: from the local copy, without attachments\r\n");
    let boundary = format!("piuma-{:016x}", u64::from(uid) ^ (m.received_at as u64));
    h.push_str(&format!(
        "Content-Type: multipart/alternative; boundary=\"{boundary}\"\r\n\r\n"
    ));
    h.push_str(&format!(
        "--{boundary}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n{}",
        base64_lines(body.text.as_bytes())
    ));
    if let Some(html) = &body.html {
        h.push_str(&format!(
            "--{boundary}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n{}",
            base64_lines(html.as_bytes())
        ));
    }
    h.push_str(&format!("--{boundary}--\r\n"));
    Some(h.into_bytes())
}

fn lock(store: &Mutex<Store>) -> std::sync::MutexGuard<'_, Store> {
    store.lock().unwrap_or_else(|e| e.into_inner())
}

enum Sink {
    Mbox(MboxWriter<BufWriter<File>>),
    Zip(Box<zip::ZipWriter<BufWriter<File>>>),
}

/// The file being written, next to where it goes; removed unless
/// [`Partial::keep`] renames it into place.
struct Partial {
    path: PathBuf,
    kept: bool,
}

impl Partial {
    fn keep(mut self, to: &Path) -> io::Result<()> {
        fs::rename(&self.path, to)?;
        self.kept = true;
        Ok(())
    }
}

impl Drop for Partial {
    fn drop(&mut self) {
        if !self.kept {
            let _ = fs::remove_file(&self.path);
        }
    }
}

/// Opens the file an export writes into: next to `dest`, never through
/// a link. `dest` itself may be a file the person chose to replace, never
/// a link or a folder.
fn open_partial(dest: &Path) -> io::Result<(File, Partial)> {
    if let Ok(meta) = fs::symlink_metadata(dest) {
        if !meta.file_type().is_file() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "the destination is not a plain file",
            ));
        }
    }
    let name = dest
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "no file name"))?;
    let mut part_name = std::ffi::OsString::from(".");
    part_name.push(name);
    part_name.push(".part");
    let path = dest.with_file_name(part_name);
    // One left by an export that crashed: a file of ours by its name
    // (a link there is removed, not followed).
    let _ = fs::remove_file(&path);
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)?;
    Ok((file, Partial { path, kept: false }))
}

/// Exports `messages` (account, folder and uid, in order) into
/// `dest`. Messages come from `source`, else from the local copy (see
/// [`rebuild`]). The file appears at `dest` only once complete, marked as
/// come from the internet; a cancelled or failed export leaves nothing.
#[allow(clippy::too_many_arguments)]
pub async fn export(
    source: &mut impl ExportSource,
    store: &Mutex<Store>,
    messages: &[(AccountId, String, u32)],
    format: ExportFormat,
    dest: &Path,
    cancel: &AtomicBool,
    mut progress: impl FnMut(Progress),
) -> io::Result<ExportReport> {
    let mut report = ExportReport::default();
    let (file, partial) = open_partial(dest)?;
    let out = BufWriter::with_capacity(1 << 16, file);
    let mut sink = match format {
        ExportFormat::Mbox => Sink::Mbox(MboxWriter::new(out)),
        ExportFormat::EmlZip => Sink::Zip(Box::new(zip::ZipWriter::new(out))),
    };
    let options = zip::write::SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated);
    let mut at = Progress {
        done: 0,
        total: messages.len() as u64,
        messages: 0,
    };
    // Accounts whose server could not be reached.
    let mut offline: HashSet<AccountId> = HashSet::new();
    let mut i = 0;
    while i < messages.len() {
        if cancel.load(Ordering::Relaxed) {
            report.cancelled = true;
            return Ok(report);
        }
        // A run of messages of one folder.
        let (account, folder) = (messages[i].0, &messages[i].1);
        let mut end = i;
        while end < messages.len()
            && end - i < EXPORT_BATCH
            && messages[end].0 == account
            && messages[end].1 == *folder
        {
            end += 1;
        }
        let uids: Vec<u32> = messages[i..end].iter().map(|(_, _, u)| *u).collect();
        let mut online = !offline.contains(&account);
        let fetched: Fetched = if online {
            match source.fetch(account, folder, &uids).await {
                Ok(f) => f,
                Err(_) => {
                    online = false;
                    offline.insert(account);
                    report.offline = true;
                    uids.iter().map(|u| (*u, None)).collect()
                }
            }
        } else {
            uids.iter().map(|u| (*u, None)).collect()
        };
        for (uid, raw) in fetched {
            if cancel.load(Ordering::Relaxed) {
                report.cancelled = true;
                return Ok(report);
            }
            let summary = lock(store).message(account, folder, uid).ok().flatten();
            let subject = summary
                .as_ref()
                .map(|m| m.subject.clone())
                .unwrap_or_default();
            let (raw, rebuilt) = match raw {
                Some(raw) => (Some(raw), false),
                None if online => (None, false),
                None => (rebuild(&lock(store), account, folder, uid), true),
            };
            at.messages += 1;
            at.done += 1;
            let Some(raw) = raw else {
                let reason = if online {
                    SkipReason::Gone
                } else {
                    SkipReason::NotDownloaded
                };
                note_skip(
                    &mut report.skipped,
                    &mut report.skipped_count,
                    subject,
                    reason,
                );
                progress(at);
                continue;
            };
            match &mut sink {
                Sink::Mbox(w) => {
                    let (sender, when, flags) = match &summary {
                        Some(m) => (m.from_email.as_str(), m.received_at, Some(m.flags)),
                        None => ("", 0, None),
                    };
                    w.add(&raw, sender, when, flags)?;
                }
                Sink::Zip(z) => {
                    z.start_file(entry_name(report.exported + 1, &subject), options)
                        .map_err(io::Error::other)?;
                    z.write_all(&raw)?;
                }
            }
            report.exported += 1;
            if rebuilt {
                report.rebuilt += 1;
            }
            progress(at);
        }
        i = end;
    }
    let mut out = match sink {
        Sink::Mbox(w) => w.into_inner(),
        Sink::Zip(z) => z.finish().map_err(io::Error::other)?,
    };
    out.flush()?;
    out.into_inner().map_err(|e| e.into_error())?.sync_all()?;
    partial.keep(dest)?;
    crate::files::mark_from_internet(dest);
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ONE: &[u8] = b"From: Ada <ada@example.com>\r\nTo: bob@example.com\r\nSubject: First\r\nDate: Tue, 3 Nov 2026 10:00:00 +0000\r\nMessage-ID: <one@example.com>\r\n\r\nFrom the start.\r\n>From quoted.\r\n";

    #[test]
    fn prepared_messages_get_crlf_and_an_id() {
        let p = prepare(
            b"Subject: no id\nX-Mozilla-Status: 0000\n\nhi\n",
            None,
            1 << 20,
        )
        .unwrap();
        assert!(p.raw.starts_with(b"Message-ID: <"));
        assert!(p.message_id.ends_with("@import.piuma.invalid"));
        assert!(!p.raw.windows(2).any(|w| w[1] == b'\n' && w[0] != b'\r'));
        assert!(!p.flags.seen);
        // The same bytes get the same id: a second import skips them.
        let again = prepare(
            b"Subject: no id\nX-Mozilla-Status: 0000\n\nhi\n",
            None,
            1 << 20,
        )
        .unwrap();
        assert_eq!(again.message_id, p.message_id);
        let one = prepare(ONE, Some(5), 1 << 20).unwrap();
        assert_eq!(one.message_id, "one@example.com");
        assert_eq!(one.raw, ONE);
        assert_eq!(one.at, Some(5));
        assert_eq!(prepare(ONE, None, 1 << 20).unwrap().at, Some(1_793_700_000));
    }

    #[test]
    fn what_is_not_mail_or_too_large_is_refused() {
        assert_eq!(
            prepare(b"\x89PNG\r\n\x1a\n", None, 100),
            Err(SkipReason::NotMail)
        );
        assert_eq!(prepare(b"", None, 100), Err(SkipReason::NotMail));
        assert_eq!(
            prepare(b"just some words\n", None, 100),
            Err(SkipReason::NotMail)
        );
        assert_eq!(prepare(ONE, None, 10), Err(SkipReason::TooLarge));
        // Noise of every kind never panics.
        let mut seed: u32 = 1;
        for len in 0..300 {
            let data: Vec<u8> = (0..len)
                .map(|_| {
                    seed = seed.wrapping_mul(1_103_515_245).wrapping_add(12_345);
                    match (seed >> 16) % 9 {
                        0 => b'\n',
                        1 => b':',
                        2 => b'=',
                        3 => b'?',
                        _ => (seed >> 8) as u8,
                    }
                })
                .collect();
            let _ = prepare(&data, None, 1 << 20);
        }
    }

    #[test]
    fn zip_entries_never_leave_the_archive() {
        for subject in [
            "../../etc/passwd",
            "a/b\\c",
            "..",
            "",
            "C:\\x",
            "\u{202E}gpj.exe",
            "nul\0",
        ] {
            let name = entry_name(7, subject);
            assert!(
                !name.contains('/') && !name.contains('\\') && !name.contains(".."),
                "{name}"
            );
            assert!(
                name.starts_with("00007 ") && name.ends_with(".eml"),
                "{name}"
            );
        }
        assert_eq!(
            entry_name(1, "Re: Invoice #12"),
            "00001 Re_ Invoice _12.eml"
        );
        assert_eq!(entry_name(2, "Café"), "00002 Café.eml");
    }

    #[test]
    fn rebuilt_headers_are_encoded() {
        assert_eq!(encoded_word("plain"), "plain");
        assert!(encoded_word("Caffè").starts_with("=?utf-8?b?"));
        assert_eq!(
            mailbox("Ada \"L\"", "ada@example.com"),
            "\"Ada L\" <ada@example.com>"
        );
        assert_eq!(mailbox("", "a b@x"), "ab@x");
    }

    /// A folder in memory, for import tests.
    #[derive(Default)]
    pub(crate) struct Memory {
        pub(crate) messages: Vec<Prepared>,
        pub(crate) limit: u64,
        pub(crate) refuse: bool,
    }

    impl ImportTarget for Memory {
        async fn existing(&mut self) -> Result<HashSet<String>, String> {
            Ok(self.messages.iter().map(|m| m.message_id.clone()).collect())
        }
        fn limit(&self) -> u64 {
            self.limit
        }
        async fn put(&mut self, m: &Prepared) -> Result<(), (bool, String)> {
            if self.refuse {
                return Err((false, "NO [LIMIT] too big".into()));
            }
            self.messages.push(m.clone());
            Ok(())
        }
    }

    fn temp(name: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("piuma-transfer-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn run<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(f)
    }

    #[test]
    fn import_dedupes_resumes_and_reports() {
        let dir = temp("import");
        let mut file = MboxWriter::new(Vec::new());
        file.add(ONE, "ada@example.com", 100, None).unwrap();
        // Twice in the file: imported once.
        file.add(ONE, "ada@example.com", 100, None).unwrap();
        file.add(
            b"Subject: two\r\nX-Gmail-Labels: Starred,Unread\r\n\r\nhi\r\n",
            "",
            200,
            None,
        )
        .unwrap();
        file.add(b"not an email at all", "", 300, None).unwrap();
        let mbox_path = dir.join("Takeout.mbox");
        fs::write(&mbox_path, file.into_inner()).unwrap();
        let eml = dir.join("loose.eml");
        fs::write(
            &eml,
            b"From: c@example.com\nSubject: loose\nMessage-ID: <loose@x>\n\nbody\n",
        )
        .unwrap();
        let junk = dir.join("photo.eml");
        fs::write(&junk, b"\x89PNG\r\n\x1a\n").unwrap();
        let paths = vec![
            mbox_path.clone(),
            eml.clone(),
            junk.clone(),
            dir.join("missing.eml"),
        ];
        let mut folder = Memory {
            limit: 1 << 20,
            ..Default::default()
        };
        let cancel = AtomicBool::new(false);
        let mut last = Progress::default();
        let report = run(import(&mut folder, &paths, &cancel, |p| last = p));
        assert_eq!(report.imported, 3, "{report:?}");
        assert_eq!(report.duplicates, 1);
        assert_eq!(report.skipped_count, 3);
        assert_eq!(report.skipped[0].item, "Takeout.mbox #4");
        assert_eq!(report.skipped[0].reason, SkipReason::NotMail);
        assert_eq!(report.skipped[1].item, "photo.eml");
        assert_eq!(report.skipped[2].reason, SkipReason::Unreadable);
        assert_eq!(last.done, last.total);
        let two = &folder.messages[1];
        assert!(!two.flags.seen && two.flags.flagged);
        assert_eq!(two.at, Some(200));
        assert!(folder.messages[0].flags.seen);
        // Again: everything is already there.
        let again = run(import(&mut folder, &paths, &cancel, |_| {}));
        assert_eq!(again.imported, 0);
        assert_eq!(again.duplicates, 4);
        // Cancelled before it starts.
        cancel.store(true, Ordering::Relaxed);
        let stopped = run(import(&mut Memory::default(), &paths, &cancel, |_| {}));
        assert!(stopped.cancelled && stopped.imported == 0);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn refusals_and_limits() {
        let dir = temp("limits");
        let eml = dir.join("a.eml");
        fs::write(&eml, ONE).unwrap();
        let mut small = Memory {
            limit: 20,
            ..Default::default()
        };
        let cancel = AtomicBool::new(false);
        let r = run(import(
            &mut small,
            std::slice::from_ref(&eml),
            &cancel,
            |_| {},
        ));
        assert_eq!(r.skipped[0].reason, SkipReason::TooLarge);
        let mut refusing = Memory {
            limit: 1 << 20,
            refuse: true,
            ..Default::default()
        };
        let r = run(import(
            &mut refusing,
            std::slice::from_ref(&eml),
            &cancel,
            |_| {},
        ));
        assert!(matches!(r.skipped[0].reason, SkipReason::Refused(_)));
        assert!(r.error.is_none());
        // Five refusals in a row: the server is taken to be gone.
        let many: Vec<PathBuf> = (0..7)
            .map(|i| {
                let p = dir.join(format!("{i}.eml"));
                fs::write(&p, format!("Subject: {i}\r\n\r\nx\r\n")).unwrap();
                p
            })
            .collect();
        let r = run(import(&mut refusing, &many, &cancel, |_| {}));
        assert!(r.error.is_some());
        assert_eq!(r.skipped_count, 4);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn links_are_not_followed() {
        let dir = temp("links");
        let real = dir.join("real.eml");
        fs::write(&real, ONE).unwrap();
        let link = dir.join("link.eml");
        std::os::unix::fs::symlink(&real, &link).unwrap();
        assert_eq!(recognise(&link), Err(SkipReason::NotAFile));
        // An Apple Mail folder whose mbox is a link.
        let bundle = dir.join("Box.mbox");
        fs::create_dir(&bundle).unwrap();
        std::os::unix::fs::symlink(&real, bundle.join("mbox")).unwrap();
        assert_eq!(recognise(&bundle), Err(SkipReason::NotAFile));
        // An export never writes through a link.
        let target = dir.join("target.mbox");
        fs::write(&target, b"keep").unwrap();
        let dest = dir.join("out.mbox");
        std::os::unix::fs::symlink(&target, &dest).unwrap();
        assert!(open_partial(&dest).is_err());
        assert_eq!(fs::read(&target).unwrap(), b"keep");
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn apple_mail_folders_are_read() {
        let dir = temp("apple");
        let bundle = dir.join("Inbox.mbox");
        fs::create_dir(&bundle).unwrap();
        let mut w = MboxWriter::new(Vec::new());
        w.add(ONE, "ada@example.com", 0, None).unwrap();
        fs::write(bundle.join("mbox"), w.into_inner()).unwrap();
        assert_eq!(
            recognise(&bundle),
            Ok(ImportFile::Mbox(bundle.join("mbox")))
        );
        assert_eq!(shown(&bundle.join("mbox")), "Inbox.mbox");
        fs::remove_dir_all(&dir).unwrap();
    }

    /// Messages from a map, for export tests; None as offline.
    struct Fake(Option<std::collections::HashMap<u32, Vec<u8>>>);

    impl ExportSource for Fake {
        async fn fetch(&mut self, _: AccountId, _: &str, uids: &[u32]) -> Result<Fetched, String> {
            let Some(map) = &self.0 else {
                return Err("offline".into());
            };
            Ok(uids.iter().map(|u| (*u, map.get(u).cloned())).collect())
        }
    }

    #[test]
    fn export_then_import_gives_the_same_messages() {
        let dir = temp("roundtrip");
        let store = Mutex::new(Store::open_in_memory().unwrap());
        let account = AccountId(1);
        let mut map = std::collections::HashMap::new();
        let mut messages = Vec::new();
        for uid in 1..=120u32 {
            let raw = format!(
                "From: s{uid}@example.com\r\nSubject: n{uid}\r\nMessage-ID: <m{uid}@example.com>\r\n\r\nFrom line {uid}\r\n>From quoted\r\n\r\n\r\nend\r\n"
            );
            map.insert(uid, raw.into_bytes());
            messages.push((account, "INBOX".to_owned(), uid));
        }
        // One the server no longer has.
        messages.push((account, "INBOX".to_owned(), 999));
        let cancel = AtomicBool::new(false);
        let dest = dir.join("Inbox.mbox");
        let mut count = 0;
        let report = run(export(
            &mut Fake(Some(map.clone())),
            &store,
            &messages,
            ExportFormat::Mbox,
            &dest,
            &cancel,
            |_| count += 1,
        ))
        .unwrap();
        assert_eq!(report.exported, 120);
        assert_eq!(report.skipped_count, 1);
        assert_eq!(count, 121);
        assert!(!dir.join(".Inbox.mbox.part").exists());
        let mut folder = Memory {
            limit: 1 << 20,
            ..Default::default()
        };
        let back = run(import(
            &mut folder,
            std::slice::from_ref(&dest),
            &cancel,
            |_| {},
        ));
        assert_eq!(back.imported, 120, "{back:?}");
        for (i, m) in folder.messages.iter().enumerate() {
            assert_eq!(m.raw, map[&(i as u32 + 1)]);
        }
        // A ZIP of .eml files with the same bytes.
        let zip_path = dir.join("Inbox.zip");
        let report = run(export(
            &mut Fake(Some(map.clone())),
            &store,
            &messages[..3],
            ExportFormat::EmlZip,
            &zip_path,
            &cancel,
            |_| {},
        ))
        .unwrap();
        assert_eq!(report.exported, 3);
        let mut archive = zip::ZipArchive::new(File::open(&zip_path).unwrap()).unwrap();
        assert_eq!(archive.len(), 3);
        let mut first = Vec::new();
        archive
            .by_index(0)
            .unwrap()
            .read_to_end(&mut first)
            .unwrap();
        assert_eq!(first, map[&1]);
        // Offline with nothing downloaded: nothing exported, and said why.
        let offline = run(export(
            &mut Fake(None),
            &store,
            &messages[..2],
            ExportFormat::Mbox,
            &dir.join("offline.mbox"),
            &cancel,
            |_| {},
        ))
        .unwrap();
        assert!(offline.offline);
        assert_eq!(offline.exported, 0);
        assert_eq!(offline.skipped[0].reason, SkipReason::NotDownloaded);
        // Cancelled: no file is left behind.
        cancel.store(true, Ordering::Relaxed);
        let stopped = run(export(
            &mut Fake(Some(map)),
            &store,
            &messages,
            ExportFormat::Mbox,
            &dir.join("stopped.mbox"),
            &cancel,
            |_| {},
        ))
        .unwrap();
        assert!(stopped.cancelled);
        assert!(!dir.join("stopped.mbox").exists());
        assert!(!dir.join(".stopped.mbox.part").exists());
        fs::remove_dir_all(&dir).unwrap();
    }
    #[test]
    fn offline_exports_rebuild_what_was_downloaded() {
        use crate::model::{Account, AccountKind, MessageSummary, Security, Server};
        let dir = temp("offline");
        let mut store = Store::open_in_memory().unwrap();
        let server = Server {
            host: "localhost".into(),
            port: 993,
            security: Security::Tls,
        };
        let account = store
            .add_account(&Account {
                id: AccountId(0),
                name: "Work".into(),
                email: "me@example.org".into(),
                sender_name: String::new(),
                color: "#2F8F83".into(),
                kind: AccountKind::Imap {
                    imap: server.clone(),
                    smtp: server,
                    username: "me".into(),
                },
            })
            .unwrap();
        let row = |uid: u32, subject: &str| MessageSummary {
            account,
            mailbox: "INBOX".into(),
            uid,
            from_name: "Zoë".into(),
            from_email: "zoe@example.org".into(),
            to: String::new(),
            subject: subject.into(),
            preview: String::new(),
            received_at: 1_793_700_000,
            flags: Flags::default(),
            reply: Default::default(),
            list: Default::default(),
        };
        store
            .upsert_messages(&[row(1, "Caffè domani"), row(2, "Never opened")])
            .unwrap();
        store
            .set_full_body(
                account,
                "INBOX",
                1,
                &crate::store::Body {
                    text: "A domani!".into(),
                    html: Some("<p>A domani!</p>".into()),
                    ..Default::default()
                },
            )
            .unwrap();
        let store = Mutex::new(store);
        let dest = dir.join("offline.zip");
        let cancel = AtomicBool::new(false);
        let messages = vec![
            (account, "INBOX".to_owned(), 1),
            (account, "INBOX".to_owned(), 2),
        ];
        let report = run(export(
            &mut Offline,
            &store,
            &messages,
            ExportFormat::EmlZip,
            &dest,
            &cancel,
            |_| {},
        ))
        .unwrap();
        assert!(report.offline);
        assert_eq!((report.exported, report.rebuilt), (1, 1));
        assert_eq!(report.skipped[0].reason, SkipReason::NotDownloaded);
        assert_eq!(report.skipped[0].item, "Never opened");
        let mut archive = zip::ZipArchive::new(File::open(&dest).unwrap()).unwrap();
        let mut raw = Vec::new();
        archive.by_index(0).unwrap().read_to_end(&mut raw).unwrap();
        // It reads as mail, with its text, through the usual parser.
        let read = crate::eml::read(&raw).unwrap();
        assert_eq!(read.subject, "Caffè domani");
        assert_eq!(read.from_name, "Zoë");
        assert!(read.body.text.contains("A domani!"));
        fs::remove_dir_all(&dir).unwrap();
    }

    /// 50,000 messages stream through without being held: an export and
    /// the import of what it wrote.
    #[test]
    fn fifty_thousand_messages_go_through() {
        let dir = temp("fifty");
        let store = Mutex::new(Store::open_in_memory().unwrap());
        let account = AccountId(1);
        let n = 50_000u32;
        let map: std::collections::HashMap<u32, Vec<u8>> = (1..=n)
            .map(|u| {
                (
                    u,
                    format!("Subject: {u}\r\nMessage-ID: <{u}@x>\r\n\r\nFrom {u}\r\n").into_bytes(),
                )
            })
            .collect();
        let messages: Vec<_> = (1..=n).map(|u| (account, "INBOX".to_owned(), u)).collect();
        let dest = dir.join("big.mbox");
        let cancel = AtomicBool::new(false);
        let report = run(export(
            &mut Fake(Some(map)),
            &store,
            &messages,
            ExportFormat::Mbox,
            &dest,
            &cancel,
            |_| {},
        ))
        .unwrap();
        assert_eq!(report.exported, u64::from(n));
        let mut folder = Memory {
            limit: 1 << 20,
            ..Default::default()
        };
        let back = run(import(&mut folder, &[dest], &cancel, |_| {}));
        assert_eq!(back.imported, u64::from(n));
        fs::remove_dir_all(&dir).unwrap();
    }
}
