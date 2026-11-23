import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/move_menu.dart' show MoveMenu;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../mail/phone_files.dart';
import '../onboarding/add_account_screen.dart';
import '../widgets/bidi.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/links.dart' show openLocalFile;
import '../widgets/progress.dart';
import '../widgets/segments.dart';
import 'settings_screen.dart' show SettingsHeader;

/// Where an export or the settings file goes on a computer: the system's
/// save window, with [name] suggested; null when closed. Tests replace it.
Future<String?> Function(String name, String label, List<String> extensions)
pickTransferSaveLocation = (name, label, extensions) async {
  final picked = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
  );
  return picked?.path;
};

/// The files to import: `.eml` and `.mbox` (on Android any file, as the
/// system has no type for mbox). Tests replace it.
Future<List<String>> Function(String label) pickMailFiles = (label) async {
  final files = await openFiles(
    acceptedTypeGroups: [
      if (PhoneFiles.android)
        const XTypeGroup()
      else
        XTypeGroup(label: label, extensions: const ['eml', 'mbox', 'mbx']),
    ],
  );
  return [for (final f in files) f.path];
};

/// A settings file to read. Tests replace it.
Future<String?> Function(String label) pickSettingsFile = (label) async {
  final file = await openFile(
    acceptedTypeGroups: [
      if (PhoneFiles.android)
        const XTypeGroup()
      else
        XTypeGroup(label: label, extensions: const ['json']),
    ],
  );
  return file?.path;
};

/// Where a phone writes a file before it moves into Downloads. Tests
/// replace it.
Future<String> Function(String name) phoneStagingPath = (name) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/export');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$name');
  if (await file.exists()) await file.delete();
  return file.path;
};

