import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/widgets.dart' show StringCharacters;

import 'calendars.dart';
import 'features.dart';
import 'readable.dart';
import 'sender_pictures.dart';

export 'calendars.dart';
export 'features.dart';
export 'readable.dart';

/// An account as the interface shows it.
class MailAccount {
  const MailAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.color,
    this.senderName = '',
  });

  final int id;
  final String name;
  final String email;
  final Color color;

  /// The person's name in From; may be empty.
  final String senderName;

  /// What From shows: the person's name, else the account's.
  String get fromLabel => senderName.isNotEmpty ? senderName : name;
}

/// A list of every account's messages with the same job.
enum MailFolder {
  inbox,
  sent,
  archive,
  drafts,
  newsletters,

  /// Mail put away until a time, soonest back first.
  snoozed,

  /// Mail you sent that nobody has answered yet, newest first. Its rows
  /// are in Sent.
  waiting,

  /// Not a list of emails: the cards read from receipts, bills, parcels
  /// and bookings, wherever those emails are.
  vault,

  /// Not a list of emails: every file received, wherever its email is.
  attachments,

  /// Every email with one label, wherever it is (`LabelsToApprove`).
  label,
}

/// A colored word on emails, shared across accounts (`LabelsToApprove`).
class MailLabel {
  const MailLabel({
    required this.id,
    required this.name,
    required this.color,
    required this.keyword,
    this.count = 0,
  });

  final int id;
  final String name;

  /// amber, teal, coral, blue or violet: a pair of `PiumaLabelColors`.
  final String color;

  /// What the server keeps on each email; it stays when the label is
  /// renamed.
  final String keyword;

  /// How many emails carry it, outside the trash.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is MailLabel &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.keyword == keyword &&
      other.count == count;

  @override
  int get hashCode => Object.hash(id, name, color, keyword, count);
}

/// The five label colors, in the order new labels take them.
const labelColors = ['amber', 'teal', 'coral', 'blue', 'violet'];

/// An address a sender writes from, for their card's Addresses
/// (`PhoneSender`): "Work · 18 emails" and the verified mark.
class SenderAddress {
  const SenderAddress({
    required this.email,
    required this.accountId,
    required this.emails,
    this.verified = false,
  });

  final String email;

  /// The account most of its emails arrived in.
  final int accountId;
  final int emails;
  final bool verified;
}

/// A file received with an email, for the Attachments board.
class AttachedFile {
  const AttachedFile(this.row, this.file);

  /// The email it came with.
  final MailRow row;
  final MailAttachment file;
}

/// A newsletter in Newsletters, with how long it takes to read.
class Newsletter {
  const Newsletter(this.row, {this.minutes = 0});

  final MailRow row;

  /// Minutes to read it; 0 while its body is not here yet.
  final int minutes;
}

/// What a Vault card is about.
enum VaultKind {
  shipment,
  bill,
  flight,

  /// A table, a room, a ticket: a place on a day.
  booking,

  /// Something sold: to ship, on its way to the buyer, paid out.
  sale,

  /// A date that costs you if missed: a renewal, an expiry, a fine.
  deadline,

  /// A gift card or a voucher, with its code.
  voucher,

  /// A payslip, a statement, a tax form: a file to keep.
  document,
}

/// How far a parcel has come.
enum ParcelStage { ordered, shipped, transit, delivered }

/// How far a message sent from a PEC mailbox has got.
enum PecStage {
  /// Accepted by the provider, waiting for every delivery.
  accepted,

  /// In every certified recipient's mailbox.
  delivered,

  /// Refused, or not delivered to someone.
  failed,
}

/// A message sent from a certified-mail (PEC) mailbox, with what its
/// receipts say, for the Vault.
class PecMessage {
  const PecMessage({
    required this.row,
    required this.subject,
    required this.recipients,
    required this.stage,
    required this.delivered,
    required this.stageAt,
    this.reason = '',
    this.failedTo = '',
    this.proofs = const [],
  });

  /// The receipt a tap opens: the failure, else the newest one.
  final MailRow row;
  final String subject;

  /// The certified recipients.
  final List<String> recipients;
  final PecStage stage;

  /// How many recipients have it.
  final int delivered;

  /// When it was accepted, delivered to all, or failed.
  final DateTime stageAt;

  /// Why it failed, in the provider's words; may be empty.
  final String reason;
  final String failedTo;

  /// The receipts worth keeping as proof, by uid in [row]'s folder.
  final List<int> proofs;
}

/// A card in the Vault, read on the device from the email it opens. Only
/// the fields of its kind are filled in.
class VaultCard {
  const VaultCard({
    required this.row,
    required this.kind,
    required this.key,
    this.title = '',
    this.merchant = '',
    this.vatNumber = '',
    this.day,
    this.time = '',
    this.carrier = '',
    this.tracking = '',
    this.stage = ParcelStage.ordered,
    this.lastScan = '',
    this.trackUrl = '',
    this.amount,
    this.currency = '',
    this.paid = false,
    this.number = '',
    this.origin = '',
    this.originCity = '',
    this.destination = '',
    this.destinationCity = '',
    this.arrives = '',
    this.seat = '',
    this.coach = '',
    this.code = '',
    this.party = 0,
    this.status = '',
    this.address = '',
    this.travel = '',
    this.until,
    this.period = '',
    this.returnDays = 0,
    this.first,
    this.file,
  });

  /// The email it was read from, which a tap opens.
  final MailRow row;
  final VaultKind kind;

  /// What joins the emails about one thing; what Mark as paid keeps.
  final String key;

  /// The item, the bill, the place.
  final String title;

  /// The shop, the company billing, the airline.
  final String merchant;

  /// The merchant's VAT number, empty when unknown.
  final String vatNumber;

  /// The day it arrives, is due, leaves or is booked for; null when the
  /// email doesn't say.
  final DateTime? day;

  /// "HH:MM" on that day, or empty.
  final String time;

  final String carrier;
  final String tracking;
  final ParcelStage stage;
  final String lastScan;

  /// The carrier's page for the parcel, or empty.
  final String trackUrl;

  /// In cents.
  final int? amount;

  /// ISO 4217, like "EUR".
  final String currency;
  final bool paid;

  final String number;
  final String origin;
  final String originCity;
  final String destination;
  final String destinationCity;
  final String arrives;
  final String seat;

  /// A train's coach, "4".
  final String coach;
  final String code;

  final int party;

  /// A booking's "confirmed", "pending" or "cancelled"; a bill's
  /// "failed", "refund", "in" (money received), "renews" or "ending"; a
  /// parcel's "pickup"; a document's "payslip", "statement", "tax" or
  /// "contract".
  final String status;
  final String address;

  /// What a booking is: "train", "ferry", "bus", "stay", "parking",
  /// "car", "event", "table", or empty when the email doesn't tell.
  final String travel;

  /// The day something ends: a check-out, a parking's or a car's return
  /// (its time in [arrives]), a pick-up point's last day, a plan's
  /// renewal or end, a voucher's expiry.
  final DateTime? until;

  /// How often a plan charges: "week", "month" or "year"; empty when the
  /// email isn't about one.
  final String period;

  /// The days a shop gives to send things back, 0 when it doesn't say.
  final int returnDays;

  /// The day of the first email about it: when an order was placed.
  final DateTime? first;

  /// The bill's PDF, or the boarding pass.
  final MailAttachment? file;

  /// A booking whose status says it is off.
  bool get cancelled => status == 'cancelled';

  VaultCard withPaid(bool paid) => VaultCard(
    row: row,
    kind: kind,
    key: key,
    title: title,
    merchant: merchant,
    vatNumber: vatNumber,
    day: day,
    time: time,
    carrier: carrier,
    tracking: tracking,
    stage: stage,
    lastScan: lastScan,
    trackUrl: trackUrl,
    amount: amount,
    currency: currency,
    paid: paid,
    number: number,
    origin: origin,
    originCity: originCity,
    destination: destination,
    destinationCity: destinationCity,
    arrives: arrives,
    seat: seat,
    coach: coach,
    code: code,
    party: party,
    status: status,
    address: address,
    travel: travel,
    until: until,
    period: period,
    returnDays: returnDays,
    first: first,
    file: file,
  );
}

/// How the list a newsletter came from can be left.
enum UnsubscribeKind {
  /// Its headers give no way.
  none,

  /// One request, nothing to open.
  oneClick,

  /// A message to the list's address.
  mail,

  /// A page of the sender's, in the browser.
  page,
}

class UnsubscribeInfo {
  const UnsubscribeInfo(this.kind, [this.address = '']);

  static const none = UnsubscribeInfo(UnsubscribeKind.none);

  final UnsubscribeKind kind;

  /// The page, or the address the message goes to.
  final String address;
}

/// One of an account's own folders, as its server keeps them.
class AccountFolder {
  const AccountFolder({
    required this.mailbox,
    required this.name,
    this.depth = 0,
    this.selectable = true,
    this.unread = 0,
    this.total = 0,
  });

  /// What the server calls it, e.g. "Clients/Acme": what opens it.
  final String mailbox;

  /// What the person reads: "Acme".
  final String name;

  /// 0 at the top, 1 for a subfolder, and so on.
  final int depth;

  /// False for a folder that only holds other folders.
  final bool selectable;
  final int unread;

  /// How many emails it holds on the server.
  final int total;
}

