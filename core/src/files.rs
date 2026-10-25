//! Files on the person's device: attachments saved from a message, and
//! the content types of files attached to a draft.

use std::fs::OpenOptions;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use crate::imap::file_name;

/// Writes `data` into `dir` as `name`, never over an existing file:
/// "quote.pdf" becomes "quote (2).pdf" when the first is taken.
pub fn save_new(dir: &Path, name: &str, data: &[u8]) -> io::Result<PathBuf> {
    let name = file_name(name);
    let (stem, ext) = match name.rfind('.') {
        Some(i) if i > 0 => (&name[..i], &name[i..]),
        _ => (name.as_str(), ""),
    };
    for n in 1..1000 {
        let candidate = if n == 1 {
            dir.join(&name)
        } else {
            dir.join(format!("{stem} ({n}){ext}"))
        };
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(mut f) => {
                f.write_all(data)?;
                return Ok(candidate);
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "too many files with this name",
    ))
}

/// Biggest side of a preview on the Attachments board, in pixels: twice
/// the card on a dense screen.
const THUMB_SIDE: u32 = 640;

/// Width a document's first page is drawn at for its preview.
const PAGE_WIDTH: u32 = 480;

/// What kind of preview a file can have, from its name and type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThumbKind {
    /// PNG, JPEG, GIF, WebP, BMP, TIFF and SVG.
    Picture,
    /// A PDF's first page.
    Pdf,
    /// Word, Excel, PowerPoint and OpenDocument files, which keep a
    /// small picture of their first page inside.
    Office,
}

impl ThumbKind {
    /// The kind for a file, or None when it has no preview here (HEIC,
    /// video, archives…).
    pub fn of(name: &str, mime: &str) -> Option<Self> {
        let mime = mime.to_ascii_lowercase();
        let ext = name
            .rsplit_once('.')
            .map(|(_, e)| e.to_ascii_lowercase())
            .unwrap_or_default();
        if matches!(
            mime.as_str(),
            "image/png"
                | "image/jpeg"
                | "image/jpg"
                | "image/pjpeg"
                | "image/gif"
                | "image/webp"
                | "image/bmp"
                | "image/tiff"
                | "image/svg+xml"
        ) || matches!(
            ext.as_str(),
            "png" | "jpg" | "jpeg" | "gif" | "webp" | "bmp" | "tif" | "tiff" | "svg"
        ) {
            return Some(Self::Picture);
        }
        if mime == "application/pdf" || ext == "pdf" {
            return Some(Self::Pdf);
        }
        if matches!(
            ext.as_str(),
            "docx" | "xlsx" | "pptx" | "docm" | "xlsm" | "pptm" | "odt" | "ods" | "odp" | "odg"
        ) {
            return Some(Self::Office);
        }
        None
    }

    /// Files fetched for a preview at most, in bytes.
    pub fn max_bytes(self) -> u64 {
        match self {
            Self::Picture => 12 * 1024 * 1024,
            Self::Pdf | Self::Office => 15 * 1024 * 1024,
        }
    }
}

/// A small JPEG preview of an attached file: a picture made small, a
/// PDF's first page, or the picture an office document keeps of itself.
/// None when the data has none.
pub fn thumbnail(data: &[u8], kind: ThumbKind) -> Option<Vec<u8>> {
    let img = match kind {
        ThumbKind::Picture => picture(data).or_else(|| svg(data))?,
        ThumbKind::Pdf => {
            let png = crate::preview::page(data, 0, PAGE_WIDTH)?;
            image::load_from_memory_with_format(&png, image::ImageFormat::Png).ok()?
        }
        ThumbKind::Office => picture(&office_thumbnail(data)?)?,
    };
    let small = if img.width() > THUMB_SIDE || img.height() > THUMB_SIDE {
        img.thumbnail(THUMB_SIDE, THUMB_SIDE)
    } else {
        img
    };
    let mut jpeg = Vec::new();
    on_white(small)
        .write_to(
            &mut std::io::Cursor::new(&mut jpeg),
            image::ImageFormat::Jpeg,
        )
        .ok()?;
    Some(jpeg)
}

/// A bitmap picture, turned upright as its camera said.
fn picture(data: &[u8]) -> Option<image::DynamicImage> {
    use image::ImageDecoder;
    let mut decoder = image::ImageReader::new(std::io::Cursor::new(data))
        .with_guessed_format()
        .ok()?
        .into_decoder()
        .ok()?;
    let orientation = decoder.orientation().ok();
    let mut img = image::DynamicImage::from_decoder(decoder).ok()?;
    if let Some(o) = orientation {
        img.apply_orientation(o);
    }
    Some(img)
}

