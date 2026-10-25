import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import 'rich_body.dart';

final _address = RegExp(r'^(https?://|mailto:)\S+$', caseSensitive: false);

/// Compose's formatting, as `FormattingToApprove` draws it: Bold, Italic
/// and Link, then the two lists and Quote. On the desktop a pill over the
/// selected words; on the phone the row above the keyboard. While
/// [linking] it is one field for the link's address.
class FormatBar extends StatefulWidget {
  const FormatBar({
    super.key,
    required this.body,
    required this.phone,
    required this.linking,
    required this.onLinking,
  });

  final RichBodyController body;
  final bool phone;
  final bool linking;
  final ValueChanged<bool> onLinking;

  @override
  State<FormatBar> createState() => _FormatBarState();
}

class _FormatBarState extends State<FormatBar> {
  final _url = TextEditingController();

  @override
  void didUpdateWidget(FormatBar old) {
    super.didUpdateWidget(old);
    if (widget.linking && !old.linking) _startLink();
  }

  @override
  void initState() {
    super.initState();
    if (widget.linking) _startLink();
  }

  /// The field starts with the link already there, or an address on the
  /// clipboard.
  Future<void> _startLink() async {
    _url.text = widget.body.linkAt() ?? '';
    if (_url.text.isNotEmpty) return;
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim() ?? '';
    if (mounted && _url.text.isEmpty && _address.hasMatch(text)) {
      _url.text = text;
      _url.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    }
  }

  void _addLink() {
    widget.body.link(_url.text);
    widget.onLinking(false);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final phone = widget.phone;
    final Widget row = ListenableBuilder(
      listenable: widget.body,
      builder: (context, _) {
        if (widget.linking) return _linkField(c, l);
        final body = widget.body;
        final block = body.blockHere();
        Widget button(
          PiumaIcon icon,
          String label,
          bool on,
          VoidCallback tap,
        ) => _FormatButton(
          icon: icon,
          label: label,
          on: on,
          size: phone ? 44 : 32,
          onTap: tap,
        );
        final buttons = [
          button(
            PiumaIcon.bold,
            l.formatBold,
            body.isOn(BodyMarkKind.bold),
            () => body.toggle(BodyMarkKind.bold),
          ),
          button(
            PiumaIcon.italic,
            l.formatItalic,
            body.isOn(BodyMarkKind.italic),
            () => body.toggle(BodyMarkKind.italic),
          ),
          button(
            PiumaIcon.link,
            l.formatLink,
            body.linkAt() != null,
            () => widget.onLinking(true),
          ),
          if (!phone)
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: PiumaSpace.s4),
              color: c.line,
            ),
          button(
            PiumaIcon.listBullet,
            l.formatBullets,
            block == LineBlock.bullets,
            () => body.toggleBlock(LineBlock.bullets),
          ),
          button(
            PiumaIcon.listNumber,
            l.formatNumbers,
            block == LineBlock.numbers,
            () => body.toggleBlock(LineBlock.numbers),
          ),
          button(
            PiumaIcon.quote,
            l.formatQuote,
            block == LineBlock.quote,
            () => body.toggleBlock(LineBlock.quote),
          ),
        ];
        return Row(
          mainAxisSize: phone ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: phone
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.start,
          children: buttons,
        );
      },
    );
    // Taps on the bar count as taps in the text, which keeps its focus and
    // its selection.
    final bar = TextFieldTapRegion(
      child: Semantics(container: true, label: l.formatting, child: row),
    );
    if (phone) return bar;
    return Container(
      padding: const EdgeInsets.all(PiumaSpace.s4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PiumaRadius.row),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            offset: const Offset(0, 6),
            blurRadius: 22,
            spreadRadius: -6,
          ),
        ],
      ),
      child: bar,
    );
  }

  Widget _linkField(PiumaColors c, AppLocalizations l) {
    final field = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: PiumaSpace.s8),
        PiumaIconView(PiumaIcon.link, size: 16, color: c.muted),
        const SizedBox(width: PiumaSpace.s8),
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  widget.onLinking(false),
            },
            child: TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addLink(),
              style: PiumaType.body.copyWith(
                fontSize: 13.5,
                color: c.fg,
                fontFamily: PiumaFonts.sans,
              ),
              cursorColor: c.accent,
              decoration: InputDecoration.collapsed(
                hintText: l.linkAddressHint,
                hintStyle: PiumaType.body.copyWith(
                  fontSize: 13.5,
                  color: c.muted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: PiumaSpace.s8),
        if (widget.body.linkAt() != null && _url.text.isEmpty)
          _TextButton(label: l.linkRemove, onTap: _addLink)
        else
          _TextButton(label: l.linkAdd, onTap: _addLink, primary: true),
      ],
    );
    return SizedBox(
      width: widget.phone ? double.infinity : 360,
      height: widget.phone ? 44 : 32,
      child: ListenableBuilder(listenable: _url, builder: (_, _) => field),
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.icon,
    required this.label,
    required this.on,
    required this.size,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;
  final bool on;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Tooltip(
      message: label,
      child: Semantics(
        selected: on,
        child: PiumaPressable(
          onTap: onTap,
          semanticLabel: label,
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.soft : c.soft.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(
                size > 40 ? PiumaRadius.row : PiumaRadius.field,
              ),
            ),
            child: PiumaIconView(
              icon,
              size: size > 40 ? 20 : 16,
              color: on ? c.accentText : c.fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({
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
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: PiumaSpace.s12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? c.accent : null,
          borderRadius: BorderRadius.circular(PiumaRadius.field),
        ),
        child: Text(
          label,
          style: PiumaType.small.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: primary ? c.onAccent : c.accentText,
          ),
        ),
      ),
    );
  }
}

/// The desktop pill coming in: it grows a little out of the selection on
/// the quick spring while it fades in.
class FormatBarEnter extends StatelessWidget {
  const FormatBarEnter({super.key, required this.child, this.below = false});

  final Widget child;

  /// It sits under the selection, so it grows from its top.
  final bool below;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: PiumaMotion.fast,
      child: child,
      builder: (context, v, child) {
        final fadeAt =
            PiumaMotion.press.inMicroseconds / PiumaMotion.fast.inMicroseconds;
        return Opacity(
          opacity: PiumaMotion.curve.transform((v / fadeAt).clamp(0, 1)),
          child: Transform.scale(
            scale: .92 + .08 * PiumaSprings.fast.transform(v),
            alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    );
  }
}
