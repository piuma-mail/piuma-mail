// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'Piuma Mail';

  @override
  String get inbox => 'Boîte de réception';

  @override
  String newCount(int count) {
    return '$count nouveaux';
  }

  @override
  String get nothingHere => 'Rien de nouveau';

  @override
  String get openOnPhone =>
      'Ouvrez Piuma Mail sur le téléphone, près de la montre';

  @override
  String get reaching => 'Recherche du téléphone…';

  @override
  String get restOnPhone => 'La suite est sur le téléphone';

  @override
  String get archive => 'Archiver';

  @override
  String get snooze => 'Reporter';

  @override
  String get reply => 'Répondre';

  @override
  String replyTo(String name) {
    return 'Répondre à $name';
  }

  @override
  String get speakOrType => 'Dictez ou écrivez';

  @override
  String get yourTemplates => 'Vos modèles';

  @override
  String get snoozeUntil => 'Reporter jusqu’à…';

  @override
  String get snoozeEvening => 'Ce soir';

  @override
  String get snoozeMorning => 'Demain matin';

  @override
  String get snoozeWeekend => 'Ce week-end';

  @override
  String get snoozeNextWeek => 'La semaine prochaine';

  @override
  String get archived => 'Archivé';

  @override
  String get snoozed => 'Reporté';

  @override
  String get sent => 'Envoyé';

  @override
  String get undo => 'Annuler';

  @override
  String get replyAll => 'Répondre à tous';

  @override
  String replyToAll(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count autres personnes',
      one: '1 autre personne',
    );
    return 'Répondre à $name et $_temp0';
  }

  @override
  String get lockedOnPhone =>
      'Piuma est verrouillé sur votre téléphone. Déverrouillez-le là pour voir vos e-mails ici.';
}
