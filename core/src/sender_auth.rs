//! Whether a message really comes from the domain in its From: what the
//! account's own server found when it checked DKIM, SPF and DMARC, as its
//! Authentication-Results headers say (RFC 8601).
//!
//! Nothing is looked up from the device: a DNS query for a sender's key
//! would tell the sender that the message was opened.
//!
//! Anyone can write an Authentication-Results header into a message, so
//! only the ones above the hops of other servers count: headers are added
//! on top as a message travels, and whatever the sender wrote sits below
//! the `Received` lines of the servers it went through.

use mail_parser::Message;

use crate::model::{Account, AccountKind};

/// The headers that matter, top to bottom, and the domain in From.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Trail {
    pub from_domain: String,
    pub steps: Vec<Step>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    /// A server's hop: the host after "by", when it names one, and the
    /// one it took the message from.
    Received {
        by: Option<String>,
        from: Option<String>,
    },
    /// What a server found, by the name it signs with (`authserv-id`).
    Results { id: String, methods: Vec<Method> },
}

/// One check: "dkim=pass header.d=example.com".
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Method {
    pub name: String,
    pub result: String,
    /// Properties as written, lowercase: ("header.d", "example.com").
    pub props: Vec<(String, String)>,
}

impl Method {
    fn prop(&self, key: &str) -> Option<&str> {
        self.props
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }
}

/// The servers whose results an account can believe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Trust {
    domains: Vec<String>,
    /// A provider known to write its results and remove look-alikes: its
    /// own hops above them are fine. For any other server only results
    /// above every hop count.
    known: bool,
}

/// Providers that check every message and write what they found, by the
/// domain of their servers, with the names they sign their results with.
const KNOWN: &[(&[&str], &[&str])] = &[
    (
        &["gmail.com", "googlemail.com", "google.com"],
        &["google.com"],
    ),
    (
        &["me.com", "icloud.com", "apple.com"],
        &["icloud.com", "me.com", "apple.com"],
    ),
    (
        &["fastmail.com", "messagingengine.com"],
        &["messagingengine.com", "fastmail.com"],
    ),
    (&["yahoo.com"], &["yahoo.com"]),
    (
        &["outlook.com", "office365.com"],
        &["outlook.com", "office365.com"],
    ),
    (
        &["aruba.it", "arubapec.it", "pec.it"],
        &["aruba.it", "arubapec.it", "pec.it", "legalmail.it"],
    ),
];

impl Trust {
    pub fn for_account(account: &Account) -> Trust {
        let host = match &account.kind {
            AccountKind::Imap { imap, .. } => imap.host.to_ascii_lowercase(),
            AccountKind::Jmap { session_url, .. } => session_url
                .split("://")
                .nth(1)
                .and_then(|r| r.split(['/', ':']).next())
                .unwrap_or_default()
                .to_ascii_lowercase(),
        };
        for (hosts, ids) in KNOWN {
            if hosts.iter().any(|d| under(&host, d)) {
                return Trust {
                    domains: ids.iter().map(|d| (*d).to_owned()).collect(),
                    known: true,
                };
            }
        }
        Trust {
            domains: vec![organization(&host)],
            known: false,
        }
    }

    fn covers(&self, host: &str) -> bool {
        self.domains.iter().any(|d| under(host, d))
    }
}

/// The headers of a message that tell whether its sender is verified.
pub fn trail(m: &Message, raw: &[u8]) -> Trail {
    let from_domain = m
        .from()
        .and_then(|a| a.first())
        .and_then(|a| a.address())
        .and_then(|e| e.rsplit_once('@'))
        .map(|(_, d)| d.trim().to_ascii_lowercase())
        .unwrap_or_default();
    let mut steps = Vec::new();
    for h in m.headers() {
        let name = h.name.as_str();
        let value = raw
            .get(h.offset_start as usize..h.offset_end as usize)
            .map(|v| String::from_utf8_lossy(v).replace(['\r', '\n'], " "))
            .unwrap_or_default();
        if name.eq_ignore_ascii_case("received") {
            steps.push(Step::Received {
                by: received_word(&value, "by"),
                from: received_word(&value, "from"),
            });
        } else if name.eq_ignore_ascii_case("authentication-results") {
            if let Some(step) = results(&value) {
                steps.push(step);
            }
        }
    }
    Trail { from_domain, steps }
}

