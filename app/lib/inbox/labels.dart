import 'package:flutter/foundation.dart';
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

/// The tint and the ink of one label color, for the theme in use.
(Color, Color) labelTint(BuildContext context, String color) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final pairs = dark ? PiumaLabelColors.dark : PiumaLabelColors.light;
  return pairs[color] ?? pairs[labelColors.first]!;
}

/// The labels known to the screen below, so rows and the reader can
/// draw a keyword as its pill.
class LabelScope extends InheritedWidget {
  const LabelScope({super.key, required this.labels, required super.child});

  final List<MailLabel> labels;

  /// The labels, in their order; empty above any [LabelScope].
  static List<MailLabel> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LabelScope>()?.labels ??
      const [];

  /// The labels a row carries that are still in the list, in its order.
  static List<MailLabel> on(BuildContext context, List<String> keywords) {
    if (keywords.isEmpty) return const [];
    final all = of(context);
    return [
      for (final k in keywords) ?all.where((l) => l.keyword == k).firstOrNull,
    ];
  }

  @override
  // The inbox reads the labels again on every change: only a different
  // list wakes what depends on it, so the message list isn't read again.
  bool updateShouldNotify(LabelScope oldWidget) =>
      !listEquals(labels, oldWidget.labels);
}

/// One label as a colored pill: small under a row's preview, larger
/// with a × under the reader's subject (`LabelsToApprove`).
class LabelPill extends StatelessWidget {
  const LabelPill({
    super.key,
    required this.label,
    this.large = false,
    this.phone = false,
    this.onRemove,
  });

  final MailLabel label;

  /// The reader's pill.
  final bool large;

  /// The smaller pill of a phone row.
  final bool phone;

  /// A click on the pill takes the label off.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final (tint, ink) = labelTint(context, label.color);
    final l = AppLocalizations.of(context);
    final height = large ? 26.0 : (phone ? 20.0 : 22.0);
    final dot = large ? 7.0 : (phone ? 5.0 : 6.0);
    final size = large ? 13.0 : (phone ? 11.0 : 12.0);
    final pill = Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: large ? 10 : (phone ? 7 : 8)),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(PiumaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
          ),
          SizedBox(width: phone ? 4 : 5),
          Flexible(
            child: Text(
              label.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: size,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            Opacity(
              opacity: 0.7,
              child: PiumaIconView(PiumaIcon.close, size: 12, color: ink),
            ),
          ],
        ],
      ),
    );
    if (onRemove == null) return pill;
    return PiumaPressable(
      onTap: onRemove,
      semanticLabel: l.labelRemove(label.name),
      child: pill,
    );
  }
}

/// The pills of a row: two at most, then "+1".
class RowLabels extends StatelessWidget {
  const RowLabels({super.key, required this.labels, this.phone = false});

