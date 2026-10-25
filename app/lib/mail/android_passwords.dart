import 'dart:io';

import 'package:flutter/services.dart';

import '../engine/api/calendars.dart' as cal;
import '../engine/api/engine.dart' as engine;
import '../engine/api/sync.dart' as sync;

/// Android has no keychain the engine can reach: passwords are kept
/// encrypted with a key in the Android Keystore (`MainActivity.kt`) and
/// handed to the engine at start. Elsewhere the engine uses the system
/// keychain and this does nothing.
class AndroidPasswords {
  static const _channel = MethodChannel('mail.piuma/passwords');

  // The real system, not the one tests pretend to be.
  static bool get _on => Platform.isAndroid;

  static String _key(int accountId) => 'account-$accountId';

  /// This device's secret for the sync space.
  static const spaceKey = 'space-device';

  /// Hands every account's password to the engine, before syncing.
  static Future<void> load() async {
    if (!_on) return;
    for (final a in engine.accounts()) {
      final password = await _channel.invokeMethod<String>('read', {
        'key': _key(a.id),
      });
      if (password != null) {
        engine.rememberPassword(accountId: a.id, password: password);
      }
    }
    final secret = await _channel.invokeMethod<String>('read', {
      'key': spaceKey,
    });
    if (secret != null) sync.rememberSyncSecret(secret: secret);
    // Calendars of their own: those of an email account use its password.
    for (final s in cal.calendarSources().where((s) => s.accountId == null)) {
      final password = await _channel.invokeMethod<String>('read', {
        'key': 'calendar-${s.id}',
      });
      if (password != null) {
        cal.rememberCalendarPassword(sourceId: s.id, password: password);
      }
    }
  }

  /// Keeps a password the engine just accepted.
  static Future<void> save(int accountId, String password) =>
      saveKey(_key(accountId), password);

  /// Forgets the password of an account just removed.
  static Future<void> forget(int accountId) async {
    if (!_on) return;
    await _channel.invokeMethod<void>('delete', {'key': _key(accountId)});
  }

  /// The name the person gave this device ("Pixel 8", "MacBook Pro di
  /// Matteo"), for Devices & sync; elsewhere the computer's name.
  static Future<String> deviceName() async {
    if (_on) {
      final name = await const MethodChannel('mail.piuma/background')
          .invokeMethod<String>('deviceName');
      if (name != null && name.isNotEmpty) return name;
    }
    if (Platform.isMacOS || Platform.isIOS) {
      try {
        final name = await const MethodChannel('mail.piuma/device')
            .invokeMethod<String>('name');
        if (name != null && name.isNotEmpty) return name;
      } on MissingPluginException {
        // A window of its own, or tests: the host name below.
      } on PlatformException {
        // The system wouldn't say: the host name below.
      }
    }
    final host = Platform.localHostname.replaceFirst(
      RegExp(r'\.(local|lan|home)$'),
      '',
    );
    return host.replaceAll('-', ' ');
  }

  /// Keeps a password under its own name, like `calendar-2`.
  static Future<void> saveKey(String key, String password) async {
    if (!_on) return;
    await _channel.invokeMethod<void>('write', {'key': key, 'value': password});
  }
}
