import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/links.dart';
import 'message_body.dart';
import 'reader.dart' show MessageView;
import 'vault.dart' show ZoneTile;

/// How many newsletters the list loads; older ones archive themselves.
const _limit = 300;

/// The quiet square a newsletter gets in place of a picture, the same for
/// every issue of one sender.
Color newsletterTint(BuildContext context, String email) {
  final tints = Theme.of(context).brightness == Brightness.dark
      ? PiumaTints.dark
      : PiumaTints.light;
  var hash = 0;
  for (final unit in email.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return tints[hash % tints.length];
}

/// "today", "yesterday", the weekday this week, the date before.
String newsletterDay(
  AppLocalizations l,
  DateTime t,
  DateTime now,
  String locale,
) {
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return l.dayToday;
  if (days == 1) return l.dayYesterday;
  if (days < 7) return DateFormat.E(locale).format(t);
  return DateFormat.MMMd(locale).format(t);
}

/// "8 min read · arrived at 7:02", or on a date when not today.
String newsletterArrival(
  AppLocalizations l,
  Newsletter n,
  DateTime now,
  String locale,
) {
  final t = n.row.receivedAt;
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  final time = DateFormat.Hm(locale).format(t);
  final date = DateFormat.MMMd(locale).format(t);
  return switch ((n.minutes > 0, today)) {
    (true, true) => l.newsletterReadTime(n.minutes, time),
    (true, false) => l.newsletterReadTimeOn(n.minutes, date),
    (false, true) => l.newsletterArrived(time),
    (false, false) => l.newsletterArrivedOn(date),
  };
}

/// What the header says: "3 reads · 23 min", or "All read".
String newslettersSummary(
  AppLocalizations l,
  List<Newsletter> letters, {
  bool long = false,
}) {
  if (letters.isEmpty) return l.newslettersEmpty;
  final (count, minutes) = _toRead(letters);
  return [
    l.newslettersToRead(count),
    if (count > 0 && minutes > 0)
      long ? l.newslettersMinutesLong(minutes) : l.newslettersMinutes(minutes),
  ].join(' · ');
}

/// Unread ones and the minutes they take.
(int, int) _toRead(List<Newsletter> letters) {
  var count = 0, minutes = 0;
  for (final n in letters) {
    if (n.row.seen) continue;
    count++;
    minutes += n.minutes;
  }
  return (count, minutes);
}

/// The issues last read, per source and account: shown at once when
/// Newsletters opens again, while they're read afresh.
final _lastLetters = Expando<Map<int?, List<Newsletter>>>();

/// Newsletters read elsewhere, for every account, kept so the page has
/// them the first time it opens too.
void rememberNewsletters(MailSource source, List<Newsletter> letters) =>
    (_lastLetters[source] ??= {})[null] = letters;

/// How many issues Newsletters lists at most.
const newsletterLimit = _limit;

/// Keeps Newsletters loaded, and fresh when the mail changes.
mixin _Letters<T extends StatefulWidget> on State<T> {
  MailSource get source;
  int? get account;

  List<Newsletter>? letters;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    letters = _lastLetters[source]?[account];
    _load();
    _changes = source.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await source.newsletters(0, _limit, account: account);
    (_lastLetters[source] ??= {})[account] = loaded;
    if (mounted) setState(() => letters = loaded);
  }
}

/// The left half of `DesktopEdicola`: the date, "Newsletters" with what
/// is left to read, and one row per issue.
class NewsletterList extends StatefulWidget {
  const NewsletterList({
    super.key,
    required this.source,
    required this.now,
    required this.onSelect,
    this.selected,
    this.account,
  });

  final MailSource source;
  final DateTime Function() now;
  final ValueChanged<MailRow> onSelect;
  final Object? selected;
  final int? account;

  @override
  State<NewsletterList> createState() => _NewsletterListState();
}

class _NewsletterListState extends State<NewsletterList>
    with _Letters<NewsletterList> {
  @override
  MailSource get source => widget.source;

  @override
  int? get account => widget.account;

  @override
  void didUpdateWidget(NewsletterList old) {
    super.didUpdateWidget(old);
    if (old.account != widget.account) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    final letters = this.letters ?? const <Newsletter>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 22, 12, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat.MMMMEEEEd(locale).format(now).toUpperCase(),
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.96,
                  color: c.muted,
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l.folderNewsletters,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 28,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.84,
                        color: c.fg,
                      ),
                    ),
                  ),
                  if (this.letters != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        newslettersSummary(l, letters),
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 13,
                          color: c.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        for (final n in letters)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _DesktopRow(
              source: widget.source,
              letter: n,
              when: newsletterDay(l, n.row.receivedAt, now, locale),
              selected: n.row.key == widget.selected,
              onTap: () => widget.onSelect(n.row),
            ),
          ),
      ],
    );
  }
}

