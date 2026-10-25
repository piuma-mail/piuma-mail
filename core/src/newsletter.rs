//! Newsletters: telling them from other mail by their list headers, how
//! long one takes to read, and leaving one.

use std::time::Duration;

use mail_parser::Message;

use crate::model::ListInfo;

/// The header fields [`list_info`] reads besides those of
/// [`crate::notify::HEADER_FIELDS`], for an IMAP fetch.
pub const HEADER_FIELDS: &str = "LIST-UNSUBSCRIBE-POST LIST-POST FEEDBACK-ID X-SES-OUTGOING \
     X-MAILGUN-SID X-SG-EID X-MC-USER X-MANDRILL-USER X-CSA-COMPLAINTS X-SFMC-STACK X-MSFBL \
     X-CAMPAIGN X-CAMPAIGNID";

/// Headers that mailing services (SES, Mailgun, SendGrid, Mailchimp,
/// Salesforce…) put on what they send, and people's mail never carries.
const SERVICE_MARKS: [&str; 11] = [
    "Feedback-ID",
    "X-SES-Outgoing",
    "X-Mailgun-Sid",
    "X-SG-EID",
    "X-MC-User",
    "X-Mandrill-User",
    "X-CSA-Complaints",
    "X-SFMC-Stack",
    "X-MSFBL",
    "X-Campaign",
    "X-CampaignID",
];

/// Words a minute, for the reading time.
const WORDS_A_MINUTE: u32 = 230;

/// What the list headers of `m` say. A newsletter is mail one can leave
/// (List-Unsubscribe) that takes no posts: a discussion list has a
/// List-Post address, an announcement list says "NO". Bulk is mail sent
/// to many or by a machine: Precedence, Auto-Submitted, a list nobody
/// posts to, or the marks of a mailing service.
pub fn list_info(m: &Message) -> ListInfo {
    let raw = |name: &'static str| m.header_raw(name).map(str::trim).unwrap_or_default();
    let submitted = raw("Auto-Submitted");
    let post = raw("List-Post");
    let discussion = !post.is_empty() && !post.eq_ignore_ascii_case("no");
    let bulk = ["bulk", "list", "junk"]
        .iter()
        .any(|p| raw("Precedence").eq_ignore_ascii_case(p))
        || !(submitted.is_empty() || submitted.eq_ignore_ascii_case("no"))
        || (!raw("List-Id").is_empty() && !discussion)
        || SERVICE_MARKS.iter().any(|h| m.header_raw(*h).is_some());
    let links = links(raw("List-Unsubscribe"));
    if links.is_empty() {
        return ListInfo {
            bulk,
            ..ListInfo::default()
        };
    }
    let pick = |scheme: &str| links.iter().find(|l| l.starts_with(scheme));
    let https = pick("https://");
    let one_click = https.is_some()
        && raw("List-Unsubscribe-Post")
            .to_ascii_lowercase()
            .contains("list-unsubscribe=one-click");
    ListInfo {
        newsletter: !discussion,
        unsubscribe: https
            .or_else(|| pick("http://"))
            .or_else(|| pick("mailto:"))
            .cloned()
            .unwrap_or_default(),
        one_click,
        bulk,
        receipt: None,
    }
}

/// The addresses of a List-Unsubscribe value, `<mailto:…>, <https://…>`,
/// that the app can use.
fn links(value: &str) -> Vec<String> {
    value
        .split('<')
        .skip(1)
        .filter_map(|part| part.split_once('>'))
        .map(|(link, _)| link.split_whitespace().collect::<String>())
        .filter(|l| {
            ["https://", "http://", "mailto:"]
                .iter()
                .any(|s| l.starts_with(s))
        })
        .collect()
}

/// Minutes to read `words` words, at least one; 0 when not known.
pub fn minutes(words: u32) -> u32 {
    if words == 0 {
        0
    } else {
        words.div_ceil(WORDS_A_MINUTE)
    }
}

/// How many words a message body has, as the reader shows it.
pub fn words(text: &str, html: Option<&str>) -> u32 {
    let shown = crate::reading::plain_text(&crate::reading::readable(text, html));
    shown.split_whitespace().count() as u32
}

/// A mailto unsubscribe, as the message to send.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnsubscribeMail {
    pub to: String,
    pub subject: String,
    pub body: String,
}

