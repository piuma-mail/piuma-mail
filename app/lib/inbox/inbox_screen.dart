import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../compose/compose_pane.dart';
import '../compose/remind_me.dart';
import '../compose/reply_builder.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../mail/senders.dart';
import '../notify/android_background.dart';
import '../notify/background_sheet.dart';
import '../notify/notifier.dart';
import '../outside/arrivals.dart';
import '../outside/arrive.dart';
import '../outside/eml_reader.dart';
import '../outside/shell.dart';
import '../notify/unread_badge.dart';
import '../design/icons.dart';
import '../feedback/crash_line.dart';
import '../feedback/report_context.dart';
import '../feedback/report_sheet.dart';
import '../feedback/shake.dart';
import '../search/command_palette.dart';
import '../search/saved_searches.dart';
import '../search/search_panel.dart';
import '../settings/pair_ask.dart';
import '../settings/settings_screen.dart';
import '../updates/updates.dart';
import '../updates/whats_new.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/predictive_back.dart';
import '../widgets/route.dart';
import '../design/tokens.g.dart';
import 'group_sheet.dart';
import 'inbox_tabs.dart';
import 'labels.dart';
import 'mailbox_actions.dart';
import 'pictures.dart';
import 'mail_pager.dart';
import 'message_actions.dart';
import 'text_size.dart';
import 'message_list.dart';
import 'move_menu.dart';
import 'newsletters.dart';
import 'attachments.dart';
import 'vault.dart';
import 'phone_parts.dart';
import 'reader.dart';
import 'selection_panel.dart';
import 'sender_card.dart';
import 'away_line.dart';
import 'service_states.dart';
import 'sidebar.dart';
import 'snooze.dart';
import 'swipe.dart';
import 'tablet_parts.dart';
import 'waiting.dart';

