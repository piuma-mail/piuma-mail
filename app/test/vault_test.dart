import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/attachments.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/newsletters.dart';
import 'package:piuma_mail/inbox/phone_parts.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/inbox/vault.dart';
import 'package:piuma_mail/l10n/app_localizations.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/links.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  bool certified = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, certified: certified);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
  return source;
}

/// Lets the screens' motion finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// The desktop board.
Future<DemoMailSource> _openDesktop(
  WidgetTester tester, {
  bool dark = false,
  bool certified = false,
}) async {
  final source = await _pump(tester, dark: dark, certified: certified);
  await tester.tap(find.text('Vault'));
  await _settle(tester);
  return source;
}

final _tile = find.descendant(
  of: find.byType(VaultTile),
  matching: find.text('Vault'),
);

/// Now on the phone.
Future<DemoMailSource> _openPhone(
  WidgetTester tester, {
  bool dark = false,
  bool certified = false,
}) async {
  final source = await _pump(
    tester,
    dark: dark,
    phone: true,
    certified: certified,
  );
  await _reachTile(tester);
  await tester.tap(_tile);
  await _settle(tester);
  return source;
}

/// The chips slide sideways when they do not fit.
Future<void> _reachTile(WidgetTester tester) async {
  for (var i = 0; i < 5 && _tile.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(PhoneChipRow), const Offset(-120, 0));
    await tester.pumpAndSettle();
  }
}

/// A category's page on the phone, from its tile under Now.
Future<void> _openCategory(WidgetTester tester, String name) async {
  final tile = find.descendant(
    of: find.byType(PhoneVault),
    matching: find.text(name),
  );
  await tester.scrollUntilVisible(tile, 200, scrollable: _nowList);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await _settle(tester);
}

final _page = find.byType(PhoneVaultPage);

/// Now's list, on the phone.
final _nowList = find
    .descendant(of: find.byType(PhoneVault), matching: find.byType(Scrollable))
    .first;

Finder _onPage(String text) =>
    find.descendant(of: _page, matching: find.text(text));

MailRow _row(int daysAgo, {String from = '', String subject = ''}) => MailRow(
  accountId: 1,
  mailbox: 'INBOX',
  uid: daysAgo,
  fromName: from,
  fromEmail: '',
  subject: subject,
  preview: '',
  receivedAt: DateTime(
    _now.year,
    _now.month,
    _now.day - daysAgo,
    _now.hour,
    _now.minute,
  ),
  seen: true,
);

final _today = DateTime(_now.year, _now.month, _now.day);
// By the calendar, so a clock change in between keeps the day.
DateTime _in(int days) =>
    DateTime(_today.year, _today.month, _today.day + days);