/// A file name made from what the person calls a folder: letters, digits
/// and a few signs, never a path.
String transferFileName(String name, String extension) {
  final safe = name
      .replaceAll(RegExp(r'[^\p{L}\p{N} _\-()]', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  return '${safe.isEmpty ? 'Mail' : safe}.$extension';
}

/// Where a file chosen to be written ends up: on a computer the save
/// window; on a phone the app's staging, moved to Downloads once written
/// (see [settleSaved]). Null when the person closed the window.
Future<String?> chooseSavePath(
  String name,
  String label,
  List<String> extensions, {
  required bool phone,
}) async {
  if (phone || PhoneFiles.android || PhoneFiles.ios) {
    return phoneStagingPath(name);
  }
  return pickTransferSaveLocation(name, label, extensions);
}

/// A phone's written file goes into Downloads; elsewhere it stays.
Future<String> settleSaved(String path) async =>
    await PhoneFiles.toDownloads(path) ?? path;

/// A running import or export as the page shows it.
class _Job {
  _Job(this.title, this.export);
  final String title;
  final bool export;
  double fraction = 0;
  int messages = 0;
}

/// Runs an import or export: its progress, Cancel, then its summary with
/// what was skipped. One at a time; the page and a folder's "Export
/// folder…" both show it.
class TransferRun extends StatefulWidget {
  const TransferRun({
    super.key,
    required this.source,
    required this.title,
    required this.export,
    required this.updates,
    this.onDone,
    this.onClose,
  });

  final MailSource source;
  final String title;
  final bool export;
  final Stream<TransferUpdate> updates;

  /// Hears the summary once it ends (a phone moves the file first).
  final ValueChanged<TransferResult>? onDone;

  /// Done, after the summary; hidden when null.
  final VoidCallback? onClose;

  @override
  State<TransferRun> createState() => _TransferRunState();
}

class _TransferRunState extends State<TransferRun> {
  late final _job = _Job(widget.title, widget.export);
  StreamSubscription<TransferUpdate>? _sub;
  TransferResult? _result;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.updates.listen((u) async {
      var result = u.result;
      final path = result?.path;
      if (result != null &&
          path != null &&
          !result.cancelled &&
          result.error == null) {
        // A phone's file moves into Downloads once it is complete.
        final moved = await settleSaved(path).catchError((_) => path);
        result = TransferResult(
          export: result.export,
          done: result.done,
          rebuilt: result.rebuilt,
          skipped: result.skipped,
          skippedCount: result.skippedCount,
          offline: result.offline,
          path: moved,
        );
      }
      if (!mounted) return;
      setState(() {
        _job
          ..fraction = u.fraction
          ..messages = u.messages;
        _result = result;
      });
      if (result != null) widget.onDone?.call(result);
    });
  }

  @override
  void dispose() {
    // Leaving the page doesn't stop the job: it finishes on its own.
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AnimatedSwitcher(
      duration: reduceMotion(context) ? Duration.zero : PiumaMotion.move,
      switchInCurve: PiumaMotion.curve,
      switchOutCurve: PiumaMotion.curve,
      child: result == null
          ? _Progress(
              key: const ValueKey('progress'),
              job: _job,
              stopping: _stopping,
              onCancel: () {
                widget.source.cancelTransfer();
                setState(() => _stopping = true);
              },
            )
          : TransferSummary(
              key: const ValueKey('summary'),
              result: result,
              onClose: widget.onClose,
            ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    super.key,
    required this.job,
    required this.stopping,
    required this.onCancel,
  });

  final _Job job;
  final bool stopping;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final percent = NumberFormat.percentPattern(locale).format(job.fraction);
    return Semantics(
      liveRegion: true,
      label: '${job.title}, $percent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            job.title,
            style: PiumaType.body.copyWith(
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: PiumaSpace.s12),
          PiumaProgress(value: job.fraction, track: c.line),
          const SizedBox(height: PiumaSpace.s8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$percent · ${l.transferMessagesSoFar(job.messages)}',
                  style: PiumaType.small.copyWith(color: c.muted),
                ),
              ),
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.secondary,
                size: PiumaButtonSize.compact,
                onPressed: stopping ? null : onCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How an import or export ended: what was done, what was already
/// there, and each message or file left out with why.
class TransferSummary extends StatelessWidget {
  const TransferSummary({super.key, required this.result, this.onClose});

  final TransferResult result;
  final VoidCallback? onClose;

  static String reason(AppLocalizations l, TransferSkipped s) =>
      switch (s.kind) {
        TransferSkip.notMail => l.transferSkipNotMail,
        TransferSkip.tooLarge => l.transferSkipTooLarge,
        TransferSkip.notDownloaded => l.transferSkipNotDownloaded,
        TransferSkip.gone => l.transferSkipGone,
        TransferSkip.notAFile => l.transferSkipNotAFile,
        TransferSkip.unreadable => l.transferSkipUnreadable,
        TransferSkip.refused => l.transferSkipRefused,
      };

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final r = result;
    final hint = PiumaType.small.copyWith(color: c.muted);
    final failed = (r.error != null || r.busy) && r.done == 0 && !r.cancelled;
    final ok = !failed && !r.cancelled;
    final headline = r.cancelled
        ? (r.export ? l.transferExportStopped : l.transferImportStopped)
        : r.busy
        ? l.transferBusy
        : failed
        ? (r.export ? l.transferExportFailed : l.transferImportFailed)
        : r.export
        ? l.transferExported(r.done)
        : l.transferImported(r.done);
    final notes = <String>[
      if (!r.export && r.duplicates > 0) l.transferDuplicates(r.duplicates),
      if (r.offline) l.transferOffline,
      if (r.rebuilt > 0) l.transferRebuilt(r.rebuilt),
      if (!failed && r.error != null && !r.export) l.transferImportFailed,
    ];
    final path = r.path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: PiumaIconView(
                ok ? PiumaIcon.check : PiumaIcon.warning,
                size: 18,
                color: failed ? c.danger : (ok ? c.accent : c.muted),
              ),
            ),
            const SizedBox(width: PiumaSpace.s8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  headline,
                  style: PiumaType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: failed ? c.danger : c.fg,
                  ),
                ),
              ),
            ),
          ],
        ),
        for (final n in notes) ...[
          const SizedBox(height: PiumaSpace.s4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26),
            child: Text(n, style: hint),
          ),
        ],
        if (r.skippedCount > 0) ...[
          const SizedBox(height: PiumaSpace.s12),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26),
            child: Text(
              l.transferSkippedCount(r.skippedCount),
              style: PiumaType.small.copyWith(
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
          ),
          const SizedBox(height: PiumaSpace.s4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Container(
              margin: const EdgeInsetsDirectional.only(start: 26),
              decoration: BoxDecoration(
                color: c.chip,
                borderRadius: BorderRadius.circular(PiumaRadius.field),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: PiumaSpace.s12,
                  vertical: PiumaSpace.s8,
                ),
                children: [
                  for (final s in r.skipped)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: bidiArg(context, s.item),
                              style: PiumaType.small.copyWith(color: c.fg),
                            ),
                            TextSpan(text: ' — ${reason(l, s)}'),
                          ],
                        ),
                        style: hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (r.skippedCount > r.skipped.length)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        l.transferSkippedMore(
                          r.skippedCount - r.skipped.length,
                        ),
                        style: hint,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (onClose != null || (ok && path != null)) ...[
          const SizedBox(height: PiumaSpace.s16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: PiumaSpace.s8,
            runSpacing: PiumaSpace.s8,
            children: [
              if (ok && path != null && r.done > 0)
                PiumaButton(
                  label: l.transferShowFile,
                  kind: PiumaButtonKind.secondary,
                  size: PiumaButtonSize.compact,
                  onPressed: () => openLocalFile(path),
                ),
              if (onClose != null)
                PiumaButton(
                  label: l.transferDone,
                  kind: PiumaButtonKind.primary,
                  size: PiumaButtonSize.compact,
                  onPressed: onClose,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A bordered group of rows with lines between them, as Settings' cards.
class _Box extends StatelessWidget {
  const _Box({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(PiumaSpace.s16),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

/// A section's title and what it does, over its controls.
class _Titled extends StatelessWidget {
  const _Titled({required this.title, required this.hint, this.trailing});
  final String title;
  final String hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: PiumaType.body.copyWith(
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(hint, style: PiumaType.small.copyWith(color: c.muted)),
      ],
    );
    final trailing = this.trailing;
    if (trailing == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: text),
        const SizedBox(width: PiumaSpace.s12),
        trailing,
      ],
    );
  }
}

/// "Work › Archive": the account and folder a job uses; tapping it picks
/// another.
class _FolderChoice extends StatelessWidget {
  const _FolderChoice({
    required this.label,
    required this.account,
    required this.folder,
    required this.onTap,
  });

  final String label;
  final MailAccount? account;
  final AccountFolder? folder;
  final ValueChanged<Rect> onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final account = this.account;
    final folder = this.folder;
    final chosen = account != null && folder != null;
    final text = chosen
        ? '${bidiArg(context, account.name)} › ${bidiArg(context, folder.name)}'
        : l.transferChooseFolder;
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: PiumaType.small.copyWith(color: c.muted)),
        ),
        Flexible(
          child: Builder(
            builder: (button) => PiumaPressable(
              semanticLabel: '$label: $text',
              onTap: () {
                final box = button.findRenderObject()! as RenderBox;
                onTap(box.localToGlobal(Offset.zero) & box.size);
              },
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: PiumaSpace.s12,
                  ),
                  decoration: BoxDecoration(
                    color: c.chip,
                    borderRadius: BorderRadius.circular(PiumaRadius.field),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (account != null) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: account.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: PiumaSpace.s8),
                      ],
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PiumaType.small.copyWith(
                            color: chosen ? c.fg : c.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: PiumaSpace.s4),
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
        ),
      ],
    );
  }
}

