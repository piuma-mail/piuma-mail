import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// A phone row that archives with a swipe toward the reading end (to the
/// right in a left-to-right language, to the left in Arabic or Hebrew), as
/// in the
/// `PhoneSwipe` mockup: the row slides over a green band with "Archive",
/// and past a quarter of the way it leaves. With
/// [onSnooze], a swipe to the left snoozes it over an amber band. With
/// [hint] the row shows how, once: it slides a little over the Archive
/// band and back (`DetailsToApprove`), not at all with reduce motion.
///
/// The swipe is sticky, as Material 3 Expressive notifications are: the
/// row holds back a little until the point where letting go acts, snaps
/// to the finger there (with a tick on phones), lets go again if the
/// finger goes back, and when released carries the finger's speed on a
/// spring.
/// The colour of a swipe's band, from the theme.
enum SwipeTone { ok, warn, danger, accent }

/// What one side of a row's swipe shows and does, as the person set it
/// (Settings › Appearance › Lists): its band, and whether the row leaves
/// or springs back ([stays], as for Star or Read). [off]: that side
/// doesn't swipe.
class SwipeSide {
  const SwipeSide({
    required this.icon,
    required this.label,
    this.tone = SwipeTone.ok,
    this.stays = false,
    this.off = false,
  });

  final PiumaIcon icon;
  final String label;
  final SwipeTone tone;
  final bool stays;
  final bool off;
}

class SwipeToArchive extends StatefulWidget {
  const SwipeToArchive({
    super.key,
    required this.label,
    required this.onArchive,
    required this.child,
    this.snoozeLabel,
    this.onSnooze,
    this.hint = false,
    this.icon = PiumaIcon.archive,
    this.snoozeIcon = PiumaIcon.clock,
    this.snoozeStays = false,
    this.archiveStays = false,
    this.rightOff = false,
    this.tone = SwipeTone.ok,
    this.snoozeTone = SwipeTone.warn,
  });

  /// The right swipe springs back in place, as the left one can.
  final bool archiveStays;

  /// The right swipe does nothing: the row doesn't move that way.
  final bool rightOff;

  /// The bands' colours.
  final SwipeTone tone;
  final SwipeTone snoozeTone;

  /// The right swipe's band: Archive, or Stop waiting in Waiting.
  final PiumaIcon icon;

  /// The left swipe's band: Snooze, or Remind me in Waiting, where the
  /// row springs back in place ([snoozeStays]) as its choices come up.
  final PiumaIcon snoozeIcon;
  final bool snoozeStays;
  final String label;
  final VoidCallback onArchive;
  final String? snoozeLabel;
  final VoidCallback? onSnooze;
  final bool hint;
  final Widget child;

  @override
  State<SwipeToArchive> createState() => _SwipeToArchiveState();
}