/// The desktop layout of the `Main` mockup: sidebar, inbox, reading pane.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.source,
    required this.onAddAccount,
    this.now = DateTime.now,
    this.initialSelection,
    this.onOpenWindow,
    this.replies,
    this.arrivals,
  });

  final MailSource source;
  final VoidCallback onAddAccount;

  /// What other apps and the system ask for (`mailto:` links, email
  /// files, shares, files dropped on the window); null in tests that
  /// don't need it.
  final Arrivals? arrivals;
  final DateTime Function() now;

  /// Opens this row at start (used by screenshots).
  final MailRow? initialSelection;

  /// Opens a message in a window of its own (⌘↵ in search), on the
  /// desktop.
  final ValueChanged<MailRow>? onOpenWindow;

  /// Replies asked for from a message's own window: compose is here.
  final Stream<MailRow>? replies;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late MailRow? _selected = widget.initialSelection;
  MailFolder _folder = MailFolder.inbox;

  /// The one account whose mail the lists show; every account's when null.
  int? _account;

  /// One of [_account]'s own folders, shown in place of [_folder].
  String? _mailbox;

  /// Each account's own folders, for the sidebar and Move to.
  Map<int, List<AccountFolder>> _ownFolders = const {};

  /// Every label, for the pills, the sidebar and the picker.
  List<MailLabel> _labels = const [];

  /// Saved searches, for the sidebar.
  List<SavedSearch> _saved = const [];

  /// The label whose mail [MailFolder.label] shows, by keyword.
  String? _labelKeyword;

  MailLabel? get _shownLabel =>
      _labels.where((l) => l.keyword == _labelKeyword).firstOrNull;

  /// What the lists are given as their mailbox: the label's keyword in
  /// [MailFolder.label].
  String? get _listMailbox =>
      _folder == MailFolder.label ? _labelKeyword : _mailbox;

  /// How many accounts the shown label's emails come from.
  int _labelAccounts = 0;

  Future<void> _countLabelAccounts() async {
    final keyword = _labelKeyword;
    if (_folder != MailFolder.label || keyword == null) return;
    final rows = await widget.source.labelled(keyword);
    if (!mounted || keyword != _labelKeyword) return;
    setState(() => _labelAccounts = {for (final r in rows) r.accountId}.length);
  }

  /// The phone reader's More menu.
  final _more = MenuController();

  /// Accounts whose "can't connect" card was put off with Later.
  final _later = <int>{};

  /// The first account that can't sign in and wasn't put off.
  MailAccount? _failedAccount(SyncStatus s) {
    for (final id in s.failed) {
      if (!_later.contains(id)) return _accountOf(id);
    }
    return null;
  }

  /// In a narrow desktop window the open message covers the list; this is
  /// whether it does now. Set by a click, cleared by Back.
  bool _readerUp = false;

  /// The window is narrow enough for one pane at a time.
  bool _stacked = false;

  /// A tablet held sideways: the `Tablet` layout.
  bool _tablet = false;

  /// A tablet held upright: `TabletPortrait`, with the message in a
  /// panel over the list.
  bool _tabletTall = false;
  int _unread = 0;

  /// How many drafts there are, for the sidebar.
  int _drafts = 0;

  /// How many conversations are snoozed, for the sidebar.
  int _snoozed = 0;

  /// Starred emails, for the sidebar's Starred.
  int _starred = 0;

  /// How many sent emails are in Waiting, and how many have waited 3
  /// days or more: the sidebar's count and the phone's line.
  ({int all, int long}) _waiting = (all: 0, long: 0);

  /// Away messages answering now, by account.
  List<AwayLine> _awayLines = const [];

  /// Newsletters: how many, how many unread, and the minutes those take.
  (int, int, int) _letters = (0, 0, 0);

  /// The Vault's cards, for its sidebar count and phone tile.
  List<VaultCard> _vaultCards = const [];

  /// The Vault category open over Now, on the phone.
  VaultCategory? _vaultPage;
  List<PecMessage> _certified = const [];

  bool get _hasVault => _vaultCards.isNotEmpty || _certified.isNotEmpty;

  /// Every file received, for the Attachments count and phone tile.
  List<AttachedFile> _files = const [];
  StreamSubscription<void>? _changes;
  StreamSubscription<List<MailNotice>>? _notices;
  StreamSubscription<int>? _dropped;
  StreamSubscription<MailRow>? _replies;

  /// How many devices share the sync space; null while sync is off.
  late int? _synced = _syncedDevices();

  int? _syncedDevices() {
    try {
      final s = widget.source.syncState();
      return s.on ? s.devices.length : null;
    } catch (_) {
      return null;
    }
  }

  void _refreshSync() {
    final n = _syncedDevices();
    if (mounted && n != _synced) setState(() => _synced = n);
  }

  bool _notifierStarted = false;

  /// The open compose pane's starting point, or null when reading.
  Draft? _composing;
  String? _composeError;

  /// Bumped so a reopened pane starts from its new draft.
  int _composeRound = 0;

  /// The search panel is open over the inbox.
  bool _searching = false;

  /// Keeps the phone's search, what is typed and found, while a message
  /// opened from it is read over it.
  GlobalKey _searchKey = GlobalKey();

  /// What search starts with when the palette opens it.
  String _searchQuery = '';

  /// The ⌘K palette is open over the inbox (desktop).
  bool _palette = false;

  /// The last run crashed: offer once to report it.
  late bool _crashed = widget.source.crashWaiting;

  /// Shake to report, while it is on and the app is in front.
  late final ShakeWatch _shake;

  /// What the attachments board starts filtered by, from the palette.
  String _filesQuery = '';

  /// Archive, Delete and Move waiting out the Undo window, one entry per
  /// action, with what tells the servers. For a conversation, every
  /// message of it in the list goes together.
  final _pendingActions =
      <Object, (Timer, List<MailRow>, Future<void> Function(List<MailRow>))>{};

  /// Rows picked to act on several at once, in the order they were picked.
  final _picked = <Object, MailRow>{};

  /// How many rows the open list has.
  int _total = 0;

  final _list = GlobalKey<MessageListState>();

  /// For the compose pane.
  List<MailSignature> _signatures = const [];

  /// Groups and every account's aliases, for From.
  List<MailGroup> _groups = const [];
  Map<int, List<String>> _aliases = const {};

  /// The group, or one address of it, whose mail the inbox shows in place
  /// of every account's (`GroupsSidebar`, `GroupsPhone`).
  GroupScope? _group;

  /// What is unread in each group and its addresses, by group id.
  Map<int, GroupUnread> _groupUnread = const {};

  /// The groups with their own Inbox.
  List<MailGroup> get _separate => [
    for (final g in _groups)
      if (g.separateInbox && g.addresses.isNotEmpty) g,
  ];

  MailGroup? _groupOf(GroupScope? scope) =>
      _groups.where((g) => g.id == scope?.group).firstOrNull;

  /// The inbox's group, while the inbox shows.
  GroupScope? get _listGroup =>
      _folder == MailFolder.inbox && _mailbox == null ? _group : null;

  @override
  void initState() {
    super.initState();
    _stopArrivals = widget.arrivals?.listen(_arrive);
    _refreshUnread();
    _loadSignatures();
    _shake = ShakeWatch(
      enabled: widget.source.shakeToReport,
      onShake: () => _report(ReportKind.problem),
    );
    _changes = widget.source.changes.listen((_) {
      _accountsChanged();
      _refreshUnread();
      _refreshSync();
    });
    _notices = widget.source.notices.listen(_notify);
    _dropped = widget.source.changesDropped.listen(_changesDropped);
    _replies = widget.replies?.listen((row) async {
      final body = await widget.source.body(row).catchError((_) => '');
      if (mounted) _reply(row, body);
    });
    widget.source.status.addListener(_signInNotice);
    widget.source.pairAsks.addListener(_pairAsk);
    widget.source.features.addListener(_refreshUnread);
    // The Vault's notices come with the day, not with new mail.
    _reminders = Timer.periodic(const Duration(minutes: 10), (_) => _remind());
    WidgetsBinding.instance.addPostFrameCallback((_) => _remind());
    WidgetsBinding.instance.addPostFrameCallback((_) => _updated());
  }

  Timer? _reminders;

  /// An account removed in Settings takes its mail out of view.
  void _accountsChanged() {
    final ids = {for (final a in widget.source.accounts) a.id};
    final gone =
        (_account != null && !ids.contains(_account)) ||
        (_selected != null && !ids.contains(_selected!.accountId));
    if (!gone || !mounted) return;
    setState(() {
      if (!ids.contains(_account)) {
        _account = null;
        _mailbox = null;
      }
      if (_selected != null && !ids.contains(_selected!.accountId)) {
        _selected = null;
      }
    });
  }

  /// Pairing requests already shown, so each asks once.
  final _asked = <String>{};

  /// A new device asks to be linked: "New phone wants to connect".
  void _pairAsk() {
    final ask = widget.source.pairAsks.value
        .where((a) => !_asked.contains(a.id))
        .firstOrNull;
    if (ask == null || !mounted) return;
    _asked.add(ask.id);
    // Away from the app, the system tells; the sheet waits inside.
    final away = switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.inactive ||
      AppLifecycleState.hidden ||
      AppLifecycleState.paused => true,
      _ => false,
    };
    if (away) {
      final l = AppLocalizations.of(context);
      notifier.show(
        SystemNotice(
          id: Object.hash('pair', ask.id) & 0x7fffffff,
          title: l.syncAskTitle(ask.kind.name),
          subject: ask.name,
          preview: l.syncAskCode(ask.kind.name),
          payload: 'pair',
        ),
      );
    }
    showPairAsk(
      context,
      source: widget.source,
      ask: ask,
      phone: MediaQuery.sizeOf(context).width < phoneWidth,
      now: widget.now,
    );
  }

  /// Accounts already told they can't sign in, until they can again.
  final _signInTold = <int>{};

  /// "Tell me when it can't sign in": one notice the first time an
  /// account's password is refused. A click opens its details.
  Future<void> _signInNotice() async {
    // Android's background service gives it, even with the app closed.
    if (widget.source.nativeNotices) return;
    final failed = widget.source.status.value.failed.toSet();
    _signInTold.retainAll(failed);
    for (final id in failed.difference(_signInTold)) {
      _signInTold.add(id);
      final account = widget.source.accounts
          .where((a) => a.id == id)
          .firstOrNull;
      if (account == null || !await widget.source.signInAlert(id)) continue;
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      notifier.show(
        SystemNotice(
          id: Object.hash('sign-in', id) & 0x7fffffff,
          title: l.noticeSignInTitle(account.name),
          subject: widget.source.accountHealth(id).certificate
              ? l.accountCertificateRefused
              : l.accountPasswordRefused,
          preview: '',
          payload: 'account\n$id',
          silent: false,
        ),
      );
    }
  }

  Future<void> _remind() async {
    if (!mounted || widget.source.nativeNotices) return;
    final due = await widget.source.vaultReminders().catchError(
      (Object _) => const <MailNotice>[],
    );
    if (due.isNotEmpty) _notify(due);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyShell();
    if (_notifierStarted) return;
    _notifierStarted = true;
    final l = AppLocalizations.of(context);
    notifier.init(
      _openNotice,
      openLabel: l.noticeOpen,
      channelLabel: l.noticeChannel,
      buttons: NoticeButtons(
        reply: l.actionReply,
        archive: l.archive,
        snooze: l.actionSnooze,
        delete: l.actionDelete,
        markRead: l.markRead,
        send: l.actionSend,
        replyHint: l.noticeReplyHint,
        onAction: _noticeAction,
      ),
    );
    AndroidBackground.listen(_openNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) => _askBackground());
  }

  /// After the first account, once: how new mail arrives with the app
  /// closed (`AndroidBackground`).
  Future<void> _askBackground() async {
    final source = widget.source;
    if (!source.backgroundChoice || source.accounts.isEmpty) return;
    if (await source.backgroundDelivery() != null || !mounted) return;
    await askBackgroundDelivery(
      context,
      source,
      askNotices: askNoticePermission,
    );
  }

  /// New mail worth it becomes a system notification, one per sender;
  /// the quiet hours take its sound, or hold it back for "While you were
  /// away".
  void _notify(List<MailNotice> notices) {
    // Android's background service shows them itself.
    if (!mounted || widget.source.nativeNotices) return;
    final l = AppLocalizations.of(context);
    final now = weekMinute(widget.now());
    final locale = Localizations.localeOf(context).toLanguageTag();
    // Reminders, of the Vault and of "Remind me", come as they are.
    bool reminder(MailNotice n) =>
        n.vault != null || n.away != null || n.noReply != null;
    final mail = [
      for (final n in notices)
        if (!reminder(n)) n,
    ];
    var shown = mail;
    try {
      shown = widget.source.quiet(mail, now);
    } catch (_) {
      // Shown as they are.
    }
    final quietNow = widget.source.quietAt(now);
    for (final n in [
      for (final n in notices)
        if (reminder(n)) n,
      ...shown,
    ]) {
      final vault = n.vault;
      final away = n.away;
      if (n.noReply case final r?) {
        notifier.show(
          SystemNotice(
            id:
                Object.hash('no-reply', n.accountId, n.mailbox, n.uid) &
                0x7fffffff,
            title:
                '${l.remindNoReply(n.sender)} · ${remindSent(r.sentDaysAgo, l)}',
            subject: n.subject,
            preview: '',
            payload: '${n.accountId}\n${n.mailbox}\n${n.uid}',
            silent: quietNow,
          ),
        );
        continue;
      }
      notifier.show(
        SystemNotice(
          id: away != null
              ? Object.hash('away', 0) & 0x7fffffff
              : vault == null
              ? Object.hash(n.accountId, n.senderEmail.toLowerCase()) &
                    0x7fffffff
              : Object.hash('vault', n.accountId, n.mailbox, n.uid) &
                    0x7fffffff,
          title: away != null
              ? l.noticeAwayTitle
              : vault != null
              ? vaultNoticeTitle(l, vault)
              : n.count > 1
              ? l.noticeTitleMany(n.sender, n.count)
              : n.sender,
          subject: away != null
              ? awayNoticeDetail(l, away)
              : vault != null
              ? vaultNoticeDetail(l, vault, locale)
              : n.subject,
          preview: n.preview,
          payload: away != null
              ? 'inbox'
              : '${n.accountId}\n${n.mailbox}\n${n.uid}',
          silent: n.silent || (vault != null && quietNow),
          // Buttons would touch only the newest of several.
          buttons: vault == null && away == null && n.count == 1,
        ),
      );
    }
  }

  /// A clicked notification opens its message in the inbox. A message
  /// being written stays open.
  Future<void> _openNotice(String payload) async {
    final parts = payload.split('\n');
    if (parts.length == 2 && parts[0] == 'account') {
      final id = int.tryParse(parts[1]);
      if (id == null || !mounted) return;
      final here = ModalRoute.of(context);
      Navigator.of(context).popUntil((r) => r == here || r.isFirst);
      await _openSettings(account: id);
      return;
    }
    var row = await _noticeRow(payload);
    if (!mounted || row == null) return;
    // A reminder's email opens as in Waiting, with Write again.
    final key = row.key;
    final back = await widget.source
        .reminded(widget.now())
        .catchError((Object _) => const <MailRow>[]);
    if (!mounted) return;
    row = back.where((r) => r.key == key).firstOrNull ?? row;
    final here = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == here || r.isFirst);
    setState(() {
      _searching = false;
      _picked.clear();
      _folder = MailFolder.inbox;
    });
    _open(row);
  }

  /// The message a notice is about.
  Future<MailRow?> _noticeRow(String payload) async {
    final parts = payload.split('\n');
    if (parts.length != 3) return null;
    final account = int.tryParse(parts[0]);
    final uid = int.tryParse(parts[2]);
    if (account == null || uid == null) return null;
    return widget.source.messageRow(account, parts[1], uid);
  }

  /// A button on a notice for one email, as on `Notifications`: Reply
  /// sends what was typed in the notice (or opens the reply where the
  /// system has no field), Archive and Snooze do what swiping does. Each
  /// marks the message read.
  Future<void> _noticeAction(
    String payload,
    String action,
    String? text,
  ) async {
    final row = await _noticeRow(payload);
    if (!mounted || row == null) return;
    await widget.source.setSeen([row], true).catchError((Object _) {});
    if (!mounted) return;
    switch (action) {
      case 'read':
        // Read already, as for every button.
        break;
      case 'delete':
        await _act([row], MessageAction.delete, reopen: false);
      case 'archive':
        await _act([row], MessageAction.archive, reopen: false);
      case 'snooze':
        await _snooze(
          [row],
          until: snoozeTime(SnoozeChoice.tomorrow, widget.now()),
          reopen: false,
        );
      case 'reply':
        final body = await widget.source.body(row).catchError((_) => '');
        if (!mounted) return;
        if (text != null) {
          // As on Android, a reply from a notice doesn't quote.
          await _quickReply(row, body, text, quote: false);
        } else {
          await _openNotice(payload);
          if (mounted) _reply(row, body);
        }
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _stopArrivals?.call();
    _changes?.cancel();
    _notices?.cancel();
    _dropped?.cancel();
    _replies?.cancel();
    _reminders?.cancel();
    widget.source.status.removeListener(_signInNotice);
    widget.source.pairAsks.removeListener(_pairAsk);
    widget.source.features.removeListener(_refreshUnread);
    // A message in its Undo window is in the outbox, on disk: it goes
    // without this screen (see _send).
    for (final (timer, rows, run) in _pendingActions.values) {
      timer.cancel();
      run(rows).ignore();
    }
    super.dispose();
  }

  // From outside the app (lib/outside/): links, files, shares.

  VoidCallback? _stopArrivals;

  /// Messages asked for while another was being written: each opens
  /// when the one before is closed, so nothing written is replaced.
  final _arrived = <ComposeArrival>[];
  static const _maxArrived = 16;

  bool _shellSet = false;

  /// Keeping running with the window closed, as set, with the tray's
  /// words in the person's language.
  void _applyShell() {
    if (widget.arrivals == null || !Shell.canKeepRunning) return;
    final l = AppLocalizations.of(context);
    final d = widget.source.desktopSettings;
    Shell.keepRunning(
      d.keepRunning,
      open: l.trayOpen,
      compose: l.compose,
      quit: l.trayQuit,
    ).ignore();
    if (!_shellSet) {
      _shellSet = true;
      // What sign-in starts follows the setting, wherever the app moved.
      if (d.startAtLogin) Shell.startAtLogin(true).ignore();
    }
  }

  void _arrive(Arrival arrival) {
    if (!mounted) return;
    switch (arrival) {
      case EmlArrival(:final path):
        _openEml(path).ignore();
      case NetworkFileArrival():
        _toast(AppLocalizations.of(context).arrivalNetworkFile);
      case final ComposeArrival a:
        if (_composing != null) {
          // Kept like the arrivals before the inbox: never unbounded. One
          // past the limit is dropped, so nothing says it waits.
          if (_arrived.length >= _maxArrived) return;
          _arrived.add(a);
          _toast(AppLocalizations.of(context).arrivalWaits);
          return;
        }
        _write(a).ignore();
    }
  }

  Future<void> _write(ComposeArrival a) async {
    final l = AppLocalizations.of(context);
    if (widget.source.accounts.isEmpty) return;
    final account = await pickAccount(
      context,
      widget.source.accounts,
      title: l.arrivalWhichAccount,
    );
    if (account == null || !mounted) return;
    final (draft, left) = await draftFor(a, account);
    if (!mounted) return;
    if (_composing != null) {
      if (_arrived.length < _maxArrived) _arrived.add(a);
      return;
    }
    _openCompose(draft);
    if (left > 0) _toast(l.arrivalFilesLeft(left));
  }

  Future<void> _openEml(String path) async {
    final l = AppLocalizations.of(context);
    final EmlMessage message;
    try {
      message = await widget.source.openEml(path);
    } on EmlException catch (e) {
      if (mounted) {
        _toast(e.problem == EmlProblem.tooLarge ? l.emlTooLarge : l.emlNotMail);
      }
      return;
    } catch (_) {
      if (mounted) _toast(l.emlNotMail);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => EmlReader(
          source: widget.source,
          message: message,
          onClose: () => Navigator.of(route).pop(),
        ),
      ),
    );
  }

  /// Files dropped on the window, while nothing is being written (compose
  /// takes its own): an email file opens, others go in a new message.
  Widget _dropFiles(Widget child) {
    final arrivals = widget.arrivals;
    if (arrivals == null || touchDevice) return child;
    return DropTarget(
      enable: _composing == null,
      onDragDone: (detail) =>
          arrivals.addArgs([for (final f in detail.files) f.path]),
      child: child,
    );
  }

  void _openCompose([Draft? draft, String? error]) {
    final accounts = widget.source.accounts;
    if (accounts.isEmpty) return;
    setState(() {
      _composing = draft ?? Draft(accountId: accounts.first.id);
      _composeError = error;
      _composeRound++;
    });
  }

  void _toast(
    String text, {
    String? action,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final shown = messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        width: phone ? null : 360,
        // Above the quick reply bar while a message is open.
        margin: phone
            ? EdgeInsets.fromLTRB(16, 0, 16, _selected == null ? 34 : 82)
            : null,
        // One with an action stays longer, so there is time to reach it.
        duration:
            duration ??
            (action == null ? PiumaMotion.toast : PiumaMotion.toastAction),
        // A toast with an action would stay until replaced; Undo is
        // only true for its window.
        persist: false,
        action: action == null
            ? null
            : SnackBarAction(label: action, onPressed: onAction!),
      ),
    );
    // On the phone the compose button steps up out of its way.
    final id = Object();
    _toastId = id;
    setState(() => _toastUp = true);
    shown.closed.then((_) {
      if (mounted && _toastId == id) setState(() => _toastUp = false);
    });
  }

  Object? _toastId;
  bool _toastUp = false;

  /// "Updated to 0.1.0 (612) · What's new", once after an update went in
  /// (`UpdatesToApprove` section 4).
  void _updated() {
    final updates = Updates.instance;
    final release = updates.updatedTo;
    if (!mounted || release == null || updates.announced) return;
    updates.announced = true;
    final l = AppLocalizations.of(context);
    _toast(
      l.updatedTo(shownVersion(release.version)),
      action: l.whatsNew,
      onAction: () => showWhatsNew(context, release: release),
    );
  }

  /// Closes compose. What was written stays in Drafts, with a way to
  /// throw it away; when it could not be saved, a way back to it.
  Future<void> _closeCompose(Draft draft, Future<DraftCopy?>? saved) async {
    final l = AppLocalizations.of(context);
    final source = widget.source;
    setState(() => _composing = null);
    if (saved == null) {
      // Nothing changed: a draft opened and left as it was stays, and an
      // untouched reply goes quietly.
      return;
    }
    final copy = await saved;
    if (!mounted) return;
    if (draft.isEmpty) {
      // Everything was deleted: so is its copy.
      if (copy != null) source.discardDraft(copy).ignore();
      return;
    }
    if (copy == null) {
      _toast(
        l.draftNotSavedToast,
        action: l.reopen,
        onAction: () => _openCompose(draft),
      );
      return;
    }
    _toast(
      l.draftSaved,
      action: l.discard,
      onAction: () => source.discardDraft(copy).ignore(),
    );
  }

  /// Discards compose. Deletes any saved draft copy and offers Undo.
  Future<void> _discardCompose(Draft draft) async {
    final l = AppLocalizations.of(context);
    final source = widget.source;
    setState(() => _composing = null);
    final copy = draft.copy;
    if (copy == null) return;
    try {
      await source.discardDraft(copy);
    } catch (_) {
      if (mounted) _toast(AppLocalizations.of(context).actionFailed);
      return;
    }
    if (!mounted) return;
    _toast(
      l.draftDiscarded,
      action: l.undo,
      duration: undoSendWindow,
      onAction: () async {
        try {
          final restored = await source.saveDraft(draft.withCopy(null));
          if (mounted) _openCompose(draft.withCopy(restored));
        } catch (_) {
          if (mounted) _toast(AppLocalizations.of(context).actionFailed);
        }
      },
    );
  }

  /// A saved draft opens in compose, to go on writing it.
  Future<void> _openDraft(MailRow row) async {
    try {
      final draft = await widget.source.openDraft(row);
      if (mounted) _openCompose(draft);
    } catch (_) {
      if (mounted) _toast(AppLocalizations.of(context).actionFailed);
    }
  }

  /// Send, with Undo: the message goes to the outbox on disk at once, to
  /// leave when its Undo window ends. Nothing about it lives only here: a
  /// second send keeps the first, and closing the window or the app in
  /// the window still sends it (at the next start, if the app is gone).
  Future<void> _send(Draft draft) async {
    final l = AppLocalizations.of(context);
    final source = widget.source;
    setState(() => _composing = null);
    final int id;
    try {
      id = await source.sendWithUndo(draft, undoSendWindow);
    } on SendException catch (e) {
      if (mounted) _openCompose(draft, _sendProblem(l, e.error, e.detail));
      return;
    }
    final delivery = source.deliver(id);
    if (!mounted) return;
    _toast(
      l.sending,
      action: l.undo,
      duration: undoSendWindow,
      onAction: () => _reopenOutgoing(id),
    );
    final done = await delivery;
    if (!mounted) return;
    final now = AppLocalizations.of(context);
    switch (done.outcome) {
      case SendOutcome.sent:
        _toast(now.sent);
      case SendOutcome.waiting:
        // Offline: it waits in the Outbox and goes by itself.
        _toast(
          now.inOutbox,
          action: now.editAction,
          onAction: () => _reopenOutgoing(id),
        );
      case SendOutcome.maybeSent:
        // Kept in the Outbox, marked: never sent twice by itself.
        _toast(now.outboxMaybeSentCheck);
      case SendOutcome.wrongPassword:
      case SendOutcome.refused:
      case SendOutcome.insecure:
        // As before the outbox: the message comes back with the reason.
        final problem = _sendProblem(now, switch (done.outcome) {
          SendOutcome.wrongPassword => SendError.wrongPassword,
          SendOutcome.refused => SendError.rejected,
          _ => SendError.other,
        }, done.detail);
        try {
          final back = await source.reopenOutgoing(id);
          if (!mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          _openCompose(
            back,
            done.outcome == SendOutcome.insecure ? now.errorInsecure : problem,
          );
        } catch (_) {
          // Left in the Outbox, with its reason.
        }
      case SendOutcome.gone:
        break;
    }
  }

  String _sendProblem(AppLocalizations l, SendError error, String detail) =>
      switch (error) {
        SendError.badAddress => l.sendBadAddress(detail),
        SendError.noRecipients => l.sendNoRecipients,
        SendError.wrongPassword => l.sendErrorPassword,
        SendError.unreachable => l.sendErrorUnreachable,
        SendError.rejected => l.sendErrorRejected,
        SendError.other => l.sendErrorOther,
      };

  /// Archive, Delete, Report spam or Not spam: the rows leave at once, their
  /// servers are told after the Undo window, all in one go. [reopen] puts
  /// a single message back in the reader on Undo; a swiped one goes back
  /// to its row instead.
  Future<void> _act(
    List<MailRow> picked,
    MessageAction action, {
    bool reopen = true,
  }) async {
    if (picked.isEmpty) return;
    // A draft has nothing to archive: it goes to Trash.
    if (action == MessageAction.archive &&
        picked.every((r) => r.folder == MailFolder.drafts)) {
      action = MessageAction.delete;
    }
    // In Trash and spam, Delete is for good: asked first, no Undo. A
    // selection with mail from elsewhere too splits: that mail goes to
    // Trash with Undo, the rest only once confirmed.
    if (action == MessageAction.delete) {
      bool forGood(MailRow r) =>
          widget.source.deletesForGood(r.accountId, r.mailbox);
      final forever = [
        for (final r in picked)
          if (forGood(r)) r,
      ];
      if (forever.isNotEmpty) {
        final rest = [
          for (final r in picked)
            if (!forGood(r)) r,
        ];
        // Cancelled: nothing of the selection is deleted.
        if (!await _deleteForever(forever) || rest.isEmpty || !mounted) {
          return;
        }
        picked = rest;
      }
    }
    final l = AppLocalizations.of(context);
    final n = picked.length;
    PiumaHaptics.done();
    await _withUndo(
      picked,
      switch (action) {
        MessageAction.archive => l.archivedMany(n),
        MessageAction.delete => l.trashedMany(n),
        MessageAction.junk => l.reportedSpamMany(n),
        MessageAction.notJunk => l.notSpamMany(n),
      },
      (rows) => widget.source.apply(rows, action),
      reopen: reopen,
    );
  }

  /// "Move to…": the folders of the messages' account come up, under
  /// [anchor] when given; the move has Undo like Archive. Messages of
  /// several accounts can't go to one folder, so nothing happens then.
  Future<void> _move(
    List<MailRow> picked, {
    Rect? anchor,
    bool phone = false,
    bool reopen = true,
  }) async {
    if (picked.isEmpty) return;
    final account = _accountOf(picked.first.accountId);
    if (account == null || picked.any((r) => r.accountId != account.id)) {
      return;
    }
    final from = picked.first.mailbox;
    final target = await showMoveTo(
      context,
      source: widget.source,
      account: account,
      from: picked.every((r) => r.mailbox == from) ? from : '',
      anchor: anchor,
      phone: phone,
    );
    if (target == null || !mounted) return;
    final l = AppLocalizations.of(context);
    await _withUndo(
      picked,
      l.movedMany(picked.length, target.name),
      (rows) => widget.source.moveTo(rows, target.mailbox),
      reopen: reopen,
    );
  }

  /// "Snooze until…" under [anchor] (a sheet on the phone), or straight
  /// to [until]: the rows leave at once, with Undo like Archive.
  Future<void> _snooze(
    List<MailRow> picked, {
    Rect? anchor,
    bool phone = false,
    DateTime? until,
    bool reopen = true,
  }) async {
    if (picked.isEmpty) return;
    final now = widget.now();
    final pick = until != null
        ? (at: until, unlessReply: false)
        : await showSnooze(context, now: now, anchor: anchor, phone: phone);
    if (pick == null || !mounted) return;
    final at = pick.at;
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    await _withUndo(
      picked,
      l.snoozedMany(picked.length, snoozeWhen(at, now, l, locale)),
      (rows) => widget.source.snooze(rows, at, unlessReply: pick.unlessReply),
      reopen: reopen,
    );
  }

  /// Snoozed mail back in the inbox now, with Undo.
  Future<void> _wake(List<MailRow> picked) async {
    if (picked.isEmpty) return;
    final l = AppLocalizations.of(context);
    await _withUndo(
      picked,
      l.wokenMany(picked.length),
      (rows) => widget.source.wake(rows),
    );
  }

  /// Stop waiting: the rows leave Waiting and stay in Sent.
  Future<void> _stopWaiting(List<MailRow> picked, {bool reopen = true}) async {
    if (picked.isEmpty) return;
    final l = AppLocalizations.of(context);
    await _withUndo(picked, l.stoppedWaiting, (rows) async {
      final source = widget.source;
      await source.stopWaiting(rows);
      // Hidden only while Undo was open: they stay in Sent.
      for (final r in rows) {
        source.setHidden(r, false);
      }
    }, reopen: reopen);
  }

  /// "Remind me if nobody replies" for sent mail that waits: its choices
  /// under [anchor], or in a sheet on the phone.
  Future<void> _remindMe(
    MailRow row, {
    Rect? anchor,
    bool phone = false,
  }) async {
    final picked = await showRemindMe(
      context,
      now: widget.now(),
      current: row.remindAt,
      anchor: anchor,
      phone: phone,
    );
    if (picked == null || !mounted) return;
    await widget.source.remindMe(row, picked.at);
    if (!mounted || _selected?.key != row.key) return;
    setState(() => _selected = _selected!.copyWith(remindAt: picked.at));
  }

  /// Sent mail that waits for a reply, in Waiting or back from a
  /// reminder: Write again, Stop waiting and Remind me, as in Waiting.
  bool _waits(MailRow? row) =>
      _folder == MailFolder.waiting || (row?.waitingFor.isNotEmpty ?? false);

  /// Write again: a reply to your own email, to the people it waits on.
  void _writeAgain(MailRow row, String body) {
    final to =
        row.waitingFor.length == 1 &&
            row.to.isNotEmpty &&
            !row.to.contains(',') &&
            !row.to.contains('@')
        ? ['${row.to} <${row.waitingFor.single}>']
        : row.waitingFor;
    _openCompose(_replyDraft(row, body, to: to.isEmpty ? null : to));
  }

  /// The rows leave the list at once; [run] tells their servers after the
  /// Undo window, all in one go. [reopen] puts a single message back in
  /// the reader on Undo.
  Future<void> _withUndo(
    List<MailRow> picked,
    String done,
    Future<void> Function(List<MailRow>) run, {
    bool reopen = true,
  }) async {
    final l = AppLocalizations.of(context);
    final source = widget.source;
    final wasPicked = _picked.isNotEmpty;
    final keys = {for (final r in picked) r.key};
    await _list.currentState?.fold(keys);
    if (!mounted) return;
    for (final r in picked) {
      source.setHidden(r, true);
    }
    setState(() {
      if (keys.contains(_selected?.key)) _selected = null;
      _picked.removeWhere((k, _) => keys.contains(k));
    });
    final id = Object();
    final rows = [...picked];
    Object? toast;
    _pendingActions[id] = (
      Timer(undoSendWindow, () async {
        _pendingActions.remove(id);
        // Undo goes with its window: a late tap can't bring back rows
        // the servers have already moved.
        if (mounted && _toastId == toast) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
        try {
          await run(rows);
        } catch (_) {
          if (mounted) _toast(AppLocalizations.of(context).actionFailed);
        }
      }),
      rows,
      run,
    );
    _toast(
      done,
      action: l.undo,
      duration: undoSendWindow,
      onAction: () {
        final pending = _pendingActions.remove(id);
        if (pending == null) return;
        pending.$1.cancel();
        for (final r in rows) {
          source.setHidden(r, false);
        }
        setState(() {
          if (wasPicked) {
            _picked.addAll({for (final r in picked) r.key: r});
          } else if (reopen) {
            _selected = picked.single;
          }
        });
      },
    );
    toast = _toastId;
    // A conversation's other messages in this list go with it, so the
    // row doesn't come back showing the one before.
    for (final row in picked.where((r) => r.isConversation)) {
      final others = (await source.conversation(row))
          .where((m) => m.listed && m.folder == row.folder && m.key != row.key);
      if (_pendingActions[id] == null) return;
      for (final m in others) {
        source.setHidden(m, true);
        rows.add(m);
      }
    }
  }

  /// Read or unread, for every message of the conversations given.
  Future<void> _markSeen(List<MailRow> picked, bool seen) async {
    final source = widget.source;
    final rows = <MailRow>[];
    for (final row in picked) {
      final members = row.isConversation
          ? await source.conversation(row)
          : [row];
      rows.addAll(members.where((m) => m.seen != seen));
    }
    if (rows.isEmpty) return;
    try {
      await source.setSeen(rows, seen);
    } catch (_) {
      if (mounted) _toast(AppLocalizations.of(context).seenFailed);
    }
  }

  /// A row opened by a click or a key: it is read now.
  void _open(MailRow row) {
    if (row.folder == MailFolder.drafts) {
      _openDraft(row);
      return;
    }
    setState(() {
      // Read from now on: More offers Mark as unread.
      _selected = row.withSeen(true);
      _readerUp = true;
    });
    _markSeen([row], true);
  }

  void _pick(List<MailRow> rows, bool on) => setState(() {
    for (final r in rows) {
      on ? _picked[r.key] = r : _picked.remove(r.key);
    }
  });

  /// Cmd/Ctrl+A, or the header checkbox: all of them, or none when all
  /// are already picked.
  Future<void> _pickAll() async {
    if (_total > 0 && _picked.length >= _total) {
      setState(_picked.clear);
      return;
    }
    final rows = await _list.currentState?.allRows() ?? const <MailRow>[];
    if (!mounted) return;
    setState(() => _picked.addAll({for (final r in rows) r.key: r}));
  }

  void _unpickAll() {
    if (_picked.isNotEmpty) setState(_picked.clear);
  }

  /// J and K, ↓ and ↑: the email after [row] in the list, or the one
  /// before, as a swipe does on the phone.
  void _step(MailRow row, int step) {
    final next = _list.currentState?.near(row, step);
    if (next != null) _open(next);
  }

  /// The open email's text size, from Ctrl/⌘ + and − (and 0 for the
  /// size the app sets) and from Text size in More, on the phone too;
  /// kept while the app runs.
  double _zoom = 1;

  void _zoomBy(int step) => _zoomTo(textSizeStep(_zoom, step));

  /// [toast] says the new size; Text size shows it itself.
  void _zoomTo(double zoom, {bool toast = true}) {
    if (_selected == null || _zoom == zoom) return;
    setState(() => _zoom = zoom);
    if (toast) {
      _toast(AppLocalizations.of(context).zoomLevel((zoom * 100).round()));
    }
  }

  /// More's Text size: smaller, larger, actual size.
  void _textSize() => showTextSize(
    context,
    size: () => _zoom,
    onSize: (z) => _zoomTo(z, toast: false),
    phone: MediaQuery.sizeOf(context).width < phoneWidth,
  );

  /// Ctrl + and − (⌘ on Apple), with or without Shift for "+", on the main
  /// keys and the keypad; Ctrl 0 for the size the app sets.
  Map<ShortcutActivator, VoidCallback> get _zoomKeys => {
    for (final apple in [true, false]) ...{
      for (final shift in [true, false]) ...{
        for (final key in [
          LogicalKeyboardKey.equal,
          LogicalKeyboardKey.add,
          LogicalKeyboardKey.numpadAdd,
        ])
          SingleActivator(
            key,
            meta: apple,
            control: !apple,
            shift: shift,
          ): () =>
              _zoomBy(1),
      },
      for (final key in [
        LogicalKeyboardKey.minus,
        LogicalKeyboardKey.numpadSubtract,
      ])
        SingleActivator(key, meta: apple, control: !apple): () => _zoomBy(-1),
      for (final key in [LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0])
        SingleActivator(key, meta: apple, control: !apple): () => _zoomTo(1),
    },
  };

  /// Single keys, as listed in Settings › Shortcuts: C writes a new
  /// email; Delete, E, H, M and R work on the picked rows or the open message
  /// (R, A for Reply all and F for Forward, on the open message only);
  /// J and ↓ open the next email in the list, K and ↑ the one before;
  /// Shift+U and Esc on the picked rows.
  /// A text field keeps them for itself, and compose or search stops
  /// them.
  KeyEventResult _pickedKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final open = _composing != null || _searching ? null : _selected;
    final rows = _picked.values.toList();
    final shift = keys.isShiftPressed;
    if (rows.isEmpty) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyC
            when !shift && _composing == null && !_searching:
          _openCompose();
        case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace
            when !shift && open != null:
          _act([open], MessageAction.delete);
        case LogicalKeyboardKey.keyE when !shift && open != null:
          if (_inArchive || open.folder == MailFolder.drafts) {
            return KeyEventResult.ignored;
          }
          _act([open], MessageAction.archive);
        case LogicalKeyboardKey.keyF when !shift && _canForward(open):
          _forward(open!);
        case LogicalKeyboardKey.keyH when !shift && _canSnooze(open):
          _snooze([open!]);
        case LogicalKeyboardKey.keyM when !shift && open != null:
          if (open.folder == MailFolder.drafts) return KeyEventResult.ignored;
          _move([open]);
        case LogicalKeyboardKey.keyL when !shift && open != null:
          if (open.folder == MailFolder.drafts) return KeyEventResult.ignored;
          _label([open]);
        case LogicalKeyboardKey.keyS when !shift && open != null:
          if (open.folder == MailFolder.drafts) return KeyEventResult.ignored;
          _star([open], !open.starred);
        case LogicalKeyboardKey.keyR when !shift && open != null && !_inSent:
          widget.source
              .body(open)
              .catchError((_) => '')
              .then((body) => mounted ? _reply(open, body) : null);
        case LogicalKeyboardKey.keyA when !shift && open != null && !_inSent:
          widget.source
              .body(open)
              .catchError((_) => '')
              .then((body) => mounted ? _replyAll(open, body) : null);
        case LogicalKeyboardKey.keyJ || LogicalKeyboardKey.arrowDown
            when !shift && open != null:
          _step(open, 1);
        case LogicalKeyboardKey.keyK || LogicalKeyboardKey.arrowUp
            when !shift && open != null:
          _step(open, -1);
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _unpickAll();
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace
          when !shift:
        _act(rows, MessageAction.delete);
      case LogicalKeyboardKey.keyE when !shift:
        if (_folder == MailFolder.archive) return KeyEventResult.ignored;
        _act(rows, MessageAction.archive);
      case LogicalKeyboardKey.keyH when !shift && _snoozable:
        _snooze(rows);
      case LogicalKeyboardKey.keyM when !shift:
        _move(rows);
      case LogicalKeyboardKey.keyL when !shift:
        _label(rows);
      case LogicalKeyboardKey.keyS when !shift:
        _star(rows, !rows.every((r) => r.starred));
      case LogicalKeyboardKey.keyU when shift:
        _markSeen(rows, false);
        _refreshPicked(false);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Keeps the picked rows' read state in step with what was just set,
  /// so the panel offers the opposite next.
  void _refreshPicked(bool seen) => setState(() {
    _picked.updateAll((_, r) => r.withSeen(seen));
  });

  // Reply, Reply all, Forward and the rest of the reader's More build
  // their drafts in `reply_builder.dart` and `message_actions.dart`; what
  // is here only picks them and hands the draft to compose or to [_send].

  void _reply(MailRow row, String body, [String text = '']) =>
      _answer(row, body, ReplyMode.sender, text);

  void _replyAll(MailRow row, String body, [String text = '']) =>
      _answer(row, body, ReplyMode.all, text);

  void _replyList(MailRow row, String body, [String text = '']) =>
      _answer(row, body, ReplyMode.list, text);

  /// Compose, answering [row] as [mode] says, once the engine has said
  /// who that is (every Reply-To, everyone else on To and Cc).
  Future<void> _answer(
    MailRow row,
    String body,
    ReplyMode mode, [
    String text = '',
  ]) async {
    final envelope = await widget.source
        .envelope(row)
        .catchError((Object _) => null);
    if (!mounted) return;
    _openCompose(
      _replyDraft(row, body, text: text, envelope: envelope, mode: mode),
    );
  }

  /// The reader's other ways to send a message on, and its source.
  MessageActions get _actions => MessageActions(
    context: context,
    source: widget.source,
    openCompose: _openCompose,
    toast: _toast,
    phone: MediaQuery.sizeOf(context).width < phoneWidth,
  );

  /// Drafts stay drafts: anything else can be forwarded.
  bool _canForward(MailRow? row) =>
      row != null &&
      row.folder != MailFolder.drafts &&
      _folder != MailFolder.drafts &&
      _folder != MailFolder.waiting;

  /// Forward, as on `ForwardToApprove` (option A): the message being read
  /// with its formatting, under a "Forwarded message" block, and its
  /// files, fetched in sight; any that can't be are named, with Try again.
  Future<void> _forward(MailRow row) => _actions.forward(row);

  /// A few words from the quick reply box, sent as a reply with the
  /// account's reply signature and the usual Undo; to everyone with
  /// [all] (the box's Reply all).
  ///
  /// [envelope] is the one the reader has already; without it, it is
  /// asked for. A Reply all that follows an unverified Mail-Followup-To
  /// (`MailEnvelope.replyAllReview`) opens compose instead, to be seen
  /// before it goes.
  Future<void> _quickReply(
    MailRow row,
    String body,
    String text, {
    bool quote = true,
    bool all = false,
    MailEnvelope? envelope,
  }) async {
    envelope ??= await widget.source
        .envelope(row)
        .catchError((Object _) => null);
    if (!mounted) return;
    final draft = _replyDraft(
      row,
      body,
      text: text,
      signatureId: _replySignature(row),
      quote: quote,
      envelope: envelope,
      mode: all ? ReplyMode.all : ReplyMode.sender,
    );
    if (all && (envelope?.replyAllReview ?? false)) {
      _openCompose(draft);
      return;
    }
    _send(draft);
  }

  /// The signature a reply to [row] takes: its group's, else the
  /// account's reply signature.
  int? _replySignature(MailRow row) {
    int? signature;
    for (final s in _signatures) {
      if (s.accountId == row.accountId && s.forReplies) signature = s.id;
    }
    final account = widget.source.accounts
        .where((a) => a.id == row.accountId)
        .firstOrNull;
    final from = widget.source.replyFrom(row) ?? account?.email;
    final group = from == null ? null : groupOf(_groups, from)?.signatureId;
    if (_signatures.any((s) => s.id == group)) signature = group;
    return signature;
  }

  /// The line under the reply box when a reply goes from an alias.
  ReplyFrom? _replyFromOf(MailRow row) {
    final from = widget.source.replyFrom(row);
    if (from == null) return null;
    final id = _replySignature(row);
    return (
      address: from,
      signature: _signatures.where((s) => s.id == id).firstOrNull?.label,
    );
  }

  Draft _replyDraft(
    MailRow row,
    String body, {
    String text = '',
    int? signatureId,
    List<String>? to,
    bool quote = true,
    MailEnvelope? envelope,
    ReplyMode mode = ReplyMode.sender,
  }) =>
      ReplyBuilder(
        AppLocalizations.of(context),
        Localizations.localeOf(context).toLanguageTag(),
      ).reply(
        row,
        body,
        envelope: envelope,
        mode: mode,
        text: text,
        fromEmail: widget.source.replyFrom(row),
        signatureId: signatureId,
        to: to,
        quote: quote,
      );

  /// Send later: compose closes, the message waits in the Outbox for its
  /// time, and Undo opens it again.
  Future<void> _schedule(Draft draft, DateTime at) async {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    setState(() => _composing = null);
    try {
      final id = await widget.source.schedule(draft, at);
      if (!mounted) return;
      _toast(
        l.scheduledToast(snoozeWhen(at, widget.now(), l, locale)),
        action: l.undo,
        onAction: () => _reopenOutgoing(id),
      );
    } catch (_) {
      if (mounted) _openCompose(draft, l.actionFailed);
    }
  }

  /// A row of the Outbox, tapped: a message opens in compose again; a
  /// Redirect, which has nothing to edit, offers Cancel or Try again.
  void _openOutgoing(OutboxItem item) =>
      item.redirect ? _actions.outboxRedirect(item) : _reopenOutgoing(item.id);

  /// A message in the Outbox opens in compose again, and stops waiting.
  /// Undo of a send is this too.
  Future<void> _reopenOutgoing(int id) async {
    try {
      final draft = await widget.source.reopenOutgoing(id);
      if (mounted) _openCompose(draft);
    } catch (_) {
      if (!mounted) return;
      // On its way right now, or already gone: it was sent meanwhile.
      final waiting = await widget.source
          .outbox(null)
          .catchError((_) => const <OutboxItem>[]);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      _toast(waiting.any((o) => o.id == id) ? l.sending : l.sent);
    }
  }

  /// "Find or create a label" for [rows]; from the keyboard (L) or the
  /// selection panel's Label, hung from [anchor] when there is one.
  Future<void> _label(List<MailRow> rows, {Rect? anchor}) async {
    await showLabelPicker(
      context,
      source: widget.source,
      rows: rows,
      anchor: anchor,
      phone: MediaQuery.sizeOf(context).width < phoneWidth,
      // The rows keep what they carry now: the reader's pills, the next L.
      onToggle: (keyword, add) {
        if (!mounted) return;
        MailRow mark(MailRow r) => r.copyWith(
          labels: [
            for (final k in r.labels)
              if (k != keyword) k,
            if (add) keyword,
          ],
        );
        final keys = {for (final r in rows) r.key};
        setState(() {
          _picked.updateAll((_, r) => mark(r));
          if (_selected case final open? when keys.contains(open.key)) {
            _selected = mark(open);
          }
        });
      },
    );
  }

  /// Every email with [label], from every account (`LabelsToApprove`).
  void _showLabel(MailLabel label) {
    if (_folder == MailFolder.label && _labelKeyword == label.keyword) return;
    setState(() {
      _folder = MailFolder.label;
      _labelKeyword = label.keyword;
      _labelAccounts = 0;
      _mailbox = null;
      _account = null;
      _group = null;
      _filesQuery = '';
      _selected = null;
      _picked.clear();
    });
    _countLabelAccounts();
  }

  /// The inbox shows all the mail: no account picked, or only one
  /// account to pick, so the zone tiles and Waiting count for it.
  bool get _everyAccount =>
      _account == null || widget.source.accounts.length == 1;

  void _showFolder(MailFolder folder) {
    // The unified inbox shows every account again.
    final all = folder == MailFolder.inbox;
    if (folder == _folder &&
        _mailbox == null &&
        _filesQuery.isEmpty &&
        (!all || (_account == null && _group == null))) {
      return;
    }
    setState(() {
      _folder = folder;
      _mailbox = null;
      _filesQuery = '';
      if (all) _account = null;
      _group = null;
      _selected = null;
      _picked.clear();
    });
  }

  /// On the phone a folder keeps the account picked in the same sheet.
  void _showPhoneFolder(MailFolder folder) {
    if (folder == _folder && _mailbox == null) return;
    setState(() {
      _vaultPage = null;
      _folder = folder;
      _mailbox = null;
      _selected = null;
      _picked.clear();
    });
  }

  MailAccount? _accountOf(int? id) {
    for (final a in widget.source.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  void _showAccount(int? account) {
    if (account == _account && _mailbox == null && _group == null) return;
    setState(() {
      _account = account;
      _group = null;
      _mailbox = null;
      _selected = null;
      _picked.clear();
    });
    _refreshTabs();
  }

  /// A group's Inbox, or one address of it; every account's when null.
  void _showGroup(GroupScope? group) {
    if (group == _group &&
        _folder == MailFolder.inbox &&
        _mailbox == null &&
        _account == null) {
      return;
    }
    setState(() {
      _group = group;
      _account = null;
      _mailbox = null;
      _folder = MailFolder.inbox;
      _selected = null;
      _picked.clear();
    });
    _refreshTabs();
  }

  /// One of an account's own folders: what is here shows at once, and the
  /// server is asked for the rest.
  void _showMailbox(int account, String mailbox) {
    if (account == _account && mailbox == _mailbox) return;
    setState(() {
      _account = account;
      _group = null;
      _mailbox = mailbox;
      _folder = MailFolder.inbox;
      _selected = null;
      _picked.clear();
    });
    _refreshFolder(account, mailbox);
  }

  /// Asks the server for what an own folder holds; when that fails, says
  /// so, with a way to ask again, while what is here stays.
  void _refreshFolder(int account, String mailbox) {
    widget.source.refreshFolder(account, mailbox).catchError((_) {
      if (!mounted || account != _account || mailbox != _mailbox) return;
      final l = AppLocalizations.of(context);
      _toast(
        l.folderRefreshFailed,
        action: l.tryAgain,
        onAction: () => _refreshFolder(account, mailbox),
      );
    });
  }

  /// Changes the server kept refusing were given up: their messages are
  /// back where the server has them, and the person knows why.
  void _changesDropped(int count) {
    if (!mounted || count <= 0) return;
    _toast(AppLocalizations.of(context).changesDropped(count));
  }

  /// What the person calls the own folder shown.
  String? get _mailboxName {
    final mailbox = _mailbox;
    if (mailbox == null) return null;
    for (final f in _ownFolders[_account] ?? const <AccountFolder>[]) {
      if (f.mailbox == mailbox) return f.name;
    }
    return mailbox.split(RegExp(r'[/.]')).last;
  }

  void _openSearch([String query = '']) => setState(() {
    _palette = false;
    _searchQuery = query;
    _searchKey = GlobalKey();
    _searching = true;
  });

  void _closeSearch() => setState(() => _searching = false);

  /// ⌘K: the palette on the desktop, search on the phone.
  void _openPalette() {
    if (MediaQuery.sizeOf(context).width < phoneWidth) {
      _openSearch();
      return;
    }
    setState(() {
      _searching = false;
      _palette = true;
    });
  }

  void _closePalette() => setState(() => _palette = false);

  /// Closes the palette, then does [run].
  VoidCallback _fromPalette(VoidCallback run) => () {
    _closePalette();
    run();
  };

  List<PaletteCommand> _paletteCommands(AppLocalizations l) {
    PaletteCommand go(PiumaIcon icon, String place, MailFolder folder) =>
        PaletteCommand(
          icon,
          l.paletteGoTo(place),
          _fromPalette(() => _showFolder(folder)),
        );
    return [
      PaletteCommand(
        PiumaIcon.compose,
        l.newMessage,
        _fromPalette(_openCompose),
      ),
      if (_picked.isEmpty && _canForward(_selected))
        PaletteCommand(
          PiumaIcon.forward,
          l.actionForward,
          _fromPalette(() => _forward(_selected!)),
          meta: 'F',
        ),
      ..._readerCommands(l),
      go(PiumaIcon.inbox, l.unifiedInbox, MailFolder.inbox),
      if (_waiting.all > 0)
        go(PiumaIcon.hourglass, l.folderWaiting, MailFolder.waiting),
      if (_snoozed > 0)
        go(PiumaIcon.clock, l.folderSnoozed, MailFolder.snoozed),
      if (_drafts > 0) go(PiumaIcon.pen, l.folderDrafts, MailFolder.drafts),
      go(PiumaIcon.send, l.folderSent, MailFolder.sent),
      go(PiumaIcon.archive, l.folderArchive, MailFolder.archive),
      if (_letters.$1 > 0)
        go(PiumaIcon.newsletter, l.folderNewsletters, MailFolder.newsletters),
      if (_hasVault) go(PiumaIcon.vault, l.folderVault, MailFolder.vault),
      if (_files.isNotEmpty)
        go(PiumaIcon.paperclip, l.folderAttachments, MailFolder.attachments),
      PaletteCommand(
        PiumaIcon.settings,
        l.settings,
        _fromPalette(() => _openSettings()),
      ),
      PaletteCommand(
        PiumaIcon.warning,
        l.reportProblem,
        _fromPalette(() => _report(ReportKind.problem)),
        keywords: 'bug report',
        meta: l.paletteHelp,
      ),
      PaletteCommand(
        PiumaIcon.spark,
        l.suggestIdea,
        _fromPalette(() => _report(ReportKind.idea)),
        keywords: 'report feedback',
        meta: l.paletteHelp,
      ),
    ];
  }

  /// ⌘K's commands for the open email: Reply all and the rest of the
  /// reader's More, the next and previous email, and the text size.
  List<PaletteCommand> _readerCommands(AppLocalizations l) {
    final open = _selected;
    if (_picked.isNotEmpty || open == null) return const [];
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final mod = apple ? '⌘' : 'Ctrl ';
    void withBody(void Function(MailRow, String, [String]) answer) => widget
        .source
        .body(open)
        .catchError((Object _) => '')
        .then((body) => mounted ? answer(open, body) : null);
    return [
      if (!_inSent)
        PaletteCommand(
          PiumaIcon.replyAll,
          l.actionReplyAll,
          _fromPalette(() => withBody(_replyAll)),
          meta: 'A',
        ),
      if (_canForward(open)) ...[
        PaletteCommand(
          PiumaIcon.paperclip,
          l.actionForwardAttachment,
          _fromPalette(() => _actions.forwardAsAttachment(open)),
        ),
        PaletteCommand(
          PiumaIcon.arrowRight,
          l.actionRedirect,
          _fromPalette(() => _actions.redirect(open)),
        ),
        PaletteCommand(
          PiumaIcon.pen,
          l.actionEditAsNew,
          _fromPalette(() => _actions.editAsNew(open)),
        ),
      ],
      PaletteCommand(
        PiumaIcon.document,
        l.actionViewSource,
        _fromPalette(() => _actions.viewSource(open)),
        keywords: 'headers raw',
      ),
      PaletteCommand(
        PiumaIcon.download,
        l.actionSaveEml,
        _fromPalette(() => _actions.saveEml(open)),
        keywords: 'export',
      ),
      PaletteCommand(
        PiumaIcon.arrowRight,
        l.shortcutNextEmail,
        _fromPalette(() => _step(open, 1)),
        meta: 'J',
      ),
      PaletteCommand(
        PiumaIcon.chevronLeft,
        l.shortcutPreviousEmail,
        _fromPalette(() => _step(open, -1)),
        meta: 'K',
      ),
      PaletteCommand(
        PiumaIcon.plus,
        l.zoomIn,
        _fromPalette(() => _zoomBy(1)),
        meta: '$mod+',
      ),
      PaletteCommand(
        PiumaIcon.search,
        l.zoomOut,
        _fromPalette(() => _zoomBy(-1)),
        meta: '$mod−',
      ),
      PaletteCommand(
        PiumaIcon.search,
        l.zoomReset,
        _fromPalette(() => _zoomTo(1)),
        meta: '${mod}0',
      ),
      PaletteCommand(PiumaIcon.sliders, l.textSize, _fromPalette(_textSize)),
    ];
  }

  /// The report sheet, as from ⌘K, Settings › Help & feedback or a shake.
  Future<void> _report(ReportKind kind) =>
      openReport(context, source: widget.source, kind: kind);

  /// The crash line's Report: the sheet with Problem picked; the crash
  /// goes in its log.
  Future<void> _reportCrash() async {
    await _report(ReportKind.problem);
    if (!mounted) return;
    _dismissCrash();
  }

  void _dismissCrash() {
    widget.source.dismissCrash();
    setState(() => _crashed = false);
  }

  Widget _crashLine(EdgeInsets padding) => Padding(
    padding: padding,
    child: PiumaEnter(
      child: CrashLine(onReport: _reportCrash, onDismiss: _dismissCrash),
    ),
  );

  Widget _commandPalette(BuildContext context) {
    final l = AppLocalizations.of(context);
    String address(Contact p) =>
        p.name.isEmpty ? p.email : '${p.name} <${p.email}>';
    return CommandPalette(
      source: widget.source,
      now: widget.now,
      commands: _paletteCommands(l),
      onWrite: (p) {
        _closePalette();
        final accounts = widget.source.accounts;
        if (accounts.isEmpty) return;
        _openCompose(
          Draft(accountId: _account ?? accounts.first.id, to: [address(p)]),
        );
      },
      onFrom: (p) => _openSearch('from:${p.email}'),
      onFilesFrom: (p) => setState(() {
        _palette = false;
        _folder = MailFolder.attachments;
        _mailbox = null;
        _selected = null;
        _picked.clear();
        _filesQuery = p.email;
      }),
      filesFrom: (p) => _files
          .where((f) => f.row.fromEmail.toLowerCase() == p.email.toLowerCase())
          .length,
      onSearch: _openSearch,
      onOpen: (row) {
        _closePalette();
        _openFound(row);
      },
      onClose: _closePalette,
    );
  }

  /// Opens a search result in the reading pane.
  void _openFound(MailRow row) {
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    setState(() {
      _searching = phone && row.folder != MailFolder.drafts;
      _composing = null;
      _picked.clear();
    });
    _open(row);
  }

  Future<void> _openSettings({
    SettingsSection section = SettingsSection.accounts,
    int? signature,
    int? account,
  }) async {
    ReportContext.visit('Settings');
    final write = await Navigator.of(context).push(
      PiumaRoute.of<Draft>(
        context,
        (route) => SettingsScreen(
          source: widget.source,
          onBack: () => Navigator.of(route).pop(),
          onAddAccount: widget.onAddAccount,
          section: section,
          signature: signature,
          account: account,
          now: widget.now,
          onWrite: (draft) => Navigator.of(route).pop(draft),
        ),
      ),
    );
    ReportContext.visit('Inbox');
    if (write != null && mounted) _openCompose(write);
    _refreshSync();
    // Signatures may have changed under an open compose pane.
    await _loadSignatures();
  }

  /// The phone's accounts sheet, where Settings opens from.
  Future<void> _openAccounts() => showPiumaSheet<void>(
    context,
    label: AppLocalizations.of(context).accounts,
    builder: (sheet) => PhoneAccountsSheet(
      accounts: widget.source.accounts,
      account: _account,
      onAccount: (id) {
        Navigator.of(sheet).pop();
        _showAccount(id);
      },
      folder: _mailbox == null ? _folder : null,
      drafts: _drafts,
      snoozed: _snoozed,
      starred: _starred,
      onFolder: (folder) {
        Navigator.of(sheet).pop();
        _showPhoneFolder(folder);
      },
      ownFolders: (_ownFolders[_account] ?? const []).length,
      onOwnFolders: () {
        Navigator.of(sheet).pop();
        _openPhoneFolders();
      },
      labels: _labels,
      label: _folder == MailFolder.label ? _labelKeyword : null,
      onLabel: (label) {
        Navigator.of(sheet).pop();
        _showLabel(label);
      },
      onAddAccount: () {
        Navigator.of(sheet).pop();
        widget.onAddAccount();
      },
      onSettings: () {
        Navigator.of(sheet).pop();
        _openSettings();
      },
    ),
  );

  /// The phone's group sheet, opened from the title.
  Future<void> _openGroups() => showPiumaSheet<void>(
    context,
    label: AppLocalizations.of(context).groupSheetLabel,
    builder: (sheet) => PhoneGroupSheet(
      groups: _separate,
      accounts: widget.source.accounts,
      account: _account,
      onAccount: (id) {
        Navigator.of(sheet).pop();
        _showAccount(id);
      },
      unread: _groupUnread,
      allUnread: _unread,
      current: _listGroup?.group,
      onGroup: (id) {
        Navigator.of(sheet).pop();
        _showGroup(id == null ? null : GroupScope(id));
      },
      onManage: () {
        Navigator.of(sheet).pop();
        _openSettings(section: SettingsSection.groups);
      },
    ),
  );

  /// The phone's list of the picked account's own folders.
  Future<void> _openPhoneFolders() async {
    final account = _accountOf(_account);
    if (account == null) return;
    final l = AppLocalizations.of(context);
    // The same tree as the desktop's sidebar: folders open and close,
    // hidden ones on demand.
    final picked = await showPiumaSheet<AccountFolder>(
      context,
      label: l.accountFolders(account.name),
      builder: (_) => PhoneFolderTree(
        account: account,
        folders: _ownFolders[account.id] ?? const [],
        current: _account == account.id ? _mailbox : null,
      ),
    );
    if (picked != null && mounted) _showMailbox(account.id, picked.mailbox);
  }

  Future<void> _loadSignatures() async {
    final all = await widget.source.signatures();
    final groups = await widget.source.groups();
    final aliases = {
      for (final a in widget.source.accounts)
        a.id: await widget.source.aliases(a.id),
    };
    if (mounted) {
      setState(() {
        _signatures = all;
        _groups = groups;
        _aliases = aliases;
      });
    }
  }

  /// What the inbox's first chips keep: People unless All or
  /// Notifications is picked, and with [_onlyUnread] only unread mail.
  InboxTab _tab = InboxTab.people;
  bool _onlyUnread = false;
  TabCounts _tabs = const TabCounts();

  /// Whether the tabs show: in the inbox, once machines have sent some.
  bool get _hasTabs =>
      _folder == MailFolder.inbox &&
      _mailbox == null &&
      _tabs.notifications > 0;

  /// The half of the inbox the list keeps; null outside the inbox.
  InboxTab? get _listTab => _folder != MailFolder.inbox || _mailbox != null
      ? null
      : _tabs.notifications > 0
      ? _tab
      : InboxTab.people;

  /// Whether the list keeps only unread mail: Unread is on where the
  /// tabs show.
  bool get _listUnread => _hasTabs && _onlyUnread;

  void _pickUnread(bool unread) {
    if (unread == _onlyUnread) return;
    setState(() {
      _onlyUnread = unread;
      _selected = null;
      _picked.clear();
    });
  }

  Future<void> _refreshTabs() async {
    final account = _account;
    final group = _group;
    final tabs = await widget.source.tabCounts(account: account, group: group);
    if (mounted && account == _account && group == _group) {
      setState(() => _tabs = tabs);
    }
  }

  void _pickTab(InboxTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _selected = null;
      _picked.clear();
    });
  }

  /// One count at a time, as the message list reads: changes that come
  /// meanwhile fold into one more after it.
  bool _counting = false, _countAgain = false;

  Future<void> _refreshUnread() async {
    if (_counting) {
      _countAgain = true;
      return;
    }
    _counting = true;
    try {
      await _countUnread();
    } finally {
      _counting = false;
      if (_countAgain && mounted) {
        _countAgain = false;
        _refreshUnread();
      }
    }
  }

  Future<void> _countUnread() async {
    _refreshTabs();
    final away = widget.source.awayLines();
    if (mounted) setState(() => _awayLines = away);
    final n = await widget.source.inboxUnread();
    final drafts = await widget.source.draftCount();
    final snoozed = await widget.source.snoozedCount();
    final starred = await _starredCount();
    final waiting = await widget.source.waitingCount(widget.now());
    // Settings › Features: a zone that is off is not asked for at all.
    final on = await widget.source.featureSettings();
    final letters = on.newsletters
        ? await widget.source.newsletters(0, newsletterLimit)
        : <Newsletter>[];
    rememberNewsletters(widget.source, letters);
    var unreadLetters = 0, minutes = 0;
    for (final n in letters) {
      if (n.row.seen) continue;
      unreadLetters++;
      minutes += n.minutes;
    }
    if (!mounted) return;
    final spam = AppLocalizations.of(context).spamFolder;
    final trashName = AppLocalizations.of(context).trashFolder;
    final own = {
      for (final a in widget.source.accounts)
        a.id: [
          ...await widget.source.folders(a.id),
          // Trash and the spam folder come last, where Delete is for
          // good and Not spam is.
          if (widget.source.trashMailbox(a.id) case final trash?)
            AccountFolder(mailbox: trash, name: trashName),
          if (widget.source.junkMailbox(a.id) case final junk?)
            AccountFolder(mailbox: junk, name: spam),
        ],
    };
    final vault = on.vault ? await widget.source.vaultCards() : <VaultCard>[];
    final certified = on.vault
        ? await widget.source.pecMessages()
        : <PecMessage>[];
    final files = on.attachments
        ? await widget.source.attachedFiles()
        : <AttachedFile>[];
    final groups = await widget.source.groups();
    final groupUnread = await widget.source.groupUnread();
    final labels = await widget.source.labels();
    final saved = await widget.source.savedSearches();
    if (mounted) {
      setState(() {
        _labels = labels;
        _saved = saved;
        // A label that went shows the inbox again.
        if (_folder == MailFolder.label &&
            !labels.any((l) => l.keyword == _labelKeyword)) {
          _folder = MailFolder.inbox;
          _selected = null;
          _picked.clear();
        }
        _groups = groups;
        _groupUnread = groupUnread;
        // A group that went, or lost its own Inbox, shows everyone's again.
        final g = _groupOf(_group);
        if (_group != null &&
            (g == null ||
                !_separate.contains(g) ||
                (_group!.address != null &&
                    !g.addresses.any((a) => a.email == _group!.address)))) {
          _group = null;
        }
        _files = files;
        _unread = n;
        _shellUnread(n);
        _drafts = drafts;
        _snoozed = snoozed;
        _starred = starred;
        _badge(n);
        _waiting = waiting;
        _letters = (letters.length, unreadLetters, minutes);
        _vaultCards = vault;
        _certified = certified;
        _ownFolders = own;
        // A zone turned off while open shows the inbox again.
        if ((_folder == MailFolder.newsletters && !on.newsletters) ||
            (_folder == MailFolder.vault && !on.vault) ||
            (_folder == MailFolder.attachments && !on.attachments)) {
          _folder = MailFolder.inbox;
          _selected = null;
          _picked.clear();
        }
      });
      _countLabelAccounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    // A message asked for from outside while another was being written.
    if (_composing == null && _arrived.isNotEmpty) {
      final next = _arrived.removeAt(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _arrive(next));
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _openSettings,
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            _openSettings,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _pickAll,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): _pickAll,
        const SingleActivator(LogicalKeyboardKey.escape): _closeStacked,
        ..._zoomKeys,
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _pickedKeys,
        child: PictureScope(
          pictures: widget.source.pictures,
          child: LabelScope(
            labels: _labels,
            child: _dropFiles(_layout(context)),
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // A phone on its side keeps the phone layout: its short side is
      // a phone's, too low for the sidebar.
      final short = MediaQuery.sizeOf(context).shortestSide < phoneWidth;
      if (box.maxWidth < phoneWidth || (touchDevice && short)) {
        return _phone(context);
      }
      final tablet = touchDevice && !short;
      _tablet = tablet && box.maxWidth > box.maxHeight;
      _tabletTall = tablet && !_tablet;
      return _desktop(context, box.maxWidth);
    },
  );

  /// Back from a message that covers the list in a narrow window.
  void _closeStacked() {
    if (!_stacked || _composing != null || _searching || !_readerUp) return;
    setState(() => _readerUp = false);
  }

  /// "Away message on for Work until Sun 2 Nov", at the top of the inbox:
  /// every account's in the unified inbox, one account's in its own.
  List<Widget> _awayTop(EdgeInsets padding) {
    if (_folder != MailFolder.inbox || _mailbox != null) return const [];
    return [
      for (final line in _awayLines)
        if (_account == null || _account == line.accountId)
          if (_accountOf(line.accountId) case final a?)
            Padding(
              key: ValueKey(('away', a.id)),
              padding: padding,
              child: PiumaEnter(
                child: AwayLineView(
                  account: a,
                  end: line.end,
                  onTurnOff: () => _turnOffAway(a.id),
                ),
              ),
            ),
    ];
  }

  Future<void> _turnOffAway(int accountId) async {
    setState(() {
      _awayLines = [
        for (final l in _awayLines)
          if (l.accountId != accountId) l,
      ];
    });
    try {
      await widget.source.turnOffAwayMessage(accountId);
    } catch (_) {
      // Still on: the line comes back with the next count.
    }
    _refreshUnread();
  }

  /// The unread count in the tray's tooltip and on the Linux launcher.
  void _shellUnread(int n) {
    if (widget.arrivals == null) return;
    Shell.unread(
      n,
      tooltip: AppLocalizations.of(context).trayTooltip(n),
    ).ignore();
  }

  /// Above the phone list, never folding: the offline strip, and the way
  /// back from Waiting.
  Widget _phoneAbove(SyncStatus status) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (status.offline) const PiumaEnter(child: OfflineBanner()),
      if (_folder == MailFolder.waiting && _mailbox == null)
        WaitingBack(onBack: () => _showPhoneFolder(MailFolder.inbox)),
    ],
  );

  /// The zones in a strip at the top of the phone list
  /// (`ZonesToApprove`, variant 2). They wait for a first download to
  /// end, as on `StatesSync`.
  List<(Widget, int)> _phoneZones(SyncStatus status) =>
      _accountOf(status.downloading) == null &&
          _folder == MailFolder.inbox &&
          _mailbox == null &&
          _everyAccount &&
          _group == null
      ? [
          if (_letters.$1 > 0)
            (
              NewslettersTile(
                unread: _letters.$2,
                onTap: () => _showPhoneFolder(MailFolder.newsletters),
              ),
              4,
            ),
          if (_hasVault) (_vaultTile(context), 3),
          if (_files.isNotEmpty)
            (
              AttachmentsTile(
                fresh: newFiles(_files, widget.now()),
                onTap: () => _showPhoneFolder(MailFolder.attachments),
              ),
              4,
            ),
        ]
      : const <(Widget, int)>[];

  /// The top of the phone list, folding as it scrolls (`HomeToApprove`,
  /// variant 2): the title, search, and one row of chips with the filters
  /// (`FiltersToApprove`, variant 2).
  Widget _phoneHeader(SyncStatus status) {
    final downloading = _accountOf(status.downloading);
    return PhoneFoldingHeader(
      title: (fold) => PhoneInboxHeader(
        accounts: widget.source.accounts,
        account: _account,
        folder: _folder,
        title: _folder == MailFolder.label ? _shownLabel?.name : _mailboxName,
        onAccounts: _openAccounts,
        dimmed: status.failed,
        group: _groupOf(_listGroup),
        onGroups:
            _separate.isNotEmpty &&
                _folder == MailFolder.inbox &&
                _mailbox == null
            ? _openGroups
            : null,
        fold: fold,
        onSearch: _openSearch,
      ),
      search: PhoneSearchField(
        accounts: widget.source.accounts.length,
        account: _groupOf(_listGroup)?.name ?? _accountOf(_account)?.name,
        syncing: downloading?.name,
        onTap: _openSearch,
      ),
      chips: _hasTabs
          ? PhoneChipRow(
              tabs: InboxTabs(
                tab: _tab,
                counts: _tabs,
                onTab: _pickTab,
                unread: _onlyUnread,
                onUnread: _pickUnread,
                phone: true,
              ),
            )
          : null,
    );
  }

  /// Under the phone header, scrolling away with the list: the zones,
  /// first-sync progress, the away line, emails waiting long, and the
  /// card of an account that can't sign in.
  Widget _phoneUnder(SyncStatus status) {
    final downloading = _accountOf(status.downloading);
    final failed = _failedAccount(status);
    final zones = _phoneZones(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (zones.isNotEmpty) ZoneStrip(zones: zones),
        if (_crashed) _crashLine(const EdgeInsets.fromLTRB(20, 4, 20, 8)),
        if (downloading != null && status.total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: SyncProgress(
              account: downloading,
              done: status.done,
              total: status.total,
              now: widget.now,
            ),
          ),
        ..._awayTop(const EdgeInsets.fromLTRB(20, 4, 20, 8)),
        // Trash and spam: Empty, as at the head of the desktop's list.
        if (_emptyButton() case final empty?)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Align(alignment: Alignment.centerRight, child: empty),
          ),
        // Only when something has waited 3 days or more.
        if (_waiting.long > 0 &&
            downloading == null &&
            _folder == MailFolder.inbox &&
            _mailbox == null &&
            _everyAccount &&
            _group == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: PiumaEnter(
              child: WaitingLine(
                count: _waiting.long,
                onTap: () => _showPhoneFolder(MailFolder.waiting),
              ),
            ),
          ),
        if (failed != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: PiumaEnter(
              child: SignInCard(
                account: failed,
                onSignIn: () => showSignInAgain(
                  context,
                  source: widget.source,
                  account: failed,
                  phone: true,
                ),
                onLater: () => setState(() => _later.add(failed.id)),
              ),
            ),
          ),
      ],
    );
  }

  /// Search on the phone. A message opened from it reads over it, and
  /// Back returns to the search as it was left.
  Widget _phoneSearch() => SearchPanel(
    key: _searchKey,
    source: widget.source,
    now: widget.now,
    initialQuery: _searchQuery,
    phone: true,
    initialAccount: _account,
    initialGroup: _groupOf(_listGroup),
    onClose: _closeSearch,
    onOpen: _openFound,
    onReply: (row, body) {
      _closeSearch();
      _reply(row, body);
    },
    onArchive: (row) => _act([row], MessageAction.archive),
  );

  /// The open email on the phone. Opened from the list, a sideways swipe
  /// turns to the next or the one before ([MailPager]).
  Widget _phoneReader(MailRow reading) {
    if (_searching) return _phoneEmail(reading, true);
    return MailPager(
      row: reading,
      near: (row, step) => _list.currentState?.near(row, step),
      build: _phoneEmail,
      onTurn: _turn,
    );
  }

  /// Swiped to [row] in an open email: it is read now, as on a tap.
  void _turn(MailRow row) {
    setState(() => _selected = row.withSeen(true));
    if (!row.seen) _markSeen([row], true);
  }

  Widget _phoneEmail(MailRow reading, bool showing) {
    final reader = Reader(
      source: widget.source,
      row: reading,
      now: widget.now,
      phone: true,
      onBack: () => setState(() => _selected = null),
      onArchive: _inArchive
          ? null
          : (row) => _act([row], MessageAction.archive),
      onDelete: (row) => _act([row], MessageAction.delete),
      onMove: _canMove ? (row, _) => _move([row], phone: true) : null,
      onLabel: (row, _) => _label([row]),
      onSnooze: _canSnooze(reading)
          ? (row, _) => _snooze([row], phone: true)
          : null,
      onWake: reading.folder == MailFolder.snoozed
          ? (row) => _wake([row])
          : null,
      onWriteAgain: _waits(reading) ? _writeAgain : null,
      onStopWaiting: _waits(reading)
          ? (row) => _stopWaiting([row], reopen: false)
          : null,
      onRemind: _waits(reading)
          ? (row, _) => _remindMe(row, phone: true)
          : null,
      onReply: _inSent ? null : _reply,
      onReplyAll: _inSent ? null : _replyAll,
      onReplyList: _inSent ? null : _replyList,
      onForward: _canForward(reading) ? _forward : null,
      onForwardAttachment: _canForward(reading)
          ? (row) => _actions.forwardAsAttachment(row)
          : null,
      onRedirect: _canForward(reading) ? (row) => _actions.redirect(row) : null,
      onEditAsNew: _canForward(reading)
          ? (row) => _actions.editAsNew(row)
          : null,
      onViewSource: (row) => _actions.viewSource(row),
      onSaveEml: (row) => _actions.saveEml(row),
      onMute: (row, muted, done) => _actions.setMuted(row, muted, done: done),
      zoom: _zoom,
      onTextSize: _textSize,
      onReportSpam: _canReportSpam(reading)
          ? (row) => _act([row], MessageAction.junk)
          : null,
      onNotSpam: _inJunk(reading)
          ? (row) => _act([row], MessageAction.notJunk)
          : null,
      onQuickReply: (row, body, text, all, envelope) =>
          _quickReply(row, body, text, all: all, envelope: envelope),
      replyFrom: _replyFromOf,
      moreMenu: showing ? _more : null,
      backLabel: switch (_folder) {
        MailFolder.newsletters => AppLocalizations.of(
          context,
        ).folderNewsletters,
        MailFolder.snoozed => AppLocalizations.of(context).folderSnoozed,
        MailFolder.waiting => AppLocalizations.of(context).folderWaiting,
        MailFolder.vault => AppLocalizations.of(context).folderVault,
        MailFolder.attachments => AppLocalizations.of(
          context,
        ).folderAttachments,
        _ => null,
      },
      onUnsubscribe: (row) =>
          unsubscribeFrom(context, widget.source, row, onToast: _toast),
      onSender: (row, _) => _senderCard(row, phone: true),
      onSide: _canSide(reading) ? _side : null,
      onStar: (row, on) => _star([row], on),
      onCopy: _canMove ? (row, _) => _copy([row], phone: true) : null,
    );
    return reader;
  }

  /// The `Phone` layout: the inbox fills the screen, and reading, writing
  /// and searching each take it over, with Back to return.
  Widget _phone(BuildContext context) {
    final c = PiumaTheme.of(context);
    final composing = _composing;
    final reading = _selected;
    final picking = _picked.isNotEmpty;
    final Widget page;
    Widget? compose;
    if (composing != null) {
      compose = ComposePane(
        key: ValueKey(_composeRound),
        accounts: widget.source.accounts,
        initial: composing,
        error: _composeError,
        signatures: _signatures,
        aliases: _aliases,
        groups: _groups,
        onManageSignatures: (id) =>
            _openSettings(section: SettingsSection.writing, signature: id),
        onSend: _send,
        onSchedule: _schedule,
        now: widget.now,
        onClose: _closeCompose,
        onDiscard: _discardCompose,
        onSave: widget.source.saveDraft,
        templates: widget.source.templates,
        suggest: widget.source.suggestRecipients,
        onSaveTemplate: widget.source.saveTemplate,
        onTemplateUsed: widget.source.templateUsed,
        onManageTemplates: () =>
            _openSettings(section: SettingsSection.templates),
        phone: true,
      );
    }
    if (_folder == MailFolder.attachments) {
      page = PhoneAttachments(
        source: widget.source,
        now: widget.now,
        account: _account,
        onBack: () => _showPhoneFolder(MailFolder.inbox),
        onOpen: _open,
        onToast: _toast,
      );
    } else if (_folder == MailFolder.vault) {
      page = PhoneVault(
        source: widget.source,
        now: widget.now,
        account: _account,
        onBack: () => _showPhoneFolder(MailFolder.inbox),
        onOpen: _open,
        onToast: _toast,
        onCategory: (c) => setState(() => _vaultPage = c),
      );
    } else if (_folder == MailFolder.newsletters && _mailbox == null) {
      page = PhoneNewsletters(
        source: widget.source,
        now: widget.now,
        account: _account,
        onBack: () => _showPhoneFolder(MailFolder.inbox),
        onOpen: _open,
      );
    } else {
      page = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (picking)
            PhoneSelectHeader(
              count: _picked.length,
              total: _total,
              onCancel: _unpickAll,
              onAll: _pickAll,
            )
          else
            ValueListenableBuilder<SyncStatus>(
              valueListenable: widget.source.status,
              builder: (context, status, _) => _phoneAbove(status),
            ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: picking ? BorderSide(color: c.line) : BorderSide.none,
                ),
              ),
              child: MessageList(
                key: _list,
                source: widget.source,
                folder: _folder,
                account: _account,
                mailbox: _listMailbox,
                tab: _listTab,
                unread: _listUnread,
                group: _listGroup,
                now: widget.now,
                selected: null,
                onSelect: _open,
                onOutbox: _openOutgoing,
                phone: true,
                picked: _picked.keys.toSet(),
                onPick: _pick,
                onTotal: (n) {
                  if (n != _total) setState(() => _total = n);
                },
                onNoticeArchive: (rows) => _act(rows, MessageAction.archive),
                onSwipe: picking ? null : _swipeArchive,
                swipeAs: _swipeAs,
                leftSwipeAs: _leftSwipeAs,
                onSnoozeSwipe: picking ? null : _swipeSnooze,
                rightSwipe: _rightSwipe,
                leftSwipe: _leftSwipe,
                top: picking
                    ? const []
                    : [
                        ValueListenableBuilder<SyncStatus>(
                          valueListenable: widget.source.status,
                          builder: (context, status, _) => _phoneHeader(status),
                        ),
                        SliverToBoxAdapter(
                          child: ValueListenableBuilder<SyncStatus>(
                            valueListenable: widget.source.status,
                            builder: (context, status, _) =>
                                _phoneUnder(status),
                          ),
                        ),
                      ],
              ),
            ),
          ),
        ],
      );
    }
    final home = composing == null && reading == null && !_searching;
    final picked = _picked.values.toList();
    return PopScope(
      // Back from Sent or Archive returns to the inbox first.
      canPop:
          home && !picking && _folder == MailFolder.inbox && _mailbox == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || composing != null) return;
        // Back with the More menu open closes just the menu.
        if (_more.isOpen) {
          _more.close();
          return;
        }
        if (home && !picking && _vaultPage != null) {
          setState(() => _vaultPage = null);
          return;
        }
        if (home && !picking) {
          _showPhoneFolder(MailFolder.inbox);
          return;
        }
        setState(() {
          if (!(_searching && reading != null)) _searching = false;
          _selected = null;
          _picked.clear();
        });
      },
      child: Scaffold(
        backgroundColor: c.surface,
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                child: PhoneLayers(
                  layers: [
                    // PhoneLayers moves them: a screen that comes up grows
                    // out of what was touched; a folder switch is instant.
                    KeyedSubtree(
                      key: ValueKey(('list', _folder)),
                      // The compose button lives on the list, so a draft
                      // shrinking back into it is drawn over it.
                      child: Stack(
                        children: [
                          Positioned.fill(child: page),
                          if (home &&
                              !picking &&
                              _folder != MailFolder.newsletters &&
                              _folder != MailFolder.vault &&
                              _folder != MailFolder.attachments)
                            Positioned(
                              right: ComposeFab.right,
                              bottom: ComposeFab.bottom,
                              child: ComposeFab(
                                onTap: _openCompose,
                                raised: _toastUp,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_folder == MailFolder.vault && _vaultPage != null)
                      KeyedSubtree(
                        key: ValueKey(('vault', _vaultPage)),
                        child: PhoneVaultPage(
                          source: widget.source,
                          now: widget.now,
                          account: _account,
                          category: _vaultPage!,
                          onBack: () => setState(() => _vaultPage = null),
                          onOpen: _open,
                          onToast: _toast,
                          onCategory: (c) => setState(() => _vaultPage = c),
                        ),
                      ),
                    if (_searching)
                      KeyedSubtree(
                        key: const ValueKey('search'),
                        child: _phoneSearch(),
                      ),
                    if (reading != null)
                      KeyedSubtree(
                        key: const ValueKey('reader'),
                        child: _phoneReader(reading),
                      ),
                    if (compose != null)
                      KeyedSubtree(
                        key: ValueKey(('compose', _composeRound)),
                        child: compose,
                      ),
                  ],
                  canFollow: () => !_more.isOpen,
                  onBack: () => Navigator.maybePop(context),
                ),
              ),
            ),
            if (home && picking)
              Positioned(
                left: 12,
                right: 12,
                bottom: 28 + MediaQuery.paddingOf(context).bottom,
                child: PiumaEnter(
                  child: PhoneSelectBar(
                    allRead: picked.every((r) => r.seen),
                    onArchive: _folder == MailFolder.archive || _showingJunk
                        ? null
                        : () => _act(picked, MessageAction.archive),
                    onNotSpam: _showingJunk
                        ? () => _act(picked, MessageAction.notJunk)
                        : null,
                    onSeen: (seen) {
                      _markSeen(picked, seen);
                      _refreshPicked(seen);
                    },
                    onDelete: () => _act(picked, MessageAction.delete),
                    onMove: _oneAccount(picked)
                        ? () => _move(picked, phone: true)
                        : null,
                    onSnooze: _snoozable
                        ? () => _snooze(picked, phone: true)
                        : null,
                    onMore: _folder == MailFolder.drafts
                        ? null
                        : () => _phoneSelectMore(picked),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _desktop(BuildContext context, double width) {
    final c = PiumaTheme.of(context);
    final rail = _tablet || width < railBelow;
    _stacked = _tabletTall || (!_tablet && width < stackBelow);
    return Scaffold(
      backgroundColor: c.bg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tabletTall)
            const SizedBox.shrink()
          else if (_tablet)
            TabletRail(
              accounts: widget.source.accounts,
              folder: _folder,
              unread: _unread,
              account: _account,
              mailbox: _mailbox != null,
              onCompose: _openCompose,
              onFolder: _showFolder,
              onAccounts: _openAccounts,
            )
          else
            SizedBox(
              width: rail ? Sidebar.railWidth : 240,
              child: Sidebar(
                rail: rail,
                accounts: widget.source.accounts,
                unread: _unread,
                drafts: _drafts,
                snoozed: _snoozed > 0 ? _snoozed : null,
                waiting: _waiting.all > 0 ? _waiting.long : null,
                onAddAccount: widget.onAddAccount,
                onCompose: _openCompose,
                onSearch: _openSearch,
                onSettings: () => _openSettings(),
                folder: _folder,
                onFolder: _showFolder,
                account: _account,
                onAccount: _showAccount,
                folders: _ownFolders,
                mailbox: _mailbox,
                onMailbox: _showMailbox,
                groups: _groups,
                groupUnread: _groupUnread,
                group: _listGroup,
                onGroup: _showGroup,
                onNewGroup: () =>
                    _openSettings(section: SettingsSection.groups),
                labels: _labels,
                label: _folder == MailFolder.label ? _labelKeyword : null,
                onLabel: _showLabel,
                onNewLabel: () =>
                    showLabelEditor(context, source: widget.source),
                savedSearches: _saved,
                onSavedSearch: (s) => _openSearch(s.query),
                onEditSavedSearch: (s) => showSavedSearchEditor(
                  context,
                  source: widget.source,
                  saved: s,
                ),
                newsletters: _letters.$1 > 0 ? _letters.$2 : null,
                vault: _hasVault
                    ? VaultView(
                        _vaultCards,
                        widget.now(),
                        certified: _certified,
                      ).waiting
                    : null,
                attachments: _files.isNotEmpty
                    ? newFiles(_files, widget.now())
                    : null,
                syncedDevices: _synced,
                starred: _starred > 0 ? _starred : null,
                onDropRows: _dropRows,
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _tabletTall && _boardShown
                      // The boards have no list header: the sections
                      // sit over them.
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ColoredBox(
                              color: c.surface,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  24,
                                  20,
                                  12,
                                ),
                                child: _tallSections(),
                              ),
                            ),
                            Expanded(child: _main(context, rail: rail)),
                          ],
                        )
                      : _main(context, rail: rail),
                ),
                if (_searching) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _closeSearch,
                      child: ColoredBox(color: c.scrim),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Center(
                        child: PiumaEnter(
                          child: SearchPanel(
                            key: ValueKey(_searchQuery),
                            source: widget.source,
                            now: widget.now,
                            initialQuery: _searchQuery,
                            initialAccount: _account,
                            initialGroup: _groupOf(_listGroup),
                            onClose: _closeSearch,
                            onOpen: _openFound,
                            onReply: (row, body) {
                              _closeSearch();
                              _reply(row, body);
                            },
                            onArchive: (row) =>
                                _act([row], MessageAction.archive),
                            onOpenWindow: widget.onOpenWindow,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (_palette) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _closePalette,
                      child: ColoredBox(color: c.scrim),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 110, 16, 16),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: PiumaEnter(child: _commandPalette(context)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _main(BuildContext context, {required bool rail}) {
    final c = PiumaTheme.of(context);
    if (_folder == MailFolder.newsletters &&
        _mailbox == null &&
        _composing == null) {
      return _newsletters(context, rail: rail);
    }
    if (_folder == MailFolder.vault || _folder == MailFolder.attachments) {
      return _board(context);
    }
    final picking = _picked.isNotEmpty;
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_groupOf(_listGroup) case final g? when !picking)
          _GroupHeader(
            group: g,
            scope: _listGroup!,
            unread: _groupUnread[g.id]?.unread ?? 0,
            onClear: () => _showGroup(GroupScope(g.id)),
          )
        else
          _ListHeader(
            source: widget.source,
            unread: _unread,
            folder: _folder,
            account: _accountOf(_account),
            mailbox: _mailboxName,
            label: _folder == MailFolder.label ? _shownLabel : null,
            labelAccounts: _labelAccounts,
            onShowAll: () => _showAccount(null),
            picked: _picked.length,
            total: _total,
            onPickAll: _pickAll,
            onUnpickAll: _unpickAll,
            trailing: _tabletTall && !picking
                ? _tallActions()
                : picking
                ? null
                : _emptyButton(),
          ),
        if ((_tablet || _tabletTall) && !picking)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TabletSearchField(onTap: _openPalette),
          ),
        if (_tabletTall && !picking)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: _tallSections(),
          ),
        if (_hasTabs && !picking)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: InboxTabs(
              tab: _tab,
              counts: _tabs,
              onTab: _pickTab,
              unread: _onlyUnread,
              onUnread: _pickUnread,
            ),
          ),
        // A server that keeps no keywords: a quiet line per account.
        if (_folder == MailFolder.label && !picking)
          for (final a in widget.source.accounts)
            if (widget.source.labelsLocal(a.id))
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                child: Text(
                  AppLocalizations.of(context).labelsLocalNote(a.name),
                  style: PiumaType.small.copyWith(
                    fontSize: 12,
                    color: PiumaTheme.of(context).muted,
                  ),
                ),
              ),
        ValueListenableBuilder<SyncStatus>(
          valueListenable: widget.source.status,
          builder: (context, status, _) {
            final failed = _failedAccount(status);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (status.offline)
                  const PiumaEnter(child: OfflineBanner(phone: false)),
                ..._awayTop(const EdgeInsets.fromLTRB(12, 8, 12, 0)),
                if (_crashed)
                  _crashLine(const EdgeInsets.fromLTRB(12, 8, 12, 0)),
                if (failed != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: PiumaEnter(
                      child: SignInCard(
                        account: failed,
                        onSignIn: () => showSignInAgain(
                          context,
                          source: widget.source,
                          account: failed,
                          phone: false,
                        ),
                        onLater: () => setState(() => _later.add(failed.id)),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        Expanded(
          child: MessageList(
            key: _list,
            source: widget.source,
            folder: _folder,
            account: _account,
            mailbox: _listMailbox,
            tab: _listTab,
            unread: _listUnread,
            group: _listGroup,
            now: widget.now,
            // Alone in the window, the list marks nothing as open.
            selected: _stacked ? null : _selected?.key,
            onSelect: _open,
            onOutbox: _openOutgoing,
            picked: _picked.keys.toSet(),
            onPick: _pick,
            onTotal: (n) {
              if (n != _total) setState(() => _total = n);
            },
            // A tablet's rows are the phone's, with its swipes.
            phone: _tablet || _tabletTall,
            onNoticeArchive: (rows) => _act(rows, MessageAction.archive),
            onSwipe: (_tablet || _tabletTall) && !picking
                ? _swipeArchive
                : null,
            swipeAs: _tablet || _tabletTall ? _swipeAs : null,
            swipeHint: _tablet && !picking,
            leftSwipeAs: _tablet || _tabletTall ? _leftSwipeAs : null,
            onSnoozeSwipe: (_tablet || _tabletTall) && !picking
                ? _swipeSnooze
                : null,
            rightSwipe: _tablet || _tabletTall ? _rightSwipe : null,
            leftSwipe: _tablet || _tabletTall ? _leftSwipe : null,
            dragRows: _tablet || _tabletTall ? null : _dragged,
          ),
        ),
      ],
    );
    if (_stacked) {
      // One pane at a time: the message or compose covers the list.
      final covered =
          _composing != null || (_readerUp && _selected != null && !picking);
      final picked = _picked.values.toList();
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: _tablet || _tabletTall
              ? null
              : Border(left: BorderSide(color: c.line)),
        ),
        child: covered && !_tabletTall
            ? Listener(
                // The mouse's Back button goes back too.
                onPointerDown: (e) {
                  if (e.buttons & kBackMouseButton != 0) _closeStacked();
                },
                child: PiumaEnter(
                  key: const ValueKey('covered'),
                  child: _pane(stacked: true),
                ),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: KeyedSubtree(
                      key: const ValueKey('list'),
                      child: list,
                    ),
                  ),
                  // `TabletPortrait`: the message in a panel over the list.
                  if (covered)
                    Positioned(
                      top: 14,
                      right: 14,
                      bottom: 14,
                      width: 520,
                      child: PiumaEnter(
                        key: const ValueKey('panel'),
                        child: TabletPanel(child: _pane(stacked: true)),
                      ),
                    ),
                  if (picking)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: PiumaEnter(
                            child: PhoneSelectBar(
                              allRead: picked.every((r) => r.seen),
                              onArchive:
                                  _folder == MailFolder.archive || _showingJunk
                                  ? null
                                  : () => _act(picked, MessageAction.archive),
                              onNotSpam: _showingJunk
                                  ? () => _act(picked, MessageAction.notJunk)
                                  : null,
                              onSeen: (seen) {
                                _markSeen(picked, seen);
                                _refreshPicked(seen);
                              },
                              onDelete: () =>
                                  _act(picked, MessageAction.delete),
                              onMove: _oneAccount(picked)
                                  ? () => _move(picked)
                                  : null,
                              onSnooze: _snoozable
                                  ? () => _snooze(picked)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: _tablet || _tabletTall
            ? null
            : Border(left: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _tablet ? 380 : (rail ? 360 : 400),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: c.line)),
            ),
            child: list,
          ),
          Expanded(child: _pane(stacked: false)),
        ],
      ),
    );
  }

  /// `DesktopCaveau` and `DesktopAllegati`: the cards fill the pane; an
  /// opened email covers them, with Back to return, as does compose.
  Widget _board(BuildContext context) {
    final c = PiumaTheme.of(context);
    final covered = _composing != null || (_readerUp && _selected != null);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: _tablet || _tabletTall
            ? null
            : Border(left: BorderSide(color: c.line)),
      ),
      // The board itself has no entrance: its cards have theirs.
      child: covered
          ? PiumaEnter(
              child: Listener(
                onPointerDown: (e) {
                  if (e.buttons & kBackMouseButton != 0) {
                    setState(() => _readerUp = false);
                  }
                },
                child: _pane(stacked: true),
              ),
            )
          : _folder == MailFolder.attachments
          ? AttachmentBoard(
              key: ValueKey(_filesQuery),
              initialQuery: _filesQuery,
              source: widget.source,
              now: widget.now,
              account: _account,
              onOpen: _open,
              onToast: _toast,
            )
          : VaultBoard(
              source: widget.source,
              now: widget.now,
              account: _account,
              onOpen: _open,
              onToast: _toast,
            ),
    );
  }

  /// The phone tile: what is waiting, and the nearest day.
  Widget _vaultTile(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    final view = VaultView(_vaultCards, now, certified: _certified);
    return VaultTile(
      status: vaultStatus(l, view, now, locale),
      urgent: view.needs.isNotEmpty,
      onTap: () => _showPhoneFolder(MailFolder.vault),
    );
  }

  /// `DesktopEdicola`: the issues beside the open one, set as an article.
  Widget _newsletters(BuildContext context, {required bool rail}) {
    final c = PiumaTheme.of(context);
    final list = NewsletterList(
      source: widget.source,
      now: widget.now,
      account: _account,
      selected: _stacked ? null : _selected?.key,
      onSelect: _open,
    );
    final pane = NewsletterPane(
      source: widget.source,
      row: _selected,
      now: widget.now,
      onBack: _stacked ? () => setState(() => _readerUp = false) : null,
      // Straight to the source: the open row still says unread.
      onReadLater: (row) async {
        final l = AppLocalizations.of(context);
        try {
          await widget.source.setSeen([row], false);
          if (mounted) _toast(l.readLaterDone);
        } catch (_) {
          if (mounted) _toast(l.seenFailed);
        }
      },
      onToast: _toast,
    );
    final decoration = BoxDecoration(
      color: c.surface,
      border: _tablet || _tabletTall
          ? null
          : Border(left: BorderSide(color: c.line)),
    );
    if (_stacked) {
      final covered = _readerUp && _selected != null;
      return DecoratedBox(
        decoration: decoration,
        child: PiumaEnter(key: ValueKey(covered), child: covered ? pane : list),
      );
    }
    return DecoratedBox(
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _tablet ? 380 : (rail ? 360 : 400),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: c.line)),
            ),
            child: list,
          ),
          Expanded(child: pane),
        ],
      ),
    );
  }

  /// What sits beside the list: compose, the selection, or the message.
  Widget _pane({required bool stacked}) => switch (_composing) {
    final draft? => ComposePane(
      key: ValueKey(_composeRound),
      accounts: widget.source.accounts,
      initial: draft,
      error: _composeError,
      signatures: _signatures,
      aliases: _aliases,
      groups: _groups,
      onManageSignatures: (id) =>
          _openSettings(section: SettingsSection.writing, signature: id),
      onSend: _send,
      onSchedule: _schedule,
      now: widget.now,
      onClose: _closeCompose,
      onDiscard: _discardCompose,
      onSave: widget.source.saveDraft,
      templates: widget.source.templates,
      suggest: widget.source.suggestRecipients,
      onSaveTemplate: widget.source.saveTemplate,
      onTemplateUsed: widget.source.templateUsed,
      onManageTemplates: () =>
          _openSettings(section: SettingsSection.templates),
    ),
    null when _picked.isNotEmpty => SelectionPanel(
      rows: _picked.values.toList(),
      onArchive: _folder == MailFolder.archive || _showingJunk
          ? null
          : () => _act(_picked.values.toList(), MessageAction.archive),
      onNotSpam: _showingJunk
          ? () => _act(_picked.values.toList(), MessageAction.notJunk)
          : null,
      onDelete: () => _act(_picked.values.toList(), MessageAction.delete),
      onMove: _oneAccount(_picked.values)
          ? (at) => _move(_picked.values.toList(), anchor: at)
          : null,
      onLabel: _folder == MailFolder.drafts
          ? null
          : (at) => _label(_picked.values.toList(), anchor: at),
      onSnooze: _snoozable
          ? (at) => _snooze(_picked.values.toList(), anchor: at)
          : null,
      onSeen: (seen) {
        _markSeen(_picked.values.toList(), seen);
        _refreshPicked(seen);
      },
      onStar: _folder == MailFolder.drafts
          ? null
          : (on) => _star(_picked.values.toList(), on),
      onCopy: _oneAccount(_picked.values) && _folder != MailFolder.drafts
          ? (at) => _copy(_picked.values.toList(), anchor: at)
          : null,
    ),
    null => Reader(
      source: widget.source,
      row: _selected,
      now: widget.now,
      onBack: stacked ? () => setState(() => _readerUp = false) : null,
      tablet: (_tablet && !stacked) || _tabletTall,
      backLabel: switch (_folder) {
        MailFolder.waiting => AppLocalizations.of(context).folderWaiting,
        MailFolder.vault => AppLocalizations.of(context).folderVault,
        MailFolder.attachments => AppLocalizations.of(
          context,
        ).folderAttachments,
        _ => null,
      },
      // Archived mail is already in Archive; a reply to your own
      // message would go back to you.
      onArchive: _inArchive
          ? null
          : (row) => _act([row], MessageAction.archive),
      onDelete: (row) => _act([row], MessageAction.delete),
      onMove: _canMove ? (row, at) => _move([row], anchor: at) : null,
      onSnooze: _canSnooze(_selected)
          ? (row, at) => _snooze([row], anchor: at)
          : null,
      onWake: _selected?.folder == MailFolder.snoozed
          ? (row) => _wake([row])
          : null,
      onWriteAgain: _waits(_selected) ? _writeAgain : null,
      onStopWaiting: _waits(_selected) ? (row) => _stopWaiting([row]) : null,
      onRemind: _waits(_selected)
          ? (row, at) => _remindMe(row, anchor: at)
          : null,
      onReply: _inSent ? null : _reply,
      onReplyAll: _inSent ? null : _replyAll,
      onReplyList: _inSent ? null : _replyList,
      onForward: _canForward(_selected) ? _forward : null,
      onForwardAttachment: _canForward(_selected)
          ? (row) => _actions.forwardAsAttachment(row)
          : null,
      onRedirect: _canForward(_selected)
          ? (row) => _actions.redirect(row)
          : null,
      onEditAsNew: _canForward(_selected)
          ? (row) => _actions.editAsNew(row)
          : null,
      onViewSource: (row) => _actions.viewSource(row),
      onSaveEml: (row) => _actions.saveEml(row),
      onMute: (row, muted, done) => _actions.setMuted(row, muted, done: done),
      zoom: _zoom,
      onTextSize: _textSize,
      onQuickReply: _inSent
          ? null
          : (row, body, text, all, envelope) =>
                _quickReply(row, body, text, all: all, envelope: envelope),
      replyFrom: _replyFromOf,
      onSender: (row, at) => _senderCard(row, anchor: at),
      onLabel: (row, at) => _label([row], anchor: at),
      // The open row may say read still: it is the opposite until now.
      onSeen: (row, seen) => _markSeen([row.withSeen(!seen)], seen),
      onSide: _canSide(_selected) ? _side : null,
      onReportSpam: _canReportSpam(_selected)
          ? (row) => _act([row], MessageAction.junk)
          : null,
      onNotSpam: _inJunk(_selected)
          ? (row) => _act([row], MessageAction.notJunk)
          : null,
      onUnsubscribe: (row) =>
          unsubscribeFrom(context, widget.source, row, onToast: _toast),
      onStar: (row, on) => _star([row], on),
      onCopy: _canMove ? (row, at) => _copy([row], anchor: at) : null,
    ),
  };

  /// "Move to Notifications" or "Move to People": inbox mail someone
  /// sent.
  bool _canSide(MailRow? row) =>
      row != null &&
      row.folder == MailFolder.inbox &&
      row.fromEmail.isNotEmpty &&
      _mailbox == null;

  /// Moves [row]'s sender to the other side of the inbox from now on.
  Future<void> _side(MailRow row) async {
    final source = widget.source;
    final people = !source.byPerson(row);
    await source.setSenderSide(row.fromEmail, people);
    await _refreshTabs();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    _toast(
      people ? l.movedToPeople(row.sender) : l.movedToNotifications(row.sender),
      action: l.undo,
      onAction: () async {
        await source.setSenderSide(row.fromEmail, null);
        await _refreshTabs();
      },
    );
  }

  /// Report spam: mail someone sent, in an account with a spam folder,
  /// not already in it.
  bool _canReportSpam(MailRow? row) {
    if (row == null ||
        row.folder == MailFolder.sent ||
        row.folder == MailFolder.drafts ||
        _folder == MailFolder.waiting) {
      return false;
    }
    final junk = widget.source.junkMailbox(row.accountId);
    return junk != null && row.mailbox != junk;
  }

  /// Not spam: mail in its account's spam folder.
  bool _inJunk(MailRow? row) =>
      row != null && row.mailbox == widget.source.junkMailbox(row.accountId);

  /// Showing the spam folder, where Archive gives way to Not spam.
  bool get _showingJunk =>
      _mailbox != null && _mailbox == widget.source.junkMailbox(_account ?? -1);

  /// A sender's card, and what was picked on it.
  Future<void> _senderCard(
    MailRow row, {
    Rect? anchor,
    bool phone = false,
  }) async {
    final pick = await showSenderCard(
      context,
      source: widget.source,
      row: row,
      now: widget.now,
      anchor: anchor,
      phone: phone,
    );
    if (!mounted) return;
    switch (pick) {
      case WriteToSender():
        final to = row.fromName.isEmpty
            ? row.fromEmail
            : '${row.fromName} <${row.fromEmail}>';
        _openCompose(Draft(accountId: row.accountId, to: [to]));
      case AllFromSender():
        _openSearch('from:${row.fromEmail}');
      case OpenFromSender(:final row):
        _openFound(row);
      case RulesForSender():
        _openSettings(section: SettingsSection.organizing);
      case null:
        break;
    }
  }

  /// Sent mail and drafts have nothing to come back for.
  bool get _snoozable =>
      _folder != MailFolder.sent &&
      _folder != MailFolder.drafts &&
      _folder != MailFolder.waiting;

  bool _canSnooze(MailRow? row) =>
      _snoozable &&
      row != null &&
      row.folder != MailFolder.sent &&
      row.folder != MailFolder.drafts;

  /// The open message is in Archive already: the list is Archive, or
  /// the Vault or search opened an archived email.
  bool get _inArchive =>
      _folder == MailFolder.archive || _selected?.folder == MailFolder.archive;

  /// The open message is one you sent: nothing to reply to.
  bool get _inSent =>
      _folder == MailFolder.sent || _selected?.folder == MailFolder.sent;

  /// Drafts stay in Drafts; everything else can go to a folder.
  bool get _canMove => _folder != MailFolder.drafts;

  /// Move to lists one account's folders, so it needs rows of one account.
  bool _oneAccount(Iterable<MailRow> rows) =>
      _canMove && rows.map((r) => r.accountId).toSet().length == 1;

  /// Newsletters, the Vault or Attachments fill the pane, not a list.
  bool get _boardShown =>
      (_folder == MailFolder.newsletters &&
          _mailbox == null &&
          _composing == null) ||
      _folder == MailFolder.vault ||
      _folder == MailFolder.attachments;

  /// `TabletPortrait`: the accounts' dots and Compose beside the title.
  Widget _tallActions() => TabletTitleActions(
    accounts: widget.source.accounts,
    account: _account,
    onAccounts: _openAccounts,
    onCompose: _openCompose,
  );

  /// `TabletPortrait`: the sections as pills under the search field.
  Widget _tallSections() => TabletSections(
    folder: _mailbox == null ? _folder : null,
    newsletters: _letters.$1 > 0 ? _letters.$2 : 0,
    vault: _hasVault
        ? VaultView(_vaultCards, widget.now(), certified: _certified).waiting
        : 0,
    snoozed: _snoozed,
    onFolder: _showFolder,
  );

  /// A swipe to the right (`PhoneSwipe`): as the person set it (Archive
  /// until changed); in Waiting stop waiting, in spam Not spam.
  void _swipeArchive(MailRow row) => _folder == MailFolder.waiting
      ? _stopWaiting([row], reopen: false)
      : _inJunk(row)
      ? _act([row], MessageAction.notJunk, reopen: false)
      : _swipeDo(widget.source.listPrefs.value.swipeRight, row);

  /// What the swipe to the right says, when not Archive.
  ({PiumaIcon icon, String label})? get _swipeAs =>
      _folder == MailFolder.waiting
      ? (
          icon: PiumaIcon.hourglass,
          label: AppLocalizations.of(context).stopWaiting,
        )
      : _showingJunk
      ? (icon: PiumaIcon.inbox, label: AppLocalizations.of(context).notSpam)
      : null;

  /// What the swipe to the left says, when not Snooze: in Waiting,
  /// Remind me.
  ({PiumaIcon icon, String label})? get _leftSwipeAs =>
      _folder == MailFolder.waiting
      ? (
          icon: PiumaIcon.hourglass,
          label: AppLocalizations.of(context).remindMe,
        )
      : null;

  /// A swipe to the left: as the person set it (Snooze until tomorrow
  /// morning until changed); in Waiting it asks when to remind you.
  ValueChanged<MailRow>? get _swipeSnooze {
    if (_folder == MailFolder.waiting) {
      return (row) => _remindMe(row, phone: true);
    }
    final left = widget.source.listPrefs.value.swipeLeft;
    return switch (left) {
      SwipeChoice.nothing => null,
      SwipeChoice.snooze when !_snoozable => null,
      _ => (row) => _swipeDo(left, row),
    };
  }

  // Managing the mailbox: stars, deleting for good, emptying Trash and
  // spam, copying, rows dropped on folders, and the swipes as set.

  /// The phone's More while rows are picked: Star (or Remove star) and
  /// Copy to…, as the desktop's selection panel has them.
  Future<void> _phoneSelectMore(List<MailRow> picked) async {
    final l = AppLocalizations.of(context);
    final allStarred = picked.every((r) => r.starred);
    final copy = _oneAccount(picked);
    final choice = await showPiumaSheet<int>(
      context,
      label: l.moreActions,
      builder: (sheet) => PhoneActionList(
        items: [
          (PiumaIcon.star, allStarred ? l.unstar : l.star),
          if (copy) (PiumaIcon.copy, l.copyTo),
        ],
        onPick: (i) => Navigator.of(sheet).pop(i),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 0) {
      await _star(picked, !allStarred);
    } else {
      await _copy(picked, phone: true);
    }
  }

  /// The unread count on the app's icon, the taskbar or the title.
  void _badge(int unread) {
    final l = AppLocalizations.of(context);
    UnreadBadge.show(
      unread,
      title: l.badgeTitle(unread),
      label: l.badgeUnread(unread),
      color: PiumaTheme.of(context).accent,
    );
  }

  /// How many emails are starred, for the sidebar.
  Future<int> _starredCount() async =>
      (await widget.source.page(0, 100000, folder: MailFolder.starred)).length;

  /// Stars the rows, or takes their stars off, at once.
  Future<void> _star(List<MailRow> rows, bool starred) async {
    if (rows.isEmpty) return;
    final keys = {for (final r in rows) r.key};
    setState(() {
      if (_selected case final open? when keys.contains(open.key)) {
        _selected = open.copyWith(starred: starred);
      }
      _picked.updateAll(
        (k, r) => keys.contains(k) ? r.copyWith(starred: starred) : r,
      );
    });
    PiumaHaptics.select();
    try {
      await widget.source.setStarred(rows, starred);
    } catch (_) {
      if (mounted) _toast(AppLocalizations.of(context).starFailed);
    }
    _countUnread();
  }

  /// Delete in Trash or spam: asked first, then gone for good. False when
  /// the person said no.
  Future<bool> _deleteForever(List<MailRow> rows) async {
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    if (!await confirmDeleteForever(
          context,
          count: rows.length,
          phone: phone,
        ) ||
        !mounted) {
      return false;
    }
    final keys = {for (final r in rows) r.key};
    await _list.currentState?.fold(keys);
    if (!mounted) return true;
    for (final r in rows) {
      widget.source.setHidden(r, true);
    }
    setState(() {
      if (keys.contains(_selected?.key)) _selected = null;
      _picked.removeWhere((k, _) => keys.contains(k));
    });
    final l = AppLocalizations.of(context);
    try {
      await widget.source.deleteForever(rows);
      if (mounted) _toast(l.deletedForeverMany(rows.length));
    } catch (_) {
      for (final r in rows) {
        widget.source.setHidden(r, false);
      }
      if (mounted) _toast(l.actionFailed);
    }
    return true;
  }

  /// "Empty Trash" or "Empty spam" at the head of that folder's list.
  Widget? _emptyButton() {
    final account = _account;
    final mailbox = _mailbox;
    if (account == null || mailbox == null) return null;
    final source = widget.source;
    final l = AppLocalizations.of(context);
    final String label;
    if (mailbox == source.trashMailbox(account)) {
      label = l.emptyTrash;
    } else if (mailbox == source.junkMailbox(account)) {
      label = l.emptySpam;
    } else {
      return null;
    }
    return PiumaButton(
      label: label,
      kind: PiumaButtonKind.tertiary,
      size: PiumaButtonSize.compact,
      onPressed: _total == 0 ? null : () => _empty(account, mailbox),
    );
  }

  /// Empties Trash or spam, after saying how many emails go.
  Future<void> _empty(int account, String mailbox) async {
    final l = AppLocalizations.of(context);
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    final name = mailbox == widget.source.trashMailbox(account)
        ? l.trashFolder
        : l.spamFolder;
    var count = _total;
    try {
      count = await widget.source.folderTotal(account, mailbox);
    } catch (_) {}
    if (!mounted || count == 0) return;
    if (!await confirmEmpty(
          context,
          folder: name,
          count: count,
          phone: phone,
        ) ||
        !mounted) {
      return;
    }
    try {
      final n = await widget.source.emptyFolder(account, mailbox);
      if (mounted) _toast(l.deletedForeverMany(n));
    } catch (_) {
      if (mounted) _toast(l.emptyFailed);
    }
  }

  /// "Copy to…": the folders of the messages' account; they stay where
  /// they are.
  Future<void> _copy(
    List<MailRow> picked, {
    Rect? anchor,
    bool phone = false,
  }) async {
    if (picked.isEmpty) return;
    final account = _accountOf(picked.first.accountId);
    if (account == null || picked.any((r) => r.accountId != account.id)) {
      return;
    }
    final from = picked.first.mailbox;
    final target = await showMoveTo(
      context,
      source: widget.source,
      account: account,
      from: picked.every((r) => r.mailbox == from) ? from : '',
      anchor: anchor,
      phone: phone,
      copy: true,
    );
    if (target == null || !mounted) return;
    final l = AppLocalizations.of(context);
    try {
      await widget.source.copyTo(picked, target.mailbox);
      if (mounted) _toast(l.copiedMany(picked.length, target.name));
    } catch (_) {
      if (mounted) _toast(l.actionFailed);
    }
  }

  /// What dragging [row] carries: the picked rows when it is one of them.
  List<MailRow> _dragged(MailRow row) =>
      _picked.containsKey(row.key) ? _picked.values.toList() : [row];

  /// Rows dropped on one of an account's folders: moved there, with Undo,
  /// as "Move to…" does.
  Future<void> _dropRows(
    int account,
    String mailbox,
    List<MailRow> rows,
  ) async {
    if (rows.isEmpty) return;
    final l = AppLocalizations.of(context);
    String name = mailbox;
    for (final f in _ownFolders[account] ?? const <AccountFolder>[]) {
      if (f.mailbox == mailbox) name = f.name;
    }
    await _withUndo(
      rows,
      l.movedMany(rows.length, name),
      (rows) => widget.source.moveTo(rows, mailbox),
    );
  }

  /// The swipes as the person set them, outside Waiting and spam, where
  /// they keep their own meaning.
  SwipeSide? get _rightSwipe => _folder == MailFolder.waiting || _showingJunk
      ? null
      : _swipeSide(widget.source.listPrefs.value.swipeRight);
  SwipeSide? get _leftSwipe => _folder == MailFolder.waiting
      ? null
      : _swipeSide(widget.source.listPrefs.value.swipeLeft);

  SwipeSide _swipeSide(SwipeChoice choice) {
    final l = AppLocalizations.of(context);
    return switch (choice) {
      SwipeChoice.archive => SwipeSide(
        icon: PiumaIcon.archive,
        label: l.archive,
      ),
      SwipeChoice.snooze => SwipeSide(
        icon: PiumaIcon.clock,
        label: l.actionSnooze,
        tone: SwipeTone.warn,
      ),
      SwipeChoice.delete => SwipeSide(
        icon: PiumaIcon.trash,
        label: l.actionDelete,
        tone: SwipeTone.danger,
      ),
      SwipeChoice.read => SwipeSide(
        icon: PiumaIcon.mailOpen,
        label: l.swipeRead,
        tone: SwipeTone.accent,
        stays: true,
      ),
      SwipeChoice.star => SwipeSide(
        icon: PiumaIcon.star,
        label: l.swipeStar,
        tone: SwipeTone.warn,
        stays: true,
      ),
      SwipeChoice.move => SwipeSide(
        icon: PiumaIcon.folder,
        label: l.swipeMove,
        tone: SwipeTone.accent,
        stays: true,
      ),
      SwipeChoice.nothing => SwipeSide(
        icon: PiumaIcon.close,
        label: l.swipeNothing,
        off: true,
      ),
    };
  }

  /// What a swipe set to [choice] does to [row].
  void _swipeDo(SwipeChoice choice, MailRow row) {
    switch (choice) {
      case SwipeChoice.archive:
        if (_inArchive) return;
        _act([row], MessageAction.archive, reopen: false);
      case SwipeChoice.snooze:
        if (!_snoozable) return;
        _snooze(
          [row],
          until: snoozeTime(SnoozeChoice.tomorrow, widget.now()),
          reopen: false,
        );
      case SwipeChoice.delete:
        _act([row], MessageAction.delete, reopen: false);
      case SwipeChoice.read:
        _markSeen([row], !row.seen);
      case SwipeChoice.star:
        _star([row], !row.starred);
      case SwipeChoice.move:
        _move([row], phone: true, reopen: false);
      case SwipeChoice.nothing:
        break;
    }
  }
}

