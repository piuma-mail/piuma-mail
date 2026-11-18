import 'package:flutter/material.dart';

import 'design/icons.dart';
import 'design/motion.dart';
import 'design/tokens.g.dart';
import 'done_screen.dart';
import 'l10n/app_localizations.dart';
import 'link.dart';
import 'round.dart';
import 'summary.dart';

/// Reply (`WatchWearOS` 4): speak, type or write with the watch's own
/// input, or send one of the person's templates. No suggested replies.
/// When others got the email too, "Reply all" switches the answer to
/// everyone; Reply stays the default.
class ReplyScreen extends StatefulWidget {
  const ReplyScreen({super.key, required this.row});

  final WatchRow row;

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  bool _all = false;

  WatchRow get row => widget.row;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final link = LinkScope.of(context);
    final templates = link.summary?.templates ?? const <WatchTemplate>[];
    const c = watchColors;
    final to = _all
        ? l.replyToAll(row.sender, row.others)
        : l.replyTo(row.sender);
    return Scaffold(
      backgroundColor: c.darkroom,
      body: RoundScroll(
        children: [
          Text(
            to,
            textAlign: TextAlign.center,
            // "Reply to Giulia Romano and 2 others" needs two lines.
            maxLines: _all ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: PiumaType.label.copyWith(letterSpacing: 0, color: c.muted),
          ),
          const SizedBox(height: 8),
          Center(
            child: RoundButton(
              icon: PiumaIcon.mic,
              label: l.speakOrType,
              size: 64,
              accent: true,
              onPressed: () async {
                final text = await link.speak(to);
                if (text == null || text.trim().isEmpty || !context.mounted) {
                  return;
                }
                _send(context, link, text.trim());
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l.speakOrType,
            textAlign: TextAlign.center,
            style: PiumaType.label.copyWith(letterSpacing: 0, color: c.muted),
          ),
          if (row.others > 0) ...[
            const SizedBox(height: 8),
            Semantics(
              toggled: _all,
              child: Pill(
                label: l.replyAll,
                icon: _all ? PiumaIcon.check : PiumaIcon.replyAll,
                trailing: _all ? null : '+${row.others}',
                center: true,
                onPressed: () => setState(() => _all = !_all),
              ),
            ),
          ],
          if (templates.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l.yourTemplates.toUpperCase(),
              textAlign: TextAlign.center,
              style: PiumaType.label.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
            const SizedBox(height: 4),
            for (final t in templates)
              Pill(
                label: t.label,
                center: true,
                onPressed: () => _send(context, link, t.body),
              ),
          ],
        ],
      ),
    );
  }

  void _send(BuildContext context, PhoneLink link, String text) {
    Navigator.of(context).pushReplacement(
      GrowRoute<void>(
        instant: reduceMotion(context),
        builder: (context) => DoneScreen(
          title: AppLocalizations.of(context).sent,
          detail: text,
          then: () => _all
              ? link.replyAll(row.payload, text)
              : link.reply(row.payload, text),
        ),
      ),
    );
  }
}
