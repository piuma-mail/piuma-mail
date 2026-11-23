import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/lock/app_lock.dart';
import 'package:piuma_mail/lock/lock_platform.dart';

void main() {
  group('the settings file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('piuma-lock-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('no file: the lock is off', () async {
      expect(await FileLockStore(dir.path).loadSettings(), isNull);
    });

    test('written, read back, then removed', () async {
      final store = FileLockStore(dir.path);
      const s = LockSettings(after: LockAfter.fiveMinutes, device: false);
      await store.saveSettings(s);
      expect(await store.loadSettings(), s);
      await store.saveSettings(null);
      expect(await store.loadSettings(), isNull);
      // Removing it twice is fine.
      await store.saveSettings(null);
    });

    test('a look that fails for another reason is not "off"', () async {
      // Something is there that can't be read as a file.
      Directory('${dir.path}/app-lock.json').createSync();
      await expectLater(
        FileLockStore(dir.path).loadSettings(),
        throwsA(isA<FileSystemException>()),
      );
      // A folder that is a file: not "not found" either.
      File('${dir.path}/not-a-folder').writeAsStringSync('');
      await expectLater(
        FileLockStore('${dir.path}/not-a-folder').loadSettings(),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e,
            'not PathNotFoundException',
            isNot(isA<PathNotFoundException>()),
          ),
        ),
      );
    });

    test('AppLock counts a settings file it cannot read as on', () async {
      Directory('${dir.path}/app-lock.json').createSync();
      final lock = AppLock(
        store: _NoKeychain(dir.path),
        hasher: const EnginePinHasher(),
        device: _NoDevice(),
      );
      await lock.load();
      expect(lock.enabled, isTrue);
      expect(lock.locked, isTrue);
      lock.dispose();
    });
  });

  group('the boot clock', () {
    test("Android's boot count and elapsedRealtime", () {
      final t = androidBootTime([12, 5000])!;
      expect(t.id, 'android:12');
      expect(t.since, const Duration(seconds: 5));
    });

    test('an unknown boot count is no clock at all', () {
      expect(androidBootTime([-1, 5000]), isNull);
      expect(androidBootTime(null), isNull);
      expect(androidBootTime([]), isNull);
      expect(androidBootTime([null, 5000]), isNull);
      expect(androidBootTime([3, -1]), isNull);
      // A secret kept with a boot is then waited out in full.
      const s = LockSecret(
        pin: 'h',
        failures: 9,
        wait: Duration(hours: 1),
        boot: 'android:-1',
        bootUntil: Duration(seconds: 1),
      );
      expect(s.waitAt(androidBootTime([-1, 999999])), const Duration(hours: 1));
    });

    test("Linux's boot id and /proc/uptime", () {
      final t = linuxBootTime('abc-123\n', '3600.25 7000.00\n')!;
      expect(t.id, 'linux:abc-123');
      expect(t.since, const Duration(milliseconds: 3600250));
      expect(linuxBootTime('', '1.0 2.0'), isNull);
      expect(linuxBootTime('abc', 'nope'), isNull);
      expect(linuxBootTime('abc', '-5 2'), isNull);
      expect(linuxBootTime('abc', 'Infinity 2'), isNull);
    });
  });
}

class _NoKeychain extends FileLockStore {
  _NoKeychain(super.folder);

  @override
  Future<String?> loadSecret() async => throw StateError('keychain');
}

class _NoDevice implements DeviceUnlock {
  @override
  Future<bool> available() async => false;

  @override
  Future<bool> authenticate(String reason) async => false;
}
