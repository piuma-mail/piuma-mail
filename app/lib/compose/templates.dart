import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/dialog.dart';

/// What was chosen in the templates list: one to put in the message,
/// "Save as template", or "Manage".
sealed class TemplateChoice {
  const TemplateChoice();
}

class TemplatePicked extends TemplateChoice {
  const TemplatePicked(this.template);
  final MailTemplate template;
}

class TemplateSave extends TemplateChoice {
  const TemplateSave();
}

class TemplateManage extends TemplateChoice {
  const TemplateManage();
}

/// The templates over the text, as on `FeaturesToApprove`: a popover by
/// [anchor] on the desktop, a sheet from the foot on the phone. Typing
/// narrows the list; Enter takes the one marked. Null when dismissed.
Future<TemplateChoice?> showTemplates(
  BuildContext context, {
  required List<MailTemplate> templates,
  required Rect anchor,
  bool phone = false,
  bool canSave = true,
  ValueChanged<String>? onQuery,
}) {
  final l = AppLocalizations.of(context);
  Widget picker(BuildContext context) => TemplatePicker(
    templates: templates,
    canSave: canSave,
    onQuery: onQuery,
    onChoice: (choice) => Navigator.of(context).pop(choice),
  );
  return phone
      ? showPiumaSheet<TemplateChoice>(
          context,
          label: l.templatesTitle,
          builder: (context) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: PiumaSpace.s8),
            child: picker(context),
          ),
        )
      : showPiumaPopover<TemplateChoice>(
          context,
          label: l.templatesTitle,
          anchor: anchor,
          width: 400,
          builder: picker,
        );
}

/// The list itself: "/" and what is typed, the matching templates with
/// the typed part marked, then "Save as template" and "Manage".
class TemplatePicker extends StatefulWidget {
  const TemplatePicker({
    super.key,
    required this.templates,
    required this.onChoice,
    this.canSave = true,
    this.onQuery,
  });

  final List<MailTemplate> templates;
  final ValueChanged<TemplateChoice> onChoice;

  /// What is typed, as it changes: a "/" typed in the text puts it back
  /// when nothing is picked.
  final ValueChanged<String>? onQuery;

  /// Whether there is something written to keep as a template.
  final bool canSave;

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  final _query = TextEditingController();
  int _marked = 0;

  List<MailTemplate> get _found {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.templates;
    return [
      for (final t in widget.templates)
        if (t.name.toLowerCase().contains(q)) t,
    ];
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() {
      widget.onQuery?.call(_query.text);
      setState(() => _marked = 0);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final found = _found;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && found.isNotEmpty) {
      setState(() => _marked = (_marked + 1) % found.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && found.isNotEmpty) {
      setState(() => _marked = (_marked - 1) % found.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _take() {
    final found = _found;
    if (found.isEmpty) return;
    widget.onChoice(TemplatePicked(found[_marked.clamp(0, found.length - 1)]));
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final found = _found;
    final query = _query.text.trim();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Text(
                    '/',
                    style: PiumaType.mono.copyWith(
                      fontSize: 14,
                      color: c.muted,
                    ),
                  ),
                ),
                const SizedBox(width: PiumaSpace.s8),
                Expanded(
                  child: Focus(
                    onKeyEvent: _key,
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      onSubmitted: (_) => _take(),
                      cursorColor: c.accent,
                      style: PiumaType.body.copyWith(color: c.fg),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: l.templatesSearch,
                        hintStyle: PiumaType.body.copyWith(color: c.muted),
                      ),
                    ),
                  ),
                ),
                if (widget.templates.isNotEmpty)
                  Text(
                    l.templatesFound(found.length, widget.templates.length),
                    style: PiumaType.small.copyWith(
                      fontSize: 12,
                      color: c.muted,
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.line),
          const SizedBox(height: PiumaSpace.s4),
          if (widget.templates.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                l.templatesNone,
                style: PiumaType.small.copyWith(color: c.muted),
              ),
            )
          else if (found.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                l.templatesNoMatch(query),
                style: PiumaType.small.copyWith(color: c.muted),
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final (i, t) in found.indexed)
                      _Option(
                        template: t,
                        query: query,
                        marked: i == _marked,
                        onTap: () => widget.onChoice(TemplatePicked(t)),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: PiumaSpace.s4),
          Divider(height: 1, thickness: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.only(top: PiumaSpace.s4),
            child: Row(
              children: [
                if (widget.canSave)
                  _FootButton(
                    label: l.templateSaveThis,
                    color: c.fg,
                    onTap: () => widget.onChoice(const TemplateSave()),
                  ),
                const Spacer(),
                _FootButton(
                  label: l.templatesManage,
                  color: c.muted,
                  onTap: () => widget.onChoice(const TemplateManage()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One template: its name, the typed part in the accent, and its first
/// words under it.
class _Option extends StatelessWidget {
  const _Option({
    required this.template,
    required this.query,
    required this.marked,
    required this.onTap,
  });

  final MailTemplate template;
  final String query;
  final bool marked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final name = template.name;
    final at = query.isEmpty
        ? -1
        : name.toLowerCase().indexOf(query.toLowerCase());
    final bold = PiumaType.body.copyWith(
      fontWeight: FontWeight.w600,
      color: c.fg,
    );
    final instant = reduceMotion(context);
    return Semantics(
      selected: marked,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: name,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: marked ? c.soft : c.soft.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  at < 0
                      ? TextSpan(text: name)
                      : TextSpan(
                          children: [
                            TextSpan(text: name.substring(0, at)),
                            TextSpan(
                              text: name.substring(at, at + query.length),
                              style: TextStyle(color: c.accentText),
                            ),
                            TextSpan(text: name.substring(at + query.length)),
                          ],
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bold,
                ),
                if (template.body.trim().isNotEmpty)
                  Text(
                    template.body.trim().replaceAll('\n', ' '),
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

class _FootButton extends StatelessWidget {
  const _FootButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PiumaPressable(
    onTap: onTap,
    semanticLabel: label,
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      child: ExcludeSemantics(
        child: Text(label, style: PiumaType.body.copyWith(color: color)),
      ),
    ),
  );
}

/// A name for what is written: its subject, else its first line.
String templateName(String subject, String body, String untitled) {
  final s = subject.trim();
  if (s.isNotEmpty) return s;
  final first = body.trim().split('\n').first.trim();
  if (first.isEmpty) return untitled;
  return first.length <= 40 ? first : '${first.substring(0, 40).trimRight()}…';
}
