//! Managing the mailbox, on this device first: stars and the Starred
//! list, deleting for good, the account's own folders as the person sees
//! them before the server has the change (renamed, deleted, hidden),
//! which folder has which job, how lists are sorted and swiped, and how
//! full each mailbox is. What reaches the server goes through the queue
//! (`pending.rs`), like every other change.

use rusqlite::{params, OptionalExtension};

use super::{row_to_summary, AccountFolder, Result, Store};
use crate::imap::FolderRole;
use crate::model::{AccountId, Flags, ListOrder, MessageSummary};
use crate::pending::{Change, FolderChange};

/// What a swipe on a row does (Settings › Appearance › Lists).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SwipeAction {
    Archive,
    Snooze,
    Delete,
    /// Read, or unread when it is read.
    Read,
    /// Starred, or not when it is.
    Star,
    /// "Move to…".
    Move,
    /// Nothing: that side doesn't swipe.
    Nothing,
}

impl SwipeAction {
    fn tag(self) -> &'static str {
        match self {
            SwipeAction::Archive => "archive",
            SwipeAction::Snooze => "snooze",
            SwipeAction::Delete => "delete",
            SwipeAction::Read => "read",
            SwipeAction::Star => "star",
            SwipeAction::Move => "move",
            SwipeAction::Nothing => "none",
        }
    }

    fn from_tag(tag: &str) -> Option<Self> {
        Some(match tag {
            "archive" => SwipeAction::Archive,
            "snooze" => SwipeAction::Snooze,
            "delete" => SwipeAction::Delete,
            "read" => SwipeAction::Read,
            "star" => SwipeAction::Star,
            "move" => SwipeAction::Move,
            "none" => SwipeAction::Nothing,
            _ => return None,
        })
    }
}

/// How the lists look: their order, conversations or single emails, and
/// what the swipes do. Newest first, in conversations, archive to the
/// right and snooze to the left until changed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ListSettings {
    pub order: ListOrder,
    /// Grouped in conversations.
    pub threads: bool,
    pub swipe_right: SwipeAction,
    pub swipe_left: SwipeAction,
}

impl Default for ListSettings {
    fn default() -> Self {
        ListSettings {
            order: ListOrder::Newest,
            threads: true,
            swipe_right: SwipeAction::Archive,
            swipe_left: SwipeAction::Snooze,
        }
    }
}

const ORDER: &str = "list.order";
const THREADS: &str = "list.threads";
const SWIPE_RIGHT: &str = "list.swipe_right";
const SWIPE_LEFT: &str = "list.swipe_left";

/// How full a mailbox is, as its server last said, in bytes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Quota {
    pub used: u64,
    pub limit: u64,
    /// When the server said so, in Unix seconds.
    pub at: i64,
}

/// The folder doing one job for an account, and whether the person chose
/// it (else the server's marks or a usual name found it).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoleChoice {
    pub role: FolderRole,
    /// Its server name; None while no folder does that job.
    pub mailbox: Option<String>,
    pub chosen: bool,
}

fn role_key(account: AccountId, role: FolderRole) -> String {
    format!("account.{}.role.{}", account.0, role.tag())
}

impl Store {
    /// Stars a message here, or takes its star off, keeping its other
    /// flags.
    pub fn set_flagged(
        &self,
        account: AccountId,
        mailbox: &str,
        uid: u32,
        flagged: bool,
    ) -> Result<()> {
        let bit = Flags {
            flagged: true,
            ..Flags::default()
        }
        .to_bits();
        self.conn.execute(
            "UPDATE message SET flags = CASE WHEN ?4 THEN flags | ?5 ELSE flags & ~?5 END
             WHERE account = ?1 AND mailbox = ?2 AND uid = ?3",
            params![account.0, mailbox, uid, flagged, bit],
        )?;
        Ok(())
    }

