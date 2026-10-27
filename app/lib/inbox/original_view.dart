import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../mail/mail_source.dart';
import 'original_linux.dart';
import 'original_windows.dart';

/// Draws an original's safe HTML and hands every link tap to [onLink].
typedef OriginalPaper = Widget Function(
  String html,
  ValueChanged<String> onLink,
);

/// How the original is drawn: the system's web view (Android, iPhone,
/// iPad, macOS, WebView2 on Windows and WebKitGTK on Linux), nothing on
/// the web, so the button doesn't show. Tests put a stand-in here.
OriginalPaper? originalPaper = WebViewPlatform.instance != null
    ? (html, onLink) => _WebPaper(html: html, onLink: onLink)
    : !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
    ? (html, onLink) => WindowsPaper(html: html, onLink: onLink)
    : !kIsWeb && defaultTargetPlatform == TargetPlatform.linux
    ? (html, onLink) => LinuxPaper(html: html, onLink: onLink)
    : null;

/// The email as it was sent (`OriginalToApprove`, opened by default since
/// `ImagesToApprove`): the original on white paper in the middle of the
/// stage, or from edge to edge on a phone. The switch to the clean view
/// sits above it, in the reader.
///
/// Once the web view measures the document's height it calls
/// [OriginalView.setHeight], so the paper takes the email's full length
/// and only the reader scrolls vertically.
class OriginalView extends StatefulWidget {
  const OriginalView({
    super.key,
    required this.original,
    required this.onLink,
    this.phone = false,
  });

  final Future<OriginalDoc> original;

  /// A link was tapped: the address, and the text it shows when the
  /// engine found it suspicious.
  final void Function(String link, String? shown) onLink;
  final bool phone;

  /// Email designs are made for this width, or a little more.
  static const paperWidth = 680.0;

  /// Reports the rendered document height from inside [OriginalPaper], so
  /// the paper expands to fit the whole email without an inner vertical
  /// scroll.
  static void setHeight(BuildContext context, double height) {
    if (!height.isFinite || height <= 0) return;
    context.dependOnInheritedWidgetOfExactType<_OriginalPaperScope>()?.onHeight(
      height,
    );
  }

  @override
  State<OriginalView> createState() => _OriginalViewState();
}

class _OriginalViewState extends State<OriginalView> {
  double? _height;

  @override
  void didUpdateWidget(OriginalView old) {
    super.didUpdateWidget(old);
    if (old.original != widget.original) _height = null;
  }

  void _setHeight(double height) {
    final clamped = height.clamp(120.0, 20000.0);
    if (_height != null && (_height! - clamped).abs() < 1) return;
    if (mounted) setState(() => _height = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final paper = originalPaper;
    final fallback = (size.height * (widget.phone ? 0.72 : 0.78)).clamp(
      360.0,
      1400.0,
    );
    final sheet = ColoredBox(
      color: PiumaColors.light.page,
      child: _OriginalPaperScope(
        onHeight: _setHeight,
        child: FutureBuilder<OriginalDoc>(
          future: widget.original,
          builder: (context, snap) {
            final doc = snap.data;
            if (doc == null || paper == null) {
              return const SizedBox.expand();
            }
            return paper(
              doc.html,
              (link) => widget.onLink(link, doc.suspicious[link]),
            );
          },
        ),
      ),
    );
    // On a phone the paper runs from edge to edge of the screen, with no
    // stage around it (feedback #17, variant B approved by Matteo).
    if (widget.phone) {
      return SizedBox(
        height: _height ?? fallback,
        child: _EdgeToEdge(child: sheet),
      );
    }
    const pad = 24.0;
    return Container(
      height: _height != null ? _height! + pad * 2 : fallback,
      padding: const EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: c.stage,
        borderRadius: BorderRadius.circular(PiumaRadius.card),
      ),
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OriginalView.paperWidth),
        child: SizedBox.expand(child: sheet),
      ),
    );
  }
}

/// Widens [child] past the reader's side margins to the edges of the
/// scrolling view it sits in, so the email fills the phone's width.
class _EdgeToEdge extends StatefulWidget {
  const _EdgeToEdge({required this.child});

  final Widget child;

  @override
  State<_EdgeToEdge> createState() => _EdgeToEdgeState();
}

class _EdgeToEdgeState extends State<_EdgeToEdge> {
  double _left = 0;
  double _right = 0;

