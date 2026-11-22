import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/lock/app_lock.dart';
import 'package:piuma_mail/notify/notifier.dart';

import 'support/fake_lock.dart';

void main() {
  late MemoryLockStore store;
  late FakeDevice device;
  late FakeClock clock;

  AppLock make() => AppLock(
    store: store,
    hasher: FakeHasher(),
    device: device,
    now: clock.call,
  );

  Future<AppLock> on({LockAfter after = LockAfter.oneMinute}) async {
    final lock = make();
    await lock.load();
    await lock.enable('2468', settings: LockSettings(after: after));
    return lock;
  }

  setUp(() {
    store = MemoryLockStore();
    device = FakeDevice();
    clock = FakeClock(DateTime(2026, 11, 22, 9));
  });

  test('off by default: nothing kept, never locked', () async {
    final lock = make();
    await lock.load();
    expect(lock.enabled, isFalse);
    expect(lock.locked, isFalse);
    lock.left();
    clock.advance(const Duration(hours: 1));
    lock.back();
    expect(lock.locked, isFalse);
  });

  test('turning it on keeps a hash, never the PIN', () async {
    await on();
    expect(store.settings, isNotNull);
    expect(store.secret, contains('hash:2468'));
    expect(LockSecret.parse(store.secret)!.pin, 'hash:2468');
  });

  test('a cold start with the lock on is locked', () async {
    await on();
    final again = make();
    await again.load();
    expect(again.enabled, isTrue);
    expect(again.locked, isTrue);
    again.dispose();
  });

  test('locks after the chosen time in the background, not before', () async {
    final lock = await on(after: LockAfter.fiveMinutes);
    lock.left();
    clock.advance(const Duration(minutes: 4, seconds: 59));
    lock.back();
    expect(lock.locked, isFalse);
    lock.left();
    clock.advance(const Duration(minutes: 5));
    lock.back();
    expect(lock.locked, isTrue);
    lock.dispose();
  });

  test('the first time away counts, not the last hide', () async {
    final lock = await on(after: LockAfter.oneMinute);
    lock.left();
    clock.advance(const Duration(seconds: 40));
    // Hidden then paused: two calls for one time away.
    lock.left();
    clock.advance(const Duration(seconds: 30));
    lock.back();
    expect(lock.locked, isTrue);
    lock.dispose();
  });

  test('"At once" locks as the app leaves', () async {
    final lock = await on(after: LockAfter.immediately);
    var told = 0;
    lock.onLocked = () => told++;
    lock.left();
    expect(lock.locked, isTrue);
    expect(told, 1);
    expect(AppLock.lockedNow, isTrue);
    expect(await lock.tryPin('2468'), isA<PinRight>());
    expect(lock.locked, isFalse);
    expect(AppLock.lockedNow, isFalse);
    lock.dispose();
  });

  test('wrong PINs wait longer and longer, even after a restart', () async {
    final lock = await on();
    lock.lockNow();
    for (var i = 0; i < 4; i++) {
      final r = await lock.tryPin('0000');
      expect(r, isA<PinWrong>());
      expect((r as PinWrong).wait, Duration.zero);
    }
    final fifth = await lock.tryPin('0000');
    expect((fifth as PinWrong).wait, const Duration(seconds: 30));
    // Even the right one waits.
    final early = await lock.tryPin('2468');
    expect(early, isA<PinWaiting>());
    expect(lock.locked, isTrue);

    // Closing the app doesn't reset the wait.
    final again = make();
    await again.load();
    expect(again.failures, 5);
    expect(again.waitLeft, const Duration(seconds: 30));
    clock.advance(const Duration(seconds: 31));
    final sixth = await again.tryPin('1111');
    expect((sixth as PinWrong).wait, const Duration(minutes: 1));
    clock.advance(const Duration(minutes: 1));
    expect(await again.tryPin('2468'), isA<PinRight>());
    expect(again.failures, 0);
    expect(again.waitLeft, Duration.zero);
    expect(LockSecret.parse(store.secret)!.failures, 0);
    lock.dispose();
    again.dispose();
  });

  test('the wait grows to an hour', () {
    expect(lockWait(0), Duration.zero);
    expect(lockWait(4), Duration.zero);
    expect(lockWait(5), const Duration(seconds: 30));
    expect(lockWait(6), const Duration(minutes: 1));
    expect(lockWait(7), const Duration(minutes: 5));
    expect(lockWait(8), const Duration(minutes: 15));
    expect(lockWait(9), const Duration(hours: 1));
    expect(lockWait(40), const Duration(hours: 1));
  });

  test('the device unlock opens it and clears the wrong tries', () async {
    final lock = await on();
    lock.lockNow();
    for (var i = 0; i < 5; i++) {
      await lock.tryPin('0000');
    }
    expect(lock.waitLeft, greaterThan(Duration.zero));
    device.passes = false;
    expect(await lock.tryDevice('Unlock'), isFalse);
    expect(lock.locked, isTrue);
    device.passes = true;
    expect(await lock.tryDevice('Unlock'), isTrue);
    expect(lock.locked, isFalse);
    expect(lock.failures, 0);
    expect(lock.waitLeft, Duration.zero);
    lock.dispose();
  });

  test('the system unlock sheet pausing the app does not lock it', () async {
    final lock = await on(after: LockAfter.immediately);
    lock.lockNow();
    device.passes = true;
    final asking = lock.tryDevice('Unlock');
    // Android pauses the activity for the screen lock.
    lock.left();
    expect(await asking, isTrue);
    lock.back();
    expect(lock.locked, isFalse);
    expect(lock.justPrompted, isTrue);
    clock.advance(const Duration(seconds: 3));
    expect(lock.justPrompted, isFalse);
    lock.dispose();
  });

  test('without the device unlock, or with it turned off', () async {
    device.has = false;
    final lock = await on();
    expect(lock.deviceAvailable, isFalse);
    expect(lock.deviceUnlock, isFalse);
    expect(await lock.tryDevice('Unlock'), isFalse);
    device.has = true;
    final other = make();
    await other.load();
    expect(other.deviceUnlock, isTrue);
    await other.update(other.settings!.copyWith(device: false));
    expect(other.deviceUnlock, isFalse);
    expect(store.settings!.device, isFalse);
    other.dispose();
  });

  test('a keychain that does not answer keeps it locked', () async {
    await on();
    store.keychainDown = true;
    final lock = make();
    await lock.load();
    expect(lock.locked, isTrue);
    expect(lock.pinUnreadable, isTrue);
    expect(await lock.tryPin('2468'), isA<PinWrong>());
    expect(lock.locked, isTrue);
    device.passes = true;
    expect(await lock.tryDevice('Unlock'), isTrue);
    expect(lock.locked, isFalse);
    lock.dispose();
  });

  test('turning on fails, and stays off, when the keychain cannot keep '
      'the PIN', () async {
    store.keychainDown = true;
    final lock = make();
    await lock.load();
    await expectLater(
      lock.enable('2468', settings: const LockSettings()),
      throwsA(isA<StateError>()),
    );
    expect(lock.enabled, isFalse);
    expect(store.settings, isNull);
  });

  test('turning it off forgets the PIN and opens it', () async {
    final lock = await on();
    var changes = 0;
    lock.onSettings = () => changes++;
    lock.lockNow();
    await lock.disable();
    expect(lock.enabled, isFalse);
    expect(lock.locked, isFalse);
    expect(store.settings, isNull);
    expect(store.secret, isNull);
    expect(changes, 1);
  });

  test('a new PIN replaces the old one', () async {
    final lock = await on();
    await lock.changePin('13579');
    lock.lockNow();
    expect(await lock.tryPin('2468'), isA<PinWrong>());
    expect(await lock.tryPin('13579'), isA<PinRight>());
    lock.dispose();
  });

  test('the settings file round-trips, and a damaged one means on', () {
    const s = LockSettings(
      after: LockAfter.fifteenMinutes,
      device: false,
      notice: 'Nuovo messaggio',
    );
    expect(LockSettings.parse(jsonEncode(s.toJson())), s);
    expect(LockSettings.parse('not json'), const LockSettings());
    expect(LockSettings.parse(''), isNull);
    expect(LockAfter.fromSeconds(300), LockAfter.fiveMinutes);
    expect(LockAfter.fromSeconds(7), LockAfter.oneMinute);
  });

  test('notices while the lock is on say only "New message"', () {
    const n = SystemNotice(
      id: 3,
      title: 'Giulia Romano',
      subject: 'Dinner on Friday?',
      preview: 'Shall we try the new place',
      payload: '2\nINBOX\n41',
      buttons: true,
    );
    expect(identical(privateNotice(n), n), isTrue);
    lockedNoticeTitle = 'New message';
    addTearDown(() => lockedNoticeTitle = null);
    final hidden = privateNotice(n);
    expect(hidden.title, 'New message');
    expect(hidden.subject, isEmpty);
    expect(hidden.preview, isEmpty);
    expect(hidden.buttons, isFalse);
    expect(hidden.payload, n.payload);
    expect(hidden.id, n.id);
  });

  test('the notice text follows the app language', () async {
    final lock = await on();
    var changes = 0;
    lock.onSettings = () => changes++;
    await lock.noticeText('Nuovo messaggio');
    await lock.noticeText('Nuovo messaggio');
    expect(store.settings!.notice, 'Nuovo messaggio');
    expect(changes, 1);
    lock.dispose();
  });
}
