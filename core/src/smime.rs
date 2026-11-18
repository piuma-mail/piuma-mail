//! Checking an S/MIME signature (CMS SignedData, RFC 5652) against a
//! fixed set of trusted certificates, for PEC receipts (`pec::signed`).
//!
//! Only what such signatures use is read: DER (no indefinite lengths),
//! one signer, RSA PKCS #1 v1.5 or ECDSA keys, SHA-256 to SHA-512 (SHA-1
//! is refused: collisions for it can be bought). Anything else is simply
//! not verified. The arithmetic is aws-lc-rs's, which the engine already
//! carries for TLS.
//!
//! Every certificate in the chain must be valid now, and also when the
//! signature says it was made, if it says. A receipt is checked when the
//! app first reads it, which is soon after it arrived, and what was found
//! then is kept (`pec_receipt.verified` only ever turns on): a provider
//! certificate expiring years later doesn't take the proof away, and an
//! expired one can't make a new one.

use aws_lc_rs::digest;
use aws_lc_rs::signature::{self, UnparsedPublicKey, VerificationAlgorithm};

// Object identifiers, as their DER contents.
const SIGNED_DATA: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02];
const MESSAGE_DIGEST: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04];
const SIGNING_TIME: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x05];
const EMAIL_ADDRESS: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x01];
const RSA: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01];
const RSA_SHA256: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B];
const RSA_SHA384: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0C];
const RSA_SHA512: &[u8] = &[0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0D];
const EC_KEY: &[u8] = &[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01];
const ECDSA_SHA256: &[u8] = &[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02];
const ECDSA_SHA384: &[u8] = &[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x03];
const P256: &[u8] = &[0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07];
const P384: &[u8] = &[0x2B, 0x81, 0x04, 0x00, 0x22];
const SHA256: &[u8] = &[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01];
const SHA384: &[u8] = &[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02];
const SHA512: &[u8] = &[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03];
const SUBJECT_ALT_NAME: &[u8] = &[0x55, 0x1D, 0x11];
const BASIC_CONSTRAINTS: &[u8] = &[0x55, 0x1D, 0x13];
const KEY_USAGE: &[u8] = &[0x55, 0x1D, 0x0F];
const EXTENDED_KEY_USAGE: &[u8] = &[0x55, 0x1D, 0x25];
const EMAIL_PROTECTION: &[u8] = &[0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x04];
const ORGANIZATION: &[u8] = &[0x55, 0x04, 0x0A];

/// Key usage bits, in the first byte of the BIT STRING.
const DIGITAL_SIGNATURE: u8 = 0x80;
const KEY_CERT_SIGN: u8 = 0x04;

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
    /// The first byte of its key usage, when it has the extension.
    usage: Option<u8>,
    /// Its extended key usages, when it has the extension.
    extended: Option<Vec<&'a [u8]>>,
    /// Its e-mail addresses (subject and alternative names), lowercase.
    pub emails: Vec<String>,
    /// Its subject's organization (O), as written.
    pub organization: Option<String>,
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
        usage: None,
        extended: None,
        emails: Vec::new(),
        organization: None,
    };
    for rdn in items(subject.value)? {
        for pair in items(rdn.value)? {
            let kv = items(pair.value)?;
            let id = kv.first()?.value;
            if id == EMAIL_ADDRESS {
                let v = std::str::from_utf8(kv.get(1)?.value).ok()?;
                out.emails.push(v.trim().to_ascii_lowercase());
            } else if id == ORGANIZATION && out.organization.is_none() {
                let v = String::from_utf8_lossy(kv.get(1)?.value);
                out.organization = Some(v.trim().to_owned());
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
                    if name.tag == 0x81 {
                        out.emails.push(text);
                    }
                }
            } else if id == BASIC_CONSTRAINTS {
                out.ca = items(value.value)?
                    .first()
                    .is_some_and(|b| b.tag == 0x01 && b.value == [0xFF]);
            } else if id == KEY_USAGE {
                // A BIT STRING: unused bits, then the bits.
                out.usage = (value.tag == 0x03)
                    .then(|| value.value.get(1).copied())
                    .flatten()
                    .or(Some(0));
            } else if id == EXTENDED_KEY_USAGE {
                out.extended = Some(
                    items(value.value)?
                        .into_iter()
                        .filter(|o| o.tag == 0x06)
                        .map(|o| o.value)
                        .collect(),
                );
            }
        }
    }
    Some(out)
}

