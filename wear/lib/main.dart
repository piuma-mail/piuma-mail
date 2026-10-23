import 'package:flutter/material.dart';

import 'design/tokens.g.dart';
import 'inbox_screen.dart';
import 'l10n/app_localizations.dart';
import 'link.dart';
import 'round.dart';

/// Piuma Mail on Wear OS (`WatchWearOS`): the inbox at a glance, fed by
/// the phone, which keeps the mail and the accounts.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final link = PhoneLink();
  runApp(WatchApp(link: link));
  link.start();
}

class WatchApp extends StatefulWidget {
  const WatchApp({super.key, required this.link});

  final PhoneLink link;

  @override
  State<WatchApp> createState() => _WatchAppState();
}

class _WatchAppState extends State<WatchApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Fresh mail each time the watch app comes back on screen.
    if (state == AppLifecycleState.resumed) widget.link.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const c = watchColors;
    return LinkScope(
      link: widget.link,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => AppLocalizations.of(context).appName,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: PiumaFonts.sans,
          scaffoldBackgroundColor: c.darkroom,
          colorScheme: ColorScheme.dark(
            primary: c.accent,
            onPrimary: c.onAccent,
            surface: c.darkroom,
            onSurface: c.fg,
          ),
          splashFactory: InkRipple.splashFactory,
        ),
        home: const InboxScreen(),
      ),
    );
  }
}
