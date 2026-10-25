import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/l10n/app_localizations.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/calendars_page.dart';
import 'package:piuma_mail/settings/settings_screen.dart';

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  List<CalendarSuggestion> suggestions = const [],
  bool synced = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now)..suggestions = suggestions;
  if (synced) await source.turnOnSync(source.accounts.first.id);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        section: phone ? SettingsSection.accounts : SettingsSection.calendars,
        now: () => _now,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (phone) {
    await tester.tap(find.text('Calendars'));
    await tester.pumpAndSettle();
  }
  return source;
}

Finder _inPage(Finder f) =>
    find.descendant(of: find.byType(CalendarsPage), matching: f);

Future<void> _softShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets('connected calendars show with their switches', (tester) async {
    final source = await _pump(tester);
    expect(_inPage(find.text('iCloud')), findsNothing);
    expect(
      _inPage(find.textContaining('iCloud', findRichText: true)),
      findsWidgets,
    );
    expect(_inPage(find.text('Personal')), findsWidgets);
    expect(_inPage(find.text('Family')), findsOneWidget);
    expect(_inPage(find.text('read-only')), findsNWidgets(2));
    expect(_inPage(find.text('invites')), findsOneWidget);
    expect(_inPage(find.text('2 sources · 3 calendars')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Show availability for Family'));
    await tester.pumpAndSettle();
    final family = (await source.calendarSources()).first.calendars[1];
    expect(family.availability, isFalse);
  });

  testWidgets('a feed says how often it is read', (tester) async {
    await _pump(tester);
    expect(_inPage(find.textContaining('updates daily')), findsOneWidget);
    final l = lookupAppLocalizations(const Locale('en'));
    expect(updatesEvery(l, const Duration(hours: 1)), 'updates every hour');
    expect(updatesEvery(l, const Duration(hours: 6)), 'updates every 6 hours');
    expect(updatesEvery(l, const Duration(days: 7)), 'updates weekly');
    expect(updatesEvery(l, const Duration(days: 3)), 'updates every 3 days');
  });

  testWidgets('with sync on, connections say they sync', (tester) async {
    await _pump(tester, synced: true);
    await tester.ensureVisible(
      find.textContaining('Connections sync across all your devices'),
    );
    expect(
      find.text(
        'Connections sync across all your devices; passwords travel '
        'encrypted and stay in the system keychain.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('dates found in emails can be turned off', (tester) async {
    final source = await _pump(tester);
    final label = 'Suggest adding dates found in emails';
    expect(
      _inPage(find.textContaining(label, findRichText: true)),
      findsOneWidget,
    );
    expect(_inPage(find.text('on-device')), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel(label));
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pumpAndSettle();
    expect((await source.calendarPrefs()).findDates, isFalse);
  });

  testWidgets('a CalDAV account connects with its password', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Connect a calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^CalDAV')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'teo@fastmail.com');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(_inPage(find.text('Connect')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_inPage(find.text('Wrong user name or password.')), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'app-password');
    await tester.tap(_inPage(find.text('Connect')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(source.connected.last, ('teo@fastmail.com', '', 'app-password'));
    expect(
      _inPage(find.textContaining('Fastmail', findRichText: true)),
      findsWidgets,
    );
    expect(_inPage(find.text('Projects')), findsOneWidget);
  });

  testWidgets('Google Calendar subscribes with its secret iCal address', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Connect a calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Google Calendar')));
    await tester.pumpAndSettle();
    expect(find.text('Google Calendar iCal address'), findsOneWidget);
    expect(
      find.textContaining('Secret address in iCal format'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextField).first,
      'https://calendar.google.com/calendar/ical/teo/private/basic.ics',
    );
    await tester.tap(_inPage(find.text('Subscribe')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_inPage(find.text('3 sources · 4 calendars')), findsOneWidget);
  });

  testWidgets('an email account with a calendar is suggested', (tester) async {
    await _pump(
      tester,
      suggestions: const [
        CalendarSuggestion(accountId: 2, email: 'matteo@studio.it'),
      ],
    );
    await tester.tap(find.bySemanticsLabel('Connect a calendar'));
    await tester.pumpAndSettle();
    expect(
      _inPage(find.textContaining('has a calendar too', findRichText: true)),
      findsOneWidget,
    );
    await tester.tap(_inPage(find.text('Connect')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_inPage(find.text('Connected')), findsOneWidget);
    expect(_inPage(find.text('3 sources · 4 calendars')), findsOneWidget);
  });

  testWidgets('invites can go to another calendar; disconnect forgets it', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Connect a calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^CalDAV')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'teo@fastmail.com');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'pw');
    await tester.tap(_inPage(find.text('Connect')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add invites to: Personal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect((await source.calendarPrefs()).defaultCalendar, 300);

    await tester.tap(find.bySemanticsLabel('Disconnect Fastmail'));
    await tester.pumpAndSettle();
    expect(_inPage(find.text('Projects')), findsNothing);
    expect((await source.calendarPrefs()).defaultCalendar, 11);
  });

  testWidgets('on the phone it is a row of Settings', (tester) async {
    await _pump(tester, phone: true);
    expect(find.byType(CalendarsPage), findsOneWidget);
    expect(_inPage(find.text('Family')), findsOneWidget);
    await tester.tap(_inPage(find.text('Connect a calendar')));
    await tester.pumpAndSettle();
    expect(find.text('Subscribe to an .ics URL'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('calendars golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await tester.tap(find.bySemanticsLabel('Connect a calendar'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/calendars_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone calendars golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark, phone: true);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_calendars_$name.png'),
        );
      });
    }, tags: ['golden']);
  }
}
