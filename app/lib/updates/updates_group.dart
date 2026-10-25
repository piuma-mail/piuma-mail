import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/readable.dart' show fileSize;
import '../version.dart';
import '../widgets/button.dart';
import '../widgets/progress.dart';
import 'updates.dart';
import 'whats_new.dart';

/// Settings › Help & feedback › Updates (`UpdatesToApprove` section 3):
/// the version you have, where the update stands, and the notes. Only
/// where the build can update (the desktop installs).
class UpdatesGroup extends StatelessWidget {
  const UpdatesGroup({super.key, required this.now});

  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final updates = Updates.instance;
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder<UpdateState>(
      valueListenable: updates.state,
      builder: (context, state, _) {
        // The notes to show: the version waiting, else the one just
        // restarted into.
        final notes = switch (state) {
          UpdateReady(:final release) => release,
          _ => updates.updatedTo,
        };
        final rows = <Widget>[
          _Row(
            title: l.updatesVersion,
            trailing: Text(
              appVersionShown,
              style: PiumaType.body.copyWith(
                fontSize: 13,
                color: c.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _state(context, updates, state),
          if (notes != null)
            Builder(
              builder: (row) => PiumaPressable(
                onTap: () {
                  final box = row.findRenderObject() as RenderBox?;
                  showWhatsNew(
                    row,
                    release: notes,
                    ready: state is UpdateReady,
                    from: box != null && box.hasSize
                        ? box.localToGlobal(Offset.zero) & box.size
                        : null,
                  );
                },
                semanticLabel: l.seeWhatsNew,
                child: _Row(
                  title: l.seeWhatsNew,
                  trailing: PiumaIconView(
                    PiumaIcon.chevronRight,
                    size: 16,
                    color: c.muted,
                  ),
                ),
              ),
            ),
        ];
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              for (final (i, row) in rows.indexed)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: c.line)),
                  ),
                  child: row,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _state(BuildContext context, Updates updates, UpdateState state) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final check = PiumaButton(
      label: l.checkForUpdates,
      kind: PiumaButtonKind.secondary,
      size: PiumaButtonSize.compact,
      onPressed: state is UpdateChecking ? null : updates.check,
    );
    switch (state) {
      case UpdateReady(:final release):
        return _Row(
          title: l.updateReadyTitle(shownVersion(release.version)),
          subtitle: l.updateGoesInOnRestart,
          trailing: PiumaButton(
            label: l.restart,
            size: PiumaButtonSize.compact,
            onPressed: () => updates.restart().ignore(),
          ),
        );
      case UpdateDownloading(:final release, :final percent):
        final total = release.size.toInt();
        return _Row(
          title: l.updateDownloading(
            shownVersion(release.version).split(' ').first,
            percent,
          ),
          below: PiumaProgress(
            value: percent / 100,
            track: PiumaTheme.of(context).chip,
            thickness: 4,
          ),
          trailing: total > 0
              ? Text(
                  l.updateDownloadedOf(
                    fileSize(total * percent ~/ 100, locale: locale),
                    fileSize(total, locale: locale),
                  ),
                  style: PiumaType.small.copyWith(
                    fontSize: 12.5,
                    color: c.muted,
                  ),
                )
              : null,
        );
      case UpdateFailed():
        return _Row(
          title: l.updateCouldntCheck,
          trailing: PiumaButton(
            label: l.tryAgain,
            kind: PiumaButtonKind.secondary,
            size: PiumaButtonSize.compact,
            onPressed: updates.check,
          ),
        );
      case UpdateChecking():
        return _Row(title: l.updateChecking, trailing: check);
      case UpToDate():
      case UpdateIdle():
        final at = updates.checkedAt;
        return _Row(
          title: state is UpToDate ? l.upToDate : l.updatesAuto,
          subtitle: at == null ? null : _checked(l, now().difference(at)),
          trailing: check,
        );
    }
  }

  static String _checked(AppLocalizations l, Duration ago) {
    if (ago.inMinutes < 1) return l.checkedJustNow;
    if (ago.inHours < 1) return l.checkedMinutesAgo(ago.inMinutes);
    if (ago.inDays < 1) return l.checkedHoursAgo(ago.inHours);
    return l.checkedDaysAgo(ago.inDays);
  }
}

/// One line of the group: its title, a muted line or a bar under it, and
/// what sits on the right.
class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.below, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? below;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final trailing = this.trailing;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PiumaType.body.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                  if (subtitle case final s?)
                    Text(
                      s,
                      style: PiumaType.body.copyWith(
                        fontSize: 13,
                        color: c.muted,
                      ),
                    ),
                  if (below case final b?) ...[const SizedBox(height: 6), b],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing],
          ],
        ),
      ),
    );
  }
}