/// The folders of [list] that share [folder]'s parent, [folder] among them,
/// in order.
List<AccountFolder> folderSiblings(
  List<AccountFolder> list,
  AccountFolder folder,
) {
  final (start, end) = _siblingRun(list, list.indexOf(folder));
  return [
    for (final f in list.sublist(start, end))
      if (f.depth == folder.depth) f,
  ];
}

/// [list] with the siblings named in [order] put in that order, each
/// followed by its subfolders, as the engine lists them after
/// `setFolderOrder`.
List<AccountFolder> withFolderOrder(
  List<AccountFolder> list,
  List<String> order,
) {
  final at = list.indexWhere((f) => order.isNotEmpty && f.mailbox == order[0]);
  if (at < 0) return list;
  final depth = list[at].depth;
  final (start, end) = _siblingRun(list, at);
  final blocks = <List<AccountFolder>>[];
  for (final f in list.sublist(start, end)) {
    if (f.depth == depth) {
      blocks.add([f]);
    } else {
      blocks.last.add(f);
    }
  }
  int rank(List<AccountFolder> b) {
    final i = order.indexOf(b.first.mailbox);
    return i < 0 ? order.length : i;
  }

  final sorted = [...blocks]
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0
          ? byRank
          : blocks.indexOf(a).compareTo(blocks.indexOf(b));
    });
  return [
    ...list.sublist(0, start),
    for (final b in sorted) ...b,
    ...list.sublist(end),
  ];
}

/// Where the run of [list] holding the folder at [i] and its siblings
/// (with their subfolders) starts and ends.
(int, int) _siblingRun(List<AccountFolder> list, int i) {
  final depth = list[i].depth;
  var start = i;
  while (start > 0 && list[start - 1].depth >= depth) {
    start--;
  }
  var end = i + 1;
  while (end < list.length && list[end].depth >= depth) {
    end++;
  }
  return (start, end);
}

/// What a rule looks at. The body is its first words as it arrives, all
/// of it once it is here.
enum RuleField { sender, subject, recipient, body }

/// How a rule compares, ignoring case.
enum RuleOp { contains, exactly, startsWith, notContains }

/// What a rule does with a match.
/// [vault] is "move to Vault": into Archive, with a card in the Vault.
enum RuleAction { moveTo, archive, markRead, label, vault }

/// "You often move emails from Ferrovia Rapida to Travel. Create a
/// rule?": a sender whose mail was moved by hand to one folder at least
/// five times in the last month, with no rule on them yet.
class RuleSuggestion {
  const RuleSuggestion({
    required this.accountId,
    required this.sender,
    required this.name,
    required this.target,
    required this.moves,
  });

  final int accountId;

  /// The address, lowercase.
  final String sender;
  final String name;

  /// The folder's server name.
  final String target;
  final int moves;

  /// The rule it suggests: mail from this address goes to the folder.
  MailRule get rule => MailRule(
    accountId: accountId,
    value: sender,
    action: RuleAction.moveTo,
    target: target,
  );
}

/// A rule, read as a sentence: "When the sender contains @studio.it, move
/// to Worksite". Rules sort new inbox mail on this device; the first that
/// matches wins.
class MailRule {
  const MailRule({
    this.id = 0,
    this.accountId,
    this.field = RuleField.sender,
    this.op = RuleOp.contains,
    this.value = '',
    this.action = RuleAction.moveTo,
    this.target = '',
    this.enabled = true,
    this.lastRun,
    this.matched = 0,
  });

  /// 0 until it is saved.
  final int id;

  /// The account whose mail it sorts; null for every account. A move is
  /// always to one account's folder, so it has one.
  final int? accountId;
  final RuleField field;
  final RuleOp op;
  final String value;
  final RuleAction action;

  /// The folder's server name, for a move; the label's keyword, for a
  /// label.
  final String target;
  final bool enabled;
  final DateTime? lastRun;

  /// How many emails it has sorted.
  final int matched;

  /// Whether it can be saved.
  bool get complete =>
      value.trim().isNotEmpty &&
      switch (action) {
        RuleAction.moveTo => accountId != null && target.isNotEmpty,
        RuleAction.label => target.isNotEmpty,
        _ => true,
      };

  MailRule copyWith({
    int? id,
    int? Function()? accountId,
    RuleField? field,
    RuleOp? op,
    String? value,
    RuleAction? action,
    String? target,
    bool? enabled,
  }) => MailRule(
    id: id ?? this.id,
    accountId: accountId != null ? accountId() : this.accountId,
    field: field ?? this.field,
    op: op ?? this.op,
    value: value ?? this.value,
    action: action ?? this.action,
    target: target ?? this.target,
    enabled: enabled ?? this.enabled,
    lastRun: lastRun,
    matched: matched,
  );

  /// Whether [row] is mail this rule sorts, as the engine decides it.
  bool matches(MailRow row) {
    if (accountId != null && accountId != row.accountId) return false;
    final needle = value.trim().toLowerCase();
    if (needle.isEmpty) return false;
    final hay = switch (field) {
      RuleField.sender => [row.fromEmail, row.fromName],
      RuleField.subject => [row.subject],
      RuleField.recipient => row.to.split(',').map((t) => t.trim()),
      RuleField.body => [row.preview],
    }.map((h) => h.toLowerCase());
    final any = hay.any(
      (h) => switch (op) {
        RuleOp.contains || RuleOp.notContains => h.contains(needle),
        RuleOp.exactly => h == needle,
        RuleOp.startsWith => h.startsWith(needle),
      },
    );
    return op == RuleOp.notContains ? !any : any;
  }

  /// Whether doing it to [row] would change anything.
  bool changes(MailRow row) => switch (action) {
    RuleAction.moveTo => row.mailbox != target,
    RuleAction.archive || RuleAction.vault => true,
    RuleAction.markRead => !row.seen,
    RuleAction.label => !row.labels.contains(target),
  };
}

/// One row of a message list.
/// How many days sent mail waits before Waiting counts it.
const waitingLongDays = 3;

/// Whole days from [sent] to [now], by the calendar.
int waitingDays(DateTime sent, DateTime now) => DateTime.utc(
  now.year,
  now.month,
  now.day,
).difference(DateTime.utc(sent.year, sent.month, sent.day)).inDays;

/// What `copyWith` leaves as it is, where null is a value too.
const Object _unchanged = Object();

class MailRow {
  const MailRow({
    required this.accountId,
    required this.mailbox,
    required this.uid,
    required this.fromName,
    required this.fromEmail,
    required this.subject,
    required this.preview,
    required this.receivedAt,
    required this.seen,
    this.messageId = '',
    this.references = '',
    this.replyTo = '',
    this.to = '',
    this.folder = MailFolder.inbox,
    this.thread = '',
    this.messages = 1,
    this.listed = true,
    this.snoozedUntil,
    this.files = 0,
    this.pictures = 0,
    this.invite = false,
    this.waitingFor = const [],
    this.labels = const [],
    this.remindAt,
  });

  final int accountId;
  final String mailbox;
  final int uid;
  final String fromName;
  final String fromEmail;
  final String subject;
  final String preview;
  final DateTime receivedAt;
  final bool seen;

  /// Message-ID with angle brackets, for replies; may be empty.
  final String messageId;

  /// References, space separated, oldest first.
  final String references;

  /// Reply-To when it differs from the sender; may be empty.
  final String replyTo;

  /// Who it went to: names, or addresses, comma separated.
  final String to;

  /// The list it is in.
  final MailFolder folder;

  /// The conversation it belongs to; empty for a message on its own.
  final String thread;

  /// How many messages its conversation has, 1 for a message on its own.
  final int messages;

  /// False for a message of a conversation that sits in a folder no list
  /// shows (Trash, a folder of the person's own).
  final bool listed;

  /// When a snoozed message comes back; null when it isn't snoozed, or
  /// when no device of the person's knows (snoozed in another app).
  final DateTime? snoozedUntil;

  /// How many files are attached, and how many of them are pictures, as
  /// far as the list knows (0 when it doesn't say).
  final int files;
  final int pictures;

  /// It carries a calendar invite, as far as the list knows.
  final bool invite;

  /// In Waiting: the people it went to, by address, who Write again
  /// writes to. Empty elsewhere.
  final List<String> waitingFor;

  /// Its labels, by keyword (`MailLabel.keyword`).
  final List<String> labels;

  /// In Waiting: when "Remind me" brings it back to the top of the inbox,
  /// if nobody has replied by then. Null without a reminder.
  final DateTime? remindAt;

  bool get isConversation => messages > 1 && thread.isNotEmpty;

  MailRow withSeen(bool seen) => copyWith(seen: seen);

  MailRow copyWith({
    String? mailbox,
    int? uid,
    bool? seen,
    MailFolder? folder,
    DateTime? snoozedUntil,
    List<String>? waitingFor,
    List<String>? labels,
    Object? remindAt = _unchanged,
  }) => MailRow(
    accountId: accountId,
    mailbox: mailbox ?? this.mailbox,
    uid: uid ?? this.uid,
    fromName: fromName,
    fromEmail: fromEmail,
    subject: subject,
    preview: preview,
    receivedAt: receivedAt,
    seen: seen ?? this.seen,
    messageId: messageId,
    references: references,
    replyTo: replyTo,
    to: to,
    folder: folder ?? this.folder,
    thread: thread,
    messages: messages,
    listed: listed,
    snoozedUntil: snoozedUntil ?? this.snoozedUntil,
    files: files,
    pictures: pictures,
    invite: invite,
    waitingFor: waitingFor ?? this.waitingFor,
    labels: labels ?? this.labels,
    remindAt: identical(remindAt, _unchanged)
        ? this.remindAt
        : remindAt as DateTime?,
  );

