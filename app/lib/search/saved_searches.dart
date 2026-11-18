import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/text_field.dart';

/// Saves [query] under a name the person picks, or with [saved] renames
/// or deletes that one: the same small panel as a label's.
Future<void> showSavedSearchEditor(
  BuildContext context, {
  required MailSource source,
  String query = '',
  SavedSearch? saved,
}) {
  final l = AppLocalizations.of(context);
  return showPiumaDialog<void>(
    context,
    label: saved == null ? l.saveSearch : l.savedSearchEdit,
    width: 380,
    // The name field needs a Material above it.
    builder: (_) => Material(
      type: MaterialType.transparency,
      child: SavedSearchEditor(source: source, query: query, saved: saved),
    ),
  );
}

class SavedSearchEditor extends StatefulWidget {
  const SavedSearchEditor({
    super.key,
    required this.source,
    this.query = '',
    this.saved,
  });
  final MailSource source;
  final String query;
  final SavedSearch? saved;

  @override
  State<SavedSearchEditor> createState() => _SavedSearchEditorState();
}

class _SavedSearchEditorState extends State<SavedSearchEditor> {
  late final _name = TextEditingController(
    text: widget.saved?.name ?? widget.query,
  );
  bool _asking = false, _taken = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final saved = widget.saved;
    if (saved == null) {
      await widget.source.saveSearch(name, widget.query);
    } else if (!await widget.source.renameSavedSearch(saved.id, name)) {
      if (mounted) setState(() => _taken = true);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await widget.source.deleteSavedSearch(widget.saved!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final editing = widget.saved != null;
    final title = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: c.fg,
    );
    if (_asking) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.savedSearchDelete, style: title),
          const SizedBox(height: 8),
          Text(
            l.savedSearchDeleteNote,
            style: PiumaType.body.copyWith(color: c.muted),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.secondary,
                onPressed: () => setState(() => _asking = false),
              ),
              const SizedBox(width: 8),
              PiumaButton(
                label: l.savedSearchDelete,
                kind: PiumaButtonKind.danger,
                onPressed: _delete,
              ),
            ],
          ),
        ],
      );
    }
    final query = widget.saved?.query ?? widget.query;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(editing ? l.savedSearchEdit : l.saveSearch, style: title),
        const SizedBox(height: 6),
        Text(
          query,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: PiumaType.mono.copyWith(fontSize: 13, color: c.muted),
        ),
        const SizedBox(height: 16),
        PiumaTextField(
          label: l.savedSearchName,
          controller: _name,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        if (_taken) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              l.savedSearchNameTaken,
              style: PiumaType.small.copyWith(color: c.danger),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            if (editing)
              PiumaButton(
                label: l.savedSearchDelete,
                kind: PiumaButtonKind.tertiary,
                onPressed: () => setState(() => _asking = true),
              ),
            const Spacer(),
            PiumaButton(
              label: l.cancel,
              kind: PiumaButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: _name,
              builder: (_, _) => PiumaButton(
                label: l.savedSearchSave,
                onPressed: _name.text.trim().isEmpty ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The sidebar's SAVED SEARCHES, under the labels: each one a row that
/// opens search with its query. Right-click, a long press or F2 renames
/// or deletes it; with the keyboard, Tab reaches each row and Enter
/// opens it.
class SidebarSavedSearches extends StatelessWidget {
  const SidebarSavedSearches({
    super.key,
    required this.searches,
    required this.onOpen,
    required this.onEdit,
  });

  final List<SavedSearch> searches;
  final ValueChanged<SavedSearch> onOpen;
  final ValueChanged<SavedSearch> onEdit;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 4, 6),
          child: Semantics(
            header: true,
            child: Text(
              l.savedSearchesSection,
              style: PiumaType.label.copyWith(
                color: c.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        for (final s in searches)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _SavedRow(
              search: s,
              onOpen: () => onOpen(s),
              onEdit: () => onEdit(s),
            ),
          ),
      ],
    );
  }
}

class _SavedRow extends StatefulWidget {
  const _SavedRow({
    required this.search,
    required this.onOpen,
    required this.onEdit,
  });
  final SavedSearch search;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  State<_SavedRow> createState() => _SavedRowState();
}

class _SavedRowState extends State<_SavedRow> {
  bool _focused = false, _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    final s = widget.search;
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      mouseCursor: SystemMouseCursors.click,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.f2): _EditIntent(),
        SingleActivator(LogicalKeyboardKey.delete): _EditIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onOpen();
            return null;
          },
        ),
        _EditIntent: CallbackAction<_EditIntent>(
          onInvoke: (_) {
            widget.onEdit();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        label: s.name,
        hint: s.query,
        customSemanticsActions: {
          CustomSemanticsAction(label: l.savedSearchEdit): widget.onEdit,
        },
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          onLongPress: widget.onEdit,
          onSecondaryTap: widget.onEdit,
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _focused || _hover ? c.sel : null,
              borderRadius: BorderRadius.circular(9),
              border: _focused ? Border.all(color: c.accent) : null,
            ),
            child: Row(
              children: [
                PiumaIconView(PiumaIcon.search, size: 14, color: c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditIntent extends Intent {
  const _EditIntent();
}