/// The checks the account's server wrote, as far as they can be believed.
fn believed<'a>(trail: &'a Trail, trust: &Trust) -> Vec<&'a Method> {
    let mut believed: Vec<&Vec<Method>> = Vec::new();
    let mut ids: Vec<&str> = Vec::new();
    for step in &trail.steps {
        match step {
            Step::Received { by, .. } => {
                let theirs = by.as_deref().is_some_and(|h| named(h) && !trust.covers(h));
                if !trust.known || theirs {
                    break;
                }
            }
            // The first results under each name: a sender's look-alike
            // comes after the real one.
            Step::Results { id, methods } => {
                if trust.covers(id) && !ids.contains(&id.as_str()) {
                    ids.push(id);
                    believed.push(methods);
                }
            }
        }
    }
    believed.into_iter().flatten().collect()
}

/// The domain a passing DKIM signature is from.
fn signer(m: &Method) -> Option<&str> {
    if m.name != "dkim" || m.result != "pass" {
        return None;
    }
    m.prop("header.d").or_else(|| {
        m.prop("header.i")
            .and_then(|i| i.rsplit_once('@').map(|(_, d)| d))
    })
}

/// Whether the account's server vouches for the domain in From: DMARC
/// passed, or, where it wasn't checked, a DKIM signature of that domain.
pub fn verified(trail: &Trail, trust: &Trust) -> bool {
    if trail.from_domain.is_empty() {
        return false;
    }
    let methods = believed(trail, trust);
    let from = trail.from_domain.as_str();
    if let Some(d) = methods.iter().find(|m| m.name == "dmarc") {
        return d.result == "pass" && d.prop("header.from").is_none_or(|f| aligned(f, from));
    }
    methods
        .iter()
        .filter_map(|m| signer(m))
        .any(|d| aligned(d, from))
}

/// What the account's server found, for a sender warning's Details.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Checked {
    /// The domain in From has a DMARC policy, and this message failed it:
    /// whoever sent it isn't that domain.
    pub dmarc_failed: bool,
    /// The domain whose DKIM signature passed, if one did.
    pub signed_by: Option<String>,
    /// The server that handed the message to the account's provider.
    pub sent_by: Option<String>,
}

pub fn checked(trail: &Trail, trust: &Trust) -> Checked {
    let methods = believed(trail, trust);
    let from = trail.from_domain.as_str();
    let dmarc_failed = !from.is_empty()
        && methods.iter().find(|m| m.name == "dmarc").is_some_and(|d| {
            d.result == "fail" && d.prop("header.from").is_none_or(|f| aligned(f, from))
        });
    let signed_by = methods.iter().find_map(|m| signer(m)).map(str::to_owned);
    // The first hop, from the top, that came from outside the provider.
    let sent_by = trail.steps.iter().find_map(|s| match s {
        Step::Received { from: Some(h), .. } if named(h) && !trust.covers(h) => Some(h.clone()),
        _ => None,
    });
    Checked {
        dmarc_failed,
        signed_by,
        sent_by,
    }
}

/// The host a Received line names after "by" or "from".
fn received_word(value: &str, word: &str) -> Option<String> {
    let value = without_comments(value);
    let mut words = value.split_whitespace();
    while let Some(w) = words.next() {
        if w.eq_ignore_ascii_case(word) {
            return words
                .next()
                .map(|h| h.trim_matches([';', '[', ']', '.']).to_ascii_lowercase());
        }
    }
    None
}