class _SwipeToArchiveState extends State<SwipeToArchive>
    with TickerProviderStateMixin {
  /// How far the row has moved, as a share of its width: positive toward
  /// the reading end (Archive's side), negative toward the start.
  late final _offset = AnimationController(
    vsync: this,
    lowerBound: -1,
    upperBound: 1,
    value: 0,
  );

  /// How far the row has caught up with the finger: 0 while it holds
  /// back, 1 once past the point where letting go acts. On the fast
  /// spring, so the catch-up lands with a little give.
  late final _snap = AnimationController(
    vsync: this,
    lowerBound: -0.5,
    upperBound: 1.5,
    value: 0,
  )..addListener(_follow);

  /// Where the finger is, as a share of the width.
  double _finger = 0;
  bool _dragging = false;
  bool _armed = false;
  double _width = 1;
  bool _leaving = false;

  /// 1 in a left-to-right layout, -1 in a right-to-left one: turns the
  /// finger's travel into [_offset]'s reading-order direction and back.
  double _sign = 1;

  static const _threshold = PiumaMotion.swipeAt;

  /// The widest the band's label sits in.
  static const _bandPx = 132.0;

  /// How far the hint slides the row.
  static const _hintPx = 72.0;

  Timer? _hintWait;
  bool _hinting = false;

  @override
  void initState() {
    super.initState();
    if (widget.hint) _playHint();
  }

  /// After a pause, slides the row over the Archive band and back.
  void _playHint() {
    _hintWait?.cancel();
    _hintWait = Timer(PiumaMotion.reveal, () async {
      if (!mounted || reduceMotion(context) || _offset.value != 0) return;
      _hinting = true;
      try {
        await _offset
            .animateTo(
              _hintPx / _width,
              duration: PiumaMotion.move,
              curve: PiumaMotion.curve,
            )
            .orCancel;
        await Future<void>.delayed(PiumaMotion.move);
        if (!mounted || !_hinting) return;
        await _offset
            .animateTo(0, duration: PiumaMotion.move, curve: PiumaMotion.curve)
            .orCancel;
      } on TickerCanceled {
        // A finger took over.
      } finally {
        _hinting = false;
      }
    });
  }

  @override
  void dispose() {
    _hintWait?.cancel();
    _offset.dispose();
    _snap.dispose();
    super.dispose();
  }

  /// The share of the finger's travel the row shows.
  double get _grip =>
      PiumaMotion.swipeResist + (1 - PiumaMotion.swipeResist) * _snap.value;

  /// Puts the row where the finger and the snap say.
  void _follow() {
    if (!_dragging) return;
    final left = widget.onSnooze == null ? 0.0 : -1.0;
    final right = widget.rightOff ? 0.0 : 1.0;
    _offset.value = (_finger * _grip).clamp(left, right);
  }

  void _start(DragStartDetails d) {
    if (_leaving) return;
    // A finger takes over from the hint, or from a row on its way back.
    _hintWait?.cancel();
    _hinting = false;
    _offset.stop();
    _snap.stop();
    _dragging = true;
    _armed = _offset.value.abs() >= _threshold;
    _snap.value = _armed ? 1 : 0;
    _finger = _offset.value / _grip;
  }

  void _drag(DragUpdateDetails d) {
    if (_leaving || !_dragging) return;
    final left = widget.onSnooze == null ? 0.0 : -1.0;
    final right = widget.rightOff ? 0.0 : 1.0;
    _finger = (_finger + _sign * d.primaryDelta! / _width).clamp(left, right);
    // Snaps on past the point where letting go acts, and off a little
    // before it, so it does not chatter on the edge.
    final reach = _finger.abs();
    final armed = _armed
        ? reach >= _threshold * PiumaMotion.swipeRelease
        : reach >= _threshold;
    if (armed != _armed) {
      _armed = armed;
      PiumaHaptics.threshold();
      if (reduceMotion(context)) {
        _snap.value = armed ? 1 : 0;
      } else {
        _snap.animateTo(
          armed ? 1 : 0,
          duration: PiumaMotion.fast,
          curve: PiumaSprings.fast,
        );
      }
    }
    _follow();
  }

  /// Carries [velocity] (in shares of the width a second) to [target] on
  /// the spatial spring, or there at once with reduce motion.
  Future<void> _settle(double target, double velocity, {double ratio = 1}) {
    if (reduceMotion(context)) {
      _offset.value = target;
      return Future.value();
    }
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: PiumaMotion.spatialStiffness,
      ratio: ratio,
    );
    // The spring ends within a hair of [target]; then it is exactly there.
    return _offset
        .animateWith(SpringSimulation(spring, _offset.value, target, velocity))
        .then((_) => _offset.value = target);
  }

  Future<void> _release(DragEndDetails d) async {
    if (_leaving || !_dragging) return;
    _dragging = false;
    _snap.stop();
    final v = _sign * (d.primaryVelocity ?? 0);
    // Leaving, the row never comes back past its edge: no overshoot.
    final away = (v / _width).abs().clamp(1.5, double.infinity);
    if (_armed && _finger > 0 && !widget.rightOff) {
      if (widget.archiveStays) {
        widget.onArchive();
        await _settle(0, v / _width, ratio: PiumaMotion.spatialDamping);
        return;
      }
      _leaving = true;
      await _settle(1, away);
      widget.onArchive();
      return;
    }
    if (widget.onSnooze case final snooze? when _armed && _finger < 0) {
      if (widget.snoozeStays) {
        snooze();
        await _settle(0, v / _width, ratio: PiumaMotion.spatialDamping);
        return;
      }
      _leaving = true;
      await _settle(-1, -away);
      snooze();
      return;
    }
    // Back in place on a spring, with the finger's speed.
    await _settle(0, v / _width, ratio: PiumaMotion.spatialDamping);
  }

  void _cancel() {
    if (!_dragging || _leaving) return;
    _dragging = false;
    _armed = false;
    _snap.stop();
    unawaited(_settle(0, 0, ratio: PiumaMotion.spatialDamping));
  }

  @override
  void didUpdateWidget(SwipeToArchive old) {
    super.didUpdateWidget(old);
    if (widget.hint && !old.hint) _playHint();
    // The same row back after Undo starts in place.
    if (_leaving && _offset.value.abs() == 1) {
      _leaving = false;
      _armed = false;
      _snap.value = 0;
      _offset.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    _sign = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth == 0 ? 1 : box.maxWidth;
        return Semantics(
          customSemanticsActions: {
            if (!widget.rightOff)
              CustomSemanticsAction(label: widget.label): widget.onArchive,
            CustomSemanticsAction(label: widget.snoozeLabel ?? ''):
                ?widget.onSnooze,
          },
          child: RawGestureDetector(
            gestures: {
              _MailSwipeRecognizer:
                  GestureRecognizerFactoryWithHandlers<_MailSwipeRecognizer>(
                    _MailSwipeRecognizer.new,
                    (recognizer) => recognizer
                      ..onStart = _start
                      ..onUpdate = _drag
                      ..onEnd = _release
                      ..onCancel = _cancel,
                  ),
            },
            child: AnimatedBuilder(
              animation: _offset,
              builder: (context, child) {
                final dx = _offset.value * _width;
                return Stack(
                  children: [
                    if (dx > 0)
                      Positioned.fill(
                        child: ColoredBox(
                          color: _tone(c, widget.tone),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(
                              // Centered in what is showing, up to 132px.
                              width: dx.clamp(0, _bandPx),
                              child: ExcludeSemantics(
                                child: _BandLabel(
                                  pop: _snap.value,
                                  icon: widget.icon,
                                  label: widget.label,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (dx < 0)
                      Positioned.fill(
                        child: ColoredBox(
                          color: _tone(c, widget.snoozeTone),
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: SizedBox(
                              width: (-dx).clamp(0, _bandPx),
                              child: ExcludeSemantics(
                                child: _BandLabel(
                                  pop: _snap.value,
                                  icon: widget.snoozeIcon,
                                  label: widget.snoozeLabel ?? '',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Transform.translate(
                      offset: Offset(_sign * dx, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surface,
                          boxShadow: dx != 0
                              ? [
                                  BoxShadow(
                                    color: c.shadow.withValues(
                                      alpha: c.shadow.a / 3,
                                    ),
                                    blurRadius: 14,
                                    offset: Offset(
                                      _sign * (dx > 0 ? -6 : 6),
                                      0,
                                    ),
                                  ),
                                ]
                              : null,
                        ),
                        child: child,
                      ),
                    ),
                  ],
                );
              },
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

Color _tone(PiumaColors c, SwipeTone tone) => switch (tone) {
  SwipeTone.ok => c.ok,
  SwipeTone.warn => c.warn,
  SwipeTone.danger => c.danger,
  SwipeTone.accent => c.accent,
};

/// The icon and word on the band a row slides off. The icon grows as the
/// swipe snaps on ([pop] from 0 to 1, a touch past it on the spring).
class _BandLabel extends StatelessWidget {
  const _BandLabel({
    required this.icon,
    required this.label,
    required this.pop,
  });

  final PiumaIcon icon;
  final String label;
  final double pop;

  /// The icon's size before the snap, as a share of its full size.
  static const _rest = 0.82;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: _rest + (1 - _rest) * pop,
          child: PiumaIconView(icon, size: 22, color: c.onAccent),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.onAccent,
          ),
        ),
      ],
    );
  }
}

/// Leave diagonal gestures to the inbox's vertical scroll recognizer.
class _MailSwipeRecognizer extends HorizontalDragGestureRecognizer {
  final _travel = <int, Offset>{};
  Offset _currentTravel = Offset.zero;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _currentTravel = (_travel[event.pointer] ?? Offset.zero) + event.delta;
      _travel[event.pointer] = _currentTravel;
    }
    // Flutter ends an accepted drag even on pointer cancellation.
    // Disarm the row before that end callback can perform an action.
    if (event is PointerCancelEvent) onCancel?.call();
    super.handleEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _travel.remove(event.pointer);
    }
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      _currentTravel.dx.abs() > 2 * _currentTravel.dy.abs() &&
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );

  @override
  void dispose() {
    _travel.clear();
    super.dispose();
  }
}
