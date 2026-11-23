import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/lock/app_lock.dart';
import 'package:piuma_mail/notify/notifier.dart';

import 'support/fake_lock.dart';

void main() {
  late MemoryLockStore store;
  late FakeDevice device;
  late FakeClock clock;
  late FakeTimers timers;

  AppLock make({FakeBoot? boot}) => AppLock(
    store: store,
    hasher: FakeHasher(),
    device: device,
    now: clock.call,
    elapsed: clock.elapsed,
    bootClock: boot?.call,
    timer: timers.call,
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
    timers = FakeTimers();
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
    expect(LockSettings.parse(''), const LockSettings());
    expect(LockAfter.fromSeconds(300), LockAfter.fiveMinutes);
    expect(LockAfter.fromSeconds(7), LockAfter.oneMinute);
  });

  test('notices while the lock is on are the one "New messages"', () {
    const n = SystemNotice(
      id: 3,
      title: 'Giulia Romano',
      subject: 'Dinner on Friday?',
      preview: 'Shall we try the new place',
      payload: '2\nINBOX\n41',
      buttons: true,
      silent: true,
    );
    expect(identical(privateNotice(n), n), isTrue);
    lockedNoticeTitle = 'New message';
    addTearDown(() => lockedNoticeTitle = null);
    final hidden = privateNotice(n);
    expect(hidden.title, 'New message');
    expect(hidden.subject, isEmpty);
    expect(hidden.preview, isEmpty);
    expect(hidden.buttons, isFalse);
    expect(hidden.payload, 'inbox');
    expect(hidden.id, lockedNoticeId);
    expect(hidden.standIn, isTrue);
    expect(hidden.silent, isTrue);
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

  group('away', () {
    test('locks when the time is up, without coming back', () async {
      final lock = await on();
      var told = 0;
      lock.onLocked = () => told++;
      lock.left();
      expect(timers.pending, hasLength(1));
      clock.advance(const Duration(minutes: 1));
      timers.fireUpTo(const Duration(minutes: 1));
      expect(lock.locked, isTrue);
      expect(told, 1);
      lock.dispose();
    });

    test('coming back in time stops the timer', () async {
      final lock = await on();
      lock.left();
      clock.advance(const Duration(seconds: 20));
      lock.back();
      expect(timers.pending, isEmpty);
      expect(lock.locked, isFalse);
      lock.dispose();
    });

    test('a reader window in front keeps the app in use; once none is, '
        'the time runs and every window locks', () async {
      final lock = await on();
      lock.windowInFront('reader-1', true);
      // The main window minimized while reading in another one.
      lock.left();
      expect(timers.pending, isEmpty);
      clock.advance(const Duration(minutes: 3));
      expect(lock.locked, isFalse);
      // Another app in front: the reader window stays on screen, unused.
      lock.windowInFront('reader-1', false);
      expect(timers.pending, hasLength(1));
      clock.advance(const Duration(minutes: 1));
      timers.fireUpTo(const Duration(minutes: 1));
      expect(lock.locked, isTrue);
      lock.dispose();
    });

    test('"At once" locks when the last window in front goes', () async {
      final lock = await on(after: LockAfter.immediately);
      lock.windowInFront('reader-1', true);
      lock.left();
      expect(lock.locked, isFalse);
      lock.windowInFront('reader-1', false);
      expect(lock.locked, isTrue);
      lock.dispose();
    });

    test('setting the clock back does not keep it open', () async {
      final lock = await on();
      lock.left();
      clock.advance(const Duration(minutes: 2));
      clock.jump(const Duration(hours: -3));
      lock.back();
      expect(lock.locked, isTrue);
      lock.dispose();
    });
  });

  group('the wrong-PIN wait', () {
    Future<AppLock> fiveWrong({FakeBoot? boot}) async {
      await on();
      final lock = make(boot: boot);
      await lock.load();
      for (var i = 0; i < 5; i++) {
        await lock.tryPin('0000');
      }
      expect(lock.waitLeft, const Duration(seconds: 30));
      return lock;
    }

    test('moving the clock forward does not end it', () async {
      final lock = await fiveWrong();
      clock.jump(const Duration(days: 1));
      expect(lock.waitLeft, const Duration(seconds: 30));
      expect(await lock.tryPin('2468'), isA<PinWaiting>());
      clock.advance(const Duration(seconds: 30));
      expect(await lock.tryPin('2468'), isA<PinRight>());
      lock.dispose();
    });

    test(
      'after a restart it starts over where there is no boot clock',
      () async {
        final lock = await fiveWrong();
        clock.advance(const Duration(seconds: 20));
        lock.dispose();
        clock.jump(const Duration(days: 1));
        final again = make();
        await again.load();
        expect(again.waitLeft, const Duration(seconds: 30));
        again.dispose();
      },
    );

    test(
      'within the same boot, the time closed counts by the boot clock',
      () async {
        final boot = FakeBoot();
        final lock = await fiveWrong(boot: boot);
        lock.dispose();
        boot.since += const Duration(seconds: 20);
        clock.jump(const Duration(days: 1));
        final again = make(boot: boot);
        await again.load();
        expect(again.waitLeft, const Duration(seconds: 10));
        again.dispose();
        // After the device restarts, all of it.
        boot.id = 'boot-2';
        boot.since = const Duration(minutes: 1);
        final rebooted = make(boot: boot);
        await rebooted.load();
        expect(rebooted.waitLeft, const Duration(seconds: 30));
        rebooted.dispose();
      },
    );

    test('the boot clock catches up the time the device slept', () async {
      final boot = FakeBoot();
      final lock = await fiveWrong(boot: boot);
      // Asleep: the process clock stood still, the boot clock didn't.
      boot.since += const Duration(seconds: 25);
      lock.back();
      await pumpEventQueue();
      expect(lock.waitLeft, const Duration(seconds: 5));
      // Never longer by it.
      boot.since -= const Duration(minutes: 5);
      await lock.refreshWait();
      expect(lock.waitLeft, const Duration(seconds: 5));
      lock.dispose();
    });

    test('a try that cannot be counted is not tried', () async {
      final lock = await on();
      lock.lockNow();
      store.keychainFull = true;
      for (var i = 0; i < 20; i++) {
        expect(await lock.tryPin('0000'), isA<PinNotKept>());
      }
      expect(lock.triesNotKept, isTrue);
      expect(await lock.tryPin('2468'), isA<PinNotKept>());
      expect(lock.locked, isTrue);
      expect(LockSecret.parse(store.secret)!.failures, 0);
      store.keychainFull = false;
      expect(await lock.tryPin('0000'), isA<PinWrong>());
      expect(lock.triesNotKept, isFalse);
      expect(LockSecret.parse(store.secret)!.failures, 1);
      lock.dispose();
    });

    test('a try is counted before the PIN is checked', () async {
      await on();
      final hasher = _SlowHasher();
      final slow = AppLock(
        store: store,
        hasher: hasher,
        device: device,
        now: clock.call,
        elapsed: clock.elapsed,
        timer: timers.call,
      );
      await slow.load();
      final trying = slow.tryPin('0000');
      await pumpEventQueue();
      // Closing the app while Argon2 runs doesn't make a free try.
      expect(LockSecret.parse(store.secret)!.failures, 1);
      hasher.done.complete();
      expect(await trying, isA<PinWrong>());
      slow.dispose();
    });
  });

  group('a damaged settings file', () {
    test('empty or unreadable, it starts locked', () async {
      store.secret = const LockSecret(pin: 'hash:2468').encode();
      store.fileUnreadable = true;
      final lock = make();
      await lock.load();
      expect(lock.enabled, isTrue);
      expect(lock.locked, isTrue);
      expect(lock.pinUnreadable, isFalse);
      expect(await lock.tryPin('2468'), isA<PinRight>());
      lock.dispose();
    });

    test('without a PIN in the keychain either, it says so', () async {
      store.fileUnreadable = true;
      device.has = false;
      final lock = make();
      await lock.load();
      expect(lock.locked, isTrue);
      expect(lock.pinMissing, isTrue);
      expect(lock.pinUnreadable, isTrue);
      lock.dispose();
    });
  });

  test('a PIN is checked only once its try is in the keychain', () async {
    final lock = await on();
    final hasher = _SeeingHasher(store);
    final checked = AppLock(
      store: store,
      hasher: hasher,
      device: device,
      now: clock.call,
      elapsed: clock.elapsed,
      timer: timers.call,
    );
    await checked.load();
    lock.dispose();
    expect(await checked.tryPin('0000'), isA<PinWrong>());
    expect(hasher.failuresSeen, [1]);
    // The keychain refuses: the PIN isn't checked at all.
    store.keychainFull = true;
    expect(await checked.tryPin('2468'), isA<PinNotKept>());
    expect(hasher.failuresSeen, [1]);
    checked.dispose();
  });

  group('a notice on its way when the lock turns on', () {
    const n = SystemNotice(
      id: 4,
      title: 'Giulia Romano',
      subject: 'Dinner on Friday?',
      preview: 'Shall we try the new place',
      payload: '2\nINBOX\n41',
      buttons: true,
    );
    tearDown(() => lockedNoticeTitle = null);

    test('goes out blank when the lock turned on during the seal', () async {
      final posted = <SystemNotice>[];
      final seal = _FlippingSeal(() => lockedNoticeTitle = 'New message');
      await postNotice(
        n,
        seal: seal,
        post: (shown, sealed) async {
          expect(sealed, 'sealed:inbox');
          posted.add(shown);
        },
      );
      expect(posted, hasLength(1));
      expect(posted.single.title, 'New message');
      expect(posted.single.subject, isEmpty);
      expect(posted.single.preview, isEmpty);
      expect(posted.single.buttons, isFalse);
      expect(posted.single.standIn, isTrue);
      // Its own payload is sealed, not the email's.
      expect(posted.single.payload, 'inbox');
      expect(seal.payloads.last, 'inbox');
    });

    test('keeps its words while the lock stays off', () async {
      final posted = <SystemNotice>[];
      final sealedAs = <String>[];
      await postNotice(
        n,
        seal: _FlippingSeal(() {}),
        post: (shown, sealed) async {
          posted.add(shown);
          sealedAs.add(sealed);
        },
      );
      expect(identical(posted.single, n), isTrue);
      expect(sealedAs.single, 'sealed:${n.payload}');
    });
  });
}

class _SlowHasher extends FakeHasher {
  final done = Completer<void>();

  @override
  Future<bool> verify(String pin, String hash) async {
    await done.future;
    return super.verify(pin, hash);
  }
}

/// Notes how many tries the keychain held when the PIN was checked.
class _SeeingHasher extends FakeHasher {
  _SeeingHasher(this.store);
  final MemoryLockStore store;
  final failuresSeen = <int>[];

  @override
  Future<bool> verify(String pin, String hash) async {
    failuresSeen.add(LockSecret.parse(store.secret)!.failures);
    return super.verify(pin, hash);
  }
}

/// A seal that takes a moment, during which [meanwhile] runs (the lock
/// turning on).
class _FlippingSeal extends NoticeSeal {
  _FlippingSeal(this.meanwhile);
  final void Function() meanwhile;
  final payloads = <String>[];

  @override
  Future<String> seal(String payload) async {
    await Future<void>.delayed(Duration.zero);
    meanwhile();
    payloads.add(payload);
    return 'sealed:$payload';
  }

  @override
  Future<String?> open(String sealed) async => sealed;
}