/// Narrower than this, the app takes the phone layout.
const double phoneWidth = 600;

/// Narrower than this, the desktop sidebar becomes a rail of icons.
const double railBelow = 1100;

/// Narrower than this, a message or compose covers the list instead of
/// sitting beside it.
const double stackBelow = 900;

/// The head of a group's Inbox, as on `GroupsSidebar`: its dot and name,
/// how many addresses and unread, and "Only fatture@…" while one address
/// shows.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.scope,
    required this.unread,
    required this.onClear,
  });

  final MailGroup group;
  final GroupScope scope;
  final int unread;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: group.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.84,
                      color: c.fg,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l.groupUnreadLine(group.addresses.length, unread),
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          if (scope.address case final email?) ...[
            const SizedBox(height: 14),
            PiumaPressable(
              onTap: onClear,
              semanticLabel: l.groupOnlyClear(email),
              child: ExcludeSemantics(
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  decoration: BoxDecoration(
                    color: c.chip,
                    borderRadius: BorderRadius.circular(PiumaRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          l.groupOnly(email),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.fg),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PiumaIconView(PiumaIcon.close, size: 14, color: c.muted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.source,
    required this.unread,
    this.folder = MailFolder.inbox,
    this.account,
    this.mailbox,
    this.onShowAll,
    this.picked = 0,
    this.total = 0,
    this.onPickAll,
    this.onUnpickAll,
    this.label,
    this.labelAccounts = 0,
    this.trailing,
  });

  final MailSource source;
  final int unread;
  final MailFolder folder;

  /// At the end of the line: the accounts and Compose on `TabletPortrait`.
  final Widget? trailing;

  /// The label whose emails the list shows: its dot and name are the
  /// title, "46 emails · 3 accounts" beside it.
  final MailLabel? label;
  final int labelAccounts;

  /// The one account the list shows, with Show all; null for every one.
  final MailAccount? account;
  final VoidCallback? onShowAll;

  /// The name of the account's own folder shown, if one is: it is the
  /// title, and the account is named beside it.
  final String? mailbox;

  /// While rows are picked: a select-all box before the title, "3 of 7
  /// selected" and Deselect, as in `DesktopSelect`.
  final int picked;
  final int total;
  final VoidCallback? onPickAll;
  final VoidCallback? onUnpickAll;

  String _title(AppLocalizations l) =>
      label?.name ??
      mailbox ??
      switch (folder) {
        MailFolder.inbox => l.inbox,
        MailFolder.sent => l.folderSent,
        MailFolder.archive => l.folderArchive,
        MailFolder.drafts => l.folderDrafts,
        MailFolder.newsletters => l.folderNewsletters,
        MailFolder.snoozed => l.folderSnoozed,
        MailFolder.waiting => l.folderWaiting,
        MailFolder.vault => l.folderVault,
        MailFolder.attachments => l.folderAttachments,
        MailFolder.label => l.labelsHeading,
        MailFolder.starred => l.folderStarred,
      };

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (picked > 0) ...[
            Transform.translate(
              offset: const Offset(-8, 0),
              child: Semantics(
                checked: picked >= total,
                mixed: picked < total,
                label: l.selectAll,
                child: PiumaPressable(
                  onTap: onPickAll,
                  child: SizedBox.square(
                    dimension: 32,
                    child: Center(
                      child: PickBox(
                        on: picked >= total,
                        some: picked < total,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
          Text.rich(
            TextSpan(
              children: [
                if (label case final label? when picked == 0)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: labelTint(context, label.color).$2,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                TextSpan(text: _title(l)),
              ],
            ),
            style: TextStyle(
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.84,
              color: c.fg,
            ),
          ),
          const SizedBox(width: 12),
          if (picked > 0) ...[
            Expanded(
              child: Text(
                l.pickedOf(picked, total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
            PiumaPressable(
              onTap: onUnpickAll,
              semanticLabel: l.deselect,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ExcludeSemantics(
                  child: Text(
                    l.deselect,
                    style: TextStyle(fontSize: 13, color: c.accentText),
                  ),
                ),
              ),
            ),
          ] else if (account case final a?) ...[
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: a.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    TextSpan(
                      text: mailbox == null ? l.accountOnly(a.name) : a.name,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
            if (onShowAll case final showAll? when mailbox == null)
              PiumaPressable(
                onTap: showAll,
                semanticLabel: l.showAllAccounts,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ExcludeSemantics(
                    child: Text(
                      l.showAllAccounts,
                      style: TextStyle(fontSize: 13, color: c.accentText),
                    ),
                  ),
                ),
              ),
          ] else
            Expanded(
              child: ValueListenableBuilder<SyncStatus>(
                valueListenable: source.status,
                builder: (context, s, _) {
                  final (text, color) = switch (s.phase) {
                    SyncPhase.downloading => (
                      l.downloading(
                        number.format(s.done),
                        number.format(s.total),
                      ),
                      c.muted,
                    ),
                    SyncPhase.offline => (l.offline, c.warn),
                    SyncPhase.signInFailed => (l.signInFailed, c.danger),
                    SyncPhase.idle => (
                      switch (folder) {
                        MailFolder.inbox => l.inboxSummary(
                          source.accounts.length,
                          unread,
                        ),
                        MailFolder.waiting => l.waitingSummary(total),
                        MailFolder.label when labelAccounts > 1 =>
                          '${l.labelEmails(total)} · '
                              '${l.labelAccounts(labelAccounts)}',
                        MailFolder.label => l.labelEmails(total),
                        _ => l.folderSummary(source.accounts.length),
                      },
                      c.muted,
                    ),
                  };
                  return Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: color),
                  );
                },
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}

/// "Your package arrives today · Corriere Rapido", "Due in 3 days · Enel":
/// a Vault notice's title, as the Android service writes it too.
String vaultNoticeTitle(AppLocalizations l, VaultNotice v) {
  final what = switch (v.dueIn) {
    null => l.vaultNoticeParcel,
    0 => l.vaultNoticeDueToday,
    1 => l.vaultNoticeDueTomorrow,
    final days => l.vaultNoticeDueIn(days),
  };
  return v.merchant.isEmpty ? what : '$what · ${v.merchant}';
}

/// "Desk lamp · around 10:00", "€62.40 · Electricity bill".
String vaultNoticeDetail(AppLocalizations l, VaultNotice v, String locale) {
  final parts = v.dueIn == null
      ? [v.title, if (v.time.isNotEmpty) l.vaultNoticeAround(v.time)]
      : [
          if (v.amount case final cents?)
            NumberFormat.simpleCurrency(
              locale: locale,
              name: v.currency.isEmpty ? null : v.currency,
            ).format(cents / 100),
          v.title,
        ];
  return parts.where((p) => p.isNotEmpty).join(' · ');
}

/// "12 emails, 3 from people: Sara Conti, Luca Bianchi, Dad", under
/// "While you were away", as the Android service writes it too.
String awayNoticeDetail(AppLocalizations l, AwayNotice a) {
  final all = l.noticeAwayEmails(a.emails);
  if (a.people == 0) return all;
  final from = '$all, ${l.noticeAwayPeople(a.people)}';
  return a.names.isEmpty ? from : '$from: ${a.names.join(', ')}';
}
