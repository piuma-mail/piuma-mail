//! How long to wait before trying a server again: the one policy for every
//! account watcher (IMAP and JMAP) and for the app's watcher supervisor.
//!
//! - The wait doubles with each failure in a row, from `first` up to a
//!   cap, and every wait is spread by ±20 % so that many devices (or many
//!   accounts on one device) do not knock at the same moment.
//! - It starts over only after a whole sync round went through, not when
//!   a connection or a login merely worked: a folder the server refuses
//!   to open, or a store that cannot write, fails right after the login,
//!   and starting over there meant logging in every few seconds for ever.
//! - Failing to reach the server at all asks nothing of it, so those waits
//!   stop growing at [`OFFLINE_MOST`]; failing once it answered (a refused
//!   folder, a reply that can't be read) goes on growing to
//!   [`ANSWERED_MOST`], which is what keeps a provider from throttling or
//!   banning the account.
//!
//! The supervisor in the app restarts a watcher that panicked or ended:
//! its waits come after the watcher's own and use the same rules, so a
//! watcher that dies on every round is restarted at a growing distance,
//! never in a tight loop.

use std::hash::{BuildHasher, Hasher};
use std::time::Duration;

/// First wait after a failure.
pub const FIRST: Duration = Duration::from_secs(2);
/// Longest wait while the server can't be reached.
pub const OFFLINE_MOST: Duration = Duration::from_secs(60);
/// Longest wait once the server answered and something still failed.
pub const ANSWERED_MOST: Duration = Duration::from_secs(15 * 60);

/// Waits that grow with each failure in a row.
#[derive(Debug, Clone)]
pub struct Backoff {
    first: Duration,
    failures: u32,
}

impl Default for Backoff {
    fn default() -> Self {
        Backoff::new(FIRST)
    }
}

impl Backoff {
    pub fn new(first: Duration) -> Self {
        Backoff { first, failures: 0 }
    }

    /// The wait after one more failure, at most `most` before spreading.
    pub fn fail(&mut self, most: Duration) -> Duration {
        let wait = self.peek(most);
        self.failures = self.failures.saturating_add(1);
        jitter(wait)
    }

    /// The wait the next failure would bring, unspread.
    pub fn peek(&self, most: Duration) -> Duration {
        let doubled = self
            .first
            .checked_mul(1u32.checked_shl(self.failures.min(20)).unwrap_or(u32::MAX))
            .unwrap_or(most);
        doubled.min(most)
    }

    /// A round went through: the next failure waits `first` again.
    pub fn reset(&mut self) {
        self.failures = 0;
    }

    /// Failures in a row so far.
    pub fn failures(&self) -> u32 {
        self.failures
    }
}

/// `wait` spread by up to ±20 %.
pub fn jitter(wait: Duration) -> Duration {
    // A fresh random seed per call is enough here; no need for a
    // generator crate.
    let r = std::collections::hash_map::RandomState::new()
        .build_hasher()
        .finish();
    let unit = (r % 10_001) as f64 / 10_000.0; // 0..=1
    wait.mul_f64(0.8 + 0.4 * unit)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn waits_double_up_to_the_cap_and_start_over_after_a_round() {
        let mut b = Backoff::default();
        let mut seen = Vec::new();
        for _ in 0..12 {
            seen.push(b.peek(ANSWERED_MOST));
            let w = b.fail(ANSWERED_MOST);
            let base = *seen.last().unwrap();
            assert!(
                w >= base.mul_f64(0.8) && w <= base.mul_f64(1.2),
                "{w:?} {base:?}"
            );
        }
        assert_eq!(seen[0], Duration::from_secs(2));
        assert_eq!(seen[1], Duration::from_secs(4));
        assert_eq!(seen[5], Duration::from_secs(64));
        assert_eq!(*seen.last().unwrap(), ANSWERED_MOST);
        // Unreachable: no more than a minute.
        assert_eq!(b.peek(OFFLINE_MOST), OFFLINE_MOST);
        b.reset();
        assert_eq!(b.peek(ANSWERED_MOST), FIRST);
    }

    #[test]
    fn many_failures_never_overflow() {
        let mut b = Backoff::default();
        for _ in 0..10_000 {
            b.fail(ANSWERED_MOST);
        }
        assert_eq!(b.peek(ANSWERED_MOST), ANSWERED_MOST);
    }

    #[test]
    fn waits_are_spread() {
        let waits: std::collections::HashSet<Duration> =
            (0..50).map(|_| jitter(Duration::from_secs(100))).collect();
        assert!(waits.len() > 10);
    }
}
