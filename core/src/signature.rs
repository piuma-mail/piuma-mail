//! Signatures: what one says, and how it is written into an email, as
//! HTML for most readers and as plain text for the rest.
//!
//! The four templates are those of the Signatures canvas: Minimal,
//! Classic, Monogram and With logo. The HTML uses inline styles and no
//! remote images, so it arrives the same everywhere, even where images are
//! blocked; a logo travels inside the message.

use crate::model::AccountId;
use crate::tokens_g::{MUTED, ON_ACCENT, SIGNATURE_ACCENTS, TEXT};

/// Largest logo kept, in bytes, after shrinking.
pub const LOGO_MAX_BYTES: usize = 40 * 1024;

/// The logo's Content-ID inside the message.
pub const LOGO_CID: &str = "signature-logo@piuma.mail";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Template {
    Minimal,
    #[default]
    Classic,
    Monogram,
    Logo,
}

impl Template {
    pub fn tag(self) -> &'static str {
        match self {
            Template::Minimal => "minimal",
            Template::Classic => "classic",
            Template::Monogram => "monogram",
            Template::Logo => "logo",
        }
    }

    pub fn from_tag(tag: &str) -> Self {
        match tag {
            "minimal" => Template::Minimal,
            "monogram" => Template::Monogram,
            "logo" => Template::Logo,
            _ => Template::Classic,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Accent {
    #[default]
    Blue,
    Black,
    Terracotta,
}

impl Accent {
    pub fn tag(self) -> &'static str {
        match self {
            Accent::Blue => "blue",
            Accent::Black => "black",
            Accent::Terracotta => "terracotta",
        }
    }

    pub fn from_tag(tag: &str) -> Self {
        match tag {
            "black" => Accent::Black,
            "terracotta" => Accent::Terracotta,
            _ => Accent::Blue,
        }
    }

    fn hex(self) -> &'static str {
        SIGNATURE_ACCENTS
            .iter()
            .find(|(name, _)| *name == self.tag())
            .map(|(_, hex)| *hex)
            .unwrap_or(TEXT)
    }
}

/// A logo image, already small enough to send.
#[derive(Clone, PartialEq, Eq)]
pub struct Logo {
    /// "image/png" or "image/jpeg".
    pub mime: String,
    pub data: Vec<u8>,
}

impl std::fmt::Debug for Logo {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Logo({}, {} bytes)", self.mime, self.data.len())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Signature {
    /// 0 until stored.
    pub id: i64,
    pub account: AccountId,
    /// What the person calls it: "Work", "Short".
    pub label: String,
    pub template: Template,
    pub name: String,
    pub role: String,
    pub company: String,
    pub phone: String,
    pub website: String,
    pub accent: Accent,
    pub logo: Option<Logo>,
    /// The account's signature for new emails.
    pub for_new: bool,
    /// The account's signature for replies and forwards.
    pub for_replies: bool,
}

impl Signature {
    /// Its lines, as both versions show them: name, then the rest.
    pub fn lines(&self) -> Vec<String> {
        let join = |parts: &[&str]| {
            parts
                .iter()
                .map(|p| p.trim())
                .filter(|p| !p.is_empty())
                .collect::<Vec<_>>()
                .join(" · ")
        };
        let role = join(&[&self.role, &self.company]);
        let contact = join(&[&self.phone, &self.website]);
        let mut lines = vec![self.name.trim().to_string(), role];
        match self.template {
            Template::Minimal => {}
            Template::Classic | Template::Logo => lines.push(contact),
            Template::Monogram => lines.push(self.website.trim().to_string()),
        }
        lines.retain(|l| !l.is_empty());
        lines
    }

    /// The plain-text version, after the usual "-- " line.
    pub fn text(&self) -> String {
        let lines = self.lines();
        if lines.is_empty() {
            return String::new();
        }
        format!("-- \n{}", lines.join("\n"))
    }

    /// "Matteo Neri" → "MN".
    pub fn monogram(&self) -> String {
        let words: Vec<&str> = self.name.split_whitespace().collect();
        let first = |w: &str| w.chars().next().map(|c| c.to_uppercase().to_string());
        match words.as_slice() {
            [] => String::new(),
            [one] => first(one).unwrap_or_default(),
            [a, .., b] => format!(
                "{}{}",
                first(a).unwrap_or_default(),
                first(b).unwrap_or_default()
            ),
        }
    }

