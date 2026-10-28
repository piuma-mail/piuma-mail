import 'dart:async';

import 'package:flutter/foundation.dart'
    show SynchronousFuture, TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:intl/intl.dart';

import '../compose/remind_me.dart';
import '../design/icons.dart';
import '../design/look.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../mail/translator.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/dialog.dart';
import '../widgets/links.dart';
import 'labels.dart';
import 'pictures.dart';
import 'attach_preview.dart';
import 'found_date.dart';
import 'inbox_screen.dart' show phoneWidth;
import 'invite_card.dart';
import 'message_body.dart';
import 'images_bar.dart';
import 'original_view.dart';
import 'print.dart';
import 'translate_parts.dart';
import 'message_list.dart' show initials;
import 'risky_file.dart';
import 'sender_warning.dart';

/// Right pane: the message being read, made safe by the engine, or its
/// whole conversation as in `FeatureThread`. Remote images wait for
/// consent unless the sender is trusted.
class Reader extends StatefulWidget {
  const Reader({
    super.key,
    required this.source,
    required this.row,
    required this.now,
    this.onArchive,
    this.onDelete,
    this.onReply,
    this.onForward,
    this.onMove,
    this.onLabel,
    this.onSnooze,
    this.onWake,
    this.onWriteAgain,
    this.onStopWaiting,
    this.onRemind,
    this.phone = false,
    this.tablet = false,
    this.onBack,
    this.onQuickReply,
    this.replyFrom,
    this.moreMenu,
    this.backLabel,
    this.onUnsubscribe,
    this.onSender,
    this.onSeen,
    this.onReportSpam,
    this.onNotSpam,
    this.onSide,
    this.printer = printEmail,
  });

  /// "Mark as unread" (or read) in the desktop's More menu, and ⇧⌘U
  /// (Ctrl Shift U off Apple) while the message is shown.
  final void Function(MailRow row, bool seen)? onSeen;

  /// "Report spam" in More: null where the account has no spam folder,
  /// or the message is already there.
  final ValueChanged<MailRow>? onReportSpam;

  /// "Not spam" in the spam folder, in its place (`ProtectionToApprove`):
  /// a button in the desktop's bar, and in More.
  final ValueChanged<MailRow>? onNotSpam;

  /// "Move to Notifications" (or People) in the More menus: the sender's
  /// inbox mail to the other side from now on. Null outside the inbox.
  final ValueChanged<MailRow>? onSide;

  /// Print, or save as PDF: the system's print window, by default.
  final PrintHook printer;

  /// What "‹ Inbox" says on the phone, when it goes back elsewhere.
  final String? backLabel;

  /// Unsubscribe, in More, for mail whose list can be left.
  final ValueChanged<MailRow>? onUnsubscribe;

  /// The sender's name was tapped: their card, under [anchor].
  final void Function(MailRow row, Rect anchor)? onSender;

  /// The phone's More menu, so system Back can close it before the
  /// message.
  final MenuController? moreMenu;

  final MailSource source;
  final MailRow? row;
  final DateTime Function() now;
  final ValueChanged<MailRow>? onArchive;
  final ValueChanged<MailRow>? onDelete;

  /// "Move to…", with where its button is (null on the phone, where the
  /// folders come up in a sheet).
  final void Function(MailRow row, Rect? anchor)? onMove;

  /// "Label…" in the More menus: the labels, with where More is on the
  /// desktop (null on the phone and tablet, where they come up in a sheet
  /// or a dialog).
  final void Function(MailRow row, Rect? anchor)? onLabel;

  /// "Snooze until…", with where its button is (null on the phone).
  final void Function(MailRow row, Rect? anchor)? onSnooze;

  /// Brings a snoozed message back to the inbox now.
  final ValueChanged<MailRow>? onWake;

  /// In Waiting (`WaitingToApprove`): a reply to your own email, with its
  /// text once loaded, and taking it out of Waiting.
  final void Function(MailRow row, String body)? onWriteAgain;
  final ValueChanged<MailRow>? onStopWaiting;

  /// "Remind me if nobody replies", next to Write again: its choices
  /// under the chip (null on the phone, where they come up in a sheet).
  final void Function(MailRow row, Rect? anchor)? onRemind;

  /// Called with the message, its text once loaded, and any words
  /// already typed in the quick reply box.
  final void Function(MailRow row, String body, [String text])? onReply;

  /// Forward, as on `ForwardToApprove`: next to Reply on the desktop, in
  /// More on the phone.
  final ValueChanged<MailRow>? onForward;

  /// The `PhoneRead` layout: "‹ Inbox" with Archive and More on top, and
  /// the quick reply bar at the foot.
  final bool phone;

  /// The `Tablet` layout: no toolbar on top, and Reply, Archive, Snooze
  /// and More in a bar floating over the foot of the message.
  final bool tablet;
  final VoidCallback? onBack;

  /// Sends [text] as a reply to the message, whose text is [body].
  final void Function(MailRow row, String body, String text)? onQuickReply;

  /// Where a reply to the message goes from, when that is one of the
  /// account's other addresses, and the signature it takes: the line
  /// under the reply box, as on `GroupsSidebar`.
  final ReplyFrom? Function(MailRow row)? replyFrom;

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  late final _images = RemoteImages(widget.source);
  final _replyText = TextEditingController();

  /// The conversation's messages, when the row is one.
  Future<List<MailRow>>? _thread;
  ThreadBrief? _brief;
  StreamSubscription<ThreadBrief?>? _briefs;

  /// Messages opened or closed by hand, by key.
  final _opened = <Object, bool>{};

  /// "6 read messages" was pressed.
  bool _showAll = false;

  /// "In short" on the phone, shown by the Summary button.
  bool _briefShown = false;

  /// The subject translated, while a message shows translated.
  String? _subject;

  /// The messages showing translated, by key: they print as they show.
  final _translations = <Object, Readable>{};

  /// Read or unread as set from More or its key since it opened; until
  /// then, as the row says.
  bool? _seenNow;

  /// "Original layout" for each message shown that has one and shows
  /// its reading view, by key.
  final _layouts = <Object, VoidCallback>{};

