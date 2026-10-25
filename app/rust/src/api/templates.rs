//! Templates for compose's "/", kept on this device for every account,
//! as on `FeaturesToApprove`: the list, saving one, and noting its use.

use flutter_rust_bridge::frb;
use piuma_core::MessageTemplate;

use super::engine::{now_secs, reader, store, EngineError};

/// A template: a name, and the subject and text it puts in a message.
#[derive(Debug, Clone)]
pub struct MailTemplate {
    /// 0 for one not kept yet.
    pub id: i64,
    pub name: String,
    pub subject: String,
    pub body: String,
}

impl From<MessageTemplate> for MailTemplate {
    fn from(t: MessageTemplate) -> Self {
        MailTemplate {
            id: t.id,
            name: t.name,
            subject: t.subject,
            body: t.body,
        }
    }
}

/// Every template, the ones used last first, then by name.
#[frb(sync)]
pub fn templates() -> Result<Vec<MailTemplate>, EngineError> {
    Ok(reader()?
        .message_templates()?
        .into_iter()
        .map(MailTemplate::from)
        .collect())
}

/// Keeps a template, a new one when its id is 0. Returns its id.
#[frb(sync)]
pub fn save_template(template: MailTemplate) -> Result<i64, EngineError> {
    Ok(store()?.save_message_template(&MessageTemplate {
        id: template.id,
        name: template.name,
        subject: template.subject,
        body: template.body,
    })?)
}

#[frb(sync)]
pub fn delete_template(id: i64) -> Result<(), EngineError> {
    Ok(store()?.delete_message_template(id)?)
}

/// Notes that a template was just used, so it lists first.
#[frb(sync)]
pub fn template_used(id: i64) -> Result<(), EngineError> {
    Ok(store()?.message_template_used(id, now_secs())?)
}