  /// Name if the sender has one, otherwise the address.
  String get sender => fromName.isNotEmpty ? fromName : fromEmail;

  /// Who the list shows: the recipients of a sent message or a draft
  /// (none yet for a draft that has none), else the sender.
  String get listName => switch (folder) {
    MailFolder.drafts => to,
    MailFolder.sent when to.isNotEmpty => to,
    _ => sender,
  };

  Object get key => (accountId, mailbox, uid);
}

enum SyncPhase { idle, downloading, offline, signInFailed }

/// What the inbox says about syncing. [phase] is the one thing worth
/// saying first; the rest says what else is going on.
class SyncStatus {
  const SyncStatus(
    this.phase, {
    this.done = 0,
    this.total = 0,
    this.downloading,
    this.offline = false,
    this.failed = const [],
  });

  static const idle = SyncStatus(SyncPhase.idle);

  final SyncPhase phase;

  /// Messages downloaded of those to download, over every account.
  final int done;
  final int total;

  /// The account downloading, when one is.
  final int? downloading;

  /// The servers can't be reached right now; the engine keeps retrying.
  final bool offline;

  /// Accounts whose password stopped working, waiting for a new one.
  final List<int> failed;
}

/// How a server connection is protected.
enum ServerSecurity { tls, startTls, none }

/// A server and how to reach it.
class MailServer {
  const MailServer(this.host, this.port, this.security);
  final String host;
  final int port;
  final ServerSecurity security;
}

/// Where an account reads and sends its mail, as its details show.
class AccountServers {
  const AccountServers({
    required this.imap,
    required this.smtp,
    this.username = '',
    this.jmapUrl,
  });
  final MailServer imap;
  final MailServer smtp;
  final String username;

  /// The JMAP session, for a JMAP account: [imap] then holds its host.
  final String? jmapUrl;
}

/// How an account's connection is going, as its details show it.
class AccountHealth {
  const AccountHealth({this.checkedAt, this.failedSince});

  /// When the server last answered.
  final DateTime? checkedAt;

  /// Since when the server refuses the password; null while it works.
  final DateTime? failedSince;
}

/// An account's away message (`RemindAwayPrintToApprove`, section 2): an
/// automatic reply the mail server sends while the person is away. Days
/// are local dates at midnight.
class AwayMessage {
  const AwayMessage({
    this.on = false,
    this.start,
    this.end,
    this.subject = '',
    this.body = '',
  });

  final bool on;

  /// The first day; null from today.
  final DateTime? start;

  /// The last day; null keeps it on until it is turned off.
  final DateTime? end;
  final String subject;
  final String body;

  AwayMessage copyWith({
    bool? on,
    DateTime? Function()? start,
    DateTime? Function()? end,
    String? subject,
    String? body,
  }) => AwayMessage(
    on: on ?? this.on,
    start: start == null ? this.start : start(),
    end: end == null ? this.end : end(),
    subject: subject ?? this.subject,
    body: body ?? this.body,
  );
}

/// How saving an away message went.
enum AwaySaved {
  saved,

  /// Another filter of the person's is active on the server: the away
  /// message can't be on alongside it, and nothing was changed there.
  otherFilters,

  /// The server no longer takes an away message.
  unsupported,
}

/// An away message answering now: one quiet line per account at the top
/// of the inbox.
class AwayLine {
  const AwayLine(this.accountId, {this.end});

  final int accountId;

  /// The last day; null until turned off.
  final DateTime? end;
}

/// Where the settings of an address came from.
enum SettingsSource { known, published, guessed }

/// Server settings found from an email address.
class FoundSettings {
  const FoundSettings({
    required this.imap,
    required this.smtp,
    required this.username,
    required this.source,
    this.jmapUrl,
  });
  final MailServer imap;
  final MailServer smtp;
  final String username;
  final SettingsSource source;

  /// The JMAP session, when the domain serves JMAP: the account then uses
  /// it in place of IMAP and SMTP.
  final String? jmapUrl;

  /// The host shown for a JMAP account.
  String? get jmapHost => jmapUrl == null ? null : Uri.tryParse(jmapUrl!)?.host;
}

/// Why adding an account failed.
enum AddAccountError { wrongPassword, unreachable, insecure, keychain, other }

class AddAccountException implements Exception {
  const AddAccountException(this.error, [this.detail = '']);
  final AddAccountError error;
  final String detail;

  @override
  String toString() => 'AddAccountException($error, $detail)';
}

/// A message being written.
/// How new mail reaches Android with the app closed (`AndroidBackground`).
enum BackgroundDelivery {
  /// A background service keeps the connection open: mail as it arrives,
  /// with a silent notice of its own.
  instant,

  /// A look every 15 minutes, with no notice of its own.
  periodic,
}

/// A message waiting in the outbox (`Outbox`).
class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.accountId,
    required this.to,
    required this.subject,
    required this.body,
    required this.queuedAt,
    this.error,
    this.sendAt,
  });

  final int id;
  final int accountId;

  /// When it goes, for mail sent later; null to go as soon as it can.
  final DateTime? sendAt;

  /// Addresses, as `a@b.c` or `Name <a@b.c>`.
  final List<String> to;
  final String subject;
  final String body;
  final DateTime queuedAt;

  /// Why the server refused it; null while it only waits.
  final String? error;

  /// Who it goes to, by name where there is one.
  String get recipients => to
      .map((a) {
        final name = a.replaceAll(RegExp(r'\s*<.*>'), '').trim();
        return name.isEmpty ? a.replaceAll(RegExp(r'[<>]'), '') : name;
      })
      .join(', ');
}

class Draft {
  const Draft({
    required this.accountId,
    this.fromEmail,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = '',
    this.inReplyTo,
    this.references = const [],
    this.files = const [],
    this.signatureId,
    this.signaturePicked = false,
    this.copy,
    this.forward = false,
    this.remindAt,
    this.marks = const [],
  });

  /// The account it goes out from.
  final int accountId;

  /// One of the account's aliases it goes from; null for the account's
  /// own address.
  final String? fromEmail;

  /// Addresses, as `a@b.c` or `Name <a@b.c>`.
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String body;

  /// Message-ID of the message being answered.
  final String? inReplyTo;

  /// The thread so far, oldest first.
  final List<String> references;

  /// Files attached to it.
  final List<DraftFile> files;

  /// The signature added when it goes, if any.
  final int? signatureId;

  /// [signatureId] was picked by hand (null: "No signature"), so the
  /// draft keeps it when it is opened again.
  final bool signaturePicked;

  /// Where its saved copy is, once it has one.
  final DraftCopy? copy;

  /// It forwards a message: titled Forward, with the signature for
  /// replies and forwards.
  final bool forward;

  /// "Remind me if nobody replies": once sent, it comes back to the top of
  /// the inbox at this time if nobody has replied. Kept on this device.
  final DateTime? remindAt;

  /// Bold, italic and links over [body] (`FormattingToApprove`).
  final List<BodyMark> marks;

  Draft withCopy(DraftCopy? copy) => Draft(
    accountId: accountId,
    fromEmail: fromEmail,
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    body: body,
    inReplyTo: inReplyTo,
    references: references,
    files: files,
    signatureId: signatureId,
    signaturePicked: signaturePicked,
    copy: copy,
    forward: forward,
    remindAt: remindAt,
    marks: marks,
  );

  /// Total size of the attached files, in bytes.
  int get filesSize => files.fold(0, (sum, f) => sum + f.data.length);

  bool get isReply => inReplyTo != null;

  bool get isEmpty =>
      to.isEmpty &&
      cc.isEmpty &&
      bcc.isEmpty &&
      subject.trim().isEmpty &&
      body.trim().isEmpty &&
      files.isEmpty;

  List<String> get recipients => [...to, ...cc, ...bcc];
}

/// What a [BodyMark] does to the words under it.
enum BodyMarkKind { bold, italic, link }

/// Bold, italic or a link over the text `start..end` of a body, counted
/// as Dart counts a String (UTF-16 code units).
@immutable
class BodyMark {
  const BodyMark(this.kind, this.start, this.end, [this.url = '']);

  final BodyMarkKind kind;
  final int start;
  final int end;

  /// A link's address; empty for the others.
  final String url;

  BodyMark copyWith({int? start, int? end}) =>
      BodyMark(kind, start ?? this.start, end ?? this.end, url);

  @override
  bool operator ==(Object other) =>
      other is BodyMark &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.url == url;

  @override
  int get hashCode => Object.hash(kind, start, end, url);

  @override
  String toString() =>
      'BodyMark($kind, $start, $end${url.isEmpty ? '' : ', $url'})';
}

/// A template for compose's "/": a name, and the subject and text it
/// puts in a message.
@immutable
class MailTemplate {
  const MailTemplate({
    this.id = 0,
    required this.name,
    this.subject = '',
    this.body = '',
  });

  /// 0 for one not kept yet.
  final int id;
  final String name;
  final String subject;
  final String body;

  MailTemplate copyWith({
    int? id,
    String? name,
    String? subject,
    String? body,
  }) => MailTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    body: body ?? this.body,
  );
}

/// A group of addresses from different accounts and domains, as on
/// `Groups`: its color, signature and sending address.
@immutable
class MailGroup {
  const MailGroup({
    this.id = 0,
    required this.name,
    required this.color,
    this.signatureId,
    this.sendFrom = '',
    this.separateInbox = true,
    this.notify = true,
    this.addresses = const [],
  });

