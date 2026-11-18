//! Sender pictures for companies: the verified logo a domain publishes
//! (BIMI), or its website's icon, as in `PicturesToApprove`.
//!
//! A logo stands for one message, not for a domain: it shows only beside
//! a message whose DMARC check passed (see `sender_auth::Checked`), from
//! a domain whose DMARC policy rejects or quarantines what fails, and it
//! is looked up only once such a message has been opened. The lookup is
//! on the organization's domain, never the full sender domain, so a
//! sender can't give each recipient a subdomain of their own and learn
//! from the DNS query when that person's mail was shown.
//!
//! No Verified Mark Certificate is required: checking one needs the mark
//! authorities' roots and their logotype extension, and what it adds (that
//! a trademark office registered the picture) does not change what the
//! logo can claim here, which is only "this message really comes from
//! this domain". A look-alike domain is caught by the impostor check,
//! and a message it flags never gets a logo.
//!
//! A domain is looked up once and kept on the device. The requests say as
//! little as possible: no cookies, no referrer, a generic user agent.
//! People's own addresses at mail providers (gmail.com, libero.it…) never
//! get a picture from here: the provider's logo would stand for every one
//! of them.

use std::io::Cursor;
use std::time::Duration;

/// Logos and icons are drawn at this size, in pixels, for every screen.
pub const SIZE: u32 = 96;

/// A looked-up domain is kept this long, found or not.
pub const KEEP_SECS: i64 = 30 * 24 * 3600;

/// A domain with nothing is asked again sooner.
pub const RETRY_SECS: i64 = 7 * 24 * 3600;

/// BIMI logos are small by rule (32 KB); a little slack.
const MAX_SVG: usize = 64 * 1024;
const MAX_ICON: usize = 512 * 1024;
const MAX_PAGE: usize = 512 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// The domain's verified logo.
    Logo,
    /// Its website's icon.
    Icon,
    /// Nothing to show: the letter stays.
    None,
}

impl Kind {
    pub fn tag(self) -> &'static str {
        match self {
            Kind::Logo => "logo",
            Kind::Icon => "icon",
            Kind::None => "none",
        }
    }

    pub fn from_tag(s: &str) -> Kind {
        match s {
            "logo" => Kind::Logo,
            "icon" => Kind::Icon,
            _ => Kind::None,
        }
    }
}

/// What a lookup found: a square PNG of [`SIZE`], or nothing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Picture {
    pub kind: Kind,
    pub png: Vec<u8>,
}

impl Picture {
    pub fn none() -> Picture {
        Picture {
            kind: Kind::None,
            png: Vec::new(),
        }
    }
}

/// Mail providers whose addresses belong to people, not to the provider.
const PROVIDERS: &[&str] = &[
    "gmail.com",
    "googlemail.com",
    "outlook.com",
    "outlook.it",
    "hotmail.com",
    "hotmail.it",
    "live.com",
    "live.it",
    "msn.com",
    "yahoo.com",
    "yahoo.it",
    "ymail.com",
    "icloud.com",
    "me.com",
    "mac.com",
    "aol.com",
    "gmx.com",
    "gmx.net",
    "gmx.de",
    "web.de",
    "proton.me",
    "protonmail.com",
    "pm.me",
    "tutanota.com",
    "tuta.io",
    "zoho.com",
    "yandex.com",
    "yandex.ru",
    "mail.ru",
    "fastmail.com",
    "libero.it",
    "virgilio.it",
    "tiscali.it",
    "alice.it",
    "tim.it",
    "poste.it",
    "tin.it",
    "fastwebnet.it",
    "email.it",
    "inwind.it",
    "iol.it",
    "aruba.it",
    "pec.it",
    "legalmail.it",
    "postecert.it",
    "arubapec.it",
];

