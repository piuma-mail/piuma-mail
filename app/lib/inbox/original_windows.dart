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
  _reportScroll();
}
// Where the page is scrolled, how far it can go, once it is longer than
// its paper (paperMaxHeight): wheel turns go to it first, and the last
// scroll command of the app it had applied by then (_piumaScrolled).
var _scrollAck = 0;
function _reportScroll() {
  var e = document.scrollingElement || document.documentElement;
  if (!e) return;
  var max = Math.max(0, e.scrollHeight - window.innerHeight);
  window.chrome.webview.postMessage('#scroll:' + Math.round(window.scrollY) +
    ',' + Math.round(max) + ',' + _scrollAck);
}
// The app's scroll command n reached the page: a key's scroll, run just
// before, or a touchpad pan's step, which came as input just before. The
// page reports once the frame has handled that input, even when it
// couldn't move (at its end), so every step gets acknowledged.
function _piumaScrolled(n) {
  window.requestAnimationFrame(function () {
    if (n > _scrollAck) _scrollAck = n;
    _reportScroll();
  });
}
window.addEventListener('scroll', _reportScroll, {passive: true});
window.addEventListener('resize', _reportScroll);
document.addEventListener('click', function (e) {
  var a = e.target.closest && e.target.closest('a[href]');
  if (!a) return;
  var href = a.href;
  if (href.indexOf('about:') === 0) return;
  e.preventDefault();
  // A click the page made up is not the person's.
  if (!e.isTrusted) return;
  // A trusted click is the person's, by the mouse or by Enter on a
  // focused link (detail 0): it opens without waiting for a press.
  window.chrome.webview.postMessage((e.detail === 0 ? '#key:' : '') + href);
}, true);
document.addEventListener('mouseover', function (e) {
  var a = e.target.closest && e.target.closest('a[href]');
  window.chrome.webview.postMessage('#hover:' + (a ? a.href : ''));
}, true);
document.addEventListener('contextmenu', function (e) {
  var a = e.target.closest && e.target.closest('a[href]');
  if (!a || !e.isTrusted) return;
  e.preventDefault();
  window.chrome.webview.postMessage('#press:' + a.href);
}, true);
document.addEventListener('mouseleave', function () {
  window.chrome.webview.postMessage('#hover:');
});
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
  var _scroll = const InnerScrollPosition(0, 0);

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
            if (m.startsWith('#scroll:')) {
              final parts = m.substring('#scroll:'.length).split(',');
              if (parts.length != 3) return;
              _scroll = InnerScrollPosition(
                double.tryParse(parts[0]) ?? 0,
                double.tryParse(parts[1]) ?? 0,
                int.tryParse(parts[2]) ?? 0,
              );
              return;
            }
            if (m.startsWith('#hover:')) {
              final url = m.substring('#hover:'.length);
              if (mounted) {
                OriginalView.hover(
                  context,
                  url.isEmpty || url.length > 2048 ? null : url,
                );
              }
              return;
            }
            if (m.startsWith('#press:')) {
              final url = m.substring('#press:'.length);
              if (mounted && url.isNotEmpty && url.length <= 2048) {
                OriginalView.pressed(context, url);
              }
              return;
            }
            if (m.startsWith('#key:')) {
              if (mounted) {
                OriginalView.keyPressed(context);
                widget.onLink(m.substring('#key:'.length));
              }
              return;
            }
            // Opens only right after the person pressed on the paper.
            widget.onLink(m);
          }),
        )
        // Anything that gets past the script anyway: back to the email,
        // and out only when it followed a press (OriginalView's gate).
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
      // No WebView2 on this PC: the email shows in the clean view.
      if (mounted) OriginalView.unavailable(context);
    }
  }

  /// Page Down and the other paging keys inside the page, once it is
  /// longer than its paper ([InnerScrollFirst]), as command [seq]: the
  /// page's own scroll reports where it got to. Only numbers go into the
  /// script.
  void _scrollKey(InnerScrollKey key, int seq) {
    final scroll = switch (key) {
      InnerScrollKey.pageDown =>
        'window.scrollBy(0, Math.round(window.innerHeight * 0.8))',
      InnerScrollKey.pageUp =>
        'window.scrollBy(0, -Math.round(window.innerHeight * 0.8))',
      InnerScrollKey.top => 'window.scrollTo(0, 0)',
      InnerScrollKey.bottom =>
        'window.scrollTo(0, (document.scrollingElement || '
            'document.documentElement).scrollHeight)',
    };
    _run('$scroll; _piumaScrolled($seq)');
  }

  /// A touchpad pan's step went to WebView2 through the plugin's own
  /// `setScrollDelta`, on this same channel just before: the page
  /// acknowledges [seq] once it handled it.
  void _panStep(int seq) => _run('_piumaScrolled($seq)');

  void _run(String script) =>
      unawaited(_controller.executeScript(script).catchError((_) => null));

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
  Widget build(BuildContext context) => _shown
      ? InnerScrollFirst(
          position: () => _scroll,
          onKey: _scrollKey,
          onPanStep: _panStep,
          child: Webview(_controller),
        )
      : const SizedBox.expand();
}
