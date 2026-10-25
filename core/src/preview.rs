//! Pages of an attached PDF as pictures, for the attachment preview
//! (`AttachPreview`). Drawn on this device with hayro, in pure Rust: no
//! system viewer and nothing sent anywhere.

use hayro::hayro_interpret::InterpreterSettings;
use hayro::hayro_syntax::Pdf;
use hayro::vello_cpu::color::palette::css::WHITE;
use hayro::{render, PixmapSettings, RenderCache, RenderSettings};

/// Widest page drawn, in pixels, whatever the screen asks for.
const MAX_WIDTH: u32 = 2400;

/// How many pages the PDF has; None when it can't be read (damaged, or
/// locked with a password).
pub fn pages(data: &[u8]) -> Option<usize> {
    let pdf = Pdf::new(data.to_vec()).ok()?;
    Some(pdf.pages().len()).filter(|&n| n > 0)
}

/// Page [index] (from 0) as a PNG [width] pixels wide, on white.
pub fn page(data: &[u8], index: usize, width: u32) -> Option<Vec<u8>> {
    let pdf = Pdf::new(data.to_vec()).ok()?;
    let page = pdf.pages().get(index)?;
    let (w, h) = page.render_dimensions();
    if w <= 0.0 || h <= 0.0 {
        return None;
    }
    let scale = width.clamp(1, MAX_WIDTH) as f32 / w;
    // The drawing surface is at most 65,535 pixels a side.
    let scale = scale.min(65_000.0 / h);
    let pixmap = render(
        page,
        &RenderCache::new(),
        &InterpreterSettings::default(),
        &RenderSettings::default(),
        &PixmapSettings {
            x_scale: scale,
            y_scale: scale,
            bg_color: WHITE,
        },
    );
    pixmap.into_png().ok()
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// A PDF of [n] A4 pages, each with a line of Helvetica and a black bar.
    pub(crate) fn sample(n: usize) -> Vec<u8> {
        let mut objects: Vec<String> = vec![
            "<< /Type /Catalog /Pages 2 0 R >>".into(),
            String::new(),
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".into(),
        ];
        let mut kids = Vec::new();
        for i in 0..n {
            let content = format!(
                "BT /F1 24 Tf 72 760 Td (Quote page {}) Tj ET 72 700 300 20 re f",
                i + 1
            );
            let page = objects.len() + 1;
            kids.push(format!("{page} 0 R"));
            objects.push(format!(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] \
                 /Resources << /Font << /F1 3 0 R >> >> /Contents {} 0 R >>",
                page + 1
            ));
            objects.push(format!(
                "<< /Length {} >>\nstream\n{content}\nendstream",
                content.len()
            ));
        }
        objects[1] = format!("<< /Type /Pages /Kids [{}] /Count {n} >>", kids.join(" "));
        let mut out = b"%PDF-1.4\n".to_vec();
        let mut offsets = Vec::new();
        for (i, o) in objects.iter().enumerate() {
            offsets.push(out.len());
            out.extend(format!("{} 0 obj\n{o}\nendobj\n", i + 1).bytes());
        }
        let xref = out.len();
        out.extend(format!("xref\n0 {}\n0000000000 65535 f \n", objects.len() + 1).bytes());
        for o in offsets {
            out.extend(format!("{o:010} 00000 n \n").bytes());
        }
        out.extend(
            format!(
                "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
                objects.len() + 1
            )
            .bytes(),
        );
        out
    }

    #[test]
    fn counts_and_draws_pages() {
        let pdf = sample(2);
        assert_eq!(pages(&pdf), Some(2));
        let png = page(&pdf, 1, 600).expect("drawn");
        let img = image::load_from_memory(&png).unwrap().to_rgb8();
        assert_eq!(img.width(), 600);
        assert_eq!(img.height(), 849);
        // White paper, and the black bar where it was drawn.
        assert_eq!(img.get_pixel(5, 5).0, [255, 255, 255]);
        let bar = img.get_pixel(150, 849 - (710.0 * 600.0 / 595.0) as u32);
        assert!(bar.0.iter().all(|&c| c < 40), "{bar:?}");
        assert_eq!(page(&pdf, 2, 600), None);
    }

    #[test]
    fn not_a_pdf() {
        assert_eq!(pages(b"hello"), None);
        assert_eq!(page(b"hello", 0, 100), None);
    }
}
