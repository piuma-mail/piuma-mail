//! Checking an S/MIME signature (CMS SignedData, RFC 5652) against a
//! fixed set of trusted certificates, for PEC receipts (`pec::signed`).
//!
//! Only what such signatures use is read: DER (no indefinite lengths),
//! one signer, RSA PKCS #1 v1.5 or ECDSA keys, SHA-1 to SHA-512. Anything
//! else is simply not verified. The arithmetic is aws-lc-rs's, which the
//! engine already carries for TLS.

use aws_lc_rs::digest;
use aws_lc_rs::signature::{self, UnparsedPublicKey, VerificationAlgorithm};

// Object identifiers, as their DER contents.
const SIGNED_DATA: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02];
const MESSAGE_DIGEST: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04];
const SIGNING_TIME: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x05];
const EMAIL_ADDRESS: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x01];
const RSA: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01];
const RSA_SHA1: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x05];
const RSA_SHA256: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B];
const RSA_SHA384: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0C];
const RSA_SHA512: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0D];
const EC_KEY: &[u8] = &[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01];
const ECDSA_SHA256: &[u8] = &[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02];
const ECDSA_SHA384: &[u8] = &[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x03];
const P256: &[u8] = &[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07];
const P384: &[u8] = &[0x2B, 0x81, 0x04, 0x00, 0x22];
const SHA1: &[u8] = &[0x2B, 0x0E, 0x03, 0x02, 0x1A];
const SHA256: &[u8] = &[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01];
const SHA384: &[u8] = &[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02];
const SHA512: &[u8] = &[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03];
const SUBJECT_ALT_NAME: &[u8] = &[0x55, 0x1D, 0x11];
const BASIC_CONSTRAINTS: &[u8] = &[0x55, 0x1D, 0x13];

/// One DER element: its tag, its contents, and all of it.
#[derive(Debug, Clone, Copy)]
struct Tlv<'a> {
    tag: u8,
    value: &'a [u8],
    raw: &'a [u8],
}

/// The element at the start of `input`, and what follows it.
fn read(input: &[u8]) -> Option<(Tlv<'_>, &[u8])> {
    let tag = *input.first()?;
    // Tags above 30 take more bytes; nothing read here uses them.
    if tag & 0x1F == 0x1F {
        return None;
    }
    let first = *input.get(1)? as usize;
    let (len, head) = if first < 0x80 {
        (first, 2)
    } else {
        let n = first & 0x7F;
        // 0x80 is BER's indefinite length: not DER.
        if n == 0 || n > 4 {
            return None;
        }
        let mut len = 0usize;
        for i in 0..n {
            len = (len << 8) | *input.get(2 + i)? as usize;
        }
        (len, 2 + n)
    };
    let end = head.checked_add(len)?;
    let raw = input.get(..end)?;
    Some((
        Tlv {
            tag,
            value: &raw[head..],
            raw,
        },
        &input[end..],
    ))
}

/// The elements inside a constructed one.
fn items(mut value: &[u8]) -> Option<Vec<Tlv<'_>>> {
    let mut out = Vec::new();
    while !value.is_empty() {
        let (t, rest) = read(value)?;
        out.push(t);
        value = rest;
    }
    Some(out)
}

/// The one element `value` is.
fn only(value: &[u8]) -> Option<Tlv<'_>> {
    match read(value)? {
        (t, []) => Some(t),
        _ => None,
    }
}

/// A BIT STRING's bits, when it uses whole bytes.
fn bits<'a>(t: Tlv<'a>) -> Option<&'a [u8]> {
    match (t.tag, t.value.split_first()) {
        (0x03, Some((0, bits))) => Some(bits),
        _ => None,
    }
}

/// An AlgorithmIdentifier: the OID and its parameters' element, if any.
fn algorithm<'a>(t: Tlv<'a>) -> Option<(&'a [u8], Option<Tlv<'a>>)> {
    let parts = items(t.value)?;
    let oid = parts.first().filter(|o| o.tag == 0x06)?.value;
    Some((oid, parts.get(1).copied()))
}

