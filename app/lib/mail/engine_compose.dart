import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/api/compose.dart' as cmp;
import '../engine/api/engine.dart' as engine;
import 'mail_source.dart';

/// [ComposeExtras] kept in the engine: pictures made ready there, the
/// writing settings and contact groups in its database, read receipts
/// sent through the account's server.
mixin EngineCompose on MailSource {
  @override
  Future<DraftImage> prepareImage(String name, Uint8List data) async {
    try {
      final p = await cmp.prepareInlineImage(data: data);
      return DraftImage(
        _named(name, p.mime),
        p.mime,
        p.data,
        width: p.width,
        height: p.height,
      );
    } on engine.EngineError catch (e) {
      throw ImageException(
        e.kind == engine.ErrorKind.tooBig
            ? ImageProblem.tooBig
            : ImageProblem.notAnImage,
      );
    }
  }

  /// Android hands the clipboard's picture to Dart (`Clipboard.kt`).
  static const _clipboard = MethodChannel('mail.piuma/clipboard');

  @override
  Future<DraftImage?> clipboardImage() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final data = await _clipboard.invokeMethod<Uint8List>('picture');
      return data == null ? null : prepareImage('image', data);
    }
    try {
      final p = await cmp.clipboardImage();
      if (p == null) return null;
      return DraftImage(
        _named('image', p.mime),
        p.mime,
        p.data,
        width: p.width,
        height: p.height,
      );
    } on engine.EngineError catch (e) {
      throw ImageException(
        e.kind == engine.ErrorKind.tooBig
            ? ImageProblem.tooBig
            : ImageProblem.notAnImage,
      );
    }
  }

  /// [name] with the extension of what it became ("IMG_1.HEIC" turned
  /// JPEG is "IMG_1.jpg").
  static String _named(String name, String mime) {
    final ext = switch (mime) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      _ => 'jpg',
    };
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    return '${stem.isEmpty ? 'image' : stem}.$ext';
  }

  @override
  String? textLanguage(String text) {
    try {
      return cmp.textLanguage(text: text);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ComposeSettings> composeSettings() async {
    final s = cmp.composeSettings();
    return ComposeSettings(
      replyBelow: s.replyBelow,
      quoteSelection: s.quoteSelection,
      plainTextAccounts: {for (final a in s.plainTextAccounts) a},
    );
  }

  @override
  Future<void> setComposeSettings(ComposeSettings settings) =>
      cmp.setComposeSettings(
        settings: cmp.ComposeSettings(
          replyBelow: settings.replyBelow,
          quoteSelection: settings.quoteSelection,
          plainTextAccounts: settings.plainTextAccounts.toList(),
        ),
      );

  @override
  Future<List<ContactGroup>> contactGroups() async => [
    for (final g in cmp.contactGroups())
      ContactGroup(uid: g.uid, name: g.name, addresses: g.addresses),
  ];

  @override
  Future<String> saveContactGroup(ContactGroup group) => cmp.saveContactGroup(
    group: cmp.ContactGroupInfo(
      uid: group.uid,
      name: group.name,
      addresses: group.addresses,
    ),
  );

  @override
  Future<void> deleteContactGroup(String uid) =>
      cmp.deleteContactGroup(uid: uid);

  @override
  Future<MessageAsks> messageAsks(MailRow row) async {
    final a = cmp.messageAsks(
      accountId: row.accountId,
      mailbox: row.mailbox,
      uid: row.uid,
    );
    return MessageAsks(
      readReceiptTo: a.readReceiptTo,
      highPriority: a.highPriority,
    );
  }

  @override
  Future<void> answerReadReceipt(
    MailRow row, {
    required bool send,
    bool never = false,
  }) => cmp.answerReadReceipt(
    accountId: row.accountId,
    mailbox: row.mailbox,
    uid: row.uid,
    send: send,
    never: never,
  );
}