/// The domain a sender's picture is looked up for, or none for people at
/// mail providers and for addresses that aren't one.
pub fn domain_for(email: &str) -> Option<String> {
    let (_, domain) = email.trim().rsplit_once('@')?;
    let domain = domain.trim_end_matches('.').to_ascii_lowercase();
    let valid = domain.contains('.')
        && domain
            .split('.')
            .all(|l| !l.is_empty() && l.chars().all(|c| c.is_ascii_alphanumeric() || c == '-'));
    if !valid {
        return None;
    }
    let org = organizational(&domain);
    if PROVIDERS.contains(&org.as_str()) || PROVIDERS.contains(&domain.as_str()) {
        return None;
    }
    Some(domain)
}

/// The registered domain under a subdomain: news.shop.it → shop.it,
/// mail.bank.co.uk → bank.co.uk.
pub fn organizational(domain: &str) -> String {
    let labels: Vec<&str> = domain.split('.').collect();
    let n = labels.len();
    if n <= 2 {
        return domain.to_owned();
    }
    // A country code under a second level such as co., com., gov.
    let second = labels[n - 2];
    let take = if labels[n - 1].len() == 2
        && ["co", "com", "net", "org", "gov", "ac", "edu"].contains(&second)
    {
        3
    } else {
        2
    };
    labels[n - take.min(n)..].join(".")
}

/// The logo address of a BIMI record: `v=BIMI1; l=https://…/logo.svg`.
pub fn bimi_logo(record: &str) -> Option<String> {
    let mut parts = record.split(';').map(str::trim);
    if !parts.next()?.eq_ignore_ascii_case("v=BIMI1") {
        return None;
    }
    parts.find_map(|p| {
        let (k, v) = p.split_once('=')?;
        let v = v.trim();
        (k.trim().eq_ignore_ascii_case("l") && v.starts_with("https://")).then(|| v.to_owned())
    })
}

/// The icons a page's head names, best first: Apple's touch icon, then
/// the largest declared icon, SVG before small bitmaps.
pub fn icon_links(html: &str, base: &url::Url) -> Vec<url::Url> {
    let page = scraper::Html::parse_document(html);
    let Ok(links) = scraper::Selector::parse("link[rel][href]") else {
        return Vec::new();
    };
    let mut found: Vec<(u32, url::Url)> = page
        .select(&links)
        .filter_map(|l| {
            let rel = l.value().attr("rel")?.to_ascii_lowercase();
            let rels: Vec<&str> = rel.split_whitespace().collect();
            let touch = rels.iter().any(|r| r.starts_with("apple-touch-icon"));
            if !touch && !rels.contains(&"icon") {
                return None;
            }
            let href = base.join(l.value().attr("href")?).ok()?;
            if href.scheme() != "https" {
                return None;
            }
            let svg =
                href.path().ends_with(".svg") || l.value().attr("type") == Some("image/svg+xml");
            let size = l
                .value()
                .attr("sizes")
                .and_then(|s| s.split(['x', 'X']).next()?.trim().parse::<u32>().ok())
                .unwrap_or(if touch { 180 } else { 16 });
            let score = if touch {
                10_000 + size
            } else if svg {
                5_000
            } else {
                size
            };
            Some((score, href))
        })
        .collect();
    found.sort_by_key(|f| std::cmp::Reverse(f.0));
    found.into_iter().map(|(_, u)| u).collect()
}

/// An SVG drawn into a square PNG of [`SIZE`], centered on white so a
/// logo never floats. None when it isn't one.
pub fn svg_to_png(svg: &[u8]) -> Option<Vec<u8>> {
    let tree = resvg::usvg::Tree::from_data(svg, &resvg::usvg::Options::default()).ok()?;
    let size = tree.size();
    if size.width() <= 0.0 || size.height() <= 0.0 {
        return None;
    }
    let mut pixmap = resvg::tiny_skia::Pixmap::new(SIZE, SIZE)?;
    pixmap.fill(resvg::tiny_skia::Color::WHITE);
    let scale = SIZE as f32 / size.width().max(size.height());
    let dx = (SIZE as f32 - size.width() * scale) / 2.0;
    let dy = (SIZE as f32 - size.height() * scale) / 2.0;
    let transform = resvg::tiny_skia::Transform::from_scale(scale, scale).post_translate(dx, dy);
    resvg::render(&tree, transform, &mut pixmap.as_mut());
    pixmap.encode_png().ok()
}

