import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../settings/settings_screen.dart' show PhoneBack;
import '../widgets/button.dart';
import '../widgets/chip.dart';
import '../widgets/dialog.dart';
import '../widgets/route.dart';
import '../widgets/switch.dart';
import 'report_context.dart';

/// Opens the report sheet of `FeedbackToApprove`: a bottom sheet on the
/// phone, a centered sheet on the desktop. The screen under it is captured
/// first, but goes only if the person turns its switch on. Shows "Report
/// queued" once sent. Does nothing while a report sheet is already open
/// (a shake over the sheet, say). [title] starts the title, as when an
/// account can't be added.
Future<void> openReport(
  BuildContext context, {
  required MailSource source,
  ReportKind kind = ReportKind.problem,
  String? title,
}) async {
  if (_ReportSheetState._open > 0) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l = AppLocalizations.of(context);
  final phone = MediaQuery.sizeOf(context).width < 600;
  final device = ReportContext.device(context);
  final screens = ReportContext.screens;
  final screenshot = ReportContext.capture();
  unawaited(source.prepareReport().catchError((_) {}));
  unawaited(ReportContext.addNetwork(device));
  if (!context.mounted) return;
  Widget sheet(BuildContext _) => ReportSheet(
    source: source,
    kind: kind,
    title: title,
    phone: phone,
    screenshot: screenshot,
    device: device,
    screens: screens,
  );
  final sent = phone
      ? await showPiumaSheet<bool>(
          context,
          label: l.reportTitle,
          builder: sheet,
        )
      : await showPiumaDialog<bool>(
          context,
          label: l.reportTitle,
          width: 420,
          builder: sheet,
        );
  if (sent != true) return;
  messenger
    ?..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(l.reportQueued),
        behavior: SnackBarBehavior.floating,
        width: phone ? null : 360,
      ),
    );
}

