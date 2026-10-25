//! Address groups and aliases: one group brings together addresses of
//! different accounts and domains (Work = studio.it + lumen.design), with
//! its own color, signature and sending address. An alias is another
//! address an account sends from.

use crate::model::AccountId;

/// The IMAP header fields [`recipients`] reads.
pub const HEADER_FIELDS: &str = "TO CC DELIVERED-TO X-ORIGINAL-TO";

/// A group, as Settings › Groups shows it.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct AddressGroup {
    /// 0 for one not kept yet.
    pub id: i64,
    pub name: String,
    /// "#RRGGBB", one of the account colors.
    pub color: String,
    /// Its default signature; None for none.
    pub signature: Option<i64>,
    /// The address new emails go from; empty for the first one.
    pub send_from: String,
    /// Gets its own item in the sidebar, besides the unified inbox.
    pub separate_inbox: bool,
    /// Its mail makes notices.
    pub notify: bool,
    pub addresses: Vec<GroupAddress>,
}

/// One address of a group: an account's own address or one of its aliases.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GroupAddress {
    pub account: AccountId,
    pub email: String,
}

impl AddressGroup {
    /// Where new emails go from: the chosen address while it is still in
    /// the group, else the first one.
    pub fn sender(&self) -> Option<&GroupAddress> {
        self.addresses
            .iter()
            .find(|a| a.email.eq_ignore_ascii_case(&self.send_from))
            .or(self.addresses.first())
    }
}

/// Whose mail a list shows: everyone's, one account's, one group's, or one
/// address of a group. A message is an address's when it was written to
/// it; an account's own address has the mail written to none of its
/// aliases.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum Within {
    #[default]
    All,
    Account(AccountId),
    Group(i64),
    Address {
        group: i64,
        email: String,
    },
}

impl From<Option<AccountId>> for Within {
    fn from(a: Option<AccountId>) -> Self {
        a.map_or(Within::All, Within::Account)
    }
}

impl Within {
    /// The one account, for the queries' `account = ?` parameter.
    pub fn account(&self) -> Option<i64> {
        match self {
            Within::Account(a) => Some(a.0),
            _ => None,
        }
    }

    /// What to add to a WHERE on `message m` for a group or an address.
    pub fn sql(&self) -> String {
        let (group, email) = match self {
            Within::Group(g) => (*g, None),
            Within::Address { group, email } => (*group, Some(email)),
            _ => return String::new(),
        };
        let email = email.map_or(String::new(), |e| {
            format!(" AND ga.email = '{}'", e.trim().replace('\'', "''"))
        });
        let has = |who: &str| {
            format!("instr(' ' || m.recipients || ' ', ' ' || lower({who}) || ' ') > 0")
        };
        format!(
            " AND EXISTS (SELECT 1 FROM group_address ga
                 WHERE ga.grp = {group} AND ga.account = m.account{email}
                   AND CASE WHEN ga.email = (SELECT email FROM account WHERE id = ga.account)
                       THEN NOT EXISTS (SELECT 1 FROM account_alias al
                                        WHERE al.account = m.account AND {})
                       ELSE {} END)",
            has("al.email"),
            has("ga.email"),
        )
    }
}

/// Every address a message went to (To, Cc, then the mailbox the server
/// delivered it to), lowercase and space separated, each once.
pub fn recipients(m: &mail_parser::Message) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut add = |a: &str| {
        let a = a.trim().trim_matches(['<', '>']).to_lowercase();
        if a.contains('@') && !out.contains(&a) {
            out.push(a);
        }
    };
    for list in [m.to(), m.cc()].into_iter().flatten() {
        for a in list.iter() {
            if let Some(address) = a.address() {
                add(address);
            }
        }
    }
    for name in ["Delivered-To", "X-Original-To"] {
        for value in m.header_values(name) {
            if let Some(text) = value.as_text() {
                add(text);
            }
        }
    }
    out.join(" ")
}

/// The same, from a JMAP Email's `to` and `cc`.
pub fn recipients_json(e: &serde_json::Value) -> String {
    let mut out: Vec<String> = Vec::new();
    for key in ["to", "cc"] {
        for a in e[key].as_array().into_iter().flatten() {
            if let Some(email) = a["email"].as_str() {
                let email = email.trim().to_lowercase();
                if email.contains('@') && !out.contains(&email) {
                    out.push(email);
                }
            }
        }
    }
    out.join(" ")
}

/// Which of the account's addresses ([own], its own first, then aliases) a
/// message was written to, the first one it names: replies go from it.
pub fn written_to<'a>(own: &'a [String], recipients: &str) -> Option<&'a str> {
    recipients.split_whitespace().find_map(|r| {
        own.iter()
            .find(|a| a.eq_ignore_ascii_case(r))
            .map(String::as_str)
    })
}

/// A plausible address: something@domain.tld, no spaces.
pub fn valid_address(email: &str) -> bool {
    let email = email.trim();
    match email.split_once('@') {
        Some((local, domain)) => {
            !local.is_empty()
                && domain.contains('.')
                && !domain.starts_with('.')
                && !domain.ends_with('.')
                && !email
                    .chars()
                    .any(|c| c.is_whitespace() || c == '<' || c == '>')
                && !domain.contains('@')
        }
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recipients_from_the_headers() {
        let raw = b"From: Sara <sara@luce.it>\r\nTo: Matteo <Matteo@Studio.it>, fatture@studio.it\r\nCc: luca@studio.it\r\nDelivered-To: fatture@studio.it\r\nX-Original-To: <conti@studio.it>\r\nSubject: x\r\n\r\nhi\r\n";
        let m = mail_parser::MessageParser::default().parse(raw).unwrap();
        assert_eq!(
            recipients(&m),
            "matteo@studio.it fatture@studio.it luca@studio.it conti@studio.it"
        );
    }

    #[test]
    fn replies_go_from_the_address_written_to() {
        let own = vec![
            "matteo@studio.it".to_owned(),
            "fatture@studio.it".to_owned(),
        ];
        assert_eq!(
            written_to(&own, "fatture@studio.it luca@studio.it"),
            Some("fatture@studio.it")
        );
        assert_eq!(
            written_to(&own, "luca@studio.it matteo@studio.it fatture@studio.it"),
            Some("matteo@studio.it")
        );
        assert_eq!(written_to(&own, "luca@studio.it"), None);
    }

    #[test]
    fn the_sender_is_the_chosen_address_or_the_first() {
        let a = |e: &str| GroupAddress {
            account: AccountId(1),
            email: e.into(),
        };
        let mut g = AddressGroup {
            addresses: vec![a("matteo@studio.it"), a("info@studio.it")],
            send_from: "INFO@studio.it".into(),
            ..Default::default()
        };
        assert_eq!(g.sender().unwrap().email, "info@studio.it");
        g.send_from = "gone@studio.it".into();
        assert_eq!(g.sender().unwrap().email, "matteo@studio.it");
    }

    #[test]
    fn addresses_are_checked() {
        assert!(valid_address("info@studio.it"));
        assert!(valid_address(" fatture@studio.it "));
        assert!(!valid_address("info"));
        assert!(!valid_address("info@studio"));
        assert!(!valid_address("a b@studio.it"));
        assert!(!valid_address("@studio.it"));
    }
}
