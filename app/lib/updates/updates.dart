import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../engine/api/updates.dart' as engine;
import '../engine/api/updates.dart' show UpdatePrefs, UpdateRelease;
import '../version.dart';
import '../widgets/links.dart';

export '../engine/api/updates.dart' show UpdatePrefs, UpdateRelease;

/// The feed this build checks (`--dart-define=PIUMA_UPDATE_URL=…`, set
/// by the release builds); empty turns updates off.
const updateFeed = String.fromEnvironment('PIUMA_UPDATE_URL');

/// The releases this build follows (`--dart-define=PIUMA_UPDATE_CHANNEL=…`):
/// "beta" takes GitHub prereleases, "stable" only full releases. Early
/// (canary) releases come on top only when the user turns them on.
const updateChannel = String.fromEnvironment(
  'PIUMA_UPDATE_CHANNEL',
  defaultValue: 'beta',
);

/// Where an update stands, for the sidebar line, Settings › Help & feedback › Updates and
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

/// Where the app cannot install updates (Android, macOS, Linux): a newer
/// release exists, and [url] is its page.
class UpdateNotice extends UpdateState {
  const UpdateNotice(this.release, this.url);
  final UpdateRelease release;
  final String url;
}

/// The defaults, until the user changes them in Settings › Help & feedback › Updates.
const defaultUpdatePrefs = UpdatePrefs(automatic: true, early: false);

/// Updates through the engine: a look shortly after start and every few
/// hours. On an installed Windows app (Velopack) the download runs in
/// the background and a restart applies it; on Android, macOS and Linux
/// the app only says that a newer release exists ([notifyOnly]). The app
/// only draws [state]. Off where the build cannot update: iOS,
/// `flutter run`, a build without a feed or a build number.
class Updates {
  Updates._(
    this.available,
    this.updatedTo, {
    this.notifyOnly = false,
    UpdatePrefs prefs = defaultUpdatePrefs,
    this._fake = false,
  }) : prefs = ValueNotifier(prefs);

  /// For tests and goldens: shows [state] and never calls the engine.
  @visibleForTesting
  factory Updates.fake({
    bool available = true,
    bool notifyOnly = false,
    UpdateRelease? updatedTo,
    UpdateState state = const UpdateIdle(),
    DateTime? checkedAt,
    UpdatePrefs prefs = defaultUpdatePrefs,
  }) =>
      Updates._(
          available,
          updatedTo,
          notifyOnly: notifyOnly,
          prefs: prefs,
          fake: true,
        )
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
  /// end the process, or restart it into an update downloaded earlier,
  /// or (after a launch that never drew its first frame) into a newer
  /// release found right now. Call [launched] once the first frame is up.
  static Updates start(String supportDir) {
    final s = engine.updatesStartup(
      supportDir: supportDir,
      feed: updateFeed,
      channel: updateChannel,
    );
    final notify = _canNotify && updateFeed.isNotEmpty && appBuild > 0;
    final u = Updates._(
      (s.installed && updateFeed.isNotEmpty) || notify,
      s.updatedTo,
      notifyOnly: notify,
      prefs: engine.updatesPrefs(),
    );
    _instance = u;
    if (u.available) {
      if (!notify) {
        if (engine.updatesReady() case final ready?) {
          u.state.value = UpdateReady(ready);
        }
      }
      // After a failed launch, look at once: a fix may be out.
      u._schedule(
        s.previousLaunchFailed
            ? const Duration(seconds: 1)
            : const Duration(seconds: 30),
      );
    }
    return u;
  }

  /// The first frame is on screen: the next launch need not look for a
  /// fix before opening the engine.
  static void launched() {
    try {
      engine.updatesLaunched();
    } catch (_) {
      // Not started (tests): nothing to clear.
    }
  }

  /// The platforms where the app says a release is out but cannot
  /// install it. iOS updates only through the App Store.
  static bool get _canNotify =>
      !kIsWeb && (Platform.isAndroid || Platform.isMacOS || Platform.isLinux);

  /// Updates can work in this build.
  final bool available;

  /// Only says a newer release exists ([UpdateNotice]); never downloads.
  final bool notifyOnly;

  /// The user's choices: automatic checks, early releases.
  final ValueNotifier<UpdatePrefs> prefs;

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

  /// The next automatic look, unless the user turned them off.
  void _schedule(Duration after) {
    _timer?.cancel();
    _timer = prefs.value.automatic ? Timer(after, _look) : null;
  }

  void _look() {
    _schedule(_every);
    check().ignore();
  }

  /// Settings › Help & feedback › Updates › "Look for new versions on their own".
  void setAutomatic(bool on) {
    _setPrefs(UpdatePrefs(automatic: on, early: prefs.value.early));
    if (!_fake) _schedule(const Duration(seconds: 5));
  }

  /// Settings › Help & feedback › Updates › "Early releases".
  void setEarly(bool on) {
    _setPrefs(UpdatePrefs(automatic: prefs.value.automatic, early: on));
    if (!_fake && prefs.value.automatic) _schedule(const Duration(seconds: 1));
  }

  void _setPrefs(UpdatePrefs p) {
    prefs.value = p;
    if (_fake) return;
    try {
      engine.updatesSetPrefs(prefs: p);
    } catch (_) {
      // Kept for this session only.
    }
  }

  /// Opens the page of the release a notice is about.
  Future<void> openNotice(UpdateNotice notice) =>
      openExternalLink(Uri.parse(notice.url));

  /// Checks now (Settings › Help & feedback › Updates › Check for updates) and downloads
  /// what it finds, or, where the app cannot install it, says so.
  Future<void> check() async {
    final now = state.value;
    if (_fake ||
        !available ||
        now is UpdateChecking ||
        now is UpdateDownloading) {
      return;
    }
    state.value = const UpdateChecking();
    if (notifyOnly) {
      try {
        final notice = await engine.updatesNotice(
          feed: updateFeed,
          channel: updateChannel,
          build: appBuild,
        );
        checkedAt = DateTime.now();
        state.value = notice == null
            ? const UpToDate()
            : UpdateNotice(notice.release, notice.url);
      } catch (_) {
        state.value = now is UpdateNotice ? now : const UpdateFailed();
      }
      return;
    }
    try {
      final release = await engine.updatesCheck(
        feed: updateFeed,
        channel: updateChannel,
      );
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
      await for (final p in engine.updatesDownload(
        feed: updateFeed,
        channel: updateChannel,
      )) {
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