    /// The HTML version, a block to put after the message.
    pub fn html(&self) -> String {
        let lines = self.lines();
        if lines.is_empty() {
            return String::new();
        }
        let accent = self.accent.hex();
        let link = if self.accent == Accent::Black {
            TEXT
        } else {
            accent
        };
        let website = self.website.trim();
        let line = |text: &str| {
            let mut html = escape(text);
            if !website.is_empty() {
                let shown = escape(website);
                if let Some(at) = html.rfind(&shown) {
                    let href = escape(&href_for(website));
                    html.replace_range(
                        at..at + shown.len(),
                        &format!(
                            "<a href=\"{href}\" style=\"color:{link};font-weight:500;text-decoration:none\">{shown}</a>"
                        ),
                    );
                }
            }
            html
        };
        let name = format!(
            "<strong style=\"font-weight:600;font-size:15px;color:{TEXT}\">{}</strong>",
            escape(&lines[0])
        );
        let rest: String = lines[1..]
            .iter()
            .map(|l| format!("<br><span style=\"color:{MUTED}\">{}</span>", line(l)))
            .collect();
        let font = "font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;line-height:1.45";
        let body = match self.template {
            Template::Minimal => format!("<div style=\"{font}\">{name}{rest}</div>"),
            Template::Classic => format!(
                "<div style=\"{font}\"><div style=\"width:28px;height:2px;background:{accent};margin-bottom:8px\"></div>{name}{rest}</div>"
            ),
            Template::Monogram => format!(
                "<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" style=\"{font}\"><tr>\
                 <td style=\"width:48px;height:48px;border-radius:10px;background:{accent};color:{ON_ACCENT};text-align:center;vertical-align:middle;font-weight:600;font-size:16px\">{}</td>\
                 <td style=\"padding-left:14px;vertical-align:middle\">{name}{rest}</td></tr></table>",
                escape(&self.monogram())
            ),
            Template::Logo => {
                let logo = match &self.logo {
                    Some(_) => format!(
                        "<img src=\"cid:{LOGO_CID}\" alt=\"{}\" height=\"36\" style=\"display:block;height:36px;border:0;margin-bottom:10px\">",
                        escape(if self.company.trim().is_empty() { &lines[0] } else { self.company.trim() })
                    ),
                    None => String::new(),
                };
                format!("<div style=\"{font}\">{logo}{name}{rest}</div>")
            }
        };
        format!("<div class=\"piuma-signature\" style=\"margin-top:18px\">{body}</div>")
    }
}

fn href_for(website: &str) -> String {
    if website.contains("://") {
        website.to_string()
    } else {
        format!("https://{website}")
    }
}