/// The sheet's content: Problem or Idea, a title, what happened, and the
/// three lines that say what goes with it.
class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.source,
    required this.kind,
    this.title,
    required this.phone,
    this.screenshot,
    this.device = const [],
    this.screens = const [],
  });

  final MailSource source;
  final ReportKind kind;

  /// The title to start from, unless a kept draft comes back.
  final String? title;
  final bool phone;

  /// The screen as it was when the sheet opened, once made into a PNG.
  final Future<Uint8List?>? screenshot;
  final List<(String, String)> device;
  final List<String> screens;

  /// Forgets a draft kept from a sheet closed without Cancel or Send.
  @visibleForTesting
  static void forgetDraft() => _ReportSheetState._kept = null;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  /// Report sheets on screen now.
  static int _open = 0;

  /// What was written in a sheet closed by Esc, back or a tap outside,
  /// for the next one of the same kind to start from. Cancel and Send
  /// forget it.
  static (ReportKind, String, String)? _kept;

  late ReportKind _kind = widget.kind;
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _withScreenshot = false;
  late bool _withLog = widget.kind == ReportKind.problem;

  /// The screenshot with the parts hidden so far.
  Uint8List? _screenshot;

  /// The screenshot as taken, before any part was hidden.
  Uint8List? _original;
  bool _sending = false;

  /// Sent or cancelled: nothing to keep.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _open++;
    if (_kept case (final kind, final title, final description)?
        when kind == widget.kind) {
      _title.text = title;
      _description.text = description;
      _kept = null;
    }
    if (_title.text.isEmpty) _title.text = widget.title ?? '';
    widget.screenshot?.then((png) {
      if (mounted && png != null) {
        setState(() => _screenshot = _original = png);
      }
    });
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _open--;
    if (!_done &&
        (_title.text.trim().isNotEmpty ||
            _description.text.trim().isNotEmpty)) {
      _kept = (_kind, _title.text, _description.text);
    }
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  ReportDraft get _draft => ReportDraft(
    kind: _kind,
    title: _title.text,
    description: _description.text,
    includeScreenshot: _withScreenshot && _screenshot != null,
    includeLog: _withLog,
    device: widget.device,
    screens: widget.screens,
  );

  bool get _ready => _title.text.trim().isNotEmpty && !_sending;

  void _pick(ReportKind kind) => setState(() {
    _kind = kind;
    // An idea rarely needs the log; a problem usually does.
    _withLog = kind == ReportKind.problem;
  });

  void _cancel() {
    _done = true;
    Navigator.of(context).pop(false);
  }

  Future<void> _send() async {
    if (!_ready) return;
    setState(() => _sending = true);
    final draft = _draft;
    try {
      await widget.source.sendReport(
        draft,
        draft.includeScreenshot ? _screenshot : null,
      );
      _done = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).reportNotKept),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _seeSent() => Navigator.of(context).push(
    PiumaRoute.of<void>(
      context,
      (_) => WhatsSentPage(
        source: widget.source,
        draft: _draft,
        screenshot: _withScreenshot ? _screenshot : null,
      ),
    ),
  );

  Future<void> _hideParts() async {
    final original = _original;
    if (original == null) return;
    final hidden = await Navigator.of(context).push<Uint8List>(
      PiumaRoute.of<Uint8List>(
        context,
        (_) => RedactPage(image: _screenshot ?? original),
      ),
    );
    if (hidden != null && mounted) setState(() => _screenshot = hidden);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final phone = widget.phone;
    final shortcut = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘↵'
        : 'Ctrl+↵';
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone) ...[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(PiumaRadius.pill),
              ),
            ),
          ),
          const SizedBox(height: PiumaSpace.s12),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PiumaPressable(
                    onTap: _cancel,
                    semanticLabel: l.cancel,
                    child: Text(
                      l.cancel,
                      style: PiumaType.body.copyWith(color: c.accentText),
                    ),
                  ),
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  l.reportTitle,
                  style: PiumaType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.fg,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _kind == ReportKind.problem
                        ? l.reportProblem
                        : l.suggestIdea,
                    style: PiumaType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                ),
              ),
              PiumaPressable(
                onTap: _cancel,
                semanticLabel: l.cancel,
                child: PiumaIconView(PiumaIcon.close, size: 16, color: c.muted),
              ),
            ],
          ),
        const SizedBox(height: PiumaSpace.s12),
        Row(
          children: [
            PiumaChip(
              label: l.reportKindProblem,
              selected: _kind == ReportKind.problem,
              onChanged: (_) => _pick(ReportKind.problem),
            ),
            const SizedBox(width: PiumaSpace.s8),
            PiumaChip(
              label: l.reportKindIdea,
              selected: _kind == ReportKind.idea,
              onChanged: (_) => _pick(ReportKind.idea),
            ),
          ],
        ),
        const SizedBox(height: PiumaSpace.s12),
        _Field(
          controller: _title,
          label: l.reportTitleField,
          hint: l.reportTitleHint,
          autofocus: !phone,
        ),
        const SizedBox(height: PiumaSpace.s8),
        _Field(
          controller: _description,
          label: _kind == ReportKind.problem
              ? l.reportProblemField
              : l.reportIdeaField,
          hint: l.reportDescriptionHint,
          lines: phone ? 3 : 4,
        ),
        const SizedBox(height: PiumaSpace.s12),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.card),
          ),
          child: Column(
            children: [
              _Line(
                label: phone ? l.reportScreenshot : l.reportScreenshotWindow,
                hint: _withScreenshot
                    ? l.reportScreenshotOn
                    : l.reportScreenshotOff,
                leading: _withScreenshot && _screenshot != null
                    ? PiumaPressable(
                        onTap: _hideParts,
                        semanticLabel: l.reportHideParts,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            PiumaRadius.field,
                          ),
                          child: Image.memory(
                            _screenshot!,
                            width: 30,
                            height: 44,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      )
                    : null,
                trailing: PiumaSwitch(
                  value: _withScreenshot,
                  label: l.reportScreenshot,
                  onChanged: _original == null
                      ? null
                      : (v) => setState(() => _withScreenshot = v),
                ),
              ),
              _Line(
                label: l.reportLog,
                hint: l.reportLogHint,
                top: true,
                trailing: PiumaSwitch(
                  value: _withLog,
                  label: l.reportLog,
                  onChanged: (v) => setState(() => _withLog = v),
                ),
              ),
              _Line(
                label: l.reportDevice,
                hint: l.reportDeviceHint,
                top: true,
                trailing: Text(
                  l.reportAlways,
                  style: PiumaType.small.copyWith(fontSize: 12, color: c.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PiumaSpace.s16),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: PiumaPressable(
                  onTap: _seeSent,
                  semanticLabel: l.reportSeeSent,
                  child: Text(
                    l.reportSeeSent,
                    style: PiumaType.small.copyWith(
                      fontWeight: FontWeight.w500,
                      color: c.accentText,
                    ),
                  ),
                ),
              ),
            ),
            PiumaButton(
              label: l.reportSend,
              shortcut: phone ? null : shortcut,
              size: phone ? PiumaButtonSize.standard : PiumaButtonSize.compact,
              onPressed: _ready ? _send : null,
            ),
          ],
        ),
      ],
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
      },
      // The fields need a Material above them; it draws nothing.
      child: Material(
        type: MaterialType.transparency,
        child: phone
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: PiumaSpace.s16),
                child: SingleChildScrollView(child: body),
              )
            : body,
      ),
    );
  }
}