/// An SVG drawn [`THUMB_SIDE`] on its longer side.
fn svg(data: &[u8]) -> Option<image::DynamicImage> {
    let tree = resvg::usvg::Tree::from_data(data, &resvg::usvg::Options::default()).ok()?;
    let size = tree.size();
    if size.width() <= 0.0 || size.height() <= 0.0 {
        return None;
    }
    let scale = THUMB_SIDE as f32 / size.width().max(size.height());
    let w = (size.width() * scale).ceil().max(1.0) as u32;
    let h = (size.height() * scale).ceil().max(1.0) as u32;
    let mut pixmap = resvg::tiny_skia::Pixmap::new(w, h)?;
    pixmap.fill(resvg::tiny_skia::Color::WHITE);
    resvg::render(
        &tree,
        resvg::tiny_skia::Transform::from_scale(scale, scale),
        &mut pixmap.as_mut(),
    );
    let png = pixmap.encode_png().ok()?;
    image::load_from_memory_with_format(&png, image::ImageFormat::Png).ok()
}

/// The picture of its first page an office document keeps: OpenDocument
/// always, Word, Excel and PowerPoint when saved with one.
fn office_thumbnail(data: &[u8]) -> Option<Vec<u8>> {
    use std::io::Read;
    let mut zip = zip::ZipArchive::new(std::io::Cursor::new(data)).ok()?;
    for name in [
        "Thumbnails/thumbnail.png",
        "docProps/thumbnail.jpeg",
        "docProps/thumbnail.jpg",
        "docProps/thumbnail.png",
    ] {
        let Ok(entry) = zip.by_name(name) else {
            continue;
        };
        if entry.size() > THUMB_SOURCE_MAX {
            return None;
        }
        let mut out = Vec::new();
        entry.take(THUMB_SOURCE_MAX).read_to_end(&mut out).ok()?;
        return Some(out);
    }
    None
}

/// An office document's own preview at most, in bytes.
const THUMB_SOURCE_MAX: u64 = 4 * 1024 * 1024;

/// Transparent parts on white, as the card's page is.
fn on_white(img: image::DynamicImage) -> image::RgbImage {
    let rgba = img.to_rgba8();
    let mut out = image::RgbImage::new(rgba.width(), rgba.height());
    for (o, p) in out.pixels_mut().zip(rgba.pixels()) {
        let a = p[3] as u32;
        for i in 0..3 {
            o[i] = ((p[i] as u32 * a + 255 * (255 - a)) / 255) as u8;
        }
    }
    out
}

/// The content type of a file, from its extension.
pub fn mime_for(name: &str) -> &'static str {
    let ext = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase());
    match ext.as_deref() {
        Some("pdf") => "application/pdf",
        Some("png") => "image/png",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        Some("heic") => "image/heic",
        Some("svg") => "image/svg+xml",
        Some("txt") => "text/plain",
        Some("csv") => "text/csv",
        Some("ics") => "text/calendar",
        Some("html" | "htm") => "text/html",
        Some("zip") => "application/zip",
        Some("doc") => "application/msword",
        Some("docx") => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        Some("xls") => "application/vnd.ms-excel",
        Some("xlsx") => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        Some("ppt") => "application/vnd.ms-powerpoint",
        Some("pptx") => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        Some("odt") => "application/vnd.oasis.opendocument.text",
        Some("ods") => "application/vnd.oasis.opendocument.spreadsheet",
        Some("mp3") => "audio/mpeg",
        Some("mp4") => "video/mp4",
        Some("mov") => "video/quicktime",
        Some("eml") => "message/rfc822",
        _ => "application/octet-stream",
    }
}

/// Why a file from an email deserves a word before it opens
/// (`ProtectionToApprove` section 3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileRisk {
    /// A program or a script, which runs when opened.
    Program,
    /// A program named like a document: "invoice.pdf.exe", or with the
    /// letters turned around by a right-to-left mark.
    Disguised,
    /// An Office file that keeps macros, which can run when it opens.
    Macros,
    /// An archive locked with a password, which no scanner can look into.
    Locked,
}

