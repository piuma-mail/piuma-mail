//! What a server's certificate says about itself, for the person deciding
//! whether to trust it: who it names, who signed it, until when, and its
//! SHA-256 fingerprint. Only the few fields shown are read, straight from
//! the DER encoding; nothing here decides whether the certificate is good.

use sha2::{Digest, Sha256};

/// A certificate as the person sees it.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CertInfo {
    /// SHA-256 of the whole certificate, as upper-case hex pairs joined by
    /// colons (`AB:CD:…`), the way browsers show it.
    pub fingerprint: String,
    /// The subject, e.g. "CN=mail.studio.it, O=Studio".
    pub subject: String,
    /// Who signed it; the subject again for a self-signed certificate.
    pub issuer: String,
    /// The last day it is valid, as written in it (`2027-01-31`).
    pub not_after: String,
}

impl CertInfo {
    pub fn read(der: &[u8]) -> Self {
        let parsed = parse(der).unwrap_or_default();
        CertInfo {
            fingerprint: fingerprint_text(&sha256(der)),
            ..parsed
        }
    }
}

pub fn sha256(der: &[u8]) -> [u8; 32] {
    Sha256::digest(der).into()
}

/// `AB:CD:…`, the form shown to people.
pub fn fingerprint_text(hash: &[u8; 32]) -> String {
    hash.iter()
        .map(|b| format!("{b:02X}"))
        .collect::<Vec<_>>()
        .join(":")
}

/// Reads a fingerprint back, with or without colons, in any case.
pub fn parse_fingerprint(text: &str) -> Option<[u8; 32]> {
    let hex: String = text.chars().filter(|c| !matches!(c, ':' | ' ')).collect();
    if hex.len() != 64 {
        return None;
    }
    let mut out = [0u8; 32];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(hex.get(2 * i..2 * i + 2)?, 16).ok()?;
    }
    Some(out)
}

/// One DER element: its tag and its contents.
struct Tlv<'a> {
    tag: u8,
    body: &'a [u8],
}

/// Splits the first element off `data`.
fn next(data: &[u8]) -> Option<(Tlv<'_>, &[u8])> {
    let (&tag, rest) = data.split_first()?;
    let (&first, rest) = rest.split_first()?;
    let (len, rest) = if first < 0x80 {
        (first as usize, rest)
    } else {
        let n = (first & 0x7f) as usize;
        if n == 0 || n > 4 || rest.len() < n {
            return None;
        }
        let len = rest[..n].iter().fold(0usize, |a, b| (a << 8) | *b as usize);
        (len, &rest[n..])
    };
    if rest.len() < len {
        return None;
    }
    Some((
        Tlv {
            tag,
            body: &rest[..len],
        },
        &rest[len..],
    ))
}

fn elements(mut data: &[u8]) -> Vec<Tlv<'_>> {
    let mut out = Vec::new();
    while let Some((t, rest)) = next(data) {
        out.push(t);
        data = rest;
    }
    out
}

fn parse(der: &[u8]) -> Option<CertInfo> {
    let (cert, _) = next(der)?;
    let (tbs, _) = next(cert.body)?;
    let mut fields = elements(tbs.body).into_iter();
    let mut field = fields.next()?;
    // [0] version, when present.
    if field.tag == 0xa0 {
        field = fields.next()?;
    }
    // serial number, then the signature algorithm.
    let _serial = field;
    let _algorithm = fields.next()?;
    let issuer = fields.next()?;
    let validity = fields.next()?;
    let subject = fields.next()?;
    let times = elements(validity.body);
    Some(CertInfo {
        fingerprint: String::new(),
        subject: name(subject.body),
        issuer: name(issuer.body),
        not_after: times.get(1).map(time).unwrap_or_default(),
    })
}

/// "CN=…, O=…" from a Name: the parts people recognise, in order.
fn name(rdns: &[u8]) -> String {
    let mut parts = Vec::new();
    for set in elements(rdns) {
        for pair in elements(set.body) {
            let inner = elements(pair.body);
            let (Some(oid), Some(value)) = (inner.first(), inner.get(1)) else {
                continue;
            };
            let label = match oid.body {
                [0x55, 0x04, 0x03] => "CN",
                [0x55, 0x04, 0x0a] => "O",
                [0x55, 0x04, 0x0b] => "OU",
                [0x55, 0x04, 0x06] => "C",
                [0x55, 0x04, 0x07] => "L",
                [0x55, 0x04, 0x08] => "ST",
                _ => continue,
            };
            let text = match value.tag {
                // BMPString: UTF-16 big-endian.
                0x1e => {
                    let units: Vec<u16> = value
                        .body
                        .as_chunks::<2>()
                        .0
                        .iter()
                        .map(|c| u16::from_be_bytes(*c))
                        .collect();
                    String::from_utf16_lossy(&units)
                }
                _ => String::from_utf8_lossy(value.body).into_owned(),
            };
            parts.push(format!("{label}={text}"));
        }
    }
    parts.join(", ")
}

/// `YYYY-MM-DD` from a UTCTime or GeneralizedTime.
fn time(t: &Tlv<'_>) -> String {
    let text = String::from_utf8_lossy(t.body);
    let (year, rest) = match t.tag {
        0x17 if text.len() >= 6 => {
            let yy: u32 = text[..2].parse().unwrap_or(0);
            (if yy >= 50 { 1900 + yy } else { 2000 + yy }, &text[2..])
        }
        0x18 if text.len() >= 8 => (text[..4].parse().unwrap_or(0), &text[4..]),
        _ => return String::new(),
    };
    format!("{year:04}-{}-{}", &rest[..2], &rest[2..4])
}

#[cfg(test)]
mod tests {
    use super::*;

    const LEAF: &[u8] = include_bytes!("../tests/fixtures/tls/first.der");

    #[test]
    fn reads_who_a_certificate_names() {
        let info = CertInfo::read(LEAF);
        assert_eq!(info.subject, "CN=localhost, O=Piuma Test");
        assert_eq!(info.issuer, info.subject, "self-signed");
        assert_eq!(info.not_after.len(), 10);
        assert_eq!(info.fingerprint.len(), 32 * 3 - 1);
        assert_eq!(parse_fingerprint(&info.fingerprint), Some(sha256(LEAF)));
    }

    #[test]
    fn fingerprints_read_back_in_any_form() {
        let hash = [0xabu8; 32];
        let text = fingerprint_text(&hash);
        assert!(text.starts_with("AB:AB:"));
        assert_eq!(parse_fingerprint(&text.to_lowercase()), Some(hash));
        assert_eq!(parse_fingerprint(&text.replace(':', "")), Some(hash));
        assert_eq!(parse_fingerprint("AB:CD"), None);
        assert_eq!(parse_fingerprint(&"zz".repeat(32)), None);
    }

    #[test]
    fn garbage_gives_only_the_fingerprint() {
        let info = CertInfo::read(b"not a certificate");
        assert!(info.subject.is_empty());
        assert_eq!(info.fingerprint.len(), 95);
    }
}