  final List<MailLabel> labels;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final more = labels.length - 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, label) in labels.take(2).indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Flexible(
            child: LabelPill(label: label, phone: phone),
          ),
        ],
        if (more > 0) ...[
          const SizedBox(width: 6),
          Text(
            '+$more',
            style: TextStyle(
              fontSize: phone ? 11 : 12,
              fontWeight: FontWeight.w500,
              color: c.muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// The labels under the reader's subject, each with its ×, and
/// "+ Label", which opens the picker.
class ReaderLabels extends StatefulWidget {
  const ReaderLabels({super.key, required this.source, required this.row});

  final MailSource source;
  final MailRow row;

  @override
  State<ReaderLabels> createState() => _ReaderLabelsState();
}

class _ReaderLabelsState extends State<ReaderLabels> {
  /// What the email carries, changed here at once.
  late List<String> _keywords = widget.row.labels;

  /// The labels, read here when no [LabelScope] is above (a reader in a
  /// window of its own).
  List<MailLabel>? _own;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.dependOnInheritedWidgetOfExactType<LabelScope>() == null &&
        _own == null) {
      _loadOwn();
    }
  }

  Future<void> _loadOwn() async {
    final labels = await widget.source.labels();
    if (mounted) setState(() => _own = labels);
  }

  List<MailLabel> _shown(BuildContext context) {
    final own = _own;
    if (own == null) return LabelScope.on(context, _keywords);
    return [
      for (final k in _keywords) ?own.where((l) => l.keyword == k).firstOrNull,
    ];
  }

  @override
  void didUpdateWidget(ReaderLabels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.key != widget.row.key ||
        oldWidget.row.labels != widget.row.labels) {
      _keywords = widget.row.labels;
    }
  }

  void _set(String keyword, bool add) {
    if (!mounted) return;
    setState(
      () => _keywords = [
        for (final k in _keywords)
          if (k != keyword) k,
        if (add) keyword,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = widget.row.copyWith(labels: _keywords);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final label in _shown(context))
          LabelPill(
            label: label,
            large: true,
            onRemove: () {
              _set(label.keyword, false);
              widget.source.setLabel([row], label.keyword, false);
            },
          ),
        Builder(
          builder: (context) => PiumaPressable(
            onTap: () async {
              await showLabelPicker(
                context,
                source: widget.source,
                rows: [row],
                anchor: _rectOf(context),
                onToggle: _set,
              );
              // A label made in the picker.
              if (_own != null) _loadOwn();
            },
            semanticLabel: l.labelAction,
            child: CustomPaint(
              painter: _DashedPill(c.line),
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    l.labelAdd,
                    style: TextStyle(fontSize: 13, height: 1.2, color: c.muted),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Rect? _rectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The dashed outline of "+ Label".
class _DashedPill extends CustomPainter {
  _DashedPill(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      Radius.circular(size.height / 2),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPill oldDelegate) => oldDelegate.color != color;
}

/// "Find or create a label" (`LabelsToApprove`): every label with a
/// check on those all [rows] carry; a click puts it on or takes it off,
/// and a new name typed and Enter creates it with the next free color.
Future<void> showLabelPicker(
  BuildContext context, {
  required MailSource source,
  required List<MailRow> rows,
  Rect? anchor,
  bool phone = false,
  void Function(String keyword, bool add)? onToggle,
}) async {
  if (rows.isEmpty) return;
  final l = AppLocalizations.of(context);
  final labels = await source.labels();
  if (!context.mounted) return;
  final picker = LabelPicker(
    source: source,
    rows: rows,
    labels: labels,
    phone: phone,
    onToggle: onToggle,
  );
  if (phone) {
    await showPiumaSheet<void>(
      context,
      label: l.labelsHeading,
      builder: (_) => picker,
    );
  } else if (anchor == null) {
    await showPiumaDialog<void>(
      context,
      label: l.labelsHeading,
      width: 300,
      builder: (_) => picker,
    );
  } else {
    await showPiumaPopover<void>(
      context,
      label: l.labelsHeading,
      anchor: anchor,
      width: 280,
      builder: (_) => picker,
    );
  }
}

class LabelPicker extends StatefulWidget {
  const LabelPicker({
    super.key,
    required this.source,
    required this.rows,
    required this.labels,
    this.phone = false,
    this.onToggle,
  });

  /// Told of each label put on or taken off.
  final void Function(String keyword, bool add)? onToggle;

  final MailSource source;
  final List<MailRow> rows;
  final List<MailLabel> labels;
  final bool phone;

  @override
  State<LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<LabelPicker> {
  final _field = TextEditingController();
  late List<MailLabel> _labels = widget.labels;

  /// On the phone, "+ New label" was tapped: a field in its place.
  bool _naming = false;

  /// The keywords every row carries.
  late final Set<String> _on = {
    for (final l in widget.labels)
      if (widget.rows.every((r) => r.labels.contains(l.keyword))) l.keyword,
  };

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  String get _query => _field.text.trim();

  List<MailLabel> get _shown {
    final q = _query.toLowerCase();
    if (q.isEmpty) return _labels;
    return [
      for (final l in _labels)
        if (l.name.toLowerCase().contains(q)) l,
    ];
  }

  /// Typed text that names no label yet.
  bool get _creates =>
      _query.isNotEmpty &&
      !_labels.any((l) => l.name.toLowerCase() == _query.toLowerCase());

  void _toggle(MailLabel label) {
    final add = !_on.contains(label.keyword);
    setState(() => add ? _on.add(label.keyword) : _on.remove(label.keyword));
    widget.source.setLabel(widget.rows, label.keyword, add);
    widget.onToggle?.call(label.keyword, add);
  }

  Future<void> _create() async {
    final label = await widget.source.addLabel(_query);
    if (!mounted) return;
    setState(() {
      if (!_labels.any((l) => l.id == label.id)) {
        _labels = [..._labels, label];
      }
      _field.clear();
      _naming = false;
    });
    if (!_on.contains(label.keyword)) _toggle(label);
  }

  void _submit() {
    if (_creates) {
      _create();
    } else if (_shown.firstOrNull case final first?) {
      _toggle(first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final shown = _shown;
    final phone = widget.phone;
    final pad = phone ? 20.0 : 0.0;
    if (phone) return _sheet(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Container(
              height: phone ? 40 : 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _field,
                autofocus: !phone,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                style: PiumaType.small.copyWith(color: c.fg),
                cursorColor: c.accent,
                decoration: InputDecoration.collapsed(
                  hintText: l.labelFind,
                  hintStyle: PiumaType.small.copyWith(color: c.muted),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.symmetric(horizontal: pad),
              children: [
                for (final label in shown)
                  _Choice(
                    label: label,
                    on: _on.contains(label.keyword),
                    phone: phone,
                    onTap: () => _toggle(label),
                  ),
                if (_creates)
                  _Create(name: _query, phone: phone, onTap: _create),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The phone's sheet (`LabelsToApprove`, section 2): "Labels", each
  /// label with its check, and "+ New label", which becomes a field.
  Widget _sheet(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget line() => Container(height: 1, color: c.line);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(PiumaRadius.pill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Semantics(
              header: true,
              child: Text(
                l.labelsHeading,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final label in _labels) ...[
                  line(),
                  _Choice(
                    label: label,
                    on: _on.contains(label.keyword),
                    phone: true,
                    onTap: () => _toggle(label),
                  ),
                ],
                line(),
                if (_naming)
                  SizedBox(
                    height: 46,
                    child: Row(
                      children: [
                        PiumaIconView(
                          PiumaIcon.plus,
                          size: 16,
                          color: c.accentText,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _field,
                            autofocus: true,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              if (_creates) _create();
                            },
                            style: PiumaType.body.copyWith(
                              fontSize: 16,
                              color: c.fg,
                            ),
                            cursorColor: c.accent,
                            decoration: InputDecoration.collapsed(
                              hintText: l.labelName,
                              hintStyle: PiumaType.body.copyWith(
                                fontSize: 16,
                                color: c.muted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  PiumaPressable(
                    onTap: () => setState(() => _naming = true),
                    semanticLabel: l.labelNew,
                    child: SizedBox(
                      height: 46,
                      child: Row(
                        children: [
                          PiumaIconView(
                            PiumaIcon.plus,
                            size: 16,
                            color: c.accentText,
                          ),
                          const SizedBox(width: 12),
                          ExcludeSemantics(
                            child: Text(
                              l.labelNew,
                              style: PiumaType.body.copyWith(
                                fontSize: 16,
                                color: c.accentText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.on,
    required this.onTap,
    this.phone = false,
  });

  final MailLabel label;
  final bool on;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final (_, ink) = labelTint(context, label.color);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label.name,
      child: Semantics(
        checked: on,
        child: _Hover(
          child: Container(
            height: phone ? 46 : 34,
            padding: EdgeInsets.symmetric(horizontal: phone ? 0 : 10),
            child: Row(
              children: [
                Container(
                  width: phone ? 10 : 9,
                  height: phone ? 10 : 9,
                  decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
                ),
                SizedBox(width: phone ? 12 : 10),
                Expanded(
                  child: Text(
                    label.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PiumaType.body.copyWith(
                      color: c.fg,
                      fontSize: phone ? 16 : null,
                    ),
                  ),
                ),
                if (on)
                  PiumaIconView(PiumaIcon.check, size: 16, color: c.accentText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Create "Site visits"": the typed name, as a new label.
class _Create extends StatelessWidget {
  const _Create({required this.name, required this.onTap, this.phone = false});
  final String name;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: l.labelCreate(name),
      child: _Hover(
        child: Container(
          height: phone ? 46 : 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              PiumaIconView(PiumaIcon.plus, size: 14, color: c.accentText),
              SizedBox(width: phone ? 12 : 10),
              Expanded(
                child: Text(
                  l.labelCreate(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.body.copyWith(color: c.accentText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The soft tint under the pointer.
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
          borderRadius: BorderRadius.circular(8),
        ),
        child: widget.child,
      ),
    );
  }
}

/// What a label color is called, for screen readers.
String labelColorName(AppLocalizations l, String color) => switch (color) {
  'teal' => l.labelColorTeal,
  'coral' => l.labelColorCoral,
  'blue' => l.labelColorBlue,
  'violet' => l.labelColorViolet,
  _ => l.labelColorAmber,
};

/// A new label, or [label] renamed, recolored or deleted: a name and one
/// of the five colors (`LabelsToApprove`, Rules & folders).
Future<void> showLabelEditor(
  BuildContext context, {
  required MailSource source,
  MailLabel? label,
}) async {
  final l = AppLocalizations.of(context);
  final used = label == null
      ? [for (final x in await source.labels()) x.color]
      : const <String>[];
  if (!context.mounted) return;
  // A new label starts on the color fewest labels have.
  final fresh = labelColors.reduce(
    (a, b) =>
        used.where((u) => u == b).length < used.where((u) => u == a).length
        ? b
        : a,
  );
  await showPiumaDialog<void>(
    context,
    label: label == null ? l.labelNew : l.labelEdit,
    width: 360,
    // The name field needs a Material above it.
    builder: (_) => Material(
      type: MaterialType.transparency,
      child: _LabelEditor(
        source: source,
        label: label,
        color: label?.color ?? fresh,
      ),
    ),
  );
}

class _LabelEditor extends StatefulWidget {
  const _LabelEditor({required this.source, required this.color, this.label});
  final MailSource source;
  final MailLabel? label;
  final String color;

  @override
  State<_LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends State<_LabelEditor> {
  late final _name = TextEditingController(text: widget.label?.name ?? '');
  late String _color = widget.color;
  bool _asking = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final label = widget.label;
    if (label == null) {
      await widget.source.addLabel(name, color: _color);
    } else {
      await widget.source.updateLabel(label.id, name, _color);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await widget.source.removeLabel(widget.label!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final editing = widget.label != null;
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
          Text(l.labelDelete, style: title),
          const SizedBox(height: 8),
          Text(
            l.labelDeleteNote,
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
                label: l.labelDelete,
                kind: PiumaButtonKind.danger,
                onPressed: _delete,
              ),
            ],
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(editing ? l.labelEdit : l.labelNew, style: title),
        const SizedBox(height: 16),
        PiumaTextField(
          label: l.labelName,
          controller: _name,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final color in labelColors)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _Swatch(
                  color: color,
                  on: color == _color,
                  onTap: () => setState(() => _color = color),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            if (editing)
              PiumaButton(
                label: l.labelDelete,
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
                label: editing ? l.labelSave : l.labelCreateButton,
                onPressed: _name.text.trim().isEmpty ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One of the five colors, as a round tint with its ink dot; a ring
/// when it is the one picked.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.on, required this.onTap});
  final String color;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final (tint, ink) = labelTint(context, color);
    return Semantics(
      selected: on,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: labelColorName(AppLocalizations.of(context), color),
        child: Container(
          width: 30,
          height: 30,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: on ? c.accent : c.line,
              width: on ? 2 : 1,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sidebar's LABELS, as on `LabelsToApprove`: + makes a new one;
/// each label with its dot and how many emails carry it, a click shows
/// them.
class SidebarLabels extends StatelessWidget {
  const SidebarLabels({
    super.key,
    required this.labels,
    this.current,
    this.onLabel,
    this.onNewLabel,
  });

  final List<MailLabel> labels;

  /// The keyword of the label shown, if one is.
  final String? current;
  final ValueChanged<MailLabel>? onLabel;
  final VoidCallback? onNewLabel;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.labelsSection,
                  style: PiumaType.label.copyWith(
                    color: c.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (onNewLabel case final add?)
                PiumaPressable(
                  onTap: add,
                  semanticLabel: l.labelNew,
                  child: SizedBox.square(
                    dimension: 28,
                    child: Center(
                      child: PiumaIconView(
                        PiumaIcon.plus,
                        size: 15,
                        color: c.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final label in labels)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Semantics(
              selected: label.keyword == current,
              button: true,
              child: PiumaPressable(
                onTap: onLabel == null ? null : () => onLabel!(label),
                semanticLabel: label.name,
                child: AnimatedContainer(
                  duration: instant ? Duration.zero : PiumaMotion.press,
                  curve: PiumaMotion.curve,
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: label.keyword == current ? c.sel : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: labelTint(context, label.color).$2,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: c.fg,
                            fontWeight: label.keyword == current
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (label.count > 0)
                        Text(
                          '${label.count}',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
