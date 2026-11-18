import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart' show showPiumaDialog, showPiumaSheet;
import 'rich_body.dart' show quotePrefix;

/// Words that say a file comes with the message, in the app's six
/// languages and their usual forms.
final _attachmentWords = RegExp(
  r'(?<![\p{L}\p{N}])('
  // English
  r'attach(ed|ing|ment|ments)?|enclosed'
  // Italian
  r'|allegat[oaie]|allego|alleghiamo|allegando|in allegato'
  // German
  r'|anhang|anhängen|angehängt|anbei|beigefügt|beiliegend'
  // French
  r'|pièces? jointes?|ci-joint(e|es|s)?|en pj|joint(e|es|s)? à ce'
  // Spanish
  r'|adjunt[oa]s?|adjunto|adjuntamos|adjuntar|te adjunto'
  // Portuguese
  r'|anexos?|anexad[oa]s?|em anexo|segue anexo'
  r')(?![\p{L}\p{N}])',
  caseSensitive: false,
  unicode: true,
);

/// The person's own words in [body]: without quoted lines ("> ") and the
/// "On …, … wrote:" line before them, wherever the quote is.
String ownWords(String body) {
  final lines = body.split('\n');
  final kept = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('>')) continue;
    final next = i + 1 < lines.length ? lines[i + 1] : '';
    if (line.trimRight().endsWith(':') && next.startsWith('>')) continue;
    kept.add(line);
  }
  return kept.join('\n');
}

/// Whether [subject] or the person's own words in [body] say a file is
/// attached.
bool mentionsAttachment(String subject, String body) =>
    _attachmentWords.hasMatch(subject) ||
    _attachmentWords.hasMatch(ownWords(body));

/// Why compose asks before sending.
enum SendCheck { forgottenAttachment, noSubject }

/// What the person picked when asked before sending.
enum SendAnswer { send, fix }

/// The questions to ask before [d] goes, in order: a file mentioned and
/// none attached, then an empty subject.
List<SendCheck> sendChecks(Draft d) => [
  if (d.files.isEmpty &&
      d.images.isEmpty &&
      mentionsAttachment(d.subject, d.body))
    SendCheck.forgottenAttachment,
  if (d.subject.trim().isEmpty) SendCheck.noSubject,
];

/// Asks about [check] before sending, as Open anyway does for a risky
/// file: a dialog on the desktop, a sheet on the phone. Null when closed
/// without an answer.
Future<SendAnswer?> askBeforeSending(
  BuildContext context,
  SendCheck check, {
  required bool phone,
}) async {
  final l = AppLocalizations.of(context);
  final (icon, title, body, fix) = switch (check) {
    SendCheck.forgottenAttachment => (
      PiumaIcon.paperclip,
      l.sendForgotAttachmentTitle,
      l.sendForgotAttachmentBody,
      l.attachFile,
    ),
    SendCheck.noSubject => (
      PiumaIcon.mail,
      l.sendNoSubjectTitle,
      l.sendNoSubjectBody,
      l.sendAddSubject,
    ),
  };
  final answer = await askInCompose(
    context,
    icon: icon,
    title: title,
    body: body,
    main: fix,
    other: l.sendAnyway,
    phone: phone,
  );
  return switch (answer) {
    true => SendAnswer.fix,
    false => SendAnswer.send,
    null => null,
  };
}

/// Asks before turning the text into plain text, which loses its
/// formatting. True to go ahead.
Future<bool> askToMakePlain(BuildContext context, {required bool phone}) async {
  final l = AppLocalizations.of(context);
  return await askInCompose(
        context,
        icon: PiumaIcon.warning,
        title: l.composePlainTitle,
        body: l.composePlainBody,
        main: l.composePlainConfirm,
        other: l.cancel,
        phone: phone,
      ) ==
      true;
}

/// A question compose asks, laid out as Open anyway's: its [title] by an
/// [icon], a sentence, then [other] and the [main] answer. True for
/// [main], false for [other], null when closed.
Future<bool?> askInCompose(
  BuildContext context, {
  required PiumaIcon icon,
  required String title,
  required String body,
  required String main,
  required String other,
  required bool phone,
}) {
  Widget panel(BuildContext context) => _Question(
    icon: icon,
    title: title,
    body: body,
    main: main,
    other: other,
    phone: phone,
  );
  return phone
      ? showPiumaSheet<bool>(context, label: title, builder: panel)
      : showPiumaDialog<bool>(context, label: title, builder: panel);
}

class _Question extends StatelessWidget {
  const _Question({
    required this.icon,
    required this.title,
    required this.body,
    required this.main,
    required this.other,
    required this.phone,
  });

  final PiumaIcon icon;
  final String title;
  final String body;
  final String main;
  final String other;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final second = PiumaButton(
      label: other,
      kind: PiumaButtonKind.tertiary,
      onPressed: () => Navigator.of(context).pop(false),
    );
    final first = PiumaButton(
      label: main,
      onPressed: () => Navigator.of(context).pop(true),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: PiumaIconView(icon, size: 18, color: c.accentText),
            ),
            const SizedBox(width: PiumaSpace.s12),
            Expanded(
              child: Text(
                title,
                style: PiumaType.subtitle.copyWith(color: c.fg),
              ),
            ),
          ],
        ),
        const SizedBox(height: PiumaSpace.s16),
        Text(body, style: PiumaType.body.copyWith(color: c.fg)),
        const SizedBox(height: PiumaSpace.s24),
        if (phone) ...[
          first,
          const SizedBox(height: PiumaSpace.s8),
          second,
        ] else
          Wrap(
            alignment: WrapAlignment.end,
            spacing: PiumaSpace.s8,
            runSpacing: PiumaSpace.s8,
            children: [second, first],
          ),
      ],
    );
  }
}

/// A body made plain text: links written out after their words, quote
/// bars as "> ", pictures moved out of the text to be attached.
typedef PlainBody = ({String text, List<DraftFile> files});

/// Whether turning the body into plain text loses something: bold,
/// italic, links or pictures.
bool losesFormatting(List<BodyMark> marks, List<DraftImage> images) =>
    marks.isNotEmpty || images.isNotEmpty;

/// [text] with [marks] and [images] made plain: each link's address
/// follows its words ("menu (https://…)"), quoted lines start with "> ",
/// and each picture leaves the text to go as a file.
PlainBody toPlainBody(
  String text,
  List<BodyMark> marks,
  List<DraftImage> images,
) {
  final links = [
    for (final m in marks)
      if (m.kind == BodyMarkKind.link && m.url.isNotEmpty) m,
  ]..sort((a, b) => b.end.compareTo(a.end));
  var out = text;
  for (final m in links) {
    final end = m.end.clamp(0, out.length);
    final words = out.substring(m.start.clamp(0, end), end);
    if (words.trim() == m.url.trim()) continue;
    out = out.replaceRange(end, end, ' (${m.url})');
  }
  final lines = [
    for (final line in out.split('\n'))
      // A picture alone on its line takes the line with it.
      if (line != imagePlaceholder)
        line.startsWith(quotePrefix)
            ? '> ${line.substring(quotePrefix.length)}'
            : line == '│'
            ? '>'
            : line.replaceAll(imagePlaceholder, ''),
  ];
  return (
    text: lines.join('\n'),
    files: [for (final i in images) DraftFile(i.name, i.data)],
  );
}
