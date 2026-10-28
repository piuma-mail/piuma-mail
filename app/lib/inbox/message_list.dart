import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../compose/remind_me.dart';
import '../design/icons.dart';
import '../design/look.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import 'service_states.dart';
import '../mail/mail_source.dart';
import 'labels.dart';
import 'phone_parts.dart' show ComposeFab;
import 'pictures.dart';
import 'sections.dart';
import 'snooze.dart';
import 'swipe.dart';
import 'waiting.dart';

/// Row and header heights are fixed, so a 50,000-message inbox lays out
/// without measuring rows it does not show.
const double kRowExtent = 110;

/// A row with a chip of `Main` ("4 messages", "2 attachments"): taller.
const double kConversationRowExtent = kRowExtent + 28;
const double kHeaderExtent = 36;

/// What compact rows (Settings › Appearance) leave out, above and below.
const double _compactTrim = 5;

/// One line of preview.
const double _previewLine = 20;

/// [kRowExtent] or [kConversationRowExtent] as Settings › Appearance
/// makes them.
/// [oneLine]: the row has one line under the subject whatever the look
/// says ("No reply yet" in Waiting).
double rowExtent(Appearance look, {bool chip = false, bool oneLine = false}) =>
    (chip ? kConversationRowExtent : kRowExtent) -
    (look.compact ? 2 * _compactTrim : 0) -
    (look.previewLines == 1 || oneLine ? _previewLine : 0);
const int _pageSize = 100;

/// Each list as last read, per source: shown at once when it opens
/// again.
final _lastLists =
    Expando<
      Map<
        Object,
        ({
          List<InboxSection> sections,
          List<MailRow> first,
          List<OutboxItem> outbox,
          List<MailRow> snoozed,
          List<MailRow> reminded,
        })
      >
    >();

/// The unified inbox: section headers ("Today", "Yesterday"…) and rows,
/// loaded from the database a page at a time as they scroll into view.
class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.source,
    required this.selected,
    required this.onSelect,
    required this.now,
    this.folder = MailFolder.inbox,
    this.account,
    this.mailbox,
    this.tab,
    this.unread = false,
    this.group,
    this.picked = const {},
    this.onPick,
    this.onTotal,
    this.phone = false,
    this.onSwipe,
    this.onSnoozeSwipe,
    this.onOutbox,
    this.swipeAs,
    this.leftSwipeAs,
    this.top = const [],
    this.swipeHint = false,
    this.onNoticeArchive,
  });

  /// Slivers above the rows that scroll with them: the phone's folding
  /// header and what sits under it (`HomeToApprove`, variant 2).
  final List<Widget> top;

  /// Archives an entire collapsed notice run, with the usual Undo.
  final ValueChanged<List<MailRow>>? onNoticeArchive;

  /// "Swipe right to archive, left to snooze" under the rows, as the
  /// tablet's list has it (`Tablet`).
  final bool swipeHint;

  /// What a right swipe does, when not Archive: Stop waiting.
  final ({PiumaIcon icon, String label})? swipeAs;

  /// What a left swipe does, when not Snooze: Remind me, in Waiting,
  /// which leaves the row where it is.
  final ({PiumaIcon icon, String label})? leftSwipeAs;

  /// A swipe to the left on a phone row snoozes it (`PhoneSwipe`).
  final ValueChanged<MailRow>? onSnoozeSwipe;

  /// A click on a message waiting in the outbox, shown above the inbox
  /// while something waits (`Outbox`).
  final ValueChanged<OutboxItem>? onOutbox;

  final MailSource source;

  /// The phone layout of `Phone`: rows edge to edge, larger avatars.
  final bool phone;

  /// A swipe to the right on a phone row archives it (`PhoneSwipe`).
  final ValueChanged<MailRow>? onSwipe;

  /// Which list: the unified inbox, Sent or Archive.
  final MailFolder folder;

  /// Only this account's rows; every account's when null.
  final int? account;

  /// One of [account]'s own folders in place of [folder].
  final String? mailbox;

  /// In the inbox, the half its tabs show; the whole inbox when null.
  final InboxTab? tab;

  /// In the inbox, only the conversations with something unread (the
  /// Unread switch of `FiltersToApprove`).
  final bool unread;

  /// In the inbox, one group's mail, or one of its addresses'. Rows
  /// written to an alias then say which.
  final GroupScope? group;
  final Object? selected;
  final ValueChanged<MailRow> onSelect;

  /// Keys of the rows picked for an action on several at once.
  final Set<Object> picked;

  /// Picks or unpicks rows: Cmd/Ctrl+click, Shift+click for a range, a
  /// click on the avatar, or any click while something is picked. Null
  /// turns picking off.
  final void Function(List<MailRow> rows, bool picked)? onPick;

  /// How many rows the list has, each time it loads.
  final ValueChanged<int>? onTotal;

  /// The clock used for sections and times (fixed in screenshots).
  final DateTime Function() now;

  @override
  State<MessageList> createState() => MessageListState();
}

