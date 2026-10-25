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
import '../widgets/links.dart';
import 'attach_preview.dart';
import 'vault.dart' show FilterPill, ZoneTile;
import 'risky_file.dart';

/// The board's filters: every file, or one kind.
enum FileFilter { all, media, documents, sheets }

/// How a file is sorted on the board.
enum FileSort { recent, largest }

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
}

/// Which filter a file is in, besides All.
FileFilter fileFilter(MailAttachment f) {
  final mime = f.mime.toLowerCase();
  final ext = _ext(f.name);
  if (mime.startsWith('image/') ||
      mime.startsWith('video/') ||
      mime.startsWith('audio/')) {
    return FileFilter.media;
  }
  if (const {'csv', 'tsv', 'xls', 'xlsx', 'ods', 'numbers'}.contains(ext) ||
      mime == 'text/csv' ||
      mime.contains('spreadsheet') ||
      mime.contains('ms-excel')) {
    return FileFilter.sheets;
  }
  return FileFilter.documents;
}

/// How a file's card draws its preview: the picture, a page (PDFs and
/// documents), a sheet, a slide, or an icon.
enum _Look { picture, page, sheet, slide, zip, calendar, email, other }

_Look _look(MailAttachment f) {
  final mime = f.mime.toLowerCase();
  final ext = _ext(f.name);
  if (mime.startsWith('image/')) return _Look.picture;
  if (mime == 'application/pdf' ||
      mime.contains('wordprocessing') ||
      mime == 'application/msword' ||
      const {
        'pdf',
        'doc',
        'docx',
        'docm',
        'odt',
        'rtf',
        'txt',
        'md',
        'pages',
      }.contains(ext)) {
    return _Look.page;
  }
  if (fileFilter(f) == FileFilter.sheets) return _Look.sheet;
  if (const {'ppt', 'pptx', 'pptm', 'odp', 'key'}.contains(ext) ||
      mime.contains('presentation') ||
      mime.contains('powerpoint')) {
    return _Look.slide;
  }
  if (const {'zip', '7z', 'rar', 'tar', 'gz', 'tgz'}.contains(ext) ||
      mime.contains('zip') ||
      mime.contains('compressed')) {
    return _Look.zip;
  }
  if (ext == 'ics' || mime == 'text/calendar') return _Look.calendar;
  if (ext == 'eml' || mime == 'message/rfc822') return _Look.email;
  return _Look.other;
}

/// Monday of [now]'s week, at midnight.
DateTime _weekStart(DateTime now) =>
    DateTime(now.year, now.month, now.day - (now.weekday - 1));

/// Files received this week: the sidebar's count and the phone tile's.
int newFiles(List<AttachedFile> files, DateTime now) {
  final start = _weekStart(now);
  return files.where((f) => !f.row.receivedAt.isBefore(start)).length;
}

/// The tile's line: "4 new", or "Nothing new".
String attachmentsStatus(AppLocalizations l, int fresh) =>
    fresh > 0 ? l.attachmentsNew(fresh) : l.attachmentsNoneNew;

/// "today", "yesterday", the weekday this week, else "Oct 3".
String fileWhen(AppLocalizations l, DateTime at, DateTime now, String locale) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return l.dayToday;
  if (days == 1) return l.dayYesterday;
  if (days < 7) return DateFormat.E(locale).format(at);
  return DateFormat.MMMd(locale).format(at);
}

