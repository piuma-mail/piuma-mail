//! "A new version is available", where the app cannot update itself
//! (Android, macOS, Linux): the newest release of the project's GitHub
//! repository that this build may follow, read from GitHub's API. Nothing
//! is downloaded or installed; the app shows a notice with a link.
//!
//! The releases are the ones the "Release" workflow publishes: tags
//! `v0.1.0-beta.N` (the beta channel, GitHub prereleases) and
//! `canary-v0.1.0-beta.N` (early releases, followed only when the user
//! opted in). N, the build number, orders them; drafts are never offered.

use std::time::Duration;

/// The kind of package a platform installs from a release.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Android,
    Macos,
    Linux,
}

impl Platform {
    /// The platform this engine was built for, where a notice makes sense.
    pub fn current() -> Option<Platform> {
        if cfg!(target_os = "android") {
            Some(Platform::Android)
        } else if cfg!(target_os = "macos") {
            Some(Platform::Macos)
        } else if cfg!(target_os = "linux") {
            Some(Platform::Linux)
        } else {
            None
        }
    }

    /// The release asset this platform installs: the phone APK (not the
    /// watch's), the Linux AppImage for this processor, the macOS archive.
    fn wants(self, asset: &str) -> bool {
        let name = asset.to_ascii_lowercase();
        match self {
            Platform::Android => name.ends_with(".apk") && !name.contains("wear"),
            Platform::Linux => name.ends_with(".appimage") && name.contains(std::env::consts::ARCH),
            Platform::Macos => {
                name.contains("macos") && (name.ends_with(".zip") || name.ends_with(".dmg"))
            }
        }
    }
}

/// Which releases a build follows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Follow {
    /// GitHub prereleases too (the beta channel); off for a stable build.
    pub prereleases: bool,
    /// Early (canary) releases too: only when the user opted in.
    pub early: bool,
}

/// A newer release this build may move to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Offer {
    /// As packaged, e.g. "0.1.0-beta.812".
    pub version: String,
    /// The build number, the N in the version.
    pub build: u32,
    /// The changelog, in Markdown.
    pub notes: String,
    /// The release's page, where the package is downloaded.
    pub url: String,
}

/// The longest changelog kept, in bytes.
const MAX_NOTES: usize = 20_000;
/// The largest answer read from GitHub.
const MAX_BODY: usize = 2 << 20;

/// `https://github.com/owner/name` → the repository's API address for
/// its releases; `None` for any other feed (a plain web folder of
/// Velopack packages has no page to point a phone at).
pub fn api_url(feed: &str) -> Option<String> {
    let rest = feed
        .trim_end_matches('/')
        .strip_prefix("https://github.com/")?;
    let (owner, name) = rest.split_once('/')?;
    let ok = |s: &str| {
        !s.is_empty()
            && s.chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
    };
    if !ok(owner) || !ok(name) || name.contains('/') {
        return None;
    }
    Some(format!(
        "https://api.github.com/repos/{owner}/{name}/releases?per_page=30"
    ))
}

/// The tag's parts: whether it is an early release, the version and its
/// build number. `None` for tags the workflow does not make.
fn parse_tag(tag: &str) -> Option<(bool, String, u32)> {
    let (early, rest) = match tag.strip_prefix("canary-") {
        Some(r) => (true, r),
        None => (false, tag),
    };
    let version = rest.strip_prefix('v')?;
    if version.is_empty()
        || !version
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-'))
    {
        return None;
    }
    let build = version.rsplit('.').next()?.parse().ok()?;
    Some((early, version.to_owned(), build))
}

