import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// A period of the inbox with its header, e.g. "Today" with 12 messages.
class InboxSection {
  const InboxSection(this.label, this.count);
  final String label;
  final int count;
}

/// The periods the inbox is split into, newest first, as descending edges.
/// Today, yesterday, the rest of this week, the rest of this month, then
/// one per month for two years, then everything older.
class SectionPlan {
  SectionPlan(this.now, this.l, String locale) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final week = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final month = DateTime(now.year, now.month);
    final monthName = DateFormat.yMMMM(locale);

    void add(DateTime start, String label) {
      // Edges never go back up: an empty period is just skipped later.
      final last = _starts.isEmpty ? _far : _starts.last;
      _starts.add(start.isBefore(last) ? start : last);
      labels.add(label);
    }

    add(today, l.sectionToday);
    add(yesterday, l.sectionYesterday);
    add(week, l.sectionThisWeek);
    add(month, l.sectionThisMonth);
    for (var i = 1; i <= 24; i++) {
      final start = DateTime(now.year, now.month - i);
      add(start, monthName.format(start));
    }
    add(DateTime.fromMillisecondsSinceEpoch(0), l.sectionOlder);
  }

  final DateTime now;
  final AppLocalizations l;
  final labels = <String>[];
  final _starts = <DateTime>[];

  static final _far = DateTime(9999);

  /// Edges for [MailSource.countsBetween]: one more than [labels].
  List<DateTime> get edges => [_far, ..._starts];

  List<InboxSection> sections(List<int> counts) => [
    for (var i = 0; i < labels.length; i++)
      if (counts[i] > 0) InboxSection(labels[i], counts[i]),
  ];
}

/// The time shown on a row: 09:42 today and yesterday, the weekday this
/// week, the date before.
String rowTime(DateTime t, DateTime now, String locale) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days <= 1) return DateFormat.Hm(locale).format(t);
  if (days < 7) return DateFormat.E(locale).format(t);
  if (t.year == now.year) return DateFormat.MMMd(locale).format(t);
  return DateFormat.yMMMd(locale).format(t);
}
