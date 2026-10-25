import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart';

import '../design/tokens.g.dart';
import '../dev_copy.dart';
import 'original_view.dart';

/// The original on Windows, in WebView2. It can't turn JavaScript off or
/// stop navigations the way the other web views do, so the page's policy
/// keeps its own scripts from running and a script of ours, which the
/// policy doesn't cover, hands every link and the document's height to
/// the app instead.
class WindowsPaper extends StatefulWidget {
  const WindowsPaper({super.key, required this.html, required this.onLink});

  final String html;
  final ValueChanged<String> onLink;

  @override
  State<WindowsPaper> createState() => _WindowsPaperState();
}

/// WebView2 keeps its profile in the app's folder, once for the process.
Future<void>? _environment;

Future<void> _ready() => _environment ??= () async {
  final dir = await appFolder();
  await WebviewController.initializeEnvironment(
    userDataPath: '${dir.path}\\webview',
  );
}();

/// Every click on a link goes to the app, links inside the page
/// (`#section`) still scroll, and the document's height is reported so
/// the outer reader scrolls as a single page.
const _links =
    '''
function _reportHeight() {
  var b = document.body ? document.body.scrollHeight : 0;
  var d = document.documentElement ? document.documentElement.scrollHeight : 0;
  var h = Math.max(b, d);
  if (h > 0) window.chrome.webview.postMessage('#height:' + h);
}
document.addEventListener('click', function (e) {
  var a = e.target.closest && e.target.closest('a[href]');
  if (!a) return;
  var href = a.href;
  if (href.indexOf('about:') === 0) return;
  e.preventDefault();
  window.chrome.webview.postMessage(href);
}, true);
document.addEventListener('auxclick', function (e) {
  if (e.target.closest && e.target.closest('a[href]')) e.preventDefault();
}, true);
document.addEventListener('DOMContentLoaded', function () {
  var s = document.createElement('style');
  s.textContent = $_scrollbar;
  document.head.appendChild(s);
  _reportHeight();
  if (window.ResizeObserver && document.body) {
    new ResizeObserver(_reportHeight).observe(document.body);
  }
});
window.addEventListener('load', _reportHeight);
''';

/// A thin scrollbar like the app's own, not Windows' old one with arrows.
/// The page's policy allows inline styles.
const _scrollbar = '''`
::-webkit-scrollbar { width: 12px; height: 12px; background: transparent; }
::-webkit-scrollbar-button { display: none; }
::-webkit-scrollbar-thumb { background: rgba(0,0,0,.28); border-radius: 6px;
  border: 3px solid transparent; background-clip: content-box; }
::-webkit-scrollbar-thumb:hover { background-color: rgba(0,0,0,.45); }
::-webkit-scrollbar-corner { background: transparent; }
`''';

class _WindowsPaperState extends State<WindowsPaper> {
  final _controller = WebviewController();
  final _subs = <StreamSubscription<Object?>>[];
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      await _ready();
      await _controller.initialize();
      if (!mounted) return;
      await _controller.setBackgroundColor(PiumaColors.light.page);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.setCacheDisabled(true);
      await _controller.addScriptToExecuteOnDocumentCreated(_links);
      _subs
        ..add(
          _controller.webMessage.listen((m) {
            if (m is! String) return;
            if (m.startsWith('#height:')) {
              final h = double.tryParse(m.substring('#height:'.length));
              if (mounted && h != null) OriginalView.setHeight(context, h);
              return;
            }
            widget.onLink(m);
          }),
        )
        // Anything that gets past the script anyway: back to the email.
        ..add(
          _controller.url.listen((url) {
            if (url.isEmpty ||
                url.startsWith('about:') ||
                url.startsWith('data:')) {
              return;
            }
            _controller.loadStringContent(widget.html);
            widget.onLink(url);
          }),
        );
      await _controller.loadStringContent(widget.html);
      if (mounted) setState(() => _shown = true);
    } catch (_) {
      // No WebView2 on this PC: the paper stays white.
    }
  }

  @override
  void didUpdateWidget(WindowsPaper old) {
    super.didUpdateWidget(old);
    if (_shown && old.html != widget.html) {
      _controller.loadStringContent(widget.html);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _shown ? Webview(_controller) : const SizedBox.expand();
}
