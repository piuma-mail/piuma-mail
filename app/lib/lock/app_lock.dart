import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// How long Piuma may stay in the background before it locks.
enum LockAfter {
  immediately(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5)),
  fifteenMinutes(Duration(minutes: 15));

  const LockAfter(this.duration);
  final Duration duration;

  static LockAfter fromSeconds(int? seconds) => values.firstWhere(
    (v) => v.duration.inSeconds == seconds,
    orElse: () => LockAfter.oneMinute,
  );
}

/// What the lock is set to. Not secret: it lives in a small file next to
/// the database (`app-lock.json`), so Android's background service can
/// read it to keep notices blank, and a cold start knows to lock before
/// anything is drawn. The PIN's hash is in [LockSecret], in the keychain.
@immutable
class LockSettings {
  const LockSettings({
    this.after = LockAfter.oneMinute,
    this.device = true,
    this.notice = 'New message',
  });

  final LockAfter after;

  /// Unlock with the device too: fingerprint, face, Windows Hello or the
  /// device's own screen lock, where there is one.
  final bool device;

  /// What a notice says while the lock is on, in the app's language
  /// (written here for Android's background service).
  final String notice;

  LockSettings copyWith({LockAfter? after, bool? device, String? notice}) =>
      LockSettings(
        after: after ?? this.after,
        device: device ?? this.device,
        notice: notice ?? this.notice,
      );

  Map<String, Object> toJson() => {
    'v': 1,
    'after': after.duration.inSeconds,
    'device': device,
    'notice': notice,
  };

  static LockSettings? parse(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final m = jsonDecode(text) as Map<String, dynamic>;
      return LockSettings(
        after: LockAfter.fromSeconds((m['after'] as num?)?.toInt()),
        device: m['device'] as bool? ?? true,
        notice: m['notice'] as String? ?? 'New message',
      );
    } on Object {
      // A damaged file still means the lock is on.
      return const LockSettings();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LockSettings &&
      other.after == after &&
      other.device == device &&
      other.notice == notice;

  @override
  int get hashCode => Object.hash(after, device, notice);
}

/// What the keychain keeps: the PIN's slow hash (never the PIN) and the
/// wrong tries so far, so closing the app doesn't reset the wait.
@immutable
class LockSecret {
  const LockSecret({required this.pin, this.failures = 0, this.waitUntil});

  /// The Argon2id hash the engine made (`core/src/app_lock.rs`).
  final String pin;
  final int failures;
  final DateTime? waitUntil;

  String encode() => jsonEncode({
    'pin': pin,
    'failures': failures,
    if (waitUntil case final w?) 'wait_until': w.millisecondsSinceEpoch,
  });

  static LockSecret? parse(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final m = jsonDecode(text) as Map<String, dynamic>;
      final until = (m['wait_until'] as num?)?.toInt();
      return LockSecret(
        pin: m['pin'] as String,
        failures: (m['failures'] as num?)?.toInt() ?? 0,
        waitUntil: until == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(until),
      );
    } on Object {
      return null;
    }
  }
}

/// How long the next try waits after [failures] wrong PINs in a row: the
/// first five are free, then 30 seconds, a minute, 5, 15, and an hour
/// from the tenth on.
Duration lockWait(int failures) => switch (failures) {
  < 5 => Duration.zero,
  5 => const Duration(seconds: 30),
  6 => const Duration(minutes: 1),
  7 => const Duration(minutes: 5),
  8 => const Duration(minutes: 15),
  _ => const Duration(hours: 1),
};

/// Where the lock's two halves are kept (`lock_platform.dart`); tests
/// keep them in memory.
abstract class LockStore {
  Future<LockSettings?> loadSettings();

  /// Null turns the lock off: the file goes.
  Future<void> saveSettings(LockSettings? settings);

  /// Throws when the keychain can't answer now.
  Future<String?> loadSecret();

  /// Throws when the keychain can't keep it (Linux without a keyring).
  Future<void> saveSecret(String? secret);
}

