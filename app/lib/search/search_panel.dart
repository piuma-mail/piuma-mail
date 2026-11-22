import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../feedback/report_context.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/attachments.dart' show fileWhen;
import '../inbox/message_list.dart' show initials;
import '../inbox/sections.dart' show rowTime;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/button.dart';
import '../widgets/links.dart';
import '../widgets/progress.dart';
import 'highlight.dart';
import 'saved_searches.dart';
import 'search_start.dart';
import 'suggestions.dart';
import '../inbox/risky_file.dart';
import '../widgets/bidi.dart';

/// Desktop search, as in the `SearchDesktop` mockup: the field with its
/// filters and operators on top, results on the left, the selected message
/// on the right.
class SearchPanel extends StatefulWidget {
  const SearchPanel({
    super.key,
    required this.source,
    required this.onClose,
    required this.onOpen,
    required this.onReply,
    required this.onArchive,
    this.now = DateTime.now,
    this.initialQuery = '',
    this.initialAccount,
    this.initialGroup,
    this.phone = false,
    this.onOpenWindow,
  });

  /// The account filter to start with, by account id: the inbox's own
  /// filter when one is on.
  final int? initialAccount;

  /// The group the inbox shows, when it shows one: search starts within
  /// its mail.
  final MailGroup? initialGroup;

  final MailSource source;
  final VoidCallback onClose;
  final ValueChanged<MailRow> onOpen;
  final void Function(MailRow row, String body) onReply;
  final ValueChanged<MailRow> onArchive;

  /// ⌘↵: the selected message in a window of its own; null where the app
  /// has one window only.
  final ValueChanged<MailRow>? onOpenWindow;
  final DateTime Function() now;
  final String initialQuery;

  /// The `SearchPhone` layout: the field with Cancel, the filters in a
  /// row that scrolls, and results that open with a tap.
  final bool phone;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  late final _field = TextEditingController(text: widget.initialQuery);

  // The field sees Tab first: it takes the first suggestion.
  late final _focus = FocusNode(onKeyEvent: _key);
  final _list = ScrollController();

  bool _unread = false;
  bool _lastMonth = false;

  /// Only mail with files (`has:attachment`).
  bool _files = false;

  /// Index in the accounts, or null for all of them.
  int? _account;

  /// Only the mail written to this group's addresses.
  late MailGroup? _group = widget.initialGroup;

  /// The kind of mail picked under "Search by type", as its operator.
  String? _type;

  /// What the phone shows before anything is typed.
  SearchStart? _start;

  /// The saved searches, for the phone's start screen.
  List<SavedSearch> _saved = const [];

  /// What the servers found for [_serverQuery], once they answered.
  ServerResults? _server;

  /// The query the server search ran, or runs, for; null before one.
  String? _serverQuery;
  bool _serverRunning = false, _serverFailed = false;

  /// With nothing found here, the servers are asked after a pause, so a
  /// word still being typed isn't sent.

  /// Suggestions for the token being typed, and where that token starts.
  List<SearchSuggestion> _suggestions = const [];
  int _suggestStart = 0;
  SuggestionData _suggestData = const SuggestionData();
  int _suggestRound = 0;

  SearchResults _results = SearchResults.empty;
  int _selected = 0;
  Timer? _debounce;

