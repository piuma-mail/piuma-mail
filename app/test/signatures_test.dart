import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/settings/signatures_page.dart';
import 'package:piuma_mail/widgets/text_field.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// A one-pixel blue PNG.
const _pixel = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  2,
  0,
  0,
  0,
  144,
  119,
  83,
  222,
  0,
  0,
  0,
  12,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  48,
  9,
  188,
  8,
  0,
  2,
  19,
  1,
  87,
  227,
  162,
  145,
  17,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

Future<DemoMailSource> _pump(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        section: SettingsSection.writing,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return source;
}

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(PiumaTextField, label),
  matching: find.byType(TextField),
);

void main() {
  testWidgets('lists the signatures and opens the first one', (tester) async {
    await _pump(tester);
    expect(find.text('Work'), findsWidgets);
    expect(find.text('matteo@studio.it · new emails'), findsOneWidget);
    expect(
      find.text('matteo@studio.it · replies and forwards'),
      findsOneWidget,
    );
    expect(find.text('matteo@posta.it · replies and forwards'), findsOneWidget);
    // The preview draws it as the email will.
    expect(
      find.descendant(
        of: find.byType(SignatureView),
        matching: find.text('Matteo Neri'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Product designer · Studio Lumen'),
      findsOneWidget,
    );
  });

  testWidgets('typing saves at once', (tester) async {
    final source = await _pump(tester);
    await tester.enterText(_field('Role'), 'Art director');
    await tester.pumpAndSettle();
    final work = (await source.signatures()).firstWhere((s) => s.id == 1);
    expect(work.role, 'Art director');
    expect(find.textContaining('Art director · Studio Lumen'), findsOneWidget);
  });

  testWidgets('templates, accent and the plain-text preview', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Monogram'));
    await tester.pumpAndSettle();
    expect(find.text('MN'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Accent terracotta'));
    await tester.pumpAndSettle();
    final work = (await source.signatures()).first;
    expect(work.template, SignatureTemplate.monogram);
    expect(work.accent, SignatureAccent.terracotta);

    await tester.tap(find.bySemanticsLabel('Text'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('-- \nMatteo Neri\nProduct designer · Studio Lumen'),
      findsOneWidget,
    );
  });

  testWidgets('a job moves to the signature that takes it', (tester) async {
    final source = await _pump(tester);
    // Work takes replies from Short.
    await tester.tap(find.bySemanticsLabel('Replies and forwards'));
    await tester.pumpAndSettle();
    final all = await source.signatures();
    expect(all.firstWhere((s) => s.id == 1).forReplies, isTrue);
    expect(all.firstWhere((s) => s.id == 2).forReplies, isFalse);
    expect(find.text('matteo@studio.it · all'), findsOneWidget);
    expect(find.text('matteo@studio.it · not in use'), findsOneWidget);
  });

  testWidgets('new, rename and delete', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('New signature'));
    await tester.pumpAndSettle();
    expect(await source.signatures(), hasLength(4));
    await tester.enterText(_field('Signature name'), 'Invoices');
    await tester.pumpAndSettle();
    expect((await source.signatures()).last.label, 'Invoices');
    await tester.tap(find.text('Delete signature'));
    await tester.pumpAndSettle();
    expect(await source.signatures(), hasLength(3));
  });

  testWidgets('a logo is shrunk, or refused with the reason', (tester) async {
    final source = await _pump(tester);
    pickLogo = () async =>
        XFile.fromData(Uint8List.fromList(_pixel), name: 'logo.png');
    addTearDown(() => pickLogo = () async => null);
    await tester.tap(find.bySemanticsLabel('With logo'));
    await tester.pumpAndSettle();
    expect(find.text('NO LOGO'), findsOneWidget);

    source.refuseLogo = LogoError.tooBig;
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.textContaining('over 40 KB'), findsOneWidget);

    source.refuseLogo = null;
    await tester.tap(find.text('Upload'));
    await tester.pump();
    final work = (await source.signatures()).first;
    expect(work.logo, _pixel);
    expect(find.text('Remove'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('signatures golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_signatures_$name.png'),
      );
    }, tags: ['golden']);
  }
}
