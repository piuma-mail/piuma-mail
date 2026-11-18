import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/dialog.dart';
import '../widgets/segments.dart';
import '../widgets/switch.dart';

/// Settings › Reading › Lists: how lists are sorted, whether they group
/// conversations, and what each swipe does on phones and tablets. Built
/// from the page's existing parts: segments, a card of rows, a switch.
class ListOptions extends StatelessWidget {
  const ListOptions({super.key, required this.source, this.phone = false});

  final MailSource source;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final heading = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: c.muted,
    );
    return ValueListenableBuilder<ListPrefs>(
      valueListenable: source.listPrefs,
      builder: (context, prefs, _) {
        void set(ListPrefs next) => source.setListPrefs(next);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(l.listsHeading, style: heading),
            ),
            const SizedBox(height: 10),
            Text(l.listOrder, style: PiumaType.body.copyWith(color: c.fg)),
            const SizedBox(height: PiumaSpace.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: PiumaSegments(
                label: l.listOrder,
                items: [
                  for (final (order, label) in [
                    (ListOrder.newest, l.orderNewest),
                    (ListOrder.oldest, l.orderOldest),
                    (ListOrder.sender, l.orderSender),
                  ])
                    (
                      label,
                      prefs.order == order,
                      () => set(prefs.copyWith(order: order)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: PiumaSpace.s16),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _Line(
                    label: l.listThreads,
                    hint: prefs.threads ? null : l.listThreadsNote,
                    trailing: PiumaSwitch(
                      value: prefs.threads,
                      label: l.listThreads,
                      onChanged: (on) => set(prefs.copyWith(threads: on)),
                    ),
                  ),
                  _SwipeLine(
                    label: l.swipeRight,
                    choice: prefs.swipeRight,
                    phone: phone,
                    onPick: (choice) => set(prefs.copyWith(swipeRight: choice)),
                  ),
                  _SwipeLine(
                    label: l.swipeLeft,
                    choice: prefs.swipeLeft,
                    phone: phone,
                    onPick: (choice) => set(prefs.copyWith(swipeLeft: choice)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PiumaSpace.s8),
            Text(l.swipeNote, style: PiumaType.small.copyWith(color: c.muted)),
          ],
        );
      },
    );
  }
}

/// What a swipe choice is called.
String swipeName(AppLocalizations l, SwipeChoice choice) => switch (choice) {
  SwipeChoice.archive => l.archive,
  SwipeChoice.snooze => l.actionSnooze,
  SwipeChoice.delete => l.actionDelete,
  SwipeChoice.read => l.swipeRead,
  SwipeChoice.star => l.swipeStar,
  SwipeChoice.move => l.swipeMove,
  SwipeChoice.nothing => l.swipeNothing,
};

/// A row of the card: its words (and a line under them) and what sits on
/// the right.
class _Line extends StatelessWidget {
  const _Line({required this.label, required this.trailing, this.hint});

  final String label;
  final String? hint;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: PiumaType.body.copyWith(color: c.fg)),
                  if (hint case final hint?)
                    Text(hint, style: PiumaType.small.copyWith(color: c.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// "Swipe right" or "Swipe left", with what it does; a tap opens the
/// choices.
class _SwipeLine extends StatelessWidget {
  const _SwipeLine({
    required this.label,
    required this.choice,
    required this.onPick,
    this.phone = false,
  });

  final String label;
  final SwipeChoice choice;
  final ValueChanged<SwipeChoice> onPick;
  final bool phone;

  Future<void> _open(BuildContext button) async {
    final l = AppLocalizations.of(button);
    final c = PiumaTheme.of(button);
    final box = button.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero) & box.size;
    Widget menu(BuildContext menu) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in SwipeChoice.values)
          PiumaPressable(
            onTap: () => Navigator.of(menu).pop(option),
            semanticLabel: swipeName(l, option),
            child: ExcludeSemantics(
              child: Container(
                constraints: BoxConstraints(minHeight: phone ? 48 : 36),
                padding: EdgeInsets.symmetric(
                  horizontal: phone ? 20 : 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        swipeName(l, option),
                        style: PiumaType.body.copyWith(color: c.fg),
                      ),
                    ),
                    if (option == choice)
                      PiumaIconView(
                        PiumaIcon.check,
                        size: 14,
                        color: c.accentText,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    final picked = phone
        ? await showPiumaSheet<SwipeChoice>(button, label: label, builder: menu)
        : await showPiumaPopover<SwipeChoice>(
            button,
            label: label,
            anchor: at,
            width: 240,
            end: true,
            builder: menu,
          );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Builder(
      builder: (button) => PiumaPressable(
        onTap: () => _open(button),
        semanticLabel: '$label: ${swipeName(l, choice)}',
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: _Line(
            label: label,
            trailing: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    swipeName(l, choice),
                    style: PiumaType.body.copyWith(color: c.muted),
                  ),
                  const SizedBox(width: 6),
                  PiumaIconView(
                    PiumaIcon.chevronDown,
                    size: 14,
                    color: c.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
