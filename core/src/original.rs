//! The original layout of an HTML email, made safe to show as it was sent
//! (`OriginalToApprove`).
//!
//! The reader normally redraws a message as one clean column
//! ([`crate::reading`]). For an email built as a layout (product grids,
//! columns, a designed newsletter) the person can ask for the original:
//! the HTML as it came, in the system's web view. What reaches the web
//! view has nothing to run and nothing to load:
//!
//! - scripts, frames, forms, plugins, media and SVG are taken out, with
//!   every `on…` handler and `javascript:` value;
//! - styles stay, but `@import` goes and a `url(…)` can only be a `data:`
//!   picture or font;
//! - pictures inside the message (`cid:`, `data:`) are written in as
//!   `data:` addresses; remote images are grey placeholders until the
//!   person loads them, and then travel in as `data:` too, fetched by the
//!   engine like any remote image, background pictures and the sharpest
//!   `srcset` version included; tracking pixels go;
//! - links are cleaned like the reader's, and the suspicious ones listed
//!   so the app can warn before opening them;
//! - a Content-Security-Policy that allows only `data:` images and fonts
//!   and inline styles closes anything left over.

use std::collections::HashMap;
use std::fmt::Write as _;

use base64::Engine as _;
use scraper::{ElementRef, Html, Node};
use url::Url;

use crate::reading::{self, Options};
use crate::tokens_g;

/// What the web view gets, and what the app needs to handle its links.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Original {
    /// A whole HTML document, safe to show.
    pub html: String,
    /// The remote images, in order and once each, shown as placeholders
    /// (or no background) unless loaded.
    pub remote: Vec<String>,
    /// Links (as cleaned) whose text shows another site, with that text.
    pub suspicious: Vec<(String, String)>,
}

/// A remote image fetched with the person's consent: its bytes.
pub type Loaded = HashMap<String, Vec<u8>>;

/// Elements that go with everything inside them.
const DROPPED: &[&str] = &[
    "script", "noscript", "iframe", "frame", "frameset", "object", "embed", "applet", "svg",
    "math", "template", "audio", "video", "canvas", "input", "select", "textarea", "button",
    "link", "meta", "base", "title", "param", "source", "track", "portal", "dialog",
];

/// Elements whose content stays without them. A `<picture>` keeps its
/// `<img>`, which every sender gives as the fallback.
const UNWRAPPED: &[&str] = &["form", "fieldset", "label", "picture"];

/// Void elements: written without a closing tag.
const VOID: &[&str] = &["br", "hr", "img", "wbr", "col", "area"];

/// Attributes that are never kept, whatever their value.
const DROPPED_ATTRS: &[&str] = &[
    "srcset",
    "formaction",
    "action",
    "background",
    "ping",
    "lowsrc",
    "dynsrc",
    "poster",
    "data",
    "codebase",
    "manifest",
    "xlink:href",
    "integrity",
];

/// Whether an email was built as a layout, so its original is worth a
/// look: a table row with two cells or more, or tables inside tables.
pub fn is_layout(html: &str) -> bool {
    let doc = Html::parse_document(html);
    doc.tree.root().descendants().any(|n| {
        let Some(el) = ElementRef::wrap(n) else {
            return false;
        };
        match el.value().name() {
            "tr" => {
                el.children()
                    .filter_map(ElementRef::wrap)
                    .filter(|c| matches!(c.value().name(), "td" | "th"))
                    .count()
                    >= 2
            }
            "table" => el
                .ancestors()
                .filter_map(ElementRef::wrap)
                .any(|a| a.value().name() == "table"),
            _ => false,
        }
    })
}