/// The files to show, filtered, searched and sorted: by week when
/// recent, else one group, biggest first.
class FilesView {
  FilesView(
    List<AttachedFile> files,
    DateTime now, {
    this.filter = FileFilter.all,
    this.sort = FileSort.recent,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    bool matches(AttachedFile f) =>
        q.isEmpty ||
        f.file.name.toLowerCase().contains(q) ||
        f.row.fromName.toLowerCase().contains(q) ||
        f.row.fromEmail.toLowerCase().contains(q);
    final searched = files.where(matches).toList();
    for (final f in FileFilter.values) {
      counts[f] = f == FileFilter.all
          ? searched.length
          : searched.where((x) => fileFilter(x.file) == f).length;
    }
    final shown = [
      for (final f in searched)
        if (filter == FileFilter.all || fileFilter(f.file) == filter) f,
    ];
    if (sort == FileSort.largest) {
      shown.sort((a, b) => b.file.size.compareTo(a.file.size));
      thisWeek = shown;
      earlier = const [];
    } else {
      final start = _weekStart(now);
      thisWeek = [
        for (final f in shown)
          if (!f.row.receivedAt.isBefore(start)) f,
      ];
      earlier = [
        for (final f in shown)
          if (f.row.receivedAt.isBefore(start)) f,
      ];
    }
  }

  final FileFilter filter;
  final FileSort sort;

  /// How many files each filter has, the search applied.
  final counts = <FileFilter, int>{};

  /// With [FileSort.largest], every file shown, and [earlier] is empty.
  late final List<AttachedFile> thisWeek;
  late final List<AttachedFile> earlier;

  bool get isEmpty => thisWeek.isEmpty && earlier.isEmpty;
}

String _key(AttachedFile f) =>
    '${f.row.accountId}/${f.row.mailbox}/${f.row.uid}/${f.file.part}';

/// The files last read, per source and account: shown at once when
/// Attachments opens again, while they're read afresh.
final _lastFiles = Expando<Map<int?, List<AttachedFile>>>();

/// Loads the files and follows changes, for the desktop board and the
/// phone page.
mixin _Files<T extends StatefulWidget> on State<T> {
  MailSource get source;
  int? get account;
  ValueChanged<String> get onToast;
  ValueChanged<MailRow> get onOpen;
  DateTime Function() get now;

  List<AttachedFile>? files;
  StreamSubscription<void>? _changes;

  var filter = FileFilter.all;
  var sort = FileSort.recent;
  var query = '';

  /// The card whose actions show.
  String? selected;

  /// Previews asked for, by file, so each is fetched once.
  final _thumbs = <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    files = _lastFiles[source]?[account];
    _load();
    _changes = source.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await source.attachedFiles(account: account);
    (_lastFiles[source] ??= {})[account] = all;
    if (mounted) setState(() => files = all);
  }

  /// The engine makes previews of pictures, PDFs and office documents,
  /// and says None for the rest.
  Future<Uint8List?>? thumb(AttachedFile f) => switch (_look(f.file)) {
    _Look.picture ||
    _Look.page ||
    _Look.sheet ||
    _Look.slide => _thumbs.putIfAbsent(
      _key(f),
      () => source.attachmentThumb(f).catchError((_) => null),
    ),
    _ => null,
  };

  Color accountColor(AttachedFile f) {
    for (final a in source.accounts) {
      if (a.id == f.row.accountId) return a.color;
    }
    return PiumaTheme.of(context).muted;
  }

  String accountName(AttachedFile f) {
    for (final a in source.accounts) {
      if (a.id == f.row.accountId) return a.name;
    }
    return '';
  }

  void pick(AttachedFile f) => setState(() {
    final key = _key(f);
    selected = selected == key ? null : key;
  });

  /// `AttachPreview` over the board: a page on the phone, a panel on the
  /// desktop. Open email closes it first.
  void preview(AttachedFile f, {required bool desktop}) {
    final photos = AttachPreview.isPicture(f.file)
        ? (files ?? const <AttachedFile>[])
              .where(
                (o) =>
                    o.row.key == f.row.key && AttachPreview.isPicture(o.file),
              )
              .toList()
        : const <AttachedFile>[];
    AttachPreview.open(
      context,
      source: source,
      file: f,
      photos: photos,
      desktop: desktop,
      now: now,
      onDownload: download,
      onOpenEmail: onOpen,
    );
  }

  /// Saves the file in Downloads and opens it.
  Future<void> download(AttachedFile f) async {
    final l = AppLocalizations.of(context);
    try {
      final path = await source.saveAttachment(f.row, f.file);
      onToast(l.attachmentSaved(f.file.name));
      if (!mounted ||
          !await mayOpenFile(context, source, f.row, f.file, path)) {
        return;
      }
      await openLocalFile(path);
    } catch (_) {
      onToast(l.attachmentNotSaved(f.file.name));
    }
  }

  List<(FileFilter, String)> filters(AppLocalizations l) => [
    (FileFilter.all, l.attachmentsAll),
    (FileFilter.media, l.attachmentsMedia),
    (FileFilter.documents, l.attachmentsDocuments),
    (FileFilter.sheets, l.attachmentsSheets),
  ];

