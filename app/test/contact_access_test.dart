import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/contact_photos.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/switch.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The contacts book as the system would answer, without a system.
class _Book extends ContactsPermission {
  _Book();

  bool asked = false;
  int requests = 0;
  int settings = 0;
  bool granted = false;

  @override
  Future<ContactsAccess> status() async => granted
      ? ContactsAccess.granted
      : asked
      ? ContactsAccess.refused
      : ContactsAccess.notAsked;

  @override
  Future<void> markAsked() async => asked = true;

  @override
  Future<bool> request() async {
    asked = true;
    requests++;
    granted = true;
    return true;
  }

  @override
  Future<void> openSettings() async => settings++;
}

/// Counts the times the contacts' photos are read again.
class _Source extends DemoMailSource {
  _Source() : super(now: _now);
  int rereads = 0;

  @override
  void contactsChanged() {
    rereads++;
    super.contactsChanged();
  }
}

Future<_Source> _inbox(WidgetTester tester, {bool phone = false}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = _Source();
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

Future<void> _openFirst(WidgetTester tester) async {
  await tester.tap(find.byType(InboxRowTile).first);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Back to the list, as the system's Back does on the phone.
Future<void> _close(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    ContactsPermission.current = const ContactsPermission();
    ContactPhotos.debugSupported = null;
  });

  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'desktop';

    testWidgets('the inbox never asks for contacts on its own, $where', (
      tester,
    ) async {
      final book = _Book();
      ContactsPermission.current = book;
      await _inbox(tester, phone: phone);
      expect(find.text('Faces you know'), findsNothing);
      expect(book.requests, 0);
      expect(book.asked, isFalse);
    });

    testWidgets('a first message explains, then asks once, $where', (
      tester,
    ) async {
      final book = _Book();
      ContactsPermission.current = book;
      final source = await _inbox(tester, phone: phone);
      await _openFirst(tester);
      expect(find.text('Faces you know'), findsOneWidget);
      expect(book.requests, 0, reason: 'the explanation comes first');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(book.requests, 1);
      expect(source.rereads, 1);
    });

    testWidgets('Not now is never asked again, $where', (tester) async {
      final book = _Book();
      ContactsPermission.current = book;
      await _inbox(tester, phone: phone);
      await _openFirst(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(book.requests, 0);
      expect(book.asked, isTrue);
      await _close(tester);
      await _openFirst(tester);
      expect(find.text('Faces you know'), findsNothing);
    });
  }

  testWidgets('Settings › Privacy offers it again after a refusal', (
    tester,
  ) async {
    ContactPhotos.debugSupported = true;
    final book = _Book()..asked = true;
    ContactsPermission.current = book;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = _Source();
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => SettingsScreen(
          source: source,
          section: SettingsSection.privacy,
          onBack: () {},
          onAddAccount: () {},
          now: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.text('Photos from your contacts');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    // The switch on the same line as its label.
    final y = tester.getCenter(row).dy;
    final toggle = find.byWidgetPredicate((w) {
      if (w is! PiumaSwitch) return false;
      final box = tester.getRect(find.byWidget(w));
      return (box.center.dy - y).abs() < 24;
    });
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(book.requests, 1);
    expect(source.rereads, 1);
    // On: turning it off is the system's.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(book.settings, 1);
  });
}
