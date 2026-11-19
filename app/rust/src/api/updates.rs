//! Updates. On Windows, through Velopack: the installer, a background
//! check against a release feed, the download and the restart that
//! applies it. The feed is a GitHub repository's Releases or any web
//! folder `vpk upload` filled. On Android, macOS and Linux the app only
//! says that a newer release exists (`updates_notice`); nothing is
//! installed for the user.
//! The app draws the notice, the "What's new" sheet and the toast.
//!
//! The channel is explicit: "beta" follows GitHub prereleases, "stable"
//! only full releases (`PIUMA_UPDATE_CHANNEL` at build time). Early
//! (canary) releases are followed only when the user opted in.
//!
//! A launch marker lets a release that crashes while starting heal
//! itself: `updates_startup` leaves it, `updates_launched` (the first
//! frame) removes it. Found at the next start, the previous launch never
//! got that far, and on Windows the update check runs at once, before
//! the engine opens, and restarts into a newer release when there is one.
//!
//! In a build not installed by the installer (`flutter run`) the Windows
//! calls are quiet no-ops.

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
    /// The previous launch never drew its first frame.
    pub previous_launch_failed: bool,
}

/// A newer release where the app cannot install it (Android, macOS,
/// Linux): the notice links to its page.
#[derive(Debug, Clone)]
pub struct UpdateNotice {
    pub release: UpdateRelease,
    /// The release's page on the feed.
    pub url: String,
}

/// The user's choices in Settings › Help & feedback › Updates.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UpdatePrefs {
    /// Look for new versions on its own (on by default). Off, nothing
    /// is asked of the feed until "Check for updates".
    pub automatic: bool,
    /// Follow early (canary) releases too (off by default).
    pub early: bool,
}

impl Default for UpdatePrefs {
    fn default() -> Self {
        Self {
            automatic: true,
            early: false,
        }
    }
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
/// `support_dir` is the app's support folder, where notes wait; `feed`
/// and `channel` are the build's (`PIUMA_UPDATE_URL`,
/// `PIUMA_UPDATE_CHANNEL`).
///
/// When the previous launch never reached its first frame (see
/// `updates_launched`) and automatic checks are on, an installed
/// Windows app looks for a newer release right here and restarts into
/// it, so a release that crashes at launch is replaced by the next one.
#[frb(sync)]
pub fn updates_startup(support_dir: String, feed: String, channel: String) -> UpdateStartup {
    let _ = NOTES_DIR.set(PathBuf::from(support_dir).join("updates"));
    // Before Velopack's first download: it brings a second TLS library.
    piuma_core::tls::use_one_crypto_provider();
    #[cfg(target_os = "windows")]
    {
        velopack::VelopackApp::build()
            .set_app_user_model_id(AUMID)
            .on_restarted(|v| *UPDATED_TO.lock().unwrap() = Some(v.to_string()))
            .run();
        // After the installer's hooks, which end the process here: they
        // are not launches.
        let previous_launch_failed = leave_marker();
        let installed = manager(None, &channel).is_ok();
        if installed && previous_launch_failed && !feed.is_empty() && updates_prefs().automatic {
            // Returns only when there is nothing newer, or it failed: the
            // launch goes on as usual.
            if let Err(e) = heal(&feed, &channel) {
                log::warn!("updates: no fix found after a failed launch: {e}");
            }
        }
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
            previous_launch_failed,
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (feed, channel);
        let previous_launch_failed = leave_marker();
        UpdateStartup {
            previous_launch_failed,
            ..UpdateStartup::default()
        }
    }
}

/// The first frame is on screen: this launch worked, so the next one
/// need not look for a fix first.
#[frb(sync)]
pub fn updates_launched() {
    if let Some(path) = marker_file() {
        let _ = std::fs::remove_file(path);
    }
}

/// The user's choices in Settings › Help & feedback › Updates; the defaults until they
/// change one.
#[frb(sync)]
pub fn updates_prefs() -> UpdatePrefs {
    prefs_file()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .map(|text| parse_prefs(&text))
        .unwrap_or_default()
}

/// Keeps the user's choices in Settings › Help & feedback › Updates.
#[frb(sync)]
pub fn updates_set_prefs(prefs: UpdatePrefs) -> Result<(), EngineError> {
    let path = prefs_file().ok_or_else(|| err("not started"))?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(err)?;
    }
    std::fs::write(path, format_prefs(prefs)).map_err(err)
}