/// UTCTime or GeneralizedTime, as Unix seconds.
fn time(t: Tlv) -> Option<i64> {
    let s = std::str::from_utf8(t.value).ok()?.strip_suffix('Z')?;
    let (year, rest) = match t.tag {
        0x17 if s.len() == 12 => {
            let yy: i64 = s.get(..2)?.parse().ok()?;
            (if yy < 50 { 2000 + yy } else { 1900 + yy }, &s[2..])
        }
        0x18 if s.len() == 14 => (s.get(..4)?.parse().ok()?, &s[4..]),
        _ => return None,
    };
    let n = |i: usize| -> Option<i64> { rest.get(i..i + 2)?.parse().ok() };
    let (month, day, hour, minute, second) = (n(0)?, n(2)?, n(4)?, n(6)?, n(8)?);
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    // Days from 1970-01-01 (Howard Hinnant's days_from_civil).
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(days * 86_400 + hour * 3600 + minute * 60 + second)
}

/// What a certificate says, as far as checking a signature needs.
#[derive(Debug, Clone)]
pub struct Cert<'a> {
    raw: &'a [u8],
    tbs: &'a [u8],
    signature_algorithm: &'a [u8],
    signature: &'a [u8],
    serial: &'a [u8],
    issuer: &'a [u8],
    subject: &'a [u8],
    not_before: i64,
    not_after: i64,
    key_algorithm: &'a [u8],
    key_curve: Option<&'a [u8]>,
    key: &'a [u8],
    ca: bool,
    /// Its e-mail addresses (subject and alternative names), lowercase.
    pub emails: Vec<String>,
    /// Its host names (alternative names), lowercase.
    pub hosts: Vec<String>,
}

fn cert(raw: &[u8]) -> Option<Cert<'_>> {
    let outer = only(raw)?;
    let [tbs, alg, sig] = items(outer.value)?[..] else {
        return None;
    };
    let mut fields = items(tbs.value)?.into_iter().peekable();
    if fields.peek()?.tag == 0xA0 {
        fields.next();
    }
    let serial = fields.next().filter(|t| t.tag == 0x02)?.value;
    fields.next()?; // the signature algorithm again
    let issuer = fields.next().filter(|t| t.tag == 0x30)?.raw;
    let validity = items(fields.next()?.value)?;
    let subject = fields.next().filter(|t| t.tag == 0x30)?;
    let spki = items(fields.next()?.value)?;
    let (key_algorithm, params) = algorithm(*spki.first()?)?;
    let key = bits(*spki.get(1)?)?;
    let mut out = Cert {
        raw,
        tbs: tbs.raw,
        signature_algorithm: algorithm(alg)?.0,
        signature: bits(sig)?,
        serial,
        issuer,
        subject: subject.raw,
        not_before: time(*validity.first()?)?,
        not_after: time(*validity.get(1)?)?,
        key_algorithm,
        key_curve: params.filter(|p| p.tag == 0x06).map(|p| p.value),
        key,
        ca: false,
        emails: Vec::new(),
        hosts: Vec::new(),
    };
    for rdn in items(subject.value)? {
        for pair in items(rdn.value)? {
            let kv = items(pair.value)?;
            if kv.first()?.value == EMAIL_ADDRESS {
                let v = std::str::from_utf8(kv.get(1)?.value).ok()?;
                out.emails.push(v.trim().to_ascii_lowercase());
            }
        }
    }
    for f in fields {
        if f.tag != 0xA3 {
            continue;
        }
        for ext in items(only(f.value)?.value)? {
            let parts = items(ext.value)?;
            let id = parts.first()?.value;
            // The value is the last part, after an optional "critical".
            let value = only(parts.last()?.value)?;
            if id == SUBJECT_ALT_NAME {
                for name in items(value.value)? {
                    let text = String::from_utf8_lossy(name.value).to_ascii_lowercase();
                    match name.tag {
                        0x81 => out.emails.push(text),
                        0x82 => out.hosts.push(text),
                        _ => {}
                    }
                }
            } else if id == BASIC_CONSTRAINTS {
                out.ca = items(value.value)?
                    .first()
                    .is_some_and(|b| b.tag == 0x01 && b.value == [0xFF]);
            }
        }
    }
    Some(out)
}

