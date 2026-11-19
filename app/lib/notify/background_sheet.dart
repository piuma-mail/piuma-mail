import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';

/// Asks once, after the first account, how new mail arrives with the app
/// closed (`AndroidBackground`, 2). Continue asks Android for notices
/// and picks "As it arrives"; Not now, or closing the sheet, picks
/// "Every 15 minutes". Settings › Notifications changes it later.
Future<void> askBackgroundDelivery(
  BuildContext context,
  MailSource source, {
  Future<void> Function() askNotices = _noAsk,
}) async {
  final l = AppLocalizations.of(context);
  final instant = await showPiumaSheet<bool>(
    context,
    label: l.backgroundTitle,
    builder: (_) => const BackgroundSheet(),
  );
  if (instant ?? false) {
    await askNotices();
    await source.setBackgroundDelivery(BackgroundDelivery.instant);
  } else {
    await source.setBackgroundDelivery(BackgroundDelivery.periodic);
  }
}

Future<void> _noAsk() async {}

class BackgroundSheet extends StatelessWidget {
  const BackgroundSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IntroSheet(
      icon: PiumaIcon.bell,
      title: l.backgroundTitle,
      body: l.backgroundBody,
    );
  }
}

/// What the app is about to ask the system for, and why, before the
/// system's own question: Continue pops true, Not now false.
class IntroSheet extends StatelessWidget {
  const IntroSheet({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.sheet = true,
  });

  final PiumaIcon icon;
  final String title;
  final String body;

  /// In a sheet from the bottom, with its handle; false in a dialog.
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: sheet
          ? const EdgeInsets.fromLTRB(22, 0, 22, 8)
          : EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sheet)
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: PiumaIconView(icon, size: 20, color: c.fg),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: PiumaType.title.copyWith(color: c.fg, fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(body, style: PiumaType.body.copyWith(color: c.muted)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PiumaButton(
              label: l.continueAction,
              size: PiumaButtonSize.large,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: PiumaButton(
              label: l.notNow,
              kind: PiumaButtonKind.tertiary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
        ],
      ),
    );
  }
}
