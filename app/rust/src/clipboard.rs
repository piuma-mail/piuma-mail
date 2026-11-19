//! The picture on the system clipboard, for compose: desktops only.

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
mod inner {
    /// The clipboard's picture, as pixels.
    pub fn image() -> Option<piuma_core::compose_image::DynamicImage> {
        let picture = arboard::Clipboard::new().ok()?.get_image().ok()?;
        piuma_core::compose_image::from_rgba(
            u32::try_from(picture.width).ok()?,
            u32::try_from(picture.height).ok()?,
            picture.bytes.into_owned(),
        )
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos", target_os = "linux")))]
mod inner {
    pub fn image() -> Option<piuma_core::compose_image::DynamicImage> {
        None
    }
}

pub use inner::image;
