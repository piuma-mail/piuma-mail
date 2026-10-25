import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
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
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, synced: synced);
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
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Devices & sync')));
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
    expect(find.text('iPad Air'), findsNothing);
    expect(source.syncState().devices, hasLength(2));
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
}
