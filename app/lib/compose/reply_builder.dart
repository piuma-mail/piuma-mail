import 'dart:typed_data';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import 'quoting.dart';
import 'rich_body.dart' show bulletPrefix;

/// Who an answer goes to.
enum ReplyMode {
  /// Reply: the author (every Reply-To address when there are some). The
  /// default everywhere: Reply all is one tap away, never the first one,
  /// so a quick answer can't land on a whole list by accident.
  sender,

  /// Reply all: the author and everyone else on To and Cc, or the
  /// Mail-Followup-To the author asked for; never the person's own
  /// addresses.
  all,

  /// Reply to list: the list's posting address (List-Post).
  list,
}

/// The drafts Reply, Reply all, Forward and Edit as new open with, made
/// from the message and what the engine says about its recipients
/// ([MailEnvelope]). Nothing here sends: the draft goes to compose, or to
/// whatever sends it.
class ReplyBuilder {
  const ReplyBuilder(
    this.l,
    this.locale, {
    this.settings = const ComposeSettings(),
    this.accounts = const [],
  });

  final AppLocalizations l;
  final String locale;

  /// Settings › Writing: where a reply is written, what it quotes, and the
  /// accounts that write plain text.
  final ComposeSettings settings;

  /// The person's accounts, for the address of a message's own account.
  final List<MailAccount> accounts;

  /// A message from [row]'s account, or from [fromEmail], is plain text
  /// (Settings › Writing): its draft keeps no formatting.
  bool plainText(MailRow row, String? fromEmail) =>
      settings.plainTextFor(fromEmail ?? '') ||
      settings.plainTextFor(
        accounts.where((a) => a.id == row.accountId).firstOrNull?.email ?? '',
      );

  /// Who [mode] writes to, as compose writes addresses. Without an
  /// envelope (mail kept before its headers were read, offline), every
  /// mode falls back to the sender.
  static ({List<String> to, List<String> cc}) recipients(
    MailRow row,
    MailEnvelope? envelope,
    ReplyMode mode,
  ) {
    if (envelope != null) {
      if (mode == ReplyMode.all && envelope.replyAllTo.isNotEmpty) {
        return (to: envelope.replyAllTo, cc: envelope.replyAllCc);
      }
      if (mode == ReplyMode.list && envelope.listPost != null) {
        return (to: [envelope.listPost!], cc: const []);
      }
      if (envelope.replyTo.isNotEmpty) {
        return (to: envelope.replyTo, cc: const []);
      }
    }
    final sender = row.replyTo.isNotEmpty
        ? row.replyTo
        : row.fromName.isNotEmpty
        ? '${row.fromName} <${row.fromEmail}>'
        : row.fromEmail;
    return (to: [sender], cc: const []);
  }

  /// "Re: " before a subject that doesn't have it yet.
  static String replySubject(String subject) =>
      RegExp(r'^\s*re:', caseSensitive: false).hasMatch(subject)
      ? subject
      : 'Re: $subject';

  /// "Fwd: " before a subject that doesn't have it yet.
  static String forwardSubject(String subject) =>
      RegExp(r'^\s*fwd?:', caseSensitive: false).hasMatch(subject)
      ? subject
      : 'Fwd: $subject';

  /// An answer to [row], whose text is [body]: [text], then the message
  /// quoted unless [quote] is off (above it with
  /// [ComposeSettings.replyBelow]). With [ComposeSettings.quoteSelection],
  /// only the [selection] made in the reader is quoted, when it is part of
  /// [body]. [to] replaces the recipients (Write again).
  Draft reply(
    MailRow row,
    String body, {
    MailEnvelope? envelope,
    ReplyMode mode = ReplyMode.sender,
    String text = '',
    String? fromEmail,
    int? signatureId,
    List<String>? to,
    bool quote = true,
    String? selection,
  }) {
    final when = DateFormat.yMMMd(locale).add_Hm().format(row.receivedAt);
    final quoted = quoteLines(
      quoteSource(body, selection, trim: settings.quoteSelection),
    );
    final going = to != null
        ? (to: to, cc: const <String>[])
        : recipients(row, envelope, mode);
    return Draft(
      accountId: row.accountId,
      fromEmail: fromEmail,
      to: going.to,
      cc: going.cc,
      subject: replySubject(row.subject),
      body: quote
          ? replyBody(
              text: text,
              header: l.quoteHeader(when, row.sender),
              quoted: quoted,
              below: settings.replyBelow,
            )
          : text,
      inReplyTo: row.messageId.isEmpty ? '' : row.messageId,
      references: [
        ...row.references.split(' ').where((r) => r.isNotEmpty),
        if (row.messageId.isNotEmpty) row.messageId,
      ],
      signatureId: signatureId,
      plainText: plainText(row, fromEmail),
    );
  }

