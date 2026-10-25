import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/notify/background_sheet.dart';
import 'package:piuma_mail/notify/notifier.dart';
import 'package:piuma_mail/settings/settings_screen.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The phone inbox on Android, as in `AndroidBackground`.
Future<DemoMailSource> _pump(
  WidgetTester tester, {
  BackgroundDelivery? delivery,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now)
    ..android = true
    ..delivery = delivery;
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

void main() {
  late int asked;
  setUp(() {
    asked = 0;
    askNoticePermission = () async => asked++;
  });

  testWidgets('Continue asks for notices and picks As it arrives', (
    tester,
  ) async {
    final source = await _pump(tester);
    expect(find.byType(BackgroundSheet), findsOneWidget);
    expect(find.text('New mail as it arrives'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(BackgroundSheet), findsNothing);
    expect(asked, 1);
    expect(source.delivery, BackgroundDelivery.instant);
  });

  testWidgets('Not now picks Every 15 minutes', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(asked, 0);
    expect(source.delivery, BackgroundDelivery.periodic);
  });

  testWidgets('once picked, the sheet does not come back', (tester) async {
    await _pump(tester, delivery: BackgroundDelivery.periodic);
    expect(find.byType(BackgroundSheet), findsNothing);
  });

  testWidgets('away from Android there is nothing to pick', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
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
    expect(find.byType(BackgroundSheet), findsNothing);
    expect(source.delivery, isNull);
  });

  testWidgets('Settings › Notifications changes it', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now)
      ..android = true
      ..delivery = BackgroundDelivery.instant;
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => SettingsScreen(
          source: source,
          onBack: () {},
          onAddAccount: () {},
          section: SettingsSection.notifications,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New mail'), findsOneWidget);
    expect(find.text('As it arrives'), findsOneWidget);
    await tester.tap(find.text('Every 15 minutes'));
    await tester.pumpAndSettle();
    expect(source.delivery, BackgroundDelivery.periodic);
  });

  testWidgets('background sheet golden', (tester) async {
    debugDisableShadows = false;
    try {
      await _pump(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/android_background_sheet_light.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }, tags: ['golden']);

  testWidgets('settings new mail golden', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now)
      ..android = true
      ..delivery = BackgroundDelivery.instant;
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => SettingsScreen(
          source: source,
          onBack: () {},
          onAddAccount: () {},
          section: SettingsSection.notifications,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/android_background_settings_light.png'),
    );
  }, tags: ['golden']);
}
