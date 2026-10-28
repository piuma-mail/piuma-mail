import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/design/tokens.g.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/phone_parts.dart';
import 'package:piuma_mail/inbox/swipe.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/search/search_panel.dart';
import 'package:piuma_mail/search/search_start.dart';
import 'package:piuma_mail/inbox/reader.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The inbox on a 390×844 phone, as in the `Phone` mockup.
Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  DemoMailSource? using,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = using ?? DemoMailSource(now: _now);
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

/// Goldens draw real soft shadows, as the phone shows them.
Future<void> _softShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

Finder _row(String subject) => find.descendant(
  of: find.byType(InboxRowTile),
  matching: find.text(subject),
);

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

void main() {
  testWidgets('a narrow window shows the phone inbox', (tester) async {
    await _pump(tester);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);
    expect(find.text('Search 3 accounts'), findsOneWidget);
    expect(find.byType(ComposeFab), findsOneWidget);
    expect(find.byType(SwipeToArchive), findsWidgets);
    expect(_row('Dinner on Friday?'), findsOneWidget);
    // No sidebar and no reading pane beside the list.
    expect(find.byType(Reader), findsNothing);
  });

  testWidgets('scrolled to the end, the last row clears the compose button', (
    tester,
  ) async {
    // A large phone with a gesture bar under the screen.
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
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
    final list = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(MessageList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final rows = find.byType(InboxRowTile);
    expect(rows, findsWidgets);
    final last = rows
        .evaluate()
        .map((e) => tester.getRect(find.byElementPredicate((x) => x == e)))
        .reduce((a, b) => a.bottom > b.bottom ? a : b);
    expect(last.overlaps(tester.getRect(find.byType(ComposeFab))), isFalse);
  });

  testWidgets('a swipe to the right archives, Undo brings it back', (
    tester,
  ) async {
    await _pump(tester);
    await tester.drag(_row('Dinner on Friday?'), const Offset(220, 0));
    await tester.pumpAndSettle();
    // The toast pushes the compose button up.
    expect(tester.widget<ComposeFab>(find.byType(ComposeFab)).raised, isTrue);
    expect(_row('Dinner on Friday?'), findsNothing);
    expect(find.text('Archived'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsOneWidget);
    expect(tester.widget<ComposeFab>(find.byType(ComposeFab)).raised, isFalse);
  });

  testWidgets('Undo goes with its window', (tester) async {
    final source = await _pump(tester);
    await tester.drag(_row('Dinner on Friday?'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    // The servers are told when the window ends, and the toast goes
    // with it, so a late tap can't bring back what has moved.
    await tester.pump(const Duration(seconds: 10));
    expect(source.applied, hasLength(1));
    await tester.tap(find.text('Undo'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
    expect(_row('Dinner on Friday?'), findsNothing);
  });

  testWidgets('the first inbox shows the swipe once', (tester) async {
    final source = DemoMailSource(now: _now, swipeHint: true);
    final band = find.descendant(
      of: find.byType(SwipeToArchive),
      matching: find.text('Archive'),
    );
    await _pump(tester, using: source);
    expect(band, findsNothing);
    // After a pause the newest row slides over the band, and waits.
    await tester.pump(PiumaMotion.reveal);
    await tester.pump(PiumaMotion.move);
    expect(band, findsOneWidget);
    expect(tester.getTopLeft(_row('Dinner on Friday?')).dx, greaterThan(70));
    // Then it slides back.
    await tester.pump(PiumaMotion.move);
    await tester.pump(PiumaMotion.move);
    await tester.pumpAndSettle();
    expect(band, findsNothing);

    // Never again.
    await _pump(tester, using: source);
    await tester.pump(PiumaMotion.reveal + PiumaMotion.move);
    expect(band, findsNothing);
  });

  testWidgets('with reduce motion the swipe hint stays still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, using: DemoMailSource(now: _now, swipeHint: true));
    await tester.pump(PiumaMotion.reveal + PiumaMotion.move);
    expect(
      find.descendant(
        of: find.byType(SwipeToArchive),
        matching: find.text('Archive'),
      ),
      findsNothing,
    );
  });

  testWidgets('a short swipe springs back and archives nothing', (
    tester,
  ) async {
    await _pump(tester);
    await tester.timedDrag(
      _row('Dinner on Friday?'),
      const Offset(60, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsOneWidget);
    expect(find.text('Archived'), findsNothing);
  });

  testWidgets('a short fast flick cannot archive', (tester) async {
    await _pump(tester);
    await tester.fling(_row('Dinner on Friday?'), const Offset(60, 0), 1800);
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsOneWidget);
    expect(find.text('Archived'), findsNothing);
  });

  testWidgets('a diagonal drag scrolls instead of archiving', (tester) async {
    await _pump(tester);
    await tester.timedDrag(
      _row('Dinner on Friday?'),
      const Offset(180, -150),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('a cancelled swipe returns without archiving', (tester) async {
    await _pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(_row('Dinner on Friday?')),
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsOneWidget);
    expect(find.text('Archived'), findsNothing);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(find.byType(Reader), findsOneWidget);
  });

  testWidgets('a row opens full screen, Back returns to the inbox', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(find.byType(Reader), findsOneWidget);
    expect(find.text('Reply to Giulia…'), findsOneWidget);
    expect(find.byType(ComposeFab), findsNothing);

    await tester.tap(find.bySemanticsLabel('Inbox'));
    await tester.pumpAndSettle();
    expect(find.byType(Reader), findsNothing);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);

    // The system Back does the same.
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Reader), findsNothing);
  });

  testWidgets('the quick reply sends a few words, with Undo', (tester) async {
    final source = await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), "I'm in!");
    await tester.tap(find.bySemanticsLabel('Send reply'));
    await tester.pumpAndSettle();
    expect(find.text('Sending…'), findsOneWidget);
    // Still reading, the bar empty again.
    expect(find.byType(Reader), findsOneWidget);
    expect(find.text("I'm in!"), findsNothing);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final draft = source.sent.single;
    expect(draft.subject, 'Re: Dinner on Friday?');
    expect(draft.to.single, contains('giulia'));
    expect(draft.body, startsWith("I'm in!\n\n"));
    expect(draft.body, contains('> Hi Matteo,'));
    expect(draft.inReplyTo, isNotNull);
  });

  testWidgets('the quick reply bar opens the full editor keeping typed words', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'See you at 8!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Reply'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.text('Re: Dinner on Friday?'), findsOneWidget);
    expect(find.textContaining('See you at 8!'), findsOneWidget);
    expect(find.textContaining('> Hi Matteo,'), findsOneWidget);
  });

  testWidgets('More holds Reply and Delete', (tester) async {
    await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.text('Re: Dinner on Friday?'), findsOneWidget);
  });

  testWidgets('Back with More open closes only the menu', (tester) async {
    await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.byType(PhoneInboxHeader), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneInboxHeader), findsOneWidget);
  });

  testWidgets('compose has Cancel and Send on top', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.byType(ComposeFab));
    await tester.pumpAndSettle();
    expect(find.text('New message'), findsOneWidget);
    // No keyboard shortcut on the phone's Send.
    expect(find.text('Ctrl ↩'), findsNothing);
    expect(find.text('⌘↩'), findsNothing);

    await tester.enterText(_field(0), 'luca@studio.it,');
    await tester.enterText(_field(1), 'Hello');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent.single.subject, 'Hello');
    // Once "Sent" goes, the compose button is back in its place.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ComposeFab));
    await tester.pumpAndSettle();
    await tester.enterText(_field(1), 'Draft');
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsNothing);
    expect(find.text('Draft saved'), findsOneWidget);
  });

  testWidgets('a long press picks, then taps pick more', (tester) async {
    await _pump(tester);
    await tester.longPress(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneSelectHeader), findsOneWidget);
    expect(find.byType(PhoneSelectBar), findsOneWidget);
    expect(find.byType(ComposeFab), findsNothing);
    expect(find.bySemanticsLabel('1 of 5 selected'), findsOneWidget);

    await tester.tap(_row('Trip photos'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 of 5 selected'), findsOneWidget);
    // Tapping a picked row lets it go, and opens nothing.
    await tester.tap(_row('Trip photos'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('1 of 5 selected'), findsOneWidget);
    expect(find.byType(Reader), findsNothing);

    await tester.tap(find.bySemanticsLabel('All'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('5 of 5 selected'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('None'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneSelectHeader), findsNothing);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);
  });

  testWidgets('the bar archives the picked rows, Back lets go', (tester) async {
    final source = await _pump(tester);
    await tester.longPress(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(_row('Mockup v3 review'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Read'));
    await tester.pumpAndSettle();
    final rows = await source.page(0, 10);
    expect(
      rows.where((r) => !r.seen && r.subject == 'Dinner on Friday?'),
      isEmpty,
    );
    expect(find.bySemanticsLabel('Unread'), findsOneWidget);

    final tile = find.ancestor(
      of: _row('Dinner on Friday?'),
      matching: find.byType(ClipRect),
    );
    final open = tester
        .getSize(
          find.ancestor(
            of: _row('Dinner on Friday?'),
            matching: find.byType(InboxRowTile),
          ),
        )
        .height;
    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    // Halfway: the rows fold shut before they go, and Undo waits for them.
    expect(tester.getSize(tile.first).height, lessThan(open - 10));
    expect(tester.getSize(tile.first).height, greaterThan(0));
    expect(find.text('2 conversations archived'), findsNothing);
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsNothing);
    expect(_row('Mockup v3 review'), findsNothing);
    expect(find.text('2 conversations archived'), findsOneWidget);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);

    await tester.longPress(_row('Trip photos'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PhoneSelectHeader), findsNothing);
  });

  testWidgets('filter tokens never push the search field over', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Search 3 accounts'));
    await tester.pumpAndSettle();
    Finder chip(String label) => find.descendant(
      of: find.byType(SearchPanel),
      matching: find.text(label),
    );
    Finder field() => find.descendant(
      of: find.byType(SearchPanel),
      matching: find.byType(TextField),
    );
    // The start screen has no filters: they come with the first word.
    expect(chip('Last month'), findsNothing);
    await tester.enterText(field(), 'a');
    await tester.pumpAndSettle();
    await tester.tap(chip('Last month'));
    await tester.pumpAndSettle();
    await tester.tap(chip('Unread'));
    await tester.pumpAndSettle();
    await tester.tap(chip('Account'));
    await tester.pumpAndSettle();
    // The caret opens a picker.
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      field(),
      'a rather long query about the print quote',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Clear search'), findsOneWidget);
  });

  testWidgets('search starts with the inbox account filter', (tester) async {
    await _pump(tester);
    await tester.tap(
      find.bySemanticsLabel('3 accounts, accounts and Settings'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Work, matteo@studio.it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search Work'));
    await tester.pumpAndSettle();
    // The account is where search looks, not a filter: the start screen
    // shows, and the field names the account rather than its operator.
    expect(find.byType(SearchStartView), findsOneWidget);
    expect(find.text('Frequent contacts'), findsOneWidget);
    expect(find.text('account:matteo@studio.it'), findsNothing);
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchPanel),
        matching: find.byType(TextField),
      ),
      'quote',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Searched 1 account'), findsOneWidget);
  });

  testWidgets('search fills the screen, a result opens it', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Search 3 accounts'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchPanel),
        matching: find.byType(TextField),
      ),
      'quote',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Searched 3 accounts'), findsOneWidget);
    // No keyboard hints on the phone.
    expect(find.text('esc'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(SearchPanel),
        matching: find.text('Unread'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('is:unread'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SearchPanel),
        matching: find.text('Unread'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .descendant(
            of: find.byType(SearchPanel),
            matching: find.text('Re: Print quote'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing);
    expect(find.byType(Reader), findsOneWidget);

    // Back returns to the search as it was left.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Reader), findsNothing);
    expect(find.byType(SearchPanel), findsOneWidget);
    expect(find.text('quote'), findsOneWidget);
    expect(find.textContaining('Searched 3 accounts'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);
  });

  testWidgets('Cancel and Back close search', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Search 3 accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing);

    await tester.tap(find.text('Search 3 accounts'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);
  });

  Future<void> settle(WidgetTester tester) async {
    // A page that comes back fades in on the next frame.
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
  }

  testWidgets('the accounts chip opens a sheet with accounts and Settings', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsNothing);
    await tester.tap(
      find.bySemanticsLabel('3 accounts, accounts and Settings'),
    );
    await tester.pumpAndSettle();
    final sheet = find.byType(PhoneAccountsSheet);
    expect(sheet, findsOneWidget);
    for (final name in ['Personal', 'Work', 'iCloud', 'Add account']) {
      expect(
        find.descendant(of: sheet, matching: find.text(name)),
        findsOneWidget,
      );
    }
    // A tap on the scrim closes it.
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('an account in the sheet shows only its mail', (tester) async {
    await _pump(tester);
    Iterable<int> accounts() => tester
        .widgetList<InboxRowTile>(find.byType(InboxRowTile))
        .map((t) => t.row.accountId)
        .toSet();
    expect(accounts(), {1, 2, 3});
    await tester.tap(
      find.bySemanticsLabel('3 accounts, accounts and Settings'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Work, matteo@studio.it'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneAccountsSheet), findsNothing);
    expect(accounts(), {2});
    expect(find.bySemanticsLabel('Work only, accounts and Settings'), findsOne);
    await tester.tap(find.bySemanticsLabel('Work only, accounts and Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('All accounts, 3 inboxes together'));
    await tester.pumpAndSettle();
    expect(accounts(), {1, 2, 3});
  });

  testWidgets('the sheet opens Sent and Archive, Back returns', (tester) async {
    await _pump(tester);
    Future<void> folder(String name) async {
      await tester.tap(
        find.bySemanticsLabel(RegExp(r'accounts and Settings$')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(PhoneAccountsSheet),
          matching: find.text(name),
        ),
      );
      await tester.pumpAndSettle();
    }

    await folder('Sent');
    expect(find.text('Sent'), findsOneWidget);
    expect(_row('Re: Print quote'), findsOneWidget);
    expect(_row('Dinner on Friday?'), findsNothing);
    await folder('Archive');
    expect(find.text('Archive'), findsOneWidget);
    // System Back goes to the inbox before leaving the app.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    expect(_row('Dinner on Friday?'), findsOneWidget);
  });

  testWidgets('Settings opens from the sheet, each section full screen', (
    tester,
  ) async {
    await _pump(tester);
    await _openSettings(tester);
    await settle(tester);
    expect(find.byType(PhoneAccountsSheet), findsNothing);
    expect(find.text('Add account'), findsOneWidget);
    expect(find.bySemanticsLabel('Writing, 3 signatures'), findsOneWidget);
    expect(find.bySemanticsLabel('Notifications, People only'), findsOneWidget);
    expect(find.bySemanticsLabel('Appearance, Light'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await settle(tester);
    expect(find.text('Mail, made light.'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Notifications, People only'));
    await settle(tester);
    expect(find.text('Notify me about'), findsOneWidget);
    await tester.tap(find.text('All'));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await settle(tester);
    expect(find.bySemanticsLabel('Notifications, All'), findsOneWidget);

    // Signatures: the list, then one signature, then back step by step.
    await tester.tap(find.bySemanticsLabel('Writing, 3 signatures'));
    await settle(tester);
    expect(find.text('New signature'), findsOneWidget);
    await tester.tap(find.text('Work').first);
    await settle(tester);
    expect(find.text('Template'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('New signature'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Add account'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);
  });

  testWidgets('compose says Draft saved under the title for a moment', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byType(ComposeFab));
    await tester.pumpAndSettle();
    final saved = find.descendant(
      of: find.byType(ComposePane),
      matching: find.text('Draft saved'),
    );
    await tester.enterText(_field(1), 'Mockups approved');
    expect(saved, findsNothing);
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
    expect(saved, findsOneWidget);
    await tester.pump(PiumaMotion.note);
    await tester.pumpAndSettle();
    expect(saved, findsNothing);
    expect(find.text('New message'), findsOneWidget);
  });

  testWidgets('the compose button writes, Back closes the draft', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byType(ComposeFab));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsNothing);
    expect(find.byType(PhoneInboxHeader), findsOneWidget);
  });

  testWidgets('the header folds into a bar while the list scrolls', (
    tester,
  ) async {
    await _pump(tester);
    final list = find.byType(MessageList);
    double top() => tester.getTopLeft(_row('Dinner on Friday?')).dy;
    final open = top();
    // Scrolling down folds search and the chips away under the bar.
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Search 3 accounts').hitTestable(), findsNothing);
    final bar = tester.getRect(find.byType(PhoneInboxHeader));
    expect(bar.bottom, lessThanOrEqualTo(PhoneFoldingHeader.folded));
    // The bar keeps a way into search.
    expect(
      find.descendant(
        of: find.byType(PhoneInboxHeader),
        matching: find.bySemanticsLabel('Search 3 accounts'),
      ),
      findsWidgets,
    );
    // A little scroll up brings them back, even far down the list.
    await tester.drag(list, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.text('Search 3 accounts').hitTestable(), findsOneWidget);
    // Back at the top it is all as it was.
    await tester.drag(list, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(top(), open);
  });

  testWidgets('let go halfway, the header settles open or shut', (
    tester,
  ) async {
    await _pump(tester);
    final list = find.byType(MessageList);
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    final search = tester.getRect(find.text('Search 3 accounts'));
    final folded = find.text('Search 3 accounts').hitTestable().evaluate();
    // Either all the way open, or folded away: never in between.
    expect(folded.isEmpty || search.top > 70, isTrue);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone folded header golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark);
        await tester.drag(find.byType(MessageList), const Offset(0, -400));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_inbox_folded_$name.png'),
        );
      });
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone inbox golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_inbox_$name.png'),
        );
      });
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone read golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await tester.tap(_row('Dinner on Friday?'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_read_$name.png'),
      );
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone compose golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await tester.tap(find.byType(ComposeFab));
      // The field takes the focus once compose has grown.
      await tester.pump(PiumaMotion.spatial);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_compose_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('phone compose saved golden', (tester) async {
    await _pump(tester);
    await tester.tap(find.byType(ComposeFab));
    await tester.pumpAndSettle();
    await tester.enterText(_field(1), 'Mockups approved');
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_compose_saved_light.png'),
    );
  }, tags: ['golden']);

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone select golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark);
        await tester.longPress(_row('Dinner on Friday?'));
        await tester.pumpAndSettle();
        await tester.tap(_row('Mockup v3 review'));
        await tester.tap(_row('Trip photos'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_select_$name.png'),
        );
      });
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone search golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await tester.tap(find.text('Search 3 accounts'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(SearchPanel),
          matching: find.byType(TextField),
        ),
        'quote',
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_search_$name.png'),
      );
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone settings golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _openSettings(tester);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_settings_$name.png'),
      );
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone accounts sheet golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await tester.tap(
        find.bySemanticsLabel('3 accounts, accounts and Settings'),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_accounts_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('phone swipe hint golden', (tester) async {
    await _softShadows(() async {
      await _pump(tester, using: DemoMailSource(now: _now, swipeHint: true));
      await tester.pump(PiumaMotion.reveal);
      await tester.pump(PiumaMotion.move);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_swipe_hint_light.png'),
      );
      await tester.pump(PiumaMotion.move);
      await tester.pump(PiumaMotion.move);
      await tester.pumpAndSettle();
    });
  }, tags: ['golden']);

  testWidgets('phone swipe golden', (tester) async {
    await _softShadows(() async {
      await _pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(_row('Dinner on Friday?')),
      );
      await gesture.moveBy(const Offset(20, 0));
      // Past the point where letting go archives: snapped to the finger.
      await gesture.moveBy(const Offset(140, 0));
      await tester.pump();
      await tester.pump(PiumaMotion.fast);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_swipe_light.png'),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });
  }, tags: ['golden']);
}

/// Settings on the phone: the accounts chip, then Settings in its sheet.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('3 accounts, accounts and Settings'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(PhoneAccountsSheet),
      matching: find.text('Settings'),
    ),
  );
}
