//! Remote images, fetched only when the person allows it.
//!
//! The request says as little as possible: no cookies, no referrer, a
//! generic user agent, and only images, up to a size.

use std::time::Duration;

/// Bigger images are refused.
pub const MAX_BYTES: usize = 8 * 1024 * 1024;

/// Pictures that would take more than this many pixels once drawn are
/// refused too: a few kilobytes of PNG can declare 20,000 × 20,000, which
/// is gigabytes in memory. 32 million is a large photo.
pub const MAX_PIXELS: u64 = 32_000_000;

/// What decoding a picture from outside may take: its sides and memory,
/// so a small file that declares a huge picture is refused before it is
/// drawn.
pub fn limits() -> image::Limits {
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(20_000);
    limits.max_image_height = Some(20_000);
    limits.max_alloc = Some(MAX_PIXELS * 4 + 16 * 1024 * 1024);
    limits
}

/// A picture from outside decoded within [`limits`] and [`MAX_PIXELS`].
pub fn decode(bytes: &[u8]) -> Option<image::DynamicImage> {
    let mut reader = image::ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .ok()?;
    reader.limits(limits());
    if !fits(bytes) {
        return None;
    }
    reader.decode().ok()
}

/// Whether a picture's declared size fits [`MAX_PIXELS`]. Only its header
/// is read. One whose size can't be read passes: nothing can draw it.
pub fn fits(bytes: &[u8]) -> bool {
    let Ok(reader) = image::ImageReader::new(std::io::Cursor::new(bytes)).with_guessed_format()
    else {
        return true;
    };
    match reader.into_dimensions() {
        Ok((w, h)) => u64::from(w) * u64::from(h) <= MAX_PIXELS,
        Err(_) => true,
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ImageError {
    #[error("not an http(s) address")]
    BadAddress,
    #[error("not an image the app can show: {0}")]
    NotAnImage(String),
    #[error("image larger than {MAX_BYTES} bytes or {MAX_PIXELS} pixels")]
    TooLarge,
    #[error("network: {0}")]
    Network(#[from] reqwest::Error),
}

/// Kinds the app can draw (SVG can't be, and can carry scripts).
fn drawable(content_type: &str) -> bool {
    let t = content_type
        .split(';')
        .next()
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    [
        "image/png",
        "image/jpeg",
        "image/jpg",
        "image/gif",
        "image/webp",
        "image/bmp",
    ]
    .contains(&t.as_str())
}

pub async fn fetch(url: &str) -> Result<Vec<u8>, ImageError> {
    let parsed = reqwest::Url::parse(url).map_err(|_| ImageError::BadAddress)?;
    if !matches!(parsed.scheme(), "http" | "https") {
        return Err(ImageError::BadAddress);
    }
    let client = crate::tls::http_client()
        .timeout(Duration::from_secs(15))
        .user_agent("Mozilla/5.0")
        .referer(false)
        .build()?;
    let mut response = client
        .get(parsed)
        .header("Accept", "image/webp,image/png,image/jpeg,image/gif;q=0.9")
        .send()
        .await?
        .error_for_status()?;
    let content_type = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_owned();
    if !drawable(&content_type) {
        return Err(ImageError::NotAnImage(content_type));
    }
    if response
        .content_length()
        .is_some_and(|n| n as usize > MAX_BYTES)
    {
        return Err(ImageError::TooLarge);
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if bytes.len() + chunk.len() > MAX_BYTES {
            return Err(ImageError::TooLarge);
        }
        bytes.extend_from_slice(&chunk);
    }
    if !fits(&bytes) {
        return Err(ImageError::TooLarge);
    }
    Ok(bytes)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// A PNG that says it is `w` × `h`, with no pixels in it: enough for
    /// its size to be read, nothing to draw.
    pub(crate) fn png_header(w: u32, h: u32) -> Vec<u8> {
        fn crc(bytes: &[u8]) -> u32 {
            let mut c = 0xFFFF_FFFFu32;
            for &b in bytes {
                c ^= u32::from(b);
                for _ in 0..8 {
                    c = if c & 1 == 1 {
                        0xEDB8_8320 ^ (c >> 1)
                    } else {
                        c >> 1
                    };
                }
            }
            !c
        }
        let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
        let mut chunk = b"IHDR".to_vec();
        chunk.extend(w.to_be_bytes());
        chunk.extend(h.to_be_bytes());
        chunk.extend([8, 6, 0, 0, 0]);
        out.extend(13u32.to_be_bytes());
        out.extend(&chunk);
        out.extend(crc(&chunk).to_be_bytes());
        // An empty IDAT: the reader stops there, its size known.
        for name in [&b"IDAT"[..], &b"IEND"[..]] {
            out.extend(0u32.to_be_bytes());
            out.extend(name);
            out.extend(crc(name).to_be_bytes());
        }
        out
    }

    #[test]
    fn pictures_that_declare_too_many_pixels_do_not_fit() {
        assert!(!fits(&png_header(20_000, 20_000)));
        assert!(fits(&png_header(4_000, 3_000)));
        assert!(fits(b"not a picture"));
        assert!(decode(&png_header(20_000, 20_000)).is_none());
    }

    #[test]
    fn only_drawable_kinds() {
        assert!(drawable("image/png"));
        assert!(drawable("Image/JPEG; charset=binary"));
        assert!(!drawable("image/svg+xml"));
        assert!(!drawable("text/html"));
        assert!(!drawable(""));
    }

    #[tokio::test]
    async fn refuses_other_schemes() {
        assert!(matches!(
            fetch("file:///etc/passwd").await,
            Err(ImageError::BadAddress)
        ));
        assert!(matches!(
            fetch("nonsense").await,
            Err(ImageError::BadAddress)
        ));
    }
}
