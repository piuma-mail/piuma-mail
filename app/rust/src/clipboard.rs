//! The picture on the system clipboard, for compose: desktops only.

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
mod inner {
    /// The clipboard's picture as PNG.
    pub fn image() -> Option<Vec<u8>> {
        let picture = arboard::Clipboard::new().ok()?.get_image().ok()?;
        piuma_core::compose_image::png_from_rgba(
            picture.width as u32,
            picture.height as u32,
            picture.bytes.into_owned(),
        )
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
mod inner {
    pub fn image() -> Option<Vec<u8>> {
        None
    }
}

pub use inner::image;
