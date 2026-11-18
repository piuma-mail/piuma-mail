//! Pictures put inside a message being written (pasted or dropped into
//! the text): each one stands in the text as [`PLACEHOLDER`] and travels
//! as a `cid:` part beside the HTML. Big photos are made smaller first,
//! and every picture is written again, so what the camera kept in it (the
//! place it was taken, the phone) stays on the device.

use std::io::Cursor;

pub use image::DynamicImage;
use image::{ImageDecoder, ImageFormat, ImageReader};

/// Where a picture sits in the text: one character per picture, in order
/// (the object replacement character, as text fields draw a widget).
pub const PLACEHOLDER: char = '\u{FFFC}';

/// The longest side a picture keeps.
pub const MAX_EDGE: u32 = 1600;

/// The most one picture may weigh once made smaller: what the reader
/// keeps of a picture inside a message (`imap::INLINE_MAX`).
pub const MAX_BYTES: usize = 2_000_000;

/// The start of the Content-ID of the pictures written here, so a saved
/// draft finds them again.
pub const CID_PREFIX: &str = "piuma-img-";

/// A picture inside a message being written.
#[derive(Clone, Default, PartialEq, Eq)]
pub struct InlineImage {
    /// Its Content-ID, without angle brackets; made when the message is
    /// built when empty.
    pub cid: String,
    /// A name for it: the file's, or "image.png" for one pasted.
    pub name: String,
    pub mime: String,
    pub data: Vec<u8>,
}

impl std::fmt::Debug for InlineImage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{} <{}> ({}, {} bytes)",
            self.name,
            self.cid,
            self.mime,
            self.data.len()
        )
    }
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum PrepareError {
    #[error("not a picture")]
    NotAnImage,
    #[error("the picture stays too big")]
    TooBig,
}

/// A picture ready to go inside a message, and its size in pixels.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Prepared {
    pub mime: String,
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
}

/// Makes a picture ready to go inside a message: turned the way the
/// camera held it, at most [`MAX_EDGE`] on its longest side and
/// [`MAX_BYTES`] heavy, without the camera's metadata. Pictures with
/// transparency stay PNG, photos become JPEG; an animated GIF small
/// enough goes as it is.
pub fn prepare(data: &[u8]) -> Result<Prepared, PrepareError> {
    let mut reader = ImageReader::new(Cursor::new(data))
        .with_guessed_format()
        .map_err(|_| PrepareError::NotAnImage)?;
    reader.limits(limits());
    let format = reader.format().ok_or(PrepareError::NotAnImage)?;
    let mut decoder = reader.into_decoder().map_err(decode_error)?;
    let orientation = decoder.orientation().ok();
    let mut picture = DynamicImage::from_decoder(decoder).map_err(decode_error)?;
    if let Some(o) = orientation {
        picture.apply_orientation(o);
    }
    let (width, height) = (picture.width(), picture.height());
    if format == ImageFormat::Gif && data.len() <= MAX_BYTES && width.max(height) <= MAX_EDGE {
        return Ok(Prepared {
            mime: "image/gif".into(),
            data: data.to_vec(),
            width,
            height,
        });
    }
    prepare_picture(picture)
}

/// The most a picture may be to be read at all: a picture bigger than
/// this (a decompression bomb, a panorama of 60000 pixels) is refused
/// before it fills memory.
const MAX_DECODED_EDGE: u32 = 12_000;
const MAX_DECODED_BYTES: u64 = 256 * 1024 * 1024;

fn limits() -> image::Limits {
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(MAX_DECODED_EDGE);
    limits.max_image_height = Some(MAX_DECODED_EDGE);
    limits.max_alloc = Some(MAX_DECODED_BYTES);
    limits
}

fn decode_error(e: image::ImageError) -> PrepareError {
    match e {
        image::ImageError::Limits(_) => PrepareError::TooBig,
        _ => PrepareError::NotAnImage,
    }
}

/// A picture already in memory (the clipboard's) made ready as
/// [prepare] makes one: at most [MAX_EDGE] and [MAX_BYTES], PNG when it
/// has transparency, JPEG otherwise.
pub fn prepare_picture(picture: DynamicImage) -> Result<Prepared, PrepareError> {
    let (width, height) = (picture.width(), picture.height());
    if width.max(height) > MAX_DECODED_EDGE {
        return Err(PrepareError::TooBig);
    }
    let alpha = picture.color().has_alpha();
    let mut edge = width.max(height).min(MAX_EDGE);
    loop {
        let sized = if width.max(height) > edge {
            picture.resize(edge, edge, image::imageops::FilterType::Triangle)
        } else {
            picture.clone()
        };
        let (mime, bytes) = encode(&sized, alpha)?;
        if bytes.len() <= MAX_BYTES {
            return Ok(Prepared {
                mime: mime.into(),
                data: bytes,
                width: sized.width(),
                height: sized.height(),
            });
        }
        if edge <= 320 {
            return Err(PrepareError::TooBig);
        }
        edge = edge * 3 / 4;
    }
}

/// RGBA pixels (as a clipboard holds a picture) as a picture; None when
/// they don't make one of that size.
pub fn from_rgba(width: u32, height: u32, rgba: Vec<u8>) -> Option<DynamicImage> {
    image::RgbaImage::from_raw(width, height, rgba).map(DynamicImage::ImageRgba8)
}

