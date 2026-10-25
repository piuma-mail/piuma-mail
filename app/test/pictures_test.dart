import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/pictures.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  DemoMailSource? source,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final demo = source ?? DemoMailSource(now: _now, notifications: true);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: demo, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  // The pictures decode off the test's clock.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  return demo;
}

Finder _pictureOf(String name) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(InboxRowTile)),
  matching: find.descendant(
    of: find.byType(SenderPicture),
    matching: find.byType(Image),
  ),
);

Future<void> _openNotifications(WidgetTester tester) async {
  final tab = find.textContaining('Notifications');
  if (tab.evaluate().isNotEmpty) {
    await tester.tap(tab.first);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('company senders show their picture, people their letters', (
    tester,
  ) async {
    await _pump(tester);
    await _openNotifications(tester);
    await tester.pumpAndSettle();
    expect(_pictureOf('Banca Aurora'), findsOneWidget);
    expect(_pictureOf('Ferrovie Nord'), findsOneWidget);
  });

  testWidgets('with Sender pictures off the letters stay', (tester) async {
    final source = DemoMailSource(now: _now, notifications: true);
    await source.setPrivacySettings(
      source.privacy.copyWith(senderPictures: false),
    );
    await _pump(tester, source: source);
    await _openNotifications(tester);
    expect(
      find.descendant(
        of: find.byType(SenderPicture),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('sender pictures golden $name', (tester) async {
      await _pump(tester, dark: dark, phone: true);
      await _openNotifications(tester);
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_pictures_$name.png'),
      );
    }, tags: ['golden']);
  }
}
