import 'package:flutter/widgets.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../version.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import 'updates.dart';

/// A release's version as the app shows its own: "0.1.0 (612)" for
/// "0.1.0-beta.612", as `appVersionShown` does.
String shownVersion(String version) {
  final m = RegExp(r'^(\d+\.\d+\.\d+)-[A-Za-z]+\.(\d+)$').firstMatch(version);
  return m == null ? version : '${m[1]} (${m[2]})';
}

/// The release notes shipped with this build, available offline on every
/// platform from Settings › Help & feedback › What's new.
UpdateRelease bundledRelease(AppLocalizations l) => UpdateRelease(
  version: appVersionShown,
  notes: l.bundledReleaseNotes,
  size: BigInt.zero,
);

/// The "What's new" sheet of `UpdatesToApprove` section 2: the version,
/// the release notes and, while the update waits, Later and Restart now.
/// It grows out of [from], the line or button tapped, when given.
Future<void> showWhatsNew(
  BuildContext context, {
  required UpdateRelease release,
  bool ready = false,
  Rect? from,
}) {
  final l = AppLocalizations.of(context);
  return showPiumaDialog<void>(
    context,
    label: l.whatsNew,
    width: 480,
    from: from,
    builder: (context) => _WhatsNew(release: release, ready: ready),
  );
}

class _WhatsNew extends StatelessWidget {
  const _WhatsNew({required this.release, required this.ready});

  final UpdateRelease release;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.whatsNew,
          style: PiumaType.subtitle.copyWith(fontSize: 18, color: c.fg),
        ),
        const SizedBox(height: 2),
        Text(
          l.whatsNewVersion(shownVersion(release.version)),
          style: PiumaType.small.copyWith(fontSize: 13, color: c.muted),
        ),
        const SizedBox(height: PiumaSpace.s16),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (height - 320).clamp(120, 300).toDouble(),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(PiumaRadius.row),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: ReleaseNotes(release.notes),
            ),
          ),
        ),
        if (ready) ...[
          const SizedBox(height: PiumaSpace.s16),
          Text(
            l.updateKeepsMail,
            style: PiumaType.small.copyWith(fontSize: 13, color: c.muted),
          ),
        ],
        const SizedBox(height: PiumaSpace.s16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: ready
              ? [
                  PiumaButton(
                    label: l.later,
                    kind: PiumaButtonKind.tertiary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: PiumaSpace.s8),
                  PiumaButton(
                    label: l.restartNow,
                    onPressed: () => Updates.instance.restart().ignore(),
                  ),
                ]
              : [
                  PiumaButton(
                    label: l.close,
                    kind: PiumaButtonKind.tertiary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
        ),
      ],
    );
  }
}

/// Release notes, written in Markdown for the release, in the app's own
/// type: "## New" headings, "- " bullets and plain paragraphs. Emphasis
/// marks and links are shown as their text.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(this.markdown, {super.key});

  final String markdown;

  static String _plain(String s) => s
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .trim();

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final text = PiumaType.body.copyWith(
      fontSize: 13.5,
      height: 1.5,
      color: c.fg,
    );
    final children = <Widget>[];
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line);
      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(line);
      if (children.isNotEmpty) {
        children.add(SizedBox(height: heading != null ? 14 : 8));
      }
      if (heading != null) {
        children.add(
          Text(
            _plain(heading[1]!),
            style: PiumaType.small.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        );
      } else if (bullet != null) {
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•', style: text.copyWith(color: c.muted)),
              const SizedBox(width: 8),
              Expanded(child: Text(_plain(bullet[1]!), style: text)),
            ],
          ),
        );
      } else {
        children.add(Text(_plain(line), style: text));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