  /// One search at a time: asks that come while one runs fold into one
  /// more after it. While mail downloads, changes come faster than a
  /// search answers, and dropping every answer that was overtaken left
  /// the results as they were while the person typed.
  bool _searching = false, _searchAgain = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    final start = widget.source.accounts.indexWhere(
      (a) => a.id == widget.initialAccount,
    );
    if (start >= 0) _account = _scope = start;
    _field.addListener(_typed);
    _changes = widget.source.changes.listen((_) => _run());
    _run();
    if (widget.phone) {
      _loadStart();
    } else {
      _loadSaved();
    }
    _loadSuggestData();
    // The inbox may hold focus already, so autofocus alone isn't enough.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_serverRunning) widget.source.cancelServerSearch();
    _changes?.cancel();
    _field.dispose();
    _focus.dispose();
    _list.dispose();
    super.dispose();
  }

  String _lastText = '';

  void _typed() {
    _suggest();
    if (_field.text == _lastText) return;
    _lastText = _field.text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _run);
  }

  Future<void> _loadStart() async {
    final start = await widget.source.searchStart();
    final saved = await widget.source.savedSearches();
    if (mounted) {
      setState(() {
        _start = start;
        _saved = saved;
      });
    }
  }

  /// Folders, labels, accounts and the people written to most, for the
  /// suggestions.
  Future<void> _loadSuggestData() async {
    try {
      final source = widget.source;
      final folders = <String>[
        for (final a in source.accounts)
          ...folderPaths(await source.folders(a.id)),
      ];
      final labels = [for (final l in await source.labels()) l.name];
      final start = _start ?? await source.searchStart();
      if (!mounted) return;
      _suggestData = SuggestionData(
        folders: folders,
        labels: labels,
        accounts: [for (final a in source.accounts) a.name],
        people: [
          for (final p in start.frequent) Contact(name: p.name, email: p.email),
        ],
      );
      _frequent = _suggestData.people;
      _suggest();
    } catch (_) {
      // Suggestions are a help: without them, search still works.
    }
  }

  /// The people written to most, for `from:` before a letter is typed.
  List<Contact> _frequent = const [];

  /// Suggestions for the token at the caret.
  void _suggest() {
    final token = typedToken(_field.text, _field.selection.baseOffset);
    final shown = token == null
        ? const <SearchSuggestion>[]
        : searchSuggestions(token.typed, _suggestData, now: widget.now());
    if (token != null) _suggestStart = token.start;
    if (!listEquals(shown, _suggestions)) setState(() => _suggestions = shown);
    final person = token == null ? null : personTyped(token.typed);
    if (person != null && person.$2 != _peopleFor) _lookUpPeople(person.$2);
  }

  /// What the people in the suggestions were looked up for.
  String? _peopleFor;

  /// People whose name or address starts with [typed], for `from:` and
  /// the like.
  Future<void> _lookUpPeople(String typed) async {
    _peopleFor = typed;
    final round = ++_suggestRound;
    final people = typed.trim().isEmpty
        ? _frequent
        : await widget.source.suggestRecipients(typed);
    if (!mounted || round != _suggestRound) return;
    final d = _suggestData;
    _suggestData = SuggestionData(
      folders: d.folders,
      labels: d.labels,
      accounts: d.accounts,
      people: people,
    );
    _suggest();
  }

  void _accept(SearchSuggestion s) {
    _field.value = applySuggestion(_field.value, _suggestStart, s);
    _focus.requestFocus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        !HardwareKeyboard.instance.isShiftPressed &&
        _suggestions.isNotEmpty) {
      _accept(_suggestions.first);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// What the field and the filters ask, as the engine reads it.
  String get _query => [_field.text.trim(), ..._tokens].join(' ').trim();

  /// Forgets the server search, stopping it when it runs.
  void _forgetServer() {
    if (_serverRunning) widget.source.cancelServerSearch();
    _server = null;
    _serverQuery = null;
    _serverRunning = false;
    _serverFailed = false;
  }

  /// Asks the servers for what the search here didn't find.
  Future<void> _searchServer() async {
    final query = _query;
    if (query.isEmpty || _serverRunning && _serverQuery == query) return;
    setState(() {
      _serverQuery = query;
      _serverRunning = true;
      _serverFailed = false;
      _server = null;
    });
    try {
      final found = await widget.source.searchServer(query);
      if (!mounted || _serverQuery != query) return;
      setState(() {
        _server = found;
        _serverRunning = false;
      });
    } catch (_) {
      if (!mounted || _serverQuery != query) return;
      setState(() {
        _serverRunning = false;
        _serverFailed = true;
      });
    }
  }

  /// What the servers found that isn't among the results here.
  List<SearchHit> get _serverHits {
    final here = {for (final h in _results.hits) h.row.key};
    return [
      for (final h in _server?.hits ?? const <SearchHit>[])
        if (!here.contains(h.row.key)) h,
    ];
  }

  /// Every result, here then from the servers, as ↑↓ go through them.
  List<SearchHit> get _hits => [..._results.hits, ..._serverHits];

  /// ⌘S: keeps the search under a name.
  Future<void> _saveSearch() async {
    final query = _query;
    if (query.isEmpty) return;
    await showSavedSearchEditor(context, source: widget.source, query: query);
    await _reloadSaved();
  }

  /// The saved searches, for the desktop's empty search (the phone's come
  /// with its start screen).
  Future<void> _loadSaved() async {
    final saved = await widget.source.savedSearches();
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _reloadSaved() => widget.phone ? _loadStart() : _loadSaved();

  /// ⋯ on a saved search: rename or delete it.
  Future<void> _editSaved(SavedSearch s) async {
    await showSavedSearchEditor(context, source: widget.source, saved: s);
    await _reloadSaved();
  }

  /// Opens a result, keeping what was searched among the recent ones.
  void _open(MailRow row) {
    // Enter reaches both the field and the panel's shortcut: open once.
    if (_opened) return;
    _opened = true;
    _noteSearch();
    widget.onOpen(row);
  }

  /// ⌘↵: a result in its own window, the search staying open for more.
  void _openWindow(MailRow row) {
    _noteSearch();
    widget.onOpenWindow?.call(row);
  }

  bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void _noteSearch() {
    final query = [?_type, _field.text.trim()].join(' ').trim();
    if (query.isNotEmpty) widget.source.noteSearch(query);
  }

  /// A recent search again: its type back as a filter, the rest typed.
  void _again(String query) {
    final parts = query.split(' ');
    final type = searchTypes.contains(parts.first) ? parts.first : null;
    final words = type == null ? query : parts.skip(1).join(' ');
    setState(() => _type = type);
    _field.value = TextEditingValue(
      text: words,
      selection: TextSelection.collapsed(offset: words.length),
    );
    _run();
  }

  Future<void> _forget(String query) async {
    await widget.source.noteSearch(query, forget: true);
    await _loadStart();
  }

  Future<void> _clearRecent() async {
    await widget.source.clearSearches();
    await _loadStart();
  }

  MailAccount? get _accountFilter =>
      _account == null ? null : widget.source.accounts[_account!];

  /// "Search 3 accounts", or "Search Work" with one picked, as the inbox
  /// field says.
  String _hint(AppLocalizations l) {
    final a = _accountFilter;
    return a == null
        ? l.phoneSearch(widget.source.accounts.length)
        : l.phoneSearchOne(bidiArg(context, a.name));
  }

  /// The filters the phone field shows: the account is left out, since
  /// the placeholder and the Account chip already name it.
  List<String> get _shownTokens => [
    for (final t in _tokens)
      if (!t.startsWith('account:')) t,
  ];

  /// The filters, as the operators the engine reads.
  List<String> get _tokens {
    final since = widget.now().subtract(const Duration(days: 30));
    final account = _accountFilter;
    return [
      if (_from case final from?) 'from:${from.email}',
      ?_type,
      if (_files && _type != _hasFiles) _hasFiles,
      if (_lastMonth) 'after:${DateFormat('yyyy-MM-dd').format(since)}',
      if (account != null) 'account:${account.email}',
      if (_group case final g?) 'group:${g.id}',
      if (_unread) 'is:unread',
    ];
  }

  /// The account the inbox showed when search opened: where search
  /// looks, not a filter, so the start screen still shows.
  int? _scope;

  bool get _anyFilter =>
      _unread ||
      _lastMonth ||
      _files ||
      (_account != null && _account != _scope) ||
      _group != null ||
      _type != null ||
      _from != null;

  /// "From: Sara": the sender the results are narrowed to, when on.
  Contact? _from;

  static const _hasFiles = 'has:attachment';

  Future<void> _run() async {
    _searchAgain = true;
    if (_searching) return;
    _searching = true;
    try {
      while (_searchAgain && mounted) {
        _searchAgain = false;
        final query = _query;
        final SearchResults results;
        try {
          // Nothing typed and no filter: the start screen shows, and
          // searching the whole account for it only stalled the opening.
          results = _field.text.trim().isEmpty && !_anyFilter
              ? SearchResults.empty
              : await widget.source.search(query);
        } catch (_) {
          continue; // A half-typed query the engine refused: wait for more.
        }
        if (!mounted) return;
        final keep = _current?.row.key;
        setState(() {
          if (query != _serverQuery) _forgetServer();
          _results = results;
          final i = _hits.indexWhere((h) => h.row.key == keep);
          _selected = i < 0 ? 0 : i;
        });
      }
    } finally {
      _searching = false;
    }
    if (_openWhenReady && mounted) {
      _openWhenReady = false;
      final current = _current;
      if (current != null) _open(current.row);
    }
  }

  /// Enter, or the keyboard's search key: the selected result opens. Typed
  /// faster than the search, it opens the first one as soon as it's there.
  void _submit() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _openWhenReady = true;
      _run();
      return;
    }
    if (_searching) {
      _openWhenReady = true;
      return;
    }
    final current = _current;
    if (current != null) _open(current.row);
  }

  bool _openWhenReady = false, _opened = false;

  SearchHit? get _current {
    final hits = _hits;
    return _selected < hits.length ? hits[_selected] : null;
  }

  void _move(int by) {
    final n = _hits.length;
    if (n == 0) return;
    setState(() => _selected = (_selected + by).clamp(0, n - 1));
  }

  void _insert(String op) {
    final text = _field.text;
    final glue = text.isEmpty || text.endsWith(' ') ? '' : ' ';
    _field.value = TextEditingValue(
      text: '$text$glue$op',
      selection: TextSelection.collapsed(
        offset: text.length + glue.length + op.length,
      ),
    );
    _focus.requestFocus();
  }

  void _clearFilters() {
    setState(() {
      _unread = false;
      _lastMonth = false;
      _files = false;
      _account = null;
      _type = null;
      _from = null;
    });
    _run();
  }

  void _filter(VoidCallback change) {
    setState(change);
    _run();
  }

  @override
  Widget build(BuildContext context) => ReportScreen(
    name: 'Search',
    child: Builder(builder: _screen),
  );

  Widget _screen(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final words = searchWords(_field.text);
    final current = _current;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveSearch,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveSearch,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          shift: true,
        ): _searchServer,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          shift: true,
        ): _searchServer,
        if (widget.onOpenWindow != null) ...{
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
            if (current != null) _openWindow(current.row);
          },
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
            if (current != null) _openWindow(current.row);
          },
        },
      },
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        label: l.searchAllAccounts,
        child: widget.phone
            ? ColoredBox(
                color: c.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _phoneHeader(context),
                    Expanded(child: _resultList(context, words)),
                  ],
                ),
              )
            : Container(
                constraints: const BoxConstraints(maxWidth: 1140),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(PiumaRadius.panel),
                  border: Border.all(color: c.line),
                  boxShadow: [
                    BoxShadow(
                      color: c.shadow,
                      offset: const Offset(0, 18),
                      blurRadius: 50,
                      spreadRadius: -24,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    Expanded(
                      // A narrow window drops the preview; Enter opens.
                      child: LayoutBuilder(
                        builder: (context, box) => box.maxWidth < 820
                            ? _resultList(context, words)
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: 420,
                                    decoration: BoxDecoration(
                                      border: BorderDirectional(
                                        end: BorderSide(color: c.line),
                                      ),
                                    ),
                                    child: _resultList(context, words),
                                  ),
                                  Expanded(
                                    child: current == null
                                        ? Center(
                                            child: Text(
                                              l.noMessageToShow,
                                              style: PiumaType.body.copyWith(
                                                color: c.muted,
                                              ),
                                            ),
                                          )
                                        : _Preview(
                                            key: ValueKey(current.row.key),
                                            source: widget.source,
                                            hit: current,
                                            words: words,
                                            onOpen: widget.onOpen,
                                            onReply: widget.onReply,
                                            onArchive: widget.onArchive,
                                          ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    _footer(context),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final searching = _field.text.trim().isNotEmpty || _anyFilter;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 8, 0),
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(PiumaRadius.row),
            ),
            child: Row(
              children: [
                PiumaIconView(PiumaIcon.search, size: 19, color: c.muted),
                const SizedBox(width: 10),
                if (_tokens.isNotEmpty)
                  // Tokens take up to half the field and scroll; the text keeps the
                  // rest, so a long query never pushes the clear button out.
                  Flexible(
                    child: _FadeStart(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          children: [
                            for (final t in _tokens) ...[
                              _Token(t),
                              const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: _field,
                    focusNode: _focus,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submit(),
                    style: PiumaType.body.copyWith(fontSize: 17, color: c.fg),
                    cursorColor: c.accent,
                    decoration: InputDecoration.collapsed(
                      hintText: _hint(l),
                      hintStyle: PiumaType.body.copyWith(
                        fontSize: 17,
                        color: c.muted,
                      ),
                    ),
                  ),
                ),
                if (searching) ...[
                  const SizedBox(width: 10),
                  Text(
                    // What the servers found counts too: "No results"
                    // above a result from the server read as wrong.
                    l.searchResults(_results.total + _serverHits.length),
                    style: PiumaType.label.copyWith(color: c.muted),
                  ),
                  const SizedBox(width: 6),
                  PiumaButton(
                    label: l.saveSearch,
                    kind: PiumaButtonKind.tertiary,
                    size: PiumaButtonSize.compact,
                    shortcut: _apple ? '⌘S' : 'Ctrl S',
                    onPressed: _saveSearch,
                  ),
                ],
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: l.close,
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: _Kbd('esc', boxed: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 12),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  container: true,
                  label: l.searchFilters,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [..._chips(context)],
                  ),
                ),
                Container(width: 1, height: 18, color: c.line),
                // While an operator is typed, what it may be; Tab takes
                // the first.
                if (_suggestions.isNotEmpty)
                  Semantics(
                    container: true,
                    label: l.searchSuggestions,
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l.searchSuggestions,
                          style: PiumaType.label.copyWith(color: c.muted),
                        ),
                        const SizedBox(width: 8),
                        for (final s in _suggestions)
                          _Operator(s.insert, s.label, (_) => _accept(s)),
                        const SizedBox(width: 8),
                        const _Kbd('Tab', boxed: true),
                      ],
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.searchOperators,
                        style: PiumaType.label.copyWith(color: c.muted),
                      ),
                      const SizedBox(width: 8),
                      _Operator('from:', l.operatorNameHint, _insert),
                      _Operator('before:', l.operatorDateHint, _insert),
                      _Operator('after:', l.operatorDateHint, _insert),
                      _Operator('is:unread', '', _insert),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What the From chip calls [p]: the first name, or the address.
  static String _firstName(Contact p) {
    final name = p.name.trim();
    return name.isEmpty ? p.email : name.split(RegExp(r'\s+')).first;
  }

  /// From (the first person found), Attachments, Last month, Account and
  /// Unread.
  List<Widget> _chips(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final accounts = widget.source.accounts;
    final account = _accountFilter;
    final phone = widget.phone;
    final files = _files || _type == _hasFiles;
    final person = _from ?? _results.people.firstOrNull;
    return [
      if (widget.initialGroup case final g?)
        _FilterChip(
          phone: phone,
          label: g.name,
          dot: g.color,
          on: _group != null,
          onTap: () => _filter(() => _group = _group == null ? g : null),
        ),
      if (person != null)
        _FilterChip(
          phone: phone,
          label: l.filterFrom(bidiArg(context, _firstName(person))),
          on: _from != null,
          onTap: () => _filter(() => _from = _from == null ? person : null),
        ),
      _FilterChip(
        phone: phone,
        label: l.folderAttachments,
        on: files,
        onTap: () => _filter(() {
          _files = !files;
          if (_type == _hasFiles) _type = null;
        }),
      ),
      _FilterChip(
        phone: phone,
        label: l.filterLastMonth,
        on: _lastMonth,
        onTap: () => _filter(() => _lastMonth = !_lastMonth),
      ),
      if (accounts.length > 1)
        // The caret opens a picker: every account, or one.
        MenuAnchor(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(c.surface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PiumaRadius.card),
                side: BorderSide(color: c.line),
              ),
            ),
          ),
          menuChildren: [
            for (final (i, a) in <(int?, MailAccount?)>[
              (null, null),
              for (final (i, a) in accounts.indexed) (i, a),
            ])
              MenuItemButton(
                onPressed: () => _filter(() => _account = i),
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(200, 44)),
                  overlayColor: WidgetStatePropertyAll(c.chip),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(PiumaRadius.button),
                    ),
                  ),
                ),
                leadingIcon: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: a?.color ?? c.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                trailingIcon: _account == i
                    ? PiumaIconView(
                        PiumaIcon.check,
                        size: 16,
                        color: c.accentText,
                      )
                    : null,
                child: Text(
                  a?.name ?? l.allAccounts,
                  style: TextStyle(fontSize: 15, color: c.fg),
                ),
              ),
          ],
          builder: (context, menu, _) => _FilterChip(
            phone: phone,
            label: account?.name ?? l.filterAccount,
            dot: account?.color,
            caret: true,
            on: account != null,
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
          ),
        ),
      _FilterChip(
        phone: phone,
        label: l.filterUnread,
        on: _unread,
        onTap: () => _filter(() => _unread = !_unread),
      ),
      // On the phone the field has no room for it.
      if (phone && _query.isNotEmpty)
        _FilterChip(
          phone: phone,
          label: l.saveSearch,
          on: false,
          onTap: _saveSearch,
        ),
    ];
  }

  Widget _phoneHeader(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 4, 0),
                    decoration: BoxDecoration(
                      color: c.chip,
                      borderRadius: BorderRadius.circular(PiumaRadius.row),
                    ),
                    child: Row(
                      children: [
                        PiumaIconView(
                          PiumaIcon.search,
                          size: 17,
                          color: c.muted,
                        ),
                        const SizedBox(width: 8),
                        if (_shownTokens.isNotEmpty)
                          // Tokens take up to half the field and scroll; the text keeps the
                          // rest, so a long query never pushes the clear button out.
                          Flexible(
                            child: _FadeStart(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: Row(
                                  children: [
                                    for (final t in _shownTokens) ...[
                                      _Token(t),
                                      const SizedBox(width: 8),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: TextField(
                            controller: _field,
                            focusNode: _focus,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _submit(),
                            style: PiumaType.body.copyWith(
                              fontSize: 16,
                              color: c.fg,
                            ),
                            cursorColor: c.accent,
                            decoration: InputDecoration.collapsed(
                              hintText: _type != null
                                  ? l.searchAddWords
                                  : _hint(l),
                              hintStyle: PiumaType.body.copyWith(
                                fontSize: 16,
                                color: c.muted,
                              ),
                            ),
                          ),
                        ),
                        if (_field.text.isNotEmpty)
                          PiumaPressable(
                            onTap: () {
                              _field.clear();
                              _focus.requestFocus();
                            },
                            semanticLabel: l.clearSearch,
                            child: SizedBox.square(
                              dimension: 36,
                              child: Center(
                                child: PiumaIconView(
                                  PiumaIcon.close,
                                  size: 16,
                                  color: c.muted,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                PiumaPressable(
                  onTap: widget.onClose,
                  semanticLabel: l.cancel,
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: ExcludeSemantics(
                          child: Text(
                            l.cancel,
                            style: PiumaType.body.copyWith(
                              fontSize: 16,
                              color: c.accentText,
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
          if (_suggestions.isNotEmpty)
            Semantics(
              container: true,
              label: l.searchSuggestions,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    for (final s in _suggestions)
                      _Operator(
                        s.insert,
                        s.label,
                        (_) => _accept(s),
                        tall: true,
                      ),
                  ],
                ),
              ),
            ),
          // The start screen of `SearchEmpty` has no filters yet.
          if (_field.text.trim().isNotEmpty || _anyFilter || _start == null)
            Semantics(
              container: true,
              label: l.searchFilters,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Row(
                  children: [
                    for (final (i, chip) in _chips(context).indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      chip,
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultList(BuildContext context, List<String> words) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final r = _results;
    final searching = _field.text.trim().isNotEmpty || _anyFilter;
    final phone = widget.phone;
    final side = phone ? 20.0 : 18.0;
    if (!searching && phone && _start != null) {
      return SearchStartView(
        start: _start!,
        accounts: widget.source.accounts,
        onType: (op) => _filter(() => _type = op),
        onPerson: (p) => _again('from:${p.email}'),
        onRecent: _again,
        onForget: _forget,
        onClear: _clearRecent,
        saved: _saved,
        onSaved: (s) => _again(s.query),
        onEditSaved: _editSaved,
      );
    }
    if (!searching) {
      // The saved searches here too, as on the phone's start screen: the
      // sidebar is only icons in a narrow window.
      return ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: EdgeInsets.all(side),
            child: Text(
              l.searchEmptyHint,
              style: PiumaType.body.copyWith(color: c.muted),
            ),
          ),
          if (_saved.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(side, 4, side, 2),
              child: Semantics(
                header: true,
                child: Text(
                  l.savedSearches,
                  style: PiumaType.label.copyWith(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            for (final s in _saved)
              SavedSearchRow(
                search: s,
                onTap: () => _again(s.query),
                onEdit: () => _editSaved(s),
              ),
          ],
        ],
      );
    }
    final server = _serverHits;
    if (r.hits.isEmpty && r.people.isEmpty && server.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(side, phone ? 72 : 40, side, 18),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _anyFilter ? l.searchNoResultsFilters : l.searchNoResults,
                style: PiumaType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _anyFilter
                    ? l.searchNoResultsFiltersHint
                    : l.searchNoResultsHint,
                style: PiumaType.body.copyWith(color: c.muted),
              ),
              if (_anyFilter) ...[
                const SizedBox(height: 14),
                PiumaButton(
                  label: l.clearFilters,
                  kind: PiumaButtonKind.secondary,
                  size: PiumaButtonSize.compact,
                  onPressed: _clearFilters,
                ),
              ],
              const SizedBox(height: 22),
              ..._serverStatus(context),
            ],
          ),
        ],
      );
    }
    final heading = PiumaType.label.copyWith(
      color: c.muted,
      fontWeight: FontWeight.w600,
    );
    final people = _anyFilter ? const <Contact>[] : r.people;
    return ListView(
      controller: _list,
      padding: EdgeInsets.only(top: 4, bottom: phone ? 28 : 16),
      children: [
        if (people.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              side,
              phone ? 14 : 12,
              side,
              phone ? 4 : 6,
            ),
            child: Text(l.searchPeople, style: heading),
          ),
          if (phone)
            for (final p in people.take(3))
              _PersonRow(person: p, onTap: () => _insert('from:${p.email}'))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              child: Row(
                children: [
                  for (final (i, p) in people.take(2).indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _PersonCard(
                        person: p,
                        onTap: () => _insert('from:${p.email}'),
                      ),
                    ),
                  ],
                  if (people.length == 1) const Spacer(),
                ],
              ),
            ),
        ],
        if (r.hits.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              side,
              phone ? 16 : 14,
              side,
              phone ? 4 : 6,
            ),
            child: Row(
              children: [
                Expanded(child: Text(l.searchEmail, style: heading)),
                Text(
                  '${r.total}',
                  style: PiumaType.label.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
          for (final (i, h) in r.hits.indexed)
            Padding(
              padding: phone
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: PiumaEnter(
                key: ValueKey(h.row.key),
                index: i.clamp(0, 7),
                child: _ResultRow(
                  hit: h,
                  words: words,
                  account: _accountOf(h.row),
                  when: rowTime(
                    h.row.receivedAt,
                    widget.now(),
                    Localizations.localeOf(context).toLanguageTag(),
                  ),
                  selected: !phone && i == _selected,
                  phone: phone,
                  onTap: phone
                      ? () => _open(h.row)
                      : () => setState(() => _selected = i),
                ),
              ),
            ),
        ],
        ..._serverSection(context, words, heading),
        if (r.files.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              side,
              phone ? 18 : 16,
              side,
              phone ? 4 : 6,
            ),
            child: Text(l.folderAttachments, style: heading),
          ),
          for (final f in r.files)
            Padding(
              padding: phone
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: _FileRow(
                file: f,
                phone: phone,
                meta: l.searchFileMeta(
                  fileSize(
                    f.file.size,
                    locale: Localizations.localeOf(context).toLanguageTag(),
                  ),
                  bidiArg(context, f.row.sender),
                  fileWhen(
                    l,
                    f.row.receivedAt,
                    widget.now(),
                    Localizations.localeOf(context).toLanguageTag(),
                  ),
                ),
                onTap: () => _openFile(f),
              ),
            ),
        ],
        if (phone)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PiumaIconView(PiumaIcon.bolt, size: 13, color: c.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _stats(context),
                    textAlign: TextAlign.center,
                    style: PiumaType.label.copyWith(color: c.muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// The servers' results under the ones here: a heading, the rows, and
  /// how the search there went.
  List<Widget> _serverSection(
    BuildContext context,
    List<String> words,
    TextStyle heading,
  ) {
    final l = AppLocalizations.of(context);
    final c = PiumaTheme.of(context);
    final phone = widget.phone;
    final side = phone ? 20.0 : 18.0;
    final hits = _serverHits;
    final offset = _results.hits.length;
    return [
      if (hits.isNotEmpty) ...[
        Padding(
          padding: EdgeInsets.fromLTRB(
            side,
            phone ? 16 : 14,
            side,
            phone ? 4 : 6,
          ),
          child: Semantics(
            header: true,
            child: Row(
              children: [
                PiumaIconView(PiumaIcon.server, size: 13, color: c.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(l.searchOnServerHeading, style: heading)),
                Text(
                  '${hits.length}',
                  style: PiumaType.label.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ),
        for (final (i, h) in hits.indexed)
          Padding(
            padding: phone
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: PiumaEnter(
              key: ValueKey('server ${h.row.key}'),
              index: i.clamp(0, 7),
              child: _ResultRow(
                hit: h,
                words: words,
                account: _accountOf(h.row),
                when: rowTime(
                  h.row.receivedAt,
                  widget.now(),
                  Localizations.localeOf(context).toLanguageTag(),
                ),
                selected: !phone && offset + i == _selected,
                phone: phone,
                server: true,
                onTap: phone
                    ? () => _open(h.row)
                    : () => setState(() => _selected = offset + i),
              ),
            ),
          ),
      ],
      Padding(
        padding: EdgeInsets.fromLTRB(side, 12, side, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _serverStatus(context),
        ),
      ),
    ];
  }

  /// "Search on server", or how the search there goes or went.
  List<Widget> _serverStatus(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = PiumaTheme.of(context);
    final note = PiumaType.small.copyWith(color: c.muted);
    final server = _server;
    if (_serverRunning) {
      return [
        Semantics(
          liveRegion: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 64, child: PiumaProgress(color: c.accent)),
              const SizedBox(width: 10),
              Flexible(child: Text(l.searchingServers, style: note)),
            ],
          ),
        ),
      ];
    }
    if (_serverFailed) {
      return [
        Semantics(
          liveRegion: true,
          child: Text(l.searchServerError, style: note),
        ),
        const SizedBox(height: 8),
        _serverButton(context, l.tryAgain),
      ];
    }
    if (server != null) {
      return [
        Semantics(
          liveRegion: true,
          child: Text(
            !server.asked
                ? l.searchServerLocalOnly
                : _serverHits.isEmpty
                ? l.searchServerNothing
                : l.searchServerFound(_serverHits.length),
            style: note,
          ),
        ),
        if (server.textRefused > 0)
          Text(l.searchServerTextRefused(server.textRefused), style: note),
        if (server.failed > 0)
          Text(l.searchServerUnreachable(server.failed), style: note),
        if (server.partial)
          Text(
            server.partialAccounts.isEmpty
                ? l.searchServerPartial
                : l.searchServerPartialIn(server.partialAccounts.join(', ')),
            style: note,
          ),
      ];
    }
    if (_query.isEmpty) return const [];
    // The server is asked only from here (or ⇧⌘↵): never by itself while
    // typing. With little or nothing here, the button leads.
    final few = _results.hits.length < _fewResults;
    return [
      if (few) ...[
        Text(l.searchServerMaybe, style: note),
        const SizedBox(height: 8),
      ],
      _serverButton(context, l.searchOnServer, prominent: few),
    ];
  }

  /// Fewer results here than this, and "Search on server" leads.
  static const _fewResults = 5;

  Widget _serverButton(
    BuildContext context,
    String label, {
    bool prominent = false,
  }) => PiumaButton(
    label: label,
    kind: prominent ? PiumaButtonKind.primary : PiumaButtonKind.secondary,
    size: widget.phone ? PiumaButtonSize.touch : PiumaButtonSize.compact,
    shortcut: widget.phone ? null : (_apple ? '⇧⌘↵' : 'Ctrl ⇧ ↵'),
    onPressed: _searchServer,
  );

  /// A file's email: picked among the results on the desktop, opened on
  /// the phone or when it isn't among them.
  void _openFile(AttachedFile f) {
    final i = _results.hits.indexWhere(
      (h) =>
          h.row.key == f.row.key ||
          (h.row.subject == f.row.subject &&
              h.row.fromEmail == f.row.fromEmail),
    );
    if (widget.phone || i < 0) {
      _open(i < 0 ? f.row : _results.hits[i].row);
    } else {
      setState(() => _selected = i);
    }
  }

  MailAccount? _accountOf(MailRow row) =>
      widget.source.accounts.where((a) => a.id == row.accountId).firstOrNull;

  /// "3 accounts · 12,480 emails searched in 0.04 s".
  String _stats(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final accounts = _account == null ? widget.source.accounts.length : 1;
    // Never "0.00 s": a search always takes a moment.
    final seconds = NumberFormat('0.00', locale).format(
      (_results.elapsed.inMicroseconds / Duration.microsecondsPerSecond).clamp(
        0.01,
        double.infinity,
      ),
    );
    return l.searchStats(
      accounts,
      NumberFormat.decimalPattern(locale).format(_results.searched),
      seconds,
    );
  }

  Widget _footer(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final style = PiumaType.label.copyWith(color: c.muted);
    final searching = _field.text.trim().isNotEmpty || _anyFilter;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          if (searching) ...[
            PiumaIconView(PiumaIcon.bolt, size: 13, color: c.muted),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              // Before a search the list already shows the hint.
              searching ? _stats(context) : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          const SizedBox(width: 18),
          const _Kbd('↑↓'),
          Text(' ${l.keyMove}', style: style),
          const SizedBox(width: 18),
          const _Kbd('↵'),
          Text(' ${l.keyOpen}', style: style),
          if (widget.onOpenWindow != null) ...[
            const SizedBox(width: 18),
            _Kbd(_apple ? '⌘↵' : 'Ctrl ↵'),
            Text(' ${l.keyOpenWindow}', style: style),
          ],
        ],
      ),
    );
  }
}

/// An active filter, written as its operator inside the field.
class _Token extends StatelessWidget {
  const _Token(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: PiumaType.mono.copyWith(fontSize: 13, color: c.accentText),
      ),
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.keys, {this.boxed = false});
  final String keys;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final text = Text(
      keys,
      style: PiumaType.mono.copyWith(fontSize: 12, color: c.muted),
    );
    if (!boxed) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: text,
    );
  }
}

/// The mockup's filter chips: outlined, filled with the text color when on.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.on,
    required this.onTap,
    this.dot,
    this.caret = false,
    this.phone = false,
  });

  /// Larger, for a finger: 34 points inside a 44-point target.
  final bool phone;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final Color? dot;
  final bool caret;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    final fg = on ? c.surface : c.fg;
    final chip = AnimatedContainer(
      duration: instant ? Duration.zero : PiumaMotion.press,
      curve: PiumaMotion.curve,
      height: phone ? 34 : 30,
      padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 11),
      decoration: BoxDecoration(
        color: on ? c.fg : c.surface,
        borderRadius: BorderRadius.circular(PiumaRadius.pill),
        border: Border.all(color: on ? c.fg : c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: PiumaType.small.copyWith(
              fontSize: phone ? 14 : null,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
          if (caret) ...[
            const SizedBox(width: 6),
            PiumaIconView(PiumaIcon.chevronDown, size: 13, color: fg),
          ],
        ],
      ),
    );
    return Semantics(
      toggled: on,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: phone
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: chip,
              )
            : chip,
      ),
    );
  }
}