  /// Whether the open email's list can be left, once known: More's
  /// Unsubscribe shows only then.
  bool _leavable = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_printKey);
    HardwareKeyboard.instance.addHandler(_seenKey);
    _load();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_printKey);
    HardwareKeyboard.instance.removeHandler(_seenKey);
    _briefs?.cancel();
    _replyText.dispose();
    super.dispose();
  }

  /// ⇧⌘U on Apple, Ctrl+Shift+U elsewhere: unread, or read again, while
  /// a message is shown and nothing covers it.
  bool _seenKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyU) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    final mod = _apple ? keys.isMetaPressed : keys.isControlPressed;
    if (!mod || !keys.isShiftPressed || keys.isAltPressed) return false;
    // A text field keeps it (Ctrl+Shift+U types a character on Linux).
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final row = widget.row;
    if (!mounted || row == null || _seen(row) == null) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _seen(row)!();
    return true;
  }

  /// Mark as unread, or as read once it was marked unread.
  VoidCallback? _seen(MailRow row) {
    final onSeen = widget.onSeen;
    if (onSeen == null || row.folder == MailFolder.drafts) return null;
    return () {
      final seen = !(_seenNow ?? row.seen);
      setState(() => _seenNow = seen);
      onSeen(row, seen);
    };
  }

  /// A message view says whether it can show its original layout now.
  void _layout(Object key, VoidCallback? show) {
    if (show == null) {
      if (_layouts.remove(key) == null) return;
    } else {
      if (_layouts[key] == show) return;
      _layouts[key] = show;
    }
    if (!mounted) return;
    // Told while the tree is being built: draw the toolbar again after.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// "Original layout" for the message opened, else the last one shown
  /// that has one.
  VoidCallback? _original(MailRow row) =>
      _layouts[row.key] ?? _layouts.values.lastOrNull;

  /// ⌘P on Apple, Ctrl+P elsewhere, while a message is shown and nothing
  /// covers it.
  bool _printKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyP) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    final mod = _apple ? keys.isMetaPressed : keys.isControlPressed;
    if (!mod || keys.isShiftPressed || keys.isAltPressed) return false;
    final row = widget.row;
    if (!mounted || row == null) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    _print(row);
    return true;
  }

  static bool get _apple =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Print, or save as PDF: the email as it shows, a conversation's
  /// every message oldest first, translated where it shows translated.
  Future<void> _print(MailRow row) async {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final source = widget.source;
    final account = source.accounts
        .where((a) => a.id == row.accountId)
        .firstOrNull;
    final thread = _thread;
    final messages = thread == null
        ? [row]
        : await thread.catchError((Object _) => [row]);
    final printed = <PrintMessage>[];
    for (final m in messages) {
      final readable = await source
          .readable(m)
          .then<Readable?>((r) => r, onError: (Object _) => null);
      final translation = _translations[m.key];
      var text = translation != null
          ? _plainText(translation, endQuote: thread == null)
          : await source.body(m).catchError((Object _) => '');
      // A conversation folds each message's quote away, as it shows.
      if (thread != null && translation == null) text = withoutEndQuote(text);
      final files = readable?.attachments ?? const <MailAttachment>[];
      final t = m.receivedAt;
      printed.add(
        PrintMessage(
          from: m.fromName.isEmpty
              ? m.fromEmail
              : '${m.fromName} <${m.fromEmail}>',
          to: m.to.isNotEmpty ? m.to : (_mine(m) ? '' : account?.email ?? ''),
          date: l.forwardDate(
            DateFormat.yMMMEd(locale).format(t),
            DateFormat.Hm(locale).format(t),
          ),
          text: text,
          attachments: files.isEmpty
              ? ''
              : l.printAttachments(
                  files
                      .map(
                        (a) =>
                            '${a.name} (${fileSize(a.size, locale: locale)})',
                      )
                      .join(', '),
                ),
        ),
      );
    }
    if (!mounted) return;
    try {
      await widget.printer(
        PrintEmail(
          subject:
              _subject ?? (row.subject.isEmpty ? l.noSubject : row.subject),
          messages: printed,
          fromLabel: l.from,
          toLabel: l.to,
          dateLabel: l.printDate,
        ),
      );
    } catch (_) {
      // The print window couldn't open: nothing was lost.
    }
  }

  /// [r]'s words as plain text, quotes marked with ">"; without the quote
  /// it ends with unless [endQuote].
  static String _plainText(Readable r, {required bool endQuote}) {
    final end = endQuote ? r.blocks.length : r.quoteStart;
    return [
      for (final b in r.blocks.take(end))
        if (b.kind != BlockKind.image && b.kind != BlockKind.rule)
          '> ' * b.quote +
              (b.kind == BlockKind.listItem ? '${b.marker} ' : '') +
              b.text,
    ].join('\n\n');
  }

  @override
  void didUpdateWidget(Reader old) {
    super.didUpdateWidget(old);
    if (old.row?.key != widget.row?.key) {
      _replyText.clear();
    }
    if (old.row?.key != widget.row?.key ||
        old.row?.messages != widget.row?.messages) {
      _load();
    }
  }

  /// The conversation last drawn, and whose.
  (Object, List<MailRow>)? _threadShown;

  void _load() {
    final row = widget.row;
    _opened.clear();
    _showAll = false;
    _briefShown = false;
    _subject = null;
    _translations.clear();
    _seenNow = null;
    _layouts.clear();
    _leavable = false;
    if (row != null && widget.onUnsubscribe != null) {
      widget.source
          .unsubscribeInfo(row)
          .then((info) {
            if (!mounted || widget.row?.key != row.key) return;
            setState(() => _leavable = info.kind != UnsubscribeKind.none);
          })
          .catchError((Object _) {});
    }
    _thread = row != null && row.isConversation
        ? widget.source.conversation(row)
        : null;
    _brief = null;
    _briefs?.cancel();
    _briefs =
        row != null &&
            row.isConversation &&
            widget.source.features.value.inShort
        ? _briefOf(row).listen((b) {
            if (mounted) setState(() => _brief = b);
          })
        : null;
  }

  /// The rules' brief at once, then the device model's words when it has
  /// a model and they hold up.
  Stream<ThreadBrief?> _briefOf(MailRow row) async* {
    final source = widget.source;
    final rules = await source.threadBrief(row).catchError((Object _) => null);
    yield rules;
    if (rules == null) return;
    final better = await source
        .rewriteBrief(rules)
        .catchError((Object _) => null);
    if (better != null) yield better;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = widget.row;
    if (row == null) return _NoneSelected(touch: widget.tablet);
    MailAccount? account;
    for (final a in widget.source.accounts) {
      if (a.id == row.accountId) account = a;
    }
    final locale = Localizations.localeOf(context).toLanguageTag();

    final phone = widget.phone;
    final tablet = widget.tablet && !phone;
    final onArchive = widget.onArchive == null
        ? null
        : () => widget.onArchive!(row);
    final onDelete = widget.onDelete == null
        ? null
        : () => widget.onDelete!(row);
    final onMove = widget.onMove == null
        ? null
        : (Rect? at) => widget.onMove!(row, at);
    final onSnooze = widget.onSnooze == null
        ? null
        : (Rect? at) => widget.onSnooze!(row, at);
    final onWake = widget.onWake == null ? null : () => widget.onWake!(row);
    final onReply = widget.onReply == null
        ? null
        : () async {
            final text = _replyText.text.trim();
            _replyText.clear();
            FocusManager.instance.primaryFocus?.unfocus();
            final body = await widget.source.body(row).catchError((_) => '');
            widget.onReply!(row, body, text);
          };
    final onForward = widget.onForward == null
        ? null
        : () => widget.onForward!(row);
    final onWriteAgain = widget.onWriteAgain == null
        ? null
        : () async {
            final body = await widget.source.body(row).catchError((_) => '');
            widget.onWriteAgain!(row, body);
          };
    final onStopWaiting = widget.onStopWaiting == null
        ? null
        : () => widget.onStopWaiting!(row);
    final onRemind = widget.onRemind == null
        ? null
        : (Rect? at) => widget.onRemind!(row, at);
    final remindLabel = remindChipLabel(
      row.remindAt,
      widget.now(),
      AppLocalizations.of(context),
      Localizations.localeOf(context).toLanguageTag(),
    );
    void onPrint() => _print(row);
    final onReportSpam = widget.onReportSpam == null
        ? null
        : () => widget.onReportSpam!(row);
    final onNotSpam = widget.onNotSpam == null
        ? null
        : () => widget.onNotSpam!(row);
    final onSide = widget.onSide == null ? null : () => widget.onSide!(row);
    final onUnsubscribe = widget.onUnsubscribe == null || !_leavable
        ? null
        : () => widget.onUnsubscribe!(row);
    final sideLabel = onSide == null
        ? ''
        : widget.source.byPerson(row)
        ? AppLocalizations.of(context).moveToNotifications
        : AppLocalizations.of(context).moveToPeople;
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone)
          _PhoneBar(
            menu: widget.moreMenu,
            onBack: widget.onBack,
            onArchive: onArchive,
            onDelete: onDelete,
            onReply: onReply,
            onForward: onForward,
            onMove: onMove == null ? null : () => onMove(null),
            onLabel: widget.onLabel == null || row.folder == MailFolder.drafts
                ? null
                : () => widget.onLabel!(row, null),
            onSnooze: onSnooze == null ? null : () => onSnooze(null),
            onWake: onWake,
            onWriteAgain: onWriteAgain,
            onStopWaiting: onStopWaiting,
            onRemind: onRemind == null ? null : () => onRemind(null),
            remindLabel: remindLabel,
            backLabel: widget.backLabel,
            onUnsubscribe: onUnsubscribe,
            onPrint: onPrint,
            onReportSpam: onReportSpam,
            onNotSpam: onNotSpam,
            onSide: onSide,
            sideLabel: sideLabel,
          )
        else if (tablet && widget.onBack != null)
          _PanelTop(onClose: widget.onBack!)
        else if (!tablet)
          _Toolbar(
            onBack: widget.onBack,
            backLabel: widget.backLabel,
            onArchive: onArchive,
            onDelete: onDelete,
            onReply: onReply,
            onForward: onForward,
            onMove: onMove,
            onSnooze: onSnooze,
            onWake: onWake,
            onWriteAgain: onWriteAgain,
            onStopWaiting: onStopWaiting,
            onRemind: onRemind,
            remindLabel: remindLabel,
            remindOn: row.remindAt != null,
            onPrint: onPrint,
            printKeys: _apple ? '⌘P' : 'Ctrl+P',
            onSeen: _seen(row),
            unread: !(_seenNow ?? row.seen),
            seenKeys: _apple ? '⇧⌘U' : 'Ctrl Shift U',
            onLabel: widget.onLabel == null || row.folder == MailFolder.drafts
                ? null
                : (at) => widget.onLabel!(row, at),
            onOriginal: _original(row),
            onReportSpam: onReportSpam,
            onNotSpam: onNotSpam,
            onSide: onSide,
            sideLabel: sideLabel,
            onUnsubscribe: onUnsubscribe,
          ),
        Expanded(
          child: SingleChildScrollView(
            key: ValueKey(row.key),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: tablet ? 680 : 780),
                child: Padding(
                  padding: phone
                      ? const EdgeInsets.fromLTRB(20, 4, 20, 24)
                      // Room under the text for the floating bar; in the
                      // upright panel, the panel's own margins.
                      : tablet && widget.onBack != null
                      ? const EdgeInsets.fromLTRB(32, 18, 32, 110)
                      : tablet
                      ? const EdgeInsets.fromLTRB(48, 36, 48, 120)
                      : const EdgeInsets.fromLTRB(48, 32, 48, 28),
                  child: PiumaEnter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          _subject ??
                              (row.subject.isEmpty ? l.noSubject : row.subject),
                          style: TextStyle(
                            fontSize: phone ? 26 : 30,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: phone ? -0.65 : -0.9,
                            color: c.fg,
                          ),
                        ),
                        // The email's labels and "+ Label", as on
                        // `LabelsToApprove`; the phone has Label… in More.
                        if (!phone && row.folder != MailFolder.drafts)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: ReaderLabels(
                              source: widget.source,
                              row: row,
                            ),
                          ),
                        if (_thread case final thread?)
                          FutureBuilder<List<MailRow>>(
                            future: thread,
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return _single(row, account, locale);
                              }
                              // Read again as mail comes: the one shown
                              // stays until the new one is here.
                              final messages =
                                  snap.data ??
                                  (_threadShown?.$1 == row.key
                                      ? _threadShown!.$2
                                      : null);
                              if (messages == null) {
                                return const SizedBox.shrink();
                              }
                              _threadShown = (row.key, messages);
                              return _conversation(messages, account, locale);
                            },
                          )
                        else
                          _single(row, account, locale),
                        if (!phone && !tablet && _replies(row))
                          Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: _QuickReply(
                              key: ValueKey(row.key),
                              controller: _replyText,
                              to: _firstName(row),
                              from: widget.replyFrom?.call(row),
                              machine: widget.source.noReplySender(row),
                              onSend: (text) => _quickReply(row, text),
                              onExpand: onReply,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (phone && _replies(row))
          _QuickReply(
            key: ValueKey(row.key),
            controller: _replyText,
            phone: true,
            to: _firstName(row),
            from: widget.replyFrom?.call(row),
            machine: widget.source.noReplySender(row),
            onSend: (text) => _quickReply(row, text),
            onExpand: onReply,
          ),
      ],
    );
    if (!tablet) return page;
    return Stack(
      children: [
        Positioned.fill(child: page),
        Positioned(
          left: 16,
          right: 16,
          bottom: 22,
          child: Center(
            child: _TabletBar(
              onReply: onReply,
              onArchive: onArchive,
              onSnooze: onSnooze == null ? null : () => onSnooze(null),
              onWake: onWake,
              onWriteAgain: onWriteAgain,
              onStopWaiting: onStopWaiting,
              onRemind: onRemind == null ? null : () => onRemind(null),
              remindLabel: remindLabel,
              onForward: onForward,
              onMove: onMove == null ? null : () => onMove(null),
              onLabel: widget.onLabel == null || row.folder == MailFolder.drafts
                  ? null
                  : () => widget.onLabel!(row, null),
              onPrint: onPrint,
              onReportSpam: onReportSpam,
              onNotSpam: onNotSpam,
              onSide: onSide,
              sideLabel: sideLabel,
              onUnsubscribe: onUnsubscribe,
              onDelete: onDelete,
            ),
          ),
        ),
      ],
    );
  }

  /// Whether [row] has the reply box: not your own sent mail.
  bool _replies(MailRow row) =>
      widget.onQuickReply != null && row.folder != MailFolder.sent;

  String _firstName(MailRow row) =>
      row.fromName.isNotEmpty ? row.fromName.split(' ').first : row.fromEmail;

  Future<void> _quickReply(MailRow row, String text) async {
    final body = await widget.source.body(row).catchError((_) => '');
    widget.onQuickReply!(row, body, text);
  }

  void _translated(MailRow row, Readable? t) {
    if (t == null) {
      _translations.remove(row.key);
    } else {
      _translations[row.key] = t;
    }
  }

  /// Opens the card of [row]'s sender; none for your own messages.
  ValueChanged<Rect>? _onSender(MailRow row) {
    final open = widget.onSender;
    if (open == null || _mine(row)) return null;
    return (anchor) => open(row, anchor);
  }

  /// Messages whose sender isn't who they say.
  final _warned = <Object>{};

  void _warn(MailRow row) {
    if (_warned.add(row.key)) setState(() {});
  }

  /// Report spam for [row], for its warning band.
  VoidCallback? _reportSpam(MailRow row) {
    final spam = widget.onReportSpam;
    return spam == null ? null : () => spam(row);
  }

  /// Avatar and gap before a message's text, as the sender line has it.
  double get _indent => widget.phone ? 52 : 54;

  Widget _single(MailRow row, MailAccount? account, String locale) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: widget.phone ? 18 : 22),
        _SenderLine(
          row: row,
          account: account,
          when: _when(l, row, widget.now(), locale),
          avatar: widget.phone ? 40 : 42,
          email: !widget.phone,
          // A sender who isn't who they say shows the address on the
          // phone too, in place of when.
          address: widget.phone && _warned.contains(row.key),
          onSender: _onSender(row),
        ),
        MessageView(
          key: ValueKey(row.key),
          source: widget.source,
          row: row,
          images: _images,
          chipIndent: _indent,
          now: widget.now,
          onSubject: (s) => setState(() => _subject = s),
          onTranslation: (t) => _translated(row, t),
          onLayout: (show) => _layout(row.key, show),
          onReportSpam: _reportSpam(row),
          onWarned: () => _warn(row),
        ),
      ],
    );
  }

  Widget _conversation(
    List<MailRow> messages,
    MailAccount? account,
    String locale,
  ) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final phone = widget.phone;
    final files = messages.fold(0, (n, m) => n + m.files);
    final entries = _plan(messages);
    final children = <Widget>[];
    for (final e in entries) {
      if (children.isNotEmpty && e is! _NewDivider) {
        children.add(Container(height: 1, color: c.line));
      }
      // Keyed, so a message keeps its drawn text when the ones above
      // change (the "new" line goes once the conversation is read).
      children.add(
        KeyedSubtree(
          key: switch (e) {
            _NewDivider() => const ValueKey('new'),
            _Folded() => const ValueKey('folded'),
            _Shown(:final row) => ValueKey(row.key),
          },
          child: switch (e) {
            _NewDivider(:final count) => _NewLine(l.newMessages(count)),
            _Folded(:final rows) => _FoldedMessages(
              rows: rows,
              mine: {
                for (final r in rows)
                  if (_mine(r)) r.sender,
              },
              label: l.readMessages(rows.length),
              onTap: () => setState(() => _showAll = true),
            ),
            _Shown(:final row, :final open) =>
              open
                  ? _OpenMessage(
                      row: row,
                      indent: widget.phone ? 0 : 54,
                      avatar: widget.phone ? 40 : 42,
                      name: _name(row, l),
                      when: _when(l, row, widget.now(), locale),
                      onSender: _onSender(row),
                      warned: _warned.contains(row.key),
                      onToggle: row == messages.last
                          ? null
                          : () => setState(() => _opened[row.key] = false),
                      child: MessageView(
                        key: ValueKey(row.key),
                        source: widget.source,
                        row: row,
                        images: _images,
                        hideQuotes: true,
                        now: widget.now,
                        onSubject: (s) => setState(() => _subject = s),
                        onTranslation: (t) => _translated(row, t),
                        onLayout: (show) => _layout(row.key, show),
                        onReportSpam: _reportSpam(row),
                        onWarned: () => _warn(row),
                      ),
                    )
                  : _ClosedMessage(
                      row: row,
                      name: _name(row, l),
                      time: _shortWhen(l, row.receivedAt, locale),
                      avatar: widget.phone ? 40 : 42,
                      onTap: () => setState(() => _opened[row.key] = true),
                    ),
          },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        if (phone)
          // As in `FeatureThread`: who wrote, then Summary and the files.
          Row(
            children: [
              Expanded(
                child: Text(
                  l.conversationSummary(messages.length, _people(messages, l)),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
              if (_brief != null) ...[
                const SizedBox(width: 8),
                _Pill(
                  label: l.threadSummary,
                  on: _briefShown,
                  onTap: () => setState(() => _briefShown = !_briefShown),
                ),
              ],
              if (files > 0) ...[
                const SizedBox(width: 8),
                _Pill(
                  label: l.rowAttachments(files),
                  onTap: () => setState(() {
                    _showAll = true;
                    for (final m in messages.where((m) => m.files > 0)) {
                      _opened[m.key] = true;
                    }
                  }),
                ),
              ],
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  l.conversationSummary(messages.length, _people(messages, l)),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
              if (account != null) _AccountChip(account),
            ],
          ),
        if (_brief case final b? when !phone || _briefShown)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: InShort(brief: b),
          ),
        const SizedBox(height: 18),
        Container(height: 1, color: c.line),
        ...children,
      ],
    );
  }

  bool _mine(MailRow row) =>
      widget.source.accounts.any((a) => a.email == row.fromEmail);

  /// The sender, or "You".
  String _name(MailRow row, AppLocalizations l) =>
      _mine(row) ? l.youName : row.sender;

  /// "09:42", "Yesterday 17:20", "Oct 2": when, in a closed message.
  String _shortWhen(AppLocalizations l, DateTime t, String locale) {
    final now = widget.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
    final time = DateFormat.Hm(locale).format(t);
    if (days == 0) return time;
    if (days == 1) return l.yesterdayAt(time);
    return DateFormat.MMMd(locale).format(t);
  }

  /// "Sara, Luca, you": who wrote, in order, the person last.
  String _people(List<MailRow> messages, AppLocalizations l) {
    final names = <String>[];
    final seen = <String>{};
    var me = false;
    for (final m in messages) {
      if (_mine(m)) {
        me = true;
      } else if (seen.add(m.fromEmail)) {
        names.add(
          m.fromName.isNotEmpty
              ? m.fromName.split(' ').first
              : m.fromEmail.split('@').first,
        );
      }
    }
    return [...names, if (me) l.you].join(', ');
  }

  /// What the conversation shows: the first two messages, the last two,
  /// every unread one and the one just before them, and the one that was
  /// opened (from search, say); runs of two or more read messages in
  /// between fold into "6 read messages". Unread messages, the last one
  /// and the one opened start open.
  List<_Entry> _plan(List<MailRow> m) {
    final n = m.length;
    final firstUnread = m.indexWhere((r) => !r.seen);
    final picked = m.indexWhere((r) => r.key == widget.row?.key);
    final keep = <int>{0, 1, n - 2, n - 1, if (picked >= 0) picked};
    for (var i = 0; i < n; i++) {
      if (!m[i].seen) keep.add(i);
    }
    if (firstUnread > 0) keep.add(firstUnread - 1);
    final out = <_Entry>[];
    void show(int i) {
      if (i == firstUnread && i > 0) {
        out.add(_NewDivider(m.where((r) => !r.seen).length));
      }
      final row = m[i];
      out.add(
        _Shown(
          row,
          _opened[row.key] ?? (!row.seen || i == n - 1 || i == picked),
        ),
      );
    }

    var i = 0;
    while (i < n) {
      if (_showAll || keep.contains(i)) {
        show(i++);
        continue;
      }
      var j = i;
      while (j < n && !keep.contains(j)) {
        j++;
      }
      if (j - i >= 2) {
        out.add(_Folded(m.sublist(i, j)));
      } else {
        show(i);
      }
      i = j;
    }
    return out;
  }

  /// "to you · today at 09:42" and friends; sent mail names who it went to.
  static String _when(
    AppLocalizations l,
    MailRow row,
    DateTime now,
    String locale,
  ) {
    final t = row.receivedAt;
    final time = DateFormat.Hm(locale).format(t);
    final date = DateFormat.yMMMEd(locale).format(t);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (row.folder == MailFolder.sent && row.to.isNotEmpty) {
      if (days == 0) return l.toPeopleToday(row.to, time);
      if (days == 1) return l.toPeopleYesterday(row.to, time);
      return l.toPeopleOn(row.to, date, time);
    }
    if (days == 0) return l.toYouToday(time);
    if (days == 1) return l.toYouYesterday(time);
    return l.toYouOn(date, time);
  }
}