/// The digest an algorithm names.
fn digest_of(oid: &[u8]) -> Option<&'static digest::Algorithm> {
    Some(match oid {
        SHA256 => &digest::SHA256,
        SHA384 => &digest::SHA384,
        SHA512 => &digest::SHA512,
        _ => return None,
    })
}

/// Whether `key` signed `message` with `signature`, by the signature
/// algorithm (or, for CMS's bare `rsaEncryption`, the digest it names).
fn verify(
    key: &Cert<'_>,
    algorithm: &[u8],
    digest: Option<&[u8]>,
    message: &[u8],
    signature: &[u8],
) -> bool {
    let rsa = key.key_algorithm == RSA;
    let ec = key.key_algorithm == EC_KEY;
    let alg: &dyn VerificationAlgorithm = match (algorithm, digest) {
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
fn issued(issuer: &Cert<'_>, subject: &Cert<'_>) -> bool {
    issuer.subject == subject.issuer
        && verify(
            issuer,
            subject.signature_algorithm,
            None,
            subject.tbs,
            subject.signature,
        )
}

/// Valid now, and when the signature says it was made.
fn valid(c: &Cert<'_>, now: i64, signed_at: Option<i64>) -> bool {
    let at = |t: i64| c.not_before <= t && t <= c.not_after;
    at(now) && signed_at.is_none_or(at)
}

/// A certificate that may issue others: a CA, allowed to sign them.
fn may_issue(c: &Cert<'_>) -> bool {
    c.ca && c.usage.is_some_and(|u| u & KEY_CERT_SIGN != 0)
}

/// A certificate that may sign a message: its key usage allows digital
/// signatures, and its extended usages, if it lists them, e-mail.
fn may_sign(c: &Cert<'_>) -> bool {
    c.usage.is_some_and(|u| u & DIGITAL_SIGNATURE != 0)
        && c.extended.as_ref().is_none_or(|e| e.contains(&EMAIL_PROTECTION))
}

/// Who signed: the signer's certificate names.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Signer {
    /// Its e-mail addresses, lowercase.
    pub emails: Vec<String>,
    /// Its organization, as written.
    pub organization: Option<String>,
}

/// Checks a detached signature (`smime.p7s`) over `content`: the content
/// is what was signed, and the signer's certificate, allowed to sign,
/// leads through the certificates the signature carries to one of
/// `anchors` (DER). Each certificate must be valid at `now` (Unix
/// seconds) and when the signature says it was made, and every one
/// between the signer and the anchor must be a CA allowed to issue.
pub fn verify_detached(
    content: &[u8],
    p7s: &[u8],
    anchors: &[Vec<u8>],
    now: i64,
) -> Option<Signer> {
    let info = items(only(p7s)?.value)?;
    if info.first()?.value != SIGNED_DATA {
        return None;
    }
    let signed = only(info.get(1).filter(|t| t.tag == 0xA0)?.value)?;
    let parts = items(signed.value)?;
    let mut certs = Vec::new();
    let mut signers = None;
    for p in parts.get(1..)? {
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
    if !may_sign(signer) {
        return None;
    }
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
            *der.first_mut()? = 0x31;
            der
        }
        None => content.to_vec(),
    };
    if !verify(signer, signature_alg, Some(digest_alg), &message, signature) {
        return None;
    }

    // Not made in the future.
    if at.is_some_and(|t| t > now + 86_400) {
        return None;
    }
    let anchors: Vec<Cert<'_>> = anchors.iter().filter_map(|a| cert(a)).collect();
    let mut at_cert = signer;
    for _ in 0..5 {
        if !valid(at_cert, now, at) {
            return None;
        }
        if anchors.iter().any(|a| a.raw == at_cert.raw)
            || anchors
                .iter()
                .any(|a| valid(a, now, at) && issued(a, at_cert))
        {
            return Some(Signer {
                emails: signer.emails.clone(),
                organization: signer.organization.clone(),
            });
        }
        at_cert = certs
            .iter()
            .find(|c| may_issue(c) && c.raw != at_cert.raw && issued(c, at_cert))?;
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

    const P7S: &[u8] = include_bytes!("../tests/fixtures/pec/signed.p7s");
    const ROOT: &str = include_str!("../tests/fixtures/pec/test-root.pem");
    /// What `tools/gen_pec_fixtures.sh` signs into `signed.p7s`.
    const CONTENT: &str = "Content-Type: multipart/mixed; boundary=\"inner\"\r\n\r\n--inner\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nRicevuta di avvenuta consegna\r\n\r\nIl giorno 19/10/2026 alle ore 09:12:04 (+0200) il messaggio\r\n\"Lease renewal 2027\" proveniente da \"matteo@pec.example.it\"\r\ned indirizzato a \"studio.rossi@pec.example.it\"\r\nè stato consegnato nella casella di destinazione.\r\n--inner--\r\n";
    /// 18 November 2026.
    const NOW: i64 = 1_795_000_000;

    #[test]
    fn a_signature_checks_only_while_its_certificates_are_valid() {
        let anchors = pem(ROOT);
        let signer = verify_detached(CONTENT.as_bytes(), P7S, &anchors, NOW).unwrap();
        assert_eq!(signer.emails, ["posta-certificata@pec.example.it"]);
        assert_eq!(
            signer.organization.as_deref(),
            Some("Piuma Test PEC Provider")
        );
        // In 2050 every certificate here has expired: nothing new checks.
        assert_eq!(
            verify_detached(CONTENT.as_bytes(), P7S, &anchors, 2_524_608_000),
            None
        );
        // Before they were made, neither.
        assert_eq!(
            verify_detached(CONTENT.as_bytes(), P7S, &anchors, 1_000_000_000),
            None
        );
        assert_eq!(verify_detached(b"other", P7S, &anchors, NOW), None);
    }

    #[test]
    fn an_empty_signed_data_is_no_signature() {
        let empty = [
            0x30, 0x0B, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0,
            0x02, 0x30, 0x00,
        ];
        assert_eq!(verify_detached(b"x", &empty, &pem(ROOT), NOW), None);
        assert_eq!(verify_detached(b"x", &[], &pem(ROOT), NOW), None);
        assert_eq!(verify_detached(b"x", &[0x30], &pem(ROOT), NOW), None);
    }

    /// xorshift64*, as in the other hostile-input tests: a fixed seed
    /// keeps a failure reproducible.
    struct Rng(u64);

    impl Rng {
        fn next(&mut self) -> u64 {
            self.0 ^= self.0 >> 12;
            self.0 ^= self.0 << 25;
            self.0 ^= self.0 >> 27;
            self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
        }

        fn below(&mut self, n: usize) -> usize {
            (self.next() % n.max(1) as u64) as usize
        }
    }

    #[test]
    fn hostile_signatures_never_panic() {
        let anchors = pem(ROOT);
        let mut rng = Rng(0x05EE_D0F5_1A7E);
        for round in 0..4000 {
            let mut bytes = P7S.to_vec();
            match round % 5 {
                // A few bytes changed anywhere.
                0 | 1 => {
                    for _ in 0..1 + rng.below(8) {
                        let at = rng.below(bytes.len());
                        bytes[at] = rng.next() as u8;
                    }
                }
                // Cut short.
                2 => bytes.truncate(rng.below(bytes.len())),
                // A length byte made huge or zero.
                3 => {
                    let at = rng.below(bytes.len());
                    bytes[at] = [0x00, 0x80, 0x81, 0x84, 0xFF][rng.below(5)];
                }
                // Noise from the start.
                _ => {
                    bytes = (0..rng.below(64)).map(|_| rng.next() as u8).collect();
                    if !bytes.is_empty() {
                        bytes[0] = 0x30;
                    }
                }
            }
            let _ = verify_detached(CONTENT.as_bytes(), &bytes, &anchors, NOW);
            let _ = cert(&bytes);
        }
    }

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
