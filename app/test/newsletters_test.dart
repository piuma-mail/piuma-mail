import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/phone_parts.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_body.dart';
import 'package:piuma_mail/inbox/newsletters.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

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
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

/// Desktop Newsletters with the newest issue open, as `DesktopEdicola`.
Future<DemoMailSource> _openDesktop(
  WidgetTester tester, {
  bool dark = false,
}) async {
  final source = await _pump(tester, dark: dark);
  await tester.tap(find.text('Newsletters'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.text('Why the calmest interfaces are also the fastest'),
  );
  await tester.pumpAndSettle();
  return source;
}

const _forma = 'Why the calmest interfaces are also the fastest';

final _tile = find.descendant(
  of: find.byType(NewslettersTile),
  matching: find.text('Newsletters'),
);

void main() {
  testWidgets('newsletters have their own place in the sidebar', (
    tester,
  ) async {
    await _pump(tester);
    // Not in the inbox.
    expect(find.text(_forma), findsNothing);
    await tester.tap(find.text('Newsletters'));
    await tester.pumpAndSettle();
    expect(find.byType(NewsletterList), findsOneWidget);
    expect(find.text('3 reads · 23 min'), findsOneWidget);
    expect(find.text('8 min · today'), findsOneWidget);
    expect(find.text('6 min · yesterday'), findsOneWidget);
    expect(find.text('FORMA'), findsNWidgets(2));
  });

  testWidgets('an issue opens as an article, and can wait for later', (
    tester,
  ) async {
    final source = await _openDesktop(tester);
    expect(find.text('8 min read · arrived at 07:02'), findsOneWidget);
    expect(find.textContaining('Every extra element'), findsOneWidget);
    // Opening it read it; Read later keeps it unread.
    expect(source.seenSet.last.$2, isTrue);
    expect(find.text('2 reads · 15 min'), findsOneWidget);
    await tester.tap(find.text('Read later'));
    await tester.pumpAndSettle();
    expect(source.seenSet.last.$1.subject, _forma);
    expect(source.seenSet.last.$2, isFalse);
    expect(find.text('Kept as unread'), findsOneWidget);
    expect(find.text('3 reads · 23 min'), findsOneWidget);
  });

  testWidgets('Unsubscribe asks first, then leaves with one request', (
    tester,
  ) async {
    final source = await _openDesktop(tester);
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribe from Forma?'), findsOneWidget);
    expect(find.textContaining('one request to stop'), findsOneWidget);
    expect(source.unsubscribed, isEmpty);
    await tester.tap(find.text('Unsubscribe').last);
    await tester.pumpAndSettle();
    expect(source.unsubscribed.single.subject, _forma);
    expect(find.text('Unsubscribed from Forma'), findsOneWidget);
  });

  testWidgets('a sender can always go to the Inbox instead', (tester) async {
    final source = await _openDesktop(tester);
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always in Inbox'));
    await tester.pumpAndSettle();
    expect(source.zones.single, ('issue@forma.example', MailFolder.inbox));
    expect(source.unsubscribed, isEmpty);
    expect(find.text('Mail from Forma now goes to the Inbox'), findsOneWidget);
    expect(
      find.text('From the archive: the Swiss grid, clearly explained'),
      findsNothing,
    );
  });

  testWidgets('a trusted sender\'s issues get their first photo as cover', (
    tester,
  ) async {
    RemoteImages.clear();
    final source = await _pump(tester);
    await source.setTrusted('issue@forma.example', true);
    await tester.tap(find.text('Newsletters'));
    await tester.pumpAndSettle();
    // The picture comes from the network: a moment later.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Both Forma issues, nobody else's: the others keep their tint.
    expect(
      find.descendant(
        of: find.byType(NewsletterPicture),
        matching: find.byType(Image),
      ),
      findsNWidgets(2),
    );
    expect(source.fetched, hasLength(1));
  });

  testWidgets('without trust there are no covers and nothing is fetched', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.text('Newsletters'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(NewsletterPicture),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    expect(source.fetched, isEmpty);
  });

  testWidgets('any email whose list can be left has Unsubscribe in More', (
    tester,
  ) async {
    final source = await _pump(tester);
    Future<void> more() async {
      await tester.tap(find.bySemanticsLabel('More actions').last);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Dinner on Friday?').first);
    await tester.pumpAndSettle();
    await more();
    expect(find.text('Unsubscribe'), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    source.leavable = (row) => row.subject == 'Dinner on Friday?';
    await tester.tap(find.text('Cellar keys').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dinner on Friday?').first);
    await tester.pumpAndSettle();
    await more();
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsubscribe').last);
    await tester.pumpAndSettle();
    expect(source.unsubscribed.single.subject, 'Dinner on Friday?');
  });

  testWidgets('on the phone, Unsubscribe is in the reader\'s More too', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    source.leavable = (row) => row.subject == 'Dinner on Friday?';
    await tester.tap(find.text('Dinner on Friday?').first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More actions').last);
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribe'), findsOneWidget);
  });

  testWidgets('on the phone a tile opens Newsletters, and Back returns', (
    tester,
  ) async {
    await _pump(tester, phone: true);
    expect(find.byType(NewslettersTile), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Newsletters')), findsWidgets);
    // The chips slide sideways when they do not fit.
    for (var i = 0; i < 5 && _tile.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(PhoneChipRow), const Offset(-120, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(_tile);
    await tester.pumpAndSettle();
    expect(find.byType(PhoneNewsletters), findsOneWidget);
    expect(find.text('3 reads · 23 minutes in all'), findsOneWidget);
    final note = find.text(
      'Read more than 7 days ago? They archive themselves',
    );
    await tester.scrollUntilVisible(note, 200);
    expect(note, findsOneWidget);
    await tester.scrollUntilVisible(find.text(_forma), -200);
    await tester.tap(find.text(_forma));
    await tester.pumpAndSettle();
    expect(find.byType(Reader), findsOneWidget);
    // Back goes to Newsletters, then to the inbox.
    await tester.tap(
      find.descendant(
        of: find.byType(Reader),
        matching: find.text('Newsletters'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PhoneNewsletters), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(PhoneNewsletters),
        matching: find.text('Inbox'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewslettersTile), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('newsletters golden $name', (tester) async {
      await _openDesktop(tester, dark: dark);
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/newsletters_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone newsletters golden $name', (tester) async {
      await _pump(tester, dark: dark, phone: true);
      // The chips slide sideways when they do not fit.
      for (var i = 0; i < 5 && _tile.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(find.byType(PhoneChipRow), const Offset(-120, 0));
        await tester.pumpAndSettle();
      }
      await tester.tap(_tile);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/phone_newsletters_$name.png'),
      );
    }, tags: ['golden']);
  }
}
