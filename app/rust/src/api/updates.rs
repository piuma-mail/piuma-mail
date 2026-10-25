//! Desktop updates, through Velopack: the installer, a background check
//! against a release feed, the download and the restart that applies it.
//! The feed is any web folder `vpk upload` filled (a Cloudflare R2 bucket
//! while the repository is private) or a GitHub repository's Releases.
//! The app draws the notice, the "What's new" sheet and the toast.
//!
//! Only Windows for now. Elsewhere, and in a build not installed by the
//! installer (`flutter run`), every call is a quiet no-op.

use std::path::PathBuf;
#[cfg(target_os = "windows")]
use std::sync::Mutex;
use std::sync::OnceLock;

use flutter_rust_bridge::frb;

use super::engine::{EngineError, ErrorKind};
use crate::frb_generated::StreamSink;

/// The id notifications are shown under (as in the app's notifier), so
/// toasts keep working once the installer made the Start menu shortcut.
#[cfg(target_os = "windows")]
const AUMID: &str = "Piuma.PiumaMail";

/// A release offered by the feed, or downloaded and waiting.
#[derive(Debug, Clone)]
pub struct UpdateRelease {
    /// As packaged, e.g. "0.1.0-beta.612".
    pub version: String,
    /// The changelog, in Markdown; empty when the release has none.
    pub notes: String,
    /// Bytes to download: the delta when there is one, else the package.
    pub size: u64,
}

/// What `updates_startup` saw.
#[derive(Debug, Clone, Default)]
pub struct UpdateStartup {
    /// Installed by the installer, so updates can work at all.
    pub installed: bool,
    /// Restarted into a new version: the version and its notes, for the
    /// one-time "Updated to …" toast.
    pub updated_to: Option<UpdateRelease>,
}

#[cfg(target_os = "windows")]
static UPDATED_TO: Mutex<Option<String>> = Mutex::new(None);
/// Where the notes of a downloaded release wait for the restart.
static NOTES_DIR: OnceLock<PathBuf> = OnceLock::new();

fn err(e: impl std::fmt::Display) -> EngineError {
    EngineError::new(ErrorKind::Other, format!("updates: {e}"))
}

/// The first thing the app runs, before the engine opens. On the
/// installer's hooks it does its part and ends the process; with an
/// update downloaded earlier it applies it and restarts into it.
/// `support_dir` is the app's support folder, where notes wait.
#[frb(sync)]
pub fn updates_startup(support_dir: String) -> UpdateStartup {
    let _ = NOTES_DIR.set(PathBuf::from(support_dir).join("updates"));
    // Before Velopack's first download: it brings a second TLS library.
    piuma_core::tls::use_one_crypto_provider();
    #[cfg(target_os = "windows")]
    {
        velopack::VelopackApp::build()
            .set_app_user_model_id(AUMID)
            .on_restarted(|v| *UPDATED_TO.lock().unwrap() = Some(v.to_string()))
            .run();
        let installed = manager(None).is_ok();
        let updated_to = UPDATED_TO
            .lock()
            .unwrap()
            .take()
            .map(|version| UpdateRelease {
                notes: saved_notes(&version).unwrap_or_default(),
                version,
                size: 0,
            });
        UpdateStartup {
            installed,
            updated_to,
        }
    }
    #[cfg(not(target_os = "windows"))]
    UpdateStartup::default()
}

