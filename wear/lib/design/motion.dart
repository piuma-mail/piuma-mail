import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'tokens.g.dart';

/// True when the system asks to reduce motion: then everything is instant.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A spring from 0 to 1 laid over a fixed time, as in the phone app
/// (`app/lib/design/motion.dart`). Only for what moves, never for fades.
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

/// The two springs of the motion system (`design/tokens.json`).
abstract final class PiumaSprings {
  static final spatial = SpringCurve(
    damping: PiumaMotion.spatialDamping,
    stiffness: PiumaMotion.spatialStiffness,
    duration: PiumaMotion.spatial,
  );

  static final fast = SpringCurve(
    damping: PiumaMotion.fastDamping,
    stiffness: PiumaMotion.fastStiffness,
    duration: PiumaMotion.fast,
  );
}

/// Where the next screen grows from: what was just tapped.
abstract final class PiumaOrigin {
  static Rect? _next;

  static void from(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize && box.attached) {
      _next = box.localToGlobal(Offset.zero) & box.size;
    }
  }

  static Rect? take() {
    final r = _next;
    _next = null;
    return r;
  }
}

/// A screen that grows out of what was tapped (`WatchWearOS` 3): it
/// scales up from that place on the spatial spring and fades in on the
/// plain curve; going back, it shrinks into it again.
class GrowRoute<T> extends PageRouteBuilder<T> {
  GrowRoute({required WidgetBuilder builder, required bool instant})
    : _from = PiumaOrigin.take(),
      super(
        opaque: true,
        transitionDuration: instant ? Duration.zero : PiumaMotion.spatial,
        reverseTransitionDuration: instant ? Duration.zero : PiumaMotion.move,
        pageBuilder: (context, _, _) => builder(context),
      );

  final Rect? _from;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final size = MediaQuery.sizeOf(context);
    final from = _from;
    final alignment = from == null
        ? Alignment.center
        : Alignment(
            (from.center.dx / size.width) * 2 - 1,
            (from.center.dy / size.height) * 2 - 1,
          );
    final start = from == null
        ? 0.85
        : (from.width / size.width).clamp(0.3, 0.95).toDouble();
    final scale = Tween<double>(begin: start, end: 1).animate(
      CurvedAnimation(
        parent: animation,
        curve: PiumaSprings.spatial,
        reverseCurve: PiumaMotion.curve.flipped,
      ),
    );
    final fade = CurvedAnimation(parent: animation, curve: PiumaMotion.curve);
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(scale: scale, alignment: alignment, child: child),
    );
  }
}

/// Haptics on the watch only where they tell something: an action landed.
abstract final class PiumaHaptics {
  static bool get _watch =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Archived, snoozed or sent.
  static void done() {
    if (_watch) HapticFeedback.mediumImpact();
  }
}
