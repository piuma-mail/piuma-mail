//! Certified mail (PEC): the receipts the provider sends for each message
//! that leaves a PEC mailbox. They are read from their headers (fixed by
//! the Italian rules for PEC) and their short Italian text, kept apart from
//! the inbox, and gathered on the message they are about for the Vault.
//!
//! Headers alone prove nothing: anyone can write them. A receipt counts
//! only on a certified mailbox (whose provider wraps whatever arrives from
//! outside the PEC system in an envelope of its own), only from the
//! provider's certificate address, and it is proof only once the
//! provider's S/MIME signature checks ([`signed`]): a certificate that
//! leads to one of AgID's CAs for the PEC network or a qualified CA of the
//! Italian trusted list ([`ANCHORS`]),
//! issued to an organization in AgID's list of PEC providers
//! ([`PROVIDERS`]), for the address the receipt comes from. Qualified CAs
//! also certify people; the organization keeps their signatures from
//! passing for a provider's. Until then the Vault shows it as unverified.

use std::sync::LazyLock;

use mail_parser::Message;
use regex::Regex;
use serde::{Deserialize, Serialize};

/// The header fields [`receipt`] reads, for an IMAP fetch.
pub const HEADER_FIELDS: &str = "X-RICEVUTA X-RIFERIMENTO-MESSAGE-ID X-TRASPORTO";

/// The certificates PEC receipts must lead to, as PEM, and the PEC
/// providers, one name a line: both written by `tools/gen_pec_trust.py`,
/// which says where they come from and how they are refreshed.
const ANCHORS_PEM: &str = include_str!("pec_anchors.pem");
const PROVIDERS_TXT: &str = include_str!("pec_providers.txt");

/// [`ANCHORS_PEM`], as DER.
pub static ANCHORS: LazyLock<Vec<Vec<u8>>> = LazyLock::new(|| crate::smime::pem(ANCHORS_PEM));

/// [`PROVIDERS_TXT`], as [`organization_key`]s.
pub static PROVIDERS: LazyLock<Vec<String>> = LazyLock::new(|| {
    PROVIDERS_TXT
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(organization_key)
        .collect()
});

/// A company name with only its letters and digits, lowercase, and
/// without what it adds in brackets: AgID writes "Aruba PEC S.p.A.", a
/// certificate "ArubaPEC S.p.A."; "… S.r.l. (già I.T. Telecom S.r.l.)"
/// is the company before the brackets.
pub fn organization_key(name: &str) -> String {
    let mut depth = 0usize;
    let mut out = String::new();
    for c in name.chars() {
        match c {
            '(' => depth += 1,
            ')' => depth = depth.saturating_sub(1),
            c if depth == 0 && c.is_alphanumeric() => out.extend(c.to_lowercase()),
            _ => {}
        }
    }
    out
}

/// What a receipt's signature is checked against.
pub struct Trusted<'a> {
    /// The CAs, as DER.
    pub anchors: &'a [Vec<u8>],
    /// The providers, as [`organization_key`]s.
    pub providers: &'a [String],
}

/// Whether an account is a certified (PEC) mailbox, by its server: the
/// providers' own (Aruba, InfoCert's Legalmail, Poste, Namirial,
/// Register…) all name it so.
pub fn certified(account: &crate::model::Account) -> bool {
    let crate::model::AccountKind::Imap { imap, .. } = &account.kind else {
        return false;
    };
    let host = imap.host.to_ascii_lowercase();
    host.split('.').any(|label| {
        matches!(
            label,
            "pec" | "postecert" | "legalmail" | "cert" | "sicurezzapostale" | "arubapec"
        )
    })
}

/// The address a provider sends its receipts from.
fn from_provider(m: &Message) -> bool {
    m.from()
        .and_then(|a| a.first())
        .and_then(|a| a.address())
        .is_some_and(|e| {
            e.trim()
                .to_ascii_lowercase()
                .strip_prefix("posta-certificata@")
                .is_some_and(|d| d.contains('.'))
        })
}