/// A field of the sheet: no label above it, the label read aloud.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.lines = 1,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int lines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      label: label,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 3,
        textCapitalization: TextCapitalization.sentences,
        style: PiumaType.body.copyWith(color: c.fg),
        cursorColor: c.accent,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.surface,
          hintText: lines == 1 ? hint : '$label · $hint',
          hintStyle: PiumaType.body.copyWith(color: c.muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: PiumaSpace.s12,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PiumaRadius.button),
            borderSide: BorderSide(color: c.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PiumaRadius.button),
            borderSide: BorderSide(color: c.accent),
          ),
        ),
      ),
    );
  }
}

/// A line of the "what goes with it" card.
class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.hint,
    required this.trailing,
    this.leading,
    this.top = false,
  });

  final String label;
  final String hint;
  final Widget trailing;
  final Widget? leading;

  /// A line above it.
  final bool top;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: top ? Border(top: BorderSide(color: c.line)) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: PiumaType.body.copyWith(color: c.fg)),
                Text(
                  hint,
                  style: PiumaType.small.copyWith(fontSize: 12, color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: PiumaSpace.s12),
          trailing,
        ],
      ),
    );
  }
}

/// "What's sent": the report exactly as it will leave, the log already
/// cleaned.
class WhatsSentPage extends StatefulWidget {
  const WhatsSentPage({
    super.key,
    required this.source,
    required this.draft,
    this.screenshot,
  });

  final MailSource source;
  final ReportDraft draft;
  final Uint8List? screenshot;

  @override
  State<WhatsSentPage> createState() => _WhatsSentPageState();
}

