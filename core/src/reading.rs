//! A message made safe and calm to read.
//!
//! HTML is never shown as HTML: it is turned into a short list of blocks
//! (paragraphs, headings, quotes, list items, images) that the app draws
//! with its own type and colors. Scripts, styles, forms and frames simply
//! have nowhere to go. On the way:
//!
//! - remote images are kept as addresses, for the app to load only when the
//!   person allows it;
//! - tracking pixels are dropped and counted, with remote styles and fonts
//!   (which can also tell a sender the message was opened);
//! - links lose their tracking parameters (`utm_*`, `fbclid`, …);
//! - a link whose text shows one address but goes to another is flagged.

use base64::Engine as _;
use scraper::{ElementRef, Html, Node};
use url::Url;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Readable {
    pub blocks: Vec<Block>,
    /// Remote images, which load only when the person allows it.
    pub remote_images: u32,
    /// What was stopped, one entry per kind and server.
    pub trackers: Vec<Tracker>,
    /// Links that had tracking parameters removed.
    pub links_cleaned: u32,
    /// Links whose text shows a different address than where they go.
    pub suspicious_links: u32,
}

/// What the person chose in Privacy & security. Everything is on by
/// default; remote images are decided by the app, not here.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Options {
    /// Drop invisible images that report opens. Off: they become ordinary
    /// remote images, which load with the others.
    pub stop_pixels: bool,
    /// Remove tracking parameters from links.
    pub clean_links: bool,
    /// Flag links whose text shows another address.
    pub warn_links: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            stop_pixels: true,
            clean_links: true,
            warn_links: true,
        }
    }
}

