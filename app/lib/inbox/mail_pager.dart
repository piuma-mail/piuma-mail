import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// An open email on the phone that a sideways swipe turns into the next
/// one in the list (swiping left) or the one before (swiping right). The
/// email follows the finger with the next one beside it, as pages; past a
/// third of the way, or with a flick, it settles on the next on the
/// spatial spring, which the finger can catch again. With nothing on that
/// side it gives a little and springs back. With reduce motion nothing
/// follows the finger and the swipe turns at once.
class MailPager extends StatefulWidget {
  const MailPager({
    super.key,
    required this.row,
    required this.near,
    required this.build,
    required this.onTurn,
  });

  /// The email showing.
  final MailRow row;

  /// The email [step] places after [row] in the list (1 the next, -1 the
  /// one before), or null when there is none.
  final MailRow? Function(MailRow row, int step) near;

  /// Draws one email; [showing] is false for the one coming in from the
  /// side, which takes no menus or keys yet.
  final Widget Function(MailRow row, bool showing) build;

  /// Called once the swipe has settled on [row]'s neighbour.
  final ValueChanged<MailRow> onTurn;

  @override
  State<MailPager> createState() => _MailPagerState();
}

class _MailPagerState extends State<MailPager>
    with SingleTickerProviderStateMixin {
  /// Where the email showing is, in widths: -1 is a whole width to the
  /// left, where it is when the next one has come in.
  late final AnimationController _dx = AnimationController.unbounded(
    vsync: this,
  );

  static const _threshold = 0.3;
  static const _flick = 700.0;

  /// How much a swipe toward no email moves.
  static const _give = 0.2;

  /// Between the two emails while both show.
  static const _gap = PiumaSpace.s16;

  double _width = 1;

  /// The email coming in from the side being swiped toward, and which way
  /// it is (1 the next, from the right; -1 the one before).
  MailRow? _peek;
  int _side = 0;

  /// Set once a swipe has let go past the threshold, until [onTurn].
  bool _turning = false;

  /// With reduce motion, how far the finger went.
  double _went = 0;

  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: PiumaMotion.spatialStiffness,
    ratio: PiumaMotion.spatialDamping,
  );

  double get _page => 1 + _gap / _width;

  @override
  void didUpdateWidget(MailPager old) {
    super.didUpdateWidget(old);
    if (widget.row.key != old.row.key) {
      // The neighbour is the email now: it stays where it is, at rest.
      _dx.stop();
      _dx.value = 0;
      _peek = null;
      _side = 0;
      _turning = false;
    }
  }

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  void _start(DragStartDetails _) {
    if (_turning) return;
    _dx.stop();
    _went = 0;
  }

  void _drag(DragUpdateDetails d) {
    if (_turning) return;
    final delta = d.primaryDelta! / _width;
    if (reduceMotion(context)) {
      _went += delta;
      return;
    }
    final was = _dx.value;
    var next = was + delta;
    // Left shows the next email, right the one before.
    final side = next < 0 ? 1 : (next > 0 ? -1 : 0);
    if (side != _side) {
      setState(() {
        _side = side;
        _peek = side == 0 ? null : widget.near(widget.row, side);
      });
    }
    if (_peek == null) {
      // Nothing there: it gives, less the further it goes.
      next = was + delta * _give * (1 - (was.abs() / _give).clamp(0, 0.9));
    }
    _dx.value = next;
    if (_peek != null &&
        (was.abs() >= _threshold) != (next.abs() >= _threshold)) {
      PiumaHaptics.threshold();
    }
  }

  void _end(DragEndDetails d) {
    if (_turning) return;
    final v = (d.primaryVelocity ?? 0) / _width;
    if (reduceMotion(context)) {
      final side = _went < -_threshold || v * _width < -_flick
          ? 1
          : (_went > _threshold || v * _width > _flick ? -1 : 0);
      final to = side == 0 ? null : widget.near(widget.row, side);
      if (to != null) widget.onTurn(to);
      return;
    }
    final peek = _peek;
    final x = _dx.value;
    final turns =
        peek != null &&
        (x.abs() >= _threshold || (v * _width).abs() > _flick) &&
        // A flick the other way keeps the email.
        (v == 0 || v.sign == x.sign);
    if (turns) {
      _turning = true;
      final to = -_side * _page;
      _dx.animateWith(SpringSimulation(_spring, x, to, v)).whenCompleteOrCancel(
        () {
          if (mounted && _turning) widget.onTurn(peek);
        },
      );
      return;
    }
    _dx.animateWith(SpringSimulation(_spring, x, 0, v)).whenCompleteOrCancel(
      () {
        if (mounted && !_turning && _dx.value.abs() < 0.001) {
          setState(() {
            _peek = null;
            _side = 0;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final next = widget.near(widget.row, 1);
    final before = widget.near(widget.row, -1);
    final peek = _peek;
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth == 0 ? 1 : box.maxWidth;
        return Semantics(
          customSemanticsActions: {
            if (next != null)
              CustomSemanticsAction(label: l.nextEmail): () =>
                  widget.onTurn(next),
            if (before != null)
              CustomSemanticsAction(label: l.previousEmail): () =>
                  widget.onTurn(before),
          },
          child: GestureDetector(
            onHorizontalDragStart: _start,
            onHorizontalDragUpdate: _drag,
            onHorizontalDragEnd: _end,
            child: ClipRect(
              child: Stack(
                children: [
                  // Keyed, so the email coming in is the same one once it
                  // is the email showing.
                  if (peek != null)
                    Positioned.fill(
                      key: ValueKey(peek.key),
                      child: _Slide(
                        dx: _dx,
                        width: _width,
                        by: _side * _page,
                        child: _Page(child: widget.build(peek, false)),
                      ),
                    ),
                  Positioned.fill(
                    key: ValueKey(widget.row.key),
                    child: _Slide(
                      dx: _dx,
                      width: _width,
                      by: 0,
                      child: _Page(child: widget.build(widget.row, true)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A page at [dx] plus [by] widths, moved without building it again.
class _Slide extends AnimatedWidget {
  const _Slide({
    required Animation<double> dx,
    required this.width,
    required this.by,
    required this.child,
  }) : super(listenable: dx);

  final double width;
  final double by;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dx = (listenable as Animation<double>).value;
    return Transform.translate(
      offset: Offset((dx + by) * width, 0),
      child: child,
    );
  }
}

/// One email of the pager, on the page color, drawn on its own.
class _Page extends StatelessWidget {
  const _Page({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ColoredBox(color: PiumaTheme.of(context).surface, child: child),
  );
}