  /// Forward inline, as on `ForwardToApprove` (option A): the message
  /// under a "Forwarded message" block, keeping the bold, italic and links
  /// compose can show, lists and quotes as their line starts, and the rest
  /// as readable text. [blocks] is the message as the reader draws it;
  /// without them, its plain [text].
  Draft forward(
    MailRow row, {
    List<BodyBlock>? blocks,
    String text = '',
    MailEnvelope? envelope,
    String? fromEmail,
    String toLine = '',
    List<DraftFile> files = const [],
  }) {
    final date = l.forwardDate(
      DateFormat.yMMMMEEEEd(locale).format(row.receivedAt),
      DateFormat.Hm(locale).format(row.receivedAt),
    );
    final from = row.fromName.isNotEmpty
        ? '${row.fromName} <${row.fromEmail}>'
        : row.fromEmail;
    final to = switch (envelope) {
      final e? when e.to.isNotEmpty || e.cc.isNotEmpty => [
        ...e.to,
        ...e.cc,
      ].map((p) => p.address).join(', '),
      _ => toLine,
    };
    final head = '\n\n${l.forwardBlock(from, date, to, row.subject)}\n\n';
    final content = _content(row, blocks, text, fromEmail);
    return Draft(
      accountId: row.accountId,
      fromEmail: fromEmail,
      subject: forwardSubject(row.subject),
      body: '$head${content.text}',
      marks: [
        for (final m in content.marks)
          m.copyWith(start: m.start + head.length, end: m.end + head.length),
      ],
      files: files,
      forward: true,
      plainText: plainText(row, fromEmail),
    );
  }

  /// Forward as attachment: the whole message, as it came, attached as an
  /// `.eml` (message/rfc822) to an empty email.
  Draft forwardAsAttachment(MailRow row, Uint8List raw, {String? fromEmail}) =>
      Draft(
        accountId: row.accountId,
        fromEmail: fromEmail,
        subject: forwardSubject(row.subject),
        files: [DraftFile(emlName(row.subject), raw)],
        forward: true,
        plainText: plainText(row, fromEmail),
      );

  /// Edit as new: a new email with the message's recipients (not the
  /// person's own addresses), subject, text (with its formatting) and
  /// files, answering nothing.
  Draft editAsNew(
    MailRow row, {
    List<BodyBlock>? blocks,
    String text = '',
    MailEnvelope? envelope,
    String? fromEmail,
    List<DraftFile> files = const [],
  }) {
    final content = _content(row, blocks, text, fromEmail);
    final to = envelope == null
        ? [
            for (final a in row.waitingFor) a,
            if (row.waitingFor.isEmpty && row.to.contains('@'))
              ...row.to.split(',').map((a) => a.trim()),
          ]
        : [
            for (final p in envelope.to)
              if (!p.you) p.address,
          ];
    return Draft(
      accountId: row.accountId,
      fromEmail: fromEmail,
      to: to,
      cc: [
        for (final p in envelope?.cc ?? const <MailPerson>[])
          if (!p.you) p.address,
      ],
      subject: row.subject,
      body: content.text,
      marks: content.marks,
      files: files,
      plainText: plainText(row, fromEmail),
    );
  }