/// The safe document. `inline` gives the bytes of a picture inside the
/// message by its Content-ID; `loaded` has the remote images fetched.
pub fn original(
    html: &str,
    options: Options,
    inline: &dyn Fn(&str) -> Option<Vec<u8>>,
    loaded: &Loaded,
) -> Original {
    let doc = Html::parse_document(html);
    let mut w = Writer {
        options,
        inline,
        loaded,
        out: Original::default(),
        buf: String::new(),
        cleaned: 0,
    };
    w.buf.push_str("<!DOCTYPE html>");
    w.element(doc.root_element(), 1);
    w.out.html = std::mem::take(&mut w.buf);
    w.out
}

/// The remote images an original would show, to fetch them before
/// building it again with `loaded`.
pub fn remote_images(html: &str, options: Options) -> Vec<String> {
    original(html, options, &|_| None, &Loaded::new()).remote
}

struct Writer<'a> {
    options: Options,
    inline: &'a dyn Fn(&str) -> Option<Vec<u8>>,
    loaded: &'a Loaded,
    out: Original,
    buf: String,
    cleaned: u32,
}

impl Writer<'_> {
    fn element(&mut self, el: ElementRef, depth: usize) {
        if depth > reading::MAX_DEPTH {
            return;
        }
        let name = el.value().name().to_ascii_lowercase();
        if DROPPED.contains(&name.as_str()) || name.contains(':') {
            return;
        }
        if UNWRAPPED.contains(&name.as_str()) {
            self.children(el, depth);
            return;
        }
        if name == "img" {
            self.image(el);
            return;
        }
        let mut attrs = String::new();
        for (key, value) in el.value().attrs() {
            let key = key.to_ascii_lowercase();
            let Some(value) = self.attr(&name, &key, value, el) else {
                continue;
            };
            let _ = write!(attrs, " {key}=\"{}\"", escape(&value));
        }
        let _ = write!(self.buf, "<{name}{attrs}>");
        if name == "head" {
            self.head();
        }
        if VOID.contains(&name.as_str()) {
            return;
        }
        if name == "style" {
            let css: String = el.text().collect();
            // Text inside <style> isn't escaped; a closing tag in it would
            // end the element early.
            let css = self.css(&css);
            self.buf.push_str(&css.replace("</", "<\\/"));
        } else {
            self.children(el, depth);
        }
        let _ = write!(self.buf, "</{name}>");
    }

    fn children(&mut self, el: ElementRef, depth: usize) {
        for child in el.children() {
            match child.value() {
                Node::Text(t) => self.buf.push_str(&escape(t)),
                Node::Element(_) => {
                    if let Some(c) = ElementRef::wrap(child) {
                        self.element(c, depth + 1);
                    }
                }
                _ => {}
            }
        }
    }

    /// What the document starts with: the policy and the paper.
    fn head(&mut self) {
        let _ = write!(
            self.buf,
            "<meta charset=\"utf-8\">\
             <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; \
             img-src data:; style-src 'unsafe-inline'; font-src data:; form-action 'none'\">\
             <meta name=\"viewport\" content=\"width=600\">\
             <style>html{{background:{paper};color:{text};overflow-y:hidden}}body{{margin:0;overflow-y:hidden}}\
             img{{max-width:100%;height:auto}}</style>",
            paper = tokens_g::PAPER,
            text = tokens_g::TEXT,
        );
    }

    /// An attribute as kept, or None to leave it out.
    fn attr(&mut self, element: &str, key: &str, value: &str, el: ElementRef) -> Option<String> {
        // The background picture of a table or a cell, as a remote image.
        if key == "background" {
            return self.remote(value.trim());
        }
        if key.starts_with("on") || DROPPED_ATTRS.contains(&key) || key.contains(':') {
            return None;
        }
        let squeezed: String = value
            .chars()
            .filter(|c| !c.is_whitespace() && !c.is_control())
            .collect::<String>()
            .to_ascii_lowercase();
        if squeezed.contains("javascript:") || squeezed.contains("vbscript:") {
            return None;
        }
        match key {
            "style" => Some(self.css(value)),
            "href" if matches!(element, "a" | "area") => {
                let link = reading::safe_link(value, self.options.clean_links, &mut self.cleaned)?;
                if self.options.warn_links {
                    let text: String = el.text().collect();
                    if reading::suspicious(&text, &link)
                        && !self.out.suspicious.iter().any(|(l, _)| *l == link)
                    {
                        self.out
                            .suspicious
                            .push((link.clone(), text.trim().to_owned()));
                    }
                }
                Some(link)
            }
            "href" | "src" | "cite" | "longdesc" | "usemap" => None,
            "target" => None,
            _ => Some(value.to_owned()),
        }
    }

    /// A remote picture by its address, noted for fetching: as `data:`
    /// once loaded, None before.
    fn remote(&mut self, address: &str) -> Option<String> {
        let url = Url::parse(address).ok()?;
        if !matches!(url.scheme(), "http" | "https") {
            return None;
        }
        let url = String::from(url);
        let fetched = self.loaded.get(&url).and_then(|b| data_uri(b));
        if !self.out.remote.contains(&url) {
            self.out.remote.push(url);
        }
        fetched
    }

    /// Styles with nothing to fetch: `@import` goes, and a `url(…)` stays
    /// only as a `data:` picture or font. A remote one is noted, and comes
    /// in as `data:` once loaded; until then it is `none`.
    fn css(&mut self, css: &str) -> String {
        // `u\72l(` is `url(` to a browser: escapes are read to find what
        // loads, but only what is found is rewritten. The rest is copied
        // as written, so escaped selectors (`.w-1\/2`) keep working.
        let (decoded, at) = unescape_css(css);
        let lower = decoded.to_ascii_lowercase();
        let mut out = String::with_capacity(css.len());
        // How far the original text is already in `out`.
        let mut copied = 0;
        let mut i = 0;
        while i < decoded.len() {
            let found = if let Some(len) = IMAGE_FUNCTIONS
                .iter()
                .find(|f| lower[i..].starts_with(*f))
                .map(|f| f.len())
            {
                // `image-set("a.png" 1x)` and the like load addresses
                // without `url(`: the whole function goes.
                Some((function_end(&lower, i + len), "none".to_owned()))
            } else if lower[i..].starts_with("url(") {
                let end = function_end(&lower, i + 4);
                let inside_end = if lower[..end].ends_with(')') {
                    end - 1
                } else {
                    end
                };
                let inner = decoded[i + 4..inside_end.max(i + 4)]
                    .trim()
                    .trim_matches(['"', '\''])
                    .trim();
                let low = inner.to_ascii_lowercase();
                let keep = (low.starts_with("data:image/") && !low.starts_with("data:image/svg"))
                    || low.starts_with("data:font/")
                    || low.starts_with("data:application/font");
                let replacement = if keep {
                    css[at[i]..at[end]].to_owned()
                } else if let Some(data) = self.remote(inner) {
                    // Base64 needs no quotes, which an attribute would escape.
                    format!("url({data})")
                } else {
                    "none".to_owned()
                };
                Some((end, replacement))
            } else if lower[i..].starts_with("@import") {
                Some((statement_end(&lower, i), String::new()))
            } else if lower[i..].starts_with("expression(") {
                Some((i + "expression(".len(), "none".to_owned()))
            } else {
                None
            };
            match found {
                Some((end, replacement)) => {
                    out.push_str(&css[copied..at[i]]);
                    out.push_str(&replacement);
                    copied = at[end];
                    i = end;
                }
                None => i += decoded[i..].chars().next().map_or(1, char::len_utf8),
            }
        }
        out.push_str(&css[copied..]);
        out
    }

    fn image(&mut self, el: ElementRef) {
        let src = el.value().attr("src").unwrap_or("").trim();
        // A remote image with sharper versions: the sharpest is fetched.
        let sharpest = el.value().attr("srcset").and_then(sharpest);
        let src = match sharpest.as_deref() {
            Some(best) if src.is_empty() || src.starts_with("http") => best,
            _ => src,
        };
        let width = reading::dimension(&el, "width");
        let height = reading::dimension(&el, "height");
        let tiny = width.is_some_and(|w| w <= 3) || height.is_some_and(|h| h <= 3);
        let data = if let Some(rest) = src.strip_prefix("data:") {
            raster(rest).then(|| format!("data:{rest}"))
        } else if let Some(cid) =
            crate::guard::strip_prefix_ci(src, "cid:").filter(|c| !c.is_empty())
        {
            let cid = cid.trim_matches(['<', '>']).trim();
            (self.inline)(cid).and_then(|b| data_uri(&b))
        } else {
            let Ok(url) = Url::parse(src) else {
                return;
            };
            if !matches!(url.scheme(), "http" | "https") {
                return;
            }
            let pixel = tiny
                || reading::hidden(&el)
                || (width.is_none() && height.is_none() && reading::looks_like_tracker(&url));
            if pixel && self.options.stop_pixels {
                return;
            }
            Some(
                self.remote(url.as_str())
                    .unwrap_or_else(|| placeholder(width, height)),
            )
        };
        let Some(data) = data else {
            return;
        };
        let mut attrs = String::new();
        for (key, value) in el.value().attrs() {
            let key = key.to_ascii_lowercase();
            if key == "src" {
                continue;
            }
            let Some(value) = self.attr("img", &key, value, el) else {
                continue;
            };
            let _ = write!(attrs, " {key}=\"{}\"", escape(&value));
        }
        let _ = write!(self.buf, "<img src=\"{}\"{attrs}>", escape(&data));
    }
}

