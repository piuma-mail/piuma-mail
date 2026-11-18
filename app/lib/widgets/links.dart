import 'package:url_launcher/url_launcher.dart';

import '../mail/phone_files.dart';

/// Opens a link outside the app (the browser, or the mail app for
/// mailto:). Tests replace it to see what would open.
Future<void> Function(Uri uri) openExternalLink = (uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
};

/// The schemes a link that came with an email may open: web pages and
/// addresses. Anything else (`file:`, `intent:`, `javascript:`, a custom
/// app scheme…) would hand another app on the device whatever the sender
/// chose, so it never opens.
const mailLinkSchemes = {'http', 'https', 'mailto'};

/// Whether [uri], from an email, may open: one of [mailLinkSchemes], with
/// somewhere to go (a host, or an address).
bool isMailLinkAllowed(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (!mailLinkSchemes.contains(scheme)) return false;
  if (scheme == 'mailto') return uri.path.trim().isNotEmpty;
  return uri.host.isNotEmpty;
}

/// Where a `mailto:` link from an email goes. For now the system's mail
/// app; this is the one place to route it to Piuma's own compose.
Future<void> Function(Uri uri) openMailtoLink = (uri) => openExternalLink(uri);

/// Opens a link that came with an email (its text, its layout, its list
/// headers, a card the Vault read from it). Only [mailLinkSchemes] open;
/// false when [uri] didn't.
Future<bool> openMailLink(Uri uri) async {
  if (!isMailLinkAllowed(uri)) return false;
  if (uri.scheme.toLowerCase() == 'mailto') {
    await openMailtoLink(uri);
  } else {
    await openExternalLink(uri);
  }
  return true;
}

/// Opens a saved file with the app the system uses for it. Tests replace
/// it to see what would open.
Future<void> Function(String path) openLocalFile = (path) async {
  // Phones can't open a bare file path from another app.
  if (await PhoneFiles.open(path)) return;
  await launchUrl(Uri.file(path));
};