/// What a receipt says about the message it refers to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    /// The sender's provider took it ("accettazione").
    Accepted,
    /// The sender's provider refused it ("non-accettazione", or a virus).
    Refused,
    /// The recipient's provider took it ("presa-in-carico").
    Taken,
    /// In the recipient's mailbox ("avvenuta-consegna").
    Delivered,
    /// Not delivered yet after the first hours ("preavviso-errore-consegna").
    Late,
    /// It could not be delivered ("errore-consegna").
    Failed,
}

impl Kind {
    /// How the database names it.
    pub fn tag(self) -> &'static str {
        match self {
            Kind::Accepted => "accepted",
            Kind::Refused => "refused",
            Kind::Taken => "taken",
            Kind::Delivered => "delivered",
            Kind::Late => "late",
            Kind::Failed => "failed",
        }
    }

    pub fn from_tag(tag: &str) -> Option<Kind> {
        [
            Kind::Accepted,
            Kind::Refused,
            Kind::Taken,
            Kind::Delivered,
            Kind::Late,
            Kind::Failed,
        ]
        .into_iter()
        .find(|k| k.tag() == tag)
    }

    /// The kind an X-Ricevuta value names.
    fn from_header(value: &str) -> Option<Kind> {
        Some(match value.trim().to_ascii_lowercase().as_str() {
            "accettazione" => Kind::Accepted,
            "non-accettazione" | "rilevazione-virus" => Kind::Refused,
            "presa-in-carico" => Kind::Taken,
            "avvenuta-consegna" => Kind::Delivered,
            "preavviso-errore-consegna" => Kind::Late,
            "errore-consegna" => Kind::Failed,
            _ => return None,
        })
    }
}

/// One receipt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Receipt {
    pub kind: Kind,
    /// The Message-ID of the message it is about, with angle brackets.
    pub refers: String,
    /// Who it is about: one address for a delivery or a failure; for an
    /// acceptance, every certified address the message went to.
    pub recipients: Vec<String>,
    /// Why it failed, in the provider's words; empty when it says nothing.
    pub reason: String,
}

/// The receipt `m` is, if it is one: the provider's, at the top of the
/// message (a certified message received has X-Trasporto, and carries
/// whatever its sender wrote inside it).
pub fn receipt(m: &Message) -> Option<Receipt> {
    if m.headers().get("X-Trasporto").is_some() || !from_provider(m) {
        return None;
    }
    let kind = Kind::from_header(
        m.headers()
            .get("X-Ricevuta")
            .and_then(|h| std::str::from_utf8(h.raw_value()).ok())?,
    )?;
    let refers = m
        .headers()
        .get("X-Riferimento-Message-ID")
        .and_then(|h| std::str::from_utf8(h.raw_value()).ok())?
        .trim();
    if refers.is_empty() {
        return None;
    }
    let refers = if refers.starts_with('<') {
        refers.to_owned()
    } else {
        format!("<{refers}>")
    };
    let text = m.body_text(0).unwrap_or_default();
    Some(Receipt {
        kind,
        refers,
        recipients: recipients(kind, &text),
        reason: match kind {
            Kind::Refused | Kind::Late | Kind::Failed => reason(&text),
            _ => String::new(),
        },
    })
}

/// `"addr"` after "indirizzato a" (one recipient), or the lines
/// `addr ("posta certificata")` of an acceptance.
fn recipients(kind: Kind, text: &str) -> Vec<String> {
    static ONE: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r#"(?i)indirizzat[oa] a\s+"([^"\s]+@[^"\s]+)""#).unwrap());
    static CERTIFIED: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r#"(?im)^\s*<?([^\s<>"]+@[^\s<>"]+?)>?\s+\("posta certificata"\)"#).unwrap()
    });
    let found: Vec<String> = match kind {
        Kind::Accepted => CERTIFIED
            .captures_iter(text)
            .map(|c| c[1].to_ascii_lowercase())
            .collect(),
        _ => ONE
            .captures(text)
            .map(|c| vec![c[1].to_ascii_lowercase()])
            .unwrap_or_default(),
    };
    let mut out = Vec::new();
    for r in found {
        if !out.contains(&r) {
            out.push(r);
        }
    }
    out
}

