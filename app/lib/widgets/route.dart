import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/tokens.g.dart';
import 'predictive_back.dart';

/// A full screen that enters like everything else: a 4px rise out of a
/// fade, on the single curve. Instant with reduce motion. Android's back
/// gesture shows the screen below as the finger moves.
class PiumaRoute<T> extends PageRouteBuilder<T> {
  PiumaRoute({required WidgetBuilder builder, required bool instant})
    : super(
        transitionDuration: instant ? Duration.zero : PiumaMotion.enter,
        reverseTransitionDuration: instant ? Duration.zero : PiumaMotion.enter,
        pageBuilder: (context, _, _) => builder(context),
      );

  /// For [context]'s reduce-motion setting.
  static PiumaRoute<T> of<T>(BuildContext context, WidgetBuilder builder) =>
      PiumaRoute<T>(builder: builder, instant: reduceMotion(context));

  /// The swipe's edge, and how far the route was shown when it was let go.
  final _gesture = ValueNotifier<(SwipeEdge, double?)?>(null);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _RouteBack(
      route: this,
      child: AnimatedBuilder(
        animation: Listenable.merge([animation, _gesture]),
        child: child,
        builder: (context, child) {
          final gesture = _gesture.value;
          if (gesture != null && popGestureInProgress) {
            final (edge, shown) = gesture;
            return backGestureLook(
              progress: 1 - animation.value,
              edge: edge,
              opacity: shown == null || shown == 0
                  ? 1
                  : animation.value / shown,
              child: child!,
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
      ),
    );
  }

  @override
  void dispose() {
    _gesture.dispose();
    super.dispose();
  }
}

/// Hands Android's back gesture to [route] while it is on top.
class _RouteBack extends StatefulWidget {
  const _RouteBack({required this.route, required this.child});

  final PiumaRoute<dynamic> route;
  final Widget child;

  @override
  State<_RouteBack> createState() => _RouteBackState();
}

class _RouteBackState extends State<_RouteBack> with WidgetsBindingObserver {
  bool _active = false;

  PiumaRoute<dynamic> get _route => widget.route;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    _active =
        _route.isCurrent &&
        !_route.isFirst &&
        !_route.popGestureInProgress &&
        !reduceMotion(context) &&
        _route.popDisposition == RoutePopDisposition.pop;
    if (!_active) return false;
    _route._gesture.value = (backEvent.swipeEdge, null);
    _route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_active) {
      _route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);
    }
  }

  @override
  void handleCancelBackGesture() {
    if (!_active) return;
    _active = false;
    _route.handleCancelBackGesture();
    // Back to the usual look once the route is whole again.
    late final AnimationStatusListener whole;
    whole = (status) {
      if (!status.isCompleted) return;
      _route.animation?.removeStatusListener(whole);
      _route._gesture.value = null;
    };
    if (_route.animation?.isCompleted ?? true) {
      _route._gesture.value = null;
    } else {
      _route.animation?.addStatusListener(whole);
    }
  }

  @override
  void handleCommitBackGesture() {
    if (!_active) return;
    _active = false;
    final (edge, _) = _route._gesture.value!;
    _route._gesture.value = (edge, _route.animation!.value);
    _route.handleCommitBackGesture();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