/// The candidate of a `srcset` drawn sharpest: the largest width or
/// density, up to 2x (more only costs bytes).
fn sharpest(srcset: &str) -> Option<String> {
    let mut best: Option<(f32, &str)> = None;
    for candidate in srcset.split(',') {
        let mut parts = candidate.split_whitespace();
        let Some(url) = parts.next() else {
            continue;
        };
        if !url.starts_with("http") {
            continue;
        }
        let size = parts.next().unwrap_or("1x");
        let score = if let Some(w) = size.strip_suffix('w') {
            // Widths: a 1200w picture is 2x on a 600 px email.
            w.parse::<f32>().ok().map(|w| w / 600.0)
        } else {
            size.strip_suffix('x').and_then(|x| x.parse::<f32>().ok())
        };
        let Some(score) = score.map(|s| s.min(2.0)) else {
            continue;
        };
        if best.is_none_or(|(b, _)| score > b) {
            best = Some((score, url));
        }
    }
    best.map(|(_, url)| url.to_owned())
}

/// A `data:` image of a kind the web view draws without running
/// anything, whose payload fits the cap.
fn raster(data: &str) -> bool {
    let meta = data.split(',').next().unwrap_or("").to_ascii_lowercase();
    let payload = data.split_once(',').map(|(_, p)| p).unwrap_or("");
    if payload.len() > reading::DATA_URI_MAX {
        return false;
    }
    [
        "image/png",
        "image/jpeg",
        "image/jpg",
        "image/gif",
        "image/webp",
    ]
    .iter()
    .any(|t| meta.starts_with(t))
}

