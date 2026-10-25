import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/date_time_picker.dart';
import '../widgets/dialog.dart';
import '../widgets/switch.dart';
import 'account_page.dart' show SettingsBackLink;

/// "Mon 27 Oct", as the away message writes its days.
String awayDay(DateTime day, String locale) =>
    DateFormat('EEE d MMM', locale).format(day);

/// Settings › Accounts › Work › Away message (`RemindAwayPrintToApprove`,
/// section 2): an automatic reply the mail server sends while the person
/// is away, so it answers with every device off. A switch, the first and
/// last day, a subject and a message. Changes go to the server as they
/// are made; turning it on beside filters of the person's own on the
/// server is refused there and said here, with the server left as it was.
class AwayPage extends StatefulWidget {
  const AwayPage({
    super.key,
    required this.source,
    required this.account,
    required this.onBack,
    this.phone = false,
    this.now = DateTime.now,
  });

  final MailSource source;
  final MailAccount account;
  final VoidCallback onBack;
  final bool phone;
  final DateTime Function() now;

  @override
  State<AwayPage> createState() => _AwayPageState();
}

class _AwayPageState extends State<AwayPage> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _loaded = false;
  bool _on = false;
  DateTime? _start;
  DateTime? _end;

  /// The subject and message are still the ones made from the dates.
  bool _madeSubject = false;
  bool _madeBody = false;

  /// What the server said no to, in words.
  String? _problem;
  Timer? _saveTimer;
  Future<void> _saving = Future.value();

  static const _saveDelay = Duration(milliseconds: 800);

  DateTime get _today {
    final n = widget.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// The words for what went wrong, read while the page is up: a change
  /// still waiting is sent as the page goes.
  late AppLocalizations _l;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      unawaited(_push());
    }
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final m = await widget.source.awayMessage(widget.account.id);
    if (!mounted || m == null) return;
    setState(() {
      _loaded = true;
      _on = m.on;
      _start = m.start;
      _end = m.end;
      _subject.text = m.subject;
      _body.text = m.body;
      _madeSubject = m.subject.isEmpty;
      _madeBody = m.body.isEmpty;
    });
    _fillIn();
    _subject.addListener(_typedSubject);
    _body.addListener(_typedBody);
  }

  /// "Away until 3 November": the day after the last, when it has one.
  void _fillIn() {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final back = switch (_end) {
      final e? => DateTime(e.year, e.month, e.day + 1),
      null => null,
    };
    if (_madeSubject) {
      _subject.text = back == null
          ? l.awaySubjectPlain
          : l.awaySubjectUntil(DateFormat('d MMMM', locale).format(back));
    }
    if (_madeBody) {
      _body.text = back == null
          ? l.awayBodyPlain
          : l.awayBodyUntil(DateFormat('EEEE d MMMM', locale).format(back));
    }
  }

  void _typedSubject() {
    if (_filling) return;
    _madeSubject = false;
    _later();
  }

  void _typedBody() {
    if (_filling) return;
    _madeBody = false;
    _later();
  }

  bool _filling = false;

  void _refill() {
    _filling = true;
    _fillIn();
    _filling = false;
  }

  void _later() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_push()));
  }

  AwayMessage get _message => AwayMessage(
    on: _on,
    start: _start,
    end: _end,
    subject: _subject.text.trim(),
    body: _body.text.trim(),
  );

  /// Sends what is set to the server, one change after the other.
  Future<void> _push() {
    _saveTimer?.cancel();
    final message = _message;
    final l = _l;
    return _saving = _saving.then((_) async {
      String? problem;
      var on = message.on;
      try {
        final saved = await widget.source.setAwayMessage(
          widget.account.id,
          message,
        );
        switch (saved) {
          case AwaySaved.saved:
            break;
          case AwaySaved.otherFilters:
            on = false;
            problem = l.awayOtherFilters;
          case AwaySaved.unsupported:
            on = false;
            problem = l.awayUnsupported;
        }
      } catch (_) {
        problem = l.awayOffline;
        // Turning on that did not happen stays off.
        if (message.on) on = false;
      }
      if (!mounted) return;
      setState(() {
        _problem = problem;
        if (_on == message.on) _on = on;
      });
    });
  }

  void _setOn(bool on) {
    setState(() {
      _on = on;
      _problem = null;
    });
    unawaited(_push());
  }

  Future<void> _pick({required bool last}) async {
    final l = AppLocalizations.of(context);
    final phone = widget.phone;
    final title = last ? l.awayPickTo : l.awayPickFrom;
    final today = _today;
    // A picked day, or this for "Keep it on until I turn it off".
    const none = Object();
    Widget picker(BuildContext context) => Padding(
      padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 0),
      child: PickDay(
        today: today,
        title: title,
        phone: phone,
        initial: last ? _end : _start,
        first: last ? (_start ?? today) : today,
        clearLabel: last ? l.awayKeepOn : null,
        onClear: () => Navigator.of(context).pop(none),
        onPick: (d) => Navigator.of(context).pop(d),
      ),
    );
    final picked = phone
        ? await showPiumaSheet<Object>(context, label: title, builder: picker)
        : await showPiumaDialog<Object>(
            context,
            label: title,
            width: 384,
            builder: picker,
          );
    if (picked == null || !mounted) return;
    setState(() {
      final day = picked is DateTime ? picked : null;
      if (last) {
        _end = day;
      } else {
        _start = day;
        // The last day can't come before the first.
        if (day != null && (_end?.isBefore(day) ?? false)) _end = day;
      }
      _refill();
    });
    unawaited(_push());
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final phone = widget.phone;
    final from = switch (_start) {
      final s? when s.isAfter(_today) => awayDay(s, locale),
      _ => l.awayToday,
    };
    final to = switch (_end) {
      final e? => awayDay(e, locale),
      null => l.awayNoEnd,
    };
    final problem = _problem;
    final problemLine = problem == null
        ? null
        : Semantics(
            liveRegion: true,
            child: Text(
              problem,
              style: PiumaType.small.copyWith(color: c.warn),
            ),
          );

    final toggle = PiumaSwitch(
      value: _on,
      label: l.awayTitle,
      onChanged: _loaded ? _setOn : null,
    );

    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.awayTitle, style: PiumaType.title.copyWith(color: c.fg)),
          const SizedBox(height: PiumaSpace.s12),
          _Group(
            children: [
              _Row(
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          l.awayTitle,
                          style: PiumaType.body.copyWith(color: c.fg),
                        ),
                      ),
                    ),
                    toggle,
                  ],
                ),
              ),
              _Row(
                onTap: () => _pick(last: false),
                semanticLabel: '${l.awayFrom}, $from',
                child: _Pair(label: l.awayFrom, value: from),
              ),
              _Row(
                onTap: () => _pick(last: true),
                semanticLabel: '${l.awayTo}, $to',
                child: _Pair(label: l.awayTo, value: to),
              ),
            ],
          ),
          if (problemLine != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: PiumaEnter(child: problemLine),
            ),
          const SizedBox(height: PiumaSpace.s12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Bare(
                  controller: _subject,
                  label: l.awaySubject,
                  style: PiumaType.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                const SizedBox(height: 6),
                _Bare(
                  controller: _body,
                  label: l.awayMessage,
                  lines: true,
                  style: PiumaType.body.copyWith(
                    fontSize: 14,
                    height: 1.5,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SettingsBackLink(
            label: widget.account.name,
            onTap: widget.onBack,
          ),
        ),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(
            l.awayTitle,
            style: PiumaType.title.copyWith(color: c.fg),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.awayTitle,
                              style: PiumaType.body.copyWith(color: c.fg),
                            ),
                            Text(
                              l.awayNote,
                              style: PiumaType.small.copyWith(color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    toggle,
                  ],
                ),
              ),
              if (problemLine != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: PiumaEnter(child: problemLine),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          l.awayFrom,
                          style: PiumaType.body.copyWith(color: c.fg),
                        ),
                      ),
                    ),
                    _DayChip(
                      text: from,
                      label: '${l.awayFrom}, $from',
                      onTap: () => _pick(last: false),
                    ),
                    const SizedBox(width: 12),
                    ExcludeSemantics(
                      child: Text(
                        l.awayToInline,
                        style: PiumaType.body.copyWith(color: c.muted),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _DayChip(
                      text: to,
                      label: '${l.awayTo}, $to',
                      muted: _end == null,
                      onTap: () => _pick(last: true),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Label(l.awaySubject),
                    const SizedBox(height: 8),
                    _Boxed(controller: _subject, label: l.awaySubject),
                    const SizedBox(height: 8),
                    _Label(l.awayMessage),
                    const SizedBox(height: 8),
                    _Boxed(
                      controller: _body,
                      label: l.awayMessage,
                      lines: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.awayEndsNote,
                      style: PiumaType.small.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

/// The phone's grouped rows, bordered as the rest of the phone's
/// Settings, with lines between.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.card),
      ),
      child: Column(
        children: [
          for (final (i, child) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.child, this.onTap, this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
    return onTap == null
        ? content
        : PiumaPressable(
            onTap: onTap,
            semanticLabel: semanticLabel,
            child: ExcludeSemantics(child: content),
          );
  }
}

/// "From      Mon 27 Oct".
class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(label, style: PiumaType.body.copyWith(color: c.fg)),
        ),
        Text(value, style: PiumaType.body.copyWith(color: c.muted)),
      ],
    );
  }
}

