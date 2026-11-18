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

/// The headers that matter, top to bottom, the domain in From, and the
/// DKIM signatures the message carries.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Trail {
    pub from_domain: String,
    pub steps: Vec<Step>,
    pub signatures: Vec<Signature>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
    /// A server's hop: the host after "by", when it names one, and the
    /// one it took the message from: the name that host gave itself
    /// (`from`, its HELO, which it chooses), and the address the server
    /// saw it connect from, when the line says.
    Received {
        by: Option<String>,
        from: Option<String>,
        from_ip: Option<std::net::IpAddr>,
    },
    /// What a server found, by the name it signs with (`authserv-id`).
    Results { id: String, methods: Vec<Method> },
}

/// One DKIM-Signature header, as far as [`list_signed`] needs it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Signature {
    /// The signing domain, `d=`, lowercase.
    pub domain: String,
    /// The signature itself, `b=`, without spaces: a server's results
    /// name the one they checked by its first characters (`header.b`).
    pub b: String,
    /// The header fields it covers, `h=`, lowercase.
    pub headers: Vec<String>,
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

/// The name a provider signs its results with.
#[derive(Debug, Clone, PartialEq, Eq)]
enum Id {
    /// Exactly this name.
    Exact(&'static str),
    /// The prefix, a number, the suffix: `mx` 1…n `.messagingengine.com`.
    Numbered(&'static str, &'static str),
    /// Any name under the domain.
    Under(String),
    /// No name at all: Microsoft's results start with the first check.
    Nameless,
}

impl Id {
    fn matches(&self, id: &str) -> bool {
        match self {
            Id::Exact(name) => id == *name,
            Id::Numbered(prefix, suffix) => id
                .strip_prefix(prefix)
                .and_then(|r| r.strip_suffix(suffix))
                .is_some_and(|n| {
                    !n.is_empty() && n.len() <= 3 && n.bytes().all(|b| b.is_ascii_digit())
                }),
            Id::Under(domain) => under(id, domain),
            Id::Nameless => id.is_empty(),
        }
    }
}

/// How a provider writes its results, and so what can be believed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Shape {
    /// One header per message under one name (or names of one family).
    /// The top-most is the provider's: whatever the sender wrote comes
    /// below it, so any later one under the provider's name or domain is
    /// a forgery.
    Single,
    /// One header per check, each under its own name, all above the hop
    /// where the message entered the provider. Any of them at or below
    /// that hop is a forgery.
    Multi,
    /// One header under the name of the server that took the message: it
    /// counts only when that name is the "by" of the hop where the
    /// message entered, above it or right under it.
    Numbered,
    /// A server we know nothing about: results above the hop where the
    /// message entered, under the server's own domain. Nothing is called
    /// a forgery, since we don't know what the server strips.
    Unknown,
}

/// The servers whose results an account can believe.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Trust {
    /// The names its provider writes its results under.
    ids: Vec<Id>,
    /// The domains of the provider's own servers: hops by them are its
    /// own, and results named under them but not with one of [`ids`] are
    /// a look-alike.
    domains: Vec<String>,
    shape: Shape,
}

/// One provider that checks every message it accepts from outside and
/// writes what it found.
struct Provider {
    /// The account's server is under one of these.
    hosts: &'static [&'static str],
    /// The names its results are written under.
    ids: &'static [Id],
    /// Where its own servers are.
    domains: &'static [&'static str],
    shape: Shape,
}

