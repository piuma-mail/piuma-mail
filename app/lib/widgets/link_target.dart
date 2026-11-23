import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SnackBar, SnackBarBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import 'button.dart';
import 'dialog.dart';
import 'links.dart';

/// Where the link under the pointer really goes, on a line at the bottom
/// of the reader, as a browser's status line: for every link of an email,
/// in the clean view and in the original layout, so its text can't hide
/// its address. Only a mouse hovers, so phones never show it.
class LinkTarget extends StatefulWidget {
  const LinkTarget({super.key, required this.child});

  final Widget child;

  /// The link under the pointer now, or null when it left.
  static void show(BuildContext context, String? url) {
    final scope = context
        .getInheritedWidgetOfExactType<_LinkTargetScope>()
        ?.url;
    if (scope == null || scope.value == url) return;
    scope.value = url;
  }

  /// Hides [url] after this frame, if it is still the one shown: for a
  /// link that goes away mid-build (another message opened under the
  /// pointer), when the line can't change until the build is done.
  static void hideLater(BuildContext context, String url) {
    final scope = context
        .getInheritedWidgetOfExactType<_LinkTargetScope>()
        ?.url;
    if (scope == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (scope.value == url) scope.value = null;
      } on FlutterError {
        // Disposed with its screen: nothing left to hide.
      }
    });
  }

  @override
  State<LinkTarget> createState() => _LinkTargetState();
}

class _LinkTargetState extends State<LinkTarget> {
  final _url = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LinkTargetScope(
    url: _url,
    child: Stack(
      children: [
        widget.child,
        Positioned(
          left: PiumaSpace.s8,
          right: PiumaSpace.s8,
          bottom: PiumaSpace.s8,
          child: ValueListenableBuilder<String?>(
            valueListenable: _url,
            builder: (context, url, _) => url == null || url.isEmpty
                ? const SizedBox.shrink()
                : Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: LinkTargetLine(url: url),
                  ),
          ),
        ),
      ],
    ),
  );
}

class _LinkTargetScope extends InheritedWidget {
  const _LinkTargetScope({required this.url, required super.child});

  final ValueNotifier<String?> url;

  @override
  bool updateShouldNotify(_LinkTargetScope old) => url != old.url;
}

/// The address itself, small and quiet, never in the way of the pointer.
class LinkTargetLine extends StatelessWidget {
  const LinkTargetLine({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(
            horizontal: PiumaSpace.s8,
            vertical: PiumaSpace.s4,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.field),
            border: Border.all(color: c.line),
          ),
          child: _LinkTargetText(url: url, size: 12, oneLine: true),
        ),
      ),
    );
  }
}

/// A link's target, so its host is always seen: the host first, never
/// cut, its registrable domain in the text's strong color, the ASCII
/// (punycode) form of a host that has other letters, then the rest of the
/// address cut in the middle, not at the end.
class _LinkTargetText extends StatelessWidget {
  const _LinkTargetText({
    required this.url,
    required this.size,
    required this.oneLine,
  });