class _WhatsSentPageState extends State<WhatsSentPage> {
  late final Future<ReportPreview> _preview = widget.source.previewReport(
    widget.draft,
  );

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget card(String label, Widget child, {Widget? trailing}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: PiumaSpace.s12),
      padding: const EdgeInsets.all(PiumaSpace.s12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: PiumaType.label.copyWith(color: c.muted),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
    final mono = PiumaType.mono.copyWith(
      fontSize: 11.5,
      height: 1.6,
      color: c.muted,
    );
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PhoneBack(
                        label: l.reportTitle,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    Text(
                      l.reportWhatsSent,
                      style: PiumaType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.fg,
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
                Expanded(
                  child: FutureBuilder<ReportPreview>(
                    future: _preview,
                    builder: (context, snap) {
                      final p = snap.data;
                      if (p == null) return const SizedBox.shrink();
                      final parts = p.report.split('\nDevice and app\n');
                      final report = parts.first.trim();
                      final device = parts.length > 1 ? parts[1].trim() : '';
                      final log = p.log;
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          card(
                            l.reportSectionReport,
                            Text(
                              report,
                              style: PiumaType.small.copyWith(
                                color: c.fg,
                                height: 1.5,
                              ),
                            ),
                          ),
                          card(
                            l.reportSectionDevice,
                            Text(device, style: mono),
                          ),
                          if (widget.screenshot case final png?)
                            card(
                              l.reportSectionScreenshot,
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  PiumaRadius.field,
                                ),
                                child: Image.memory(png, height: 220),
                              ),
                            ),
                          if (log != null)
                            card(
                              l.reportSectionLog(
                                '\n'.allMatches(log).length + 1,
                              ),
                              SelectableText(log, style: mono),
                            ),
                        ],
                      );
                    },
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

/// "Hide parts": the screenshot full screen; dragging draws a blurred box,
/// as many as needed. Done returns the picture with the boxes burned in.
class RedactPage extends StatefulWidget {
  const RedactPage({super.key, required this.image});
  final Uint8List image;

  @override
  State<RedactPage> createState() => _RedactPageState();
}

class _RedactPageState extends State<RedactPage> {
  ui.Image? _image;

  /// Boxes in the picture's own pixels.
  final _boxes = <Rect>[];
  Offset? _start;

  @override
  void initState() {
    super.initState();
    ui.decodeImageFromList(widget.image, (image) {
      if (mounted) {
        setState(() => _image = image);
      } else {
        image.dispose();
      }
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final image = _image;
    if (image == null || _boxes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final png = await burnBlur(image, _boxes);
    if (mounted) Navigator.of(context).pop(png);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final image = _image;
    final onDark = PiumaColors.dark.fg;
    return Scaffold(
      backgroundColor: c.darkroom,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: PiumaPressable(
                          onTap: () => Navigator.of(context).pop(),
                          semanticLabel: l.cancel,
                          child: Text(
                            l.cancel,
                            style: PiumaType.body.copyWith(
                              color: onDark.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      l.reportHideParts,
                      style: PiumaType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onDark,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: PiumaPressable(
                          onTap: _done,
                          semanticLabel: l.reportDone,
                          child: Text(
                            l.reportDone,
                            style: PiumaType.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: onDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
                child: image == null
                    ? const SizedBox.shrink()
                    : LayoutBuilder(
                        builder: (context, box) {
                          final scale = [
                            box.maxWidth / image.width,
                            box.maxHeight / image.height,
                          ].reduce((a, b) => a < b ? a : b);
                          final size = Size(
                            image.width * scale,
                            image.height * scale,
                          );
                          Offset toImage(Offset p) => Offset(
                            (p.dx / scale).clamp(0, image.width.toDouble()),
                            (p.dy / scale).clamp(0, image.height.toDouble()),
                          );
                          return Center(
                            child: SizedBox.fromSize(
                              size: size,
                              child: GestureDetector(
                                onPanStart: (d) => setState(() {
                                  _start = toImage(d.localPosition);
                                  _boxes.add(Rect.fromPoints(_start!, _start!));
                                }),
                                onPanUpdate: (d) => setState(() {
                                  _boxes.last = Rect.fromPoints(
                                    _start!,
                                    toImage(d.localPosition),
                                  );
                                }),
                                onPanEnd: (_) => setState(() {
                                  if (_boxes.last.shortestSide < 4) {
                                    _boxes.removeLast();
                                  }
                                }),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    PiumaRadius.card,
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      RawImage(image: image, fit: BoxFit.fill),
                                      for (final b in _boxes)
                                        Positioned.fromRect(
                                          rect: Rect.fromLTRB(
                                            b.left * scale,
                                            b.top * scale,
                                            b.right * scale,
                                            b.bottom * scale,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              PiumaRadius.field,
                                            ),
                                            child: BackdropFilter(
                                              filter: ui.ImageFilter.blur(
                                                sigmaX: 8,
                                                sigmaY: 8,
                                              ),
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: c.muted.withValues(
                                                    alpha: 0.28,
                                                  ),
                                                  border: Border.all(
                                                    color: c.accent,
                                                    width: 1.5,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        PiumaRadius.field,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DarkChip(label: l.reportDragToBlur, strong: true),
                  const SizedBox(width: 10),
                  _DarkChip(
                    label: l.undo,
                    onTap: _boxes.isEmpty
                        ? null
                        : () => setState(_boxes.removeLast),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  const _DarkChip({required this.label, this.onTap, this.strong = false});
  final String label;
  final VoidCallback? onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final onDark = PiumaColors.dark.fg;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onDark.withValues(alpha: strong ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(PiumaRadius.pill),
        ),
        child: Text(
          label,
          style: PiumaType.small.copyWith(
            color: onDark.withValues(alpha: strong ? 1 : 0.7),
          ),
        ),
      ),
    );
  }
}

/// [image] as a PNG with each of [boxes] blurred past reading, then dimmed:
/// what was under them can't be read back.
Future<Uint8List> burnBlur(ui.Image image, List<Rect> boxes) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final whole = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  canvas.drawImage(image, Offset.zero, Paint());
  final sigma = image.width / 30;
  for (final box in boxes) {
    final b = box.intersect(whole);
    if (b.isEmpty) continue;
    canvas.save();
    canvas.clipRect(b);
    // Each pass spreads it further; three leave no letters to read.
    for (var i = 0; i < 3; i++) {
      canvas.drawImage(
        image,
        Offset.zero,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
    }
    canvas.drawRect(
      b,
      Paint()..color = PiumaColors.light.muted.withValues(alpha: 0.35),
    );
    canvas.restore();
  }
  final out = await recorder.endRecording().toImage(image.width, image.height);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  return data!.buffer.asUint8List();
}