  /// 0 for one not kept yet.
  final int id;
  final String name;
  final Color color;

  /// Its default signature; null for none.
  final int? signatureId;

  /// Where new emails go from; empty for the first address.
  final String sendFrom;

  /// Gets its own item in the sidebar, besides the unified inbox.
  final bool separateInbox;
  final bool notify;
  final List<GroupAddress> addresses;

  /// Where new emails go from: [sendFrom] while it is in the group, else
  /// the first address.
  GroupAddress? get sender =>
      addresses
          .where((a) => a.email.toLowerCase() == sendFrom.toLowerCase())
          .firstOrNull ??
      addresses.firstOrNull;

  MailGroup copyWith({
    int? id,
    String? name,
    Color? color,
    int? Function()? signatureId,
    String? sendFrom,
    bool? separateInbox,
    bool? notify,
    List<GroupAddress>? addresses,
  }) => MailGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    signatureId: signatureId == null ? this.signatureId : signatureId(),
    sendFrom: sendFrom ?? this.sendFrom,
    separateInbox: separateInbox ?? this.separateInbox,
    notify: notify ?? this.notify,
    addresses: addresses ?? this.addresses,
  );
}

/// Whose mail the inbox shows in place of every account's: one group's,
/// or one of its addresses'.
@immutable
class GroupScope {
  const GroupScope(this.group, [this.address]);
  final int group;

  /// Only the mail written to this address of the group.
  final String? address;

  @override
  bool operator ==(Object other) =>
      other is GroupScope && other.group == group && other.address == address;

  @override
  int get hashCode => Object.hash(group, address);
}

/// What is unread in a group's inbox, and in each of its addresses, in
/// the group's order: for the sidebar and the phone's group sheet.
class GroupUnread {
  const GroupUnread(this.unread, [this.addresses = const []]);
  final int unread;
  final List<int> addresses;
}

/// One address of a group: an account's own, or one of its aliases.
@immutable
class GroupAddress {
  const GroupAddress(this.accountId, this.email);
  final int accountId;
  final String email;

  @override
  bool operator ==(Object other) =>
      other is GroupAddress &&
      other.accountId == accountId &&
      other.email.toLowerCase() == email.toLowerCase();

  @override
  int get hashCode => Object.hash(accountId, email.toLowerCase());
}

/// What the inbox's first chips keep (`Main`, `Phone`, `FiltersToApprove`):
/// everything, mail people wrote, or mail machines send (receipts,
/// alerts, no-reply).
enum InboxTab { all, people, notifications }

/// What the inbox tabs show: conversations and unread messages of each.
class TabCounts {
  const TabCounts({
    this.people = 0,
    this.peopleUnread = 0,
    this.notifications = 0,
    this.notificationsUnread = 0,
  });

  final int people;
  final int peopleUnread;
  final int notifications;
  final int notificationsUnread;
}

/// A draft kept in its account's Drafts folder.
@immutable
class DraftCopy {
  const DraftCopy(this.accountId, this.mailbox, this.uid);

  final int accountId;
  final String mailbox;
  final int uid;

  @override
  bool operator ==(Object other) =>
      other is DraftCopy &&
      other.accountId == accountId &&
      other.mailbox == mailbox &&
      other.uid == uid;

  @override
  int get hashCode => Object.hash(accountId, mailbox, uid);
}

/// The four templates of the `Signatures` mockup.
enum SignatureTemplate { minimal, classic, monogram, logo }

/// Accent colors a signature can use, named as in the tokens.
enum SignatureAccent { blue, black, terracotta }

/// A signature, as the Signatures editor shows it.
class MailSignature {
  const MailSignature({
    this.id = 0,
    required this.accountId,
    required this.label,
    this.template = SignatureTemplate.classic,
    this.name = '',
    this.role = '',
    this.company = '',
    this.phone = '',
    this.website = '',
    this.accent = SignatureAccent.blue,
    this.logo,
    this.forNew = false,
    this.forReplies = false,
  });

  /// 0 until saved.
  final int id;
  final int accountId;

  /// What the person calls it: "Work", "Short".
  final String label;
  final SignatureTemplate template;
  final String name;
  final String role;
  final String company;
  final String phone;
  final String website;
  final SignatureAccent accent;

  /// PNG or JPEG, already shrunk.
  final Uint8List? logo;

  /// Its account's signature for new emails.
  final bool forNew;

  /// Its account's signature for replies and forwards.
  final bool forReplies;

  /// Its lines, name first, as the email will have them (the engine
  /// writes the same ones).
  List<String> get lines {
    String join(List<String> parts) =>
        parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(' · ');
    return [
      name.trim(),
      join([role, company]),
      ...switch (template) {
        SignatureTemplate.minimal => const <String>[],
        SignatureTemplate.classic || SignatureTemplate.logo => [
          join([phone, website]),
        ],
        SignatureTemplate.monogram => [website.trim()],
      },
    ].where((l) => l.isNotEmpty).toList();
  }

  /// The plain-text version, after the usual "-- " line.
  String get text => lines.isEmpty ? '' : '-- \n${lines.join('\n')}';

  /// "Matteo Neri" → "MN".
  String get monogram {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '';
    final first = words.first.characters.first.toUpperCase();
    if (words.length == 1) return first;
    return first + words.last.characters.first.toUpperCase();
  }

  MailSignature copyWith({
    int? id,
    int? accountId,
    String? label,
    SignatureTemplate? template,
    String? name,
    String? role,
    String? company,
    String? phone,
    String? website,
    SignatureAccent? accent,
    Uint8List? logo,
    bool clearLogo = false,
    bool? forNew,
    bool? forReplies,
  }) => MailSignature(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    label: label ?? this.label,
    template: template ?? this.template,
    name: name ?? this.name,
    role: role ?? this.role,
    company: company ?? this.company,
    phone: phone ?? this.phone,
    website: website ?? this.website,
    accent: accent ?? this.accent,
    logo: clearLogo ? null : logo ?? this.logo,
    forNew: forNew ?? this.forNew,
    forReplies: forReplies ?? this.forReplies,
  );
}

/// Why a logo was not taken.
enum LogoError { notAnImage, tooBig }

class LogoException implements Exception {
  const LogoException(this.error);
  final LogoError error;
}

/// A file attached to a draft.
class DraftFile {
  const DraftFile(this.name, this.data);
  final String name;
  final Uint8List data;
}

/// Most servers refuse messages above 25 MB; attachments grow by a third
/// on the way, so the files themselves stop a little below.
const maxDraftFilesSize = 18 * 1000 * 1000;

/// Where a message can go from the inbox: Archive, Trash, or the
/// account's spam folder (Report spam).
enum MessageAction { archive, delete, junk, notJunk }

/// Why sending failed.
enum SendError {
  badAddress,
  noRecipients,
  wrongPassword,
  unreachable,
  rejected,
  other,
}

class SendException implements Exception {
  const SendException(this.error, [this.detail = '']);
  final SendError error;

  /// For [SendError.badAddress], the address; otherwise technical detail.
  final String detail;

  @override
  String toString() => 'SendException($error, $detail)';
}

/// A message found by a search.
class SearchHit {
  const SearchHit(this.row, {this.snippet = '', this.files = false});
  final MailRow row;

  /// Where the body matched, each match between U+0002 and U+0003; empty
  /// when the body didn't match.
  final String snippet;

  /// Whether it came with files.
  final bool files;
}

/// Someone who wrote to the person.
/// Someone who writes often, for "Frequent contacts".
class FrequentContact {
  const FrequentContact({
    required this.name,
    required this.email,
    required this.accountId,
  });
  final String name;
  final String email;

  /// The account their newest message came to, for its dot.
  final int accountId;
}

/// What an empty search shows (`SearchEmpty`).
class SearchStart {
  const SearchStart({
    this.frequent = const [],
    this.recent = const [],
    this.indexed = 0,
  });

  final List<FrequentContact> frequent;

  /// What was searched lately, newest first.
  final List<String> recent;

  /// How many messages search looks through on this device.
  final int indexed;
}

class Contact {
  const Contact({
    required this.name,
    required this.email,
    this.messages = 0,
    this.writtenTo = false,
    this.accountColor,
  });
  final String name;
  final String email;

  /// How many of their messages are on this device.
  final int messages;

  /// A recipient suggestion written to from here ("Wrote to"), rather
  /// than one who only wrote ("Wrote to you").
  final bool writtenTo;

  /// Known association with an account or one of its aliases.
  final Color? accountColor;
}

/// What a search found.
class SearchResults {
  const SearchResults({
    this.total = 0,
    this.hits = const [],
    this.people = const [],
    this.files = const [],
    this.searched = 0,
    this.elapsed = Duration.zero,
  });

  static const empty = SearchResults();

  /// How many messages match in all; [hits] holds the newest of them.
  final int total;
  final List<SearchHit> hits;

  /// Senders matching the words, most frequent first.
  final List<Contact> people;

  /// The files of the newest messages found, for Attachments.
  final List<AttachedFile> files;

  /// How many messages the search looked through.
  final int searched;
  final Duration elapsed;
}

/// One notification: a sender's newest message, and how many came.
class MailNotice {
  const MailNotice({
    required this.accountId,
    required this.mailbox,
    required this.uid,
    required this.sender,
    this.senderEmail = '',
    this.subject = '',
    this.preview = '',
    this.count = 1,
    this.vault,
    this.people = true,
    this.silent = false,
    this.away,
    this.noReply,
  });