/// The engine's Argon2id (`lock_hash_pin`, `lock_verify_pin`).
abstract class PinHasher {
  Future<String> hash(String pin);
  Future<bool> verify(String pin, String hash);
}

/// The device's own unlock: BiometricPrompt with the screen lock as
/// fallback on Android, Windows Hello, Touch ID and the Mac's password.
abstract class DeviceUnlock {
  /// Whether this device has one set up; false on Linux.
  Future<bool> available();

  /// Asks for it, with [reason] on the system's sheet; true when it
  /// passed.
  Future<bool> authenticate(String reason);
}

/// Whether a PIN opened the lock.
sealed class PinResult {
  const PinResult();
}

class PinRight extends PinResult {
  const PinRight();
}

/// Wrong: [wait] before the next try (zero for the first few).
class PinWrong extends PinResult {
  const PinWrong(this.wait);
  final Duration wait;
}

/// Not tried: still [wait] to go after the last wrong ones.
class PinWaiting extends PinResult {
  const PinWaiting(this.wait);
  final Duration wait;
}

/// The app lock: on or off, locked or open, and the clock that decides.
/// Off by default. When on, a cold start is locked, and so is a return
/// from the background after [LockSettings.after].
class AppLock extends ChangeNotifier {
  AppLock({
    required this.store,
    required this.hasher,
    required this.device,
    this.now = DateTime.now,
  });

  final LockStore store;
  final PinHasher hasher;
  final DeviceUnlock device;
  final DateTime Function() now;

  /// While one is locked, every [AppLock] says so: the keyboard handlers
  /// that act outside the widget tree (print, mark read) stay quiet.
  static bool get lockedNow => _lockedCount > 0;
  static int _lockedCount = 0;

  LockSettings? _settings;
  LockSecret? _secret;
  bool _locked = false;
  bool _deviceReady = false;
  bool _unreadable = false;
  DateTime? _leftAt;

  /// Set while the system's own unlock sheet is up: Android pauses the
  /// app for the screen lock, which must not lock it again.
  bool _prompting = false;
  DateTime? _promptEnded;

  /// The system's unlock sheet closed a moment ago: the app coming back
  /// in front is its doing, not the person's.
  bool get justPrompted {
    final at = _promptEnded;
    return _prompting ||
        (at != null && now().difference(at) < const Duration(seconds: 2));
  }

  /// Told when the lock closes, e.g. to hide the reader windows.
  VoidCallback? onLocked;

  /// Told when the lock is turned on or off or changed, for what the
  /// platform does about it (Android's FLAG_SECURE, the watch).
  VoidCallback? onSettings;

  bool get enabled => _settings != null;
  LockSettings? get settings => _settings;
  bool get locked => _locked;

  /// The device's unlock is set up and the person wants it.
  bool get deviceUnlock => _deviceReady && (_settings?.device ?? false);

  /// Whether the device has an unlock at all, for Settings.
  bool get deviceAvailable => _deviceReady;

  /// The lock is on but the keychain didn't give its PIN back: only the
  /// device's unlock opens it.
  bool get pinUnreadable => _unreadable;

  /// How long until a PIN may be tried again; zero when it may now.
  Duration get waitLeft {
    final until = _secret?.waitUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(now());
    return left.isNegative ? Duration.zero : left;
  }

  int get failures => _secret?.failures ?? 0;

  /// At start, before anything is drawn: a lock that is on starts locked.
  Future<void> load() async {
    _settings = await store.loadSettings();
    _deviceReady = await device.available().catchError((Object _) => false);
    if (_settings == null) return;
    try {
      _secret = LockSecret.parse(await store.loadSecret());
    } on Object {
      _secret = null;
    }
    _unreadable = _secret == null;
    _setLocked(true);
  }

