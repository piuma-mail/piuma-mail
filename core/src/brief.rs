//! "In short": the gist of a long conversation, on this device.
//!
//! Plain rules, not a model: the sentences that carry decisions, prices,
//! amounts and dates are picked as they were written, newest first, and a
//! fact already said again later is kept only in its newest words. When
//! the last message asks something of you, its request is "Your turn".

use std::collections::BTreeSet;
use std::sync::LazyLock;

use regex::Regex;

use crate::reading::Readable;

/// One message of the conversation, oldest first.
#[derive(Debug, Clone)]
pub struct Note {
    /// You wrote it.
    pub mine: bool,
    /// Its own words, without the quoted text at the end.
    pub text: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Brief {
    /// At most three, oldest first.
    pub points: Vec<String>,
    /// What the last message asks of you, in its own words.
    pub your_turn: Option<String>,
}

/// Conversations shorter than this read fine without a summary.
pub const LONG: usize = 4;

/// A single substantial message also benefits from a brief.
pub const LONG_WORDS: usize = 250;

fn re(pattern: &str) -> Regex {
    Regex::new(pattern).expect("brief pattern")
}

static DECISION: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i)\b(let[’']?s go with|we[’']ll go with|go ahead|confirm(ed|s)?|agreed|decided|chose|approved|deal|booked|scheduled|andiamo con|scegliamo|confermo|confermat[oaie]|d[’']accordo|decis[oaie]|approvat[oaie]|prenotat[oaie]|fissat[oaie])\b",
    )
});
static MONEY: LazyLock<Regex> =
    LazyLock::new(|| re(r"(?i)(€|\$|£)\s?\d|\d\s?(€|eur\b|euro\b|usd\b)"));
static TOPIC: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i)\b(deliver(y|ed)?|invoice|price|quote|deadline|total|due|copies|consegn[ao]|fattura|prezzo|preventivo|scadenza|totale|copie)\b",
    )
});
static REQUEST: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i)\b(can you|could you|would you|please|i (just )?need|we (just )?need|let me know|send me|waiting for your|puoi|potresti|mi mandi|mandami|fammi sapere|ho bisogno|mi serve|ci serve|aspetto|attendo|per favore|sarebbe bello poter collaborare|hai qualcuno cui inviare)\b",
    )
});
static DATE: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|lunedì|martedì|mercoledì|giovedì|venerdì|sabato|domenica|gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)\b",
    )
});
static NUMBER: LazyLock<Regex> = LazyLock::new(|| re(r"\d+(?:[.,]\d+)?"));
static GREETING: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i)^(hi|hello|hey|dear|thanks|thank you|best|regards|cheers|talk soon|ciao|salve|gentile|grazie|saluti|a presto|buongiorno|buonasera)\b",
    )
});
static OPENER: LazyLock<Regex> = LazyLock::new(|| {
    re(r"(?i)^(perfect|great|ok|okay|sure|good|fine|perfetto|ottimo|bene|va bene|certo)[,!]\s+")
});

/// A message's own words: its blocks until the quoted text and the
/// signature.
pub fn own_words(r: &Readable) -> String {
    let mut out = Vec::new();
    for b in &r.blocks {
        let text = b.text();
        let line = text.trim();
        if b.quote > 0 || line == "--" || line.starts_with("-- ") {
            break;
        }
        // "On Oct 20, Luca wrote:" starts the quote.
        if line.ends_with(':')
            && line.len() < 200
            && ["wrote", "scritto", "ha scritto"]
                .iter()
                .any(|w| line.to_lowercase().contains(w))
        {
            break;
        }
        out.push(text);
    }
    out.join("\n")
}

/// Sentences, and clauses after a colon or a semicolon.
fn sentences(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for para in text.split('\n') {
        let mut start = 0;
        let chars: Vec<(usize, char)> = para.char_indices().collect();
        for (i, &(at, c)) in chars.iter().enumerate() {
            let next = chars.get(i + 1).map(|(_, n)| *n);
            let ends = matches!(c, '.' | '!' | '?' | ';' | ':')
                && next.is_none_or(|n| n.is_whitespace())
                // "4 p.m. " and "e.g. " are not the end of a sentence.
                && !(c == '.' && abbreviation(&para[..at]));
            if ends {
                let end = at + c.len_utf8();
                push(&mut out, &para[start..end]);
                start = end;
            }
        }
        push(&mut out, &para[start..]);
    }
    out
}

