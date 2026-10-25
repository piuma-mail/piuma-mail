import 'package:flutter/painting.dart' show Color;

/// Where a connected calendar comes from.
enum CalendarKind { calDav, ics }

/// One calendar of a connected source.
class MailCalendar {
  const MailCalendar({
    required this.id,
    required this.name,
    this.color,
    this.readOnly = false,
    this.availability = true,
  });

  final int id;
  final String name;

  /// The color its server keeps, if any.
  final Color? color;

  /// It can be read but takes no events.
  final bool readOnly;

  /// Its events count when telling whether you are free.
  final bool availability;

  MailCalendar copyWith({bool? availability}) => MailCalendar(
    id: id,
    name: name,
    color: color,
    readOnly: readOnly,
    availability: availability ?? this.availability,
  );
}

/// A connected CalDAV account or .ics feed (`Calendars`).
class CalendarSource {
  const CalendarSource({
    required this.id,
    required this.kind,
    required this.name,
    required this.detail,
    this.accountId,
    this.calendars = const [],
    this.updatesEvery,
  });

  final int id;
  final CalendarKind kind;

  /// "iCloud", "Fastmail", a feed's own name.
  final String name;

  /// The user name, or the feed's address.
  final String detail;

  /// The email account it shares a password with.
  final int? accountId;
  final List<MailCalendar> calendars;

  /// For a feed, how often it is read again.
  final Duration? updatesEvery;

  CalendarSource copyWith({List<MailCalendar>? calendars}) => CalendarSource(
    id: id,
    kind: kind,
    name: name,
    detail: detail,
    accountId: accountId,
    calendars: calendars ?? this.calendars,
    updatesEvery: updatesEvery,
  );
}

/// An email account whose provider has a calendar too.
class CalendarSuggestion {
  const CalendarSuggestion({required this.accountId, required this.email});
  final int accountId;
  final String email;
}

class CalendarPrefs {
  const CalendarPrefs({
    this.defaultCalendar,
    this.checkConflicts = true,
    this.findDates = true,
  });

  /// Where accepted invites go; null when no calendar takes events.
  final int? defaultCalendar;

  /// Invites show when you are already busy.
  final bool checkConflicts;

  /// Days with a time in a message are offered for a calendar.
  final bool findDates;

  CalendarPrefs copyWith({
    int? defaultCalendar,
    bool? checkConflicts,
    bool? findDates,
  }) => CalendarPrefs(
    defaultCalendar: defaultCalendar ?? this.defaultCalendar,
    checkConflicts: checkConflicts ?? this.checkConflicts,
    findDates: findDates ?? this.findDates,
  );
}

/// Something in your calendars that makes you busy.
class BusyTime {
  const BusyTime({
    this.uid = '',
    required this.summary,
    required this.start,
    required this.end,
    this.allDay = false,
    this.calendar = '',
    this.color,
  });

  /// The event's UID: an invite already accepted is not a conflict with
  /// itself.
  final String uid;
  final String summary;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String calendar;
  final Color? color;

  bool overlaps(DateTime from, DateTime to) =>
      start.isBefore(to) && end.isAfter(from);
}

/// What answering an invite did.
class InviteResult {
  const InviteResult({this.queued = false, this.addedTo});

  /// The reply waits in the outbox until the server can be reached.
  final bool queued;

  /// The calendar the event went in, if any.
  final String? addedTo;
}
