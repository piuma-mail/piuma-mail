//! Finding a mailbox's server settings from the email address alone.
//!
//! Tried in order, stopping at the first answer:
//! 1. Providers the engine already knows (no network).
//! 2. The domain's own autoconfig file (Thunderbird format), asked of the
//!    domain itself: `autoconfig.<domain>` and `<domain>/.well-known`.
//! 3. The domain's mail servers (its MX records): a custom domain hosted
//!    by a provider the engine knows (Aruba, Google, Fastmail…) gets that
//!    provider's settings.
//! 4. The usual host names (`imap.<domain>`, `mail.<domain>`…), kept only
//!    when a connection to them actually opens.
//!
//! Nothing here asks a third party: the address never leaves the device
//! except towards the person's own mail domain, and the MX lookup goes to
//! the system's own DNS resolver.

use std::time::Duration;

use tokio::net::TcpStream;

use crate::model::{Security, Server};

/// Where the settings came from, so the interface can say how sure it is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    /// A provider the engine knows.
    Known,
    /// The domain published them.
    Published,
    /// Usual host names that answered.
    Guessed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings {
    pub imap: Server,
    pub smtp: Server,
    /// The login, usually the whole address.
    pub username: String,
    pub source: Source,
}

/// Finds the settings for an address, or None when only a manual setup
/// will do.
pub async fn discover(email: &str) -> Option<Settings> {
    let (_, domain) = split(email)?;
    if let Some(s) = known(email) {
        return Some(s);
    }
    let first = reqwest::Url::parse_with_params(
        &format!("https://autoconfig.{domain}/mail/config-v1.1.xml"),
        [("emailaddress", email.trim())],
    )
    .ok()?;
    let urls = [
        first.to_string(),
        format!("https://{domain}/.well-known/autoconfig/mail/config-v1.1.xml"),
    ];
    for url in &urls {
        if let Some(s) = from_url(url, email).await {
            return Some(s);
        }
    }
    // Some hosts serve autoconfig only over plain HTTP: Aruba points
    // autoconfig.<domain> at a server whose certificate is for aruba.it.
    // Anyone on the network could rewrite that answer, so it is kept only
    // when it names the domain's own servers or a provider the engine knows.
    if let Some(s) = from_url(&first.to_string().replacen("https://", "http://", 1), email).await {
        if trusted_over_http(&s, &domain) {
            return Some(s);
        }
    }
    if let Some((imap, smtp)) = mx_hosts(&domain).await.iter().find_map(|h| by_mx(h)) {
        return Some(Settings {
            imap,
            smtp,
            username: email.trim().to_owned(),
            source: Source::Known,
        });
    }
    guess(email).await
}

fn split(email: &str) -> Option<(&str, String)> {
    let (local, domain) = email.trim().rsplit_once('@')?;
    let domain = domain.trim().to_ascii_lowercase();
    (!local.is_empty() && domain.contains('.')).then_some((local, domain))
}

fn server(host: &str, port: u16, security: Security) -> Server {
    Server {
        host: host.to_owned(),
        port,
        security,
    }
}

/// Providers whose settings never change.
pub fn known(email: &str) -> Option<Settings> {
    let (_, domain) = split(email)?;
    let (imap, smtp) = preset(&domain)?;
    Some(Settings {
        imap,
        smtp,
        username: email.trim().to_owned(),
        source: Source::Known,
    })
}

