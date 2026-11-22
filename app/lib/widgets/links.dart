import 'package:url_launcher/url_launcher.dart';

import '../engine/api/links.dart' as engine;
import '../mail/phone_files.dart';

/// [host] (percent-decoding undone, any case) in the ASCII form the
/// browser goes to: UTS #46 mapping (full-width letters, the dots `。` `．`
/// `｡`, case, characters it drops), then punycode. The engine does it
/// with the Rust `idna` crate, the same parsing its suspicious-link check
/// uses, so the app shows and compares the host the engine checked. Null
/// when it isn't a host a browser would open (an `@`, a label UTS #46
/// refuses). Tests replace it.
String? Function(String host) linkHostAscii = (host) =>
    engine.linkHostAscii(host: host);

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
/// destination. So is one whose host hides an `@` in percent-encoding
/// (`https://bank.example%40evil.example/`): it reads the same way, and
/// no browser goes to such a host. An IPv6 address (`http://[::1]:8080/`)
/// is a host like any other.
bool isMailLinkAllowed(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (!mailLinkSchemes.contains(scheme)) return false;
  if (scheme == 'mailto') return uri.path.trim().isNotEmpty;
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
  // Browsers decode a host's percent-encoding once and refuse what is
  // left with an `@` or a `%` in it.
  final decoded = _decodeHost(uri.host);
  return !decoded.contains('@') && !decoded.contains('%');
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
///
/// A host is compared in the ASCII form browsers hand back, after UTS #46
/// ([linkHostAscii]): `bücher.de` and `BÜCHER.de` are both
/// `xn--bcher-kva.de`, `example。com` is `example.com`. A link whose host
/// doesn't make a host once decoded (an `@` in percent-encoding) is only
/// lowercased, its letters outside ASCII in punycode.
String normalizeLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || !uri.hasScheme) return link.trim();
  // An IPv6 address is left in the form [Uri] wrote it.
  final host = uri.host.contains(':')
      ? uri.host.toLowerCase()
      : _asciiHost(_decodeHost(uri.host));
  try {
    var out = uri.replace(scheme: uri.scheme.toLowerCase(), host: host);
    if ((out.scheme == 'http' || out.scheme == 'https') && out.path.isEmpty) {
      out = out.replace(path: '/');
    }
    return out.normalizePath().toString();
  } on FormatException {
    return link.trim();
  }
}

/// What a link's target is shown as, so its text can't hide where it goes.
class LinkParts {
  const LinkParts({
    required this.host,
    required this.registrable,
    required this.ascii,
    required this.rest,
  });

  /// The host as people read it (Unicode, also when the link wrote it in
  /// punycode).
  final String host;

  /// The part of [host] an organization registers: `bank.example` of
  /// `login.bank.example`.
  final String registrable;

  /// The host in ASCII (punycode, the form the browser goes to) when its
  /// Unicode form differs: letters outside ASCII can imitate others
  /// (`раураl.com`). Null otherwise.
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
    final to = _decodeHost(uri.path);
    final at = to.lastIndexOf('@');
    final (host, ascii) = _readableHost(at < 0 ? to : to.substring(at + 1));
    return LinkParts(
      host: host,
      registrable: registrableDomain(host),
      ascii: ascii,
      rest: to,
    );
  }
  if (uri.host.isEmpty) return null;
  // An IPv6 address is shown in its brackets, so its port reads apart
  // from it (`[::1]:8080`, not `::1:8080`).
  if (uri.host.contains(':')) {
    final host = '[${_decodeHost(uri.host).toLowerCase()}]';
    return LinkParts(
      host: host,
      registrable: host,
      ascii: null,
      rest: _rest(uri),
    );
  }
  final (host, ascii) = _readableHost(_decodeHost(uri.host));
  // A host hiding an `@` (`bank.example%40evil.example`): what follows the
  // `@` is the part to read, as with a user name before the host.
  final at = host.lastIndexOf('@');
  final named = at < 0 ? host : host.substring(at + 1);
  return LinkParts(
    host: host,
    registrable: _ipv4.hasMatch(named) ? named : registrableDomain(named),
    ascii: ascii,
    rest: _rest(uri),
  );
}

/// An IPv4 address, which has no registrable part to pick out.
final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