/// What is assumed of each provider (from their published headers,
/// November 2026; the tests carry one stack of each):
///
/// - Gmail writes one `Authentication-Results: mx.google.com` on every
///   message it accepts from outside, right under its own `Received`,
///   with `dmarc=` only when the From domain publishes a DMARC record.
/// - Outlook.com and Microsoft 365 write one header with no name at all
///   (`spf=pass (sender IP is …) …; dmarc=pass action=none …`), above the
///   hop of `*.mail.protection.outlook.com` that took the message.
/// - Yahoo writes one header named after the server that checked
///   (`atlas…mail…yahoo.com`), above its own hop.
/// - iCloud writes one header per check, each under its own exact name
///   (`dmarc.icloud.com`, `dkim-verifier.icloud.com`…), above the hop
///   where the message entered.
/// - Fastmail writes one header named after the MX that took the message,
///   `mx1.messagingengine.com` to `mx999.messagingengine.com`; its hops
///   in between are on private addresses (`*.internal`).
///
/// Every one of them writes its header on every message it accepts from
/// outside: a sender's header can only come below it. Any other server
/// (Aruba, a company's own) is believed only above the hop where the
/// message entered it.
const KNOWN: &[Provider] = &[
    Provider {
        hosts: &["gmail.com", "googlemail.com", "google.com"],
        ids: &[Id::Exact("mx.google.com")],
        domains: &["google.com"],
        shape: Shape::Single,
    },
    Provider {
        hosts: &["outlook.com", "office365.com", "hotmail.com", "live.com"],
        ids: &[Id::Nameless],
        domains: &["outlook.com", "office365.com"],
        shape: Shape::Single,
    },
    Provider {
        hosts: &["yahoo.com"],
        ids: &[Id::Under(String::new())],
        domains: &["yahoo.com"],
        shape: Shape::Single,
    },
    Provider {
        hosts: &["me.com", "icloud.com", "apple.com"],
        ids: &[
            Id::Exact("dmarc.icloud.com"),
            Id::Exact("dkim-verifier.icloud.com"),
            Id::Exact("spf.icloud.com"),
            Id::Exact("bimi.icloud.com"),
            Id::Exact("arc-verifier.icloud.com"),
        ],
        domains: &["icloud.com", "me.com", "apple.com"],
        shape: Shape::Multi,
    },
    Provider {
        hosts: &["fastmail.com", "messagingengine.com"],
        ids: &[Id::Numbered("mx", ".messagingengine.com")],
        domains: &["messagingengine.com", "fastmail.com"],
        shape: Shape::Numbered,
    },
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
        for p in KNOWN {
            if p.hosts.iter().any(|d| under(&host, d)) {
                let domains: Vec<String> = p.domains.iter().map(|d| (*d).to_owned()).collect();
                let ids = p
                    .ids
                    .iter()
                    .map(|i| match i {
                        // A family of names: under the provider's domain.
                        Id::Under(d) if d.is_empty() => Id::Under(domains[0].clone()),
                        other => other.clone(),
                    })
                    .collect();
                return Trust {
                    ids,
                    domains,
                    shape: p.shape,
                };
            }
        }
        let org = organization(&host);
        Trust {
            ids: vec![Id::Under(org.clone())],
            domains: vec![org],
            shape: Shape::Unknown,
        }
    }

    /// Results under this name are the provider's own.
    fn pinned(&self, id: &str) -> bool {
        self.ids.iter().any(|i| i.matches(id))
    }

    /// A server of the provider's.
    fn own(&self, host: &str) -> bool {
        named(host) && self.domains.iter().any(|d| under(host, d))
    }

    /// Results that claim to be the provider's, by its name or a name of
    /// its domain.
    fn claims(&self, id: &str) -> bool {
        self.pinned(id) || self.own(id)
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
    let mut signatures = Vec::new();
    for h in m.headers() {
        let header_name = h.name();
        let name = header_name.as_str();
        let value = raw
            .get(h.offset_start() as usize..h.offset_end() as usize)
            .map(|v| String::from_utf8_lossy(v).replace(['\r', '\n'], " "))
            .unwrap_or_default();
        if name.eq_ignore_ascii_case("received") {
            steps.push(Step::Received {
                by: received_word(&value, "by"),
                from: received_word(&value, "from"),
                from_ip: received_ip(&value),
            });
        } else if name.eq_ignore_ascii_case("authentication-results") {
            if let Some(step) = results(&value) {
                steps.push(step);
            }
        } else if name.eq_ignore_ascii_case("dkim-signature") {
            if let Some(s) = signature(&value) {
                signatures.push(s);
            }
        }
    }
    Trail {
        from_domain,
        steps,
        signatures,
    }
}

/// The checks the provider wrote, as far as they can be believed, and
/// whether something below them imitates the provider.
struct Believed<'a> {
    methods: Vec<&'a Method>,
    /// Results under the provider's name (or a look-alike of it) that it
    /// didn't write: whoever sent the message tried to pass for it.
    forged: bool,
}

/// A hop's sending side is the provider's own: an address of a private
/// network or the machine itself, or, when the line gives no address,
/// a name of the provider's or a private one. A public address is
/// always someone else's (its reverse name is the sender's to choose),
/// and so is the name a sender gives itself next to one.
fn from_inside(trust: &Trust, from: Option<&str>, ip: Option<std::net::IpAddr>) -> bool {
    // A bare address in place of a name counts as the address.
    let ip = ip.or_else(|| from.and_then(|h| h.parse().ok()));
    match ip {
        Some(ip) => private(ip),
        // No address: one of the provider's machines, which name
        // themselves without a domain (`p00-icloudmta-…`) or with its own.
        // The hop where a message comes in from outside always has one.
        None => from.is_none_or(|h| {
            !h.contains('.')
                || trust.own(h)
                || [".internal", ".local", ".localdomain"]
                    .iter()
                    .any(|s| h.ends_with(s))
        }),
    }
}

