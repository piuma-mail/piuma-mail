import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/compose/reply_builder.dart';
import 'package:piuma_mail/inbox/recipients_line.dart';
import 'package:piuma_mail/l10n/app_localizations.dart';
import 'package:piuma_mail/mail/mail_source.dart';

final _l = lookupAppLocalizations(const Locale('en'));
final _b = ReplyBuilder(_l, 'en');

MailRow _row({String replyTo = '', String to = 'Matteo'}) => MailRow(
  accountId: 1,
  mailbox: 'INBOX',
  uid: 7,
  fromName: 'Anna Bo',
  fromEmail: 'anna@x.it',
  subject: 'Plan',
  preview: 'Hi',
  receivedAt: DateTime(2026, 10, 15, 9, 42),
  seen: true,
  messageId: '<p@x.it>',
  references: '<o@x.it>',
  replyTo: replyTo,
  to: to,
);

/// As the engine describes Anna's email to the person and Carla, with Dan
/// in Cc (`core/src/envelope.rs` leaves the person out of the answers).
const _envelope = MailEnvelope(
  to: [
    MailPerson('Matteo', 'me@studio.it', you: true),
    MailPerson('Carla', 'carla@x.it'),
  ],
  cc: [MailPerson('Dan', 'dan@x.it')],
  replyTo: ['desk@x.it', 'Bo <bo@x.it>'],
  replyAllTo: ['desk@x.it', 'Bo <bo@x.it>', 'Carla <carla@x.it>'],
  replyAllCc: ['Dan <dan@x.it>'],
  listPost: 'dev@lists.x.it',
);

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  group('who an answer goes to', () {
    test('Reply goes to every Reply-To address', () {
      final d = _b.reply(_row(), 'Hi', envelope: _envelope);
      expect(d.to, ['desk@x.it', 'Bo <bo@x.it>']);
      expect(d.cc, isEmpty);
      expect(d.subject, 'Re: Plan');
      expect(d.inReplyTo, '<p@x.it>');
      expect(d.references, ['<o@x.it>', '<p@x.it>']);
    });

    test('Reply all takes To and Cc as the engine worked them out', () {
      final d = _b.reply(
        _row(),
        'Hi',
        envelope: _envelope,
        mode: ReplyMode.all,
      );
      expect(d.to, ['desk@x.it', 'Bo <bo@x.it>', 'Carla <carla@x.it>']);
      expect(d.cc, ['Dan <dan@x.it>']);
    });

    test('Reply to list writes to the list alone', () {
      final d = _b.reply(
        _row(),
        'Hi',
        envelope: _envelope,
        mode: ReplyMode.list,
      );
      expect(d.to, ['dev@lists.x.it']);
      expect(d.cc, isEmpty);
    });

    test('without an envelope every answer goes to the sender', () {
      for (final mode in ReplyMode.values) {
        expect(_b.reply(_row(), 'Hi', mode: mode).to, ['Anna Bo <anna@x.it>']);
        expect(_b.reply(_row(replyTo: 'desk@x.it'), 'Hi', mode: mode).to, [
          'desk@x.it',
        ]);
      }
    });

    test('Reply all with nobody else falls back to Reply', () {
      const alone = MailEnvelope(
        to: [MailPerson('Matteo', 'me@studio.it', you: true)],
        replyTo: ['Anna Bo <anna@x.it>'],
        replyAllTo: [],
      );
      final d = _b.reply(_row(), 'Hi', envelope: alone, mode: ReplyMode.all);
      expect(d.to, ['Anna Bo <anna@x.it>']);
      expect(alone.others, 0);
    });

    test('others counts who Reply all adds, without case or names', () {
      expect(_envelope.others, 2);
      const same = MailEnvelope(
        replyTo: ['Anna <ANNA@x.it>'],
        replyAllTo: ['anna@x.it'],
      );
      expect(same.others, 0);
    });

    test('the quote keeps the message, with the date and the sender', () {
      final d = _b.reply(_row(), 'Line one\n\nLine two', text: 'Sure');
      expect(
        d.body,
        'Sure\n\nOn Oct 15, 2026 09:42, Anna Bo wrote:\n> Line one\n>\n> Line two',
      );
      expect(_b.reply(_row(), 'x', text: 'Sure', quote: false).body, 'Sure');
    });
  });

  group('the reader’s line', () {
    test('names the person first, then the others', () {
      expect(RecipientsLine.who(_envelope, _l), 'you, Carla, Dan');
      const many = MailEnvelope(
        to: [
          MailPerson('', 'me@studio.it', you: true),
          MailPerson('Carla Neri', 'carla@x.it'),
          MailPerson('', 'dan@x.it'),
        ],
        cc: [MailPerson('Eve', 'eve@x.it'), MailPerson('Carla', 'CARLA@x.it')],
      );
      expect(RecipientsLine.who(many, _l), 'you, Carla Neri and 2 others');
    });

    test('says when the person was a blind copy', () {
      const bcc = MailEnvelope(
        to: [MailPerson('Mum', 'mamma@posta.it')],
        bccYou: true,
      );
      expect(RecipientsLine.who(bcc, _l), 'Mum · you were Bcc’d');
      const nobody = MailEnvelope(bccYou: true);
      expect(RecipientsLine.who(nobody, _l), 'you');
    });
  });

  group('Forward', () {
    test('keeps bold, italic and links, lists and quotes', () {
      final blocks = [
        const BodyBlock(
          kind: BlockKind.heading,
          level: 1,
          spans: [BodySpan('Agenda')],
        ),
        const BodyBlock.text([
          BodySpan('Read '),
          BodySpan('this', bold: true),
          BodySpan(' and '),
          BodySpan('that', italic: true),
          BodySpan(': '),
          BodySpan('the plan', link: 'https://x.it/plan'),
        ]),
        const BodyBlock(
          kind: BlockKind.listItem,
          marker: '•',
          spans: [BodySpan('one')],
        ),
        const BodyBlock(
          kind: BlockKind.listItem,
          marker: '2.',
          spans: [BodySpan('two')],
        ),
        const BodyBlock(kind: BlockKind.rule),
        const BodyBlock(
          kind: BlockKind.image,
          image: BodyImage(alt: 'Logo'),
        ),
        const BodyBlock.text([BodySpan('Earlier words')], quote: 1),
      ];
      final f = ReplyBuilder.formatted(blocks);
      expect(
        f.text,
        'Agenda\n\nRead this and that: the plan\n\n• one\n2. two\n\n'
        '[Logo]\n\n> Earlier words',
      );
      String marked(BodyMark m) => f.text.substring(m.start, m.end);
      expect(
        [for (final m in f.marks) (m.kind, marked(m), m.url)],
        [
          (BodyMarkKind.bold, 'Agenda', ''),
          (BodyMarkKind.bold, 'this', ''),
          (BodyMarkKind.italic, 'that', ''),
          (BodyMarkKind.link, 'the plan', 'https://x.it/plan'),
        ],
      );
    });

    test('the marks follow the forwarded block', () {
      final d = _b.forward(
        _row(),
        blocks: [
          const BodyBlock.text([BodySpan('Big', bold: true)]),
        ],
        envelope: _envelope,
      );
      final mark = d.marks.single;
      expect(d.body.substring(mark.start, mark.end), 'Big');
      expect(
        d.body,
        contains(
          'To: Matteo <me@studio.it>, Carla <carla@x.it>, Dan <dan@x.it>\n',
        ),
      );
      expect(d.subject, 'Fwd: Plan');
      expect(d.forward, isTrue);
    });

    test('as attachment: the whole email as an .eml file', () {
      final raw = Uint8List.fromList([1, 2, 3]);
      final d = _b.forwardAsAttachment(_row(), raw, fromEmail: 'me@alias.it');
      expect(d.files.single.name, 'Plan.eml');
      expect(d.files.single.data, raw);
      expect(d.body, isEmpty);
      expect(d.fromEmail, 'me@alias.it');
    });

    test('file names leave out what file systems refuse', () {
      expect(ReplyBuilder.emlName('Re: a/b?  c'), 'Re_ a_b_ c.eml');
      expect(ReplyBuilder.emlName(''), 'message.eml');
      expect(ReplyBuilder.emlName('x' * 200).length, 84);
    });
  });

  test('Edit as new keeps recipients, subject, text and files', () {
    final file = DraftFile('a.pdf', Uint8List(3));
    final d = _b.editAsNew(
      _row(),
      blocks: [
        const BodyBlock.text([BodySpan('Hello', italic: true)]),
      ],
      envelope: _envelope,
      files: [file],
    );
    expect(d.to, ['Carla <carla@x.it>']);
    expect(d.cc, ['Dan <dan@x.it>']);
    expect(d.subject, 'Plan');
    expect(d.body, 'Hello');
    expect(d.marks.single.kind, BodyMarkKind.italic);
    expect(d.files.single, file);
    expect(d.inReplyTo, isNull);
  });
}
