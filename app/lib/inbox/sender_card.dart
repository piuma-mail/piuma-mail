import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import 'pictures.dart';
import '../widgets/dialog.dart';
import '../widgets/links.dart';
import '../widgets/message_row.dart';
import '../widgets/route.dart';
import '../widgets/verified.dart';
import 'attachments.dart' show FilePreview;
import 'message_list.dart' show initials;
import 'sections.dart' show rowTime;

/// What the person picked on a sender's card.
sealed class SenderPick {
  const SenderPick();
}

/// Write them a new email.
class WriteToSender extends SenderPick {
  const WriteToSender();
}

/// Every email from them, as a search.
class AllFromSender extends SenderPick {
  const AllFromSender();
}

/// Rules & folders, from the card's ⋯ menu.
class RulesForSender extends SenderPick {
  const RulesForSender();
}

/// One of their emails.
class OpenFromSender extends SenderPick {
  const OpenFromSender(this.row);
  final MailRow row;
}

/// A sender's card for [row]'s sender: a popover under [anchor] on the
/// desktop (`DesktopSender`), a page of its own on the phone
/// (`PhoneSender`).
Future<SenderPick?> showSenderCard(
  BuildContext context, {
  required MailSource source,
  required MailRow row,
  required DateTime Function() now,
  Rect? anchor,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  final card = SenderCard(source: source, row: row, now: now, phone: phone);
  if (phone) {
    return Navigator.of(context).push(PiumaRoute.of(context, (_) => card));
  }
  if (anchor == null) {
    return showPiumaDialog<SenderPick>(
      context,
      label: l.senderCardLabel(row.sender),
      width: 380,
      builder: (_) => card,
    );
  }
  return showPiumaPopover<SenderPick>(
    context,
    label: l.senderCardLabel(row.sender),
    anchor: anchor,
    width: 340,
    builder: (_) => card,
  );
}

class SenderCard extends StatefulWidget {
  const SenderCard({
    super.key,
    required this.source,
    required this.row,
    required this.now,
    this.phone = false,
  });

  final MailSource source;
  final MailRow row;
  final DateTime Function() now;
  final bool phone;

  @override
  State<SenderCard> createState() => _SenderCardState();
}

class _SenderCardState extends State<SenderCard> {
  List<MailRow>? _recent;
  SenderBrief? _brief;
  bool _muted = false;
  bool _blocked = false;

  /// On the phone, a newsletter's card (`PhoneSenderNewsletter`): how much
  /// it writes, Unsubscribe and Move to Newsletters.
  SenderStats? _stats;
  UnsubscribeInfo _unsubscribe = UnsubscribeInfo.none;
  bool _inNewsletters = false;
  _Leaving _leaving = _Leaving.no;

  /// Leaving went wrong: say so over the button.
  bool _failed = false;

  /// Emails moved to Trash after leaving.
  int _cleared = 0;

  /// On the phone: the files they sent, the addresses they write from,
  /// and which tab shows (Conversations or Attachments).
  List<AttachedFile> _files = const [];
  List<SenderAddress> _addresses = const [];
  bool _filesTab = false;
  final _thumbs = <Object, Future<Uint8List?>>{};
  final _menu = MenuController();

  Future<Uint8List?> _thumb(AttachedFile f) => _thumbs.putIfAbsent((
    f.row.key,
    f.file.part,
  ), () => widget.source.attachmentThumb(f).catchError((Object _) => null));

  bool get _newsletter =>
      _unsubscribe.kind != UnsubscribeKind.none ||
      (_stats?.inNewsletters ?? false);

  String get _email => widget.row.fromEmail;

  /// The account's server vouched for this message's sender.
  late final bool _verified = widget.source.senderVerified(widget.row);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final found = await widget.source.search(
      'from:$_email',
      limit: widget.phone ? 6 : 3,
    );
    final muted = await widget.source.isMuted(_email);
    final blocked = widget.phone
        ? await widget.source.isBlocked(_email)
        : false;
    // "In short" turned off in Settings › Features: no brief here either.
    final brief = widget.source.features.value.inShort
        ? await widget.source.senderBrief(_email).catchError((Object _) => null)
        : null;
    final stats = widget.phone ? await widget.source.senderStats(_email) : null;
    final unsubscribe = widget.phone
        ? await widget.source.unsubscribeInfo(widget.row)
        : UnsubscribeInfo.none;
    final files = widget.phone
        ? await widget.source.senderFiles(_email)
        : const <AttachedFile>[];
    final addresses = widget.phone
        ? await widget.source.senderAddresses(_email)
        : const <SenderAddress>[];
    if (!mounted) return;
    setState(() {
      _files = files;
      _addresses = addresses;
      _stats = stats;
      _unsubscribe = unsubscribe;
      _inNewsletters = stats?.inNewsletters ?? false;
      _recent = [for (final h in found.hits) h.row];
      _muted = muted;
      _blocked = blocked;
      _brief = brief;
    });
  }

  Future<void> _mute() async {
    final muted = !_muted;
    setState(() => _muted = muted);
    await widget.source.setMuted(_email, muted);
  }

  Future<void> _block() async {
    final blocked = !_blocked;
    setState(() => _blocked = blocked);
    await widget.source.setBlocked(_email, blocked);
  }

  void _pick(SenderPick pick) => Navigator.of(context).pop(pick);

  Future<void> _leave() async {
    if (_unsubscribe.kind == UnsubscribeKind.page) {
      final uri = Uri.tryParse(_unsubscribe.address);
      if (uri != null) await openExternalLink(uri);
      if (mounted) setState(() => _leaving = _Leaving.page);
      return;
    }
    try {
      await widget.source.unsubscribe(widget.row);
      if (mounted) setState(() => _leaving = _Leaving.ask);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Moves what the newsletter sent before to Trash.
  Future<void> _clear() async {
    final found = await widget.source.search('from:$_email', limit: 1000);
    final rows = [
      for (final h in found.hits)
        if (h.row.fromEmail.toLowerCase() == _email.toLowerCase()) h.row,
    ];
    if (rows.isNotEmpty) {
      await widget.source.apply(rows, MessageAction.delete);
    }
    if (!mounted) return;
    setState(() {
      _cleared = rows.length;
      _leaving = _Leaving.cleared;
    });
  }

  Future<void> _move() async {
    final moved = !_inNewsletters;
    setState(() => _inNewsletters = moved);
    await widget.source.setSenderZone(
      _email,
      moved ? MailFolder.newsletters : MailFolder.inbox,
    );
  }

  MailAccount? get _account {
    for (final a in widget.source.accounts) {
      if (a.id == widget.row.accountId) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => PictureScope(
    // The card opens in a route of its own, outside the inbox's scope.
    pictures: widget.source.pictures,
    child: Builder(
      builder: (context) => widget.phone ? _page(context) : _popover(context),
    ),
  );

  Widget _popover(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = widget.row;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SenderPicture(
                email: row.fromEmail,
                size: 52,
                letter: PiumaAvatar(initials: initials(row.sender), size: 52),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        row.sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.subtitle.copyWith(color: c.fg),
                      ),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PiumaType.small.copyWith(color: c.muted),
                          ),
                        ),
                        if (_verified) ...[
                          const SizedBox(width: 6),
                          Semantics(
                            label: l.verifiedSenderLabel,
                            child: PiumaIconView(
                              PiumaIcon.shield,
                              size: 14,
                              color: c.ok,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_brief case final b? when b.telling)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SenderInShort(brief: b),
            ),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in _recent ?? const <MailRow>[])
                  _RecentLine(
                    row: r,
                    when: _when(context, r),
                    onTap: () => _pick(OpenFromSender(r)),
                  ),
                if (_recent != null && _recent!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      l.senderNoMail,
                      style: PiumaType.small.copyWith(color: c.muted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: _Button(
                  label: l.senderWrite,
                  strong: true,
                  onTap: () => _pick(const WriteToSender()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 13,
                child: _Button(
                  label: l.senderAll,
                  onTap: () => _pick(const AllFromSender()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 10,
                child: _Button(
                  label: _muted ? l.senderMuted : l.senderMute,
                  on: _muted,
                  onTap: _mute,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _when(BuildContext context, MailRow r) => rowTime(
    r.receivedAt,
    widget.now(),
    Localizations.localeOf(context).toLanguageTag(),
  );

  Widget _page(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final row = widget.row;
    final account = _account;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: l.senderCardLabel(row.sender),
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                child: Row(
                  children: [
                    PiumaPressable(
                      onTap: () => Navigator.of(context).pop(),
                      semanticLabel: l.senderClose,
                      child: SizedBox.square(
                        dimension: 44,
                        child: Center(
                          child: PiumaIconView(PiumaIcon.close, color: c.fg),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _newsletter ? l.senderNewsletterKind : l.senderKind,
                        textAlign: TextAlign.center,
                        style: PiumaType.label.copyWith(
                          fontSize: 14,
                          color: c.muted,
                        ),
                      ),
                    ),
                    _MoreMenu(
                      controller: _menu,
                      onCopy: () =>
                          Clipboard.setData(ClipboardData(text: _email)),
                      onRules: () => _pick(const RulesForSender()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 32),
                  children: [
                    Center(
                      child: SenderPicture(
                        email: row.fromEmail,
                        size: 84,
                        letter: PiumaAvatar(
                          initials: initials(row.sender),
                          size: 84,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      header: true,
                      child: Text(
                        row.sender,
                        textAlign: TextAlign.center,
                        style: PiumaType.title.copyWith(
                          fontSize: 24,
                          color: c.fg,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _email,
                      textAlign: TextAlign.center,
                      style: PiumaType.body.copyWith(
                        fontSize: 14,
                        color: c.muted,
                      ),
                    ),
                    if (_verified) ...[
                      const SizedBox(height: 6),
                      Semantics(
                        label: l.verifiedSenderLabel,
                        child: ExcludeSemantics(
                          child: Center(
                            child: VerifiedPill(
                              label: l.verifiedBadge,
                              icon: PiumaIcon.shield,
                              large: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (account != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                          Text(
                            l.senderArrivesIn(account.name),
                            style: PiumaType.small.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      // A label on two lines ("Tutte le email") keeps its
                      // circle in line with the others.
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_newsletter) ...[
                          _RoundAction(
                            icon: PiumaIcon.compose,
                            label: l.senderWrite,
                            onTap: () => _pick(const WriteToSender()),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _RoundAction(
                          icon: PiumaIcon.search,
                          label: l.senderAll,
                          onTap: () => _pick(const AllFromSender()),
                        ),
                        const SizedBox(width: 6),
                        _RoundAction(
                          icon: PiumaIcon.bell,
                          label: _muted ? l.senderMuted : l.senderMute,
                          on: _muted,
                          onTap: _mute,
                        ),
                        const SizedBox(width: 6),
                        _RoundAction(
                          icon: PiumaIcon.blocked,
                          label: _blocked ? l.senderBlocked : l.senderBlock,
                          on: _blocked,
                          danger: true,
                          onTap: _block,
                        ),
                      ],
                    ),
                    if (_brief case final b? when b.telling)
                      Container(
                        margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: PiumaSpace.s12,
                        ),
                        decoration: BoxDecoration(
                          color: c.bg,
                          borderRadius: BorderRadius.circular(PiumaRadius.card),
                        ),
                        child: SenderInShort(brief: b, onDevice: true),
                      ),
                    if (_newsletter) _newsletterPanel(context),
                    _Tabs(
                      files: _filesTab,
                      onPick: (files) => setState(() => _filesTab = files),
                    ),
                    if (_filesTab)
                      ..._allFiles(context)
                    else
                      ..._conversations(context),
                    if (_addresses.isNotEmpty) ...[
                      _Header(l.senderAddresses, top: 26),
                      _Addresses(
                        addresses: _addresses,
                        accounts: widget.source.accounts,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Conversations tab: their emails, then the files they shared.
  List<Widget> _conversations(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return [
      _Header(l.senderConversations),
      for (final r in _recent ?? const <MailRow>[])
        _Conversation(
          row: r,
          when: _when(context, r),
          onTap: () => _pick(OpenFromSender(r)),
        ),
      if (_recent != null && _recent!.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            l.senderNoMail,
            style: PiumaType.small.copyWith(color: c.muted),
          ),
        ),
      if (_files.isNotEmpty) ...[
        _Header(l.senderSharedFiles, top: 24, bottom: 10),
        SizedBox(
          height: 74 + 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final (i, f) in _files.take(3).indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                SizedBox(width: 136, child: _fileCard(context, f, 74)),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  /// The Attachments tab: every file they sent, two by two.
  List<Widget> _allFiles(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return [
      _Header(l.senderFileCount(_files.length), bottom: 10),
      if (_files.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            l.senderNoFiles,
            style: PiumaType.small.copyWith(color: c.muted),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (var i = 0; i < _files.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _fileCard(context, _files[i], 84)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: i + 1 < _files.length
                          ? _fileCard(context, _files[i + 1], 84)
                          : const SizedBox(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
    ];
  }

  /// A file's card: its preview, name, size and day. A tap opens the
  /// email it came with.
  Widget _fileCard(BuildContext context, AttachedFile f, double preview) {
    final c = PiumaTheme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final mark = widget.source.accounts
        .where((a) => a.id == f.row.accountId)
        .map((a) => a.color)
        .firstOrNull;
    final meta =
        '${fileSize(f.file.size, locale: locale)} · ${_when(context, f.row)}';
    return PiumaPressable(
      onTap: () => _pick(OpenFromSender(f.row)),
      semanticLabel: '${f.file.name}, $meta',
      child: ExcludeSemantics(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.card),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PiumaRadius.card),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: preview,
                child: FilePreview(
                  file: f.file,
                  thumb: _thumb(f),
                  mark: mark ?? c.muted,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.small.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                      ),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.label.copyWith(color: c.muted),
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

  Widget _newsletterPanel(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final stats = _stats;
    final weeks = SenderStats.days / 7;
    final perWeek = stats == null ? 0 : (stats.recent / weeks).round();
    final often = stats == null || stats.recent == 0
        ? null
        : perWeek >= 1
        ? l.newsletterPerWeek(perWeek)
        : l.newsletterPerMonth((stats.recent / (SenderStats.days / 30)).ceil());
    Widget done(Widget child) => Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.all(PiumaSpace.s12),
      decoration: BoxDecoration(
        color: c.okSoft,
        borderRadius: BorderRadius.circular(PiumaRadius.row),
      ),
      child: Semantics(liveRegion: true, child: child),
    );
    Widget tick(String text, {String? bold}) => Row(
      children: [
        PiumaIconView(PiumaIcon.check, size: 16, color: c.ok),
        const SizedBox(width: PiumaSpace.s8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (bold != null)
                  TextSpan(
                    text: '$bold · ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                TextSpan(text: text),
              ],
            ),
            style: PiumaType.small.copyWith(fontSize: 14, color: c.fg),
          ),
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(PiumaSpace.s16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PiumaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (often != null && stats != null) ...[
            Row(
              children: [
                PiumaIconView(PiumaIcon.mail, size: 17, color: c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$often · ${l.newsletterOpened(stats.openedPercent)}',
                    style: PiumaType.small.copyWith(fontSize: 14, color: c.fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: PiumaSpace.s12),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PiumaRadius.pill),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: c.chip)),
                      FractionallySizedBox(
                        widthFactor: stats.openedPercent / 100,
                        heightFactor: 1,
                        child: ColoredBox(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: PiumaSpace.s12),
          ],
          if (_failed && _leaving == _Leaving.no) ...[
            Text(
              l.unsubscribeFailed,
              style: PiumaType.small.copyWith(color: c.danger),
            ),
            const SizedBox(height: PiumaSpace.s8),
          ],
          switch (_leaving) {
            _Leaving.no when _unsubscribe.kind != UnsubscribeKind.none =>
              PiumaPressable(
                onTap: _leave,
                semanticLabel: l.unsubscribe,
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.fg,
                    borderRadius: BorderRadius.circular(PiumaRadius.row),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      l.unsubscribe,
                      style: PiumaType.body.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.surface,
                      ),
                    ),
                  ),
                ),
              ),
            _Leaving.no => const SizedBox.shrink(),
            _Leaving.ask => done(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tick(l.newsletterClearAsk, bold: l.newsletterUnsubscribed),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Choice(
                          label: l.newsletterClearYes,
                          strong: true,
                          onTap: _clear,
                        ),
                      ),
                      const SizedBox(width: PiumaSpace.s8),
                      Expanded(
                        child: _Choice(
                          label: l.newsletterClearNo,
                          onTap: () => setState(() => _leaving = _Leaving.kept),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _Leaving.cleared => done(tick(l.newsletterCleared(_cleared))),
            _Leaving.kept => done(tick(l.newsletterKept)),
            _Leaving.page => done(tick(l.newsletterPageOpened)),
          },
          if (_leaving != _Leaving.no ||
              _unsubscribe.kind != UnsubscribeKind.none)
            const SizedBox(height: PiumaSpace.s12),
          Semantics(
            toggled: _inNewsletters,
            child: PiumaPressable(
              onTap: _move,
              semanticLabel: _inNewsletters
                  ? l.movedToNewsletters
                  : l.moveToNewsletters,
              child: ExcludeSemantics(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(PiumaRadius.row),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PiumaIconView(
                        PiumaIcon.newsletter,
                        size: 16,
                        color: c.fg,
                      ),
                      const SizedBox(width: PiumaSpace.s8),
                      Text(
                        _inNewsletters
                            ? l.movedToNewsletters
                            : l.moveToNewsletters,
                        style: PiumaType.small.copyWith(
                          fontSize: 14,
                          color: c.fg,
                        ),
                      ),
                    ],
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

/// "In short: mostly about “Quote for the Via Roma site”; the latest is
/// waiting on your reply.", as in `DesktopSender` and `PhoneSender`.
class SenderInShort extends StatelessWidget {
  const SenderInShort({super.key, required this.brief, this.onDevice = false});

  final SenderBrief brief;

  /// Ends with "· on device", as on the phone.
  final bool onDevice;

  static String words(AppLocalizations l, SenderBrief b) {
    final first = [
      if (b.topic case final t?) l.senderBriefTopic(t),
      if (b.recent > 0) l.senderBriefCount(b.recent),
    ].join(', ');
    final all = [
      if (first.isNotEmpty) first,
      if (b.waiting) l.senderBriefWaiting,
    ].join('; ');
    return '$all.';
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final size = onDevice ? 13.5 : 13.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: PiumaIconView(PiumaIcon.spark, size: 14, color: c.muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: l.inShortColon,
                  style: TextStyle(color: c.fg, fontWeight: FontWeight.w500),
                ),
                TextSpan(text: ' ${words(l, brief)}'),
                // Kept together, never "·" alone at the end of a line.
                if (onDevice)
                  TextSpan(
                    text: ' ${'· ${l.onDevice}'.replaceAll(' ', '\u00a0')}',
                  ),
              ],
            ),
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: size,
              height: 1.5,
              color: c.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// One of their recent emails, as a line of `DesktopSender`.
class _RecentLine extends StatelessWidget {
  const _RecentLine({
    required this.row,
    required this.when,
    required this.onTap,
  });

  final MailRow row;
  final String when;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final subject = row.subject.isEmpty ? l.noSubject : row.subject;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: subject,
      child: ExcludeSemantics(
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.small.copyWith(
                    fontSize: 13.5,
                    color: c.fg,
                    fontWeight: row.seen ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(when, style: PiumaType.label.copyWith(color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of their emails on the phone card: subject, date and preview.
class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.row,
    required this.when,
    required this.onTap,
  });

  final MailRow row;
  final String when;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final subject = row.subject.isEmpty ? l.noSubject : row.subject;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: subject,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 8, right: 10),
                decoration: BoxDecoration(
                  color: row.seen ? null : c.accent,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PiumaType.body.copyWith(
                              color: c.fg,
                              fontWeight: row.seen
                                  ? FontWeight.w500
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          when,
                          style: PiumaType.label.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                    Text(
                      row.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.small.copyWith(
                        fontSize: 13.5,
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

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onTap,
    this.strong = false,
    this.on,
  });

  final String label;
  final VoidCallback onTap;
  final bool strong;

  /// For a switch (Mute), whether it is on.
  final bool? on;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      toggled: on,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: ExcludeSemantics(
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: strong ? c.accent : (on == true ? c.chip : c.surface),
              border: strong ? null : Border.all(color: c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.button),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: PiumaType.small.copyWith(
                fontSize: 13.5,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                color: strong ? c.onAccent : c.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round action under the name on the phone card.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.on = false,
    this.danger = false,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback onTap;
  final bool on;

  /// Red when on (Block), as `PhoneSender` draws it.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final strong = on ? (danger ? c.danger : c.fg) : null;
    return Semantics(
      toggled: on,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: ExcludeSemantics(
          child: SizedBox(
            width: 76,
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: strong ?? c.chip,
                    borderRadius: BorderRadius.circular(PiumaRadius.card),
                  ),
                  alignment: Alignment.center,
                  child: PiumaIconView(icon, color: on ? c.surface : c.fg),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: PiumaType.label.copyWith(
                    color: on && danger ? c.danger : c.fg,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
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

/// Where leaving a newsletter is, on its card.
enum _Leaving {
  /// Not asked yet.
  no,

  /// Left; clear the old emails too?
  ask,
  cleared,
  kept,

  /// Its page opened in the browser.
  page,
}

/// One of the two answers after Unsubscribe.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.onTap,
    this.strong = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: strong ? c.fg : c.surface,
            border: strong ? null : Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.button),
          ),
          child: Text(
            label,
            style: PiumaType.body.copyWith(
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
              color: strong ? c.surface : c.fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// A section's heading on the phone card: "CONVERSATIONS", "ADDRESSES".
class _Header extends StatelessWidget {
  const _Header(this.text, {this.top = 22, this.bottom = 6});

  final String text;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top, 20, bottom),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: PiumaType.label.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: c.muted,
          ),
        ),
      ),
    );
  }
}

/// Conversations and Attachments, as on `PhoneSender`: two halves on the
/// chip color, the one shown on a white pill that slides.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.files, required this.onPick});

  /// Attachments shows.
  final bool files;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final slide = reduceMotion(context) ? Duration.zero : PiumaMotion.move;
    Widget tab(String label, bool on, bool pick) => Expanded(
      child: Semantics(
        selected: on,
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onPick(pick),
          child: ExcludeSemantics(
            child: Center(
              child: Text(
                label,
                style: PiumaType.small.copyWith(
                  fontSize: 14,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? c.fg : c.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: l.senderContent,
      container: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: slide,
              curve: PiumaMotion.curve,
              alignment: files ? Alignment.centerRight : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: c.fg.withValues(alpha: 0.10),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                tab(l.senderConversations, !files, false),
                tab(l.folderAttachments, files, true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The addresses a sender writes from, in a bordered box: the address,
/// "Work · 18 emails", and the green shield when a server vouched for it.
class _Addresses extends StatelessWidget {
  const _Addresses({required this.addresses, required this.accounts});

  final List<SenderAddress> addresses;
  final List<MailAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.card),
      ),
      child: Column(
        children: [
          for (final (i, a) in addresses.indexed)
            Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PiumaType.small.copyWith(
                            fontSize: 14,
                            color: c.fg,
                          ),
                        ),
                        Text(
                          l.senderAddressNote(
                            accounts
                                    .where((x) => x.id == a.accountId)
                                    .map((x) => x.name)
                                    .firstOrNull ??
                                '',
                            a.emails,
                          ),
                          style: PiumaType.label.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  if (a.verified)
                    Semantics(
                      label: l.verifiedBadge,
                      child: PiumaIconView(
                        PiumaIcon.shield,
                        size: 16,
                        color: c.ok,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The card's ⋯: Copy address and Rules & folders (not drawn on the
/// boards beyond the button).
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.controller,
    required this.onCopy,
    required this.onRules,
  });

  final MenuController controller;
  final VoidCallback onCopy;
  final VoidCallback onRules;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget item(PiumaIcon icon, String label, VoidCallback onPressed) =>
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
    return MenuAnchor(
      controller: controller,
      alignmentOffset: const Offset(-184, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
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
        item(PiumaIcon.copy, l.senderCopyAddress, onCopy),
        item(PiumaIcon.folder, l.senderRules, onRules),
      ],
      builder: (context, menu, _) => PiumaPressable(
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        semanticLabel: l.moreActions,
        child: SizedBox.square(
          dimension: 44,
          child: Center(child: PiumaIconView(PiumaIcon.more, color: c.fg)),
        ),
      ),
    );
  }
}
