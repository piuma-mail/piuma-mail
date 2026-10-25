import 'package:flutter/widgets.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';

/// Avatar with initials and, if given, the account color dot.
class PiumaAvatar extends StatelessWidget {
  const PiumaAvatar({
    super.key,
    required this.initials,
    this.accountColor,
    this.ringColor,
    this.size = 32,
  });

  final String initials;
  final Color? accountColor;

  /// Ring color around the dot: the background the row sits on.
  final Color? ringColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: size * 0.375,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
          ),
          if (accountColor != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accountColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor ?? c.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Message list row, as in the canvas design system.
class MessageRow extends StatelessWidget {
  const MessageRow({
    super.key,
    required this.initials,
    required this.from,
    required this.time,
    required this.subject,
    required this.preview,
    required this.accountColor,
    this.unread = false,
    this.selected = false,
    this.onTap,
  });

  final String initials, from, time, subject, preview;
  final Color accountColor;
  final bool unread, selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final weight = unread
        ? FontWeight.w600
        : selected
        ? FontWeight.w500
        : FontWeight.w400;
    final bg = selected ? c.sel : const Color(0x00000000);
    const ellipsis = TextOverflow.ellipsis;

    return Semantics(
      selected: selected,
      label: unread ? AppLocalizations.of(context).messageUnread : null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(PiumaRadius.row),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PiumaAvatar(
                initials: initials,
                accountColor: accountColor,
                ringColor: selected ? c.sel : c.surface,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            from,
                            maxLines: 1,
                            overflow: ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: weight,
                              color: c.fg,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      subject,
                      maxLines: 1,
                      overflow: ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: weight,
                        color: c.fg,
                      ),
                    ),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
