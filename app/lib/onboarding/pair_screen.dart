import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../settings/sync_page.dart' show syncAgo;
import '../widgets/button.dart';

enum _Pair { found, code, phrase, done }

/// A new device joins the space, as on `PairPhone` and section 4 of
/// `SyncToApprove`: "We found your space", then the code to type on a
/// device already paired (or the recovery phrase), then what came over.
class PairScreen extends StatefulWidget {
  const PairScreen({
    super.key,
    required this.source,
    required this.account,
    required this.found,
    required this.onDone,
    required this.onSkip,
    this.phone = true,
    this.now = DateTime.now,
    this.paired = false,
  });

  final MailSource source;

  /// The account signed in to, whose mailbox holds the space.
  final MailAccount account;

  /// What the mailbox's space says of itself; null once [paired].
  final SpaceFound? found;

  /// Linked already, with a scanned QR code: "Phone paired" right away.
  final bool paired;
  final VoidCallback onDone;

  /// Back from "We found your space": this device goes on alone.
  final VoidCallback onSkip;
  final bool phone;
  final DateTime Function() now;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  late _Pair _step = widget.paired ? _Pair.done : _Pair.found;
  String _code = '';
  DateTime _codeAt = DateTime(0);
  String? _error;
  bool _busy = false;
  Timer? _tick;
  final _phrase = TextEditingController();