class _DesktopRow extends StatelessWidget {
  const _DesktopRow({
    required this.source,
    required this.letter,
    required this.when,
    required this.selected,
    required this.onTap,
  });

  final MailSource source;
  final Newsletter letter;
  final String when;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = letter.row;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: '${row.sender}, ${row.subject}',
      child: AnimatedContainer(
        duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
        curve: PiumaMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? c.sel : const Color(0x00000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: NewsletterPicture(
                  source: source,
                  row: row,
                  radius: 10,
                  fallback: ColoredBox(
                    color: newsletterTint(context, row.fromEmail),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RowText(
                  source: row.sender,
                  title: row.subject,
                  meta: letter.minutes > 0
                      ? l.newsletterRowMeta(letter.minutes, when)
                      : when,
                  unread: !row.seen,
                  sizes: (11, 15, 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Source in capitals, the title (heavier when unread), then the meta.
class _RowText extends StatelessWidget {
  const _RowText({
    required this.source,
    required this.title,
    required this.meta,
    required this.unread,
    required this.sizes,
  });

  final String source;
  final String title;
  final String meta;
  final bool unread;

  /// Source, title and meta font sizes.
  final (double, double, double) sizes;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final (s, t, m) = sizes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          source.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: s,
            fontWeight: FontWeight.w600,
            letterSpacing: s * 0.05,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: t,
            height: 1.3,
            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
            letterSpacing: t > 16 ? -0.17 : 0,
            color: c.fg,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          meta,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: m,
            color: c.muted,
          ),
        ),
      ],
    );
  }
}

/// The right half of `DesktopEdicola`: who sent it, Read later and
/// Unsubscribe, then the issue set as an article.
class NewsletterPane extends StatefulWidget {
  const NewsletterPane({
    super.key,
    required this.source,
    required this.row,
    required this.now,
    required this.onReadLater,
    required this.onToast,
    this.onBack,
  });

  final MailSource source;
  final MailRow? row;
  final DateTime Function() now;
  final ValueChanged<MailRow> onReadLater;
  final ValueChanged<String> onToast;

  /// Back to the list, when the pane covers it.
  final VoidCallback? onBack;

  @override
  State<NewsletterPane> createState() => _NewsletterPaneState();
}

class _NewsletterPaneState extends State<NewsletterPane> {
  late final _images = RemoteImages(widget.source);

  /// The open issue's reading time, once known.
  Future<List<Newsletter>>? _letter;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void didUpdateWidget(NewsletterPane old) {
    super.didUpdateWidget(old);
    if (old.row?.key != widget.row?.key) _find();
  }

  void _find() => _letter = widget.row == null
      ? null
      : widget.source.newsletters(0, _limit);

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = widget.row;
    if (row == null) {
      return Center(
        child: Text(
          l.nothingSelected,
          style: TextStyle(fontSize: 14, color: c.muted),
        ),
      );
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              if (widget.onBack case final back?) ...[
                PiumaPressable(
                  onTap: back,
                  semanticLabel: l.back,
                  child: PiumaIconView(
                    PiumaIcon.chevronLeft,
                    size: 20,
                    color: c.accentText,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  '${row.sender} · ${row.fromEmail}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    color: c.muted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PiumaButton(
                label: l.readLater,
                kind: PiumaButtonKind.secondary,
                size: PiumaButtonSize.compact,
                onPressed: () => widget.onReadLater(row),
              ),
              const SizedBox(width: 6),
              PiumaButton(
                label: l.unsubscribe,
                kind: PiumaButtonKind.secondary,
                size: PiumaButtonSize.compact,
                onPressed: () => unsubscribeFrom(
                  context,
                  widget.source,
                  row,
                  onToast: widget.onToast,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: PageStorageKey(row.key),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 44),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: PiumaEnter(
                  key: ValueKey(row.key),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.sender.toUpperCase(),
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.96,
                          color: c.accentText,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        row.subject,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 38,
                          height: 1.12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.14,
                          color: c.fg,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FutureBuilder<List<Newsletter>>(
                        future: _letter,
                        builder: (context, snap) {
                          final n = (snap.data ?? const <Newsletter>[])
                              .where((n) => n.row.key == row.key)
                              .firstOrNull;
                          return Text(
                            newsletterArrival(
                              l,
                              n ?? Newsletter(row),
                              widget.now(),
                              locale,
                            ),
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 14,
                              color: c.muted,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      MessageView(
                        key: ValueKey(row.key),
                        source: widget.source,
                        row: row,
                        images: _images,
                        article: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `PhoneEdicola`: "‹ Inbox", the date and what is left to read, the
/// newest unread issue as a cover, then the rest.
class PhoneNewsletters extends StatefulWidget {
  const PhoneNewsletters({
    super.key,
    required this.source,
    required this.now,
    required this.onBack,
    required this.onOpen,
    this.account,
  });

  final MailSource source;
  final DateTime Function() now;
  final VoidCallback onBack;
  final ValueChanged<MailRow> onOpen;
  final int? account;

  @override
  State<PhoneNewsletters> createState() => _PhoneNewslettersState();
}

class _PhoneNewslettersState extends State<PhoneNewsletters>
    with _Letters<PhoneNewsletters> {
  @override
  MailSource get source => widget.source;

  @override
  int? get account => widget.account;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    final letters = this.letters ?? const <Newsletter>[];
    final cover = letters.where((n) => !n.row.seen).firstOrNull;
    final rest = [
      for (final n in letters)
        if (n != cover) n,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: PiumaPressable(
              onTap: widget.onBack,
              semanticLabel: l.inbox,
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PiumaIconView(
                        PiumaIcon.chevronLeft,
                        size: 22,
                        color: c.accentText,
                      ),
                      const SizedBox(width: 2),
                      ExcludeSemantics(
                        child: Text(
                          l.inbox,
                          style: TextStyle(fontSize: 16, color: c.accentText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat.MMMMEEEEd(locale).format(now).toUpperCase(),
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.96,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Semantics(
                      header: true,
                      child: Text(
                        l.folderNewsletters,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 30,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.9,
                          color: c.fg,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (this.letters != null)
                      Text(
                        newslettersSummary(l, letters, long: true),
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 14,
                          color: c.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (cover != null)
                _Cover(
                  source: widget.source,
                  letter: cover,
                  arrival: newsletterArrival(l, cover, now, locale),
                  onTap: () => widget.onOpen(cover.row),
                ),
              for (final n in rest)
                _PhoneRow(
                  source: widget.source,
                  letter: n,
                  when: newsletterDay(l, n.row.receivedAt, now, locale),
                  onTap: () => widget.onOpen(n.row),
                ),
              if (letters.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                  child: Text(
                    l.newslettersArchiveNote,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 13,
                      color: c.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The newest unread issue, with its first photo as a cover when the
/// sender is trusted, else one in the sender's tint.
class _Cover extends StatelessWidget {
  const _Cover({
    required this.source,
    required this.letter,
    required this.arrival,
    required this.onTap,
  });

  final MailSource source;
  final Newsletter letter;
  final String arrival;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final row = letter.row;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tints = dark ? PiumaTints.dark : PiumaTints.light;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: '${row.sender}, ${row.subject}',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 22),
          padding: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: NewsletterPicture(
                    source: source,
                    row: row,
                    radius: 0,
                    fallback: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            newsletterTint(context, row.fromEmail),
                            tints[1],
                            tints[2],
                          ],
                          stops: const [0, 0.45, 1],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 24,
                            top: 30,
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                color: c.accent.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 30,
                            bottom: 26,
                            child: Container(
                              width: 120,
                              height: 56,
                              decoration: BoxDecoration(
                                color: c.surface.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                row.sender.toUpperCase(),
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.72,
                  color: c.accentText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                row.subject,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 23,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.46,
                  color: c.fg,
                ),
              ),
              if (row.preview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  row.preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 15,
                    height: 1.55,
                    color: c.muted,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                arrival,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  color: c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({
    required this.source,
    required this.letter,
    required this.when,
    required this.onTap,
  });

  final MailSource source;
  final Newsletter letter;
  final String when;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = letter.row;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: '${row.sender}, ${row.subject}',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 22),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _RowText(
                  source: row.sender,
                  title: row.subject,
                  meta: letter.minutes > 0
                      ? l.newsletterRowMeta(letter.minutes, when)
                      : when,
                  unread: !row.seen,
                  sizes: (12, 17, 13),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 64,
                height: 64,
                child: NewsletterPicture(
                  source: source,
                  row: row,
                  radius: 12,
                  fallback: ColoredBox(
                    color: newsletterTint(context, row.fromEmail),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Newsletters tile at the top of the phone list (`ZonesToApprove`):
/// how many are new.
class NewslettersTile extends StatelessWidget {
  const NewslettersTile({super.key, required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ZoneTile(
      icon: PiumaIcon.newsletter,
      title: l.folderNewsletters,
      line: unread > 0 ? l.newslettersNew(unread) : l.zoneNothingNew,
      semanticLabel: l.newslettersTileLabel(unread),
      onTap: onTap,
    );
  }
}

/// Asks, then leaves the list [row] came from: one request, a message to
/// its address, or its page in the browser. "Always in Inbox" is there
/// too, for a sender that is not a newsletter at all.
Future<void> unsubscribeFrom(
  BuildContext context,
  MailSource source,
  MailRow row, {
  required ValueChanged<String> onToast,
}) async {
  final l = AppLocalizations.of(context);
  final info = await source.unsubscribeInfo(row);
  if (!context.mounted) return;
  final choice = await showPiumaDialog<_Choice>(
    context,
    label: l.unsubscribeTitle(row.sender),
    builder: (context) => _Unsubscribe(row: row, info: info),
  );
  switch (choice) {
    case null:
      return;
    case _Choice.inbox:
      await source.setSenderZone(row.fromEmail, MailFolder.inbox);
      onToast(l.alwaysInInboxDone(row.sender));
    case _Choice.leave when info.kind == UnsubscribeKind.page:
      final uri = Uri.tryParse(info.address);
      if (uri != null) await openExternalLink(uri);
    case _Choice.leave:
      try {
        await source.unsubscribe(row);
        onToast(l.unsubscribeDone(row.sender));
      } catch (_) {
        onToast(l.unsubscribeFailed);
      }
  }
}

enum _Choice { leave, inbox }

class _Unsubscribe extends StatelessWidget {
  const _Unsubscribe({required this.row, required this.info});

  final MailRow row;
  final UnsubscribeInfo info;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final body = switch (info.kind) {
      UnsubscribeKind.oneClick => l.unsubscribeOneClick(row.sender),
      UnsubscribeKind.mail => l.unsubscribeMail(info.address),
      UnsubscribeKind.page => l.unsubscribePage,
      UnsubscribeKind.none => l.unsubscribeNone(row.sender),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.unsubscribeTitle(row.sender),
          style: PiumaType.subtitle.copyWith(color: c.fg),
        ),
        const SizedBox(height: PiumaSpace.s12),
        Text(body, style: PiumaType.body.copyWith(color: c.fg)),
        const SizedBox(height: PiumaSpace.s24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: PiumaSpace.s8,
          runSpacing: PiumaSpace.s8,
          children: [
            PiumaButton(
              label: l.alwaysInInbox,
              kind: PiumaButtonKind.tertiary,
              onPressed: () => Navigator.of(context).pop(_Choice.inbox),
            ),
            if (info.kind != UnsubscribeKind.none)
              PiumaButton(
                label: info.kind == UnsubscribeKind.page
                    ? l.unsubscribeOpen
                    : l.unsubscribeConfirm,
                onPressed: () => Navigator.of(context).pop(_Choice.leave),
              )
            else
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
          ],
        ),
      ],
    );
  }
}

/// An issue's cover picture (`ImagesToApprove` section 3): its first
/// photo, only from a sender whose images may load, fading in over
/// [fallback]; [fallback] alone otherwise.
class NewsletterPicture extends StatefulWidget {
  const NewsletterPicture({
    super.key,
    required this.source,
    required this.row,
    required this.radius,
    required this.fallback,
  });

  final MailSource source;
  final MailRow row;
  final double radius;
  final Widget fallback;

  @override
  State<NewsletterPicture> createState() => _NewsletterPictureState();
}

class _NewsletterPictureState extends State<NewsletterPicture> {
  late Future<Uint8List?> _bytes = _load();

  // Asked each time it shows, so a sender no longer trusted loses it;
  // the picture itself comes from the shared cache.
  Future<Uint8List?> _load() async {
    final url = await widget.source.newsletterCover(widget.row);
    if (url == null) return null;
    final bytes = await RemoteImages(widget.source).get(url);
    return bytes.isEmpty ? null : bytes;
  }

  @override
  void didUpdateWidget(NewsletterPicture old) {
    super.didUpdateWidget(old);
    if (old.row.key != widget.row.key) _bytes = _load();
  }

  @override
  Widget build(BuildContext context) {
    final instant = reduceMotion(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.fallback,
          FutureBuilder<Uint8List?>(
            future: _bytes,
            builder: (context, snap) {
              final bytes = snap.data;
              return AnimatedOpacity(
                opacity: bytes == null ? 0 : 1,
                duration: instant ? Duration.zero : PiumaMotion.enter,
                curve: PiumaMotion.curve,
                child: bytes == null
                    ? const SizedBox.expand()
                    : Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const SizedBox.expand(),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
