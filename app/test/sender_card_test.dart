import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/newsletters.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/inbox/sender_card.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/search/search_panel.dart';
import 'package:piuma_mail/widgets/links.dart';

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  DemoMailSource? source,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  source ??= DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source!, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _row(String subject) => find.descendant(
  of: find.byType(InboxRowTile),
  matching: find.text(subject),
);

Finder _inCard(Finder f) =>
    find.descendant(of: find.byType(SenderCard), matching: f);

Future<void> _openCard(WidgetTester tester) async {
  await tester.tap(_row('Dinner on Friday?'));
  await _settle(tester);
  await tester.tap(find.bySemanticsLabel('Giulia Romano’s card'));
  await _settle(tester);
}

/// Sara wrote several times about the print quote.
Future<void> _openSara(WidgetTester tester) async {
  await tester.tap(_row('Re: Print quote'));
  await _settle(tester);
  await tester.tap(find.bySemanticsLabel('Sara Conti’s card').last);
  await _settle(tester);
}

/// Forma's newsletter, from the Newsletters tile on the phone.
Future<void> _openForma(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NewslettersTile),
      matching: find.text('Newsletters'),
    ),
  );
  await _settle(tester);
  await tester.tap(
    find.text('Why the calmest interfaces are also the fastest'),
  );
  await _settle(tester);
  await tester.tap(find.bySemanticsLabel('Forma’s card').last);
  await _settle(tester);
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

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets('tapping the sender avatar also opens the card', (tester) async {
    await _pump(tester, phone: true);
    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(
      find.descendant(of: find.byType(Reader), matching: find.text('GR')).first,
    );
    await _settle(tester);
    expect(find.byType(SenderCard), findsOneWidget);
  });

  testWidgets('the name opens the card; Mute stops her notifications', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _openCard(tester);
    expect(find.byType(SenderCard), findsOneWidget);
    expect(_inCard(find.text('giulia.romano@posta.it')), findsOneWidget);
    expect(_inCard(find.text('Dinner on Friday?')), findsOneWidget);
    expect(_inCard(find.text('Write')), findsOneWidget);
    expect(_inCard(find.text('All emails')), findsOneWidget);

    await tester.tap(_inCard(find.text('Mute')));
    await tester.pumpAndSettle();
    expect(_inCard(find.text('Muted')), findsOneWidget);
    expect(source.muted, {'giulia.romano@posta.it'});
    await tester.tap(_inCard(find.text('Muted')));
    await tester.pumpAndSettle();
    expect(source.muted, isEmpty);
  });

  testWidgets('Write starts an email to her from the same account', (
    tester,
  ) async {
    await _pump(tester);
    await _openCard(tester);
    await tester.tap(_inCard(find.text('Write')));
    await _settle(tester);
    expect(find.byType(SenderCard), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ComposePane),
        matching: find.text('Giulia Romano'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('matteo@posta.it'), findsWidgets);
  });

  testWidgets('All emails searches her address', (tester) async {
    await _pump(tester);
    await _openCard(tester);
    await tester.tap(_inCard(find.text('All emails')));
    await _settle(tester);
    expect(find.byType(SearchPanel), findsOneWidget);
    expect(find.text('from:giulia.romano@posta.it'), findsOneWidget);
  });

  testWidgets('on the phone the card is a page of its own', (tester) async {
    await _pump(tester, phone: true);
    await _openCard(tester);
    expect(_inCard(find.text('Sender')), findsOneWidget);
    expect(_inCard(find.text('Arrives in Personal')), findsOneWidget);
    expect(_inCard(find.text('CONVERSATIONS')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close card'));
    await _settle(tester);
    expect(find.byType(SenderCard), findsNothing);
  });

  testWidgets('on the phone Block sends her new mail to Trash', (tester) async {
    final source = await _pump(tester, phone: true);
    await _openCard(tester);
    await tester.tap(_inCard(find.text('Block')));
    await tester.pumpAndSettle();
    expect(_inCard(find.text('Blocked')), findsOneWidget);
    expect(source.blocked, {'giulia.romano@posta.it'});
    await tester.tap(_inCard(find.text('Blocked')));
    await tester.pumpAndSettle();
    expect(source.blocked, isEmpty);
  });

  testWidgets('a page unsubscribe the person doesn’t open says nothing '
      'was opened', (tester) async {
    final opened = <Uri>[];
    final before = openExternalLink;
    openExternalLink = (uri) async => opened.add(uri);
    addTearDown(() => openExternalLink = before);
    final beforeHost = linkHostAscii;
    linkHostAscii = (host) => host == 'xn--zz.com' ? null : beforeHost(host);
    addTearDown(() => linkHostAscii = beforeHost);
    final source = await _pump(tester, phone: true);
    source.leaveBy = const UnsubscribeInfo(
      UnsubscribeKind.page,
      'https://xn--zz.com/leave',
    );
    await _openForma(tester);
    await tester.tap(_inCard(find.text('Unsubscribe')));
    await tester.pumpAndSettle();
    expect(find.text('Check this link'), findsOneWidget);
    await tester.tap(find.text('Don’t open'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(
      find.text('Their unsubscribe page is open in the browser'),
      findsNothing,
    );
  });

  testWidgets('a mailto unsubscribe from the card asks with its message', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    source.leaveBy = const UnsubscribeInfo(
      UnsubscribeKind.mail,
      'leave@forma.example',
      'stop',
    );
    await _openForma(tester);
    await tester.tap(_inCard(find.text('Unsubscribe')));
    await tester.pumpAndSettle();
    expect(find.text('To: leave@forma.example'), findsOneWidget);
    expect(find.text('Subject: stop'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(source.unsubscribed, isEmpty);
  });

  testWidgets('a newsletter’s card: how often, Unsubscribe, clear', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    await _openForma(tester);
    expect(_inCard(find.text('Newsletter')), findsOneWidget);
    expect(_inCard(find.text('Write')), findsNothing);
    expect(
      _inCard(find.text('about 2 a month · you open 100%')),
      findsOneWidget,
    );
    expect(_inCard(find.text('Moved to Newsletters')), findsOneWidget);

    await tester.tap(_inCard(find.text('Unsubscribe')));
    await tester.pumpAndSettle();
    expect(source.unsubscribed.single.fromEmail, 'issue@forma.example');
    expect(_inCard(find.text('Yes, clear')), findsOneWidget);
    await tester.tap(_inCard(find.text('Yes, clear')));
    await tester.pumpAndSettle();
    expect(_inCard(find.textContaining('moved to Trash')), findsOneWidget);

    // Back to the inbox for good, and to Newsletters again.
    await tester.tap(_inCard(find.text('Moved to Newsletters')));
    await tester.pumpAndSettle();
    expect(source.zones.last.$2.name, 'inbox');
    expect(_inCard(find.text('Move to Newsletters')), findsOneWidget);
  });

  testWidgets(
    'clearing a newsletter leaves what is in spam and counts the rest',
    (tester) async {
      final source = await _pump(
        tester,
        phone: true,
        source: _AlsoInSpam(now: _now),
      );
      await _openForma(tester);
      await tester.tap(_inCard(find.text('Unsubscribe')));
      await tester.pumpAndSettle();
      await tester.tap(_inCard(find.text('Yes, clear')));
      await tester.pumpAndSettle();
      final trashed = [
        for (final (r, a) in source.applied)
          if (a == MessageAction.delete) r,
      ];
      expect(trashed, isNotEmpty);
      expect(trashed.where((r) => r.mailbox == 'Junk'), isEmpty);
      final n = trashed.length;
      expect(
        _inCard(
          find.text(
            n == 1
                ? 'Unsubscribed · 1 email moved to Trash'
                : 'Unsubscribed · $n emails moved to Trash',
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('the desktop card has no Block', (tester) async {
    await _pump(tester);
    await _openCard(tester);
    expect(_inCard(find.text('Block')), findsNothing);
  });

  testWidgets('someone who writes often has In short', (tester) async {
    await _pump(tester);
    await _openSara(tester);
    expect(
      _inCard(
        find.textContaining(
          'In short: mostly about “Print quote”',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      _inCard(
        find.textContaining(
          'the latest is waiting on your reply.',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('someone who wrote once has none', (tester) async {
    await _pump(tester);
    await _openCard(tester);
    expect(_inCard(find.byType(SenderInShort)), findsNothing);
  });

  testWidgets('a verified sender gets the shield, others none', (tester) async {
    final source = await _pump(tester);
    await _openSara(tester);
    expect(_inCard(find.bySemanticsLabel('Verified sender')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await _settle(tester);
    await _openCard(tester);
    expect(_inCard(find.bySemanticsLabel('Verified sender')), findsNothing);

    // With "Show verified sender" off, no mark at all.
    source.privacy = source.privacy.copyWith(verifiedSender: false);
    await tester.tapAt(const Offset(5, 5));
    await _settle(tester);
    await _openSara(tester);
    expect(_inCard(find.bySemanticsLabel('Verified sender')), findsNothing);
  });

  testWidgets('phone: "Verified" under the address', (tester) async {
    await _softShadows(() async {
      await _pump(tester, phone: true);
      await _openSara(tester);
      expect(_inCard(find.text('Verified')), findsOneWidget);
    });
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('sender card golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _openSara(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sender_card_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone sender card golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark, phone: true);
        await _openSara(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_sender_card_$name.png'),
        );
      });
    }, tags: ['golden']);

    testWidgets('phone newsletter card golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark, phone: true);
        await _openForma(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_newsletter_card_$name.png'),
        );
      });
    }, tags: ['golden']);
  }

  testWidgets('the phone card lists her files and her addresses', (
    tester,
  ) async {
    await _pump(tester, phone: true);
    await _openCard(tester);
    expect(_inCard(find.text('SHARED ATTACHMENTS')), findsOneWidget);
    expect(_inCard(find.text('Pier-sunset.jpg')), findsOneWidget);
    await tester.tap(_inCard(find.text('Attachments')));
    await tester.pumpAndSettle();
    expect(_inCard(find.text('1 ATTACHMENT')), findsOneWidget);
    expect(_inCard(find.text('CONVERSATIONS')), findsNothing);
    await tester.scrollUntilVisible(
      _inCard(find.text('giulia@romanofoto.it')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SenderCard),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(_inCard(find.text('ADDRESSES')), findsOneWidget);
    expect(_inCard(find.text('Work · 4 emails')), findsOneWidget);
    // A tap on a file opens the email it came with.
    await tester.tap(_inCard(find.text('Pier-sunset.jpg')));
    await _settle(tester);
    expect(find.byType(SenderCard), findsNothing);
    expect(find.text('Sunset at the pier'), findsWidgets);
  });

  testWidgets('the phone card ⋯ opens Rules & folders', (tester) async {
    await _pump(tester, phone: true);
    await _openCard(tester);
    await tester.tap(_inCard(find.bySemanticsLabel('More actions')));
    await tester.pumpAndSettle();
    expect(find.text('Copy address'), findsOneWidget);
    await tester.tap(find.text('Rules & folders'));
    await _settle(tester);
    expect(find.byType(SenderCard), findsNothing);
    expect(find.text('Organizing'), findsWidgets);
  });

  testWidgets('phone sender card attachments golden', (tester) async {
    await _softShadows(() async {
      await _pump(tester, phone: true);
      await _openSara(tester);
      await tester.tap(_inCard(find.text('Attachments')));
      await tester.pumpAndSettle();
      await tester.drag(
        find
            .descendant(
              of: find.byType(SenderCard),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_sender_files_light.png'),
      );
    });
  }, tags: ['golden']);
}

/// The demo, with one of the newsletter's emails also found in spam:
/// Delete there would be for good, so clearing leaves it.
class _AlsoInSpam extends DemoMailSource {
  _AlsoInSpam({super.now});

  @override
  Future<SearchResults> search(String query, {int limit = 50}) async {
    final found = await super.search(query, limit: limit);
    if (found.hits.isEmpty) return found;
    final spam = found.hits.first.row.copyWith(mailbox: 'Junk', uid: 99999);
    return SearchResults(
      total: found.total + 1,
      hits: [...found.hits, SearchHit(spam)],
      people: found.people,
      files: found.files,
      searched: found.searched,
      elapsed: found.elapsed,
    );
  }
}
