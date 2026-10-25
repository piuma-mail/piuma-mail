import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// How a page looks while Android's back gesture is at [progress] (0–1):
/// a little smaller and shifted toward the swipe, with rounded corners,
/// so what Back returns to shows around it. The same widgets at rest, so
/// the page below keeps its state.
Widget backGestureLook({
  required double progress,
  required SwipeEdge edge,
  required Widget child,
  double opacity = 1,
}) {
  // The whole look by halfway: a back swipe rarely goes much further
  // before it is let go, and less would hardly show.
  progress = (progress * 2).clamp(0.0, 1.0);
  final shift = PiumaMotion.backShiftPx * progress;
  return Opacity(
    opacity: opacity.clamp(0, 1),
    child: Transform.translate(
      offset: Offset(edge == SwipeEdge.left ? shift : -shift, 0),
      child: Transform.scale(
        scale: 1 - (1 - PiumaMotion.backScale) * progress,
        child: ClipRRect(
          clipBehavior: progress == 0 ? Clip.none : Clip.antiAlias,
          borderRadius: BorderRadius.circular(PiumaRadius.panel * progress),
          child: child,
        ),
      ),
    ),
  );
}

/// Phone screens stacked on each other, the top one showing: the inbox,
/// then search, a message, a draft. The ones below stay built, so going
/// back finds them as they were, and while Android's back gesture runs the
/// top one follows the finger with the one below showing around it.
/// Letting go fades the top out and calls [onBack]; with reduce motion
/// nothing follows the finger and Back is instant.
///
/// A screen that comes up grows out of what was touched ([PiumaOrigin]),
/// on the spatial spring, while the one below sinks back a little; going
/// back shrinks it into the same place. Without a place it rises in.
class PhoneLayers extends StatefulWidget {
  const PhoneLayers({
    super.key,
    required this.layers,
    required this.onBack,
    this.canFollow,
  });

  /// Bottom first. Each needs a key that stays the same while it shows.
  final List<Widget> layers;

  /// Does what Back does.
  final VoidCallback onBack;

  /// False while Back would do something else first, like closing a menu.
  final bool Function()? canFollow;

  @override
  State<PhoneLayers> createState() => _PhoneLayersState();
}