/// The newest release in GitHub's answer (`json`) that `platform` can
/// install, that `follow` allows and that is newer than `build`.
/// A build without a number (`0`, a developer's) is never offered one.
pub fn newest(
    json: &str,
    feed: &str,
    platform: Platform,
    follow: Follow,
    build: u32,
) -> Option<Offer> {
    if build == 0 {
        return None;
    }
    let releases: Vec<serde_json::Value> = serde_json::from_str(json).ok()?;
    let page = feed.trim_end_matches('/');
    releases
        .iter()
        .filter_map(|r| {
            if r["draft"].as_bool() != Some(false) {
                return None;
            }
            if r["prerelease"].as_bool() == Some(true) && !follow.prereleases {
                return None;
            }
            let tag = r["tag_name"].as_str()?;
            let (early, version, n) = parse_tag(tag)?;
            if (early && !follow.early) || n <= build {
                return None;
            }
            let assets = r["assets"].as_array()?;
            if !assets
                .iter()
                .filter_map(|a| a["name"].as_str())
                .any(|name| platform.wants(name))
            {
                return None;
            }
            let mut notes = r["body"].as_str().unwrap_or_default().to_owned();
            if notes.len() > MAX_NOTES {
                let mut end = MAX_NOTES;
                while !notes.is_char_boundary(end) {
                    end -= 1;
                }
                notes.truncate(end);
            }
            Some(Offer {
                version,
                build: n,
                notes,
                // Made here, not taken from the answer: the link always
                // goes to the feed's own releases.
                url: format!("{page}/releases/tag/{tag}"),
            })
        })
        .max_by_key(|o| o.build)
}

/// Asks `feed` (a GitHub repository) for a release newer than `build`.
pub async fn check(
    feed: &str,
    platform: Platform,
    follow: Follow,
    build: u32,
) -> Result<Option<Offer>, String> {
    let Some(url) = api_url(feed) else {
        return Ok(None);
    };
    if build == 0 {
        return Ok(None);
    }
    let client = crate::tls::http_client()
        .timeout(Duration::from_secs(20))
        // GitHub's API wants a user agent; a generic one, nothing about
        // the user.
        .user_agent("PiumaMail-update-check")
        .redirect(reqwest::redirect::Policy::limited(3))
        .build()
        .map_err(|e| e.to_string())?;
    let mut response = client
        .get(url)
        .header("Accept", "application/vnd.github+json")
        .send()
        .await
        .map_err(|e| e.to_string())?
        .error_for_status()
        .map_err(|e| e.to_string())?;
    let mut body = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(|e| e.to_string())? {
        if body.len() + chunk.len() > MAX_BODY {
            return Err("the release list is too large".into());
        }
        body.extend_from_slice(&chunk);
    }
    let json = String::from_utf8_lossy(&body);
    Ok(newest(&json, feed, platform, follow, build))
}

#[cfg(test)]
mod tests {
    use super::*;

    const FEED: &str = "https://github.com/piuma-mail/piuma-mail";
    const BETA: Follow = Follow {
        prereleases: true,
        early: false,
    };

    fn release(tag: &str, prerelease: bool, draft: bool, assets: &[&str]) -> serde_json::Value {
        serde_json::json!({
            "tag_name": tag,
            "prerelease": prerelease,
            "draft": draft,
            "body": format!("Notes for {tag}"),
            "html_url": "https://evil.example/",
            "assets": assets.iter().map(|a| serde_json::json!({"name": a})).collect::<Vec<_>>(),
        })
    }

    fn list(items: &[serde_json::Value]) -> String {
        serde_json::Value::Array(items.to_vec()).to_string()
    }

    #[test]
    fn only_github_repositories_have_an_api_address() {
        assert_eq!(
            api_url("https://github.com/piuma-mail/piuma-mail/").as_deref(),
            Some("https://api.github.com/repos/piuma-mail/piuma-mail/releases?per_page=30")
        );
        assert_eq!(api_url("https://example.org/updates"), None);
        assert_eq!(api_url("http://github.com/a/b"), None);
        assert_eq!(api_url("https://github.com/a/b/c"), None);
        assert_eq!(api_url("https://github.com/a/b?x=1"), None);
    }

