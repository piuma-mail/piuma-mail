//! Whether an email's sender isn't who they say (`ProtectionToApprove`
//! section 2): an address that imitates a domain the person already gets
//! mail from, or a name that claims a known company while the address
//! belongs elsewhere. A failed DMARC check, the third case, comes from
//! [`crate::sender_auth::checked`].
//!
//! Everything is worked out on the device from mail already kept: nothing
//! is looked up.

use crate::sender_auth::{organization, under};

/// Companies whose names are worth borrowing, with the domains they send
/// from. A name that claims one of them from any other domain is flagged,
/// and these domains count as known even before any mail from them.
pub const BRANDS: &[(&str, &[&str])] = &[
    (
        "PayPal",
        &[
            "paypal.com",
            "paypal.it",
            "paypal.de",
            "paypal.fr",
            "paypal.es",
            "paypal.me",
        ],
    ),
    (
        "Amazon",
        &[
            "amazon.com",
            "amazon.it",
            "amazon.de",
            "amazon.fr",
            "amazon.es",
            "amazon.co.uk",
            "amazon.com.br",
            "amazonses.com",
        ],
    ),
    ("Apple", &["apple.com", "icloud.com", "me.com"]),
    (
        "Microsoft",
        &[
            "microsoft.com",
            "outlook.com",
            "live.com",
            "office.com",
            "office365.com",
            "microsoftonline.com",
            "hotmail.com",
            "xbox.com",
        ],
    ),
    ("Google", &["google.com", "gmail.com", "youtube.com"]),
    ("Netflix", &["netflix.com"]),
    (
        "Facebook",
        &["facebook.com", "facebookmail.com", "meta.com"],
    ),
    ("Instagram", &["instagram.com", "facebookmail.com"]),
    ("WhatsApp", &["whatsapp.com"]),
    ("Spotify", &["spotify.com"]),
    (
        "eBay",
        &[
            "ebay.com",
            "ebay.it",
            "ebay.de",
            "ebay.fr",
            "ebay.es",
            "ebay.co.uk",
        ],
    ),
    ("DHL", &["dhl.com", "dhl.it", "dhl.de", "dhl.fr", "dhl.es"]),
    ("Poste Italiane", &["poste.it", "posteitaliane.it"]),
    (
        "Intesa Sanpaolo",
        &["intesasanpaolo.com", "intesasanpaolo.it"],
    ),
    ("UniCredit", &["unicredit.it", "unicredit.eu"]),
    (
        "Agenzia delle Entrate",
        &["agenziaentrate.it", "agenziaentrate.gov.it"],
    ),
    ("INPS", &["inps.it"]),
    ("Revolut", &["revolut.com"]),
    ("Booking.com", &["booking.com"]),
    ("Airbnb", &["airbnb.com", "airbnb.it"]),
    ("Nexi", &["nexi.it"]),
    ("Satispay", &["satispay.com"]),
    ("Aruba", &["aruba.it", "arubapec.it", "pec.it"]),
    ("Vodafone", &["vodafone.it", "vodafone.com"]),
    ("Enel", &["enel.it", "enel.com"]),
];

/// Domains anyone can have an address at: writing to one person there
/// vouches for nobody else.
const SHARED: &[&str] = &[
    "gmail.com",
    "googlemail.com",
    "outlook.com",
    "outlook.it",
    "hotmail.com",
    "hotmail.it",
    "live.com",
    "live.it",
    "msn.com",
    "yahoo.com",
    "yahoo.it",
    "icloud.com",
    "me.com",
    "mac.com",
    "aol.com",
    "libero.it",
    "virgilio.it",
    "tiscali.it",
    "alice.it",
    "tim.it",
    "tin.it",
    "fastwebnet.it",
    "email.it",
    "inwind.it",
    "iol.it",
    "gmx.com",
    "gmx.de",
    "gmx.net",
    "web.de",
    "mail.com",
    "proton.me",
    "protonmail.com",
    "pm.me",
    "tutanota.com",
    "tuta.io",
    "posteo.de",
    "fastmail.com",
    "zoho.com",
    "yandex.com",
    "hey.com",
    "pec.it",
    "legalmail.it",
];

