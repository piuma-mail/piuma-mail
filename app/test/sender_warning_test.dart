import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/sender_warning.dart';
import 'package:piuma_mail/l10n/app_localizations.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/links.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

const _line = "paypa1.com looks like paypal.com, but it's a different address.";

/// "PayPal" writing from paypa1.com, opened.
Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(1440, 900),
  String subject = DemoMailSource.impostorSubject,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, impostor: true);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await tester.tap(find.text(subject).first);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  test('each case says what is wrong in one line', () async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      senderWarningLine(
        l,
        const SenderWarning(
          kind: SenderWarningKind.brand,
          domain: 'fastpay-secure.example',
          brand: 'PayPal',
        ),
      ),
      'The name says PayPal, but the address is at fastpay-secure.example.',
    );
    expect(
      senderWarningLine(
        l,
        const SenderWarning(
          kind: SenderWarningKind.dmarcFailed,
          domain: 'paypal.com',
          dmarcFailed: true,
        ),
      ),
      "This email says it's from paypal.com, but paypal.com didn't send it.",
    );
  });

  testWidgets('the band shows under the sender, the list stays as it is', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(SenderWarningBand), findsOneWidget);
    expect(find.text(_line), findsOneWidget);
    // One row in the list, without a mark of its own.
    expect(find.text(DemoMailSource.impostorSubject), findsNWidgets(2));
  });

  testWidgets('other senders get no band', (tester) async {
    await _pump(tester, subject: 'Mockup v3 review');
    expect(find.byType(SenderWarningBand), findsNothing);
  });

  testWidgets('Details lists what was checked', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('What was checked'), findsOneWidget);
    expect(find.text('mail.paypa1.com'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('paypal.com, 14 emails from it'), findsOneWidget);
  });

  testWidgets('Report spam in the band reports it', (tester) async {
    final source = await _pump(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(SenderWarningBand),
        matching: find.text('Report spam'),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 11));
    expect(source.applied.single.$2, MessageAction.junk);
    await tester.pumpAndSettle();
  });

  testWidgets('every link in it asks first', (tester) async {
    final opened = <Uri>[];
    final before = openExternalLink;
    openExternalLink = (uri) async => opened.add(uri);
    addTearDown(() => openExternalLink = before);
    await _pump(tester);
    await tester.tap(find.textContaining('Confirm my details'));
    await tester.pumpAndSettle();
    expect(find.text('Check this link'), findsOneWidget);
    expect(
      find.text(
        'This email may not be from who it says. The link goes to paypa1.com.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Don’t open'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets('on the phone, Details and Report spam sit under the line', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));
    expect(find.text(_line), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Details')).dy,
      greaterThan(tester.getTopLeft(find.text(_line)).dy),
    );
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('What was checked'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final phone in [false, true]) {
      final name =
          'sender_warning_${phone ? 'phone' : 'desktop'}_${dark ? 'dark' : 'light'}';
      testWidgets(name, (tester) async {
        await _pump(
          tester,
          dark: dark,
          size: phone ? const Size(390, 844) : const Size(1440, 900),
        );
        await expectLater(
          find.byType(PiumaApp),
          matchesGoldenFile('goldens/$name.png'),
        );
      });
    }
  }

  testWidgets('sender_details_desktop_light', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PiumaApp),
      matchesGoldenFile('goldens/sender_details_desktop_light.png'),
    );
  });
}