    #[test]
    fn tags_give_the_build_number() {
        assert_eq!(
            parse_tag("v0.1.0-beta.812"),
            Some((false, "0.1.0-beta.812".into(), 812))
        );
        assert_eq!(
            parse_tag("canary-v0.1.0-beta.813"),
            Some((true, "0.1.0-beta.813".into(), 813))
        );
        assert_eq!(parse_tag("v1.2.0"), Some((false, "1.2.0".into(), 0)));
        assert_eq!(parse_tag("nightly"), None);
        assert_eq!(parse_tag("v0.1.0-beta.x"), None);
        assert_eq!(parse_tag("v0.1.0/../x.5"), None);
    }

    #[test]
    fn offers_the_newest_release_this_platform_installs() {
        let json = list(&[
            release(
                "v0.1.0-beta.810",
                true,
                false,
                &["PiumaMail-android-arm64.apk"],
            ),
            release(
                "v0.1.0-beta.812",
                true,
                false,
                &["PiumaMail-android-arm64.apk", "PiumaMail-wear.apk"],
            ),
            release("v0.1.0-beta.811", true, false, &["PiumaMail-win-Setup.exe"]),
        ]);
        let offer = newest(&json, FEED, Platform::Android, BETA, 800).unwrap();
        assert_eq!(offer.version, "0.1.0-beta.812");
        assert_eq!(offer.build, 812);
        assert_eq!(offer.notes, "Notes for v0.1.0-beta.812");
        // The page comes from the feed, never from the answer.
        assert_eq!(offer.url, format!("{FEED}/releases/tag/v0.1.0-beta.812"));
        // Already there: nothing to offer.
        assert_eq!(newest(&json, FEED, Platform::Android, BETA, 812), None);
        // A release with nothing for this platform is skipped.
        assert_eq!(newest(&json, FEED, Platform::Macos, BETA, 800), None);
    }

    #[test]
    fn the_watch_package_is_not_the_phone_app() {
        let json = list(&[release(
            "v0.1.0-beta.812",
            true,
            false,
            &["PiumaMail-wear.apk"],
        )]);
        assert_eq!(newest(&json, FEED, Platform::Android, BETA, 800), None);
    }

    #[test]
    fn drafts_early_releases_and_prereleases_follow_the_channel() {
        let json = list(&[
            release(
                "v0.1.0-beta.815",
                true,
                true,
                &["PiumaMail-android-arm64.apk"],
            ),
            release(
                "canary-v0.1.0-beta.814",
                true,
                false,
                &["PiumaMail-android-arm64.apk"],
            ),
            release(
                "v0.1.0-beta.813",
                true,
                false,
                &["PiumaMail-android-arm64.apk"],
            ),
            release(
                "v0.1.0-beta.812",
                false,
                false,
                &["PiumaMail-android-arm64.apk"],
            ),
        ]);
        let pick = |follow| newest(&json, FEED, Platform::Android, follow, 800).map(|o| o.build);
        assert_eq!(pick(BETA), Some(813));
        assert_eq!(
            pick(Follow {
                prereleases: true,
                early: true
            }),
            Some(814)
        );
        assert_eq!(
            pick(Follow {
                prereleases: false,
                early: false
            }),
            Some(812)
        );
    }

    #[test]
    fn a_developer_build_is_never_offered_a_release() {
        let json = list(&[release(
            "v0.1.0-beta.900",
            true,
            false,
            &["PiumaMail-android-arm64.apk"],
        )]);
        assert_eq!(newest(&json, FEED, Platform::Android, BETA, 0), None);
    }

    #[test]
    fn a_broken_answer_offers_nothing() {
        assert_eq!(
            newest(
                "{\"message\": \"rate limited\"}",
                FEED,
                Platform::Linux,
                BETA,
                1
            ),
            None
        );
        assert_eq!(newest("not json", FEED, Platform::Linux, BETA, 1), None);
    }

    #[test]
    fn long_notes_are_cut_on_a_character() {
        let mut r = release(
            "v0.1.0-beta.812",
            true,
            false,
            &["PiumaMail-android-arm64.apk"],
        );
        r["body"] = serde_json::Value::String("é".repeat(MAX_NOTES));
        let offer = newest(&list(&[r]), FEED, Platform::Android, BETA, 800).unwrap();
        assert!(offer.notes.len() <= MAX_NOTES);
    }
}
