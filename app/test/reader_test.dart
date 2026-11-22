import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/design/look.dart';
import 'package:piuma_mail/design/theme.dart';
import 'package:piuma_mail/inbox/images_bar.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_body.dart';
import 'package:piuma_mail/inbox/original_view.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/readable.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/button.dart';
import 'package:piuma_mail/widgets/link_target.dart';
import 'package:piuma_mail/widgets/links.dart';
import 'package:piuma_mail/widgets/switch.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Settings › Reading › Open emails in › Original layout (the default is
/// the clean view).
const _asSent = Appearance(openOriginal: true);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(1440, 900),
  Appearance appearance = const Appearance(),
  double scale = 1,
  double textScale = 1,
  TextDirection? direction,
}) async {
  tester.view.physicalSize = size * scale;
  tester.view.devicePixelRatio = scale;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  RemoteImages.clear();
  final source = DemoMailSource(now: _now, newsletter: true);
  final first = (await source.page(0, 1)).first;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      appearance: appearance,
      home: (_, _) {
        final inbox = InboxScreen(
          source: source,
          onAddAccount: () {},
          now: () => _now,
          initialSelection: first,
        );
        return direction == null
            ? inbox
            : Directionality(textDirection: direction, child: inbox);
      },
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

  group('where a link goes', () {
    late List<Uri> opened;
    late Future<void> Function(Uri) before;
    String? copied;

    setUp(() {
      opened = [];
      copied = null;
      before = openExternalLink;
      openExternalLink = (uri) async => opened.add(uri);
    });
    tearDown(() => openExternalLink = before);

    Future<void> watchClipboard(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
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
    }

    testWidgets('on a phone a long press shows it, to copy or open', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 844));
      await watchClipboard(tester);
      final link = find.text('Explore the collection');
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.longPress(link);
      await tester.pumpAndSettle();
      expect(find.text('Where this link goes'), findsOneWidget);
      expect(find.text('bottegalume.example'), findsOneWidget);
      expect(find.text('/autumn'), findsOneWidget);
      expect(opened, isEmpty);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(copied, 'https://bottegalume.example/autumn');
      expect(find.text('Link copied'), findsOneWidget);
      expect(opened, isEmpty);

      await tester.longPress(link);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open link'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://bottegalume.example/autumn')]);
      // A tap still opens it at once.
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(opened, hasLength(2));
    });

    testWidgets('on a desktop the pointer over it shows it', (tester) async {
      await _pump(tester);
      final link = find.text('Explore the collection');
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(link));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(LinkTargetLine),
          matching: find.textContaining('bottegalume.example'),
        ),
        findsOneWidget,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byType(LinkTargetLine), findsNothing);
    });

    testWidgets('a long press in the original layout shows it too', (
      tester,
    ) async {
      originalPaper = (html, onLink) => Builder(
        builder: (context) => GestureDetector(
          onLongPress: () =>
              OriginalView.pressed(context, 'https://lume.example/x'),
          child: const Text('Long press here'),
        ),
      );
      addTearDown(() => originalPaper = null);
      await _pump(tester, appearance: _asSent, size: const Size(390, 844));
      await tester.longPress(find.text('Long press here'));
      await tester.pumpAndSettle();
      expect(find.text('lume.example'), findsOneWidget);
      expect(find.text('/x'), findsOneWidget);
      await tester.tap(find.text('Open link'));
      await tester.pumpAndSettle();
      if (find.text('Open anyway').evaluate().isNotEmpty) {
        await tester.tap(find.text('Open anyway'));
        await tester.pumpAndSettle();
      }
      expect(opened, [Uri.parse('https://lume.example/x')]);
    });
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
      final source = await _pump(tester, appearance: _asSent);
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

    for (final (name, size) in [
      ('desktop', const Size(1440, 900)),
      ('phone', const Size(390, 844)),
    ]) {
      testWidgets('on the $name, by default, it opens clean', (tester) async {
        final source = await _pump(tester, size: size);
        // Nothing made until asked: no web view, nothing fetched.
        expect(source.originals, isEmpty);
        expect(source.fetched, isEmpty);
        expect(find.byType(OriginalView), findsNothing);
        expect(
          find.textContaining('ceramics handmade in Faenza'),
          findsOneWidget,
        );
        expect(find.byType(ViewSwitch), findsOneWidget);

        // The switch still brings the original, images still blocked.
        await tester.tap(
          find.text(name == 'phone' ? 'Original layout' : 'Original'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('characters of HTML'), findsOneWidget);
        expect(source.originals, [false]);
        expect(source.fetched, isEmpty);
        expect(find.byType(ImagesBar), findsOneWidget);
      });
    }

    // #109: on a phone held upright "Original layout" cut the chip short.
    for (final (name, size, ownLine) in [
      ('small phone', const Size(360, 780), true),
      ('phone', const Size(390, 844), true),
      ('desktop', const Size(1440, 900), false),
    ]) {
      testWidgets('the privacy chip reads in full: $name', (tester) async {
        await _pump(tester, size: size);
        final label = find.descendant(
          of: find.byType(PrivacyChip),
          matching: find.byType(Text),
        );
        expect(tester.widget<Text>(label).data, contains('trackers stopped'));
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse);
        final chip = tester.getRect(find.byType(PrivacyChip));
        final view = tester.getRect(find.byType(ViewSwitch));
        if (ownLine) {
          // The link goes under the chip, never over it.
          expect(view.top, greaterThanOrEqualTo(chip.bottom));
        } else {
          // Room enough: on the chip's row, at its end.
          expect(view.center.dy, closeTo(chip.center.dy, 1));
          expect(view.left, greaterThan(chip.right));
        }
        expect(tester.takeException(), isNull);
      });
    }

    // #109: on narrow phones and with large text the chip grows onto more
    // lines instead of cutting "N trackers stopped" short.
    for (final width in [320.0, 360.0, 390.0]) {
      for (final textScale in [1.0, 2.0]) {
        for (final direction in TextDirection.values) {
          testWidgets('the privacy chip is never cut short: ${width.round()} '
              'px, text ×$textScale, ${direction.name}', (tester) async {
            await _pump(
              tester,
              size: Size(width, 844),
              textScale: textScale,
              direction: direction,
            );
            final label = find.descendant(
              of: find.byType(PrivacyChip),
              matching: find.byType(Text),
            );
            expect(
              tester.widget<Text>(label).data,
              'Images blocked · 3 trackers stopped',
            );
            final paragraph = tester.renderObject<RenderParagraph>(label);
            expect(paragraph.didExceedMaxLines, isFalse);
            final chip = tester.getRect(find.byType(PrivacyChip));
            expect(chip.left, greaterThanOrEqualTo(0));
            expect(chip.right, lessThanOrEqualTo(width));
            // The text stays inside the chip's border.
            final text = tester.getRect(label);
            expect(text.top, greaterThanOrEqualTo(chip.top));
            expect(text.bottom, lessThanOrEqualTo(chip.bottom));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('the privacy panel still shows it after the clean view', (
      tester,
    ) async {
      final source = await _pump(tester, appearance: _asSent);
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
        await _pump(tester, appearance: _asSent);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(OriginalView)).height, 1648);
      },
    );

    testWidgets(
      'on Windows a very long email never makes the web view taller than '
      'Direct3D 11 can draw (feedback #22)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        originalPaper = (html, onLink) => Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // A long thread quoted in a reply, on a 4K screen at 150%.
              OriginalView.setHeight(context, 18000);
            });
            return const SizedBox.expand(key: ValueKey('web view'));
          },
        );
        await _pump(tester, appearance: _asSent, scale: 1.5);
        await tester.pumpAndSettle();
        final points = tester.getSize(find.byKey(const ValueKey('web view')));
        expect(points.height, greaterThan(10000));
        expect(points.height * 1.5, lessThanOrEqualTo(16384));
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('a navigation the page starts by itself opens nothing', (
      tester,
    ) async {
      final opened = <Uri>[];
      final before = openExternalLink;
      openExternalLink = (uri) async => opened.add(uri);
      addTearDown(() => openExternalLink = before);
      // A refresh, a form, a script: no press of the person's before it.
      originalPaper = (html, onLink) => Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onLink('https://lume.example/');
          });
          return Text('${html.length} characters of HTML');
        },
      );
      await _pump(tester, appearance: _asSent);
      await tester.pumpAndSettle();
      expect(find.text('Check this link'), findsNothing);
      expect(opened, isEmpty);
      // A link the web view itself reports as clicked opens.
      originalPaper = (html, onLink) => Builder(
        builder: (context) => GestureDetector(
          onTap: () => OriginalView.clicked(context, 'https://lume.example/'),
          child: const Text('Clicked in WebKit'),
        ),
      );
      await tester.tap(find.text('Clean'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clicked in WebKit'));
      await tester.pumpAndSettle();
      if (find.text('Open anyway').evaluate().isNotEmpty) {
        await tester.tap(find.text('Open anyway'));
        await tester.pumpAndSettle();
      }
      expect(opened, [Uri.parse('https://lume.example/')]);
    });

    testWidgets('the browser\'s form of a suspicious link still warns', (
      tester,
    ) async {
      // WebKit hands back `a.href` normalized: another case, no slash.
      originalPaper = (html, onLink) => GestureDetector(
        onTap: () => onLink('HTTPS://LUME-LOGIN.EXAMPLE'),
        child: const Text('A link inside'),
      );
      await _pump(tester, appearance: _asSent);
      await tester.tap(find.text('A link inside'));
      await tester.pumpAndSettle();
      expect(find.text('Check this link'), findsOneWidget);
    });

    testWidgets('a link activated from the keyboard opens', (tester) async {
      final opened = <Uri>[];
      final before = openExternalLink;
      openExternalLink = (uri) async => opened.add(uri);
      addTearDown(() => openExternalLink = before);
      // Enter on a focused link, as the web view reports it: no pointer.
      var pressed = false;
      originalPaper = (html, onLink) => Builder(
        builder: (context) {
          if (!pressed) {
            pressed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              OriginalView.keyPressed(context);
              onLink('https://lume.example/');
            });
          }
          return const SizedBox.expand();
        },
      );
      await _pump(tester, appearance: _asSent);
      await tester.pumpAndSettle();
      if (find.text('Open anyway').evaluate().isNotEmpty) {
        await tester.tap(find.text('Open anyway'));
        await tester.pumpAndSettle();
      }
      expect(opened, [Uri.parse('https://lume.example/')]);
    });

    testWidgets('a web view that can’t start gives way to the clean view', (
      tester,
    ) async {
      addTearDown(() => originalPaperFailed = false);
      originalPaper = (html, onLink) => Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            OriginalView.unavailable(context);
          });
          return const SizedBox.expand();
        },
      );
      await _pump(tester, appearance: _asSent);
      await tester.pumpAndSettle();
      expect(find.byType(OriginalView), findsNothing);
      expect(
        find.textContaining('ceramics handmade in Faenza'),
        findsOneWidget,
      );
      // And no switch back to a paper that can't show.
      expect(find.byType(ViewSwitch), findsNothing);
    });

    testWidgets('the link under the pointer shows where it goes', (
      tester,
    ) async {
      String? next = 'https://lume-login.example/account';
      originalPaper = (html, onLink) => Builder(
        builder: (context) => GestureDetector(
          onTap: () => OriginalView.hover(context, next),
          child: const Text('Hover here'),
        ),
      );
      await _pump(tester, appearance: _asSent);
      await tester.tap(find.text('Hover here'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(LinkTargetLine),
          matching: find.textContaining('lume-login.example'),
        ),
        findsOneWidget,
      );
      // Not a link that could open: nothing to show.
      next = 'javascript:alert(1)';
      await tester.tap(find.text('Hover here'));
      await tester.pumpAndSettle();
      expect(find.byType(LinkTargetLine), findsNothing);
    });

    testWidgets('without a web view there is no button', (tester) async {
      originalPaper = null;
      await _pump(tester, appearance: _asSent);
      expect(find.byType(ViewSwitch), findsNothing);
      await tester.tap(find.byType(PrivacyChip));
      await tester.pumpAndSettle();
      expect(_inSheet(find.text('Show original layout')), findsNothing);
    });

    testWidgets('original layout goldens', (tester) async {
      await _pump(tester, appearance: _asSent);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_original_light.png'),
      );
    }, tags: ['golden']);

    testWidgets('original layout golden dark', (tester) async {
      await _pump(tester, appearance: _asSent, dark: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_original_dark.png'),
      );
    }, tags: ['golden']);

    // Settings › Reading › Open emails in › Clean view, the default.
    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      testWidgets('opened clean golden $name', (tester) async {
        await _pump(tester, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/reader_opens_clean_$name.png'),
        );
      }, tags: ['golden']);

      testWidgets('phone opened clean golden $name', (tester) async {
        await _pump(tester, dark: dark, size: const Size(390, 844));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_opens_clean_$name.png'),
        );
      }, tags: ['golden']);
    }

    testWidgets('phone original layout golden', (tester) async {
      await _pump(tester, appearance: _asSent, size: const Size(390, 844));
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
      await _pump(
        tester,
        appearance: _asSent,
        dark: true,
        size: const Size(390, 844),
      );
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
    // "Load images" is the filled one and comes first on every layout.
    for (final (name, phone, width) in [
      ('phone, stacked', true, 320.0),
      ('phone, side by side', true, 390.0),
      ('desktop, one line', false, 720.0),
      ('desktop, narrow', false, 420.0),
    ]) {
      testWidgets('"Load images" is primary and first: $name', (tester) async {
        tester.view.physicalSize = const Size(1000, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          PiumaApp(
            home: (_, _) => Center(
              child: SizedBox(
                width: width,
                child: ImagesBar(
                  count: 2,
                  sender: 'Bottega Lume',
                  onLoad: () {},
                  onTrust: () {},
                  phone: phone,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        PiumaButton button(String label) =>
            tester.widget<PiumaButton>(find.widgetWithText(PiumaButton, label));
        expect(button('Load images').kind, PiumaButtonKind.primary);
        expect(
          button('Always for this sender').kind,
          phone ? PiumaButtonKind.secondary : PiumaButtonKind.tertiary,
        );
        final load = tester.getRect(find.text('Load images'));
        final trust = tester.getRect(find.text('Always for this sender'));
        expect(
          load.bottom <= trust.top || load.right <= trust.left,
          isTrue,
          reason: '"Load images" comes before "Always for this sender"',
        );
      });
    }

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
      expect(trust.top, greaterThanOrEqualTo(load.bottom));
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

  testWidgets('a link to a host UTS #46 refuses asks before opening', (
    tester,
  ) async {
    final opened = <Uri>[];
    final before = openExternalLink;
    openExternalLink = (uri) async => opened.add(uri);
    addTearDown(() => openExternalLink = before);
    final beforeHost = linkHostAscii;
    // As the engine reads it: a punycode label that doesn't decode.
    linkHostAscii = (host) => host == 'xn--zz.com' ? null : beforeHost(host);
    addTearDown(() => linkHostAscii = beforeHost);
    final source = DemoMailSource(now: _now);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: MessageBody(
            readable: const Readable(
              blocks: [
                BodyBlock.text([
                  BodySpan('Your parcel', link: 'https://xn--zz.com/track'),
                ]),
              ],
            ),
            images: RemoteImages(source),
            showRemote: false,
          ),
        ),
      ),
    );
    await tester.tapOnText(find.textRange.ofSubstring('parcel'));
    await tester.pumpAndSettle();
    expect(find.text('Check this link'), findsOneWidget);
    expect(
      find.text(
        "This link's address isn't one a browser reads for sure: xn--zz.com.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Don’t open'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
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
