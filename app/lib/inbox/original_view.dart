import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../mail/mail_source.dart';
import '../widgets/link_target.dart';
import '../widgets/links.dart';
import 'original_linux.dart';
import 'original_windows.dart';

/// Draws an original's safe HTML and hands every navigation it would make
/// to [onLink]. [OriginalView] opens one only right after the person
/// pressed on the paper ([ClickGate]); a web view that tells clicks apart
/// itself reports them with [OriginalView.clicked] instead. The height,
/// the link under the pointer and a web view that can't start go up with
/// [OriginalView.setHeight], [OriginalView.hover] and
/// [OriginalView.unavailable].
typedef OriginalPaper = Widget Function(
  String html,
  ValueChanged<String> onLink,
);

/// Set once a web view failed to start in this run: emails open in the
/// clean view from then on.
bool originalPaperFailed = false;

/// Whether a navigation follows a real press of the person's on the
/// paper: a link they clicked, not one the page started by itself (a
/// refresh, a form, a script that got past the policy).
class ClickGate {
  ClickGate({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _at;

  /// How long after a press its navigation may come.
  static const window = Duration(milliseconds: 1500);

  void pressed() => _at = _clock();

  /// Whether a press came just before; it lets one navigation through.
  bool take() {
    final at = _at;
    _at = null;
    return at != null && _clock().difference(at) <= window;
  }
}

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
    this.onUnavailable,
  });

  final Future<OriginalDoc> original;

  /// The web view couldn't start: the reader shows the clean view.
  final VoidCallback? onUnavailable;

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

  static _OriginalPaperScope? _scope(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_OriginalPaperScope>();

  /// A link the web view itself knows the person clicked (WebKitGTK's
  /// "link clicked"): it opens without [ClickGate].
  static void clicked(BuildContext context, String url) =>
      _scope(context)?.onClicked(url);

  /// The link under the pointer, or null when it left one.
  static void hover(BuildContext context, String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    LinkTarget.show(
      context,
      uri != null && isMailLinkAllowed(uri) ? url : null,
    );
  }

  /// The web view couldn't start (no WebView2, say): the clean view.
  static void unavailable(BuildContext context) =>
      _scope(context)?.onUnavailable();

  /// The person activated a link from the keyboard (Enter or Space, as
  /// the web view saw it, not as a page script made it up): the next
  /// navigation counts as theirs, as after a press ([ClickGate]).
  static void keyPressed(BuildContext context) => _scope(context)?.onKey();

  /// A long press (or a right click) on a link: where it really goes,
  /// to open or copy ([showLinkTarget]), as hovering shows on a desktop.
  static void pressed(BuildContext context, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !isMailLinkAllowed(uri)) return;
    _scope(context)?.onPress(url);
  }

  @override
  State<OriginalView> createState() => _OriginalViewState();
}

class _OriginalViewState extends State<OriginalView> {
  double? _height;
  final _gate = ClickGate();
  OriginalDoc? _doc;

  void _open(String link, {required bool clicked}) {
    final doc = _doc;
    if (doc == null || !mounted) return;
    if (!clicked && !_gate.take()) return;
    widget.onLink(link, doc.suspicious[link]);
  }

