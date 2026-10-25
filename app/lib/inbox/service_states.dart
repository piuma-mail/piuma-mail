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
import '../widgets/progress.dart';
import '../widgets/text_field.dart';
import 'snooze.dart';

/// The strip at the very top of `StatesOffline`: the servers can't be
/// reached, and the engine keeps retrying on its own.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.phone = true});

  /// The phone's strip runs edge to edge; the desktop's sits in the list.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        color: c.chip,
        padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 22, vertical: 7),
        child: Row(
          children: [
            PiumaIconView(PiumaIcon.wifiOff, size: 15, color: c.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: l.offlineTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.fg,
                      ),
                    ),
                    TextSpan(text: ' · ${l.offlineDetail}'),
                  ],
                ),
                style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Downloading Work · 2,340 of 8,100" with a thin bar, under the title
/// while an account downloads for the first time (`StatesSync`).
class SyncProgress extends StatefulWidget {
  const SyncProgress({
    super.key,
    required this.account,
    required this.done,
    required this.total,
    this.now = DateTime.now,
  });

  final MailAccount account;
  final int done;
  final int total;

  /// The clock the time left is reckoned by.
  final DateTime Function() now;

  @override
  State<SyncProgress> createState() => _SyncProgressState();
}

class _SyncProgressState extends State<SyncProgress> {
  /// When this download was first seen, and how far along it was then.
  late var _since = (widget.now(), widget.done);

  @override
  void didUpdateWidget(SyncProgress old) {
    super.didUpdateWidget(old);
    // Another account, or a fresh start: reckon from here.
    if (widget.account.id != old.account.id || widget.done < old.done) {
      _since = (widget.now(), widget.done);
    }
  }

  /// "about 3 min" from the pace so far; null until there is a pace.
  String? _timeLeft(AppLocalizations l) {
    final (at, from) = _since;
    final spent = widget.now().difference(at);
    final got = widget.done - from;
    if (spent < const Duration(seconds: 5) || got <= 0) return null;
    final left = Duration(
      microseconds: (spent.inMicroseconds * (widget.total - widget.done) / got)
          .round(),
    );
    if (left < const Duration(minutes: 1)) return l.syncLeftUnderMinute;
    if (left < const Duration(minutes: 90)) {
      return l.syncLeftMinutes((left.inSeconds / 60).round());
    }
    return l.syncLeftHours((left.inMinutes / 60).round());
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final account = widget.account;
    final done = widget.done;
    final total = widget.total;
    final left = _timeLeft(l);
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final mono = TextStyle(
      fontFamily: PiumaFonts.mono,
      fontSize: 12,
      color: c.fg,
    );
    final part = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Semantics(
      label: l.downloadingAccount(account.name),
      value: [
        l.downloadingCount(number.format(done), number.format(total)),
        ?left,
      ].join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: account.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${l.downloadingAccount(account.name)} · ',
                        ),
                        TextSpan(text: number.format(done), style: mono),
                        TextSpan(text: ' ${l.countOf} '),
                        TextSpan(
                          text: number.format(total),
                          style: mono.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
                if (left != null)
                  Text(left, style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
            const SizedBox(height: 6),
            PiumaProgress(value: part, track: c.line),
          ],
        ),
      ),
    );
  }
}

/// The card of `StatesError`: an account whose password stopped working,
/// with "Sign in again" and "Later".
class SignInCard extends StatelessWidget {
  const SignInCard({
    super.key,
    required this.account,
    required this.onSignIn,
    required this.onLater,
  });

