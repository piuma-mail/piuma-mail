//! Shared signals for local People/Notifications classification.
use mail_parser::Message;

/// Small, explicit headers: no full-header or body fetch is needed.
pub(crate) const HEADER_FIELDS: &str =
    "X-AUTO-RESPONSE-SUPPRESS X-MAILER X-WP-NOTIFICATION X-WP-EMAIL";
pub(crate) const HEADERS: [&str; 4] = [
    "X-Auto-Response-Suppress",
    "X-Mailer",
    "X-WP-Notification",
    "X-WP-Email",
];

/// Automation markers, excluding list headers (discussion lists have exceptions).
pub(crate) fn headers(m: &Message) -> bool {
    m.header_raw("X-Auto-Response-Suppress")
        .is_some_and(|v| !v.trim().is_empty() && !v.trim().eq_ignore_ascii_case("none"))
        || m.header_raw("X-Mailer")
            .is_some_and(|v| v.to_ascii_lowercase().contains("wordpress"))
        || m.headers()
            .iter()
            .any(|h| h.name.as_str().to_ascii_lowercase().starts_with("x-wp-"))
}

/// Conservative content fallbacks; merely mentioning WordPress or spam is not enough.
pub(crate) fn content(name: &str, subject: &str, attached_message: bool) -> bool {
    let name = name.trim().to_ascii_lowercase();
    let subject = subject.trim_start().to_ascii_lowercase();
    ["*****spam*****", "[spam]", "***spam***"]
        .iter()
        .any(|p| subject.starts_with(p))
        || (attached_message && subject.contains("spam") && subject.contains("report"))
        || ((name == "wordpress" || name == "notifications from wp")
            && (subject.contains("needs confirmation of the admin email")
                || subject.contains("plugins were updated automatically")))
}

pub(crate) fn message(m: &Message) -> bool {
    let name = m
        .from()
        .and_then(|a| a.first())
        .and_then(|a| a.name())
        .unwrap_or_default();
    content(
        name,
        m.subject().unwrap_or_default(),
        m.attachments()
            .any(|p| matches!(p.body, mail_parser::PartType::Message(_))),
    )
}

/// Whether an address looks like a machine's (no-reply, notifications,
/// orders, bounces…, or sent from a mailing domain such as
/// `notice.shop.com` or `e-mail.brand.com`), for local classification.
pub(crate) fn machine_address(email: &str) -> bool {
    let email = email.trim().to_lowercase();
    let (local, domain) = email.split_once('@').unwrap_or((&email, ""));
    let labels: Vec<&str> = domain.split('.').collect();
    // A first label a mailing service sends from, on a domain of a brand:
    // email.brand.com, e-mail.brand.com, email2.brand.com, notice.brand.com.
    if labels.len() >= 3 {
        let first: String = labels[0].chars().filter(|c| *c != '-').collect();
        let first = first.trim_end_matches(|c: char| c.is_ascii_digit());
        if [
            "email",
            "emails",
            "em",
            "e",
            "mailer",
            "mailing",
            "mailings",
            "news",
            "newsletter",
            "newsletters",
            "notice",
            "notices",
            "notify",
            "notification",
            "notifications",
            "alerts",
            "updates",
            "marketing",
            "mkt",
            "comms",
            "communication",
            "communications",
            "crm",
            "info",
            "reply",
            "bounce",
            "bounces",
            "txn",
            "transactional",
            "promo",
            "offers",
            "deals",
        ]
        .contains(&first)
        {
            return true;
        }
    }
    let local: String = local
        .chars()
        .filter(|c| !matches!(c, '.' | '-' | '_'))
        .collect();
    ["noreply", "donotreply"].iter().any(|p| local.contains(p))
        || ["mailerdaemon", "postmaster", "bounce"]
            .iter()
            .any(|p| local.starts_with(p))
        || [
            "notifications",
            "notification",
            "notifiche",
            "notifica",
            "newsletter",
            "news",
            "alerts",
            "alert",
            "avvisi",
            "avviso",
            "comunicazioni",
            "mailer",
            "automated",
            "info",
            "wordpress",
            "transaction",
            "transactions",
            "order",
            "orders",
            "booking",
            "bookings",
            "billing",
            "invoice",
            "invoices",
            "receipts",
            "security",
            "account",
            "accounts",
            "updates",
            "notice",
            "marketing",
            "promo",
            "offers",
        ]
        .contains(&local.as_str())
}

/// Whether replies to an address go unread: a no-reply or bounce
/// address, not a shared role address such as `info@` or `billing@`,
/// which people do read. The reader warns before a quick reply.
pub fn no_reply_address(email: &str) -> bool {
    let email = email.trim().to_lowercase();
    let local: String = email
        .split_once('@')
        .map_or(email.as_str(), |(l, _)| l)
        .chars()
        .filter(|c| !matches!(c, '.' | '-' | '_'))
        .collect();
    ["noreply", "donotreply"].iter().any(|p| local.contains(p))
        || ["mailerdaemon", "bounce"]
            .iter()
            .any(|p| local.starts_with(p))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn automated_local_parts_and_normal_people() {
        for local in [
            "no-reply",
            "noreply",
            "do-not-reply",
            "donotreply",
            "mailer-daemon",
            "postmaster",
            "notifications",
            "notification",
            "wordpress",
            "alerts",
            "bounce",
        ] {
            assert!(machine_address(&format!("{local}@example.org")), "{local}");
        }
        assert!(!machine_address("giulia@example.org"));
    }

    #[test]
    fn no_reply_only_for_addresses_nobody_reads() {
        for a in [
            "no-reply@example.org",
            "noreply@shop.example",
            "do_not_reply@bank.example",
            "mailer-daemon@example.org",
            "bounces+123@mailer.example",
        ] {
            assert!(no_reply_address(a), "{a}");
        }
        for a in [
            "info@studio.example",
            "billing@studio.example",
            "notifications@github.example",
            "giulia@example.org",
        ] {
            assert!(!no_reply_address(a), "{a}");
        }
    }

    #[test]
    fn spam_report_requires_both_subject_and_attached_message() {
        use mail_parser::MessageParser;
        let raw = b"From: service@provider.example\r\nSubject: Spam report\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\nContent-Type: text/plain\r\n\r\nour automatic systems flagged the attached email as SPAM\r\n--x\r\nContent-Type: message/rfc822\r\nContent-Disposition: attachment; filename=original.eml\r\n\r\nFrom: sender@example.org\r\nSubject: Original\r\n\r\nBody\r\n--x--\r\n";
        let m = MessageParser::default().parse(raw).unwrap();
        assert!(message(&m));
        assert!(crate::notify::automated(&m));
        assert!(crate::newsletter::list_info(&m).bulk);
        assert!(!content("Giulia", "Spam report", false));
        assert!(!content("Giulia", "Fwd: Dinner", true));
        assert!(!content("WordPress", "Lunch tomorrow?", false));
    }
}
