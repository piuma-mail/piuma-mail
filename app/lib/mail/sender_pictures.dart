import 'dart:typed_data';

import 'package:flutter/painting.dart' show MemoryImage;

/// Sender pictures (`PicturesToApprove`): a company's verified logo or
/// website icon, looked up by the engine and kept on the device. Each
/// address is asked once per run; what came back is kept here, so a
/// row scrolled back into view draws at once.
class SenderPictures {
  SenderPictures(this._load);

  final Future<Uint8List?> Function(String email) _load;
  final _done = <String, MemoryImage?>{};
  final _asked = <String, Future<MemoryImage?>>{};

  String _key(String email) => email.trim().toLowerCase();

  /// What is already known: the picture, or null (none, or not yet).
  MemoryImage? now(String email) => _done[_key(email)];

  Future<MemoryImage?> get(String email) {
    final key = _key(email);
    return _asked[key] ??= () async {
      Uint8List? png;
      try {
        png = await _load(email);
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
