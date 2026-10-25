import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/sections.dart' show rowTime;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../settings/settings_screen.dart' show SettingsHeader;
import '../updates/updates.dart';
import '../updates/updates_group.dart';
import '../updates/whats_new.dart';
import '../widgets/dialog.dart';
import '../widgets/switch.dart';
import 'report_sheet.dart';
import 'shake.dart';

/// Settings › Help & feedback (`FeedbackToApprove`): Report a problem,
/// Suggest an idea, Shake to report where the device can tell a shake,
/// and the reports already made with where each stands.
class HelpPage extends StatefulWidget {
  const HelpPage({
    super.key,
    required this.source,
    required this.now,
    this.onWrite,
  });

  final MailSource source;
  final DateTime Function() now;

  /// Opens a draft in compose: Send by email instead.
  final ValueChanged<Draft>? onWrite;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  List<SentReport>? _reports;
  Timer? _watch;

  /// Whether this device can tell a shake: only then is the row shown.
  bool _canShake = false;

  @override
  void initState() {
    super.initState();
    _load();
    Shake.available().then((can) {
      if (mounted && can) setState(() => _canShake = true);
    });
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final reports = await widget.source.reports();
    if (!mounted) return;
    setState(() => _reports = reports);
    // While some are on their way, look again now and then.
    _watch?.cancel();
    final going = reports.any(
      (r) =>
          r.status == ReportStatus.waiting || r.status == ReportStatus.sending,
    );
    if (going) _watch = Timer(const Duration(seconds: 10), _load);
  }

  Future<void> _report(ReportKind kind) async {
    await openReport(context, source: widget.source, kind: kind);
    await _load();
  }

  Future<void> _retry(SentReport r) async {
    await widget.source.retryReport(r.id);
    await _load();
  }

  Future<void> _delete(SentReport r) async {
    await widget.source.deleteReport(r.id);
    await _load();
  }

  Future<void> _email(SentReport r) async {
    final write = widget.onWrite;
    final accounts = widget.source.accounts;
    if (write == null || accounts.isEmpty) return;
    final e = await widget.source.reportEmail(r.id);
    await widget.source.reportEmailed(r.id);
    await _load();
    write(
      Draft(
        accountId: accounts.first.id,
        to: [e.to],
        subject: e.subject,
        body: e.body,
        files: e.files,
      ),
    );
  }

