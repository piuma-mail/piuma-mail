import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

const _notice = 'This sender doesn’t read replies';

/// The reader open on the email with [subject], on a desktop or a phone.
Future<DemoMailSource> _open(
  WidgetTester tester,
  String subject, {
  bool phone = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, notifications: true);
  final row = (await source.page(
    0,
    50,
  )).firstWhere((r) => r.subject == subject);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => _now,
        initialSelection: row,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'desktop';

    testWidgets('a no-reply sender gets the notice, and a reply: $where', (
      tester,
    ) async {
      final source = await _open(
        tester,
        'Your parcel is out for delivery',
        phone: phone,
      );
      expect(find.text(_notice), findsOneWidget);
      expect(find.text('Reply to Corriere…'), findsOneWidget);
      // Over the box, not in place of it.
      expect(
        tester.getRect(find.text(_notice)).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Reply to Corriere…')).top),
      );

      await tester.enterText(find.byType(TextField).last, 'Thanks');
      await tester.tap(find.bySemanticsLabel('Send reply'));
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(source.sent.single.to.single, contains('corriererapido'));
    });

    testWidgets('a person gets no notice: $where', (tester) async {
      await _open(tester, 'Dinner on Friday?', phone: phone);
      expect(find.text('Reply to Giulia…'), findsOneWidget);
      expect(find.text(_notice), findsNothing);
    });
  }

  testWidgets('phone no-reply notice golden', (tester) async {
    await _open(tester, 'Your parcel is out for delivery', phone: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_no_reply_notice_light.png'),
    );
  }, tags: ['golden']);
}