/// Extensions of programs and scripts the systems run on a double click.
const PROGRAMS: &[&str] = &[
    "exe", "scr", "com", "pif", "bat", "cmd", "msi", "msix", "msp", "cpl", "vbs", "vbe", "js",
    "jse", "wsf", "wsh", "hta", "ps1", "psm1", "jar", "lnk", "reg", "scf", "apk", "xapk", "appx",
    "appimage", "command", "action", "workflow",
];

/// Office files that keep macros.
const MACROS: &[&str] = &[
    "docm", "dotm", "xlsm", "xltm", "xlsb", "xlam", "pptm", "potm", "ppsm", "ppam", "sldm",
];

/// What a document's name usually ends with, to catch "invoice.pdf.exe".
const DOCUMENTS: &[&str] = &[
    "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "txt", "rtf", "csv", "jpg",
    "jpeg", "png", "gif", "zip", "rar", "mp3", "mp4", "mov", "html", "htm",
];

/// Whether a file deserves a word before it opens, from its name alone;
/// a locked archive is only known from its bytes ([locked_archive]).
pub fn file_risk(name: &str) -> Option<FileRisk> {
    let lower = name.trim().trim_end_matches('.').to_lowercase();
    // A right-to-left mark shows "photo\u{202E}gpj.exe" as "photoexe.jpg".
    if lower.contains('\u{202E}') || lower.contains('\u{202D}') {
        return Some(FileRisk::Disguised);
    }
    let mut parts = lower.rsplit('.');
    let ext = parts.next().filter(|_| lower.contains('.'))?;
    if MACROS.contains(&ext) {
        return Some(FileRisk::Macros);
    }
    if !PROGRAMS.contains(&ext) {
        return None;
    }
    let inner = parts.next().map(str::trim);
    let disguised =
        lower.matches('.').count() >= 2 && inner.is_some_and(|i| DOCUMENTS.contains(&i));
    Some(if disguised {
        FileRisk::Disguised
    } else {
        FileRisk::Program
    })
}

