import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/service_states.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The demo's Work account.
const _work = 2;

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  required Size size,
  bool dark = false,
  SyncStatus status = SyncStatus.idle,
  DateTime Function()? clock,
  DemoMailSource? using,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = (using ?? DemoMailSource(now: _now))..status.value = status;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: clock ?? () => _now,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  if (status.phase == SyncPhase.downloading) {
    // The placeholder rows breathe for as long as the download runs.
    await tester.pump(const Duration(seconds: 1));
  } else {
    await tester.pumpAndSettle();
  }
  return source;
}

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);

const _offline = SyncStatus(SyncPhase.offline, offline: true);
const _failed = SyncStatus(SyncPhase.signInFailed, failed: [_work]);
const _syncing = SyncStatus(
  SyncPhase.downloading,
  done: 2340,
  total: 8100,
  downloading: _work,
);

/// A first download two emails in: the inbox has only its newest two.
class _FirstRows extends DemoMailSource {
  _FirstRows() : super(now: _now);

  static const _got = 2;

  @override
  Future<List<int>> countsBetween(
    List<DateTime> edges, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  }) async {
    var left = _got;
    return [
      for (final n in await super.countsBetween(
        edges,
        folder: folder,
        account: account,
        mailbox: mailbox,
        tab: tab,
        unread: unread,
      ))
        if (n < left) (left -= n, n).$2 else (left, left = 0).$1,
    ];
  }

  @override
  Future<List<MailRow>> page(
    int offset,
    int limit, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  }) async => [
    ...await super.page(
      offset,
      limit,
      folder: folder,
      account: account,
      mailbox: mailbox,
      tab: tab,
      unread: unread,
    ),
  ].take(_got - offset).toList();
}

void main() {
  testWidgets('offline shows the strip at the top', (tester) async {
    final source = await _pump(tester, size: _phone, status: _offline);
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(
      find.textContaining('You’re offline', findRichText: true),
      findsOneWidget,
    );
    // Back online, the strip goes.
    source.status.value = SyncStatus.idle;
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsNothing);
  });

  testWidgets('a first download shows its progress', (tester) async {
    await _pump(tester, size: _phone, status: _syncing);
    expect(
      find.textContaining('Downloading Work', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('2,340', findRichText: true), findsOneWidget);
  });

  testWidgets('a first download says how long is left', (tester) async {
    var now = _now;
    final source = await _pump(
      tester,
      size: _phone,
      status: _syncing,
      clock: () => now,
      using: _FirstRows(),
    );
    expect(find.byType(SyncPlaceholder), findsWidgets);
    expect(find.text('Search 3 accounts · Work syncing'), findsOneWidget);
    expect(find.textContaining('about'), findsNothing);
    // 580 more in 30 seconds: 5,180 to go is about 4 and a half minutes.
    now = _now.add(const Duration(seconds: 30));
    source.status.value = const SyncStatus(
      SyncPhase.downloading,
      done: 2920,
      total: 8100,
      downloading: _work,
    );
    await tester.pump();
    expect(find.text('about 4 min'), findsOneWidget);

    // Done, the placeholders go.
    source.status.value = SyncStatus.idle;
    await tester.pumpAndSettle();
    expect(find.byType(SyncPlaceholder), findsNothing);
    expect(find.textContaining('syncing'), findsNothing);
  });

  testWidgets('the rows of an account that can’t connect fade back', (
    tester,
  ) async {
    await _pump(tester, size: _phone, status: _failed);
    Iterable<double> opacities(String name) => tester
        .widgetList<AnimatedOpacity>(
          find.ancestor(
            of: find.text(name),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .map((o) => o.opacity);
    // Luca writes to Work, Giulia to Personal.
    expect(opacities('Luca Bianchi'), contains(0.42));
    expect(opacities('Giulia Romano'), everyElement(1));
  });

  testWidgets('an account that can’t sign in asks for its password', (
    tester,
  ) async {
    await _pump(tester, size: _phone, status: _failed);
    expect(find.text('The Work account can’t connect'), findsOneWidget);
    expect(find.textContaining('matteo@studio.it'), findsOneWidget);

    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Work'), findsOneWidget);

    // A wrong password says so and keeps the sheet open.
    await tester.enterText(find.byType(TextField).last, 'old-password');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Work'), findsOneWidget);
    expect(find.textContaining('password'), findsWidgets);

    // The right one closes it, and the card goes.
    await tester.enterText(find.byType(TextField).last, 'carta-120-opaca');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Work'), findsNothing);
    expect(find.byType(SignInCard), findsNothing);
  });

  testWidgets('Later puts the card off', (tester) async {
    await _pump(tester, size: _phone, status: _failed);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInCard), findsNothing);
  });

  testWidgets('desktop shows the card and the strip above the list', (
    tester,
  ) async {
    final source = await _pump(tester, size: _desktop, status: _failed);
    expect(find.byType(SignInCard), findsOneWidget);
    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Work'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    source.status.value = _offline;
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(find.byType(SignInCard), findsNothing);
  });

  testWidgets('an empty inbox is all caught up', (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PiumaApp(home: (_, _) => const Scaffold(body: AllCaughtUp())),
    );
    await tester.pumpAndSettle();
    expect(find.text('All caught up'), findsOneWidget);
  });

  Future<DemoMailSource> pumpSnoozed(
    WidgetTester tester, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now, snoozedMail: true);
    final snoozed = await source.page(0, 50, folder: MailFolder.snoozed);
    await tester.pumpWidget(
      PiumaApp(
        initialDark: dark,
        home: (_, _) => Scaffold(
          body: AllCaughtUp(
            snoozed: snoozed,
            accountOf: (id) => source.accounts.firstWhere((a) => a.id == id),
            now: () => _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return source;
  }

  testWidgets('all caught up shows what is snoozed, on request', (
    tester,
  ) async {
    await pumpSnoozed(tester);
    expect(find.text('Show Snoozed (2)'), findsOneWidget);
    expect(find.text('tomorrow 9:00'), findsNothing);
    await tester.tap(find.text('Show Snoozed (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Hide Snoozed'), findsOneWidget);
    expect(find.text('tomorrow 9:00'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
  });

  testWidgets('an empty inbox with nothing snoozed has no Show Snoozed', (
    tester,
  ) async {
    await tester.pumpWidget(
      PiumaApp(home: (_, _) => const Scaffold(body: AllCaughtUp())),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Snoozed'), findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('all caught up with Snoozed golden $name', (tester) async {
      await pumpSnoozed(tester, dark: dark);
      await tester.tap(find.text('Show Snoozed (2)'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/states_empty_snoozed_$name.png'),
      );
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    for (final (state, status) in [
      ('offline', _offline),
      ('error', _failed),
      ('sync', _syncing),
    ]) {
      testWidgets('phone $state golden $name', (tester) async {
        await _pump(
          tester,
          size: _phone,
          dark: dark,
          status: status,
          using: state == 'sync' ? _FirstRows() : null,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/states_${state}_$name.png'),
        );
      }, tags: ['golden']);
    }
  }
  testWidgets('desktop error golden', (tester) async {
    await _pump(tester, size: _desktop, status: _failed);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/states_desktop_error_light.png'),
    );
  }, tags: ['golden']);
}