/// Everything of [uri] after its host: port, path, query, fragment.
String _rest(Uri uri) {
  final rest = StringBuffer()
    ..write(uri.hasPort ? ':${uri.port}' : '')
    ..write(uri.path)
    ..write(uri.hasQuery ? '?${uri.query}' : '')
    ..write(uri.hasFragment ? '#${uri.fragment}' : '');
  return rest.toString();
}

/// A host's percent-encoding undone, or the host as it is when that
/// doesn't read (a bad escape, or bytes that aren't UTF-8: `a%ff.example`).
/// A host left with its `%` never opens ([isMailLinkAllowed]).
String _decodeHost(String host) {
  try {
    return Uri.decodeComponent(host);
  } on ArgumentError {
    return host;
  } on FormatException {
    return host;
  }
}

/// [host] (decoded) in the ASCII form the browser goes to
/// ([linkHostAscii]); when UTS #46 refuses it, lowercased with its letters
/// outside ASCII in punycode.
String _asciiHost(String host) {
  if (linkHostAscii(host) case final ascii?) return ascii;
  // Lowercase after decoding: [Uri] lowercases only ASCII letters, so `Ü`
  // arrives as `%C3%9C`.
  final lower = host.toLowerCase();
  return punycodeHost(lower) ?? lower;
}

/// [host] (decoded) as people read it (Unicode) and its ASCII form when
/// the two differ, whichever of them the link wrote. Read after UTS #46
/// ([linkHostAscii]), so `ｅxample。com` shows as the `example.com` the
/// browser opens.
(String, String?) _readableHost(String host) {
  if (linkHostAscii(host) case final ascii?) {
    final unicode = unicodeHost(ascii);
    return unicode == ascii ? (ascii, null) : (unicode, ascii);
  }
  host = host.toLowerCase();
  if (punycodeHost(host) case final ascii?) return (host, ascii);
  final unicode = unicodeHost(host);
  return unicode == host ? (host, null) : (unicode, host);
}

/// [host] with its punycode (`xn--`) labels in Unicode; a label that
/// doesn't decode stays as it is.
String unicodeHost(String host) =>
    host.split('.').map((l) => _unpunycodeLabel(l) ?? l).join('.');

/// RFC 3492 decoding of an `xn--` label; null when it isn't one or
/// doesn't decode.
String? _unpunycodeLabel(String label) {
  if (!label.toLowerCase().startsWith('xn--')) return null;
  final input = label.substring(4).toLowerCase();
  // A DNS label is at most 63 characters.
  if (input.isEmpty || input.length > 59) return null;
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

  int? value(int c) {
    if (c >= 0x61 && c <= 0x7A) return c - 0x61;
    if (c >= 0x30 && c <= 0x39) return c - 0x30 + 26;
    return null;
  }

  final dash = input.lastIndexOf('-');
  final out = <int>[];
  if (dash > 0) {
    final basic = input.substring(0, dash).codeUnits;
    if (basic.any((c) => c >= 0x80)) return null;
    out.addAll(basic);
  }
  var pos = dash > 0 ? dash + 1 : 0;
  var n = 0x80, i = 0, bias = 72;
  while (pos < input.length) {
    final old = i;
    var w = 1;
    for (var k = base; ; k += base) {
      if (pos >= input.length) return null;
      final digit = value(input.codeUnitAt(pos++));
      if (digit == null) return null;
      i += digit * w;
      final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
      if (digit < t) break;
      w *= base - t;
      if (i > 0x10FFFF * 64) return null;
    }
    bias = adapt(i - old, out.length + 1, old == 0);
    n += i ~/ (out.length + 1);
    if (n > 0x10FFFF) return null;
    i %= out.length + 1;
    out.insert(i, n);
    i++;
  }
  // Only a label that is really punycode of letters outside ASCII.
  if (out.every((r) => r < 0x80)) return null;
  return String.fromCharCodes(out);
}

/// The registrable domain of [host]: its last two labels, or three under a
/// country's second level (`bank.co.uk`), as the engine reckons it. A
/// trailing dot (`bank.example.`, the same host to a browser) is kept, not
/// counted as a label.
String registrableDomain(String host) {
  if (host.length > 1 && host.endsWith('.')) {
    return '${registrableDomain(host.substring(0, host.length - 1))}.';
  }
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