  final int accountId;
  final String mailbox;

  /// The newest message, opened when the notice is clicked.
  final int uid;
  final String sender;
  final String senderEmail;
  final String subject;
  final String preview;
  final int count;

  /// Set for a Vault notice: a parcel today, a bill due soon.
  final VaultNotice? vault;

  /// Written by a person, not a machine.
  final bool people;

  /// Shown without a sound: the quiet hours cover it.
  final bool silent;

  /// Set for "While you were away", once quiet hours that held notices
  /// back are over.
  final AwayNotice? away;

  /// Set for "Remind me if nobody replies": your email back at the top of
  /// the inbox. [sender] is who it waits on.
  final NoReplyNotice? noReply;

  Object get key => (accountId, mailbox, uid);

  MailNotice silenced() => MailNotice(
    accountId: accountId,
    mailbox: mailbox,
    uid: uid,
    sender: sender,
    senderEmail: senderEmail,
    subject: subject,
    preview: preview,
    count: count,
    vault: vault,
    people: people,
    silent: true,
    away: away,
    noReply: noReply,
  );
}

/// "No reply from Luca · sent 3 days ago": a reminder's notice.
class NoReplyNotice {
  const NoReplyNotice({required this.sentDaysAgo});

  /// Whole days, by the calendar, since it was sent.
  final int sentDaysAgo;
}

/// "While you were away · 12 emails, 3 from people: Sara Conti, Luca
/// Bianchi, Dad".
class AwayNotice {
  const AwayNotice({
    required this.emails,
    this.people = 0,
    this.names = const [],
  });

  final int emails;

  /// Of those, written by people.
  final int people;

  /// Who, newest first, at most three.
  final List<String> names;
}

/// What a Vault notice says (`Notifications`, "Piuma · Vault").
class VaultNotice {
  const VaultNotice({
    this.dueIn,
    this.merchant = '',
    this.title = '',
    this.time = '',
    this.amount,
    this.currency = '',
  });

  /// Null for a parcel arriving today; days left for a bill.
  final int? dueIn;
  final String merchant;
  final String title;

  /// "HH:MM", or empty.
  final String time;

  /// In cents, with its ISO currency.
  final int? amount;
  final String currency;
}

/// Minutes since Monday 00:00 at [t], as quiet hours count local time.
int weekMinute(DateTime t) =>
    (t.weekday - 1) * 24 * 60 + t.hour * 60 + t.minute;

/// "Notify me about" in Settings › Notifications.
enum NotifyMode { people, all, off }

/// Settings › Notifications. Times are minutes after local midnight.
class NotifySettings {
  const NotifySettings({
    this.mode = NotifyMode.people,
    this.quiet = true,
    this.quietFrom = 22 * 60,
    this.quietTo = 8 * 60,
    this.weekends = false,
    this.hold = false,
    this.parcels = true,
    this.due = true,
  });

  final NotifyMode mode;

  /// Quiet every night, from [quietFrom] to [quietTo].
  final bool quiet;
  final int quietFrom;
  final int quietTo;

  /// Quiet all day on Saturday and Sunday.
  final bool weekends;

  /// While quiet, no notices (summed up at the end), not just no sound.
  final bool hold;

  /// Vault: a parcel on its delivery day, a bill three days ahead.
  final bool parcels;
  final bool due;

  NotifySettings copyWith({
    NotifyMode? mode,
    bool? quiet,
    int? quietFrom,
    int? quietTo,
    bool? weekends,
    bool? hold,
    bool? parcels,
    bool? due,
  }) => NotifySettings(
    mode: mode ?? this.mode,
    quiet: quiet ?? this.quiet,
    quietFrom: quietFrom ?? this.quietFrom,
    quietTo: quietTo ?? this.quietTo,
    weekends: weekends ?? this.weekends,
    hold: hold ?? this.hold,
    parcels: parcels ?? this.parcels,
    due: due ?? this.due,
  );
}

/// Where the interface gets its mail: the real engine, or demo data for
/// tests and screenshots.
/// Devices & sync, as on `SyncToApprove` and `Groups`: where the encrypted
/// space lives, and the devices that read it.
class SyncState {
  const SyncState({this.home, this.syncedAt, this.devices = const []});

  /// The address whose mailbox holds the space; null while sync is off.
  final String? home;

  /// The last time a round reached the space.
  final DateTime? syncedAt;
  final List<SyncDevice> devices;

  bool get on => home != null;
}

enum SyncDeviceKind { laptop, phone, tablet }

class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.lastSeen,
    this.thisDevice = false,
  });

  final String id;
  final String name;
  final SyncDeviceKind kind;
  final DateTime lastSeen;
  final bool thisDevice;
}

/// A new device asking to be linked; it goes by itself five minutes
/// after [at].
class PairAsk {
  const PairAsk({
    required this.id,
    required this.name,
    required this.kind,
    required this.at,
  });

  final String id;
  final String name;
  final SyncDeviceKind kind;
  final DateTime at;

  @override
  bool operator ==(Object other) => other is PairAsk && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum SyncProblem {
  /// The recovery phrase doesn't open the space.
  wrongPhrase,

  /// The code typed on the other device wasn't the one shown.
  wrongCode,

  /// Nobody approved in time, or the request is gone.
  expired,

  /// A linked device said "Not me".
  refused,

  /// The mailbox holds no space.
  noSpace,
  offline,

  /// The mailbox to move the space to holds another one.
  taken,
  other,
}

/// The QR code "Link a new device" shows, as on `QrPairToApprove`.
class PairInvite {
  const PairInvite({
    required this.width,
    required this.modules,
    required this.expiresAt,
  });

  /// Modules a side, without the quiet zone.
  final int width;

  /// Row by row, true for dark.
  final List<bool> modules;

  /// When a new code takes its place.
  final DateTime expiresAt;
}

/// A linked device's QR code, as the new phone read it.
class ScannedPair {
  const ScannedPair({required this.link, required this.email});

  /// The whole code, handed back to sign in and join.
  final String link;

  /// The address whose mailbox holds the space.
  final String email;
}

/// What a mailbox's space says of itself before it is open, for "We
/// found your space".
class SpaceFound {
  const SpaceFound({
    required this.accounts,
    required this.groups,
    required this.signatures,
    required this.updatedAt,
    this.devices = const [],
  });

  final int accounts;
  final int groups;
  final int signatures;
  final DateTime updatedAt;

  /// The devices that can approve this one, most recently seen first.
  final List<SyncDevice> devices;
}

class SyncFailure implements Exception {
  const SyncFailure(this.problem);
  final SyncProblem problem;

  @override
  String toString() => 'SyncFailure($problem)';
}

/// A report from the app: a problem, or an idea.
enum ReportKind { problem, idea }

/// Where a report is, as Your reports shows it.
enum ReportStatus {
  /// Its turn comes soon: the relay spaces reports out.
  waiting,

  /// No connection: it goes when there is one.
  offline,

  /// The relay took its fill for today; it goes later by itself.
  paused,
  sending,

  /// An issue exists: [SentReport.issue].
  sent,

  /// It kept failing, or was refused; it can be tried again.
  failed,

  /// It went by email from the person's own account instead.
  emailed,
}

/// What the report sheet holds when Send or "See what's sent" is pressed.
@immutable
class ReportDraft {
  const ReportDraft({
    required this.kind,
    required this.title,
    this.description = '',
    this.includeScreenshot = false,
    this.includeLog = true,
    this.device = const [],
    this.screens = const [],
  });

  final ReportKind kind;
  final String title;
  final String description;
  final bool includeScreenshot;
  final bool includeLog;

  /// App, system, device, screen, language, the screen it came from.
  final List<(String, String)> device;

  /// The last screens visited, "HH:MM:SS Name", oldest first.
  final List<String> screens;
}

/// A report in Your reports.
@immutable
class SentReport {
  const SentReport({
    required this.id,
    required this.kind,
    required this.title,
    required this.created,
    required this.status,
    this.nextTry,
    this.issue,
  });

  final String id;
  final ReportKind kind;
  final String title;
  final DateTime created;
  final ReportStatus status;

  /// When a waiting report is due to go.
  final DateTime? nextTry;

  /// The issue number once sent.
  final int? issue;
}

/// "See what's sent": the report as it will leave, and the whole log when
/// it goes with it (already cleaned).
@immutable
class ReportPreview {
  const ReportPreview({required this.report, this.log});
  final String report;
  final String? log;
}

/// A report written as an email, for "Send by email instead".
@immutable
class ReportEmail {
  const ReportEmail({
    required this.to,
    required this.subject,
    required this.body,
    this.files = const [],
  });
  final String to;
  final String subject;
  final String body;
  final List<DraftFile> files;
}

abstract class MailSource {
  List<MailAccount> get accounts;

  /// Fires whenever the inbox changed and should be redrawn.
  Stream<void> get changes;

  /// New mail worth a notification, as it arrives.
  Stream<List<MailNotice>> get notices;

  Future<NotifySettings> notifySettings();

  Future<void> setNotifySettings(NotifySettings settings);

  /// Settings › Features as last read: what the zones and the helpers on
  /// this device show. Listened to by everything a feature puts on screen.
  final features = ValueNotifier<FeatureSettings>(const FeatureSettings());

  /// Reads Settings › Features again, as another device may have changed
  /// them.
  Future<FeatureSettings> featureSettings() async => features.value;

  Future<void> setFeatureSettings(FeatureSettings settings) async =>
      features.value = settings;

