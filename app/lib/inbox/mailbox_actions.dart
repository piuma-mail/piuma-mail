import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/text_field.dart';

/// The pieces of managing the mailbox that several screens share: the
/// questions asked before what can't be undone (deleting for good,
/// emptying Trash or spam, deleting a folder), renaming a folder, rows
/// dragged onto a folder, and which folder does which job. Built from the
/// existing dialog, sheet, button and field components.

/// A question before something that can't be undone: [title], [note]
/// under it, Cancel and [confirm] in danger red. A sheet on the phone, a
/// dialog elsewhere. True when confirmed.
Future<bool> askToConfirm(
  BuildContext context, {
  required String title,
  required String note,
  required String confirm,
  bool phone = false,
}) async {
  final c = PiumaTheme.of(context);
  final l = AppLocalizations.of(context);
  Widget panel(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: PiumaType.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(height: PiumaSpace.s8),
        Text(note, style: PiumaType.body.copyWith(color: c.muted)),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: PiumaSpace.s8,
          runSpacing: PiumaSpace.s8,
          children: [
            PiumaButton(
              label: l.cancel,
              kind: PiumaButtonKind.tertiary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            PiumaButton(
              label: confirm,
              kind: PiumaButtonKind.danger,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ],
    ),
  );
  final yes = phone
      ? await showPiumaSheet<bool>(context, label: title, builder: panel)
      : await showPiumaDialog<bool>(context, label: title, builder: panel);
  return yes ?? false;
}

/// "Delete for good?" for [count] emails in Trash or spam.
Future<bool> confirmDeleteForever(
  BuildContext context, {
  required int count,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  return askToConfirm(
    context,
    title: l.deleteForeverTitle(count),
    note: l.deleteForeverNote,
    confirm: l.deleteForever,
    phone: phone,
  );
}

/// "Empty Trash" or "Empty spam": how many go, then Empty.
Future<bool> confirmEmpty(
  BuildContext context, {
  required String folder,
  required int count,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  return askToConfirm(
    context,
    title: l.emptyTitle(count, folder),
    note: l.deleteForeverNote,
    confirm: l.emptyConfirm,
    phone: phone,
  );
}

/// "Delete “Clients”?": where its emails go, whether its subfolders go
/// too, and that the folder can't come back.
Future<bool> confirmDeleteFolder(
  BuildContext context, {
  required String name,
  required int emails,
  required int subfolders,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  return askToConfirm(
    context,
    title: l.folderDeleteTitle(name),
    note: [
      l.folderDeleteEmails(emails),
      if (subfolders > 0) l.folderDeleteSubfolders(subfolders),
      l.folderDeleteEnd,
    ].join(' '),
    confirm: l.folderDelete,
    phone: phone,
  );
}

/// "Rename “Clients”": the name in a field, Rename. Returns the new name,
/// or null when nothing changed.
Future<String?> askFolderName(
  BuildContext context, {
  required String name,
  bool phone = false,
}) {
  final title = AppLocalizations.of(context).folderRenameTitle(name);
  // The field is a Material text field: it needs a Material under it.
  Widget panel(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: _FolderName(name: name, title: title, phone: phone),
  );
  return phone
      ? showPiumaSheet<String>(context, label: title, builder: panel)
      : showPiumaDialog<String>(context, label: title, builder: panel);
}

/// The panel of [askFolderName], which keeps its field.
class _FolderName extends StatefulWidget {
  const _FolderName({
    required this.name,
    required this.title,
    required this.phone,
  });

  final String name;
  final String title;
  final bool phone;

  @override
  State<_FolderName> createState() => _FolderNameState();
}

class _FolderNameState extends State<_FolderName> {
  late final _field = TextEditingController(
    text: widget.name,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _done() {
    final text = _field.text.trim();
    Navigator.of(context)
        .pop(text.isEmpty || text == widget.name ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.phone ? 20 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              widget.title,
              style: PiumaType.body.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
          ),
          const SizedBox(height: PiumaSpace.s16),
          PiumaTextField(
            label: l.folderNewName,
            controller: _field,
            autofocus: true,
            onSubmitted: (_) => _done(),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: PiumaSpace.s8,
            runSpacing: PiumaSpace.s8,
            children: [
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.tertiary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              PiumaButton(label: l.folderRename, onPressed: _done),
            ],
          ),
        ],
      ),
    );
  }
}

/// Emails dragged from the list onto a folder of the sidebar.
class MailDrag {
  const MailDrag(this.rows);
  final List<MailRow> rows;

  /// The one account they all belong to; null when they are of several,
  /// which no single folder can take.
  int? get account {
    final ids = {for (final r in rows) r.accountId};
    return ids.length == 1 ? ids.single : null;
  }
}

/// A desktop row that can be dragged onto a folder of the sidebar: a
/// small chip saying how many emails follows the pointer.
class DraggableRows extends StatelessWidget {
  const DraggableRows({super.key, required this.rows, required this.child});

  /// What the drag carries, read when it starts: the picked rows when
  /// the row is one of them.
  final List<MailRow> Function() rows;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Builder(
      builder: (context) {
        final carried = rows();
        return Draggable<MailDrag>(
          data: MailDrag(carried),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            type: MaterialType.transparency,
            child: Container(
              margin: const EdgeInsets.only(left: 14, top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(PiumaRadius.pill),
                border: Border.all(color: c.line),
                boxShadow: [
                  BoxShadow(
                    color: c.shadow.withValues(alpha: 0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PiumaIconView(PiumaIcon.mail, size: 14, color: c.muted),
                  const SizedBox(width: 8),
                  Text(
                    l.draggedEmails(carried.length),
                    style: PiumaType.small.copyWith(color: c.fg),
                  ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.5, child: child),
          child: child,
        );
      },
    );
  }
}

/// A folder of the sidebar that takes emails dragged onto it: [builder]
/// draws it, told whether a drag it would take is over it.
class FolderDropTarget extends StatelessWidget {
  const FolderDropTarget({
    super.key,
    required this.account,
    required this.mailbox,
    required this.onDrop,
    required this.builder,
  });

  final int account;
  final String mailbox;
  final void Function(List<MailRow> rows) onDrop;
  final Widget Function(BuildContext context, bool over) builder;

  @override
  Widget build(BuildContext context) => DragTarget<MailDrag>(
    // Only the account's own emails, and not into where they already are.
    onWillAcceptWithDetails: (d) =>
        d.data.account == account &&
        d.data.rows.any((r) => r.mailbox != mailbox),
    onAcceptWithDetails: (d) => onDrop([
      for (final r in d.data.rows)
        if (r.mailbox != mailbox) r,
    ]),
    builder: (context, candidates, _) =>
        builder(context, candidates.isNotEmpty),
  );
}

/// "Special folders" of one account: Sent, Drafts, Trash, spam and
/// Archive, each with the folder doing it and a menu to pick another
/// (or go back to what the server says).
Future<void> showSpecialFolders(
  BuildContext context, {
  required MailSource source,
  required MailAccount account,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  final title = l.specialFoldersOf(account.name);
  Widget panel(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 0),
    child: SpecialFolders(source: source, account: account),
  );
  return phone
      ? showPiumaSheet<void>(context, label: title, builder: panel)
      : showPiumaDialog<void>(
          context,
          label: title,
          width: 460,
          builder: panel,
        );
}

/// The rows of [showSpecialFolders].
class SpecialFolders extends StatefulWidget {
  const SpecialFolders({
    super.key,
    required this.source,
    required this.account,
  });

  final MailSource source;
  final MailAccount account;

  @override
  State<SpecialFolders> createState() => _SpecialFoldersState();
}

class _SpecialFoldersState extends State<SpecialFolders> {
  late List<SpecialFolder> _roles = widget.source.specialFolders(
    widget.account.id,
  );

  String _roleName(AppLocalizations l, SpecialRole role) => switch (role) {
    SpecialRole.sent => l.folderSent,
    SpecialRole.drafts => l.folderDrafts,
    SpecialRole.trash => l.trashFolder,
    SpecialRole.junk => l.spamFolder,
    SpecialRole.archive => l.folderArchive,
  };

  Future<void> _pick(BuildContext button, SpecialFolder role) async {
    final l = AppLocalizations.of(context);
    final c = PiumaTheme.of(context);
    final box = button.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero) & box.size;
    final folders = widget.source.serverFolders(widget.account.id);
    // Null: back to the server's; a record: that folder.
    final picked = await showPiumaPopover<({String? mailbox})>(
      button,
      label: _roleName(l, role.role),
      anchor: at,
      width: 280,
      builder: (menu) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (mailbox, name) in [
                (null, l.specialAutomatic),
                for (final f in folders) (f.mailbox, f.name),
              ])
                PiumaPressable(
                  onTap: () => Navigator.of(menu).pop((mailbox: mailbox)),
                  semanticLabel: name,
                  child: ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: PiumaType.body.copyWith(
                                fontSize: 14,
                                color: mailbox == null ? c.muted : c.fg,
                              ),
                            ),
                          ),
                          if ((mailbox == null && !role.chosen) ||
                              (mailbox != null &&
                                  role.chosen &&
                                  mailbox == role.mailbox))
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
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await widget.source.setSpecialFolder(
      widget.account.id,
      role.role,
      picked.mailbox,
    );
    if (mounted) {
      setState(() => _roles = widget.source.specialFolders(widget.account.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final names = {
      for (final f in widget.source.serverFolders(widget.account.id))
        f.mailbox: f.name,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.specialFoldersOf(widget.account.name),
            style: PiumaType.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(height: PiumaSpace.s8),
        Text(
          l.specialFoldersNote,
          style: PiumaType.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: PiumaSpace.s16),
        for (final role in _roles)
          Builder(
            builder: (button) {
              final shown = role.mailbox == null
                  ? l.specialNone
                  : names[role.mailbox] ?? role.mailbox!;
              return PiumaPressable(
                onTap: () => _pick(button, role),
                semanticLabel: '${_roleName(l, role.role)}: $shown',
                child: ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _roleName(l, role.role),
                            style: PiumaType.body.copyWith(color: c.fg),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                shown,
                                textAlign: TextAlign.end,
                                style: PiumaType.body.copyWith(
                                  color: role.mailbox == null ? c.muted : c.fg,
                                ),
                              ),
                              if (role.chosen)
                                Text(
                                  l.specialChosen,
                                  style: PiumaType.small.copyWith(
                                    color: c.accentText,
                                  ),
                                ),
                            ],
                          ),
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
              );
            },
          ),
      ],
    );
  }
}

/// A folder's line in the sidebar, with an arrow to open or close its
/// subfolders when it has some.
class FolderChevron extends StatelessWidget {
  const FolderChevron({
    super.key,
    required this.open,
    required this.name,
    required this.onTap,
  });

  final bool open;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: open ? l.folderCollapse(name) : l.folderExpand(name),
      child: SizedBox.square(
        dimension: 24,
        child: Center(
          child: AnimatedRotation(
            turns: open ? 0 : -0.25,
            duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            child: PiumaIconView(
              PiumaIcon.chevronDown,
              size: 13,
              color: c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The folders of [list] the sidebar shows: the subscribed ones, hidden
/// ones only with [hidden] (or holding one that shows, or [keep]), and
/// none under a folder in [closed].
List<AccountFolder> shownFolders(
  List<AccountFolder> list, {
  bool hidden = false,
  Set<String> closed = const {},
  String? keep,
}) {
  final visible = <bool>[
    for (final f in list) hidden || f.subscribed || f.mailbox == keep,
  ];
  // A hidden folder that holds a shown one shows, as its parent.
  for (var i = list.length - 1; i >= 0; i--) {
    if (!visible[i]) continue;
    final depth = list[i].depth;
    for (var j = i - 1; j >= 0 && depth > 0; j--) {
      if (list[j].depth < depth) {
        visible[j] = true;
        break;
      }
    }
  }
  final out = <AccountFolder>[];
  int? under;
  for (final (i, f) in list.indexed) {
    if (under != null && f.depth > under) continue;
    under = null;
    if (!visible[i]) continue;
    out.add(f);
    if (closed.contains(f.mailbox)) under = f.depth;
  }
  return out;
}

/// Whether [list] has folders inside the one at [i].
bool hasSubfolders(List<AccountFolder> list, int i) =>
    i + 1 < list.length && list[i + 1].depth > list[i].depth;
