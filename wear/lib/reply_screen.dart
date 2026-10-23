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
class ReplyScreen extends StatelessWidget {
  const ReplyScreen({super.key, required this.row});

  final WatchRow row;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final link = LinkScope.of(context);
    final templates = link.summary?.templates ?? const <WatchTemplate>[];
    const c = watchColors;
    return Scaffold(
      backgroundColor: c.darkroom,
      body: RoundScroll(
        children: [
          Text(
            l.replyTo(row.sender),
            textAlign: TextAlign.center,
            maxLines: 1,
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
                final text = await link.speak(l.replyTo(row.sender));
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
          then: () => link.reply(row.payload, text),
        ),
      ),
    );
  }
}
