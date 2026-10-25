//! Formatting written in compose, as `FormattingToApprove` draws it: the
//! text keeps its lists and quotes as line prefixes ("• ", "1. ", "│ "),
//! and bold, italic and links as marks over it. A message with any of
//! them goes out as HTML beside a plain-text copy.

use base64::Engine as _;

/// What a mark does to the words under it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MarkKind {
    Bold,
    Italic,
    /// A link to this address.
    Link(String),
}

/// A mark over the characters `start..end` of the text (counted in
/// characters, not bytes).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Mark {
    pub kind: MarkKind,
    pub start: usize,
    pub end: usize,
}

/// The start of a bulleted line.
pub const BULLET: &str = "• ";

/// The start of a quoted line, drawn as a bar while writing.
pub const QUOTE: char = '│';

/// The header a saved draft keeps its marks in.
pub const HEADER: &str = "X-Piuma-Format";

/// Past this the marks are not kept in the draft (its HTML still is).
pub const HEADER_MAX: usize = 900;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Line {
    Text,
    Blank,
    Bullet,
    Number(u32),
    Quote,
}

/// What kind of line `line` is, and where its words start (in chars).
fn line_kind(line: &str) -> (Line, usize) {
    if line.trim().is_empty() {
        return (Line::Blank, 0);
    }
    if line.starts_with(BULLET) {
        return (Line::Bullet, BULLET.chars().count());
    }
    if let Some(rest) = line.strip_prefix(QUOTE) {
        return (Line::Quote, if rest.starts_with(' ') { 2 } else { 1 });
    }
    let digits = line.chars().take_while(char::is_ascii_digit).count();
    if (1..=3).contains(&digits) && line[digits..].starts_with(". ") {
        return (
            Line::Number(line[..digits].parse().unwrap_or(1)),
            digits + 2,
        );
    }
    (Line::Text, 0)
}

/// Whether the text has anything an HTML version is needed for.
pub fn is_formatted(text: &str, marks: &[Mark]) -> bool {
    marks.iter().any(|m| m.end > m.start)
        || text
            .lines()
            .any(|l| matches!(line_kind(l).0, Line::Bullet | Line::Quote))
}

/// The plain-text copy: quoted lines start with "> " as mail has them.
pub fn plain(text: &str) -> String {
    text.split('\n')
        .map(|line| match line.strip_prefix(QUOTE) {
            Some(rest) => match rest.strip_prefix(' ').unwrap_or(rest) {
                "" => ">".to_owned(),
                rest => format!("> {rest}"),
            },
            None => line.to_owned(),
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            _ => out.push(c),
        }
    }
    out
}

/// Only web and mail addresses become links.
fn safe_link(url: &str) -> Option<&str> {
    let url = url.trim();
    let lower = url.to_ascii_lowercase();
    (lower.starts_with("https://") || lower.starts_with("http://") || lower.starts_with("mailto:"))
        .then_some(url)
        .filter(|u| !u.chars().any(char::is_whitespace))
}

/// The characters `from..to` of `chars` with the marks over them.
fn inline(chars: &[char], from: usize, to: usize, marks: &[Mark]) -> String {
    let mut cuts = vec![from, to];
    for m in marks {
        for at in [m.start, m.end] {
            if at > from && at < to {
                cuts.push(at);
            }
        }
    }
    cuts.sort_unstable();
    cuts.dedup();
    let mut out = String::new();
    for w in cuts.windows(2) {
        let (a, b) = (w[0], w[1]);
        let words = escape(&chars[a..b].iter().collect::<String>());
        let on = |kind: fn(&MarkKind) -> bool| {
            marks
                .iter()
                .find(|m| kind(&m.kind) && m.start <= a && m.end >= b)
        };
        let mut piece = words;
        if on(|k| *k == MarkKind::Italic).is_some() {
            piece = format!("<i>{piece}</i>");
        }
        if on(|k| *k == MarkKind::Bold).is_some() {
            piece = format!("<b>{piece}</b>");
        }
        let link = on(|k| matches!(k, MarkKind::Link(_))).and_then(|m| match &m.kind {
            MarkKind::Link(url) => safe_link(url),
            _ => None,
        });
        if let Some(url) = link {
            piece = format!("<a href=\"{}\">{piece}</a>", escape(url));
        }
        out.push_str(&piece);
    }
    out
}