/// Picks an account (when there is more than one), then one of its
/// folders. Null when closed.
Future<(MailAccount, AccountFolder)?> pickTransferFolder(
  BuildContext context, {
  required MailSource source,
  required Rect anchor,
  required String hint,
  bool phone = false,
}) async {
  final l = AppLocalizations.of(context);
  final c = PiumaTheme.of(context);
  final accounts = source.accounts;
  if (accounts.isEmpty) return null;
  MailAccount? account = accounts.length == 1 ? accounts.single : null;
  if (account == null) {
    Widget list(BuildContext menu) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in accounts)
          PiumaPressable(
            onTap: () => Navigator.of(menu).pop(a),
            semanticLabel: a.name,
            child: ExcludeSemantics(
              child: Container(
                constraints: BoxConstraints(minHeight: phone ? 48 : 36),
                padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: a.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BidiText(
                        a.name,
                        style: PiumaType.body.copyWith(color: c.fg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    account = phone
        ? await showPiumaSheet<MailAccount>(
            context,
            label: l.transferChooseAccount,
            builder: list,
          )
        : await showPiumaPopover<MailAccount>(
            context,
            label: l.transferChooseAccount,
            anchor: anchor,
            width: 260,
            builder: list,
          );
    if (account == null || !context.mounted) return null;
  }
  final chosen = account;
  final own = await source.folders(chosen.id);
  if (!context.mounted) return null;
  final targets = [
    AccountFolder(mailbox: 'INBOX', name: l.inbox),
    for (final f in own)
      if (f.mailbox != 'INBOX' && f.selectable) f,
  ];
  final menu = MoveMenu(
    account: chosen,
    targets: targets,
    hint: hint,
    phone: phone,
  );
  final folder = phone
      ? await showPiumaSheet<AccountFolder>(
          context,
          label: l.transferChooseFolder,
          builder: (_) => menu,
        )
      : await showPiumaPopover<AccountFolder>(
          context,
          label: l.transferChooseFolder,
          anchor: anchor,
          width: 300,
          builder: (_) => menu,
        );
  return folder == null ? null : (chosen, folder);
}

/// Settings › Import and export (`SettingsTransferToApprove`): export a
/// folder as `.mbox` or a ZIP of `.eml`, import `.eml` and `.mbox` files
/// into a folder, and the settings file.
class TransferPage extends StatefulWidget {
  const TransferPage({super.key, required this.source, this.phone = false});

  final MailSource source;
  final bool phone;

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  MailAccount? _exportAccount;
  AccountFolder? _exportFolder;
  MailFileFormat _format = MailFileFormat.mbox;
  MailAccount? _importAccount;
  AccountFolder? _importFolder;

  /// The job under way or just ended, with its key so a new one starts
  /// fresh.
  ({Key key, String title, bool export, Stream<TransferUpdate> updates})? _run;
  late bool _running = widget.source.transferRunning;

  String? _settingsPath;
  SettingsFileSummary? _settings;
  SettingsApplied? _applied;
  String? _settingsNote;

  @override
  void initState() {
    super.initState();
    final first = widget.source.accounts.firstOrNull;
    final inbox = first == null
        ? null
        : const AccountFolder(mailbox: 'INBOX', name: '');
    _exportAccount = first;
    _importAccount = first;
    _exportFolder = inbox;
    _importFolder = inbox;
  }

  AccountFolder? _named(AccountFolder? f, AppLocalizations l) =>
      f != null && f.mailbox == 'INBOX'
      ? AccountFolder(mailbox: 'INBOX', name: l.inbox)
      : f;

  void _start(String title, bool export, Stream<TransferUpdate> updates) {
    setState(() {
      _running = true;
      _run = (key: UniqueKey(), title: title, export: export, updates: updates);
    });
  }

  Future<void> _export() async {
    final l = AppLocalizations.of(context);
    final account = _exportAccount;
    final folder = _named(_exportFolder, l);
    if (account == null || folder == null || _running) return;
    final mbox = _format == MailFileFormat.mbox;
    final name = transferFileName(
      '${account.name} ${folder.name}',
      mbox ? 'mbox' : 'zip',
    );
    final path = await chooseSavePath(
      name,
      mbox ? l.fileTypeMbox : l.fileTypeZip,
      [mbox ? 'mbox' : 'zip'],
      phone: widget.phone,
    );
    if (path == null || !mounted) return;
    _start(
      l.transferExporting(
        '${bidiArg(context, account.name)} › ${bidiArg(context, folder.name)}',
      ),
      true,
      widget.source.exportFolder(account.id, folder.mailbox, _format, path),
    );
  }

  Future<void> _import() async {
    final l = AppLocalizations.of(context);
    final account = _importAccount;
    final folder = _named(_importFolder, l);
    if (account == null || folder == null || _running) return;
    final paths = await pickMailFiles(l.fileTypeMailFiles);
    if (paths.isEmpty || !mounted) return;
    _start(
      l.transferImporting(
        '${bidiArg(context, account.name)} › ${bidiArg(context, folder.name)}',
      ),
      false,
      widget.source.importMail(account.id, folder.mailbox, paths),
    );
  }

  Future<void> _choose(bool export, Rect at) async {
    final l = AppLocalizations.of(context);
    final picked = await pickTransferFolder(
      context,
      source: widget.source,
      anchor: at,
      hint: l.transferChooseFolder,
      phone: widget.phone,
    );
    if (picked == null || !mounted) return;
    final (account, folder) = picked;
    setState(() {
      if (export) {
        _exportAccount = account;
        _exportFolder = folder;
      } else {
        _importAccount = account;
        _importFolder = folder;
      }
    });
  }

  Future<void> _exportSettings() async {
    final l = AppLocalizations.of(context);
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final path = await chooseSavePath(
      'Piuma settings $stamp.json',
      l.fileTypeSettings,
      const ['json'],
      phone: widget.phone,
    );
    if (path == null || !mounted) return;
    String note;
    try {
      await widget.source.exportSettings(path);
      final saved = await settleSaved(path);
      note = l.transferSettingsSaved(saved.split(RegExp(r'[\\/]')).last);
    } catch (_) {
      note = l.transferSettingsNotSaved;
    }
    if (mounted) setState(() => _settingsNote = note);
  }

  Future<void> _importSettings() async {
    final l = AppLocalizations.of(context);
    final path = await pickSettingsFile(l.fileTypeSettings);
    if (path == null || !mounted) return;
    try {
      final file = await widget.source.readSettingsFile(path);
      if (!mounted) return;
      setState(() {
        _settingsPath = path;
        _settings = file;
        _applied = null;
        _settingsNote = null;
      });
    } on SettingsFileException catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = null;
        _settingsNote = e.problem == SettingsFileProblem.newer
            ? l.transferSettingsNewer
            : l.transferSettingsNotFile;
      });
    } catch (_) {
      if (mounted) setState(() => _settingsNote = l.transferSettingsNotFile);
    }
  }

  Future<void> _apply() async {
    final path = _settingsPath;
    if (path == null) return;
    final applied = await widget.source.applySettingsFile(
      path,
      appearance: true,
    );
    if (mounted) setState(() => _applied = applied);
  }

  /// The add-account form, filled in from the file.
  Future<void> _add(AccountPreset preset) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => AddAccountScreen(
          source: widget.source,
          preset: preset,
          onCancel: () => Navigator.of(route).pop(),
          onDone: (_) => Navigator.of(route).pop(),
        ),
      ),
    );
    final path = _settingsPath;
    if (path == null || !mounted) return;
    // The list says which are added now.
    try {
      final file = await widget.source.readSettingsFile(path);
      if (mounted) setState(() => _settings = file);
    } catch (_) {}
  }

  Widget _heading(String text) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: PiumaSpace.s24,
        bottom: PiumaSpace.s8,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: PiumaType.small.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: c.muted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final hint = PiumaType.small.copyWith(color: c.muted);
    final run = _run;
    final noAccounts = widget.source.accounts.isEmpty;
    final settings = _settings;
    final applied = _applied;
    final note = _settingsNote;
    final buttonSize = widget.phone
        ? PiumaButtonSize.standard
        : PiumaButtonSize.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHeader(title: l.transferTitle, subtitle: l.transferSubtitle),
        _heading(l.transferMail),
        _Box(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Titled(
                  title: l.transferExportTitle,
                  hint: l.transferExportHint,
                ),
                const SizedBox(height: PiumaSpace.s12),
                _FolderChoice(
                  label: l.transferFrom,
                  account: _exportAccount,
                  folder: _named(_exportFolder, l),
                  onTap: (at) => _choose(true, at),
                ),
                const SizedBox(height: PiumaSpace.s12),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  spacing: PiumaSpace.s12,
                  runSpacing: PiumaSpace.s12,
                  children: [
                    PiumaSegments(
                      label: l.transferFormat,
                      items: [
                        for (final (f, text) in [
                          (MailFileFormat.mbox, l.transferFormatMbox),
                          (MailFileFormat.emlZip, l.transferFormatZip),
                        ])
                          (
                            text,
                            _format == f,
                            () => setState(() => _format = f),
                          ),
                      ],
                    ),
                    PiumaButton(
                      label: l.transferExportButton,
                      kind: PiumaButtonKind.secondary,
                      size: buttonSize,
                      onPressed: _running || noAccounts ? null : _export,
                    ),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Titled(
                  title: l.transferImportTitle,
                  hint: l.transferImportHint,
                ),
                const SizedBox(height: PiumaSpace.s12),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  spacing: PiumaSpace.s12,
                  runSpacing: PiumaSpace.s12,
                  children: [
                    _FolderChoice(
                      label: l.transferInto,
                      account: _importAccount,
                      folder: _named(_importFolder, l),
                      onTap: (at) => _choose(false, at),
                    ),
                    PiumaButton(
                      label: l.transferImportButton,
                      kind: PiumaButtonKind.secondary,
                      size: buttonSize,
                      onPressed: _running || noAccounts ? null : _import,
                    ),
                  ],
                ),
              ],
            ),
            if (run != null)
              TransferRun(
                key: run.key,
                source: widget.source,
                title: run.title,
                export: run.export,
                updates: run.updates,
                onDone: (_) => setState(() => _running = false),
                onClose: () => setState(() => _run = null),
              ),
          ],
        ),
        _heading(l.transferSettings),
        _Box(
          children: [
            _Titled(
              title: l.transferSettingsExport,
              hint: l.transferSettingsExportHint,
              trailing: PiumaButton(
                label: l.transferExportButton,
                kind: PiumaButtonKind.secondary,
                size: buttonSize,
                onPressed: noAccounts ? null : _exportSettings,
              ),
            ),
            _Titled(
              title: l.transferSettingsImport,
              hint: l.transferSettingsImportHint,
              trailing: PiumaButton(
                label: l.transferSettingsImportButton,
                kind: PiumaButtonKind.secondary,
                size: buttonSize,
                onPressed: _importSettings,
              ),
            ),
            if (settings != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.transferInFile,
                    style: PiumaType.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                  for (final a in settings.accounts)
                    Padding(
                      padding: const EdgeInsets.only(top: PiumaSpace.s8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BidiText(
                                  a.name.isEmpty ? a.email : a.name,
                                  style: PiumaType.body.copyWith(color: c.fg),
                                ),
                                Text(
                                  a.jmap
                                      ? '${a.email} · JMAP'
                                      : '${a.email} · ${a.imapHost}',
                                  style: hint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: PiumaSpace.s12),
                          if (a.added)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PiumaIconView(
                                  PiumaIcon.check,
                                  size: 14,
                                  color: c.muted,
                                ),
                                const SizedBox(width: PiumaSpace.s4),
                                Text(l.transferAdded, style: hint),
                              ],
                            )
                          else
                            PiumaButton(
                              label: l.transferAdd,
                              kind: PiumaButtonKind.secondary,
                              size: PiumaButtonSize.compact,
                              onPressed: () => _add(a),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: PiumaSpace.s12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: PiumaSpace.s12,
                    runSpacing: PiumaSpace.s8,
                    children: [
                      Text(
                        l.transferSettingsSignatures(settings.signatures),
                        style: hint,
                      ),
                      PiumaButton(
                        label: l.transferSettingsApply,
                        kind: PiumaButtonKind.secondary,
                        size: PiumaButtonSize.compact,
                        onPressed: _apply,
                      ),
                    ],
                  ),
                  if (applied != null) ...[
                    const SizedBox(height: PiumaSpace.s8),
                    Text(
                      l.transferSettingsApplied(applied.signaturesAdded),
                      style: hint,
                    ),
                    if (applied.signaturesWaiting > 0)
                      Text(
                        l.transferSignaturesWaiting(applied.signaturesWaiting),
                        style: hint,
                      ),
                  ],
                ],
              ),
            if (note != null) Text(note, style: hint),
          ],
        ),
      ],
    );
  }
}