/// "mx.example.com; dkim=pass header.d=a.org; spf=fail" as its parts.
fn results(value: &str) -> Option<Step> {
    let value = without_comments(value);
    let mut parts = value.split(';');
    let id = parts
        .next()?
        .split_whitespace()
        .next()?
        .to_ascii_lowercase();
    let methods = parts
        .filter_map(|p| {
            let mut words = p.split_whitespace();
            let (name, result) = words.next()?.split_once('=')?;
            Some(Method {
                name: name.split('/').next()?.to_ascii_lowercase(),
                result: result.to_ascii_lowercase(),
                props: words
                    .filter_map(|w| w.split_once('='))
                    .map(|(k, v)| {
                        (
                            k.to_ascii_lowercase(),
                            v.trim_matches('"').to_ascii_lowercase(),
                        )
                    })
                    .collect(),
            })
        })
        .collect();
    Some(Step::Results { id, methods })
}

/// The text without its (comments), which may nest.
fn without_comments(value: &str) -> String {
    let mut depth = 0usize;
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '(' => depth += 1,
            ')' if depth > 0 => depth -= 1,
            _ if depth == 0 => out.push(c),
            _ => {}
        }
    }
    out
}

/// A host name, not an address or a server's private name.
fn named(host: &str) -> bool {
    host.contains('.') && !host.chars().all(|c| c.is_ascii_digit() || c == '.')
}

pub(crate) fn under(host: &str, domain: &str) -> bool {
    host == domain || host.ends_with(&format!(".{domain}"))
}

/// The domain an organization owns: "mail.example.co.uk" is
/// "example.co.uk".
pub(crate) fn organization(host: &str) -> String {
    let labels: Vec<&str> = host.trim_end_matches('.').split('.').collect();
    let n = labels.len();
    if n < 2 {
        return host.to_owned();
    }
    let second = labels[n - 2];
    let take = if n >= 3
        && labels[n - 1].len() == 2
        && ["co", "com", "net", "org", "gov", "ac", "edu"].contains(&second)
    {
        3
    } else {
        2
    };
    labels[n - take..].join(".")
}

