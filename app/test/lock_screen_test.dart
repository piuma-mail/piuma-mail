import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/lock/app_lock.dart';
import 'package:piuma_mail/lock/lock_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/segments.dart';
import 'package:piuma_mail/widgets/switch.dart';

import 'support/fake_lock.dart';

final _now = DateTime(2026, 11, 22, 9);

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);

class _Lock {
  _Lock({bool device = true}) : device = FakeDevice(has: device);
  final store = MemoryLockStore();
  final FakeDevice device;
  final clock = FakeClock(_now);

  AppLock make() => AppLock(
    store: store,
    hasher: FakeHasher(),
    device: device,
    now: clock.call,
    elapsed: clock.elapsed,
  );

  /// A lock turned on with 2468, as at a cold start: locked.
  Future<AppLock> locked() async {
    store.settings = const LockSettings();
    store.secret = const LockSecret(pin: 'hash:2468').encode();
    final lock = make();
    await lock.load();
    return lock;
  }
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpApp(
  WidgetTester tester,
  AppLock lock, {
  bool dark = false,
  Size size = _desktop,
}) async {
  _size(tester, size);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      lock: lock,
      home: (_, _) => const Scaffold(body: Center(child: Text('Secret mail'))),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

void main() {
  testWidgets('locked, the mail is not drawn and the lock screen is', (
    tester,
  ) async {
    final lock = await _Lock(device: false).locked();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    expect(find.text('Secret mail'), findsNothing);
    expect(find.text('Piuma is locked'), findsOneWidget);
    expect(find.text('Type your PIN to see your mail.'), findsOneWidget);
    // No device unlock here: only the PIN, and what forgetting it means.
    expect(find.text('Use this device’s unlock'), findsNothing);
    expect(find.textContaining('removing Piuma’s data'), findsOneWidget);
  });

  testWidgets('a wrong PIN says so; the right one opens the mail', (
    tester,
  ) async {
    final lock = await _Lock(device: false).locked();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    final pin = find.byKey(const ValueKey('lock-pin'));
    await _type(tester, pin, '1111');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN.'), findsOneWidget);
    expect(find.text('Secret mail'), findsNothing);
    await _type(tester, pin, '2468');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Piuma is locked'), findsNothing);
    expect(find.text('Secret mail'), findsOneWidget);
  });

  testWidgets('after five wrong PINs it counts down before the next try', (
    tester,
  ) async {
    final l = _Lock(device: false);
    final lock = await l.locked();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    final pin = find.byKey(const ValueKey('lock-pin'));
    for (var i = 0; i < 5; i++) {
      await _type(tester, pin, '0000');
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();
    }
    expect(
      find.text('Too many wrong tries. Try again in 0:30.'),
      findsOneWidget,
    );
    l.clock.advance(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Too many wrong tries. Try again in 0:20.'),
      findsOneWidget,
    );
    l.clock.advance(const Duration(seconds: 21));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Too many wrong tries'), findsNothing);
  });

  testWidgets('the device unlock is asked at once and opens the mail', (
    tester,
  ) async {
    final l = _Lock();
    l.device.passes = true;
    final lock = await l.locked();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    expect(l.device.asked, 1);
    expect(find.text('Secret mail'), findsOneWidget);
  });

  testWidgets('cancelled, the device unlock waits on Unlock, or the PIN', (
    tester,
  ) async {
    final l = _Lock();
    final lock = await l.locked();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    expect(l.device.asked, 1);
    expect(find.text('Unlock to see your mail.'), findsOneWidget);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(l.device.asked, 2);
    await tester.tap(find.text('Use PIN'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lock-pin')), findsOneWidget);
    expect(find.text('Use this device’s unlock'), findsOneWidget);
    expect(find.textContaining('Unlock with this device instead'), findsOne);
  });

  testWidgets('back from the background after the time, it locks again', (
    tester,
  ) async {
    final l = _Lock(device: false);
    l.store.settings = const LockSettings(after: LockAfter.fiveMinutes);
    l.store.secret = const LockSecret(pin: 'hash:2468').encode();
    final lock = l.make();
    await lock.load();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    expect(find.text('Secret mail'), findsNothing);
    final pin = find.byKey(const ValueKey('lock-pin'));
    await _type(tester, pin, '2468');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Secret mail'), findsOneWidget);

    Future<void> away(Duration d) async {
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      l.clock.advance(d);
      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
    }

    await away(const Duration(minutes: 2));
    expect(find.text('Secret mail'), findsOneWidget);
    await away(const Duration(minutes: 6));
    expect(find.text('Secret mail'), findsNothing);
    expect(find.text('Piuma is locked'), findsOneWidget);
  });

  testWidgets('a try the keychain cannot count is refused, and says so', (
    tester,
  ) async {
    final l = _Lock(device: false);
    final lock = await l.locked();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    l.store.keychainFull = true;
    final pin = find.byKey(const ValueKey('lock-pin'));
    await _type(tester, pin, '2468');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.textContaining('couldn’t record this try'), findsOneWidget);
    expect(find.text('Secret mail'), findsNothing);
    l.store.keychainFull = false;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Secret mail'), findsOneWidget);
  });

  testWidgets('a damaged settings file without a PIN says why it is shut', (
    tester,
  ) async {
    final l = _Lock(device: false);
    l.store.fileUnreadable = true;
    final lock = l.make();
    await lock.load();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    expect(find.text('Secret mail'), findsNothing);
    expect(find.textContaining('has no PIN for it'), findsOneWidget);
    expect(find.byKey(const ValueKey('lock-pin')), findsNothing);
  });

  testWidgets('away for the time with the window still up, it locks', (
    tester,
  ) async {
    final l = _Lock(device: false);
    l.store.settings = const LockSettings(after: LockAfter.oneMinute);
    l.store.secret = const LockSecret(pin: 'hash:2468').encode();
    final lock = l.make();
    await lock.load();
    addTearDown(lock.dispose);
    await _pumpApp(tester, lock);
    await _type(tester, find.byKey(const ValueKey('lock-pin')), '2468');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Secret mail'), findsOneWidget);
    // Minimized, never brought back.
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    l.clock.advance(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(lock.locked, isTrue);
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
    expect(find.text('Piuma is locked'), findsOneWidget);
  });

  group('Settings › Privacy & security', () {
    Future<DemoMailSource> openPrivacy(
      WidgetTester tester,
      AppLock lock, {
      bool dark = false,
      Size size = _desktop,
    }) async {
      _size(tester, size);
      final source = DemoMailSource(now: _now);
      await tester.pumpWidget(
        PiumaApp(
          initialDark: dark,
          lock: lock,
          home: (_, _) => SettingsScreen(
            source: source,
            onBack: () {},
            onAddAccount: () {},
            section: SettingsSection.privacy,
            now: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Lock Piuma'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      return source;
    }

    Finder switchOf(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
      matching: find.byType(PiumaSwitch),
    );

    testWidgets('Lock Piuma is off by default and turns on with a PIN', (
      tester,
    ) async {
      final l = _Lock();
      final lock = l.make();
      await lock.load();
      addTearDown(lock.dispose);
      await openPrivacy(tester, lock);
      expect(find.text('Lock Piuma'), findsOneWidget);
      expect(find.text('Lock after'), findsNothing);
      await tester.tap(switchOf('Lock Piuma'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a PIN'), findsWidgets);
      expect(find.textContaining('no other way back in'), findsOneWidget);

      await _type(tester, find.byKey(const ValueKey('new-pin')), '12');
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(find.text('A PIN is 4 to 12 digits.'), findsOneWidget);
      await _type(tester, find.byKey(const ValueKey('new-pin')), '2468');
      await _type(tester, find.byKey(const ValueKey('new-pin-again')), '2469');
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(find.text('The two PINs aren’t the same.'), findsOneWidget);
      await _type(tester, find.byKey(const ValueKey('new-pin-again')), '2468');
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();

      expect(lock.enabled, isTrue);
      expect(lock.locked, isFalse);
      expect(l.store.secret, contains('hash:2468'));
      expect(l.store.settings!.after, LockAfter.oneMinute);
      expect(l.store.settings!.device, isTrue);
      expect(find.text('Lock after'), findsOneWidget);
      expect(find.text('Unlock with this device'), findsOneWidget);
      expect(find.text('Change PIN'), findsOneWidget);

      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      expect(l.store.settings!.after, LockAfter.fifteenMinutes);
      await tester.tap(switchOf('Unlock with this device'));
      await tester.pumpAndSettle();
      expect(l.store.settings!.device, isFalse);

      await tester.tap(switchOf('Lock Piuma'));
      await tester.pumpAndSettle();
      expect(lock.enabled, isFalse);
      expect(l.store.settings, isNull);
      expect(l.store.secret, isNull);
      expect(find.text('Lock after'), findsNothing);
    });

    testWidgets('no device unlock: no switch for it', (tester) async {
      final l = _Lock(device: false);
      l.store.settings = const LockSettings();
      l.store.secret = const LockSecret(pin: 'hash:2468').encode();
      final lock = l.make();
      // Opened, as after typing the PIN.
      await lock.load();
      await lock.tryPin('2468');
      addTearDown(lock.dispose);
      await openPrivacy(tester, lock);
      expect(find.text('Lock after'), findsOneWidget);
      expect(find.text('Unlock with this device'), findsNothing);
      expect(find.byType(PiumaSegments), findsOneWidget);
    });

    testWidgets('a keychain that cannot keep the PIN leaves it off', (
      tester,
    ) async {
      final l = _Lock();
      l.store.keychainDown = true;
      final lock = l.make();
      await lock.load();
      addTearDown(lock.dispose);
      await openPrivacy(tester, lock);
      await tester.tap(switchOf('Lock Piuma'));
      await tester.pumpAndSettle();
      await _type(tester, find.byKey(const ValueKey('new-pin')), '2468');
      await _type(tester, find.byKey(const ValueKey('new-pin-again')), '2468');
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(lock.enabled, isFalse);
      expect(find.textContaining('couldn’t keep the PIN'), findsOneWidget);
    });

    for (final (form, size) in [('desktop', _desktop), ('phone', _phone)]) {
      for (final dark in [false, true]) {
        final name = '${form}_${dark ? 'dark' : 'light'}';
        testWidgets('golden settings $name', (tester) async {
          final l = _Lock();
          l.store.settings = const LockSettings();
          l.store.secret = const LockSecret(pin: 'hash:2468').encode();
          l.device.passes = true;
          final lock = l.make();
          await lock.load();
          await lock.tryDevice('Unlock');
          addTearDown(lock.dispose);
          await openPrivacy(tester, lock, dark: dark, size: size);
          await tester.scrollUntilVisible(
            find.text('Change PIN'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          // The whole section, from its switch down.
          Scrollable.ensureVisible(
            tester.element(find.text('Lock Piuma')),
            alignment: 0.08,
          ).ignore();
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/lock_settings_$name.png'),
          );
        });
      }
    }
  });

  for (final (form, size) in [('desktop', _desktop), ('phone', _phone)]) {
    for (final dark in [false, true]) {
      final name = '${form}_${dark ? 'dark' : 'light'}';
      testWidgets('golden lock screen, device unlock, $name', (tester) async {
        final lock = await _Lock().locked();
        addTearDown(lock.dispose);
        await _pumpApp(tester, lock, dark: dark, size: size);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/lock_device_$name.png'),
        );
      });

      testWidgets('golden lock screen, PIN, $name', (tester) async {
        final lock = await _Lock().locked();
        addTearDown(lock.dispose);
        await _pumpApp(tester, lock, dark: dark, size: size);
        await tester.tap(find.text('Use PIN'));
        await tester.pumpAndSettle();
        await _type(tester, find.byKey(const ValueKey('lock-pin')), '1111');
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
        await _type(tester, find.byKey(const ValueKey('lock-pin')), '24');
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/lock_pin_$name.png'),
        );
      });
    }
  }

  testWidgets('the scope gives Settings the lock', (tester) async {
    final lock = await _Lock().locked();
    addTearDown(lock.dispose);
    AppLock? seen;
    _size(tester, _desktop);
    await tester.pumpWidget(
      PiumaApp(
        lock: lock,
        home: (_, _) => Builder(
          builder: (context) {
            seen = AppLockScope.maybeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, same(lock));
  });
}
