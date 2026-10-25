import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'tokens.g.dart';

/// True when the system asks to reduce motion: then everything is instant.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A spring from 0 to 1 laid over a fixed time, for widgets that take a
/// [Curve]. It may pass 1 a little before it settles, so use it only for
/// what moves (position, size, scale), never for opacity or color.
class SpringCurve extends Curve {
  SpringCurve({
    required double damping,
    required double stiffness,
    required this.duration,
  }) : _sim = SpringSimulation(
         SpringDescription.withDampingRatio(
           mass: 1,
           stiffness: stiffness,
           ratio: damping,
         ),
         0,
         1,
         0,
       );

  final Duration duration;
  final SpringSimulation _sim;

  @override
  double transformInternal(double t) =>
      _sim.x(t * duration.inMicroseconds / Duration.microsecondsPerSecond);

  @override
  double transform(double t) => t >= 1 ? 1 : super.transform(t);
}

/// The two springs of the motion system (`design/tokens.json`), with the
/// time each is laid over. Fades keep [PiumaMotion.curve].
abstract final class PiumaSprings {
  /// Screens, panels and anything that travels: a soft spring.
  static final spatial = SpringCurve(
    damping: PiumaMotion.spatialDamping,
    stiffness: PiumaMotion.spatialStiffness,
    duration: PiumaMotion.spatial,
  );

  /// Small things that answer a touch (a press, a pill, a row): quicker,
  /// with a little more give.
  static final fast = SpringCurve(
    damping: PiumaMotion.fastDamping,
    stiffness: PiumaMotion.fastStiffness,
    duration: PiumaMotion.fast,
  );
}

/// Where the next screen grows from: the row, button or tile just
/// touched, in global coordinates. [PhoneLayers] takes it when a screen
/// comes up and gives it back when that screen goes.
abstract final class PiumaOrigin {
  static Rect? _next;

  /// Remembers [context]'s box as the place the next screen grows from.
  static void from(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize && box.attached) {
      _next = box.localToGlobal(Offset.zero) & box.size;
    }
  }

  /// The place remembered, once.
  static Rect? take() {
    final r = _next;
    _next = null;
    return r;
  }
}

/// Haptics, on phones only and only where they tell something: an email
/// archived or deleted, a swipe crossing the point where it will act, an
/// email sent, a long press starting to select. Never on plain taps.
abstract final class PiumaHaptics {
  static bool get _phone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// An email archived, deleted or moved away.
  static void done() {
    if (_phone) HapticFeedback.mediumImpact();
  }

  /// A swipe crossed the point where letting go acts.
  static void threshold() {
    if (_phone) HapticFeedback.selectionClick();
  }

  /// A long press started selecting.
  static void select() {
    if (_phone) HapticFeedback.selectionClick();
  }

  /// An email went.
  static void sent() {
    if (!_phone) return;
    HapticFeedback.lightImpact();
    Future<void>.delayed(
      const Duration(milliseconds: 70),
      HapticFeedback.mediumImpact,
    );
  }
}

/// Entrance: fades in while it rises 4px on the spatial spring. No blur,
/// so whole panes stay cheap to draw. [index] staggers list items by 40ms
/// each.
class PiumaEnter extends StatefulWidget {
  const PiumaEnter({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<PiumaEnter> createState() => _PiumaEnterState();
}

class _PiumaEnterState extends State<PiumaEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PiumaMotion.spatial,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
      return;
    }
    Future<void>.delayed(PiumaMotion.stagger * widget.index, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      // Painted once and moved and faded as a picture, instead of drawn
      // again on every frame of the entrance.
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final v = _c.value;
        if (v == 1) return child!;
        // The fade is done in [PiumaMotion.enter]; the rise settles later.
        final fadeAt =
            PiumaMotion.enter.inMicroseconds /
            PiumaMotion.spatial.inMicroseconds;
        final fade = PiumaMotion.curve.transform((v / fadeAt).clamp(0, 1));
        final rise = PiumaSprings.spatial.transform(v);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(0, PiumaMotion.enterRisePx * (1 - rise)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Press: squishes to 0.96 while held and springs back with a little give
/// when let go.
class PiumaPressable extends StatefulWidget {
  const PiumaPressable({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<PiumaPressable> createState() => _PiumaPressableState();
}

class _PiumaPressableState extends State<PiumaPressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final instant = reduceMotion(context);
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: AnimatedScale(
            scale: _down ? PiumaMotion.pressScale : 1,
            duration: instant
                ? Duration.zero
                : _down
                ? PiumaMotion.press
                : PiumaMotion.fast,
            curve: _down ? PiumaMotion.curve : PiumaSprings.fast,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