/// The provider's words after "errore:", on one line.
fn reason(text: &str) -> String {
    static ERROR: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?im)\berrore\b[^:\n]*:\s*(\S[^\n]*)").unwrap());
    ERROR
        .captures(text)
        .map(|c| c[1].trim().trim_end_matches('.').trim().to_owned())
        .unwrap_or_default()
}

/// Whether `m` (as `raw`) is a receipt signed by a PEC provider, now: a
/// detached S/MIME signature over the message, by a certificate that
/// leads to [`ANCHORS`], belongs to an organization in [`PROVIDERS`] and
/// is for the very address the receipt comes from.
pub fn signed(m: &Message, raw: &[u8]) -> bool {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64);
    signed_with(
        m,
        raw,
        &Trusted {
            anchors: &ANCHORS,
            providers: &PROVIDERS,
        },
        now,
    )
}

pub(crate) fn signed_with(m: &Message, raw: &[u8], trusted: &Trusted<'_>, now: i64) -> bool {
    if trusted.anchors.is_empty() || receipt(m).is_none() {
        return false;
    }
    let Some(from) = m
        .from()
        .and_then(|a| a.first())
        .and_then(|a| a.address())
        .map(|e| e.trim().to_ascii_lowercase())
    else {
        return false;
    };
    let Some((content, p7s)) = detached(m, raw) else {
        return false;
    };
    let Some(signer) = crate::smime::verify_detached(content, &p7s, trusted.anchors, now) else {
        return false;
    };
    // `receipt` made sure the address is posta-certificata@…
    signer.emails.iter().any(|e| e == &from)
        && signer
            .organization
            .as_deref()
            .map(organization_key)
            .is_some_and(|o| !o.is_empty() && trusted.providers.contains(&o))
}

/// The signed part of a multipart/signed message, as written, and its
/// signature.
fn detached<'a>(m: &Message, raw: &'a [u8]) -> Option<(&'a [u8], Vec<u8>)> {
    let ct = m.root().content_type()?;
    if !ct.ctype().eq_ignore_ascii_case("multipart")
        || !ct.subtype()?.eq_ignore_ascii_case("signed")
    {
        return None;
    }
    let boundary = format!("--{}", ct.attribute("boundary")?);
    let b = boundary.as_bytes();
    let find = |from: usize| -> Option<usize> {
        raw.get(from..)?
            .windows(b.len() + 1)
            .position(|w| w[0] == b'\n' && &w[1..] == b)
            .map(|i| from + i + 1)
    };
    let first = find(0)?;
    let start = first + raw.get(first..)?.iter().position(|&c| c == b'\n')? + 1;
    let next = find(start)?;
    // The line break before the next boundary belongs to it.
    let mut end = next - 1;
    if end > start && raw[end - 1] == b'\r' {
        end -= 1;
    }
    let content = raw.get(start..end)?;
    let p7s = m.root().parts().find_map(|p| {
        let ct = p.content_type()?;
        let sub = ct.subtype()?.to_ascii_lowercase();
        (ct.ctype().eq_ignore_ascii_case("application")
            && (sub == "pkcs7-signature" || sub == "x-pkcs7-signature"))
            .then(|| p.decoded().to_vec())
    })?;
    Some((content, p7s))
}

/// The subject a receipt gives its message, without "CONSEGNA: " and the
/// like.
pub fn subject(receipt_subject: &str) -> &str {
    const PREFIXES: &[&str] = &[
        "AVVISO DI MANCATA CONSEGNA PER SUP. TEMPO MASSIMO:",
        "AVVISO DI MANCATA CONSEGNA:",
        "AVVISO DI NON ACCETTAZIONE PER VIRUS:",
        "AVVISO DI NON ACCETTAZIONE:",
        "AVVISO DI RILEVAZIONE VIRUS:",
        "ACCETTAZIONE:",
        "PRESA IN CARICO:",
        "CONSEGNA:",
    ];
    let upper = receipt_subject.to_ascii_uppercase();
    PREFIXES
        .iter()
        .find(|p| upper.starts_with(*p))
        .map(|p| receipt_subject[p.len()..].trim())
        .unwrap_or(receipt_subject.trim())
}

