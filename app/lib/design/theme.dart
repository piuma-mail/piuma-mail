import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// Carries Piuma's role colors inside [ThemeData].
///
/// Read it with `PiumaTheme.of(context)`.
class PiumaTheme extends ThemeExtension<PiumaTheme> {
  const PiumaTheme(this.colors);

  final PiumaColors colors;

  static PiumaColors of(BuildContext context) =>
      Theme.of(context).extension<PiumaTheme>()!.colors;

  @override
  PiumaTheme copyWith({PiumaColors? colors}) =>
      PiumaTheme(colors ?? this.colors);

  @override
  PiumaTheme lerp(PiumaTheme? other, double t) {
    if (other == null) return this;
    final a = colors, b = other.colors;
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    return PiumaTheme(
      PiumaColors(
        bg: l(a.bg, b.bg),
        surface: l(a.surface, b.surface),
        fg: l(a.fg, b.fg),
        muted: l(a.muted, b.muted),
        line: l(a.line, b.line),
        sel: l(a.sel, b.sel),
        chip: l(a.chip, b.chip),
        accent: l(a.accent, b.accent),
        onAccent: l(a.onAccent, b.onAccent),
        soft: l(a.soft, b.soft),
        accentText: l(a.accentText, b.accentText),
        ok: l(a.ok, b.ok),
        warn: l(a.warn, b.warn),
        warnSoft: l(a.warnSoft, b.warnSoft),
        warnLine: l(a.warnLine, b.warnLine),
        danger: l(a.danger, b.danger),
        scrim: l(a.scrim, b.scrim),
        shadow: l(a.shadow, b.shadow),
        placeholder: l(a.placeholder, b.placeholder),
        ring: l(a.ring, b.ring),
        hover: l(a.hover, b.hover),
        page: l(a.page, b.page),
        rule: l(a.rule, b.rule),
        okSoft: l(a.okSoft, b.okSoft),
        busy: l(a.busy, b.busy),
        stage: l(a.stage, b.stage),
        darkroom: l(a.darkroom, b.darkroom),
        track: l(a.track, b.track),
      ),
    );
  }
}

/// Full theme for light or dark.
ThemeData buildPiumaTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? PiumaColors.dark
      : PiumaColors.light;
  final text = TextTheme(
    displaySmall: PiumaType.display,
    headlineSmall: PiumaType.title,
    titleMedium: PiumaType.subtitle,
    bodyLarge: PiumaType.body,
    bodyMedium: PiumaType.body,
    bodySmall: PiumaType.small.copyWith(color: c.muted),
    labelSmall: PiumaType.label.copyWith(color: c.muted),
  ).apply(bodyColor: c.fg, displayColor: c.fg);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: PiumaFonts.sans,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: text,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.accentText,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: c.onAccent,
      surface: c.surface,
      onSurface: c.fg,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.sel,
    ),
    extensions: [PiumaTheme(c)],
  );
}
