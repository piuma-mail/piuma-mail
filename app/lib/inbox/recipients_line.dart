import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// Who received a message, under the sender's name: "to you, Carla and 3
/// others · today at 09:42", which opens into the whole To and Cc, so the
/// person sees who Reply all writes to. A blind copy says so.
class RecipientsLine extends StatefulWidget {
  const RecipientsLine({
    super.key,
    required this.envelope,
    required this.line,
    this.fontSize = 13,
  });

  final MailEnvelope envelope;

  /// The whole line for "who": `to {who} · today at 09:42`.
  final String Function(String who) line;
  final double fontSize;

  /// "you, Carla and 3 others": the person first, then the others by
  /// first name, two at most before the count.
  static String who(MailEnvelope e, AppLocalizations l) {
    final seen = <String>{};
    var you = false;
    final others = <String>[];
    for (final p in [...e.to, ...e.cc]) {
      if (p.you) {
        you = true;
      } else if (seen.add(p.email.toLowerCase())) {
        others.add(p.name.trim().isEmpty ? p.email : p.name.trim());
      }
    }
    final names = [if (you || others.isEmpty) l.recipientYou, ...others];
    final who = names.length <= 3
        ? names.join(', ')
        : l.recipientsMore(names.take(2).join(', '), names.length - 2);
    return e.bccYou && others.isNotEmpty ? '$who · ${l.recipientsBcc}' : who;
  }

  @override
  State<RecipientsLine> createState() => _RecipientsLineState();
}

class _RecipientsLineState extends State<RecipientsLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final e = widget.envelope;
    final style = TextStyle(
      fontSize: widget.fontSize,
      height: 1.35,
      color: c.muted,
    );
    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            widget.line(RecipientsLine.who(e, l)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 2),
        AnimatedRotation(
          turns: _open ? 0.5 : 0,
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          child: PiumaIconView(PiumaIcon.chevronDown, size: 14, color: c.muted),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: PiumaPressable(
            onTap: () => setState(() => _open = !_open),
            semanticLabel: _open ? l.hideRecipients : l.showRecipients,
            child: line,
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: PiumaSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.to.isNotEmpty) _list(l.recipientsTo, e.to, c),
                if (e.cc.isNotEmpty) _list(l.recipientsCc, e.cc, c),
                if (e.bccYou)
                  _list(l.recipientsBccLabel, [
                    MailPerson(l.recipientYou, '', you: true),
                  ], c),
              ],
            ),
          ),
      ],
    );
  }

  /// "Cc  Dan `<dan@x.it>`, Eve `<eve@x.it>`": selectable, every address
  /// whole.
  Widget _list(String label, List<MailPerson> people, PiumaColors c) {
    final size = widget.fontSize;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: size * 2.6),
            child: Text(
              label,
              style: TextStyle(fontSize: size, height: 1.35, color: c.muted),
            ),
          ),
          const SizedBox(width: PiumaSpace.s8),
          Expanded(
            child: SelectableText(
              [
                for (final p in people)
                  p.email.isEmpty
                      ? p.name
                      : p.name.trim().isEmpty
                      ? p.email
                      : '${p.name.trim()} <${p.email}>',
              ].join(', '),
              style: TextStyle(fontSize: size, height: 1.35, color: c.fg),
            ),
          ),
        ],
      ),
    );
  }
}
