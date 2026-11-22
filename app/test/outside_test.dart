import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/outside/arrivals.dart';
import 'package:piuma_mail/outside/eml_reader.dart';
import 'package:piuma_mail/outside/mailto.dart';
import 'package:piuma_mail/outside/shell.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/links.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<(DemoMailSource, Arrivals)> _inbox(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  final arrivals = Arrivals.test();
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => _now,
        arrivals: arrivals,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return (source, arrivals);
}

/// What compose shows in its fields and chips.
bool _composeShows(WidgetTester tester, String text) =>
    find
        .descendant(of: find.byType(ComposePane), matching: find.text(text))
        .evaluate()
        .isNotEmpty ||
    tester
        .widgetList<EditableText>(
          find.descendant(
            of: find.byType(ComposePane),
            matching: find.byType(EditableText),
          ),
        )
        .any((e) => e.controller.text.contains(text));

void main() {
  setUp(Shell.reset);

  testWidgets('a mailto: link asks which account, then opens compose', (
    tester,
  ) async {
    final (_, arrivals) = await _inbox(tester);
    arrivals.add(
      ComposeArrival(
        link: MailtoLink.parse(
          'mailto:ada@example.com?cc=carol@example.com'
          '&subject=Notes%20on%20the%20engine&body=Hi%20Ada',
        )!,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Write from which account?'), findsOneWidget);
    await tester.tap(find.text('matteo@studio.it').last);
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    final pane = tester.widget<ComposePane>(find.byType(ComposePane));
    expect(pane.initial.accountId, 2);
    expect(pane.initial.to, ['ada@example.com']);
    expect(pane.initial.cc, ['carol@example.com']);
    expect(_composeShows(tester, 'Notes on the engine'), isTrue);
    expect(_composeShows(tester, 'Hi Ada'), isTrue);
  });

  testWidgets('closing the account question writes nothing', (tester) async {
    final (_, arrivals) = await _inbox(tester);
    arrivals.compose();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsNothing);
  });

  testWidgets('a link that comes while writing waits, never replacing it', (
    tester,
  ) async {
    final (_, arrivals) = await _inbox(tester);
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    final first = tester.widget<ComposePane>(find.byType(ComposePane));
    arrivals.mailto(Uri.parse('mailto:bob@example.com'));
    await tester.pumpAndSettle();
    expect(
      find.text('The new message opens when you close this one.'),
      findsOneWidget,
    );
    final still = tester.widget<ComposePane>(find.byType(ComposePane));
    expect(still.key, first.key);
    expect(still.initial, same(first.initial));
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('matteo@posta.it').last);
    await tester.pumpAndSettle();
    final pane = tester.widget<ComposePane>(find.byType(ComposePane));
    expect(pane.initial.to, ['bob@example.com']);
  });

  testWidgets('mailto: links in an email write in Piuma', (tester) async {
    final arrivals = Arrivals.test();
    final got = <Arrival>[];
    arrivals.listen(got.add);
    final before = openMailtoLink;
    addTearDown(() => openMailtoLink = before);
    openMailtoLink = (uri) async => arrivals.mailto(uri);
    expect(await launchMailLink(Uri.parse('mailto:ada@example.com')), isTrue);
    expect((got.single as ComposeArrival).link.to, ['ada@example.com']);
    // Other schemes from an email still never open.
    expect(await launchMailLink(Uri.parse('javascript:alert(1)')), isFalse);
    expect(got, hasLength(1));
  });

  testWidgets('an email file opens read only; images wait; import asks '
      'where', (tester) async {
    final (source, arrivals) = await _inbox(tester);
    arrivals.add(const EmlArrival('/files/notes.eml'));
    await tester.pumpAndSettle();
    expect(find.byType(EmlReader), findsOneWidget);
    expect(find.text('Notes on the analytical engine'), findsOneWidget);
    expect(find.text('Opened from a file'), findsOneWidget);
    expect(find.text('Load images'), findsOneWidget);
    // A file can claim any sender: no "always" for it.
    expect(find.text('Always for this sender'), findsNothing);
    expect(source.fetched, isEmpty);

    await tester.tap(find.text('Import to a folder'));
    await tester.pumpAndSettle();
    expect(find.text('Import into which account?'), findsOneWidget);
    await tester.tap(find.text('matteo@studio.it').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();
    expect(source.importedEml, [('/files/notes.eml', 2, 'INBOX')]);
    expect(find.text('Imported to Inbox'), findsOneWidget);

    await tester.tap(find.text('Note G.pdf'));
    await tester.pumpAndSettle();
    expect(source.saved, ['Note G.pdf']);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(EmlReader), findsNothing);
  });

  testWidgets('a file that is not mail, or too large, says so', (tester) async {
    final (_, arrivals) = await _inbox(tester);
    arrivals.add(const EmlArrival('/files/photo.eml'));
    await tester.pumpAndSettle();
    expect(find.byType(EmlReader), findsNothing);
    expect(find.text('This file isn’t an email Piuma can read.'), findsOne);
    arrivals.add(const EmlArrival('/files/huge.eml'));
    await tester.pumpAndSettle();
    expect(find.text('This email file is too large to open.'), findsOne);
  });

  testWidgets('a file from a network folder is never opened, and says so', (
    tester,
  ) async {
    final (_, arrivals) = await _inbox(tester);
    arrivals.addArgs([r'\\server\share\notes.eml']);
    await tester.pumpAndSettle();
    expect(find.byType(EmlReader), findsNothing);
    expect(
      find.text(
        'Files in network folders don’t open in Piuma. '
        'Copy them to this device first.',
      ),
      findsOne,
    );
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('email file golden $name', (tester) async {
      final (_, arrivals) = await _inbox(tester, dark: dark);
      arrivals.add(const EmlArrival('/files/notes.eml'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/eml_reader_$name.png'),
      );
    });
  }

  group('Settings › This device', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    Future<(DemoMailSource, List<MethodCall>)> settings(
      WidgetTester tester, {
      bool dark = false,
      String state = 'other',
    }) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(Arrivals.channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'defaultMail' => state,
          'makeDefault' => 'unknown',
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(Arrivals.channel, null),
      );
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = DemoMailSource(now: _now);
      await tester.pumpWidget(
        PiumaApp(
          initialDark: dark,
          home: (_, _) => SettingsScreen(
            source: source,
            onBack: () {},
            onAddAccount: () {},
            section: SettingsSection.notifications,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // To the end: "This device", under "New mail" and the rest.
      await tester.scrollUntilVisible(
        find.text(state == 'unavailable' ? 'Due dates' : 'This device'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      return (source, calls);
    }

    testWidgets(
      'keeps running, starts at sign-in, and asks to be the default',
      (tester) async {
        final (source, calls) = await settings(tester);
        expect(find.text('This device'), findsOneWidget);
        expect(find.text('Make Piuma your default mail app'), findsOneWidget);
        // Under "New mail", as the phone's background delivery.
        expect(find.text('With Piuma closed'), findsOneWidget);
        await tester.tap(find.text('Make default'));
        await tester.pumpAndSettle();
        expect(calls.map((c) => c.method), contains('makeDefault'));

        await tester.ensureVisible(find.text('Start when you sign in'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Start when you sign in').last);
        await tester.pumpAndSettle();
        expect(source.desktop.startAtLogin, isTrue);
        expect(calls.where((c) => c.method == 'startAtLogin').last.arguments, {
          'on': true,
        });
        await tester.ensureVisible(
          find.text('Keep running in the background when closed'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .bySemanticsLabel('Keep running in the background when closed')
              .last,
        );
        await tester.pumpAndSettle();
        expect(source.desktop.keepRunning, isFalse);
        final keep = calls.where((c) => c.method == 'keepRunning').last;
        expect((keep.arguments as Map)['on'], isFalse);
        expect((keep.arguments as Map)['quit'], 'Quit Piuma Mail');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('says so when Piuma already is the default', (tester) async {
      await settings(tester, state: 'piuma');
      expect(find.text('Piuma is your default mail app'), findsOneWidget);
      expect(find.text('Make default'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('nothing to offer where the system has no way', (tester) async {
      await settings(tester, state: 'unavailable');
      expect(find.text('Make Piuma your default mail app'), findsNothing);
      // The rest is still there.
      expect(find.text('Start when you sign in'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      testWidgets('golden $name', (tester) async {
        await settings(tester, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/settings_device_$name.png'),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }
  });
}
