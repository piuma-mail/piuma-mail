//! What reaches Piuma from outside it: email files opened from the file
//! manager or shared from another app, and the desktop settings that keep
//! it reachable (running in the background, starting at sign-in).
//!
//! Email files are untrusted: they go through the engine's own parser
//! ([`piuma_core::eml`]), are never stored, and nothing in them is
//! fetched. Remote images wait for the usual consent in the reader.

use std::path::Path;

use flutter_rust_bridge::frb;
use piuma_core::eml::{self, EmlError};
use piuma_core::remote::Remote;
use piuma_core::{files, reading, AccountId};

use super::engine::{
    body_block, engine, file_risk, privacy_settings, store, AttachmentInfo, EngineError, ErrorKind,
    ReadableMessage, StoppedTracker, TrackerKind,
};

const KEEP_RUNNING: &str = "desktop.keep_running";
const START_AT_LOGIN: &str = "desktop.start_at_login";

/// How the desktop app behaves when its window is closed, and at sign-in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DesktopSettings {
    /// Closing the window leaves Piuma running, in the tray, so new mail
    /// still shows notifications. On unless turned off on Windows and
    /// Linux; elsewhere the system decides.
    pub keep_running: bool,
    /// Piuma starts, without its window, when the person signs in.
    pub start_at_login: bool,
}

/// Whether closing the window keeps the app running where nothing was
/// chosen yet: on Windows and Linux, where closing used to quit.
const KEEP_RUNNING_DEFAULT: bool = cfg!(any(target_os = "windows", target_os = "linux"));

#[frb(sync)]
pub fn desktop_settings() -> Result<DesktopSettings, EngineError> {
    let store = store()?;
    Ok(DesktopSettings {
        keep_running: match store.setting(KEEP_RUNNING)?.as_deref() {
            None => KEEP_RUNNING_DEFAULT,
            Some(v) => v != "false",
        },
        start_at_login: store.setting(START_AT_LOGIN)?.as_deref() == Some("true"),
    })
}

pub fn set_desktop_settings(settings: DesktopSettings) -> Result<(), EngineError> {
    let store = store()?;
    store.set_setting(KEEP_RUNNING, &settings.keep_running.to_string())?;
    store.set_setting(START_AT_LOGIN, &settings.start_at_login.to_string())?;
    Ok(())
}

/// An email file, read for the reader.
#[derive(Debug, Clone)]
pub struct EmlFile {
    pub from_name: String,
    pub from_email: String,
    pub to: Vec<String>,
    pub cc: Vec<String>,
    pub subject: String,
    /// Seconds since the epoch, when it says.
    pub date: Option<i64>,
    pub readable: ReadableMessage,
}

fn eml_error(e: EmlError) -> EngineError {
    EngineError::new(
        match e {
            EmlError::TooLarge => ErrorKind::TooBig,
            _ => ErrorKind::Other,
        },
        e.to_string(),
    )
}

fn load(path: &str) -> Result<(Vec<u8>, eml::EmlMessage), EngineError> {
    let raw = eml::load(Path::new(path)).map_err(eml_error)?;
    let message = eml::read(&raw).map_err(eml_error)?;
    Ok((raw, message))
}

/// Reads the email file at `path` (at most 50 MB): its headers, and its
/// body made safe to read exactly like a synced message's. Pictures inside
/// it show; remote ones wait for consent; nothing is stored or fetched.
pub async fn open_eml(path: String) -> Result<EmlFile, EngineError> {
    let (_, m) = load(&path)?;
    let settings = privacy_settings()?;
    let body = m.body;
    let mut r = reading::readable_with(
        &body.text,
        body.html.as_deref(),
        reading::Options {
            stop_pixels: settings.stop_pixels,
            clean_links: settings.clean_links,
            warn_links: settings.warn_links,
        },
    );
    // Pictures inside the file come from its own parts.
    r.blocks.retain_mut(|b| {
        let Some(image) = b.image.as_mut() else {
            return true;
        };
        let Some(cid) = image.cid.take() else {
            return true;
        };
        image.data = body
            .inline
            .iter()
            .find(|i| i.cid == cid)
            .map(|i| i.data.clone());
        image.data.is_some()
    });
    let readable = ReadableMessage {
        language: piuma_core::language::of_readable(&r).map(str::to_owned),
        layout: false,
        invite: None,
        dates: Vec::new(),
        // A file is nobody's verified mail: its images always ask.
        trusted: false,
        block_images: true,
        remote_images: r.remote_images,
        links_cleaned: r.links_cleaned,
        trackers: r
            .trackers
            .into_iter()
            .map(|t| StoppedTracker {
                kind: match t.kind {
                    reading::TrackerKind::Pixel => TrackerKind::Pixel,
                    reading::TrackerKind::Font => TrackerKind::Font,
                    reading::TrackerKind::Style => TrackerKind::Style,
                },
                host: t.host,
                count: t.count,
            })
            .collect(),
        blocks: r.blocks.into_iter().map(body_block).collect(),
        attachments: body
            .attachments
            .into_iter()
            .map(|a| AttachmentInfo {
                part_id: a.part,
                risk: file_risk(&a.name),
                name: a.name,
                mime: a.mime,
                size: a.size,
            })
            .collect(),
    };
    Ok(EmlFile {
        from_name: m.from_name,
        from_email: m.from_email,
        to: m.to,
        cc: m.cc,
        subject: m.subject,
        date: m.date,
        readable,
    })
}

/// Saves one file attached to the email file at `path` in `folder`, under
/// a name no other file there has (only the name it gives is kept, never
/// a path). Returns the saved file's path.
pub async fn save_eml_attachment(
    path: String,
    part_id: u32,
    folder: String,
) -> Result<String, EngineError> {
    let (raw, m) = load(&path)?;
    let file = m
        .body
        .attachments
        .iter()
        .find(|a| a.part == part_id)
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "no such attachment"))?;
    let data = piuma_core::imap::attachment_data(&raw, part_id)
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "no such attachment"))?;
    let saved = files::save_new(Path::new(&folder), &file.name, &data)
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?;
    Ok(saved.to_string_lossy().into_owned())
}

/// Puts the email file at `path` in one of an account's folders on its
/// server, as read; the next sync of that folder brings it into the app.
pub async fn import_eml(account_id: i64, mailbox: String, path: String) -> Result<(), EngineError> {
    let engine = engine()?;
    let id = AccountId(account_id);
    // Only something that reads as mail goes to the server.
    let (raw, _) = load(&path)?;
    let account = store()?
        .account(id)?
        .ok_or_else(|| EngineError::new(ErrorKind::Other, "unknown account"))?;
    let password = crate::login::load(id)?;
    engine
        .runtime
        .spawn(async move {
            let mut conn = Remote::open(&account, &password).await?;
            let put = conn.append_to(&mailbox, &raw).await;
            conn.close().await;
            put
        })
        .await
        .map_err(|e| EngineError::new(ErrorKind::Other, e.to_string()))?
        .map_err(EngineError::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeping_running_is_the_default_where_closing_used_to_quit() {
        assert_eq!(
            KEEP_RUNNING_DEFAULT,
            cfg!(any(target_os = "windows", target_os = "linux"))
        );
    }

    #[test]
    fn a_file_that_is_not_mail_says_so() {
        let dir = std::env::temp_dir().join(format!("piuma-outside-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("photo.eml");
        std::fs::write(&path, b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR").unwrap();
        let e = load(path.to_str().unwrap()).unwrap_err();
        assert_eq!(e.kind, ErrorKind::Other);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