/// An operator button: puts the operator in the field.
class _Operator extends StatelessWidget {
  const _Operator(this.op, this.hint, this.onInsert, {this.tall = false});
  final String op;
  final String hint;
  final ValueChanged<String> onInsert;

  /// 44 points high, for a finger.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: () => onInsert(op),
      semanticLabel: hint.isEmpty ? op : '$op $hint',
      child: Container(
        height: tall ? 44 : 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        // As wide as its text, in a Wrap too.
        child: Center(
          widthFactor: 1,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: op,
                  style: PiumaType.mono.copyWith(fontSize: 13, color: c.fg),
                ),
                if (hint.isNotEmpty)
                  TextSpan(
                    text: ' $hint',
                    style: PiumaType.small.copyWith(color: c.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});
  final Contact person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final name = person.name.isNotEmpty ? person.name : person.email;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: name,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
              child: Text(
                initials(name),
                style: PiumaType.label.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.accentText,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PiumaType.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                  // A long address gives way; the count always shows.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          person.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PiumaType.label.copyWith(color: c.muted),
                        ),
                      ),
                      Text(
                        ' · ${l.personEmails(person.messages)}',
                        maxLines: 1,
                        style: PiumaType.label.copyWith(color: c.muted),
                      ),
                    ],
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

/// Text with the search's matches marked, as `<mark>` in the mockup.
class _Marked extends StatelessWidget {
  const _Marked(
    this.runs, {
    required this.style,
    this.maxLines,
    this.markWeight,
  });