/// The text ends with a word a full stop shortens: "incl", "p.m", "e.g".
fn abbreviation(before: &str) -> bool {
    let word: String = before
        .chars()
        .rev()
        .take_while(|c| !c.is_whitespace() && *c != '.')
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    (word.chars().count() == 1 && word.chars().all(char::is_alphabetic))
        || [
            "incl", "excl", "approx", "ca", "etc", "ecc", "vs", "nr", "no", "tel", "mr", "mrs",
            "ms", "dr", "sig", "dott", "ing", "avv", "pag", "art",
        ]
        .contains(&word.to_lowercase().as_str())
}

fn push(out: &mut Vec<String>, s: &str) {
    let s = s.trim();
    if !s.is_empty() {
        out.push(s.to_owned());
    }
}

/// A clause made to stand on its own: no "perfect, " before it, a capital
/// first letter, a full stop for a clause cut at a colon, not too long.
fn tidy(s: &str) -> String {
    let s = OPENER.replace(s.trim(), "");
    let mut s = s.trim_end_matches([':', ';', ',']).trim().to_owned();
    if !s.ends_with(['.', '!', '?']) {
        s.push('.');
    }
    if s.chars().count() > 120 {
        let cut: String = s.chars().take(118).collect();
        let cut = cut.rsplit_once(' ').map_or(cut.as_str(), |(a, _)| a);
        s = format!("{}…", cut.trim_end_matches([',', ';', ':']));
    }
    let mut chars = s.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars).collect(),
        None => s,
    }
}

fn numbers(s: &str) -> BTreeSet<String> {
    NUMBER.find_iter(s).map(|m| m.as_str().to_owned()).collect()
}

fn score(s: &str) -> u32 {
    let mut n = 0;
    if DECISION.is_match(s) {
        n += 3;
    }
    if MONEY.is_match(s) {
        n += 3;
    }
    if NUMBER.is_match(s) {
        n += 2;
    }
    if TOPIC.is_match(s) {
        n += 1;
    }
    n
}

/// What the last message asks of you, from where the request begins.
fn request(text: &str) -> Option<String> {
    sentences(text).into_iter().find_map(|s| {
        let m = REQUEST.find(&s)?;
        // From the start of its clause: "I'll forward the invoice, I just
        // need the file" asks for the file.
        let from = s[..m.start()].rfind(", ").map_or(0, |i| i + 2);
        Some(tidy(&s[from..]))
    })
}

/// The gist of a conversation, oldest message first. None when it is
/// short or nothing in it stands out.
pub fn thread(notes: &[Note]) -> Option<Brief> {
    if notes.len() < LONG
        && !notes
            .iter()
            .any(|note| note.text.split_whitespace().count() > LONG_WORDS)
    {
        return None;
    }
    // (score, message, order, text), newest first.
    let mut candidates = Vec::new();
    for (i, note) in notes.iter().enumerate().rev() {
        for (j, s) in sentences(&note.text).into_iter().enumerate() {
            let words = s.split_whitespace().count();
            if ((s.ends_with('?') || REQUEST.is_match(&s)) && notes.len() >= LONG)
                || GREETING.is_match(&s)
                || !(3..=40).contains(&words)
            {
                continue;
            }
            let n = score(&s)
                + if REQUEST.is_match(&s) || (notes.len() < LONG && DATE.is_match(&s)) {
                    3
                } else {
                    0
                };
            if n >= 3 {
                candidates.push((n, i, j, s));
            }
        }
    }
    // Best first; between equals, the newer.
    candidates.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)).then(a.2.cmp(&b.2)));
    let mut picked: Vec<(usize, usize, String)> = Vec::new();
    for (_, i, j, s) in &candidates {
        let nums = numbers(s);
        // Its figures all come again in a later message: skip it.
        let later: BTreeSet<String> = candidates
            .iter()
            .filter(|c| c.1 > *i)
            .flat_map(|c| numbers(&c.3))
            .collect();
        if !nums.is_empty() && nums.is_subset(&later) {
            continue;
        }
        picked.push((*i, *j, tidy(s)));
        if picked.len() == 3 {
            break;
        }
    }
    picked.sort();
    let last = notes.last()?;
    let your_turn = if last.mine { None } else { request(&last.text) };
    let brief = Brief {
        points: picked.into_iter().map(|(_, _, s)| s).collect(),
        your_turn,
    };
    (!brief.points.is_empty() || brief.your_turn.is_some()).then_some(brief)
}