/// Asks the feed for a newer release; `None` when there is none, or
/// this build cannot update.
pub fn updates_check(feed: String) -> Result<Option<UpdateRelease>, EngineError> {
    #[cfg(target_os = "windows")]
    {
        let Ok(m) = manager(Some(&feed)) else {
            return Ok(None);
        };
        match m.check_for_updates().map_err(err)? {
            velopack::UpdateCheck::UpdateAvailable(info) => Ok(Some(release(&info))),
            _ => Ok(None),
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = feed;
        Ok(None)
    }
}

/// Downloads the newest release, reporting progress from 0 to 100; the
/// stream ends once it is ready for the restart (`updates_ready`), or
/// at once when the feed has nothing newer by now.
pub fn updates_download(feed: String, progress: StreamSink<i32>) -> Result<(), EngineError> {
    #[cfg(target_os = "windows")]
    {
        let Ok(m) = manager(Some(&feed)) else {
            return Ok(());
        };
        let velopack::UpdateCheck::UpdateAvailable(info) = m.check_for_updates().map_err(err)?
        else {
            return Ok(());
        };
        let (tx, rx) = std::sync::mpsc::channel::<i16>();
        let relay = std::thread::spawn(move || {
            for p in rx {
                let _ = progress.add(i32::from(p));
            }
        });
        let done = m.download_updates(&info, Some(tx));
        let _ = relay.join();
        done.map_err(err)?;
        save_notes(&release(&info));
        Ok(())
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (feed, progress);
        Ok(())
    }
}

/// A release downloaded and waiting for the restart, if any.
#[frb(sync)]
pub fn updates_ready() -> Option<UpdateRelease> {
    #[cfg(target_os = "windows")]
    {
        let asset = manager(None).ok()?.get_update_pending_restart()?;
        Some(UpdateRelease {
            notes: if asset.NotesMarkdown.is_empty() {
                saved_notes(&asset.Version).unwrap_or_default()
            } else {
                asset.NotesMarkdown
            },
            version: asset.Version,
            size: asset.Size,
        })
    }
    #[cfg(not(target_os = "windows"))]
    None
}

/// Closes the app, applies the waiting release and opens it again. Mail
/// and drafts are in the database, so nothing is lost.
pub fn updates_restart() -> Result<(), EngineError> {
    #[cfg(target_os = "windows")]
    {
        let m = manager(None).map_err(err)?;
        let asset = m
            .get_update_pending_restart()
            .ok_or_else(|| err("no update waiting"))?;
        m.apply_updates_and_restart(&asset).map_err(err)
    }
    #[cfg(not(target_os = "windows"))]
    Err(err("updates only work on Windows for now"))
}

/// A manager for the installed app; reading the feed when one is given.
#[cfg(target_os = "windows")]
fn manager(feed: Option<&str>) -> Result<velopack::UpdateManager, velopack::Error> {
    use velopack::sources::{GithubSource, HttpSource, NoneSource};
    use velopack::UpdateManager;
    match feed {
        Some(f) if f.starts_with("https://github.com/") => {
            UpdateManager::new(GithubSource::new(f, None, false), None, None)
        }
        Some(f) => UpdateManager::new(HttpSource::new(f), None, None),
        None => UpdateManager::new(NoneSource {}, None, None),
    }
}

#[cfg(target_os = "windows")]
fn release(info: &velopack::UpdateInfo) -> UpdateRelease {
    let target = &info.TargetFullRelease;
    let size = if info.DeltasToTarget.is_empty() {
        target.Size
    } else {
        info.DeltasToTarget.iter().map(|d| d.Size).sum()
    };
    UpdateRelease {
        version: target.Version.clone(),
        notes: target.NotesMarkdown.clone(),
        size,
    }
}

fn notes_file(version: &str) -> Option<PathBuf> {
    let safe: String = version
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '+'))
        .collect();
    Some(NOTES_DIR.get()?.join(format!("{safe}.md")))
}

#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn save_notes(r: &UpdateRelease) {
    if let Some(path) = notes_file(&r.version) {
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(path, &r.notes);
    }
}

#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn saved_notes(version: &str) -> Option<String> {
    std::fs::read_to_string(notes_file(version)?).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notes_wait_for_the_restart() {
        let dir = std::env::temp_dir().join(format!("piuma-updates-{}", std::process::id()));
        let _ = NOTES_DIR.set(dir.join("updates"));
        let r = UpdateRelease {
            version: "0.1.0-beta.612".into(),
            notes: "- Faster search".into(),
            size: 0,
        };
        save_notes(&r);
        assert_eq!(
            saved_notes("0.1.0-beta.612").as_deref(),
            Some("- Faster search")
        );
        assert_eq!(saved_notes("0.1.0-beta.613"), None);
        // A version never names a file outside the folder.
        let odd = notes_file("../../evil").unwrap();
        assert_eq!(odd.parent(), NOTES_DIR.get().map(|d| d.as_path()));
        let _ = std::fs::remove_dir_all(dir);
    }
}
