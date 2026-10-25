import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/phone_parts.dart';
import 'package:piuma_mail/inbox/attach_preview.dart';
import 'package:piuma_mail/inbox/attachments.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/reader.dart';
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
  DemoMailSource? demo,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = demo ?? DemoMailSource(now: _now);
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

/// Lets the cards' staggered entrance finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// The demo, with the first page of every PDF drawn by the engine, as on
/// a real account.
class _PagesSource extends DemoMailSource {
  _PagesSource() : super(now: _now);

  static final pageBytes = File('test/assets/quote_page.jpg').readAsBytesSync();

  @override
  Future<Uint8List?> attachmentThumb(AttachedFile file) async =>
      file.file.mime == 'application/pdf'
      ? pageBytes
      : super.attachmentThumb(file);
}

/// Desktop Attachments, as `DesktopAllegati`.
Future<DemoMailSource> _openDesktop(
  WidgetTester tester, {
  bool dark = false,
  DemoMailSource? demo,
}) async {
  final source = await _pump(tester, dark: dark, demo: demo);
  await tester.tap(find.text('Attachments'));
  await _settle(tester);
  return source;
}

/// The desktop preview of the lake email with three photos, as on the
/// `AttachPreviewDesktopPhoto` board (the demo's emails carry one file).
Future<void> _photos(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  final lake = (await source.attachedFiles()).firstWhere(
    (f) => f.file.name == 'Lake-trip.jpg',
  );
  final photos = [
    for (final name in [
      'Lake-trip.jpg',
      'Pier-sunset.jpg',
      'Cansiglio-forest.jpg',
    ])
      AttachedFile(
        lake.row,
        MailAttachment(
          part: 2,
          name: name,
          mime: 'image/jpeg',
          size: lake.file.size,
        ),
      ),
  ];
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => Builder(
        builder: (context) => GestureDetector(
          onTap: () => AttachPreview.open(
            context,
            source: source,
            file: photos.first,
            photos: photos,
            desktop: true,
            now: () => _now,
            onDownload: (_) {},
            onOpenEmail: (_) {},
          ),
          child: const Material(
            key: ValueKey('host'),
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('host')));
  await _settle(tester);
}

final _tile = find.descendant(
  of: find.byType(AttachmentsTile),
  matching: find.text('Attachments'),
);

void main() {
  testWidgets('Attachments has its place in the sidebar, with new files', (
    tester,
  ) async {
    await _pump(tester);
    // Received this week, since Monday.
    expect(
      find.descendant(
        of: find
            .ancestor(of: find.text('Attachments'), matching: find.byType(Row))
            .first,
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Attachments'));
    await _settle(tester);
    expect(find.byType(AttachmentBoard), findsOneWidget);
    expect(
      find.text('Every file you’ve received, no need to open the email'),
      findsOneWidget,
    );
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Mockup-review-v3.png'), findsOneWidget);
    expect(find.text('From: Luca Bianchi · 2.1 MB · today'), findsOneWidget);
    expect(find.text('From: Studio Riva · 86 KB · Mon'), findsOneWidget);
    expect(find.text('From: Tipografia Conti · 180 KB · Sep 22'), findsOne);
    expect(find.bySemanticsLabel('Photos & media, 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Documents, 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Sheets, 2'), findsOneWidget);
  });

  testWidgets('files filter by type, search by name or sender, and sort', (
    tester,
  ) async {
    await _openDesktop(tester);
    await tester.tap(find.bySemanticsLabel('Sheets, 2'));
    await _settle(tester);
    expect(find.text('October-budget.xlsx'), findsOneWidget);
    expect(find.text('Building-expenses.csv'), findsOneWidget);
    expect(find.text('Catalog-quote.pdf'), findsNothing);

    await tester.tap(find.bySemanticsLabel('All, 12'));
    await tester.enterText(find.byType(TextField), 'dad');
    await _settle(tester);
    expect(find.text('Lake-trip.jpg'), findsOneWidget);
    expect(find.text('Cansiglio-forest.jpg'), findsOneWidget);
    expect(find.text('Pier-sunset.jpg'), findsNothing);
    expect(find.bySemanticsLabel('All, 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await _settle(tester);
    expect(find.text('No files match “nothing like it”'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.bySemanticsLabel('Sort by: Recent'));
    await _settle(tester);
    expect(find.bySemanticsLabel('Sort by: Largest'), findsOneWidget);
    expect(find.text('This week'), findsNothing);
    final zip = tester.getTopLeft(find.text('Catalog-fonts.zip'));
    final forest = tester.getTopLeft(find.text('Cansiglio-forest.jpg'));
    expect(zip.dy < forest.dy || zip.dx < forest.dx, isTrue);
  });

  testWidgets('a card shows Download and Open email', (tester) async {
    final opened = <String>[];
    final before = openLocalFile;
    openLocalFile = (path) async => opened.add(path);
    addTearDown(() => openLocalFile = before);
    final source = await _openDesktop(tester);
    expect(find.text('Open email'), findsNothing);
    await tester.tap(find.text('October-budget.xlsx'));
    await _settle(tester);
    expect(find.byType(AttachPreview), findsNothing);
    await tester.tap(find.text('Download'));
    await _settle(tester);
    expect(source.saved.single, 'October-budget.xlsx');
    expect(opened.single, endsWith('October-budget.xlsx'));
    expect(find.text('October-budget.xlsx saved in Downloads'), findsOneWidget);

    await tester.tap(find.text('Open email'));
    await _settle(tester);
    expect(find.byType(Reader), findsOneWidget);
    expect(find.byType(AttachmentBoard), findsNothing);
    expect(find.text('October budget'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byType(Reader),
        matching: find.text('Attachments'),
      ),
    );
    await _settle(tester);
    expect(find.byType(AttachmentBoard), findsOneWidget);
  });

  testWidgets('on the phone a tile opens Attachments, a tap its actions', (
    tester,
  ) async {
    await _pump(tester, phone: true);
    expect(find.byType(AttachmentsTile), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('4 new')), findsOneWidget);
    // The chips slide sideways when they do not fit.
    for (var i = 0; i < 5 && _tile.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(PhoneChipRow), const Offset(-120, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(_tile);
    await _settle(tester);
    expect(find.byType(PhoneAttachments), findsOneWidget);
    await tester.ensureVisible(find.text('Sheets'));
    await tester.tap(find.text('Sheets'));
    await _settle(tester);
    expect(find.text('Lake-trip.jpg'), findsNothing);
    expect(find.text('Studio Riva · 86 KB'), findsOneWidget);
    await tester.ensureVisible(find.text('All'));
    await tester.tap(find.text('All'));
    await _settle(tester);
    await tester.tap(find.text('October-budget.xlsx'));
    await _settle(tester);
    expect(
      find.bySemanticsLabel('Download October-budget.xlsx'),
      findsOneWidget,
    );
    await tester.tap(find.text('Lake-trip.jpg'));
    await _settle(tester);
    expect(find.byType(AttachPreview), findsOneWidget);
    expect(find.text('3.8 MB · from Dad'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Open Dad’s email'));
    await _settle(tester);
    expect(find.byType(AttachPreview), findsNothing);
    expect(find.byType(Reader), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(Reader),
        matching: find.text('Attachments'),
      ),
    );
    await _settle(tester);
    expect(find.byType(PhoneAttachments), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(PhoneAttachments),
        matching: find.text('Inbox'),
      ),
    );
    await _settle(tester);
    expect(find.byType(AttachmentsTile), findsOneWidget);
  });

  testWidgets('a PDF turns its pages in the preview', (tester) async {
    await _pump(tester, phone: true);
    // The chips slide sideways when they do not fit.
    for (var i = 0; i < 5 && _tile.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(PhoneChipRow), const Offset(-120, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(_tile);
    await _settle(tester);
    await tester.ensureVisible(find.text('Catalog-quote.pdf'));
    await tester.tap(find.text('Catalog-quote.pdf'));
    await _settle(tester);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Next page'));
    await _settle(tester);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close preview'));
    await _settle(tester);
    expect(find.byType(AttachPreview), findsNothing);
    expect(find.byType(PhoneAttachments), findsOneWidget);
  });

  testWidgets('on the desktop a PDF opens in a panel over the board', (
    tester,
  ) async {
    final source = await _openDesktop(tester);
    await tester.tap(find.text('Catalog-quote.pdf'));
    await _settle(tester);
    expect(find.byType(AttachPreview), findsOneWidget);
    expect(find.byType(AttachmentBoard), findsOneWidget);
    expect(find.text('412 KB · from Sara Conti · yesterday'), findsOneWidget);
    expect(find.text('Drawn on this device'), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Previous page'));
    await _settle(tester);
    expect(find.text('Page 1 of 2'), findsOneWidget);

    final before = openLocalFile;
    openLocalFile = (_) async {};
    addTearDown(() => openLocalFile = before);
    await tester.tap(find.bySemanticsLabel('Download'));
    await _settle(tester);
    expect(source.saved.single, 'Catalog-quote.pdf');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byType(AttachPreview), findsNothing);
    expect(find.byType(AttachmentBoard), findsOneWidget);

    await tester.tap(find.text('Catalog-quote.pdf'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Open Sara Conti’s email'));
    await _settle(tester);
    expect(find.byType(AttachPreview), findsNothing);
    expect(find.byType(Reader), findsOneWidget);
  });

  testWidgets('on the desktop the arrows step through the email’s photos', (
    tester,
  ) async {
    await _photos(tester);
    expect(find.text('3.8 MB · from Dad · yesterday'), findsOneWidget);
    expect(find.text('Photo 1 of 3 · from the same email'), findsOneWidget);
    expect(find.text('Download all'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('Photo 2 of 3 · from the same email'), findsOneWidget);
    expect(find.text('Pier-sunset.jpg'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Cansiglio-forest.jpg').last);
    await _settle(tester);
    expect(find.text('Photo 3 of 3 · from the same email'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.text('Photo 3 of 3 · from the same email'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close preview'));
    await _settle(tester);
    expect(find.byType(AttachPreview), findsNothing);
  });

  test('files sort into types and weeks', () {
    AttachedFile f(String name, String mime, int daysAgo, int size) =>
        AttachedFile(
          MailRow(
            accountId: 1,
            mailbox: 'INBOX',
            uid: daysAgo,
            fromName: 'Sara',
            fromEmail: 'sara@example.org',
            subject: '',
            preview: '',
            receivedAt: _now.subtract(Duration(days: daysAgo)),
            seen: true,
          ),
          MailAttachment(part: 1, name: name, mime: mime, size: size),
        );
    expect(
      fileFilter(
        const MailAttachment(part: 1, name: 'a.mov', mime: 'video/quicktime'),
      ),
      FileFilter.media,
    );
    expect(
      fileFilter(const MailAttachment(part: 1, name: 'Budget.XLSX')),
      FileFilter.sheets,
    );
    expect(
      fileFilter(const MailAttachment(part: 1, name: 'notes.txt')),
      FileFilter.documents,
    );
    final files = [
      f('photo.jpg', 'image/jpeg', 0, 10),
      f('quote.pdf', 'application/pdf', 3, 30),
      f('old.csv', 'text/csv', 4, 20),
    ];
    final recent = FilesView(files, _now);
    expect(recent.thisWeek.map((x) => x.file.name), ['photo.jpg', 'quote.pdf']);
    expect(recent.earlier.map((x) => x.file.name), ['old.csv']);
    expect(newFiles(files, _now), 2);
    final big = FilesView(files, _now, sort: FileSort.largest, query: 'sara');
    expect(big.thisWeek.map((x) => x.file.size), [30, 20, 10]);
    final docs = FilesView(files, _now, filter: FileFilter.documents);
    expect(docs.thisWeek.single.file.name, 'quote.pdf');
    expect(docs.counts[FileFilter.all], 3);
  });

  testWidgets('a PDF shows its own first page once the engine has it', (
    tester,
  ) async {
    // Pages are drawn at the card's size, the photos fill the card.
    int pages() => tester
        .widgetList<Image>(find.byType(Image))
        .where((i) => i.image is ResizeImage)
        .length;
    await _openDesktop(tester, demo: _PagesSource());
    expect(pages(), 4, reason: "the four PDFs on screen");
  });

  testWidgets('a PDF keeps the sketch while it has no page', (tester) async {
    await _openDesktop(tester);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .where((i) => i.image is ResizeImage),
      isEmpty,
    );
  });

  testWidgets('attachments with pages golden light', (tester) async {
    await _openDesktop(tester, demo: _PagesSource());
    await _decodeImages(tester);
    await expectLater(
      find.byType(InboxScreen),
      matchesGoldenFile('goldens/attachments_pages_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('phone attachments with pages golden light', (tester) async {
    await _pump(tester, phone: true, demo: _PagesSource());
    // The chips slide sideways when they do not fit.
    for (var i = 0; i < 5 && _tile.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(PhoneChipRow), const Offset(-120, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(_tile);
    await _settle(tester);
    await _decodeImages(tester);
    await expectLater(
      find.byType(InboxScreen),
      matchesGoldenFile('goldens/phone_attachments_pages_light.png'),
    );
  }, tags: ['golden']);

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('attachments golden $name', (tester) async {
      await _openDesktop(tester, dark: dark);
      await tester.tap(find.text('October-budget.xlsx'));
      await _settle(tester);
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/attachments_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone attachments golden $name', (tester) async {
      await _pump(tester, dark: dark, phone: true);
      // The chips slide sideways when they do not fit.
      for (var i = 0; i < 5 && _tile.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(find.byType(PhoneChipRow), const Offset(-120, 0));
        await tester.pumpAndSettle();
      }
      await tester.tap(_tile);
      await _settle(tester);
      await tester.tap(find.text('October-budget.xlsx'));
      await _settle(tester);
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/phone_attachments_$name.png'),
      );
    }, tags: ['golden']);

    for (final file in ['Catalog-quote.pdf', 'Lake-trip.jpg']) {
      final kind = file.endsWith('.pdf') ? 'pdf' : 'photo';
      testWidgets('attachment preview $kind golden $name', (tester) async {
        await _pump(tester, dark: dark, phone: true);
        // The chips slide sideways when they do not fit.
        for (var i = 0; i < 5 && _tile.hitTestable().evaluate().isEmpty; i++) {
          await tester.drag(find.byType(PhoneChipRow), const Offset(-120, 0));
          await tester.pumpAndSettle();
        }
        await tester.tap(_tile);
        await _settle(tester);
        await tester.ensureVisible(find.text(file));
        await tester.tap(find.text(file));
        await _settle(tester);
        await expectLater(
          find.byType(AttachPreview),
          matchesGoldenFile('goldens/attach_preview_${kind}_$name.png'),
        );
      }, tags: ['golden']);

      testWidgets('desktop attachment preview $kind golden $name', (
        tester,
      ) async {
        if (kind == 'pdf') {
          await _openDesktop(tester, dark: dark);
          await tester.tap(find.text(file));
          await _settle(tester);
        } else {
          await _photos(tester, dark: dark);
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/attach_preview_desktop_${kind}_$name.png'),
        );
      }, tags: ['golden']);
    }
  }
}

/// Decodes the pictures on screen, which needs real time.
Future<void> _decodeImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(
        image.image,
        tester.element(find.byType(InboxScreen)),
      );
    }
  });
  await tester.pumpAndSettle();
}