/// Where a certified message has got to, from all its receipts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage {
    /// Accepted, waiting for every delivery.
    Accepted,
    /// In every certified recipient's mailbox.
    Delivered,
    /// Refused, or not delivered to someone.
    Failed,
}

/// One message sent from a PEC mailbox, as the Vault shows it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sent {
    pub account: crate::model::AccountId,
    pub refers: String,
    pub subject: String,
    /// The certified recipients, from the acceptance (or the deliveries).
    pub recipients: Vec<String>,
    pub stage: Stage,
    /// How many of them have it.
    pub delivered: u32,
    /// When the last receipt came, Unix seconds.
    pub at: i64,
    /// When it was accepted, delivered to all, or failed.
    pub stage_at: i64,
    pub reason: String,
    /// The failed recipient, for "Not delivered".
    pub failed_to: String,
    /// Each receipt (mailbox, uid) worth keeping as proof: the deliveries,
    /// else the acceptance or the failure.
    pub proofs: Vec<(String, u32)>,
    /// Every receipt the stage rests on carries its provider's checked
    /// signature. Otherwise the stage is only what headers claim.
    pub verified: bool,
}

/// One stored receipt, as [`gather`] reads it.
#[derive(Debug, Clone)]
pub struct Stored {
    pub account: crate::model::AccountId,
    pub mailbox: String,
    pub uid: u32,
    pub kind: Kind,
    pub refers: String,
    pub recipients: Vec<String>,
    pub reason: String,
    pub subject: String,
    pub received_at: i64,
    /// Its provider's signature checked ([`signed`]).
    pub verified: bool,
}

