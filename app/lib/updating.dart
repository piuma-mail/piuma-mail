import 'dart:async';

import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'design/tokens.g.dart';
import 'engine/api/engine.dart' as engine;
import 'l10n/app_localizations.dart';
import 'widgets/progress.dart';

/// How long opening may take before "Updating your mail" shows: an open
/// that needs no update is over well before, and nothing flashes.
const _quietOpen = Duration(milliseconds: 400);

/// Opens the engine. That is quick, except the first time after an update
/// of the app on a big mailbox, when the database is copied and brought
/// up to date first: then [UpdatingMail] shows meanwhile, drawn by
/// [show], instead of a window that doesn't answer. Throws what opening
/// threw.
Future<void> openEngineShowingUpdate(
  String dbPath, {
  required void Function(Widget screen) show,
}) async {
  final slow = Timer(_quietOpen, () => show(const UpdatingMail()));
  try {
    await engine.openEngine(dbPath: dbPath);
  } finally {
    slow.cancel();
  }
}

/// "Updating your mail", while the database is brought up to date after
/// an update of the app. Stopping the app meanwhile loses nothing: the
/// update goes on where it stopped at the next start.
class UpdatingMail extends StatelessWidget {
  const UpdatingMail({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Material(
      color: c.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(PiumaSpace.s32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.updatingMail,
                  textAlign: TextAlign.center,
                  style: PiumaType.title.copyWith(color: c.fg),
                ),
                const SizedBox(height: PiumaSpace.s8),
                Text(
                  l.updatingMailNote,
                  textAlign: TextAlign.center,
                  style: PiumaType.body.copyWith(color: c.muted),
                ),
                const SizedBox(height: PiumaSpace.s24),
                PiumaProgress(track: c.track),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