/// The longest base64 payload, before decoding, that an inline `data:`
/// image may hold: beyond that it is storage, not an image.
pub const DATA_URI_MAX: usize = 2_000_000;
/// How deep the walkers may descend: hostile markup is stopped before
/// it can overflow the stack, and its deeper content is left out.
pub const MAX_DEPTH: usize = 128;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlockKind {
    Paragraph,
    Heading,
    ListItem,
    Image,
    Rule,
    Code,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Block {
    pub kind: BlockKind,
    /// Heading level (1 large, 2 small) or list depth (from 1).
    pub level: u8,
    /// How many quotes deep the block is (0 = not quoted).
    pub quote: u8,
    /// "•" or "3." for list items.
    pub marker: String,
    pub spans: Vec<Span>,
    pub image: Option<Image>,
    /// The direction the markup sets with `dir` on the block or an
    /// ancestor: `Some(true)` right to left, `Some(false)` left to right,
    /// `None` when unset or `auto` (the app takes the text's own).
    pub rtl: Option<bool>,
}

impl Block {
    fn new(kind: BlockKind) -> Block {
        Block {
            kind,
            level: 0,
            quote: 0,
            marker: String::new(),
            spans: Vec::new(),
            image: None,
            rtl: None,
        }
    }

    /// The block's words, as plain text.
    pub fn text(&self) -> String {
        self.spans.iter().map(|s| s.text.as_str()).collect()
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Span {
    pub text: String,
    pub bold: bool,
    pub italic: bool,
    pub code: bool,
    /// Where the link goes, already cleaned. Only http, https and mailto.
    pub link: Option<String>,
    /// The link's text shows a different address than where it goes.
    pub suspicious: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Image {
    /// An http(s) address, loaded only with the person's consent. Empty
    /// when the image travels inside the message (`data`).
    pub url: String,
    /// Bytes of an image embedded in the message.
    pub data: Option<Vec<u8>>,
    pub alt: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub link: Option<String>,
    /// The Content-ID of a picture inside the message (`cid:`), for the
    /// caller to fill [`Image::data`] from; None otherwise.
    pub cid: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrackerKind {
    /// An invisible image that reports when the message is opened.
    Pixel,
    /// Fonts loaded from a server.
    Font,
    /// Styles loaded from a server.
    Style,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Tracker {
    pub kind: TrackerKind,
    pub host: String,
    /// How many of this kind came from this server.
    pub count: u32,
}

/// The readable form of a message. `html` wins when there is one.
pub fn readable(text: &str, html: Option<&str>) -> Readable {
    readable_with(text, html, Options::default())
}

pub fn readable_with(text: &str, html: Option<&str>, options: Options) -> Readable {
    match html {
        Some(h) if !h.trim().is_empty() => from_html_with(h, options),
        _ => from_text_with(text, options),
    }
}

/// A visible list marker at the start of a plain-text line.
fn text_list_marker(line: &str) -> Option<(&str, &str)> {
    let line = line.trim_start();
    for marker in ["-", "*", "•"] {
        if let Some(rest) = line.strip_prefix(marker).and_then(|s| s.strip_prefix(' ')) {
            return Some((marker, rest));
        }
    }
    let digits = line.bytes().take_while(u8::is_ascii_digit).count();
    if digits > 0 {
        let rest = line[digits..].strip_prefix(". ")?;
        return Some((&line[..digits + 1], rest));
    }
    None
}

/// Decode text/plain line structure while MIME parameters are still available.
/// Fixed text only reflows likely transport wrapping; flowed text follows RFC 3676.
pub(crate) fn normalize_text(text: &str, flowed: bool, delsp: bool) -> String {
    let mut out = String::new();
    let mut previous: Option<(usize, bool, bool, bool)> = None;
    for line in text.lines() {
        let depth = line.bytes().take_while(|&b| b == b'>').count();
        let content = if flowed || depth > 0 {
            line[depth..].strip_prefix(' ').unwrap_or(&line[depth..])
        } else {
            line
        };
        let signature = content == "-- ";
        let soft = flowed && content.ends_with(' ') && !signature;
        let list = text_list_marker(content).is_some();
        let blank = content.is_empty();
        if let Some((old_depth, join, old_blank, old_list)) = previous {
            if join
                && old_depth == depth
                && !blank
                && !old_blank
                && !signature
                && (flowed || (!list && !old_list && !content.starts_with([' ', '\t'])))
            {
                if !flowed {
                    out.push(' ');
                }
            } else {
                out.push('\n');
                out.push_str(&">".repeat(depth));
                if depth > 0 {
                    out.push(' ');
                }
                // Keep a stuffed literal '>' distinct from a quote prefix
                // when the normalized text is read again.
                if flowed && content.starts_with('>') {
                    out.push(' ');
                }
            }
        } else {
            out.push_str(&">".repeat(depth));
            if depth > 0 {
                out.push(' ');
            }
            if flowed && content.starts_with('>') {
                out.push(' ');
            }
        }
        if soft && delsp {
            out.push_str(&content[..content.len() - 1]);
        } else if flowed {
            out.push_str(content);
        } else {
            out.push_str(content.trim_end());
        }
        // Be conservative with undeclared wrapping: short lines, lists and
        // indented content are intentional. Only long prose lines can join.
        let width = content.chars().count();
        let hard_wrap = !flowed
            && (60..=80).contains(&width)
            && !line[depth..].starts_with([' ', '\t'])
            && !signature;
        previous = Some((depth, soft || hard_wrap, blank, list));
    }
    out
}

/// Plain text: paragraphs on blank lines, `>` quotes, addresses as links.
pub fn from_text(text: &str) -> Readable {
    from_text_with(text, Options::default())
}

fn from_text_with(text: &str, options: Options) -> Readable {
    let mut out = Readable::default();
    let mut lines: Vec<(u8, &str)> = Vec::new();
    let flush = |lines: &mut Vec<(u8, &str)>, out: &mut Readable| {
        if lines.is_empty() {
            return;
        }
        let quote = lines[0].0;
        let joined = lines
            .iter()
            .map(|(_, l)| l.trim_end())
            .collect::<Vec<_>>()
            .join("\n");
        let (kind, marker, joined) = match text_list_marker(joined.trim()) {
            Some((marker, rest)) => (BlockKind::ListItem, marker, rest),
            None => (BlockKind::Paragraph, "", joined.trim()),
        };
        let mut block = Block::new(kind);
        block.marker = marker.to_owned();
        block.level = u8::from(kind == BlockKind::ListItem);
        block.quote = quote;
        block.spans = autolink(joined.trim(), options.clean_links, &mut out.links_cleaned);
        if !block.spans.is_empty() {
            out.blocks.push(block);
        }
        lines.clear();
    };
    for line in text.lines() {
        let mut rest = line;
        let mut depth = 0u8;
        while let Some(r) = rest.strip_prefix('>') {
            depth = depth.saturating_add(1);
            rest = r;
        }
        if depth > 0 {
            rest = rest.strip_prefix(' ').unwrap_or(rest);
        }
        if rest.trim().is_empty() {
            flush(&mut lines, &mut out);
            continue;
        }
        if lines.first().is_some_and(|(d, _)| *d != depth)
            || text_list_marker(rest).is_some()
            || lines
                .first()
                .is_some_and(|(_, l)| text_list_marker(l).is_some())
        {
            flush(&mut lines, &mut out);
        }
        lines.push((depth, rest));
    }
    flush(&mut lines, &mut out);
    out
}

/// Where the first "http://" or "https://" in `text` starts. One pass
/// from the start: looking for each separately would scan the rest of a
/// long text again for every link in it.
fn link_start(text: &str) -> Option<usize> {
    text.match_indices("http").map(|(i, _)| i).find(|&i| {
        let after = &text[i + 4..];
        after.starts_with("://") || after.starts_with("s://")
    })
}

/// Words that start with http:// or https:// become (cleaned) links.
fn autolink(text: &str, clean: bool, cleaned: &mut u32) -> Vec<Span> {
    let mut spans = Vec::new();
    let mut plain = String::new();
    let mut rest = text;
    while let Some(start) = link_start(rest) {
        let end = rest[start..]
            .find(|c: char| c.is_whitespace() || c == '<' || c == '>' || c == '"')
            .map_or(rest.len(), |e| start + e);
        let mut word = &rest[start..end];
        // Sentence punctuation after an address isn't part of it.
        while word.ends_with(['.', ',', ')', ';', ':', '!', '?']) {
            word = &word[..word.len() - 1];
        }
        let end = start + word.len();
        plain.push_str(&rest[..start]);
        match safe_link(word, clean, cleaned) {
            Some(link) => {
                if !plain.is_empty() {
                    spans.push(Span {
                        text: std::mem::take(&mut plain),
                        ..Span::default()
                    });
                }
                spans.push(Span {
                    text: crate::bidi::neutralize(word),
                    link: Some(link),
                    ..Span::default()
                });
            }
            None => plain.push_str(word),
        }
        rest = &rest[end..];
    }
    plain.push_str(rest);
    if !plain.is_empty() {
        spans.push(Span {
            text: plain,
            ..Span::default()
        });
    }
    spans
}

/// Parameters that only say who clicked, from where.
const TRACKING_PARAMS: &[&str] = &[
    "fbclid",
    "gclid",
    "gclsrc",
    "dclid",
    "gbraid",
    "wbraid",
    "msclkid",
    "yclid",
    "twclid",
    "igshid",
    "mc_cid",
    "mc_eid",
    "_hsenc",
    "_hsmi",
    "__hssc",
    "__hstc",
    "__hsfp",
    "hsCtaTracking",
    "mkt_tok",
    "oly_anon_id",
    "oly_enc_id",
    "vero_id",
    "vero_conv",
    "rb_clickid",
    "s_cid",
    "ss_email_id",
    "ml_subscriber",
    "ml_subscriber_hash",
    "_kx",
    "ck_subscriber_id",
    "trk",
    "trkCampaign",
    "sc_campaign",
    "sc_channel",
    "ref_src",
    "spm",
];

fn is_tracking_param(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower.starts_with("utm_")
        || TRACKING_PARAMS
            .iter()
            .any(|p| p.eq_ignore_ascii_case(&lower))
}

/// A link the app may open: http, https or mailto, without tracking
/// parameters when `clean`. Counts it in `cleaned` when something was
/// removed.
pub(crate) fn safe_link(href: &str, clean: bool, cleaned: &mut u32) -> Option<String> {
    let href = href.trim();
    let mut url = Url::parse(href).ok()?;
    match url.scheme() {
        "mailto" => return Some(url.into()),
        "http" | "https" => {}
        _ => return None,
    }
    url.host_str()?;
    if clean && url.query().is_some() {
        let pairs: Vec<(String, String)> = url
            .query_pairs()
            .map(|(k, v)| (k.into_owned(), v.into_owned()))
            .collect();
        let kept: Vec<&(String, String)> = pairs
            .iter()
            .filter(|(k, _)| !is_tracking_param(k))
            .collect();
        if kept.len() != pairs.len() {
            *cleaned += 1;
            if kept.is_empty() {
                url.set_query(None);
            } else {
                url.query_pairs_mut()
                    .clear()
                    .extend_pairs(kept.iter().map(|(k, v)| (k, v)));
            }
        }
    }
    Some(url.into())
}

/// The part of a host a person recognises: "bank.it" in "www.bank.it",
/// "bank.co.uk" in "login.bank.co.uk". An approximation without the full
/// public suffix list, good enough to compare two addresses.
fn site(host: &str) -> String {
    let host = host.trim_end_matches('.').to_ascii_lowercase();
    let labels: Vec<&str> = host.split('.').collect();
    if labels.len() <= 2 {
        return host;
    }
    let second = labels[labels.len() - 2];
    let keep = if ["co", "com", "net", "org", "gov", "ac", "edu"].contains(&second)
        && labels[labels.len() - 1].len() == 2
    {
        3
    } else {
        2
    };
    labels[labels.len() - keep..].join(".")
}

/// The host a link's visible text shows, when it reads as an address.
fn shown_host(text: &str) -> Option<String> {
    let t = text.trim();
    // A dot, or one UTS #46 reads as a dot ("bank．example").
    if t.is_empty()
        || t.contains(char::is_whitespace)
        || !t.contains(['.', '\u{3002}', '\u{FF0E}', '\u{FF61}'])
    {
        return None;
    }
    let with_scheme = if t.contains("://") {
        t.to_owned()
    } else {
        format!("https://{t}")
    };
    let url = Url::parse(&with_scheme).ok()?;
    let host = url.host_str()?;
    // "v1.2" or "Mr.Smith" aren't addresses: the last label must be letters.
    // One dot at the end ("paypal.com.") is still the same address.
    let tld = host.strip_suffix('.').unwrap_or(host).rsplit('.').next()?;
    (tld.len() >= 2 && tld.chars().all(|c| c.is_ascii_alphabetic())).then(|| host.to_owned())
}

/// Endings that make the name before an `@` read as a domain rather than
/// a person ("paypal.com@…", not "john.smith@…").
const USER_HOST_TLDS: [&str; 19] = [
    "com", "net", "org", "info", "io", "co", "app", "biz", "it", "de", "fr", "es", "pt", "uk",
    "eu", "ch", "at", "br", "us",
];

/// The name before an `@` in a link text's address, when it reads as an
/// address itself: "www.paypal.com" in "www.paypal.com@evil.com", which a
/// browser takes as a user name and doesn't go to. An email address's own
/// name ("anna", "john.smith") isn't one: the name counts only when the
/// text has a scheme ("https://…"), or the name starts with "www.", or it
/// ends in a common top-level domain.
fn shown_user_host(text: &str) -> Option<String> {
    let t = text.trim();
    let (has_scheme, t) = t
        .split_once("://")
        .map_or((false, t), |(_, rest)| (true, rest));
    let authority = t.split(['/', '?', '#']).next()?;
    let (name, _) = authority.rsplit_once('@')?;
    let lower = name.to_ascii_lowercase();
    let last = lower.trim_end_matches('.').rsplit('.').next()?;
    if !(has_scheme || lower.starts_with("www.") || USER_HOST_TLDS.contains(&last)) {
        return None;
    }
    shown_host(name)
}

/// `text` with every `%40` written back as the `@` it encodes, so
/// "www.paypal.com%40evil.com" shows its user name like the plain form.
/// Only that escape: the rest of the text is read as written.
fn decode_at(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(i) = rest.find('%') {
        out.push_str(&rest[..i]);
        let after = &rest[i + 1..];
        if after.get(..2).is_some_and(|hex| hex == "40") {
            out.push('@');
            rest = &after[2..];
        } else {
            out.push('%');
            rest = after;
        }
    }
    out.push_str(rest);
    out
}

pub(crate) fn suspicious(text: &str, link: &str) -> bool {
    let text = &decode_at(text);
    let Some(shown) = shown_host(text) else {
        return false;
    };
    let Some(real) = Url::parse(link)
        .ok()
        .and_then(|u| u.host_str().map(str::to_owned))
    else {
        return false;
    };
    let real = site(&real);
    site(&shown) != real || shown_user_host(text).is_some_and(|name| site(&name) != real)
}

/// A link's host in the ASCII form a browser goes to: UTS #46 mapping
/// (full-width letters and the dots `。` `．` `｡` read as ASCII, case folded,
/// characters UTS #46 drops removed), then punycode, as the WHATWG URL
/// standard does it. The same parsing `suspicious` compares with, so the
/// app shows and compares the host the engine checked. An IPv4 address
/// comes back in its usual dotted form, an IPv6 one in brackets. `None`
/// when `host` isn't a host a browser would open (a forbidden character
/// such as `@` or `%`, or a label UTS #46 refuses).
pub fn link_host_ascii(host: &str) -> Option<String> {
    let host = host.trim();
    // The app hands the host percent-decoded: a `%` left in it would be
    // decoded a second time here (`bank%252eexample`), and a browser
    // refuses it anyway.
    if host.is_empty() || host.contains('%') {
        return None;
    }
    let parsed = if host.contains(':') && !host.starts_with('[') {
        url::Host::parse(&format!("[{host}]"))
    } else {
        url::Host::parse(host)
    };
    match parsed.ok()? {
        url::Host::Domain(d) if !d.is_empty() => Some(d),
        url::Host::Domain(_) => None,
        url::Host::Ipv4(a) => Some(a.to_string()),
        url::Host::Ipv6(a) => Some(format!("[{a}]")),
    }
}

/// Elements whose content is never shown.
const SKIPPED: &[&str] = &[
    "head", "script", "style", "title", "noscript", "template", "iframe", "object", "embed", "svg",
    "math", "canvas", "audio", "video", "select", "textarea", "input", "map", "frame", "frameset",
    "applet", "meta", "base",
];

/// Elements that start a new block.
/// Elements whose `dir` sets the direction of the blocks inside them.
fn sets_direction(name: &str) -> bool {
    BLOCKS.contains(&name)
        || matches!(
            name,
            "blockquote" | "ul" | "ol" | "li" | "pre" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6"
        )
}

const BLOCKS: &[&str] = &[
    "p",
    "div",
    "section",
    "article",
    "header",
    "footer",
    "main",
    "aside",
    "nav",
    "table",
    "tbody",
    "thead",
    "tfoot",
    "tr",
    "td",
    "th",
    "center",
    "address",
    "figure",
    "figcaption",
    "dl",
    "dt",
    "dd",
    "form",
    "fieldset",
    "details",
    "summary",
    "body",
    "html",
];

#[derive(Clone, Copy, Default)]
struct Style {
    bold: bool,
    italic: bool,
    code: bool,
    pre: bool,
    quote: u8,
    list_depth: u8,
    /// From the nearest `dir`: see [`Block::rtl`].
    rtl: Option<bool>,
}

struct Walker {
    options: Options,
    out: Readable,
    current: Vec<Span>,
    current_style: Style,
    heading: u8,
    marker: Option<String>,
    link: Option<(String, bool)>,
    /// The number of the `<li>` about to be walked, given by its `<ol>`.
    number: Option<usize>,
}

/// Rich HTML: see the module's description.
pub fn from_html(html: &str) -> Readable {
    from_html_with(html, Options::default())
}

fn from_html_with(html: &str, options: Options) -> Readable {
    let doc = Html::parse_document(html);
    let mut w = Walker {
        options,
        out: Readable::default(),
        current: Vec::new(),
        current_style: Style::default(),
        heading: 0,
        marker: None,
        link: None,
        number: None,
    };
    // Styles and fonts in <head> are noticed, never loaded.
    for node in doc.tree.root().descendants() {
        if let Some(el) = ElementRef::wrap(node) {
            match el.value().name() {
                "link" => {
                    let rel = el.value().attr("rel").unwrap_or("").to_ascii_lowercase();
                    if rel.contains("stylesheet") || rel.contains("preload") || rel.contains("icon")
                    {
                        if let Some(href) = el.value().attr("href") {
                            w.remote_style(href);
                        }
                    }
                }
                "style" => {
                    let css: String = el.text().collect();
                    for href in css_urls(&css) {
                        w.remote_style(&href);
                    }
                }
                _ => {}
            }
        }
    }
    w.walk(doc.root_element(), Style::default(), 1);
    w.flush();
    // Keep the blocks tidy: no empty ones, no two rules in a row.
    let mut blocks: Vec<Block> = Vec::with_capacity(w.out.blocks.len());
    for b in std::mem::take(&mut w.out.blocks) {
        let rule_after_rule =
            b.kind == BlockKind::Rule && blocks.last().is_none_or(|l| l.kind == BlockKind::Rule);
        if !rule_after_rule {
            blocks.push(b);
        }
    }
    while blocks.last().is_some_and(|b| b.kind == BlockKind::Rule) {
        blocks.pop();
    }
    w.out.blocks = blocks;
    w.out
}

/// `url(...)` and `@import "..."` addresses in a style sheet.
fn css_urls(css: &str) -> Vec<String> {
    let mut out = Vec::new();
    let lower = css.to_ascii_lowercase();
    let mut from = 0;
    while let Some(i) = lower[from..].find("url(") {
        let start = from + i + 4;
        let end = lower[start..].find(')').map_or(lower.len(), |e| start + e);
        out.push(css[start..end].trim().trim_matches(['"', '\'']).to_owned());
        from = end;
    }
    let mut from = 0;
    while let Some(i) = lower[from..].find("@import") {
        let start = from + i + 7;
        let rest = css[start..].trim_start();
        if let Some(q) = rest.chars().next().filter(|c| *c == '"' || *c == '\'') {
            if let Some(end) = rest[1..].find(q) {
                out.push(rest[1..1 + end].to_owned());
            }
        }
        from = start;
    }
    out
}

fn style_attr(el: &ElementRef) -> String {
    el.value()
        .attr("style")
        .unwrap_or("")
        .to_ascii_lowercase()
        .replace(' ', "")
}

pub(crate) fn hidden(el: &ElementRef) -> bool {
    if el.value().attr("hidden").is_some() {
        return true;
    }
    let s = style_attr(el);
    s.contains("display:none")
        || s.contains("visibility:hidden")
        || s.contains("mso-hide:all")
        || (s.contains("max-height:0") && s.contains("overflow:hidden"))
        || s.contains("opacity:0;")
        || s.ends_with("opacity:0")
}

/// A pixel size from `width="1"` or `style="width:1px"`.
pub(crate) fn dimension(el: &ElementRef, name: &str) -> Option<u32> {
    if let Some(v) = el.value().attr(name) {
        let digits: String = v.trim().chars().take_while(char::is_ascii_digit).collect();
        if !digits.is_empty() && !v.contains('%') {
            return digits.parse().ok();
        }
    }
    let s = style_attr(el);
    let key = format!("{name}:");
    let pos = s
        .split(';')
        .find_map(|d| d.strip_prefix(key.as_str()).map(str::to_owned))?;
    pos.strip_suffix("px")?
        .parse::<f32>()
        .ok()
        .map(|f| f as u32)
}

/// Paths and servers that exist only to count opens.
pub(crate) fn looks_like_tracker(url: &Url) -> bool {
    let host = url.host_str().unwrap_or("").to_ascii_lowercase();
    let path = url.path().to_ascii_lowercase();
    const HOSTS: &[&str] = &[
        "list-manage.com",
        "mailtrack.io",
        "mailtrack.com",
        "pixel.",
        "track.",
        "tracking.",
        "open.",
        "opens.",
        "beacon.",
        "sendgrid.net",
        "mandrillapp.com",
        "mailchimp.com",
        "hubspotemail.net",
        "exct.net",
        "rs6.net",
        "mixmax.com",
        "yesware.com",
    ];
    const PATHS: &[&str] = &[
        "/open",
        "/o.gif",
        "/o/",
        "/track",
        "/pixel",
        "/beacon",
        "/wf/open",
        "/e/o/",
        "/imp",
        "/1x1",
        "/spacer",
        "/blank.gif",
        "/t.gif",
        "/p.gif",
    ];
    HOSTS
        .iter()
        .any(|h| host.starts_with(h) || host.ends_with(h) || host.contains(&format!(".{h}")))
        || PATHS
            .iter()
            .any(|p| path.starts_with(p) || path.contains(p))
}

impl Walker {
    fn remote_style(&mut self, href: &str) {
        let Ok(url) = Url::parse(href.trim()) else {
            return;
        };
        if !matches!(url.scheme(), "http" | "https") {
            return;
        }
        let path = url.path().to_ascii_lowercase();
        let host = url.host_str().unwrap_or("").to_owned();
        let font = host.contains("font")
            || [".woff", ".woff2", ".ttf", ".otf", ".eot"]
                .iter()
                .any(|e| path.ends_with(e))
            || path.contains("/css2");
        self.tracker(
            if font {
                TrackerKind::Font
            } else {
                TrackerKind::Style
            },
            host,
        );
    }

    fn tracker(&mut self, kind: TrackerKind, host: String) {
        match self
            .out
            .trackers
            .iter_mut()
            .find(|t| t.kind == kind && t.host == host)
        {
            Some(t) => t.count += 1,
            None => self.out.trackers.push(Tracker {
                kind,
                host,
                count: 1,
            }),
        }
    }

    fn flush(&mut self) {
        // Trim the edges and drop blocks with nothing to read.
        let style = self.current_style;
        let mut spans = std::mem::take(&mut self.current);
        if !style.pre {
            if let Some(first) = spans.first_mut() {
                first.text = first.text.trim_start().to_owned();
            }
            if let Some(last) = spans.last_mut() {
                last.text = last.text.trim_end().to_owned();
            }
        }
        spans.retain(|s| !s.text.is_empty());
        let marker = self.marker.take();
        if spans.iter().all(|s| s.text.trim().is_empty()) {
            if let Some(m) = marker {
                // An empty list item keeps its number for the next text.
                self.marker = Some(m);
            }
            return;
        }
        let mut block = Block::new(if self.heading > 0 {
            BlockKind::Heading
        } else if style.pre {
            BlockKind::Code
        } else if marker.is_some() {
            BlockKind::ListItem
        } else {
            BlockKind::Paragraph
        });
        block.level = if self.heading > 0 {
            self.heading
        } else {
            style.list_depth
        };
        block.quote = style.quote;
        block.rtl = style.rtl;
        block.marker = marker.unwrap_or_default();
        block.spans = spans;
        self.out.blocks.push(block);
    }

    fn push_text(&mut self, text: &str, style: Style) {
        let text = if style.pre {
            text.to_owned()
        } else {
            let mut collapsed = String::with_capacity(text.len());
            let mut space = self
                .current
                .last()
                .is_none_or(|s| s.text.ends_with([' ', '\n']));
            for ch in text.chars() {
                if ch.is_whitespace() && ch != '\u{a0}' {
                    if !space {
                        collapsed.push(' ');
                        space = true;
                    }
                } else {
                    // Invisible characters newsletters use to pad previews.
                    if matches!(
                        ch,
                        '\u{200b}'
                            | '\u{200c}'
                            | '\u{200d}'
                            | '\u{2060}'
                            | '\u{feff}'
                            | '\u{34f}'
                            | '\u{ad}'
                    ) {
                        continue;
                    }
                    collapsed.push(if ch == '\u{a0}' { ' ' } else { ch });
                    space = false;
                }
            }
            collapsed
        };
        if text.is_empty() {
            return;
        }
        if self.current.is_empty() {
            self.current_style = style;
        }
        let (link, suspicious) = match &self.link {
            Some((l, s)) => (Some(l.clone()), *s),
            None => (None, false),
        };
        // A link's text is the sender's: no direction controls of its own.
        let text = if link.is_some() {
            crate::bidi::neutralize(&text)
        } else {
            text
        };
        match self.current.last_mut() {
            Some(last)
                if last.bold == style.bold
                    && last.italic == style.italic
                    && last.code == style.code
                    && last.link == link =>
            {
                last.text.push_str(&text);
            }
            _ => self.current.push(Span {
                text,
                bold: style.bold,
                italic: style.italic,
                code: style.code,
                link,
                suspicious,
            }),
        }
    }

    fn image(&mut self, el: &ElementRef, style: Style) {
        let src = el.value().attr("src").unwrap_or("").trim();
        let width = dimension(el, "width");
        let height = dimension(el, "height");
        let alt = el.value().attr("alt").unwrap_or("").trim().to_owned();
        let tiny = width.is_some_and(|w| w <= 3) || height.is_some_and(|h| h <= 3);
        let mut image = Image {
            alt,
            width,
            height,
            link: self.link.as_ref().map(|(l, _)| l.clone()),
            ..Image::default()
        };
        if let Some(data) = src.strip_prefix("data:") {
            if tiny || hidden(el) {
                return;
            }
            let Some((meta, payload)) = data.split_once(',') else {
                return;
            };
            let meta = meta.to_ascii_lowercase();
            let supported = [
                "image/png",
                "image/jpeg",
                "image/jpg",
                "image/gif",
                "image/webp",
            ]
            .iter()
            .any(|t| meta.starts_with(t));
            if !supported || !meta.ends_with(";base64") || payload.len() > DATA_URI_MAX {
                return;
            }
            let Ok(bytes) = base64::engine::general_purpose::STANDARD
                .decode(payload.trim().replace(['\n', '\r', ' '], ""))
            else {
                return;
            };
            image.data = Some(bytes);
        } else if let Some(cid) =
            crate::guard::strip_prefix_ci(src, "cid:").filter(|c| !c.is_empty())
        {
            // Inside the message: no request leaves the device.
            if tiny || hidden(el) {
                return;
            }
            image.cid = Some(cid.trim_matches(['<', '>']).trim().to_owned());
        } else {
            let Ok(url) = Url::parse(src) else {
                return;
            };
            if !matches!(url.scheme(), "http" | "https") {
                return;
            }
            let host = url.host_str().unwrap_or("").to_owned();
            let pixel = tiny
                || hidden(el)
                || (width.is_none() && height.is_none() && looks_like_tracker(&url));
            if pixel && self.options.stop_pixels {
                self.tracker(TrackerKind::Pixel, host);
                return;
            }
            self.out.remote_images += 1;
            image.url = url.into();
        }
        self.flush();
        let mut block = Block::new(BlockKind::Image);
        block.quote = style.quote;
        block.rtl = style.rtl;
        block.image = Some(image);
        self.out.blocks.push(block);
    }

    fn walk(&mut self, el: ElementRef, inherited: Style, depth: usize) {
        if depth > MAX_DEPTH {
            return;
        }
        let name = el.value().name();
        if SKIPPED.contains(&name) {
            return;
        }
        if name == "img" {
            self.image(&el, inherited);
            return;
        }
        if hidden(&el) {
            return;
        }
        // Background images are remote content too; never loaded.
        for href in css_urls(el.value().attr("style").unwrap_or("")) {
            self.remote_style(&href);
        }
        if let Some(bg) = el.value().attr("background") {
            self.remote_style(bg);
        }

        let mut style = inherited;
        // A block's `dir` holds for everything inside, until another
        // block's; `auto` hands the choice back to the text. An inline
        // element's (a `span`, a link) turns a few words around, not the
        // paragraph they sit in.
        if let Some(dir) = el.value().attr("dir").filter(|_| sets_direction(name)) {
            style.rtl = match dir.trim().to_ascii_lowercase().as_str() {
                "rtl" => Some(true),
                "ltr" => Some(false),
                "auto" => None,
                _ => style.rtl,
            };
        }
        let heading = match name {
            "h1" | "h2" => 1,
            "h3" | "h4" | "h5" | "h6" => 2,
            _ => 0,
        };
        let block = heading > 0
            || BLOCKS.contains(&name)
            || matches!(name, "blockquote" | "ul" | "ol" | "li" | "pre" | "hr");
        if block {
            self.flush();
        }
        match name {
            "b" | "strong" => style.bold = true,
            "i" | "em" | "cite" => style.italic = true,
            "code" | "kbd" | "samp" | "tt" => style.code = true,
            "pre" => style.pre = true,
            "blockquote" => style.quote = style.quote.saturating_add(1),
            "ul" | "ol" => style.list_depth = style.list_depth.saturating_add(1),
            "hr" => {
                let mut rule = Block::new(BlockKind::Rule);
                rule.quote = style.quote;
                self.out.blocks.push(rule);
                return;
            }
            "br" => {
                if self.current.is_empty() {
                    self.current_style = style;
                }
                match self.current.last_mut() {
                    Some(last) if last.link.is_none() => {
                        let trimmed = last.text.trim_end_matches(' ').len();
                        last.text.truncate(trimmed);
                        last.text.push('\n');
                    }
                    _ => self.current.push(Span {
                        text: "\n".into(),
                        ..Span::default()
                    }),
                }
                return;
            }
            _ => {}
        }
        let s = style_attr(&el);
        if s.contains("font-weight:bold")
            || s.contains("font-weight:700")
            || s.contains("font-weight:600")
        {
            style.bold = true;
        }
        if s.contains("font-style:italic") {
            style.italic = true;
        }
        if heading > 0 {
            self.heading = heading;
        }
        if name == "li" {
            // Its number was counted by the `<ol>` walking its children:
            // looking back at every earlier item would make a long list
            // quadratic.
            let number = self.number.take();
            self.marker = Some(match el.parent().and_then(ElementRef::wrap) {
                Some(p) if p.value().name() == "ol" => format!("{}.", number.unwrap_or(1)),
                _ => "•".into(),
            });
            if style.list_depth == 0 {
                style.list_depth = 1;
            }
        }
        let outer_link = self.link.clone();
        if name == "a" {
            let href = el.value().attr("href").unwrap_or("");
            let clean = self.options.clean_links;
            self.link = safe_link(href, clean, &mut self.out.links_cleaned).map(|l| {
                let text: String = el.text().collect();
                let s = self.options.warn_links && suspicious(&text, &l);
                if s {
                    self.out.suspicious_links += 1;
                }
                (l, s)
            });
        }

        // The number the next `<li>` of an `<ol>` shows.
        let mut next_number = (name == "ol").then(|| {
            el.value()
                .attr("start")
                .and_then(|s| s.trim().parse::<usize>().ok())
                .unwrap_or(1)
        });
        for child in el.children() {
            match child.value() {
                Node::Text(t) => self.push_text(t, style),
                Node::Element(_) => {
                    if let Some(c) = ElementRef::wrap(child) {
                        if let Some(n) = next_number.as_mut().filter(|_| c.value().name() == "li") {
                            self.number = Some(*n);
                            *n = n.saturating_add(1);
                        }
                        self.walk(c, style, depth + 1);
                    }
                }
                _ => {}
            }
        }

        if name == "a" {
            self.link = outer_link;
        }
        if block {
            self.flush();
        }
        if heading > 0 {
            self.heading = 0;
        }
    }
}

/// The picture a newsletter issue opens with, for its cover in
/// Newsletters: the first remote image that looks like a photo, not a
/// logo, a spacer, a button or an icon. Its address only; nothing loads.
pub fn cover(html: &str) -> Option<String> {
    from_html(html)
        .blocks
        .into_iter()
        .filter_map(|b| b.image)
        .find(|i| {
            if i.url.is_empty() {
                return false;
            }
            let small = i.width.is_some_and(|w| w < 200) || i.height.is_some_and(|h| h < 90);
            let thin = match (i.width, i.height) {
                (Some(w), Some(h)) if w > 0 && h > 0 => w > 4 * h || h > 3 * w,
                _ => false,
            };
            let named = |text: &str| {
                let t = text.to_ascii_lowercase();
                ["logo", "icon", "spacer", "button", "badge", "social"]
                    .iter()
                    .any(|w| t.contains(w))
            };
            let path = Url::parse(&i.url)
                .map(|u| u.path().to_owned())
                .unwrap_or_default();
            !small && !thin && !named(&i.alt) && !named(&path)
        })
        .map(|i| i.url)
}

/// The readable text of HTML, for search and replies.
pub fn plain_text(r: &Readable) -> String {
    r.blocks
        .iter()
        .filter(|b| b.kind != BlockKind::Image && b.kind != BlockKind::Rule)
        .map(|b| {
            let text = b.text();
            let text = if b.marker.is_empty() {
                text
            } else {
                format!("{} {text}", b.marker)
            };
            if b.quote > 0 {
                text.lines()
                    .map(|l| format!("{} {l}", ">".repeat(b.quote as usize)))
                    .collect::<Vec<_>>()
                    .join("\n")
            } else {
                text
            }
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_inline_dir_does_not_turn_the_paragraph() {
        let r = from_html(
            "<p><span dir=\"rtl\">\u{645}\u{631}\u{62d}\u{628}\u{627}</span> English</p>\
             <div dir=\"rtl\"><p>x <b dir=\"ltr\">y</b></p></div>\
             <ul dir=\"rtl\"><li>a</li></ul><table><tr><td dir=\"rtl\">b</td></tr></table>\
             <h2 dir=\"rtl\">c</h2>",
        );
        let dirs: Vec<Option<bool>> = r.blocks.iter().map(|b| b.rtl).collect();
        assert_eq!(dirs, [None, Some(true), Some(true), Some(true), Some(true)]);
    }

    #[test]
    fn a_links_text_loses_its_direction_controls() {
        let r = from_html(
            "<p>Pay at <a href=\"https://evil.example/\">bank\u{202E}moc.\u{2069}x\u{200F}</a></p>",
        );
        let link = r.blocks[0]
            .spans
            .iter()
            .find(|s| s.link.is_some())
            .expect("a link");
        assert_eq!(link.text, "bank\u{FFFD}moc.\u{FFFD}x\u{2060}");
        // Text around it is the email's own and stays as written.
        let r = from_html("<p>\u{200F}abc</p>");
        assert_eq!(r.blocks[0].spans[0].text, "\u{200F}abc");
        // Plain-text links too.
        let r = from_text("see https://a.example/\u{202E}gpj.exe");
        let link = r.blocks[0].spans.iter().find(|s| s.link.is_some());
        if let Some(link) = link {
            assert!(!link.text.contains('\u{202E}'), "{}", link.text);
        }
    }

    #[test]
    fn blocks_keep_the_direction_their_markup_sets() {
        let r = from_html(
            "<html dir=\"rtl\"><body><p>\u{645}\u{631}\u{62d}\u{628}\u{627}</p>\
             <div dir=\"ltr\"><p>Hello</p><p dir=\"auto\">Auto</p></div>\
             <p dir=\"RTL \">\u{5e9}\u{5dc}\u{5d5}\u{5dd}</p><p dir=\"sideways\">Odd</p></body></html>",
        );
        let dirs: Vec<Option<bool>> = r.blocks.iter().map(|b| b.rtl).collect();
        assert_eq!(
            dirs,
            [Some(true), Some(false), None, Some(true), Some(true)]
        );
        // Plain text and markup without `dir` leave it to the text.
        assert!(from_html("<p>Hi</p>")
            .blocks
            .iter()
            .all(|b| b.rtl.is_none()));
        assert!(from_text("Hi\n\nThere")
            .blocks
            .iter()
            .all(|b| b.rtl.is_none()));
    }

    #[test]
    fn an_image_source_cut_inside_a_character_is_no_cid() {
        // "cid" then "é": the fourth byte falls inside the "é".
        let r = from_html("<p>Hi</p><img src=\"cid\u{e9}x\">");
        assert!(r
            .blocks
            .iter()
            .all(|b| b.image.as_ref().is_none_or(|i| i.cid.is_none())));
        let r = from_html("<img src=\"CID:logo@x\">");
        let cid = r.blocks.iter().find_map(|b| b.image.as_ref()?.cid.clone());
        assert_eq!(cid.as_deref(), Some("logo@x"));
    }

    #[test]
    fn ordered_lists_count_from_their_start() {
        let r = from_html(
            "<ol start=\"7\"><li>a</li><li>b</li></ol><ol><li>c</li><li>d</li><li>e</li></ol>\
             <ul><li>f</li></ul><ol start=\"99999999999999999999999\"><li>g</li></ol>",
        );
        let markers: Vec<&str> = r.blocks.iter().map(|b| b.marker.as_str()).collect();
        assert_eq!(markers, ["7.", "8.", "1.", "2.", "3.", "•", "1."]);
        let r = from_html(&format!(
            "<ol start=\"{}\"><li>a</li><li>b</li></ol>",
            usize::MAX
        ));
        assert_eq!(r.blocks[1].marker, format!("{}.", usize::MAX));
    }

    #[test]
    fn a_long_list_and_many_links_read_in_linear_time() {
        let started = std::time::Instant::now();
        let items: String = (0..60_000).map(|_| "<li>x</li>").collect();
        let r = from_html(&format!("<ol>{items}</ol>"));
        assert_eq!(r.blocks.last().map(|b| b.marker.as_str()), Some("60000."));
        // Many plain addresses and no secure one: each used to send the
        // search for "https://" through all the rest.
        let text: String = (0..60_000).map(|_| "http://a.example ").collect();
        let r = from_text(&text);
        assert!(!r.blocks.is_empty());
        assert!(started.elapsed() < std::time::Duration::from_secs(60));
    }

    fn texts(r: &Readable) -> Vec<String> {
        r.blocks.iter().map(Block::text).collect()
    }

    #[test]
    fn a_cover_is_the_first_photo_not_the_logo() {
        let html = r#"<table><tr><td><img src="https://n.example.com/logo.png" width="140" height="40" alt="Lume"></td></tr>
            <tr><td><img src="https://n.example.com/spacer.gif" width="600" height="20"></td></tr>
            <tr><td><img src="https://n.example.com/icons/fb.png"></td></tr>
            <tr><td><img src="https://n.example.com/autumn.jpg" width="600" height="300" alt="Wool and light"></td></tr>
            <tr><td><img src="https://n.example.com/second.jpg" width="600" height="300"></td></tr></table>"#;
        assert_eq!(
            cover(html).as_deref(),
            Some("https://n.example.com/autumn.jpg")
        );
        assert_eq!(cover("<p>Only words</p>"), None);
        // A picture inside the message isn't remote: nothing to fetch.
        assert_eq!(
            cover(r#"<img src="cid:hero@x" width="600" height="300">"#),
            None
        );
    }

    #[test]
    fn pictures_inside_the_message_wait_for_their_bytes() {
        let r = from_html(
            r#"<p>Hi</p><img src="cid:logo@studio" alt="Studio"><img src="cid:x" width="1">"#,
        );
        let images: Vec<_> = r.blocks.iter().filter_map(|b| b.image.as_ref()).collect();
        assert_eq!(images.len(), 1);
        assert_eq!(images[0].cid.as_deref(), Some("logo@studio"));
        assert_eq!(images[0].alt, "Studio");
        assert_eq!(r.remote_images, 0);
    }

    #[test]
    fn text_paragraphs_quotes_and_links() {
        let r = from_text(
            "Hi Matteo,\r\n\r\nsee https://shop.example/a?utm_source=x&id=4.\nThanks\n\n> earlier\n>> older\n",
        );
        assert_eq!(
            texts(&r),
            [
                "Hi Matteo,",
                "see https://shop.example/a?utm_source=x&id=4.\nThanks",
                "earlier",
                "older"
            ]
        );
        assert_eq!(r.blocks[2].quote, 1);
        assert_eq!(r.blocks[3].quote, 2);
        let link = r.blocks[1].spans[1].link.as_deref();
        assert_eq!(link, Some("https://shop.example/a?id=4"));
        assert_eq!(r.links_cleaned, 1);
    }

    #[test]
    fn scripts_styles_and_forms_have_nowhere_to_go() {
        let r = from_html(
            r#"<html><head><title>T</title><script>alert(1)</script>
            <style>p{color:red}</style></head><body>
            <p onclick="x()">Hello <b>there</b> <i>friend</i></p>
            <form action="https://evil.example"><input value="pw"><button>Send</button></form>
            <iframe src="https://evil.example"></iframe>
            <a href="javascript:alert(1)">click</a></body></html>"#,
        );
        assert_eq!(texts(&r), ["Hello there friend", "Send", "click"]);
        let hello = &r.blocks[0].spans;
        assert_eq!(hello.len(), 4);
        assert!(hello[1].bold && hello[3].italic);
        assert_eq!(r.blocks[2].spans[0].link, None);
    }

    #[test]
    fn remote_images_wait_and_pixels_are_stopped() {
        let r = from_html(
            r#"<h1>New autumn arrivals</h1>
            <a href="https://bottegalume.example/collection?utm_campaign=autumn&utm_medium=email">
              <img src="https://cdn.bottegalume.example/hero.jpg" alt="Living room" width="600" height="300"></a>
            <img src="https://lume-mail.example/o.gif">
            <img src="https://cdn.example/x.png" width="1" height="1">
            <img src="https://cdn.example/y.png" style="display:none">
            <link rel="stylesheet" href="https://fonts.lume-cdn.example/css2?family=X">
            <p>Hi Matteo</p>"#,
        );
        assert_eq!(r.remote_images, 1);
        assert_eq!(r.links_cleaned, 1);
        assert_eq!(r.blocks[0].kind, BlockKind::Heading);
        let hero = r.blocks[1].image.as_ref().unwrap();
        assert_eq!(hero.url, "https://cdn.bottegalume.example/hero.jpg");
        assert_eq!((hero.width, hero.height), (Some(600), Some(300)));
        assert_eq!(
            hero.link.as_deref(),
            Some("https://bottegalume.example/collection")
        );
        assert_eq!(texts(&r).last().unwrap(), "Hi Matteo");
        let kinds: Vec<(TrackerKind, &str, u32)> = r
            .trackers
            .iter()
            .map(|t| (t.kind, t.host.as_str(), t.count))
            .collect();
        assert_eq!(
            kinds,
            [
                (TrackerKind::Font, "fonts.lume-cdn.example", 1),
                (TrackerKind::Pixel, "lume-mail.example", 1),
                (TrackerKind::Pixel, "cdn.example", 2),
            ]
        );
    }

    #[test]
    fn layout_tables_lists_and_quotes() {
        let r = from_html(
            r#"<table><tr><td>One</td><td>Two&nbsp;cols</td></tr></table>
            <ol start="3"><li>third</li><li>fourth<ul><li>inner</li></ul></li></ol>
            <blockquote><p>quoted<br>  line</p></blockquote>
            <hr><hr><pre>  keep   spaces</pre>
            <span style="display:none">preheader&zwnj;&zwnj;</span>"#,
        );
        assert_eq!(
            texts(&r),
            [
                "One",
                "Two cols",
                "third",
                "fourth",
                "inner",
                "quoted\nline",
                "",
                "  keep   spaces"
            ]
        );
        let markers: Vec<&str> = r.blocks.iter().map(|b| b.marker.as_str()).collect();
        assert_eq!(&markers[2..5], ["3.", "4.", "•"]);
        assert_eq!(r.blocks[4].level, 2);
        assert_eq!(r.blocks[5].quote, 1);
        assert_eq!(r.blocks[6].kind, BlockKind::Rule);
        assert_eq!(r.blocks[7].kind, BlockKind::Code);
    }

    #[test]
    fn links_that_lie_are_flagged() {
        let r = from_html(
            r#"<p><a href="https://login.bank-secure.example/x">www.mybank.it</a>
            <a href="https://www.mybank.it/login">mybank.it</a>
            <a href="https://evil.example">Sign in</a></p>"#,
        );
        let spans: Vec<(&str, bool)> = r.blocks[0]
            .spans
            .iter()
            .filter(|s| s.link.is_some())
            .map(|s| (s.text.as_str(), s.suspicious))
            .collect();
        assert_eq!(
            spans,
            [
                ("www.mybank.it", true),
                ("mybank.it", false),
                ("Sign in", false)
            ]
        );
        assert_eq!(site("a.b.bank.co.uk"), "bank.co.uk");
        assert_eq!(shown_host("v1.2"), None);
    }

    #[test]
    fn options_turn_protections_off() {
        let html = r#"<a href="https://evil.example/?utm_source=x">www.mybank.it</a>
            <img src="https://t.example/o.gif" width="1" height="1">"#;
        let on = from_html(html);
        assert_eq!(
            (on.links_cleaned, on.suspicious_links, on.remote_images),
            (1, 1, 0)
        );
        let off = readable_with(
            "",
            Some(html),
            Options {
                stop_pixels: false,
                clean_links: false,
                warn_links: false,
            },
        );
        assert_eq!(
            (off.links_cleaned, off.suspicious_links, off.remote_images),
            (0, 0, 1)
        );
        assert!(off.trackers.is_empty());
        let link = off.blocks[0].spans[0].link.as_deref();
        assert_eq!(link, Some("https://evil.example/?utm_source=x"));
        assert!(!off.blocks[0].spans[0].suspicious);
    }

    #[test]
    fn embedded_images_and_plain_text() {
        let r = from_html(
            r#"<p>Logo</p><img alt="logo" src="data:image/png;base64,iVBORw0KGgo="><p>Bye</p>"#,
        );
        assert_eq!(
            r.blocks[1].image.as_ref().unwrap().data.as_deref(),
            Some(&b"\x89PNG\r\n\x1a\n"[..])
        );
        assert_eq!(r.remote_images, 0);
        assert_eq!(plain_text(&r), "Logo\n\nBye");
    }

    #[test]
    fn a_pathological_nesting_stops_before_the_stack_does() {
        // 200 levels of divs: deep content is dropped, nothing overflows.
        let mut html = String::new();
        for _ in 0..200 {
            html.push('<');
            html.push_str("div>");
        }
        html.push_str("innermost");
        for _ in 0..200 {
            html.push_str("</div>");
        }
        let before = from_html(&html);
        assert_eq!(plain_text(&before), "");
        // Below the cap the text survives.
        let mut ok = String::new();
        for _ in 0..50 {
            ok.push('<');
            ok.push_str("div>");
        }
        ok.push_str("innermost");
        for _ in 0..50 {
            ok.push_str("</div>");
        }
        assert_eq!(plain_text(&from_html(&ok)), "innermost");
    }

    #[test]
    fn link_hosts_follow_uts46_like_a_browser() {
        // The other dots UTS #46 reads as ".".
        for host in [
            "example\u{3002}com",
            "example\u{FF0E}com",
            "example\u{FF61}com",
        ] {
            assert_eq!(
                link_host_ascii(host).as_deref(),
                Some("example.com"),
                "{host}"
            );
        }
        // Full-width ASCII letters and digits.
        assert_eq!(
            link_host_ascii("\u{FF45}\u{FF58}\u{FF41}\u{FF4D}\u{FF50}\u{FF4C}\u{FF45}.com")
                .as_deref(),
            Some("example.com")
        );
        assert_eq!(
            link_host_ascii("\u{FF22}\u{FF21}\u{FF2E}\u{FF2B}\u{FF11}.example").as_deref(),
            Some("bank1.example")
        );
        // Mixed-case IDN, in Unicode or in punycode.
        for host in [
            "B\u{dc}cher.DE",
            "b\u{dc}CHER.de",
            "XN--BCHER-KVA.DE",
            "bücher.de",
        ] {
            assert_eq!(
                link_host_ascii(host).as_deref(),
                Some("xn--bcher-kva.de"),
                "{host}"
            );
        }
        // A character UTS #46 drops (a soft hyphen) and one it maps (ß stays
        // ß, as browsers keep it: non-transitional).
        assert_eq!(
            link_host_ascii("exam\u{AD}ple.com").as_deref(),
            Some("example.com")
        );
        assert_eq!(link_host_ascii("faß.de").as_deref(), Some("xn--fa-hia.de"));
        // The hosts of #99 don't change.
        assert_eq!(
            link_host_ascii("раураl.com").as_deref(),
            Some("xn--l-7sba6dbr.com")
        );
        assert_eq!(
            link_host_ascii("shop.example").as_deref(),
            Some("shop.example")
        );
        assert_eq!(
            link_host_ascii("evil.example.").as_deref(),
            Some("evil.example.")
        );
        assert_eq!(
            link_host_ascii("192.168.1.10").as_deref(),
            Some("192.168.1.10")
        );
        assert_eq!(link_host_ascii("FE80::1").as_deref(), Some("[fe80::1]"));
        assert_eq!(link_host_ascii("[::1]").as_deref(), Some("[::1]"));
        // Not a host a browser opens.
        for host in [
            "bank.example@evil.example",
            "a%ff.example",
            "",
            "a b.example",
        ] {
            assert_eq!(link_host_ascii(host), None, "{host:?}");
        }
    }

    #[test]
    fn a_link_text_with_another_dot_is_the_same_site() {
        assert!(!suspicious("example\u{3002}com", "https://example.com/"));
        assert!(!suspicious("\u{FF45}xample.com", "https://EXAMPLE.com/"));
        assert!(suspicious("bank\u{FF0E}example", "https://evil.example/"));
    }

    #[test]
    fn a_link_host_is_percent_decoded_only_once() {
        // The app decodes the host's percent-encoding before asking: a `%`
        // left is one the browser keeps, never a second escape.
        for host in [
            "bank%2eexample",
            "bank%252eexample",
            "a%ff.example",
            "%41.example",
        ] {
            assert_eq!(link_host_ascii(host), None, "{host}");
        }
    }

    #[test]
    fn a_link_text_ending_in_a_dot_is_an_address() {
        for text in [
            "paypal.com.",
            "paypal\u{3002}com\u{3002}",
            "www.paypal.com.",
        ] {
            assert!(suspicious(text, "https://evil.com/"), "{text}");
            assert!(!suspicious(text, "https://paypal.com/"), "{text}");
        }
    }

    #[test]
    fn a_link_text_with_a_domain_before_an_at_is_suspicious() {
        for text in [
            "www.paypal.com@evil.com",
            "https://www.paypal.com@evil.com/login",
            "paypal.com@evil.com",
        ] {
            assert!(suspicious(text, "https://evil.com/"), "{text}");
        }
        // An address as the text of its own mailto, or of its site.
        assert!(!suspicious("anna@example.org", "mailto:anna@example.org"));
        assert!(!suspicious(
            "anna.rossi@example.org",
            "mailto:anna.rossi@example.org"
        ));
        assert!(!suspicious("anna@example.org", "https://example.org/"));
        assert!(suspicious("anna@example.org", "https://evil.com/"));
    }

    #[test]
    fn a_person_s_address_is_not_a_domain_before_an_at() {
        // A person's name with a dot, as the text of their company's site.
        assert!(!suspicious(
            "john.smith@company.com",
            "https://company.com/"
        ));
        assert!(!suspicious(
            "mario.rossi@azienda.it",
            "https://www.azienda.it/"
        ));
        assert!(!suspicious(
            "john.smith@company.com",
            "mailto:john.smith@company.com"
        ));
        assert!(!suspicious(
            "mario.rossi@azienda.it",
            "mailto:mario.rossi@azienda.it"
        ));
        // Still a domain: a scheme, "www.", or a common ending.
        assert!(suspicious(
            "https://john.smith@company.com/",
            "https://company.com/"
        ));
        assert!(suspicious(
            "www.company.example@evil.com",
            "https://evil.com/"
        ));
        assert!(suspicious("paypal.IT@evil.com", "https://evil.com/"));
    }

    #[test]
    fn an_encoded_at_in_a_link_text_is_read_as_an_at() {
        assert!(suspicious("www.paypal.com%40evil.com", "https://evil.com/"));
        assert!(suspicious(
            "paypal.com%40evil.com",
            "https://evil.com/login"
        ));
        assert!(!suspicious(
            "john.smith%40company.com",
            "https://company.com/"
        ));
        // Other escapes stay as written.
        assert_eq!(decode_at("a%41b%40c%4"), "a%41b@c%4");
    }
}
