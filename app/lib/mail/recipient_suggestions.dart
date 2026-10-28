import 'mail_source.dart';

/// Include the device's own addresses, which the engine's people query omits.
/// Preserve its recency ranking and deduplicate case-insensitively.
List<Contact> recipientSuggestions(
  String typed,
  List<Contact> people,
  List<MailAccount> accounts,
  Map<int, List<String>> aliases, {
  int limit = 6,
  List<FrequentContact> frequent = const [],
}) {
  final query = typed.trim().toLowerCase();
  if (query.isEmpty || limit <= 0) return const [];
  final own = {
    for (final account in accounts)
      for (final email in [account.email, ...?aliases[account.id]])
        email.trim().toLowerCase(): account,
  };
  final colors = {for (final account in accounts) account.id: account.color};
  final associations = {
    for (final person in frequent)
      person.email.trim().toLowerCase(): colors[person.accountId],
  };
  final found = <String, Contact>{};
  for (final person in people) {
    final key = person.email.trim().toLowerCase();
    found.putIfAbsent(
      key,
      () => Contact(
        name: person.name,
        email: person.email,
        messages: person.messages,
        writtenTo: person.writtenTo,
        accountColor: own[key]?.color ?? associations[key],
      ),
    );
  }
  for (final entry in own.entries) {
    final account = entry.value;
    if (entry.key.startsWith(query) ||
        account.fromLabel
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .any((word) => word.startsWith(query))) {
      found.putIfAbsent(
        entry.key,
        () => Contact(
          name: account.fromLabel,
          email: entry.key,
          accountColor: account.color,
        ),
      );
    }
  }
  return found.values.take(limit).toList();
}
