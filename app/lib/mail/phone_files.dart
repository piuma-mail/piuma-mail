import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Saved attachments on the phone, where a file path is not enough: on
/// Android the file goes into the shared Downloads (through the system's
/// media store, so no storage permission is asked) and opens through the
/// app the person picks; on iPhone and iPad it opens in the system's
/// preview, with Share for "Open in…".
abstract final class PhoneFiles {
  static const _channel = MethodChannel('mail.piuma/files');

  static bool get android => !kIsWeb && Platform.isAndroid;
  static bool get ios => !kIsWeb && Platform.isIOS;

  /// Moves a file the engine wrote into Downloads, under a name no other
  /// file there has, and gives back where it now is (a content:// address).
  /// Null where the system has no such store (Android before 10): the
  /// file then stays where it is.
  static Future<String?> toDownloads(String path) async {
    if (!android) return null;
    return _channel.invokeMethod<String>('toDownloads', {'path': path});
  }

  /// Opens a saved file with the system: the app chooser on Android, the
  /// preview on iPhone and iPad. False on any other system.
  static Future<bool> open(String path) async {
    if (!android && !ios) return false;
    await _channel.invokeMethod<void>('open', {'path': path});
    return true;
  }
}
