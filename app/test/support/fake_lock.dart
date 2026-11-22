import 'dart:async';

import 'package:piuma_mail/lock/app_lock.dart';

/// The lock's two halves in memory.
class MemoryLockStore implements LockStore {
  LockSettings? settings;
  String? secret;

  /// The keychain can't answer (locked, no Secret Service).
  bool keychainDown = false;

  /// The keychain answers but can't keep anything.
  bool keychainFull = false;

  /// The settings file is there but can't be read.
  bool fileUnreadable = false;

  @override
  Future<LockSettings?> loadSettings() async {
    if (fileUnreadable) throw StateError('file');
    return settings;
  }

  @override
  Future<void> saveSettings(LockSettings? s) async => settings = s;

  @override
  Future<String?> loadSecret() async {
    if (keychainDown) throw StateError('keychain');
    return secret;
  }

  @override
  Future<void> saveSecret(String? s) async {
    if (keychainDown || keychainFull) throw StateError('keychain');
    secret = s;
  }
}

/// Not Argon2: the engine's is tested in `core/src/app_lock.rs`.
class FakeHasher implements PinHasher {
  @override
  Future<String> hash(String pin) async => 'hash:$pin';

  @override
  Future<bool> verify(String pin, String hash) async => hash == 'hash:$pin';
}

class FakeDevice implements DeviceUnlock {
  FakeDevice({this.has = true, this.passes = false});

  bool has;
  bool passes;
  int asked = 0;

  @override
  Future<bool> available() async => has;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return passes;
  }
}

/// A clock tests move by hand: the time of day ([call]) and the one that
/// never jumps ([elapsed]) move together with [advance]; [jump] moves
/// only the time of day, as someone setting the device's clock would.
class FakeClock {
  FakeClock(this.at);
  DateTime at;
  Duration _elapsed = Duration.zero;
  DateTime call() => at;
  Duration elapsed() => _elapsed;
  void advance(Duration d) {
    at = at.add(d);
    _elapsed += d;
  }

  void jump(Duration d) => at = at.add(d);
}

/// A boot clock tests move by hand.
class FakeBoot {
  FakeBoot([this.id = 'boot-1']);
  String id;
  Duration since = const Duration(hours: 3);
  Future<BootTime?> call() async => BootTime(id, since);
}

/// Timers tests fire by hand.
class FakeTimers {
  final pending = <(Duration, void Function())>[];
  Timer call(Duration d, void Function() f) {
    final t = _FakeTimer(this, (d, f));
    pending.add(t.entry);
    return t;
  }

  /// Fires every timer of [at] most [d].
  void fireUpTo(Duration d) {
    for (final e in [...pending]) {
      if (e.$1 <= d) {
        pending.remove(e);
        e.$2();
      }
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.owner, this.entry);
  final FakeTimers owner;
  final (Duration, void Function()) entry;

  @override
  void cancel() => owner.pending.remove(entry);

  @override
  bool get isActive => owner.pending.contains(entry);

  @override
  int get tick => 0;
}
