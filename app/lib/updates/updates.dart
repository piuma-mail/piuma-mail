import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/api/updates.dart' as engine;
import '../engine/api/updates.dart' show UpdateRelease;

export '../engine/api/updates.dart' show UpdateRelease;

/// The feed this build checks (`--dart-define=PIUMA_UPDATE_URL=…`, set
/// by `tools/windows-release.ps1`); empty turns updates off.
const updateFeed = String.fromEnvironment('PIUMA_UPDATE_URL');

/// Where an update stands, for the sidebar line, Settings › Updates and
/// the "What's new" sheet (`UpdatesToApprove`).
sealed class UpdateState {
  const UpdateState();
}

/// Not checked yet, or the last check failed (offline, say): quiet.
class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpToDate extends UpdateState {
  const UpToDate();
}

/// The last check couldn't reach the feed: Settings says so, quietly,
/// with Try again; the sidebar shows nothing.
class UpdateFailed extends UpdateState {
  const UpdateFailed();
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.release, this.percent);
  final UpdateRelease release;
  final int percent;
}

/// Downloaded: "Restart now" applies it, and the next start does anyway.
class UpdateReady extends UpdateState {
  const UpdateReady(this.release);
  final UpdateRelease release;
}

/// Desktop updates through the engine (Velopack): a look shortly after
/// start and every few hours, the download in the background, and the
/// restart. The app only draws [state]. Off where the build cannot
/// update: phones, `flutter run`, a build without a feed.
class Updates {
  Updates._(this.available, this.updatedTo, {this._fake = false});

  /// For tests and goldens: shows [state] and never calls the engine.
  @visibleForTesting
  factory Updates.fake({
    bool available = true,
    UpdateRelease? updatedTo,
    UpdateState state = const UpdateIdle(),
    DateTime? checkedAt,
  }) => Updates._(available, updatedTo, fake: true)
    ..state.value = state
    ..checkedAt = checkedAt;

  /// Makes [u] the one [instance] hands out (tests).
  @visibleForTesting
  static void use(Updates? u) => _instance = u;

  final bool _fake;

  static Updates? _instance;

  /// Set by [start]; off until then (tests, reader windows).
  static Updates get instance => _instance ?? Updates._(false, null);

  /// Runs the installer's start-up part, before the engine opens: it may
  /// end the process, or restart it into an update downloaded earlier.
  static Updates start(String supportDir) {
    final s = engine.updatesStartup(supportDir: supportDir);
    final u = Updates._(s.installed && updateFeed.isNotEmpty, s.updatedTo);
    _instance = u;
    if (u.available) {
      if (engine.updatesReady() case final ready?) {
        u.state.value = UpdateReady(ready);
      }
      u._timer = Timer(const Duration(seconds: 30), u._look);
    }
    return u;
  }

  /// Updates can work in this build.
  final bool available;

  /// Restarted into a new version: for the one-time "Updated to …" toast.
  final UpdateRelease? updatedTo;

  /// The toast for [updatedTo] went up: once, however often the inbox
  /// opens.
  bool announced = false;

  final state = ValueNotifier<UpdateState>(const UpdateIdle());

  /// When a check last reached the feed: "Checked 10 minutes ago".
  DateTime? checkedAt;

  Timer? _timer;
  static const _every = Duration(hours: 4);

  void _look() {
    _timer = Timer(_every, _look);
    check().ignore();
  }

  /// Checks now (Settings › Updates › Check for updates) and downloads
  /// what it finds.
  Future<void> check() async {
    final now = state.value;
    if (_fake ||
        !available ||
        now is UpdateChecking ||
        now is UpdateDownloading) {
      return;
    }
    state.value = const UpdateChecking();
    try {
      final release = await engine.updatesCheck(feed: updateFeed);
      checkedAt = DateTime.now();
      if (release == null) {
        state.value = now is UpdateReady ? now : const UpToDate();
        return;
      }
      if (now is UpdateReady && now.release.version == release.version) {
        state.value = now;
        return;
      }
      state.value = UpdateDownloading(release, 0);
      await for (final p in engine.updatesDownload(feed: updateFeed)) {
        state.value = UpdateDownloading(release, p);
      }
      final ready = engine.updatesReady();
      state.value = ready == null ? const UpdateIdle() : UpdateReady(ready);
    } catch (_) {
      // Offline or the feed is away: look again later, quietly.
      state.value = now is UpdateReady ? now : const UpdateFailed();
    }
  }

  /// "Restart now": closes the app, applies the update and opens it.
  Future<void> restart() async {
    if (!_fake) await engine.updatesRestart();
  }

  @visibleForTesting
  void dispose() => _timer?.cancel();
}
