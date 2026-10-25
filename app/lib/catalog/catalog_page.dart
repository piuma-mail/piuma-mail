import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../legal.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../widgets/button.dart';
import '../widgets/chip.dart';
import '../widgets/message_row.dart';

/// Component catalog: the Flutter version of the canvas "Design system"
/// section, to compare the two at a glance.
class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.dark,
    required this.onToggleTheme,
  });

  final bool dark;
  final VoidCallback onToggleTheme;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _chips = <_Filter, bool>{
    _Filter.unread: true,
    _Filter.attachments: false,
    _Filter.people: false,
  };
  int _selected = 2;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    var i = 0;
    Widget enter(Widget w) => PiumaEnter(index: i++, child: w);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            PiumaSpace.s24,
            PiumaSpace.s32,
            PiumaSpace.s24,
            PiumaSpace.s32,
          ),
          children: [
            enter(
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Piuma Mail',
                      style: PiumaType.display.copyWith(color: c.fg),
                    ),
                  ),
                  PiumaButton(
                    label: widget.dark ? l.themeLight : l.themeDark,
                    kind: PiumaButtonKind.secondary,
                    size: PiumaButtonSize.compact,
                    onPressed: widget.onToggleTheme,
                  ),
                ],
              ),
            ),
            const SizedBox(height: PiumaSpace.s4),
            enter(
              Text(
                l.catalogSubtitle,
                style: PiumaType.small.copyWith(color: c.muted),
              ),
            ),
            const SizedBox(height: PiumaSpace.s32),
            enter(_Section(l.sectionColors)),
            enter(
              Wrap(
                spacing: PiumaSpace.s8,
                runSpacing: PiumaSpace.s8,
                children: [
                  for (final (name, color) in [
                    (l.colorBackground, c.bg),
                    (l.colorSurface, c.surface),
                    (l.colorText, c.fg),
                    (l.colorSecondary, c.muted),
                    (l.colorAccent, c.accent),
                    (l.colorSoft, c.soft),
                    (l.colorSuccess, c.ok),
                    (l.colorWarning, c.warn),
                    (l.colorDanger, c.danger),
                  ])
                    _Swatch(name: name, color: color),
                ],
              ),
            ),
            const SizedBox(height: PiumaSpace.s12),
            enter(
              Wrap(
                spacing: PiumaSpace.s12,
                children: [
                  for (final color in PiumaAccountColors.all)
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: PiumaSpace.s32),
            enter(_Section(l.sectionTypography)),
            for (final (name, style) in [
              (l.typeDisplay, PiumaType.display),
              (l.typeTitle, PiumaType.title),
              (l.typeSubtitle, PiumaType.subtitle),
              (l.typeBody, PiumaType.body),
              (l.typeSmall, PiumaType.small),
              (l.typeMono, PiumaType.mono),
            ])
              enter(
                Padding(
                  padding: const EdgeInsets.only(bottom: PiumaSpace.s8),
                  child: Text(name, style: style.copyWith(color: c.fg)),
                ),
              ),
            const SizedBox(height: PiumaSpace.s24),
            enter(_Section(l.sectionButtons)),
            enter(
              Wrap(
                spacing: PiumaSpace.s8,
                runSpacing: PiumaSpace.s8,
                children: [
                  PiumaButton(label: l.actionSend, onPressed: () {}),
                  PiumaButton(
                    label: l.actionSnooze,
                    kind: PiumaButtonKind.secondary,
                    onPressed: () {},
                  ),
                  PiumaButton(
                    label: l.actionReply,
                    kind: PiumaButtonKind.tertiary,
                    onPressed: () {},
                  ),
                  PiumaButton(
                    label: l.actionDelete,
                    kind: PiumaButtonKind.danger,
                    onPressed: () {},
                  ),
                  PiumaButton(label: l.actionDisabled),
                ],
              ),
            ),
            const SizedBox(height: PiumaSpace.s32),
            enter(_Section(l.sectionFilters)),
            enter(
              Wrap(
                spacing: PiumaSpace.s8,
                children: [
                  for (final e in _chips.entries)
                    PiumaChip(
                      label: e.key.label(l),
                      selected: e.value,
                      onChanged: (v) => setState(() => _chips[e.key] = v),
                    ),
                ],
              ),
            ),
            const SizedBox(height: PiumaSpace.s32),
            enter(_Section(l.sectionMessageRows)),
            for (final (n, row) in [
              (
                0,
                (
                  'JR',
                  'Julia Reed',
                  '9:41',
                  'New website quote',
                  'Here is the updated version with the changes',
                  true,
                ),
              ),
              (
                1,
                (
                  'LB',
                  'Luke Baker',
                  'Yesterday',
                  'Thursday meeting',
                  '3 pm works for me, I will bring the sketches',
                  false,
                ),
              ),
              (
                2,
                (
                  'SF',
                  'Sarah Ford',
                  'Mon',
                  'Signed contract',
                  'Attached is the copy signed by both of us',
                  false,
                ),
              ),
            ])
              enter(
                MessageRow(
                  initials: row.$1,
                  from: row.$2,
                  time: row.$3,
                  subject: row.$4,
                  preview: row.$5,
                  unread: row.$6,
                  selected: _selected == n,
                  accountColor: PiumaAccountColors.lavoro,
                  onTap: () => setState(() => _selected = n),
                ),
              ),
            const SizedBox(height: PiumaSpace.s32),
            enter(
              Text(fontCredit, style: PiumaType.small.copyWith(color: c.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Filter {
  unread,
  attachments,
  people;

  String label(AppLocalizations l) => switch (this) {
    _Filter.unread => l.filterUnread,
    _Filter.attachments => l.filterAttachments,
    _Filter.people => l.filterPeople,
  };
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: PiumaSpace.s12),
      child: Text(
        title.toUpperCase(),
        style: PiumaType.label.copyWith(color: c.muted),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return SizedBox(
      width: 88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(PiumaRadius.row),
              border: Border.all(color: c.line),
            ),
          ),
          const SizedBox(height: PiumaSpace.s4),
          Text(name, style: PiumaType.small.copyWith(color: c.muted)),
        ],
      ),
    );
  }
}
