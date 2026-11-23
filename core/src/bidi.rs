//! Direction controls in text that comes from outside.
//!
//! A sender's name, a subject or a link's text can carry the characters
//! that steer Unicode's bidirectional algorithm: an override shows
//! "Bank\u{202E}gro.evil" as "Bank live.org", a stray POP DIRECTIONAL
//! ISOLATE closes the isolate the app puts around a name early. The app
//! does the same in Dart (`app/lib/widgets/bidi.dart`, `safeBidi`): the two
//! must agree.

/// Embeddings, overrides and isolates: they reorder what follows.
pub fn is_bidi_override(c: char) -> bool {
    matches!(c, '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}')
}

/// The invisible marks: LEFT-TO-RIGHT, RIGHT-TO-LEFT and ARABIC LETTER MARK.
pub fn is_bidi_mark(c: char) -> bool {
    matches!(c, '\u{200E}' | '\u{200F}' | '\u{061C}')
}

/// [text] with its direction controls made harmless: an embedding,
/// override or isolate becomes a visible U+FFFD, a mark an invisible WORD
/// JOINER (which the bidi algorithm ignores). One character for one, so
/// character and UTF-16 offsets into the text still hold.
pub fn neutralize(text: &str) -> String {
    if !text.chars().any(|c| is_bidi_override(c) || is_bidi_mark(c)) {
        return text.to_owned();
    }
    text.chars()
        .map(|c| {
            if is_bidi_override(c) {
                '\u{FFFD}'
            } else if is_bidi_mark(c) {
                '\u{2060}'
            } else {
                c
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overrides_show_and_marks_vanish() {
        assert_eq!(neutralize("Bank\u{202E}gro.evil"), "Bank\u{FFFD}gro.evil");
        assert_eq!(neutralize("a\u{2069}b\u{2066}"), "a\u{FFFD}b\u{FFFD}");
        assert_eq!(
            neutralize("\u{200F}x\u{200E}\u{061C}"),
            "\u{2060}x\u{2060}\u{2060}"
        );
        assert_eq!(neutralize("שלום Hello"), "שלום Hello");
        // One for one: offsets hold.
        let s = "\u{202D}ab\u{200F}";
        assert_eq!(
            neutralize(s).encode_utf16().count(),
            s.encode_utf16().count()
        );
    }
}