  void _setLocked(bool value) {
    if (value == _locked) return;
    _locked = value;
    _lockedCount += value ? 1 : -1;
    if (value) onLocked?.call();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_locked) _lockedCount--;
    super.dispose();
  }

  /// The app went to the background (hidden, paused, the window
  /// minimized or closed to the tray).
  void left() {
    if (!enabled || _locked || _prompting) return;
    if (_settings!.after == LockAfter.immediately) {
      _setLocked(true);
      return;
    }
    _leftAt ??= now();
  }

  /// The app is back in front: locked when it was away long enough.
  void back() {
    final at = _leftAt;
    _leftAt = null;
    if (!enabled || _locked || _prompting || at == null) return;
    if (now().difference(at) >= _settings!.after.duration) _setLocked(true);
  }

  /// Locks now (from the keyboard or the menu).
  void lockNow() {
    if (enabled) _setLocked(true);
  }

  Future<PinResult> tryPin(String pin) async {
    final secret = _secret;
    final wait = waitLeft;
    if (wait > Duration.zero) return PinWaiting(wait);
    if (secret == null) return const PinWrong(Duration.zero);
    final right = await hasher
        .verify(pin, secret.pin)
        .catchError((Object _) => false);
    if (right) {
      await _keep(LockSecret(pin: secret.pin));
      _setLocked(false);
      return const PinRight();
    }
    final failures = secret.failures + 1;
    final next = lockWait(failures);
    await _keep(
      LockSecret(
        pin: secret.pin,
        failures: failures,
        waitUntil: next == Duration.zero ? null : now().add(next),
      ),
    );
    notifyListeners();
    return PinWrong(next);
  }

  /// The device's unlock; it also clears the wrong PIN tries.
  Future<bool> tryDevice(String reason) async {
    if (!_deviceReady || _prompting) return false;
    _prompting = true;
    bool ok;
    try {
      ok = await device.authenticate(reason);
    } on Object {
      ok = false;
    } finally {
      _prompting = false;
      _promptEnded = now();
      _leftAt = null;
    }
    if (!ok) return false;
    if (_secret case final s? when s.failures > 0) {
      await _keep(LockSecret(pin: s.pin));
    }
    if (_locked) _setLocked(false);
    return true;
  }

  Future<void> _keep(LockSecret secret) async {
    _secret = secret;
    try {
      await store.saveSecret(secret.encode());
    } on Object {
      // Kept for this run; the wait still holds until the app closes.
    }
  }

  /// Turns the lock on with [pin]. Throws when the keychain can't keep it.
  Future<void> enable(String pin, {required LockSettings settings}) async {
    final hash = await hasher.hash(pin);
    final secret = LockSecret(pin: hash);
    await store.saveSecret(secret.encode());
    await store.saveSettings(settings);
    _secret = secret;
    _settings = settings;
    _unreadable = false;
    _leftAt = null;
    onSettings?.call();
    notifyListeners();
  }

  /// A new PIN, once the lock is on.
  Future<void> changePin(String pin) async {
    final hash = await hasher.hash(pin);
    final secret = LockSecret(pin: hash);
    await store.saveSecret(secret.encode());
    _secret = secret;
    _unreadable = false;
    notifyListeners();
  }

  Future<void> update(LockSettings settings) async {
    if (!enabled || settings == _settings) return;
    _settings = settings;
    await store.saveSettings(settings);
    onSettings?.call();
    notifyListeners();
  }

  Future<void> disable() async {
    if (!enabled) return;
    await store.saveSettings(null);
    try {
      await store.saveSecret(null);
    } on Object {
      // The file is what turns it on; a leftover hash opens nothing.
    }
    _settings = null;
    _secret = null;
    _unreadable = false;
    _leftAt = null;
    _setLocked(false);
    onSettings?.call();
    notifyListeners();
  }

  /// Keeps the notice text in the app's language, for Android's
  /// background service.
  Future<void> noticeText(String text) async {
    final s = _settings;
    if (s == null || s.notice == text) return;
    await update(s.copyWith(notice: text));
  }
}
