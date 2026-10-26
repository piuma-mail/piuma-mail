import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

/// The line icons the watch uses, with the same path data and stroke as
/// the phone app's (`app/lib/design/icons.dart`, 24×24 grid, 1.75 stroke).
enum PiumaIcon {
  check(['M20 6 9 17l-5-5']),
  archive([
    'M4 4h16a1 1 0 0 1 1 1v2a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z',
    'M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8',
    'M10 12h4',
  ]),
  reply(['M9 14 4 9l5-5', 'M4 9h11a5 5 0 0 1 5 5v6']),
  clock(['M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0z', 'M12 7v5l3 2']),

  /// Speak or type a reply.
  mic([
    'M12 3a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3z',
    'M5 11a7 7 0 0 0 14 0',
    'M12 18v3',
  ]),

  /// The phone: what waits there.
  phone([
    'M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z',
    'M11 18h2',
  ]);

  const PiumaIcon(this.paths);

  final List<String> paths;
}

class PiumaIconView extends StatelessWidget {
  const PiumaIconView(this.icon, {super.key, this.size = 16, this.color});

  final PiumaIcon icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _IconPainter(icon, c),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);

  final PiumaIcon icon;
  final Color color;

  static final _cache = <PiumaIcon, List<Path>>{};

  static List<Path> _paths(PiumaIcon icon) => _cache.putIfAbsent(icon, () {
    return [for (final d in icon.paths) _parse(d)];
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in _paths(icon)) {
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}

Path _parse(String d) {
  final sink = _PathSink();
  writeSvgPathDataToPath(d, sink);
  return sink.path;
}

class _PathSink extends PathProxy {
  final path = Path();

  @override
  void close() => path.close();

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}
