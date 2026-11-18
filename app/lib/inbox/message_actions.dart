import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../compose/reply_builder.dart';
import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/progress.dart';
import '../widgets/segments.dart';
import '../widgets/text_field.dart';

/// Where Save as .eml puts the file on a computer: the system's save
/// window, with [name] suggested; null when the person closed it. Tests
/// replace it.
Future<String?> Function(String name) pickSaveLocation = (name) async {
  final picked = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Email', extensions: ['eml']),
    ],
  );
  return picked?.path;
};

/// Writes a picked file. Tests replace it.
Future<void> Function(String path, Uint8List data) writeSavedFile = (
  path,
  data,
) => File(path).writeAsBytes(data, flush: true);

/// What the reader's More menus do with a message beyond Reply: Forward
/// (inline, with its files fetched in sight), Forward as attachment, Edit
/// as new, Redirect, View source, Save as .eml and Mute conversation. The
/// drafts go to [openCompose]; nothing here sends one.
class MessageActions {
  MessageActions({
    required this.context,
    required this.source,
    required this.openCompose,
    required this.toast,
    this.phone = false,
  });

  final BuildContext context;
  final MailSource source;
  final ValueChanged<Draft> openCompose;
  final void Function(String text, {String? action, VoidCallback? onAction})
  toast;

  /// A sheet from the bottom, not a dialog.
  final bool phone;

  AppLocalizations get _l => AppLocalizations.of(context);

  ReplyBuilder get _builder =>
      ReplyBuilder(_l, Localizations.localeOf(context).toLanguageTag());

  /// Forward, as on `ForwardToApprove` (option A), keeping the message's
  /// formatting: compose opens once its files are here, each fetched in
  /// sight; any that can't be are named, with Try again.
  Future<void> forward(MailRow row) async {
    final (blocks, files, text) = await _content(row);
    final envelope = await source.envelope(row).catchError((Object _) => null);
    if (!context.mounted) return;
    final data = await fetchFiles(row, files);
    if (data == null || !context.mounted) return;
    final mine = source.replyFrom(row);
    openCompose(
      _builder.forward(
        row,
        blocks: blocks,
        text: text,
        envelope: envelope,
        fromEmail: mine,
        toLine: row.to.isNotEmpty ? row.to : (mine ?? _accountEmail(row)),
        files: data,
      ),
    );
  }

  /// Forward as attachment: the whole message, as it came, in an empty
  /// email.
  Future<void> forwardAsAttachment(MailRow row) async {
    final raw = await _raw(row);
    if (raw == null || !context.mounted) return;
    openCompose(
      _builder.forwardAsAttachment(row, raw, fromEmail: source.replyFrom(row)),
    );
  }

  /// Edit as new: a new email with the message's recipients, subject, text
  /// and files.
  Future<void> editAsNew(MailRow row) async {
    final (blocks, files, text) = await _content(row);
    final envelope = await source.envelope(row).catchError((Object _) => null);
    if (!context.mounted) return;
    final data = await fetchFiles(row, files);
    if (data == null || !context.mounted) return;
    openCompose(
      _builder.editAsNew(
        row,
        blocks: blocks,
        text: text,
        envelope: envelope,
        fromEmail: source.replyFrom(row),
        files: data,
      ),
    );
  }

  /// Redirect: asks where to, then sends the message unchanged.
  Future<void> redirect(MailRow row) async {
    final l = _l;
    Widget panel(BuildContext context) => _RedirectPanel(row: row);
    final to = phone
        ? await showPiumaSheet<List<String>>(
            context,
            label: l.redirectTitle,
            builder: panel,
          )
        : await showPiumaDialog<List<String>>(
            context,
            label: l.redirectTitle,
            builder: panel,
          );
    if (to == null || to.isEmpty || !context.mounted) return;
    await _sendRedirect(row, to);
  }