/// The IMAP and SMTP servers of a provider's own domain.
fn preset(domain: &str) -> Option<(Server, Server)> {
    use Security::{StartTls, Tls};
    Some(match domain {
        "gmail.com" | "googlemail.com" => (
            server("imap.gmail.com", 993, Tls),
            server("smtp.gmail.com", 465, Tls),
        ),
        "outlook.com" | "hotmail.com" | "hotmail.it" | "live.com" | "live.it" | "msn.com" => (
            server("outlook.office365.com", 993, Tls),
            server("smtp-mail.outlook.com", 587, StartTls),
        ),
        "icloud.com" | "me.com" | "mac.com" => (
            server("imap.mail.me.com", 993, Tls),
            server("smtp.mail.me.com", 587, StartTls),
        ),
        "yahoo.com" | "yahoo.it" | "ymail.com" => (
            server("imap.mail.yahoo.com", 993, Tls),
            server("smtp.mail.yahoo.com", 465, Tls),
        ),
        "aol.com" => (
            server("imap.aol.com", 993, Tls),
            server("smtp.aol.com", 465, Tls),
        ),
        "fastmail.com" | "fastmail.fm" => (
            server("imap.fastmail.com", 993, Tls),
            server("smtp.fastmail.com", 465, Tls),
        ),
        "gmx.com" | "gmx.net" | "gmx.de" | "gmx.it" => (
            server("imap.gmx.net", 993, Tls),
            server("mail.gmx.net", 465, Tls),
        ),
        "zoho.com" | "zohomail.com" => (
            server("imap.zoho.com", 993, Tls),
            server("smtp.zoho.com", 465, Tls),
        ),
        "libero.it" | "inwind.it" | "iol.it" | "blu.it" => (
            server("imapmail.libero.it", 993, Tls),
            server("smtp.libero.it", 465, Tls),
        ),
        "virgilio.it" => (
            server("in.virgilio.it", 993, Tls),
            server("out.virgilio.it", 465, Tls),
        ),
        "tim.it" => (
            server("imap.tim.it", 993, Tls),
            server("smtp.tim.it", 465, Tls),
        ),
        "alice.it" | "tin.it" => (
            server("in.alice.it", 993, Tls),
            server("out.alice.it", 465, Tls),
        ),
        "fastwebnet.it" => (
            server("imap.fastwebnet.it", 993, Tls),
            server("smtp.fastwebnet.it", 465, Tls),
        ),
        "aruba.it" => (
            server("imaps.aruba.it", 993, Tls),
            server("smtps.aruba.it", 465, Tls),
        ),
        // Certified mail (PEC): Aruba, InfoCert Legalmail, Poste Italiane
        // and Namirial.
        "pec.it" => (
            server("imaps.pec.aruba.it", 993, Tls),
            server("smtps.pec.aruba.it", 465, Tls),
        ),
        "legalmail.it" => (
            server("mbox.cert.legalmail.it", 993, Tls),
            server("sendm.cert.legalmail.it", 465, Tls),
        ),
        "postecert.it" => (
            server("mail.postecert.it", 993, Tls),
            server("mail.postecert.it", 465, Tls),
        ),
        "sicurezzapostale.it" => (
            server("imaps.sicurezzapostale.it", 993, Tls),
            server("smtps.sicurezzapostale.it", 465, Tls),
        ),
        _ => return None,
    })
}

/// A custom domain whose mail a known provider receives, by the host name
/// of one of its MX records.
pub fn by_mx(host: &str) -> Option<(Server, Server)> {
    let host = host.trim_end_matches('.').to_ascii_lowercase();
    let under = |suffix: &str| host == suffix || host.ends_with(&format!(".{suffix}"));
    let provider = if under("pec.aruba.it") {
        "pec.it"
    } else if under("cert.legalmail.it") {
        "legalmail.it"
    } else if under("aruba.it") {
        "aruba.it"
    } else if under("google.com") || under("googlemail.com") {
        "gmail.com"
    } else if under("messagingengine.com") {
        "fastmail.com"
    } else if under("icloud.com") {
        "icloud.com"
    } else if under("zoho.com") {
        "zoho.com"
    } else {
        return None;
    };
    preset(provider)
}

/// Whether settings that came over plain HTTP only name servers of the
/// address's own domain or of a provider the engine knows.
fn trusted_over_http(s: &Settings, domain: &str) -> bool {
    let ok = |host: &str| {
        let host = host.trim_end_matches('.').to_ascii_lowercase();
        host == domain || host.ends_with(&format!(".{domain}")) || by_mx(&host).is_some()
    };
    ok(&s.imap.host) && ok(&s.smtp.host)
}

/// The domain's MX hosts, most preferred first; empty when DNS can't say.
async fn mx_hosts(domain: &str) -> Vec<String> {
    let Ok(builder) = hickory_resolver::Resolver::builder_tokio() else {
        return Vec::new();
    };
    let Ok(resolver) = builder.build() else {
        return Vec::new();
    };
    let lookup = resolver.mx_lookup(format!("{domain}."));
    let Ok(Ok(found)) = tokio::time::timeout(Duration::from_secs(4), lookup).await else {
        return Vec::new();
    };
    let mut mx: Vec<_> = found
        .answers()
        .iter()
        .filter_map(|r| match &r.data {
            hickory_resolver::proto::rr::RData::MX(mx) => {
                Some((mx.preference, mx.exchange.to_ascii()))
            }
            _ => None,
        })
        .collect();
    mx.sort();
    mx.into_iter().map(|(_, host)| host).collect()
}