sealed class _Entry {}

class _Shown extends _Entry {
  _Shown(this.row, this.open);
  final MailRow row;
  final bool open;
}

class _Folded extends _Entry {
  _Folded(this.rows);
  final List<MailRow> rows;
}

class _NewDivider extends _Entry {
  _NewDivider(this.count);
  final int count;
}

/// One message read in full: the body, its privacy chip and attachments.
/// In a conversation the quoted text at the end is folded away.
/// One message's body, with its privacy chip and attachments.
class MessageView extends StatefulWidget {
  const MessageView({
    super.key,
    required this.source,
    required this.row,
    required this.images,
    this.chipIndent = 0,
    this.hideQuotes = false,
    this.article = false,
    this.now = DateTime.now,
    this.onSubject,
    this.onTranslation,
    this.onLayout,
    this.onReportSpam,
    this.onWarned,
  });

  final MailSource source;
  final MailRow row;
  final RemoteImages images;

  /// Told when the band shows: the phone then shows the address too.
  final VoidCallback? onWarned;

  /// Report spam, offered by the warning band when the sender isn't who
  /// they say.
  final VoidCallback? onReportSpam;

  /// Told how to show the original layout while the email has one and
  /// shows its reading view, and null otherwise: the desktop's More.
  final ValueChanged<VoidCallback?>? onLayout;

  /// The email in the reader's language once it shows translated; null
  /// again on "Original".
  final ValueChanged<Readable?>? onTranslation;

  /// The subject in the reader's language while the email shows
  /// translated; null again on "Original".
  final ValueChanged<String?>? onSubject;