/// Where the message entered the provider, from the top: the first hop by
/// one of its servers (or an unnamed one) from outside, and the server
/// that took it. None when a server of someone else's comes first, or
/// there is none.
fn ingress<'a>(trail: &'a Trail, trust: &Trust) -> Option<(usize, &'a str)> {
    for (i, step) in trail.steps.iter().enumerate() {
        let Step::Received { by, from, from_ip } = step else {
            continue;
        };
        let by = by.as_deref().unwrap_or_default();
        if named(by) && !trust.own(by) {
            return None;
        }
        if !from_inside(trust, from.as_deref(), *from_ip) {
            return Some((i, by));
        }
    }
    None
}

/// The first hop, from the top, by a server that isn't the provider's.
fn foreign(trail: &Trail, trust: &Trust) -> usize {
    trail
        .steps
        .iter()
        .position(|s| matches!(s, Step::Received { by: Some(h), .. } if named(h) && !trust.own(h)))
        .unwrap_or(trail.steps.len())
}

fn believed<'a>(trail: &'a Trail, trust: &Trust) -> Believed<'a> {
    let mut methods = Vec::new();
    let mut taken: Vec<&str> = Vec::new();
    let mut forged = false;
    let entered = ingress(trail, trust);
    let foreign = foreign(trail, trust);
    // Where the provider's own results can be: above the hop where the
    // message entered, or for some, right under it.
    let limit = match (trust.shape, entered) {
        (Shape::Single, _) => foreign,
        (Shape::Numbered, Some((i, _))) => trail.steps[i + 1..]
            .iter()
            .position(|s| matches!(s, Step::Received { .. }))
            .map_or(trail.steps.len(), |n| i + 1 + n),
        (Shape::Multi | Shape::Unknown, Some((i, _))) => i,
        // No hop from outside: mail between the provider's own users,
        // above any server of someone else's.
        (_, None) => foreign,
    };
    let entry_by = entered.map(|(_, by)| by);
    let warns = trust.shape != Shape::Unknown;
    for (i, step) in trail.steps.iter().enumerate() {
        let Step::Results { id, methods: m } = step else {
            continue;
        };
        // A numbered name counts only for the server that took the
        // message (any, for mail that never came from outside).
        let pinned = trust.pinned(id)
            && (trust.shape != Shape::Numbered || entry_by.is_none_or(|b| b == id));
        let above_entry = entered.is_none_or(|(e, _)| i < e);
        // One header in all for a provider that writes one.
        let room = if trust.shape == Shape::Single {
            taken.is_empty()
        } else {
            !taken.contains(&id.as_str())
        };
        if i < limit && pinned && room {
            // The top-most results under each name: the provider adds
            // its own above what came with the message.
            taken.push(id);
            methods.extend(m.iter());
        } else if !warns || !trust.claims(id) {
            // Another server's results: not ours to judge.
        } else if trust.shape == Shape::Multi && above_entry && i < limit {
            // A second header of the provider's own, where only it
            // writes.
        } else {
            // Its name a second time where a sender writes, its name
            // below the hop where the message came in, another of its
            // servers' names than the one that took the message, or a
            // name of its domain it never signs with.
            forged = true;
        }
    }
    Believed { methods, forged }
}

/// An address of a private network or of the machine itself.
fn private(ip: std::net::IpAddr) -> bool {
    match ip {
        std::net::IpAddr::V4(v) => {
            v.is_private() || v.is_loopback() || v.is_link_local() || v.is_unspecified()
        }
        std::net::IpAddr::V6(v) => {
            let first = v.segments()[0];
            v.is_loopback()
                || v.is_unspecified()
                || (first & 0xfe00) == 0xfc00
                || (first & 0xffc0) == 0xfe80
                || v.to_ipv4_mapped().is_some_and(|v4| private(v4.into()))
        }
    }
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
    let believed = believed(trail, trust);
    if believed.forged {
        return false;
    }
    let methods = believed.methods;
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
    /// whoever sent it isn't that domain. Also set when the message
    /// carries results that imitate the provider's own.
    pub dmarc_failed: bool,
    /// The domain whose DKIM signature passed, if one did.
    pub signed_by: Option<String>,
    /// The server that handed the message to the account's provider.
    pub sent_by: Option<String>,
    /// DMARC itself passed for the domain in From (not only a DKIM
    /// signature of it): what a brand logo needs, with the domain's
    /// policy (see `pictures::logo`).
    pub dmarc_pass: bool,
    /// A DKIM signature of the From domain that passed covers
    /// List-Unsubscribe and List-Unsubscribe-Post (RFC 8058 section 4).
    pub list_signed: bool,
}

