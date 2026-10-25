import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// On Windows, a build the installer didn't put in place (`flutter run`,
/// a test build) is a dev copy: it keeps its own folder, passwords, Start
/// menu shortcut and notices, so it never touches the copy installed on
/// the same PC. The installer keeps `Update.exe` one folder above the
/// program (`…\PiumaMail\current\piuma_mail.exe`); the runner
/// (`windows/runner/start_menu.cpp`) and the engine (`credentials.rs`)
/// tell the two apart the same way.
final bool devCopy =
    !kIsWeb &&
    Platform.isWindows &&
    !File('${File(Platform.resolvedExecutable).parent.parent.path}\\Update.exe')
        .existsSync();

/// The app's folder: the database, the web view's profile, crashes. A
/// dev copy's sits next to the installed copy's.
Future<Directory> appFolder() async {
  final dir = await getApplicationSupportDirectory();
  return devCopy ? Directory('${dir.path} (dev)') : dir;
}
