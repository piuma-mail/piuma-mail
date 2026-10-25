import 'dart:typed_data';

/// A message made safe to read by the engine: blocks the app draws with
/// its own type, never HTML. See `core/src/reading.rs`.
class Readable {
  const Readable({
    required this.blocks,
    this.remoteImages = 0,
    this.trackers = const [],
    this.linksCleaned = 0,
    this.trusted = false,
    this.blockImages = true,
    this.attachments = const [],
    this.invite,
    this.dates = const [],
    this.layout = false,
    this.language,
  });

  /// Plain text in paragraphs, `>` lines as quotes.
  factory Readable.fromText(String text) {
    final blocks = <BodyBlock>[];
    var quote = 0;
    final lines = <String>[];
    void flush() {
      final joined = lines.join('\n').trim();
      if (joined.isNotEmpty) {
        blocks.add(BodyBlock.text([BodySpan(joined)], quote: quote));
      }
      lines.clear();
    }

    for (var line in text.replaceAll('\r\n', '\n').split('\n')) {
      var depth = 0;
      while (line.trimLeft().startsWith('>')) {
        line = line.trimLeft().substring(1);
        if (line.startsWith(' ')) line = line.substring(1);
        depth++;
      }
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      if (lines.isNotEmpty && depth != quote) flush();
      quote = depth;
      lines.add(line.trimRight());
    }
    flush();
    return Readable(blocks: blocks);
  }

  final List<BodyBlock> blocks;

  /// Remote images, which load only when the person allows it.
  final int remoteImages;
  final List<StoppedTracker> trackers;
  final int linksCleaned;

  /// The sender is trusted: their images load on their own.
  final bool trusted;

  /// Remote images wait for consent (the default).
  final bool blockImages;

  /// Files attached to the message, fetched when opened.
  final List<MailAttachment> attachments;

  /// The calendar invite it carries, if any.
  final MailInvite? invite;

  /// Days with a time in its words, offered for a calendar.
  final List<FoundDate> dates;

  /// It was built as a layout (grids, columns): its original is worth a
  /// look, with Show original layout.
  final bool layout;

  /// The language it is written in ("de"), when the engine is sure.
  final String? language;

  /// Everything stopped, one entry per row of the privacy sheet: each
  /// tracker, and the cleaned links.
  int get stopped => trackers.length + (linksCleaned > 0 ? 1 : 0);

  bool get hasPrivacyNews => remoteImages > 0 || stopped > 0;

  /// Where the quoted text at the end begins (with its "… wrote:" line),
  /// or `blocks.length` when the message doesn't end with a quote.
  int get quoteStart {
    var i = blocks.length;
    while (i > 0 && blocks[i - 1].quote > 0) {
      i--;
    }
    if (i == blocks.length || i == 0) return blocks.length;
    final intro = blocks[i - 1].text.trim();
    if (intro.endsWith(':') && intro.length < 200) i--;
    return i == 0 ? blocks.length : i;
  }

  Readable copyWith({
    List<BodyBlock>? blocks,
    bool? trusted,
    bool? blockImages,
    List<MailAttachment>? attachments,
    MailInvite? invite,
    List<FoundDate>? dates,
    String? language,
  }) => Readable(
    blocks: blocks ?? this.blocks,
    remoteImages: remoteImages,
    trackers: trackers,
    linksCleaned: linksCleaned,
    trusted: trusted ?? this.trusted,
    blockImages: blockImages ?? this.blockImages,
    attachments: attachments ?? this.attachments,
    invite: invite ?? this.invite,
    dates: dates ?? this.dates,
    layout: layout,
    language: language ?? this.language,
  );
}

/// An email as it was sent, made safe by the engine for the web view.
class OriginalDoc {
  const OriginalDoc({required this.html, this.suspicious = const {}});

  final String html;

  /// Links whose text shows another site, with that text.
  final Map<String, String> suspicious;
}

/// "In short" over a long conversation, found on this device: the
/// sentences that carry its decisions and figures, and what the last
/// message asks of you.
class ThreadBrief {
  const ThreadBrief({
    required this.points,
    this.yourTurn,
    this.askedBy = '',
    this.transcript = '',
    this.byModel = false,
  });

  final List<String> points;

  /// The last message's request, in its own words.
  final String? yourTurn;

  /// Who asks it.
  final String askedBy;

  /// The messages' own words, "Name: text" a line, for the device's own
  /// model to rewrite [points] from.
  final String transcript;

  /// [points] are the device model's words, not picked by the rules.
  final bool byModel;
}