/// Role words used as a sender's display name when the company name is
/// placed in the message banner or subject instead ("Servizio Clienti").
const GENERIC_ROLES: &[&str] = &[
    "servizio",
    "servizi",
    "clienti",
    "cliente",
    "assistenza",
    "supporto",
    "tecnico",
    "ufficio",
    "amministrazione",
    "fatturazione",
    "pagamenti",
    "sicurezza",
    "avviso",
    "avvisi",
    "notifica",
    "notifiche",
    "comunicazioni",
    "info",
    "informazioni",
    "rinnovo",
    "domini",
    "dominio",
    "account",
    "team",
    "staff",
    "reparto",
    "gestione",
    "customer",
    "customers",
    "service",
    "services",
    "support",
    "care",
    "help",
    "helpdesk",
    "desk",
    "security",
    "billing",
    "admin",
    "administration",
    "notification",
    "notifications",
    "alert",
    "alerts",
    "noreply",
    "no",
    "reply",
    "mail",
    "email",
    "webmail",
];

/// Whether an organization's domain is one anyone can have an address at.
pub fn shared(org: &str) -> bool {
    SHARED.contains(&org)
}

/// The company a sender's name claims, when the address isn't one of its
/// domains: "PayPal" for "PayPal Service <help@fastpay-secure.example>".
pub fn claimed_brand(name: &str, domain: &str) -> Option<&'static str> {
    let words = name_words(name);
    if words.is_empty() {
        return None;
    }
    BRANDS.iter().find_map(|(brand, domains)| {
        let claimed = name_words(brand);
        let says = words
            .windows(claimed.len())
            .any(|w| w == claimed.as_slice());
        (says && !domains.iter().any(|d| under(domain, d))).then_some(*brand)
    })
}

/// The company a message claims when the sender's display name either
/// names the brand directly or uses a generic role ("Servizio Clienti")
/// while the subject or opening banner names a known brand.
pub fn claimed_brand_in_message(
    name: &str,
    subject: &str,
    text: &str,
    domain: &str,
) -> Option<&'static str> {
    if let Some(brand) = claimed_brand(name, domain) {
        return Some(brand);
    }
    if is_brand_domain(domain) {
        return None;
    }
    let opening: String = text.chars().take(600).collect();
    if generic_role_name(name) {
        if let Some(brand) =
            claimed_brand(subject, domain).or_else(|| claimed_brand(&opening, domain))
        {
            return Some(brand);
        }
    }
    let first_line = text
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or_default();
    let lower_first = first_line.to_ascii_lowercase();
    BRANDS.iter().find_map(|(brand, domains)| {
        let has_domain = domains.iter().any(|d| {
            lower_first == *d
                || lower_first.starts_with(&format!("{d} "))
                || lower_first.starts_with(&format!("{d}\t"))
                || lower_first.starts_with(&format!("{d}|"))
        });
        (has_domain && !domains.iter().any(|d| under(domain, d))).then_some(*brand)
    })
}

fn generic_role_name(name: &str) -> bool {
    let mut any = false;
    for word in name
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
    {
        any = true;
        let lower = word.to_lowercase();
        if !GENERIC_ROLES.contains(&lower.as_str()) {
            return false;
        }
    }
    any
}

/// A name's words, as they look: "P4yPal" and "PayPal" are the same.
fn name_words(name: &str) -> Vec<String> {
    name.split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(skeleton)
        .collect()
}