/// Whether a ZIP archive keeps any of its files under a password: the
/// first bit of a file header's flags says so.
pub fn locked_archive(data: &[u8]) -> bool {
    const LOCAL: &[u8] = b"PK\x03\x04";
    const CENTRAL: &[u8] = b"PK\x01\x02";
    let flag = |i: usize, at: usize| data.get(i + at..i + at + 2).is_some_and(|f| f[0] & 1 == 1);
    data.windows(4)
        .enumerate()
        .any(|(i, w)| (w == LOCAL && flag(i, 6)) || (w == CENTRAL && flag(i, 8)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn programs_and_macros_are_known_by_name() {
        assert_eq!(file_risk("setup.exe"), Some(FileRisk::Program));
        assert_eq!(file_risk("Run.JS"), Some(FileRisk::Program));
        assert_eq!(file_risk("app.apk"), Some(FileRisk::Program));
        assert_eq!(file_risk("invoice.pdf.exe"), Some(FileRisk::Disguised));
        assert_eq!(file_risk("invoice.pdf .scr"), Some(FileRisk::Disguised));
        assert_eq!(file_risk("photo\u{202E}gpj.exe"), Some(FileRisk::Disguised));
        assert_eq!(file_risk("Budget 2027.xlsm"), Some(FileRisk::Macros));
        assert_eq!(file_risk("v1.2.exe"), Some(FileRisk::Program));
        for safe in ["Quote Acme.pdf", "photo.jpg", "notes", "report.docx", "exe"] {
            assert_eq!(file_risk(safe), None, "{safe}");
        }
    }

    #[test]
    fn a_locked_archive_shows_in_its_headers() {
        let mut open = b"PK\x03\x04\x14\x00".to_vec();
        open.extend_from_slice(&[0x00, 0x00]);
        open.extend_from_slice(&[0; 40]);
        assert!(!locked_archive(&open));
        let mut locked = b"PK\x03\x04\x14\x00".to_vec();
        locked.extend_from_slice(&[0x01, 0x00]);
        locked.extend_from_slice(&[0; 40]);
        assert!(locked_archive(&locked));
        assert!(!locked_archive(b"%PDF-1.4"));
    }

    #[test]
    fn pictures_get_a_small_preview() {
        let big = image::RgbImage::from_pixel(1600, 1200, image::Rgb([52, 81, 209]));
        let mut png = Vec::new();
        big.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
            .unwrap();
        let thumb = image::load_from_memory(&thumbnail(&png, ThumbKind::Picture).unwrap()).unwrap();
        assert_eq!((thumb.width(), thumb.height()), (640, 480));
        assert_eq!(thumbnail(b"%PDF-1.4", ThumbKind::Picture), None);
    }

    #[test]
    fn transparent_pictures_sit_on_white() {
        let clear = image::RgbaImage::from_pixel(20, 20, image::Rgba([0, 0, 0, 0]));
        let mut png = Vec::new();
        clear
            .write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
            .unwrap();
        let thumb = image::load_from_memory(&thumbnail(&png, ThumbKind::Picture).unwrap())
            .unwrap()
            .to_rgb8();
        assert!(thumb.get_pixel(10, 10).0.iter().all(|&c| c > 245));
    }

    #[test]
    fn svgs_are_drawn() {
        let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="black"/></svg>"#;
        let thumb = image::load_from_memory(&thumbnail(svg, ThumbKind::Picture).unwrap()).unwrap();
        assert_eq!((thumb.width(), thumb.height()), (640, 320));
    }

    #[test]
    fn a_pdf_shows_its_first_page() {
        let pdf = crate::preview::tests::sample(2);
        let thumb = image::load_from_memory(&thumbnail(&pdf, ThumbKind::Pdf).unwrap()).unwrap();
        assert_eq!(thumb.width(), 452);
        assert_eq!(thumb.height(), 640);
        assert_eq!(thumbnail(b"hello", ThumbKind::Pdf), None);
    }

    #[test]
    fn office_files_show_the_picture_they_keep() {
        use std::io::Write;
        let page = image::RgbImage::from_pixel(120, 170, image::Rgb([255, 255, 255]));
        let mut png = Vec::new();
        page.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
            .unwrap();
        let mut odt = Vec::new();
        {
            let mut zip = zip::ZipWriter::new(std::io::Cursor::new(&mut odt));
            let opts = zip::write::SimpleFileOptions::default();
            zip.start_file("mimetype", opts).unwrap();
            zip.write_all(b"application/vnd.oasis.opendocument.text")
                .unwrap();
            zip.start_file("Thumbnails/thumbnail.png", opts).unwrap();
            zip.write_all(&png).unwrap();
            zip.finish().unwrap();
        }
        let thumb = image::load_from_memory(&thumbnail(&odt, ThumbKind::Office).unwrap()).unwrap();
        assert_eq!((thumb.width(), thumb.height()), (120, 170));
        // A .docx saved without one has none.
        let mut docx = Vec::new();
        {
            let mut zip = zip::ZipWriter::new(std::io::Cursor::new(&mut docx));
            zip.start_file(
                "word/document.xml",
                zip::write::SimpleFileOptions::default(),
            )
            .unwrap();
            zip.write_all(b"<w:document/>").unwrap();
            zip.finish().unwrap();
        }
        assert_eq!(thumbnail(&docx, ThumbKind::Office), None);
    }

    #[test]
    fn kinds_come_from_the_name_and_type() {
        assert_eq!(ThumbKind::of("a.JPG", ""), Some(ThumbKind::Picture));
        assert_eq!(
            ThumbKind::of("scan", "image/webp"),
            Some(ThumbKind::Picture)
        );
        assert_eq!(
            ThumbKind::of("Quote.pdf", "application/octet-stream"),
            Some(ThumbKind::Pdf)
        );
        assert_eq!(ThumbKind::of("Budget.xlsx", ""), Some(ThumbKind::Office));
        assert_eq!(ThumbKind::of("IMG_1.heic", "image/heic"), None);
        assert_eq!(ThumbKind::of("photos.zip", "application/zip"), None);
    }

    #[test]
    fn saving_never_overwrites() {
        let dir = std::env::temp_dir().join(format!("piuma-files-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let a = save_new(&dir, "quote.pdf", b"one").unwrap();
        let b = save_new(&dir, "quote.pdf", b"two").unwrap();
        let c = save_new(&dir, "../notes", b"three").unwrap();
        assert_eq!(a.file_name().unwrap(), "quote.pdf");
        assert_eq!(b.file_name().unwrap(), "quote (2).pdf");
        assert_eq!(c, dir.join("notes"));
        assert_eq!(std::fs::read(&a).unwrap(), b"one");
        assert_eq!(std::fs::read(&b).unwrap(), b"two");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn types_come_from_the_extension() {
        assert_eq!(mime_for("Quote.PDF"), "application/pdf");
        assert_eq!(mime_for("photo.jpeg"), "image/jpeg");
        assert_eq!(mime_for("README"), "application/octet-stream");
    }
}
