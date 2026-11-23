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

  /// The file's [text]. The file being there is what turns the lock on,
  /// so an empty or damaged one still means on, with the defaults.
  static LockSettings parse(String text) {
    try {
      final m = jsonDecode(text) as Map<String, dynamic>;
      return LockSettings(
        after: LockAfter.fromSeconds((m['after'] as num?)?.toInt()),
        device: m['device'] as bool? ?? true,
        notice: m['notice'] as String? ?? 'New message',
      );
    } on Object {
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
///
/// The wait is kept as what was left of it ([wait]), never as a time of
/// day: moving the device's clock doesn't shorten it. Where the system
/// has a clock that counts from boot and can't be set ([BootTime]), the
/// end of the wait on that clock is kept too ([boot], [bootUntil]), so
/// the time the app was closed still counts within the same boot.
@immutable
class LockSecret {
  const LockSecret({
    required this.pin,
    this.failures = 0,
    this.wait = Duration.zero,
    this.boot,
    this.bootUntil,
  });

  /// The Argon2id hash the engine made (`core/src/app_lock.rs`).
  final String pin;
  final int failures;

  /// The wait left when this was kept.
  final Duration wait;

  /// The boot [bootUntil] belongs to ([BootTime.id]).
  final String? boot;

  /// When the wait ends, on that boot's clock ([BootTime.since]).
  final Duration? bootUntil;

  String encode() => jsonEncode({
    'pin': pin,
    'failures': failures,
    if (wait > Duration.zero) 'wait_ms': wait.inMilliseconds,
    'boot': ?boot,
    if (bootUntil case final u?) 'boot_until_ms': u.inMilliseconds,
  });

  static LockSecret? parse(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final m = jsonDecode(text) as Map<String, dynamic>;
      final wait = (m['wait_ms'] as num?)?.toInt() ?? 0;
      final until = (m['boot_until_ms'] as num?)?.toInt();
      return LockSecret(
        pin: m['pin'] as String,
        failures: (m['failures'] as num?)?.toInt() ?? 0,
        wait: Duration(milliseconds: wait < 0 ? 0 : wait),
        boot: m['boot'] as String?,
        bootUntil: until == null ? null : Duration(milliseconds: until),
      );
    } on Object {
      return null;
    }
  }

  /// The wait left at [now] on the boot clock: by that clock within the
  /// same boot, never more than [wait]; all of [wait] after a restart of
  /// the device, or where there is no such clock.
  Duration waitAt(BootTime? now) {
    final until = bootUntil;
    if (now == null || until == null || boot == null || now.id != boot) {
      return wait;
    }
    final left = until - now.since;
    if (left.isNegative) return Duration.zero;
    return left > wait ? wait : left;
  }
}

/// A clock that counts from the device's boot, through sleep, and that
/// nobody can set: Android's `elapsedRealtime`, Linux's `CLOCK_BOOTTIME`.
@immutable
class BootTime {
  const BootTime(this.id, this.since);

  /// Different after every boot.
  final String id;
  final Duration since;
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

/// Not tried: the try couldn't be counted in the keychain, and a try that
/// isn't counted could be repeated without waiting.
class PinNotKept extends PinResult {
  const PinNotKept();
}

/// A clock that never jumps: how long this process has run. It stops
/// while the device sleeps, which only makes a wait longer.
final Stopwatch _running = Stopwatch()..start();
Duration _monotonic() => _running.elapsed;

/// The app lock: on or off, locked or open, and the clocks that decide.
/// Off by default. When on, a cold start is locked, and so is the app
/// once it has been away for [LockSettings.after], whether or not it
/// comes back: every window locks at once.
class AppLock extends ChangeNotifier {
  AppLock({
    required this.store,
    required this.hasher,
    required this.device,
    this.now = DateTime.now,
    Duration Function()? elapsed,
    this.bootClock,
    Timer Function(Duration, void Function())? timer,
  }) : elapsed = elapsed ?? _monotonic,
       _timer = timer ?? Timer.new;

  final LockStore store;
  final PinHasher hasher;
  final DeviceUnlock device;

  /// The time of day: only for how long the app was away, together with
  /// [elapsed], so moving it forward can lock sooner, never later.
  final DateTime Function() now;

  /// A clock that never jumps ([Stopwatch]); the wrong-PIN wait runs on it.
  final Duration Function() elapsed;

  /// The device's boot clock, where there is one (`lock_platform.dart`).
  final Future<BootTime?> Function()? bootClock;

  final Timer Function(Duration, void Function()) _timer;

  /// While one is locked, every [AppLock] says so: the keyboard handlers
  /// that act outside the widget tree (print, mark read) stay quiet, and
  /// so do notices' buttons.
  static bool get lockedNow => _lockedCount > 0;
  static int _lockedCount = 0;

  LockSettings? _settings;
  LockSecret? _secret;
  bool _locked = false;
  bool _deviceReady = false;
  bool _unreadable = false;
  bool _missing = false;
  bool _notKept = false;

  /// When the wrong-PIN wait ends, on [elapsed].
  Duration? _waitEnds;

  /// Away: the main window hidden and no other window of the app in front.
  bool _mainAway = false;
  final _inFront = <Object>{};
  DateTime? _leftAt;
  Duration? _leftElapsed;
  Timer? _away;

  /// Set while the system's own unlock sheet is up: Android pauses the
  /// app for the screen lock, which must not lock it again.
  bool _prompting = false;
  Duration? _promptEnded;

  /// The system's unlock sheet closed a moment ago: the app coming back
  /// in front is its doing, not the person's.
  bool get justPrompted {
    final at = _promptEnded;
    return _prompting ||
        (at != null && elapsed() - at < const Duration(seconds: 2));
  }

  /// Told when the lock closes, e.g. to hide the reader windows and blank
  /// the notices already shown.
  VoidCallback? onLocked;

  /// Told when the lock opens, e.g. to bring the reader windows back.
  VoidCallback? onUnlocked;

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

  /// The lock is on but there is no PIN to check: the keychain didn't
  /// answer, or has none ([pinMissing]). Only the device's unlock opens it.
  bool get pinUnreadable => _unreadable;

  /// The keychain answered without a PIN while the settings file says
  /// the lock is on (a damaged file, a keychain emptied by hand).
  bool get pinMissing => _missing;

  /// The last try couldn't be counted in the keychain: no PIN is tried
  /// until one can be.
  bool get triesNotKept => _notKept;

  /// How long until a PIN may be tried again; zero when it may now.
  Duration get waitLeft {
    final ends = _waitEnds;
    if (ends == null) return Duration.zero;
    final left = ends - elapsed();
    return left.isNegative ? Duration.zero : left;
  }

  int get failures => _secret?.failures ?? 0;

  /// At start, before anything is drawn: a lock that is on starts locked.
  /// Never throws. A settings file that can't be read counts as on.
  Future<void> load() async {
    try {
      _settings = await store.loadSettings();
    } on Object {
      _settings = const LockSettings();
    }
    _deviceReady = await device.available().catchError((Object _) => false);
    if (_settings == null) return;
    try {
      _secret = LockSecret.parse(await store.loadSecret());
      _missing = _secret == null;
    } on Object {
      _secret = null;
    }
    _unreadable = _secret == null;
    if (_secret case final s?) {
      _startWait(s.waitAt(await _boot()));
    }
    _setLocked(true);
  }

  Future<BootTime?> _boot() async {
    try {
      return await bootClock?.call();
    } on Object {
      return null;
    }
  }

  void _startWait(Duration wait) {
    _waitEnds = wait > Duration.zero ? elapsed() + wait : null;
  }

  void _setLocked(bool value) {
    if (value == _locked) return;
    _locked = value;
    _lockedCount += value ? 1 : -1;
    if (value) {
      _cancelAway();
      onLocked?.call();
    } else {
      onUnlocked?.call();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelAway();
    if (_locked) _lockedCount--;
    _locked = false;
    super.dispose();
  }

  /// The main window went to the background (hidden, paused, minimized
  /// or closed to the tray).
  void left() {
    _mainAway = true;
    _followAway();
  }

  /// The main window is back in front.
  void back() {
    _mainAway = false;
    _followAway();
    if (_locked && _waitEnds != null) refreshWait().ignore();
  }

  /// Catches the wait up with the boot clock, which counts the time the
  /// device slept ([elapsed] doesn't). Never lengthens it.
  Future<void> refreshWait() async {
    final s = _secret;
    if (s == null || _waitEnds == null) return;
    final boot = await _boot();
    if (boot == null || s.boot == null) return;
    final left = s.waitAt(boot);
    if (left < waitLeft) {
      _startWait(left);
      notifyListeners();
    }
  }

  /// Another window of the app ([id]: a desktop reader window) came in
  /// front, or went out of it. While one is in front the app is in use,
  /// even with the main window hidden.
  void windowInFront(Object id, bool front) {
    if (front) {
      _inFront.add(id);
    } else {
      _inFront.remove(id);
    }
    _followAway();
  }

  bool get _isAway => _mainAway && _inFront.isEmpty;

  void _followAway() {
    if (_isAway) {
      _goAway();
    } else {
      _comeBack();
    }
  }

  void _goAway() {
    if (!enabled || _locked || _prompting || _leftAt != null) return;
    final after = _settings!.after.duration;
    if (after == Duration.zero) {
      _setLocked(true);
      return;
    }
    _leftAt = now();
    _leftElapsed = elapsed();
    // Locks when the time is up, away or not: the windows still on screen
    // hide then, not when the main one comes back.
    _away = _timer(after, () {
      _away = null;
      if (_isAway && _awayLongEnough()) _setLocked(true);
    });
  }

  void _comeBack() {
    final long = _awayLongEnough();
    _cancelAway();
    if (!enabled || _locked || _prompting || !long) return;
    _setLocked(true);
  }

  /// Away for [LockSettings.after] by either clock: the time of day counts
  /// a device's sleep, the other can't be moved back.
  bool _awayLongEnough() {
    final at = _leftAt;
    final from = _leftElapsed;
    final s = _settings;
    if (at == null || from == null || s == null) return false;
    final after = s.after.duration;
    return now().difference(at) >= after || elapsed() - from >= after;
  }

  void _cancelAway() {
    _away?.cancel();
    _away = null;
    _leftAt = null;
    _leftElapsed = null;
  }

  /// Locks now (from the keyboard or the menu).
  void lockNow() {
    if (enabled) _setLocked(true);
  }

  /// Checks [pin]. The try is counted in the keychain, with the wait that
  /// follows if it is wrong, before the PIN is checked: closing the app
  /// while it checks doesn't make a free try. When it can't be counted,
  /// nothing is tried ([PinNotKept]).
  Future<PinResult> tryPin(String pin) async {
    final secret = _secret;
    final wait = waitLeft;
    if (wait > Duration.zero) return PinWaiting(wait);
    if (secret == null) return const PinWrong(Duration.zero);
    final failures = secret.failures + 1;
    final next = lockWait(failures);
    final boot = next > Duration.zero ? await _boot() : null;
    final counted = LockSecret(
      pin: secret.pin,
      failures: failures,
      wait: next,
      boot: boot?.id,
      bootUntil: boot == null ? null : boot.since + next,
    );
    if (!await _keep(counted)) return const PinNotKept();
    final right = await hasher
        .verify(pin, secret.pin)
        .catchError((Object _) => false);
    if (right) {
      // Should this fail, the next start counts one more wrong try.
      await _keep(LockSecret(pin: secret.pin));
      _notKept = false;
      _waitEnds = null;
      _setLocked(false);
      return const PinRight();
    }
    _startWait(next);
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
      _promptEnded = elapsed();
      _cancelAway();
    }
    if (!ok) return false;
    if (_secret case final s? when s.failures > 0) {
      await _keep(LockSecret(pin: s.pin));
    }
    _notKept = false;
    _waitEnds = null;
    if (_locked) _setLocked(false);
    return true;
  }

  /// Keeps [secret] in the keychain; false, and [triesNotKept], when it
  /// can't.
  Future<bool> _keep(LockSecret secret) async {
    try {
      await store.saveSecret(secret.encode());
    } on Object {
      if (!_notKept) {
        _notKept = true;
        notifyListeners();
      }
      return false;
    }
    _secret = secret;
    if (_notKept) {
      _notKept = false;
      notifyListeners();
    }
    return true;
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
    _missing = false;
    _notKept = false;
    _waitEnds = null;
    _cancelAway();
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
    _missing = false;
    _notKept = false;
    _waitEnds = null;
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
    _missing = false;
    _notKept = false;
    _waitEnds = null;
    _cancelAway();
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