/// A bitmap icon (PNG, JPEG, ICO, GIF, WebP) as a square PNG of [`SIZE`]
/// on white. None for what isn't one, and for tiny icons that would blur.
pub fn bitmap_to_png(bytes: &[u8]) -> Option<Vec<u8>> {
    let image = image::load_from_memory(bytes).ok()?;
    if image.width() < 32 || image.height() < 32 {
        return None;
    }
    let fitted = image.resize(SIZE, SIZE, image::imageops::FilterType::Lanczos3);
    let mut canvas = image::RgbaImage::from_pixel(SIZE, SIZE, image::Rgba([255, 255, 255, 255]));
    let x = (SIZE - fitted.width()) / 2;
    let y = (SIZE - fitted.height()) / 2;
    image::imageops::overlay(&mut canvas, &fitted.to_rgba8(), x.into(), y.into());
    let mut out = Vec::new();
    image::DynamicImage::ImageRgba8(canvas)
        .write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png)
        .ok()?;
    Some(out)
}

fn client() -> Option<reqwest::Client> {
    crate::tls::http_client()
        .timeout(Duration::from_secs(10))
        .user_agent("Mozilla/5.0")
        .referer(false)
        .redirect(reqwest::redirect::Policy::limited(3))
        .build()
        .ok()
}