  /// The groups to draw: "This week" and "Earlier", or one unnamed.
  List<(String?, List<AttachedFile>)> groups(AppLocalizations l, FilesView v) =>
      v.sort == FileSort.largest
      ? [if (v.thisWeek.isNotEmpty) (null, v.thisWeek)]
      : [
          if (v.thisWeek.isNotEmpty) (l.attachmentsThisWeek, v.thisWeek),
          if (v.earlier.isNotEmpty) (l.attachmentsEarlier, v.earlier),
        ];

  /// What shows when there are no cards.
  String emptyLine(AppLocalizations l) => query.trim().isEmpty
      ? l.attachmentsEmpty
      : l.attachmentsNoMatch(query.trim());
}

/// `AttachBoard` on desktop: every file as a card in a grid, by type,
/// searched and sorted; a click shows Download and Open email.
class AttachmentBoard extends StatefulWidget {
  const AttachmentBoard({
    super.key,
    required this.source,
    required this.now,
    required this.onOpen,
    required this.onToast,
    this.account,
    this.initialQuery = '',
  });

  final MailSource source;
  final DateTime Function() now;
  final ValueChanged<MailRow> onOpen;
  final ValueChanged<String> onToast;
  final int? account;

  /// What "Search files or senders" starts with.
  final String initialQuery;

  @override
  State<AttachmentBoard> createState() => _AttachmentBoardState();
}

