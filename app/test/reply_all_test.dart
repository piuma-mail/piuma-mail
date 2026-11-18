import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_actions.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/shortcuts_page.dart';
import 'package:piuma_mail/widgets/attachment_chip.dart';
import 'package:piuma_mail/widgets/links.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
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
  await tester.pumpAndSettle();
  return source;
}

Future<void> _open(WidgetTester tester, String subject) async {
  await tester.tap(
    find.descendant(
      of: find.byType(InboxRowTile),
      matching: find.text(subject),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _inCompose(Finder f) =>
    find.descendant(of: find.byType(ComposePane), matching: f);

String _text(WidgetTester tester, int i) => tester
    .widget<TextField>(_inCompose(find.byType(TextField)).at(i))
    .controller!
    .text;

void main() {
  testWidgets('Reply all from the reader: everyone else, Cc kept', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    // Reply stays first; Reply all sits next to it with its key (and by
    // the reply box).
    expect(find.bySemanticsLabel('Reply'), findsWidgets);
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Reply all').first);
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(_inCompose(find.text('Re: Mockup v3 review')), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final sent = source.sent.single;
    expect(sent.to, [
      'Luca Bianchi <luca@studio.it>',
      'Sara Conti <sara@studio.it>',
    ]);
    expect(sent.cc, ['Elena Ferri <elena@studio.it>']);
    // Never the person's own address.
    expect(
      [...sent.to, ...sent.cc].where((a) => a.contains('matteo@studio.it')),
      isEmpty,
    );
    expect(sent.inReplyTo, isNotNull);
  });

  testWidgets('A answers everyone; R still the sender alone', (tester) async {
    final source = await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent.last.cc, ['Elena Ferri <elena@studio.it>']);

    await _open(tester, 'Mockup v3 review');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent.last.to, ['Luca Bianchi <luca@studio.it>']);
    expect(source.sent.last.cc, isEmpty);
  });

  testWidgets('a message only to the person has no Reply all', (tester) async {
    await _pump(tester);
    await _open(tester, 'Re: Print quote');
    // Sara wrote to the person, with Luca in Cc: Reply all is there.
    expect(find.bySemanticsLabel('Reply all'), findsWidgets);
    await _open(tester, 'Trip photos');
    expect(find.bySemanticsLabel('Reply all'), findsNothing);
  });

  testWidgets('quick reply: Reply all is one tap away, never the default', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _open(tester, 'Dinner on Friday?');
    final box = find.descendant(
      of: find.byType(Reader),
      matching: find.byType(TextField),
    );
    expect(find.text('Reply to Giulia…'), findsOneWidget);
    // The box's own Reply all, under it.
    await tester.tap(find.bySemanticsLabel('Reply all').last);
    await tester.pumpAndSettle();
    expect(find.text('Reply to Giulia and 2 others…'), findsOneWidget);
    await tester.enterText(box.last, "I'm in!");
    await tester.tap(find.bySemanticsLabel('Send reply'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final sent = source.sent.single;
    expect(sent.to, [
      'Giulia Romano <giulia.romano@posta.it>',
      'Elena Ferri <elena.ferri@icloud.com>',
    ]);
    expect(sent.cc, ['Marco Riva <marco.riva@posta.it>']);
    expect(sent.body, startsWith("I'm in!"));

    // Another email starts with Reply again.
    await _open(tester, 'Mockup v3 review');
    expect(find.text('Reply to Luca…'), findsOneWidget);
  });

  testWidgets('the reader names To and Cc, and opens into them', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    expect(
      find.textContaining('to you, Sara Conti, Elena Ferri · today at'),
      findsOneWidget,
    );
    expect(find.text('Elena Ferri <elena@studio.it>'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Show who received it'));
    await tester.pumpAndSettle();
    expect(find.text('Cc'), findsOneWidget);
    expect(find.text('Elena Ferri <elena@studio.it>'), findsOneWidget);
    expect(
      find.text('Matteo <matteo@studio.it>, Sara Conti <sara@studio.it>'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Hide who received it'));
    await tester.pumpAndSettle();
    expect(find.text('Cc'), findsNothing);
  });

  testWidgets('a blind copy says so', (tester) async {
    await _pump(tester);
    await _open(tester, 'Trip photos');
    expect(find.textContaining('to Mum · you were Bcc’d · '), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Show who received it'));
    await tester.pumpAndSettle();
    expect(find.text('Bcc'), findsOneWidget);
  });

  testWidgets('Forward: a file that fails is named, with Try again', (
    tester,
  ) async {
    final source = await _pump(tester);
    source.failFiles.add('compose-notes.png');
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('Forward'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsNothing);
    expect(find.text('This file couldn’t be attached:'), findsOneWidget);
    // Named in the panel, over the reader's own chip for it.
    expect(find.text('compose-notes.png'), findsNWidgets(2));

    // Still failing: still named.
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('This file couldn’t be attached:'), findsOneWidget);

    // Back on the server: Try again attaches it, and compose opens.
    source.failFiles.clear();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(_inCompose(find.byType(AttachmentChip)), findsNWidgets(2));
  });

  testWidgets('Forward goes on without the files that failed', (tester) async {
    final source = await _pump(tester);
    source.failFiles.add('compose-notes.png');
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('Forward'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go on without it'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(_inCompose(find.byType(AttachmentChip)), findsOneWidget);
    expect(_inCompose(find.text('mockup-v3.pdf')), findsOneWidget);
  });

  testWidgets('More: Forward as attachment attaches the whole email', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward as attachment'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(_text(tester, 1), 'Fwd: Mockup v3 review');
    expect(_inCompose(find.text('Mockup v3 review.eml')), findsOneWidget);
  });

  testWidgets('More: Edit as new keeps recipients, subject and text', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit as new'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(_inCompose(find.text('Mockup v3 review')), findsOneWidget);
    expect(
      _inCompose(find.textContaining('I left two comments')),
      findsOneWidget,
    );
    expect(_inCompose(find.byType(AttachmentChip)), findsNWidgets(2));
  });

  testWidgets('More: Redirect asks where to and sends it unchanged', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redirect'));
    await tester.pumpAndSettle();
    expect(find.text('Redirect this email'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'eve@example.org');
    await tester.pump();
    await tester.tap(find.text('Redirect').last);
    await tester.pumpAndSettle();
    expect(source.redirected.single.$2, ['eve@example.org']);
    expect(source.redirected.single.$1.subject, 'Mockup v3 review');
    // Through the outbox, as Send: Undo first, then it goes.
    // The toast, and the row in the Outbox.
    expect(find.text('Sending…'), findsWidgets);
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Redirected to eve@example.org'), findsOneWidget);
  });

  testWidgets('More: View source shows the headers and the raw email', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View source'));
    await tester.pumpAndSettle();
    expect(find.text('Source of the email'), findsOneWidget);
    expect(find.textContaining('Subject: ', findRichText: true), findsWidgets);
    await tester.tap(find.text('Raw'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Message-ID: <demo-'), findsOneWidget);
  });

  testWidgets('Save as .eml writes the raw email where the person picked', (
    tester,
  ) async {
    String? suggested;
    Uint8List? written;
    pickSaveLocation = (name) async {
      suggested = name;
      return '/picked/$name';
    };
    writeSavedFile = (path, data) async => written = data;
    addTearDown(() {
      pickSaveLocation = (name) async => null;
    });
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as .eml'));
    await tester.pumpAndSettle();
    expect(suggested, 'Mockup v3 review.eml');
    expect(utf8.decode(written!), contains('Subject: Mockup v3 review'));
    expect(find.text('Saved as Mockup v3 review.eml'), findsOneWidget);
  });

  testWidgets('More: Mute conversation, with Undo, then Unmute', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute conversation'));
    await tester.pumpAndSettle();
    expect(source.mutedThreads, hasLength(1));
    expect(
      find.text(
        'Conversation muted: new messages arrive read, without a notification',
      ),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Unmute conversation'), findsOneWidget);
  });

  testWidgets('J and K, ↓ and ↑ open the next and previous email', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Dinner on Friday?');
    Reader reader() => tester.widget<Reader>(find.byType(Reader));
    expect(reader().row!.subject, 'Dinner on Friday?');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(reader().row!.subject, 'Mockup v3 review');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(reader().row!.subject, 'Re: Print quote');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(reader().row!.subject, 'Mockup v3 review');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(reader().row!.subject, 'Dinner on Friday?');
  });

  testWidgets('Ctrl + and − zoom the email, Ctrl 0 sets it back', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    Reader reader() => tester.widget<Reader>(find.byType(Reader));
    expect(reader().zoom, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(reader().zoom, 1.25);
    expect(find.text('Text size 125%'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(reader().zoom, 1.1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(reader().zoom, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Settings › Shortcuts lists the new keys', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutsPage), findsOneWidget);
    for (final label in [
      'Reply all',
      'Forward',
      'Next email',
      'Previous email',
      'Zoom in',
      'Zoom out',
      'Actual size',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('J  ↓'), findsOneWidget);
    expect(find.text('K  ↑'), findsOneWidget);
  });

  testWidgets('the palette has Reply all and the new commands', (tester) async {
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'reply all');
    await tester.pumpAndSettle();
    expect(find.text('Reply all'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'next');
    await tester.pumpAndSettle();
    expect(find.text('Next email'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  group('on the phone', () {
    testWidgets('More holds Reply all and the rest', (tester) async {
      final source = await _pump(tester, size: const Size(390, 844));
      await tester.tap(find.text('Mockup v3 review'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      for (final item in [
        'Forward as attachment',
        'Redirect',
        'Edit as new',
        'Mute conversation',
        'View source',
        'Save as .eml',
      ]) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      // In the menu, and by the reply box.
      expect(find.text('Reply all'), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('Reply all'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ComposePane), findsOneWidget);
      expect(source.sent, isEmpty);
    });

    testWidgets('the quick reply bar has Reply all', (tester) async {
      final source = await _pump(tester, size: const Size(390, 844));
      await tester.tap(find.text('Dinner on Friday?'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Reply all'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Count me in');
      await tester.tap(find.bySemanticsLabel('Send reply'));
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(source.sent.single.cc, ['Marco Riva <marco.riva@posta.it>']);
    });

    /// The phone's More, then [item] in it.
    Future<void> more(WidgetTester tester, String item) async {
      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text(item),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<DemoMailSource> phone(WidgetTester tester, String subject) async {
      final source = await _pump(tester, size: const Size(390, 844));
      await tester.tap(find.text(subject));
      await tester.pumpAndSettle();
      return source;
    }

    testWidgets('To and Cc show and open, as on the desktop', (tester) async {
      await phone(tester, 'Mockup v3 review');
      expect(
        find.textContaining('to you, Sara Conti, Elena Ferri · today at'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Show who received it'));
      await tester.pumpAndSettle();
      expect(find.text('Elena Ferri <elena@studio.it>'), findsOneWidget);
    });

    testWidgets('a blind copy says so, and has no Reply all', (tester) async {
      await phone(tester, 'Trip photos');
      expect(find.textContaining('to Mum · you were Bcc’d · '), findsOneWidget);
      expect(find.bySemanticsLabel('Reply all'), findsNothing);
    });

    testWidgets('Forward: a failed file is named, Try again, Go on', (
      tester,
    ) async {
      final source = await phone(tester, 'Mockup v3 review');
      source.failFiles.add('compose-notes.png');
      await more(tester, 'Forward');
      expect(find.byType(ComposePane), findsNothing);
      expect(find.text('This file couldn’t be attached:'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('This file couldn’t be attached:'), findsOneWidget);
      await tester.tap(find.text('Go on without it'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposePane), findsOneWidget);
      expect(_inCompose(find.byType(AttachmentChip)), findsOneWidget);
    });

    testWidgets('Forward as attachment', (tester) async {
      await phone(tester, 'Mockup v3 review');
      await more(tester, 'Forward as attachment');
      expect(find.byType(ComposePane), findsOneWidget);
      expect(_inCompose(find.text('Mockup v3 review.eml')), findsOneWidget);
    });

    testWidgets('Edit as new', (tester) async {
      await phone(tester, 'Mockup v3 review');
      await more(tester, 'Edit as new');
      expect(find.byType(ComposePane), findsOneWidget);
      expect(
        _inCompose(find.textContaining('I left two comments')),
        findsOneWidget,
      );
    });

    testWidgets('Redirect', (tester) async {
      final source = await phone(tester, 'Mockup v3 review');
      await more(tester, 'Redirect');
      expect(find.text('Redirect this email'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'eve@example.org');
      await tester.pump();
      await tester.tap(find.text('Redirect').last);
      await tester.pumpAndSettle();
      expect(source.redirected.single.$2, ['eve@example.org']);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.text('Redirected to eve@example.org'), findsOneWidget);
    });

    testWidgets('View source', (tester) async {
      await phone(tester, 'Mockup v3 review');
      await more(tester, 'View source');
      expect(find.text('Source of the email'), findsOneWidget);
      await tester.tap(find.text('Raw'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Message-ID: <demo-'), findsOneWidget);
    });

    testWidgets('Save as .eml: Downloads, then Open hands it to the system', (
      tester,
    ) async {
      String? opened;
      openLocalFile = (path) async => opened = path;
      final source = await phone(tester, 'Mockup v3 review');
      await more(tester, 'Save as .eml');
      expect(
        utf8.decode(source.savedFiles['Mockup v3 review.eml']!),
        contains('Subject: Mockup v3 review'),
      );
      expect(
        find.text('Mockup v3 review.eml saved in Downloads'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(opened, '/demo/Downloads/Mockup v3 review.eml');
    });

    testWidgets('Mute conversation, then Unmute', (tester) async {
      final source = await phone(tester, 'Mockup v3 review');
      await more(tester, 'Mute conversation');
      expect(source.mutedThreads, hasLength(1));
      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Unmute conversation'), findsOneWidget);
    });

    testWidgets('Text size: larger, smaller, actual size', (tester) async {
      await phone(tester, 'Mockup v3 review');
      Reader reader() => tester.widget<Reader>(find.byType(Reader).last);
      await more(tester, 'Text size');
      expect(find.text('100%'), findsOneWidget);
      await tester.tap(find.text('Zoom in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zoom in'));
      await tester.pumpAndSettle();
      expect(find.text('125%'), findsOneWidget);
      expect(reader().zoom, 1.25);
      await tester.tap(find.text('Zoom out'));
      await tester.pumpAndSettle();
      expect(reader().zoom, 1.1);
      await tester.tap(find.text('Actual size'));
      await tester.pumpAndSettle();
      expect(reader().zoom, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsNothing);
    });
  });

  testWidgets('desktop: Text size in More, beside Ctrl + and −', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    Reader reader() => tester.widget<Reader>(find.byType(Reader));
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom in'));
    await tester.pumpAndSettle();
    expect(find.text('110%'), findsOneWidget);
    expect(reader().zoom, 1.1);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('desktop: Save as .eml offers Open too', (tester) async {
    String? opened;
    openLocalFile = (path) async => opened = path;
    pickSaveLocation = (name) async => '/picked/$name';
    writeSavedFile = (path, data) async {};
    await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as .eml'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, '/picked/Mockup v3 review.eml');
  });

  testWidgets('Redirect: Undo takes it back before it goes', (tester) async {
    final source = await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redirect'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'eve@example.org');
    await tester.pump();
    await tester.tap(find.text('Redirect').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Redirected to eve@example.org'), findsNothing);
    expect(source.sent, isEmpty);
  });

  testWidgets('Redirect: names with a comma, and a wrong address said', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _open(tester, 'Mockup v3 review');
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redirect'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).last;
    await tester.enterText(field, 'Rossi, Mario <m@x.it>, nope');
    await tester.pump();
    expect(find.text('“nope” is not an email address.'), findsOneWidget);
    // Not sent while an address is wrong.
    await tester.tap(find.text('Redirect').last);
    await tester.pump();
    expect(source.redirected, isEmpty);
    await tester.enterText(field, 'Rossi, Mario <m@x.it>; "Bo, B" <b@x.it>');
    await tester.pump();
    expect(find.textContaining('is not an email address'), findsNothing);
    await tester.tap(find.text('Redirect').last);
    await tester.pumpAndSettle();
    expect(source.redirected.single.$2, ['m@x.it', 'b@x.it']);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets('Reply all to an unverified Mail-Followup-To opens compose', (
    tester,
  ) async {
    final source = await _pump(tester);
    source.envelopeFor['Dinner on Friday?'] = const MailEnvelope(
      to: [
        MailPerson('Matteo', 'matteo@posta.it', you: true),
        MailPerson('Elena Ferri', 'elena.ferri@icloud.com'),
      ],
      replyTo: ['Giulia Romano <giulia.romano@posta.it>'],
      replyAllTo: ['eve@evil.example'],
      replyAllReview: true,
    );
    await _open(tester, 'Dinner on Friday?');
    // The box's Reply all, on; what is typed opens compose, not sent.
    await tester.tap(find.bySemanticsLabel('Reply all').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(of: find.byType(Reader), matching: find.byType(TextField))
          .last,
      "I'm in!",
    );
    await tester.tap(find.bySemanticsLabel('Send reply'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent, isEmpty);
  });
}