/// The receipts of each sent message, gathered into one, newest first.
pub fn gather(receipts: Vec<Stored>) -> Vec<Sent> {
    let mut out: Vec<Sent> = Vec::new();
    let mut groups: Vec<Vec<Stored>> = Vec::new();
    for r in receipts {
        match groups
            .iter_mut()
            .find(|g| g[0].account == r.account && g[0].refers == r.refers)
        {
            Some(g) => g.push(r),
            None => groups.push(vec![r]),
        }
    }
    for mut g in groups {
        g.sort_by_key(|r| r.received_at);
        let of = |k: Kind| g.iter().filter(move |r| r.kind == k);
        let mut recipients: Vec<String> = of(Kind::Accepted)
            .flat_map(|r| r.recipients.clone())
            .collect();
        for r in g.iter().filter(|r| r.kind != Kind::Accepted) {
            for to in &r.recipients {
                if !recipients.contains(to) {
                    recipients.push(to.clone());
                }
            }
        }
        let mut delivered_to: Vec<&String> = of(Kind::Delivered)
            .flat_map(|r| r.recipients.iter())
            .collect();
        delivered_to.dedup();
        let failure = g
            .iter()
            .rev()
            .find(|r| matches!(r.kind, Kind::Refused | Kind::Failed));
        let delivered = delivered_to.len() as u32;
        let all = !recipients.is_empty() && delivered as usize >= recipients.len()
            || recipients.is_empty() && delivered > 0;
        let (stage, stage_at) = match failure {
            Some(f) => (Stage::Failed, f.received_at),
            None if all => (
                Stage::Delivered,
                of(Kind::Delivered)
                    .map(|r| r.received_at)
                    .max()
                    .unwrap_or(0),
            ),
            None => (
                Stage::Accepted,
                of(Kind::Accepted)
                    .map(|r| r.received_at)
                    .min()
                    .unwrap_or(g[0].received_at),
            ),
        };
        let proofs: Vec<(String, u32)> = {
            let deliveries: Vec<&Stored> = of(Kind::Delivered).collect();
            let picked: Vec<&Stored> = match (failure, deliveries.is_empty()) {
                (Some(f), _) => vec![f],
                (None, false) => deliveries,
                (None, true) => of(Kind::Accepted).take(1).collect(),
            };
            picked
                .into_iter()
                .map(|r| (r.mailbox.clone(), r.uid))
                .collect()
        };
        // What the stage rests on: the failure, the deliveries, or the
        // acceptance.
        let verified = match (failure, stage) {
            (Some(f), _) => f.verified,
            (None, Stage::Delivered) => of(Kind::Delivered).all(|r| r.verified),
            (None, _) => of(Kind::Accepted).next().is_some_and(|r| r.verified),
        };
        let last = g.last().expect("a group has a receipt");
        out.push(Sent {
            account: last.account,
            refers: last.refers.clone(),
            subject: subject(&g[0].subject).to_owned(),
            recipients,
            stage,
            delivered,
            at: last.received_at,
            stage_at,
            reason: failure.map(|f| f.reason.clone()).unwrap_or_default(),
            failed_to: failure
                .and_then(|f| f.recipients.first().cloned())
                .unwrap_or_default(),
            proofs,
            verified,
        });
    }
    out.sort_by_key(|s| std::cmp::Reverse(s.at));
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::AccountId;
    use mail_parser::MessageParser;

    fn parse(raw: &str) -> Option<Receipt> {
        let m = MessageParser::default().parse(raw.as_bytes()).unwrap();
        receipt(&m)
    }

    const ACCEPTED: &str = "From: posta-certificata@pec.aruba.it\r\n\
        Subject: ACCETTAZIONE: Lease renewal 2027\r\n\
        X-Ricevuta: accettazione\r\n\
        X-Riferimento-Message-ID: <opec1.20261019@pec.it>\r\n\
        Content-Type: text/plain; charset=utf-8\r\n\r\n\
        Ricevuta di accettazione\r\n\r\n\
        Il giorno 19/10/2026 alle ore 09:12:00 (+0200) il messaggio\r\n\
        \"Lease renewal 2027\" proveniente da \"matteo@pec.it\"\r\n\
        ed indirizzato a:\r\n\
        studio.rossi@pec.it (\"posta certificata\")\r\n\
        Amministrazione@Pec.Condominio.it (\"posta certificata\")\r\n\
        luca@example.org (\"posta ordinaria\")\r\n\
        Il messaggio è stato accettato dal sistema ed inoltrato.\r\n";

    #[test]
    fn reads_an_acceptance() {
        let r = parse(ACCEPTED).unwrap();
        assert_eq!(r.kind, Kind::Accepted);
        assert_eq!(r.refers, "<opec1.20261019@pec.it>");
        assert_eq!(
            r.recipients,
            ["studio.rossi@pec.it", "amministrazione@pec.condominio.it"]
        );
        assert_eq!(r.reason, "");
    }

    #[test]
    fn reads_a_delivery_and_a_failure() {
        let r = parse(
            "From: posta-certificata@pec.aruba.it\r\n\
             Subject: CONSEGNA: Lease renewal 2027\r\n\
             X-Ricevuta: avvenuta-consegna\r\n\
             X-Riferimento-Message-ID: opec1.20261019@pec.it\r\n\r\n\
             Il giorno 19/10/2026 alle ore 09:12:04 (+0200) il messaggio\r\n\
             \"Lease renewal 2027\" proveniente da \"matteo@pec.it\"\r\n\
             ed indirizzato a \"studio.rossi@pec.it\"\r\n\
             è stato consegnato nella casella di destinazione.\r\n",
        )
        .unwrap();
        assert_eq!(r.kind, Kind::Delivered);
        assert_eq!(r.refers, "<opec1.20261019@pec.it>");
        assert_eq!(r.recipients, ["studio.rossi@pec.it"]);

        let r = parse(
            "From: posta-certificata@pec.aruba.it\r\n\
             Subject: AVVISO DI MANCATA CONSEGNA: Formal notice\r\n\
             X-Ricevuta: errore-consegna\r\n\
             X-Riferimento-Message-ID: <opec2@pec.it>\r\n\r\n\
             Il giorno 16/10/2026 alle ore 18:05:00 (+0200) nel messaggio\r\n\
             \"Formal notice\" proveniente da \"matteo@pec.it\"\r\n\
             ed indirizzato a \"amministrazione@pec.condominio.it\"\r\n\
             è stato rilevato un problema che ne impedisce la consegna.\r\n\
             Errore: 5.2.2 - casella piena.\r\n",
        )
        .unwrap();
        assert_eq!(r.kind, Kind::Failed);
        assert_eq!(r.recipients, ["amministrazione@pec.condominio.it"]);
        assert_eq!(r.reason, "5.2.2 - casella piena");
    }

    #[test]
    fn ordinary_mail_is_no_receipt() {
        assert_eq!(parse("Subject: CONSEGNA: hi\r\n\r\nhello\r\n"), None);
        // Receipt headers from someone else than the provider.
        assert_eq!(
            parse(
                "From: bank@example.org\r\nX-Ricevuta: avvenuta-consegna\r\n\
                 X-Riferimento-Message-ID: <a@pec.it>\r\n\r\nx\r\n"
            ),
            None
        );
        // A certified message received is the envelope, not a receipt.
        assert_eq!(
            parse("X-Trasporto: posta-certificata\r\nSubject: POSTA CERTIFICATA: hi\r\n\r\nx\r\n"),
            None
        );
    }

    const SIGNED: &str = include_str!("../tests/fixtures/pec/signed.eml");
    const STRANGER: &str = include_str!("../tests/fixtures/pec/stranger.eml");
    const PERSON: &str = include_str!("../tests/fixtures/pec/person.eml");
    const NOSIGN: &str = include_str!("../tests/fixtures/pec/nosign.eml");
    const SHA1: &str = include_str!("../tests/fixtures/pec/sha1.eml");
    const TEST_ROOT: &str = include_str!("../tests/fixtures/pec/test-root.pem");
    const AGID_PEC_CA: &str = include_str!("../tests/fixtures/pec/agid-pec-ca.pem");
    const PECNET: &str = include_str!("../tests/fixtures/pec/pecnet.eml");
    const ROOTONLY: &str = include_str!("../tests/fixtures/pec/rootonly.eml");
    const RENEWED: &str = include_str!("../tests/fixtures/pec/renewed.eml");
    const CROSS: &str = include_str!("../tests/fixtures/pec/cross.eml");
    /// 29 November 2026: after the fixtures were made, and after the old
    /// copy of the renewed CA expired.
    const NOW: i64 = 1_796_000_000;

    fn signed_by(raw: &str, anchors: &[Vec<u8>]) -> bool {
        signed_at(raw, anchors, NOW)
    }

    fn signed_at(raw: &str, anchors: &[Vec<u8>], now: i64) -> bool {
        let m = MessageParser::default().parse(raw.as_bytes()).unwrap();
        let providers = [organization_key("Piuma Test PEC Provider")];
        signed_with(
            &m,
            raw.as_bytes(),
            &Trusted {
                anchors,
                providers: &providers,
            },
            now,
        )
    }

    #[test]
    fn a_receipt_signed_by_its_provider_is_proof() {
        let anchors = crate::smime::pem(TEST_ROOT);
        assert_eq!(anchors.len(), 1);
        assert!(parse(SIGNED).is_some());
        assert!(signed_by(SIGNED, &anchors));
        // Not without its CA among the anchors: the app's own bundled
        // ones never issued it.
        assert!(!signed_by(SIGNED, &[]));
        assert!(!signed(
            &MessageParser::default().parse(SIGNED.as_bytes()).unwrap(),
            SIGNED.as_bytes()
        ));
        // Nor from an organization that isn't a provider.
        let m = MessageParser::default().parse(SIGNED.as_bytes()).unwrap();
        assert!(!signed_with(
            &m,
            SIGNED.as_bytes(),
            &Trusted {
                anchors: &anchors,
                providers: &[organization_key("Aruba PEC S.p.A.")],
            },
            NOW
        ));
    }

    #[test]
    fn a_changed_or_unsigned_receipt_is_not() {
        let anchors = crate::smime::pem(TEST_ROOT);
        // One word of the signed text changed.
        let changed = SIGNED.replace("consegnato nella", "consegnata nella");
        assert_ne!(changed, SIGNED);
        assert!(parse(&changed).is_some());
        assert!(!signed_by(&changed, &anchors));
        // The same headers with no signature at all.
        let unsigned = ACCEPTED.replace(
            "From: posta-certificata@pec.aruba.it",
            "From: posta-certificata@pec.example.it",
        );
        assert!(parse(&unsigned).is_some());
        assert!(!signed_by(&unsigned, &anchors));
    }

    #[test]
    fn a_signature_from_another_ca_or_sender_is_not() {
        let anchors = crate::smime::pem(TEST_ROOT);
        // Signed, but by a certificate the anchors never issued.
        assert!(!signed_by(STRANGER, &anchors));
        // Signed by the provider, but sent as another address: the
        // certificate names posta-certificata@pec.example.it.
        let other = SIGNED.replace(
            "From: posta-certificata@pec.example.it",
            "From: posta-certificata@pec.other.example",
        );
        assert!(parse(&other).is_some());
        assert!(!signed_by(&other, &anchors));
        // From anyone else, it isn't a receipt at all.
        let person = SIGNED.replace(
            "From: posta-certificata@pec.example.it",
            "From: help@pec.example.it",
        );
        assert_eq!(parse(&person), None);
        assert!(!signed_by(&person, &anchors));
    }

    #[test]
    fn only_a_provider_s_certificate_made_to_sign_and_strong_hashes() {
        let anchors = crate::smime::pem(TEST_ROOT);
        // A qualified certificate of a person's, for the same address.
        assert!(parse(PERSON).is_some());
        assert!(!signed_by(PERSON, &anchors));
        // A provider's certificate that isn't for signing.
        assert!(!signed_by(NOSIGN, &anchors));
        // Signed with SHA-1.
        assert!(!signed_by(SHA1, &anchors));
        // Once the certificates have expired, nothing new is proof.
        assert!(!signed_at(SIGNED, &anchors, 2_524_608_000));
    }

    /// The anchors as the app has them: AgID's PEC CA (a stand-in here)
    /// and the qualified CAs (one stand-in).
    fn both() -> Vec<Vec<u8>> {
        let mut anchors = crate::smime::pem(AGID_PEC_CA);
        anchors.extend(crate::smime::pem(TEST_ROOT));
        anchors
    }

    #[test]
    fn a_receipt_from_agid_s_pec_network_ca_is_proof() {
        let anchors = both();
        assert!(parse(PECNET).is_some());
        assert!(signed_by(PECNET, &anchors));
        // The root above AgID's CA is not trusted for itself.
        assert!(!signed_by(ROOTONLY, &anchors));
        // A qualified CA's certificate for a person, with the provider's
        // address: still refused.
        assert!(!signed_by(PERSON, &anchors));
        // The qualified CA's provider certificate still checks.
        assert!(signed_by(SIGNED, &anchors));
    }

    #[test]
    fn an_expired_copy_of_a_renewed_ca_doesn_t_hide_the_valid_one() {
        // The signature carries the CA twice, same name and key: first a
        // copy that has expired by now, then the renewed one.
        assert!(signed_by(RENEWED, &both()));
    }

    #[test]
    fn a_ca_certified_twice_leads_to_the_anchor_through_either() {
        // The signature carries the CA certified first under another
        // root (a dead end), then by the test CA: the second is tried.
        assert!(signed_by(CROSS, &both()));
        // Without the test CA among the anchors, neither path ends.
        assert!(!signed_by(CROSS, &crate::smime::pem(AGID_PEC_CA)));
    }

    #[test]
    fn the_bundled_lists_are_read() {
        assert!(organization_key("Aruba PEC S.p.A.") == organization_key("ArubaPEC S.p.A."));
        assert_eq!(
            organization_key("Telecom Italia Trust Technologies S.r.l. (già I.T. Telecom S.r.l.)"),
            "telecomitaliatrusttechnologiessrl"
        );
        assert!(PROVIDERS.contains(&organization_key("Aruba PEC S.p.A.")));
        assert!(PROVIDERS.contains(&organization_key("Poste Italiane S.p.A.")));
        assert!(ANCHORS.len() > 10);
        // AgID's own CAs for the PEC network come first, and read.
        for der in &ANCHORS[..2] {
            assert_eq!(
                crate::smime::organization(der).as_deref(),
                Some("Agenzia per l'Italia Digitale")
            );
        }
        // Every anchor reads.
        assert!(ANCHORS.iter().all(|d| crate::smime::readable(d)));
    }

    #[test]
    fn only_certified_mailboxes_have_receipts() {
        use crate::model::{Account, AccountKind, Security, Server};
        let at = |host: &str| Account {
            id: AccountId(1),
            name: "Mail".into(),
            email: "matteo@example.org".into(),
            sender_name: String::new(),
            color: "#2F8F83".into(),
            kind: AccountKind::Imap {
                imap: Server {
                    host: host.into(),
                    port: 993,
                    security: Security::Tls,
                },
                smtp: Server {
                    host: host.into(),
                    port: 465,
                    security: Security::Tls,
                },
                username: "matteo".into(),
            },
        };
        assert!(certified(&at("imaps.pec.aruba.it")));
        assert!(certified(&at("mbox.cert.legalmail.it")));
        assert!(certified(&at("imaps.postecert.it")));
        assert!(!certified(&at("imap.gmail.com")));
        assert!(!certified(&at("imap.specchio.it")));
    }

    #[test]
    fn strips_the_receipt_words() {
        assert_eq!(subject("CONSEGNA: Lease renewal"), "Lease renewal");
        assert_eq!(
            subject("AVVISO DI MANCATA CONSEGNA: Formal notice"),
            "Formal notice"
        );
        assert_eq!(subject("Hello"), "Hello");
    }

    fn stored(uid: u32, kind: Kind, refers: &str, to: &[&str], at: i64) -> Stored {
        Stored {
            verified: true,
            account: AccountId(1),
            mailbox: "INBOX".into(),
            uid,
            kind,
            refers: refers.into(),
            recipients: to.iter().map(|s| s.to_string()).collect(),
            reason: if kind == Kind::Failed {
                "casella piena".into()
            } else {
                String::new()
            },
            subject: "ACCETTAZIONE: Tax form".into(),
            received_at: at,
        }
    }

    #[test]
    fn gathers_receipts_per_message() {
        let sent = gather(vec![
            stored(1, Kind::Accepted, "<a>", &["x@pec.it", "y@pec.it"], 100),
            stored(2, Kind::Delivered, "<a>", &["x@pec.it"], 104),
            stored(3, Kind::Accepted, "<b>", &["z@pec.it"], 50),
            stored(4, Kind::Delivered, "<b>", &["z@pec.it"], 55),
            stored(5, Kind::Accepted, "<c>", &["w@pec.it"], 10),
            stored(6, Kind::Failed, "<c>", &["w@pec.it"], 20),
        ]);
        assert_eq!(sent.len(), 3);
        assert_eq!(sent[0].refers, "<a>");
        assert_eq!(sent[0].subject, "Tax form");
        assert_eq!(sent[0].stage, Stage::Accepted);
        assert_eq!(sent[0].stage_at, 100);
        assert_eq!((sent[0].delivered, sent[0].recipients.len()), (1, 2));
        assert_eq!(sent[0].proofs, [("INBOX".to_owned(), 2)]);
        assert_eq!(sent[1].stage, Stage::Delivered);
        assert_eq!(sent[1].stage_at, 55);
        assert_eq!(sent[2].stage, Stage::Failed);
        assert_eq!(sent[2].failed_to, "w@pec.it");
        assert_eq!(sent[2].reason, "casella piena");
        assert_eq!(sent[2].proofs, [("INBOX".to_owned(), 6)]);
        assert!(sent.iter().all(|s| s.verified));
    }

    #[test]
    fn a_stage_on_unsigned_receipts_is_unverified() {
        let mut delivery = stored(2, Kind::Delivered, "<a>", &["x@pec.it"], 104);
        delivery.verified = false;
        let sent = gather(vec![
            stored(1, Kind::Accepted, "<a>", &["x@pec.it"], 100),
            delivery,
        ]);
        assert_eq!(sent[0].stage, Stage::Delivered);
        assert!(!sent[0].verified);
        let mut failure = stored(4, Kind::Failed, "<b>", &["y@pec.it"], 20);
        failure.verified = false;
        let sent = gather(vec![
            stored(3, Kind::Accepted, "<b>", &["y@pec.it"], 10),
            failure,
        ]);
        assert_eq!(sent[0].stage, Stage::Failed);
        assert!(!sent[0].verified);
    }
}