  Future<void> _sendRedirect(MailRow row, List<String> to) async {
    final l = _l;
    try {
      await source.redirect(row, to);
      if (!context.mounted) return;
      toast(l.redirectDone(to.map(bareAddress).join(', ')));
    } catch (_) {
      if (!context.mounted) return;
      toast(
        l.redirectFailed,
        action: l.tryAgain,
        onAction: () => _sendRedirect(row, to),
      );
    }
  }

  /// View source: the headers, one by one, and the raw message.
  Future<void> viewSource(MailRow row) async {
    final raw = await _raw(row);
    if (raw == null || !context.mounted) return;
    final headers = source.headersOf(raw);
    Widget panel(BuildContext context) => _SourcePanel(
      raw: raw,
      headers: headers,
      phone: phone,
      onSave: () => _save(row, raw),
    );
    final l = _l;
    if (phone) {
      await showPiumaSheet<void>(context, label: l.sourceTitle, builder: panel);
    } else {
      await showPiumaDialog<void>(
        context,
        label: l.sourceTitle,
        width: 760,
        builder: panel,
      );
    }
  }

  /// Save as .eml: through the system's save window on a computer, into
  /// Downloads on a phone.
  Future<void> saveEml(MailRow row) async {
    final raw = await _raw(row);
    if (raw == null || !context.mounted) return;
    await _save(row, raw);
  }

  Future<void> _save(MailRow row, Uint8List raw) async {
    final l = _l;
    final name = ReplyBuilder.emlName(row.subject);
    try {
      if (phone || kIsWeb || Platform.isAndroid || Platform.isIOS) {
        await source.saveFile(name, raw);
        if (context.mounted) toast(l.attachmentSaved(name));
        return;
      }
      final path = await pickSaveLocation(name);
      if (path == null) return;
      await writeSavedFile(path, raw);
      if (context.mounted) toast(l.emlSaved(path.split(RegExp(r'[\\/]')).last));
    } catch (_) {
      if (context.mounted) toast(l.emlNotSaved);
    }
  }

  /// Mute conversation, or unmute it, with Undo.
  Future<void> setMuted(MailRow row, bool muted, {VoidCallback? done}) async {
    final l = _l;
    await source.setThreadMuted(row, muted);
    done?.call();
    if (!context.mounted) return;
    toast(
      muted ? l.conversationMuted : l.conversationUnmuted,
      action: l.undo,
      onAction: () async {
        await source.setThreadMuted(row, !muted);
        done?.call();
      },
    );
  }

  /// The message as the reader draws it, its files, and its plain text
  /// for when the blocks can't be had.
  Future<(List<BodyBlock>?, List<MailAttachment>, String)> _content(
    MailRow row,
  ) async {
    List<BodyBlock>? blocks;
    var files = const <MailAttachment>[];
    try {
      final r = await source.readable(row);
      blocks = r.blocks;
      files = r.attachments;
    } catch (_) {
      // Without them it goes as plain text, with no files.
    }
    final text = blocks == null
        ? await source.body(row).catchError((Object _) => '')
        : '';
    return (blocks, files, text);
  }

  /// The raw message, with a word on the screen while it comes; null,
  /// with Try again, when it can't.
  Future<Uint8List?> _raw(MailRow row) async {
    final got = await fetchFiles(row, const [], whole: true);
    return got == null || got.isEmpty ? null : got.first.data;
  }

  /// Fetches [files] of [row] (or, with [whole], the message itself) in a
  /// panel that shows how far it got. Returns them all, or the ones the
  /// person went on with after some failed; null when they cancelled.
  /// Nothing to fetch, nothing shown.
  Future<List<DraftFile>?> fetchFiles(
    MailRow row,
    List<MailAttachment> files, {
    bool whole = false,
  }) async {
    if (files.isEmpty && !whole) return const [];
    final l = _l;
    final items = whole
        ? [
            _Fetch(
              ReplyBuilder.emlName(row.subject),
              () => source.rawMessage(row),
            ),
          ]
        : [
            for (final f in files)
              _Fetch(f.name, () => source.attachmentData(AttachedFile(row, f))),
          ];
    final label = whole ? l.gettingEmail : l.forwardFilesTitle(items.length);
    Widget panel(BuildContext context) =>
        _FetchPanel(items: items, title: label, whole: whole);
    return phone
        ? showPiumaSheet<List<DraftFile>>(context, label: label, builder: panel)
        : showPiumaDialog<List<DraftFile>>(
            context,
            label: label,
            builder: panel,
          );
  }