/// The known domain a sender's domain imitates, and how many emails came
/// from that one: "paypal.com" for "paypa1.com", "microsoft.com" for
/// "rnicrosoft.com", "apple.com" for an "аpple.com" with a Cyrillic a.
/// `known` holds the organizations' domains the person gets mail from.
pub fn looks_like(domain: &str, known: &[(String, u32)]) -> Option<(String, u32)> {
    let own = organization(&unicode(domain));
    if own.is_empty() || known.iter().any(|(k, _)| *k == own) || is_brand_domain(&own) {
        return None;
    }
    let (own_name, own_end) = split(&own);
    let own_shape = skeleton(own_name);
    let brands = BRANDS
        .iter()
        .flat_map(|(_, ds)| ds.iter())
        .filter(|d| !known.iter().any(|(k, _)| k == *d))
        .map(|d| ((*d).to_owned(), 0));
    known
        .iter()
        .cloned()
        .chain(brands)
        .filter(|(k, _)| *k != own)
        .find(|(k, count)| {
            let (name, end) = split(k);
            if name.is_empty() {
                return false;
            }
            let shape = skeleton(name);
            // The same letters as they look, under any ending: "paypal.it"
            // next to "paypal.com" is no imitation, "paypa1.it" is.
            if shape == own_shape && own_name != name {
                return true;
            }
            // One letter off, for names long enough not to collide by
            // chance, against domains that are clearly someone's.
            let long = match is_brand_domain(k) {
                true => 5,
                false if *count >= 3 => 8,
                false => return false,
            };
            end == own_end && name.chars().count() >= long && one_edit(&shape, &own_shape)
        })
}

fn is_brand_domain(domain: &str) -> bool {
    BRANDS
        .iter()
        .any(|(_, ds)| ds.iter().any(|d| under(domain, d)))
}

/// "paypal.co.uk" as ("paypal", "co.uk").
fn split(domain: &str) -> (&str, &str) {
    domain.split_once('.').unwrap_or((domain, ""))
}

/// A domain in its own letters: "xn--pple-43d.com" is "аpple.com".
fn unicode(domain: &str) -> String {
    url::quirks::domain_to_unicode(&domain.to_lowercase())
        .trim_end_matches('.')
        .to_owned()
}

/// What a word looks like, folding letters that pass for others: digits
/// for letters, "rn" for "m", letters from other alphabets that look
/// Latin, and the dashes in between.
pub fn skeleton(word: &str) -> String {
    let mut out = String::with_capacity(word.len());
    for c in word.to_lowercase().chars() {
        let c = match c {
            '0' | 'о' | 'ο' | 'օ' => 'o',
            '1' | 'i' | '|' | 'і' | 'ӏ' | 'ι' | 'l' | 'ı' => 'l',
            '3' | 'е' | 'ё' | 'ε' => 'e',
            '4' | 'а' | 'α' => 'a',
            '5' | 'ѕ' => 's',
            '7' | 'τ' => 't',
            '8' => 'b',
            'р' | 'ρ' => 'p',
            'с' | 'ϲ' => 'c',
            'у' | 'γ' => 'y',
            'х' | 'χ' => 'x',
            'ј' => 'j',
            'ԁ' => 'd',
            'ɡ' => 'g',
            'ν' => 'v',
            'κ' | 'к' => 'k',
            'н' => 'h',
            'т' => 't',
            'м' => 'm',
            'в' => 'b',
            '-' | '_' => continue,
            c => c,
        };
        out.push(c);
    }
    out.replace("rn", "m").replace("vv", "w")
}