/// "In short" on a sender's card: what they write about and whether the
/// latest waits on you. The app puts it in words.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SenderBrief {
    /// Their emails in the last 30 days.
    pub recent: u32,
    /// The subject most of their recent emails share, without "Re:".
    pub topic: Option<String>,
    /// Their latest email is still unanswered.
    pub waiting: bool,
}

/// The conversation as a system model reads it, where the device has one
/// to rewrite the brief: "Name: own words" a message a line, oldest first.
/// The oldest go first when it runs past [budget] characters, which keeps
/// within the few thousand tokens those models take.
pub fn transcript(lines: &[(String, String)], budget: usize) -> String {
    let mut kept: Vec<String> = Vec::new();
    let mut used = 0;
    for (who, text) in lines.iter().rev() {
        let words = text.split_whitespace().collect::<Vec<_>>().join(" ");
        if words.is_empty() {
            continue;
        }
        let line = format!("{who}: {words}");
        let size = line.chars().count() + 1;
        if used + size > budget {
            if kept.is_empty() {
                kept.push(line.chars().take(budget).collect());
            }
            break;
        }
        used += size;
        kept.push(line);
    }
    kept.reverse();
    kept.join("\n")
}

/// One of a sender's emails, newest first.
#[derive(Debug, Clone)]
pub struct Letter {
    pub subject: String,
    pub received_at: i64,
    pub answered: bool,
}

/// A subject without its "Re:" and "Fwd:".
pub fn bare_subject(subject: &str) -> String {
    let mut s = subject.trim();
    loop {
        let lower = s.to_lowercase();
        let Some(rest) = ["re:", "fwd:", "fw:", "i:", "r:", "rif:"]
            .iter()
            .find(|p| lower.starts_with(*p))
            .map(|p| &s[p.len()..])
        else {
            return s.to_owned();
        };
        s = rest.trim_start();
    }
}