/// A folder's "Export folder…": the format, then where, then its
/// progress and summary, in a sheet on the phone and a dialog elsewhere.
Future<void> showExportFolder(
  BuildContext context, {
  required MailSource source,
  required MailAccount account,
  required AccountFolder folder,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  final title = l.transferExportFolderTitle(bidiArg(context, folder.name));
  Widget panel(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: phone ? PiumaSpace.s20 : 0),
    child: _ExportFolderPanel(
      source: source,
      account: account,
      folder: folder,
      phone: phone,
      title: title,
    ),
  );
  return phone
      ? showPiumaSheet<void>(context, label: title, builder: panel)
      : showPiumaDialog<void>(context, label: title, builder: panel);
}

class _ExportFolderPanel extends StatefulWidget {
  const _ExportFolderPanel({
    required this.source,
    required this.account,
    required this.folder,
    required this.phone,
    required this.title,
  });

  final MailSource source;
  final MailAccount account;
  final AccountFolder folder;
  final bool phone;
  final String title;

  @override
  State<_ExportFolderPanel> createState() => _ExportFolderPanelState();
}

class _ExportFolderPanelState extends State<_ExportFolderPanel> {
  MailFileFormat _format = MailFileFormat.mbox;
  Stream<TransferUpdate>? _updates;
  late final int _count = widget.source.exportFolderSize(
    widget.account.id,
    widget.folder.mailbox,
  );