  String _accountEmail(MailRow row) =>
      source.accounts.where((a) => a.id == row.accountId).firstOrNull?.email ??
      '';
}

/// One file to fetch.
class _Fetch {
  _Fetch(this.name, this.fetch);
  final String name;
  final Future<Uint8List?> Function() fetch;
  Uint8List? data;
  bool failed = false;
}

/// "Getting 3 files": a progress line and each file's state; once they
/// are all here it closes by itself. Files that failed are named, with
/// Try again and Go on without them.
class _FetchPanel extends StatefulWidget {
  const _FetchPanel({
    required this.items,
    required this.title,
    required this.whole,
  });

  final List<_Fetch> items;
  final String title;

  /// The message itself, not its files: failing, there's nothing to go
  /// on without.
  final bool whole;

  @override
  State<_FetchPanel> createState() => _FetchPanelState();
}

class _FetchPanelState extends State<_FetchPanel> {
  bool _running = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Iterable<_Fetch> get _failed => widget.items.where((i) => i.failed);
  int get _done => widget.items.where((i) => i.data != null).length;

  Future<void> _run() async {
    setState(() => _running = true);
    final todo = [
      for (final i in widget.items)
        if (i.data == null) i,
    ];
    for (final i in todo) {
      i.failed = false;
    }
    await Future.wait([
      for (final i in todo)
        i
            .fetch()
            .then((d) {
              if (d == null) {
                i.failed = true;
              } else {
                i.data = d;
              }
            })
            .catchError((Object _) {
              i.failed = true;
            })
            .whenComplete(() {
              if (mounted) setState(() {});
            }),
    ]);
    if (!mounted) return;
    setState(() => _running = false);
    if (_failed.isEmpty) _finish();
  }

  void _finish() => Navigator.of(context).pop([
    for (final i in widget.items)
      if (i.data case final d?) DraftFile(i.name, d),
  ]);

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final total = widget.items.length;
    final failed = _failed.toList();
    final stuck = !_running && failed.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: PiumaType.subtitle.copyWith(color: c.fg)),
        const SizedBox(height: PiumaSpace.s16),
        if (!stuck) ...[
          Semantics(
            label: widget.title,
            value: l.forwardFilesDone(_done, total),
            child: PiumaProgress(
              value: widget.whole ? null : (total == 0 ? null : _done / total),
              track: c.line,
            ),
          ),
          if (!widget.whole) ...[
            const SizedBox(height: PiumaSpace.s8),
            ExcludeSemantics(
              child: Text(
                l.forwardFilesDone(_done, total),
                style: PiumaType.small.copyWith(color: c.muted),
              ),
            ),
          ],
        ] else ...[
          Text(
            widget.whole
                ? l.messageFetchFailed
                : l.forwardFilesFailed(failed.length),
            style: PiumaType.body.copyWith(color: c.fg),
          ),
          if (!widget.whole) ...[
            const SizedBox(height: PiumaSpace.s8),
            for (final f in failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    PiumaIconView(PiumaIcon.warning, size: 16, color: c.warn),
                    const SizedBox(width: PiumaSpace.s8),
                    Expanded(
                      child: Text(
                        f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.body.copyWith(color: c.fg),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
        const SizedBox(height: PiumaSpace.s24),
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
            if (stuck && !widget.whole)
              PiumaButton(
                label: l.forwardWithoutFiles(failed.length),
                kind: PiumaButtonKind.secondary,
                onPressed: _finish,
              ),
            if (stuck) PiumaButton(label: l.tryAgain, onPressed: _run),
          ],
        ),
      ],
    );
  }
}

