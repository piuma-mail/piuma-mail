import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How many emails are unread, where the system shows it: the Dock's badge
/// on macOS, an overlay on the taskbar button on Windows, the window's
/// title on Linux ("Piuma Mail (3)"). On Android the notifications carry
/// it (`AndroidNotificationDetails.number`), for launchers that show a
/// count. A platform without the channel (tests, the web) ignores it.
class UnreadBadge {
  UnreadBadge._();

  static const channel = MethodChannel('piuma/badge');

  /// The last count shown, for the notifications.
  static int count = 0;

  static int? _shown;

  /// Shows [count]: [title] for the window, [label] for screen readers,
  /// [color] for the badge (the theme's accent).
  static Future<void> show(
    int count, {
    required String title,
    required String label,
    required Color color,
  }) async {
    UnreadBadge.count = count;
    if (_shown == count) return;
    _shown = count;
    try {
      await channel.invokeMethod<void>('set', {
        'count': count,
        'title': title,
        'label': label,
        'color': color.toARGB32(),
      });
    } on MissingPluginException {
      // No badge here.
    } on PlatformException catch (e) {
      debugPrint('unread badge: ${e.message}');
    }
  }

  /// Forgets what was shown, for tests.
  @visibleForTesting
  static void reset() {
    _shown = null;
    count = 0;
  }
}
