//! Plain text as `format=flowed` (RFC 3676), for mail sent as plain text
//! only: long lines are cut at spaces, each cut line keeps its trailing
//! space so a reader that knows flowed text joins it back, and quoted
//! lines keep their `>` on every piece.
//!
//! The reading side is [`crate::reading::normalize_text`].

/// The longest line written, without the line break (RFC 3676 §4.2
/// recommends 78; 72 leaves room for the quote marks a reply adds).
pub const WIDTH: usize = 72;

/// `text` (lines separated by `\n`) as flowed lines, joined by `\r\n`.
pub fn encode(text: &str) -> String {
    let mut out: Vec<String> = Vec::new();
    for line in text.replace("\r\n", "\n").split('\n') {
        // The signature separator keeps its space: it is never flowed.
        if line == "-- " {
            out.push(line.to_owned());
            continue;
        }
        let (depth, content) = quote_depth(line);
        // A trailing space would make a hard break soft.
        let content = content.trim_end_matches(' ');
        let prefix = ">".repeat(depth);
        if content.is_empty() {
            out.push(prefix);
            continue;
        }
        // Space-stuffing (§4.4): a line that starts with a space, a quote
        // mark or "From " gets a space before it; quoted lines always have
        // one after their marks, which is the same space.
        let stuff = depth > 0
            || content.starts_with(' ')
            || content.starts_with('>')
            || content.starts_with("From ");
        let lead = if stuff { format!("{prefix} ") } else { prefix };
        let room = WIDTH.saturating_sub(lead.chars().count()).max(20);
        for piece in wrap(content, room) {
            out.push(format!("{lead}{piece}"));
        }
    }
    out.join("\r\n")
}

/// How many quote marks start `line`, read as people type them ("> > a"
/// is two deep), and what follows them.
fn quote_depth(line: &str) -> (usize, &str) {
    let mut depth = 0;
    let mut rest = line;
    while let Some(after) = rest.strip_prefix('>') {
        depth += 1;
        rest = after.strip_prefix(' ').unwrap_or(after);
        // "> > a": the next mark may follow the stuffed space.
        if !rest.starts_with('>') {
            break;
        }
    }
    (depth, if depth == 0 { line } else { rest })
}

/// `content` in pieces of at most `room` characters, cut after a space;
/// every piece but the last ends with that space (a soft break). A word
/// longer than `room` stays whole.
fn wrap(content: &str, room: usize) -> Vec<String> {
    let chars: Vec<char> = content.chars().collect();
    let mut pieces = Vec::new();
    let mut start = 0;
    while chars.len() - start > room {
        // The last space within reach, so the piece ends with it.
        let window = &chars[start..(start + room).min(chars.len())];
        let cut = match window.iter().rposition(|&c| c == ' ') {
            Some(i) if i > 0 => start + i + 1,
            // No space in reach: the word runs on to its first space.
            _ => match chars[start + room..].iter().position(|&c| c == ' ') {
                Some(i) => start + room + i + 1,
                None => chars.len(),
            },
        };
        if cut >= chars.len() {
            break;
        }
        pieces.push(chars[start..cut].iter().collect());
        start = cut;
    }
    pieces.push(chars[start..].iter().collect());
    pieces
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_lines_stay() {
        assert_eq!(encode("Hi Luca,\nsee you"), "Hi Luca,\r\nsee you");
    }

    #[test]
    fn long_lines_flow() {
        let long = "word ".repeat(30);
        let out = encode(long.trim_end());
        let lines: Vec<&str> = out.split("\r\n").collect();
        assert!(lines.len() > 1);
        for l in &lines[..lines.len() - 1] {
            assert!(l.ends_with(' '), "{l:?}");
            assert!(l.chars().count() <= WIDTH, "{l:?}");
        }
        assert!(!lines.last().unwrap().ends_with(' '));
        // Read back, it is the same text.
        let back = crate::reading::normalize_text(&out.replace("\r\n", "\n"), true, false);
        assert_eq!(back.trim(), long.trim());
    }

    #[test]
    fn hard_breaks_lose_trailing_spaces() {
        assert_eq!(encode("one  \ntwo"), "one\r\ntwo");
    }

    #[test]
    fn quotes_keep_their_marks_on_every_piece() {
        let quoted = format!("> {}", "quoted ".repeat(20).trim_end());
        let out = encode(&format!("{quoted}\n>\n> > deeper"));
        let lines: Vec<&str> = out.split("\r\n").collect();
        assert!(lines.len() > 3);
        assert!(lines[..lines.len() - 2].iter().all(|l| l.starts_with("> ")));
        assert_eq!(lines[lines.len() - 2], ">");
        assert_eq!(lines[lines.len() - 1], ">> deeper");
    }

    #[test]
    fn stuffs_lines_that_need_it() {
        assert_eq!(
            encode("From here\n indented\nx"),
            " From here\r\n  indented\r\nx"
        );
    }

    #[test]
    fn signature_separator_keeps_its_space() {
        assert_eq!(encode("Thanks\n-- \nMatteo"), "Thanks\r\n-- \r\nMatteo");
    }

    #[test]
    fn long_words_stay_whole() {
        let url = format!("see https://example.org/{}", "a".repeat(100));
        let out = encode(&url);
        assert_eq!(
            out,
            format!("see \r\nhttps://example.org/{}", "a".repeat(100))
        );
    }
}
