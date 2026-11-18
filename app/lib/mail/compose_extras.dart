import 'package:flutter/foundation.dart';

import 'mail_source.dart';

/// Where a picture sits in a body: one object replacement character per
/// picture, in order (the engine's `compose_image::PLACEHOLDER`).
const imagePlaceholder = '￼';

/// The most one picture inside a message weighs once made ready (the
/// engine's `compose_image::MAX_BYTES`, what a reader keeps of one).
const maxInlineImageSize = 2 * 1000 * 1000;

/// The most all the pictures inside one message weigh together: what a
/// reader keeps of them (`imap::INLINE_TOTAL`).
const maxInlineImagesSize = 8 * 1000 * 1000;

/// A picture inside the text of a message being written.
@immutable
class DraftImage {
  const DraftImage(
    this.name,
    this.mime,
    this.data, {
    this.width = 0,
    this.height = 0,
  });

  final String name;

  /// "image/jpeg", "image/png" or "image/gif".
  final String mime;
  final Uint8List data;

  /// Its size in pixels, when known; 0 otherwise.
  final int width;
  final int height;
}

/// Why a picture could not go inside a message.
enum ImageProblem { notAnImage, tooBig }

class ImageException implements Exception {
  const ImageException(this.problem, {this.file});
  final ImageProblem problem;

  /// A picture the engine can't draw (HEIC from a phone's clipboard),
  /// to attach as it is instead.
  final DraftFile? file;
}

/// The answer of Android's clipboard (`Clipboard.kt`) made a picture for
/// the text by [prepare]: null for none; [ImageProblem.tooBig] for one
/// too big to read; one the engine can't draw comes back as a file to
/// attach ([ImageException.file]).
Future<DraftImage?> androidClipboardPicture(
  Map<String, Object?>? got,
  Future<DraftImage> Function(String name, Uint8List data) prepare,
) async {
  if (got == null) return null;
  if (got['tooBig'] == true) throw const ImageException(ImageProblem.tooBig);
  final data = got['data'];
  if (data is! Uint8List || data.isEmpty) return null;
  final mime = (got['mime'] as String?)?.toLowerCase() ?? '';
  final sub = mime.startsWith('image/') ? mime.substring(6) : '';
  final ext = switch (sub) {
    'jpeg' || 'pjpeg' => 'jpg',
    'svg+xml' => 'svg',
    final s when RegExp(r'^[a-z0-9]{1,8}$').hasMatch(s) => s,
    _ => 'png',
  };
  final name = 'image.$ext';
  try {
    return await prepare(name, data);
  } on ImageException catch (e) {
    if (e.problem != ImageProblem.notAnImage) rethrow;
    throw ImageException(ImageProblem.notAnImage, file: DraftFile(name, data));
  }
}

/// Settings › Writing › Replies, and each account's plain-text default.
@immutable
class ComposeSettings {
  const ComposeSettings({
    this.replyBelow = false,
    this.quoteSelection = true,
    this.plainTextAccounts = const {},
  });

  /// Replies are written under the quoted message instead of above it.
  final bool replyBelow;

  /// With words selected in the reader, a reply quotes only them.
  final bool quoteSelection;

  /// The accounts (by address, lowercase) whose new messages start as
  /// plain text.
  final Set<String> plainTextAccounts;

  bool plainTextFor(String email) =>
      plainTextAccounts.contains(email.toLowerCase());

  ComposeSettings copyWith({
    bool? replyBelow,
    bool? quoteSelection,
    Set<String>? plainTextAccounts,
  }) => ComposeSettings(
    replyBelow: replyBelow ?? this.replyBelow,
    quoteSelection: quoteSelection ?? this.quoteSelection,
    plainTextAccounts: plainTextAccounts ?? this.plainTextAccounts,
  );
}

/// A contact group: a name typed in To, Cc or Bcc for all its addresses.
@immutable
class ContactGroup {
  const ContactGroup({
    this.uid = '',
    required this.name,
    this.addresses = const [],
  });

  /// Empty for one not kept yet.
  final String uid;
  final String name;

  /// `a@b.c` or `Name <a@b.c>`.
  final List<String> addresses;

  ContactGroup copyWith({String? uid, String? name, List<String>? addresses}) =>
      ContactGroup(
        uid: uid ?? this.uid,
        name: name ?? this.name,
        addresses: addresses ?? this.addresses,
      );
}

/// The contact group named [typed] (ignoring case), if any.
ContactGroup? contactGroupNamed(List<ContactGroup> groups, String typed) {
  final t = typed.trim().toLowerCase();
  if (t.isEmpty) return null;
  for (final g in groups) {
    if (g.name.trim().toLowerCase() == t) return g;
  }
  return null;
}