  void _unavailable() {
    originalPaperFailed = true;
    widget.onUnavailable?.call();
  }

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
        onClicked: (link) => _open(link, clicked: true),
        onUnavailable: _unavailable,
        onKey: _gate.pressed,
        onPress: (link) => showLinkTarget(
          context,
          link,
          onOpen: () => _open(link, clicked: true),
        ),
        child: FutureBuilder<OriginalDoc>(
          future: widget.original,
          builder: (context, snap) {
            final doc = snap.data;
            if (doc == null || paper == null) {
              return const SizedBox.expand();
            }
            _doc = doc;
            // Every press on the paper, seen before the web view gets it.
            return MouseRegion(
              onExit: (_) => LinkTarget.show(context, null),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _gate.pressed(),
                onPointerUp: (_) => _gate.pressed(),
                child: paper(doc.html, (link) => _open(link, clicked: false)),
              ),
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
  const _OriginalPaperScope({
    required this.onHeight,
    required this.onClicked,
    required this.onUnavailable,
    required this.onKey,
    required this.onPress,
    required super.child,
  });

  final ValueChanged<double> onHeight;
  final ValueChanged<String> onClicked;
  final VoidCallback onUnavailable;
  final VoidCallback onKey;
  final ValueChanged<String> onPress;

  @override
  bool updateShouldNotify(_OriginalPaperScope old) => old.onHeight != onHeight;
}

/// The system web view: the email's own scripts are stripped and blocked
/// by the page's Content-Security-Policy (`default-src 'none'`), while
/// the host watches the document's height so the reader scrolls as one
/// page, and every navigation is stopped and handed to the app.
///
/// JavaScript stays on only because the height can't be measured without
/// it: the email's own scripts can't run under the policy, and the
/// channel back to the app takes nothing but two numbers.
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
  if (window.PiumaHover) {
    document.addEventListener('mouseover', function (e) {
      var a = e.target.closest && e.target.closest('a[href]');
      PiumaHover.postMessage(a ? a.href : '');
    }, true);
  }
  // A long press on a link (a right click with a mouse): the app shows
  // where it goes, in place of the web view's own menu.
  if (window.PiumaPress) {
    document.addEventListener('contextmenu', function (e) {
      var a = e.target.closest && e.target.closest('a[href]');
      if (!a || !e.isTrusted) return;
      e.preventDefault();
      PiumaPress.postMessage(a.href);
    }, true);
  }
  // Enter or Space on a link, pressed by the person (a script's made-up
  // event isn't trusted): its navigation may open, as after a click.
  if (window.PiumaKey) {
    document.addEventListener('keydown', function (e) {
      if (!e.isTrusted || (e.key !== 'Enter' && e.key !== ' ')) return;
      var a = e.target.closest && e.target.closest('a[href]');
      if (a) PiumaKey.postMessage('1');
    }, true);
  }
})();
''';

/// The paper's height in the app's points for a report of [_watchHeight]
/// ("height,viewportWidth" in CSS pixels), drawn [width] points wide.
/// The original asks for a 600-pixel viewport, so on a phone the page is
/// scaled down to fit and its CSS pixels are not the app's points.
@visibleForTesting
double? paperHeight(String report, double width) {
  // Two numbers and nothing else.
  if (!RegExp(r'^\d{1,7}(\.\d{1,4})?,\d{1,6}(\.\d{1,4})?$').hasMatch(report)) {
    return null;
  }
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
    ..addJavaScriptChannel('PiumaHover', onMessageReceived: _onHover)
    ..addJavaScriptChannel(
      'PiumaPress',
      onMessageReceived: (m) {
        final url = m.message;
        if (mounted && url.isNotEmpty && url.length <= 2048) {
          OriginalView.pressed(context, url);
        }
      },
    )
    ..addJavaScriptChannel(
      'PiumaKey',
      onMessageReceived: (_) {
        if (mounted) OriginalView.keyPressed(context);
      },
    )
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) => _watch(),
        onNavigationRequest: (request) {
          final url = request.url;
          // The document itself, loaded from the string.
          if (url == 'about:blank' || url.startsWith('data:')) {
            return NavigationDecision.navigate;
          }
          // A frame inside the email navigating is never the person's.
          if (request.isMainFrame) widget.onLink(url);
          return NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame ?? false) {
            if (mounted) OriginalView.unavailable(context);
          }
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

  /// Only shown, never opened: at most an address of a link.
  void _onHover(JavaScriptMessage message) {
    if (!mounted) return;
    final url = message.message;
    OriginalView.hover(context, url.isEmpty || url.length > 2048 ? null : url);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _width = constraints.maxWidth;
      return WebViewWidget(controller: _controller);
    },
  );
}
