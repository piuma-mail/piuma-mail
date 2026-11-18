import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/outside/arrivals.dart';
import 'package:piuma_mail/outside/arrive.dart';
import 'package:piuma_mail/outside/mailto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Only these exist, as regular files; "/home/me/folder" is a folder.
  // (Either slash: a file: URI becomes a Windows path on Windows.)
  FileSystemEntityType typeOf(String path) =>
      switch (path.replaceAll(r'\', '/')) {
        '/home/me/notes.eml' ||
        '/home/me/NOTES.EML' ||
        '/home/me/photo.jpg' ||
        '/home/me/a b.pdf' ||
        'C:/Users/me/report.pdf' => FileSystemEntityType.file,
        '/home/me/folder' => FileSystemEntityType.directory,
        _ => FileSystemEntityType.notFound,
      };

  group('command line', () {
    test('a mailto: link writes a message', () {
      final a = arrivalsFrom([
        'mailto:ada@example.com?subject=Hi',
      ], typeOf: typeOf);
      expect(a, hasLength(1));
      final c = a.single as ComposeArrival;
      expect(c.link.to, ['ada@example.com']);
      expect(c.link.subject, 'Hi');
    });

    test('an email file opens; other files go into one message', () {
      final a = arrivalsFrom([
        '/home/me/notes.eml',
        '/home/me/photo.jpg',
        'file:///home/me/a%20b.pdf',
        r'C:\Users\me\report.pdf',
      ], typeOf: typeOf);
      expect(a, hasLength(2));
      expect((a[0] as EmlArrival).path, '/home/me/notes.eml');
      final c = a[1] as ComposeArrival;
      expect(c.files.map((f) => f.name), [
        'photo.jpg',
        'a b.pdf',
        'report.pdf',
      ]);
      expect(c.link.isEmpty, isTrue);
      expect(
        (arrivalsFrom(['/home/me/NOTES.EML'], typeOf: typeOf).single
                as EmlArrival)
            .path,
        '/home/me/NOTES.EML',
      );
    });

    test('flags, folders, missing files and other links are ignored', () {
      final a = arrivalsFrom([
        '--background',
        '-psn_0_12345',
        'multi_window',
        '/home/me/folder',
        '/home/me/missing.eml',
        'https://example.com/x.eml',
        'javascript:alert(1)',
        'ms-settings:defaultapps',
        '',
        '   ',
      ], typeOf: typeOf);
      expect(a, isEmpty);
    });

    test('a network folder is never looked at, and the person is told', () {
      final looked = <String>[];
      FileSystemEntityType spy(String path) {
        looked.add(path);
        return FileSystemEntityType.file;
      }

      for (final arg in [
        r'\\server\share\notes.eml',
        '//server/share/notes.eml',
        r'\/server/share/notes.eml',
        r'/\server\share\notes.eml',
        r'\\?\UNC\server\share\notes.eml',
        r'\\.\pipe\x',
        r'  \\server\share\notes.eml',
        'file://server/share/notes.eml',
        'file:////server/share/notes.eml',
        'file://///server/share/notes.eml',
        'file:///%5C%5Cserver/share/notes.eml',
        'file:///%5Cserver/share/notes.eml',
      ]) {
        final a = arrivalsFrom([arg], typeOf: spy);
        expect(a, [isA<NetworkFileArrival>()], reason: arg);
      }
      expect(looked, isEmpty);
      // Along with files that do open: those still go, with one notice.
      final a = arrivalsFrom([
        '/home/me/photo.jpg',
        r'\\server\share\a.pdf',
        '//server/share/b.pdf',
      ], typeOf: typeOf);
      expect(a, hasLength(2));
      expect((a[0] as ComposeArrival).files.single.name, 'photo.jpg');
      expect(a[1], isA<NetworkFileArrival>());
    });

    test('two separators in any order name another computer', () {
      for (final p in [r'\\a', '//a', r'\/a', r'/\a', r'\\?\UNC\a']) {
        expect(isNetworkPath(p), isTrue, reason: p);
      }
      for (final p in ['/a/b', r'C:\a', r'\a', 'a//b', '/']) {
        expect(isNetworkPath(p), isFalse, reason: p);
      }
    });

    test('with a mailto: link, only the link counts', () {
      // What "exe" "%1" gives for a link written to break out of its
      // quotes: more words, files and flags among them.
      final a = arrivalsFrom([
        'mailto:a@example.com?subject=Hi',
        '/home/me/photo.jpg',
        '/home/me/notes.eml',
        'mailto:b@example.com',
      ], typeOf: typeOf);
      final c = a.single as ComposeArrival;
      expect(c.link.to, ['a@example.com']);
      expect(c.files, isEmpty);
      // Not first either.
      final b = arrivalsFrom([
        '/home/me/photo.jpg',
        'MAILTO:b@example.com',
      ], typeOf: typeOf);
      expect((b.single as ComposeArrival).link.to, ['b@example.com']);
      expect((b.single as ComposeArrival).files, isEmpty);
      // A link too long is no link, and still nothing else goes.
      expect(
        arrivalsFrom([
          'mailto:a@example.com?body=${'x' * MailtoLink.maxLength}',
          '/home/me/photo.jpg',
        ], typeOf: typeOf),
        isEmpty,
      );
    });

    test('a file that cannot be looked at is ignored', () {
      final a = arrivalsFrom([
        '/home/me/notes.eml',
      ], typeOf: (_) => throw const FileSystemException('denied'));
      expect(a, isEmpty);
    });

    test('at most 20 files, the rest counted as left out', () {
      final a = arrivalsFrom(
        List.filled(30, '/home/me/photo.jpg'),
        typeOf: typeOf,
      );
      final c = a.single as ComposeArrival;
      expect(c.files, hasLength(Arrivals.maxFiles));
      expect(c.tooLarge, 10);
    });

    test('at most 64 words are looked at', () {
      final a = arrivalsFrom([
        ...List.filled(64, '--x'),
        'mailto:a@example.com',
      ], typeOf: typeOf);
      expect(a, isEmpty);
    });
  });

  group('file names', () {
    test('only a name, never a folder or a hidden file', () {
      expect(fileName('/home/me/a.pdf'), 'a.pdf');
      expect(fileName(r'C:\x\y\a.pdf'), 'a.pdf');
      expect(safeFileName('../../.bashrc'), '_.._.bashrc');
      expect(safeFileName('.bashrc'), 'bashrc');
      expect(safeFileName(''), 'file');
      expect(safeFileName('invoice\u202Efdp.exe'), 'invoicefdp.exe');
      expect(safeFileName('a\u0000b:c?.txt'), 'ab_c_.txt');
      final long = safeFileName('${'n' * 300}.pdf');
      expect(long.length, 120);
      expect(long, endsWith('.pdf'));
    });
  });

  group('Android', () {
    test('a mailto: intent with its extras', () {
      final a = sharedArrival({
        'link': 'mailto:ada@example.com?subject=From%20link',
        'subject': 'From extra',
        'text': 'Hello',
        'to': ['bob@example.com', 'not an address'],
        'cc': ['carol@example.com'],
        'bcc': 42,
      }) as ComposeArrival;
      expect(a.link.to, ['ada@example.com', 'bob@example.com']);
      expect(a.link.cc, ['carol@example.com']);
      expect(a.link.bcc, isEmpty);
      // The link's own subject wins; its missing body comes from the text.
      expect(a.link.subject, 'From link');
      expect(a.link.body, 'Hello');
    });

    test('a share: text and files, names cleaned', () {
      final a = sharedArrival({
        'subject': 'Look\r\nBcc: x@evil.example',
        'text': 'https://example.com',
        'files': [
          {'path': '/data/cache/shared/1', 'name': '../../evil.sh'},
          {'path': '/data/cache/shared/2'},
          {'path': 3, 'name': 'x'},
          'nonsense',
        ],
        'skipped': 2,
      }) as ComposeArrival;
      expect(a.link.subject, 'Look Bcc: x@evil.example');
      expect(a.link.bcc, isEmpty);
      expect(a.link.body, 'https://example.com');
      expect(a.files.map((f) => (f.path, f.name)), [
        ('/data/cache/shared/1', '_.._evil.sh'),
        ('/data/cache/shared/2', 'file'),
      ]);
      expect(a.tooLarge, 2);
    });

    test('an email file', () {
      final a = sharedArrival({'eml': '/data/cache/shared/9'}) as EmlArrival;
      expect(a.path, '/data/cache/shared/9');
    });

    test('anything of the wrong shape is ignored', () {
      expect(sharedArrival(null), isNull);
      expect(sharedArrival('mailto:a@example.com'), isNull);
      expect(sharedArrival([1, 2]), isNull);
      final a = sharedArrival({'files': 'x', 'to': 'a@example.com'});
      expect((a as ComposeArrival).files, isEmpty);
      expect(a.link.to, isEmpty);
      final long = sharedArrival({'text': 'x' * 500000}) as ComposeArrival;
      expect(long.link.body.length, MailtoLink.maxBody);
    });
  });

  group('the platform side', () {
    const channel = Arrivals.channel;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    Future<void> fromPlatform(String method, [Object? arguments]) async {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
    }

    test('later launches, the tray and shares reach one listener, '
        'and wait for it', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final arrivals = Arrivals.test();
      await arrivals.start();
      expect(calls, ['ready']);

      await fromPlatform('open', ['mailto:a@example.com', 42, '--flag']);
      await fromPlatform('compose');
      await fromPlatform('shared', {'eml': '/tmp/x'});
      await fromPlatform('unknown', 'x');

      final got = <Arrival>[];
      final stop = arrivals.listen(got.add);
      expect(got, hasLength(3));
      expect((got[0] as ComposeArrival).link.to, ['a@example.com']);
      expect((got[1] as ComposeArrival).link.isEmpty, isTrue);
      expect((got[2] as EmlArrival).path, '/tmp/x');

      arrivals.mailto(Uri.parse('mailto:b@example.com'));
      expect((got.last as ComposeArrival).link.to, ['b@example.com']);
      stop();
      arrivals.compose();
      expect(got, hasLength(4));
    });

    test('never an endless queue before the inbox listens', () {
      final arrivals = Arrivals.test();
      for (var i = 0; i < 100; i++) {
        arrivals.compose();
      }
      final got = <Arrival>[];
      arrivals.listen(got.add);
      expect(got, hasLength(16));
    });
  });

  group('the message', () {
    const account = MailAccount(
      id: 7,
      name: 'Work',
      email: 'me@example.com',
      color: Color(0xFF000000),
    );

    test('what the link says, from the account picked', () async {
      final link = MailtoLink.parse(
        'mailto:a@example.com?cc=b@example.com&subject=Hi&body=Text'
        '&in-reply-to=%3Cid@host%3E',
      )!;
      final (draft, left) = await draftFor(ComposeArrival(link: link), account);
      expect(draft.accountId, 7);
      expect(draft.to, ['a@example.com']);
      expect(draft.cc, ['b@example.com']);
      expect(draft.subject, 'Hi');
      expect(draft.body, 'Text');
      expect(draft.inReplyTo, '<id@host>');
      expect(draft.references, ['<id@host>']);
      expect(left, 0);
    });

    test('files up to what a message carries; the rest left out', () async {
      final sizes = {'/a': 10, '/b': maxDraftFilesSize, '/c': 20, '/gone': 1};
      final (draft, left) = await draftFor(
        const ComposeArrival(
          files: [
            ArrivedFile('/a', 'a.txt'),
            ArrivedFile('/b', 'b.bin'),
            ArrivedFile('/c', '../c.txt'),
            ArrivedFile('/gone', 'gone.txt'),
          ],
          tooLarge: 1,
        ),
        account,
        sizeOf: (p) async => sizes[p]!,
        openRead: (p) {
          if (p == '/gone') throw const FileSystemException('gone');
          return Stream.value(List.filled(sizes[p]!, 1));
        },
      );
      expect(draft.files.map((f) => (f.name, f.data.length)), [
        ('a.txt', 10),
        ('_c.txt', 20),
      ]);
      expect(left, 3);
    });

    test('what is read counts, not the size a file reports', () async {
      // Like a file in /proc: it says 0 and holds more than a message.
      const chunk = 1024 * 1024;
      var given = 0;
      final (draft, left) = await draftFor(
        const ComposeArrival(
          files: [ArrivedFile('/proc/x', 'x'), ArrivedFile('/small', 's')],
        ),
        account,
        sizeOf: (p) async => 0,
        openRead: (p) async* {
          if (p == '/small') {
            yield [1, 2, 3];
            return;
          }
          while (true) {
            given += chunk;
            yield List.filled(chunk, 0);
          }
        },
      );
      expect(draft.files.map((f) => (f.name, f.data.length)), [('s', 3)]);
      expect(left, 1);
      // It stopped reading once past the cap.
      expect(given, lessThanOrEqualTo(maxDraftFilesSize + chunk));
    });
  });
}