  @override
  void initState() {
    super.initState();
    _phrase.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_step == _Pair.code) widget.source.cancelJoin();
    _phrase.dispose();
    super.dispose();
  }

  SyncDevice? get _approver => widget.found?.devices.firstOrNull;

  /// "Matteo's MacBook", or a plain word when the space names none.
  String get _approverName => _approver?.name ?? '';

  void _go(_Pair step) => setState(() {
    _step = step;
    _error = null;
  });

  Future<void> _showCode() async {
    final code = widget.source.pairCode();
    _tick?.cancel();
    setState(() {
      _step = _Pair.code;
      _code = code;
      _codeAt = widget.now();
      _error = null;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      await widget.source.joinSpace(widget.account.id, code);
      if (!mounted || _code != code) return;
      _tick?.cancel();
      _go(_Pair.done);
    } on SyncFailure catch (e) {
      if (!mounted || _code != code) return;
      final l = AppLocalizations.of(context);
      _tick?.cancel();
      setState(() {
        _error = switch (e.problem) {
          SyncProblem.refused => l.pairRefused(_approverName),
          SyncProblem.wrongCode => l.pairWrongCode,
          SyncProblem.expired => l.pairExpired,
          SyncProblem.offline => l.syncFailOffline(widget.account.email),
          _ => l.syncFailOther,
        };
      });
    }
  }

  Future<void> _recover() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.source.recoverSpace(widget.account.id, _words.join(' '));
      if (mounted) _go(_Pair.done);
    } on SyncFailure catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      setState(() {
        _error = switch (e.problem) {
          SyncProblem.wrongPhrase => l.pairPhraseWrong,
          SyncProblem.offline => l.syncFailOffline(widget.account.email),
          _ => l.syncFailOther,
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> get _words => _phrase.text
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  VoidCallback? get _back => switch (_step) {
    _Pair.found => widget.onSkip,
    _Pair.code => () {
      widget.source.cancelJoin();
      _tick?.cancel();
      _code = '';
      _go(_Pair.found);
    },
    _Pair.phrase => () => _go(_Pair.found),
    _Pair.done => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final step = switch (_step) {
      _Pair.found => 1,
      _Pair.code || _Pair.phrase => 2,
      _Pair.done => 3,
    };
    final back = _back;
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              if (back != null)
                Transform.translate(
                  offset: const Offset(-10, 0),
                  child: PiumaPressable(
                    onTap: back,
                    semanticLabel: l.back,
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            PiumaIconView(
                              PiumaIcon.chevronLeft,
                              size: 22,
                              color: c.accentText,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              l.back,
                              style: PiumaType.body.copyWith(
                                fontSize: 16,
                                color: c.accentText,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              _Dots(step: step),
            ],
          ),
        ),
        Expanded(
          child: PiumaEnter(
            key: ValueKey((_step, _code)),
            child: switch (_step) {
              _Pair.found => _found(context),
              _Pair.code => _codeStep(context),
              _Pair.phrase => _phraseStep(context),
              _Pair.done => _done(context),
            },
          ),
        ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back?.call();
      },
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  widget.phone ? 14 : 40,
                  24,
                  widget.phone ? 16 : 40,
                ),
                child: page,
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _title(PiumaColors c) => TextStyle(
    fontFamily: PiumaFonts.sans,
    fontSize: 30,
    height: 1.12,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.9,
    color: c.fg,
  );

  Widget _heading(String text, PiumaColors c) =>
      Semantics(header: true, child: Text(text, style: _title(c)));

  /// "updated yesterday at 18:40".
  String _when(DateTime t) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    final time = DateFormat.Hm(locale).format(t);
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    return switch (today.difference(day).inDays) {
      0 => l.pairTodayAt(time),
      1 => l.pairYesterdayAt(time),
      _ => l.pairOnDay(DateFormat.MMMd(locale).format(t)),
    };
  }

  Widget _found(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final f = widget.found!;
    final approver = _approver;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 28, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: PiumaIconView(
                      PiumaIcon.lock,
                      size: 26,
                      color: c.accentText,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _heading(l.pairFoundTitle, c),
                const SizedBox(height: 8),
                Text(
                  l.pairFoundBody(widget.account.email),
                  style: PiumaType.body.copyWith(fontSize: 15, color: c.muted),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final (i, (n, label)) in [
                            (f.accounts, l.pairAccounts(f.accounts)),
                            (f.groups, l.pairGroups(f.groups)),
                            (f.signatures, l.pairSignatures(f.signatures)),
                          ].indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(child: _Count(n, label)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          PiumaIconView(
                            PiumaIcon.shield,
                            size: 15,
                            color: c.ok,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.pairEncrypted(_when(f.updatedAt)),
                              style: PiumaType.body.copyWith(
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
                if (approver != null) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: PiumaIconView(
                            PiumaIcon.laptop,
                            size: 18,
                            color: c.muted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l.pairConfirmFrom(
                              approver.name,
                              syncAgo(l, approver.lastSeen, widget.now()),
                            ),
                            style: PiumaType.body.copyWith(
                              fontSize: 14,
                              color: c.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        PiumaButton(
          label: l.pairShowCode,
          size: PiumaButtonSize.large,
          onPressed: _showCode,
        ),
        const SizedBox(height: 8),
        PiumaButton(
          label: l.pairUsePhrase,
          kind: PiumaButtonKind.tertiary,
          size: PiumaButtonSize.touch,
          onPressed: () => _go(_Pair.phrase),
        ),
      ],
    );
  }

  Widget _codeStep(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final name = _approverName;
    final left = const Duration(minutes: 5) - widget.now().difference(_codeAt);
    final secs = left.isNegative ? 0 : left.inSeconds;
    final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final shown = '${_code.substring(0, 3)} ${_code.substring(3)}';
    final error = _error;
    final mine = widget.phone ? 'phone' : 'other';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 28, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(l.pairCodeTitle(_approver?.kind.name ?? 'laptop'), c),
                const SizedBox(height: 8),
                Text(
                  l.pairCodeBody(name),
                  style: PiumaType.body.copyWith(fontSize: 15, color: c.muted),
                ),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 30, 16, 24),
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      Semantics(
                        label: l.pairCodeLabel(_code.split('').join(' ')),
                        child: ExcludeSemantics(
                          child: Text(
                            shown,
                            style: TextStyle(
                              fontFamily: PiumaFonts.mono,
                              fontSize: 52,
                              height: 1,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2,
                              color: error == null ? c.fg : c.muted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        error == null ? l.pairExpiresIn(time) : l.pairExpired,
                        style: PiumaType.body.copyWith(
                          fontSize: 13,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Semantics(
                  liveRegion: true,
                  child: error != null
                      ? Text(
                          error,
                          textAlign: TextAlign.center,
                          style: PiumaType.body.copyWith(
                            fontSize: 14,
                            color: c.danger,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _Spinner(),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                l.pairWaiting(name),
                                style: PiumaType.body.copyWith(
                                  fontSize: 14,
                                  color: c.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Numbered(1, l.pairStep1(name, l.syncAskTitle(mine))),
                      const SizedBox(height: 10),
                      _Numbered(2, l.pairStep2),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null)
          PiumaButton(
            label: l.pairNewCode,
            size: PiumaButtonSize.large,
            onPressed: _showCode,
          ),
      ],
    );
  }

  Widget _phraseStep(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final count = _words.length;
    final ready = count == 24 && widget.source.phraseValid(_words.join(' '));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 28, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(l.pairPhraseTitle, c),
                const SizedBox(height: 8),
                Text(
                  l.pairPhraseBody,
                  style: PiumaType.body.copyWith(fontSize: 15, color: c.muted),
                ),
                const SizedBox(height: 24),
                _PhraseField(
                  controller: _phrase,
                  label: l.pairPhraseTitle,
                  onSubmitted: ready && !_busy ? _recover : null,
                ),
                const SizedBox(height: 8),
                Text(
                  l.pairPhraseCount(count),
                  style: PiumaType.body.copyWith(
                    fontSize: 13,
                    color: count > 24 ? c.danger : c.muted,
                  ),
                ),
                if (_error case final e?) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      e,
                      style: PiumaType.body.copyWith(
                        fontSize: 14,
                        color: c.danger,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        PiumaButton(
          label: l.pairContinue,
          size: PiumaButtonSize.large,
          onPressed: ready && !_busy ? _recover : null,
        ),
      ],
    );
  }

  Widget _done(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return _DoneList(
      source: widget.source,
      title: l.pairDoneTitle(widget.phone ? 'phone' : 'other'),
      onDone: widget.onDone,
      heading: _heading,
      colors: c,
    );
  }
}

/// The three dots at the top right: the step shown is the long one.
class _Dots extends StatelessWidget {
  const _Dots({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      label: l.pairStepOf(step),
      child: Row(
        children: [
          for (var i = 1; i <= 3; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            AnimatedContainer(
              duration: instant ? Duration.zero : PiumaMotion.move,
              curve: PiumaMotion.curve,
              width: i == step ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == step ? c.accent : c.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, this.label);
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$n',
            style: PiumaType.body.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.44,
              color: c.fg,
            ),
          ),
          Text(
            label,
            style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _Numbered extends StatelessWidget {
  const _Numbered(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
          child: Text(
            '$n',
            style: PiumaType.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
          ),
        ),
      ],
    );
  }
}

/// The arc that turns while waiting; still with reduce motion.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: PiumaMotion.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return RotationTransition(
      turns: _turn,
      child: SizedBox.square(
        dimension: 16,
        child: CustomPaint(painter: _Arc(c.accent)),
      ),
    );
  }
}

class _Arc extends CustomPainter {
  const _Arc(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: r),
      0,
      4.7,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Arc old) => old.color != color;
}

/// The recovery phrase, typed: several lines, thin border, accent ring
/// when focused.
class _PhraseField extends StatefulWidget {
  const _PhraseField({
    required this.controller,
    required this.label,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final VoidCallback? onSubmitted;

  @override
  State<_PhraseField> createState() => _PhraseFieldState();
}

class _PhraseFieldState extends State<_PhraseField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final focused = _focus.hasFocus;
    final instant = reduceMotion(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: PiumaType.body.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: focused ? c.accent : c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.field),
            boxShadow: focused
                ? [BoxShadow(color: c.ring, spreadRadius: 3)]
                : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Semantics(
              label: widget.label,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: true,
                minLines: 4,
                maxLines: 6,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => widget.onSubmitted?.call(),
                cursorColor: c.accent,
                style: TextStyle(
                  fontFamily: PiumaFonts.mono,
                  fontSize: 15,
                  height: 1.5,
                  color: c.fg,
                ),
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Phone paired": the accounts and groups that came over.
class _DoneList extends StatefulWidget {
  const _DoneList({
    required this.source,
    required this.title,
    required this.onDone,
    required this.heading,
    required this.colors,
  });
  final MailSource source;
  final String title;
  final VoidCallback onDone;
  final Widget Function(String, PiumaColors) heading;
  final PiumaColors colors;

  @override
  State<_DoneList> createState() => _DoneListState();
}

class _DoneListState extends State<_DoneList> {
  List<MailGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    widget.source.groups().then((g) {
      if (mounted) setState(() => _groups = g);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: PiumaType.label.copyWith(
          fontWeight: FontWeight.w500,
          color: c.muted,
        ),
      ),
    );
    Widget synced() => Semantics(
      label: l.pairSynced,
      child: PiumaIconView(PiumaIcon.check, size: 18, color: c.ok),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 28, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: c.ok,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: PiumaIconView(
                        PiumaIcon.check,
                        size: 26,
                        color: c.surface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                widget.heading(widget.title, c),
                const SizedBox(height: 8),
                Text(
                  l.pairDoneBody,
                  style: PiumaType.body.copyWith(fontSize: 15, color: c.muted),
                ),
                const SizedBox(height: 24),
                label(l.pairDoneAccounts),
                for (final a in widget.source.accounts)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: a.email),
                                TextSpan(
                                  text: '  ${a.name}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.muted,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PiumaType.body.copyWith(color: c.fg),
                          ),
                        ),
                        synced(),
                      ],
                    ),
                  ),
                if (_groups.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  label(l.pairDoneGroups),
                  for (final g in _groups)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 40),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: g.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              g.name,
                              style: PiumaType.body.copyWith(
                                fontWeight: FontWeight.w500,
                                color: c.fg,
                              ),
                            ),
                          ),
                          Text(
                            '${g.addresses.length}',
                            style: PiumaType.body.copyWith(
                              fontSize: 13,
                              color: c.muted,
                            ),
                          ),
                          const SizedBox(width: 12),
                          synced(),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      PiumaIconView(PiumaIcon.sync, size: 18, color: c.ok),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.pairDoneSettings,
                          style: PiumaType.body.copyWith(
                            fontSize: 14,
                            color: c.fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        PiumaButton(
          label: l.goToInbox,
          size: PiumaButtonSize.large,
          onPressed: widget.onDone,
        ),
      ],
    );
  }
}
