//! The app lock's PIN. It is never kept as it is typed: only a slow,
//! salted Argon2id hash, which the app puts in the system keychain (the
//! Android Keystore on Android). The hash is written as
//! `argon2id$v=19$m=<KiB>,t=<passes>,p=<lanes>$<salt>$<hash>`, salt and
//! hash in unpadded base64, so a later release can make it slower and
//! still check the PINs kept before.
//!
//! How often a wrong PIN may be tried is the app's to say (the lock's
//! state machine, `app/lib/lock/`): the hash only makes each try slow.

use argon2::{Algorithm, Argon2, Params, Version};
use base64::engine::general_purpose::STANDARD_NO_PAD as B64;
use base64::Engine as _;
use subtle::ConstantTimeEq;
use zeroize::Zeroizing;

/// OWASP's first choice for Argon2id: 19 MiB, two passes, one lane.
/// About 50 ms on a recent phone, far slower for anyone guessing.
const MEMORY_KIB: u32 = 19 * 1024;
const PASSES: u32 = 2;
const LANES: u32 = 1;
const SALT_LEN: usize = 16;
const HASH_LEN: usize = 32;

/// Shortest and longest PIN the app takes.
pub const PIN_MIN: usize = 4;
pub const PIN_MAX: usize = 12;

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum PinError {
    #[error("a PIN is 4 to 12 digits")]
    NotAPin,
    #[error("the PIN could not be hashed")]
    Hash,
}

/// Whether [pin] is a PIN the app takes: 4 to 12 ASCII digits.
pub fn valid_pin(pin: &str) -> bool {
    (PIN_MIN..=PIN_MAX).contains(&pin.len()) && pin.bytes().all(|b| b.is_ascii_digit())
}

/// The hash to keep for [pin], with a new random salt.
pub fn hash_pin(pin: &str) -> Result<String, PinError> {
    if !valid_pin(pin) {
        return Err(PinError::NotAPin);
    }
    let mut salt = [0u8; SALT_LEN];
    getrandom::fill(&mut salt).expect("the system has randomness");
    let params = (MEMORY_KIB, PASSES, LANES);
    let hash = derive(pin, &salt, params)?;
    Ok(format!(
        "argon2id$v=19$m={},t={},p={}${}${}",
        params.0,
        params.1,
        params.2,
        B64.encode(salt),
        B64.encode(hash.as_slice())
    ))
}

/// Whether [pin] is the one [kept] was made from. A kept value that
/// isn't a hash of ours never matches.
pub fn verify_pin(pin: &str, kept: &str) -> bool {
    let Some((params, salt, hash)) = parse(kept) else {
        return false;
    };
    if !valid_pin(pin) {
        return false;
    }
    match derive(pin, &salt, params) {
        Ok(again) => again.as_slice().ct_eq(&hash).into(),
        Err(_) => false,
    }
}

fn derive(
    pin: &str,
    salt: &[u8],
    (m, t, p): (u32, u32, u32),
) -> Result<Zeroizing<[u8; HASH_LEN]>, PinError> {
    let params = Params::new(m, t, p, Some(HASH_LEN)).map_err(|_| PinError::Hash)?;
    let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut out = Zeroizing::new([0u8; HASH_LEN]);
    argon
        .hash_password_into(pin.as_bytes(), salt, out.as_mut())
        .map_err(|_| PinError::Hash)?;
    Ok(out)
}

type Parsed = ((u32, u32, u32), Vec<u8>, Vec<u8>);

fn parse(kept: &str) -> Option<Parsed> {
    let mut parts = kept.split('$');
    if parts.next()? != "argon2id" || parts.next()? != "v=19" {
        return None;
    }
    let mut m = None;
    let mut t = None;
    let mut p = None;
    for pair in parts.next()?.split(',') {
        let (k, v) = pair.split_once('=')?;
        let v: u32 = v.parse().ok()?;
        match k {
            "m" => m = Some(v),
            "t" => t = Some(v),
            "p" => p = Some(v),
            _ => return None,
        }
    }
    // Never weaker than what this release writes: a kept value someone
    // edited down to a cheap hash doesn't make guessing faster.
    let (m, t, p) = (m?, t?, p?);
    if m < MEMORY_KIB || t < PASSES || p < LANES || m > 4 * 1024 * 1024 || t > 64 || p > 16 {
        return None;
    }
    let salt = B64.decode(parts.next()?).ok()?;
    let hash = B64.decode(parts.next()?).ok()?;
    if parts.next().is_some() || salt.len() < 8 || hash.len() != HASH_LEN {
        return None;
    }
    Some(((m, t, p), salt, hash))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pin_checks_against_its_own_hash_only() {
        let kept = hash_pin("2468").unwrap();
        assert!(kept.starts_with("argon2id$v=19$m=19456,t=2,p=1$"));
        assert!(!kept.contains("2468"));
        assert!(verify_pin("2468", &kept));
        assert!(!verify_pin("2469", &kept));
        assert!(!verify_pin("24680", &kept));
        assert!(!verify_pin("", &kept));
    }

    #[test]
    fn the_same_pin_gets_a_new_salt_each_time() {
        let a = hash_pin("1357").unwrap();
        let b = hash_pin("1357").unwrap();
        assert_ne!(a, b);
        assert!(verify_pin("1357", &a));
        assert!(verify_pin("1357", &b));
    }

    #[test]
    fn only_four_to_twelve_digits_are_a_pin() {
        assert_eq!(hash_pin("123"), Err(PinError::NotAPin));
        assert_eq!(hash_pin("1234567890123"), Err(PinError::NotAPin));
        assert_eq!(hash_pin("12a4"), Err(PinError::NotAPin));
        assert_eq!(hash_pin("١٢٣٤"), Err(PinError::NotAPin));
        assert!(valid_pin("0000"));
        assert!(valid_pin("123456789012"));
    }

    #[test]
    fn a_damaged_or_weakened_hash_never_matches() {
        let kept = hash_pin("8080").unwrap();
        let weaker = kept.replace("m=19456", "m=8");
        assert!(!verify_pin("8080", &weaker));
        let fewer = kept.replace("t=2", "t=1");
        assert!(!verify_pin("8080", &fewer));
        let cut = &kept[..kept.len() - 4];
        assert!(!verify_pin("8080", cut));
        for junk in [
            "",
            "8080",
            "argon2id",
            "argon2i$v=19$m=19456,t=2,p=1$AAAA$AAAA",
        ] {
            assert!(!verify_pin("8080", junk), "{junk}");
        }
    }
}
