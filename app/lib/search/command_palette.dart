import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/message_list.dart' show initials;
import '../inbox/sections.dart' show rowTime;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/message_row.dart';
import 'highlight.dart';

/// Something the palette can do with no one in mind: write, go somewhere.
class PaletteCommand {
  const PaletteCommand(
    this.icon,
    this.label,
    this.run, {
    this.keywords = '',
    this.meta = '',
  });
  final PiumaIcon icon;
  final String label;
  final VoidCallback run;

  /// Other words that find it ("bug" for Report a problem).
  final String keywords;

  /// Shown on the right, as "Help".
  final String meta;
}

/// Whether every word typed starts a word of [label], accents aside.
bool paletteMatches(String label, List<String> words) {
  if (words.isEmpty) return true;
  final parts = fold(label).split(RegExp(r'[^\p{L}\p{N}]+', unicode: true));
  return words.every((w) {
    final f = fold(w);
    return parts.any((p) => p.startsWith(f));
  });
}

/// The ⌘K palette of `FeaturePalette`: one field that runs a command,
/// acts on a person it finds, or opens a message.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.source,
    required this.now,
    required this.commands,
    required this.onWrite,
    required this.onFrom,
    required this.onFilesFrom,
    required this.filesFrom,
    required this.onSearch,
    required this.onOpen,
    required this.onClose,
  });

  final MailSource source;
  final DateTime Function() now;
  final List<PaletteCommand> commands;
  final ValueChanged<Contact> onWrite;
  final ValueChanged<Contact> onFrom;
  final ValueChanged<Contact> onFilesFrom;

  /// How many files this device has from a sender.
  final int Function(Contact person) filesFrom;
  final ValueChanged<String> onSearch;
  final ValueChanged<MailRow> onOpen;
  final VoidCallback onClose;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

/// One line of the palette.
class _Item {
  const _Item(this.icon, this.label, this.run, {this.meta = ''});
  final PiumaIcon icon;
  final String label;
  final VoidCallback run;
  final String meta;
}

class _CommandPaletteState extends State<CommandPalette> {
  final _field = TextEditingController();

  // The field's own node sees the keys first: a text field takes the
  // arrows for its cursor otherwise.
  late final _focus = FocusNode(onKeyEvent: _key);

  /// What Enter runs for each line shown, as last built.
  List<VoidCallback> _runs = const [];

  SearchResults _found = SearchResults.empty;
  int _selected = 0;
  Timer? _debounce;
  int _round = 0;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _field.addListener(_typed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed() {
    if (_field.text == _lastText) return;
    _lastText = _field.text;
    setState(() => _selected = 0);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _run);
  }

  Future<void> _run() async {
    final round = ++_round;
    final query = _field.text.trim();
    final found = query.isEmpty
        ? SearchResults.empty
        : await widget.source.search(query, limit: 4);
    if (!mounted || round != _round) return;
    setState(() => _found = found);
  }

  String _first(Contact p) {
    final name = p.name.trim();
    return name.isEmpty ? p.email : name.split(RegExp(r'\s+')).first;
  }

