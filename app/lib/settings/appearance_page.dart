import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/look.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/message_list.dart' show InboxRowTile;
import '../inbox/sections.dart' show rowTime;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../mail/translator.dart';
import '../widgets/segments.dart';
import 'settings_screen.dart' show HelperSwitches, SettingsHeader;

/// Settings › Appearance, as on the `Settings` board: the theme as three
/// cards and the app's language.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key, required this.source, this.phone = false});

  final MailSource source;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final look = PiumaLook.of(context);
    void set(Appearance next) => PiumaLook.set(context, next);
    Widget heading(String text) => Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: c.muted,
        ),
      ),
    );
    final themes = [
      for (final (choice, label) in [
        (ThemeChoice.light, l.themeLight),
        (ThemeChoice.dark, l.themeDark),
        (ThemeChoice.automatic, l.themeAutomatic),
      ])
        Expanded(
          child: _ThemeCard(
            choice: choice,
            label: label,
            selected: look.theme == choice,
            onTap: () => set(look.copyWith(theme: choice)),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeader(
          title: l.appearanceTitle,
          subtitle: l.appearanceSubtitle,
        ),
        const SizedBox(height: PiumaSpace.s32),
        heading(l.appearanceTheme),
        const SizedBox(height: 10),
        Semantics(
          container: true,
          label: l.appearanceTheme,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, card) in themes.indexed) ...[
                if (i > 0) SizedBox(width: phone ? 10 : 12),
                card,
              ],
            ],
          ),
        ),
        const SizedBox(height: PiumaSpace.s32),
        heading(l.appearanceLanguage),
        const SizedBox(height: 10),
        _AppLanguage(
          selected: look.language,
          phone: phone,
          onPick: (code) =>
              set(look.copyWith(language: () => code.isEmpty ? null : code)),
        ),
      ],
    );
  }
}

/// Settings › Reading (`SettingsOrderToApprove`, B): how the list looks,
/// and the on-device helpers with the language Translate writes in.
class ReadingPage extends StatelessWidget {
  const ReadingPage({
    super.key,
    required this.source,
    this.phone = false,
    this.now = DateTime.now,
  });

  final MailSource source;
  final bool phone;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final look = PiumaLook.of(context);
    void set(Appearance next) => PiumaLook.set(context, next);
    Widget heading(String text) => Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: c.muted,
        ),
      ),
    );
    return ValueListenableBuilder(
      valueListenable: source.features,
      builder: (context, features, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsHeader(title: l.readingTitle, subtitle: l.readingSubtitle),
          const SizedBox(height: PiumaSpace.s32),
          Wrap(
            spacing: PiumaSpace.s32,
            runSpacing: PiumaSpace.s24,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading(l.appearanceDensity),
                  const SizedBox(height: 10),
                  PiumaSegments(
                    label: l.appearanceDensity,
                    items: [
                      (
                        l.densityComfortable,
                        !look.compact,
                        () => set(look.copyWith(compact: false)),
                      ),
                      (
                        l.densityCompact,
                        look.compact,
                        () => set(look.copyWith(compact: true)),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading(l.appearancePreview),
                  const SizedBox(height: 10),
                  PiumaSegments(
                    label: l.appearancePreview,
                    items: [
                      for (final n in [1, 2])
                        (
                          l.previewLines(n),
                          look.previewLines == n,
                          () => set(look.copyWith(previewLines: n)),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          _Example(source: source, phone: phone, now: now),
          const SizedBox(height: PiumaSpace.s32),
          HelperSwitches(source: source),
          // Translate turned off just above: only the languages
          // already downloaded, to remove them.
          if (Translator.offered && !features.translate)
            _DownloadedPairs(phone: phone)
          else if (Translator.offered) ...[
            const SizedBox(height: PiumaSpace.s32),
            heading(l.appearanceTranslateInto),
            const SizedBox(height: 10),
            _TranslateInto(
              selected: look.translateInto,
              phone: phone,
              onPick: (code) => set(
                look.copyWith(translateInto: () => code.isEmpty ? null : code),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.translateIntoHint,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 12.5,
                color: c.muted,
              ),
            ),
            _DownloadedPairs(phone: phone),
          ],
        ],
      ),
    );
  }
}

/// The first two emails of the inbox, drawn as Density and Preview make
/// them look.
class _Example extends StatefulWidget {
  const _Example({
    required this.source,
    required this.phone,
    required this.now,
  });

  final MailSource source;
  final bool phone;
  final DateTime Function() now;

  @override
  State<_Example> createState() => _ExampleState();
}

class _ExampleState extends State<_Example> {
  List<MailRow> _sample = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.source.page(0, 2);
      if (mounted) setState(() => _sample = rows);
    } catch (_) {
      // No example then.
    }
  }

  MailAccount? _account(int id) {
    for (final a in widget.source.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_sample.isEmpty) return const SizedBox.shrink();
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: PiumaSpace.s32),
        Semantics(
          container: true,
          label: l.appearanceExample,
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: widget.phone
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(6, 6, 6, 4),
                color: c.surface,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (final (i, row) in _sample.indexed) ...[
                      if (i > 0 && widget.phone)
                        Container(height: 1, color: c.line),
                      InboxRowTile(
                        row: row,
                        account: _account(row.accountId),
                        time: rowTime(row.receivedAt, now, locale),
                        selected: false,
                        phone: widget.phone,
                        onTap: () {},
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A language picked from a menu: the first item, empty, stands for the
/// default, and the rest are by name.
class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({
    required this.label,
    required this.items,
    required this.selected,
    required this.phone,
    required this.onPick,
  });

  final String label;

  /// Codes and names, the default first with an empty code.
  final List<(String, String)> items;

  final String? selected;
  final bool phone;

  /// An empty code for the default.
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    TextStyle style(Color color) =>
        TextStyle(fontFamily: PiumaFonts.sans, fontSize: 14, color: color);
    final current = items.firstWhere(
      (item) => item.$1 == (selected ?? ''),
      orElse: () => items.first,
    );
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onPick,
      color: c.surface,
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 220),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PiumaRadius.row),
        side: BorderSide(color: c.line),
      ),
      itemBuilder: (_) => [
        for (final (code, name) in items)
          PopupMenuItem(
            value: code,
            child: Text(name, style: style(c.fg)),
          ),
      ],
      child: Container(
        width: phone ? double.infinity : 280,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.button),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style(c.fg).copyWith(fontSize: 15),
              ),
            ),
            PiumaIconView(PiumaIcon.chevronDown, size: 14, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// The app's language: the device's, or one the app speaks, each named
/// in its own words.
class _AppLanguage extends StatelessWidget {
  const _AppLanguage({
    required this.selected,
    required this.phone,
    required this.onPick,
  });

  final String? selected;
  final bool phone;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final names = appLanguages.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return _LanguageMenu(
      label: l.appearanceLanguage,
      items: [('', l.languageDevice), for (final e in names) (e.key, e.value)],
      selected: selected,
      phone: phone,
      onPick: onPick,
    );
  }
}

/// "Translate into": the app's language, or one of the languages Translate
/// knows, by name.
class _TranslateInto extends StatelessWidget {
  const _TranslateInto({
    required this.selected,
    required this.phone,
    required this.onPick,
  });

  final String? selected;
  final bool phone;

  /// An empty code for the app's language.
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String name(String code) {
      final n = l.languageName(code);
      return n.isEmpty ? n : n[0].toUpperCase() + n.substring(1);
    }

    final codes = [...Translator.languages]
      ..sort((a, b) => name(a).compareTo(name(b)));
    return _LanguageMenu(
      label: l.appearanceTranslateInto,
      items: [
        ('', l.translateIntoApp),
        for (final code in codes) (code, name(code)),
      ],
      selected: selected,
      phone: phone,
      onPick: onPick,
    );
  }
}

