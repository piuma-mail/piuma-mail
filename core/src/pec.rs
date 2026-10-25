//! Certified mail (PEC): the receipts the provider sends for each message
//! that leaves a PEC mailbox. They are read from their headers (fixed by
//! the Italian rules for PEC) and their short Italian text, kept apart from
//! the inbox, and gathered on the message they are about for the Vault.

use std::sync::LazyLock;

use mail_parser::Message;
use regex::Regex;
use serde::{Deserialize, Serialize};

/// The header fields [`receipt`] reads, for an IMAP fetch.
pub const HEADER_FIELDS: &str = "X-RICEVUTA X-RIFERIMENTO-MESSAGE-ID";

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

/// The receipt `m` is, if it is one.
pub fn receipt(m: &Message) -> Option<Receipt> {
    let kind = Kind::from_header(m.header_raw("X-Ricevuta")?)?;
    let refers = m.header_raw("X-Riferimento-Message-ID")?.trim();
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
            "Subject: CONSEGNA: Lease renewal 2027\r\n\
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
            "Subject: AVVISO DI MANCATA CONSEGNA: Formal notice\r\n\
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
        // A certified message received is the envelope, not a receipt.
        assert_eq!(
            parse("X-Trasporto: posta-certificata\r\nSubject: POSTA CERTIFICATA: hi\r\n\r\nx\r\n"),
            None
        );
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
    }
}