  /// What Forward and Edit as new carry of the message: its [blocks] with
  /// their formatting, or its plain [text]; never a picture's placeholder
  /// character (U+FFFC), and no formatting from a plain-text account.
  ({String text, List<BodyMark> marks}) _content(
    MailRow row,
    List<BodyBlock>? blocks,
    String text,
    String? fromEmail,
  ) {
    final content = blocks != null && blocks.isNotEmpty
        ? formatted(blocks)
        : (
            text: withoutPlaceholders(text)
                .replaceAll('\r\n', '\n')
                .trimRight(),
            marks: const <BodyMark>[],
          );
    return plainText(row, fromEmail)
        ? (text: content.text, marks: const <BodyMark>[])
        : content;
  }

  /// A file name for a message saved or attached whole: its subject,
  /// without the characters file systems refuse.
  static String emlName(String subject) {
    var name = subject
        // Control and direction characters: a name that reads one way
        // and opens as another ("invoice\u202Elme.exe").
        .replaceAll(
          RegExp(
            r'[\u0000-\u001F\u007F-\u009F\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
          ),
          '',
        )
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Cut by what shows as one character, never inside a surrogate pair
    // or an emoji.
    if (name.characters.length > 80) {
      name = name.characters.take(80).toString().trimRight();
    }
    if (name.isEmpty || name.replaceAll('.', '').isEmpty) name = 'message';
    return '$name.eml';
  }

  /// The reader's blocks as compose's text: bold, italic and links as
  /// marks; headings in bold; lists with their bullet or number; quotes
  /// with "> "; pictures by their description; code as it is.
  static ({String text, List<BodyMark> marks}) formatted(
    List<BodyBlock> blocks,
  ) {
    final out = StringBuffer();
    final marks = <BodyMark>[];
    var first = true;
    BodyBlock? last;
    for (final b in blocks) {
      final lines = _blockLines(b);
      if (lines == null) continue;
      // List items and lines of one quote follow each other; anything else
      // has a blank line before it.
      final together =
          last != null &&
          ((b.kind == BlockKind.listItem && last.kind == BlockKind.listItem) ||
              (b.kind == BlockKind.code && last.kind == BlockKind.code));
      if (!first) out.write(together ? '\n' : '\n\n');
      first = false;
      last = b;
      final prefix = '> ' * b.quote;
      final lead = switch (b.kind) {
        BlockKind.listItem =>
          '${'  ' * (b.level > 0 ? b.level - 1 : 0)}'
              '${b.marker.isEmpty || b.marker == '•' ? bulletPrefix : '${b.marker} '}',
        _ => '',
      };
      out.write(prefix);
      out.write(lead);
      for (final span in lines) {
        final start = out.length;
        // A quote's later lines keep their "> ".
        out.write(withoutPlaceholders(span.text).replaceAll('\n', '\n$prefix'));
        final end = out.length;
        if (end > start) {
          if (span.bold || b.kind == BlockKind.heading) {
            marks.add(BodyMark(BodyMarkKind.bold, start, end));
          }
          if (span.italic) marks.add(BodyMark(BodyMarkKind.italic, start, end));
          if (span.link case final url? when url.isNotEmpty) {
            marks.add(BodyMark(BodyMarkKind.link, start, end, url));
          }
        }
      }
    }
    return (text: out.toString(), marks: _merged(marks));
  }

  /// What a block writes, as spans; null for what has no words (a rule, a
  /// picture with no description).
  static List<BodySpan>? _blockLines(BodyBlock b) {
    switch (b.kind) {
      case BlockKind.rule:
        return null;
      case BlockKind.image:
        final alt = b.image?.alt.trim() ?? '';
        if (alt.isEmpty) return null;
        return [BodySpan('[$alt]', link: b.image?.link)];
      default:
        final spans = [
          for (final s in b.spans)
            if (withoutPlaceholders(s.text).isNotEmpty) s,
        ];
        if (withoutPlaceholders(spans.map((s) => s.text).join())
            .trim()
            .isEmpty) {
          return null;
        }
        return spans;
    }
  }

  /// Marks of one kind that touch become one.
  static List<BodyMark> _merged(List<BodyMark> marks) {
    final out = <BodyMark>[];
    for (final m in marks) {
      final i = out.lastIndexWhere(
        (o) => o.kind == m.kind && o.url == m.url && o.end == m.start,
      );
      if (i >= 0) {
        out[i] = out[i].copyWith(end: m.end);
      } else {
        out.add(m);
      }
    }
    return out;
  }
}