    /// Stars messages, or takes their stars off, here at once, and queues
    /// the change for their servers.
    pub fn queue_flags(&self, messages: &[(AccountId, String, u32)], flagged: bool) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        for (account, mailbox, uid) in messages {
            self.set_flagged(*account, mailbox, *uid, flagged)?;
            self.queue_change(*account, mailbox, *uid, Change::Flag(flagged))?;
        }
        tx.commit()?;
        Ok(())
    }

    /// Starred mail of every account (or one), newest first, wherever it
    /// is but Trash, spam and Drafts.
    pub fn starred(&self, account: Option<AccountId>) -> Result<Vec<MessageSummary>> {
        let mut stmt = self.conn.prepare(
            "SELECT m.account, m.mailbox, m.uid, m.from_name, m.from_email, m.subject, m.preview,
                    m.received_at, m.flags, m.message_id, m.refs, m.reply_to, m.to_list
               FROM message m
              WHERE (m.flags & 2) <> 0 AND m.hidden = 0 AND m.folder <> 'drafts'
                AND (?1 IS NULL OR m.account = ?1)
                AND m.mailbox NOT IN (SELECT value FROM setting
                     WHERE key = 'account.' || m.account || '.trash'
                        OR key = 'account.' || m.account || '.junk')
              ORDER BY m.received_at DESC, m.account, m.uid DESC",
        )?;
        let rows = stmt.query_map(params![account.map(|a| a.0)], row_to_summary)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Remembers the account's Trash, by its server name, or that it has
    /// none.
    pub fn set_trash_mailbox(&self, account: AccountId, mailbox: Option<&str>) -> Result<()> {
        self.set_setting(
            &format!("account.{}.trash", account.0),
            mailbox.unwrap_or_default(),
        )
    }

    /// The account's Trash, once a sync found it.
    pub fn trash_mailbox(&self, account: AccountId) -> Result<Option<String>> {
        Ok(self
            .setting(&format!("account.{}.trash", account.0))?
            .filter(|m| !m.is_empty()))
    }

    /// Whether Delete in `mailbox` deletes for good: in Trash and in spam,
    /// where moving to Trash would only put it back.
    pub fn deletes_for_good(&self, account: AccountId, mailbox: &str) -> Result<bool> {
        Ok(self.trash_mailbox(account)?.as_deref() == Some(mailbox)
            || self.junk_mailbox(account)?.as_deref() == Some(mailbox))
    }

    /// Hides messages of one folder and queues their deletion for good.
    pub fn queue_erase(&self, account: AccountId, mailbox: &str, uids: &[u32]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        for uid in uids {
            self.set_hidden(account, mailbox, *uid, true)?;
            self.queue_change(account, mailbox, *uid, Change::Erase)?;
        }
        tx.commit()?;
        Ok(())
    }

    /// How many messages of one folder are here, shown or not.
    pub fn messages_in(&self, account: AccountId, mailbox: &str) -> Result<u32> {
        Ok(self.conn.query_row(
            "SELECT COUNT(*) FROM message WHERE account = ?1 AND mailbox = ?2 AND hidden = 0",
            params![account.0, mailbox],
            |r| r.get(0),
        )?)
    }

    /// One of the account's own folders, by its server name.
    pub fn account_folder(
        &self,
        account: AccountId,
        mailbox: &str,
    ) -> Result<Option<AccountFolder>> {
        Ok(self
            .account_folders(account)?
            .into_iter()
            .find(|f| f.mailbox == mailbox))
    }

    /// [`Store::account_folder`]'s subfolders, at any depth: the folders
    /// under it in tree order, down to the next one as high as it.
    fn subfolders(&self, account: AccountId, folder: &AccountFolder) -> Result<Vec<String>> {
        let list = self.account_folders(account)?;
        let Some(at) = list.iter().position(|f| f.mailbox == folder.mailbox) else {
            return Ok(Vec::new());
        };
        Ok(list[at + 1..]
            .iter()
            .take_while(|f| f.depth > folder.depth)
            .map(|f| f.mailbox.clone())
            .collect())
    }

    /// Renames one of the account's own folders here and queues it for
    /// the server. On IMAP its server name changes ("Clients/Acme" to
    /// "Clients/Acme Ltd", its subfolders with it) and its mail here is
    /// read again from the server under the new name; changes waiting for
    /// it follow it. On JMAP, where folders are named by id, only what the
    /// person reads changes. Returns its server name now.
    pub fn rename_folder(&self, account: AccountId, mailbox: &str, name: &str) -> Result<String> {
        let name = name.trim();
        let Some(folder) = self.account_folder(account, mailbox)? else {
            return Ok(mailbox.to_owned());
        };
        if folder.delimiter.is_empty() {
            // Named by id (JMAP), or by a server that has no tree.
            let jmap = self.is_jmap(account)?;
            let to = if jmap {
                mailbox.to_owned()
            } else {
                crate::imap::utf7_encode(name)
            };
            let tx = self.conn.unchecked_transaction()?;
            self.conn.execute(
                "UPDATE account_folder SET name = ?3 WHERE account = ?1 AND mailbox = ?2",
                params![account.0, mailbox, name],
            )?;
            if !jmap {
                self.move_folder_here(account, mailbox, &to, "")?;
            }
            self.queue_change(
                account,
                mailbox,
                0,
                Change::Folder(FolderChange::Rename(if jmap {
                    name.to_owned()
                } else {
                    to.clone()
                })),
            )?;
            tx.commit()?;
            return Ok(to);
        }
        let parent = match mailbox.rfind(folder.delimiter.as_str()) {
            Some(i) => &mailbox[..i + folder.delimiter.len()],
            None => "",
        };
        let to = format!("{parent}{}", crate::imap::utf7_encode(name));
        if to == mailbox {
            return Ok(to);
        }
        let tx = self.conn.unchecked_transaction()?;
        self.conn.execute(
            "UPDATE account_folder SET name = ?3 WHERE account = ?1 AND mailbox = ?2",
            params![account.0, mailbox, name],
        )?;
        self.move_folder_here(account, mailbox, &to, &folder.delimiter)?;
        self.queue_change(
            account,
            mailbox,
            0,
            Change::Folder(FolderChange::Rename(to.clone())),
        )?;
        tx.commit()?;
        Ok(to)
    }

    /// Whether the account is a JMAP one.
    fn is_jmap(&self, account: AccountId) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT kind FROM account WHERE id = ?1",
                params![account.0],
                |r| r.get::<_, String>(0),
            )
            .optional()?
            .is_some_and(|k| k == "jmap"))
    }

    /// Everything kept under a folder's server name `from` (and its
    /// subfolders', after `delimiter`) goes under `to`: its place in the
    /// list, its order, its numbers, and the changes waiting for its mail.
    /// The mail itself is read again from the server.
    fn move_folder_here(
        &self,
        account: AccountId,
        from: &str,
        to: &str,
        delimiter: &str,
    ) -> Result<()> {
        // `from`, and `from` + delimiter + anything when there is one.
        let under = |column: &str| {
            if delimiter.is_empty() {
                format!("{column} = ?2")
            } else {
                format!(
                    "({column} = ?2 OR substr({column}, 1, length(?2) + length(?4)) = ?2 || ?4)"
                )
            }
        };
        let renamed = |column: &str| format!("?3 || substr({column}, length(?2) + 1)");
        let p = params![account.0, from, to, delimiter];
        for (table, column, extra) in [
            ("account_folder", "mailbox", ""),
            ("folder_order", "mailbox", ""),
            ("mailbox", "name", ""),
            ("folder_role", "mailbox", ""),
            // The folder's own operations keep the name they were made on.
            (
                "pending_change",
                "mailbox",
                " AND change NOT LIKE 'folder.%'",
            ),
        ] {
            let sql = format!(
                "UPDATE {table} SET {column} = {} WHERE account = ?1 AND {}{extra}",
                renamed(column),
                under(column)
            );
            if delimiter.is_empty() {
                self.conn.execute(&sql, params![account.0, from, to])?;
            } else {
                self.conn.execute(&sql, p)?;
            }
        }
        // Numbers stay the server's, but every flag is looked at again.
        let sql = format!(
            "UPDATE mailbox SET highest_modseq = NULL WHERE account = ?1 AND {}",
            under("name").replace("?2", "?3")
        );
        if delimiter.is_empty() {
            self.conn.execute(&sql, params![account.0, from, to])?;
        } else {
            self.conn.execute(&sql, p)?;
        }
        let sql = format!(
            "DELETE FROM message WHERE account = ?1 AND {}",
            under("mailbox")
        );
        if delimiter.is_empty() {
            self.conn.execute(&sql, params![account.0, from])?;
        } else {
            self.conn.execute(
                &sql.replace("?4", "?3"),
                params![account.0, from, delimiter],
            )?;
        }
        Ok(())
    }

    /// Deletes one of the account's own folders here (with its
    /// subfolders) and queues it for the server, where its mail goes to
    /// Trash first. Its mail is hidden meanwhile. Returns how many emails
    /// go to Trash, as far as this device knows.
    pub fn delete_folder(&self, account: AccountId, mailbox: &str) -> Result<u32> {
        let Some(folder) = self.account_folder(account, mailbox)? else {
            return Ok(0);
        };
        let mut gone = self.subfolders(account, &folder)?;
        gone.push(folder.mailbox.clone());
        let tx = self.conn.unchecked_transaction()?;
        let mut moved = 0;
        for m in &gone {
            moved += self.conn.execute(
                "UPDATE message SET hidden = 1 WHERE account = ?1 AND mailbox = ?2",
                params![account.0, m],
            )? as u32;
            self.conn.execute(
                "DELETE FROM account_folder WHERE account = ?1 AND mailbox = ?2",
                params![account.0, m],
            )?;
        }
        self.queue_change(account, mailbox, 0, Change::Folder(FolderChange::Delete))?;
        tx.commit()?;
        Ok(moved)
    }

    /// The emails a folder and its subfolders hold, as far as the server
    /// last said: what Delete folder sends to Trash. With how many
    /// subfolders go with it.
    pub fn folder_contents(&self, account: AccountId, mailbox: &str) -> Result<(u32, u32)> {
        let Some(folder) = self.account_folder(account, mailbox)? else {
            return Ok((0, 0));
        };
        let subfolders = self.subfolders(account, &folder)?;
        let mut total = folder.total.max(self.messages_in(account, mailbox)?);
        for m in &subfolders {
            if let Some(f) = self.account_folder(account, m)? {
                total += f.total.max(self.messages_in(account, m)?);
            }
        }
        Ok((total, subfolders.len() as u32))
    }

    /// Shows one of the account's own folders in the lists (subscribed)
    /// or hides it, here and, queued, on the server.
    pub fn subscribe_folder(&self, account: AccountId, mailbox: &str, on: bool) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        self.conn.execute(
            "UPDATE account_folder SET subscribed = ?3 WHERE account = ?1 AND mailbox = ?2",
            params![account.0, mailbox, on],
        )?;
        self.conn.execute(
            "DELETE FROM pending_change WHERE account = ?1 AND mailbox = ?2
               AND change IN ('folder.subscribe', 'folder.unsubscribe')",
            params![account.0, mailbox],
        )?;
        self.queue_change(
            account,
            mailbox,
            0,
            Change::Folder(FolderChange::Subscribe(on)),
        )?;
        tx.commit()?;
        Ok(())
    }

    /// The folder the person chose for a job, if they did.
    pub fn role_choice(&self, account: AccountId, role: FolderRole) -> Result<Option<String>> {
        Ok(self
            .setting(&role_key(account, role))?
            .filter(|m| !m.is_empty()))
    }

    /// Every job the person gave a folder of their choice.
    pub fn role_choices(&self, account: AccountId) -> Result<Vec<(FolderRole, String)>> {
        let mut out = Vec::new();
        for role in FolderRole::CHOOSABLE {
            if let Some(m) = self.role_choice(account, role)? {
                out.push((role, m));
            }
        }
        Ok(out)
    }

    /// Gives a job to a folder of the person's choice, by its server name,
    /// or with None goes back to what the server says. It wins over the
    /// server's marks and the usual names from the next look at the
    /// folders on.
    pub fn set_role_choice(
        &self,
        account: AccountId,
        role: FolderRole,
        mailbox: Option<&str>,
    ) -> Result<()> {
        match mailbox {
            Some(m) => self.set_setting(&role_key(account, role), m),
            None => self.remove_setting(&role_key(account, role)),
        }
    }

    /// Which folder does each job the person can choose, as the last look
    /// at the server found, and whether the person chose it.
    pub fn roles(&self, account: AccountId) -> Result<Vec<RoleChoice>> {
        let mut out = Vec::new();
        for role in FolderRole::CHOOSABLE {
            let chosen = self.role_choice(account, role)?;
            let found = match role {
                FolderRole::Trash => self.trash_mailbox(account)?,
                FolderRole::Junk => self.junk_mailbox(account)?,
                FolderRole::Sent => self.folder_mailbox(account, crate::Folder::Sent)?,
                FolderRole::Drafts => self.folder_mailbox(account, crate::Folder::Drafts)?,
                FolderRole::Archive => self.folder_mailbox(account, crate::Folder::Archive)?,
                FolderRole::Snoozed => self.folder_mailbox(account, crate::Folder::Snoozed)?,
            };
            out.push(RoleChoice {
                role,
                chosen: chosen.is_some(),
                mailbox: chosen.or(found),
            });
        }
        Ok(out)
    }

    /// Remembers every folder the server listed, by server name with the
    /// name people read, so a job can be given to any of them offline.
    pub fn set_server_folders(
        &self,
        account: AccountId,
        folders: &[(String, String)],
    ) -> Result<()> {
        let list: Vec<[&str; 2]> = folders
            .iter()
            .map(|(m, n)| [m.as_str(), n.as_str()])
            .collect();
        self.set_setting(
            &format!("account.{}.folders", account.0),
            &serde_json::to_string(&list).unwrap_or_default(),
        )
    }

    /// Every folder the server last listed: (server name, name people
    /// read).
    pub fn server_folders(&self, account: AccountId) -> Result<Vec<(String, String)>> {
        let raw = self
            .setting(&format!("account.{}.folders", account.0))?
            .unwrap_or_default();
        let list: Vec<[String; 2]> = serde_json::from_str(&raw).unwrap_or_default();
        Ok(list.into_iter().map(|[m, n]| (m, n)).collect())
    }

    /// How the lists look.
    pub fn list_settings(&self) -> Result<ListSettings> {
        let d = ListSettings::default();
        Ok(ListSettings {
            order: self
                .setting(ORDER)?
                .map_or(d.order, |t| ListOrder::from_tag(&t)),
            threads: self.setting(THREADS)?.as_deref() != Some("off"),
            swipe_right: self
                .setting(SWIPE_RIGHT)?
                .and_then(|t| SwipeAction::from_tag(&t))
                .unwrap_or(d.swipe_right),
            swipe_left: self
                .setting(SWIPE_LEFT)?
                .and_then(|t| SwipeAction::from_tag(&t))
                .unwrap_or(d.swipe_left),
        })
    }

    pub fn set_list_settings(&self, settings: ListSettings) -> Result<()> {
        self.set_setting(ORDER, settings.order.tag())?;
        self.set_setting(THREADS, if settings.threads { "on" } else { "off" })?;
        self.set_setting(SWIPE_RIGHT, settings.swipe_right.tag())?;
        self.set_setting(SWIPE_LEFT, settings.swipe_left.tag())?;
        Ok(())
    }

    /// Keeps what the server said about how full the mailbox is; None
    /// when it doesn't say.
    pub fn set_quota(&self, account: AccountId, quota: Option<Quota>) -> Result<()> {
        let key = format!("account.{}.quota", account.0);
        match quota {
            Some(q) => self.set_setting(&key, &format!("{} {} {}", q.used, q.limit, q.at)),
            None => self.remove_setting(&key),
        }
    }

    /// How full the mailbox was when the server last said.
    pub fn quota(&self, account: AccountId) -> Result<Option<Quota>> {
        let Some(raw) = self.setting(&format!("account.{}.quota", account.0))? else {
            return Ok(None);
        };
        let mut parts = raw.split(' ').map(str::parse::<i64>);
        let (Some(Ok(used)), Some(Ok(limit)), Some(Ok(at))) =
            (parts.next(), parts.next(), parts.next())
        else {
            return Ok(None);
        };
        Ok(Some(Quota {
            used: used.max(0) as u64,
            limit: limit.max(0) as u64,
            at,
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Account, AccountKind, ListInfo, ReplyInfo, Security, Server};
    use crate::Folder;

    fn account(store: &Store) -> AccountId {
        store
            .add_account(&Account {
                id: AccountId(0),
                name: "Work".into(),
                email: "me@work.it".into(),
                sender_name: String::new(),
                color: "#3451D1".into(),
                kind: AccountKind::Imap {
                    imap: Server {
                        host: "imap.work.it".into(),
                        port: 993,
                        security: Security::Tls,
                    },
                    smtp: Server {
                        host: "smtp.work.it".into(),
                        port: 465,
                        security: Security::Tls,
                    },
                    username: "me".into(),
                },
            })
            .unwrap()
    }

    fn msg(account: AccountId, mailbox: &str, uid: u32, at: i64) -> MessageSummary {
        MessageSummary {
            account,
            mailbox: mailbox.into(),
            uid,
            from_name: String::new(),
            from_email: format!("sender{uid}@example.org"),
            to: String::new(),
            subject: format!("Message {uid}"),
            preview: String::new(),
            received_at: at,
            flags: Flags::default(),
            reply: ReplyInfo::default(),
            list: ListInfo::default(),
        }
    }

    fn folder(mailbox: &str, depth: u32) -> AccountFolder {
        AccountFolder {
            mailbox: mailbox.into(),
            name: mailbox.rsplit('/').next().unwrap().into(),
            depth,
            selectable: true,
            unread: 0,
            total: 0,
            subscribed: true,
            delimiter: "/".into(),
        }
    }

    #[test]
    fn stars_wait_for_the_server_and_list_apart() {
        let mut store = Store::open_in_memory().unwrap();
        let a = account(&store);
        store
            .upsert_messages(&[
                msg(a, "INBOX", 1, 100),
                msg(a, "INBOX", 2, 200),
                msg(a, "Trash", 3, 300),
            ])
            .unwrap();
        store.set_trash_mailbox(a, Some("Trash")).unwrap();
        store
            .queue_flags(
                &[
                    (a, "INBOX".into(), 1),
                    (a, "INBOX".into(), 2),
                    (a, "Trash".into(), 3),
                ],
                true,
            )
            .unwrap();
        // Trash keeps its stars out of Starred.
        let starred: Vec<u32> = store.starred(None).unwrap().iter().map(|m| m.uid).collect();
        assert_eq!(starred, [2, 1]);
        // Unstarred before the star went: one change waits, the last.
        store.queue_flags(&[(a, "INBOX".into(), 2)], false).unwrap();
        let waiting: Vec<Change> = store
            .pending_changes(a)
            .unwrap()
            .into_iter()
            .filter(|p| p.uid == 2)
            .map(|p| p.change)
            .collect();
        assert_eq!(waiting, [Change::Flag(false)]);
        // A sync that read the server's flags before the change got there
        // doesn't put the star back.
        let server = Flags {
            flagged: true,
            ..Flags::default()
        };
        store.update_flags(a, "INBOX", &[(2, server)]).unwrap();
        assert!(!store.message(a, "INBOX", 2).unwrap().unwrap().flags.flagged);
        assert_eq!(store.starred(Some(a)).unwrap().len(), 1);
    }

    #[test]
    fn delete_in_trash_and_spam_is_for_good() {
        let store = Store::open_in_memory().unwrap();
        let a = account(&store);
        store.set_trash_mailbox(a, Some("Trash")).unwrap();
        store.set_junk_mailbox(a, Some("Spam")).unwrap();
        assert!(store.deletes_for_good(a, "Trash").unwrap());
        assert!(store.deletes_for_good(a, "Spam").unwrap());
        assert!(!store.deletes_for_good(a, "INBOX").unwrap());
        assert!(!store.deletes_for_good(a, "Projects").unwrap());
    }

    #[test]
    fn a_renamed_folder_takes_its_subfolders_and_waiting_changes() {
        let mut store = Store::open_in_memory().unwrap();
        let a = account(&store);
        store
            .set_account_folders(
                a,
                &[
                    folder("Clients", 0),
                    folder("Clients/Acme", 1),
                    folder("Clientele", 0),
                ],
            )
            .unwrap();
        store
            .upsert_messages(&[msg(a, "Clients/Acme", 7, 100), msg(a, "Clientele", 8, 100)])
            .unwrap();
        store
            .set_mailbox_state(
                a,
                "Clients/Acme",
                crate::MailboxState {
                    uid_validity: 9,
                    highest_modseq: Some(4),
                },
            )
            .unwrap();
        store
            .queue_change(a, "Clients/Acme", 7, Change::Seen(true))
            .unwrap();
        let to = store.rename_folder(a, "Clients", "Customers").unwrap();
        assert_eq!(to, "Customers");
        let names: Vec<String> = store
            .account_folders(a)
            .unwrap()
            .into_iter()
            .map(|f| f.mailbox)
            .collect();
        assert_eq!(names, ["Customers", "Customers/Acme", "Clientele"]);
        // A folder whose name merely starts the same stays.
        assert!(store.message(a, "Clientele", 8).unwrap().is_some());
        // The subfolder's numbers and changes follow it; its mail is read
        // again.
        let state = store.mailbox_state(a, "Customers/Acme").unwrap().unwrap();
        assert_eq!((state.uid_validity, state.highest_modseq), (9, None));
        assert!(store.message(a, "Clients/Acme", 7).unwrap().is_none());
        let waiting: Vec<(String, Change)> = store
            .pending_changes(a)
            .unwrap()
            .into_iter()
            .map(|p| (p.mailbox, p.change))
            .collect();
        assert_eq!(
            waiting,
            [
                ("Customers/Acme".into(), Change::Seen(true)),
                (
                    "Clients".into(),
                    Change::Folder(FolderChange::Rename("Customers".into()))
                ),
            ]
        );
    }

    #[test]
    fn a_deleted_folder_hides_its_mail_and_its_subfolders() {
        let mut store = Store::open_in_memory().unwrap();
        let a = account(&store);
        let mut acme = folder("Clients/Acme", 1);
        acme.total = 4;
        store
            .set_account_folders(a, &[folder("Clients", 0), acme, folder("Home", 0)])
            .unwrap();
        store
            .upsert_messages(&[msg(a, "Clients", 1, 100), msg(a, "Clients/Acme", 2, 100)])
            .unwrap();
        assert_eq!(store.folder_contents(a, "Clients").unwrap(), (5, 1));
        store.delete_folder(a, "Clients").unwrap();
        let names: Vec<String> = store
            .account_folders(a)
            .unwrap()
            .into_iter()
            .map(|f| f.mailbox)
            .collect();
        assert_eq!(names, ["Home"]);
        assert_eq!(store.messages_in(a, "Clients").unwrap(), 0);
        // Hidden, not gone, until the server has them in Trash.
        assert!(store.message(a, "Clients", 1).unwrap().is_some());
    }

    #[test]
    fn a_chosen_folder_wins_over_the_one_found() {
        let store = Store::open_in_memory().unwrap();
        let a = account(&store);
        store.set_folder_role(a, Folder::Sent, "Sent").unwrap();
        store.set_trash_mailbox(a, Some("Trash")).unwrap();
        store
            .set_role_choice(a, FolderRole::Trash, Some("Papierkorb"))
            .unwrap();
        let roles = store.roles(a).unwrap();
        let trash = roles.iter().find(|r| r.role == FolderRole::Trash).unwrap();
        assert_eq!(trash.mailbox.as_deref(), Some("Papierkorb"));
        assert!(trash.chosen);
        let sent = roles.iter().find(|r| r.role == FolderRole::Sent).unwrap();
        assert_eq!(sent.mailbox.as_deref(), Some("Sent"));
        assert!(!sent.chosen);
        store.set_role_choice(a, FolderRole::Trash, None).unwrap();
        assert!(store.role_choices(a).unwrap().is_empty());
    }

    #[test]
    fn lists_sort_and_split_conversations_as_set() {
        let mut store = Store::open_in_memory().unwrap();
        let a = account(&store);
        let mut first = msg(a, "INBOX", 1, 100);
        first.from_name = "Zoe".into();
        first.reply.message_id = "<1@x>".into();
        let mut reply = msg(a, "INBOX", 2, 200);
        reply.from_name = "Anna".into();
        reply.subject = "Re: Message 1".into();
        reply.reply.message_id = "<2@x>".into();
        reply.reply.references = "<1@x>".into();
        let mut other = msg(a, "INBOX", 3, 150);
        other.from_name = "Mia".into();
        store.upsert_messages(&[first, reply, other]).unwrap();
        let uids = |filter: crate::ListFilter| -> Vec<(u32, u32)> {
            store
                .conversations_page(Folder::Inbox, None, filter, 0, 10)
                .unwrap()
                .into_iter()
                .map(|c| (c.latest.uid, c.messages))
                .collect()
        };
        assert_eq!(uids(Default::default()), [(2, 2), (3, 1)]);
        let flat = crate::ListFilter {
            flat: true,
            ..Default::default()
        };
        assert_eq!(uids(flat), [(2, 1), (3, 1), (1, 1)]);
        let oldest = crate::ListFilter {
            flat: true,
            order: ListOrder::Oldest,
            ..Default::default()
        };
        assert_eq!(uids(oldest), [(1, 1), (3, 1), (2, 1)]);
        let sender = crate::ListFilter {
            flat: true,
            order: ListOrder::Sender,
            ..Default::default()
        };
        assert_eq!(uids(sender), [(2, 1), (3, 1), (1, 1)]);
        assert_eq!(
            store.conversation_count(Folder::Inbox, None, flat).unwrap(),
            3
        );
        assert_eq!(
            store
                .conversation_count(Folder::Inbox, None, crate::ListFilter::default())
                .unwrap(),
            2
        );
    }

    #[test]
    fn list_settings_and_quota_are_kept() {
        let store = Store::open_in_memory().unwrap();
        let a = account(&store);
        assert_eq!(store.list_settings().unwrap(), ListSettings::default());
        let set = ListSettings {
            order: ListOrder::Sender,
            threads: false,
            swipe_right: SwipeAction::Delete,
            swipe_left: SwipeAction::Nothing,
        };
        store.set_list_settings(set).unwrap();
        assert_eq!(store.list_settings().unwrap(), set);
        assert_eq!(store.quota(a).unwrap(), None);
        let q = Quota {
            used: 900,
            limit: 1000,
            at: 5,
        };
        store.set_quota(a, Some(q)).unwrap();
        assert_eq!(store.quota(a).unwrap(), Some(q));
    }
}