/// The language pairs downloaded for translation, each with its size and
/// Remove; nothing where none is (Apple's are the system's own).
class _DownloadedPairs extends StatefulWidget {
  const _DownloadedPairs({required this.phone});

  final bool phone;

  @override
  State<_DownloadedPairs> createState() => _DownloadedPairsState();
}

class _DownloadedPairsState extends State<_DownloadedPairs> {
  List<DownloadedPair> _pairs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pairs = await Translator.engine.downloaded();
    if (mounted) setState(() => _pairs = pairs);
  }

  Future<void> _remove(DownloadedPair pair) async {
    setState(() => _pairs = [..._pairs]..remove(pair));
    try {
      await Translator.engine.remove(pair);
    } finally {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pairs.isEmpty) return const SizedBox.shrink();
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    String name(String code) {
      final n = l.languageName(code);
      return n.isEmpty ? n : n[0].toUpperCase() + n.substring(1);
    }

    final text = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 14,
      color: c.fg,
    );
    return Padding(
      padding: const EdgeInsets.only(top: PiumaSpace.s16),
      child: Container(
        width: widget.phone ? double.infinity : 420,
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: Column(
          children: [
            for (final (i, pair) in _pairs.indexed)
              Container(
                height: 44,
                padding: const EdgeInsets.only(left: 14, right: 4),
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.translatePair(name(pair.from), name(pair.to)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text,
                      ),
                    ),
                    Text(
                      fileSize(pair.bytes, locale: locale),
                      style: PiumaType.mono.copyWith(
                        fontSize: 12.5,
                        color: c.muted,
                      ),
                    ),
                    PiumaPressable(
                      onTap: () => _remove(pair),
                      semanticLabel: l.translateRemovePair(
                        l.translatePair(name(pair.from), name(pair.to)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          l.translateRemove,
                          style: text.copyWith(
                            fontSize: 13,
                            color: c.accentText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A theme as a small picture of the app and its name.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.choice,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ThemeChoice choice;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    final picture = switch (choice) {
      ThemeChoice.light => const _Miniature(PiumaColors.light),
      ThemeChoice.dark => const _Miniature(PiumaColors.dark),
      ThemeChoice.automatic => const Stack(
        fit: StackFit.expand,
        children: [
          _Miniature(PiumaColors.light),
          ClipRect(clipper: _RightHalf(), child: _Miniature(PiumaColors.dark)),
        ],
      ),
    };
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? c.accent : c.line),
            boxShadow: [
              BoxShadow(
                color: selected ? c.accent : c.accent.withValues(alpha: 0),
                spreadRadius: 1,
              ),
            ],
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 88,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: picture,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The app in one palette: a sidebar and two emails.
class _Miniature extends StatelessWidget {
  const _Miniature(this.p);
  final PiumaColors p;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height, {bool strong = false}) =>
        FractionallySizedBox(
          widthFactor: width,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: strong ? p.muted : p.line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
    return ColoredBox(
      color: p.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: ColoredBox(color: p.bg)),
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(0.7, 6, strong: true),
                  const SizedBox(height: 7),
                  bar(0.9, 5),
                  const SizedBox(height: 13),
                  bar(0.55, 6, strong: true),
                  const SizedBox(height: 7),
                  bar(0.8, 5),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RightHalf extends CustomClipper<Rect> {
  const _RightHalf();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width / 2, 0, size.width, size.height);

  @override
  bool shouldReclip(_RightHalf old) => false;
}