/// "In short" on a sender's card, found on this device.
class SenderBrief {
  const SenderBrief({required this.recent, this.topic, this.waiting = false});

  /// Their emails in the last 30 days.
  final int recent;

  /// The subject most of their recent emails share.
  final String? topic;

  /// Their latest email is still unanswered.
  final bool waiting;

  /// Worth a line: a topic, an email waiting, or several this month.
  bool get telling => topic != null || waiting || recent >= 2;
}

/// How much a sender writes, for a newsletter's card.
class SenderStats {
  const SenderStats({
    required this.recent,
    required this.opened,
    this.inNewsletters = false,
  });

  /// The days [recent] covers.
  static const days = 56;

  /// Their emails in the last [days] days.
  final int recent;

  /// Of those, opened.
  final int opened;

  /// Their mail goes to Newsletters.
  final bool inNewsletters;

  /// Opened, out of 100.
  int get openedPercent => recent == 0 ? 0 : (opened * 100 / recent).round();
}

/// A day with a time written in a message ("can we talk Friday at 10?"),
/// found on this device, which the reader offers to put in a calendar.
class FoundDate {
  const FoundDate({
    required this.block,
    required this.start,
    required this.end,
    required this.at,
    required this.uid,
    this.addedTo,
  });

  /// The block it is in, and where in the block's text.
  final int block;
  final int start;
  final int end;

  /// The time it names, where you are.
  final DateTime at;

  /// The event it becomes, so adding it twice changes nothing.
  final String uid;

  /// The calendar it went to, once added.
  final String? addedTo;

  FoundDate added(String calendar) => FoundDate(
    block: block,
    start: start,
    end: end,
    at: at,
    uid: uid,
    addedTo: calendar,
  );
}

/// What an invite's calendar asks for.
enum InviteMethod {
  /// An invite, or a change to one: it can be answered.
  request,

  /// The event is off.
  cancel,

  /// Someone answered an invite you sent.
  reply,

  /// An event to look at, with nothing to answer.
  publish,
}

enum InviteAnswer { accepted, tentative, declined }

class InvitePerson {
  const InvitePerson({required this.name, required this.email, this.answer});
  final String name;
  final String email;
  final InviteAnswer? answer;

  String get label => name.isNotEmpty ? name : email;
}

/// A calendar invite in a message, as its card shows it. Piuma has no
/// calendar of its own: an answer goes to the organizer by email.
class MailInvite {
  const MailInvite({
    required this.method,
    this.uid = '',
    required this.summary,
    this.location = '',
    required this.start,
    required this.end,
    this.allDay = false,
    this.repeats = false,
    this.organizer,
    this.attendees = const [],
    this.answer,
    this.yours = false,
  });

  final InviteMethod method;

  /// The event's UID, the same in your calendar once accepted.
  final String uid;
  final String summary;
  final String location;

  /// In the person's own time.
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final bool repeats;
  final InvitePerson? organizer;
  final List<InvitePerson> attendees;

  /// How you answered.
  final InviteAnswer? answer;

  /// You sent it.
  final bool yours;

  /// Whether Yes, Maybe and No are offered.
  bool get answerable =>
      method == InviteMethod.request && organizer != null && !yours;

  MailInvite withAnswer(InviteAnswer? answer) => MailInvite(
    method: method,
    uid: uid,
    summary: summary,
    location: location,
    start: start,
    end: end,
    allDay: allDay,
    repeats: repeats,
    organizer: organizer,
    attendees: attendees,
    answer: answer,
    yours: yours,
  );
}

enum BlockKind { paragraph, heading, listItem, image, rule, code }

class BodyBlock {
  const BodyBlock({
    required this.kind,
    this.level = 0,
    this.quote = 0,
    this.marker = '',
    this.spans = const [],
    this.image,
  });

  const BodyBlock.text(this.spans, {this.quote = 0})
    : kind = BlockKind.paragraph,
      level = 0,
      marker = '',
      image = null;

  final BlockKind kind;

  /// Heading level (1 large, 2 small) or list depth.
  final int level;

  /// Quote depth, 0 when not quoted.
  final int quote;

  /// "•" or "3." for list items.
  final String marker;
  final List<BodySpan> spans;
  final BodyImage? image;

  String get text => spans.map((s) => s.text).join();
}

class BodySpan {
  const BodySpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.link,
    this.suspicious = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  /// Where the link goes, already cleaned: http, https or mailto.
  final String? link;

  /// The text shows a different address than where the link goes.
  final bool suspicious;
}

class BodyImage {
  const BodyImage({
    this.url = '',
    this.data,
    this.alt = '',
    this.width,
    this.height,
    this.link,
  });

