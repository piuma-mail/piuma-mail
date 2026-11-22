import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../engine/api/lock.dart' as engine;
import 'app_lock.dart';

/// The lock's settings in `app-lock.json` next to the database (Android's
/// background service reads the same file: `AppLockFile.kt`), and its
/// secret in the keychain: through the engine, or on Android in the
/// Keystore, as the passwords are.
class FileLockStore implements LockStore {
  FileLockStore(String folder) : _file = File('$folder/app-lock.json');

  final File _file;
  static const _passwords = MethodChannel('mail.piuma/passwords');
  static const _key = 'app-lock';

  bool get _android => Platform.isAndroid;

  @override
  Future<LockSettings?> loadSettings() async {
    if (!await _file.exists()) return null;
    return LockSettings.parse(await _file.readAsString());
  }

  @override
  Future<void> saveSettings(LockSettings? settings) async {
    if (settings == null) {
      if (await _file.exists()) await _file.delete();
      return;
    }
    // Written aside and moved in, so a crash never leaves half a file.
    final next = File('${_file.path}.new');
    await next.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await next.rename(_file.path);
  }

  @override
  Future<String?> loadSecret() async {
    if (_android) {
      return _passwords.invokeMethod<String>('read', {'key': _key});
    }
    return engine.lockSecretLoad();
  }

  @override
  Future<void> saveSecret(String? secret) async {
    if (_android) {
      if (secret == null) {
        await _passwords.invokeMethod<void>('delete', {'key': _key});
      } else {
        await _passwords.invokeMethod<void>('write', {
          'key': _key,
          'value': secret,
        });
      }
      return;
    }
    if (secret == null) {
      engine.lockSecretForget();
    } else {
      engine.lockSecretSave(value: secret);
    }
  }
}

/// Argon2id in the engine (`core/src/app_lock.rs`).
class EnginePinHasher implements PinHasher {
  const EnginePinHasher();

  @override
  Future<String> hash(String pin) => engine.lockHashPin(pin: pin);

  @override
  Future<bool> verify(String pin, String hash) =>
      engine.lockVerifyPin(pin: pin, kept: hash);
}

/// The `local_auth` plugin: Android's BiometricPrompt with the screen lock
/// as fallback, Windows Hello, Touch ID or Face ID with the passcode, and
/// the Mac's password. Linux has none: the PIN only.
class SystemDeviceUnlock implements DeviceUnlock {
  SystemDeviceUnlock();

  final _auth = LocalAuthentication();

  bool get _supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  @override
  Future<bool> available() async {
    if (!_supported) return false;
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    if (!_supported) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // The screen lock (PIN, pattern, password) is a way in too.
        biometricOnly: false,
        // Leaving the app cancels it; the lock screen asks again on return.
        persistAcrossBackgrounding: false,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// What the platform does while the lock is on: Android keeps Piuma out
/// of the recent apps' thumbnails and screenshots (FLAG_SECURE) and tells
/// the watch (`MainActivity.kt`); iOS covers its app switcher snapshot
/// itself (`AppDelegate.swift`), reading the same file.
abstract final class LockPlatform {
  static const _channel = MethodChannel('mail.piuma/lock');

  static Future<void> changed({required bool on}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('changed', {'on': on});
    } on Object {
      // An older activity: the flag follows at the next start.
    }
  }
}
