import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design/look.dart';
import 'design/theme.dart';
import 'design/tokens.g.dart';
import 'dev_copy.dart';
import 'engine/api/engine.dart' as engine;
import 'engine/api/feedback.dart' as feedback;
import 'engine/frb_generated.dart';
import 'feedback/report_context.dart';
import 'home.dart';
import 'l10n/app_localizations.dart';
import 'legal.dart';
import 'notify/android_background.dart';
import 'mail/android_passwords.dart';
import 'mail/engine_source.dart';
import 'mail/mail_source.dart';
import 'reader_window.dart';
import 'updates/updates.dart';

Future<void> main(List<String> args) async {
  // A message opened in a window of its own: [window id, its argument].
  if (args.firstOrNull == 'multi_window') {
    return _readerWindow(args.elementAtOrNull(2) ?? '');
  }
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  await RustLib.init();
  final dir = await appFolder();
  await dir.create(recursive: true);
  // First: the installer's hooks end here, and a downloaded update
  // restarts into itself before the engine opens.
  Updates.start(dir.path);
  engine.openEngine(dbPath: '${dir.path}/piuma.db');
  _keepCrashes();
  await AndroidPasswords.load();
  final source = EngineMailSource()..startSync();
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
      appearance: _loadAppearance(),
      onAppearance: _saveAppearance,
      home: (_, _) => MailHome(
        source: source,
        onOpenWindow: canOpenWindows ? openReaderWindow : null,
        replies: replies.stream,
      ),
    ),
  );
}

/// Keeps what went wrong for the next start, where the inbox offers to
/// report it. Only the error and its stack: nothing from the screen.
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
    flutter?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    keep(error, stack);
    return false;
  };
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
  });

  final HomeBuilder home;

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
