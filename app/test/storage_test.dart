import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/updating.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _settings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
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
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Storage'));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  testWidgets('Settings › Storage shows the room each account takes', (
    tester,
  ) async {
    final source = await _settings(tester);
    expect(find.byType(StoragePage), findsOneWidget);
    final use = await source.storage();
    expect(use.accounts, isNotEmpty);
    expect(find.textContaining(RegExp(r'B on this device$')), findsOneWidget);
    expect(
      find.textContaining('kept for reading offline'),
      findsNWidgets(use.accounts.length),
    );
    // Three months is the default.
    expect(use.keepDays, 90);
    await tester.tap(find.text('1 year'));
    await tester.pumpAndSettle();
    expect((await source.storage()).keepDays, 365);
    await tester.tap(find.text('Always'));
    await tester.pumpAndSettle();
    expect((await source.storage()).keepDays, isNull);
  });

  testWidgets('Clearing an account\'s cached mail asks first', (tester) async {
    final source = await _settings(tester);
    final first = source.accounts.first;
    await tester.tap(find.text('Clear cached mail').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Clear the cached mail of ${first.name}?'),
      findsOneWidget,
    );
    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      (await source.storage()).accounts
          .firstWhere((a) => a.accountId == first.id)
          .cachedBytes,
      greaterThan(0),
    );
    await tester.tap(find.text('Clear cached mail').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear cached mail').last);
    await tester.pumpAndSettle();
    expect(
      (await source.storage()).accounts
          .firstWhere((a) => a.accountId == first.id)
          .cachedBytes,
      0,
    );
    expect(find.textContaining('0 B kept for reading offline'), findsOneWidget);
  });

  testWidgets('Updating your mail says what is going on', (tester) async {
    await tester.pumpWidget(PiumaApp(home: (_, _) => const UpdatingMail()));
    await tester.pump();
    expect(find.text('Updating your mail'), findsOneWidget);
    expect(find.textContaining('It only happens once'), findsOneWidget);
  });
}
