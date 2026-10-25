import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/sidebar.dart';
import 'package:piuma_mail/inbox/vault.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/inbox/phone_parts.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/switch.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, newsletter: true);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
  return source;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Settings › Organizing (the zones) or Reading (the helpers).
Future<void> _openSettings(WidgetTester tester, String section) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(section));
  await tester.pumpAndSettle();
  await tester.tap(find.text(section));
  await _settle(tester);
}

Finder _inSidebar(String label) =>
    find.descendant(of: find.byType(Sidebar), matching: find.text(label));

void main() {
  testWidgets('every feature is on to begin with', (tester) async {
    final source = await _pump(tester);
    expect(source.features.value.off, 0);
    for (final zone in ['Newsletters', 'Vault', 'Attachments']) {
      expect(_inSidebar(zone), findsOneWidget, reason: zone);
    }
  });

  testWidgets('a zone turned off leaves the sidebar, and comes back', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _openSettings(tester, 'Organizing');
    await tester.tap(
      find
          .descendant(
            of: find.byType(ZoneSwitches),
            matching: find.byType(PiumaSwitch),
          )
          .at(2),
    );
    await tester.pumpAndSettle();
    expect(source.features.value.attachments, isFalse);
    expect(
      find.text(
        'Off · files stay in their emails, and search still finds them',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to mail'));
    await _settle(tester);
    expect(_inSidebar('Attachments'), findsNothing);
    expect(_inSidebar('Vault'), findsOneWidget);

    source.features.value = source.features.value.copyWith(
      vault: false,
      attachments: true,
    );
    await _settle(tester);
    expect(_inSidebar('Vault'), findsNothing);
    expect(_inSidebar('Attachments'), findsOneWidget);
  });

  testWidgets('a zone open when turned off shows the inbox again', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(_inSidebar('Vault'));
    await _settle(tester);
    expect(find.byType(VaultBoard), findsOneWidget);
    source.features.value = source.features.value.copyWith(vault: false);
    await _settle(tester);
    expect(find.byType(VaultBoard), findsNothing);
  });

  testWidgets('with the Vault off, Notifications has no Vault rows', (
    tester,
  ) async {
    final source = await _pump(tester);
    source.features.value = source.features.value.copyWith(vault: false);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await _settle(tester);
    expect(find.text('Package deliveries'), findsNothing);
  });

  testWidgets('on the phone only the zones on have a chip', (tester) async {
    final source = await _pump(tester, phone: true);
    expect(find.byType(ZoneTile), findsNWidgets(3));
    source.features.value = source.features.value.copyWith(
      newsletters: false,
      attachments: false,
    );
    await _settle(tester);
    expect(find.byType(VaultTile), findsOneWidget);
    expect(find.byType(ZoneTile), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_tiles_one.png'),
    );
    source.features.value = source.features.value.copyWith(vault: false);
    await _settle(tester);
    expect(find.byType(ZoneTile), findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('organizing golden $name', (tester) async {
      final source = await _pump(tester, dark: dark);
      await _openSettings(tester, 'Organizing');
      source.features.value = source.features.value.copyWith(
        attachments: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ZoneSwitches), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_organizing_$name.png'),
      );
    });

    testWidgets('reading golden $name', (tester) async {
      final source = await _pump(tester, dark: dark);
      await _openSettings(tester, 'Reading');
      source.features.value = source.features.value.copyWith(inShort: false);
      await tester.pumpAndSettle();
      expect(find.byType(HelperSwitches), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_reading_$name.png'),
      );
    });
  }

  testWidgets('phone reading golden', (tester) async {
    final source = await _pump(tester, phone: true);
    source.features.value = source.features.value.copyWith(inShort: false);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsLabel('3 accounts, accounts and Settings'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PhoneAccountsSheet),
        matching: find.text('Settings'),
      ),
    );
    await _settle(tester);
    await tester.ensureVisible(find.text('Reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading'));
    await _settle(tester);
    expect(find.byType(HelperSwitches), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_reading.png'),
    );
  });
}