  /// Whether [weekMinute] (minutes since Monday 00:00, local time) falls
  /// in the quiet hours.
  bool quietAt(int weekMinute);

  /// Whether the quiet hours cover an account; one switched off rings as
  /// usual.
  bool quietCovers(int accountId);

  /// New mail's [notices] as the quiet hours leave them at [weekMinute]:
  /// each covered account's lose their sound or, with "No notices", are
  /// kept for "While you were away" and left out.
  List<MailNotice> quiet(List<MailNotice> notices, int weekMinute);

  void setQuietCovers(int accountId, bool covered);

  /// The Vault notices due now (a parcel today, a bill due soon), each
  /// given once; none before 8:00 or in the night's quiet hours. With them,
  /// once quiet hours that held notices back are over, "While you were
  /// away".
  Future<List<MailNotice>> vaultReminders();

  /// The row of one message, to open it from a notice. Null when gone.
  Future<MailRow?> messageRow(int accountId, String mailbox, int uid);

  ValueListenable<SyncStatus> get status;

  Future<int> inboxCount();
  Future<int> inboxUnread();

  /// The two halves of the inbox for its tabs: how many conversations
  /// each lists and how many of their messages are unread. With
  /// [account], only that account's.
  Future<TabCounts> tabCounts({int? account, GroupScope? group});

  /// Counts per period; `edges` are descending times. With [account],
  /// only that account's conversations; with [mailbox] too, those of one
  /// of its own folders; with [group], one group's inbox.
  Future<List<int>> countsBetween(
    List<DateTime> edges, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  });