/// The digest an algorithm names.
fn digest_of(oid: &[u8]) -> Option<&'static digest::Algorithm> {
    Some(match oid {
        SHA1 => &digest::SHA1_FOR_LEGACY_USE_ONLY,
        SHA256 => &digest::SHA256,
        SHA384 => &digest::SHA384,
        SHA512 => &digest::SHA512,
        _ => return None,
    })
}

/// Whether `key` signed `message` with `signature`, by the signature
/// algorithm (or, for CMS's bare `rsaEncryption`, the digest it names).
fn verify(
    key: &Cert,
    algorithm: &[u8],
    digest: Option<&[u8]>,
    message: &[u8],
    signature: &[u8],
) -> bool {
    let rsa = key.key_algorithm == RSA;
    let ec = key.key_algorithm == EC_KEY;
    let alg: &dyn VerificationAlgorithm = match (algorithm, digest) {
        (RSA_SHA1, _) | (RSA, Some(SHA1)) if rsa => {
            &signature::RSA_PKCS1_2048_8192_SHA1_FOR_LEGACY_USE_ONLY
        }
        (RSA_SHA256, _) | (RSA, Some(SHA256)) if rsa => &signature::RSA_PKCS1_2048_8192_SHA256,
        (RSA_SHA384, _) | (RSA, Some(SHA384)) if rsa => &signature::RSA_PKCS1_2048_8192_SHA384,
        (RSA_SHA512, _) | (RSA, Some(SHA512)) if rsa => &signature::RSA_PKCS1_2048_8192_SHA512,
        (ECDSA_SHA256, _) if ec && key.key_curve == Some(P256) => {
            &signature::ECDSA_P256_SHA256_ASN1
        }
        (ECDSA_SHA384, _) if ec && key.key_curve == Some(P384) => {
            &signature::ECDSA_P384_SHA384_ASN1
        }
        _ => return false,
    };
    UnparsedPublicKey::new(alg, key.key)
        .verify(message, signature)
        .is_ok()
}

/// Whether `issuer` signed `subject`'s certificate.
fn issued(issuer: &Cert, subject: &Cert) -> bool {
    issuer.subject == subject.issuer
        && verify(
            issuer,
            subject.signature_algorithm,
            None,
            subject.tbs,
            subject.signature,
        )
}

fn valid_at(c: &Cert, at: Option<i64>) -> bool {
    at.is_none_or(|t| c.not_before <= t && t <= c.not_after)
}

/// Who signed: the signer's certificate names.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Signer {
    pub emails: Vec<String>,
    pub hosts: Vec<String>,
}

