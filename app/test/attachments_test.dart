import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/attach_preview.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/attachment_chip.dart';
import 'package:piuma_mail/widgets/links.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
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
  return source;
}

Future<void> _openReview(WidgetTester tester) async {
  await tester.tap(find.text('Mockup v3 review'));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

void _pickReturns(List<XFile> files) {
  final before = pickFiles;
  pickFiles = () async => files;
  addTearDown(() => pickFiles = before);
}

XFile _file(String name, int size) =>
    XFile.fromData(Uint8List(size), name: name, path: '/picked/$name');

void main() {
  test('badges and sizes', () {
    expect(fileBadge('mockup-v3.pdf'), 'PDF');
    expect(fileBadge('photo', 'image/jpeg'), 'IMG');
    expect(fileBadge('archive.backup'), 'FILE');
    expect(fileSize(2400000), '2.4 MB');
    expect(fileSize(2400000, locale: 'it'), '2,4 MB');
    expect(fileSize(318000), '318 KB');
    expect(fileSize(12), '12 B');
  });

  testWidgets('attachments open from the reader', (tester) async {
    final opened = <String>[];
    final before = openLocalFile;
    openLocalFile = (path) async => opened.add(path);
    addTearDown(() => openLocalFile = before);
    final source = await _pump(tester);
    await _openReview(tester);
    expect(find.byType(AttachmentChip), findsNWidgets(2));
    expect(find.text('mockup-v3.pdf'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.bySemanticsLabel('mockup-v3.pdf, 2.4 MB'), findsOneWidget);

    // A PDF opens in the preview, as from the Attachments board; the
    // email is already open, so there is no Open email.
    await tester.tap(find.text('mockup-v3.pdf'));
    await tester.pumpAndSettle();
    expect(find.byType(AttachPreview), findsOneWidget);
    expect(find.textContaining('email'), findsNothing);
    expect(source.saved, isEmpty);
    await tester.tap(find.bySemanticsLabel('Download'));
    await tester.pumpAndSettle();
    expect(source.saved, ['mockup-v3.pdf']);
    expect(opened, ['/demo/Downloads/mockup-v3.pdf']);
    expect(find.text('mockup-v3.pdf saved in Downloads'), findsOneWidget);
  });

  testWidgets('a failed download says so', (tester) async {
    final source = await _pump(tester);
    await _openReview(tester);
    source.failNextSave = Exception('offline');
    await tester.tap(find.text('compose-notes.png'));
    await tester.pumpAndSettle();
    expect(find.byType(AttachPreview), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Download'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Couldn’t download compose-notes.png. Check the connection and try '
        'again.',
      ),
      findsOneWidget,
    );
  });

  for (final (kind, size) in [
    ('desktop', Size(1440, 900)),
    ('phone', Size(390, 844)),
  ]) {
    testWidgets('$kind preview from an open message golden', (tester) async {
      await _pump(tester, size: size);
      await _openReview(tester);
      await tester.tap(find.text('mockup-v3.pdf'));
      await tester.pumpAndSettle();
      expect(find.byType(AttachPreview), findsOneWidget);
      expect(find.bySemanticsLabel('Download'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_attach_preview_${kind}_light.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('messages without files show none', (tester) async {
    await _pump(tester);
    expect(find.byType(AttachmentChip), findsNothing);
  });

  testWidgets('files attached in compose go out with the message', (
    tester,
  ) async {
    final source = await _pump(tester);
    _pickReturns([_file('mockup-v3.pdf', 2400000), _file('notes.txt', 820)]);
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    await tester.enterText(_field(0), 'luca@studio.it,');
    await tester.enterText(_field(1), 'Mockups approved');
    await tester.tap(find.byTooltip('Attach file'));
    await tester.pumpAndSettle();
    expect(find.text('mockup-v3.pdf'), findsOneWidget);
    expect(find.text('2.4 MB'), findsOneWidget);
    expect(find.text('820 B'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove notes.txt'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsNothing);

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent.single.files.map((f) => f.name), ['mockup-v3.pdf']);
    expect(source.sent.single.files.single.data.length, 2400000);
  });

  testWidgets('files dropped on compose are attached', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    const at = Offset(400, 300);
    target.onDragEntered!(
      DropEventDetails(localPosition: at, globalPosition: at),
    );
    await tester.pumpAndSettle();
    expect(find.text('Drop to attach'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compose_drop_light.png'),
    );

    target.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile.fromData(Uint8List(318000), path: '/dropped/quote.pdf'),
          DropItemDirectory('/dropped/folder', const []),
        ],
        localPosition: at,
        globalPosition: at,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('quote.pdf'), findsOneWidget);
    expect(find.text('318 KB'), findsOneWidget);
    expect(find.text('folder'), findsNothing);
  });

  testWidgets('too much to send is stopped before it leaves', (tester) async {
    final source = await _pump(tester);
    _pickReturns([_file('video.mov', maxDraftFilesSize + 1)]);
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    await tester.enterText(_field(0), 'luca@studio.it,');
    await tester.tap(find.byTooltip('Attach file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Attachments can be up to 18 MB in all. Remove some and try '
        'again.',
      ),
      findsOneWidget,
    );
    expect(find.byType(ComposePane), findsOneWidget);
    expect(source.sent, isEmpty);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('attachments golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _openReview(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_attachments_$name.png'),
      );
      _pickReturns([_file('mockup-v3.pdf', 2400000)]);
      await tester.tap(find.text('Compose'));
      await tester.pumpAndSettle();
      await tester.enterText(_field(0), 'luca@studio.it,');
      await tester.enterText(_field(1), 'Mockups approved: let’s go');
      await tester.enterText(
        _field(2),
        'Hi Luca, hi Sara,\n\nI went through v3 and I think we’re there.\n\n'
        'Matteo',
      );
      await tester.tap(find.byTooltip('Attach file'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/compose_attachments_$name.png'),
      );
    }, tags: ['golden']);
  }
}