  final MailAccount account;
  final VoidCallback onSignIn;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.warnSoft,
          border: Border.all(color: c.warnLine),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(PiumaRadius.button),
                  ),
                  alignment: Alignment.center,
                  child: PiumaIconView(
                    PiumaIcon.lockOpen,
                    size: 18,
                    color: c.warn,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                          Expanded(
                            child: Text(
                              l.accountCantConnect(account.name),
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: c.fg,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        l.passwordChanged(account.email),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PiumaPressable(
                    onTap: onSignIn,
                    semanticLabel: l.signInAgain,
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.fg,
                        borderRadius: BorderRadius.circular(PiumaRadius.row),
                      ),
                      child: ExcludeSemantics(
                        child: Text(
                          l.signInAgain,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.surface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PiumaPressable(
                  onTap: onLater,
                  semanticLabel: l.later,
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        widthFactor: 1,
                        child: ExcludeSemantics(
                          child: Text(
                            l.later,
                            style: TextStyle(fontSize: 14, color: c.muted),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty inbox of `States`: a sun over the horizon, "All caught up",
/// and when mail is snoozed, "Show Snoozed (2)" opening the list of what
/// comes back and when.
class AllCaughtUp extends StatefulWidget {
  const AllCaughtUp({
    super.key,
    this.snoozed = const [],
    this.accountOf,
    this.now,
    this.onOpen,
  });

  final List<MailRow> snoozed;
  final MailAccount? Function(int id)? accountOf;
  final DateTime Function()? now;
  final ValueChanged<MailRow>? onOpen;

  @override
  State<AllCaughtUp> createState() => _AllCaughtUpState();
}

class _AllCaughtUpState extends State<AllCaughtUp> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final snoozed = widget.snoozed;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 34, 32, 110),
      child: Column(
        children: [
          SizedBox(
            width: 200,
            height: 132,
            child: CustomPaint(painter: _Horizon(c)),
          ),
          const SizedBox(height: 22),
          Text(
            l.allCaughtUp,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              l.allCaughtUpDetail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.45, color: c.muted),
            ),
          ),
          if (snoozed.isNotEmpty) ...[
            const SizedBox(height: 14),
            Semantics(
              expanded: _open,
              child: PiumaPressable(
                onTap: () => setState(() => _open = !_open),
                semanticLabel: _open
                    ? l.hideSnoozed
                    : l.showSnoozed(snoozed.length),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      widthFactor: 1,
                      child: ExcludeSemantics(
                        child: Text(
                          _open ? l.hideSnoozed : l.showSnoozed(snoozed.length),
                          style: PiumaType.body.copyWith(
                            fontWeight: FontWeight.w500,
                            color: c.accentText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_open)
              PiumaEnter(
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(PiumaRadius.card),
                  ),
                  child: Column(
                    children: [
                      for (final (i, row) in snoozed.indexed)
                        _SnoozedLine(
                          row: row,
                          color: widget.accountOf?.call(row.accountId)?.color,
                          now: widget.now?.call() ?? DateTime.now(),
                          last: i == snoozed.length - 1,
                          onTap: widget.onOpen == null
                              ? null
                              : () => widget.onOpen!(row),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One snoozed message under "All caught up": its account's dot, the
/// subject over the sender, and when it comes back.
class _SnoozedLine extends StatelessWidget {
  const _SnoozedLine({
    required this.row,
    required this.color,
    required this.now,
    required this.last,
    this.onTap,
  });

  final MailRow row;
  final Color? color;
  final DateTime now;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final when = snoozedRowTime(row.snoozedUntil, now, l, locale);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: '${row.subject}, ${row.sender}, $when',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color ?? c.muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.body.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: c.fg,
                      ),
                    ),
                    Text(
                      row.sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.small.copyWith(
                        height: 1.3,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PiumaIconView(PiumaIcon.clock, size: 13, color: c.muted),
              const SizedBox(width: 4),
              Text(
                when,
                style: PiumaType.small.copyWith(fontSize: 12, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Horizon extends CustomPainter {
  _Horizon(this.c);
  final PiumaColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(const Offset(100, 70), 56, Paint()..color = c.soft);
    canvas.drawCircle(const Offset(130, 48), 11, Paint()..color = c.accent);
    final line = Paint()..color = c.line;
    canvas.drawRRect(
      RRect.fromLTRBR(28, 104, 172, 106, const Radius.circular(1)),
      line,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(62, 116, 138, 118, const Radius.circular(1)),
      line,
    );
  }

  @override
  bool shouldRepaint(_Horizon old) => old.c != c;
}

/// Asks for the new password of an account whose sign-in failed: a sheet
/// from the bottom on the phone, a centered panel on desktop.
Future<void> showSignInAgain(
  BuildContext context, {
  required MailSource source,
  required MailAccount account,
  required bool phone,
}) {
  final l = AppLocalizations.of(context);
  final label = l.signInTo(account.name);
  // Material, for the text field inside the dialog route.
  Widget form(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: _SignInForm(source: source, account: account, phone: phone),
  );
  return phone
      ? showPiumaSheet<void>(context, label: label, builder: form)
      : showPiumaDialog<void>(context, label: label, builder: form);
}

class _SignInForm extends StatefulWidget {
  const _SignInForm({
    required this.source,
    required this.account,
    required this.phone,
  });

  final MailSource source;
  final MailAccount account;
  final bool phone;

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _password = TextEditingController();
  bool _show = false;
  bool _busy = false;
  AddAccountError? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.source.signInAgain(widget.account.id, _password.text);
      if (mounted) Navigator.of(context).pop();
    } on AddAccountException catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final a = widget.account;
    final side = widget.phone ? 24.0 : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        side,
        widget.phone ? 14 : 0,
        side,
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: a.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  a.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.signInTo(a.name),
            style: TextStyle(
              fontSize: 24,
              height: 1.15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 18),
          PiumaTextField(
            label: l.password,
            controller: _password,
            obscure: !_show,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            trailing: PiumaButton(
              label: _show ? l.hide : l.show,
              kind: PiumaButtonKind.tertiary,
              size: PiumaButtonSize.compact,
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            PiumaEnter(
              child: Text(switch (_error!) {
                AddAccountError.wrongPassword => l.errorWrongPassword,
                AddAccountError.unreachable => l.errorUnreachable,
                AddAccountError.insecure => l.errorInsecure,
                AddAccountError.keychain => l.errorKeychain,
                AddAccountError.other => l.errorOther,
              }, style: TextStyle(fontSize: 14, color: c.danger)),
            ),
          ],
          const SizedBox(height: 20),
          ListenableBuilder(
            listenable: _password,
            builder: (context, _) => PiumaButton(
              label: _busy ? l.signingIn : l.signIn,
              size: widget.phone
                  ? PiumaButtonSize.large
                  : PiumaButtonSize.touch,
              onPressed: _password.text.isNotEmpty && !_busy ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}