/// A day on the desktop row: "Mon 27 Oct" on a chip.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.text,
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final String text;
  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.chip,
            borderRadius: BorderRadius.circular(PiumaRadius.field),
          ),
          child: Text(
            text,
            style: PiumaType.small.copyWith(color: muted ? c.muted : c.fg),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(
      text,
      style: PiumaType.small.copyWith(color: PiumaTheme.of(context).muted),
    ),
  );
}

/// A bordered field: one line for the subject, several for the message.
class _Boxed extends StatefulWidget {
  const _Boxed({
    required this.controller,
    required this.label,
    this.lines = false,
  });

  final TextEditingController controller;
  final String label;
  final bool lines;

  @override
  State<_Boxed> createState() => _BoxedState();
}

class _BoxedState extends State<_Boxed> {
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
    return AnimatedContainer(
      duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
      curve: PiumaMotion.curve,
      constraints: BoxConstraints(minHeight: widget.lines ? 96 : 36),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: widget.lines ? 10 : 7,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: focused ? c.accent : c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.button),
      ),
      child: _Bare(
        controller: widget.controller,
        label: widget.label,
        focusNode: _focus,
        lines: widget.lines,
        style: PiumaType.body.copyWith(
          fontSize: 14,
          height: widget.lines ? 1.55 : 1.4,
          color: c.fg,
        ),
      ),
    );
  }
}

/// A text field with no frame of its own.
class _Bare extends StatelessWidget {
  const _Bare({
    required this.controller,
    required this.label,
    required this.style,
    this.focusNode,
    this.lines = false,
  });

  final TextEditingController controller;
  final String label;
  final TextStyle style;
  final FocusNode? focusNode;
  final bool lines;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      label: label,
      textField: true,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        minLines: 1,
        maxLines: lines ? null : 1,
        keyboardType: lines ? TextInputType.multiline : TextInputType.text,
        cursorColor: c.accent,
        style: style,
        decoration: InputDecoration.collapsed(
          hintText: label,
          hintStyle: style.copyWith(color: c.placeholder),
        ),
      ),
    );
  }
}
