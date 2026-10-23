// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appName => 'Piuma Mail';

  @override
  String get inbox => 'Inbox';

  @override
  String newCount(int count) {
    return '$count nuove';
  }

  @override
  String get nothingHere => 'Niente di nuovo nella inbox';

  @override
  String get openOnPhone =>
      'Apri Piuma Mail sul telefono, vicino all\'orologio';

  @override
  String get reaching => 'Cerco il telefono…';

  @override
  String get restOnPhone => 'Il resto è sul telefono';

  @override
  String get archive => 'Archivia';

  @override
  String get snooze => 'Posticipa';

  @override
  String get reply => 'Rispondi';

  @override
  String replyTo(String name) {
    return 'Rispondi a $name';
  }

  @override
  String get speakOrType => 'Parla o scrivi';

  @override
  String get yourTemplates => 'I tuoi modelli';

  @override
  String get snoozeUntil => 'Posticipa a…';

  @override
  String get snoozeEvening => 'Stasera';

  @override
  String get snoozeMorning => 'Domani mattina';

  @override
  String get snoozeWeekend => 'Weekend';

  @override
  String get snoozeNextWeek => 'Settimana prossima';

  @override
  String get archived => 'Archiviata';

  @override
  String get snoozed => 'Posticipata';

  @override
  String get sent => 'Inviata';

  @override
  String get undo => 'Annulla';
}
