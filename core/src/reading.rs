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
        let mut block = Block::new(BlockKind::Paragraph);
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
        while let Some(r) = rest.trim_start().strip_prefix('>') {
            depth = depth.saturating_add(1);
            rest = r.strip_prefix(' ').unwrap_or(r);
        }
        if rest.trim().is_empty() {
            flush(&mut lines, &mut out);
            continue;
        }
        if lines.first().is_some_and(|(d, _)| *d != depth) {
            flush(&mut lines, &mut out);
        }
        lines.push((depth, rest));
    }
    flush(&mut lines, &mut out);
    out
}

/// Words that start with http:// or https:// become (cleaned) links.
fn autolink(text: &str, clean: bool, cleaned: &mut u32) -> Vec<Span> {
    let mut spans = Vec::new();
    let mut plain = String::new();
    let mut rest = text;
    while let Some(start) = rest
        .find("http://")
        .into_iter()
        .chain(rest.find("https://"))
        .min()
    {
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
                    text: word.to_owned(),
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
    if t.is_empty() || t.contains(char::is_whitespace) || !t.contains('.') {
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
    let tld = host.rsplit('.').next()?;
    (tld.len() >= 2 && tld.chars().all(|c| c.is_ascii_alphabetic())).then(|| host.to_owned())
}

pub(crate) fn suspicious(text: &str, link: &str) -> bool {
    let Some(shown) = shown_host(text) else {
        return false;
    };
    let Some(real) = Url::parse(link)
        .ok()
        .and_then(|u| u.host_str().map(str::to_owned))
    else {
        return false;
    };
    site(&shown) != site(&real)
}

/// Elements whose content is never shown.
const SKIPPED: &[&str] = &[
    "head", "script", "style", "title", "noscript", "template", "iframe", "object", "embed", "svg",
    "math", "canvas", "audio", "video", "select", "textarea", "input", "map", "frame", "frameset",
    "applet", "meta", "base",
];

/// Elements that start a new block.
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
}

struct Walker {
    options: Options,
    out: Readable,
    current: Vec<Span>,
    current_style: Style,
    heading: u8,
    marker: Option<String>,
    link: Option<(String, bool)>,
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
        } else if src.len() > 4 && src[..4].eq_ignore_ascii_case("cid:") {
            // Inside the message: no request leaves the device.
            if tiny || hidden(el) {
                return;
            }
            image.cid = Some(src[4..].trim_matches(['<', '>']).trim().to_owned());
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
            self.marker = Some(match el.parent().and_then(ElementRef::wrap) {
                Some(p) if p.value().name() == "ol" => {
                    let start: usize = p
                        .value()
                        .attr("start")
                        .and_then(|s| s.parse().ok())
                        .unwrap_or(1);
                    let index = p
                        .children()
                        .filter_map(ElementRef::wrap)
                        .take_while(|c| c.id() != el.id())
                        .filter(|c| c.value().name() == "li")
                        .count();
                    format!("{}.", start + index)
                }
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

        for child in el.children() {
            match child.value() {
                Node::Text(t) => self.push_text(t, style),
                Node::Element(_) => {
                    if let Some(c) = ElementRef::wrap(child) {
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
}
