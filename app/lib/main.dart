import 'dart:async';
import 'dart:io' show Directory, IOSink, Platform, exit, stderr, stdout;
import 'dart:ui' show AppExitResponse;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design/look.dart';
import 'design/theme.dart';
import 'design/tokens.g.dart';
import 'data_problem.dart';
import 'dev_copy.dart';
import 'engine/api/engine.dart' as engine;
import 'engine/api/feedback.dart' as feedback;
import 'engine/frb_generated.dart';
import 'engine/api/updates.dart' as engine_updates;
import 'feedback/report_context.dart';
import 'feedback/report_sheet.dart';
import 'home.dart';
import 'l10n/app_localizations.dart';
import 'legal.dart';
import 'notify/android_background.dart';
import 'mail/android_passwords.dart';
import 'mail/engine_source.dart';
import 'mail/mail_source.dart';
import 'outside/arrivals.dart';
import 'outside/shell.dart';
import 'reader_window.dart';
import 'updates/updates.dart';
import 'updating.dart';
import 'widgets/links.dart';

Future<void> main(List<String> args) async {
  // A message opened in a window of its own: [window id, its argument].
  if (args.firstOrNull == 'multi_window') {
    return _readerWindow(args.elementAtOrNull(2) ?? '');
  }
  if (args.contains('--smoke-test')) return _smokeTest();
  // First, so whatever goes wrong from here on is kept for a report.
  _keepCrashes();
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  await RustLib.init();
  final dir = await appFolder();
  await dir.create(recursive: true);
  // First: the installer's hooks end here, and a downloaded update
  // restarts into itself before the engine opens.
  Updates.start(dir.path);
  // What this launch was asked to open (a mailto: link, an email file,
  // files to send): it waits for the inbox. Later launches come through
  // the platform (Arrivals.start).
  Arrivals.instance.addArgs(args);
  await _start(dir.path);
}

/// Opens the engine and shows the inbox; when the data can't be opened (a
/// failed update of the database, a locked or damaged file, data from a
/// newer Piuma), says so with Try again and Report instead of a blank
/// window or a crash at every start.
Future<void> _start(String dir) async {
  try {
    // Off the thread that draws: after an update the database is brought
    // up to date first, with "Updating your mail" on screen if it is slow.
    await openEngineShowingUpdate(
      '$dir/piuma.db',
      show: (screen) => runApp(PiumaApp(home: (_, _) => screen)),
    );
  } catch (e, stack) {
    // Kept for the report offered at the next start that works.
    try {
      feedback.feedbackRecordCrash(text: '$e\n$stack');
    } catch (_) {}
    runApp(
      PiumaApp(
        appearance: _loadAppearance(),
        home: (_, _) => DataProblem(
          detail: '$e',
          newer: '$e'.contains('newer version of Piuma'),
          reportAddress: _feedbackAddress(),
          onRetry: () => _start(dir).ignore(),
        ),
      ),
    );
    return;
  }
  _watchExits();
  // A password the system can no longer read leaves its account asking
  // for it again; it doesn't keep the app from starting.
  await AndroidPasswords.load();
  final source = EngineMailSource()..startSync();
  // mailto: links in emails write here, in Piuma's own compose.
  openMailtoLink = (uri) async => Arrivals.instance.mailto(uri);
  Arrivals.instance.start().ignore();
  // The background service or the 15-minute look, as picked.
  AndroidBackground.apply().ignore();
  final replies = StreamController<MailRow>.broadcast();
  if (canOpenWindows) {
    listenToReaderWindows(
      onChanged: source.changedElsewhere,
      onReply: (m) async {
        if (await m.find(source) case final row?) replies.add(row);
      },
    ).ignore();
  }
  runApp(
    PiumaApp(
      reportSource: source,
      appearance: _loadAppearance(),
      onAppearance: _saveAppearance,
      home: (_, _) => MailHome(
        source: source,
        onOpenWindow: canOpenWindows ? openReaderWindow : null,
        replies: replies.stream,
        arrivals: Arrivals.instance,
      ),
    ),
  );
  // This launch worked: the next one need not look for a fix first.
  WidgetsBinding.instance.addPostFrameCallback((_) => Updates.launched());
}