void main() {
  testWidgets('the sidebar counts only what needs you', (tester) async {
    await _pump(tester);
    // A failed payment, a bill due and a sale to ship.
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('Vault'), matching: find.byType(Row))
            .first,
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the desktop board leads with Now, then the categories', (
    tester,
  ) async {
    await _openDesktop(tester);
    expect(find.byType(VaultBoard), findsOneWidget);
    expect(find.text('3 things need you · a train today'), findsOneWidget);
    expect(find.text('Needs you'), findsWidgets);
    expect(find.text('Payment failed · Notepad Cloud'), findsOneWidget);
    expect(find.text('Update payment'), findsOneWidget);
    expect(find.text('Ship by Saturday'), findsOneWidget);
    expect(find.text('Climbing harness · sold on Mercatino'), findsOneWidget);
    expect(find.text('€64.20'), findsOneWidget);
    // Today: the train home, with its coach, seat and ticket.
    expect(find.text('Train 8134 · Treno Veloce'), findsOneWidget);
    expect(find.text('16:35'), findsOneWidget);
    expect(find.text('Milano Centrale'), findsWidgets);
    expect(find.text('in 6 h'), findsOneWidget);
    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('K7RW2Q'), findsOneWidget);
    expect(find.text('Ticket'), findsOneWidget);
    // The categories, Spending open first: something in it needs you.
    for (final name in [
      'Parcels',
      'Trips',
      'Sales',
      'Subscriptions',
      'Returns & warranty',
      'Deadlines',
      'Bookings',
      'Gift cards & codes',
      'Documents',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Spending'), findsNWidgets(2));
    expect(find.text('October · €213.68 · 3 receipts'), findsOneWidget);
    expect(find.text('Certified mail'), findsNothing);
  });

  testWidgets('Spending is the month: one row per purchase, money in apart', (
    tester,
  ) async {
    await _openDesktop(tester);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Spent · €213.68'), findsOneWidget);
    expect(find.text('Money in · €24.99'), findsOneWidget);
    // The shop's email and PayPal's are one row.
    expect(find.text('Montagna Shop'), findsOneWidget);
    expect(find.text('Softshell jacket · via PayPal'), findsOneWidget);
    expect(find.text('PayPal'), findsNothing);
    expect(find.text('€124.78'), findsOneWidget);
    expect(find.text('Subscriptions · 2'), findsOneWidget);
    expect(find.text('€11.57 a month'), findsOneWidget);
    await tester.tap(find.text('Money in · €24.99'));
    await _settle(tester);
    expect(find.text('KeyStore'), findsOneWidget);
    expect(find.text('+€24.99'), findsOneWidget);
    expect(find.text('Montagna Shop'), findsNothing);
    // September has the plan's receipt.
    await tester.tap(find.bySemanticsLabel('Previous month'));
    await _settle(tester);
    expect(find.text('September 2026'), findsOneWidget);
  });

  testWidgets('Export month saves the PDFs and a CSV for the accountant', (
    tester,
  ) async {
    final source = await _openDesktop(tester);
    await tester.tap(find.text('Export month'));
    await _settle(tester);
    expect(source.saved, ['montagnashop-receipt.pdf']);
    final csv = source.savedText['Spending October 2026.csv']!;
    final lines = csv.trim().split('\n');
    expect(
      lines.first,
      'Date,Who,What,Amount,Currency,Paid via,File,VAT number',
    );
    expect(lines, hasLength(4));
    expect(lines.skip(1).where((line) => line.endsWith(',')), hasLength(2));
    expect(
      lines,
      contains(
        '2026-10-06,Montagna Shop,Softshell jacket,124.78,EUR,PayPal,'
        'montagnashop-receipt.pdf,IT01234567890',
      ),
    );
    expect(
      find.text('Spending October 2026.csv and 1 PDF saved in Downloads'),
      findsOneWidget,
    );
  });

  testWidgets('a bill due can be marked paid, and stays where it was', (
    tester,
  ) async {
    final source = await _openDesktop(tester);
    await tester.tap(find.text('Mark as paid'));
    await _settle(tester);
    expect(source.paidKeys, {'bill:<demo-energia@piuma.mail>': true});
    expect(find.text('€64.20'), findsWidgets);
    expect(find.text('Mark as paid'), findsNothing);
    expect(find.text('2 things need you · a train today'), findsOneWidget);
    // And back.
    await tester.tap(find.bySemanticsLabel('Mark as paid'));
    await _settle(tester);
    expect(source.paidKeys.values.single, isFalse);
    expect(find.text('Mark as paid'), findsOneWidget);
  });

  testWidgets('Download PDF saves the bill and opens it', (tester) async {
    final opened = <String>[];
    final before = openLocalFile;
    openLocalFile = (path) async => opened.add(path);
    addTearDown(() => openLocalFile = before);
    await _openDesktop(tester);
    await tester.tap(find.text('Download PDF'));
    await _settle(tester);
    expect(opened.single, endsWith('energiaverde-october.pdf'));
    expect(find.text('energiaverde-october.pdf saved in Downloads'), findsOne);
  });

  testWidgets('Trips are grouped, the one under way first', (tester) async {
    await _openDesktop(tester);
    await tester.tap(find.text('Trips'));
    await _settle(tester);
    expect(find.text('On a trip now · 1 coming up'), findsOneWidget);
    expect(find.text('Reggio Emilia AV'), findsWidgets);
    expect(find.text('Now · back today'), findsOneWidget);
    expect(find.text('Wed 14 · 10:40 → 11:25 · coach 9, seat 23'), findsOne);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Until 23:45'), findsOneWidget);
    expect(find.text('Today 16:35'), findsOneWidget);
    expect(find.text('Lisbon'), findsOneWidget);
    expect(find.text('Oct 23–26'), findsOneWidget);
    expect(find.text('Flight VL 482 · MXP → LIS'), findsOneWidget);
    expect(find.text('Fri 23, from 15:00 → Mon 26 · 3 nights'), findsOne);
  });

  testWidgets('a card opens its email, and Back returns to the Vault', (
    tester,
  ) async {
    await _openDesktop(tester);
    await tester.tap(find.text('Parcels'));
    await _settle(tester);
    await tester.tap(find.text('Desk lamp'));
    await _settle(tester);
    expect(find.byType(Reader), findsOneWidget);
    expect(find.byType(VaultBoard), findsNothing);
    expect(find.text('Your desk lamp is on its way'), findsWidgets);
    await tester.tap(
      find.descendant(of: find.byType(Reader), matching: find.text('Vault')),
    );
    await _settle(tester);
    expect(find.byType(VaultBoard), findsOneWidget);
  });

  testWidgets('Track parcel opens the parcel, not the email', (tester) async {
    final opened = <Uri>[];
    final before = openExternalLink;
    openExternalLink = (uri) async => opened.add(uri);
    addTearDown(() => openExternalLink = before);
    await _openDesktop(tester);
    await tester.tap(find.text('Parcels'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Track parcel'));
    await _settle(tester);
    expect(
      opened.single.toString(),
      'https://corriererapido.example/track/CR77412093IT',
    );
    expect(find.byType(Reader), findsNothing);
  });

  testWidgets('the empty Vault fits its tile on a phone in every language', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final locale in AppLocalizations.supportedLocales) {
      // The tile at its narrowest: beside both other zones.
      await tester.pumpWidget(
        PiumaApp(
          locale: locale,
          home: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => ZoneStrip(
                zones: [
                  (NewslettersTile(unread: 0, onTap: () {}), 4),
                  (
                    VaultTile(
                      status: AppLocalizations.of(context).vaultAllClear,
                      onTap: () {},
                    ),
                    3,
                  ),
                  (AttachmentsTile(fresh: 0, onTap: () {}), 4),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = await AppLocalizations.delegate.load(locale);
      final line = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(VaultTile),
          matching: find.text(l.vaultAllClear),
        ),
      );
      expect(line.didExceedMaxLines, isFalse, reason: '$locale');
    }
  });

  testWidgets('on the phone the tile tells the first thing that needs you', (
    tester,
  ) async {
    await _pump(tester, phone: true);
    expect(find.byType(VaultTile), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Payment failed')), findsOneWidget);
  });

  testWidgets('Now on the phone, and a tile opens its category', (
    tester,
  ) async {
    await _openPhone(tester);
    expect(find.byType(PhoneVault), findsOneWidget);
    expect(find.text('3 things need you · a train today'), findsOneWidget);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Train 8134 · Treno Veloce'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Desk lamp'),
      300,
      scrollable: _nowList,
    );
    expect(find.text('On the way'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Everything'),
      300,
      scrollable: _nowList,
    );
    expect(find.text('1 parcel delivered this week'), findsOneWidget);
    expect(find.text('Spent in October'), findsOneWidget);
    await _openCategory(tester, 'Bookings');
    expect(_page, findsOneWidget);
    expect(_onPage('Osteria del Ponte'), findsOneWidget);
    expect(_onPage('Notte di jazz'), findsOneWidget);
    // Back, by the page's button and by the system's.
    await tester.tap(_onPage('Vault'));
    await _settle(tester);
    expect(_page, findsNothing);
    expect(find.byType(PhoneVault), findsOneWidget);
    await _openCategory(tester, 'Documents');
    expect(_onPage('Payslip · October'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_page, findsNothing);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(PhoneVault), findsNothing);
    expect(find.byType(VaultTile), findsOneWidget);
  });

  testWidgets('a category page opens its email, and Back returns there', (
    tester,
  ) async {
    await _openPhone(tester);
    await _openCategory(tester, 'Deadlines');
    expect(_onPage('Car insurance'), findsOneWidget);
    await tester.tap(_onPage('Car insurance'));
    await _settle(tester);
    expect(find.byType(Reader), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(Reader), findsNothing);
    expect(_onPage('Car insurance'), findsOneWidget);
  });

  testWidgets('Spending opens Subscriptions from its row', (tester) async {
    await _openPhone(tester);
    await _openCategory(tester, 'Spending');
    expect(_onPage('October · €213.68 · 3 receipts'), findsOneWidget);
    await tester.tap(_onPage('Subscriptions · 2'));
    await _settle(tester);
    expect(_onPage('Notepad Cloud'), findsOneWidget);
    expect(_onPage('€9.99 a month'), findsOneWidget);
    expect(_onPage('Payment failed'), findsOneWidget);
    expect(_onPage('DroneMap'), findsOneWidget);
    expect(_onPage('Renews Nov 1'), findsOneWidget);
  });

  testWidgets('a gift card copies its code', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _openPhone(tester);
    await _openCategory(tester, 'Gift cards & codes');
    expect(_onPage('GC7X-29QP-LM4D · €50.00'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Copy code'));
    await tester.pump();
    expect(copied, 'GC7X-29QP-LM4D');
    expect(find.text('Code copied'), findsOneWidget);
  });

  testWidgets('Directions opens a booking\'s place in maps', (tester) async {
    final opened = <Uri>[];
    final before = openExternalLink;
    openExternalLink = (uri) async => opened.add(uri);
    addTearDown(() => openExternalLink = before);
    await _openPhone(tester);
    await _openCategory(tester, 'Bookings');
    await tester.tap(find.bySemanticsLabel('Directions').first);
    await _settle(tester);
    expect(opened.single.toString(), contains('Via+del+Ponte+3'));
  });

  testWidgets('certified emails have their category, with their receipts', (
    tester,
  ) async {
    final source = await _openPhone(tester, certified: true);
    expect(find.text('4 things need you · a train today'), findsOneWidget);
    await _openCategory(tester, 'Certified mail');
    expect(_onPage('3 certified emails · 1 not delivered'), findsOneWidget);
    expect(_onPage('Formal notice, flat 3B'), findsOneWidget);
    expect(_onPage('casella piena · Mon, Oct 12, 18:05'), findsOneWidget);
    expect(_onPage('To 2 recipients · 1 of 2 delivered'), findsOneWidget);
    expect(_onPage('Accepted Today, 9:12'), findsOneWidget);
    expect(_onPage('Delivered Tue, Oct 13, 10:42'), findsOneWidget);
    // Failures first, then what is on its way, then what arrived.
    final y = [
      'Formal notice, flat 3B',
      'Tax form, second copy',
      'Lease renewal 2027',
    ].map((t) => tester.getTopLeft(_onPage(t)).dy).toList();
    expect(y, [...y]..sort());

    await tester.tap(_onPage('Receipt').first);
    await tester.pump();
    expect(source.savedReceipts.single.subject, 'Tax form, second copy');
    expect(find.text('Receipt saved in Downloads'), findsOneWidget);
  });

  testWidgets('a category emptied while open says so', (tester) async {
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
    await _settle(tester);
    await _reachTile(tester);
    await tester.tap(_tile);
    await _settle(tester);
    await _openCategory(tester, 'Deadlines');
    expect(_onPage('Electricity bill · October'), findsOneWidget);
    // Paid elsewhere: the bill leaves, the insurance stays.
    await source.setVaultPaid('bill:<demo-energia@piuma.mail>', true);
    await _settle(tester);
    expect(_onPage('Electricity bill · October'), findsNothing);
    expect(_onPage('Car insurance'), findsOneWidget);
  });

  group('VaultView', () {
    test('needs come most pressing first', () {
      final v = VaultView([
        VaultCard(row: _row(1), kind: VaultKind.sale, key: 'sale', day: _in(2)),
        VaultCard(row: _row(1), kind: VaultKind.bill, key: 'due', day: _in(10)),
        VaultCard(
          row: _row(1),
          kind: VaultKind.bill,
          key: 'failed',
          status: 'failed',
        ),
        VaultCard(
          row: _row(1),
          kind: VaultKind.shipment,
          key: 'pickup',
          stage: ParcelStage.transit,
          status: 'pickup',
          until: _in(4),
        ),
        VaultCard(
          row: _row(1),
          kind: VaultKind.deadline,
          key: 'soon',
          day: _in(5),
        ),
        VaultCard(
          row: _row(1),
          kind: VaultKind.deadline,
          key: 'later',
          day: _in(40),
        ),
      ], _now);
      expect(v.needs.map((n) => n.kind), [
        VaultNeedKind.failed,
        VaultNeedKind.due,
        VaultNeedKind.toShip,
        VaultNeedKind.pickup,
        VaultNeedKind.deadline,
      ]);
      expect(v.waiting, 5);
      expect(v.deadlines.map((c) => c.key), ['soon', 'later']);
      expect(v.flagged(VaultCategory.parcels), isTrue);
      expect(v.flagged(VaultCategory.sales), isTrue);
    });

    test('done things go after a while, trips once they are past', () {
      final v = VaultView([
        VaultCard(
          row: _row(2),
          kind: VaultKind.shipment,
          key: 'a',
          stage: ParcelStage.delivered,
        ),
        VaultCard(
          row: _row(10),
          kind: VaultKind.shipment,
          key: 'b',
          stage: ParcelStage.delivered,
        ),
        VaultCard(
          row: _row(30),
          kind: VaultKind.flight,
          key: 'past',
          day: DateTime(2026, 9, 14),
          time: '08:00',
          arrives: '10:00',
        ),
        VaultCard(
          row: _row(9),
          kind: VaultKind.flight,
          key: 'today',
          day: _today,
          time: '18:00',
          arrives: '20:00',
        ),
      ], _now);
      expect(v.delivered.map((c) => c.key), ['a']);
      expect(v.trips.single.legs.single.key, 'today');
      expect(v.pastTrips.single.legs.single.key, 'past');
      expect(v.happensToday, isTrue);
    });

    test('a bill with no due day is a receipt, never a bill to pay', () {
      final v = VaultView([
        VaultCard(
          row: _row(3),
          kind: VaultKind.bill,
          key: 'receipt',
          amount: 1200,
          currency: 'EUR',
        ),
        VaultCard(
          row: _row(3),
          kind: VaultKind.bill,
          key: 'dated',
          day: _in(2),
        ),
        VaultCard(
          row: _row(3),
          kind: VaultKind.bill,
          key: 'old due',
          day: _in(-40),
        ),
      ], _now);
      expect(v.toPay.map((c) => c.key), ['dated']);
      expect(v.spent.map((r) => r.card.key), ['receipt']);
    });

    test('parcels that never said they arrived go quiet', () {
      VaultCard parcel(String key, int daysAgo, {int? dueIn}) => VaultCard(
        row: _row(daysAgo),
        kind: VaultKind.shipment,
        key: key,
        stage: ParcelStage.transit,
        day: dueIn == null ? null : _in(dueIn),
      );
      final v = VaultView([
        parcel('ahead', 1, dueIn: 2),
        parcel('late', 5, dueIn: -3),
        parcel('gone', 8, dueIn: -4),
        parcel('undated', 10),
        parcel('old undated', 90),
      ], _now);
      expect(v.parcels.map((c) => c.key), ['late', 'ahead', 'undated']);
    });

    test('legs a few days apart make one trip, in order', () {
      VaultCard leg(String key, int inDays, {String travel = 'train'}) =>
          VaultCard(
            row: _row(1),
            kind: VaultKind.booking,
            key: key,
            travel: travel,
            title: 'A → $key',
            day: _in(inDays),
            time: '09:00',
            arrives: '11:00',
          );
      final v = VaultView([
        leg('back', 5),
        leg('out', 3),
        VaultCard(
          row: _row(1),
          kind: VaultKind.booking,
          key: 'stay',
          travel: 'stay',
          title: 'Hotel',
          day: _in(3),
          time: '15:00',
          until: _in(5),
        ),
        leg('far', 20),
        VaultCard(
          row: _row(1),
          kind: VaultKind.booking,
          key: 'show',
          travel: 'event',
          title: 'Show',
          day: _in(4),
          time: '21:00',
        ),
        VaultCard(
          row: _row(1),
          kind: VaultKind.booking,
          key: 'gone',
          travel: 'train',
          status: 'cancelled',
          day: _in(4),
        ),
      ], _now);
      expect(v.trips, hasLength(2));
      expect(v.trips.first.legs.map((c) => c.key), ['out', 'stay', 'back']);
      expect(v.trips.first.place, 'out');
      expect(v.bookings.single.key, 'show');
      expect(v.upcoming.single.key, 'out');
      expect(v.happensToday, isFalse);
    });

    test('a shop and its payment service are one row, "via PayPal"', () {
      final v = VaultView([
        VaultCard(
          row: _row(2, from: 'Shop'),
          kind: VaultKind.shipment,
          key: 'order',
          title: 'Lamp',
          merchant: 'Shop',
          vatNumber: 'IT01234567890',
          amount: 4990,
          currency: 'EUR',
          stage: ParcelStage.shipped,
        ),
        VaultCard(
          row: _row(2, from: 'PayPal'),
          kind: VaultKind.bill,
          key: 'paypal',
          vatNumber: 'LU999999999',
          amount: 4990,
          currency: 'EUR',
          paid: true,
          file: const MailAttachment(part: 2, name: 'r.pdf', mime: ''),
        ),
        VaultCard(
          row: _row(4, from: 'Shop'),
          kind: VaultKind.bill,
          key: 'refund',
          status: 'refund',
          amount: 1000,
          currency: 'EUR',
        ),
      ], _now);
      final row = v.spent.single;
      expect(row.card.key, 'order');
      expect(row.via, 'PayPal');
      expect(row.card.vatNumber, 'IT01234567890');
      expect(row.card.withPaid(true).vatNumber, 'IT01234567890');
      expect(row.file?.name, 'r.pdf');
      expect(v.moneyIn.single.card.key, 'refund');
      expect(v.total(DateTime(2026, 10)).cents, 4990);
      expect(v.total(DateTime(2026, 10), moneyIn: true).cents, 1000);
    });

    test('charges a month apart make a plan, renewing a month on', () {
      VaultCard charge(int daysAgo) => VaultCard(
        row: _row(daysAgo, from: 'Cloud Studio'),
        kind: VaultKind.bill,
        key: 'c$daysAgo',
        amount: 1525,
        currency: 'USD',
        paid: true,
      );
      final v = VaultView([charge(2), charge(32)], _now);
      final plan = v.plans.single;
      expect(plan.name, 'Cloud Studio');
      expect(plan.period, 'month');
      expect(plan.monthly, 1525);
      expect(plan.renews, DateTime(2026, 11, 13));
      expect(v.monthlyPlans?.cents, 1525);
    });

    test('a plan renewing within a week needs you', () {
      final v = VaultView([
        VaultCard(
          row: _row(3, from: 'DroneMap'),
          kind: VaultKind.bill,
          key: 'r',
          status: 'renews',
          period: 'year',
          amount: 1900,
          currency: 'EUR',
          until: _in(5),
        ),
      ], _now);
      expect(v.needs.single.kind, VaultNeedKind.renews);
      expect(v.flagged(VaultCategory.subscriptions), isTrue);
    });

    test('things bought can go back, then are under warranty', () {
      final v = VaultView([
        VaultCard(
          row: _row(5),
          kind: VaultKind.shipment,
          key: 'jacket',
          title: 'Jacket',
          stage: ParcelStage.delivered,
          returnDays: 100,
          first: _in(-9),
        ),
        VaultCard(
          row: _row(40),
          kind: VaultKind.shipment,
          key: 'memory',
          title: 'Memory',
          stage: ParcelStage.delivered,
          first: _in(-45),
        ),
      ], _now);
      expect(v.returnable.single.card.key, 'jacket');
      expect(v.returnable.single.returnUntil, DateTime(2027, 1, 18));
      expect(v.underWarranty.single.card.key, 'memory');
      expect(v.underWarranty.single.warrantyUntil, DateTime(2028, 8, 31));
    });

    test('a voucher leaves when it ends, and gets a dot before', () {
      final v = VaultView([
        VaultCard(
          row: _row(5),
          kind: VaultKind.voucher,
          key: 'soon',
          until: _in(10),
        ),
        VaultCard(
          row: _row(5),
          kind: VaultKind.voucher,
          key: 'over',
          until: _in(-1),
        ),
      ], _now);
      expect(v.vouchers.single.key, 'soon');
      expect(v.flagged(VaultCategory.vouchers), isTrue);
    });

    test('a category with nothing in it has no tile', () {
      final v = VaultView([
        VaultCard(
          row: _row(5),
          kind: VaultKind.document,
          key: 'doc',
          status: 'payslip',
        ),
      ], _now);
      expect(v.categories, [VaultCategory.documents]);
      expect(VaultView(const [], _now).isEmpty, isTrue);
    });
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('vault golden $name', (tester) async {
      await _openDesktop(tester, dark: dark);
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/vault_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone vault golden $name', (tester) async {
      await _openPhone(tester, dark: dark);
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/phone_vault_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone vault tiles golden $name', (tester) async {
      await _openPhone(tester, dark: dark);
      await tester.scrollUntilVisible(
        find.text('Everything'),
        300,
        scrollable: _nowList,
      );
      await tester.drag(_nowList, const Offset(0, -400));
      await _settle(tester);
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/phone_vault_tiles_$name.png'),
      );
    }, tags: ['golden']);

    for (final page in ['Spending', 'Trips']) {
      testWidgets('phone vault ${page.toLowerCase()} golden $name', (
        tester,
      ) async {
        await _openPhone(tester, dark: dark);
        await _openCategory(tester, page);
        await expectLater(
          find.byType(InboxScreen),
          matchesGoldenFile(
            'goldens/phone_vault_${page.toLowerCase()}_$name.png',
          ),
        );
      }, tags: ['golden']);
    }

    testWidgets('phone certified golden $name', (tester) async {
      await _openPhone(tester, dark: dark, certified: true);
      await _openCategory(tester, 'Certified mail');
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/phone_vault_certified_$name.png'),
      );
    }, tags: ['golden']);
  }
}