/// Asks the feed for a newer release; `None` when there is none, or
/// this build cannot update.
pub fn updates_check(feed: String, channel: String) -> Result<Option<UpdateRelease>, EngineError> {
    #[cfg(target_os = "windows")]
    {
        let Ok(m) = manager(Some(&feed), &channel) else {
            return Ok(None);
        };
        match m.check_for_updates().map_err(err)? {
            velopack::UpdateCheck::UpdateAvailable(info) => Ok(Some(release(&info))),
            _ => Ok(None),
        }
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (feed, channel);
        Ok(None)
    }
}

/// Where the app cannot install updates (Android, macOS, Linux): a
/// release newer than `build` on `feed`, for a notice with a link to its
/// page. `None` when there is none, on Windows and iOS, and for a feed
/// that is not a GitHub repository.
pub async fn updates_notice(
    feed: String,
    channel: String,
    build: u32,
) -> Result<Option<UpdateNotice>, EngineError> {
    use piuma_core::release_feed::{check, Follow, Platform};
    let Some(platform) = Platform::current() else {
        return Ok(None);
    };
    let follow = Follow {
        prereleases: follows_prereleases(&channel),
        early: updates_prefs().early,
    };
    let offer = check(&feed, platform, follow, build).await.map_err(err)?;
    Ok(offer.map(|o| UpdateNotice {
        release: UpdateRelease {
            version: o.version,
            notes: o.notes,
            size: 0,
        },
        url: o.url,
    }))
}

