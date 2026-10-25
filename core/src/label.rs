//! Labels (`LabelsToApprove`): colored words on emails, shared across
//! accounts. An email can have several, and it stays in its folder. On
//! the server each label is a keyword on the message (IMAP and JMAP both
//! have them), so other mail apps show the same word and it survives a
//! reinstall. The list, with names and colors, travels in the sync space.

/// The five label colors, from the design system: never an account dot's.
pub const COLORS: [&str; 5] = ["amber", "teal", "coral", "blue", "violet"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Label {
    pub id: i64,
    pub name: String,
    /// One of [`COLORS`].
    pub color: String,
    /// What the server keeps on each message, lower case. It stays the
    /// same when the label is renamed.
    pub keyword: String,
}

/// The keyword a label's name becomes, as Thunderbird writes its tags:
/// lower case and modified UTF-7, with spaces and the characters IMAP
/// keeps for itself as "_". "To read" is `to_read`, "Città" `citt&AOA-`.
pub fn keyword_for(name: &str) -> String {
    let encoded = crate::imap::utf7_encode(&name.trim().to_lowercase());
    let mut keyword: String = encoded
        .chars()
        .map(|c| match c {
            '(' | ')' | '{' | '}' | '[' | ']' | '%' | '*' | '"' | '\\' => '_',
            c if c.is_ascii_graphic() => c,
            _ => '_',
        })
        .collect();
    // "$" and "\" start the system's own flags.
    if keyword.starts_with('$') {
        keyword.replace_range(..1, "_");
    }
    if keyword.is_empty() {
        keyword.push_str("label");
    }
    keyword
}

/// Whether a keyword on a message may be a label: not a system flag
/// ("\Seen") or one of the keywords mail apps keep for themselves
/// ("$Forwarded", "$Junk", a snooze time).
pub fn may_be_label(keyword: &str) -> bool {
    !keyword.is_empty() && !keyword.starts_with('$') && !keyword.starts_with('\\')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_name_becomes_a_keyword_every_server_takes() {
        assert_eq!(keyword_for("Worksite"), "worksite");
        assert_eq!(keyword_for(" To read "), "to_read");
        assert_eq!(keyword_for("Città"), "citt&AOA-");
        assert_eq!(keyword_for("Bills (2026) *"), "bills__2026___");
        assert_eq!(keyword_for("$Junk"), "_junk");
        assert_eq!(keyword_for(""), "label");
        assert!(may_be_label("worksite"));
        assert!(!may_be_label("$Forwarded"));
        assert!(!may_be_label("\\Seen"));
    }
}