/// The message a `mailto:` address asks for; None when it is not one.
pub fn mailto(link: &str) -> Option<UnsubscribeMail> {
    let rest = link.strip_prefix("mailto:")?;
    let (to, query) = rest.split_once('?').unwrap_or((rest, ""));
    // Percent decoding; a '+' stays a '+', as in an address.
    let decode = |s: &str| {
        url::form_urlencoded::parse(format!("x={}", s.replace('+', "%2B")).as_bytes())
            .next()
            .map(|(_, v)| v.into_owned())
            .unwrap_or_default()
    };
    let to = decode(to);
    if !to.contains('@') {
        return None;
    }
    let mut out = UnsubscribeMail {
        to,
        subject: "unsubscribe".into(),
        body: String::new(),
    };
    for (key, value) in url::form_urlencoded::parse(query.replace('+', "%2B").as_bytes()) {
        match key.to_ascii_lowercase().as_str() {
            "subject" => out.subject = value.into_owned(),
            "body" => out.body = value.into_owned(),
            _ => {}
        }
    }
    Some(out)
}

#[derive(Debug, thiserror::Error)]
pub enum UnsubscribeError {
    #[error("not an https address")]
    BadAddress,
    #[error("network: {0}")]
    Network(#[from] reqwest::Error),
}

/// Leaves a list with one POST, as RFC 8058 says: no cookies, no page.
pub async fn one_click(link: &str) -> Result<(), UnsubscribeError> {
    let url = reqwest::Url::parse(link).map_err(|_| UnsubscribeError::BadAddress)?;
    if url.scheme() != "https" {
        return Err(UnsubscribeError::BadAddress);
    }
    crate::tls::http_client()
        .timeout(Duration::from_secs(20))
        .referer(false)
        .build()?
        .post(url)
        .header(
            reqwest::header::CONTENT_TYPE,
            "application/x-www-form-urlencoded",
        )
        .body("List-Unsubscribe=One-Click")
        .send()
        .await?
        .error_for_status()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use mail_parser::MessageParser;

    fn info(headers: &str) -> ListInfo {
        let raw = format!("From: a@b.it\r\n{headers}\r\nHello");
        list_info(&MessageParser::default().parse(raw.as_bytes()).unwrap())
    }

    #[test]
    fn newsletters_by_their_headers() {
        assert_eq!(info("Subject: Dinner\r\n"), ListInfo::default());
        // Bulk and automatic mail, with no list to leave.
        assert!(info("Precedence: Bulk\r\n").bulk);
        assert!(info("Auto-Submitted: auto-generated\r\n").bulk);
        assert!(!info("Auto-Submitted: no\r\n").bulk);
        // Sent by a mailing service, or to a list nobody posts to.
        assert!(info("Feedback-ID: 1:order:aliexpress\r\n").bulk);
        assert!(info("X-SFMC-Stack: 7\r\n").bulk);
        assert!(info("List-Id: <offers.shop.it>\r\n").bulk);
        assert!(!info("List-Id: <dev.b.it>\r\nList-Post: <mailto:dev@b.it>\r\n").bulk);
        let n = info(
            "List-Unsubscribe: <mailto:u@shop.it?subject=leave>,\r\n <https://shop.it/u?id=1>\r\n\
             List-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n",
        );
        assert_eq!(
            n,
            ListInfo {
                newsletter: true,
                unsubscribe: "https://shop.it/u?id=1".into(),
                one_click: true,
                bulk: false,
                receipt: None,
            }
        );
        let m = info("List-Unsubscribe: <mailto:u@shop.it>\r\nList-Post: NO\r\n");
        assert!(m.newsletter && !m.one_click);
        assert_eq!(m.unsubscribe, "mailto:u@shop.it");
        // A discussion list can be left, but it is people writing.
        let d = info(
            "List-Id: <dev.b.it>\r\nList-Post: <mailto:dev@b.it>\r\n\
             List-Unsubscribe: <https://b.it/leave>\r\n",
        );
        assert!(!d.newsletter && !d.one_click);
        assert_eq!(d.unsubscribe, "https://b.it/leave");
    }

    #[test]
    fn reading_time() {
        assert_eq!(minutes(0), 0);
        assert_eq!(minutes(1), 1);
        assert_eq!(minutes(230), 1);
        assert_eq!(minutes(1900), 9);
        assert_eq!(words("one two  three\nfour", None), 4);
    }

    #[test]
    fn mailto_unsubscribe() {
        assert_eq!(
            mailto("mailto:leave%40shop.it?subject=Unsubscribe%20me&body=id%3D7"),
            Some(UnsubscribeMail {
                to: "leave@shop.it".into(),
                subject: "Unsubscribe me".into(),
                body: "id=7".into(),
            })
        );
        assert_eq!(mailto("mailto:u@shop.it").unwrap().subject, "unsubscribe");
        assert_eq!(mailto("https://shop.it/u"), None);
        assert_eq!(mailto("mailto:?subject=x"), None);
    }

    #[tokio::test]
    async fn one_click_takes_only_https() {
        assert!(matches!(
            one_click("http://shop.it/u").await,
            Err(UnsubscribeError::BadAddress)
        ));
    }
}