  void _measure(Duration _) {
    if (!mounted) return;
    final box = context.findRenderObject();
    final outer = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || outer is! RenderBox) return;
    if (!box.hasSize || !outer.hasSize) return;
    final left = box.localToGlobal(Offset.zero, ancestor: outer).dx;
    final right = outer.size.width - left - box.size.width;
    if (left < 0 || right < 0) return;
    if ((left - _left).abs() < 0.5 && (right - _right).abs() < 0.5) return;
    setState(() {
      _left = left;
      _right = right;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      WidgetsBinding.instance.addPostFrameCallback(_measure);
      final width = box.maxWidth + _left + _right;
      return OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: width,
        maxWidth: width,
        child: Transform.translate(
          offset: Offset(-_left, 0),
          child: widget.child,
        ),
      );
    },
  );
}

class _OriginalPaperScope extends InheritedWidget {
  const _OriginalPaperScope({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  bool updateShouldNotify(_OriginalPaperScope old) => old.onHeight != onHeight;
}

/// The system web view: the email's own scripts are stripped and blocked
/// by the page's Content-Security-Policy (`default-src 'none'`), while
/// the host watches the document's height so the reader scrolls as one
/// page, and every navigation is stopped and handed to the app.
class _WebPaper extends StatefulWidget {
  const _WebPaper({required this.html, required this.onLink});

  final String html;
  final ValueChanged<String> onLink;

  @override
  State<_WebPaper> createState() => _WebPaperState();
}

/// Reports the document's height and the viewport's width, both in CSS
/// pixels, now and whenever they change: images decoding, fonts, a
/// layout settling after the page has finished loading (feedback #17).
/// Scripts the host runs are not bound by the page's policy.
const _watchHeight = '''
(function () {
  if (window._piumaHeight) return;
  window._piumaHeight = true;
  function report() {
    var b = document.body ? document.body.scrollHeight : 0;
    var d = document.documentElement ? document.documentElement.scrollHeight : 0;
    var h = Math.max(b, d);
    if (h > 0) PiumaPaper.postMessage(h + ',' + window.innerWidth);
  }
  report();
  if (window.ResizeObserver) {
    var o = new ResizeObserver(report);
    o.observe(document.documentElement);
    if (document.body) o.observe(document.body);
  }
  window.addEventListener('load', report);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(report);
})();
''';

/// The paper's height in the app's points for a report of [_watchHeight]
/// ("height,viewportWidth" in CSS pixels), drawn [width] points wide.
/// The original asks for a 600-pixel viewport, so on a phone the page is
/// scaled down to fit and its CSS pixels are not the app's points.
@visibleForTesting
double? paperHeight(String report, double width) {
  final parts = report.split(',');
  if (parts.length != 2) return null;
  final height = double.tryParse(parts[0]);
  final viewport = double.tryParse(parts[1]);
  if (height == null || !height.isFinite || height <= 0) return null;
  if (viewport == null || !viewport.isFinite || viewport <= 0) return height;
  if (!width.isFinite || width <= 0) return height;
  return height * width / viewport;
}

/// Android's web view ignores a page's viewport unless asked, so the
/// original's 600-pixel width would be cut at the phone's width.
WebViewController _wide(WebViewController controller) {
  final platform = controller.platform;
  if (platform is AndroidWebViewController) platform.setUseWideViewPort(true);
  return controller;
}

class _WebPaperState extends State<_WebPaper> {
  double _width = 0;

  late final WebViewController _controller = _wide(WebViewController())
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('PiumaPaper', onMessageReceived: _onReport)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) => _watch(),
        onNavigationRequest: (request) {
          final url = request.url;
          // The document itself, loaded from the string.
          if (url == 'about:blank' || url.startsWith('data:')) {
            return NavigationDecision.navigate;
          }
          widget.onLink(url);
          return NavigationDecision.prevent;
        },
      ),
    )
    ..loadHtmlString(widget.html);

  @override
  void initState() {
    super.initState();
    // WebKit on macOS can't make its view see-through, so the plugin
    // throws there; its web view is already white paper.
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      _controller.setBackgroundColor(PiumaColors.light.page);
    }
  }

  @override
  void didUpdateWidget(_WebPaper old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) _controller.loadHtmlString(widget.html);
  }

  Future<void> _watch() async {
    try {
      await _controller.runJavaScript(_watchHeight);
    } catch (_) {}
  }

  void _onReport(JavaScriptMessage message) {
    if (!mounted) return;
    final h = paperHeight(message.message, _width);
    if (h != null) OriginalView.setHeight(context, h);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      return WebViewWidget(controller: _controller);
    },
  );
}