/// The text as HTML: paragraphs, lists and quotes, with the marks inside.
pub fn to_html(text: &str, marks: &[Mark]) -> String {
    let chars: Vec<char> = text.chars().collect();
    // Each line: its kind, and where its words start and end.
    let mut lines = Vec::new();
    let mut at = 0;
    for line in text.split('\n') {
        let len = line.chars().count();
        let (kind, skip) = line_kind(line);
        lines.push((kind, at + skip, at + len));
        at += len + 1;
    }
    let mut out = String::new();
    let mut i = 0;
    while i < lines.len() {
        let (kind, ..) = lines[i];
        let same = |k: Line| match (kind, k) {
            (Line::Number(_), Line::Number(_)) => true,
            (a, b) => a == b,
        };
        let mut j = i;
        while j < lines.len() && same(lines[j].0) {
            j += 1;
        }
        let group = &lines[i..j];
        let words = |&(_, a, b): &(Line, usize, usize)| inline(&chars, a, b, marks);
        match kind {
            Line::Blank => {}
            Line::Text => {
                let body: Vec<String> = group.iter().map(words).collect();
                out.push_str("<p style=\"margin:0 0 1em\">");
                out.push_str(&body.join("<br>"));
                out.push_str("</p>");
            }
            Line::Quote => {
                let body: Vec<String> = group.iter().map(words).collect();
                out.push_str(
                    "<blockquote style=\"margin:0 0 1em;padding-left:12px;border-left:3px solid #d5d7dc;color:#5f636b\">",
                );
                out.push_str(&body.join("<br>"));
                out.push_str("</blockquote>");
            }
            Line::Bullet | Line::Number(_) => {
                let tag = if kind == Line::Bullet { "ul" } else { "ol" };
                let start = match kind {
                    Line::Number(n) if n != 1 => format!(" start=\"{n}\""),
                    _ => String::new(),
                };
                out.push_str(&format!(
                    "<{tag}{start} style=\"margin:0 0 1em;padding-left:24px\">"
                ));
                for line in group {
                    out.push_str(&format!("<li>{}</li>", words(line)));
                }
                out.push_str(&format!("</{tag}>"));
            }
        }
        i = j;
    }
    out
}

/// The marks, as a saved draft keeps them; None when there are none.
pub fn encode(marks: &[Mark]) -> Option<String> {
    let lines: Vec<String> = marks
        .iter()
        .filter(|m| m.end > m.start)
        .map(|m| match &m.kind {
            MarkKind::Bold => format!("b {} {}", m.start, m.end),
            MarkKind::Italic => format!("i {} {}", m.start, m.end),
            MarkKind::Link(url) => format!("l {} {} {url}", m.start, m.end),
        })
        .collect();
    if lines.is_empty() {
        return None;
    }
    Some(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(lines.join("\n")))
}

/// The marks a saved draft kept; none when the header is not ours.
pub fn decode(value: &str) -> Vec<Mark> {
    let Ok(raw) = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(value.trim()) else {
        return Vec::new();
    };
    let Ok(text) = String::from_utf8(raw) else {
        return Vec::new();
    };
    text.lines()
        .filter_map(|line| {
            let mut parts = line.splitn(4, ' ');
            let kind = parts.next()?;
            let start = parts.next()?.parse().ok()?;
            let end = parts.next()?.parse().ok()?;
            let kind = match kind {
                "b" => MarkKind::Bold,
                "i" => MarkKind::Italic,
                "l" => MarkKind::Link(parts.next()?.to_owned()),
                _ => return None,
            };
            (end > start).then_some(Mark { kind, start, end })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mark(kind: MarkKind, start: usize, end: usize) -> Mark {
        Mark { kind, start, end }
    }

    #[test]
    fn paragraphs_lists_and_quotes() {
        let text = "Hi Giulia,\n\nThree things:\n• the terrace\n• Marco\n\n1. eight\n2. half past\n│ as you said\nA.";
        assert_eq!(
            to_html(text, &[]),
            "<p style=\"margin:0 0 1em\">Hi Giulia,</p>\
             <p style=\"margin:0 0 1em\">Three things:</p>\
             <ul style=\"margin:0 0 1em;padding-left:24px\"><li>the terrace</li><li>Marco</li></ul>\
             <ol style=\"margin:0 0 1em;padding-left:24px\"><li>eight</li><li>half past</li></ol>\
             <blockquote style=\"margin:0 0 1em;padding-left:12px;border-left:3px solid #d5d7dc;color:#5f636b\">as you said</blockquote>\
             <p style=\"margin:0 0 1em\">A.</p>"
        );
    }

    #[test]
    fn marks_nest_and_escape() {
        // "café <b> menu": bold over "café", a link over "menu".
        let text = "café <b> menu";
        let html = to_html(
            text,
            &[
                mark(MarkKind::Bold, 0, 4),
                mark(MarkKind::Italic, 2, 4),
                mark(MarkKind::Link("https://x.it/?a=1&b=\"2\"".into()), 9, 13),
            ],
        );
        assert_eq!(
            html,
            "<p style=\"margin:0 0 1em\"><b>ca</b><b><i>fé</i></b> &lt;b&gt; \
             <a href=\"https://x.it/?a=1&amp;b=&quot;2&quot;\">menu</a></p>"
        );
    }

    #[test]
    fn only_web_and_mail_links() {
        let html = to_html(
            "tap",
            &[mark(MarkKind::Link("javascript:alert(1)".into()), 0, 3)],
        );
        assert!(!html.contains("href"));
    }

    #[test]
    fn formatted_only_with_something_to_show() {
        assert!(!is_formatted("1. plain\n2. text", &[]));
        assert!(is_formatted("• a list", &[]));
        assert!(is_formatted("│ a quote", &[]));
        assert!(is_formatted("x", &[mark(MarkKind::Bold, 0, 1)]));
    }

    #[test]
    fn plain_copy_quotes_as_mail_does() {
        assert_eq!(plain("│ said\n│\n• item"), "> said\n>\n• item");
    }

    #[test]
    fn marks_survive_the_draft() {
        let marks = vec![
            mark(MarkKind::Bold, 1, 4),
            mark(MarkKind::Link("https://a.it/x y".into()), 5, 9),
        ];
        assert_eq!(decode(&encode(&marks).unwrap()), marks);
        assert_eq!(encode(&[]), None);
        assert!(decode("not ours!").is_empty());
    }
}