/// Escapes text for HTML.
pub fn escape(text: &str) -> String {
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

/// Splits a draft into the person's own text and the quoted message at
/// its end: the "On …, … wrote:" line and the "> " lines after it.
pub fn split_quote(body: &str) -> (&str, &str) {
    let lines: Vec<&str> = body.split_inclusive('\n').collect();
    let mut start = lines.len();
    while start > 0 && lines[start - 1].starts_with('>') {
        start -= 1;
    }
    if start == lines.len() {
        return (body, "");
    }
    // The line that introduces the quote, if there is one.
    if start > 0 && lines[start - 1].trim_end().ends_with(':') {
        start -= 1;
    }
    let at: usize = lines[..start].iter().map(|l| l.len()).sum();
    body.split_at(at)
}

/// Plain text as simple HTML paragraphs, for the HTML part of an email.
pub fn text_to_html(text: &str) -> String {
    let text = text.replace("\r\n", "\n");
    let mut out = String::new();
    for para in text.split("\n\n") {
        let lines: Vec<String> = para.split('\n').map(escape).collect();
        out.push_str("<p style=\"margin:0 0 1em\">");
        out.push_str(&lines.join("<br>"));
        out.push_str("</p>");
    }
    out
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum LogoError {
    #[error("this file is not a PNG or JPEG image")]
    NotAnImage,
    #[error("this logo stays over 40 KB even when shrunk")]
    TooBig,
}

/// Makes a logo small enough to travel in every email: at most 480×144
/// pixels (twice what is shown) and 40 KB, as PNG, or JPEG if that is the
/// only way to fit.
pub fn shrink_logo(data: &[u8]) -> Result<Logo, LogoError> {
    use image::ImageFormat;
    let format = image::guess_format(data).map_err(|_| LogoError::NotAnImage)?;
    if !matches!(format, ImageFormat::Png | ImageFormat::Jpeg) {
        return Err(LogoError::NotAnImage);
    }
    let mime = if format == ImageFormat::Png {
        "image/png"
    } else {
        "image/jpeg"
    };
    if data.len() <= LOGO_MAX_BYTES {
        return Ok(Logo {
            mime: mime.into(),
            data: data.to_vec(),
        });
    }
    let img = image::load_from_memory(data).map_err(|_| LogoError::NotAnImage)?;
    let mut size = (480u32, 144u32);
    for _ in 0..5 {
        let small = img.resize(size.0, size.1, image::imageops::FilterType::Lanczos3);
        let mut png = Vec::new();
        small
            .write_to(&mut std::io::Cursor::new(&mut png), ImageFormat::Png)
            .map_err(|_| LogoError::NotAnImage)?;
        if png.len() <= LOGO_MAX_BYTES {
            return Ok(Logo {
                mime: "image/png".into(),
                data: png,
            });
        }
        let mut jpeg = Vec::new();
        small
            .to_rgb8()
            .write_to(&mut std::io::Cursor::new(&mut jpeg), ImageFormat::Jpeg)
            .map_err(|_| LogoError::NotAnImage)?;
        if jpeg.len() <= LOGO_MAX_BYTES {
            return Ok(Logo {
                mime: "image/jpeg".into(),
                data: jpeg,
            });
        }
        size = (size.0 * 3 / 4, size.1 * 3 / 4);
    }
    Err(LogoError::TooBig)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn work() -> Signature {
        Signature {
            label: "Work".into(),
            name: "Matteo Neri".into(),
            role: "Product designer".into(),
            company: "Studio Lumen".into(),
            phone: "+39 333 000 0000".into(),
            website: "studiolumen.it".into(),
            ..Default::default()
        }
    }

    #[test]
    fn plain_text_follows_the_template() {
        assert_eq!(
            work().text(),
            "-- \nMatteo Neri\nProduct designer · Studio Lumen\n+39 333 000 0000 · studiolumen.it"
        );
        let minimal = Signature {
            template: Template::Minimal,
            ..work()
        };
        assert_eq!(
            minimal.text(),
            "-- \nMatteo Neri\nProduct designer · Studio Lumen"
        );
        let mono = Signature {
            template: Template::Monogram,
            ..work()
        };
        assert_eq!(mono.lines().last().unwrap(), "studiolumen.it");
        assert_eq!(mono.monogram(), "MN");
        let empty = Signature::default();
        assert_eq!(empty.text(), "");
        assert_eq!(empty.html(), "");
        let short = Signature {
            name: "Matteo".into(),
            company: "Studio Lumen".into(),
            ..Default::default()
        };
        assert_eq!(short.text(), "-- \nMatteo\nStudio Lumen");
    }

    #[test]
    fn html_is_escaped_and_links_the_website() {
        let mut s = work();
        s.name = "Matteo <Neri>".into();
        let html = s.html();
        assert!(html.contains("Matteo &lt;Neri&gt;"));
        assert!(html.contains("href=\"https://studiolumen.it\""));
        assert!(html.contains("background:#3451D1"));
        s.accent = Accent::Black;
        assert!(s.html().contains("color:#16171A;font-weight:500"));
        assert!(!s.html().contains("<img"));
    }

    #[test]
    fn a_logo_is_embedded_not_linked() {
        let s = Signature {
            template: Template::Logo,
            logo: Some(Logo {
                mime: "image/png".into(),
                data: vec![1, 2, 3],
            }),
            ..work()
        };
        let html = s.html();
        assert!(html.contains(&format!("src=\"cid:{LOGO_CID}\"")));
        assert!(html.contains("alt=\"Studio Lumen\""));
        assert!(!html.contains("http://"));
    }

    #[test]
    fn quotes_split_off_the_end() {
        let body = "Thanks!\n\nOn Oct 12, Luca wrote:\n> Here\n>\n> Luca";
        assert_eq!(
            split_quote(body),
            ("Thanks!\n\n", "On Oct 12, Luca wrote:\n> Here\n>\n> Luca")
        );
        assert_eq!(split_quote("No quote here"), ("No quote here", ""));
        assert_eq!(split_quote("> only\n> quote"), ("", "> only\n> quote"));
    }

    #[test]
    fn text_becomes_paragraphs() {
        assert_eq!(
            text_to_html("Hi Luca,\nthe files.\n\nTalk soon, <me>"),
            "<p style=\"margin:0 0 1em\">Hi Luca,<br>the files.</p><p style=\"margin:0 0 1em\">Talk soon, &lt;me&gt;</p>"
        );
    }

    #[test]
    fn big_logos_shrink_and_others_are_refused() {
        // A noisy 1200×400 image is far over 40 KB as PNG.
        let img = image::RgbImage::from_fn(1200, 400, |x, y| {
            image::Rgb([(x * 7 + y * 13) as u8, (x * y) as u8, (x ^ y) as u8])
        });
        let mut png = Vec::new();
        img.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
            .unwrap();
        assert!(png.len() > LOGO_MAX_BYTES);
        let logo = shrink_logo(&png).unwrap();
        assert!(logo.data.len() <= LOGO_MAX_BYTES);
        let small = image::load_from_memory(&logo.data).unwrap();
        assert!(small.width() <= 480 && small.height() <= 144);

        assert_eq!(shrink_logo(b"<svg/>"), Err(LogoError::NotAnImage));
    }
}
