import 'package:flutter/foundation.dart';

/// One person on a line of a message: a name, which may be empty, and an
/// address.
@immutable
class MailPerson {
  const MailPerson(this.name, this.email, {this.you = false});

  final String name;
  final String email;

  /// One of the person's own addresses (the account's, or an alias).
  final bool you;

  /// The name, or the address when there is none.
  String get shown => name.trim().isEmpty ? email : name.trim();

  @override
  bool operator ==(Object other) =>
      other is MailPerson &&
      other.name == name &&
      other.email == email &&
      other.you == you;

  @override
  int get hashCode => Object.hash(name, email, you);

  /// As compose writes it: `a@b.c`, or `Name <a@b.c>` with the name
  /// quoted when it holds a character that would end it.
  String get address {
    final n = name.trim();
    if (n.isEmpty || n.toLowerCase() == email.toLowerCase()) return email;
    if (RegExp(r'[()<>\[\]:;@\\,."]').hasMatch(n)) {
      final quoted = n.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      return '"$quoted" <$email>';
    }
    return '$n <$email>';
  }

  @override
  String toString() => address;
}

/// Who a message went to, as the reader shows it, and who each answer goes
/// to, as compose writes addresses (`Name <a@b.c>`). The engine works it
/// out (`core/src/envelope.rs`): the person's own addresses and aliases are
/// left out of every answer, and repeats too.
@immutable
class MailEnvelope {
  const MailEnvelope({
    this.to = const [],
    this.cc = const [],
    this.bccYou = false,
    this.replyTo = const [],
    this.replyAllTo = const [],
    this.replyAllCc = const [],
    this.listPost,
    this.muted = false,
    this.replyAllReview = false,
  });

  final List<MailPerson> to;
  final List<MailPerson> cc;

  /// The person was on neither To nor Cc: a blind copy.
  final bool bccYou;

  /// Reply: the author, every Reply-To address.
  final List<String> replyTo;

  /// Reply all: everyone else on To and Cc, or the Mail-Followup-To the
  /// author asked for.
  final List<String> replyAllTo;
  final List<String> replyAllCc;

  /// Reply to list: the list's posting address, when it takes posts.
  final String? listPost;

  /// The conversation is muted.
  final bool muted;

  /// Reply all follows a Mail-Followup-To naming people the message shows
  /// nowhere else (`core/src/envelope.rs`, `followup_needs_review`): it
  /// opens compose, to be seen before it goes, and the quick reply box
  /// doesn't send it straight away.
  final bool replyAllReview;

  /// How many more people Reply all reaches than Reply: 0 when Reply all
  /// would write to the same people, and isn't worth offering. Offered
  /// nowhere for a blind copy, which answering everyone would give away.
  int get others {
    if (bccYou) return 0;
    final reply = {for (final a in replyTo) bareAddress(a).toLowerCase()};
    final all = {
      for (final a in [...replyAllTo, ...replyAllCc])
        bareAddress(a).toLowerCase(),
    };
    return all.difference(reply).length;
  }

  MailEnvelope withMuted(bool muted) => MailEnvelope(
    to: to,
    cc: cc,
    bccYou: bccYou,
    replyTo: replyTo,
    replyAllTo: replyAllTo,
    replyAllCc: replyAllCc,
    listPost: listPost,
    muted: muted,
    replyAllReview: replyAllReview,
  );
}

/// The address in `Name <a@b.c>`, or the text itself.
String bareAddress(String address) {
  final open = address.lastIndexOf('<');
  final close = address.lastIndexOf('>');
  if (open >= 0 && close > open) {
    return address.substring(open + 1, close).trim();
  }
  return address.trim();
}

/// The addresses typed in one field: split at commas, semicolons and
/// line breaks outside quotes and angle brackets, a name with a comma in
/// it kept whole (`Rossi, Mario <m@x.it>`: a piece with no address joins
/// the one after it on the same line). A line break always ends an
/// address, so a line that is not one stays on its own.
List<String> splitAddresses(String text) {
  // Pieces, each marked when a line break ends it.
  final pieces = <(String, bool)>[];
  final b = StringBuffer();
  var quoted = false, escaped = false;
  var angle = 0;
  for (final ch in text.split('')) {
    if (ch == '\n') {
      pieces.add((b.toString(), true));
      b.clear();
      quoted = escaped = false;
      angle = 0;
      continue;
    }
    if (escaped) {
      escaped = false;
    } else if (ch == r'\' && quoted) {
      escaped = true;
    } else if (ch == '"') {
      quoted = !quoted;
    } else if (!quoted && ch == '<') {
      angle++;
    } else if (!quoted && ch == '>' && angle > 0) {
      angle--;
    }
    if (!quoted && angle == 0 && (ch == ',' || ch == ';')) {
      pieces.add((b.toString(), false));
      b.clear();
    } else {
      b.write(ch);
    }
  }
  pieces.add((b.toString(), true));
  final out = <String>[];
  var pending = '';
  for (final (p, lineEnd) in pieces) {
    final joined = pending.isEmpty ? p.trim() : '$pending,${p.trimRight()}';
    if (joined.trim().isNotEmpty && (joined.contains('@') || lineEnd)) {
      out.add(joined.trim());
      pending = '';
    } else {
      pending = joined.trim().isEmpty ? '' : joined;
    }
  }
  return out;
}

/// A plausible address: something@domain.tld, no spaces, in `Name <…>`
/// or alone.
bool validAddress(String text) =>
    RegExp(r'^[^\s@<>",;]+@[^\s@<>",;]+\.[^\s@<>",;]+$')
        .hasMatch(bareAddress(text));

/// One header of a message, as View source lists them.
@immutable
class MailHeader {
  const MailHeader(this.name, this.value);
  final String name;
  final String value;
}
