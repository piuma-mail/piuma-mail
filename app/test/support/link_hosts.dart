import 'package:piuma_mail/widgets/links.dart';

/// [linkHostAscii] for tests without the engine's library: lowercase,
/// letters outside ASCII in punycode, no UTS #46 mapping. Null for what a
/// browser never opens (an `@`, a `%`, a space), as the engine refuses it.
/// links_test checks the engine's own UTS #46 when the library is built.
String? plainLinkHostAscii(String host) {
  if (host.isEmpty || host.contains(RegExp(r'[@%\s]'))) return null;
  final lower = host.toLowerCase();
  return punycodeHost(lower) ?? lower;
}