/// Reads a Thunderbird autoconfig file from `url`.
pub async fn from_url(url: &str, email: &str) -> Option<Settings> {
    let client = crate::tls::http_client()
        .timeout(Duration::from_secs(6))
        .user_agent(concat!("PiumaMail/", env!("CARGO_PKG_VERSION")))
        .build()
        .ok()?;
    let response = client.get(url).send().await.ok()?;
    if !response.status().is_success() {
        return None;
    }
    let xml = response.text().await.ok()?;
    parse(&xml, email, Source::Published)
}

/// Parses a Thunderbird autoconfig document (config-v1.1). Picks the most
/// secure IMAP and SMTP entries; plain-text servers are ignored.
pub fn parse(xml: &str, email: &str, source: Source) -> Option<Settings> {
    let doc = roxmltree::Document::parse(xml).ok()?;
    let provider = doc
        .descendants()
        .find(|n| n.has_tag_name("emailProvider"))?;
    let pick = |tag: &str, kind: &str| {
        provider
            .children()
            .filter(|n| n.has_tag_name(tag) && n.attribute("type") == Some(kind))
            .filter_map(|n| entry(n, email))
            .min_by_key(|(s, _)| match s.security {
                Security::Tls => 0,
                Security::StartTls => 1,
                Security::None => 2,
            })
    };
    let (imap, imap_user) = pick("incomingServer", "imap")?;
    let (smtp, _) = pick("outgoingServer", "smtp")?;
    Some(Settings {
        imap,
        smtp,
        username: imap_user,
        source,
    })
}

fn entry(node: roxmltree::Node, email: &str) -> Option<(Server, String)> {
    let text = |tag: &str| {
        node.children()
            .find(|c| c.has_tag_name(tag))
            .and_then(|c| c.text())
            .map(str::trim)
    };
    let security = match text("socketType")? {
        "SSL" => Security::Tls,
        "STARTTLS" => Security::StartTls,
        _ => return None,
    };
    let (local, domain) = split(email)?;
    let fill = |s: &str| {
        s.replace("%EMAILADDRESS%", email.trim())
            .replace("%EMAILLOCALPART%", local)
            .replace("%EMAILDOMAIN%", &domain)
    };
    let host = fill(text("hostname")?);
    let port = text("port")?.parse().ok()?;
    let username = fill(text("username").unwrap_or("%EMAILADDRESS%"));
    Some((server(&host, port, security), username))
}

/// Tries the usual host names and keeps the first that answers.
async fn guess(email: &str) -> Option<Settings> {
    let (_, domain) = split(email)?;
    let imap = first_open(&[
        (format!("imap.{domain}"), 993, Security::Tls),
        (format!("mail.{domain}"), 993, Security::Tls),
    ])
    .await?;
    let smtp = first_open(&[
        (format!("smtp.{domain}"), 465, Security::Tls),
        (format!("smtp.{domain}"), 587, Security::StartTls),
        (format!("mail.{domain}"), 465, Security::Tls),
        (format!("mail.{domain}"), 587, Security::StartTls),
    ])
    .await?;
    Some(Settings {
        imap,
        smtp,
        username: email.trim().to_owned(),
        source: Source::Guessed,
    })
}

