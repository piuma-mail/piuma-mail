import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/mail_pager.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The inbox on a 390×844 phone, with the rows' subjects in list order.
Future<(DemoMailSource, List<String>)> _pump(
  WidgetTester tester, {
  bool reduce = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(tester.view)
          .copyWith(disableAnimations: reduce),
      child: PiumaApp(
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  final subjects = [
    for (final t in tester.widgetList<InboxRowTile>(find.byType(InboxRowTile)))
      t.row.subject,
  ];
  return (source, subjects);
}

/// The subject of the email showing.
String _showing(WidgetTester tester) =>
    tester.widget<MailPager>(find.byType(MailPager)).row.subject;

Future<void> _open(WidgetTester tester, String subject) async {
  await tester.tap(
    find.descendant(
      of: find.byType(InboxRowTile),
      matching: find.text(subject),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a swipe left opens the next email, right the one before', (
    tester,
  ) async {
    final (_, subjects) = await _pump(tester);
    await _open(tester, subjects[1]);
    expect(_showing(tester), subjects[1]);

    await tester.fling(find.byType(MailPager), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(_showing(tester), subjects[2]);
    expect(find.byType(Reader), findsOneWidget);

    await tester.fling(find.byType(MailPager), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(_showing(tester), subjects[1]);
  });

  testWidgets('the next email shows beside it while the finger moves', (
    tester,
  ) async {
    final (_, subjects) = await _pump(tester);
    await _open(tester, subjects[0]);
    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(find.byType(Reader), findsNWidgets(2));
    // Not far enough: it springs back and stays.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_showing(tester), subjects[0]);
    expect(find.byType(Reader), findsOneWidget);
  });

  testWidgets('the first email has nothing before it', (tester) async {
    final (_, subjects) = await _pump(tester);
    await _open(tester, subjects[0]);
    await tester.fling(find.byType(MailPager), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(_showing(tester), subjects[0]);
  });

  testWidgets('the email swiped to is read', (tester) async {
    final (_, subjects) = await _pump(tester);
    final rows = [
      for (final t in tester.widgetList<InboxRowTile>(
        find.byType(InboxRowTile),
      ))
        t.row,
    ];
    final unread = rows.indexWhere((r) => !r.seen, 1);
    expect(unread, greaterThan(0));
    await _open(tester, subjects[unread - 1]);
    await tester.fling(find.byType(MailPager), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    final showing = tester.widget<MailPager>(find.byType(MailPager)).row;
    expect(showing.subject, subjects[unread]);
    expect(showing.seen, isTrue);
    // The list says so too.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<InboxRowTile>(find.byType(InboxRowTile))
          .firstWhere((t) => t.row.key == showing.key)
          .row
          .seen,
      isTrue,
    );
  });

  testWidgets('with reduce motion it turns at once', (tester) async {
    final (_, subjects) = await _pump(tester, reduce: true);
    await _open(tester, subjects[1]);
    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();
    // Nothing follows the finger.
    expect(find.byType(Reader), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(_showing(tester), subjects[2]);
  });
}
