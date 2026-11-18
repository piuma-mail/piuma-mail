//! Contact groups: a name for a list of addresses ("Book club"), typed in
//! To, Cc or Bcc to add every address at once. Not to be mixed up with
//! [`crate::groups`], which brings together the person's own addresses.
//!
//! Each group is one row named by a random id, with the time it last
//! changed and a mark once deleted, so a per-row merge can later carry
//! groups between devices (the sync space does not carry them yet).

/// A contact group, as Settings › Writing shows it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ContactGroup {
    /// Empty for one not kept yet.
    pub uid: String,
    pub name: String,
    /// "a@b.c" or "Name <a@b.c>", in the order they were written.
    pub addresses: Vec<String>,
}

/// The most addresses a group keeps.
pub const MAX_ADDRESSES: usize = 500;

/// A fresh id for a new group.
pub fn new_uid() -> String {
    let mut bytes = [0u8; 16];
    getrandom::fill(&mut bytes).expect("the system has randomness");
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// The address inside "Name <a@b.c>", or the text itself.
fn bare(address: &str) -> &str {
    let a = address.trim();
    match (a.rfind('<'), a.rfind('>')) {
        (Some(i), Some(j)) if i < j => a[i + 1..j].trim(),
        _ => a,
    }
}

/// The addresses of a group as kept: written ones only, each once
/// (ignoring case), at most [`MAX_ADDRESSES`]. Text with several
/// addresses separated by commas, semicolons or new lines counts as many.
pub fn tidy(addresses: &[String]) -> Vec<String> {
    let mut seen: Vec<String> = Vec::new();
    let mut out = Vec::new();
    for piece in addresses
        .iter()
        .flat_map(|a| a.split(['\n', ';', ',']))
        .map(str::trim)
        .filter(|a| !a.is_empty())
    {
        let email = bare(piece).to_lowercase();
        if !crate::groups::valid_address(&email) || seen.contains(&email) {
            continue;
        }
        seen.push(email);
        out.push(piece.to_owned());
        if out.len() == MAX_ADDRESSES {
            break;
        }
    }
    out
}

/// The group whose name is `typed` (ignoring case and spaces around it).
pub fn named<'a>(groups: &'a [ContactGroup], typed: &str) -> Option<&'a ContactGroup> {
    let typed = typed.trim();
    if typed.is_empty() {
        return None;
    }
    groups
        .iter()
        .find(|g| g.name.trim().to_lowercase() == typed.to_lowercase())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tidy_keeps_each_address_once() {
        let kept = tidy(&[
            "Luca <luca@example.org>, giulia@example.org".into(),
            "LUCA@example.org; not an address".into(),
            "\nmarco@example.org\n".into(),
        ]);
        assert_eq!(
            kept,
            vec![
                "Luca <luca@example.org>".to_string(),
                "giulia@example.org".into(),
                "marco@example.org".into(),
            ]
        );
    }

    #[test]
    fn finds_a_group_by_its_name() {
        let groups = vec![ContactGroup {
            uid: "a".into(),
            name: "Book club".into(),
            addresses: vec!["a@b.it".into()],
        }];
        assert_eq!(named(&groups, "  book CLUB ").unwrap().uid, "a");
        assert!(named(&groups, "book").is_none());
        assert!(named(&groups, " ").is_none());
    }

    #[test]
    fn ids_are_random() {
        assert_ne!(new_uid(), new_uid());
        assert_eq!(new_uid().len(), 32);
    }
}
