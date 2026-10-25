import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// A progress line that is wavy while it runs, as in Material 3
/// Expressive: the filled part is a small wave travelling forward, the
/// rest a flat track after a little gap. When [value] reaches 1 the wave
/// flattens into a plain line. With no [value] (not known yet) a wavy
/// stretch sweeps across. With reduce motion the wave stands still and
/// the fill jumps.
class PiumaProgress extends StatefulWidget {
  const PiumaProgress({
    super.key,
    this.value,
    this.color,
    this.track,
    this.thickness = 3,
  });

  /// From 0 to 1; null while not known.
  final double? value;

  /// The filled part; the accent when null.
  final Color? color;

  /// The rest of the line; none when null.
  final Color? track;
  final double thickness;

  /// How tall the line is with its wave.
  static double heightFor(double thickness) =>
      thickness + 2 * PiumaMotion.waveAmplitudePx;

  @override
  State<PiumaProgress> createState() => _PiumaProgressState();
}

class _PiumaProgressState extends State<PiumaProgress>
    with TickerProviderStateMixin {
  /// The wave's travel, one wavelength per turn.
  late final _phase = AnimationController(
    vsync: this,
    duration: PiumaMotion.wave,
  );

  /// The sweep of an unknown progress.
  late final _sweep = AnimationController(
    vsync: this,
    duration: PiumaMotion.waveSweep,
  );

  /// How wavy: 1 while running, 0 once done. A shape, so it eases on
  /// the fade curve and never overshoots.
  late final _wave = AnimationController(
    vsync: this,
    duration: PiumaMotion.move,
    value: _running ? 1 : 0,
  );

  /// The fill, eased toward [PiumaProgress.value].
  late final _fill = AnimationController(
    vsync: this,
    duration: PiumaMotion.press,
    value: widget.value?.clamp(0.0, 1.0) ?? 0,
  );
  double _from = 0;
  double _to = 0;

  bool get _running => widget.value == null || widget.value! < 1;

  @override
  void initState() {
    super.initState();
    _from = _to = _fill.value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PiumaProgress old) {
    super.didUpdateWidget(old);
    final to = widget.value?.clamp(0.0, 1.0);
    if (to != null && to != _to) {
      _from = _shownFill;
      _to = to;
      if (reduceMotion(context)) {
        _from = to;
      } else {
        _fill.forward(from: 0);
      }
    }
    _sync();
  }

  double get _shownFill =>
      _from + (_to - _from) * PiumaMotion.curve.transform(_fill.value);

  /// Runs only the tickers the line needs now.
  void _sync() {
    final instant = reduceMotion(context);
    final running = _running;
    if (instant) {
      _phase.stop();
      _sweep.stop();
      _wave.value = running ? 1 : 0;
      return;
    }
    if (running) {
      _wave.animateTo(1, curve: PiumaMotion.curve);
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _wave.animateTo(0, curve: PiumaMotion.curve).whenCompleteOrCancel(() {
        if (mounted && !_running) _phase.stop();
      });
    }
    if (widget.value == null) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _sweep.dispose();
    _wave.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return RepaintBoundary(
      child: SizedBox(
        height: PiumaProgress.heightFor(widget.thickness),
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(
            repaint: Listenable.merge([_phase, _sweep, _wave, _fill]),
            state: this,
            color: widget.color ?? c.accent,
            track: widget.track,
            thickness: widget.thickness,
            // With reduce motion an unknown progress is a still wave
            // across the whole line.
            still: instant,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required Listenable repaint,
    required this.state,
    required this.color,
    required this.track,
    required this.thickness,
    required this.still,
  }) : super(repaint: repaint);

  final _PiumaProgressState state;
  final Color color;
  final Color? track;
  final double thickness;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    if (w <= 0) return;
    final known = state.widget.value != null;
    double start;
    double end;
    if (known) {
      start = 0;
      end = state._shownFill * w;
    } else if (still) {
      start = 0;
      end = w;
    } else {
      // The head runs ahead, the tail follows a quarter turn later.
      final s = state._sweep.value;
      final curve = PiumaMotion.curve;
      start = curve.transform(((s - 0.25) / 0.75).clamp(0.0, 1.0)) * w;
      end = curve.transform((s / 0.75).clamp(0.0, 1.0)) * w;
    }
    final half = thickness / 2;
    final gap = thickness * 1.4;
    final mid = size.height / 2;
    final amplitude = PiumaMotion.waveAmplitudePx * state._wave.value;
    final shift = 2 * math.pi * state._phase.value;
    final k = 2 * math.pi / PiumaMotion.waveLengthPx;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final a = start + half;
    final b = end - half;
    final filled = b > a;
    if (filled) {
      line.color = color;
      if (amplitude < 0.05) {
        canvas.drawLine(Offset(a, mid), Offset(b, mid), line);
      } else {
        final path = Path()
          ..moveTo(a, mid + amplitude * math.sin(k * a - shift));
        for (var x = a + 1; x < b; x += 1) {
          path.lineTo(x, mid + amplitude * math.sin(k * x - shift));
        }
        path.lineTo(b, mid + amplitude * math.sin(k * b - shift));
        canvas.drawPath(path, line);
      }
    }

    final t = track;
    if (t == null) return;
    line.color = t;
    void flat(double from, double to) {
      if (to > from) canvas.drawLine(Offset(from, mid), Offset(to, mid), line);
    }

    // The track after the fill, and before it while sweeping.
    flat(filled ? end + gap + half : half, w - half);
    if (filled && start > 0) flat(half, start - gap - half);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.color != color ||
      old.track != track ||
      old.thickness != thickness ||
      old.still != still;
}