class _AttachmentBoardState extends State<AttachmentBoard>
    with _Files<AttachmentBoard> {
  @override
  MailSource get source => widget.source;

  @override
  int? get account => widget.account;

  @override
  ValueChanged<String> get onToast => widget.onToast;

  @override
  ValueChanged<MailRow> get onOpen => widget.onOpen;

  @override
  DateTime Function() get now => widget.now;

  late final _search = TextEditingController(text: widget.initialQuery);

  @override
  void initState() {
    query = widget.initialQuery;
    super.initState();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    final files = this.files;
    final view = FilesView(
      files ?? const [],
      now,
      filter: filter,
      sort: sort,
      query: query,
    );
    final sortLabel = sort == FileSort.largest
        ? l.attachmentsLargest
        : l.attachmentsRecent;
    return ColoredBox(
      color: c.bg,
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = PiumaSpace.s16;
          final inner = box.maxWidth - 96;
          final columns = ((inner + gap) / (240 + gap)).floor().clamp(1, 8);
          final width = (inner - gap * (columns - 1)) / columns;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(48, 40, 48, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l.folderAttachments,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.9,
                      color: c.fg,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.attachmentsSubtitle,
                  style: PiumaType.body.copyWith(color: c.muted),
                ),
                const SizedBox(height: 22),
                _Tools(
                  wide: inner >= 840,
                  children: [
                    _Segments(
                      label: l.attachmentsFilter,
                      items: [
                        for (final (f, label) in filters(l))
                          (
                            label,
                            view.counts[f] ?? 0,
                            f == filter,
                            () {
                              setState(() => filter = f);
                            },
                          ),
                      ],
                    ),
                    _SearchField(
                      controller: _search,
                      hint: l.attachmentsSearch,
                      label: l.attachmentsSearchLabel,
                      onChanged: (q) => setState(() => query = q),
                    ),
                    _SortButton(
                      label: sortLabel,
                      semanticLabel: l.attachmentsSortLabel(sortLabel),
                      onTap: () => setState(
                        () => sort = sort == FileSort.recent
                            ? FileSort.largest
                            : FileSort.recent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                if (files != null && view.isEmpty)
                  Text(
                    emptyLine(l),
                    style: PiumaType.body.copyWith(color: c.muted),
                  ),
                for (final (title, items) in groups(l, view)) ...[
                  if (title != null) _GroupLabel(title, items.length),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final f in items)
                        SizedBox(
                          width: width,
                          child: _FileCard(
                            file: f,
                            phone: false,
                            selected: selected == _key(f),
                            thumb: thumb(f),
                            dot: accountColor(f),
                            account: accountName(f),
                            meta: l.attachmentsMeta(
                              f.row.fromName.isNotEmpty
                                  ? f.row.fromName
                                  : f.row.fromEmail,
                              fileSize(f.file.size, locale: locale),
                              fileWhen(l, f.row.receivedAt, now, locale),
                            ),
                            onTap: () => AttachPreview.shows(f.file)
                                ? preview(f, desktop: true)
                                : pick(f),
                            onDownload: () => download(f),
                            onOpen: () => widget.onOpen(f.row),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// `AttachBoard` on the phone: two cards a row under filter pills; a tap
/// shows Download and Email under the card.
class PhoneAttachments extends StatefulWidget {
  const PhoneAttachments({
    super.key,
    required this.source,
    required this.now,
    required this.onBack,
    required this.onOpen,
    required this.onToast,
    this.account,
  });

  final MailSource source;
  final DateTime Function() now;
  final VoidCallback onBack;
  final ValueChanged<MailRow> onOpen;
  final ValueChanged<String> onToast;
  final int? account;

  @override
  State<PhoneAttachments> createState() => _PhoneAttachmentsState();
}

class _PhoneAttachmentsState extends State<PhoneAttachments>
    with _Files<PhoneAttachments> {
  @override
  MailSource get source => widget.source;

  @override
  int? get account => widget.account;

  @override
  ValueChanged<String> get onToast => widget.onToast;

  @override
  ValueChanged<MailRow> get onOpen => widget.onOpen;

  @override
  DateTime Function() get now => widget.now;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    final files = this.files;
    final view = FilesView(files ?? const [], now, filter: filter);
    Widget card(AttachedFile f) => _FileCard(
      file: f,
      phone: true,
      selected: selected == _key(f),
      thumb: thumb(f),
      dot: accountColor(f),
      account: accountName(f),
      meta:
          '${f.row.fromName.isNotEmpty ? f.row.fromName : f.row.fromEmail}'
          ' · ${fileSize(f.file.size, locale: locale)}',
      onTap: () =>
          AttachPreview.shows(f.file) ? preview(f, desktop: false) : pick(f),
      onDownload: () => download(f),
      onOpen: () => widget.onOpen(f.row),
    );
    final head = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Semantics(
          header: true,
          child: Text(
            l.folderAttachments,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.84,
              color: c.fg,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        child: Text(
          l.attachmentsSubtitle,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 14,
            color: c.muted,
          ),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Row(
          children: [
            for (final (f, label) in filters(l)) ...[
              FilterPill(
                label: label,
                count: view.counts[f] ?? 0,
                height: 36,
                selected: filter == f,
                onTap: () => setState(() => filter = f),
              ),
              const SizedBox(width: PiumaSpace.s8),
            ],
          ],
        ),
      ),
      if (files != null && view.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Text(
            emptyLine(l),
            style: PiumaType.body.copyWith(color: c.muted),
          ),
        ),
    ];
    // The rows of the list, each built when it shows: two cards a row,
    // the first few entering as before.
    const gap = 10.0;
    final rows = <Widget Function()>[for (final w in head) () => w];
    for (final (title, items) in groups(l, view)) {
      if (title != null) {
        rows.add(
          () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _GroupLabel(title, items.length),
          ),
        );
      }
      for (var i = 0; i < items.length; i += 2) {
        final pair = items.skip(i).take(2).toList();
        rows.add(
          () => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (j, f) in pair.indexed) ...[
                  if (j > 0) const SizedBox(width: gap),
                  Expanded(child: card(f)),
                ],
                if (pair.length == 1) ...[
                  const SizedBox(width: gap),
                  const Spacer(),
                ],
              ],
            ),
          ),
        );
      }
      rows.add(() => const SizedBox(height: 22 - gap));
    }
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
          child: ColoredBox(
            color: c.bg,
            // Built as they scroll into view: a mailbox can hold
            // hundreds of files, and building every card (and asking
            // for every picture) at once stalled the page as it opened.
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: rows.length,
              itemBuilder: (context, i) => rows[i](),
            ),
          ),
        ),
      ],
    );
  }
}

/// The filters on the left, search and sort on the right; one under the
/// other in a narrow window.
class _Tools extends StatelessWidget {
  const _Tools({required this.wide, required this.children});

  final bool wide;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => wide
      ? Row(
          children: [
            children.first,
            const Spacer(),
            for (final (i, w) in children.skip(1).indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              w,
            ],
          ],
        )
      : Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        );
}

