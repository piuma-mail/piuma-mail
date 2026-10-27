import 'dart:convert';

import 'package:flutter/widgets.dart';

/// The inbox as the phone sends it (`app/rust/src/watch.rs`).
class Summary {
  const Summary({
    required this.at,
    required this.accounts,
    required this.rows,
    required this.templates,
  });

  /// When the phone made it, in Unix seconds.
  final int at;
  final List<WatchAccount> accounts;
  final List<WatchRow> rows;
  final List<WatchTemplate> templates;

  /// How many conversations wait unread, in every account.
  int get unread => accounts.fold(0, (n, a) => n + a.unread);

  WatchAccount? account(int id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// The summary in [json], or null when it isn't one.
  static Summary? parse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return Summary(
        at: (m['at'] as num).toInt(),
        accounts: [
          for (final a in m['accounts'] as List<dynamic>)
            WatchAccount.fromJson(a as Map<String, dynamic>),
        ],
        rows: [
          for (final r in m['rows'] as List<dynamic>)
            WatchRow.fromJson(r as Map<String, dynamic>),
        ],
        templates: [
          for (final t in m['templates'] as List<dynamic>)
            WatchTemplate.fromJson(t as Map<String, dynamic>),
        ],
      );
    } on Object {
      return null;
    }
  }

  /// The same summary with [payload]'s row gone: what the watch shows
  /// once it archived or snoozed it, before the phone says so.
  Summary without(String payload) => Summary(
    at: at,
    accounts: accounts,
    rows: [
      for (final r in rows)
        if (r.payload != payload) r,
    ],
    templates: templates,
  );
}

class WatchAccount {
  const WatchAccount({
    required this.id,
    required this.name,
    required this.color,
    required this.unread,
  });

  factory WatchAccount.fromJson(Map<String, dynamic> m) => WatchAccount(
    id: (m['id'] as num).toInt(),
    name: m['name'] as String,
    color: _color(m['color'] as String),
    unread: (m['unread'] as num).toInt(),
  );

  final int id;
  final String name;
  final Color color;
  final int unread;
}

class WatchRow {
  const WatchRow({
    required this.payload,
    required this.account,
    required this.sender,
    required this.subject,
    required this.preview,
    required this.at,
    required this.seen,
    required this.messages,
  });

  factory WatchRow.fromJson(Map<String, dynamic> m) => WatchRow(
    payload: m['payload'] as String,
    account: (m['account'] as num).toInt(),
    sender: m['sender'] as String,
    subject: m['subject'] as String,
    preview: m['preview'] as String,
    at: (m['at'] as num).toInt(),
    seen: m['seen'] as bool,
    messages: (m['messages'] as num).toInt(),
  );

  /// "account\nmailbox\nuid": what the phone acts on.
  final String payload;
  final int account;
  final String sender;
  final String subject;
  final String preview;

  /// Unix seconds.
  final int at;
  final bool seen;
  final int messages;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(at * 1000);
}

/// One of the person's templates (Settings › Templates), as a quick reply.
class WatchTemplate {
  const WatchTemplate({required this.name, required this.body});

  factory WatchTemplate.fromJson(Map<String, dynamic> m) =>
      WatchTemplate(name: m['name'] as String, body: m['body'] as String);

  final String name;
  final String body;

  /// What the chip says: the body when it is short, else the name.
  String get label {
    final b = body.trim();
    return b.length <= 28 && !b.contains('\n') ? b : name;
  }
}

/// "#RRGGBB" as a color; grey when it isn't one.
Color _color(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return v == null ? const Color(0xFF8A8D93) : Color(0xFF000000 | v);
}

/// The watch's clock; tests pin it so the screens draw the same times.
DateTime Function() watchNow = DateTime.now;

/// The times of `FeatureSnooze`, as on the phone (`app/lib/inbox/snooze.dart`).
enum SnoozeChoice { evening, tomorrow, weekend, nextWeek }

/// When [choice] is, seen from [now]: this evening at 18:00, tomorrow at
/// 8:00, Saturday at 9:00 and Monday at 8:00, always ahead.
DateTime snoozeTime(SnoozeChoice choice, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime next(int weekday, int hour) {
    var days = (weekday - today.weekday) % 7;
    if (days == 0) days = 7;
    return DateTime(today.year, today.month, today.day + days, hour);
  }

  return switch (choice) {
    SnoozeChoice.evening => DateTime(today.year, today.month, today.day, 18),
    SnoozeChoice.tomorrow => DateTime(
      today.year,
      today.month,
      today.day + 1,
      8,
    ),
    SnoozeChoice.weekend => next(DateTime.saturday, 9),
    SnoozeChoice.nextWeek => next(DateTime.monday, 8),
  };
}

/// The choices that make sense at [now]: "This evening" goes once it is
/// less than an hour away.
List<SnoozeChoice> snoozeChoices(DateTime now) => [
  for (final c in SnoozeChoice.values)
    if (c != SnoozeChoice.evening || now.hour < 17) c,
];