/// Relaxed alignment (RFC 7489): the same organization's domain.
fn aligned(a: &str, b: &str) -> bool {
    organization(a) == organization(b)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{AccountId, Security, Server};
    use mail_parser::MessageParser;

    fn account(host: &str) -> Account {
        Account {
            id: AccountId(1),
            name: "Work".into(),
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
        }
    }

    fn check(raw: &str, host: &str) -> bool {
        let m = MessageParser::default().parse(raw.as_bytes()).unwrap();
        verified(
            &trail(&m, raw.as_bytes()),
            &Trust::for_account(&account(host)),
        )
    }

    const GMAIL: &str = "Delivered-To: matteo@gmail.com\r\n\
Received: by 2002:a05:6a10:1234 with SMTP id x; Mon, 19 Oct 2026 08:15:00 -0700 (PDT)\r\n\
Received: from mail.ferramentabianchi.it (mail.ferramentabianchi.it. [203.0.113.5])\r\n        by mx.google.com with ESMTPS id y; Mon, 19 Oct 2026 08:14:59 -0700 (PDT)\r\n\
Authentication-Results: mx.google.com;\r\n       dkim=pass header.i=@ferramentabianchi.it header.s=s1 header.b=abc;\r\n       spf=pass (google.com: domain of luca@ferramentabianchi.it designates 203.0.113.5) smtp.mailfrom=luca@ferramentabianchi.it;\r\n       dmarc=pass (p=NONE sp=NONE dis=NONE) header.from=ferramentabianchi.it\r\n\
Received: from laptop (unknown) by mail.ferramentabianchi.it; Mon, 19 Oct 2026 17:14:58 +0200\r\n\
From: Luca Bianchi <luca@ferramentabianchi.it>\r\n\
Subject: Quote\r\n\r\nHello\r\n";

    #[test]
    fn gmail_vouches_for_a_dmarc_pass() {
        assert!(check(GMAIL, "imap.gmail.com"));
    }

    #[test]
    fn aruba_vouches_across_internal_hops() {
        let raw = "Received: from mbox.aruba.it by mbox01.aruba.it with LMTP; Mon, 19 Oct 2026 08:00:01 +0200\r\n\
Received: from mail.ferramentabianchi.it (mail.ferramentabianchi.it [203.0.113.5]) by mx.aruba.it with ESMTPS; Mon, 19 Oct 2026 08:00:00 +0200\r\n\
Authentication-Results: mx.aruba.it; dmarc=pass header.from=ferramentabianchi.it\r\n\
From: Luca Bianchi <luca@ferramentabianchi.it>\r\n\
Subject: Quote\r\n\r\nHello\r\n";
        assert!(check(raw, "imaps.aruba.it"));
    }

    #[test]
    fn a_look_alike_of_the_sender_counts_for_nothing() {
        // The sender wrote a "pass" of their own; the server found a fail.
        let forged = GMAIL
            .replace("dmarc=pass (p=NONE sp=NONE dis=NONE)", "dmarc=fail (p=REJECT)")
            .replace(
                "From: Luca",
                "Authentication-Results: mx.google.com; dmarc=pass header.from=ferramentabianchi.it\r\nFrom: Luca",
            );
        assert!(!check(&forged, "imap.gmail.com"));
    }

    #[test]
    fn results_below_another_server_are_not_believed() {
        // A server that writes no results: the only ones came with the
        // message, below the hop of the account's own server.
        let raw = "Received: from mail.attacker.example by mx.studio.it; Mon, 19 Oct 2026 08:00:00 +0200\r\n\
Authentication-Results: mx.studio.it; dmarc=pass header.from=bank.example\r\n\
From: Bank <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(!check(raw, "imap.studio.it"));
        // The same results written above every hop, as a filter on the
        // account's own server does, are its own.
        let own = "Authentication-Results: mx.studio.it; dmarc=pass header.from=bank.example\r\n\
Received: from mail.bank.example by mx.studio.it; Mon, 19 Oct 2026 08:00:00 +0200\r\n\
From: Bank <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(check(own, "imap.studio.it"));
        // From another server's name, even on top, they are not.
        assert!(!check(
            &own.replace("mx.studio.it;", "mx.other.example;"),
            "imap.studio.it"
        ));
    }

    #[test]
    fn dkim_of_the_from_domain_without_dmarc() {
        let raw = "Authentication-Results: mx.studio.it; dkim=pass header.d=news.bottegalume.it; spf=pass\r\n\
From: Bottega Lume <ciao@bottegalume.it>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(check(raw, "imap.studio.it"));
        let other = raw.replace("header.d=news.bottegalume.it", "header.d=mailer.example");
        assert!(!check(&other, "imap.studio.it"));
        // SPF alone says nothing about From.
        let spf = "Authentication-Results: mx.studio.it; spf=pass smtp.mailfrom=bottegalume.it\r\n\
From: <ciao@bottegalume.it>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(!check(spf, "imap.studio.it"));
    }

    #[test]
    fn icloud_writes_one_header_per_check() {
        let raw = "Received: from p00-icloudmta-asmtp-us-west-2a by p00-icloudmta-asmtp-us-west-2a (Oracle) with ESMTP\r\n\
Authentication-Results: dmarc.icloud.com; dmarc=pass header.from=example.org\r\n\
Authentication-Results: dkim-verifier.icloud.com; dkim=pass header.d=example.org\r\n\
Received: from mail.example.org by mx01.mail.icloud.com; Mon, 19 Oct 2026 08:00:00 +0000\r\n\
From: <anna@example.org>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(check(raw, "imap.mail.me.com"));
    }

    #[test]
    fn organizations() {
        assert_eq!(organization("mail.example.co.uk"), "example.co.uk");
        assert_eq!(organization("imap.studio.it"), "studio.it");
        assert!(aligned("news.bottegalume.it", "bottegalume.it"));
        assert!(!aligned("bottegalume.it", "lume.it"));
    }
}