  /// For "Add Friday 10:00 to calendar".
  final DateTime Function() now;
  final double chipIndent;
  final bool hideQuotes;

  /// Set larger, as an article (a newsletter in Newsletters).
  final bool article;

  @override
  State<MessageView> createState() => _MessageViewState();
}

/// The last messages read, per source, so one opened again (or drawn
/// again as its conversation changes) shows its text at once.
final _lastReadable = Expando<Map<Object, Readable>>();

/// The originals made last, per source, by message and whether their
/// images came in.
final _lastOriginal = Expando<Map<(Object, bool), Future<OriginalDoc>>>();

class _MessageViewState extends State<MessageView> {
  void _remember(Object key, Readable r) {
    final known = _lastReadable[widget.source] ??= <Object, Readable>{};
    known
      ..remove(key)
      ..[key] = r;
    if (known.length > 24) known.remove(known.keys.first);
  }

  late Future<Readable> _readable;

  /// "Load images once" was pressed for this message.
  bool _loadOnce = false;

  /// Remote images are on their way.
  bool _imagesLoading = false;

  /// The folded quote was opened.
  bool _quotesShown = false;

  /// The original layout, while it shows instead of the reading view.
  Future<OriginalDoc>? _original;

  /// Attachments being fetched, by part.
  final _saving = <int>{};

  /// The language pair last asked about ("de>it"), and what the device
  /// said of it.
  String? _pairFor;
  PairStatus _pair = PairStatus.unsupported;
  int? _pairBytes;

  /// The email in the reader's language, while it shows instead.
  Readable? _translation;
  bool _translating = false;
  double? _progress;

  /// The body is taking long enough to say so.
  bool _slow = false;
  Timer? _slowTimer;

  /// Why the sender isn't who they say, once the body is kept.
  SenderWarning? _warning;

  void _checkSender() {
    widget.source.senderWarning(widget.row).then((w) {
      if (!mounted || w == null) return;
      setState(() => _warning = w);
      widget.onWarned?.call();
    }, onError: (Object _) {});
  }

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    _slowTimer = Timer(PiumaMotion.enter, () {
      if (mounted) setState(() => _slow = true);
    });
    // Drawn before: the text is there on the first frame.
    final known = _lastReadable[widget.source]?[row.key];
    if (known != null) {
      _slowTimer?.cancel();
      _readable = SynchronousFuture(known);
      if (_opensOriginal(known)) _original = _originalOf(known);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_showRemote(known)) _fetchImages(known);
        _tellLayout(known);
        _checkSender();
      });
      return;
    }
    _readable = widget.source.readable(row).then((r) {
      _slowTimer?.cancel();
      _remember(row.key, r);
      if (mounted && _original == null && _opensOriginal(r)) {
        _original = _originalOf(r);
      }
      if (mounted && _showRemote(r)) _fetchImages(r);
      if (mounted) _tellLayout(r);
      if (mounted) _checkSender();
      return r;
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    widget.onLayout?.call(null);
    super.dispose();
  }

  /// Tells the reader whether "Original layout" can show now.
  void _tellLayout(Readable r) => widget.onLayout?.call(
    r.layout && originalPaper != null && _original == null
        ? _showOriginal
        : null,
  );

  /// An email built as a layout opens as it was sent
  /// (`ImagesToApprove`); the switch over it goes to the clean view.
  bool _opensOriginal(Readable r) => r.layout && originalPaper != null;

  /// The clean reading view in place of the original.
  void _showClean() {
    setState(() => _original = null);
    _readable.then(_tellLayout, onError: (Object _) {});
  }

  /// The original layout in place of the reading view, as the privacy
  /// sheet's "Show original layout" does.
  void _showOriginal() {
    _readable.then((r) {
      if (!mounted || _original != null) return;
      setState(() {
        _original = _originalOf(r);
      });
      _tellLayout(r);
    }, onError: (Object _) {});
  }

  bool _showRemote(Readable r) => _loadOnce || r.trusted || !r.blockImages;

  void _fetchImages(Readable r) {
    final urls = [
      for (final b in r.blocks)
        if (b.image case final i? when i.remote) i.url,
    ];
    if (urls.isEmpty) return;
    setState(() => _imagesLoading = true);
    Future.wait([
      for (final u in urls) widget.images.get(u).then((_) {}, onError: (_) {}),
    ]).then((_) {
      if (mounted) setState(() => _imagesLoading = false);
    });
  }

  /// Applies a choice about images, then fetches those it allows, in
  /// the original too. [current] is the message as the choice left it.
  void _changeImages(Readable Function() current, void Function() apply) {
    final wasShown = _showRemote(current());
    setState(() {
      apply();
      _readable = SynchronousFuture(current());
    });
    final now = current();
    _remember(widget.row.key, now);
    if (!wasShown && _showRemote(now)) {
      _fetchImages(now);
      if (_original != null) {
        setState(() {
          _original = _originalOf(now);
        });
      }
    }
  }

  /// "Always for this sender" on the images bar: trusts them.
  void _trustSender(Readable r) {
    widget.source.setTrusted(widget.row.fromEmail, true);
    var current = r;
    _changeImages(() => current, () => current = r.copyWith(trusted: true));
  }

  Future<void> _openPrivacy(Readable r) async {
    final row = widget.row;
    var current = r;
    void change(void Function() apply) => _changeImages(() => current, apply);

    await showPrivacySheet(
      context,
      readable: r,
      sender: row.sender,
      imagesShown: _showRemote(r),
      onLoadOnce: () => change(() => _loadOnce = true),
      onTrust: (trusted) {
        widget.source.setTrusted(row.fromEmail, trusted);
        change(() => current = current.copyWith(trusted: trusted));
      },
      onBlockImages: (block) {
        widget.source.setBlockRemoteImages(block);
        change(() => current = current.copyWith(blockImages: block));
      },
      onOriginal: r.layout && originalPaper != null
          ? () {
              setState(() {
                _original = _originalOf(current);
              });
              _tellLayout(current);
            }
          : null,
      phone: MediaQuery.sizeOf(context).width < phoneWidth,
    );
  }

  /// Asks once per pair whether Translate can be offered.
  void _askPair(String? from, String to) {
    final key = '$from>$to';
    if (_pairFor == key) return;
    _pairFor = key;
    _pair = PairStatus.unsupported;
    if (from == null || from == to) return;
    final engine = Translator.engine;
    engine.status(from, to).then((s) async {
      final bytes = s == PairStatus.download
          ? await engine.downloadSize(from, to)
          : null;
      if (mounted && _pairFor == key) {
        setState(() {
          _pair = s;
          _pairBytes = bytes;
        });
      }
    }, onError: (_) {});
  }

  Future<void> _translate(Readable r, String to) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _translating = true;
      _progress = null;
    });
    try {
      final (t, subject) = await Translator.readable(
        r,
        from: r.language!,
        to: to,
        subject: widget.onSubject == null ? null : widget.row.subject,
        progress: (p) {
          if (!mounted) return;
          setState(() {
            if (p < 0) {
              // Downloaded: the pill says "Translating…" from here.
              _pair = PairStatus.ready;
              _progress = null;
            } else {
              _progress = p;
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _translation = t;
        _pair = PairStatus.ready;
      });
      widget.onTranslation?.call(t);
      if (subject != null) widget.onSubject?.call(subject);
    } catch (e) {
      final from = r.language!;
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              e is TranslateNeedsDownload
                  ? l.translateNeedsDownload(
                      l.languageName(from),
                      l.languageName(to),
                    )
                  : l.translateFailed,
            ),
            behavior: SnackBarBehavior.floating,
            width: 360,
          ),
        );
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  /// The original as the engine made it, shared with a view of the same
  /// message drawn again, so it isn't made (and loaded) twice.
  Future<OriginalDoc> _originalOf(Readable r) {
    final known = _lastOriginal[widget.source] ??= {};
    final key = (widget.row.key, _showRemote(r));
    final hit = known.remove(key);
    final doc = hit ?? widget.source.original(widget.row, loadImages: key.$2);
    known[key] = doc;
    if (known.length > 12) known.remove(known.keys.first);
    doc.catchError((Object _) {
      known.remove(key);
      return doc;
    });
    return doc;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final into =
        PiumaLook.of(context).translateInto ?? Translator.languageOf(locale);
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    return FutureBuilder<Readable>(
      future: _readable,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Text(
              l.couldNotLoadMessage,
              style: TextStyle(fontSize: 15, color: c.danger),
            ),
          );
        }
        final r = snap.data;
        if (r == null) {
          // Most bodies are here in a frame or two: "Loading…" only for
          // one that takes a while, so opening a message doesn't blink.
          return Padding(
            padding: const EdgeInsets.only(top: 22),
            child: _slow
                ? Text(
                    l.loading,
                    style: TextStyle(fontSize: 15, color: c.muted),
                  )
                : const SizedBox.shrink(),
          );
        }
        final remote = _showRemote(r);
        // Translate turned off in Settings › Features: no offer, and no
        // language is looked up or downloaded.
        final translating = widget.source.features.value.translate;
        if (translating) _askPair(r.language, into);
        final translation = _translation;
        final shown = translation ?? r;
        final quote = widget.hideQuotes && !_quotesShown
            ? shown.quoteStart
            : shown.blocks.length;
        final offer =
            translating &&
            translation == null &&
            _original == null &&
            _pair != PairStatus.unsupported;
        final warning = _warning;
        final layout = _opensOriginal(r) && translation == null;
        final askImages = !remote && r.remoteImages > 0;
        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning != null)
              Padding(
                padding: EdgeInsets.only(top: phone ? 14 : 16),
                child: SenderWarningBand(
                  warning: warning,
                  phone: phone,
                  onReportSpam: widget.onReportSpam,
                ),
              ),
            if (r.hasPrivacyNews || offer || layout)
              Padding(
                padding: EdgeInsets.only(left: widget.chipIndent, top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (r.hasPrivacyNews)
                            PrivacyChip(
                              readable: r,
                              showRemote: remote,
                              loading: _imagesLoading,
                              onTap: () => _openPrivacy(r),
                            ),
                          if (offer)
                            TranslatePill(
                              from: r.language!,
                              to: into,
                              busy: _translating,
                              download: _pair == PairStatus.download,
                              bytes: _pairBytes,
                              progress: _progress,
                              phone: phone,
                              onTap: () => _translate(r, into),
                            ),
                        ],
                      ),
                    ),
                    if (layout)
                      ViewSwitch(
                        original: _original != null,
                        phone: phone,
                        onChanged: (original) =>
                            original ? _showOriginal() : _showClean(),
                      ),
                  ],
                ),
              ),
            AnimatedSize(
              duration: reduceMotion(context)
                  ? Duration.zero
                  : PiumaMotion.collapse,
              curve: PiumaMotion.curve,
              alignment: Alignment.topCenter,
              child: askImages
                  ? Padding(
                      // On the phone it takes the whole width, as the
                      // email under it does.
                      padding: EdgeInsets.only(
                        left: phone ? 0 : widget.chipIndent,
                        top: PiumaSpace.s12,
                      ),
                      child: ImagesBar(
                        count: r.remoteImages,
                        sender: widget.row.sender,
                        phone: phone,
                        onLoad: () =>
                            _changeImages(() => r, () => _loadOnce = true),
                        onTrust: () => _trustSender(r),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            if (r.invite case final invite?) ...[
              const SizedBox(height: 18),
              InviteCard(
                invite: invite,
                source: widget.source,
                row: widget.row,
              ),
            ],
            const SizedBox(height: 22),
            if (_original case final original?)
              OriginalView(
                original: original,
                phone: MediaQuery.sizeOf(context).width < phoneWidth,
                onLink: (link, shown) => openLink(context, link, shown: shown),
              )
            else ...[
              if (translation != null) ...[
                TranslatedBar(
                  from: r.language ?? '',
                  phone: phone,
                  onOriginal: () {
                    setState(() => _translation = null);
                    widget.onSubject?.call(null);
                    widget.onTranslation?.call(null);
                  },
                ),
                const SizedBox(height: 18),
              ],
              MessageBody(
                readable: quote < shown.blocks.length
                    ? shown.copyWith(blocks: shown.blocks.sublist(0, quote))
                    : shown,
                images: widget.images,
                showRemote: remote,
                article: widget.article,
                dateChip: !widget.source.features.value.foundDates
                    ? null
                    : (d) => FoundDateChip(
                        key: ValueKey(d.uid),
                        date: d,
                        source: widget.source,
                        row: widget.row,
                        now: widget.now,
                      ),
              ),
              if (quote < shown.blocks.length) ...[
                const SizedBox(height: 14),
                _QuoteToggle(
                  label: l.quotedTextHidden,
                  semanticLabel: l.showQuotedText,
                  onTap: () => setState(() => _quotesShown = true),
                ),
              ],
            ],
            if (r.attachments.isNotEmpty) ...[
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in r.attachments)
                    AttachmentChip(
                      name: a.name,
                      mime: a.mime,
                      busy: _saving.contains(a.part),
                      semanticLabel: l.attachmentLabel(
                        a.name,
                        fileSize(a.size, locale: locale),
                      ),
                      risk: riskNote(l, a),
                      onTap: () => _tap(r, a),
                    ),
                ],
              ),
            ],
          ],
        );
        return LinksAskFirst(ask: warning != null, child: column);
      },
    );
  }

  /// PDFs and pictures open in the preview, as from the Attachments board;
  /// other files are saved and opened.
  void _tap(Readable r, MailAttachment a) {
    if (!AttachPreview.shows(a)) {
      _open(a);
      return;
    }
    final row = widget.row;
    AttachPreview.open(
      context,
      source: widget.source,
      file: AttachedFile(row, a),
      photos: AttachPreview.isPicture(a)
          ? [
              for (final o in r.attachments)
                if (AttachPreview.isPicture(o)) AttachedFile(row, o),
            ]
          : const [],
      desktop: MediaQuery.sizeOf(context).width >= phoneWidth,
      now: widget.now,
      onDownload: (f) => _open(f.file),
    );
  }

  /// Saves an attachment in Downloads and opens it.
  Future<void> _open(MailAttachment a) async {
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
      final path = await widget.source.saveAttachment(widget.row, a);
      toast(l.attachmentSaved(a.name));
      if (!mounted ||
          !await mayOpenFile(context, widget.source, widget.row, a, path)) {
        return;
      }
      await openLocalFile(path);
    } catch (_) {
      toast(l.attachmentNotSaved(a.name));
    } finally {
      if (mounted) setState(() => _saving.remove(a.part));
    }
  }
}

