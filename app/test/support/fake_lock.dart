import 'package:piuma_mail/lock/app_lock.dart';

/// The lock's two halves in memory.
class MemoryLockStore implements LockStore {
  LockSettings? settings;
  String? secret;

  /// The keychain can't answer (locked, no Secret Service).
  bool keychainDown = false;

  @override
  Future<LockSettings?> loadSettings() async => settings;

  @override
  Future<void> saveSettings(LockSettings? s) async => settings = s;

  @override
  Future<String?> loadSecret() async {
    if (keychainDown) throw StateError('keychain');
    return secret;
  }

  @override
  Future<void> saveSecret(String? s) async {
    if (keychainDown) throw StateError('keychain');
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

/// A clock tests move by hand.
class FakeClock {
  FakeClock(this.at);
  DateTime at;
  DateTime call() => at;
  void advance(Duration d) => at = at.add(d);
}