  final String url;
  final double size;
  final bool oneLine;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final parts = describeLink(url);
    final quiet = PiumaType.mono.copyWith(color: c.muted, fontSize: size);
    if (parts == null) {
      return Text(
        elideMiddle(url, oneLine ? _oneLineChars : 240),
        maxLines: oneLine ? 1 : 6,
        style: quiet,
      );
    }
    final strong = quiet.copyWith(color: c.fg, fontWeight: FontWeight.w600);
    final sub = parts.host.endsWith(parts.registrable)
        ? parts.host.substring(0, parts.host.length - parts.registrable.length)
        : '';
    // The host is never cut away: only a long run of labels in front of
    // its registrable part is cut (in the middle), and on one line the
    // rest of the address gets what room the host leaves.
    final shownSub = elideMiddle(sub, oneLine ? 28 : 64);
    final hostSpans = [
      TextSpan(
        text: shownSub,
        style: quiet.copyWith(color: c.fg),
      ),
      TextSpan(
        text: sub.isEmpty ? parts.host : parts.registrable,
        style: strong,
      ),
      if (parts.ascii case final ascii?)
        TextSpan(text: '  $ascii', style: quiet),
    ];
    if (oneLine) {
      final hostLength = hostSpans.fold<int>(
        0,
        (n, span) => n + span.text!.runes.length,
      );
      final room = (_oneLineChars - hostLength).clamp(16, _oneLineChars);
      // One paragraph, so a host longer than the line wraps rather than
      // being clipped.
      return Text.rich(
        TextSpan(
          children: [
            ...hostSpans,
            if (parts.rest.isNotEmpty)
              TextSpan(text: elideMiddle(parts.rest, room), style: quiet),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(TextSpan(children: hostSpans)),
        if (parts.rest.isNotEmpty) ...[
          const SizedBox(height: PiumaSpace.s4),
          Text(
            elideMiddle(parts.rest, 240),
            maxLines: 6,
            overflow: TextOverflow.clip,
            style: quiet,
          ),
        ],
      ],
    );
  }
}

/// How many characters the status line holds (its width at the mono
/// size it uses).
const _oneLineChars = 72;

/// Where a link goes, for a touch screen, which has no hover: a long press
/// on a link shows its real address, to open or copy (and does the same
/// with a mouse held down, or a right click in the original layout).
/// [onOpen] opens it the way a tap would, checks included.
Future<void> showLinkTarget(
  BuildContext context,
  String url, {
  required VoidCallback onOpen,
}) async {
  final l = AppLocalizations.of(context);
  final phone = MediaQuery.sizeOf(context).width < 600;
  Widget panel(BuildContext context) =>
      _LinkTargetPanel(url: url, phone: phone);
  final open = phone
      ? await showPiumaSheet<_LinkChoice>(
          context,
          label: l.linkTargetTitle,
          builder: panel,
        )
      : await showPiumaDialog<_LinkChoice>(
          context,
          label: l.linkTargetTitle,
          builder: panel,
        );
  if (!context.mounted) return;
  switch (open) {
    case _LinkChoice.open:
      onOpen();
    case _LinkChoice.copy:
      await Clipboard.setData(ClipboardData(text: url));
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l.linkCopied),
            behavior: SnackBarBehavior.floating,
            width: phone ? null : 360,
            persist: false,
          ),
        );
    case null:
      return;
  }
}

enum _LinkChoice { open, copy }

class _LinkTargetPanel extends StatelessWidget {
  const _LinkTargetPanel({required this.url, required this.phone});

  final String url;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final size = phone ? PiumaButtonSize.touch : PiumaButtonSize.standard;
    return Padding(
      padding: phone
          ? const EdgeInsets.fromLTRB(20, 8, 20, 0)
          : EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.linkTargetTitle,
            style: PiumaType.subtitle.copyWith(color: c.fg),
          ),
          const SizedBox(height: PiumaSpace.s12),
          Container(
            padding: const EdgeInsets.all(PiumaSpace.s12),
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(PiumaRadius.field),
            ),
            child: _LinkTargetText(url: url, size: 13, oneLine: false),
          ),
          const SizedBox(height: PiumaSpace.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PiumaButton(
                label: l.linkCopy,
                kind: PiumaButtonKind.secondary,
                size: size,
                onPressed: () => Navigator.of(context).pop(_LinkChoice.copy),
              ),
              const SizedBox(width: PiumaSpace.s8),
              PiumaButton(
                label: l.linkOpen,
                size: size,
                onPressed: () => Navigator.of(context).pop(_LinkChoice.open),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One gesture for a link inside text: a tap opens it, a long press shows
/// where it goes ([showLinkTarget]). A text span takes one recognizer, so
/// this long-press recognizer also reports a tap: a press let go before
/// the long press, that didn't move away.
class LinkPressRecognizer extends LongPressGestureRecognizer {
  LinkPressRecognizer({super.debugOwner});

  /// A short press.
  VoidCallback? onTapLink;

  bool _long = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _long = false;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _long = true;
    super.acceptGesture(pointer);
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    final tap = event is PointerUpEvent && !_long;
    super.handlePrimaryPointer(event);
    if (tap) onTapLink?.call();
  }
}