  /// Rows of a unified folder, newest first (Snoozed: soonest back
  /// first); with [account], only that account's; with [mailbox] too, one
  /// of its own folders. In the inbox, [tab] keeps one half of it,
  /// [unread] only conversations with something unread, and [group] one
  /// group's mail, or one of its addresses'.
  Future<List<MailRow>> page(
    int offset,
    int limit, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  });

  /// An account's own folders (not Inbox, Sent, Archive, Drafts, Trash or
  /// spam), in the server's tree order, siblings as the person ordered them.
  Future<List<AccountFolder>> folders(int accountId);

  /// Keeps the order the person dragged some sibling folders into, first
  /// to last; [folders] lists them so from then on.
  Future<void> setFolderOrder(int accountId, List<String> mailboxes);

  /// Every label, in order, with how many emails carry it
  /// (`LabelsToApprove`).
  Future<List<MailLabel>> labels();

  /// Makes a label, or finds the one with that name; without [color] it
  /// takes the next free one.
  Future<MailLabel> addLabel(String name, {String color = ''});

  /// Renames a label or changes its color; its emails keep it.
  Future<void> updateLabel(int id, String name, String color);

  /// Deletes a label: off every email, here and on the servers.
  Future<void> removeLabel(int id);

  /// Puts a label on [rows] or takes it off, then tells their servers.
  Future<void> setLabel(List<MailRow> rows, String keyword, bool add);

  /// Every email with a label, newest first, wherever it is.
  Future<List<MailRow>> labelled(String keyword);

  /// The account's server keeps no labels: they stay on this device.
  bool labelsLocal(int accountId) => false;

  /// Makes a folder of the account's own on its server, at the top of its
  /// list. Throws when the server can't be reached or refuses the name.
  Future<void> createFolder(int accountId, String name);

  /// Brings one of an account's own folders up to date, newest first, a
  /// round at a time; [changes] fires after each round.
  Future<void> refreshFolder(int accountId, String mailbox);

  /// Moves messages of one account to [mailbox], one of its own folders
  /// or "INBOX". On failure they show again and this throws.
  Future<void> moveTo(List<MailRow> rows, String mailbox);

  /// "In short" for a sender's card; null for someone who wrote once.
  Future<SenderBrief?> senderBrief(String email);

  /// How much [email] writes and how much of it was opened.
  Future<SenderStats> senderStats(String email);

  /// The files [email] sent, newest first: a sender card's Attachments.
  Future<List<AttachedFile>> senderFiles(String email) async => [
    for (final f in await attachedFiles())
      if (f.row.fromEmail.toLowerCase() == email.toLowerCase()) f,
  ];

  /// The addresses a sender writes from, most emails first: [email], and
  /// others that carry the same full name.
  Future<List<SenderAddress>> senderAddresses(String email) async => const [];

  /// "In short" over [row]'s conversation, when it is long and something
  /// in it stands out.
  Future<ThreadBrief?> threadBrief(MailRow row);

  /// [brief] in the words of the system's own model (Gemini Nano, Apple
  /// Intelligence), where the device has one ready; null keeps the rules.
  Future<ThreadBrief?> rewriteBrief(ThreadBrief brief);

  /// Every message of [row]'s conversation, oldest first; just [row]
  /// when it is on its own.
  Future<List<MailRow>> conversation(MailRow row);

  Future<String> body(MailRow row);

  /// The message made safe to read, with what was stopped.
  Future<Readable> readable(MailRow row);

  /// The message's original layout, made safe; with [loadImages] its
  /// remote images come in too.
  Future<OriginalDoc> original(MailRow row, {required bool loadImages});

  /// Fetches an attachment and saves it in Downloads under a name no
  /// other file there has. Returns the saved file's path.
  Future<String> saveAttachment(MailRow row, MailAttachment attachment);

  /// Whether the file saved at [path] is an archive locked with a
  /// password: opening it asks first.
  Future<bool> lockedArchive(String path) async => false;

  /// Saves [text] in Downloads as [name], or a name like it no other
  /// file there has: the Vault's month for the accountant. Returns the
  /// saved file's path.
  Future<String> saveText(String name, String text);

  /// A remote image, once the person allowed it.
  Future<Uint8List> fetchImage(String url);

  /// Always load a sender's images, or stop.
  Future<void> setTrusted(String email, bool trusted);

  /// Answers the invite in [row]: its organizer gets the reply their
  /// calendar reads, with [subject] and [text] for people, and an
  /// accepted one goes in the calendar chosen for invites. Throws when it
  /// can't be sent.
  Future<InviteResult> answerInvite(
    MailRow row,
    InviteAnswer answer, {
    required String subject,
    required String text,
  });

  /// Connected calendars (`Calendars`), by where they come from.
  Future<List<CalendarSource>> calendarSources();

  /// Email accounts whose provider has a calendar with the same password.
  Future<List<CalendarSuggestion>> calendarSuggestions();

  /// Connects a CalDAV account from an email or server address. Throws an
  /// [AddAccountException] when it can't.
  Future<CalendarSource> connectCalDav(
    String address, {
    String username = '',
    required String password,
  });

  /// Connects the calendar of an email account, with its password.
  Future<CalendarSource> connectAccountCalendar(int accountId);

  /// Subscribes to an .ics feed, read-only.
  Future<CalendarSource> subscribeCalendar(String url);

  /// Forgets a source here; its events stay on its server.
  Future<void> disconnectCalendar(int sourceId);

  Future<void> setCalendarAvailability(int calendarId, bool on);

  Future<CalendarPrefs> calendarPrefs();

  Future<void> setDefaultCalendar(int calendarId);

  Future<void> setCheckConflicts(bool on);

  Future<void> setFindDates(bool on);

  /// Puts a day found in [row] in the calendar that takes invites, for an
  /// hour, under the message's subject, and gives the calendar's name.
  /// Throws when it can't.
  Future<String> addFoundDate(MailRow row, FoundDate date);

  /// What makes you busy between two times, from the calendars that count
  /// for availability.
  Future<List<BusyTime>> busyBetween(DateTime start, DateTime end);

  /// Whether a sender's new mail makes no notification.
  Future<bool> isMuted(String email);

  /// Mute a sender's notifications, or let them come again.
  Future<void> setMuted(String email, bool muted);

  /// Whether a sender's new mail goes straight to Trash.
  Future<bool> isBlocked(String email);

  /// Block a sender (new mail to Trash, no notice), or let them in again.
  Future<void> setBlocked(String email, bool blocked);

  /// Every rule, in the order they are tried.
  Future<List<MailRule>> rules();

  /// Adds a rule (id 0) or changes one; returns its id. It sorts new
  /// inbox mail from now on.
  Future<int> saveRule(MailRule rule);

  Future<void> deleteRule(int id);

  Future<void> setRuleEnabled(int id, bool enabled);

  /// The rule worth suggesting in Rules & folders, or null.
  Future<RuleSuggestion?> ruleSuggestion() async => null;

  /// Not now: the same suggestion doesn't come back.
  Future<void> dismissRuleSuggestion(RuleSuggestion suggestion) async {}

  /// The inbox mail already here that [rule] would sort, newest first.
  Future<List<MailRow>> rulePreview(MailRule rule, {int limit = 500});

  /// Does what [rule] says to [rows], mail already here: "Apply to those
  /// too". On failure they show again and this throws.
  Future<void> applyRule(MailRule rule, List<MailRow> rows) async {
    if (rows.isEmpty) return;
    switch (rule.action) {
      case RuleAction.markRead:
        await setSeen(rows, true);
      case RuleAction.archive:
        for (final r in rows) {
          setHidden(r, true);
        }
        await apply(rows, MessageAction.archive);
      case RuleAction.moveTo:
        await moveTo(rows, rule.target);
      case RuleAction.label:
        await setLabel(rows, rule.target, true);
      case RuleAction.vault:
        final kept = await pinToVault(rows);
        for (final r in kept) {
          setHidden(r, true);
        }
        await apply(kept, MessageAction.archive);
    }
  }

  /// "Move to Vault": [rows] keep a card in the Vault wherever they go.
  /// Returns the ones it can follow into Archive.
  Future<List<MailRow>> pinToVault(List<MailRow> rows) async => rows;

  /// Trusted senders, most recent first.
  Future<List<TrustedSender>> trustedSenders();

  /// Whether remote images wait for consent for every untrusted sender.
  Future<void> setBlockRemoteImages(bool block) async => setPrivacySettings(
    (await privacySettings()).copyWith(blockImages: block),
  );

  Future<PrivacySettings> privacySettings();

  /// Whether the phone inbox should show, once, how a row swipes. The
  /// first ask says yes and remembers it; every later one says no.
  Future<bool> takeSwipeHint() async => false;

  Future<void> setPrivacySettings(PrivacySettings settings);

  /// A company sender's picture as a PNG (`PicturesToApprove`), or null.
  Future<Uint8List?> senderPicture(String email) async => null;

  /// The pictures already asked for, shared by every list and reader.
  late final SenderPictures pictures = SenderPictures(senderPicture);

  /// Read newsletters more than a week old archive themselves (on unless
  /// turned off in Settings › Rules & folders).
  Future<bool> archiveReadNewsletters();

  Future<void> setArchiveReadNewsletters(bool on);

  /// Newsletters left unopened for 30 days archive themselves, nightly
  /// (off unless turned on in Settings › Rules & folders), and how many
  /// did on this device.
  Future<({bool on, int archived})> unopenedNewsletters();

  Future<void> setUnopenedNewsletters(bool on);

  /// What was stopped in the last 30 days.
  Future<PrivacyStats> privacyStats();

  /// Whether the account's server vouched for the sender of [row] (DKIM,
  /// SPF, DMARC), as far as the message read here says; false while "Show
  /// verified sender" is off.
  bool senderVerified(MailRow row);

  /// Why the sender of [row] isn't who they say (`ProtectionToApprove`
  /// section 2), once its body is kept; null when all is well.
  Future<SenderWarning?> senderWarning(MailRow row) async => null;

  /// Looks for the server settings of an address; null when they have to
  /// be entered by hand.
  Future<FoundSettings?> discoverSettings(String email);

  /// An account's servers.
  Future<AccountServers> accountServers(int accountId);

  /// Changes an account's name, From name and color.
  Future<MailAccount> updateAccount(MailAccount account);

  /// Checks new servers with the account's password and keeps them.
  /// Throws [AddAccountException].
  Future<void> setAccountServers(int accountId, AccountServers servers);

  /// Removes an account and its mail from this device; the mail stays on
  /// the server.
  Future<void> removeAccount(int accountId);

  /// "Tell me when it can't sign in", on unless turned off.
  Future<bool> signInAlert(int accountId);

  /// The account's away message as its server has it; null when the
  /// server takes none, and Settings shows no row for it.
  Future<AwayMessage?> awayMessage(int accountId) async => null;

  /// Puts the away message on the server (or takes it off), as [message]
  /// says; then [changes] fires.
  Future<AwaySaved> setAwayMessage(int accountId, AwayMessage message) async =>
      AwaySaved.unsupported;

  /// "Turn off", from the inbox line.
  Future<void> turnOffAwayMessage(int accountId) async {}

  /// The away messages answering now, by account.
  List<AwayLine> awayLines() => const [];

  Future<void> setSignInAlert(int accountId, bool on);

  /// How the account's connection is going.
  AccountHealth accountHealth(int accountId);

  /// Checks a new password for an account in [SyncStatus.failed], keeps it
  /// and follows the account again. Throws [AddAccountException].
  Future<void> signInAgain(int accountId, String password);

  /// Checks the login, then adds the account. Without [smtp] the engine
  /// guesses `smtp.<domain>` on port 465.
  Future<MailAccount> addImapAccount({
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    required String host,
    required int port,
    required ServerSecurity security,
    required String username,
    required String password,
    MailServer? smtp,
  });

  /// Checks the login against a JMAP server, then adds the account. With
  /// [apiToken] the password is an API token, sent without the address.
  Future<MailAccount> addJmapAccount({
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    required String sessionUrl,
    required String password,
    bool apiToken = false,
  });

  /// Hides a message from the lists while its action can be undone, or
  /// shows it again.
  void setHidden(MailRow row, bool hidden);

  /// Moves messages to Archive, Trash or spam, all in one go. On failure
  /// they show again and this throws.
  Future<void> apply(List<MailRow> rows, MessageAction action);

  /// The account's spam folder, by its server name, once a sync found
  /// one; null when it has none, and Report spam isn't offered.
  String? junkMailbox(int accountId) => null;

  /// Snoozes messages until [until]: they leave the lists at once, wait
  /// in their account's Snoozed folder and come back to the inbox, unread.
  /// On failure they show again and this throws. With [unlessReply]
  /// ("If nobody replies") a reply from someone else brings them back
  /// sooner.
  Future<void> snooze(
    List<MailRow> rows,
    DateTime until, {
    bool unlessReply = false,
  });

  /// Brings snoozed messages back to the inbox now, unread.
  Future<void> wake(List<MailRow> rows);

  /// How many messages are snoozed, for the sidebar.
  Future<int> snoozedCount() async =>
      (await page(0, 100000, folder: MailFolder.snoozed)).length;

  /// How many emails are in Waiting, and how many of them have waited
  /// [waitingLongDays] or more: the sidebar's count and the phone's line.
  Future<({int all, int long})> waitingCount(DateTime now) async {
    final rows = await page(0, 100000, folder: MailFolder.waiting);
    return (
      all: rows.length,
      long: rows
          .where((r) => waitingDays(r.receivedAt, now) >= waitingLongDays)
          .length,
    );
  }

  /// Leaves sent mail out of Waiting; it stays in Sent.
  Future<void> stopWaiting(List<MailRow> rows) async {}

  /// "Remind me if nobody replies" for a row of Waiting: it comes back to
  /// the top of the inbox at [at] if nobody has replied by then; null
  /// forgets it.
  Future<void> remindMe(MailRow row, DateTime? at) async {}

  /// The rows of Waiting whose reminder has come by [now]: back at the
  /// top of the inbox, the latest back first.
  Future<List<MailRow>> reminded(DateTime now, {int? account}) async {
    final back = [
      for (final r in await page(
        0,
        100000,
        folder: MailFolder.waiting,
        account: account,
      ))
        if (r.remindAt case final at? when !at.isAfter(now)) r,
    ];
    return back..sort((a, b) => b.remindAt!.compareTo(a.remindAt!));
  }

  /// Marks messages read or unread: at once here, then on their servers.
  /// On failure they go back and this throws.
  Future<void> setSeen(List<MailRow> rows, bool seen);

  /// Newsletters, newest first; with [account], only that account's.
  Future<List<Newsletter>> newsletters(int offset, int limit, {int? account});

  /// The address of an issue's cover picture: its first photo, when the
  /// sender's images may load and its body is already here; else null.
  Future<String?> newsletterCover(MailRow row) async => null;

  /// How many newsletters there are, and how many are unread.
  Future<int> newsletterCount();
  Future<int> newsletterUnread();

  /// How the list [row] came from can be left.
  Future<UnsubscribeInfo> unsubscribeInfo(MailRow row);

  /// Leaves the list [row] came from, with one request or a message to
  /// its address; a page to open is the caller's to open.
  Future<void> unsubscribe(MailRow row);

  /// Where the inbox mail of [email] goes from now on, what is there
  /// already included: [MailFolder.inbox] or [MailFolder.newsletters].
  Future<void> setSenderZone(String email, MailFolder folder);

  /// Whether [row]'s sender counts as a person: its mail shows in People,
  /// not Notifications.
  bool byPerson(MailRow row);

  /// Puts [email]'s inbox mail in People ([people] true) or Notifications
  /// from now on, what is there already included; null lets its headers
  /// decide again.
  Future<void> setSenderSide(String email, bool? people);

  /// The Vault's cards, newest email first; with [account], only that
  /// account's.
  Future<List<VaultCard>> vaultCards({int? account});

  /// Messages sent from PEC mailboxes, newest receipt first; with
  /// [account], only that account's.
  Future<List<PecMessage>> pecMessages({int? account});

  /// Saves the receipts of [message] whole, as the provider signed them,
  /// in Downloads. Returns the saved files' paths.
  Future<List<String>> savePecReceipts(PecMessage message);

  /// Marks a bill paid, or not, by its card's [VaultCard.key].
  Future<void> setVaultPaid(String key, bool paid);

  /// Every file received, newest email first; with [account], only that
  /// account's. Mail you sent or drafted is left out.
  Future<List<AttachedFile>> attachedFiles({int? account});

  /// A small preview of an attached picture, fetched once and kept; null
  /// for other files, or when it can't be had.
  Future<Uint8List?> attachmentThumb(AttachedFile file);

  /// How many pages an attached PDF has, drawn on this device; null when
  /// it can't be shown here (damaged, or locked with a password).
  Future<int?> attachmentPages(AttachedFile file);

  /// Page [index] (from 0) of an attached PDF, as a picture [width]
  /// pixels wide; null when it can't be drawn here.
  Future<Uint8List?> attachmentPage(AttachedFile file, int index, int width);

  /// An attached file whole, for a picture shown full size.
  Future<Uint8List?> attachmentData(AttachedFile file);

  /// Searches every message on this device. [query] is what the person
  /// typed, operators included (`from:`, `account:`, `is:unread`,
  /// `after:`, `before:`).
  Future<SearchResults> search(String query, {int limit = 50});

  /// Frequent contacts, recent searches and how much is indexed, for an
  /// empty search.
  Future<SearchStart> searchStart();

  /// Keeps [query] among the recent searches, or with [forget] removes it.
  Future<void> noteSearch(String query, {bool forget = false});

  /// Forgets every recent search.
  Future<void> clearSearches();

  /// The people to suggest while an address is typed in compose: the
  /// ones written to most first, then the ones who write most.
  Future<List<Contact>> suggestRecipients(String typed, {int limit = 6});

  /// Groups of addresses, in order.
  Future<List<MailGroup>> groups();

  /// What is unread in each group, by group id.
  Future<Map<int, GroupUnread>> groupUnread();

  /// The alias [row] was written to, when it went to one of its account's
  /// aliases rather than its own address.
  String? writtenTo(MailRow row);

  /// Keeps a group (new when its id is 0) and returns its id. An address
  /// taken from another group leaves that one.
  Future<int> saveGroup(MailGroup group);

  Future<void> deleteGroup(int id);

  /// The other addresses an account sends from.
  Future<List<String>> aliases(int accountId);

  /// Addresses the account's Sent mail went from that aren't aliases yet:
  /// aliases to add with a tap.
  Future<List<String>> aliasSuggestions(int accountId);

  /// Adds an alias; throws when [email] isn't an address.
  Future<void> addAlias(int accountId, String email);

  /// Forgets an alias and takes it out of its group.
  Future<void> removeAlias(int accountId, String email);

  /// "Always reply from the address they wrote to"; on at first.
  bool get replyAsWritten;
  Future<void> setReplyAsWritten(bool on);

  /// The alias a reply to [row] goes from, the one it was written to, or
  /// null for the account's own address.
  String? replyFrom(MailRow row);

  /// Templates for compose's "/", on this device for every account: the
  /// ones used last first, then by name.
  Future<List<MailTemplate>> templates();

  /// Keeps a template (new when its id is 0) and returns its id.
  Future<int> saveTemplate(MailTemplate template);

  Future<void> deleteTemplate(int id);

  /// Notes that a template was just put in a message, so it lists first.
  Future<void> templateUsed(int id);

  /// Every signature, by account, oldest first.
  Future<List<MailSignature>> signatures();

  /// Saves a signature (new when its id is 0) and returns its id. When it
  /// takes a job (new emails, replies), the account's other one gives it up.
  Future<int> saveSignature(MailSignature signature);

  Future<void> deleteSignature(int id);

  /// Makes a picked logo small enough for every email. Throws
  /// [LogoException].
  Future<Uint8List> shrinkLogo(Uint8List data);

  /// Sends a draft and files a copy in Sent; its saved copy goes. When
  /// the server can't be reached it waits in the outbox, goes once the
  /// connection is back, and this returns its id there. Throws
  /// [SendException].
  Future<int?> send(Draft draft);

  /// Keeps [draft] to send at [at] from this device: it waits in the
  /// Outbox until then. Returns its id there, to take it back.
  Future<int> schedule(Draft draft, DateTime at);

  /// Whether new mail can reach the device with the app closed, and the
  /// person picks how (Android, `AndroidBackground`).
  bool get backgroundChoice => false;

  /// How new mail arrives with the app closed; null until picked.
  Future<BackgroundDelivery?> backgroundDelivery() async => null;

  /// Picks it, and starts what it needs.
  Future<void> setBackgroundDelivery(BackgroundDelivery delivery) async {}

  /// True when the system shows the notices itself (Android's background
  /// service), so the app must not show them too.
  bool get nativeNotices => false;

  /// Mail waiting to go, oldest first: one account's, or every account's.
  Future<List<OutboxItem>> outbox(int? accountId);

  /// Takes a message back out of the outbox, to edit it.
  Future<Draft> reopenOutgoing(int id);

  /// How many drafts every account keeps.
  Future<int> draftCount();

  /// Keeps a draft in its account's Drafts folder, in place of its earlier
  /// copy. Returns where it is now; throws when it can't (offline).
  Future<DraftCopy> saveDraft(Draft draft);

  /// A saved draft, to go on writing it.
  Future<Draft> openDraft(MailRow row);

  /// Moves a saved draft to Trash.
  Future<void> discardDraft(DraftCopy copy);

  /// Devices & sync as it stands.
  SyncState syncState();

  /// The accounts whose mailbox can hold the space.
  List<int> syncHomes();

  /// Turns sync on with the space in [accountId]'s mailbox. Returns the
  /// 24-word recovery phrase, shown once.
  Future<String> turnOnSync(int accountId);

  /// Moves the space to [accountId]'s mailbox. The other devices follow
  /// on their own; nobody pairs again.
  Future<void> moveSync(int accountId);

  /// The recovery phrase, to show it again.
  Future<String> recoveryPhrase();

  /// Unlinks a device and returns the new recovery phrase.
  Future<String> unlinkDevice(String id);

  /// "Turn off sync on this device": this device leaves the space; its
  /// accounts and mail stay. The last device deletes the space.
  Future<void> turnOffSync();

  /// New devices asking to be linked, newest first.
  ValueListenable<List<PairAsk>> get pairAsks;

  /// Approves a new device with the 6 digits it shows.
  Future<void> approveDevice(String id, String code);

  /// "Not me".
  Future<void> refuseDevice(String id);

  /// While "Link a new device" is open: looks for requests often.
  void watchPairing(bool on) {}

  /// On a new device, after signing in: the space [accountId]'s mailbox
  /// holds, if any.
  Future<SpaceFound?> findSpace(int accountId);

  /// Six new digits for this device to show.
  String pairCode();

  /// Asks to be linked with [code] and waits until a linked device
  /// approves it; throws a [SyncFailure] when it is refused, expires, or
  /// the code typed there was another.
  Future<void> joinSpace(int accountId, String code);

  /// Stops waiting in [joinSpace].
  void cancelJoin() {}

  /// Whether this device can scan a QR code to be linked: phones with a
  /// camera.
  bool get canScan => false;

  /// "Link a new device": a QR code for a phone to scan, with a new code;
  /// null when it can't be made (sync off). While it shows, the phones
  /// that scan it are linked without asking.
  PairInvite? pairInvite() => null;

  /// "Link a new device" closed: the code answers no one any more.
  void endPairInvite() {}

  /// Looks for a linked device's QR code in a camera frame: one byte of
  /// light per pixel, [stride] bytes a row.
  ScannedPair? readPairCode(
    Uint8List gray,
    int width,
    int height,
    int stride,
  ) => null;

  /// Signs in to the mailbox a scanned code names, with its settings.
  Future<MailAccount> addInviteAccount(ScannedPair code, String password) =>
      throw UnimplementedError();

  /// Asks to be linked with a scanned code; the device that showed it
  /// answers on its own. Throws a [SyncFailure] like [joinSpace].
  Future<void> joinWithInvite(int accountId, ScannedPair code) =>
      throw UnimplementedError();

  /// Opens the space with the recovery phrase.
  Future<void> recoverSpace(int accountId, String phrase);

  /// Whether [phrase] is 24 words that make a recovery phrase.
  bool phraseValid(String phrase);

  /// Whether reports can go through the project's relay; without it only
  /// "Send by email instead" is offered.
  bool get reportsByRelay => true;

  /// "Shake to report": shaking the phone opens the report sheet. Off at
  /// first; offered only where the device can tell a shake.
  ValueListenable<bool> get shakeToReport;
  Future<void> setShakeToReport(bool on);

  /// The report sheet opened: get ready so Send is instant.
  Future<void> prepareReport() async {}

  /// "See what's sent".
  Future<ReportPreview> previewReport(ReportDraft draft);

  /// Send: keeps the report and sends it in the background. [screenshot]
  /// is the PNG with its hidden parts already blurred.
  Future<SentReport> sendReport(ReportDraft draft, Uint8List? screenshot);

  /// Your reports, newest first.
  Future<List<SentReport>> reports();

  Future<void> retryReport(String id);

  Future<void> deleteReport(String id);

  /// The report as an email from the person's own account.
  Future<ReportEmail> reportEmail(String id);

  /// The email went: the report stops waiting.
  Future<void> reportEmailed(String id);

  /// Whether the app crashed last time and the person hasn't answered the
  /// line offering a report yet.
  bool get crashWaiting => false;

  /// The person closed that line.
  void dismissCrash() {}

  /// Adds a line to the log a report can carry; the engine cleans it.
  void logLine(String area, String message, {bool error = false}) {}

  void dispose() {}
}

/// What the reader's warning band says about a sender: see
/// [MailSource.senderWarning].
enum SenderWarningKind {
  /// The address imitates [SenderWarning.like], a domain mail comes from.
  looksLike,

  /// The name claims [SenderWarning.brand], the address is elsewhere.
  brand,

  /// The domain in From failed its own check.
  dmarcFailed,
}

class SenderWarning {
  const SenderWarning({
    required this.kind,
    required this.domain,
    this.like,
    this.likeCount = 0,
    this.brand,
    this.dmarcFailed = false,
    this.signedBy,
    this.sentBy,
  });

  final SenderWarningKind kind;

  /// The domain in From.
  final String domain;
  final String? like;

  /// How many emails came from [like].
  final int likeCount;
  final String? brand;
  final bool dmarcFailed;

  /// For Details: whose signature passed, and the server that sent it.
  final String? signedBy;
  final String? sentBy;
}
