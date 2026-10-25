import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/attachment_chip.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Future<void> _openReview(WidgetTester tester) async {
  await tester.tap(find.text('Mockup v3 review'));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _inCompose(Finder f) =>
    find.descendant(of: find.byType(ComposePane), matching: f);

Finder _field(int i) => _inCompose(find.byType(TextField)).at(i);

String _text(WidgetTester tester, int i) =>
    tester.widget<TextField>(_field(i)).controller!.text;

void main() {
  testWidgets('Forward: Fwd:, the forwarded block and the files', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _openReview(tester);
    await tester.tap(find.bySemanticsLabel('Forward'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(_inCompose(find.text('Forward')), findsOneWidget);
    expect(_text(tester, 0), isEmpty);
    expect(_text(tester, 1), 'Fwd: Mockup v3 review');
    final body = _text(tester, 2);
    expect(body, startsWith('\n\n---------- Forwarded message ----------\n'));
    expect(
      body,
      contains('\nTo: matteo@studio.it\nSubject: Mockup v3 review\n'),
    );
    expect(body, contains('Date: Thursday, October 15, 2026 at '));
    expect(_inCompose(find.byType(AttachmentChip)), findsNWidgets(2));

    // × leaves a file out.
    await tester.tap(find.bySemanticsLabel('Remove compose-notes.png'));
    await tester.pumpAndSettle();
    await tester.enterText(_field(0), 'sara@studio.it,');
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final sent = source.sent.single;
    expect(sent.subject, 'Fwd: Mockup v3 review');
    expect(sent.forward, isTrue);
    expect(sent.inReplyTo, isNull);
    expect(sent.files.map((f) => f.name), ['mockup-v3.pdf']);
    expect(sent.files.single.data.length, 2400000);
  });

  testWidgets('F forwards the open message', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Dinner on Friday?'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(_text(tester, 1), 'Fwd: Dinner on Friday?');
  });

  testWidgets('the phone has Forward in More', (tester) async {
    await _pump(tester, size: const Size(390, 844));
    await tester.tap(find.text('Mockup v3 review'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_more_forward_light.png'),
    );
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(_text(tester, 1), 'Fwd: Mockup v3 review');
  }, tags: ['golden']);

  testWidgets('forward golden', (tester) async {
    await _pump(tester);
    await _openReview(tester);
    await tester.tap(find.bySemanticsLabel('Forward'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compose_forward_light.png'),
    );
  }, tags: ['golden']);
}
