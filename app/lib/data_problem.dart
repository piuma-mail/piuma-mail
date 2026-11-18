import 'package:flutter/widgets.dart';

import 'design/theme.dart';
import 'design/tokens.g.dart';
import 'l10n/app_localizations.dart';
import 'widgets/button.dart';
import 'widgets/links.dart';

/// Shown instead of the inbox when the app can't open its database (an
/// error in an update of it, a locked or damaged file, data from a newer
/// Piuma): what happened, Try again, and Report. Nothing is lost here:
/// the mail is on the servers, and the file is left as it is.
class DataProblem extends StatelessWidget {
  const DataProblem({
    super.key,
    required this.detail,
    required this.onRetry,
    this.newer = false,
    this.reportAddress = '',
  });

  /// What the engine said, for the report.
  final String detail;
  final VoidCallback onRetry;

  /// The data was written by a newer version: updating Piuma fixes it.
  final bool newer;

  /// Where Report writes to; the project's issues when empty.
  final String reportAddress;

  Uri get _report {
    const subject = "Piuma couldn't open its data";
    if (reportAddress.isNotEmpty) {
      return Uri(
        scheme: 'mailto',
        path: reportAddress,
        query: _query({'subject': subject, 'body': detail}),
      );
    }
    return Uri.https('github.com', '/piuma-mail/piuma-mail/issues/new', {
      'title': subject,
      'body': detail,
    });
  }

  static String _query(Map<String, String> fields) => fields.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    // Shown in place of the whole app: nothing above it sets the text style.
    return ColoredBox(
      color: c.bg,
      child: DefaultTextStyle(
        style: PiumaType.body.copyWith(color: c.fg),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(PiumaSpace.s24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.dataProblemTitle,
                      style: PiumaType.title.copyWith(color: c.fg),
                    ),
                    const SizedBox(height: PiumaSpace.s12),
                    Text(
                      newer ? l.dataProblemNewer : l.dataProblemBody,
                      style: PiumaType.body.copyWith(color: c.muted),
                    ),
                    const SizedBox(height: PiumaSpace.s24),
                    Wrap(
                      spacing: PiumaSpace.s8,
                      runSpacing: PiumaSpace.s8,
                      children: [
                        PiumaButton(label: l.tryAgain, onPressed: onRetry),
                        PiumaButton(
                          label: l.reportThisProblem,
                          kind: PiumaButtonKind.secondary,
                          onPressed: () => openExternalLink(_report),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
