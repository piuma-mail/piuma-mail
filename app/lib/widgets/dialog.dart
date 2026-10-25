import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// A centered panel over the scrim. It enters like everything else (a
/// 4px rise out of a light blur) and is instant with reduce motion. Esc
/// and a tap on the scrim close it. With [from], the box just tapped (in
/// global coordinates), it grows out of it on the spatial spring instead
/// (style 8).
Future<T?> showPiumaDialog<T>(
  BuildContext context, {
  required String label,
  required WidgetBuilder builder,
  double width = 420,
  Rect? from,
}) {
  final c = PiumaTheme.of(context);
  final instant = reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: c.scrim,
    transitionDuration: instant
        ? Duration.zero
        : from != null
        ? PiumaMotion.spatial
        : PiumaMotion.enter,
    pageBuilder: (context, _, _) => Center(
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: label,
        child: Container(
          width: width,
          margin: const EdgeInsets.all(PiumaSpace.s24),
          padding: const EdgeInsets.all(PiumaSpace.s24),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.panel),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                offset: const Offset(0, 18),
                blurRadius: 50,
                spreadRadius: -24,
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: PiumaType.body.copyWith(color: c.fg),
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      if (from != null) {
        // The fade is over in the press time; the size settles on the
        // spring, which may pass 1 a touch.
        final v = animation.value;
        final fadeAt =
            PiumaMotion.press.inMicroseconds /
            PiumaMotion.spatial.inMicroseconds;
        final fade = PiumaMotion.curve.transform((v / fadeAt).clamp(0, 1));
        final spring = PiumaSprings.spatial.transform(v);
        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: PiumaMotion.backScale + (1 - PiumaMotion.backScale) * spring,
            alignment: Alignment.topLeft,
            origin: from.center,
            child: child,
          ),
        );
      }
      final t = PiumaMotion.curve.transform(animation.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, PiumaMotion.enterRisePx * (1 - t)),
          child: child,
        ),
      );
    },
  );
}

/// A panel that rises from the bottom edge over the scrim, as phone sheets
/// do on the canvas (`SettingsEntryPhone`). Same curve and timing as
/// [showPiumaDialog]; a tap on the scrim or Back closes it.
Future<T?> showPiumaSheet<T>(
  BuildContext context, {
  required String label,
  required WidgetBuilder builder,
}) {
  final c = PiumaTheme.of(context);
  final instant = reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: c.scrim,
    transitionDuration: instant ? Duration.zero : PiumaMotion.enter,
    // Above the keyboard, so a sheet with a field (the templates) stays
    // in sight while typing.
    pageBuilder: (context, _, _) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          namesRoute: true,
          label: label,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: 10,
              bottom: PiumaSpace.s16 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: DefaultTextStyle(
              style: PiumaType.body.copyWith(color: c.fg),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final t = PiumaMotion.curve.transform(animation.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      );
    },
  );
}

/// A small panel under [anchor] (in global coordinates), as menus are on
/// the canvas (`AccountFolders`): no scrim, a tap outside or Esc closes
/// it. It stays inside the window. With [grow] it grows out of [anchor],
/// its button, on the fast spring (style 8) instead of rising. With [end]
/// its right edge lines up with the anchor's, for a button at the end of
/// a bar.
Future<T?> showPiumaPopover<T>(
  BuildContext context, {
  required String label,
  required Rect anchor,
  required WidgetBuilder builder,
  double width = 300,
  bool grow = false,
  bool end = false,
}) {
  final c = PiumaTheme.of(context);
  final instant = reduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: const Color(0x00000000),
    transitionDuration: instant
        ? Duration.zero
        : grow
        ? PiumaMotion.fast
        : PiumaMotion.press,
    pageBuilder: (context, _, _) {
      final size = MediaQuery.sizeOf(context);
      return CustomSingleChildLayout(
        delegate: _PopoverLayout(anchor: anchor, width: width, end: end),
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          namesRoute: true,
          label: label,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.height - 32),
            child: Container(
              padding: const EdgeInsets.all(PiumaSpace.s8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line),
                boxShadow: [
                  BoxShadow(
                    color: c.shadow,
                    offset: const Offset(0, 12),
                    blurRadius: 32,
                    spreadRadius: -12,
                  ),
                ],
              ),
              child: DefaultTextStyle(
                style: PiumaType.body.copyWith(color: c.fg),
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      if (grow) {
        // The fade is over in the press time; the size settles on the
        // spring, which may pass 1 a touch.
        final v = animation.value;
        final fadeAt =
            PiumaMotion.press.inMicroseconds / PiumaMotion.fast.inMicroseconds;
        final fade = PiumaMotion.curve.transform((v / fadeAt).clamp(0, 1));
        final spring = PiumaSprings.fast.transform(v);
        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: PiumaMotion.backScale + (1 - PiumaMotion.backScale) * spring,
            alignment: Alignment.topLeft,
            origin: anchor.center,
            child: child,
          ),
        );
      }
      final t = PiumaMotion.curve.transform(animation.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, PiumaMotion.enterRisePx * (1 - t)),
          child: child,
        ),
      );
    },
  );
}

/// Puts a popover under its anchor, or over it when there is no room
/// below, always inside the window.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout({
    required this.anchor,
    required this.width,
    this.end = false,
  });

  final Rect anchor;
  final double width;
  final bool end;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: width)
          .copyWith(maxHeight: constraints.maxHeight - 32);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final left = (end ? anchor.right - child.width : anchor.left).clamp(
      8.0,
      size.width - child.width - 8,
    );
    final below = anchor.bottom + 6;
    final above = anchor.top - 6 - child.height;
    final top = below + child.height <= size.height - 16 || above < 16
        ? below.clamp(16.0, size.height - child.height - 16)
        : above;
    return Offset(left.toDouble(), top.toDouble());
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.anchor != anchor || old.width != width || old.end != end;
}