/// The body of an https address, up to `max` bytes.
async fn get(client: &reqwest::Client, url: url::Url, max: usize) -> Option<Vec<u8>> {
    if url.scheme() != "https" {
        return None;
    }
    let mut response = client.get(url).send().await.ok()?.error_for_status().ok()?;
    if response.content_length().is_some_and(|n| n as usize > max) {
        return None;
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await.ok()? {
        if bytes.len() + chunk.len() > max {
            return None;
        }
        bytes.extend_from_slice(&chunk);
    }
    Some(bytes)
}

/// The first TXT record at `name` that starts with `prefix`.
async fn txt_record(name: &str, prefix: &str) -> Option<String> {
    let resolver = hickory_resolver::Resolver::builder_tokio()
        .ok()?
        .build()
        .ok()?;
    let lookup = resolver.txt_lookup(format!("{name}."));
    let found = tokio::time::timeout(Duration::from_secs(4), lookup)
        .await
        .ok()?
        .ok()?;
    found.answers().iter().find_map(|r| match &r.data {
        hickory_resolver::proto::rr::RData::TXT(txt) => {
            let text: String = txt
                .txt_data
                .iter()
                .map(|d| String::from_utf8_lossy(d).into_owned())
                .collect();
            text.trim_start().starts_with(prefix).then_some(text)
        }
        _ => None,
    })
}

/// Whether a DMARC record (`v=DMARC1; p=reject; …`) keeps mail that fails
/// it from being delivered as is: `p` (or `sp`, for a subdomain's mail)
/// is quarantine or reject, for all of it (`pct` 100 or unset). BIMI asks
/// the same before a logo is shown.
pub fn dmarc_enforced(record: &str, subdomain: bool) -> bool {
    let mut parts = record.split(';').map(str::trim);
    if !parts
        .next()
        .is_some_and(|v| v.replace(' ', "").eq_ignore_ascii_case("v=DMARC1"))
    {
        return false;
    }
    let (mut p, mut sp, mut pct) = (None, None, 100u32);
    for part in parts {
        let Some((k, v)) = part.split_once('=') else {
            continue;
        };
        let v = v.trim().to_ascii_lowercase();
        match k.trim().to_ascii_lowercase().as_str() {
            "p" => p = Some(v),
            "sp" => sp = Some(v),
            "pct" => pct = v.parse().unwrap_or(0),
            _ => {}
        }
    }
    let policy = if subdomain { sp.or(p) } else { p };
    pct == 100 && matches!(policy.as_deref(), Some("quarantine" | "reject"))
}

/// The logo of the organization `domain` belongs to, from its BIMI record,
/// when its DMARC policy is enforced for `domain`'s mail.
pub async fn logo(domain: &str) -> Option<Vec<u8>> {
    let client = client()?;
    let org = organizational(domain);
    let dmarc = txt_record(&format!("_dmarc.{org}"), "v=DMARC1").await?;
    if !dmarc_enforced(&dmarc, org != domain) {
        return None;
    }
    let record = txt_record(&format!("default._bimi.{org}"), "v=BIMI1").await?;
    let url = url::Url::parse(&bimi_logo(&record)?).ok()?;
    let svg = get(&client, url, MAX_SVG).await?;
    svg_to_png(&svg)
}

/// The icon of the domain's website: what its home page names, else
/// /favicon.ico.
pub async fn icon(domain: &str) -> Option<Vec<u8>> {
    let client = client()?;
    let org = organizational(domain);
    let mut home = url::Url::parse(&format!("https://{org}/")).ok()?;
    let mut candidates = Vec::new();
    // Some sites answer only on www.
    for at in [format!("https://{org}/"), format!("https://www.{org}/")] {
        let Ok(url) = url::Url::parse(&at) else {
            continue;
        };
        if let Some(page) = get(&client, url.clone(), MAX_PAGE).await {
            candidates = icon_links(&String::from_utf8_lossy(&page), &url);
            home = url;
            break;
        }
    }
    if let Ok(ico) = home.join("/favicon.ico") {
        candidates.push(ico);
    }
    for url in candidates.into_iter().take(4) {
        let svg = url.path().ends_with(".svg");
        let Some(bytes) = get(&client, url, MAX_ICON).await else {
            continue;
        };
        let png = if svg || bytes.trim_ascii_start().starts_with(b"<") {
            svg_to_png(&bytes)
        } else {
            bitmap_to_png(&bytes)
        };
        if png.is_some() {
            return png;
        }
    }
    None
}

/// Looks the domain up for its website's icon (when those are on).
pub async fn look_up_icon(domain: &str, icons: bool) -> Picture {
    if icons {
        if let Some(png) = icon(domain).await {
            return Picture {
                kind: Kind::Icon,
                png,
            };
        }
    }
    Picture::none()
}

/// Looks the organization of `domain` up for its logo (see [`logo`]).
pub async fn look_up_logo(domain: &str) -> Picture {
    match logo(domain).await {
        Some(png) => Picture {
            kind: Kind::Logo,
            png,
        },
        None => Picture::none(),
    }
}

/// The key a logo is kept under: one per organization, apart from icons.
pub fn logo_key(domain: &str) -> String {
    format!("bimi:{}", organizational(domain))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn people_at_mail_providers_get_no_picture() {
        assert_eq!(domain_for("giulia@gmail.com"), None);
        assert_eq!(domain_for("luca.bianchi@libero.it"), None);
        assert_eq!(domain_for("Teo@iCloud.com"), None);
        assert_eq!(domain_for("not an address"), None);
        assert_eq!(domain_for("x@localhost"), None);
        assert_eq!(
            domain_for("info@News.Ferrovia-Rapida.it").as_deref(),
            Some("news.ferrovia-rapida.it")
        );
    }

    #[test]
    fn the_registered_domain_under_a_subdomain() {
        assert_eq!(organizational("news.shop.it"), "shop.it");
        assert_eq!(organizational("mail.bank.co.uk"), "bank.co.uk");
        assert_eq!(organizational("shop.it"), "shop.it");
        assert_eq!(organizational("a.b.example.com"), "example.com");
    }

    #[test]
    fn a_bimi_record_names_its_logo() {
        assert_eq!(
            bimi_logo("v=BIMI1; l=https://example.com/logo.svg; a=https://example.com/vmc.pem")
                .as_deref(),
            Some("https://example.com/logo.svg")
        );
        assert_eq!(bimi_logo("v=BIMI1; l=http://example.com/logo.svg"), None);
        assert_eq!(bimi_logo("v=BIMI1; l="), None);
        assert_eq!(bimi_logo("v=spf1 include:x"), None);
    }

    #[test]
    fn a_logo_needs_an_enforced_dmarc_policy() {
        assert!(dmarc_enforced(
            "v=DMARC1; p=reject; rua=mailto:d@shop.it",
            false
        ));
        assert!(dmarc_enforced("v=DMARC1; p=quarantine", false));
        assert!(!dmarc_enforced("v=DMARC1; p=none", false));
        assert!(!dmarc_enforced("v=DMARC1; p=reject; pct=50", false));
        assert!(!dmarc_enforced("v=spf1 -all", false));
        // A subdomain follows sp when there is one.
        assert!(!dmarc_enforced("v=DMARC1; p=reject; sp=none", true));
        assert!(dmarc_enforced("v=DMARC1; p=reject; sp=none", false));
        assert!(dmarc_enforced("v=DMARC1; p=none; sp=reject", true));
        // One logo per organization, whatever subdomain sent.
        assert_eq!(logo_key("x7f3.news.shop.it"), "bimi:shop.it");
        assert_eq!(logo_key("shop.it"), "bimi:shop.it");
    }

    #[test]
    fn the_touch_icon_comes_first_then_the_largest() {
        let base = url::Url::parse("https://shop.example/").unwrap();
        let html = r#"<html><head>
            <link rel="icon" href="/favicon-16.png" sizes="16x16">
            <link rel="icon" href="/favicon-64.png" sizes="64x64">
            <link rel="stylesheet" href="/style.css">
            <link rel="apple-touch-icon" href="/touch.png">
            <link rel="shortcut icon" href="http://shop.example/insecure.ico">
        </head></html>"#;
        let links: Vec<String> = icon_links(html, &base)
            .into_iter()
            .map(|u| u.path().to_owned())
            .collect();
        assert_eq!(links, ["/touch.png", "/favicon-64.png", "/favicon-16.png"]);
    }

    #[test]
    fn an_svg_logo_becomes_a_square_png() {
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 10"><rect width="20" height="10" fill="#C8102E"/></svg>"##;
        let png = svg_to_png(svg).unwrap();
        let image = image::load_from_memory(&png).unwrap().to_rgba8();
        assert_eq!((image.width(), image.height()), (SIZE, SIZE));
        // Wider than tall: white above, the logo's red in the middle.
        assert_eq!(image.get_pixel(48, 2).0, [255, 255, 255, 255]);
        assert_eq!(image.get_pixel(48, 48).0, [0xC8, 0x10, 0x2E, 255]);
        assert_eq!(svg_to_png(b"<html>not a picture</html>"), None);
    }

    #[test]
    fn tiny_icons_are_left_out() {
        let mut small = Vec::new();
        image::RgbaImage::from_pixel(16, 16, image::Rgba([1, 2, 3, 255]))
            .write_to(&mut Cursor::new(&mut small), image::ImageFormat::Png)
            .unwrap();
        assert_eq!(bitmap_to_png(&small), None);
        let mut big = Vec::new();
        image::RgbaImage::from_pixel(64, 64, image::Rgba([1, 2, 3, 255]))
            .write_to(&mut Cursor::new(&mut big), image::ImageFormat::Png)
            .unwrap();
        let png = bitmap_to_png(&big).unwrap();
        let image = image::load_from_memory(&png).unwrap();
        assert_eq!((image.width(), image.height()), (SIZE, SIZE));
    }
}
