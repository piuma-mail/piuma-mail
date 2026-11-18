import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/notify/notifier.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/settings/sync_page.dart';

import 'support/fake_notifier.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _settings(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  bool synced = false,
  DemoMailSource? demo,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = demo ?? DemoMailSource(now: _now, synced: synced);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        section: phone ? SettingsSection.accounts : SettingsSection.sync,
        now: () => _now,
      ),
    ),
  );
  await _settle(tester);
  if (phone) {
    // Lower in the list than one screen: brought into view first.
    final row = find.bySemanticsLabel(RegExp(r'^Devices & sync'));
    await tester.ensureVisible(row);
    await _settle(tester);
    await tester.tap(row);
    await _settle(tester);
  }
  return source;
}

/// Lets what enters run its timer and finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('turning sync on shows the recovery phrase once', (tester) async {
    final source = await _settings(tester);
    expect(find.byType(SyncPage), findsOneWidget);
    expect(find.text('Off · this device only'), findsOneWidget);
    expect(find.text('matteo@posta.it'), findsOneWidget);

    // Store it in: another account.
    await tester.tap(find.bySemanticsLabel('Store it in: matteo@posta.it'));
    await _settle(tester);
    await tester.tap(find.text('matteo@studio.it').last);
    await _settle(tester);
    expect(find.text('matteo@studio.it'), findsOneWidget);

    await tester.tap(find.text('Turn on sync'));
    await _settle(tester);
    expect(find.text('Your recovery phrase'), findsOneWidget);
    expect(find.text('orbit'), findsOneWidget);
    expect(find.text('thunder'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    await tester.tap(find.text('I wrote them down'));
    await _settle(tester);
    expect(find.text('Your recovery phrase'), findsNothing);
    expect(source.syncState().home, 'matteo@studio.it');
    expect(find.text('Linked devices'), findsOneWidget);
  });

  testWidgets('Link a new device shows a code, and closes once linked', (
    tester,
  ) async {
    final source = await _settings(tester, synced: true);
    await tester.tap(find.text('Link a new device'));
    await _settle(tester);
    expect(find.bySemanticsLabel('QR code to link a new device'), findsOne);
    expect(
      find.text('Waiting for the new device… · new code in 5:00'),
      findsOneWidget,
    );
    expect(find.textContaining('No camera? Sign in to'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sync_link_qr_light.png'),
    );

    source.linkDevice();
    await _settle(tester);
    expect(find.bySemanticsLabel('QR code to link a new device'), findsNothing);
    expect(find.text('Pixel 9 linked'), findsOneWidget);
  });

  testWidgets('a device is unlinked and the phrase changes', (tester) async {
    final source = await _settings(tester, synced: true);
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('Active now'), findsOneWidget);
    expect(find.text('Active 3 days ago'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Unlink iPad Air'));
    await _settle(tester);
    expect(find.text('Unlink iPad Air?'), findsOneWidget);
    await tester.tap(find.text('Unlink').last);
    await _settle(tester);
    expect(find.text('Your new recovery phrase'), findsOneWidget);
    await tester.tap(find.text('I wrote them down'));
    await _settle(tester);
    // It still knows the mailboxes' passwords: the person is told which.
    expect(find.text('Change these passwords'), findsOneWidget);
    expect(
      find.textContaining('iPad Air can’t read your space any more'),
      findsOneWidget,
    );
    expect(find.text('matteo@studio.it'), findsWidgets);
    await tester.tap(find.text('Got it'));
    await _settle(tester);
    expect(find.text('Change these passwords'), findsNothing);
    expect(find.text('iPad Air'), findsNothing);
    expect(source.syncState().devices, hasLength(2));
  });

  testWidgets('an account removed elsewhere waits here until the person says', (
    tester,
  ) async {
    final source = _Held(now: _now, synced: true);
    await _settings(tester, demo: source);
    expect(
      find.text('matteo@studio.it was removed on another device'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Here it still has 2 emails waiting to be sent and 1 draft not '
        'saved to the server yet. Remove it from this device too, or keep '
        'it on all your devices?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove here'));
    await _settle(tester);
    expect(source.removed, [2]);
    expect(
      find.text('matteo@studio.it was removed on another device'),
      findsNothing,
    );
  });

  testWidgets('keeping an account removed elsewhere brings it back', (
    tester,
  ) async {
    final source = _Held(now: _now, synced: true);
    await _settings(tester, demo: source);
    await tester.tap(find.text('Keep it'));
    await _settle(tester);
    expect(source.kept, [2]);
  });

  testWidgets('a recovery phrase a merge changed is offered to write down', (
    tester,
  ) async {
    await _settings(
      tester,
      demo: _Held(now: _now, synced: true, recoveryChanged: true),
    );
    expect(find.text('Write down your new recovery phrase'), findsOneWidget);
    await tester.tap(find.text('Show').first);
    await _settle(tester);
    expect(find.text('I wrote them down'), findsOneWidget);
  });

  testWidgets('an old copy put back, and a newer version, are told', (
    tester,
  ) async {
    await _settings(
      tester,
      demo: _Held(now: _now, synced: true, rollback: true, outdated: true),
    );
    expect(find.text('An older copy of your space was left out'), findsOne);
    expect(
      find.textContaining('Someone with access to matteo@posta.it'),
      findsOneWidget,
    );
    expect(
      find.text('Update Piuma to sync this device’s changes'),
      findsOneWidget,
    );
  });

  testWidgets('the space moves to another mailbox, devices kept', (
    tester,
  ) async {
    final source = await _settings(tester, synced: true);
    final home = source.syncState().home!;
    await tester.tap(find.bySemanticsLabel('Sync mailbox: $home'));
    await _settle(tester);
    await tester.tap(find.text('teo@icloud.com').last);
    await _settle(tester);
    expect(source.syncState().home, 'teo@icloud.com');
    expect(source.syncState().devices, hasLength(3));
    expect(find.bySemanticsLabel('Sync mailbox: teo@icloud.com'), findsOne);
  });

  testWidgets('sync turns off on this device, asking first', (tester) async {
    final source = await _settings(tester, synced: true);
    await tester.tap(find.text('Turn off sync on this device'));
    await _settle(tester);
    expect(find.text('Turn off sync on this device?'), findsOneWidget);
    expect(find.textContaining('Pixel 8 and iPad Air keep syncing'), findsOne);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(source.syncState().on, isTrue);

    await tester.tap(find.text('Turn off sync on this device'));
    await _settle(tester);
    await tester.tap(find.text('Turn off sync'));
    await _settle(tester);
    expect(source.syncState().on, isFalse);
    expect(find.text('Off · this device only'), findsOneWidget);
  });

  testWidgets('on the only device, turning off deletes the space', (
    tester,
  ) async {
    final source = await _settings(tester, synced: true);
    for (final name in ['Pixel 8', 'iPad Air']) {
      await tester.tap(find.bySemanticsLabel('Unlink $name'));
      await _settle(tester);
      await tester.tap(find.text('Unlink').last);
      await _settle(tester);
      await tester.tap(find.text('I wrote them down'));
      await _settle(tester);
      await tester.tap(find.text('Got it'));
      await _settle(tester);
    }
    expect(source.syncState().devices, hasLength(1));
    await tester.tap(find.text('Turn off sync on this device'));
    await _settle(tester);
    expect(
      find.textContaining('the encrypted copy in matteo@posta.it is deleted'),
      findsOne,
    );
  });

  testWidgets('turn off dialog golden', (tester) async {
    await _settings(tester, synced: true);
    await tester.tap(find.text('Turn off sync on this device'));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sync_turn_off_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('a new phone is approved with its code', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now, synced: true);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);

    source.askToPair();
    await _settle(tester);
    expect(find.text('New phone wants to connect'), findsOneWidget);
    expect(find.text('Pixel 8 · asked just now'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '482615');
    await _settle(tester);
    await tester.tap(find.text('Approve'));
    await _settle(tester);
    expect(find.text('New phone wants to connect'), findsNothing);
    expect(source.pairAsks.value, isEmpty);

    // Not me deletes the request.
    source.askToPair(name: 'Old phone');
    await _settle(tester);
    await tester.tap(find.text('Not me'));
    await _settle(tester);
    expect(source.pairAsks.value, isEmpty);
  });

  testWidgets('away from the app, a request comes as a notice', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shown = (notifier as FakeNotifier).shown..clear();
    final source = DemoMailSource(now: _now, synced: true);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);

    // In the app: the sheet only.
    source.askToPair(name: 'Work laptop');
    await _settle(tester);
    expect(shown, isEmpty);
    await tester.tap(find.text('Not me'));
    await _settle(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    source.askToPair();
    await _settle(tester);
    expect(shown.single.title, 'New phone wants to connect');
    expect(shown.single.subject, 'Pixel 8');
    expect(shown.single.preview, 'Enter the 6 digits the phone shows.');
    // Back in the app, the sheet is waiting.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(find.text('New phone wants to connect'), findsOneWidget);
  });

  testWidgets('the sidebar says on how many devices it syncs', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final synced in [false, true]) {
      await tester.pumpWidget(
        PiumaApp(
          key: ValueKey(synced),
          home: (_, _) => InboxScreen(
            source: DemoMailSource(now: _now, synced: synced),
            onAddAccount: () {},
            now: () => _now,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(
        find.text('Synced on 3 devices'),
        synced ? findsOneWidget : findsNothing,
      );
    }
  });

  testWidgets('sidebar synced golden', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => InboxScreen(
          source: DemoMailSource(now: _now, synced: true),
          onAddAccount: () {},
          now: () => _now,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sidebar_synced_light.png'),
    );
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('sync golden $name', (tester) async {
      await _settings(tester, dark: dark, synced: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sync_$name.png'),
      );
    });
  }

  testWidgets('sync off golden', (tester) async {
    await _settings(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sync_off_light.png'),
    );
  });

  testWidgets('recovery phrase golden', (tester) async {
    await _settings(tester, synced: true);
    await tester.tap(find.text('Show'));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sync_phrase_light.png'),
    );
  });

  testWidgets('phone sync golden', (tester) async {
    await _settings(tester, phone: true, synced: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_sync_light.png'),
    );
  });

  testWidgets('pair ask golden', (tester) async {
    for (final phone in [false, true]) {
      tester.view.physicalSize = phone
          ? const Size(390, 844)
          : const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final source = DemoMailSource(now: _now, synced: true);
      await tester.pumpWidget(
        PiumaApp(
          key: ValueKey(phone),
          home: (_, _) =>
              InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      source.askToPair();
      await _settle(tester);
      await tester.enterText(find.byType(TextField).last, '4826');
      await _settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/${phone ? 'phone_' : ''}pair_ask_light.png'),
      );
    }
    tester.view.reset();
  });

  // The phone, after the goldens above: the same states, in its layout.
  testWidgets('on the phone, a removal elsewhere waits for the person too', (
    tester,
  ) async {
    final source = _Held(now: _now, synced: true);
    await _settings(tester, phone: true, demo: source);
    expect(
      find.text('matteo@studio.it was removed on another device'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Remove here'));
    await tester.tap(find.text('Remove here'));
    await _settle(tester);
    expect(source.removed, [2]);
  });

  testWidgets('on the phone, keeping it works the same', (tester) async {
    final source = _Held(now: _now, synced: true);
    await _settings(tester, phone: true, demo: source);
    await tester.ensureVisible(find.text('Keep it'));
    await tester.tap(find.text('Keep it'));
    await _settle(tester);
    expect(source.kept, [2]);
  });

  testWidgets('on the phone, the warnings and the new phrase are told', (
    tester,
  ) async {
    await _settings(
      tester,
      phone: true,
      demo: _Held(now: _now, synced: true, rollback: true, outdated: true),
    );
    expect(find.text('An older copy of your space was left out'), findsOne);
    expect(
      find.text('Update Piuma to sync this device’s changes'),
      findsOneWidget,
    );
  });

  testWidgets('on the phone, a changed recovery phrase is shown in a sheet', (
    tester,
  ) async {
    await _settings(
      tester,
      phone: true,
      demo: _Held(now: _now, synced: true, recoveryChanged: true),
    );
    expect(find.text('Write down your new recovery phrase'), findsOneWidget);
    await tester.ensureVisible(find.text('Show').first);
    await tester.tap(find.text('Show').first);
    await _settle(tester);
    expect(find.text('I wrote them down'), findsOneWidget);
  });

  testWidgets('on the phone, unlinking says which passwords to change', (
    tester,
  ) async {
    final source = await _settings(tester, phone: true, synced: true);
    await tester.ensureVisible(find.bySemanticsLabel('Unlink iPad Air'));
    await tester.tap(find.bySemanticsLabel('Unlink iPad Air'));
    await _settle(tester);
    await tester.tap(find.text('Unlink').last);
    await _settle(tester);
    await tester.tap(find.text('I wrote them down'));
    await _settle(tester);
    expect(find.text('Change these passwords'), findsOneWidget);
    expect(find.text('matteo@studio.it'), findsWidgets);
    await tester.tap(find.text('Got it'));
    await _settle(tester);
    expect(find.text('Change these passwords'), findsNothing);
    expect(source.syncState().devices, hasLength(2));
  });

  _trustTests(phone: false);
  _trustTests(phone: true);
}

/// Devices & sync on a device that must be confirmed (it synced with an
/// older version), that stopped because two devices removed each other, or
/// that another device removed. Linking it again with the phrase clears
/// each.
class _Trust extends DemoMailSource {
  _Trust({
    required super.now,
    this.unverified = false,
    this.conflict = false,
    this.unlinked = false,
  }) : super(synced: true, spaceToFind: true);

  bool unverified;
  bool conflict;
  bool unlinked;

  @override
  SyncState syncState() {
    final s = super.syncState();
    return SyncState(
      home: s.home,
      syncedAt: s.syncedAt,
      devices: s.devices,
      exposed: s.exposed,
      exposedDevice: s.exposedDevice,
      unverified: unverified,
      conflict: conflict ? const ['Matteo’s MacBook', 'Old phone'] : const [],
      unlinked: s.on && unlinked ? 'Pixel 8' : null,
    );
  }

  @override
  Future<void> recoverSpace(int accountId, String phrase) async {
    await super.recoverSpace(accountId, phrase);
    _cleared();
  }

  @override
  Future<void> joinSpace(int accountId, String code) async {
    await super.joinSpace(accountId, code);
    _cleared();
  }

  void _cleared() {
    unverified = false;
    conflict = false;
    unlinked = false;
  }
}

/// Links again with a code from the card's button: the Mac approves (or,
/// with [problem], the engine refuses).
Future<void> _linkWithCode(
  WidgetTester tester,
  _Trust source,
  String button, {
  SyncProblem? problem,
}) async {
  await tester.ensureVisible(find.text(button));
  await tester.tap(find.text(button));
  await _settle(tester);
  expect(find.text('We found your space'), findsOneWidget);
  await tester.tap(find.text('Show code'));
  // The code counts down every second: nothing settles while it shows.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.bySemanticsLabel(RegExp('^Code ')), findsOneWidget);
  source.answerJoin(problem);
  await _settle(tester);
  if (problem != null) return;
  await tester.tap(find.text('Go to inbox'));
  await _settle(tester);
}

/// Confirms (or links again) with the phrase, from the card's button.
Future<void> _linkWithPhrase(WidgetTester tester, String button) async {
  await tester.ensureVisible(find.text(button));
  await tester.tap(find.text(button));
  await _settle(tester);
  expect(find.text('We found your space'), findsOneWidget);
  await tester.tap(find.text('Use recovery phrase'));
  await _settle(tester);
  await tester.enterText(find.byType(TextField), DemoMailSource.demoPhrase);
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await _settle(tester);
  await tester.tap(find.text('Go to inbox'));
  await _settle(tester);
}

void _trustTests({required bool phone}) {
  final on = phone ? 'on the phone, ' : '';
  testWidgets('${on}a device from an older version is confirmed first', (
    tester,
  ) async {
    final source = _Trust(now: _now, unverified: true);
    await _settings(tester, phone: phone, demo: source);
    expect(find.text('Confirm this device'), findsOneWidget);
    expect(find.text('Paused on this device'), findsOneWidget);
    expect(
      find.textContaining('Until you confirm this one with your recovery'),
      findsOneWidget,
    );
    await _linkWithPhrase(tester, 'Confirm');
    expect(find.byType(SyncPage), findsOneWidget);
    expect(find.text('Confirm this device'), findsNothing);
    expect(source.syncState().unverified, isFalse);
  });

  testWidgets('${on}two devices removing each other stop sync here', (
    tester,
  ) async {
    final source = _Trust(now: _now, conflict: true);
    await _settings(tester, phone: phone, demo: source);
    expect(find.text('Two devices removed each other'), findsOneWidget);
    expect(find.text('Paused on this device'), findsOneWidget);
    expect(
      find.textContaining('Matteo’s MacBook and Old phone each removed'),
      findsOneWidget,
    );
    await _linkWithPhrase(tester, 'Link again');
    expect(find.text('Two devices removed each other'), findsNothing);
  });

  testWidgets('${on}another device removing this one says which, and links '
      'again', (tester) async {
    final source = _Trust(now: _now, unlinked: true);
    await _settings(tester, phone: phone, demo: source);
    expect(find.text('Pixel 8 removed this device'), findsOneWidget);
    expect(find.text('Paused on this device'), findsOneWidget);
    expect(
      find.textContaining('its accounts and mail stay here'),
      findsOneWidget,
    );
    await _linkWithPhrase(tester, 'Link again');
    expect(find.text('Pixel 8 removed this device'), findsNothing);
    expect(source.syncState().on, isTrue);
  });

  testWidgets('${on}two devices removing each other: linked again with a '
      'code', (tester) async {
    final source = _Trust(now: _now, conflict: true);
    await _settings(tester, phone: phone, demo: source);
    await _linkWithCode(tester, source, 'Link again');
    expect(find.text('Two devices removed each other'), findsNothing);
    expect(source.syncState().conflict, isEmpty);
  });

  testWidgets('${on}another device removing this one: linked again with a '
      'code', (tester) async {
    final source = _Trust(now: _now, unlinked: true);
    await _settings(tester, phone: phone, demo: source);
    await _linkWithCode(tester, source, 'Link again');
    expect(find.text('Pixel 8 removed this device'), findsNothing);
    expect(source.syncState().on, isTrue);
  });

  testWidgets('${on}linking again while the space still stops says why', (
    tester,
  ) async {
    final source = _Trust(now: _now, conflict: true);
    await _settings(tester, phone: phone, demo: source);
    await _linkWithCode(
      tester,
      source,
      'Link again',
      problem: SyncProblem.conflict,
    );
    expect(
      find.textContaining('Two of your devices removed each other, so this'),
      findsOneWidget,
    );
    expect(source.syncState().conflict, isNotEmpty);
  });

  testWidgets('${on}a device another one removed turns sync off when asked', (
    tester,
  ) async {
    final source = _Trust(now: _now, unlinked: true);
    await _settings(tester, phone: phone, demo: source);
    final off = find.text('Turn off sync').first;
    await tester.ensureVisible(off);
    await tester.tap(off);
    await _settle(tester);
    expect(find.text('Turn off sync on this device?'), findsOneWidget);
    await tester.tap(find.text('Turn off sync').last);
    await _settle(tester);
    expect(source.syncState().on, isFalse);
    expect(find.text('Pixel 8 removed this device'), findsNothing);
  });

  testWidgets('${on}the passwords an unlinked device knew stay asked for', (
    tester,
  ) async {
    final source = await _settings(tester, phone: phone, synced: true);
    await tester.ensureVisible(find.bySemanticsLabel('Unlink iPad Air'));
    await tester.tap(find.bySemanticsLabel('Unlink iPad Air'));
    await _settle(tester);
    await tester.tap(find.text('Unlink').last);
    await _settle(tester);
    await tester.tap(find.text('I wrote them down'));
    await _settle(tester);
    // The mailbox that holds the space comes first, and says why.
    expect(find.text('First: it holds your space'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await _settle(tester);
    // Until the person says they changed them, Devices & sync asks.
    expect(find.text('Change these passwords now'), findsOneWidget);
    expect(
      find.textContaining('Start with matteo@posta.it: until its password'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('I changed them'));
    await tester.tap(find.text('I changed them'));
    await _settle(tester);
    expect(find.text('Change these passwords now'), findsNothing);
    expect(source.syncState().exposed, isEmpty);
  });
}

/// A space where another device removed an account that still has mail
/// waiting here.
class _Held extends DemoMailSource {
  _Held({
    required super.now,
    super.synced,
    this.rollback = false,
    this.outdated = false,
    this.recoveryChanged = false,
  });

  final bool rollback;
  final bool outdated;
  final bool recoveryChanged;
  final removed = <int>[];
  final kept = <int>[];

  @override
  SyncState syncState() {
    final s = super.syncState();
    return SyncState(
      home: s.home,
      syncedAt: s.syncedAt,
      devices: s.devices,
      rollback: rollback,
      outdated: outdated,
      recoveryChanged: recoveryChanged,
      held: [
        if (!rollback && !recoveryChanged && removed.isEmpty && kept.isEmpty)
          const HeldRemoval(
            accountId: 2,
            email: 'matteo@studio.it',
            outbox: 2,
            drafts: 1,
          ),
      ],
    );
  }

  @override
  Future<void> confirmRemoval(int accountId) async => removed.add(accountId);

  @override
  Future<void> keepAccount(int accountId) async => kept.add(accountId);
}