/// A message of a conversation, open: who wrote it and when, then the body
/// under the name. Tapping the header closes it (not the last one).
class _OpenMessage extends StatelessWidget {
  const _OpenMessage({
    required this.row,
    required this.name,
    required this.when,
    required this.onToggle,
    required this.child,
    this.indent = 54,
    this.avatar = 42,
    this.onSender,
    this.warned = false,
  });

  final MailRow row;
  final String name;
  final String when;

  /// The sender isn't who they say: the address shows on the phone too.
  final bool warned;
  final VoidCallback? onToggle;
  final ValueChanged<Rect>? onSender;
  final Widget child;

  /// How far the text sits in from the avatar's edge; none on the phone.
  final double indent;
  final double avatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Tappable(
            onTap: onToggle,
            expanded: true,
            child: _SenderLine(
              row: row,
              account: null,
              when: when,
              name: name,
              avatar: avatar,
              email: avatar > 40,
              address: avatar <= 40 && warned,
              onSender: onSender,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: indent),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A message of a conversation, closed: name, time and its first words.
class _ClosedMessage extends StatelessWidget {
  const _ClosedMessage({
    required this.row,
    required this.name,
    required this.time,
    required this.onTap,
    this.avatar = 42,
  });

  final MailRow row;
  final String name;
  final String time;
  final VoidCallback onTap;
  final double avatar;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return _Tappable(
      onTap: onTap,
      expanded: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            _Initials(
              row.sender,
              size: avatar,
              email: row.fromEmail,
              mine: name == AppLocalizations.of(context).youName,
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
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: row.seen
                                ? FontWeight.w500
                                : FontWeight.w600,
                            color: c.fg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        time,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ),
                  Text(
                    row.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
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

/// "6 read messages" in a dashed box, with the faces of who wrote them.
class _FoldedMessages extends StatelessWidget {
  const _FoldedMessages({
    required this.rows,
    required this.label,
    required this.onTap,
    this.mine = const {},
  });

  final List<MailRow> rows;
  final String label;
  final VoidCallback onTap;

  /// The names your own messages go by, drawn "ME".
  final Set<String> mine;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final faces = <String>[];
    for (final r in rows) {
      if (!faces.contains(r.sender)) faces.add(r.sender);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: CustomPaint(
          painter: _DashedBorder(
            color: Color.lerp(c.line, c.muted, .25)!,
            radius: PiumaRadius.button + 2,
          ),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 12),
                SizedBox(
                  width: 22.0 + 16 * (faces.take(3).length - 1),
                  height: 22,
                  child: Stack(
                    children: [
                      for (final (i, f) in faces.take(3).indexed)
                        Positioned(
                          left: 16.0 * i,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: c.surface, width: 2),
                            ),
                            child: _Initials(
                              f,
                              size: 18,
                              fontSize: 8,
                              mine: mine.contains(f),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 14, color: c.fg),
                  ),
                ),
                PiumaIconView(PiumaIcon.chevronDown, color: c.muted),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

/// "2 new" over a line, before the first unread message.
class _NewLine extends StatelessWidget {
  const _NewLine(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: PiumaType.label.copyWith(
              color: c.accentText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: c.accent.withValues(alpha: .25)),
          ),
        ],
      ),
    );
  }
}

/// "··· quoted text hidden", which opens the quote.
class _QuoteToggle extends StatelessWidget {
  const _QuoteToggle({
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
      ),
    );
  }
}

/// A header that opens or closes its message.
class _Tappable extends StatelessWidget {
  const _Tappable({
    required this.onTap,
    required this.expanded,
    required this.child,
  });

  final VoidCallback? onTap;
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Semantics(
      button: true,
      expanded: expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: child),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials(
    this.name, {
    required this.size,
    this.fontSize = 14,
    this.mine = false,
    this.email = '',
  });

  final String name;

  /// Whose picture replaces the letters once it is on the device.
  final String email;

  /// Your own message: "ME", as in `FeatureThread`.
  final bool mine;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final letter = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        mine ? AppLocalizations.of(context).meInitials : initials(name),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: c.fg,
        ),
      ),
    );
    if (mine || email.isEmpty) return letter;
    return SenderPicture(email: email, size: size, letter: letter);
  }
}

class _SenderLine extends StatelessWidget {
  const _SenderLine({
    required this.row,
    required this.account,
    required this.when,
    this.name,
    this.avatar = 42,
    this.email = true,
    this.address = false,
    this.onSender,
  });

  final MailRow row;
  final MailAccount? account;

  /// The address under the name, in place of when: the phone's, for a
  /// sender who isn't who they say.
  final bool address;
  final String when;
  final double avatar;

  /// Opens the sender's card under the name, given where the name is.
  final ValueChanged<Rect>? onSender;

  /// The address after the name; the phone has no room for it.
  final bool email;

  /// Shown instead of the sender's name ("You").
  final String? name;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Row(
      children: [
        _avatar(context),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: _name(context)),
                  if (email && (row.fromName.isNotEmpty || name != null))
                    Flexible(
                      child: Text(
                        '  ${row.fromEmail}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: c.muted,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                address ? row.fromEmail : when,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
              ),
            ],
          ),
        ),
        if (account != null) ...[
          const SizedBox(width: 12),
          _AccountChip(account!),
        ],
      ],
    );
  }
}

extension on _SenderLine {
  Widget _avatar(BuildContext context) {
    final face = _Initials(
      row.sender,
      size: avatar,
      email: row.fromEmail,
      mine: name == AppLocalizations.of(context).youName,
    );
    final open = onSender;
    if (open == null) return face;
    return ExcludeSemantics(
      child: Builder(
        builder: (context) => PiumaPressable(
          onTap: () {
            final box = context.findRenderObject()! as RenderBox;
            open(box.localToGlobal(Offset.zero) & box.size);
          },
          child: face,
        ),
      ),
    );
  }

  Widget _name(BuildContext context) {
    final c = PiumaTheme.of(context);
    final text = Text(
      name ?? row.sender,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: c.fg,
      ),
    );
    final open = onSender;
    if (open == null) return text;
    return Builder(
      builder: (context) => PiumaPressable(
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          open(box.localToGlobal(Offset.zero) & box.size);
        },
        semanticLabel: AppLocalizations.of(context).senderCardLabel(row.sender),
        child: ExcludeSemantics(child: text),
      ),
    );
  }
}

