import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/version.dart';
import 'package:piuma_mail/widgets/switch.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool trusted = true,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, newsletter: true);
  if (trusted) {
    source.trustedSince['ciao@bottegalume.example'] = DateTime(2026, 9, 2);
    source.trustedSince['sara@studio.it'] = DateTime(2026, 8, 14);
  }
  final first = (await source.page(0, 1)).first;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => _now,
        initialSelection: first,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Future<void> _openPrivacy(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Privacy & security'));
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  test('the version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: ([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });

  testWidgets('Settings opens from the sidebar and goes back', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      find.text(
        '3 IMAP mailboxes, one Inbox. Color shows where each email comes '
        'from.',
      ),
      findsOneWidget,
    );
    expect(find.text('matteo@studio.it · IMAP'), findsOneWidget);
    expect(find.text('Piuma Mail $appVersion · GPL-3.0'), findsOneWidget);
    await tester.tap(find.text('Back to mail'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('Ctrl+comma opens Settings and Esc closes it', (tester) async {
    await _pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('privacy switches change what the engine does', (tester) async {
    final source = await _pump(tester);
    await _openPrivacy(tester);
    expect(find.byType(PiumaSwitch), findsNWidgets(7));
    final pixels = find.ancestor(
      of: find.text('Stop tracking pixels'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: pixels.first, matching: find.byType(PiumaSwitch)),
    );
    await tester.pumpAndSettle();
    expect(source.privacy.stopPixels, isFalse);
    expect(source.privacy.blockImages, isTrue);
  });

  testWidgets('Show verified sender has its Verified badge', (tester) async {
    final source = await _pump(tester);
    await _openPrivacy(tester);
    expect(find.text('Show verified sender'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    final verified = find.ancestor(
      of: find.text('Show verified sender'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: verified.first, matching: find.byType(PiumaSwitch)),
    );
    await tester.pumpAndSettle();
    expect(source.privacy.verifiedSender, isFalse);
    expect(source.privacy.warnLinks, isTrue);
  });

  testWidgets('Sender pictures and Website icons have their switches', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _openPrivacy(tester);
    for (final (label, read) in [
      ('Website icons', () => source.privacy.websiteIcons),
      ('Sender pictures', () => source.privacy.senderPictures),
    ]) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      );
      final toggle = find.descendant(
        of: row.first,
        matching: find.byType(PiumaSwitch),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(read(), isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(read(), isFalse);
    }
  });

  testWidgets('the last 30 days, counted', (tester) async {
    await _pump(tester);
    await _openPrivacy(tester);
    expect(find.bySemanticsLabel('412'), findsOneWidget);
    expect(find.bySemanticsLabel('1,208'), findsOneWidget);
    expect(
      find.text(
        'Open pixels 318 · remote fonts and styles 94 · 7 suspicious links '
        'flagged',
      ),
      findsOneWidget,
    );
  });

  testWidgets('trusted senders can be removed', (tester) async {
    final source = await _pump(tester);
    await _openPrivacy(tester);
    expect(find.text('Bottega Lume'), findsOneWidget);
    expect(find.text('ciao@bottegalume.example · since Sep 2'), findsOneWidget);
    expect(find.text('Sara Conti'), findsOneWidget);
    await tester.ensureVisible(find.text('Remove').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Bottega Lume'), findsNothing);
    expect(source.trusted, {'sara@studio.it'});
    await tester.ensureVisible(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.text('No trusted senders. Images stay blocked for everyone.'),
      findsOneWidget,
    );
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('settings golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _openPrivacy(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_privacy_$name.png'),
      );
      await tester.tap(find.text('Accounts'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_accounts_$name.png'),
      );
    }, tags: ['golden']);
  }
}