fn encode(picture: &DynamicImage, alpha: bool) -> Result<(&'static str, Vec<u8>), PrepareError> {
    let mut out = Cursor::new(Vec::new());
    if alpha {
        picture
            .write_to(&mut out, ImageFormat::Png)
            .map_err(|_| PrepareError::NotAnImage)?;
        return Ok(("image/png", out.into_inner()));
    }
    let rgb = DynamicImage::ImageRgb8(picture.to_rgb8());
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 82);
    rgb.write_with_encoder(encoder)
        .map_err(|_| PrepareError::NotAnImage)?;
    Ok(("image/jpeg", out.into_inner()))
}

/// A fresh Content-ID for the `index`th picture of a message.
pub fn new_cid(index: usize) -> String {
    let mut bytes = [0u8; 8];
    getrandom::fill(&mut bytes).ok();
    let tag: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("{CID_PREFIX}{index}-{tag}@piuma")
}

/// The text with each picture written out for the plain-text copy, as
/// "[image: name]".
pub fn plain(text: &str, images: &[InlineImage]) -> String {
    let mut next = images.iter();
    text.chars()
        .map(|c| match c {
            PLACEHOLDER => match next.next() {
                Some(i) => format!("[image: {}]", i.name),
                None => String::new(),
            },
            c => c.to_string(),
        })
        .collect()
}

/// The text without its pictures (for a message that carries them as
/// files instead).
pub fn without(text: &str) -> String {
    text.replace(PLACEHOLDER, "")
}

/// HTML that already went through the text's conversion, with each
/// placeholder turned into its picture. Placeholders past the last
/// picture go.
pub fn html(html: &str, images: &[InlineImage]) -> String {
    let mut next = images.iter();
    let mut out = String::with_capacity(html.len());
    for c in html.chars() {
        if c != PLACEHOLDER {
            out.push(c);
            continue;
        }
        if let Some(i) = next.next() {
            out.push_str(&format!(
                "<img src=\"cid:{}\" alt=\"{}\" style=\"max-width:100%;height:auto\">",
                escape(&i.cid),
                escape(&i.name)
            ));
        }
    }
    out
}

fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(width: u32, height: u32, alpha: bool) -> Vec<u8> {
        let picture = if alpha {
            DynamicImage::ImageRgba8(image::RgbaImage::from_pixel(
                width,
                height,
                image::Rgba([10, 20, 30, 128]),
            ))
        } else {
            DynamicImage::ImageRgb8(image::RgbImage::from_fn(width, height, |x, y| {
                image::Rgb([(x % 256) as u8, (y % 256) as u8, ((x * y) % 256) as u8])
            }))
        };
        let mut out = Cursor::new(Vec::new());
        picture.write_to(&mut out, ImageFormat::Png).unwrap();
        out.into_inner()
    }

    #[test]
    fn big_photos_get_smaller() {
        let p = prepare(&png(4000, 3000, false)).unwrap();
        assert_eq!((p.width, p.height), (1600, 1200));
        assert_eq!(p.mime, "image/jpeg");
        assert!(p.data.len() <= MAX_BYTES);
    }

    #[test]
    fn transparent_pictures_stay_png() {
        let p = prepare(&png(40, 30, true)).unwrap();
        assert_eq!(p.mime, "image/png");
        assert_eq!((p.width, p.height), (40, 30));
    }

    #[test]
    fn pictures_too_big_to_read_are_refused() {
        // A PNG header that claims 20000 × 20000 pixels.
        let mut png = png(1, 1, false);
        png[16..20].copy_from_slice(&20_000u32.to_be_bytes());
        png[20..24].copy_from_slice(&20_000u32.to_be_bytes());
        assert!(prepare(&png).is_err());
        let wide = from_rgba(13_000, 1, vec![0; 13_000 * 4]).unwrap();
        assert_eq!(prepare_picture(wide), Err(PrepareError::TooBig));
        let small = from_rgba(2, 2, vec![255; 16]).unwrap();
        assert_eq!(prepare_picture(small).unwrap().mime, "image/png");
    }

    #[test]
    fn refuses_what_is_not_a_picture() {
        assert_eq!(prepare(b"%PDF-1.4"), Err(PrepareError::NotAnImage));
    }

    #[test]
    fn placeholders_become_pictures_or_names() {
        let images = vec![InlineImage {
            cid: "piuma-img-0-ab@piuma".into(),
            name: "a \"b\".png".into(),
            mime: "image/png".into(),
            data: vec![1],
        }];
        let text = format!("Look:\n{PLACEHOLDER}\nand{PLACEHOLDER}");
        assert_eq!(plain(&text, &images), "Look:\n[image: a \"b\".png]\nand");
        assert_eq!(
            html(&text, &images),
            "Look:\n<img src=\"cid:piuma-img-0-ab@piuma\" alt=\"a &quot;b&quot;.png\" style=\"max-width:100%;height:auto\">\nand"
        );
        assert_eq!(without(&text), "Look:\n\nand");
    }

    #[test]
    fn cids_are_unique() {
        assert_ne!(new_cid(0), new_cid(0));
        assert!(new_cid(3).starts_with("piuma-img-3-"));
    }
}
