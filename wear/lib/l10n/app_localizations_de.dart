// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appName => 'Piuma Mail';

  @override
  String get inbox => 'Posteingang';

  @override
  String newCount(int count) {
    return '$count neu';
  }

  @override
  String get nothingHere => 'Nichts Neues im Posteingang';

  @override
  String get openOnPhone => 'Öffne Piuma Mail auf dem Telefon, nahe der Uhr';

  @override
  String get reaching => 'Suche das Telefon…';

  @override
  String get restOnPhone => 'Der Rest ist auf dem Telefon';

  @override
  String get archive => 'Archivieren';

  @override
  String get snooze => 'Zurückstellen';

  @override
  String get reply => 'Antworten';

  @override
  String replyTo(String name) {
    return 'Antworten an $name';
  }

  @override
  String get speakOrType => 'Sprechen oder tippen';

  @override
  String get yourTemplates => 'Deine Vorlagen';

  @override
  String get snoozeUntil => 'Zurückstellen bis…';

  @override
  String get snoozeEvening => 'Heute Abend';

  @override
  String get snoozeMorning => 'Morgen früh';

  @override
  String get snoozeWeekend => 'Am Wochenende';

  @override
  String get snoozeNextWeek => 'Nächste Woche';

  @override
  String get archived => 'Archiviert';

  @override
  String get snoozed => 'Zurückgestellt';

  @override
  String get sent => 'Gesendet';

  @override
  String get undo => 'Rückgängig';
}
