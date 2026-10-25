import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import 'sync_page.dart' show deviceIcon, syncAgo;

/// "New phone wants to connect", as on `SyncToApprove`: a dialog on the
/// desktop, a sheet on the phone. Typing the 6 digits the new device
/// shows is what proves it's the person's own.
Future<void> showPairAsk(
  BuildContext context, {
  required MailSource source,
  required PairAsk ask,
  bool phone = false,
  DateTime Function() now = DateTime.now,
}) {
  final l = AppLocalizations.of(context);
  final title = l.syncAskTitle(ask.kind.name);
  Widget panel(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: PairAskPanel(source: source, ask: ask, phone: phone, now: now),
  );
  return phone
      ? showPiumaSheet<void>(context, label: title, builder: panel)
      : showPiumaDialog<void>(
          context,
          label: title,
          width: 440,
          builder: panel,
        );
}

class PairAskPanel extends StatefulWidget {
  const PairAskPanel({
    super.key,
    required this.source,
    required this.ask,
    this.phone = false,
    this.now = DateTime.now,
  });

  final MailSource source;
  final PairAsk ask;
  final bool phone;
  final DateTime Function() now;

  @override
  State<PairAskPanel> createState() => _PairAskPanelState();
}

class _PairAskPanelState extends State<PairAskPanel> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  /// Approve, not Not me, is on its way: the button says so.
  bool _approving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _answer(bool approve) async {
    setState(() {
      _busy = true;
      _approving = approve;
      _error = null;
    });
    try {
      if (approve) {
        await widget.source.approveDevice(widget.ask.id, _code.text);
      } else {
        await widget.source.refuseDevice(widget.ask.id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _error = switch (e) {
          SyncFailure(problem: SyncProblem.expired) => l.syncFailExpired,
          _ => l.syncFailOther,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final ask = widget.ask;
    final digits = _code.text;
    final full = digits.length == 6;
    final phone = widget.phone;
    final instant = reduceMotion(context);
    return Padding(
      padding: phone
          ? const EdgeInsets.fromLTRB(20, 8, 20, 4)
          : const EdgeInsets.all(2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.chip,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: PiumaIconView(
                    deviceIcon(ask.kind),
                    size: 22,
                    color: c.muted,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l.syncAskTitle(ask.kind.name),
                        style: PiumaType.body.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.36,
                          color: c.fg,
                        ),
                      ),
                    ),
                    Text(
                      l.syncAskLine(ask.name, syncAgo(l, ask.at, widget.now())),
                      style: PiumaType.body.copyWith(
                        fontSize: 13,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            l.syncAskCode(ask.kind.name),
            style: PiumaType.body.copyWith(color: c.fg),
          ),
          const SizedBox(height: 10),
          // Six boxes over one hidden field, which takes the typing.
          Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _code,
                    focusNode: _focus,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    showCursor: false,
                    enableInteractiveSelection: false,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      labelText: l.syncAskDigits,
                    ),
                    onSubmitted: (_) {
                      if (full && !_busy) _answer(true);
                    },
                  ),
                ),
              ),
              IgnorePointer(
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      for (var i = 0; i < 6; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        AnimatedContainer(
                          duration: instant ? Duration.zero : PiumaMotion.press,
                          curve: PiumaMotion.curve,
                          width: 46,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color:
                                  _focus.hasFocus &&
                                      i == digits.length.clamp(0, 5)
                                  ? c.accent
                                  : c.line,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            i < digits.length ? digits[i] : '',
                            style: TextStyle(
                              fontFamily: PiumaFonts.mono,
                              fontSize: 24,
                              color: c.fg,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_error case final e?) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                e,
                style: PiumaType.body.copyWith(fontSize: 13, color: c.danger),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _NotMe(onTap: _busy ? null : () => _answer(false)),
              const SizedBox(width: 8),
              PiumaButton(
                label: _busy && _approving ? l.syncApproving : l.syncApprove,
                size: phone ? PiumaButtonSize.touch : PiumaButtonSize.standard,
                onPressed: full && !_busy ? () => _answer(true) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Not me": quiet, in the danger color.
class _NotMe extends StatelessWidget {
  const _NotMe({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: l.syncNotMe,
      child: ExcludeSemantics(
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            l.syncNotMe,
            style: PiumaType.body.copyWith(
              fontWeight: FontWeight.w500,
              color: c.danger,
            ),
          ),
        ),
      ),
    );
  }
}
