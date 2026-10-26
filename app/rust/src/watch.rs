//! What a paired watch shows (`WatchWearOS`): the phone keeps the mail and
//! the watch gets a small summary of the inbox, the text of an email it
//! opens, and the person's templates. Nothing about accounts or passwords
//! goes to the watch. Its Kotlin side is `WatchLink.kt`; the JNI wrappers
//! are in `android.rs`, so this file builds and tests everywhere.

use crate::api::engine::{self, BlockKind, BodyBlock, EngineError, InboxTab, MailFolder};
use crate::background::quote;

/// How many conversations the watch lists.
pub const ROWS: u32 = 20;

/// How much of an email the watch shows, in characters: enough for a
/// glance; the rest waits on the phone.
const TEXT_LIMIT: usize = 4000;

/// One account as the watch sees it: its name for the dot, and how many
/// conversations wait unread.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WatchAccount {
    pub id: i64,
    pub name: String,
    pub color: String,
    pub unread: u32,
}

/// One row of the watch's inbox; [payload] is the notice's
/// "account\nmailbox\nuid", so the watch's buttons act as a notice's do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WatchRow {
    pub payload: String,
    pub account_id: i64,
    pub sender: String,
    pub subject: String,
    pub preview: String,
    pub received_at: i64,
    pub seen: bool,
    pub messages: u32,
}

