import 'package:url_launcher/url_launcher.dart';

import '../mail/phone_files.dart';

/// Opens a link outside the app (the browser, or the mail app for
/// mailto:). Tests replace it to see what would open.
Future<void> Function(Uri uri) openExternalLink = (uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
};

/// Opens a saved file with the app the system uses for it. Tests replace
/// it to see what would open.
Future<void> Function(String path) openLocalFile = (path) async {
  // Phones can't open a bare file path from another app.
  if (await PhoneFiles.open(path)) return;
  await launchUrl(Uri.file(path));
};