  final List<(String, bool)> runs;
  final TextStyle style;
  final int? maxLines;
  final FontWeight? markWeight;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          for (final (text, hit) in runs)
            TextSpan(
              text: text,
              style: hit
                  ? TextStyle(
                      color: c.accentText,
                      backgroundColor: c.soft,
                      fontWeight: markWeight,
                    )
                  : null,
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.hit,
    required this.words,
    required this.account,
    required this.when,
    required this.selected,
    required this.onTap,
    this.phone = false,
    this.server = false,
  });

  /// A full-width row of `SearchPhone`, with two lines of preview.
  final bool phone;

  /// Found by the server search, not here.
  final bool server;
  final SearchHit hit;
  final List<String> words;
  final MailAccount? account;
  final String when;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = hit.row;
    final weight = row.seen ? FontWeight.w500 : FontWeight.w600;
    final subject = row.subject.isEmpty ? l.noSubject : row.subject;
    final line = hit.snippet.isNotEmpty
        ? markedRuns(hit.snippet)
        : highlight(row.preview, words);
    return Semantics(
      selected: selected,
      child: PiumaPressable(
        onTap: onTap,
        child: Container(
          padding: phone
              ? const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: phone
              ? BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                )
              : BoxDecoration(
                  color: selected ? c.sel : null,
                  borderRadius: BorderRadius.circular(PiumaRadius.button),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Semantics(
                    label: account?.name,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: account?.color ?? c.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.body.copyWith(
                        fontWeight: weight,
                        color: c.fg,
                      ),
                    ),
                  ),
                  if (hit.files) ...[
                    const SizedBox(width: 8),
                    Semantics(
                      label: l.searchHasFiles,
                      child: PiumaIconView(
                        PiumaIcon.paperclip,
                        size: 13,
                        color: c.muted,
                      ),
                    ),
                  ],
                  if (server) ...[
                    const SizedBox(width: 8),
                    Semantics(
                      label: l.searchFromServer,
                      child: PiumaIconView(
                        PiumaIcon.server,
                        size: 13,
                        color: c.muted,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    when,
                    style: PiumaType.label.copyWith(
                      fontSize: phone ? 12 : null,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16),
                child: _Marked(
                  highlight(subject, words),
                  maxLines: 1,
                  style: PiumaType.body.copyWith(
                    fontSize: phone ? 15 : null,
                    fontWeight: weight,
                    color: c.fg,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16),
                child: _Marked(
                  line,
                  maxLines: phone ? 2 : 1,
                  style: PiumaType.small.copyWith(
                    fontSize: phone ? 14 : null,
                    color: c.muted,
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

/// A file under Attachments, as on `SearchDesktop`: its name, and
/// "240 KB · Sara Conti · yesterday".
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.meta,
    required this.onTap,
    this.phone = false,
  });

  final AttachedFile file;
  final String meta;
  final VoidCallback onTap;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: '${file.file.name}, $meta',
      child: ExcludeSemantics(
        child: Padding(
          padding: phone
              ? const EdgeInsets.symmetric(horizontal: 20, vertical: 9)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.chip,
                  borderRadius: BorderRadius.circular(PiumaRadius.field),
                ),
                child: PiumaIconView(PiumaIcon.file, size: 16, color: c.muted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.body.copyWith(
                        fontSize: phone ? 15 : null,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                      ),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.label.copyWith(
                        height: 1.3,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected message, matches marked, with what to do next.
class _Preview extends StatefulWidget {
  const _Preview({
    super.key,
    required this.source,
    required this.hit,
    required this.words,
    required this.onOpen,
    required this.onReply,
    required this.onArchive,
  });

  final MailSource source;
  final SearchHit hit;
  final List<String> words;
  final ValueChanged<MailRow> onOpen;
  final void Function(MailRow row, String body) onReply;
  final ValueChanged<MailRow> onArchive;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  late final Future<String> _body = widget.source.body(widget.hit.row);

  /// The files it came with, named under the text as on `SearchDesktop`.
  late final Future<List<MailAttachment>> _files = widget.hit.files
      ? widget.source
            .readable(widget.hit.row)
            .then(
              (r) => r.attachments,
              onError: (Object _) => const <MailAttachment>[],
            )
      : Future.value(const <MailAttachment>[]);

  /// Files being saved to open, dimmed meanwhile.
  final _saving = <int>{};

  /// Saves [a] and opens it, as the reader does.
  Future<void> _openFile(MailAttachment a) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving.add(a.part));
    void toast(String text) => messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          width: 360,
        ),
      );
    try {
      final path = await widget.source.saveAttachment(widget.hit.row, a);
      toast(l.attachmentSaved(a.name));
      if (!mounted ||
          !await mayOpenFile(context, widget.source, widget.hit.row, a, path)) {
        return;
      }
      await openLocalFile(path);
    } catch (_) {
      toast(l.attachmentNotSaved(a.name));
    } finally {
      if (mounted) setState(() => _saving.remove(a.part));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final row = widget.hit.row;
    final account = widget.source.accounts
        .where((a) => a.id == row.accountId)
        .firstOrNull;
    final subject = row.subject.isEmpty ? l.noSubject : row.subject;
    final full = DateFormat.yMMMd(locale).add_Hm().format(row.receivedAt);
    return FutureBuilder<String>(
      future: _body,
      builder: (context, snap) {
        final body = snap.data ?? row.preview;
        final paragraphs = body
            .replaceAll('\r\n', '\n')
            .split(RegExp(r'\n\s*\n'))
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        final matches =
            countMatches(subject, widget.words) +
            countMatches(body, widget.words);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(34, 26, 34, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (account != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: account.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${account.name} · ${account.email}',
                      style: PiumaType.label.copyWith(color: c.muted),
                    ),
                  ],
                  const Spacer(),
                  if (matches > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(PiumaRadius.pill),
                      ),
                      child: Text(
                        l.searchMatches(matches),
                        style: PiumaType.label.copyWith(
                          fontWeight: FontWeight.w500,
                          color: c.accentText,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _Marked(
                highlight(subject, widget.words),
                style: PiumaType.title.copyWith(
                  fontSize: 24,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.chip,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initials(row.sender),
                        style: PiumaType.label.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.sender,
                            style: PiumaType.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: c.fg,
                            ),
                          ),
                          Text(
                            row.fromEmail,
                            style: PiumaType.small.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    Text(full, style: PiumaType.small.copyWith(color: c.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, p) in paragraphs.indexed) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _Marked(
                          highlight(p, widget.words),
                          markWeight: FontWeight.w500,
                          style: PiumaType.body.copyWith(
                            fontSize: 15,
                            height: 1.65,
                            color: c.fg,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              FutureBuilder<List<MailAttachment>>(
                future: _files,
                builder: (context, files) => files.data?.isNotEmpty ?? false
                    ? Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final a in files.data!)
                              AttachmentChip(
                                name: a.name,
                                mime: a.mime,
                                size: fileSize(a.size, locale: locale),
                                nameRuns: highlight(a.name, widget.words),
                                risk: riskNote(l, a),
                                busy: _saving.contains(a.part),
                                semanticLabel: l.attachmentLabel(
                                  bidiArg(context, a.name),
                                  fileSize(a.size, locale: locale),
                                ),
                                onTap: () => _openFile(a),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 26),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PiumaButton(
                    label: l.openConversation,
                    shortcut: '↵',
                    size: PiumaButtonSize.compact,
                    onPressed: () => widget.onOpen(row),
                  ),
                  PiumaButton(
                    label: l.actionReply,
                    kind: PiumaButtonKind.secondary,
                    size: PiumaButtonSize.compact,
                    onPressed: () => widget.onReply(row, body),
                  ),
                  PiumaButton(
                    label: l.archive,
                    kind: PiumaButtonKind.secondary,
                    size: PiumaButtonSize.compact,
                    onPressed: () => widget.onArchive(row),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A person in `SearchPhone`: a row with their initials, name and how
/// many of their emails are here.
class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onTap});
  final Contact person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final name = person.name.isNotEmpty ? person.name : person.email;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: name,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
              child: Text(
                initials(name),
                style: PiumaType.label.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.accentText,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PiumaType.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                  Text(
                    '${person.email} · ${l.personEmails(person.messages)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PiumaType.label.copyWith(
                      fontSize: 13,
                      color: c.muted,
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

/// Fades the start edge once tokens scroll under it, so the first one
/// trails off instead of being cut hard at the search icon.
class _FadeStart extends StatefulWidget {
  const _FadeStart({required this.child});
  final Widget child;

  @override
  State<_FadeStart> createState() => _FadeStartState();
}

class _FadeStartState extends State<_FadeStart> {
  bool _hidden = false;

  bool _metrics(ScrollMetrics m) {
    // The row is reversed: what is cut off lies after the end.
    final hidden = m.extentAfter > 0;
    if (hidden != _hidden) setState(() => _hidden = hidden);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final child = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _metrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _metrics(n.metrics),
        child: widget.child,
      ),
    );
    // Always a mask, so the scroll view under it keeps its place.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        colors: [_hidden ? Colors.transparent : Colors.black, Colors.black],
        stops: [0, rect.width == 0 ? 0 : (20 / rect.width).clamp(0, 1)],
      ).createShader(rect),
      child: child,
    );
  }
}
