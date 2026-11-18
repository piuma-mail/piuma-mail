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
///
/// A web address with a user name or password before its host
/// (`https://bank.example@evil.example/`) is refused: browsers go to the
/// host after the `@`, and the text before it is there to be read as the
/// destination.
bool isMailLinkAllowed(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (!mailLinkSchemes.contains(scheme)) return false;
  if (scheme == 'mailto') return uri.path.trim().isNotEmpty;
  return uri.host.isNotEmpty && uri.userInfo.isEmpty;
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

/// A link as the browser hands it back: scheme and host lowercase, an
/// empty path as `/`, dot segments resolved, percent-encoding the way
/// [Uri] writes it. An email's own `href` and the web view's `a.href` of
/// it compare equal once both go through here.
String normalizeLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || !uri.hasScheme) return link.trim();
  var out = uri.replace(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
  );
  if ((out.scheme == 'http' || out.scheme == 'https') && out.path.isEmpty) {
    out = out.replace(path: '/');
  }
  return out.normalizePath().toString();
}

/// What a link's target is shown as, so its text can't hide where it goes.
class LinkParts {
  const LinkParts({
    required this.host,
    required this.registrable,
    required this.ascii,
    required this.rest,
  });

  /// The host as people read it (Unicode).
  final String host;

  /// The part of [host] an organization registers: `bank.example` of
  /// `login.bank.example`.
  final String registrable;

  /// The host in ASCII (punycode) when it has letters outside ASCII,
  /// which can imitate others (`раураl.com`); null otherwise.
  final String? ascii;

  /// Everything after the host: path, query, fragment (or a mailto's
  /// address).
  final String rest;
}

/// [url] split for showing ([LinkParts]); null when it isn't a link.
LinkParts? describeLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() == 'mailto') {
    final to = Uri.decodeComponent(uri.path);
    final at = to.lastIndexOf('@');
    final host = at < 0 ? to : to.substring(at + 1).toLowerCase();
    return LinkParts(
      host: host,
      registrable: registrableDomain(host),
      ascii: punycodeHost(host),
      rest: to,
    );
  }
  if (uri.host.isEmpty) return null;
  final host = Uri.decodeComponent(uri.host).toLowerCase();
  final rest = StringBuffer()
    ..write(uri.hasPort ? ':${uri.port}' : '')
    ..write(uri.path)
    ..write(uri.hasQuery ? '?${uri.query}' : '')
    ..write(uri.hasFragment ? '#${uri.fragment}' : '');
  return LinkParts(
    host: host,
    registrable: registrableDomain(host),
    ascii: punycodeHost(host),
    rest: rest.toString(),
  );
}

/// The registrable domain of [host]: its last two labels, or three under a
/// country's second level (`bank.co.uk`), as the engine reckons it.
String registrableDomain(String host) {
  final labels = host.split('.');
  final n = labels.length;
  if (n < 3) return host;
  final second = labels[n - 2];
  final take =
      labels[n - 1].length == 2 &&
          const {'co', 'com', 'net', 'org', 'gov', 'ac', 'edu'}.contains(second)
      ? 3
      : 2;
  return labels.sublist(n - take).join('.');
}

/// [text] cut in the middle to at most [max] characters, keeping its
/// start and its end, which a link's tricks hide behind padding.
String elideMiddle(String text, int max) {
  final runes = text.runes.toList();
  if (runes.length <= max) return text;
  final keep = max - 1;
  final head = (keep * 0.4).ceil();
  final tail = keep - head;
  return '${String.fromCharCodes(runes.sublist(0, head))}…'
      '${String.fromCharCodes(runes.sublist(runes.length - tail))}';
}

/// [host] in ASCII (RFC 3492 punycode, `xn--` labels), or null when it is
/// ASCII already.
String? punycodeHost(String host) {
  if (host.runes.every((r) => r < 0x80)) return null;
  return host.split('.').map(_punycodeLabel).join('.');
}

String _punycodeLabel(String label) {
  final input = label.runes.toList();
  if (input.every((r) => r < 0x80)) return label;
  const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
  int adapt(int delta, int points, bool first) {
    delta = first ? delta ~/ damp : delta ~/ 2;
    delta += delta ~/ points;
    var k = 0;
    while (delta > ((base - tMin) * tMax) ~/ 2) {
      delta ~/= base - tMin;
      k += base;
    }
    return k + (base - tMin + 1) * delta ~/ (delta + skew);
  }

  String digit(int d) => String.fromCharCode(d < 26 ? 0x61 + d : 0x30 + d - 26);
  final out = StringBuffer();
  final basic = input.where((r) => r < 0x80).toList();
  out.write(String.fromCharCodes(basic));
  var h = basic.length;
  final b = basic.length;
  if (b > 0) out.write('-');
  var n = 0x80, delta = 0, bias = 72;
  while (h < input.length) {
    final m = input.where((r) => r >= n).reduce((a, c) => a < c ? a : c);
    delta += (m - n) * (h + 1);
    n = m;
    for (final c in input) {
      if (c < n) delta++;
      if (c == n) {
        var q = delta;
        for (var k = base; ; k += base) {
          final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
          if (q < t) break;
          out.write(digit(t + (q - t) % (base - t)));
          q = (q - t) ~/ (base - t);
        }
        out.write(digit(q));
        bias = adapt(delta, h + 1, h == b);
        delta = 0;
        h++;
      }
    }
    delta++;
    n++;
  }
  return 'xn--$out';
}