pub fn checked(trail: &Trail, trust: &Trust) -> Checked {
    let believed = believed(trail, trust);
    let forged = believed.forged;
    let methods = believed.methods;
    let from = trail.from_domain.as_str();
    let dmarc = methods.iter().find(|m| m.name == "dmarc");
    let dmarc_failed = forged
        || !from.is_empty()
            && dmarc.is_some_and(|d| {
                d.result == "fail" && d.prop("header.from").is_none_or(|f| aligned(f, from))
            });
    let dmarc_pass = !forged
        && !from.is_empty()
        && dmarc.is_some_and(|d| {
            d.result == "pass" && d.prop("header.from").is_none_or(|f| aligned(f, from))
        });
    let signed_by = methods.iter().find_map(|m| signer(m)).map(str::to_owned);
    let list_signed = !forged
        && !from.is_empty()
        && methods
            .iter()
            .any(|m| signer(m).is_some_and(|d| aligned(d, from) && covers_list(trail, m, d)));
    // The first hop, from the top, that came from outside the provider.
    let sent_by = trail.steps.iter().find_map(|s| match s {
        Step::Received {
            from: Some(h),
            from_ip,
            ..
        } if named(h) && !from_inside(trust, Some(h), *from_ip) => Some(h.clone()),
        _ => None,
    });
    Checked {
        dmarc_failed,
        signed_by,
        sent_by,
        dmarc_pass,
        list_signed,
    }
}

/// Whether the DKIM signature a passing result `m` of `domain` is about
/// covers both list headers. Where the result names the signature by its
/// first characters (`header.b`, compared as written: base64 tells case
/// apart), only that one counts; where it doesn't, only a message with
/// one signature of that domain can say which one passed.
fn covers_list(trail: &Trail, m: &Method, domain: &str) -> bool {
    let of_domain: Vec<&Signature> = trail
        .signatures
        .iter()
        .filter(|s| s.domain == domain)
        .collect();
    let candidates: Vec<&Signature> = match m.prop("header.b") {
        Some(b) if !b.is_empty() => of_domain
            .into_iter()
            .filter(|s| s.b.starts_with(b))
            .collect(),
        Some(_) => Vec::new(),
        None if of_domain.len() == 1 => of_domain,
        None => Vec::new(),
    };
    // Two signatures that both start with what the result names can't
    // be told apart either.
    candidates.len() == 1
        && ["list-unsubscribe", "list-unsubscribe-post"]
            .iter()
            .all(|h| candidates[0].headers.iter().any(|x| x == h))
}

/// "v=1; a=rsa-sha256; d=shop.it; h=From:List-Unsubscribe; b=…".
fn signature(value: &str) -> Option<Signature> {
    let mut out = Signature {
        domain: String::new(),
        b: String::new(),
        headers: Vec::new(),
    };
    for tag in value.split(';') {
        let Some((k, v)) = tag.split_once('=') else {
            continue;
        };
        let v: String = v.split_whitespace().collect();
        match k.trim() {
            "d" => out.domain = v.to_ascii_lowercase(),
            "b" => out.b = v,
            "h" => {
                out.headers = v
                    .split(':')
                    .map(|h| h.trim().to_ascii_lowercase())
                    .filter(|h| !h.is_empty())
                    .collect()
            }
            _ => {}
        }
    }
    (!out.domain.is_empty()).then_some(out)
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
/// Microsoft writes no name: its first part is already a check, and the
/// name is then empty. Values are lowercase but `header.b`, a piece of a
/// signature, which is kept as written.
fn results(value: &str) -> Option<Step> {
    let value = without_comments(value);
    let mut parts = value.split(';').peekable();
    let first = parts.peek()?.split_whitespace().next()?;
    let id = if first.contains('=') {
        String::new()
    } else {
        parts.next();
        first.to_ascii_lowercase()
    };
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
                        let k = k.to_ascii_lowercase();
                        let v = v.trim_matches('"');
                        let v = if k == "header.b" {
                            v.to_owned()
                        } else {
                            v.to_ascii_lowercase()
                        };
                        (k, v)
                    })
                    .collect(),
            })
        })
        .collect();
    Some(Step::Results { id, methods })
}