/// "This week 4": a group's name and how many files it has.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: PiumaSpace.s12),
      child: Semantics(
        header: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.muted,
              ),
            ),
            const SizedBox(width: PiumaSpace.s8),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 12,
                color: c.muted.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The desktop filters, as a segmented control: label and count.
class _Segments extends StatelessWidget {
  const _Segments({required this.label, required this.items});

  final String label;
  final List<(String, int, bool, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      container: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (text, count, on, onTap)) in items.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Semantics(
                selected: on,
                child: PiumaPressable(
                  onTap: onTap,
                  semanticLabel: '$text, $count',
                  child: AnimatedContainer(
                    duration: instant ? Duration.zero : PiumaMotion.press,
                    curve: PiumaMotion.curve,
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: on ? c.surface : c.surface.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: on ? c.line : c.line.withValues(alpha: 0),
                      ),
                    ),
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            text,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 14,
                              fontWeight: on
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: on ? c.fg : c.muted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$count',
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 12,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: c.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Search files or senders": a small field that filters as you type.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      width: 220,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PiumaRadius.button),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          PiumaIconView(PiumaIcon.search, size: 15, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              textField: true,
              label: label,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 14,
                  color: c.fg,
                ),
                cursorColor: c.accent,
                decoration: InputDecoration.collapsed(
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 14,
                    color: c.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Recent ⌄": switches between newest first and biggest first.
class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        height: 36,
        padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PiumaRadius.button),
          border: Border.all(color: c.line),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(PiumaIcon.sort, size: 15, color: c.muted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 14,
                  color: c.fg,
                ),
              ),
              const SizedBox(width: 6),
              PiumaIconView(PiumaIcon.chevronDown, size: 14, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A file's card: its preview with the type, its name, where it came
/// from. Picked, it shows Download and Open email.
class _FileCard extends StatefulWidget {
  const _FileCard({
    required this.file,
    required this.phone,
    required this.selected,
    required this.thumb,
    required this.dot,
    required this.account,
    required this.meta,
    required this.onTap,
    required this.onDownload,
    required this.onOpen,
  });

  final AttachedFile file;
  final bool phone;
  final bool selected;
  final Future<Uint8List?>? thumb;

  /// The account's color, and its name for screen readers.
  final Color dot;
  final String account;
  final String meta;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onOpen;

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final f = widget.file;
    final phone = widget.phone;
    final from = f.row.fromName.isNotEmpty ? f.row.fromName : f.row.fromEmail;
    final locale = Localizations.localeOf(context).toLanguageTag();
    // A risky file says so in place of who sent it (`ProtectionToApprove`).
    final risk = riskNote(l, f.file);
    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PiumaRadius.card),
        boxShadow: widget.selected
            ? [BoxShadow(color: c.soft, spreadRadius: 3)]
            : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PiumaRadius.card),
        border: Border.all(color: widget.selected ? c.accent : c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            selected: widget.selected,
            child: PiumaPressable(
              onTap: widget.onTap,
              semanticLabel: l.attachmentsCardLabel(
                f.file.name,
                from,
                fileSize(f.file.size, locale: locale),
              ),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: phone ? 112 : 160,
                      child: _Preview(
                        file: f.file,
                        thumb: widget.thumb,
                        phone: phone,
                        mark: widget.dot,
                      ),
                    ),
                    Padding(
                      padding: phone
                          ? const EdgeInsets.fromLTRB(11, 9, 11, 10)
                          : const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: phone ? 13 : 14,
                              fontWeight: FontWeight.w500,
                              color: c.fg,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (risk != null)
                                PiumaIconView(
                                  PiumaIcon.warning,
                                  size: 12,
                                  color: c.warn,
                                )
                              else
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: widget.dot,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  risk ?? widget.meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: PiumaFonts.sans,
                                    fontSize: phone ? 12 : 13,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (phone && widget.selected)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _BarButton(
                        icon: PiumaIcon.download,
                        label: l.attachmentsDownload,
                        semanticLabel: l.attachmentsDownloadLabel(f.file.name),
                        onTap: widget.onDownload,
                      ),
                    ),
                    Container(width: 1, color: c.line),
                    Expanded(
                      child: _BarButton(
                        icon: PiumaIcon.mail,
                        label: l.attachmentsEmail,
                        semanticLabel: l.attachmentsEmailLabel(from),
                        onTap: widget.onOpen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (phone) return card;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        children: [
          card,
          if (_hover || widget.selected)
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                children: [
                  _SmallButton(
                    icon: PiumaIcon.download,
                    label: l.attachmentsDownload,
                    semanticLabel: l.attachmentsDownloadLabel(f.file.name),
                    onTap: widget.onDownload,
                  ),
                  const SizedBox(width: 6),
                  _SmallButton(
                    icon: PiumaIcon.mail,
                    label: l.attachmentsOpenEmail,
                    semanticLabel: l.attachmentsEmailLabel(from),
                    onTap: widget.onOpen,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// What the top of a card shows: the picture itself, or a sketch of a
/// page, a sheet or an archive, with the type in a corner.
/// A file's preview as the board draws it (a picture, a page with its
/// type, a box), for other places that show files: the sender card.
class FilePreview extends StatelessWidget {
  const FilePreview({
    super.key,
    required this.file,
    required this.thumb,
    required this.mark,
  });

  final MailAttachment file;
  final Future<Uint8List?>? thumb;

  /// The account's color, on a page's letterhead.
  final Color mark;

  @override
  Widget build(BuildContext context) =>
      _Preview(file: file, thumb: thumb, phone: true, mark: mark);
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.file,
    required this.thumb,
    required this.phone,
    required this.mark,
  });

  final MailAttachment file;
  final Future<Uint8List?>? thumb;
  final bool phone;

  /// The account's color, on a page's letterhead.
  final Color mark;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final look = _look(file);
    // The file's own first page or picture, once the engine has it; the
    // mockup's sketch until then, and for files it has none of.
    Widget real(Widget sketch, double width) => FutureBuilder<Uint8List?>(
      future: thumb,
      builder: (context, snap) => switch (snap.data) {
        final bytes? => _Paper(bytes: bytes, width: width),
        null => sketch,
      },
    );
    final Widget sketch = switch (look) {
      _Look.picture => FutureBuilder<Uint8List?>(
        future: thumb,
        builder: (context, snap) => switch (snap.data) {
          final bytes? => Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
          null => _Badge(icon: PiumaIcon.image),
        },
      ),
      _Look.page => real(
        _Page(width: phone ? 74 : 100, mark: mark),
        phone ? 74 : 100,
      ),
      _Look.sheet => real(_Sheet(width: phone ? 120 : 160), phone ? 120 : 160),
      _Look.slide => real(_Badge(icon: PiumaIcon.file), phone ? 120 : 160),
      _Look.zip => _Badge(icon: PiumaIcon.fileZip),
      _Look.calendar => _Badge(icon: PiumaIcon.calendar),
      _Look.email => _Badge(icon: PiumaIcon.mail),
      _Look.other => _Badge(icon: PiumaIcon.file),
    };
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: look == _Look.picture ? c.placeholder : c.bg,
        border: Border(
          bottom: BorderSide(
            color: look == _Look.picture ? c.line.withValues(alpha: 0) : c.line,
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          sketch,
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                fileBadge(file.name, file.mime),
                style: TextStyle(
                  fontFamily: PiumaFonts.mono,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  color: c.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A file's own preview on a card: its first page as paper, [width]
/// wide and running off the bottom, as the sketch of a page does.
class _Paper extends StatelessWidget {
  const _Paper({required this.bytes, required this.width});

  final Uint8List bytes;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: 0,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Container(
        width: width,
        margin: const EdgeInsets.only(top: 18),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.page,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          border: Border.all(color: c.line),
        ),
        child: Image.memory(
          bytes,
          width: width,
          fit: BoxFit.fitWidth,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          // Enough for the densest screens, and no more kept in memory.
          cacheWidth: (width * 3).round(),
        ),
      ),
    );
  }
}

/// A 48-pixel square with an icon, in the middle of the preview.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final PiumaIcon icon;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Center(
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: c.page,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
          border: Border.all(color: c.line),
        ),
        child: Center(child: PiumaIconView(icon, size: 22, color: c.muted)),
      ),
    );
  }
}

