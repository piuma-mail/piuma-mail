import 'package:flutter/widgets.dart';

/// Settings › Appearance: the theme.
enum ThemeChoice { light, dark, automatic }

/// Settings › Appearance, as on the `Settings` board: the theme, how
/// tall the inbox rows are, how many lines of preview they show, and
/// the language Translate writes in, and the app's own language.
@immutable
class Appearance {
  const Appearance({
    this.theme = ThemeChoice.automatic,
    this.compact = false,
    this.previewLines = 2,
    this.translateInto,
    this.language,
  });

  final ThemeChoice theme;

  /// Rows with less room above and below.
  final bool compact;

  /// 1 or 2.
  final int previewLines;

  /// The language Translate writes in ("it"); null follows the app's.
  final String? translateInto;

  /// The app's language, one of [appLanguages] ("it"); null follows the
  /// device's.
  final String? language;

  Appearance copyWith({
    ThemeChoice? theme,
    bool? compact,
    int? previewLines,
    String? Function()? translateInto,
    String? Function()? language,
  }) => Appearance(
    theme: theme ?? this.theme,
    compact: compact ?? this.compact,
    previewLines: previewLines ?? this.previewLines,
    translateInto: translateInto == null ? this.translateInto : translateInto(),
    language: language == null ? this.language : language(),
  );

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.theme == theme &&
      other.compact == compact &&
      other.previewLines == previewLines &&
      other.translateInto == translateInto &&
      other.language == language;

  @override
  int get hashCode =>
      Object.hash(theme, compact, previewLines, translateInto, language);
}

/// The languages the app speaks, each in its own words, as the language
/// picker lists them.
const appLanguages = {
  'en': 'English',
  'it': 'Italiano',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'pt': 'Português',
};

/// The app's language: [picked] if the app speaks it, else the first of
/// the device's languages it speaks, else English.
Locale appLocale(String? picked, List<Locale> device) {
  if (appLanguages.containsKey(picked)) return Locale(picked!);
  for (final locale in device) {
    if (appLanguages.containsKey(locale.languageCode)) {
      return Locale(locale.languageCode);
    }
  }
  return const Locale('en');
}

/// The appearance picked, and a way to change it, for the widgets below
/// the app.
class PiumaLook extends InheritedWidget {
  const PiumaLook({
    super.key,
    required this.appearance,
    required this.onChanged,
    required super.child,
  });

  final Appearance appearance;
  final ValueChanged<Appearance> onChanged;

  /// The defaults where no app is above, as in some tests.
  static Appearance of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PiumaLook>()?.appearance ??
      const Appearance();

  static void set(BuildContext context, Appearance appearance) =>
      context.getInheritedWidgetOfExactType<PiumaLook>()?.onChanged(appearance);

  @override
  bool updateShouldNotify(PiumaLook old) => old.appearance != appearance;
}