/// `piuma_mail --smoke-test`, run by the "Release" workflow on the
/// installed app: the start-up part of updates and the engine, on a
/// throwaway folder, then exit 0 (1 on any error). Nothing is drawn and
/// nothing reaches the network.
Future<void> _smokeTest() async {
  // Printed with a failure, so the workflow's log says which step broke.
  var step = 'start';
  try {
    WidgetsFlutterBinding.ensureInitialized();
    step = 'RustLib.init';
    await RustLib.init();
    final dir = await Directory.systemTemp.createTemp('piuma-smoke-');
    step = 'updatesStartup';
    // No feed: a smoke test never looks for updates.
    final s = engine_updates.updatesStartup(
      supportDir: dir.path,
      feed: '',
      channel: updateChannel,
    );
    if (s.previousLaunchFailed) throw StateError('a new folder has a marker');
    step = 'openEngine';
    // Awaited: the engine opens off this thread, and every call before it
    // is done fails with "engine not open".
    await engine.openEngine(dbPath: '${dir.path}/piuma.db');
    step = 'appearanceSettings';
    // A first query through the open database.
    engine.appearanceSettings();
    step = 'updatesLaunched';
    engine_updates.updatesLaunched();
    await _say(stdout, 'Smoke test passed (${dir.path}).');
    // The folder stays: the open database keeps it busy on Windows, and
    // the runner is thrown away.
    exit(0);
  } catch (e, stack) {
    final detail = e is engine.EngineError
        ? '${e.kind.name}: ${e.detail}'
        : '$e';
    await _say(stderr, 'Smoke test failed at $step: $detail\n$stack');
    exit(1);
  }
}

/// A line for the workflow's log. A window app may have nowhere to
/// write it; the exit code still tells.
Future<void> _say(IOSink sink, String line) async {
  try {
    sink.writeln(line);
    await sink.flush();
  } catch (_) {}
}

String _feedbackAddress() {
  try {
    return feedback.feedbackAddress();
  } catch (_) {
    return '';
  }
}

/// Keeps what went wrong for the next start, where the inbox offers to
/// report it. Only the error and its stack: nothing from the screen. The
/// engine keeps the message's first line, scrubbed, and the frames. In a
/// release build nothing goes to the console either: an exception's text
/// can quote mail, and on Android the console is the system log.
void _keepCrashes() {
  void keep(Object error, StackTrace? stack) {
    try {
      feedback.feedbackRecordCrash(text: '$error\n$stack');
    } catch (_) {
      // Nowhere to keep it.
    }
  }

  final flutter = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!details.silent) keep(details.exception, details.stack);
    if (!kReleaseMode) flutter?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    keep(error, stack);
    // Handled in a release build, so the engine doesn't print it.
    return kReleaseMode;
  };
}

/// What stopped the app without a Dart or Rust error, kept like a crash to
/// offer a report at this start: on Android, what the system recorded
/// (stopped responding, native crashes); on the desktop, a last session
/// that never closed normally. Every way out ends the session: the window
/// or Cmd-Q (asked to exit), the engine going away (detached), the tray's
/// Quit (the shell asks first), and signing out or shutting down, where
/// the shell removes the session's marker itself.
void _watchExits() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    void end() {
      try {
        feedback.feedbackSessionEnd();
      } catch (_) {}
    }

    try {
      feedback.feedbackSessionStart();
      Shell.watchSession(
        marker: feedback.feedbackSessionMarker(),
        onQuitting: end,
      ).ignore();
    } catch (_) {}
    AppLifecycleListener(
      onExitRequested: () async {
        end();
        return AppExitResponse.exit;
      },
      onDetach: end,
    );
  }
  AndroidBackground.exitReasons().then((reasons) {
    for (final r in reasons) {
      feedback.feedbackRecordCrash(text: r);
    }
  }).ignore();
}

/// A reader window: the engine is already open in this process, and
/// the inbox's window keeps it in sync.
Future<void> _readerWindow(String argument) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  await RustLib.init();
  final source = EngineMailSource();
  final row = await WindowMessage.decode(argument)?.find(source);
  final self = await WindowController.fromCurrentEngine();
  runApp(
    PiumaApp(
      reportSource: source,
      appearance: _loadAppearance(),
      home: (_, _) => ReaderWindow(
        source: source,
        row: row,
        onChanged: InboxWindow.changed,
        onReply: InboxWindow.reply,
        onDone: () => self.hide(),
      ),
    ),
  );
  // Shown once drawn, so it never flashes empty.
  WidgetsBinding.instance.addPostFrameCallback((_) => self.show());
}

Appearance _loadAppearance() {
  try {
    final a = engine.appearanceSettings();
    return Appearance(
      theme: ThemeChoice.values.byName(a.theme.name),
      compact: a.compact,
      previewLines: a.previewLines,
      translateInto: a.translateInto,
      language: a.language,
      openOriginal: a.openOriginal,
    );
  } catch (_) {
    return const Appearance();
  }
}