  List<_Item> _actions(AppLocalizations l, List<String> words) {
    final query = _field.text.trim();
    final person = _found.people.isEmpty ? null : _found.people.first;
    final files = person == null ? 0 : widget.filesFrom(person);
    return [
      if (person != null) ...[
        _Item(
          PiumaIcon.compose,
          l.paletteWriteTo(person.name.isEmpty ? person.email : person.name),
          () => widget.onWrite(person),
        ),
        _Item(
          PiumaIcon.sort,
          l.paletteOnlyFrom(_first(person)),
          () => widget.onFrom(person),
        ),
        if (files > 0)
          _Item(
            PiumaIcon.paperclip,
            l.paletteFilesFrom(_first(person)),
            () => widget.onFilesFrom(person),
            meta: l.paletteFiles(files),
          ),
      ],
      for (final c in widget.commands)
        if (paletteMatches('${c.label} ${c.keywords}', words))
          _Item(c.icon, c.label, c.run, meta: c.meta),
      if (query.isNotEmpty)
        _Item(
          PiumaIcon.search,
          l.paletteSearchAll(query),
          () => widget.onSearch(query),
        ),
    ];
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final n = _runs.length;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown when n > 0:
        setState(() => _selected = (_selected + 1).clamp(0, n - 1));
      case LogicalKeyboardKey.arrowUp when n > 0:
        setState(() => _selected = (_selected - 1).clamp(0, n - 1));
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when event is KeyDownEvent && n > 0:
        _runs[_selected.clamp(0, n - 1)]();
      case LogicalKeyboardKey.escape when event is KeyDownEvent:
        widget.onClose();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final words = searchWords(_field.text);
    final actions = _actions(l, words);
    final hits = _field.text.trim().isEmpty ? const <SearchHit>[] : _found.hits;
    final n = actions.length + hits.length;
    final selected = n == 0 ? -1 : _selected.clamp(0, n - 1);
    _runs = [
      for (final a in actions) a.run,
      for (final h in hits) () => widget.onOpen(h.row),
    ];
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        label: l.paletteLabel,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.panel),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                offset: const Offset(0, 18),
                blurRadius: 50,
                spreadRadius: -24,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    PiumaIconView(PiumaIcon.search, color: c.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _field,
                        focusNode: _focus,
                        autofocus: true,
                        style: PiumaType.body.copyWith(
                          fontSize: 18,
                          color: c.fg,
                        ),
                        cursorColor: c.accent,
                        decoration: InputDecoration.collapsed(
                          hintText: l.paletteHint,
                          hintStyle: PiumaType.body.copyWith(
                            fontSize: 18,
                            color: c.muted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      button: true,
                      label: l.close,
                      child: GestureDetector(
                        onTap: widget.onClose,
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: _Kbd('esc', boxed: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (actions.isNotEmpty) _Heading(l.paletteActions),
                      for (final (i, a) in actions.indexed)
                        _ActionRow(
                          item: a,
                          words: words,
                          selected: i == selected,
                          onHover: () => setState(() => _selected = i),
                        ),
                      if (hits.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _Heading(l.paletteMessages),
                      ],
                      for (final (j, h) in hits.indexed)
                        _HitRow(
                          hit: h,
                          when: rowTime(
                            h.row.receivedAt,
                            widget.now(),
                            Localizations.localeOf(context).toLanguageTag(),
                          ),
                          selected: actions.length + j == selected,
                          onHover: () =>
                              setState(() => _selected = actions.length + j),
                          onTap: () => widget.onOpen(h.row),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: c.bg,
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: DefaultTextStyle.merge(
                  style: PiumaType.label.copyWith(color: c.muted),
                  child: Wrap(
                    spacing: 18,
                    children: [
                      _Hint('↑↓', l.paletteMove),
                      _Hint('↩', l.paletteRun),
                      _Hint(apple ? '⌘K' : 'Ctrl K', l.paletteAnywhere),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: PiumaType.label.copyWith(
            fontSize: 12,
            letterSpacing: 0.5,
            color: c.muted,
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.item,
    required this.words,
    required this.selected,
    required this.onHover,
  });

  final _Item item;
  final List<String> words;
  final bool selected;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Semantics(
        selected: selected,
        child: PiumaPressable(
          onTap: item.run,
          semanticLabel: item.label,
          child: ExcludeSemantics(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? c.soft : null,
                borderRadius: BorderRadius.circular(PiumaRadius.button),
              ),
              child: Row(
                children: [
                  PiumaIconView(
                    item.icon,
                    size: 17,
                    color: selected ? c.accentText : c.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          for (final (text, hit) in highlight(
                            item.label,
                            words,
                          ))
                            TextSpan(
                              text: text,
                              style: hit
                                  ? const TextStyle(fontWeight: FontWeight.w600)
                                  : null,
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.body.copyWith(color: c.fg),
                    ),
                  ),
                  if (item.meta.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(
                      item.meta,
                      style: PiumaType.small.copyWith(color: c.muted),
                    ),
                  ],
                  if (selected) ...[const SizedBox(width: 12), const _Kbd('↩')],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.hit,
    required this.when,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final SearchHit hit;
  final String when;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = hit.row;
    final subject = row.subject.isEmpty ? l.noSubject : row.subject;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Semantics(
        selected: selected,
        child: PiumaPressable(
          onTap: onTap,
          semanticLabel: '${row.sender}, $subject',
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? c.soft : null,
                borderRadius: BorderRadius.circular(PiumaRadius.button),
              ),
              child: Row(
                children: [
                  PiumaAvatar(initials: initials(row.sender), size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PiumaType.body.copyWith(
                            fontWeight: FontWeight.w500,
                            color: c.fg,
                          ),
                        ),
                        Text(
                          row.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PiumaType.small.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(when, style: PiumaType.small.copyWith(color: c.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.keys, this.text);
  final String keys;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [_Kbd(keys), const SizedBox(width: 6), Text(text)],
  );
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.keys, {this.boxed = false});
  final String keys;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final text = Text(
      keys,
      style: PiumaType.mono.copyWith(fontSize: 12, color: c.muted),
    );
    if (!boxed) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: text,
    );
  }
}