class MessageListState extends State<MessageList>
    with SingleTickerProviderStateMixin {
  final _expandedNotices = <Object>{};

  bool get _groupNotices =>
      widget.folder == MailFolder.inbox &&
      widget.mailbox == null &&
      widget.tab == InboxTab.notifications;

  bool _sameNotice(MailRow? a, MailRow? b) =>
      _groupNotices &&
      a != null &&
      b != null &&
      !widget.source.byPerson(a) &&
      !widget.source.byPerson(b) &&
      !a.isConversation &&
      !b.isConversation &&
      sameNotice(a, b);

  /// The rows of the day section holding [index], as `[start, end)`: a run
  /// of notices never crosses a section header.
  (int, int) _sectionBounds(int index) {
    var start = 0;
    for (final section in _sections) {
      final end = start + section.count;
      if (index < end) return (start, end);
      start = end;
    }
    return (start, start);
  }

  bool _hiddenNotice(int index) =>
      index > _sectionBounds(index).$1 &&
      _sameNotice(_loadedRow(index - 1), _loadedRow(index));

  List<MailRow> _noticeRun(int index) {
    final first = _loadedRow(index);
    if (first == null) return const [];
    final rows = [first];
    if (!_groupNotices) return rows;
    final end = _sectionBounds(index).$2;
    for (var next = index + 1; next < end; next++) {
      final row = _loadedRow(next);
      if (!_sameNotice(first, row)) break;
      rows.add(row!);
    }
    return rows;
  }

  /// Asked once whether the swipe hint is still to play.
  bool _hintAsked = false;

  /// The row that shows the swipe hint: the first one drawn.
  Object? _hintRow;

  void _askHint(MailRow row) {
    if (_hintAsked) return;
    _hintAsked = true;
    widget.source.takeSwipeHint().then((yes) {
      if (yes && mounted) setState(() => _hintRow = row.key);
    });
  }

  List<InboxSection> _sections = const [];
  List<OutboxItem> _outbox = const [];

  /// What is snoozed, for "Show Snoozed" when the inbox is empty.
  List<MailRow> _snoozed = const [];

  /// Sent mail nobody replied to, back as "Remind me" asked: on top of
  /// the inbox, under the first header (`RemindAwayPrintToApprove`).
  List<MailRow> _reminded = const [];

  /// What that header says, as of the last read: "Today".
  String _remindedHeader = '';
  final _pages = <int, List<MailRow>>{};
  final _loading = <int>{};
  StreamSubscription<void>? _changes;
  int _generation = 0;
  bool _loaded = false;

  /// Where the last click landed, for Shift+click ranges.
  int? _anchor;

  /// Rows folding away as they leave, until the list is read again.
  Set<Object> _folding = const {};
  late final _fold = AnimationController(
    vsync: this,
    duration: PiumaMotion.collapse,
  )..addListener(() => setState(() {}));

  /// How open a folding row still is: 1 open, 0 gone.
  double get _open => 1 - PiumaMotion.curve.transform(_fold.value);

  /// Folds the rows of [keys] shut, before they leave the list; at once
  /// with reduce motion.
  Future<void> fold(Iterable<Object> keys) async {
    // Under a message on the phone the list waits still: nothing to see.
    if (reduceMotion(context) || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    setState(() => _folding = keys.toSet());
    await _fold.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _fromMemory();
    _changes = widget.source.changes.listen((_) => _changed());
  }

  /// Which list this is.
  Object get _identity => (
    widget.folder,
    widget.account,
    widget.mailbox,
    widget.tab,
    widget.unread,
    widget.group,
  );

  /// The list as last read, when it was: back to the Inbox or another
  /// folder seen before, its rows show at once while read afresh,
  /// instead of an empty list for the moment a read takes.
  void _fromMemory() {
    final last = _lastLists[widget.source]?[_identity];
    if (last == null) return;
    _loaded = true;
    _sections = last.sections;
    _outbox = last.outbox;
    _snoozed = last.snoozed;
    _reminded = last.reminded;
    _pages[0] = last.first;
    _shown = _identity;
  }

  /// What the rows in [_pages] are of.
  Object? _shown;

  /// The language the sections were named in.
  String? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read again only for a new language: the labels, the theme or a
    // message opening above (tickers off) change nothing in the rows,
    // and reading again each time made the list blink.
    final locale = Localizations.localeOf(context).toLanguageTag();
    if (locale == _locale) return;
    _locale = locale;
    reload();
  }

  /// Reads running, and whether mail changed again meanwhile: changes
  /// come faster than a read while mail downloads, so they fold into one
  /// more read after the running one instead of each starting over.
  int _reading = 0;
  bool _changedAgain = false;

  void _changed() {
    if (_reading > 0) {
      _changedAgain = true;
      return;
    }
    reload();
  }

  @override
  void didUpdateWidget(MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder != widget.folder ||
        oldWidget.account != widget.account ||
        oldWidget.mailbox != widget.mailbox ||
        oldWidget.tab != widget.tab ||
        oldWidget.unread != widget.unread ||
        oldWidget.group != widget.group) {
      _anchor = null;
      // Another list: its rows come in on their own, never under the
      // old ones (Inbox rows under "Archive").
      _loaded = false;
      _sections = const [];
      _outbox = const [];
      _snoozed = const [];
      _reminded = const [];
      _pages.clear();
      _loading.clear();
      _fromMemory();
      reload();
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    _fold.dispose();
    super.dispose();
  }

  /// Re-reads the sections and drops cached rows.
  Future<void> reload() async {
    _reading++;
    try {
      await _read();
    } finally {
      _reading--;
      if (_reading == 0 && _changedAgain && mounted) {
        _changedAgain = false;
        reload();
      }
    }
  }

  Future<void> _read() async {
    final gen = ++_generation;
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final plan = SectionPlan(widget.now(), l, locale);
    final folder = widget.folder;
    final account = widget.account;
    if (folder == MailFolder.waiting || folder == MailFolder.label) {
      // Newest first, in one list with no headers.
      final all = await widget.source.page(
        0,
        1 << 30,
        folder: folder,
        account: account,
        mailbox: widget.mailbox,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _loaded = true;
        _outbox = const [];
        _reminded = const [];
        _sections = [if (all.isNotEmpty) InboxSection('', all.length)];
        _pages.clear();
        for (var i = 0; i * _pageSize < all.length; i++) {
          _pages[i] = all.skip(i * _pageSize).take(_pageSize).toList();
        }
        _loading.clear();
        _folding = const {};
      });
      widget.onTotal?.call(total);
      return;
    }
    if (folder == MailFolder.snoozed) {
      // Soonest back first, by when they come back.
      final all = await widget.source.page(
        0,
        1 << 30,
        folder: folder,
        account: account,
      );
      if (!mounted || gen != _generation) return;
      final now = widget.now();
      final today = DateTime(now.year, now.month, now.day);
      final counts = [0, 0, 0];
      for (final r in all) {
        final at = r.snoozedUntil;
        final days = at == null
            ? 2
            : DateTime(at.year, at.month, at.day).difference(today).inDays;
        counts[days.clamp(0, 2)]++;
      }
      setState(() {
        _loaded = true;
        _outbox = const [];
        _reminded = const [];
        _sections = [
          for (final (i, label) in [
            l.sectionToday,
            l.sectionTomorrow,
            l.sectionLater,
          ].indexed)
            if (counts[i] > 0) InboxSection(label, counts[i]),
        ];
        _pages.clear();
        for (var i = 0; i * _pageSize < all.length; i++) {
          _pages[i] = all.skip(i * _pageSize).take(_pageSize).toList();
        }
        _loading.clear();
        _folding = const {};
      });
      widget.onTotal?.call(total);
      return;
    }
    final counts = await widget.source.countsBetween(
      plan.edges,
      folder: folder,
      account: account,
      mailbox: widget.mailbox,
      tab: widget.tab,
      unread: widget.unread,
      group: widget.group,
    );
    if (!mounted || gen != _generation) return;
    // Fetch the first page before swapping, so the list never flashes.
    final first = await widget.source.page(
      0,
      _pageSize,
      folder: folder,
      account: account,
      mailbox: widget.mailbox,
      tab: widget.tab,
      unread: widget.unread,
      group: widget.group,
    );
    if (!mounted || gen != _generation) return;
    // And the pages scrolled to, so the rows on screen don't blink to
    // placeholders and back. Only when the list stays the same one.
    final same =
        _loaded &&
        _shown ==
            (
              folder,
              account,
              widget.mailbox,
              widget.tab,
              widget.unread,
              widget.group,
            );
    final more = <int, List<MailRow>>{};
    if (same) {
      for (final page in [..._pages.keys.where((p) => p > 0)]..sort()) {
        if (more.length == 3) break;
        more[page] = await widget.source.page(
          page * _pageSize,
          _pageSize,
          folder: folder,
          account: account,
          mailbox: widget.mailbox,
          tab: widget.tab,
          unread: widget.unread,
          group: widget.group,
        );
        if (!mounted || gen != _generation) return;
      }
    }
    // Under Unread only unread mail: no outbox, reminders or snoozed.
    final everyone =
        widget.mailbox == null && widget.group == null && !widget.unread;
    final outbox = folder == MailFolder.inbox && everyone
        ? await widget.source.outbox(account)
        : const <OutboxItem>[];
    if (!mounted || gen != _generation) return;
    final reminded =
        folder == MailFolder.inbox &&
            everyone &&
            widget.tab != InboxTab.notifications
        ? await widget.source.reminded(widget.now(), account: account)
        : const <MailRow>[];
    if (!mounted || gen != _generation) return;
    final snoozed = first.isEmpty && folder == MailFolder.inbox && everyone
        ? await widget.source.page(
            0,
            50,
            folder: MailFolder.snoozed,
            account: account,
          )
        : const <MailRow>[];
    if (!mounted || gen != _generation) return;
    setState(() {
      _loaded = true;
      _outbox = outbox;
      _snoozed = snoozed;
      _reminded = reminded;
      _remindedHeader = l.sectionToday;
      _sections = plan.sections(counts);
      _aliases.clear();
      _pages
        ..clear()
        ..[0] = first
        ..addAll(more);
      _shown = (
        folder,
        account,
        widget.mailbox,
        widget.tab,
        widget.unread,
        widget.group,
      );
      _loading.clear();
      _folding = const {};
    });
    (_lastLists[widget.source] ??= {})[_shown!] = (
      sections: _sections,
      first: first,
      outbox: outbox,
      snoozed: snoozed,
      reminded: reminded,
    );
    widget.onTotal?.call(total);
  }

  /// The aliases rows were written to, asked once per row.
  final _aliases = <Object, String?>{};

  /// In a group's inbox, the alias [row] was written to; on the phone,
  /// as on `GroupsPhone`, every row says it, the account's own address
  /// for mail that went to no alias.
  String? _writtenTo(MailRow row) => widget.group == null
      ? null
      : _aliases.putIfAbsent(
          row.key,
          () =>
              widget.source.writtenTo(row) ??
              (widget.phone
                  ? widget.source.accounts
                        .where((a) => a.id == row.accountId)
                        .firstOrNull
                        ?.email
                  : null),
        );

  /// Whether [row] has a line of chips under its preview.
  bool _chips(MailRow row) =>
      _tag(row, null, widget.phone) != null ||
      _writtenTo(row) != null ||
      row.labels.any(_labelled.contains);

  /// The keywords that are labels, as of the last build.
  Set<String> _labelled = const {};

  /// How many rows the list has.
  int get total => _sections.fold(0, (sum, s) => sum + s.count);

  /// Every row of the list, for Cmd/Ctrl+A.
  Future<List<MailRow>> allRows() => widget.source.page(
    0,
    total,
    folder: widget.folder,
    account: widget.account,
    mailbox: widget.mailbox,
    tab: widget.tab,
    unread: widget.unread,
    group: widget.group,
  );

  void _tap(int index, MailRow row) {
    final keys = HardwareKeyboard.instance;
    final onPick = widget.onPick;
    if (onPick != null) {
      if (keys.isShiftPressed && _anchor != null) {
        final from = math.min(_anchor!, index);
        final to = math.max(_anchor!, index);
        onPick([for (var i = from; i <= to; i++) ?_loadedRow(i)], true);
        return;
      }
      if (keys.isMetaPressed ||
          keys.isControlPressed ||
          widget.picked.isNotEmpty) {
        _toggle(index, row);
        return;
      }
    }
    _anchor = index;
    widget.onSelect(row);
  }

  void _toggle(int index, MailRow row) {
    _anchor = index;
    widget.onPick?.call([row], !widget.picked.contains(row.key));
  }

  /// The row [step] places after [row] among the rows loaded (1 the next,
  /// -1 the one before), for moving between open emails; null at either
  /// end, past what is loaded, or for a row on its way out.
  MailRow? near(MailRow row, int step) {
    for (final MapEntry(key: page, value: rows) in _pages.entries) {
      final i = rows.indexWhere((r) => r.key == row.key);
      if (i < 0) continue;
      final index = page * _pageSize + i + step;
      if (index < 0) return null;
      final next = _loadedRow(index);
      return next == null || _folding.contains(next.key) ? null : next;
    }
    return null;
  }

  /// The row at [index] when its page is here, without loading it.
  MailRow? _loadedRow(int index) {
    final rows = _pages[index ~/ _pageSize];
    final i = index % _pageSize;
    return rows != null && i < rows.length ? rows[i] : null;
  }

  MailRow? _row(int index) {
    final page = index ~/ _pageSize;
    final rows = _pages[page];
    if (rows != null) {
      final i = index % _pageSize;
      return i < rows.length ? rows[i] : null;
    }
    if (_loading.add(page)) {
      final gen = _generation;
      widget.source
          .page(
            page * _pageSize,
            _pageSize,
            folder: widget.folder,
            account: widget.account,
            mailbox: widget.mailbox,
            tab: widget.tab,
            unread: widget.unread,
            group: widget.group,
          )
          .then((rows) {
            if (!mounted || gen != _generation) return;
            setState(() {
              _pages[page] = rows;
              _loading.remove(page);
            });
          });
    }
    return null;
  }

  /// Whether [s] goes without its header: one with no label (Waiting),
  /// or the first one when the reminded rows above already have it.
  bool _headless(InboxSection s) =>
      s.label.isEmpty ||
      (_reminded.isNotEmpty &&
          identical(s, _sections.first) &&
          s.label == _remindedHeader);

  /// Maps a list position to a header or a row.
  ({String? header, int row}) _item(int index) {
    var rowBase = 0;
    for (final s in _sections) {
      // A section with no label has no header (Waiting).
      if (!_headless(s)) {
        if (index == 0) return (header: s.label, row: -1);
        index -= 1;
      }
      if (index < s.count) return (header: null, row: rowBase + index);
      index -= s.count;
      rowBase += s.count;
    }
    return (header: null, row: -1);
  }

  int get _itemCount =>
      _sections.fold(0, (sum, s) => sum + (_headless(s) ? 0 : 1) + s.count);

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    _labelled = {for (final l in LabelScope.of(context)) l.keyword};
    if (_loaded &&
        _itemCount == 0 &&
        _outbox.isEmpty &&
        _reminded.isEmpty &&
        widget.folder == MailFolder.inbox &&
        widget.mailbox == null) {
      // Nothing to read; during a first download the rows are on the way.
      final empty = ValueListenableBuilder<SyncStatus>(
        valueListenable: widget.source.status,
        builder: (context, s, _) => s.phase == SyncPhase.downloading
            ? SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  children: [
                    for (var i = 0; i < kSyncPlaceholders; i++)
                      SyncPlaceholder(index: i, phone: widget.phone),
                  ],
                ),
              )
            : PiumaEnter(
                child: AllCaughtUp(
                  snoozed: _snoozed,
                  accountOf: _account,
                  now: widget.now,
                  onOpen: widget.onSelect,
                ),
              ),
      );
      return _underTop(empty, fill: true);
    }
    if (_loaded &&
        _itemCount == 0 &&
        (widget.folder != MailFolder.inbox || widget.mailbox != null)) {
      final c = PiumaTheme.of(context);
      return _underTop(
        Padding(
          padding: EdgeInsets.fromLTRB(widget.phone ? 20 : 22, 18, 22, 16),
          child: Text(
            AppLocalizations.of(context).emptyFolder,
            style: PiumaType.small.copyWith(color: c.muted),
          ),
        ),
      );
    }
    final l = AppLocalizations.of(context);
    final look = PiumaLook.of(context);
    return CustomScrollView(
      slivers: [
        ...widget.top,
        if (_outbox.isNotEmpty)
          SliverPadding(
            padding: widget.phone
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList.list(
              children: [
                _SectionHeader(
                  l.outboxHeader(_outbox.length),
                  phone: widget.phone,
                ),
                for (final o in _outbox)
                  OutboxTile(
                    item: o,
                    now: widget.now(),
                    phone: widget.phone,
                    onTap: widget.onOutbox == null
                        ? null
                        : () => widget.onOutbox!(o),
                  ),
              ],
            ),
          ),
        if (_reminded.isNotEmpty)
          SliverPadding(
            padding: widget.phone
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList.list(
              children: [
                _SectionHeader(
                  _remindedHeader.isEmpty ? l.sectionToday : _remindedHeader,
                  phone: widget.phone,
                ),
                for (final row in _reminded)
                  InboxRowTile(
                    key: ValueKey(('reminded', row.key)),
                    row: row,
                    account: _account(row.accountId),
                    time: rowTime(row.remindAt ?? now, now, locale),
                    noReply: noReplyLine(row, now, l),
                    selected:
                        widget.picked.isEmpty && row.key == widget.selected,
                    phone: widget.phone,
                    onTap: () => widget.onSelect(row),
                  ),
              ],
            ),
          ),
        SliverPadding(
          padding: widget.phone
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverVariedExtentList.builder(
            key: ValueKey(look),
            itemCount: _itemCount,
            itemExtentBuilder: (index, _) {
              final item = _item(index);
              if (item.header != null) return kHeaderExtent;
              if (_hiddenNotice(item.row)) return 0;
              final run = _noticeRun(item.row);
              if (run.length > 1) {
                final extent = rowExtent(look, chip: true);
                return extent +
                    (_expandedNotices.contains(run.first.key)
                        ? run.fold<double>(
                            0,
                            (sum, r) => sum + rowExtent(look, chip: _chips(r)),
                          )
                        : 0);
              }
              final row = _loadedRow(item.row);
              final extent = rowExtent(
                look,
                chip: row != null && _chips(row),
                oneLine: widget.folder == MailFolder.waiting,
              );
              return row != null && _folding.contains(row.key)
                  ? extent * _open
                  : extent;
            },
            itemBuilder: (context, index) {
              final item = _item(index);
              if (item.header != null) {
                return _SectionHeader(item.header!, phone: widget.phone);
              }
              if (_hiddenNotice(item.row)) return const SizedBox.shrink();
              final row = _row(item.row);
              if (row == null) return const _RowPlaceholder();
              final run = _noticeRun(item.row);
              if (_groupNotices &&
                  run.isNotEmpty &&
                  item.row + run.length < _sectionBounds(item.row).$2) {
                // Ask for the boundary page too: a run may continue there.
                _row(item.row + run.length);
              }
              if (run.length > 1) {
                final expanded = _expandedNotices.contains(row.key);
                final picked = run.every((r) => widget.picked.contains(r.key));
                void toggle() => widget.onPick?.call(run, !picked);
                final range =
                    '${DateFormat.MMMd(locale).format(run.last.receivedAt)} – '
                    '${DateFormat.MMMd(locale).format(run.first.receivedAt)}';
                final summary = InboxRowTile(
                  row: row.withSeen(run.every((r) => r.seen)),
                  account: _account(row.accountId),
                  time: rowTime(row.receivedAt, now, locale),
                  selected: false,
                  picked: picked,
                  phone: widget.phone,
                  picking: widget.phone && widget.picked.isNotEmpty,
                  noticeCount: run.length,
                  noticeRange: range,
                  expandedNotices: expanded,
                  onTap: () {
                    if (widget.picked.isNotEmpty) {
                      toggle();
                      return;
                    }
                    setState(
                      () => expanded
                          ? _expandedNotices.remove(row.key)
                          : _expandedNotices.add(row.key),
                    );
                  },
                  onPick: widget.onPick == null ? null : toggle,
                  onLongPress: widget.onPick == null ? null : toggle,
                );
                final archive = widget.onNoticeArchive;
                return Column(
                  children: [
                    SizedBox(
                      height: rowExtent(look, chip: true),
                      child:
                          archive == null ||
                              widget.onSwipe == null ||
                              widget.picked.isNotEmpty
                          ? summary
                          : SwipeToArchive(
                              key: ValueKey(('notice', row.key)),
                              label: l.archive,
                              snoozeLabel: l.actionSnooze,
                              onArchive: () => archive(run),
                              child: summary,
                            ),
                    ),
                    if (expanded)
                      for (final notice in run)
                        SizedBox(
                          height: rowExtent(look, chip: _chips(notice)),
                          child: InboxRowTile(
                            row: notice,
                            account: _account(notice.accountId),
                            time: DateFormat.MMMd(locale)
                                .add_Hm()
                                .format(notice.receivedAt),
                            phone: widget.phone,
                            selected: widget.selected == notice.key,
                            picked: widget.picked.contains(notice.key),
                            writtenTo: _writtenTo(notice),
                            onTap: () =>
                                _tap(item.row + run.indexOf(notice), notice),
                            onPick: widget.onPick == null
                                ? null
                                : () => _toggle(
                                    item.row + run.indexOf(notice),
                                    notice,
                                  ),
                          ),
                        ),
                  ],
                );
              }
              final tile = InboxRowTile(
                row: row,
                account: _account(row.accountId),
                time: row.folder == MailFolder.snoozed
                    ? snoozedRowTime(row.snoozedUntil, now, l, locale)
                    : widget.folder == MailFolder.waiting
                    ? waitingRowTime(row.receivedAt, now, l)
                    : rowTime(row.receivedAt, now, locale),
                waiting: widget.folder == MailFolder.waiting,
                selected: widget.picked.isEmpty && row.key == widget.selected,
                picked: widget.picked.contains(row.key),
                phone: widget.phone,
                picking: widget.phone && widget.picked.isNotEmpty,
                onLongPress: widget.phone && widget.onPick != null
                    ? () => _toggle(item.row, row)
                    : null,
                writtenTo: _writtenTo(row),
                onTap: () => _tap(item.row, row),
                onPick: widget.onPick == null
                    ? null
                    : () => _toggle(item.row, row),
              );
              final dimmed = _Dimmed(
                source: widget.source,
                account: row.accountId,
                child: tile,
              );
              final swipe = widget.onSwipe;
              if (swipe != null) _askHint(row);
              final Widget shown = swipe == null
                  ? dimmed
                  : SwipeToArchive(
                      key: ValueKey(row.key),
                      label:
                          widget.swipeAs?.label ??
                          AppLocalizations.of(context).archive,
                      icon: widget.swipeAs?.icon ?? PiumaIcon.archive,
                      onArchive: () => swipe(row),
                      snoozeLabel:
                          widget.leftSwipeAs?.label ??
                          AppLocalizations.of(context).actionSnooze,
                      snoozeIcon: widget.leftSwipeAs?.icon ?? PiumaIcon.clock,
                      snoozeStays: widget.leftSwipeAs != null,
                      onSnooze: widget.onSnoozeSwipe == null
                          ? null
                          : () => widget.onSnoozeSwipe!(row),
                      hint: row.key == _hintRow,
                      child: dimmed,
                    );
              if (!_folding.contains(row.key)) return shown;
              // Folding: the row keeps its height inside, clipped, and fades.
              final full = rowExtent(
                look,
                chip: _chips(row),
                oneLine: widget.folder == MailFolder.waiting,
              );
              return ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: full,
                  maxHeight: full,
                  child: Opacity(opacity: _open, child: shown),
                ),
              );
            },
          ),
        ),
        // During a first download more rows are on the way (`StatesSync`).
        if (widget.folder == MailFolder.inbox && widget.mailbox == null)
          ValueListenableBuilder<SyncStatus>(
            valueListenable: widget.source.status,
            builder: (context, s, _) {
              final coming =
                  s.phase == SyncPhase.downloading &&
                  (widget.account == null || widget.account == s.downloading);
              if (!coming) return const SliverToBoxAdapter();
              return SliverPadding(
                padding: widget.phone
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverList.list(
                  children: [
                    for (var i = 0; i < kSyncPlaceholders; i++)
                      SyncPlaceholder(index: i, phone: widget.phone),
                  ],
                ),
              );
            },
          ),
        if (widget.swipeHint && _itemCount > 0)
          SliverToBoxAdapter(
            child: _SwipeHint(onSnooze: widget.onSnoozeSwipe != null),
          ),
        // Room under the last row (on the phone, for the compose button).
        SliverToBoxAdapter(
          child: SizedBox(
            height: widget.phone
                ? ComposeFab.listRoom(context)
                : PiumaSpace.s16,
          ),
        ),
      ],
    );
  }

  /// [child] on its own, or under [MessageList.top] when there is one:
  /// filling the room left when [fill], else at its own height.
  Widget _underTop(Widget child, {bool fill = false}) {
    if (widget.top.isEmpty) return child;
    return CustomScrollView(
      slivers: [
        ...widget.top,
        fill
            ? SliverFillRemaining(child: child)
            : SliverToBoxAdapter(child: child),
      ],
    );
  }

  MailAccount? _account(int id) {
    for (final a in widget.source.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.phone = false});
  final String label;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: phone
            ? const EdgeInsets.fromLTRB(20, 14, 20, 4)
            : const EdgeInsets.fromLTRB(10, 14, 10, 4),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          style: PiumaType.label.copyWith(
            color: c.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// A message waiting in the outbox: a dashed clock where the avatar
/// goes, who it is for, and Waiting or Not sent (`Outbox`).
class OutboxTile extends StatelessWidget {
  const OutboxTile({
    super.key,
    required this.item,
    this.onTap,
    this.phone = false,
    this.now,
  });

  /// For when mail sent later goes: "tomorrow, 08:00".
  final DateTime? now;

  final OutboxItem item;
  final VoidCallback? onTap;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final refused = item.error != null;
    final tone = refused ? c.danger : c.muted;
    final size = phone ? 42.0 : 38.0;
    const line = TextStyle(fontSize: 14, height: 1.45);
    final tile = Container(
      margin: EdgeInsets.only(bottom: phone ? 0 : 2),
      padding: phone
          ? const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
          : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(phone ? 0 : 12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomPaint(
            painter: _DashedRing(tone),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: refused
                    ? Text(
                        '!',
                        style: line.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : PiumaIconView(
                        PiumaIcon.clock,
                        size: phone ? 19 : 16,
                        color: tone,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.outboxTo(item.recipients),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: line.copyWith(
                          color: c.fg,
                          fontWeight: FontWeight.w500,
                          fontSize: phone ? 15 : 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(switch ((refused, item.sendAt)) {
                      (true, _) => l.outboxNotSent,
                      (false, final at?) => snoozeWhen(
                        at,
                        now ?? DateTime.now(),
                        l,
                        Localizations.localeOf(context).toLanguageTag(),
                      ),
                      _ => l.outboxWaiting,
                    }, style: PiumaType.small.copyWith(color: tone)),
                  ],
                ),
                Text(
                  item.subject.isEmpty ? l.noSubject : item.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: line.copyWith(color: c.fg),
                ),
                Text(
                  refused
                      ? l.outboxRefused(item.error!)
                      : item.body.trim().split('\n').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: line.copyWith(color: tone, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return PiumaPressable(onTap: onTap, child: tile);
  }
}

/// The dashed circle of an outbox row.
class _DashedRing extends CustomPainter {
  _DashedRing(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Offset.zero & size;
    const dashes = 24;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(0.5), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRing old) => old.color != color;
}

/// How many [SyncPlaceholder] rows a first download shows.
const kSyncPlaceholders = 5;

/// A row of an account that can't connect fades back, as in `StatesError`.
const double _dimmedOpacity = 0.42;

/// [child] faded while [account] can't sign in.
class _Dimmed extends StatelessWidget {
  const _Dimmed({
    required this.source,
    required this.account,
    required this.child,
  });

  final MailSource source;
  final int account;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: source.status,
      child: child,
      builder: (context, s, child) => AnimatedOpacity(
        opacity: s.failed.contains(account) ? _dimmedOpacity : 1,
        duration: reduceMotion(context) ? Duration.zero : PiumaMotion.theme,
        curve: PiumaMotion.curve,
        child: child,
      ),
    );
  }
}

/// A grey row standing in for mail still downloading (`StatesSync`): the
/// avatar, two bars and a lighter one, breathing slowly. [index] staggers
/// the breath; with reduce motion it holds still.
class SyncPlaceholder extends StatefulWidget {
  const SyncPlaceholder({super.key, required this.index, this.phone = false});

  final int index;
  final bool phone;

  @override
  State<SyncPlaceholder> createState() => _SyncPlaceholderState();
}

class _SyncPlaceholderState extends State<SyncPlaceholder>
    with SingleTickerProviderStateMixin {
  late final _breath = AnimationController(
    vsync: this,
    duration: PiumaMotion.pulse ~/ 2,
  );
  Timer? _start;

  /// The widths of the two bars, as on the canvas.
  static const _widths = [
    (0.46, 0.70),
    (0.34, 0.58),
    (0.52, 0.76),
    (0.40, 0.64),
    (0.30, 0.54),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _start?.cancel();
      _breath.stop();
      _breath.value = 0;
    } else if (!_breath.isAnimating && _start == null) {
      _start = Timer(PiumaMotion.pulseStagger * widget.index, () {
        if (mounted) _breath.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final (w1, w2) = _widths[widget.index % _widths.length];
    Widget bar(double width, double height, {double opacity = 1}) => Opacity(
      opacity: opacity,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: width,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: c.chip,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) => Opacity(
          opacity:
              1 -
              (1 - PiumaMotion.pulseLow) *
                  PiumaMotion.curve.transform(_breath.value),
          child: child,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.phone ? PiumaSpace.s20 : PiumaSpace.s12,
            vertical: 14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.chip,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: PiumaSpace.s12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: bar(w1 / 0.8, 11)),
                          const SizedBox(width: 10),
                          SizedBox(width: 34, child: bar(1, 11)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      bar(w2, 11),
                      const SizedBox(height: 8),
                      bar(0.92, 9, opacity: 0.7),
                    ],
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

class _RowPlaceholder extends StatelessWidget {
  const _RowPlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A row of the inbox as in the `Main` mockup: avatar with the account dot,
/// sender and time, subject, two lines of preview. Picked, as in
/// `DesktopSelect`, a checkbox takes the avatar's place; hovering shows it.
class InboxRowTile extends StatefulWidget {
  const InboxRowTile({
    super.key,
    required this.row,
    required this.account,
    required this.time,
    required this.selected,
    required this.onTap,
    this.picked = false,
    this.onPick,
    this.phone = false,
    this.picking = false,
    this.onLongPress,
    this.writtenTo,
    this.waiting = false,
    this.noReply,
    this.noticeCount = 0,
    this.noticeRange,
    this.expandedNotices = false,
  });

  /// A row of Waiting: "To Luca Bianchi" and "No reply yet" in place of
  /// the preview, as on `WaitingToApprove`.
  final int noticeCount;
  final String? noticeRange;
  final bool expandedNotices;
  final bool waiting;

  /// Sent mail back as "Remind me" asked: "To Luca Bianchi", and this
  /// line in place of the preview, in accent ink with the hourglass ("No
  /// reply from Luca · sent 3 days ago").
  final String? noReply;

  /// The alias the message was written to, shown in a group's inbox
  /// ("to fatture@studio.it", as on `GroupsSidebar`).
  final String? writtenTo;

  /// Edge to edge, as the rows of `Phone`.
  final bool phone;

  /// On the phone, while rows are being picked: a ring in place of the
  /// avatar and the account's dot before the name, as in `PhoneSelect`.
  final bool picking;

  /// A long press on a phone row starts picking.
  final VoidCallback? onLongPress;

  final MailRow row;
  final MailAccount? account;
  final String time;
  final bool selected;
  final VoidCallback onTap;
  final bool picked;

  /// A click on the avatar or checkbox; null hides the checkbox.
  final VoidCallback? onPick;

  @override
  State<InboxRowTile> createState() => _InboxRowTileState();
}

class _InboxRowTileState extends State<InboxRowTile> {
  bool _hover = false;

  /// Held down on a phone: the row squishes a little and rounds.
  bool _down = false;

  void _press(bool down) {
    if (widget.phone && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = widget.row;
    final picked = widget.picked;
    final selected = widget.selected || picked;
    final account = widget.account;
    final time = widget.time;
    final check = picked || widget.picking || (_hover && widget.onPick != null);
    final fade = reduceMotion(context) ? Duration.zero : PiumaMotion.press;
    final unread = !row.seen;
    final noReply = widget.noReply;
    final waiting = widget.waiting || noReply != null;
    // Back from a reminder it asks to be read again, as new mail does.
    final weight = unread || noReply != null
        ? FontWeight.w600
        : FontWeight.w400;
    // Read mail steps back to the muted ink; what you sent or drafted has
    // nothing to read, so it keeps the full ink (`UnreadToApprove`).
    final outgoing =
        widget.waiting ||
        row.folder == MailFolder.sent ||
        row.folder == MailFolder.drafts;
    final ink = unread || outgoing ? c.fg : c.muted;
    const line = TextStyle(fontSize: 14, height: 1.45);
    final phone = widget.phone;
    final title = phone ? line.copyWith(fontSize: 15) : line;
    final look = PiumaLook.of(context);
    final trim = look.compact ? _compactTrim : 0.0;
    final labels = LabelScope.on(context, row.labels);
    return Padding(
      padding: EdgeInsets.only(bottom: phone ? 0 : 2),
      child: Semantics(
        selected: selected,
        button: true,
        label: unread ? l.messageUnread : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          onTap: () {
            // The email grows out of this row.
            PiumaOrigin.from(context);
            widget.onTap();
          },
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  _press(false);
                  if (!widget.picking) PiumaHaptics.select();
                  widget.onLongPress!();
                },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: AnimatedScale(
              scale: _down ? PiumaMotion.pressScale : 1,
              duration: reduceMotion(context)
                  ? Duration.zero
                  : _down
                  ? PiumaMotion.press
                  : PiumaMotion.fast,
              curve: _down ? PiumaMotion.curve : PiumaSprings.fast,
              child: AnimatedContainer(
                duration: fade,
                curve: PiumaMotion.curve,
                padding: EdgeInsets.symmetric(
                  horizontal: phone ? 20 : 12,
                  vertical: 12 - trim,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? c.sel
                      : _hover && !phone
                      ? c.hover
                      : (phone ? c.surface : c.hover.withValues(alpha: 0)),
                  borderRadius: BorderRadius.circular(
                    phone ? (_down ? PiumaRadius.card : 0) : 12,
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // A touch row beside the open email (the tablet): the
                    // accent edge of `Tablet` marks it.
                    if (phone && widget.selected && !picked)
                      Positioned(
                        left: -20,
                        top: -(12 - trim),
                        bottom: -(12 - trim),
                        width: 3,
                        child: ColoredBox(color: c.accent),
                      ),
                    // Unread: the accent dot in the gutter, where the eye
                    // starts; the account stays on the avatar's dot.
                    if (unread)
                      Positioned(
                        left: phone ? -15 : -10,
                        top: (phone ? 42 : 38) / 2 - 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onPick ?? widget.onTap,
                          child: Semantics(
                            checked: widget.onPick == null ? null : picked,
                            label: widget.onPick == null
                                ? null
                                : picked
                                ? l.unpickMessage
                                : l.pickMessage,
                            child: Stack(
                              children: [
                                AnimatedOpacity(
                                  opacity: check ? 0 : 1,
                                  duration: fade,
                                  curve: PiumaMotion.curve,
                                  child: _Avatar(
                                    initials: initials(row.listName),
                                    // Your own mail shows who it went to.
                                    email: outgoing ? '' : row.fromEmail,
                                    dot: account?.color,
                                    ring: selected ? c.sel : c.surface,
                                    size: phone ? 42 : 38,
                                  ),
                                ),
                                Positioned.fill(
                                  child: AnimatedOpacity(
                                    opacity: check ? 1 : 0,
                                    duration: fade,
                                    curve: PiumaMotion.curve,
                                    child: Center(
                                      child: PickBox(
                                        on: picked,
                                        size: widget.picking ? 24 : 20,
                                        round: widget.picking,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (widget.picking && account != null) ...[
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: account.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (waiting)
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          text: l.waitingTo,
                                          style: TextStyle(color: c.muted),
                                          children: [
                                            TextSpan(
                                              text: row.listName,
                                              style: TextStyle(
                                                color: c.fg,
                                                fontWeight: noReply != null
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: title,
                                      ),
                                    )
                                  else
                                    Expanded(
                                      child: Text(
                                        // A draft may have no one to go to yet.
                                        row.listName.isEmpty
                                            ? l.noRecipients
                                            : widget.noticeCount > 1
                                            ? '${row.listName} · ${l.notificationNotices(widget.noticeCount)}'
                                            : row.listName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: title.copyWith(
                                          fontWeight: weight,
                                          color: row.listName.isEmpty
                                              ? c.muted
                                              : ink,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: phone ? 13 : 12,
                                      fontWeight: unread
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                      color: unread ? c.accentText : c.muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                row.subject.isEmpty ? l.noSubject : row.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: title.copyWith(
                                  fontWeight: weight,
                                  color: row.subject.isEmpty ? c.muted : ink,
                                ),
                              ),
                              const SizedBox(height: 1),
                              if (noReply != null)
                                Row(
                                  children: [
                                    PiumaIconView(
                                      PiumaIcon.hourglass,
                                      size: 13,
                                      color: c.accentText,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        noReply,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: line.copyWith(
                                          fontSize: 13,
                                          color: c.accentText,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  widget.waiting
                                      ? l.waitingNoReply
                                      : row.preview,
                                  maxLines: widget.waiting
                                      ? 1
                                      : look.previewLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: line.copyWith(color: c.muted),
                                ),
                              if (widget.noticeCount > 1 ||
                                  _tag(row, l, widget.phone) != null ||
                                  widget.writtenTo != null ||
                                  labels.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      if (widget.noticeCount > 1) ...[
                                        _RowChip(text: '${widget.noticeCount}'),
                                        const SizedBox(width: PiumaSpace.s8),
                                        Expanded(
                                          child: Text(
                                            widget.noticeRange!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: PiumaType.small.copyWith(
                                              color: c.muted,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          widget.expandedNotices
                                              ? l.hide
                                              : l.show,
                                          style: PiumaType.small.copyWith(
                                            color: c.accentText,
                                          ),
                                        ),
                                      ],
                                      if (labels.isNotEmpty)
                                        Flexible(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: RowLabels(
                                              labels: labels,
                                              phone: phone,
                                            ),
                                          ),
                                        ),
                                      if (_tag(row, l, widget.phone)
                                          case final tag?)
                                        _RowChip(text: tag),
                                      if (widget.writtenTo case final to?)
                                        Flexible(
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              left:
                                                  _tag(row, l, widget.phone) ==
                                                      null
                                                  ? 0
                                                  : 6,
                                            ),
                                            child: _RowChip(
                                              icon: PiumaIcon.arrowRight,
                                              text: l.rowWrittenTo(to),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One chip under a row's preview.
class _RowChip extends StatelessWidget {
  const _RowChip({required this.text, this.icon});
  final String text;
  final PiumaIcon? icon;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            PiumaIconView(icon, size: 12, color: c.muted),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The chip under a row's preview, as on `Main` and `Tablet`: "4
/// messages" for a conversation, else "Invite" for one that carries an
/// invite, or "12 photos" or "2 attachments" when files came (not on the
/// phone, whose `Phone` rows have none). Without [l], only whether there
/// is one ("" when there is).
String? _tag(MailRow row, AppLocalizations? l, bool phone) {
  if (row.isConversation) return l?.threadMessages(row.messages) ?? '';
  if (phone) return null;
  if (row.invite) return l?.inviteLabel ?? '';
  if (row.files == 0) return null;
  if (l == null) return '';
  return row.pictures == row.files
      ? l.rowPhotos(row.files)
      : l.rowAttachments(row.files);
}

/// The rounded checkbox of `DesktopSelect`: an empty ring, filled with
/// the accent and a tick when on, or a dash when only some are on.
class PickBox extends StatelessWidget {
  const PickBox({
    super.key,
    required this.on,
    this.some = false,
    required this.size,
    this.round = false,
  });

  final bool on;
  final bool some;
  final double size;

  /// The circle of `PhoneSelect` instead of the rounded square.
  final bool round;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final filled = on || some;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c.accent : c.surface,
        border: filled
            ? null
            : Border.all(color: c.ring, width: round ? 2 : 1.5),
        borderRadius: BorderRadius.circular(size * (round ? 0.5 : 0.3)),
      ),
      child: filled
          ? CustomPaint(painter: _TickPainter(c.onAccent, dash: !on))
          : null,
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.color, {required this.dash});
  final Color color;
  final bool dash;

  @override
  void paint(Canvas canvas, Size size) {
    // The tick and dash of the mockup's 24-unit icons, drawn at 0.65 size.
    final s = size.width * 0.65 / 24;
    final o = (size.width - 24 * s) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (dash) {
      path
        ..moveTo(o + 6 * s, o + 12 * s)
        ..lineTo(o + 18 * s, o + 12 * s);
    } else {
      path
        ..moveTo(o + 5 * s, o + 12 * s)
        ..lineTo(o + 10 * s, o + 17 * s)
        ..lineTo(o + 20 * s, o + 7 * s);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.color != color || old.dash != dash;
}

/// "Giulia Romano" → "GR", "dad@x.it" → "D". Only letters and digits
/// count: "SportFits (TouriSpo GmbH)" → "ST", not "S(".
String initials(String name) {
  final words = name
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (name.contains('@') || words.length == 1) {
    return words.first.characters.first.toUpperCase();
  }
  return (words.first.characters.first + words[1].characters.first)
      .toUpperCase();
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    this.email = '',
    this.dot,
    required this.ring,
    this.size = 38,
  });
  final String initials;

  /// Whose picture replaces the letters once it is on the device.
  final String email;
  final Color? dot;
  final Color ring;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final big = size > 40;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SenderPicture(
            email: email,
            size: size,
            letter: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: big ? 14 : 13,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
            ),
          ),
          if (dot != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: big ? 12 : 11,
                height: big ? 12 : 11,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The line under a tablet's rows that says what the swipes do.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.onSnooze});

  final bool onSnooze;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          PiumaIconView(PiumaIcon.arrowRight, size: 14, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              onSnooze ? l.swipeHintArchiveSnooze : l.swipeHintArchive,
              style: PiumaType.small.copyWith(fontSize: 12, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Consecutive automated notices retain their account and exact subject words.
/// Case and whitespace differences do not split an otherwise identical run.
bool sameNotice(MailRow a, MailRow b) {
  String subject(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return a.accountId == b.accountId &&
      a.mailbox == b.mailbox &&
      a.fromEmail.trim().toLowerCase() == b.fromEmail.trim().toLowerCase() &&
      subject(a.subject).isNotEmpty &&
      subject(a.subject) == subject(b.subject);
}
