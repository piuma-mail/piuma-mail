import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// What a message being read asks of its reader, above its text: a pill
/// when the sender marked it high priority, and a band when they asked to
/// be told it was read. No receipt ever goes on its own: the band asks,
/// and "Never for this sender" stops it asking about that sender again.
class MessageAsksBar extends StatefulWidget {
  const MessageAsksBar({
    super.key,
    required this.source,
    required this.row,
    required this.phone,
  });

  final MailSource source;
  final MailRow row;
  final bool phone;

  @override
  State<MessageAsksBar> createState() => _MessageAsksBarState();
}

class _MessageAsksBarState extends State<MessageAsksBar> {
  MessageAsks _asks = const MessageAsks();

  /// The band was answered: it goes.
  bool _answered = false;

  /// What the band says once answered, for a moment: sent, or failed.
  String? _result;

  @override
  void initState() {
    super.initState();
    widget.source.messageAsks(widget.row).then((a) {
      if (mounted) setState(() => _asks = a);
    }, onError: (Object _) {});
  }

  Future<void> _answer({required bool send, bool never = false}) async {
    final l = AppLocalizations.of(context);
    setState(() => _answered = true);
    try {
      await widget.source.answerReadReceipt(
        widget.row,
        send: send,
        never: never,
      );
      if (mounted && send) setState(() => _result = l.readReceiptSent);
    } catch (_) {
      if (mounted) {
        setState(() {
          _answered = false;
          _result = l.readReceiptFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final phone = widget.phone;
    final ask = !_answered && _asks.readReceiptTo != null;
    final children = <Widget>[
      if (_asks.highPriority)
        Padding(
          padding: EdgeInsets.only(top: phone ? 12 : 14),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: HighPriorityPill(label: l.highPriority),
          ),
        ),
      if (ask)
        Padding(
          padding: EdgeInsets.only(top: phone ? 12 : 14),
          child: ReadReceiptBand(
            sender: widget.row.sender,
            phone: phone,
            error: _result,
            onSend: () => _answer(send: true),
            onDecline: () => _answer(send: false),
            onNever: () => _answer(send: false, never: true),
          ),
        )
      else if (_result case final result?)
        Padding(
          padding: EdgeInsets.only(top: phone ? 12 : 14),
          child: Semantics(
            liveRegion: true,
            child: Text(
              result,
              style: PiumaType.small.copyWith(
                color: PiumaTheme.of(context).muted,
              ),
            ),
          ),
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// The small pill of a message its sender marked important, shaped as
/// the Verified pill, in the warning tint.
class HighPriorityPill extends StatelessWidget {
  const HighPriorityPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          height: 20,
          padding: const EdgeInsets.fromLTRB(6, 0, 8, 0),
          decoration: BoxDecoration(
            color: c.warnSoft,
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(PiumaIcon.bolt, size: 11, color: c.warn),
              const SizedBox(width: PiumaSpace.s4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: c.warn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "The sender asked to be told you read this": Send, Don't send, Never
/// for this sender. Laid out as the sender warning band, in the quiet
/// tint, since nothing is wrong.
class ReadReceiptBand extends StatelessWidget {
  const ReadReceiptBand({
    super.key,
    required this.sender,
    required this.phone,
    required this.onSend,
    required this.onDecline,
    required this.onNever,
    this.error,
  });

  final String sender;
  final bool phone;
  final VoidCallback onSend;
  final VoidCallback onDecline;
  final VoidCallback onNever;

  /// Why the last try failed, under the line.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final line = Text(
      l.readReceiptAsk(sender),
      style: TextStyle(
        fontFamily: PiumaFonts.sans,
        fontSize: phone ? 14 : 13.5,
        height: 1.5,
        color: c.fg,
      ),
    );
    final actions = Wrap(
      spacing: 18,
      runSpacing: PiumaSpace.s4,
      children: [
        _Action(label: l.readReceiptSend, phone: phone, onTap: onSend),
        _Action(label: l.readReceiptDontSend, phone: phone, onTap: onDecline),
        _Action(
          label: l.readReceiptNever,
          phone: phone,
          muted: true,
          onTap: onNever,
        ),
      ],
    );
    final sign = Padding(
      padding: EdgeInsets.only(top: phone ? 2 : 1),
      child: PiumaIconView(PiumaIcon.mailOpen, size: 16, color: c.muted),
    );
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(
            phone ? PiumaRadius.card : PiumaRadius.row,
          ),
          border: Border.all(color: c.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sign,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line,
                  if (error case final e?)
                    Text(
                      e,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 13,
                        height: 1.5,
                        color: c.danger,
                      ),
                    ),
                  const SizedBox(height: PiumaSpace.s4),
                  actions,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.phone,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final bool phone;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: phone ? 6 : 2),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: phone ? 13.5 : 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: muted ? c.muted : c.accentText,
            ),
          ),
        ),
      ),
    );
  }
}
