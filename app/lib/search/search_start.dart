import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/message_list.dart' show initials;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/message_row.dart';

/// The kinds of mail "Search by type" offers, as the operators they add.
const searchTypes = [
  'has:attachment',
  'from:people',
  'in:vault',
  'in:newsletter',
];

/// The phone search before anything is typed, as `SearchEmpty`: search by
/// type, frequent contacts, recent searches, the operators and how much
/// is indexed on this device.
class SearchStartView extends StatelessWidget {
  const SearchStartView({
    super.key,
    required this.start,
    required this.accounts,
    required this.onType,
    required this.onPerson,
    required this.onRecent,
    required this.onForget,
    required this.onClear,
  });

  final SearchStart start;
  final List<MailAccount> accounts;

  /// A type was picked: its operator, from [searchTypes].
  final ValueChanged<String> onType;
  final ValueChanged<FrequentContact> onPerson;
  final ValueChanged<String> onRecent;
  final ValueChanged<String> onForget;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final heading = PiumaType.small.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: c.muted,
    );
    Widget title(String text) => Semantics(
      container: true,
      header: true,
      child: Text(text, style: heading),
    );
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 28),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title(l.searchByType),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final op in searchTypes)
                    _TypeChip(op: op, onTap: () => onType(op)),
                ],
              ),
            ],
          ),
        ),
        if (start.frequent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: title(l.frequentContacts),
          ),
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final p in start.frequent) ...[
                  _Person(
                    person: p,
                    color: _color(p.accountId),
                    onTap: () => onPerson(p),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 8, 2),
          child: Row(
            children: [
              Expanded(child: title(l.recentSearches)),
              if (start.recent.isNotEmpty)
                Semantics(
                  container: true,
                  child: PiumaPressable(
                    onTap: onClear,
                    semanticLabel: l.clearRecentSearches,
                    child: SizedBox(
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(
                          widthFactor: 1,
                          child: ExcludeSemantics(
                            child: Text(
                              l.clearRecent,
                              style: PiumaType.body.copyWith(
                                fontSize: 14,
                                color: c.accentText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (start.recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              l.noRecentSearches,
              style: PiumaType.body.copyWith(fontSize: 14, color: c.muted),
            ),
          ),
        for (final q in start.recent)
          _Recent(
            query: q,
            onTap: () => onRecent(q),
            onForget: () => onForget(q),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(20, 26, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(PiumaRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.searchOperatorsHint,
                style: PiumaType.small.copyWith(fontSize: 13, color: c.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final op in const [
                    'from:',
                    'has:attachment',
                    'before:',
                    'in:vault',
                  ])
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        op,
                        style: PiumaType.mono.copyWith(
                          fontSize: 13,
                          color: c.fg,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PiumaIconView(PiumaIcon.lock, size: 13, color: c.muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l.searchIndexed(
                    start.indexed,
                    NumberFormat.decimalPattern(locale).format(start.indexed),
                  ),
                  textAlign: TextAlign.center,
                  style: PiumaType.small.copyWith(fontSize: 12, color: c.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color? _color(int accountId) {
    for (final a in accounts) {
      if (a.id == accountId) return a.color;
    }
    return null;
  }
}

/// One "Search by type" chip: an outlined pill with its icon.
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.op, required this.onTap});

  final String op;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final (icon, label) = switch (op) {
      'has:attachment' => (PiumaIcon.paperclip, l.searchWithAttachments),
      'from:people' => (PiumaIcon.people, l.searchFromPeople),
      'in:vault' => (PiumaIcon.vault, l.folderVault),
      _ => (PiumaIcon.newsletter, l.folderNewsletters),
    };
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 44,
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 36,
              padding: const EdgeInsets.fromLTRB(11, 0, 14, 0),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(PiumaRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PiumaIconView(icon, size: 15, color: c.fg),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: PiumaType.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A frequent contact: the avatar with the account's dot, the first name.
class _Person extends StatelessWidget {
  const _Person({required this.person, this.color, required this.onTap});

  final FrequentContact person;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final name = person.name.isEmpty ? person.email : person.name;
    final first = name.split(' ').first;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: l.searchMailFrom(name),
      child: ExcludeSemantics(
        child: SizedBox(
          width: 68,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                PiumaAvatar(
                  initials: initials(name),
                  accountColor: color,
                  size: 52,
                ),
                const SizedBox(height: 6),
                Text(
                  first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.small.copyWith(fontSize: 12, color: c.fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A recent search: the history icon, its operator as a mono chip, the
/// words, and a cross that forgets it.
class _Recent extends StatelessWidget {
  const _Recent({
    required this.query,
    required this.onTap,
    required this.onForget,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final parts = query.split(' ');
    final op = parts.first.contains(':') ? parts.first : null;
    final words = op == null ? query : parts.skip(1).join(' ');
    return Container(
      padding: const EdgeInsets.only(left: 20, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: PiumaPressable(
              onTap: onTap,
              semanticLabel: query,
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      PiumaIconView(
                        PiumaIcon.history,
                        size: 17,
                        color: c.muted,
                      ),
                      const SizedBox(width: 12),
                      if (op != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: c.soft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            op,
                            style: PiumaType.mono.copyWith(
                              fontSize: 13,
                              color: c.accentText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          words,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PiumaType.body.copyWith(color: c.fg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PiumaPressable(
            onTap: onForget,
            semanticLabel: l.removeRecentSearch(query),
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: PiumaIconView(PiumaIcon.close, size: 15, color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
