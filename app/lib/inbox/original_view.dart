import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
/// stage. The switch to the clean view sits above it, in the reader.
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
    final pad = widget.phone ? 10.0 : 24.0;
    final fallback = (size.height * (widget.phone ? 0.72 : 0.78)).clamp(
      360.0,
      1400.0,
    );
    return Container(
      height: _height != null ? _height! + pad * 2 : fallback,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: c.stage,
        borderRadius: BorderRadius.circular(PiumaRadius.card),
      ),
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OriginalView.paperWidth),
        child: SizedBox.expand(
          child: ColoredBox(
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
          ),
        ),
      ),
    );
  }
}

class _OriginalPaperScope extends InheritedWidget {
  const _OriginalPaperScope({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  bool updateShouldNotify(_OriginalPaperScope old) => old.onHeight != onHeight;
}

/// The system web view: the email's own scripts are stripped and blocked
/// by the page's Content-Security-Policy (`default-src 'none'`), while
/// the host measures the document height so the reader scrolls as one
/// page, and every navigation is stopped and handed to the app.
class _WebPaper extends StatefulWidget {
  const _WebPaper({required this.html, required this.onLink});

  final String html;
  final ValueChanged<String> onLink;

  @override
  State<_WebPaper> createState() => _WebPaperState();
}

class _WebPaperState extends State<_WebPaper> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) => _measure(),
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

  Future<void> _measure() async {
    for (final wait in const [
      Duration.zero,
      Duration(milliseconds: 60),
      Duration(milliseconds: 250),
    ]) {
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!mounted) return;
      try {
        final raw = await _controller.runJavaScriptReturningResult(
          'Math.max(document.body ? document.body.scrollHeight : 0, '
          'document.documentElement ? document.documentElement.scrollHeight : 0)',
        );
        final h = switch (raw) {
          final num n => n.toDouble(),
          final String s => double.tryParse(s.replaceAll('"', '')),
          _ => null,
        };
        if (mounted && h != null && h > 0) {
          OriginalView.setHeight(context, h);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