/// The address a Received line says the sending host connected from:
/// the first IP address in the comments of its "from" part, as
/// `(name [192.0.2.1])`, `(192.0.2.1)` or `[IPv6:2001:db8::1]`.
fn received_ip(value: &str) -> Option<std::net::IpAddr> {
    // The "from" part: from its word to the first "by" outside comments.
    let mut depth = 0usize;
    let mut word = String::new();
    let mut comment = String::new();
    let mut in_from = false;
    let mut comments = Vec::new();
    for c in value.chars().chain(std::iter::once(' ')) {
        match c {
            '(' => {
                depth += 1;
                if depth == 1 {
                    comment.clear();
                    continue;
                }
            }
            ')' if depth > 0 => {
                depth -= 1;
                if depth == 0 {
                    if in_from {
                        comments.push(std::mem::take(&mut comment));
                    }
                    continue;
                }
            }
            _ => {}
        }
        if depth > 0 {
            comment.push(c);
        } else if c.is_whitespace() || c == ';' {
            if word.eq_ignore_ascii_case("from") {
                in_from = true;
            } else if in_from
                && ["by", "with", "id", "via", "for"]
                    .iter()
                    .any(|w| word.eq_ignore_ascii_case(w))
            {
                break;
            }
            word.clear();
        } else {
            word.push(c);
        }
    }
    comments.iter().find_map(|text| {
        text.split(|c: char| c.is_whitespace() || c == '[' || c == ']' || c == ',')
            .map(|t| t.trim_start_matches("IPv6:").trim_start_matches("ipv6:"))
            .find_map(|t| t.parse::<std::net::IpAddr>().ok())
    })
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

/// A host name, not an address or a server's private name
/// (`compute2.internal`, `mx.local`).
fn named(host: &str) -> bool {
    host.contains('.')
        && !host.chars().all(|c| c.is_ascii_digit() || c == '.')
        && ![".internal", ".local", ".localdomain"]
            .iter()
            .any(|s| host.ends_with(s))
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
    fn providers_without_a_pinned_name_fall_to_the_general_rule() {
        // Aruba's results sit under its own hop: without a name it is
        // known to sign with, they could be anyone's.
        let below = "Received: from mbox.aruba.it by mbox01.aruba.it with LMTP; Mon, 19 Oct 2026 08:00:01 +0200\r\n\
Received: from mail.ferramentabianchi.it (mail.ferramentabianchi.it [203.0.113.5]) by mx.aruba.it with ESMTPS; Mon, 19 Oct 2026 08:00:00 +0200\r\n\
Authentication-Results: mx.aruba.it; dmarc=pass header.from=ferramentabianchi.it\r\n\
From: Luca Bianchi <luca@ferramentabianchi.it>\r\n\
Subject: Quote\r\n\r\nHello\r\n";
        assert!(!check(below, "imaps.aruba.it"));
        // Written on top by a filter of the account's own server: its own.
        let top = "Authentication-Results: mx.aruba.it; dmarc=pass header.from=ferramentabianchi.it\r\n\
Received: from mail.ferramentabianchi.it by mx.aruba.it with ESMTPS; Mon, 19 Oct 2026 08:00:00 +0200\r\n\
From: Luca Bianchi <luca@ferramentabianchi.it>\r\n\
Subject: Quote\r\n\r\nHello\r\n";
        assert!(check(top, "imaps.aruba.it"));
    }

    fn checks(raw: &str, host: &str) -> Checked {
        let m = MessageParser::default().parse(raw.as_bytes()).unwrap();
        checked(
            &trail(&m, raw.as_bytes()),
            &Trust::for_account(&account(host)),
        )
    }

    /// Gmail's own results for a From domain that publishes no DMARC
    /// record: no `dmarc=` at all, and no DKIM signature of it.
    const GMAIL_NO_DMARC: &str = "Delivered-To: matteo@gmail.com\r\n\
Received: by 2002:a05:6a10:1234 with SMTP id x; Mon, 19 Oct 2026 08:15:00 -0700 (PDT)\r\n\
Received: from mail.attacker.example (mail.attacker.example. [198.51.100.7])\r\n        by mx.google.com with ESMTPS id y; Mon, 19 Oct 2026 08:14:59 -0700 (PDT)\r\n\
Authentication-Results: mx.google.com;\r\n       spf=pass (google.com: domain of x@attacker.example designates 198.51.100.7) smtp.mailfrom=x@attacker.example\r\n\
FORGED\
From: Bank <help@bank.example>\r\n\
Subject: Your account\r\n\r\nHello\r\n";

    #[test]
    fn a_look_alike_under_the_real_results_is_a_red_flag() {
        let honest = GMAIL_NO_DMARC.replace("FORGED", "");
        assert!(!check(&honest, "imap.gmail.com"));
        assert!(!checks(&honest, "imap.gmail.com").dmarc_failed);
        // Another name of Google's, right under Gmail's own header.
        let look_alike = GMAIL_NO_DMARC.replace(
            "FORGED",
            "Authentication-Results: mx2.google.com; dmarc=pass header.from=bank.example\r\n",
        );
        assert!(!check(&look_alike, "imap.gmail.com"));
        let c = checks(&look_alike, "imap.gmail.com");
        assert!(c.dmarc_failed && !c.dmarc_pass);
        // Gmail's exact name, a second time.
        let twice = GMAIL_NO_DMARC.replace(
            "FORGED",
            "Authentication-Results: mx.google.com; dmarc=pass header.from=bank.example; dkim=pass header.d=bank.example\r\n",
        );
        assert!(!check(&twice, "imap.gmail.com"));
        assert!(checks(&twice, "imap.gmail.com").dmarc_failed);
    }

    #[test]
    fn only_the_provider_s_exact_names_count() {
        // On top, where only Gmail writes, but not a name Gmail uses.
        let raw = "Authentication-Results: mx9.google.com; dmarc=pass header.from=bank.example\r\n\
Received: from mail.bank.example by mx.google.com; Mon, 19 Oct 2026 08:00:00 +0000\r\n\
From: <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(!check(raw, "imap.gmail.com"));
        assert!(check(
            &raw.replace("mx9.google.com;", "mx.google.com;"),
            "imap.gmail.com"
        ));
    }

    #[test]
    fn fastmail_signs_with_the_mx_that_took_the_message() {
        let raw = "Received: from compute2.internal (compute2.nyi.internal [10.202.2.42]) by sloti22d1t09 (Cyrus) with LMTPA\r\n\
Received: from mx6.messagingengine.com (mx6.nyi.internal [10.202.2.205]) by mailmx.nyi.internal (Postfix) with ESMTP\r\n\
Authentication-Results: mx6.messagingengine.com; dkim=pass header.d=example.org; dmarc=pass policy.published-domain-policy=reject header.from=example.org\r\n\
Received: from mail.example.org (mail.example.org [192.0.2.1]) by mx6.messagingengine.com (Postfix) with ESMTPS\r\n\
From: <anna@example.org>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(check(raw, "imap.fastmail.com"));
        assert!(checks(raw, "imap.fastmail.com").dmarc_pass);
        assert!(!check(
            &raw.replace(
                "Authentication-Results: mx6.",
                "Authentication-Results: mxx."
            ),
            "imap.fastmail.com"
        ));
    }

    #[test]
    fn one_click_needs_a_signature_over_the_list_headers() {
        let raw = |h: &str| {
            format!(
                "Received: from mail.shop.example by mx.google.com; Mon, 19 Oct 2026 08:00:00 +0000\r\n\
Authentication-Results: mx.google.com; dkim=pass header.i=@shop.example header.s=s1 header.b=AbCdEf12; dmarc=pass header.from=shop.example\r\n\
DKIM-Signature: v=1; a=rsa-sha256; d=shop.example; s=s1;\r\n h={h};\r\n bh=x; b=AbCdEf12345\r\n  6789\r\n\
From: <news@shop.example>\r\nList-Unsubscribe: <https://shop.example/u>\r\nList-Unsubscribe-Post: List-Unsubscribe=One-Click\r\nSubject: x\r\n\r\nHi\r\n"
            )
        };
        let covered = raw("From:Subject:List-Unsubscribe:List-Unsubscribe-Post");
        assert!(checks(&covered, "imap.gmail.com").list_signed);
        let not_covered = raw("From:Subject");
        // DMARC passed, but nothing signed the list headers: no one-click.
        let c = checks(&not_covered, "imap.gmail.com");
        assert!(c.dmarc_pass && !c.list_signed);
        assert!(!crate::newsletter::one_click_allowed(
            &crate::model::ListInfo {
                newsletter: true,
                unsubscribe: "https://shop.example/u".into(),
                one_click: true,
                ..Default::default()
            },
            c.list_signed
        ));
        // Another signature than the one that passed.
        let other = covered.replace("b=AbCdEf12345", "b=ZZZZ12345");
        assert!(!checks(&other, "imap.gmail.com").list_signed);
        // Nothing the provider wrote: no signature can be believed.
        let unchecked = covered.replace("mx.google.com; dkim", "mx.example; dkim");
        assert!(!checks(&unchecked, "imap.gmail.com").list_signed);
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
    fn fastmail_believes_only_the_mx_that_took_the_message() {
        let raw = "Received: from mx6.messagingengine.com (mx6.nyi.internal [10.202.2.205]) by mailmx.nyi.internal (Postfix) with ESMTP\r\n\
Authentication-Results: mx6.messagingengine.com; spf=pass smtp.mailfrom=attacker.example\r\n\
Received: from mail.attacker.example (mail.attacker.example [198.51.100.7]) by mx6.messagingengine.com (Postfix) with ESMTPS\r\n\
FORGED\
From: <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";
        let honest = raw.replace("FORGED", "");
        assert!(!check(&honest, "imap.fastmail.com"));
        assert!(!checks(&honest, "imap.fastmail.com").dmarc_failed);
        // Another of Fastmail's MX names, which never saw the message.
        let other_mx = raw.replace(
            "FORGED",
            "Authentication-Results: mx1.messagingengine.com; dmarc=pass header.from=bank.example\r\n",
        );
        assert!(!check(&other_mx, "imap.fastmail.com"));
        assert!(checks(&other_mx, "imap.fastmail.com").dmarc_failed);
    }

    /// iCloud's headers, then the hop where the message came in.
    const ICLOUD: &str = "Received: from p00-icloudmta-asmtp-us-west-2a by p00-icloudmta-asmtp-us-west-2a (Oracle) with ESMTP\r\n\
Authentication-Results: dmarc.icloud.com; dmarc=none header.from=bank.example\r\n\
Received: from mail.attacker.example (mail.attacker.example [198.51.100.7]) by mx01.mail.icloud.com (Postfix) with ESMTPS\r\n\
FORGED\
From: <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";

    #[test]
    fn icloud_names_below_the_entry_are_forged() {
        let honest = ICLOUD.replace("FORGED", "");
        assert!(!check(&honest, "imap.mail.me.com"));
        // A name iCloud does sign with, but it didn't write this one.
        let forged = ICLOUD.replace(
            "FORGED",
            "Authentication-Results: dkim-verifier.icloud.com; dkim=pass header.d=bank.example\r\n",
        );
        assert!(!check(&forged, "imap.mail.me.com"));
        assert!(checks(&forged, "imap.mail.me.com").dmarc_failed);
    }

    #[test]
    fn a_sender_naming_itself_after_the_provider_is_still_outside() {
        // The sender says HELO mx.studio.it from a public address: the
        // hop is still where the message came in.
        let raw = "Received: from mx.studio.it (mx.studio.it [198.51.100.7]) by mx.studio.it with ESMTP\r\n\
Authentication-Results: mx.studio.it; dmarc=pass header.from=bank.example\r\n\
From: <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(!check(raw, "imap.studio.it"));
        // A bare public address in place of a name, the same.
        let bare = raw.replace(
            "from mx.studio.it (mx.studio.it [198.51.100.7])",
            "from [198.51.100.7] (unknown)",
        );
        assert!(!check(&bare, "imap.studio.it"));
        // A hop between the server's own machines, on a private address,
        // is not.
        let inside =
            "Received: from mx.studio.it (mx.studio.it [10.0.0.5]) by mbox.studio.it with LMTP\r\n\
Authentication-Results: mx.studio.it; dmarc=pass header.from=bank.example\r\n\
Received: from mail.bank.example (mail.bank.example [192.0.2.1]) by mx.studio.it with ESMTPS\r\n\
From: <help@bank.example>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(check(inside, "imap.studio.it"));
    }

    /// Microsoft 365: internal hops, the results with no name, then the
    /// hop of the protection server that took the message.
    const OUTLOOK: &str = "Received: from DB8PR03MB5867.eurprd03.prod.outlook.com (2603:10a6:10:e5::23) by AM6PR03MB4598.eurprd03.prod.outlook.com with HTTPS; Mon, 19 Oct 2026 08:00:02 +0000\r\n\
Received: from DB5EUR03FT012.eop-EUR03.prod.protection.outlook.com (2603:10a6:20b:1::4) by DB8PR03MB5867.outlook.office365.com (2603:10a6:10:e5::23) with Microsoft SMTP Server; Mon, 19 Oct 2026 08:00:01 +0000\r\n\
Authentication-Results: spf=pass (sender IP is 192.0.2.10)\r\n smtp.mailfrom=shop.example; dkim=pass (signature was verified)\r\n header.d=shop.example;dmarc=pass action=none\r\n header.from=shop.example;compauth=pass reason=100\r\n\
Received-SPF: Pass (protection.outlook.com: domain of shop.example designates 192.0.2.10 as permitted sender)\r\n\
Received: from mail.shop.example (192.0.2.10) by DB5EUR03FT012.mail.protection.outlook.com (10.152.20.123) with Microsoft SMTP Server; Mon, 19 Oct 2026 08:00:00 +0000\r\n\
FORGED\
From: Shop <news@shop.example>\r\nSubject: x\r\n\r\nHi\r\n";

    #[test]
    fn microsoft_results_have_no_name() {
        let honest = OUTLOOK.replace("FORGED", "");
        assert!(check(&honest, "outlook.office365.com"));
        assert!(checks(&honest, "outlook.office365.com").dmarc_pass);
        // A second nameless header, from the sender.
        let forged = OUTLOOK.replace(
            "FORGED",
            "Authentication-Results: dmarc=pass action=none header.from=bank.example\r\n",
        );
        assert!(checks(&forged, "outlook.office365.com").dmarc_failed);
        assert!(!check(
            &forged.replace("@shop.example", "@bank.example"),
            "outlook.office365.com"
        ));
    }

    #[test]
    fn yahoo_names_its_results_after_the_server() {
        let raw = "Received: from 10.217.150.11 by atlas210.free.mail.bf1.yahoo.com with HTTP; Mon, 19 Oct 2026 08:00:01 +0000\r\n\
Received-SPF: pass (domain of shop.example designates 192.0.2.10 as permitted sender)\r\n\
Authentication-Results: atlas210.free.mail.bf1.yahoo.com;\r\n dkim=pass header.i=@shop.example header.s=s1;\r\n spf=pass smtp.mailfrom=shop.example;\r\n dmarc=pass(p=REJECT) header.from=shop.example;\r\n\
Received: from 10.217.150.11 (EHLO mail.shop.example) (192.0.2.10) by mta4049.mail.bf1.yahoo.com with SMTPS; Mon, 19 Oct 2026 08:00:00 +0000\r\n\
FORGED\
From: Shop <news@shop.example>\r\nSubject: x\r\n\r\nHi\r\n";
        assert!(check(&raw.replace("FORGED", ""), "imap.mail.yahoo.com"));
        let forged = raw.replace(
            "FORGED",
            "Authentication-Results: atlas1.mail.yahoo.com; dmarc=pass header.from=bank.example\r\n",
        );
        assert!(checks(&forged, "imap.mail.yahoo.com").dmarc_failed);
        assert!(!check(
            &forged.replace("@shop.example", "@bank.example"),
            "imap.mail.yahoo.com"
        ));
    }

    #[test]
    fn the_signature_named_by_its_first_characters_as_written() {
        let raw = |b: &str, sigs: &str| {
            format!(
                "Received: from mail.shop.example (mail.shop.example [192.0.2.10]) by mx.google.com; Mon, 19 Oct 2026 08:00:00 +0000\r\n\
Authentication-Results: mx.google.com; dkim=pass header.i=@shop.example header.s=s1{b}; dmarc=pass header.from=shop.example\r\n\
{sigs}\
From: <news@shop.example>\r\nList-Unsubscribe: <https://shop.example/u>\r\nList-Unsubscribe-Post: List-Unsubscribe=One-Click\r\nSubject: x\r\n\r\nHi\r\n"
            )
        };
        let sig = |b: &str, h: &str| {
            format!(
                "DKIM-Signature: v=1; a=rsa-sha256; d=shop.example; s=s1; h={h}; bh=x; b={b}\r\n"
            )
        };
        let covered = "From:List-Unsubscribe:List-Unsubscribe-Post";
        let one = sig("AbCdEf12345", covered);
        assert!(checks(&raw(" header.b=AbCdEf12", &one), "imap.gmail.com").list_signed);
        // The same letters in another case are another signature.
        assert!(!checks(&raw(" header.b=abcdef12", &one), "imap.gmail.com").list_signed);
        // Without header.b, one signature of the domain is the one.
        assert!(checks(&raw("", &one), "imap.gmail.com").list_signed);
        // Two: the one that passed might not be the one over the list
        // headers.
        let two = format!("{}{}", sig("Genuine123", "From:Subject"), one);
        assert!(!checks(&raw("", &two), "imap.gmail.com").list_signed);
    }

    #[test]
    fn organizations() {
        assert_eq!(organization("mail.example.co.uk"), "example.co.uk");
        assert_eq!(organization("imap.studio.it"), "studio.it");
        assert!(aligned("news.bottegalume.it", "bottegalume.it"));
        assert!(!aligned("bottegalume.it", "lume.it"));
    }
}