/// The summary as JSON: `{"at","accounts":[…],"rows":[…],"templates":[…]}`.
pub fn summary_json(
    at: i64,
    accounts: &[WatchAccount],
    rows: &[WatchRow],
    templates: &[(String, String)],
) -> String {
    let accounts: Vec<String> = accounts
        .iter()
        .map(|a| {
            format!(
                r#"{{"id":{},"name":{},"color":{},"unread":{}}}"#,
                a.id,
                quote(&a.name),
                quote(&a.color),
                a.unread
            )
        })
        .collect();
    let rows: Vec<String> = rows
        .iter()
        .map(|r| {
            format!(
                r#"{{"payload":{},"account":{},"sender":{},"subject":{},"preview":{},"at":{},"seen":{},"messages":{}}}"#,
                quote(&r.payload),
                r.account_id,
                quote(&r.sender),
                quote(&r.subject),
                quote(&r.preview),
                r.received_at,
                r.seen,
                r.messages
            )
        })
        .collect();
    let templates: Vec<String> = templates
        .iter()
        .map(|(name, body)| format!(r#"{{"name":{},"body":{}}}"#, quote(name), quote(body)))
        .collect();
    format!(
        r#"{{"at":{},"accounts":[{}],"rows":[{}],"templates":[{}]}}"#,
        at,
        accounts.join(","),
        rows.join(","),
        templates.join(",")
    )
}

/// The inbox as the watch shows it, newest first; "" when the engine
/// can't say.
pub fn summary() -> Result<String, EngineError> {
    let accounts = engine::accounts()?
        .into_iter()
        .map(|a| {
            let unread = engine::folder_unread(
                MailFolder::Inbox,
                Some(a.id),
                None,
                None,
                Some(InboxTab::All),
            )
            .unwrap_or(0);
            WatchAccount {
                id: a.id,
                name: a.name,
                color: a.color,
                unread,
            }
        })
        .collect::<Vec<_>>();
    let rows = engine::folder_page(
        MailFolder::Inbox,
        None,
        None,
        None,
        Some(InboxTab::All),
        false,
        0,
        ROWS,
    )?
    .into_iter()
    .map(|r| WatchRow {
        payload: format!("{}\n{}\n{}", r.account_id, r.mailbox, r.uid),
        account_id: r.account_id,
        sender: if r.from_name.is_empty() {
            r.from_email
        } else {
            r.from_name
        },
        subject: r.subject,
        preview: r.preview,
        received_at: r.received_at,
        seen: r.seen,
        messages: r.messages,
    })
    .collect::<Vec<_>>();
    let templates = crate::api::templates::templates()
        .unwrap_or_default()
        .into_iter()
        .filter(|t| !t.body.trim().is_empty())
        .map(|t| (t.name, t.body))
        .collect::<Vec<_>>();
    Ok(summary_json(
        engine::now_secs(),
        &accounts,
        &rows,
        &templates,
    ))
}

/// The words of an email, as plain paragraphs: no pictures, no links to
/// follow, cut at [TEXT_LIMIT] with "…".
pub fn plain_text(blocks: &[BodyBlock]) -> String {
    let mut out = String::new();
    for b in blocks {
        let words: String = b.spans.iter().map(|s| s.text.as_str()).collect();
        let words = words.trim();
        if words.is_empty() || matches!(b.kind, BlockKind::Image | BlockKind::Rule) {
            continue;
        }
        // Quoted replies stay on the phone.
        if b.quote > 0 {
            continue;
        }
        if !out.is_empty() {
            out.push_str("\n\n");
        }
        if b.kind == BlockKind::ListItem {
            out.push_str("• ");
        }
        out.push_str(words);
        if out.chars().count() > TEXT_LIMIT {
            let cut: String = out.chars().take(TEXT_LIMIT).collect();
            return format!("{}…", cut.trim_end());
        }
    }
    out
}

/// The text of the email [payload] names, as `{"payload","text"}`; the
/// email is read, as opening it on the phone would.
pub fn text(payload: &str, utc_offset_minutes: i32) -> Result<String, EngineError> {
    let message = crate::background::message_of(payload)
        .ok_or_else(|| EngineError::new(engine::ErrorKind::Other, "unknown message"))?;
    let engine = engine::engine()?;
    let readable = engine.runtime.block_on(engine::message_readable(
        message.account_id,
        message.mailbox.clone(),
        message.uid,
        utc_offset_minutes,
    ))?;
    engine::set_messages_seen(vec![message.clone()], true)?;
    engine
        .runtime
        .block_on(engine::push_messages_seen(vec![message], true))
        .ok();
    Ok(format!(
        r#"{{"payload":{},"text":{}}}"#,
        quote(payload),
        quote(&plain_text(&readable.blocks))
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::engine::TextSpan;

    fn block(kind: BlockKind, quote: u8, text: &str) -> BodyBlock {
        BodyBlock {
            kind,
            level: 0,
            quote,
            marker: String::new(),
            spans: vec![TextSpan {
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
    fn the_summary_is_json_the_watch_reads() {
        let json = summary_json(
            1_792_400_000,
            &[WatchAccount {
                id: 2,
                name: "Personal \"P\"".into(),
                color: "#E0782F".into(),
                unread: 2,
            }],
            &[WatchRow {
                payload: "2\nINBOX\n41".into(),
                account_id: 2,
                sender: "Giulia Romano".into(),
                subject: "Dinner on Friday?".into(),
                preview: "I booked\nOsteria".into(),
                received_at: 1_792_399_000,
                seen: false,
                messages: 1,
            }],
            &[("On my way".into(), "I'm on my way".into())],
        );
        assert!(json.starts_with(
            r##"{"at":1792400000,"accounts":[{"id":2,"name":"Personal \"P\"","color":"#E0782F","unread":2}]"##
        ));
        assert!(json.contains(r#""payload":"2\nINBOX\n41","account":2,"sender":"Giulia Romano""#));
        assert!(json.contains(
            r#""preview":"I booked\nOsteria","at":1792399000,"seen":false,"messages":1"#
        ));
        assert!(json.ends_with(r#""templates":[{"name":"On my way","body":"I'm on my way"}]}"#));
        assert_eq!(
            summary_json(0, &[], &[], &[]),
            r#"{"at":0,"accounts":[],"rows":[],"templates":[]}"#
        );
    }

    #[test]
    fn plain_text_keeps_the_words_and_leaves_quotes_out() {
        let text = plain_text(&[
            block(BlockKind::Paragraph, 0, " I booked Osteria del Ponte. "),
            block(BlockKind::Image, 0, "logo"),
            block(BlockKind::ListItem, 0, "Bring the game"),
            block(BlockKind::Paragraph, 1, "On Thursday Matteo wrote:"),
            block(BlockKind::Rule, 0, ""),
        ]);
        assert_eq!(text, "I booked Osteria del Ponte.\n\n• Bring the game");
    }

    #[test]
    fn plain_text_stops_at_the_limit() {
        let long = "word ".repeat(2000);
        let text = plain_text(&[block(BlockKind::Paragraph, 0, &long)]);
        assert!(text.ends_with('…'));
        assert_eq!(text.chars().count(), TEXT_LIMIT);
    }
}
