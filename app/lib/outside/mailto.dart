import 'dart:convert';

/// A `mailto:` link (RFC 6068), read safely: what another app, a web page
/// or an email asks Piuma to write.
///
/// Everything in it is untrusted. Only the fields a message is written
/// with are kept (to, cc, bcc, subject, body, In-Reply-To); any other
/// header (From, Reply-To, Sender, `attach`, …) is ignored, so a link can
/// neither pick the sender nor attach a file. Line breaks never reach a
/// header, and every part has a length cap.
class MailtoLink {
  const MailtoLink({
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = '',
    this.inReplyTo,
  });

  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String body;

  /// The Message-ID being answered, with its angle brackets.
  final String? inReplyTo;

  /// Longest link read at all.
  static const maxLength = 256 * 1024;

  /// Most addresses kept over to, cc and bcc together.
  static const maxAddresses = 100;

  /// Longest address kept (RFC 5321: 254, with some room for a name).
  static const maxAddressLength = 320;

  /// Longest subject kept: one header line.
  static const maxSubject = 998;

  /// Longest body kept, in characters.
  static const maxBody = 100 * 1000;

  bool get isEmpty =>
      to.isEmpty &&
      cc.isEmpty &&
      bcc.isEmpty &&
      subject.isEmpty &&
      body.isEmpty &&
      inReplyTo == null;

  /// Reads [link]; null when it isn't a `mailto:` link or is too long.
  static MailtoLink? parse(String link) {
    if (link.length > maxLength) return null;
    final trimmed = link.trim();
    if (!trimmed.toLowerCase().startsWith('mailto:')) return null;
    final rest = trimmed.substring('mailto:'.length);
    // A fragment is no part of a mailto: link.
    final hash = rest.indexOf('#');
    final noFragment = hash < 0 ? rest : rest.substring(0, hash);
    final q = noFragment.indexOf('?');
    final path = q < 0 ? noFragment : noFragment.substring(0, q);
    final query = q < 0 ? '' : noFragment.substring(q + 1);

    final to = <String>[], cc = <String>[], bcc = <String>[];
    var count = 0;
    void addAll(List<String> into, String encoded) {
      // Commas split addresses before decoding: an encoded comma (%2C)
      // stays inside one, where it can only be part of a name.
      for (final part in encoded.split(',')) {
        if (count >= maxAddresses) return;
        final address = _address(_decode(part));
        if (address == null) continue;
        final known = [...to, ...cc, ...bcc].map(_bare);
        if (known.contains(_bare(address))) continue;
        into.add(address);
        count++;
      }
    }

    addAll(to, path);
    String? subject, body, inReplyTo;
    for (final field in query.split('&')) {
      if (field.isEmpty) continue;
      final eq = field.indexOf('=');
      final name = _decode(eq < 0 ? field : field.substring(0, eq))
          .trim()
          .toLowerCase();
      final value = eq < 0 ? '' : field.substring(eq + 1);
      switch (name) {
        case 'to':
          addAll(to, value);
        case 'cc':
          addAll(cc, value);
        case 'bcc':
          addAll(bcc, value);
        // The first one counts: a second can't replace what was shown.
        case 'subject':
          subject ??= _line(_decode(value), maxSubject);
        case 'body':
          body ??= _body(_decode(value));
        case 'in-reply-to':
          inReplyTo ??= _messageId(_decode(value));
        default:
        // Any other header is not the link's to set.
      }
    }
    return MailtoLink(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject ?? '',
      body: body ?? '',
      inReplyTo: inReplyTo,
    );
  }

  /// A subject from elsewhere (an Android share), cleaned like a link's.
  static String cleanSubject(String text) => _line(text, maxSubject);

  /// A body from elsewhere, cleaned like a link's.
  static String cleanBody(String text) => _body(text);

  /// An address from elsewhere, checked like a link's; null when it isn't
  /// one.
  static String? cleanAddress(String text) => _address(text);

  /// Percent-decodes [text] as UTF-8; a broken escape stays as written and
  /// invalid UTF-8 becomes U+FFFD. `+` is a plus (RFC 6068), not a space.
  static String _decode(String text) {
    if (!text.contains('%')) return text;
    final out = StringBuffer();
    final bytes = <int>[];
    void flush() {
      if (bytes.isEmpty) return;
      out.write(utf8.decode(bytes, allowMalformed: true));
      bytes.clear();
    }

    var i = 0;
    while (i < text.length) {
      if (text.codeUnitAt(i) == 0x25 &&
          i + 2 < text.length &&
          _isHex(text, i + 1) &&
          _isHex(text, i + 2)) {
        bytes.add(int.parse(text.substring(i + 1, i + 3), radix: 16));
        i += 3;
        continue;
      }
      flush();
      out.writeCharCode(text.codeUnitAt(i));
      i++;
    }
    flush();
    return out.toString();
  }

  static bool _isHex(String s, int i) {
    final c = s.codeUnitAt(i) | 0x20;
    return (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66);
  }

  /// Characters never kept: controls other than tab and new line, and the
  /// ones that reorder text on screen (a name that reads backwards).
  static final _hidden = RegExp(
    '[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F'
    '\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );

  /// [text] on one line, tidy, at most [max] characters.
  static String _line(String text, int max) {
    final one = text
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(_hidden, '')
        .trim();
    return one.length <= max ? one : one.substring(0, max);
  }

  static String _body(String text) {
    final body = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_hidden, '');
    return body.length <= maxBody ? body : body.substring(0, maxBody);
  }

  /// One address, as `a@b.c` or `Name <a@b.c>`; null for anything else.
  static String? _address(String text) {
    final one = _line(text, maxAddressLength + 1);
    if (one.isEmpty || one.length > maxAddressLength) return null;
    final angled = RegExp(r'^(.*)<([^<>]+)>$').firstMatch(one);
    final email = (angled?.group(2) ?? one).trim();
    if (!_email.hasMatch(email)) return null;
    final name = (angled?.group(1) ?? '').trim().replaceAll('"', '');
    // A name can't carry another address (`a@b.c <x@y.z>` hides x).
    if (name.contains('@') || name.contains('<') || name.contains('>')) {
      return email;
    }
    return name.isEmpty ? email : '$name <$email>';
  }

  /// A plain address: one @, something on each side, no spaces, quotes,
  /// brackets or separators that would make it two.
  static final _email = RegExp(
    r'''^[^\s@<>()\[\]\\,;:"']+@[^\s@<>()\[\]\\,;:"']+\.[^\s@<>()\[\]\\,;:"'.]+$''',
  );

  /// The address alone, lower case: what makes two the same.
  static String bare(String address) => _bare(address);

  static String _bare(String address) {
    final angled = RegExp(r'<([^<>]+)>$').firstMatch(address);
    return (angled?.group(1) ?? address).toLowerCase();
  }

  /// A Message-ID: `<left@right>`; null for anything else.
  static String? _messageId(String text) {
    final one = _line(text, maxSubject);
    final id = one.startsWith('<') ? one : '<$one>';
    return RegExp(r'^<[^\s<>@]+@[^\s<>@]+>$').hasMatch(id) ? id : null;
  }
}
