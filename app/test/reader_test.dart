import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/design/theme.dart';
import 'package:piuma_mail/inbox/images_bar.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_body.dart';
import 'package:piuma_mail/inbox/original_view.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/readable.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/button.dart';
import 'package:piuma_mail/widgets/links.dart';
import 'package:piuma_mail/widgets/switch.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RemoteImages.clear();
  final source = DemoMailSource(now: _now, newsletter: true);
  final first = (await source.page(0, 1)).first;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => _now,
        initialSelection: first,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(PrivacySheet), matching: f);

void main() {
  testWidgets('remote images wait, trackers are stopped', (tester) async {
    final source = await _pump(tester);
    expect(find.text('New autumn arrivals'), findsWidgets);
    expect(find.text('Images blocked · 3 trackers stopped'), findsOneWidget);
    expect(find.textContaining('ceramics handmade in Faenza'), findsOneWidget);
    expect(find.bySemanticsLabel('Folded rust-colored throw'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(source.fetched, isEmpty);
  });

  testWidgets('plain messages have no privacy chip', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyChip), findsNothing);
    expect(find.textContaining('bring the new board game'), findsOneWidget);
  });

  testWidgets('the sheet lists what was stopped and loads images once', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.byType(PrivacyChip));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('Privacy for this message')), findsOneWidget);
    expect(_inSheet(find.text('Open pixel')), findsOneWidget);
    expect(_inSheet(find.text('lume-mail.example')), findsOneWidget);
    expect(_inSheet(find.text('Remote font')), findsOneWidget);
    expect(_inSheet(find.text('12 links cleaned')), findsOneWidget);
    expect(_inSheet(find.text('Stopped')), findsNWidgets(3));

    await tester.tap(_inSheet(find.text('Load images once')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PrivacySheet), findsNothing);
    expect(find.text('Loading images…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Images loaded · trackers still stopped'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(3));
    expect(source.fetched, hasLength(3));
    expect(source.trusted, isEmpty);

    // Once means once: back to the message, the images wait again, but
    // the ones already fetched aren't asked for twice.
    await tester.tap(find.text('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New autumn arrivals').first);
    await tester.pumpAndSettle();
    expect(find.text('Images blocked · 3 trackers stopped'), findsOneWidget);
  });

  testWidgets('on the phone the sheet comes up from the bottom', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));
    await tester.tap(find.byType(PrivacyChip));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('Privacy for this message')), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(PrivacySheet)).dy,
      greaterThan(780),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_privacy_sheet_light.png'),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacySheet), findsNothing);
  }, tags: ['golden']);

  testWidgets('a trusted sender\'s images load on their own', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.byType(PrivacyChip));
    await tester.pumpAndSettle();
    await tester.tap(_inSheet(find.text('Always trust Bottega Lume')));
    await tester.pump();
    expect(_inSheet(find.text('Bottega Lume is trusted')), findsOneWidget);
    expect(source.trusted, {'ciao@bottegalume.example'});
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(3));

    await tester.tap(find.text('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New autumn arrivals').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Images loaded · trackers still stopped'), findsOneWidget);
    expect(source.fetched, hasLength(3));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('remote images can load for everyone', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.byType(PrivacyChip));
    await tester.pumpAndSettle();
    await tester.tap(_inSheet(find.byType(PiumaSwitch)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(source.blockImages, isFalse);
    expect(find.byType(Image), findsNWidgets(3));
  });

  group('original layout', () {
    setUp(() {
      // A stand-in for the web view: the document's size, and a link.
      originalPaper = (html, onLink) => Column(
        children: [
          Text('${html.length} characters of HTML'),
          GestureDetector(
            onTap: () => onLink('https://lume-login.example/'),
            child: const Text('A link inside'),
          ),
        ],
      );
    });
    tearDown(() => originalPaper = null);

    testWidgets('a designed email opens as sent, and switches to clean', (
      tester,
    ) async {
      final opened = <Uri>[];
      final before = openExternalLink;
      openExternalLink = (uri) async => opened.add(uri);
      addTearDown(() => openExternalLink = before);
      final source = await _pump(tester);
      expect(source.originals, [false]);
      expect(find.byType(ViewSwitch), findsOneWidget);
      expect(find.textContaining('ceramics handmade in Faenza'), findsNothing);
      expect(find.textContaining('characters of HTML'), findsOneWidget);

      // A link that shows another site asks first, as in the reader.
      await tester.tap(find.text('A link inside'));
      await tester.pumpAndSettle();
      expect(find.text('Check this link'), findsOneWidget);
      await tester.tap(find.text('Don’t open'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);

      // Loading the images brings the original again, with them.
      await tester.tap(find.text('Load images'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(source.originals, [false, true]);
      expect(source.trusted, isEmpty);
      expect(find.byType(ImagesBar), findsNothing);

      await tester.tap(find.text('Clean'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ceramics handmade in Faenza'),
        findsOneWidget,
      );
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      expect(find.textContaining('characters of HTML'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the privacy panel still shows it after the clean view', (
      tester,
    ) async {
      final source = await _pump(tester);
      await tester.tap(find.text('Clean'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PrivacyChip));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet(find.text('Show original layout')));
      await tester.pumpAndSettle();
      expect(find.textContaining('characters of HTML'), findsOneWidget);
      // The one made when it opened, not made again.
      expect(source.originals, [false]);
    });

    testWidgets(
      'the paper expands to the document height for a single scroll',
      (tester) async {
        originalPaper = (html, onLink) => Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              OriginalView.setHeight(context, 1600);
            });
            return Text('${html.length} characters of HTML');
          },
        );
        await _pump(tester);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(OriginalView)).height, 1648);
      },
    );

    testWidgets('without a web view there is no button', (tester) async {
      originalPaper = null;
      await _pump(tester);
      expect(find.byType(ViewSwitch), findsNothing);
      await tester.tap(find.byType(PrivacyChip));
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('Show original layout')), findsNothing);
    });

    testWidgets('original layout goldens', (tester) async {
      await _pump(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_original_light.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone original layout golden', (tester) async {
      await _pump(tester, size: const Size(390, 844));
      expect(find.text('Clean view'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_original_light.png'),
      );
      await tester.tap(find.byType(PrivacyChip));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_privacy_original_light.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone original layout runs edge to edge', (tester) async {
      await _pump(tester, dark: true, size: const Size(390, 844));
      final paper = tester.getRect(
        find
            .descendant(
              of: find.byType(OriginalView),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(paper.left, 0);
      expect(paper.right, 390);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_original_dark.png'),
      );
    }, tags: ['golden']);
  });

  group('images bar', () {
    testWidgets('it asks once, and loads for this email only', (tester) async {
      final source = await _pump(tester);
      expect(
        find.text(
          '3 images are off, so Bottega Lume can’t see when you open this.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Load images'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(ImagesBar), findsNothing);
      expect(find.byType(Image), findsNWidgets(3));
      expect(source.trusted, isEmpty);

      await tester.tap(find.text('Dinner on Friday?'));
      await tester.pumpAndSettle();
      expect(find.byType(ImagesBar), findsNothing);
      await tester.tap(find.text('New autumn arrivals').first);
      await tester.pumpAndSettle();
      expect(find.byType(ImagesBar), findsOneWidget);
    });

    testWidgets('"Always for this sender" trusts them', (tester) async {
      final source = await _pump(tester);
      await tester.tap(find.text('Always for this sender'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(source.trusted, {'ciao@bottegalume.example'});
      expect(find.byType(ImagesBar), findsNothing);
      expect(find.byType(Image), findsNWidgets(3));

      await tester.tap(find.text('Dinner on Friday?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New autumn arrivals').first);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(ImagesBar), findsNothing);
      expect(find.byType(Image), findsNWidgets(3));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('on the phone the buttons are full size', (tester) async {
      await _pump(tester, size: const Size(390, 844));
      expect(
        tester.getSize(find.widgetWithText(PiumaButton, 'Load images')).height,
        44,
      );
    });

    testWidgets('longer translated labels stack instead of overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        PiumaApp(
          locale: const Locale('it'),
          home: (_, _) => Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ImagesBar(
                count: 3,
                sender: 'Bottega Lume',
                phone: true,
                onLoad: () {},
                onTrust: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final trust = tester.getRect(
        find.widgetWithText(PiumaButton, 'Sempre per questo mittente'),
      );
      final load = tester.getRect(
        find.widgetWithText(PiumaButton, 'Carica immagini'),
      );
      expect(load.top, greaterThanOrEqualTo(trust.bottom));
    });
  });

  testWidgets('a blocked picture of unknown size takes a small box', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: MessageBody(
            readable: const Readable(
              blocks: [
                BodyBlock(
                  kind: BlockKind.image,
                  image: BodyImage(url: 'https://shop.example/logo.png'),
                ),
                BodyBlock(
                  kind: BlockKind.image,
                  image: BodyImage(
                    url: 'https://shop.example/hero.jpg',
                    width: 600,
                    height: 300,
                  ),
                ),
              ],
            ),
            images: RemoteImages(source),
            showRemote: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boxes = find.descendant(
      of: find.byType(MessageBody),
      matching: find.byType(ClipRRect),
    );
    expect(tester.getSize(boxes.at(0)), const Size(120, 48));
    // A size the message gives is kept, to the width of the text.
    expect(tester.getSize(boxes.at(1)).height, greaterThan(100));
  });

  testWidgets('a link that lies asks before opening', (tester) async {
    final opened = <Uri>[];
    final before = openExternalLink;
    openExternalLink = (uri) async => opened.add(uri);
    addTearDown(() => openExternalLink = before);
    final source = DemoMailSource(now: _now);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: MessageBody(
            readable: const Readable(
              blocks: [
                BodyBlock.text([
                  BodySpan('Sign in at '),
                  BodySpan(
                    'www.mybank.it',
                    link: 'https://login.bank-secure.example/x',
                    suspicious: true,
                  ),
                  BodySpan(' or read the '),
                  BodySpan('news', link: 'https://www.mybank.it/news'),
                ]),
              ],
            ),
            images: RemoteImages(source),
            showRemote: false,
          ),
        ),
      ),
    );
    await tester.tapOnText(find.textRange.ofSubstring('news'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://www.mybank.it/news')]);

    await tester.tapOnText(find.textRange.ofSubstring('www.mybank.it'));
    await tester.pumpAndSettle();
    expect(find.text('Check this link'), findsOneWidget);
    expect(
      find.text(
        'The text shows www.mybank.it, but the link goes to '
        'login.bank-secure.example.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Don’t open'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));

    await tester.tapOnText(find.textRange.ofSubstring('www.mybank.it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open anyway'));
    await tester.pumpAndSettle();
    expect(opened.last, Uri.parse('https://login.bank-secure.example/x'));
  });

  testWidgets('quotes, lists and headings', (tester) async {
    final source = DemoMailSource(now: _now);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: MessageBody(
            readable: const Readable(
              blocks: [
                BodyBlock(
                  kind: BlockKind.heading,
                  level: 1,
                  spans: [BodySpan('Agenda')],
                ),
                BodyBlock(
                  kind: BlockKind.listItem,
                  level: 1,
                  marker: '1.',
                  spans: [BodySpan('Budget')],
                ),
                BodyBlock(kind: BlockKind.rule),
                BodyBlock.text([BodySpan('earlier')], quote: 1),
              ],
            ),
            images: RemoteImages(source),
            showRemote: false,
          ),
        ),
      ),
    );
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    final quote = tester.widget<Text>(find.text('earlier'));
    final c = PiumaTheme.of(tester.element(find.text('earlier')));
    expect(quote.textSpan!.style!.color, c.muted);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('reader privacy golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_privacy_$name.png'),
      );
      await tester.tap(find.byType(PrivacyChip));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_privacy_sheet_$name.png'),
      );
      await tester.tap(_inSheet(find.text('Load images once')));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_privacy_loaded_$name.png'),
      );
    }, tags: ['golden']);
  }
}
