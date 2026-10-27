import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Android's side of new mail with the app closed (`AndroidBackground`,
/// `Background.kt`): the person's choice, and the notices the background
/// service shows itself. Elsewhere it does nothing.
class AndroidBackground {
  static const _background = MethodChannel('mail.piuma/background');
  static const _notices = MethodChannel('mail.piuma/notices');

  // The real system, not the one tests pretend to be.
  static bool get on => Platform.isAndroid;

  /// "instant", "periodic", or null until picked.
  static Future<String?> mode() async =>
      on ? _background.invokeMethod<String>('mode') : null;

  static Future<void> setMode(String mode) async {
    if (on) await _background.invokeMethod<void>('setMode', {'mode': mode});
  }

  /// Starts what the choice needs, at app start.
  static Future<void> apply() async {
    if (on) await _background.invokeMethod<void>('apply');
  }

  /// Delivers recovery cancellations even in periodic mode, with no service.
  static Future<void> refreshSignInNotices() async {
    if (!on) return;
    try {
      await _background.invokeMethod<void>('refreshSignInNotices');
    } on PlatformException {
      // The background service/job can deliver the queued update later.
    }
  }

  /// Asks Android to leave the service out of battery saving.
  static Future<void> askBattery() async {
    if (on) await _background.invokeMethod<void>('askBattery');
  }

  /// Hands [onOpen] the payload of each notice the service showed and the
  /// person tapped, the one the app was opened from first.
  static Future<void> listen(void Function(String payload) onOpen) async {
    if (!on) return;
    _notices.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        onOpen(call.arguments as String);
      }
    });
    final launch = await _notices.invokeMethod<String>('launch');
    if (launch != null) onOpen(launch);
  }
}
