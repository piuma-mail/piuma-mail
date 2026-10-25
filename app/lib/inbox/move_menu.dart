import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/dialog.dart';

/// "Move to…" of `AccountFolders`: the inbox and the folders of the
/// message's own account; typing filters them, Enter takes the first.
/// Returns the folder picked, or null.
Future<AccountFolder?> showMoveTo(
  BuildContext context, {
  required MailSource source,
  required MailAccount account,
  required String from,
  Rect? anchor,
  bool phone = false,
}) async {
  final l = AppLocalizations.of(context);
  final own = await source.folders(account.id);
  if (!context.mounted) return null;
  final targets = [
    if (from != 'INBOX') AccountFolder(mailbox: 'INBOX', name: l.inbox),
    for (final f in own)
      if (f.mailbox != from) f,
  ];
  final menu = MoveMenu(
    account: account,
    targets: targets,
    hint: l.moveToIn(account.name),
    phone: phone,
  );
  if (phone) {
    return showPiumaSheet<AccountFolder>(
      context,
      label: l.moveTo,
      builder: (_) => menu,
    );
  }
  if (anchor == null) {
    // From the keyboard there is no button to hang it from.
    return showPiumaDialog<AccountFolder>(
      context,
      label: l.moveTo,
      width: 340,
      builder: (_) => menu,
    );
  }
  return showPiumaPopover<AccountFolder>(
    context,
    label: l.moveTo,
    anchor: anchor,
    builder: (_) => menu,
  );
}

class MoveMenu extends StatefulWidget {
  const MoveMenu({
    super.key,
    required this.account,
    required this.targets,
    required this.hint,
    this.phone = false,
  });

  final MailAccount account;

  /// What the empty search field says.
  final String hint;

  /// Where the message can go, in tree order.
  final List<AccountFolder> targets;
  final bool phone;

  @override
  State<MoveMenu> createState() => _MoveMenuState();
}

class _MoveMenuState extends State<MoveMenu> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// With words typed, the matching folders, flat; else the whole tree,
  /// with the folders that only hold others shown but not taken.
  List<AccountFolder> get _shown {
    final q = _field.text.trim().toLowerCase();
    if (q.isEmpty) return widget.targets;
    return [
      for (final f in widget.targets)
        if (f.selectable && f.name.toLowerCase().contains(q))
          AccountFolder(mailbox: f.mailbox, name: f.name, unread: f.unread),
    ];
  }

  void _pick(AccountFolder f) => Navigator.of(context).pop(f);

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final shown = _shown;
    final pad = widget.phone ? 20.0 : 0.0;
    // The search field needs a Material above it in a popover too.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.phone)
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  PiumaIconView(PiumaIcon.search, size: 16, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _field,
                      autofocus: !widget.phone,
                      onChanged: (_) => setState(() {}),
                      // Enter takes the first folder that matches.
                      onSubmitted: (_) {
                        final first = _shown.where((f) => f.selectable);
                        if (first.isNotEmpty) _pick(first.first);
                      },
                      style: PiumaType.body.copyWith(color: c.fg),
                      cursorColor: c.accent,
                      decoration: InputDecoration.collapsed(
                        hintText: widget.hint,
                        hintStyle: PiumaType.body.copyWith(color: c.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (shown.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(pad + 12, 10, pad + 12, 10),
              child: Text(
                _field.text.trim().isEmpty
                    ? l.noOtherFolders(widget.account.name)
                    : l.noFoldersMatch,
                style: PiumaType.small.copyWith(color: c.muted),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: pad),
                children: [
                  for (final f in shown)
                    _Target(
                      folder: f,
                      phone: widget.phone,
                      onTap: f.selectable ? () => _pick(f) : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Target extends StatelessWidget {
  const _Target({required this.folder, this.onTap, this.phone = false});
  final AccountFolder folder;
  final VoidCallback? onTap;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final inbox = folder.mailbox == 'INBOX';
    final row = Container(
      height: phone ? 48 : 40,
      padding: EdgeInsets.only(left: 12.0 + folder.depth * 20, right: 12),
      child: Row(
        children: [
          PiumaIconView(
            inbox ? PiumaIcon.inbox : PiumaIcon.folder,
            size: 16,
            color: c.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PiumaType.body.copyWith(
                color: onTap == null ? c.muted : c.fg,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: folder.name,
      child: _Hover(child: row),
    );
  }
}

/// The soft tint of the canvas under the pointer.
class _Hover extends StatefulWidget {
  const _Hover({required this.child});
  final Widget child;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _on = true),
      onExit: (_) => setState(() => _on = false),
      child: AnimatedContainer(
        duration: instant ? Duration.zero : PiumaMotion.press,
        curve: PiumaMotion.curve,
        decoration: BoxDecoration(
          color: _on ? c.sel : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: widget.child,
      ),
    );
  }
}