void _saveAppearance(Appearance a) {
  try {
    engine.setAppearanceSettings(
      settings: engine.AppearanceSettings(
        theme: engine.ThemeChoice.values.byName(a.theme.name),
        compact: a.compact,
        previewLines: a.previewLines,
        translateInto: a.translateInto,
        language: a.language,
        openOriginal: a.openOriginal,
      ),
    );
  } catch (_) {
    // Kept for this run only.
  }
}

/// Builds the first screen; gets the current theme and a way to flip it.
typedef HomeBuilder = Widget Function(bool dark, VoidCallback toggleTheme);

class PiumaApp extends StatefulWidget {
  const PiumaApp({
    super.key,
    required this.home,
    this.initialDark,
    this.appearance = const Appearance(),
    this.onAppearance,
    this.locale,
    this.reportSource,
  });

  final HomeBuilder home;
  final MailSource? reportSource;

  /// Light or dark from the start, over [appearance]'s theme.
  final bool? initialDark;

  /// Settings › Appearance at start.
  final Appearance appearance;

  /// Keeps a changed appearance.
  final ValueChanged<Appearance>? onAppearance;

  /// Over [appearance]'s language, as in tests.
  final Locale? locale;

  @override
  State<PiumaApp> createState() => _PiumaAppState();
}

class _PiumaAppState extends State<PiumaApp> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_reportKey);
    HardwareKeyboard.instance.addHandler(_quitKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_reportKey);
    HardwareKeyboard.instance.removeHandler(_quitKey);
    super.dispose();
  }

  /// Ctrl+Q on Linux quits for good, as GNOME and KDE apps do, even while
  /// Piuma keeps running in the tray. macOS has ⌘Q in its app menu
  /// already; on Windows quitting stays in the tray's menu (Alt+F4 closes
  /// the window, as there).
  bool _quitKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyQ ||
        defaultTargetPlatform != TargetPlatform.linux) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed ||
        keys.isShiftPressed ||
        keys.isAltPressed ||
        keys.isMetaPressed) {
      return false;
    }
    unawaited(Shell.quit());
    return true;
  }

  /// ⇧⌘R on Apple, Ctrl+Shift+R elsewhere: the report sheet, from any
  /// screen and whatever has focus. The screen is captured before the
  /// sheet opens, so the screenshot shows what was there.
  bool _reportKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyR) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final mod = apple ? keys.isMetaPressed : keys.isControlPressed;
    final other = apple ? keys.isControlPressed : keys.isMetaPressed;
    if (!mod || other || !keys.isShiftPressed || keys.isAltPressed) {
      return false;
    }
    final source = widget.reportSource;
    final context = _navigator.currentState?.overlay?.context;
    if (source == null || context == null) return false;
    unawaited(openReport(context, source: source));
    return true;
  }

  late Appearance _look = switch (widget.initialDark) {
    null => widget.appearance,
    final dark => widget.appearance.copyWith(
      theme: dark ? ThemeChoice.dark : ThemeChoice.light,
    ),
  };

  void _change(Appearance look) {
    if (look == _look) return;
    setState(() => _look = look);
    widget.onAppearance?.call(look);
  }

  @override
  Widget build(BuildContext context) {
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final dark = switch (_look.theme) {
      ThemeChoice.light => false,
      ThemeChoice.dark => true,
      ThemeChoice.automatic => systemDark,
    };
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'Piuma Mail',
      debugShowCheckedModeBanner: false,
      locale:
          widget.locale ??
          (_look.language == null ? null : Locale(_look.language!)),
      supportedLocales: AppLocalizations.supportedLocales,
      // The device's language where the app speaks it, else English.
      localeListResolutionCallback: (device, _) =>
          appLocale(null, device ?? const []),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildPiumaTheme(Brightness.light),
      darkTheme: buildPiumaTheme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: PiumaMotion.theme,
      themeAnimationCurve: PiumaMotion.curve,
      // Around everything, so a report can show the screen as it was.
      builder: (context, child) => RepaintBoundary(
        key: ReportContext.screen,
        child: PiumaLook(appearance: _look, onChanged: _change, child: child!),
      ),
      home: widget.home(
        dark,
        () => _change(
          _look.copyWith(theme: dark ? ThemeChoice.light : ThemeChoice.dark),
        ),
      ),
    );
  }
}