  Future<void> _options(BuildContext row, SentReport r, Offset? at) async {
    final l = AppLocalizations.of(context);
    final box = row.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = at != null
        ? Rect.fromLTWH(at.dx, at.dy, 0, 0)
        : box.localToGlobal(Offset.zero) & box.size;
    final canEmail =
        widget.onWrite != null &&
        widget.source.accounts.isNotEmpty &&
        r.status != ReportStatus.sent;
    final picked = await showPiumaPopover<_Pick>(
      context,
      label: l.reportOptions,
      anchor: anchor,
      width: 260,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.status != ReportStatus.sent && r.status != ReportStatus.emailed)
            _MenuItem(
              icon: PiumaIcon.sync,
              label: l.reportTryAgain,
              onTap: () => Navigator.of(menu).pop(_Pick.retry),
            ),
          if (canEmail)
            _MenuItem(
              icon: PiumaIcon.mail,
              label: l.reportByEmail,
              onTap: () => Navigator.of(menu).pop(_Pick.email),
            ),
          _MenuItem(
            icon: PiumaIcon.trash,
            label: l.reportDelete,
            danger: true,
            onTap: () => Navigator.of(menu).pop(_Pick.delete),
          ),
        ],
      ),
    );
    switch (picked) {
      case _Pick.retry:
        await _retry(r);
      case _Pick.email:
        await _email(r);
      case _Pick.delete:
        await _delete(r);
      case null:
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final reports = _reports;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeader(title: l.helpTitle, subtitle: l.helpSubtitle),
        const SizedBox(height: 28),
        if (Updates.instance.available) ...[
          Text(l.updates, style: PiumaType.subtitle.copyWith(color: c.fg)),
          const SizedBox(height: 12),
          UpdatesGroup(now: widget.now),
          const SizedBox(height: 28),
        ],
        _Box(
          children: [
            _Link(
              icon: PiumaIcon.warning,
              label: l.reportProblem,
              onTap: () => _report(ReportKind.problem),
            ),
            _Link(
              icon: PiumaIcon.spark,
              label: l.suggestIdea,
              onTap: () => _report(ReportKind.idea),
            ),
            Builder(
              builder: (row) => _Link(
                icon: PiumaIcon.newsletter,
                label: l.whatsNew,
                onTap: () {
                  final box = row.findRenderObject() as RenderBox?;
                  final from = box == null
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size;
                  final u = Updates.instance;
                  final release = switch (u.state.value) {
                    UpdateReady(:final release) => release,
                    _ => u.updatedTo ?? bundledRelease(l),
                  };
                  showWhatsNew(context, release: release, from: from);
                },
              ),
            ),
            if (_canShake)
              ValueListenableBuilder<bool>(
                valueListenable: widget.source.shakeToReport,
                builder: (context, on, _) => _ShakeRow(
                  value: on,
                  onChanged: widget.source.setShakeToReport,
                ),
              ),
          ],
        ),
        if (reports != null) ...[
          const SizedBox(height: 28),
          Text(l.yourReports, style: PiumaType.subtitle.copyWith(color: c.fg)),
          const SizedBox(height: 12),
          if (reports.isEmpty)
            Text(
              l.reportNone,
              style: PiumaType.body.copyWith(fontSize: 14, color: c.muted),
            )
          else
            _Box(
              children: [
                for (final r in reports)
                  Builder(
                    builder: (row) => _ReportRow(
                      key: ValueKey(r.id),
                      report: r,
                      now: widget.now(),
                      onTap: r.status == ReportStatus.failed
                          ? () => _retry(r)
                          : null,
                      onOptions: (at) => _options(row, r, at),
                    ),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

enum _Pick { retry, email, delete }

/// A bordered group of rows with lines between them, as Settings has.
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
        children: [
          for (final (i, child) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// "Report a problem ›".
class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.onTap});

  final PiumaIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(PiumaRadius.button),
              ),
              alignment: Alignment.center,
              child: PiumaIconView(icon, size: 17, color: c.muted),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: PiumaType.body.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
            ),
            PiumaIconView(PiumaIcon.chevronRight, size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// "Shake to report", with its line and switch; off at first.
class _ShakeRow extends StatelessWidget {
  const _ShakeRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(PiumaRadius.button),
            ),
            alignment: Alignment.center,
            child: PiumaIconView(PiumaIcon.phone, size: 17, color: c.muted),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.shakeToReport,
                  style: PiumaType.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                Text(
                  l.shakeToReportHint,
                  style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          PiumaSwitch(
            value: value,
            label: l.shakeToReport,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// One report: its title, when, why it waits, and a pill with where it
/// stands. A long press or a right click gives its options.
class _ReportRow extends StatelessWidget {
  const _ReportRow({
    super.key,
    required this.report,
    required this.now,
    required this.onOptions,
    this.onTap,
  });

  final SentReport report;
  final DateTime now;
  final VoidCallback? onTap;
  final ValueChanged<Offset?> onOptions;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final r = report;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final (pill, fill, ink) = switch (r.status) {
      ReportStatus.waiting ||
      ReportStatus.offline ||
      ReportStatus.paused => (l.reportStatusQueued, c.chip, c.muted),
      ReportStatus.sending => (l.reportStatusSending, c.soft, c.accentText),
      ReportStatus.sent => (
        switch (r.issue) {
          final n? => l.reportStatusSent(n),
          null => l.reportStatusSending,
        },
        c.okSoft,
        c.ok,
      ),
      ReportStatus.failed => (
        l.reportStatusFailed,
        c.danger.withValues(alpha: 0.1),
        c.danger,
      ),
      ReportStatus.emailed => (l.reportStatusEmailed, c.chip, c.muted),
    };
    final why = switch (r.status) {
      // Its turn: when it goes, so a report queued doesn't look stuck.
      ReportStatus.waiting => switch (r.nextTry) {
        final at? when at.isAfter(now) => l.reportWaitAt(
          DateFormat.Hm(locale).format(at),
        ),
        _ => l.reportWaitTurn,
      },
      ReportStatus.offline => l.reportWaitOffline,
      ReportStatus.paused => l.reportWaitPaused,
      ReportStatus.failed => l.reportTapRetry,
      _ => null,
    };
    final day = DateTime(now.year, now.month, now.day)
        .difference(DateTime(r.created.year, r.created.month, r.created.day))
        .inDays;
    final when = day == 1
        ? l.yesterdayAt(DateFormat.Hm(locale).format(r.created))
        : rowTime(r.created, now, locale);
    return Semantics(
      label: l.reportShown(r.title, pill),
      excludeSemantics: true,
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: () => onOptions(null),
        onSecondaryTapUp: (d) => onOptions(d.globalPosition),
        child: MouseRegion(
          cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.body.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.fg,
                        ),
                      ),
                      Text(
                        why == null ? when : '$when · $why',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.body.copyWith(
                          fontSize: 13,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: reduceMotion(context)
                      ? Duration.zero
                      : PiumaMotion.fast,
                  curve: PiumaMotion.curve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(PiumaRadius.pill),
                  ),
                  child: Text(
                    pill,
                    style: PiumaType.body.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
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

/// A line of the options popover.
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final ink = danger ? c.danger : c.fg;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              PiumaIconView(icon, size: 18, color: ink),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: PiumaType.body.copyWith(fontSize: 14, color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
