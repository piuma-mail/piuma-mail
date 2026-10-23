// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'Piuma Mail';

  @override
  String get inbox => 'Bandeja de entrada';

  @override
  String newCount(int count) {
    return '$count nuevos';
  }

  @override
  String get nothingHere => 'Nada nuevo en la bandeja';

  @override
  String get openOnPhone => 'Abre Piuma Mail en el teléfono, cerca del reloj';

  @override
  String get reaching => 'Buscando el teléfono…';

  @override
  String get restOnPhone => 'El resto está en el teléfono';

  @override
  String get archive => 'Archivar';

  @override
  String get snooze => 'Posponer';

  @override
  String get reply => 'Responder';

  @override
  String replyTo(String name) {
    return 'Responder a $name';
  }

  @override
  String get speakOrType => 'Habla o escribe';

  @override
  String get yourTemplates => 'Tus plantillas';

  @override
  String get snoozeUntil => 'Posponer hasta…';

  @override
  String get snoozeEvening => 'Esta tarde';

  @override
  String get snoozeMorning => 'Mañana por la mañana';

  @override
  String get snoozeWeekend => 'Fin de semana';

  @override
  String get snoozeNextWeek => 'La semana que viene';

  @override
  String get archived => 'Archivado';

  @override
  String get snoozed => 'Pospuesto';

  @override
  String get sent => 'Enviado';

  @override
  String get undo => 'Deshacer';
}
