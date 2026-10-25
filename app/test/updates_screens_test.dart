import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/feedback/shake.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/updates/updates.dart';
import 'package:piuma_mail/updates/whats_new.dart';

import 'support/settle.dart';

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

const _notes = '''
## New
- Not spam in the spam folder, and Spam under each account.
- Attachments that can run ask before they open.
- A warning when a sender isn't who they say.

## Fixed
- The first email opened after a cold start no longer pauses.
- Notifications on Windows show the right name.
''';

UpdateRelease _release(String version) =>
    UpdateRelease(version: version, notes: _notes, size: BigInt.from(43e6));

void _use(Updates u) {
  Updates.use(u);
  addTearDown(() => Updates.use(null));
}

Future<void> _inbox(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1440, 900);
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
}

Future<void> _help(WidgetTester tester, {bool dark = false}) async {
  Shake.availableOverride = () async => false;
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
        section: SettingsSection.help,
        now: () => _now,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.settleBesideWaves();
}

void main() {
  test('versions read as the app shows its own', () {
    expect(shownVersion('0.1.0-beta.612'), '0.1.0 (612)');
    expect(shownVersion('1.2.0'), '1.2.0');
  });

  testWidgets('nothing about updates shows where the build cannot update', (
    tester,
  ) async {
    await _inbox(tester);
    expect(find.textContaining('Update ready'), findsNothing);
    await _help(tester);
    expect(find.text('Updates'), findsNothing);
  });

  testWidgets('the sidebar says so only once the download is done', (
    tester,
  ) async {
    final u = Updates.fake(
      state: UpdateDownloading(_release('0.1.0-beta.612'), 42),
    );
    _use(u);
    await _inbox(tester);
    expect(find.textContaining('Update ready'), findsNothing);
    u.state.value = UpdateReady(_release('0.1.0-beta.612'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update ready · 0.1.0 (612)'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('Piuma Mail 0.1.0 (612)'), findsOneWidget);
    expect(
      find.text('Attachments that can run ask before they open.'),
      findsOneWidget,
    );
    // Later keeps the line.
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsNothing);
    expect(find.text('Update ready · 0.1.0 (612)'), findsOneWidget);
  });

  testWidgets('after the restart a toast says so, once', (tester) async {
    final u = Updates.fake(updatedTo: _release('0.1.0-beta.612'));
    _use(u);
    await _inbox(tester);
    expect(find.text('Updated to 0.1.0 (612)'), findsOneWidget);
    await tester.tap(find.text("What's new"));
    await tester.pumpAndSettle();
    expect(find.text('Piuma Mail 0.1.0 (612)'), findsOneWidget);
    expect(find.text('Restart now'), findsNothing);
    expect(u.announced, isTrue);
  });

  testWidgets('Settings says where the update stands', (tester) async {
    final u = Updates.fake(
      state: const UpToDate(),
      checkedAt: _now.subtract(const Duration(minutes: 10)),
    );
    _use(u);
    await _help(tester);
    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Checked 10 minutes ago'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    u.state.value = UpdateDownloading(_release('0.1.1-beta.618'), 42);
    await tester.settleBesideWaves();
    expect(find.text('Downloading 0.1.1 · 42%'), findsOneWidget);
    expect(find.text('18 MB of 43 MB'), findsOneWidget);
    u.state.value = const UpdateFailed();
    await tester.pumpAndSettle();
    expect(find.text("Couldn't check"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    u.state.value = UpdateReady(_release('0.1.1-beta.618'));
    await tester.pumpAndSettle();
    expect(find.text('Ready · 0.1.1 (618)'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
    await tester.tap(find.text("See what's new"));
    await tester.pumpAndSettle();
    expect(find.text('Restart now'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('updates goldens $name', (tester) async {
      _use(Updates.fake(state: UpdateReady(_release('0.1.0-beta.612'))));
      await _inbox(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/update_ready_$name.png'),
      );
      await tester.tap(find.text('Update ready · 0.1.0 (612)'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/whats_new_$name.png'),
      );
    });

    testWidgets('updates settings golden $name', (tester) async {
      _use(
        Updates.fake(
          state: UpdateDownloading(_release('0.1.1-beta.618'), 42),
          updatedTo: _release('0.1.0-beta.612'),
        ),
      );
      await _help(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/updates_settings_$name.png'),
      );
    });
  }
}
