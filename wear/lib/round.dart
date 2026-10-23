import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'design/icons.dart';
import 'design/motion.dart';
import 'design/tokens.g.dart';
import 'link.dart';

/// The watch is always dark; screens sit on [PiumaColors.darkroom], the
/// near-black the OLED shows as almost off.
const watchColors = PiumaColors.dark;

/// A round screen's list: the crown or bezel scrolls it on the spatial
/// spring, and rows shrink and fade as they reach the curve (`WatchWearOS` 2).
class RoundScroll extends StatefulWidget {
  const RoundScroll({super.key, required this.children, this.bottom = 0});

  final List<Widget> children;

  /// Room left free at the bottom, for an edge button.
  final double bottom;

  @override
  State<RoundScroll> createState() => _RoundScrollState();
}

class _RoundScrollState extends State<RoundScroll> {
  final _controller = ScrollController();
  StreamSubscription<double>? _rotary;
  double _target = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rotary?.cancel();
    _rotary = LinkScope.of(context).rotary.listen(_turned);
  }

  void _turned(double delta) {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    // Turns that come quickly add up to one move.
    final from = _controller.position.isScrollingNotifier.value
        ? _target
        : p.pixels;
    _target = (from + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (reduceMotion(context)) {
      _controller.jumpTo(_target);
    } else {
      _controller.animateTo(
        _target,
        duration: PiumaMotion.fast,
        curve: PiumaSprings.fast,
      );
    }
  }

  @override
  void dispose() {
    _rotary?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return ListView(
      controller: _controller,
      padding: EdgeInsets.fromLTRB(
        h * .1,
        h * .16,
        h * .1,
        h * .2 + widget.bottom,
      ),
      children: [for (final c in widget.children) EdgeScale(child: c)],
    );
  }
}

/// Shrinks and fades [child] as it nears the top or bottom of a round
/// screen, as Wear OS lists do.
class EdgeScale extends StatefulWidget {
  const EdgeScale({super.key, required this.child});

  final Widget child;

  @override
  State<EdgeScale> createState() => _EdgeScaleState();
}

class _EdgeScaleState extends State<EdgeScale> {
  ScrollPosition? _position;
  double _factor = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_measure);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_measure);
    SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final h = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    // How far past the middle 70% the row reaches, 0 to 1.
    final edge = h * .15;
    final over = [
      (edge - top) / edge,
      (bottom - (h - edge)) / edge,
    ].reduce((a, b) => a > b ? a : b).clamp(0.0, 1.0);
    if ((over - (1 - _factor)).abs() > .01) {
      setState(() => _factor = 1 - over);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_measure);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: .4 + .6 * _factor,
    child: Transform.scale(scale: .86 + .14 * _factor, child: widget.child),
  );
}

/// A button that hugs the bottom curve of the screen (Wear Material 3
/// Expressive's edge button): the main action of a screen.
class EdgeButton extends StatelessWidget {
  const EdgeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.width = 150,
  });

  final String label;
  final PiumaIcon? icon;
  final VoidCallback onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    const c = watchColors;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: c.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(22),
                topRight: const Radius.circular(22),
                bottomLeft: Radius.elliptical(width / 2, 40),
                bottomRight: Radius.elliptical(width / 2, 40),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: width,
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.only(top: 13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null) ...[
                        PiumaIconView(icon!, size: 16, color: c.onAccent),
                        const SizedBox(width: 7),
                      ],
                      ExcludeSemantics(
                        child: Text(
                          label,
                          style: PiumaType.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: c.onAccent,
                            height: 1.2,
                          ),
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
    );
  }
}

/// A full-width pill: a choice in a list, or a secondary action.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailing,
    this.center = false,
  });

  final String label;
  final PiumaIcon? icon;
  final String? trailing;
  final bool center;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const c = watchColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: c.surface,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            PiumaOrigin.from(context);
            onPressed();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: center
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  PiumaIconView(icon!, size: 16, color: c.fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  fit: center ? FlexFit.loose : FlexFit.tight,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: center ? TextAlign.center : TextAlign.start,
                    style: PiumaType.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    trailing!,
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
    );
  }
}

/// A round icon button, 44 across or more.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
    this.accent = false,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback onPressed;
  final double size;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    const c = watchColors;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: accent ? c.accent : c.chip,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            PiumaOrigin.from(context);
            onPressed();
          },
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: PiumaIconView(
                icon,
                size: size * .42,
                color: accent ? c.onAccent : c.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The account's dot, as in the phone's lists.
class AccountDot extends StatelessWidget {
  const AccountDot(this.color, {super.key, this.size = 7});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