async fn first_open(candidates: &[(String, u16, Security)]) -> Option<Server> {
    for (host, port, security) in candidates {
        let attempt = TcpStream::connect((host.as_str(), *port));
        if let Ok(Ok(_)) = tokio::time::timeout(Duration::from_secs(4), attempt).await {
            return Some(server(host, *port, *security));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const XML: &str = r#"<?xml version="1.0"?>
<clientConfig version="1.1">
  <emailProvider id="studio.it">
    <domain>studio.it</domain>
    <incomingServer type="pop3">
      <hostname>pop.studio.it</hostname><port>995</port>
      <socketType>SSL</socketType><username>%EMAILADDRESS%</username>
    </incomingServer>
    <incomingServer type="imap">
      <hostname>imap.studio.it</hostname><port>143</port>
      <socketType>STARTTLS</socketType><username>%EMAILLOCALPART%</username>
    </incomingServer>
    <incomingServer type="imap">
      <hostname>imap.studio.it</hostname><port>993</port>
      <socketType>SSL</socketType><username>%EMAILLOCALPART%</username>
    </incomingServer>
    <outgoingServer type="smtp">
      <hostname>smtp.studio.it</hostname><port>25</port>
      <socketType>plain</socketType>
    </outgoingServer>
    <outgoingServer type="smtp">
      <hostname>smtp.%EMAILDOMAIN%</hostname><port>587</port>
      <socketType>STARTTLS</socketType><username>%EMAILADDRESS%</username>
    </outgoingServer>
  </emailProvider>
</clientConfig>"#;

    #[test]
    fn parses_the_most_secure_servers() {
        let s = parse(XML, "matteo@studio.it", Source::Published).unwrap();
        assert_eq!(s.imap, server("imap.studio.it", 993, Security::Tls));
        assert_eq!(s.smtp, server("smtp.studio.it", 587, Security::StartTls));
        assert_eq!(s.username, "matteo");
    }

    #[test]
    fn plain_text_only_is_not_enough() {
        let xml = XML.replace(
            "<socketType>STARTTLS</socketType><username>%EMAILADDRESS%",
            "<socketType>plain</socketType><username>%EMAILADDRESS%",
        );
        assert_eq!(parse(&xml, "matteo@studio.it", Source::Published), None);
        assert_eq!(
            parse("not xml", "matteo@studio.it", Source::Published),
            None
        );
    }

    #[test]
    fn knows_common_providers() {
        let s = known("Someone@GMAIL.com ").unwrap();
        assert_eq!(s.imap.host, "imap.gmail.com");
        assert_eq!(s.username, "Someone@GMAIL.com");
        assert_eq!(
            known("matteo@libero.it").unwrap().smtp.host,
            "smtp.libero.it"
        );
        assert_eq!(
            known("matteo@aruba.it").unwrap().imap.host,
            "imaps.aruba.it"
        );
        assert_eq!(
            known("matteo@pec.it").unwrap().smtp,
            server("smtps.pec.aruba.it", 465, Security::Tls)
        );
        assert_eq!(
            known("studio@legalmail.it").unwrap().imap.host,
            "mbox.cert.legalmail.it"
        );
        assert_eq!(known("matteo@studio.it"), None);
        assert_eq!(known("not an address"), None);
    }

    #[test]
    fn plain_http_settings_must_name_known_servers() {
        let aruba = parse(
            &XML.replace("imap.studio.it", "imaps.aruba.it")
                .replace("smtp.%EMAILDOMAIN%", "smtps.aruba.it"),
            "info@bottegalume.example",
            Source::Published,
        )
        .unwrap();
        assert!(trusted_over_http(&aruba, "bottegalume.example"));
        let own = parse(XML, "matteo@studio.it", Source::Published).unwrap();
        assert!(trusted_over_http(&own, "studio.it"));
        let elsewhere = parse(
            &XML.replace("imap.studio.it", "imap.attacker.example"),
            "matteo@studio.it",
            Source::Published,
        )
        .unwrap();
        assert!(!trusted_over_http(&elsewhere, "studio.it"));
    }

    #[test]
    fn custom_domains_of_known_providers() {
        // An Aruba-hosted domain, e.g. bottegalume.example.
        let (imap, smtp) = by_mx("mx.aruba.it.").unwrap();
        assert_eq!(imap, server("imaps.aruba.it", 993, Security::Tls));
        assert_eq!(smtp, server("smtps.aruba.it", 465, Security::Tls));
        assert_eq!(
            by_mx("ASPMX.L.GOOGLE.COM").unwrap().0.host,
            "imap.gmail.com"
        );
        assert_eq!(
            by_mx("in1-smtp.messagingengine.com").unwrap().0.host,
            "imap.fastmail.com"
        );
        // A custom PEC domain at Aruba gets the PEC servers.
        assert_eq!(
            by_mx("mx.pec.aruba.it").unwrap().0.host,
            "imaps.pec.aruba.it"
        );
        assert_eq!(by_mx("mx.notaruba.it"), None);
        assert_eq!(by_mx("mail.studio.it"), None);
    }
}
