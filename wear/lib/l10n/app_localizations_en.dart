// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Piuma Mail';

  @override
  String get inbox => 'Inbox';

  @override
  String newCount(int count) {
    return '$count new';
  }

  @override
  String get nothingHere => 'Nothing new in the inbox';

  @override
  String get openOnPhone => 'Open Piuma Mail on your phone, near the watch';

  @override
  String get reaching => 'Reaching your phone…';

  @override
  String get restOnPhone => 'The rest is on your phone';

  @override
  String get archive => 'Archive';

  @override
  String get snooze => 'Snooze';

  @override
  String get reply => 'Reply';

  @override
  String replyTo(String name) {
    return 'Reply to $name';
  }

  @override
  String get speakOrType => 'Speak or type';

  @override
  String get yourTemplates => 'Your templates';

  @override
  String get snoozeUntil => 'Snooze until…';

  @override
  String get snoozeEvening => 'This evening';

  @override
  String get snoozeMorning => 'Tomorrow morning';

  @override
  String get snoozeWeekend => 'Weekend';

  @override
  String get snoozeNextWeek => 'Next week';

  @override
  String get archived => 'Archived';

  @override
  String get snoozed => 'Snoozed';

  @override
  String get sent => 'Sent';

  @override
  String get undo => 'Undo';
}