/// Bytes as a `data:` address, when they are a picture the app shows.
fn data_uri(bytes: &[u8]) -> Option<String> {
    let mime = match bytes {
        [0x89, b'P', b'N', b'G', ..] => "image/png",
        [0xFF, 0xD8, 0xFF, ..] => "image/jpeg",
        [b'G', b'I', b'F', b'8', ..] => "image/gif",
        [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] => "image/webp",
        [b'B', b'M', ..] => "image/bmp",
        _ => return None,
    };
    Some(format!(
        "data:{mime};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    ))
}

/// CSS functions that load a picture by an address of their own.
const IMAGE_FUNCTIONS: &[&str] = &[
    "-webkit-image-set(",
    "image-set(",
    "-webkit-cross-fade(",
    "cross-fade(",
    "image(",
    "src(",
];

/// The index after the `)` that closes a function whose arguments start at
/// `from`, counting nested parentheses and skipping quoted strings and
/// escaped characters; the end when it never closes.
fn function_end(lower: &str, from: usize) -> usize {
    let bytes = lower.as_bytes();
    let mut depth = 1usize;
    let mut quote: Option<u8> = None;
    let mut i = from;
    while i < bytes.len() {
        match (bytes[i], quote) {
            // An escaped character is never a quote or a parenthesis.
            (b'\\', _) => i += 1,
            (b, Some(q)) if b == q => quote = None,
            (_, Some(_)) => {}
            (b'"' | b'\'', None) => quote = Some(bytes[i]),
            (b'(', None) => depth += 1,
            (b')', None) => {
                depth -= 1;
                if depth == 0 {
                    return i + 1;
                }
            }
            _ => {}
        }
        i += 1;
    }
    lower.len()
}

/// The index after the `;` that ends an `@import` starting at `from`,
/// skipping quoted strings; the end when nothing ends it.
fn statement_end(lower: &str, from: usize) -> usize {
    let bytes = lower.as_bytes();
    let mut quote: Option<u8> = None;
    let mut i = from;
    while i < bytes.len() {
        match (bytes[i], quote) {
            (b'\\', _) => i += 1,
            (b, Some(q)) if b == q => quote = None,
            (_, Some(_)) => {}
            (b'"' | b'\'', None) => quote = Some(bytes[i]),
            (b';', None) => return i + 1,
            _ => {}
        }
        i += 1;
    }
    lower.len()
}

/// CSS with its escapes read (`\72` is "r", `\@` is "@"), so a keyword
/// spelled with escapes is seen, and where in `css` each byte of it came
/// from (one more entry, for the end). Escapes that stand for a quote,
/// a backslash, a parenthesis, a line break or a control character stay
/// as written: read, they would change where a string or a function
/// ends. The decoded text is only searched, never written out.
fn unescape_css(css: &str) -> (String, Vec<usize>) {
    let mut out = String::with_capacity(css.len());
    let mut at = Vec::with_capacity(css.len() + 1);
    let push = |out: &mut String, at: &mut Vec<usize>, text: &str, from: usize| {
        out.push_str(text);
        at.extend(std::iter::repeat_n(from, text.len()));
    };
    let mut chars = css.char_indices().peekable();
    while let Some((start, c)) = chars.next() {
        if c != '\\' {
            push(&mut out, &mut at, &css[start..start + c.len_utf8()], start);
            continue;
        }
        let mut hex = String::new();
        while hex.len() < 6 {
            match chars.peek() {
                Some(&(_, h)) if h.is_ascii_hexdigit() => {
                    hex.push(h);
                    chars.next();
                }
                _ => break,
            }
        }
        let (decoded, end) = if hex.is_empty() {
            match chars.peek() {
                // A backslash before a line break, or at the end, stays.
                None | Some((_, '\n' | '\r' | '\u{c}')) => {
                    push(&mut out, &mut at, "\\", start);
                    continue;
                }
                Some(&(i, n)) => {
                    chars.next();
                    (n, i + n.len_utf8())
                }
            }
        } else {
            // One white space after a hex escape belongs to it.
            if let Some(&(_, w)) = chars.peek() {
                if matches!(w, ' ' | '\t' | '\n' | '\r' | '\u{c}') {
                    chars.next();
                }
            }
            let n = u32::from_str_radix(&hex, 16).unwrap_or(0xFFFD);
            let c = char::from_u32(n)
                .filter(|&c| c != '\0')
                .unwrap_or('\u{FFFD}');
            let end = chars.peek().map_or(css.len(), |&(i, _)| i);
            (c, end)
        };
        if matches!(decoded, '"' | '\'' | '\\' | '(' | ')') || decoded.is_control() {
            // As written, each byte from its own place.
            out.push_str(&css[start..end]);
            at.extend(start..end);
        } else {
            let mut buf = [0u8; 4];
            push(&mut out, &mut at, decoded.encode_utf8(&mut buf), start);
        }
    }
    at.push(css.len());
    (out, at)
}

/// A grey box the size of the image it stands for.
fn placeholder(width: Option<u32>, height: Option<u32>) -> String {
    let w = width.unwrap_or(600).max(1);
    let h = height.unwrap_or((u64::from(w) * 2 / 3) as u32).max(1);
    let svg = format!(
        "<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{h}'>\
         <rect width='100%' height='100%' fill='{}'/></svg>",
        tokens_g::PLACEHOLDER
    );
    format!(
        "data:image/svg+xml;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(svg)
    )
}

fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plain(html: &str) -> Original {
        original(html, Options::default(), &|_| None, &Loaded::new())
    }

    #[test]
    fn cut_sources_and_styles_never_split_a_character() {
        // A cid-like source whose fourth byte is inside "é".
        let o = plain("<img src=\"cid\u{e9}\">");
        assert!(!o.html.contains("cid"));
        // An unterminated url( ending in a character of two bytes.
        let o = plain("<div style=\"background:url(a\u{e9}\">x</div>");
        assert!(o.html.contains("x"));
        let o = plain("<style>.a{background:url(\u{20ac}</style><p>y</p>");
        assert!(o.html.contains('y'));
    }

    #[test]
    fn escaped_and_image_set_addresses_are_caught() {
        let o = plain("<div style=\"background:u\\72l(https://x.example/a.png)\">x</div>");
        assert_eq!(o.remote, ["https://x.example/a.png"]);
        assert!(!o.html.contains("x.example"));
        let o = plain("<style>@\\69mport \"https://x.example/b.css\"; p{color:red}</style>");
        assert!(!o.html.contains("x.example"), "{}", o.html);
        let o = plain(
            "<div style='background-image:image-set(\"https://x.example/c.png\" 1x, \"https://x.example/d.png\" 2x)'>x</div>",
        );
        assert!(!o.html.contains("x.example"), "{}", o.html);
        let o = plain(
            "<div style='background:-webkit-image-set(url(https://x.example/e.png) 1x)'>x</div>",
        );
        assert!(!o.html.contains("x.example"), "{}", o.html);
        // Escapes that only spell a character are kept as that character,
        // and a quote spelled as an escape stays escaped.
        assert_eq!(unescape_css("a\\62 c").0, "abc");
        assert_eq!(unescape_css("content:\"\\22\"").0, "content:\"\\22\"");
        assert_eq!(unescape_css("x\\").0, "x\\");
        // Each byte read points back at where it was written.
        let (decoded, at) = unescape_css("a\\62 c");
        assert_eq!(at, [0, 1, 5, 6]);
        assert_eq!(decoded.len() + 1, at.len());
    }

    #[test]
    fn escaped_selectors_survive_unchanged() {
        // Utility classes as transactional mail writes them: the escapes
        // are part of the selector and must reach the web view as written.
        let css = ".hover\\:text-blue:hover{color:#00f}.w-1\\/2{width:50%}\
                   .\\!block{display:block}.\\32 xl\\:p-4{padding:1rem}\
                   .a{content:\"\\201C\"}";
        let o = plain(&format!(
            "<html><head><style>{css}</style></head><body><p>x</p></body></html>"
        ));
        assert!(o.html.contains(css), "{}", o.html);
        assert!(o.remote.is_empty());
        let o = plain("<p style=\"margin:0\\!important;color:red\">x</p>");
        assert!(
            o.html.contains("margin:0\\!important;color:red"),
            "{}",
            o.html
        );
    }

    #[test]
    fn quoted_parentheses_do_not_end_a_function() {
        // A ")" inside a quoted address is part of it.
        let o = plain(
            "<div style='background-image:image-set(\"https://x.example/a.png?q=)\" 1x, url(https://tracker.example/leak.png) 2x);color:red'>x</div>",
        );
        assert!(o.remote.is_empty(), "{:?}", o.remote);
        assert!(!o.html.contains("tracker.example"), "{}", o.html);
        assert!(o.html.contains("color:red"), "{}", o.html);
        let o = plain(
            "<div style='background:url(\"https://x.example/a.png?q=(1)\") no-repeat'>x</div>",
        );
        assert_eq!(o.remote, ["https://x.example/a.png?q=(1)"]);
        assert!(o.html.contains("none no-repeat"), "{}", o.html);
        let o = plain("<style>@import \"https://x.example/a;b.css\"; p{color:red}</style><p>y</p>");
        assert!(!o.html.contains("x.example"), "{}", o.html);
        assert!(o.html.contains("p{color:red}"), "{}", o.html);
        assert_eq!(function_end("(\"a)\" (b)) c", 1), 10);
        assert_eq!(function_end("('it\\'s)') c", 1), 10);
    }

    #[test]
    fn a_huge_declared_width_makes_a_placeholder() {
        let o = plain(&format!(
            "<img src=\"https://x.example/a.png\" width=\"{}\">",
            u32::MAX
        ));
        assert!(o.html.contains("<img"));
    }

    const NEWSLETTER: &str = r##"<html><head>
        <link rel="stylesheet" href="https://cdn.example.com/a.css">
        <style>@import url("https://x.example.com/b.css"); .hero{background:url(https://x.example.com/h.jpg) #fff}</style>
        <script>alert(1)</script></head>
        <body onload="track()" bgcolor="#f4f4f4">
        <table width="600"><tr><td><img src="https://shop.example.com/logo.png" width="120" height="40" alt="Shop"></td>
        <td><a href="https://shop.example.com/new?utm_source=mail&amp;id=4">New</a></td></tr></table>
        <img src="https://track.example.com/o.gif" width="1" height="1">
        <img src="cid:logo@shop">
        <a href="javascript:steal()">Click</a>
        <a href="https://evil.example.net/login">www.bank.it</a>
        <form action="https://x.example.com/post"><input name="q"><p>Inside a form</p></form>
        <iframe src="https://x.example.com/frame"></iframe>
        <div style="background-image:url('https://x.example.com/bg.png');color:red">Red</div>
        </body></html>"##;

    fn png() -> Vec<u8> {
        let mut b = vec![0x89, b'P', b'N', b'G'];
        b.extend_from_slice(&[0; 8]);
        b
    }

    #[test]
    fn nothing_runs_and_nothing_loads() {
        let o = original(NEWSLETTER, Options::default(), &|_| None, &Loaded::new());
        let h = o.html.to_ascii_lowercase();
        for gone in [
            "<script",
            "alert(",
            "onload",
            "<iframe",
            "<form",
            "<input",
            "<link",
            "@import",
            "javascript:",
            "https://x.example.com",
            "https://cdn.example.com",
            "track.example.com",
        ] {
            assert!(!h.contains(gone), "{gone} is still there");
        }
        assert!(h.contains("content-security-policy"));
        assert!(h.contains("inside a form"));
        assert!(h.contains("color:red"));
        assert!(h.contains(r##"bgcolor="#f4f4f4""##));
        // The remote logo waits as a placeholder, the pixel is gone, and a
        // picture inside the message that isn't there is left out.
        // Background pictures wait too, as `none`.
        assert_eq!(
            o.remote,
            [
                "https://x.example.com/h.jpg",
                "https://shop.example.com/logo.png",
                "https://x.example.com/bg.png",
            ]
        );
        assert!(h.contains("data:image/svg+xml;base64,"));
        // Links are cleaned, and the one whose text shows another site
        // is listed.
        assert!(o
            .html
            .contains(r#"href="https://shop.example.com/new?id=4""#));
        assert_eq!(
            o.suspicious,
            [(
                "https://evil.example.net/login".to_owned(),
                "www.bank.it".to_owned()
            )]
        );
    }

    #[test]
    fn loaded_and_inside_pictures_come_as_data() {
        let mut loaded = Loaded::new();
        loaded.insert("https://shop.example.com/logo.png".into(), png());
        let o = original(
            NEWSLETTER,
            Options::default(),
            &|cid| (cid == "logo@shop").then(png),
            &loaded,
        );
        assert_eq!(o.html.matches("data:image/png;base64,").count(), 2);
        assert!(!o.html.contains("svg+xml"));
        assert_eq!(remote_images(NEWSLETTER, Options::default()).len(), 3);
    }

    #[test]
    fn backgrounds_and_sharper_versions_load_with_the_images() {
        let html = r#"<table background="https://n.example.com/paper.jpg"><tr>
            <td style="background-image:url('https://n.example.com/hero.jpg')">Hi</td></tr></table>
            <picture><source srcset="https://n.example.com/a.webp"><img src="https://n.example.com/a.jpg"
                srcset="https://n.example.com/a.jpg 1x, https://n.example.com/a@2x.jpg 2x, https://n.example.com/a@3x.jpg 3x"
                width="300" height="200"></picture>
            <img src="https://n.example.com/a.jpg">"#;
        let none = original(html, Options::default(), &|_| None, &Loaded::new());
        assert_eq!(
            none.remote,
            [
                "https://n.example.com/paper.jpg",
                "https://n.example.com/hero.jpg",
                "https://n.example.com/a@2x.jpg",
                "https://n.example.com/a.jpg",
            ]
        );
        assert!(!none.html.contains("background="));
        assert!(none.html.contains("background-image:none"));
        assert!(!none.html.contains("<source"));

        let loaded: Loaded = none.remote.iter().map(|u| (u.clone(), png())).collect();
        let all = original(html, Options::default(), &|_| None, &loaded);
        assert!(all.html.contains(r#"background="data:image/png;base64,"#));
        assert!(all
            .html
            .contains("background-image:url(data:image/png;base64,"));
        assert_eq!(all.html.matches("data:image/png;base64,").count(), 4);
        assert!(!all.html.contains("n.example.com"));
    }

    #[test]
    fn a_layout_is_told_from_a_letter() {
        assert!(is_layout(NEWSLETTER));
        assert!(!is_layout(
            "<p>Hi Luca,</p><table><tr><td>one cell</td></tr></table>"
        ));
        assert!(is_layout(
            "<table><tr><td><table><tr><td>x</td></tr></table></td></tr></table>"
        ));
    }

    #[test]
    fn style_text_cannot_close_its_element() {
        let o = original(
            "<style>p{color:red}</style ><style>a::after{content:'</style><script>x</script>'}</style>",
            Options::default(),
            &|_| None,
            &Loaded::new(),
        );
        assert!(!o.html.to_ascii_lowercase().contains("<script"));
    }

    #[test]
    fn a_pathological_nesting_stops_before_the_stack_does() {
        let mut deep = String::new();
        for _ in 0..200 {
            deep.push('<');
            deep.push_str("div>");
        }
        deep.push_str("innermost");
        for _ in 0..200 {
            deep.push_str("</div>");
        }
        let o = original(&deep, Options::default(), &|_| None, &Loaded::new());
        assert!(!o.html.contains("innermost"));

        let mut ok = String::new();
        for _ in 0..50 {
            ok.push('<');
            ok.push_str("div>");
        }
        ok.push_str("innermost");
        for _ in 0..50 {
            ok.push_str("</div>");
        }
        let o = original(&ok, Options::default(), &|_| None, &Loaded::new());
        assert!(o.html.contains("innermost"));
    }
}