/// None for someone who wrote once or never: their email says it all.
pub fn sender(letters: &[Letter], last_sent_to: Option<i64>, now: i64) -> Option<SenderBrief> {
    if letters.len() < 2 {
        return None;
    }
    let recent = letters
        .iter()
        .filter(|l| l.received_at >= now - 30 * 86_400)
        .count() as u32;
    // The subject that comes back most among the latest ten, the newest
    // between equals; a subject seen once is no topic.
    let mut counts: Vec<(String, usize)> = Vec::new();
    for l in letters.iter().take(10) {
        let s = bare_subject(&l.subject);
        if s.is_empty() {
            continue;
        }
        match counts
            .iter_mut()
            .find(|(k, _)| k.to_lowercase() == s.to_lowercase())
        {
            Some((_, n)) => *n += 1,
            None => counts.push((s, 1)),
        }
    }
    // `max_by_key` keeps the last of equals: reversed, that is the newest.
    let topic = counts
        .iter()
        .rev()
        .filter(|(_, n)| *n >= 2)
        .max_by_key(|(_, n)| *n)
        .map(|(s, _)| s.clone());
    let latest = &letters[0];
    let waiting = !latest.answered
        && last_sent_to.is_none_or(|t| t < latest.received_at)
        && latest.received_at >= now - 14 * 86_400;
    Some(SenderBrief {
        recent,
        topic,
        waiting,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn note(mine: bool, text: &str) -> Note {
        Note {
            mine,
            text: text.into(),
        }
    }

    #[test]
    fn long_single_italian_request() {
        let text = format!(
            "{}\nIl preventivo per foto e video della stagione è di €2500.\nSarebbe bello poter collaborare di nuovo, oppure hai qualcuno cui inviare questa mail?",
            "La nostra destinazione offre paesaggi e attività per tutta la stagione. ".repeat(24)
        );
        let brief = thread(&[note(false, &text)]).unwrap();
        assert!(brief.points.len() <= 3);
        assert!(brief.points.iter().any(|p| p.contains("€2500")));
        assert!(brief.your_turn.unwrap().contains("collaborare"));
        assert!(thread(&[note(true, &text)]).unwrap().your_turn.is_none());
    }

    #[test]
    fn length_is_per_message_and_excludes_quotes() {
        let short = "background ".repeat(LONG_WORDS);
        assert!(thread(&[note(false, &short), note(false, &short)]).is_none());
        let quoted = format!("Please send the quote.\n\n> {}", short.repeat(2));
        let own = own_words(&crate::reading::from_text(&quoted));
        assert!(thread(&[note(false, &own)]).is_none());
        let long = format!("{}\nPlease send the quote.", short);
        assert!(thread(&[note(false, &long), note(true, "Thanks.")]).is_some());
    }

    #[test]
    fn transcript_keeps_the_newest_within_budget() {
        let lines = vec![
            (
                "Matteo".to_owned(),
                "Could I get a quote\nfor 500 catalogs?".to_owned(),
            ),
            ("Sara".to_owned(), "".to_owned()),
            ("Sara".to_owned(), "It comes to €640.".to_owned()),
        ];
        assert_eq!(
            transcript(&lines, 1000),
            "Matteo: Could I get a quote for 500 catalogs?\nSara: It comes to €640."
        );
        assert_eq!(transcript(&lines, 30), "Sara: It comes to €640.");
        assert_eq!(transcript(&lines, 10), "Sara: It c");
    }

    fn print_thread() -> Vec<Note> {
        vec![
            note(true, "Hi Sara,\ncould I get a quote for 500 catalogs, A5, 32 pages? Samples of the 120 g and 150 g paper would help.\nThanks,\nMatteo"),
            note(false, "Hi Matteo,\nsamples went out this morning. With the 120 g paper it comes to €640, delivered on the 28th.\nSara"),
            note(true, "The 120 g feels great, let’s go with it.\nMatteo"),
            note(false, "Hi Matteo,\nperfect, let’s go with the 120 g paper: with it the quote comes to €640 incl. VAT, delivered October 28.\nI’ll forward the invoice as soon as it arrives, I just need the final file by Friday.\nSara"),
        ]
    }

    #[test]
    fn the_newest_words_for_each_fact() {
        let brief = thread(&print_thread()).unwrap();
        assert_eq!(
            brief.points,
            [
                "Let’s go with the 120 g paper.",
                "With it the quote comes to €640 incl. VAT, delivered October 28.",
            ]
        );
        assert_eq!(
            brief.your_turn.as_deref(),
            Some("I just need the final file by Friday.")
        );
    }

    #[test]
    fn short_or_plain_conversations_have_none() {
        assert!(thread(&print_thread()[..3]).is_none());
        let chat = vec![
            note(false, "Hi!"),
            note(true, "Hey, how are you?"),
            note(false, "All good, you?"),
            note(true, "Fine, thanks."),
        ];
        assert!(thread(&chat).is_none());
    }

    #[test]
    fn your_turn_only_when_they_wrote_last() {
        let mut notes = print_thread();
        notes.push(note(true, "Sure, I’ll send it Thursday."));
        assert_eq!(thread(&notes).unwrap().your_turn, None);
    }

    #[test]
    fn own_words_stop_at_the_quote() {
        let r = crate::reading::from_text(
            "Sounds good, booked for €90.\n\nOn Oct 20, Luca wrote:\n> Shall we book it for €90?",
        );
        assert_eq!(own_words(&r), "Sounds good, booked for €90.");
    }

    #[test]
    fn a_sender_in_short() {
        let day = 86_400;
        let now = 100 * day;
        let letter = |subject: &str, days_ago: i64, answered| Letter {
            subject: subject.into(),
            received_at: now - days_ago * day,
            answered,
        };
        let letters = [
            letter("Re: Quote for the Via Roma site", 0, false),
            letter("Quote for the Via Roma site", 3, true),
            letter("Invoice 114", 40, true),
        ];
        assert_eq!(
            sender(&letters, Some(now - 2 * day), now),
            Some(SenderBrief {
                recent: 2,
                topic: Some("Quote for the Via Roma site".into()),
                waiting: true,
            })
        );
        // Between two topics as frequent, the newest.
        let letters = [
            letter("Ducati – alignment", 1, true),
            letter("Re: Ducati – alignment", 2, true),
            letter("BOSCH video", 300, true),
            letter("Re: BOSCH video", 301, true),
        ];
        assert_eq!(
            sender(&letters, None, now).unwrap().topic.as_deref(),
            Some("Ducati – alignment")
        );
        let letters = [
            letter("Re: Quote for the Via Roma site", 0, false),
            letter("Quote for the Via Roma site", 3, true),
            letter("Invoice 114", 40, true),
        ];
        // You wrote back since, from another app.
        assert!(!sender(&letters, Some(now), now).unwrap().waiting);
        assert_eq!(sender(&letters[..1], None, now), None);
    }
}