class _PhoneLayersState extends State<PhoneLayers>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: PiumaMotion.press,
  );
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: PiumaMotion.spatial,
    value: 1,
  );

  /// The screen growing in or shrinking away, and the place it grows from.
  Key? _growing;
  Widget? _gone;
  final _origins = <Key, Rect?>{};
  double _progress = 0;
  SwipeEdge _edge = SwipeEdge.left;
  bool _active = false;
  Key? _following;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _leave.addListener(() => setState(() {}));
    _grow.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leave.dispose();
    _grow.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PhoneLayers old) {
    super.didUpdateWidget(old);
    final top = widget.layers.last.key;
    final oldTop = old.layers.last.key;
    final byGesture = _following != null;
    // A new top, by Back or anything else: nothing follows the finger.
    if (_following != null && top != _following) {
      _reset();
    }
    if (top == oldTop || reduceMotion(context)) return;
    final keys = {for (final l in widget.layers) l.key};
    final oldKeys = {for (final l in old.layers) l.key};
    if (widget.layers.length > old.layers.length && !oldKeys.contains(top)) {
      // Came up: grow out of what was touched.
      _origins[top!] = _local(PiumaOrigin.take());
      _growing = top;
      _gone = null;
      _grow.forward(from: 0);
    } else if (widget.layers.length < old.layers.length &&
        !keys.contains(oldTop)) {
      final to = _origins.remove(oldTop);
      // The back gesture already took it away.
      if (byGesture) return;
      _growing = oldTop;
      _gone = old.layers.last;
      _origins[oldTop!] = to;
      _grow.reverse(from: 1).whenCompleteOrCancel(() {
        if (!mounted) return;
        setState(() {
          _gone = null;
          _origins.remove(oldTop);
        });
      });
    }
  }

  /// [global] in this stack's coordinates.
  Rect? _local(Rect? global) {
    final box = context.findRenderObject();
    if (global == null || box is! RenderBox || !box.hasSize) return null;
    final at = box.globalToLocal(global.topLeft);
    return at & global.size;
  }

  void _reset() {
    _active = false;
    _progress = 0;
    _following = null;
    _leave.value = 0;
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final route = ModalRoute.of(context);
    if (!(widget.canFollow?.call() ?? true) ||
        widget.layers.length < 2 ||
        reduceMotion(context) ||
        (route != null && !route.isCurrent) ||
        _leave.isAnimating ||
        _grow.isAnimating) {
      return false;
    }
    setState(() {
      _active = true;
      _edge = backEvent.swipeEdge;
      _progress = backEvent.progress;
      _following = widget.layers.last.key;
    });
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_active) return;
    setState(() => _progress = backEvent.progress);
  }

  @override
  void handleCancelBackGesture() {
    if (!_active) return;
    setState(_reset);
  }

  @override
  void handleCommitBackGesture() {
    if (!_active) return;
    final top = widget.layers.last.key;
    _leave.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) return;
      widget.onBack();
      // Back did something else first (closed a list, asked to save):
      // the page stays and comes back whole.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.layers.last.key == top) setState(_reset);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final layers = widget.layers;
    final last = layers.length - 1;
    final leaving = PiumaMotion.curve.transform(_leave.value);
    final surface = PiumaTheme.of(context).surface;
    final moving = _grow.isAnimating || _gone != null;
    final t = _grow.value;
    final s = PiumaSprings.spatial.transform(t);
    // While a screen grows in, the one below shows and sinks back; while
    // one shrinks away, the new top comes forward again.
    final under = _gone != null ? last : last - 1;

    _Look look(Key? key, {required bool top}) {
      if (moving && key == _growing) {
        final from = _origins[key];
        final fade = PiumaMotion.curve.transform((t / 0.45).clamp(0.0, 1.0));
        if (from == null) {
          return _Look(opacity: fade, shift: Offset(0, 24 * (1 - s)));
        }
        return _Look(
          opacity: fade,
          clip: (full) => Rect.lerp(from, full, s)!,
          radius: PiumaRadius.card * (1 - s).clamp(0.0, 1.0),
          inner: Offset(0, from.top * (1 - s)),
          innerScale: 0.96 + 0.04 * s,
        );
      }
      if (top && _active) {
        // Android's back gesture: as [backGestureLook].
        final p = (_progress * 2).clamp(0.0, 1.0);
        final shift = PiumaMotion.backShiftPx * p;
        return _Look(
          opacity: 1 - leaving,
          shift: Offset(_edge == SwipeEdge.left ? shift : -shift, 0),
          scale: 1 - (1 - PiumaMotion.backScale) * p,
          radius: PiumaRadius.panel * p,
        );
      }
      return _Look(opacity: top ? 1 - leaving : 1);
    }

    Widget layer(int i, Widget child, _Look look, {bool gone = false}) {
      final key = layers.length > i && !gone ? layers[i].key : child.key;
      final shown = gone || i == last;
      return KeyedSubtree(
        key: key,
        child: IgnorePointer(
          ignoring: gone,
          child: ExcludeFocus(
            excluding: !shown || gone,
            child: TickerMode(
              enabled: shown,
              child: Offstage(
                offstage:
                    !shown &&
                    !(_active && i == last - 1) &&
                    !(moving && i == under),
                child: look.wrap(
                  // Each on its own paper, so the one below shows only
                  // around it, never through it. Painted once and only
                  // moved while it grows, sinks or shrinks.
                  RepaintBoundary(
                    child: ColoredBox(color: surface, child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < layers.length; i++)
          layer(
            i,
            layers[i],
            moving && i == under
                ? _Look(
                    opacity: 1 - (1 - PiumaMotion.sinkOpacity) * t,
                    scale: 1 - (1 - PiumaMotion.sinkScale) * s,
                  )
                : look(layers[i].key, top: i == last),
          ),
        if (_gone case final gone?)
          layer(layers.length, gone, look(gone.key, top: true), gone: true),
      ],
    );
  }
}

/// How a layer looks this frame. The widgets are the same whatever the
/// values, so a layer keeps its state while it grows, sinks or shrinks.
class _Look {
  const _Look({
    this.opacity = 1,
    this.shift = Offset.zero,
    this.scale = 1,
    this.clip,
    this.radius = 0,
    this.inner = Offset.zero,
    this.innerScale = 1,
  });

  final double opacity;
  final Offset shift;
  final double scale;

  /// The visible part, from the whole box; null shows it all.
  final Rect Function(Rect full)? clip;
  final double radius;

  /// Where the content sits inside the clip, and how big.
  final Offset inner;
  final double innerScale;

  Widget wrap(Widget child) => Opacity(
    opacity: opacity.clamp(0.0, 1.0),
    child: Transform.translate(
      offset: shift,
      child: Transform.scale(
        scale: scale,
        child: ClipRRect(
          // Smooth corners only while there are corners to smooth.
          clipBehavior: radius > 0.5
              ? Clip.antiAlias
              : clip == null
              ? Clip.none
              : Clip.hardEdge,
          clipper: _Clip(clip, radius),
          child: Transform.translate(
            offset: inner,
            child: Transform.scale(
              scale: innerScale,
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Clip extends CustomClipper<RRect> {
  const _Clip(this.clip, this.radius);

  final Rect Function(Rect full)? clip;
  final double radius;

  @override
  RRect getClip(Size size) {
    final full = Offset.zero & size;
    return RRect.fromRectAndRadius(
      clip?.call(full) ?? full,
      Radius.circular(radius),
    );
  }

  @override
  bool shouldReclip(_Clip old) => true;
}