/// Downloads the newest release, reporting progress from 0 to 100; the
/// stream ends once it is ready for the restart (`updates_ready`), or
/// at once when the feed has nothing newer by now.
pub fn updates_download(
    feed: String,
    channel: String,
    progress: StreamSink<i32>,
) -> Result<(), EngineError> {
    #[cfg(target_os = "windows")]
    {
        let Ok(m) = manager(Some(&feed), &channel) else {
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
        let _ = (feed, channel, progress);
        Ok(())
    }
}

/// A release downloaded and waiting for the restart, if any.
#[frb(sync)]
pub fn updates_ready() -> Option<UpdateRelease> {
    #[cfg(target_os = "windows")]
    {
        let asset = manager(None, "").ok()?.get_update_pending_restart()?;
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
        let m = manager(None, "").map_err(err)?;
        let asset = m
            .get_update_pending_restart()
            .ok_or_else(|| err("no update waiting"))?;
        m.apply_updates_and_restart(&asset).map_err(err)
    }
    #[cfg(not(target_os = "windows"))]
    Err(err("updates only work on Windows for now"))
}

/// The build's channel takes GitHub prereleases: "stable" does not,
/// "beta" (and anything else) does.
fn follows_prereleases(channel: &str) -> bool {
    channel != "stable"
}

/// The Velopack channel to read: the one this copy was installed from
/// ("win", "win-arm64"), with "-canary" when early releases are on.
/// Always explicit, so turning early releases off goes back to the
/// regular channel.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
fn velopack_channel(installed: &str, early: bool) -> String {
    let base = installed.strip_suffix("-canary").unwrap_or(installed);
    let base = if base.is_empty() { "win" } else { base };
    if early {
        format!("{base}-canary")
    } else {
        base.to_owned()
    }
}

/// A manager for the installed app; reading the feed when one is given,
/// in the channel the build and the user's choice say.
#[cfg(target_os = "windows")]
fn manager(feed: Option<&str>, channel: &str) -> Result<velopack::UpdateManager, velopack::Error> {
    use velopack::locator::{auto_locate_app_manifest, LocationContext};
    use velopack::sources::{GithubSource, HttpSource, NoneSource};
    use velopack::{UpdateManager, UpdateOptions};
    let installed =
        auto_locate_app_manifest(LocationContext::FromCurrentExe)?.get_manifest_channel();
    let options = UpdateOptions {
        ExplicitChannel: Some(velopack_channel(&installed, updates_prefs().early)),
        ..UpdateOptions::default()
    };
    match feed {
        Some(f) if f.starts_with("https://github.com/") => UpdateManager::new(
            GithubSource::new(f, None, follows_prereleases(channel)),
            Some(options),
            None,
        ),
        Some(f) => UpdateManager::new(HttpSource::new(f), Some(options), None),
        None => UpdateManager::new(NoneSource {}, Some(options), None),
    }
}

/// After a launch that never drew its first frame: a newer release, if
/// the feed has one, downloaded and restarted into at once. Returns only
/// when there is none (or on an error).
#[cfg(target_os = "windows")]
fn heal(feed: &str, channel: &str) -> Result<(), velopack::Error> {
    let m = manager(Some(feed), channel)?;
    if let velopack::UpdateCheck::UpdateAvailable(info) = m.check_for_updates()? {
        log::warn!(
            "updates: the last launch failed; moving to {} before opening the engine",
            info.TargetFullRelease.Version
        );
        m.download_updates(&info, None)?;
        save_notes(&release(&info));
        m.apply_updates_and_restart(&info.TargetFullRelease)?;
        // Velopack restarts the app into the new release, which should
        // not look again.
        updates_launched();
        std::process::exit(0);
    }
    Ok(())
}

fn marker_file() -> Option<PathBuf> {
    Some(NOTES_DIR.get()?.join("launching"))
}

fn prefs_file() -> Option<PathBuf> {
    Some(NOTES_DIR.get()?.join("settings"))
}

/// Leaves the launch marker; true when the last one was still there,
/// i.e. the previous launch never drew its first frame.
fn leave_marker() -> bool {
    let Some(path) = marker_file() else {
        return false;
    };
    let failed = path.exists();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(&path, b"");
    failed
}

fn parse_prefs(text: &str) -> UpdatePrefs {
    let mut prefs = UpdatePrefs::default();
    for line in text.lines() {
        match line.trim() {
            "automatic=0" => prefs.automatic = false,
            "automatic=1" => prefs.automatic = true,
            "early=1" => prefs.early = true,
            "early=0" => prefs.early = false,
            _ => {}
        }
    }
    prefs
}

fn format_prefs(p: UpdatePrefs) -> String {
    format!(
        "automatic={}\nearly={}\n",
        u8::from(p.automatic),
        u8::from(p.early)
    )
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
        // The launch marker, in the same folder (one test: it is set once).
        assert!(!leave_marker(), "a first launch did not fail");
        assert!(leave_marker(), "no first frame: the next launch knows");
        updates_launched();
        assert!(!leave_marker(), "after the first frame all is well");
        updates_launched();
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn choices_read_back_as_written() {
        let both = UpdatePrefs {
            automatic: false,
            early: true,
        };
        assert_eq!(parse_prefs(&format_prefs(both)), both);
        assert_eq!(parse_prefs(""), UpdatePrefs::default());
        assert_eq!(
            parse_prefs("junk\nearly=1"),
            UpdatePrefs {
                automatic: true,
                early: true
            }
        );
        assert!(UpdatePrefs::default().automatic);
        assert!(!UpdatePrefs::default().early);
    }

    #[test]
    fn the_channel_is_always_explicit() {
        assert_eq!(velopack_channel("win", false), "win");
        assert_eq!(velopack_channel("win", true), "win-canary");
        assert_eq!(velopack_channel("win-arm64", true), "win-arm64-canary");
        // Installed from an early release, turned off: back to the regular one.
        assert_eq!(velopack_channel("win-arm64-canary", false), "win-arm64");
        assert_eq!(velopack_channel("", false), "win");
        assert!(follows_prereleases("beta"));
        assert!(!follows_prereleases("stable"));
    }
}