/// The account's color and name, as in `Main`.
class _AccountChip extends StatelessWidget {
  const _AccountChip(this.account);
  final MailAccount account;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: account.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(account.name, style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      ),
    );
  }
}

/// Archive, Snooze, Move to, Delete and Print on the left, Reply, Forward
/// and More on the right, as in `Main`, `AccountFolders`,
/// `ForwardToApprove` and `RemindAwayPrintToApprove`; in Snoozed, Back to
/// inbox too.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    this.onBack,
    this.backLabel,
    this.onArchive,
    this.onDelete,
    this.onReply,
    this.onForward,
    this.onMove,
    this.onSnooze,
    this.onWake,
    this.onWriteAgain,
    this.onStopWaiting,
    this.onRemind,
    this.remindLabel = '',
    this.remindOn = false,
    this.onPrint,
    this.printKeys = '',
    this.onSeen,
    this.unread = false,
    this.seenKeys = '',
    this.onLabel,
    this.onOriginal,
    this.onReportSpam,
    this.onNotSpam,
    this.onSide,
    this.sideLabel = '',
    this.onUnsubscribe,
  });

  /// More's "Move to Notifications" or "Move to People", as [sideLabel].
  final VoidCallback? onSide;
  final String sideLabel;

  /// More's "Unsubscribe", for mail whose list can be left.
  final VoidCallback? onUnsubscribe;

  /// More's "Mark as unread", "Mark as read" once [unread], with
  /// [seenKeys].
  final VoidCallback? onSeen;
  final bool unread;
  final String seenKeys;

  /// More's "Label…": the labels under More.
  final ValueChanged<Rect>? onLabel;

  /// More's "Original layout", while the email has one and shows its
  /// reading view.
  final VoidCallback? onOriginal;

  /// More's "Report spam".
  final VoidCallback? onReportSpam;

  /// "Not spam", a button in the bar and in More, in the spam folder.
  final VoidCallback? onNotSpam;

  /// Opens "Remind me" under its chip, which says [remindLabel], on the
  /// soft accent once [remindOn].
  final ValueChanged<Rect>? onRemind;
  final String remindLabel;
  final bool remindOn;

  /// Print, or save as PDF; its tooltip shows [printKeys].
  final VoidCallback? onPrint;
  final String printKeys;

  /// Opens "Snooze until…" under its button.
  final ValueChanged<Rect>? onSnooze;
  final VoidCallback? onWake;
  final VoidCallback? onWriteAgain;
  final VoidCallback? onStopWaiting;

  /// In a narrow window the message covers the list: "‹ Inbox" goes back.
  final VoidCallback? onBack;

  /// Where Back goes, when not the inbox: "‹ Vault".
  final String? backLabel;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onReply;
  final VoidCallback? onForward;

  /// Opens "Move to…" under its button.
  final ValueChanged<Rect>? onMove;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double text(String s, double size, [FontWeight w = FontWeight.w400]) {
      final p = TextPainter(
        text: TextSpan(
          text: s,
          style: base.copyWith(fontSize: size, fontWeight: w),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = p.width;
      p.dispose();
      return width;
    }

    // What the bar needs in any case: its padding, the icon buttons, the
    // words of the buttons on the right, More, and a little air for
    // rounding.
    var need = 48.0 + 44 + 8;
    if (onBack != null) {
      need += 34 + text(backLabel ?? l.inbox, 15) + 8;
    }
    need += 44.0 * [onArchive, onWake, onSnooze, onMove].nonNulls.length + 40;
    if (onReply != null) need += 54 + text(l.actionReply, 15, FontWeight.w500);
    if (onNotSpam != null) need += 36 + text(l.notSpam, 15, FontWeight.w500);
    // Waiting's Remind me chip and Write again, which go into More after
    // Forward and Stop waiting, Remind me first.
    final remindRoom = onRemind != null
        ? 8 + 31 + text(remindLabel, 14, FontWeight.w500) + 12
        : 0.0;
    final againRoom = onWriteAgain != null
        ? 8 + 28 + text(l.writeAgain, 15, FontWeight.w600)
        : 0.0;
    // What can move into More when there is no room for it.
    final rest =
        (onForward != null
            ? 62 + text(l.actionForward, 15, FontWeight.w500)
            : 0) +
        (onStopWaiting != null
            ? 28 + text(l.stopWaiting, 15, FontWeight.w500)
            : 0);
    const printRoom = 44.0;
    const keysRoom = 32.0;
    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxWidth;
        // As the bar gets shorter, Print moves into More first (it also
        // waits for 560 points), then Forward and Stop waiting, as on the
        // phone, then Remind me and then Write again; Reply's and
        // Forward's keys show from 640 when there is room for them too.
        final again = need + againRoom <= room;
        final remind = need + againRoom + remindRoom <= room;
        final all = need + againRoom + remindRoom + rest;
        final forward = all <= room;
        final print = forward && room >= 560 && all + printRoom <= room;
        final keys =
            forward &&
            room >= 640 &&
            all + (print ? printRoom : 0) + keysRoom <= room;
        return _bar(
          context,
          c,
          l,
          keys: keys,
          print: print,
          forward: forward,
          remind: remind,
          again: again,
        );
      },
    );
  }

  /// [keys]: the window is wide enough for Reply's and Forward's keys;
  /// [print], for the Print button; [forward], for the Forward button;
  /// [remind], for the Remind me chip; [again], for Write again.
  Widget _bar(
    BuildContext context,
    PiumaColors c,
    AppLocalizations l, {
    required bool keys,
    required bool print,
    required bool forward,
    required bool remind,
    required bool again,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            PiumaPressable(
              onTap: onBack,
              semanticLabel: backLabel ?? l.inbox,
              child: SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 10, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PiumaIconView(
                        PiumaIcon.chevronLeft,
                        size: 18,
                        color: c.accentText,
                      ),
                      const SizedBox(width: 4),
                      ExcludeSemantics(
                        child: Text(
                          backLabel ?? l.inbox,
                          style: TextStyle(fontSize: 15, color: c.accentText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // A folder hides what makes no sense there (Archive in Archive,
          // Reply in Sent) instead of showing a dead button.
          if (onArchive != null) ...[
            _ToolButton(
              icon: PiumaIcon.archive,
              label: l.archive,
              onTap: onArchive,
            ),
            const SizedBox(width: 4),
          ],
          if (onWake != null) ...[
            _ToolButton(icon: PiumaIcon.inbox, label: l.wakeNow, onTap: onWake),
            const SizedBox(width: 4),
          ],
          if (onSnooze case final snooze?) ...[
            Builder(
              builder: (button) => _ToolButton(
                icon: PiumaIcon.clock,
                label: l.actionSnooze,
                onTap: () {
                  final box = button.findRenderObject()! as RenderBox;
                  snooze(box.localToGlobal(Offset.zero) & box.size);
                },
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (onMove case final move?) ...[
            Builder(
              builder: (button) => _ToolButton(
                icon: PiumaIcon.folder,
                label: l.moveTo,
                onTap: () {
                  final box = button.findRenderObject()! as RenderBox;
                  move(box.localToGlobal(Offset.zero) & box.size);
                },
              ),
            ),
            const SizedBox(width: 4),
          ],
          _ToolButton(
            icon: PiumaIcon.trash,
            label: l.actionDelete,
            onTap: onDelete,
          ),
          if (onPrint != null && print) ...[
            const SizedBox(width: 4),
            _ToolButton(
              icon: PiumaIcon.printer,
              label: l.printEmail,
              tooltip: l.printTooltip(printKeys),
              onTap: onPrint,
            ),
          ],
          const Spacer(),
          if (onNotSpam case final notSpam?) ...[
            _WaitingButton(label: l.notSpam, onTap: notSpam),
            const SizedBox(width: 8),
          ],
          if (onStopWaiting case final stop? when forward)
            _WaitingButton(label: l.stopWaiting, onTap: stop),
          if (onRemind case final onTap? when remind) ...[
            if (onStopWaiting != null && forward) const SizedBox(width: 8),
            RemindChip(
              label: remindLabel,
              on: remindOn,
              onTap: onTap,
              height: 38,
              fontSize: 14,
            ),
          ],
          if (onWriteAgain case final onTap? when again) ...[
            if ((onStopWaiting != null && forward) ||
                (onRemind != null && remind))
              const SizedBox(width: 8),
            _WaitingButton(label: l.writeAgain, onTap: onTap, primary: true),
          ],
          if (onReply != null)
            _KeyButton(
              icon: PiumaIcon.reply,
              label: l.actionReply,
              keyLabel: keys ? 'R' : null,
              onTap: onReply!,
            ),
          if (onForward != null && forward) ...[
            const SizedBox(width: 8),
            _KeyButton(
              icon: PiumaIcon.forward,
              label: l.actionForward,
              keyLabel: keys ? 'F' : null,
              onTap: onForward!,
            ),
          ],
          if (_items(
                l,
                print: print,
                forward: forward,
                remind: remind,
                again: again,
              )
              case final items when items.isNotEmpty) ...[
            const SizedBox(width: 4),
            Builder(
              builder: (button) => _ToolButton(
                icon: PiumaIcon.more,
                label: l.moreActions,
                onTap: () => _more(button, items),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// What More holds here, as on `RemindAwayPrintToApprove`: what doesn't
  /// apply is left out, and Print, Forward and Stop waiting come in when
  /// the bar has no room for their buttons, and so do Remind me and Write
  /// again in a narrow Waiting reader.
  List<_MoreItem> _items(
    AppLocalizations l, {
    required bool print,
    required bool forward,
    required bool remind,
    required bool again,
  }) => [
    if (onWriteAgain case final w? when !again)
      _MoreItem(l.writeAgain, null, w),
    if (onRemind case final r? when !remind)
      _MoreItem(remindLabel, null, null, onAt: r),
    if (onForward case final f? when !forward)
      _MoreItem(l.actionForward, 'F', f),
    if (onStopWaiting case final stop? when !forward)
      _MoreItem(l.stopWaiting, null, stop),
    if (onSeen case final seen?)
      _MoreItem(unread ? l.markRead : l.markUnread, seenKeys, seen),
    if (onLabel case final label?)
      _MoreItem(l.labelMenu, 'L', null, onAt: label),
    if (onSide case final side?) _MoreItem(sideLabel, null, side),
    if (onUnsubscribe case final leave?) _MoreItem(l.unsubscribe, null, leave),
    if (onOriginal case final original?)
      _MoreItem(l.originalLayout, null, original),
    if (onPrint case final p? when !print)
      _MoreItem(l.printEmail, printKeys.replaceAll('+', ' '), p),
    if (onReportSpam case final spam?) _MoreItem(l.reportSpam, null, spam),
    if (onNotSpam case final notSpam?) _MoreItem(l.notSpam, null, notSpam),
  ];

  /// More's menu, grown out of its button and lined up with its right
  /// edge; what was picked runs once it has closed.
  Future<void> _more(BuildContext button, List<_MoreItem> items) async {
    final l = AppLocalizations.of(button);
    final box = button.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero) & box.size;
    final picked = await showPiumaPopover<_MoreItem>(
      button,
      label: l.moreActions,
      anchor: at,
      width: _MoreMenu.width,
      grow: true,
      end: true,
      builder: (menu) => _MoreMenu(
        items: items,
        onPick: (item) => Navigator.of(menu).pop(item),
      ),
    );
    if (picked == null) return;
    if (picked.onAt case final onAt?) {
      onAt(at);
    } else {
      picked.onTap?.call();
    }
  }
}

/// One line of the desktop's More: its words, its key in mono when it has
/// one, and what it does ([onAt]: Label… and Remind me, whose choices
/// hang under More).
class _MoreItem {
  const _MoreItem(this.text, this.keys, this.onTap, {this.onAt});

  final String text;
  final String? keys;
  final VoidCallback? onTap;
  final ValueChanged<Rect>? onAt;
}

/// The desktop reader's More, with the rows of the app's other desktop
/// menus (Remind me's): 34 high, the key in mono on the right. The rows
/// come in one after the other.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.items, required this.onPick});

  static const width = 260.0;

  final List<_MoreItem> items;
  final ValueChanged<_MoreItem> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          PiumaEnter(
            index: i,
            child: PiumaPressable(
              onTap: () => onPick(item),
              semanticLabel: item.text,
              child: ExcludeSemantics(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.fg),
                        ),
                      ),
                      if (item.keys case final keys?) ...[
                        const SizedBox(width: PiumaSpace.s12),
                        Text(
                          keys,
                          style: PiumaType.mono.copyWith(
                            fontSize: 12,
                            color: c.muted,
                          ),
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

/// Reply and Forward: a quiet bordered button with its key after the
/// word.
class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.icon,
    required this.label,
    this.keyLabel,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;

  /// Left out in a narrow window.
  final String? keyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.button),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(icon, color: c.fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
              if (keyLabel case final key?) ...[
                const SizedBox(width: 8),
                Text(
                  key,
                  style: PiumaType.mono.copyWith(fontSize: 12, color: c.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Stop waiting and Write again, as on `WaitingToApprove`: a quiet
/// bordered button and the accent one.
class _WaitingButton extends StatelessWidget {
  const _WaitingButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? c.accent : c.surface,
          border: primary ? null : Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.button),
        ),
        child: ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
              color: primary ? c.onAccent : c.fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  final PiumaIcon icon;
  final String label;

  /// What the tooltip says, when more than [label] (its key).
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Tooltip(
      message: tooltip ?? label,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: SizedBox.square(
          dimension: 40,
          child: Center(child: PiumaIconView(icon, size: 18, color: c.fg)),
        ),
      ),
    );
  }
}

/// The top of `PhoneRead`: "‹ Inbox", then Archive, Snooze and More
/// (Reply and Delete; Back to inbox in Snoozed).
class _PhoneBar extends StatelessWidget {
  const _PhoneBar({
    this.menu,
    this.onBack,
    this.onArchive,
    this.onDelete,
    this.onReply,
    this.onForward,
    this.onMove,
    this.onLabel,
    this.onSnooze,
    this.onWake,
    this.onWriteAgain,
    this.onStopWaiting,
    this.onRemind,
    this.remindLabel = '',
    this.backLabel,
    this.onUnsubscribe,
    this.onPrint,
    this.onReportSpam,
    this.onNotSpam,
    this.onSide,
    this.sideLabel = '',
  });

  final VoidCallback? onPrint;
  final VoidCallback? onReportSpam;
  final VoidCallback? onNotSpam;

  /// "Move to Notifications" or "Move to People", as [sideLabel].
  final VoidCallback? onSide;
  final String sideLabel;
  final VoidCallback? onSnooze;
  final VoidCallback? onWake;
  final VoidCallback? onWriteAgain;
  final VoidCallback? onStopWaiting;
  final VoidCallback? onRemind;
  final String remindLabel;

  final MenuController? menu;
  final String? backLabel;
  final VoidCallback? onUnsubscribe;

  final VoidCallback? onBack;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onReply;
  final VoidCallback? onForward;
  final VoidCallback? onMove;
  final VoidCallback? onLabel;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget item(PiumaIcon icon, String label, VoidCallback? onPressed) =>
        MenuItemButton(
          onPressed: onPressed,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(220, 48)),
            overlayColor: WidgetStatePropertyAll(c.chip),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          leadingIcon: PiumaIconView(icon, size: 18, color: c.fg),
          child: Text(label, style: TextStyle(fontSize: 16, color: c.fg)),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(
        children: [
          PiumaPressable(
            onTap: onBack,
            semanticLabel: backLabel ?? l.inbox,
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
                        backLabel ?? l.inbox,
                        style: TextStyle(fontSize: 16, color: c.accentText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (onArchive != null)
            _PhoneIconButton(
              icon: PiumaIcon.archive,
              label: l.archive,
              onTap: onArchive,
            ),
          if (onSnooze != null)
            _PhoneIconButton(
              icon: PiumaIcon.clock,
              label: l.actionSnooze,
              onTap: onSnooze,
            ),
          MenuAnchor(
            controller: menu,
            alignmentOffset: const Offset(-184, 4),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(c.surface),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(0),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: c.line),
                ),
              ),
            ),
            menuChildren: [
              // In the spam folder it comes first (`ProtectionToApprove`).
              if (onNotSpam != null)
                item(PiumaIcon.inbox, l.notSpam, onNotSpam),
              if (onWake != null) item(PiumaIcon.inbox, l.wakeNow, onWake),
              if (onWriteAgain != null)
                item(PiumaIcon.reply, l.writeAgain, onWriteAgain),
              if (onRemind != null)
                item(PiumaIcon.hourglass, remindLabel, onRemind),
              if (onStopWaiting != null)
                item(PiumaIcon.hourglass, l.stopWaiting, onStopWaiting),
              if (onReply != null)
                item(PiumaIcon.reply, l.actionReply, onReply),
              if (onForward != null)
                item(PiumaIcon.forward, l.actionForward, onForward),
              if (onMove != null) item(PiumaIcon.folder, l.moveTo, onMove),
              if (onLabel != null) item(PiumaIcon.tag, l.labelMenu, onLabel),
              if (onSide != null)
                item(
                  sideLabel == l.moveToPeople
                      ? PiumaIcon.people
                      : PiumaIcon.bell,
                  sideLabel,
                  onSide,
                ),
              if (onUnsubscribe != null)
                item(PiumaIcon.blocked, l.unsubscribe, onUnsubscribe),
              if (onPrint != null)
                item(PiumaIcon.printer, l.printOrSavePdf, onPrint),
              if (onReportSpam != null)
                item(PiumaIcon.blocked, l.reportSpam, onReportSpam),
              item(PiumaIcon.trash, l.actionDelete, onDelete),
            ],
            builder: (context, menu, _) => _PhoneIconButton(
              icon: PiumaIcon.more,
              label: l.moreActions,
              onTap: () => menu.isOpen ? menu.close() : menu.open(),
            ),
          ),
        ],
      ),
    );
  }
}

/// `TabletPortrait`: the top of the message's panel, with Close and the
/// grabber.
class _PanelTop extends StatelessWidget {
  const _PanelTop({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          PiumaPressable(
            onTap: onClose,
            semanticLabel: l.close,
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: PiumaIconView(PiumaIcon.close, size: 18, color: c.muted),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(PiumaRadius.pill),
                ),
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// `Tablet`: Reply, Archive and Snooze in a pill floating over the foot
/// of the message, and More with the rest, as the phone's More has them.
class _TabletBar extends StatelessWidget {
  const _TabletBar({
    this.onReply,
    this.onArchive,
    this.onSnooze,
    this.onWake,
    this.onWriteAgain,
    this.onStopWaiting,
    this.onRemind,
    this.remindLabel = '',
    this.onForward,
    this.onMove,
    this.onLabel,
    this.onPrint,
    this.onReportSpam,
    this.onNotSpam,
    this.onSide,
    this.sideLabel = '',
    this.onUnsubscribe,
    this.onDelete,
  });

  /// "Move to Notifications" or "Move to People", as [sideLabel].
  final VoidCallback? onSide;
  final String sideLabel;

  final VoidCallback? onRemind;
  final String remindLabel;

  final VoidCallback? onPrint;
  final VoidCallback? onReportSpam;
  final VoidCallback? onNotSpam;
  final VoidCallback? onReply;
  final VoidCallback? onArchive;
  final VoidCallback? onSnooze;
  final VoidCallback? onWake;
  final VoidCallback? onWriteAgain;
  final VoidCallback? onStopWaiting;
  final VoidCallback? onForward;
  final VoidCallback? onMove;
  final VoidCallback? onLabel;
  final VoidCallback? onDelete;

  /// "Unsubscribe", for mail whose list can be left.
  final VoidCallback? onUnsubscribe;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget item(PiumaIcon icon, String label, VoidCallback? onPressed) =>
        MenuItemButton(
          onPressed: onPressed,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(220, 48)),
            overlayColor: WidgetStatePropertyAll(c.chip),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          leadingIcon: PiumaIconView(icon, size: 18, color: c.fg),
          child: Text(label, style: TextStyle(fontSize: 16, color: c.fg)),
        );
    // Reply leads, filled; in Waiting, Write again takes its place.
    final (lead, leadLabel, leadIcon) = onWriteAgain != null
        ? (onWriteAgain, l.writeAgain, PiumaIcon.reply)
        : (onReply, l.actionReply, PiumaIcon.reply);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.pill),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            offset: const Offset(0, 12),
            blurRadius: 32,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lead != null)
            _TabletBarButton(
              icon: leadIcon,
              label: leadLabel,
              onTap: lead,
              filled: true,
            ),
          if (onArchive != null)
            _TabletBarButton(
              icon: PiumaIcon.archive,
              label: l.archive,
              onTap: onArchive,
            ),
          if (onWake != null)
            _TabletBarButton(
              icon: PiumaIcon.inbox,
              label: l.wakeNow,
              onTap: onWake,
            )
          else if (onSnooze != null)
            _TabletBarButton(
              icon: PiumaIcon.clock,
              label: l.actionSnooze,
              onTap: onSnooze,
            ),
          MenuAnchor(
            alignmentOffset: const Offset(-176, -8),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(c.surface),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(0),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: c.line),
                ),
              ),
            ),
            menuChildren: [
              if (onNotSpam != null)
                item(PiumaIcon.inbox, l.notSpam, onNotSpam),
              if (onRemind != null)
                item(PiumaIcon.hourglass, remindLabel, onRemind),
              if (onStopWaiting != null)
                item(PiumaIcon.hourglass, l.stopWaiting, onStopWaiting),
              if (onWriteAgain != null && onReply != null)
                item(PiumaIcon.reply, l.actionReply, onReply),
              if (onForward != null)
                item(PiumaIcon.forward, l.actionForward, onForward),
              if (onMove != null) item(PiumaIcon.folder, l.moveTo, onMove),
              if (onLabel != null) item(PiumaIcon.tag, l.labelMenu, onLabel),
              if (onSide != null)
                item(
                  sideLabel == l.moveToPeople
                      ? PiumaIcon.people
                      : PiumaIcon.bell,
                  sideLabel,
                  onSide,
                ),
              if (onUnsubscribe != null)
                item(PiumaIcon.blocked, l.unsubscribe, onUnsubscribe),
              if (onPrint != null)
                item(PiumaIcon.printer, l.printOrSavePdf, onPrint),
              if (onReportSpam != null)
                item(PiumaIcon.blocked, l.reportSpam, onReportSpam),
              item(PiumaIcon.trash, l.actionDelete, onDelete),
            ],
            builder: (context, menu, _) => PiumaPressable(
              onTap: () => menu.isOpen ? menu.close() : menu.open(),
              semanticLabel: l.moreActions,
              child: SizedBox.square(
                dimension: 46,
                child: Center(
                  child: PiumaIconView(PiumaIcon.more, size: 18, color: c.fg),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletBarButton extends StatelessWidget {
  const _TabletBarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.filled = false,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final ink = filled ? c.onAccent : c.fg;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 46,
        padding: EdgeInsets.symmetric(horizontal: filled ? 20 : 18),
        decoration: BoxDecoration(
          color: filled ? c.accent : null,
          borderRadius: BorderRadius.circular(PiumaRadius.pill),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(icon, size: 17, color: ink),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneIconButton extends StatelessWidget {
  const _PhoneIconButton({required this.icon, required this.label, this.onTap});

  final PiumaIcon icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: 44,
        child: Center(child: PiumaIconView(icon, size: 20, color: c.fg)),
      ),
    );
  }
}

/// Where a reply goes from, for the line under the reply box: an
/// address of the account other than its own, and the signature's name.
typedef ReplyFrom = ({String address, String? signature});

/// "Reply to Giulia…": a few words go out at once, with the usual Undo.
/// At the foot of `PhoneRead` on the phone; under the message on the
/// desktop, as in `Main`, where ⌘↩ (Ctrl ↩) sends. Over a machine's
/// address it says replies likely go unread, and still lets you reply.
class _QuickReply extends StatefulWidget {
  const _QuickReply({
    super.key,
    required this.to,
    required this.onSend,
    this.controller,
    this.onExpand,
    this.from,
    this.machine = false,
    this.phone = false,
  });

  final String to;
  final ValueChanged<String> onSend;
  final TextEditingController? controller;
  final VoidCallback? onExpand;
  final ReplyFrom? from;

  /// The sender looks like a machine (no-reply, notifications…).
  final bool machine;
  final bool phone;

  @override
  State<_QuickReply> createState() => _QuickReplyState();
}

class _QuickReplyState extends State<_QuickReply> {
  late final _ownText = TextEditingController();
  final _focus = FocusNode();

  TextEditingController get _text => widget.controller ?? _ownText;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(_QuickReply old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownText).removeListener(_changed);
      _text.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _text.removeListener(_changed);
    _focus.removeListener(_changed);
    _ownText.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      _focus.requestFocus();
      return;
    }
    _text.clear();
    _focus.unfocus();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final hint = l.quickReplyHint(widget.to);
    final from = widget.from;
    final note = from == null ? null : _ReplyFromLine(from: from);
    final machine = widget.machine
        ? Text(
            l.senderReadsNoReplies,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 12,
              height: 1.4,
              color: c.muted,
            ),
          )
        : null;
    if (!widget.phone) {
      final apple =
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (machine != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: machine,
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            decoration: BoxDecoration(
              color: c.bg,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.card),
            ),
            child: Row(
              children: [
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        meta: true,
                      ): _send,
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): _send,
                    },
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 6,
                      cursorColor: c.accent,
                      style: TextStyle(fontSize: 15, height: 1.4, color: c.fg),
                      decoration:
                          InputDecoration.collapsed(
                            hintText: hint,
                            hintStyle: TextStyle(fontSize: 15, color: c.muted),
                          ).copyWith(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            isDense: true,
                          ),
                    ),
                  ),
                ),
                if (widget.onExpand != null &&
                    (_focus.hasFocus || _text.text.isNotEmpty)) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: l.actionReply,
                    child: PiumaPressable(
                      onTap: widget.onExpand,
                      semanticLabel: l.actionReply,
                      child: SizedBox.square(
                        dimension: 38,
                        child: Center(
                          child: PiumaIconView(
                            PiumaIcon.external,
                            size: 16,
                            color: c.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Text(
                    apple ? '⌘↩' : 'Ctrl ↩',
                    style: TextStyle(
                      fontFamily: PiumaFonts.mono,
                      fontSize: 12,
                      color: c.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PiumaPressable(
                  onTap: _send,
                  semanticLabel: l.sendReply,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(PiumaRadius.button),
                    ),
                    child: PiumaIconView(
                      PiumaIcon.send,
                      size: 17,
                      color: c.onAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: note,
            ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (machine != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: machine,
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      cursorColor: c.accent,
                      style: TextStyle(fontSize: 16, height: 1.3, color: c.fg),
                      decoration: InputDecoration.collapsed(
                        hintText: hint,
                        hintStyle: TextStyle(fontSize: 16, color: c.muted),
                      ),
                    ),
                  ),
                ),
                if (widget.onExpand != null) ...[
                  const SizedBox(width: 4),
                  PiumaPressable(
                    onTap: widget.onExpand,
                    semanticLabel: l.actionReply,
                    child: SizedBox.square(
                      dimension: 40,
                      child: Center(
                        child: PiumaIconView(
                          PiumaIcon.external,
                          size: 18,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                PiumaPressable(
                  onTap: _send,
                  semanticLabel: l.sendReply,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                    child: PiumaIconView(
                      PiumaIcon.send,
                      size: 18,
                      color: c.onAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: note,
            ),
        ],
      ),
    );
  }
}

/// "✓ Reply from fatture@studio.it · signature Work", as on
/// `GroupsSidebar`.
class _ReplyFromLine extends StatelessWidget {
  const _ReplyFromLine({required this.from});

  final ReplyFrom from;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final style = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 12,
      height: 1.4,
      color: c.muted,
    );
    return Row(
      children: [
        PiumaIconView(PiumaIcon.check, size: 13, color: c.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${l.replyFromLabel} '),
                TextSpan(
                  text: from.address,
                  style: TextStyle(color: c.fg, fontWeight: FontWeight.w500),
                ),
                if (from.signature case final name?)
                  TextSpan(text: ' · ${l.replyFromSignature(name)}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// "In short" above a long conversation, as in `FeatureSummary`: its
/// decisions and figures, and "Your turn" when the last message asks
/// something of you.
class InShort extends StatelessWidget {
  const InShort({super.key, required this.brief});

  final ThreadBrief brief;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final text = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 14,
      height: 1.45,
      color: c.fg,
    );
    return Semantics(
      container: true,
      label: l.inShort,
      child: Container(
        padding: const EdgeInsets.all(PiumaSpace.s16),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.inShort,
                    style: text.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PiumaIconView(PiumaIcon.phone, size: 13, color: c.muted),
                const SizedBox(width: 5),
                Text(
                  l.generatedOnDevice,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 12,
                    color: c.muted,
                  ),
                ),
              ],
            ),
            for (final p in brief.points)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text('•', style: text.copyWith(color: c.muted)),
                    ),
                    Expanded(child: Text(p, style: text)),
                  ],
                ),
              ),
            if (brief.yourTurn case final turn?) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: PiumaSpace.s12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(PiumaRadius.button),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 10),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: l.yourTurn,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text:
                                  ' ${brief.askedBy.isEmpty ? turn : l.yourTurnAsks(brief.askedBy, turn)}',
                            ),
                          ],
                        ),
                        style: text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small outlined button in the conversation's header on the phone.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.on = false});

  final String label;
  final VoidCallback onTap;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      selected: on,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? c.chip : c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
          ),
          child: ExcludeSemantics(
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  color: c.fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The reading pane with nothing open, as in `DesktopSelect`.
class _NoneSelected extends StatelessWidget {
  const _NoneSelected({this.touch = false});

  /// On a tablet: "Tap a message to read it", with no keys.
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final keys = apple ? '⌘A' : 'Ctrl A';
    final hint = touch ? l.readerEmptyTap : l.readerEmptyHint(keys);
    final at = hint.indexOf(keys);
    final style = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 13,
      height: 1.45,
      color: c.muted,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PiumaIconView(PiumaIcon.inbox, size: 28, color: c.muted),
            const SizedBox(height: 10),
            Text(
              l.readerEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              at < 0
                  ? TextSpan(text: hint)
                  : TextSpan(
                      children: [
                        TextSpan(text: hint.substring(0, at)),
                        TextSpan(
                          text: keys,
                          style: const TextStyle(fontFamily: PiumaFonts.mono),
                        ),
                        TextSpan(text: hint.substring(at + keys.length)),
                      ],
                    ),
              textAlign: TextAlign.center,
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}
