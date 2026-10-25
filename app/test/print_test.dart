import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/print.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The reader alone on [subject], printing into [printed].
Future<void> _pump(
  WidgetTester tester,
  String subject,
  List<PrintEmail> printed, {
  bool phone = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  final rows = await source.page(0, 50);
  final row = rows.firstWhere((r) => r.subject == subject);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: false,
      home: (_, _) => Material(
        child: Reader(
          source: source,
          row: row,
          now: () => _now,
          phone: phone,
          moreMenu: phone ? MenuController() : null,
          onDelete: (_) {},
          printer: (email) async => printed.add(email),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the desktop toolbar has Print, with its key', (tester) async {
    final printed = <PrintEmail>[];
    await _pump(tester, 'Mockup v3 review', printed);
    expect(find.byTooltip('Print… Ctrl+P'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Print…'));
    await tester.pumpAndSettle();
    final email = printed.single;
    expect(email.subject, 'Mockup v3 review');
    final m = email.messages.single;
    expect(m.from, 'Luca Bianchi <luca@studio.it>');
    expect(m.text, contains('compose screen'));
    expect(m.attachments, startsWith('Attachments: '));
  });

  testWidgets('Ctrl+P prints the open email', (tester) async {
    final printed = <PrintEmail>[];
    await _pump(tester, 'Mockup v3 review', printed);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(printed.single.subject, 'Mockup v3 review');
  });

  testWidgets('⌘P prints on the Mac', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final printed = <PrintEmail>[];
    await _pump(tester, 'Mockup v3 review', printed);
    expect(find.byTooltip('Print… ⌘P'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(printed, hasLength(1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a conversation prints every message, oldest first', (
    tester,
  ) async {
    final printed = <PrintEmail>[];
    await _pump(tester, 'Re: Print quote', printed);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final messages = printed.single.messages;
    expect(messages, hasLength(4));
    expect(messages.first.text, startsWith('Hi Sara,'));
    // The quote each reply ends with is folded away, as it shows.
    expect(messages[1].text, isNot(contains('> Could I')));
    expect(messages[1].text, endsWith('Sara'));
  });

  testWidgets('the phone has Print or save as PDF in More', (tester) async {
    final printed = <PrintEmail>[];
    await _pump(tester, 'Mockup v3 review', printed, phone: true);
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print or save as PDF'));
    await tester.pumpAndSettle();
    expect(printed.single.subject, 'Mockup v3 review');
  });

  test('the quote an email ends with is left out', () {
    expect(
      withoutEndQuote('Fine by me.\n\nSara\n\nMatteo wrote:\n> Shall we?\n'),
      'Fine by me.\n\nSara',
    );
    expect(withoutEndQuote('> only a quote'), '> only a quote');
    expect(withoutEndQuote('No quote here.'), 'No quote here.');
  });

  testWidgets('the page builds, with the subject', (tester) async {
    final fonts = await tester.runAsync(geistFonts);
    const email = PrintEmail(
      subject: 'Mockup v3 review',
      fromLabel: 'From',
      toLabel: 'To',
      dateLabel: 'Date',
      messages: [
        PrintMessage(
          from: 'Luca Bianchi <luca@studio.it>',
          to: 'matteo@studio.it',
          date: 'Thu, Oct 15, 2026 at 09:15',
          text: 'Hi Matteo,\n\nI left two comments.\n\nLuca',
          attachments: 'Attachments: mockup-v3.pdf (2.4 MB)',
        ),
      ],
    );
    final bytes = await tester.runAsync(
      () => emailPdf(email, fonts: fonts!).save(),
    );
    final text = latin1.decode(bytes!);
    expect(text, startsWith('%PDF-'));
    expect(text, contains('Mockup v3 review'));
  });
}