  Future<void> _go() async {
    final l = AppLocalizations.of(context);
    final mbox = _format == MailFileFormat.mbox;
    final path = await chooseSavePath(
      transferFileName(
        '${widget.account.name} ${widget.folder.name}',
        mbox ? 'mbox' : 'zip',
      ),
      mbox ? l.fileTypeMbox : l.fileTypeZip,
      [mbox ? 'mbox' : 'zip'],
      phone: widget.phone,
    );
    if (path == null || !mounted) return;
    setState(
      () => _updates = widget.source.exportFolder(
        widget.account.id,
        widget.folder.mailbox,
        _format,
        path,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final updates = _updates;
    if (updates != null) {
      return TransferRun(
        source: widget.source,
        title: l.transferExporting(bidiArg(context, widget.folder.name)),
        export: true,
        updates: updates,
        onClose: () => Navigator.of(context).pop(),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: PiumaSpace.s8),
        Text(
          l.transferExportFolderNote(_count),
          style: PiumaType.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: PiumaSpace.s16),
        PiumaSegments(
          label: l.transferFormat,
          items: [
            for (final (f, text) in [
              (MailFileFormat.mbox, l.transferFormatMbox),
              (MailFileFormat.emlZip, l.transferFormatZip),
            ])
              (text, _format == f, () => setState(() => _format = f)),
          ],
        ),
        const SizedBox(height: PiumaSpace.s20),
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: PiumaSpace.s8,
            children: [
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.tertiary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              PiumaButton(
                label: l.transferExportButton,
                onPressed: _count == 0 ? null : _go,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
