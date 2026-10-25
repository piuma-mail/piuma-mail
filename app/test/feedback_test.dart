import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/feedback/crash_line.dart';
import 'package:piuma_mail/feedback/help_page.dart';
import 'package:piuma_mail/feedback/report_context.dart';
import 'package:piuma_mail/feedback/report_sheet.dart';
import 'package:piuma_mail/feedback/shake.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/search/command_palette.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/switch.dart';

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _inbox(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  bool crashed = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(1206, 2622)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = phone ? 3 : 1;
  addTearDown(tester.view.reset);
  ReportContext.reset();
  final source = DemoMailSource(
    now: _now,
    crashed: crashed,
    reportHistory: true,
  );
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

/// Settings › Help & feedback on its own; [shake] when the device can
/// tell a shake, as phones can.
Future<DemoMailSource> _help(
  WidgetTester tester, {
  bool phone = true,
  bool dark = false,
  bool? shake,
  ValueChanged<Draft>? onWrite,
}) async {
  final sensor = shake ?? phone;
  Shake.availableOverride = () async => sensor;
  tester.view.physicalSize = phone
      ? const Size(1206, 2622)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = phone ? 3 : 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, reportHistory: true);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        section: SettingsSection.help,
        now: () => _now,
        onWrite: onWrite,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Future<void> _openSheet(WidgetTester tester, String row) async {
  await tester.tap(find.text(row).first);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(ReportSheet), matching: f);

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  setUp(Shake.reset);
  setUp(ReportSheet.forgetDraft);
  tearDown(Shake.reset);

  testWidgets('Shake to report is offered off on a phone with a sensor', (
    tester,
  ) async {
    final source = await _help(tester);
    expect(find.text('Shake to report'), findsOneWidget);
    expect(find.text('Shake the phone on any screen'), findsOneWidget);
    expect(source.shakeToReport.value, isFalse);
    await tester.tap(find.byType(PiumaSwitch));
    await tester.pumpAndSettle();
    expect(source.shakeToReport.value, isTrue);
  });

  testWidgets('no Shake to report without a sensor', (tester) async {
    await _help(tester, shake: false);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(find.text('Shake to report'), findsNothing);
  });

  testWidgets('no Shake to report on the desktop', (tester) async {
    await _help(tester, phone: false);
    expect(find.text('Shake to report'), findsNothing);
  });

  testWidgets('a shake opens the sheet only when it is on', (tester) async {
    final shakes = StreamController<void>.broadcast();
    addTearDown(shakes.close);
    var listening = 0;
    Shake.availableOverride = () async => true;
    Shake.shakesOverride = () => shakes.stream;
    shakes.onListen = () => listening++;
    final source = await _inbox(tester, phone: true);
    // Off at first: the sensor isn't even listened to.
    expect(shakes.hasListener, isFalse);
    shakes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsNothing);

    await source.setShakeToReport(true);
    await tester.pumpAndSettle();
    expect(shakes.hasListener, isTrue);
    shakes.add(null);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsOneWidget);
    // A second shake over the sheet opens nothing more.
    shakes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsOneWidget);

    // In the background the sensor rests.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(shakes.hasListener, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(shakes.hasListener, isTrue);
    expect(listening, 2);

    await source.setShakeToReport(false);
    await tester.pump();
    expect(shakes.hasListener, isFalse);
  });

  testWidgets('Help & feedback lists the reports with where each stands', (
    tester,
  ) async {
    await _help(tester);
    expect(find.byType(HelpPage), findsOneWidget);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(find.text('Suggest an idea'), findsOneWidget);
    expect(find.text('Your reports'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Sending'), findsOneWidget);
    expect(find.text('Sent #12'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('waiting for a network'), findsOneWidget);
    expect(find.textContaining('tap to try again'), findsOneWidget);
  });

  testWidgets(
    'What\x27s new in Help & feedback opens the bundled release notes',
    (tester) async {
      await _help(tester);
      expect(find.text("What's new"), findsOneWidget);
      await tester.tap(find.text("What's new"));
      await tester.pumpAndSettle();
      expect(find.text('Mail, made light'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Mail, made light'), findsNothing);
    },
  );

  testWidgets('a tap on a failed report tries it again', (tester) async {
    await _help(tester);
    await tester.tap(find.text('Dark mode on the lock screen'));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsNothing);
    expect(find.text('Queued'), findsNWidgets(2));
  });

  testWidgets('a long press can send a report by email instead', (
    tester,
  ) async {
    Draft? written;
    await _help(tester, onWrite: (d) => written = d);
    await tester.longPress(find.text('Dark mode on the lock screen'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Send by email instead'));
    await tester.pumpAndSettle();
    expect(written?.to, ['piuma@matteomaraffio.com']);
    expect(written?.subject, contains('Dark mode on the lock screen'));
    expect(find.text('Emailed'), findsOneWidget);
  });

  testWidgets('Delete takes a report off the list', (tester) async {
    await _help(tester);
    await tester.longPress(find.text('Notification shows twice'));
    await tester.pumpAndSettle();
    // Sent already: nothing to try again or email.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Send by email instead'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Notification shows twice'), findsNothing);
  });

  testWidgets('a problem goes with the log and without the screenshot', (
    tester,
  ) async {
    final source = await _help(tester);
    await _openSheet(tester, 'Report a problem');
    expect(find.byType(ReportSheet), findsOneWidget);
    final send = _inSheet(find.text('Send'));
    await tester.tap(send);
    await tester.pumpAndSettle();
    // No title yet: nothing goes.
    expect(source.lastReport, isNull);
    await tester.enterText(_inSheet(find.byType(TextField)).first, 'Crash');
    await tester.enterText(
      _inSheet(find.byType(TextField)).last,
      'Opened Settings',
    );
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsNothing);
    final r = source.lastReport!;
    expect(r.kind, ReportKind.problem);
    expect(r.title, 'Crash');
    expect(r.description, 'Opened Settings');
    expect(r.includeLog, isTrue);
    expect(r.includeScreenshot, isFalse);
    expect(source.lastScreenshot, isNull);
    expect(r.device.map((d) => d.$1), contains('App'));
    expect(find.text('Report queued'), findsOneWidget);
    expect(find.text('Crash'), findsOneWidget);
  });

  testWidgets('a sheet closed by Esc keeps what was written; Cancel forgets', (
    tester,
  ) async {
    await _help(tester);
    await _openSheet(tester, 'Report a problem');
    await tester.enterText(_inSheet(find.byType(TextField)).first, 'Slow');
    await tester.enterText(_inSheet(find.byType(TextField)).last, 'Inbox');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsNothing);

    // Another kind starts empty, and leaves the draft be.
    await _openSheet(tester, 'Suggest an idea');
    expect(find.text('Slow'), findsNothing);
    await tester.tap(_inSheet(find.text('Cancel')));
    await tester.pumpAndSettle();

    await _openSheet(tester, 'Report a problem');
    expect(_inSheet(find.text('Slow')), findsOneWidget);
    expect(_inSheet(find.text('Inbox')), findsOneWidget);
    await tester.tap(_inSheet(find.text('Cancel')));
    await tester.pumpAndSettle();

    await _openSheet(tester, 'Report a problem');
    expect(find.text('Slow'), findsNothing);
  });

  testWidgets('an idea starts without the log', (tester) async {
    final source = await _help(tester);
    await _openSheet(tester, 'Suggest an idea');
    await tester.enterText(_inSheet(find.byType(TextField)).first, 'Pins');
    await tester.pump();
    await tester.tap(_inSheet(find.text('Send')));
    await tester.pumpAndSettle();
    expect(source.lastReport?.kind, ReportKind.idea);
    expect(source.lastReport?.includeLog, isFalse);
  });

  testWidgets('See what\'s sent shows the report as it leaves', (tester) async {
    await _help(tester);
    await _openSheet(tester, 'Report a problem');
    await tester.enterText(_inSheet(find.byType(TextField)).first, 'Slow');
    await tester.pump();
    await tester.tap(_inSheet(find.text("See what's sent")));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsSentPage), findsOneWidget);
    expect(find.textContaining('Problem: Slow'), findsOneWidget);
    expect(find.textContaining('LOGIN <hidden>'), findsOneWidget);
    expect(find.textContaining('Servers: IDLE MOVE (1 of 2)'), findsOneWidget);
  });

  testWidgets('the crash line opens the sheet, and ✕ forgets it', (
    tester,
  ) async {
    final source = await _inbox(tester, crashed: true);
    expect(find.byType(CrashLine), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(CrashLine),
        matching: find.text('Report'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CrashLine), findsNothing);
    expect(source.crashWaiting, isFalse);
  });

  testWidgets('✕ on the crash line sends nothing', (tester) async {
    final source = await _inbox(tester, crashed: true);
    await tester.tap(find.bySemanticsLabel('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(CrashLine), findsNothing);
    expect(source.crashWaiting, isFalse);
    expect(source.lastReport, isNull);
  });

  testWidgets('⌘K finds Report a problem by "bug"', (tester) async {
    await _inbox(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(CommandPalette),
        matching: find.byType(TextField),
      ),
      'bug',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Report a problem'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsOneWidget);
  });

  testWidgets('a report sent by email from Settings opens in compose', (
    tester,
  ) async {
    await _inbox(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help & feedback'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Dark mode on the lock screen'),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send by email instead'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.text('piuma@matteomaraffio.com'), findsWidgets);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('feedback goldens $name', (tester) async {
      await _help(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/feedback_help_phone_$name.png'),
      );
      await _openSheet(tester, 'Report a problem');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/feedback_sheet_phone_$name.png'),
      );
    });

    testWidgets('feedback desktop goldens $name', (tester) async {
      await _help(tester, phone: false, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/feedback_help_desktop_$name.png'),
      );
      await _openSheet(tester, 'Report a problem');
      await tester.enterText(
        _inSheet(find.byType(TextField)).first,
        'Search freezes on long words',
      );
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/feedback_sheet_desktop_$name.png'),
      );
    });
  }
}
