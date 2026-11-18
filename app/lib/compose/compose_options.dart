import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../widgets/dialog.dart' show showPiumaPopover, showPiumaSheet;

/// What a message can be set to beside its text, from the foot of
/// compose.
enum ComposeOption {
  plainText,
  highPriority,
  readReceipt,

  /// Picks pictures to put inside the text (attached in plain text).
  insertPicture,

  /// Puts the clipboard's picture inside the text, as Ctrl+V does.
  pastePicture,
}

/// The foot's options: plain text, high priority and asking for a read
/// receipt, each switched on or off from a small menu. Soft while any of
/// them is on, as Templates is while open.
class ComposeOptionsButton extends StatelessWidget {
  const ComposeOptionsButton({
    super.key,
    required this.plainText,
    required this.highPriority,
    required this.readReceipt,
    required this.onToggle,
    this.phone = false,
  });

  final bool plainText;
  final bool highPriority;
  final bool readReceipt;
  final ValueChanged<ComposeOption> onToggle;
  final bool phone;

  bool get _any => plainText || highPriority || readReceipt;

  Future<void> _open(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? Rect.zero
        : box.localToGlobal(Offset.zero) & box.size;
    Widget menu(BuildContext menu) => _OptionsMenu(
      phone: phone,
      items: [
        (ComposeOption.plainText, l.composePlainText, plainText),
        (ComposeOption.highPriority, l.composeHighPriority, highPriority),
        (ComposeOption.readReceipt, l.composeReadReceipt, readReceipt),
        (ComposeOption.insertPicture, l.composeInsertPicture, null),
        (ComposeOption.pastePicture, l.composePastePicture, null),
      ],
      onPick: (o) => Navigator.of(menu).pop(o),
    );
    final picked = phone
        ? await showPiumaSheet<ComposeOption>(
            context,
            label: l.composeOptions,
            builder: menu,
          )
        : await showPiumaPopover<ComposeOption>(
            context,
            label: l.composeOptions,
            anchor: anchor,
            width: 260,
            grow: true,
            builder: menu,
          );
    if (picked != null) onToggle(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    final on = [
      if (plainText) l.composePlainText,
      if (highPriority) l.composeHighPriority,
      if (readReceipt) l.composeReadReceipt,
    ];
    final label = on.isEmpty
        ? l.composeOptions
        : '${l.composeOptions}: ${on.join(', ')}';
    return Tooltip(
      message: label,
      child: Builder(
        builder: (context) => PiumaPressable(
          onTap: () => _open(context),
          semanticLabel: label,
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _any ? c.soft : c.soft.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(PiumaRadius.button),
            ),
            child: PiumaIconView(
              PiumaIcon.sliders,
              size: 18,
              color: _any ? c.accentText : c.fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// The options as menu rows, each with a check while it is on.
class _OptionsMenu extends StatelessWidget {
  const _OptionsMenu({
    required this.items,
    required this.onPick,
    this.phone = false,
  });

  /// Each option, its name, and whether it is on (null for an action).
  final List<(ComposeOption, String, bool?)> items;
  final ValueChanged<ComposeOption> onPick;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (option, text, on)) in items.indexed) ...[
          if (on == null && items[i - 1].$3 != null)
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: PiumaSpace.s4),
              color: c.line,
            ),
          PiumaEnter(
            index: i,
            child: Semantics(
              toggled: on,
              child: PiumaPressable(
                onTap: () => onPick(option),
                semanticLabel: text,
                child: ExcludeSemantics(
                  child: Container(
                    constraints: BoxConstraints(minHeight: phone ? 44 : 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: PiumaSpace.s4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: phone ? 15 : 13,
                              color: c.fg,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox.square(
                          dimension: 16,
                          child: switch (on) {
                            true => PiumaIconView(
                              PiumaIcon.check,
                              size: 16,
                              color: c.accentText,
                            ),
                            false => null,
                            null => PiumaIconView(
                              option == ComposeOption.insertPicture
                                  ? PiumaIcon.image
                                  : PiumaIcon.copy,
                              size: 15,
                              color: c.muted,
                            ),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Over the foot while any option is on: which ones, in words ("Plain
/// text · High priority · Read receipt asked for"), so the message says
/// how it will go without opening the menu.
class ComposeOptionsLine extends StatelessWidget {
  const ComposeOptionsLine({
    super.key,
    required this.plainText,
    required this.highPriority,
    required this.readReceipt,
  });

  final bool plainText;
  final bool highPriority;
  final bool readReceipt;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final on = [
      if (plainText) l.composePlainText,
      if (highPriority) l.composeHighPriority,
      if (readReceipt) l.composeReadReceiptAsked,
    ];
    if (on.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: PiumaIconView(PiumaIcon.sliders, size: 13, color: c.muted),
          ),
          const SizedBox(width: PiumaSpace.s8),
          Expanded(
            child: Text(
              on.join(' · '),
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}
