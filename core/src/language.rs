//! Which language an email is written in, found on this device, for the
//! reader's "Written in German · Translate".

use whatlang::Lang;

use crate::reading::Readable;

/// Shorter than this, a guess is too often wrong to offer a translation.
const MIN_LETTERS: usize = 24;

/// whatlang's own "reliable" asks for more words than most emails have;
/// below this its guesses on short emails start to go wrong.
const MIN_CONFIDENCE: f64 = 0.4;

/// Enough words to tell; the rest of a long email changes nothing.
const MAX_CHARS: usize = 2_000;

/// The language of the email's own words (quotes left out), as a two-letter
/// code ("de"); None when the text is too short or the guess unsure.
pub fn of_readable(r: &Readable) -> Option<&'static str> {
    let mut text = String::new();
    for b in r.blocks.iter().filter(|b| b.quote == 0) {
        if text.len() >= MAX_CHARS {
            break;
        }
        text.push_str(&b.text());
        text.push('\n');
    }
    detect(&text)
}

/// The language of `text`, as a two-letter code; None when unsure.
pub fn detect(text: &str) -> Option<&'static str> {
    let text: String = text.chars().take(MAX_CHARS).collect();
    if text.chars().filter(|c| c.is_alphabetic()).count() < MIN_LETTERS {
        return None;
    }
    let info = whatlang::Detector::with_allowlist(known()).detect(&text)?;
    if info.confidence() < MIN_CONFIDENCE {
        return None;
    }
    code(info.lang())
}

/// Only the languages [code] knows are considered: fewer near neighbours,
/// better guesses.
fn known() -> Vec<Lang> {
    Lang::all()
        .iter()
        .copied()
        .filter(|l| code(*l).is_some())
        .collect()
}

/// ISO 639-1 codes for the languages a translation could cover.
fn code(lang: Lang) -> Option<&'static str> {
    Some(match lang {
        Lang::Ara => "ar",
        Lang::Bul => "bg",
        Lang::Cat => "ca",
        Lang::Ces => "cs",
        Lang::Cmn => "zh",
        Lang::Dan => "da",
        Lang::Deu => "de",
        Lang::Ell => "el",
        Lang::Eng => "en",
        Lang::Est => "et",
        Lang::Fin => "fi",
        Lang::Fra => "fr",
        Lang::Heb => "he",
        Lang::Hin => "hi",
        Lang::Hrv => "hr",
        Lang::Hun => "hu",
        Lang::Ind => "id",
        Lang::Ita => "it",
        Lang::Jpn => "ja",
        Lang::Kor => "ko",
        Lang::Lit => "lt",
        Lang::Lav => "lv",
        Lang::Nld => "nl",
        Lang::Nob => "nb",
        Lang::Pol => "pl",
        Lang::Por => "pt",
        Lang::Ron => "ro",
        Lang::Rus => "ru",
        Lang::Slk => "sk",
        Lang::Slv => "sl",
        Lang::Spa => "es",
        Lang::Srp => "sr",
        Lang::Swe => "sv",
        Lang::Tha => "th",
        Lang::Tur => "tr",
        Lang::Ukr => "uk",
        Lang::Vie => "vi",
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::reading::{Block, BlockKind, Span};

    fn block(text: &str, quote: u8) -> Block {
        Block {
            kind: BlockKind::Paragraph,
            level: 0,
            quote,
            marker: String::new(),
            spans: vec![Span {
                text: text.into(),
                bold: false,
                italic: false,
                code: false,
                link: None,
                suspicious: false,
            }],
            image: None,
        }
    }

    #[test]
    fn finds_common_languages() {
        let cases = [
            (
                "Hallo Matteo, die Lampen kommen nächste Woche. Passt dir Dienstag um 10 Uhr? Viele Grüße, Klaus",
                "de",
            ),
            (
                "Ciao Klaus, martedì alle dieci va benissimo, ti aspetto in studio. A presto, Matteo",
                "it",
            ),
            (
                "Bonjour, je vous envoie la facture du mois dernier. Merci de me confirmer la réception.",
                "fr",
            ),
            (
                "Hi Matteo, the lamps arrive next week. Does Tuesday at ten work for you? Best regards",
                "en",
            ),
        ];
        for (text, want) in cases {
            assert_eq!(detect(text), Some(want), "{text}");
        }
    }

    #[test]
    fn short_text_is_not_guessed() {
        assert_eq!(detect("Danke!"), None);
        assert_eq!(detect("https://example.com 12:30"), None);
    }

    #[test]
    fn quotes_do_not_count() {
        let r = Readable {
            blocks: vec![
                block("Perfetto, martedì alle dieci va benissimo per me, grazie mille!", 0),
                block(
                    "Hallo Matteo, die Lampen kommen nächste Woche. Passt dir Dienstag um 10 Uhr? Viele Grüße, Klaus",
                    1,
                ),
            ],
            remote_images: 0,
            trackers: vec![],
            links_cleaned: 0,
            suspicious_links: 0,
        };
        assert_eq!(of_readable(&r), Some("it"));
    }
}