  /// Remote address; empty when the image is in [data].
  final String url;
  final Uint8List? data;
  final String alt;
  final int? width;
  final int? height;
  final String? link;

  bool get remote => data == null && url.isNotEmpty;
}

enum TrackerKind { pixel, font, style }

class StoppedTracker {
  const StoppedTracker(this.kind, this.host, {this.count = 1});

  final TrackerKind kind;
  final String host;
  final int count;
}

/// The switches of Privacy & security. All on by default.
class PrivacySettings {
  const PrivacySettings({
    this.blockImages = true,
    this.stopPixels = true,
    this.cleanLinks = true,
    this.warnLinks = true,
    this.verifiedSender = true,
    this.senderPictures = true,
    this.websiteIcons = true,
  });

  final bool blockImages;
  final bool stopPixels;
  final bool cleanLinks;
  final bool warnLinks;

  /// "Show verified sender" on senders' cards.
  final bool verifiedSender;

  /// "Sender pictures": photos from contacts and verified company logos
  /// in place of the letters (`PicturesToApprove`).
  final bool senderPictures;

  /// "Website icons": for companies without a verified logo.
  final bool websiteIcons;

  PrivacySettings copyWith({
    bool? blockImages,
    bool? stopPixels,
    bool? cleanLinks,
    bool? warnLinks,
    bool? verifiedSender,
    bool? senderPictures,
    bool? websiteIcons,
  }) => PrivacySettings(
    blockImages: blockImages ?? this.blockImages,
    stopPixels: stopPixels ?? this.stopPixels,
    cleanLinks: cleanLinks ?? this.cleanLinks,
    warnLinks: warnLinks ?? this.warnLinks,
    verifiedSender: verifiedSender ?? this.verifiedSender,
    senderPictures: senderPictures ?? this.senderPictures,
    websiteIcons: websiteIcons ?? this.websiteIcons,
  );
}

/// What was stopped in the messages read in the last 30 days.
class PrivacyStats {
  const PrivacyStats({
    this.trackers = 0,
    this.pixels = 0,
    this.linksCleaned = 0,
    this.suspiciousLinks = 0,
  });

  /// Every tracker, pixels included.
  final int trackers;
  final int pixels;
  final int linksCleaned;
  final int suspiciousLinks;

  /// Remote fonts and styles: the trackers that aren't pixels.
  int get remoteStyles => trackers - pixels;
}

class TrustedSender {
  const TrustedSender({
    required this.email,
    this.name = '',
    required this.since,
  });

  final String email;

  /// The name in their latest message; may be empty.
  final String name;
  final DateTime since;

  String get label => name.isNotEmpty ? name : email;
}

/// A file attached to a received message.
/// Why a file from an email deserves a word before it opens
/// (`ProtectionToApprove` section 3).
enum FileRisk {
  /// A program or a script.
  program,

  /// A program named like a document: "invoice.pdf.exe".
  disguised,

  /// An Office file that keeps macros.
  macros,

  /// An archive locked with a password, known once it is saved.
  locked,
}

class MailAttachment {
  const MailAttachment({
    required this.part,
    required this.name,
    this.mime = 'application/octet-stream',
    this.size = 0,
    this.risk,
  });

  /// Why it deserves a word before it opens, from its name; null for
  /// most files.
  final FileRisk? risk;

  /// Where it is in the message, for the engine.
  final int part;
  final String name;
  final String mime;

  /// Size in bytes.
  final int size;
}

/// What the tile of a file says: its extension, or its kind.
String fileBadge(String name, [String mime = '']) {
  final dot = name.lastIndexOf('.');
  if (dot > 0 && dot < name.length - 1) {
    final ext = name.substring(dot + 1);
    if (ext.length <= 4) return ext.toUpperCase();
  }
  if (mime.startsWith('image/')) return 'IMG';
  if (mime == 'message/rfc822') return 'EML';
  return 'FILE';
}

/// "2.4 MB", "820 KB", "12 bytes" in the person's language.
String fileSize(int bytes, {String locale = 'en'}) {
  String one(double v) {
    final fixed = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    final trimmed = fixed.endsWith('.0')
        ? fixed.substring(0, fixed.length - 2)
        : fixed;
    return locale.startsWith('it') ? trimmed.replaceAll('.', ',') : trimmed;
  }

  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${one(bytes / 1000)} KB';
  if (bytes < 1000 * 1000 * 1000) return '${one(bytes / 1e6)} MB';
  return '${one(bytes / 1e9)} GB';
}