/// Checks a detached signature (`smime.p7s`) over `content`: the content
/// is what was signed, and the signer's certificate leads, through the
/// certificates the signature carries, to one of `anchors` (DER). Each
/// certificate must be valid when the signature says it was made, and
/// every one between the signer and the anchor must be a CA.
pub fn verify_detached(content: &[u8], p7s: &[u8], anchors: &[Vec<u8>]) -> Option<Signer> {
    let info = items(only(p7s)?.value)?;
    if info.first()?.value != SIGNED_DATA {
        return None;
    }
    let signed = only(info.get(1).filter(|t| t.tag == 0xA0)?.value)?;
    let parts = items(signed.value)?;
    let mut certs = Vec::new();
    let mut signers = None;
    for p in &parts[1..] {
        match p.tag {
            0xA0 => {
                for c in items(p.value)? {
                    certs.push(cert(c.raw)?);
                }
            }
            0x31 => signers = Some(*p),
            _ => {}
        }
    }
    // Exactly one signer.
    let [info] = items(signers?.value)?[..] else {
        return None;
    };
    let mut fields = items(info.value)?.into_iter();
    fields.next()?; // version
    let sid = items(fields.next().filter(|t| t.tag == 0x30)?.value)?;
    let (issuer, serial) = (sid.first()?.raw, sid.get(1)?.value);
    let digest_alg = algorithm(fields.next()?)?.0;
    let mut next = fields.next()?;
    let attrs = if next.tag == 0xA0 {
        let a = next;
        next = fields.next()?;
        Some(a)
    } else {
        None
    };
    let signature_alg = algorithm(next)?.0;
    let signature = fields.next().filter(|t| t.tag == 0x04)?.value;

    let signer = certs
        .iter()
        .find(|c| c.issuer == issuer && c.serial == serial)?;
    let hashed = digest::digest(digest_of(digest_alg)?, content);
    let mut at = None;
    let message: Vec<u8> = match attrs {
        Some(a) => {
            let mut digest_ok = false;
            for attr in items(a.value)? {
                let kv = items(attr.value)?;
                let values = items(kv.get(1)?.value)?;
                match kv.first()?.value {
                    MESSAGE_DIGEST => {
                        digest_ok = values.first().is_some_and(|v| {
                            v.tag == 0x04 && v.value == hashed.as_ref() && values.len() == 1
                        });
                    }
                    SIGNING_TIME => at = time(*values.first()?),
                    _ => {}
                }
            }
            if !digest_ok {
                return None;
            }
            // Signed as a SET, not with the [0] it is stored under.
            let mut der = a.raw.to_vec();
            der[0] = 0x31;
            der
        }
        None => content.to_vec(),
    };
    if !verify(signer, signature_alg, Some(digest_alg), &message, signature) {
        return None;
    }

    let anchors: Vec<Cert> = anchors.iter().filter_map(|a| cert(a)).collect();
    let mut at_cert = signer;
    for _ in 0..5 {
        if !valid_at(at_cert, at) {
            return None;
        }
        if anchors.iter().any(|a| a.raw == at_cert.raw)
            || anchors
                .iter()
                .any(|a| valid_at(a, at) && issued(a, at_cert))
        {
            return Some(Signer {
                emails: signer.emails.clone(),
                hosts: signer.hosts.clone(),
            });
        }
        at_cert = certs
            .iter()
            .find(|c| c.ca && c.raw != at_cert.raw && issued(c, at_cert))?;
    }
    None
}

/// The certificates of a PEM text, as DER.
pub fn pem(text: &str) -> Vec<Vec<u8>> {
    use base64::Engine;
    let mut out = Vec::new();
    let mut body: Option<String> = None;
    for line in text.lines().map(str::trim) {
        if line == "-----BEGIN CERTIFICATE-----" {
            body = Some(String::new());
        } else if line == "-----END CERTIFICATE-----" {
            if let Some(b) = body.take() {
                if let Ok(der) = base64::engine::general_purpose::STANDARD.decode(b) {
                    out.push(der);
                }
            }
        } else if let Some(b) = body.as_mut() {
            b.push_str(line);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn times() {
        let t = |tag, s: &str| {
            time(Tlv {
                tag,
                value: s.as_bytes(),
                raw: &[],
            })
        };
        assert_eq!(t(0x17, "700101000000Z"), Some(0));
        assert_eq!(t(0x17, "261019091200Z"), Some(1_792_401_120));
        assert_eq!(t(0x18, "20261019091200Z"), Some(1_792_401_120));
        assert_eq!(t(0x17, "261319091200Z"), None);
    }

    #[test]
    fn indefinite_lengths_are_not_read() {
        assert!(read(&[0x30, 0x80, 0x00, 0x00]).is_none());
        assert!(read(&[0x04, 0x02, 0x01]).is_none());
        let (t, rest) = read(&[0x04, 0x01, 0xAA, 0x05]).unwrap();
        assert_eq!((t.tag, t.value, rest), (0x04, &[0xAA][..], &[0x05][..]));
    }
}
