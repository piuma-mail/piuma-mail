import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';

/// Settings › Shortcuts, as in `Settings` (desktop only): the few single
/// keys worth knowing; everything else is in the command palette.
class ShortcutsPage extends StatelessWidget {
  const ShortcutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = PiumaTheme.of(context);
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final palette = apple ? '⌘K' : 'Ctrl K';
    final line = l.shortcutsLine('\u0000').split('\u0000');
    final body = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 14,
      color: c.muted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.shortcutsTitle,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.84,
            color: c.fg,
          ),
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            style: body,
            children: [
              TextSpan(text: line.first),
              TextSpan(
                text: palette,
                style: PiumaType.mono.copyWith(color: c.muted),
              ),
              TextSpan(text: line.last),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Semantics(
          label: l.shortcutsTable,
          container: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                for (final (label, key) in [
                  (l.compose, 'C'),
                  (l.archive, 'E'),
                  (l.actionSnooze, 'H'),
                  (l.shortcutPalette, palette),
                  (l.actionReply, 'R'),
                ])
                  _Row(label: label, keys: key),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A shortcut: what it does on the left, its key cap on the right.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.keys});
  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 14,
                color: c.fg,
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 22),
            padding: const EdgeInsets.fromLTRB(7, 1, 7, 1),
            decoration: BoxDecoration(
              color: c.bg,
              border: Border(
                top: BorderSide(color: c.line),
                left: BorderSide(color: c.line),
                right: BorderSide(color: c.line),
                bottom: BorderSide(color: c.line, width: 2),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              keys,
              textAlign: TextAlign.center,
              style: PiumaType.mono.copyWith(color: c.fg),
            ),
          ),
        ],
      ),
    );
  }
}
