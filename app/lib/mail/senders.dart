import 'package:flutter/painting.dart' show Color;

import 'mail_source.dart';

/// An address mail can go from: an account's own, or one of its aliases.
class Sender {
  const Sender(this.account, this.email);
  final MailAccount account;
  final String email;

  bool same(int accountId, String? email) =>
      account.id == accountId &&
      this.email.toLowerCase() == (email ?? account.email).toLowerCase();
}

/// The From list's sections, as on `ComposeFrom`: each group with its
/// addresses, then each account's addresses that are in no group.
class SenderSection {
  const SenderSection(this.name, this.color, this.senders);
  final String name;
  final Color color;
  final List<Sender> senders;
}

List<SenderSection> senderSections(
  List<MailAccount> accounts,
  Map<int, List<String>> aliases,
  List<MailGroup> groups,
) {
  final byId = {for (final a in accounts) a.id: a};
  final grouped = <String>{};
  final sections = <SenderSection>[];
  for (final g in groups) {
    final senders = [
      for (final a in g.addresses)
        if (byId[a.accountId] case final account?) Sender(account, a.email),
    ];
    grouped.addAll(senders.map((s) => s.email.toLowerCase()));
    if (senders.isNotEmpty) {
      sections.add(SenderSection(g.name, g.color, senders));
    }
  }
  for (final a in accounts) {
    final senders = [
      for (final e in [a.email, ...?aliases[a.id]])
        if (!grouped.contains(e.toLowerCase())) Sender(a, e),
    ];
    if (senders.isNotEmpty) {
      sections.add(SenderSection(a.name, a.color, senders));
    }
  }
  return sections;
}

/// The group an address is in, if any.
MailGroup? groupOf(List<MailGroup> groups, String email) {
  final e = email.toLowerCase();
  for (final g in groups) {
    if (g.addresses.any((a) => a.email.toLowerCase() == e)) return g;
  }
  return null;
}
