//! Remote images, fetched only when the person allows it.
//!
//! The request says as little as possible: no cookies, no referrer, a
//! generic user agent, and only images, up to a size.

use std::time::Duration;

/// Bigger images are refused.
pub const MAX_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, thiserror::Error)]
pub enum ImageError {
    #[error("not an http(s) address")]
    BadAddress,
    #[error("not an image the app can show: {0}")]
    NotAnImage(String),
    #[error("image larger than {MAX_BYTES} bytes")]
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
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

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
