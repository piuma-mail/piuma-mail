//! What keeps one odd message from stopping an account.
//!
//! Mail and server replies are written by strangers. The parsers that read
//! them are careful, but a reader that trips (a slice cut inside a
//! character, an index a server chose) must cost one message, never the
//! whole sync: [`shielded`] runs such a step and, if it panics, logs where
//! (never what: a panic message can quote the mail) and hands back a
//! fallback. The text helpers here cut strings only where a character
//! starts.

use std::cell::Cell;
use std::panic::{self, AssertUnwindSafe};
use std::sync::{Mutex, Once};

thread_local! {
    /// Where the last panic on this thread happened, from the hook.
    static LAST: Cell<Option<(&'static str, u32)>> = const { Cell::new(None) };
}

/// Where the last panic on any thread happened, for a task's supervisor,
/// which learns of it on another thread.
static LAST_ANYWHERE: Mutex<Option<(&'static str, u32)>> = Mutex::new(None);

static HOOK: Once = Once::new();

/// The largest whole message the engine downloads, in bytes. Servers
/// refuse to deliver much smaller ones (25 to 150 MB, attachments
/// included); a server that offers more is not believed.
pub const MESSAGE_MAX: usize = 160 * 1024 * 1024;

/// The one place that decides what a panic prints: call it after any other
/// hook is installed (the bridge's included), and it takes their place.
/// Safe to call any number of times.
///
/// Each panic's place is noted for [`shielded`] and [`last_panic_place`].
/// A release build then prints only that place: a panic's message can
/// quote the mail being read ("byte index 4 is not a char boundary … of
/// `…`"), and stderr ends up in the system log. Debug and test builds run
/// the hook that was there before, with the whole message.
pub fn install() {
    HOOK.call_once(|| {
        let previous = panic::take_hook();
        panic::set_hook(Box::new(move |info| {
            let place = info.location().map(|l| (l.file(), l.line()));
            if let Some((file, line)) = place {
                // `file()` borrows from the panic; keep only file names the
                // binary holds, which are 'static.
                let file: &'static str = static_file(file);
                LAST.with(|c| c.set(Some((file, line))));
                *LAST_ANYWHERE.lock().unwrap_or_else(|e| e.into_inner()) = Some((file, line));
            }
            if FULL_MESSAGES {
                previous(info);
            } else {
                eprintln!("{}", place_only(place));
            }
        }));
    });
}

/// Whether a panic prints its whole message: only where no one's mail is
/// read.
const FULL_MESSAGES: bool = cfg!(debug_assertions);

/// What a release build prints for a panic: where, never what.
fn place_only(place: Option<(&str, u32)>) -> String {
    match place {
        Some((file, line)) => format!("panic at {file}:{line}"),
        None => "panic".to_owned(),
    }
}

/// The source file of a panic, as a 'static string: locations from
/// `#[track_caller]` and `panic!` are always 'static in practice, but the
/// type doesn't say so; anything else is named "unknown".
fn static_file(file: &str) -> &'static str {
    // The crate's own files are the ones worth naming.
    const KNOWN: &[&str] = &[
        "reading.rs",
        "original.rs",
        "vault.rs",
        "invite.rs",
        "calendar.rs",
        "imap.rs",
        "jmap.rs",
        "store.rs",
        "brief.rs",
        "language.rs",
        "signature.rs",
        "dates.rs",
        "notify.rs",
        "preview.rs",
        "files.rs",
        "sender_auth.rs",
        "newsletter.rs",
        "pec.rs",
        "rich.rs",
        "impostor.rs",
        "remote.rs",
        "engine.rs",
        "guard.rs",
    ];
    let name = file.rsplit(['/', '\\']).next().unwrap_or(file);
    KNOWN
        .iter()
        .find(|k| **k == name)
        .copied()
        .unwrap_or("library")
}

/// Runs `f`; if it panics, logs the step and where it stopped, and
/// returns `fallback()` instead.
pub fn shielded<T>(step: &str, fallback: impl FnOnce() -> T, f: impl FnOnce() -> T) -> T {
    LAST.with(|c| c.set(None));
    match panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(v) => v,
        Err(_) => {
            report(step);
            fallback()
        }
    }
}

/// " at file:line" of the last panic on any thread, or nothing when the
/// hook didn't see it.
pub fn last_panic_place() -> String {
    LAST_ANYWHERE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .take()
        .map(|(file, line)| format!(" at {file}:{line}"))
        .unwrap_or_default()
}

/// Logs a caught panic in `step`: the place only, never its message.
pub fn report(step: &str) {
    let place = LAST
        .with(|c| c.take())
        .map(|(file, line)| format!(" at {file}:{line}"))
        .unwrap_or_default();
    crate::feedback::log(
        crate::feedback::Level::Error,
        "guard",
        &format!("panic in {step}{place}; skipped"),
    );
}

/// `s` without `prefix`, compared ignoring ASCII case; None when `s`
/// doesn't start with it. Never cuts inside a character.
pub fn strip_prefix_ci<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
    let head = s.get(..prefix.len())?;
    head.eq_ignore_ascii_case(prefix)
        .then(|| &s[prefix.len()..])
}

/// The largest index `<= at` where a character of `s` starts.
pub fn floor_boundary(s: &str, at: usize) -> usize {
    if at >= s.len() {
        return s.len();
    }
    let mut i = at;
    while !s.is_char_boundary(i) {
        i -= 1;
    }
    i
}

/// At most `max` bytes of `s`, cut where a character starts.
pub fn truncate(s: &str, max: usize) -> &str {
    &s[..floor_boundary(s, max)]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_panic_becomes_the_fallback() {
        install();
        let got = shielded("test", || 7, || -> i32 { panic!("boom") });
        assert_eq!(got, 7);
        assert_eq!(shielded("test", || 7, || 1), 1);
        assert!(crate::feedback::recent_log().contains("panic in test"));
    }

    #[test]
    fn the_log_never_carries_the_panic_message() {
        install();
        shielded("secret step", || (), || panic!("mail text: hunter2"));
        // The guard's own line names the step, never the message. (When a
        // test elsewhere installed feedback's panic hook in this process,
        // its "Rust panic at" entry keeps the first line scrubbed of
        // quoted text: tested there, in `panics_leave_the_place_and_never_the_mail`.)
        let log = crate::feedback::recent_log();
        assert!(log.contains("panic in secret step"));
        assert!(!log
            .lines()
            .filter(|l| !l.contains("Rust panic at"))
            .any(|l| l.contains("hunter2")));
    }

    #[test]
    fn a_release_build_prints_the_place_only() {
        assert_eq!(
            place_only(Some(("core/src/reading.rs", 902))),
            "panic at core/src/reading.rs:902"
        );
        assert_eq!(place_only(None), "panic");
    }

    #[test]
    fn prefixes_and_cuts_respect_characters() {
        assert_eq!(strip_prefix_ci("CID:x", "cid:"), Some("x"));
        assert_eq!(strip_prefix_ci("cié", "cid:"), None);
        assert_eq!(strip_prefix_ci("abcé", "abcd"), None);
        assert_eq!(strip_prefix_ci("é", "cid:"), None);
        assert_eq!(truncate("aé", 2), "a");
        assert_eq!(truncate("aé", 3), "aé");
        assert_eq!(truncate("aé", 9), "aé");
        assert_eq!(floor_boundary("€", 1), 0);
    }
}
