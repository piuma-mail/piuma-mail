import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.g.dart';
import 'original_view.dart';

/// The original on Linux, in WebKitGTK (`linux/runner/original_paper.cc`).
/// Flutter on Linux can't draw a web view inside its own picture, so the
/// runner lays one over the window and this widget keeps it on the
/// paper's rectangle: moved with every frame the paper moves, cut to what
/// of it the reader shows, and hidden while a dialog covers the page. The
/// web view runs no JavaScript and opens nothing: every link it would
/// follow comes back to the app.
class LinuxPaper extends StatefulWidget {
  const LinuxPaper({super.key, required this.html, required this.onLink});

  final String html;
  final ValueChanged<String> onLink;

  @override
  State<LinuxPaper> createState() => _LinuxPaperState();
}

const _channel = MethodChannel('piuma/original');

/// The papers on screen in this window, by the id the runner knows.
final _papers = <int, _LinuxPaperState>{};
var _nextId = 0;
var _listening = false;

void _listen() {
  if (_listening) return;
  _listening = true;
  _channel.setMethodCallHandler((call) async {
    final args = call.arguments as Map<Object?, Object?>;
    final paper = _papers[args['id']];
    if (paper == null || !paper.mounted) return;
    if (call.method == 'link') {
      final url = args['url'];
      if (url is String) paper.widget.onLink(url);
    } else if (call.method == 'height') {
      final h = args['height'];
      if (h is num) OriginalView.setHeight(paper.context, h.toDouble());
    }
  });
  // Every frame drawn: a paper may have moved, with the reader's scroll,
  // a resize, or a layout change above it. No frame, nothing moved.
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    if (_papers.isEmpty) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final p in _papers.values.toList()) {
        p._sync();
      }
    });
  });
}

class _LinuxPaperState extends State<LinuxPaper> {
  final int _id = _nextId++;
  final _box = GlobalKey();
  Map<String, Object>? _placed;

  // Read while building, so a dialog, a resize or a new scroll area
  // above brings a frame, and with it a new place.
  bool _current = true;
  Size _window = Size.zero;
  List<ScrollableState> _scrolls = const [];

  @override
  void initState() {
    super.initState();
    _listen();
    _papers[_id] = this;
    _channel.invokeMethod<void>('open', {
      'id': _id,
      'html': widget.html,
      'background': PiumaColors.light.page.toARGB32(),
    });
    SchedulerBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(LinuxPaper old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) {
      _channel.invokeMethod<void>('load', {'id': _id, 'html': widget.html});
    }
  }

  /// Tells the runner where the paper is now, when that changed.
  void _sync() {
    if (!mounted) return;
    final place = _place();
    if (_mapEquals(place, _placed)) return;
    _placed = place;
    _channel.invokeMethod<void>('place', {'id': _id, ...place});
  }

  Map<String, Object> _place() {
    final box = _box.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || !_current) {
      return const {'visible': false};
    }
    final paper = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    // Cut to every scrolling area the paper is in, and to the window.
    var clip = Offset.zero & _window;
    for (final s in _scrolls) {
      final view = s.context.findRenderObject();
      if (view is RenderBox && view.hasSize) {
        clip = clip.intersect(
          MatrixUtils.transformRect(
            view.getTransformTo(null),
            Offset.zero & view.size,
          ),
        );
      }
    }
    clip = clip.intersect(paper);
    if (clip.width <= 0 || clip.height <= 0) return const {'visible': false};
    return {
      'visible': true,
      'x': paper.left.roundToDouble(),
      'y': paper.top.roundToDouble(),
      'width': paper.width.roundToDouble(),
      'height': paper.height.roundToDouble(),
      'clipX': clip.left.roundToDouble(),
      'clipY': clip.top.roundToDouble(),
      'clipWidth': clip.width.roundToDouble(),
      'clipHeight': clip.height.roundToDouble(),
    };
  }

  @override
  void dispose() {
    _papers.remove(_id);
    _channel.invokeMethod<void>('close', {'id': _id});
    super.dispose();
  }

  // The web view covers this box; until it shows, the paper is white.
  @override
  Widget build(BuildContext context) {
    _current = ModalRoute.isCurrentOf(context) ?? true;
    _window = MediaQuery.sizeOf(context);
    _scrolls = [
      for (
        var s = Scrollable.maybeOf(context);
        s != null;
        s = Scrollable.maybeOf(s.context)
      )
        s,
    ];
    return SizedBox.expand(key: _box);
  }
}

bool _mapEquals(Map<String, Object>? a, Map<String, Object>? b) {
  if (a == null || b == null || a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
