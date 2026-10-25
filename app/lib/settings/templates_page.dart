import 'dart:async';

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/text_field.dart';
import 'settings_screen.dart' show SettingsHeader;

/// Settings › Templates, as on `FeaturesToApprove`: the templates behind
/// compose's "/", each with its subject, New template, and the one picked
/// open under the list, saved as it is typed.
class TemplatesPage extends StatefulWidget {
  const TemplatesPage({
    super.key,
    required this.source,
    this.phone = false,
    this.embedded = false,
  });

  final MailSource source;
  final bool phone;

  /// Under the signatures in Writing on the phone: a small heading
  /// instead of the page's title.
  final bool embedded;

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  List<MailTemplate>? _templates;
  int? _open;
  final _name = TextEditingController();
  final _text = TextEditingController();
  Timer? _saveTimer;

  /// Writing into the fields from code, not from the person.
  bool _filling = false;

  /// The name for a template left nameless; kept for saves on the way out.
  String _untitled = '';

  static const _saveDelay = Duration(milliseconds: 500);

  MailTemplate? get _current =>
      _templates?.where((t) => t.id == _open).firstOrNull;

  @override
  void initState() {
    super.initState();
    _name.addListener(_typed);
    _text.addListener(_typed);
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _flush();
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({int? open}) async {
    List<MailTemplate> templates;
    try {
      templates = await widget.source.templates();
    } catch (_) {
      templates = const [];
    }
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _pick(open ?? _open ?? templates.firstOrNull?.id);
    });
  }

  void _pick(int? id) {
    _flush();
    _open = id;
    final t = _current;
    _filling = true;
    _name.text = t?.name ?? '';
    _text.text = t?.body ?? '';
    _filling = false;
  }

  void _typed() {
    final t = _current;
    if (_filling || t == null) return;
    if (_name.text == t.name && _text.text == t.body) return;
    final edited = t.copyWith(name: _name.text, body: _text.text);
    setState(() {
      _templates = [for (final x in _templates!) x.id == t.id ? edited : x];
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveNow);
  }

  /// Saves the open template now if a save is waiting.
  void _flush() {
    if (!(_saveTimer?.isActive ?? false)) return;
    _saveTimer!.cancel();
    _saveNow();
  }

  void _saveNow() {
    final t = _current;
    if (t == null) return;
    final name = t.name.trim().isEmpty ? _untitled : t.name.trim();
    unawaited(
      widget.source.saveTemplate(t.copyWith(name: name)).catchError((_) => 0),
    );
  }

  Future<void> _new() async {
    final l = AppLocalizations.of(context);
    _flush();
    try {
      final id = await widget.source.saveTemplate(
        MailTemplate(name: l.templateUntitled),
      );
      await _load(open: id);
    } catch (_) {
      // Nothing was added.
    }
  }

  Future<void> _delete(MailTemplate t) async {
    _saveTimer?.cancel();
    try {
      await widget.source.deleteTemplate(t.id);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _open = null);
    await _load(open: _templates?.where((x) => x.id != t.id).firstOrNull?.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    _untitled = l.templateUntitled;
    final templates = _templates;
    final current = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded) ...[
          Semantics(
            header: true,
            child: Text(
              l.templatesTitle,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.muted,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ] else ...[
          SettingsHeader(
            title: l.templatesTitle,
            subtitle: l.templatesSubtitle,
          ),
          const SizedBox(height: 24),
        ],
        if (templates != null) ...[
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in templates)
                  _TemplateRow(
                    template: t,
                    open: t.id == _open,
                    phone: widget.phone,
                    onTap: () => setState(() => _pick(t.id)),
                  ),
                PiumaPressable(
                  onTap: _new,
                  semanticLabel: l.templatesNew,
                  child: Container(
                    height: widget.phone ? 52 : 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    child: ExcludeSemantics(
                      child: Text(
                        l.templatesNew,
                        style: PiumaType.body.copyWith(
                          fontWeight: FontWeight.w500,
                          color: c.accentText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (templates.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l.templatesNone,
              style: PiumaType.small.copyWith(color: c.muted),
            ),
          ],
        ],
        if (current != null) ...[
          const SizedBox(height: 20),
          PiumaTextField(
            key: ValueKey('name-${current.id}'),
            label: l.templateNameLabel,
            controller: _name,
          ),
          const SizedBox(height: 14),
          _TextBox(
            key: ValueKey('text-${current.id}'),
            label: l.templateTextLabel,
            controller: _text,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.templateSavedAsYouType,
                  style: PiumaType.small.copyWith(color: c.muted),
                ),
              ),
              PiumaPressable(
                onTap: () => _delete(current),
                semanticLabel: l.actionDelete,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      l.actionDelete,
                      style: PiumaType.body.copyWith(color: c.danger),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}

/// One template in the list: its name, and its subject under it.
class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.template,
    required this.open,
    required this.phone,
    required this.onTap,
  });

  final MailTemplate template;
  final bool open;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final subject = template.subject.trim();
    final line = subject.isEmpty
        ? l.templateNoSubject
        : l.templateSubjectLine(subject);
    final instant = reduceMotion(context);
    return Semantics(
      selected: open,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: '${template.name}, $line',
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: phone ? 14 : 12,
          ),
          decoration: BoxDecoration(
            color: open ? c.soft : c.soft.withValues(alpha: 0),
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.fg,
                  ),
                ),
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.small.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A labeled box of several lines, bordered like [PiumaTextField].
class _TextBox extends StatefulWidget {
  const _TextBox({super.key, required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  State<_TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<_TextBox> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final focused = _focus.hasFocus;
    final instant = reduceMotion(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.button),
            border: Border.all(color: focused ? c.accent : c.line),
          ),
          child: Semantics(
            label: widget.label,
            textField: true,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              minLines: 3,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              cursorColor: c.accent,
              style: PiumaType.body.copyWith(height: 1.5, color: c.fg),
              decoration: const InputDecoration.collapsed(hintText: null),
            ),
          ),
        ),
      ],
    );
  }
}