/// What was typed in To, Cc or Bcc, cut into recipients at commas,
/// semicolons and line breaks: a contact group's name, found by
/// [expand], even one with a comma in it ("Smith, family"; the longest
/// name wins), comes with its addresses; a piece with no address and no
/// group joins the next (`Rossi, Mario <m@x.it>`). The last piece may be
/// neither, still being typed.
List<({String text, List<String>? group})> typedRecipients(
  String text,
  List<String>? Function(String typed)? expand,
) {
  final pieces = text.split(RegExp(r'[,;\n]'));
  String join(int from, int to) => pieces.sublist(from, to + 1).join(',');
  final out = <({String text, List<String>? group})>[];
  var i = 0;
  while (i < pieces.length) {
    var found = false;
    for (var j = pieces.length - 1; j >= i && expand != null; j--) {
      final name = join(i, j).trim();
      if (name.isEmpty) continue;
      if (expand(name) case final group?) {
        out.add((text: name, group: group));
        i = j + 1;
        found = true;
        break;
      }
    }
    if (found) continue;
    if (pieces[i].trim().isEmpty) {
      i++;
      continue;
    }
    var j = i;
    while (j < pieces.length - 1 &&
        pieces[j + 1].trim().isNotEmpty &&
        !join(i, j).contains('@')) {
      j++;
    }
    out.add((text: join(i, j).trim(), group: null));
    i = j + 1;
  }
  return out;
}

/// What a message being read asks of its reader.
@immutable
class MessageAsks {
  const MessageAsks({this.readReceiptTo, this.highPriority = false});

  /// Where a read receipt would go, when the reader should offer one.
  final String? readReceiptTo;

  /// The sender marked it important.
  final bool highPriority;
}

/// The picture kinds a message carries inside its text, by their first
/// bytes; null for anything else.
String? imageMime(Uint8List data) {
  bool starts(List<int> magic) =>
      data.length >= magic.length &&
      Iterable.generate(magic.length).every((i) => data[i] == magic[i]);
  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  return null;
}

/// What compose needs beside the message: pictures, the writing
/// settings, contact groups, and read receipts. The defaults keep
/// everything in memory and take pictures as they are, for the demo and
/// tests; the engine's source keeps them in the engine.
mixin ComposeExtras {
  /// A picture made ready to go inside a message: turned the right way,
  /// smaller when big, without the camera's metadata. Throws
  /// [ImageException].
  Future<DraftImage> prepareImage(String name, Uint8List data) async {
    final mime = imageMime(data);
    if (mime == null) throw const ImageException(ImageProblem.notAnImage);
    if (data.length > maxInlineImageSize) {
      throw const ImageException(ImageProblem.tooBig);
    }
    return DraftImage(name, mime, data);
  }

  /// The picture on the system clipboard, made ready; null when there is
  /// none (and on phones, whose keyboards hand pictures to the field).
  Future<DraftImage?> clipboardImage() async => null;

  /// The language of text being written ("it", "de"…), for the spell
  /// checker; null when it can't tell.
  String? textLanguage(String text) => null;

  ComposeSettings _composeSettings = const ComposeSettings();

  Future<ComposeSettings> composeSettings() async => _composeSettings;

  Future<void> setComposeSettings(ComposeSettings settings) async =>
      _composeSettings = settings;

  List<ContactGroup> _contactGroups = const [];
  int _nextGroup = 1;

  /// Every contact group, by name.
  Future<List<ContactGroup>> contactGroups() async =>
      [..._contactGroups]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Keeps a group, a new one when its uid is empty. Returns its uid.
  Future<String> saveContactGroup(ContactGroup group) async {
    final uid = group.uid.isEmpty ? 'g${_nextGroup++}' : group.uid;
    _contactGroups = [
      for (final g in _contactGroups)
        if (g.uid != uid) g,
      group.copyWith(uid: uid, name: group.name.trim()),
    ];
    return uid;
  }

  Future<void> deleteContactGroup(String uid) async => _contactGroups = [
    for (final g in _contactGroups)
      if (g.uid != uid) g,
  ];

  /// What [row] asks of its reader; nothing until its body is kept.
  Future<MessageAsks> messageAsks(MailRow row) async => const MessageAsks();

  /// The person's answer to the read receipt [row] asks for: [send] it,
  /// or not; with [never], none is offered for that sender again. True
  /// when the receipt waits in the outbox for the connection, false once
  /// sent, null when it was deleted from the Outbox before it went.
  Future<bool?> answerReadReceipt(
    MailRow row, {
    required bool send,
    bool never = false,
  }) async => false;
}