/// A bar of a sketch.
Widget _bar(Color color, {double? width, double height = 4}) => Container(
  width: width,
  height: height,
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(height / 2),
  ),
);

/// The top of a document's first page: letterhead, lines, a table.
class _Page extends StatelessWidget {
  const _Page({required this.width, required this.mark});

  final double width;
  final Color mark;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    Widget row(double flex) => Row(
      children: [
        Expanded(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: flex,
            child: _bar(c.rule),
          ),
        ),
        const SizedBox(width: 6),
        _bar(c.rule, width: 16),
      ],
    );
    // Taller than the preview: it runs off the bottom, as a page would.
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: 0,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Container(
        width: width,
        margin: const EdgeInsets.only(top: 18),
        constraints: const BoxConstraints(minHeight: 200),
        padding: const EdgeInsets.fromLTRB(11, 12, 11, 12),
        decoration: BoxDecoration(
          color: c.page,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: mark,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 5),
                _bar(c.muted.withValues(alpha: 0.55), width: 34, height: 5),
              ],
            ),
            const SizedBox(height: 9),
            FractionallySizedBox(widthFactor: 0.7, child: _bar(c.rule)),
            const SizedBox(height: 5),
            FractionallySizedBox(widthFactor: 0.52, child: _bar(c.rule)),
            const SizedBox(height: 10),
            Container(height: 1, color: c.rule),
            const SizedBox(height: 7),
            row(1),
            const SizedBox(height: 5),
            row(1),
            const SizedBox(height: 5),
            row(0.7),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _bar(c.fg.withValues(alpha: 0.45), width: 26, height: 5),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sheet's first rows: a green header, figures on the right, a total.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    const label = [0.6, 0.75, 0.5, 0.65, 0.0];
    const figure = [0.5, 0.4, 0.55, 0.45, 0.6];
    Widget cell(Widget? child, {required int flex, bool right = false}) =>
        Expanded(
          flex: flex,
          child: Container(
            height: 15,
            color: c.page,
            padding: EdgeInsets.only(left: right ? 0 : 5, right: right ? 5 : 0),
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            child: child,
          ),
        );
    Widget gapped(List<Widget> cells) => Row(
      children: [
        for (final (i, w) in cells.indexed) ...[
          if (i > 0) const SizedBox(width: 1),
          w,
        ],
      ],
    );
    // Taller than the preview: it runs off the bottom, as a page would.
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: 0,
      minHeight: 0,
      maxHeight: double.infinity,
      child: Container(
        width: width,
        margin: const EdgeInsets.only(top: 18),
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: c.rule,
          borderRadius: BorderRadius.circular(5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            gapped([
              for (final flex in [16, 10, 10, 10])
                Expanded(
                  flex: flex,
                  child: Container(height: 16, color: c.okSoft),
                ),
            ]),
            for (var r = 0; r < 5; r++) ...[
              const SizedBox(height: 1),
              gapped([
                cell(
                  label[r] == 0
                      ? null
                      : FractionallySizedBox(
                          widthFactor: label[r],
                          child: _bar(c.rule, height: 3),
                        ),
                  flex: 16,
                ),
                cell(null, flex: 10),
                cell(null, flex: 10),
                cell(
                  FractionallySizedBox(
                    widthFactor: figure[r],
                    child: r == 4
                        ? _bar(c.ok)
                        : _bar(c.muted.withValues(alpha: 0.45), height: 3),
                  ),
                  flex: 10,
                  right: true,
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Download or Open email on a desktop card, on top of its preview.
class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PiumaRadius.button),
          border: Border.all(color: c.line),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(icon, size: 14, color: c.fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Download or Email in the bar under a picked phone card.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: SizedBox(
        height: 44,
        child: ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PiumaIconView(icon, size: 15, color: c.accentText),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: c.accentText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Attachments tile at the top of the phone list (`ZonesToApprove`):
/// files received this week.
class AttachmentsTile extends StatelessWidget {
  const AttachmentsTile({super.key, required this.fresh, required this.onTap});

  /// Files received this week.
  final int fresh;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = attachmentsStatus(l, fresh);
    return ZoneTile(
      icon: PiumaIcon.paperclip,
      title: l.folderAttachments,
      line: status,
      semanticLabel: l.attachmentsTileLabel(status),
      onTap: onTap,
    );
  }
}
