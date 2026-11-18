import 'dart:typed_data';

import 'package:flutter/painting.dart' show MemoryImage;

import 'mail_source.dart' show MailRow;

/// Asks for a sender's picture: by address, and for the message [row]
/// when there is one, [opened] when the person is reading it.
typedef SenderPictureLoad = Future<Uint8List?> Function(
  String email,
  MailRow? row,
  bool opened,
);

/// Sender pictures (`PicturesToApprove`): a company's brand logo or
/// website icon, looked up by the engine and kept on the device. A logo
/// belongs to one verified message, not to an address, so what is asked
/// for a message is kept apart from what is asked for an address alone.
/// Each is asked once per run; what came back is kept here, so a row
/// scrolled back into view draws at once.
class SenderPictures {
  SenderPictures(this._load);

  final SenderPictureLoad _load;
  final _done = <String, MemoryImage?>{};
  final _asked = <String, Future<MemoryImage?>>{};

  String _key(String email, MailRow? row, bool opened) {
    final address = email.trim().toLowerCase();
    if (row == null) return address;
    return '$address|${row.accountId}|${row.mailbox}|${row.uid}|$opened';
  }

  /// What is already known: the picture, or null (none, or not yet).
  MemoryImage? now(String email, {MailRow? row, bool opened = false}) =>
      _done[_key(email, row, opened)];

  Future<MemoryImage?> get(String email, {MailRow? row, bool opened = false}) {
    final key = _key(email, row, opened);
    return _asked[key] ??= () async {
      Uint8List? png;
      try {
        png = await _load(email, row, opened);
      } catch (_) {
        // No picture is no loss: the letter stays.
      }
      final image = png == null || png.isEmpty ? null : MemoryImage(png);
      _done[key] = image;
      return image;
    }();
  }

  /// After the switches change: everything is asked again.
  void clear() {
    _done.clear();
    _asked.clear();
  }
}