/// "Redirect this email": where to, and what it means.
class _RedirectPanel extends StatefulWidget {
  const _RedirectPanel({required this.row});
  final MailRow row;

  @override
  State<_RedirectPanel> createState() => _RedirectPanelState();
}

class _RedirectPanelState extends State<_RedirectPanel> {
  final _to = TextEditingController();

  @override
  void initState() {
    super.initState();
    _to.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  List<String> get _addresses => [
    for (final a in _to.text.split(RegExp(r'[,;\n]')))
      if (a.trim().isNotEmpty) a.trim(),
  ];

  void _send() {
    if (_addresses.isEmpty) return;
    Navigator.of(context).pop(_addresses);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    // The field is a material one.
    return Material(type: MaterialType.transparency, child: _panel(c, l));
  }

  Widget _panel(PiumaColors c, AppLocalizations l) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.redirectTitle, style: PiumaType.subtitle.copyWith(color: c.fg)),
        const SizedBox(height: PiumaSpace.s12),
        Text(
          l.redirectBody(widget.row.sender),
          style: PiumaType.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: PiumaSpace.s16),
        PiumaTextField(
          label: l.redirectTo,
          controller: _to,
          hint: l.redirectHint,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: PiumaSpace.s24),
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
            PiumaButton(
              label: l.actionRedirect,
              onPressed: _addresses.isEmpty ? null : _send,
            ),
          ],
        ),
      ],
    );
  }
}

/// View source: the headers as a list, or the raw message, to read,
/// select and copy; Save as .eml beside them.
class _SourcePanel extends StatefulWidget {
  const _SourcePanel({
    required this.raw,
    required this.headers,
    required this.phone,
    required this.onSave,
  });

  final Uint8List raw;
  final List<MailHeader> headers;
  final bool phone;
  final VoidCallback onSave;

  @override
  State<_SourcePanel> createState() => _SourcePanelState();
}

class _SourcePanelState extends State<_SourcePanel> {
  bool _raw = false;
  late final String _text = utf8.decode(widget.raw, allowMalformed: true);

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final mono = PiumaType.mono.copyWith(
      fontSize: 12,
      height: 1.5,
      color: c.fg,
    );
    final height =
        MediaQuery.sizeOf(context).height * (widget.phone ? 0.6 : 0.55);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.sourceTitle, style: PiumaType.subtitle.copyWith(color: c.fg)),
        const SizedBox(height: PiumaSpace.s12),
        Align(
          alignment: Alignment.centerLeft,
          child: PiumaSegments(
            label: l.sourceTitle,
            items: [
              (l.sourceHeaders, !_raw, () => setState(() => _raw = false)),
              (l.sourceRaw, _raw, () => setState(() => _raw = true)),
            ],
          ),
        ),
        const SizedBox(height: PiumaSpace.s12),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: c.bg,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.card),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PiumaSpace.s12),
            child: _raw
                ? SelectableText(_text, style: mono)
                : SelectableText.rich(
                    TextSpan(
                      children: [
                        for (final h in widget.headers) ...[
                          TextSpan(
                            text: '${h.name}: ',
                            style: mono.copyWith(color: c.muted),
                          ),
                          TextSpan(text: '${h.value}\n', style: mono),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: PiumaSpace.s16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: PiumaSpace.s8,
          runSpacing: PiumaSpace.s8,
          children: [
            PiumaButton(
              label: l.sourceCopy,
              kind: PiumaButtonKind.tertiary,
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: _raw
                      ? _text
                      : [
                          for (final h in widget.headers)
                            '${h.name}: ${h.value}',
                        ].join('\n'),
                ),
              ),
            ),
            PiumaButton(
              label: l.actionSaveEml,
              kind: PiumaButtonKind.secondary,
              onPressed: widget.onSave,
            ),
            PiumaButton(
              label: l.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