/// Whether two words are one letter apart: one changed, added, dropped,
/// or two side by side swapped.
fn one_edit(a: &str, b: &str) -> bool {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    if a == b {
        return false;
    }
    let (short, long) = if a.len() <= b.len() {
        (&a, &b)
    } else {
        (&b, &a)
    };
    match long.len() - short.len() {
        0 => {
            let diff: Vec<usize> = (0..a.len()).filter(|&i| a[i] != b[i]).collect();
            diff.len() == 1
                || (diff.len() == 2
                    && diff[1] == diff[0] + 1
                    && a[diff[0]] == b[diff[1]]
                    && a[diff[1]] == b[diff[0]])
        }
        1 => {
            let i = (0..short.len())
                .find(|&i| short[i] != long[i])
                .unwrap_or(short.len());
            short[i..] == long[i + 1..]
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn known() -> Vec<(String, u32)> {
        vec![
            ("studio.it".into(), 40),
            ("ferramentabianchi.it".into(), 6),
            ("bottegalume.example".into(), 1),
        ]
    }

    #[test]
    fn digits_and_letter_pairs_pass_for_letters() {
        assert_eq!(
            looks_like("paypa1.com", &known()),
            Some(("paypal.com".into(), 0))
        );
        assert_eq!(
            looks_like("rnicrosoft.com", &known()),
            Some(("microsoft.com".into(), 0))
        );
        assert_eq!(
            looks_like("5tudio.it", &known()),
            Some(("studio.it".into(), 40))
        );
    }

    #[test]
    fn letters_from_other_alphabets_are_caught() {
        // "аpple.com" with a Cyrillic а, as it arrives.
        assert_eq!(
            looks_like("xn--pple-43d.com", &known()),
            Some(("apple.com".into(), 0))
        );
        assert_eq!(
            looks_like("аpple.com", &known()),
            Some(("apple.com".into(), 0))
        );
    }

    #[test]
    fn one_letter_off_only_for_long_known_names() {
        assert_eq!(
            looks_like("ferramentabianci.it", &known()),
            Some(("ferramentabianchi.it".into(), 6))
        );
        assert_eq!(
            looks_like("paypall.com", &known()),
            Some(("paypal.com".into(), 0))
        );
        // Too few emails to be sure it's someone's.
        assert_eq!(looks_like("bottegalumi.example", &known()), None);
        // Short names collide by chance.
        assert_eq!(looks_like("studia.it", &known()), None);
    }

    #[test]
    fn real_domains_are_left_alone() {
        assert_eq!(looks_like("studio.it", &known()), None);
        assert_eq!(looks_like("mail.studio.it", &known()), None);
        assert_eq!(looks_like("paypal.com", &known()), None);
        assert_eq!(looks_like("e.paypal.it", &known()), None);
        assert_eq!(looks_like("trattoriavalentina.it", &known()), None);
        assert_eq!(looks_like("gmail.com", &known()), None);
    }

    #[test]
    fn names_that_borrow_a_company() {
        assert_eq!(
            claimed_brand("PayPal", "fastpay-secure.example"),
            Some("PayPal")
        );
        assert_eq!(
            claimed_brand("PayPaI Service", "paypa1.com"),
            Some("PayPal")
        );
        assert_eq!(
            claimed_brand("Poste Italiane", "poste-avvisi.example"),
            Some("Poste Italiane")
        );
        assert_eq!(claimed_brand("PayPal", "paypal.com"), None);
        assert_eq!(claimed_brand("PayPal", "e.paypal.it"), None);
        assert_eq!(claimed_brand("Amazon.it", "amazon.it"), None);
        assert_eq!(claimed_brand("Giulia Romano", "gmail.com"), None);
        // A word inside another word is not the company.
        assert_eq!(claimed_brand("Applebee's", "applebees.example"), None);
    }

    #[test]
    fn generic_role_with_brand_banner_is_caught() {
        assert_eq!(
            claimed_brand_in_message(
                "Servizio Clienti",
                "⚠️ Ultimo avviso! Il tuo dominio sta per essere sospeso",
                "aruba.it\nIl tuo dominio è stato sospeso\nGentile Cliente,\nTi informiamo che il rinnovo del tuo dominio non è andato a buon fine.",
                "rinnovo-hosting.example",
            ),
            Some("Aruba")
        );
        assert_eq!(
            claimed_brand_in_message(
                "Servizio Clienti",
                "Il tuo dominio sta per essere sospeso",
                "aruba.it\nIl tuo dominio è stato sospeso",
                "staff.aruba.it",
            ),
            None
        );
        assert_eq!(
            claimed_brand_in_message(
                "Bottega Lume",
                "Il tuo ordine #42",
                "Grazie per l'ordine. Pagamento ricevuto con PayPal.",
                "bottegalume.it",
            ),
            None
        );
    }

    #[test]
    fn one_edit_is_one_letter() {
        assert!(one_edit("paypal", "paypall"));
        assert!(one_edit("paypal", "papyal"));
        assert!(one_edit("paypal", "paypol"));
        assert!(!one_edit("paypal", "paypal"));
        assert!(!one_edit("paypal", "pypl"));
    }
}
