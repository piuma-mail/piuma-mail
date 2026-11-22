import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

/// The tallest a paper grows, in points, before the rest of the email
/// scrolls inside the web view instead of in the reader.
///
/// On Windows WebView2 reaches the app as a Direct3D 11 texture as tall as
/// the paper ([WindowsPaper]); past 16384 pixels, the most Direct3D 11
/// allows, the system's capture of the web view crashes the whole app
/// (feedback #22: a long email on a 4K screen at 150%). The paper stays
/// a little under that many pixels, whatever the screen's scale.
double paperMaxHeight(TargetPlatform platform, double devicePixelRatio) {
  if (platform != TargetPlatform.windows) return _tallestPaper;
  const pixels = 16000.0;
  final scale = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  return math.min(_tallestPaper, pixels / scale);
}

/// The tallest a paper grows anywhere, in points.
const _tallestPaper = 20000.0;

/// How far, in points, a web view at [offset] of the [extent] it can
/// scroll can still go in the direction of [dy] (positive: down); 0 when
/// it is at that end, or when the page fits its paper ([paperMaxHeight]
/// not reached).
double innerScrollRoom(double offset, double extent, double dy) {
  if (extent <= 1 || dy == 0) return 0;
  final room = dy > 0 ? extent - offset : offset;
  return room > 1 ? room : 0;
}

/// Whether a wheel turn of [dy] points (positive: down) scrolls a web view
/// that is at [offset] of the [extent] it can scroll, rather than the
/// reader around it, as nested scrolling works in a browser: the inner
/// page first, then the outer one once the inner can't go further. A page
/// that fits its paper ([paperMaxHeight] not reached) never takes it.
bool innerScrollTakes(double offset, double extent, double dy) =>
    innerScrollRoom(offset, extent, dy) > 0;

/// Where a web view last said it was scrolled ([offset] of the [extent]
/// it can scroll, in points) and the last scroll command of
/// [InnerScrollFirst] it had applied by then ([ack]: the command's
/// sequence number, 0 before any).
@immutable
class InnerScrollPosition {
  const InnerScrollPosition(this.offset, this.extent, [this.ack = 0]);

  final double offset;
  final double extent;
  final int ack;

  /// How far it can still go in the direction of [dy] ([innerScrollRoom]).
  double room(double dy) => innerScrollRoom(offset, extent, dy);
}

/// Where a web view is during a touchpad pan, as far as the app knows:
/// its position comes back a little after each step of the pan, so the
/// steps it hasn't acknowledged yet ([InnerScrollPosition.ack]) are
/// added to the last position it reported.
///
/// Each step stops at the page's ends as the page does, worked out with
/// the extent of the report at hand: a page that grows or shrinks during
/// the gesture (an image loading) is predicted with its new extent, never
/// one it had when a step was sent.
class InnerPanTracker {
  /// The most steps kept one by one while they wait for an
  /// acknowledgement; past that the oldest half is set aside as runs
  /// (consecutive steps the same way, added up), so a gesture with no
  /// reports at all stays cheap.
  static const maxPending = 64;

  double? _base;
  int _baseSeq = 0;
  // Steps set aside after [_base], no longer acknowledged one by one:
  // runs that go each way in turn. Adding up steps that go the same way
  // stops at the same place whatever the extent, so they are worked out
  // again with every report's extent.
  final _runs = <double>[];
  final _pending = <(int, double)>[];

  /// Steps sent and not acknowledged yet, one by one.
  int get pending => _pending.length;

  /// A new gesture: nothing predicted until the next report.
  void reset() {
    _base = null;
    _baseSeq = 0;
    _runs.clear();
    _pending.clear();
  }

  /// Where the web view is now: its [report], or what came before it when
  /// the report is older than what this already knows (out of order),
  /// moved by every step it hasn't acknowledged, each stopping at the
  /// page's ends ([InnerScrollPosition.extent]) as the page does.
  double offset(InnerScrollPosition report) {
    if (_base == null || report.ack >= _baseSeq) {
      _base = report.offset;
      _baseSeq = report.ack;
      _runs.clear();
      _pending.removeWhere((step) => step.$1 <= report.ack);
    }
    final folded = _fold(_base!, _runs, report.extent);
    return _fold(folded, _pending.map((s) => s.$2), report.extent);
  }

  /// Step [seq] of [dy] points (positive: down) went to the web view,
  /// which can scroll [extent] as far as the app knows.
  void sent(int seq, double dy, double extent) {
    _pending.add((seq, dy));
    if (_pending.length <= maxPending) return;
    final old = _pending.sublist(0, maxPending ~/ 2);
    _pending.removeRange(0, old.length);
    _base ??= 0;
    _baseSeq = old.last.$1;
    for (final (_, d) in old) {
      if (_runs.isNotEmpty && (_runs.last >= 0) == (d >= 0)) {
        _runs.last += d;
      } else {
        _runs.add(d);
      }
    }
    // Only a pan turning back and forth that often with no report at all
    // gets here: the oldest runs go into the base with the extent known
    // now, an estimate the next report replaces.
    if (_runs.length > maxPending) {
      final first = _runs.sublist(0, maxPending ~/ 2);
      _runs.removeRange(0, first.length);
      _base = _fold(_base!, first, extent);
    }
  }

  static double _fold(double from, Iterable<double> steps, double extent) {
    final max = math.max(0.0, extent);
    return steps.fold(from.clamp(0.0, max), (o, d) => (o + d).clamp(0.0, max));
  }
}

/// A key that scrolls a page: Page Down and Space, Page Up and
/// Shift+Space, Home and End.
enum InnerScrollKey {
  pageDown(1),
  pageUp(-1),
  top(-1),
  bottom(1);

  const InnerScrollKey(this.dy);

  /// Which way it scrolls: positive is down.
  final double dy;
}

/// Scrolls the web view in [child] before the reader around it, as nested
/// pages scroll in a browser, once the email is longer than its paper
/// ([paperMaxHeight]):
///
/// * a wheel turn over it goes to the web view while it can still move
///   that way ([innerScrollTakes]), and to the reader once it can't;
/// * a precision touchpad's pan goes to [onPanStep], step by step, and
///   the reader gets only the part the web view can't take any more. The
///   pan's events don't reach [child] (the web view's own pan handling):
///   [onPanStep] moves the page itself, at once, and acknowledges the step
///   in the same go, so the position the page reports always includes
///   every step it acknowledges;
/// * Page Down, Page Up, Space, Shift+Space, Home and End, while the
///   pointer is over the web view or it has the focus, go to [onKey] while
///   the web view can move that way, and scroll the reader after.
///
/// Every scroll command for the web view carries a sequence number, and
/// the web view's [position] says the last one it had applied, so a pan
/// knows which of its steps the reported position already covers
/// ([InnerPanTracker]).
///
/// Without this a page longer than its paper scrolled together with the
/// reader, twice as fast (feedback #22, #116). A page that fits its paper
/// (no room either way) leaves everything to the reader, as before.
class InnerScrollFirst extends StatefulWidget {
  const InnerScrollFirst({
    super.key,
    required this.position,
    this.onKey,
    this.onPanStep,
    required this.child,
  });

  /// Where the web view last said it was ([InnerScrollPosition]).
  final InnerScrollPosition Function() position;

  /// Scrolls the web view for a key, as command `seq`; it is called only
  /// while the web view can move that way.
  final void Function(InnerScrollKey key, int seq)? onKey;

  /// Scrolls the web view by a touchpad pan's step, as command `seq`:
  /// `delta` points, positive down and right. The web view must apply it
  /// at once, not animated, and acknowledge `seq` with the position it got
  /// to: [child] doesn't see the pan.
  final void Function(int seq, Offset delta)? onPanStep;
  final Widget child;

  @override
  State<InnerScrollFirst> createState() => _InnerScrollFirstState();
}

class _InnerScrollFirstState extends State<InnerScrollFirst> {
  final _focus = FocusNode(debugLabel: 'inner page', skipTraversal: true);
  bool _over = false;

  // The touchpad pan in progress: the part of it that goes to the reader.
  Drag? _drag;
  VelocityTracker? _velocity;
  bool _lastToReader = false;
  final _tracker = InnerPanTracker();
  // The pan this scrolls the web view for: its events don't reach the web
  // view's own handling.
  int? _panPointer;
  // The last scroll command's number; the web view echoes it back.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    _drag?.cancel();
    _drag = null;
    _focus.dispose();
    super.dispose();
  }

  double _room(double dy) => widget.position().room(dy);

  bool get _scrolls => _room(1) > 0 || _room(-1) > 0;

  void _panStart(PointerPanZoomStartEvent event) {
    _drag?.cancel();
    _drag = null;
    _velocity = VelocityTracker.withKind(PointerDeviceKind.trackpad)
      ..addPosition(event.timeStamp, Offset.zero);
    _lastToReader = false;
    _tracker.reset();
    _panPointer = event.pointer;
  }

  void _panUpdate(PointerPanZoomUpdateEvent event) {
    _velocity?.addPosition(event.timeStamp, event.pan);
    // The fingers move the page: up is a scroll down.
    final dx = -event.panDelta.dx;
    final dy = -event.panDelta.dy;
    if (dx == 0 && dy == 0) return;
    final position = widget.position();
    final offset = _tracker.offset(position);
    final extent = position.extent;
    final left = dy > 0 ? extent - offset : offset;
    final room = left > 1 ? left : 0.0;
    final inner = math.min(dy.abs(), room);
    final seq = ++_seq;
    _tracker.sent(seq, dy, extent);
    widget.onPanStep?.call(seq, Offset(dx, dy));
    final rest = dy.abs() - inner;
    if (kDebugMode && innerScrollLog) {
      debugPrint(
        'inner pan: seq $seq, ack ${position.ack}, '
        'reported ${position.offset.toStringAsFixed(1)} of '
        '${extent.toStringAsFixed(1)}, '
        'predicted ${offset.toStringAsFixed(1)}, '
        'dy ${dy.toStringAsFixed(1)}, to reader ${rest.toStringAsFixed(1)}',
      );
    }
    if (dy == 0) return;
    _lastToReader = rest > 0;
    if (rest <= 0) return;
    final delta = -dy.sign * rest;
    final drag = _drag ??= Scrollable.maybeOf(context, axis: Axis.vertical)
        ?.position
        .drag(
          DragStartDetails(
            globalPosition: event.position,
            localPosition: event.localPosition,
            kind: PointerDeviceKind.trackpad,
          ),
          () => _drag = null,
        );
    drag?.update(
      DragUpdateDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        delta: Offset(0, delta),
        primaryDelta: delta,
      ),
    );
  }

  void _panEnd() {
    _panPointer = null;
    final drag = _drag;
    _drag = null;
    if (drag == null) return;
    // The reader glides on only when it was the one moving at the end.
    final v = _lastToReader
        ? _velocity?.getVelocity().pixelsPerSecond.dy ?? 0.0
        : 0.0;
    drag.end(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, v)),
        primaryVelocity: v,
      ),
    );
  }

  /// The page key [event] is, when it may scroll the web view or, at the
  /// web view's end that way, the reader: not a key a text field or a
  /// focused button keeps, and not with a dialog over the reader.
  InnerScrollKey? _pageKey(KeyEvent event) {
    if (event is KeyUpEvent || widget.onKey == null || !mounted) return null;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed) {
      return null;
    }
    final space = event.logicalKey == LogicalKeyboardKey.space;
    final key = switch (event.logicalKey) {
      LogicalKeyboardKey.pageDown => InnerScrollKey.pageDown,
      LogicalKeyboardKey.pageUp => InnerScrollKey.pageUp,
      LogicalKeyboardKey.space when keys.isShiftPressed =>
        InnerScrollKey.pageUp,
      LogicalKeyboardKey.space => InnerScrollKey.pageDown,
      LogicalKeyboardKey.home => InnerScrollKey.top,
      LogicalKeyboardKey.end => InnerScrollKey.bottom,
      _ => null,
    };
    if (key == null) return null;
    // A text field keeps its keys, and a focused button its Space.
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null) {
      if (focus.widget is EditableText ||
          focus.findAncestorWidgetOfExactType<EditableText>() != null) {
        return null;
      }
      if (space && !_focus.hasFocus) {
        final activate = Actions.maybeFind<ActivateIntent>(focus);
        if (activate != null && activate.isEnabled(const ActivateIntent())) {
          return null;
        }
      }
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return null;
    return key;
  }

  /// Sends [key] to the web view when it can still move that way.
  bool _toPage(InnerScrollKey key) {
    if (_room(key.dy) <= 0) return false;
    widget.onKey!(key, ++_seq);
    return true;
  }

  /// With the focus on the web view (it was clicked): before the reader's
  /// own page keys, which sit further up and take the key at the web
  /// view's end.
  ///
  /// Not verified on Windows yet: webview_windows 0.4.0 forwards a click
  /// to WebView2 (`SendMouseInput`) and never forwards keys, and typing in
  /// a page's field works there, so WebView2 most likely takes the
  /// system's keyboard focus on a click. Then the keys go straight to it
  /// and never reach Flutter: the page scrolls itself, this never runs,
  /// the reader doesn't take over at the page's end, and Tab may stay
  /// inside the page (the plugin doesn't handle WebView2's
  /// MoveFocusRequested). This path stays right for when Flutter does get
  /// the keys; the PR's Windows checklist covers the rest.
  ///
  /// At the web view's end that way the reader scrolls here too: Flutter's
  /// own shortcuts on Windows and Linux scroll it for Page Down and Page
  /// Up only, not for Home, End, Space or Shift+Space.
  KeyEventResult _focusedKey(FocusNode node, KeyEvent event) {
    final key = _pageKey(event);
    if (key == null) return KeyEventResult.ignored;
    return _toPage(key) || _scrollReader(key)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// With only the pointer over the web view. Returning true here doesn't
  /// keep the key from the focus, so this takes it only when the focus has
  /// nothing the key would scroll: not inside the reader or any other
  /// list (the message list, search results, a long menu), and not in an
  /// open menu. Otherwise the focus keeps it, as before, and only one
  /// thing scrolls. At the web view's end that way the reader takes the
  /// key, as it does from the focused web view.
  bool _key(KeyEvent event) {
    if (!_over || _focus.hasFocus) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (_verticalScrollable(focus) != null ||
            (MenuController.maybeOf(focus)?.isOpen ?? false))) {
      return false;
    }
    final key = _pageKey(event);
    if (key == null) return false;
    return _toPage(key) || _scrollReader(key);
  }

  /// Scrolls the reader around the web view for [key], as its own page
  /// keys do (a page is 80% of what it shows); false when it can't move
  /// that way.
  bool _scrollReader(InnerScrollKey key) {
    final reader = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (reader == null || !reader.hasContentDimensions) return false;
    final to = switch (key) {
      InnerScrollKey.pageDown => reader.pixels + reader.viewportDimension * .8,
      InnerScrollKey.pageUp => reader.pixels - reader.viewportDimension * .8,
      InnerScrollKey.top => reader.minScrollExtent,
      InnerScrollKey.bottom => reader.maxScrollExtent,
    }.clamp(reader.minScrollExtent, reader.maxScrollExtent);
    if ((to - reader.pixels).abs() < 1) return false;
    unawaited(
      reader.moveTo(
        to,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
      ),
    );
    return true;
  }

  static ScrollableState? _verticalScrollable(BuildContext context) {
    var s = context.findAncestorStateOfType<ScrollableState>();
    while (s != null && s.position.axis != Axis.vertical) {
      s = s.context.findAncestorStateOfType<ScrollableState>();
    }
    return s;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _focusedKey,
    child: MouseRegion(
      opaque: false,
      onEnter: (_) => _over = true,
      onExit: (_) => _over = false,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _focus.requestFocus(),
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          if (_room(event.scrollDelta.dy) <= 0) return;
          // The first to register wins: the reader's Scrollable, further
          // up, lets this one go.
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
        },
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            _InnerPan: GestureRecognizerFactoryWithHandlers<_InnerPan>(
              () => _InnerPan(),
              (pan) => pan
                ..claims = (() => _scrolls)
                ..onStart = _panStart
                ..onUpdate = _panUpdate
                ..onEnd = _panEnd,
            ),
          },
          child: _PanShield(
            keeps: (pointer) => pointer == _panPointer,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

/// Logs each touchpad pan step over a long page ([InnerScrollFirst]) and
/// each position the page reports, in debug builds run with
/// `--dart-define=PIUMA_SCROLL_LOG=true`.
const innerScrollLog = bool.fromEnvironment('PIUMA_SCROLL_LOG');

/// Keeps a pan's updates from [child] while [keeps] says the pan is
/// [InnerScrollFirst]'s: webview_windows' own widget forwards every
/// pan/zoom update to WebView2 as a wheel turn, separately from the
/// scripts that report the page's position, and that is what this
/// replaces. Everything else (clicks, hover, the wheel, the pan's start
/// and end) reaches [child] as usual.
class _PanShield extends SingleChildRenderObjectWidget {
  const _PanShield({required this.keeps, super.child});

  final bool Function(int pointer) keeps;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPanShield(keeps);

  @override
  void updateRenderObject(BuildContext context, _RenderPanShield render) =>
      render.keeps = keeps;
}

class _RenderPanShield extends RenderProxyBox {
  _RenderPanShield(this.keeps);

  bool Function(int pointer) keeps;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    // The child's targets, seen from here, each behind a filter. Mouse
    // regions go through as they are: the mouse tracker looks for them in
    // the result and their pointer events don't matter.
    final inner = BoxHitTestResult();
    final hit = child.hitTest(inner, position: position);
    for (final entry in inner.path) {
      if (entry.target is MouseTrackerAnnotation) {
        result.add(entry);
      } else {
        result.add(HitTestEntry(_Shielded(entry, this)));
      }
    }
    return hit;
  }
}

class _Shielded implements HitTestTarget {
  _Shielded(this.entry, this.shield);

  final HitTestEntry entry;
  final _RenderPanShield shield;

  @override
  void handleEvent(PointerEvent event, HitTestEntry _) {
    if (event is PointerPanZoomUpdateEvent && shield.keeps(event.pointer)) {
      return;
    }
    // The event comes transformed to the shield; on to the target.
    final toTarget = entry.transform;
    final toShield = event.transform;
    entry.target.handleEvent(
      toTarget == null || toShield == null
          ? event
          : event.transformed(toTarget.multiplied(toShield)),
      entry,
    );
  }
}

/// Takes a touchpad's pan away from the reader's own drag over a web view
/// that scrolls ([InnerScrollFirst]); the web view still sees the pan's
/// events, and the reader gets only what it can't take.
class _InnerPan extends OneSequenceGestureRecognizer {
  _InnerPan() : super(supportedDevices: {PointerDeviceKind.trackpad});

  bool Function() claims = () => false;
  ValueChanged<PointerPanZoomStartEvent> onStart = (_) {};
  ValueChanged<PointerPanZoomUpdateEvent> onUpdate = (_) {};
  VoidCallback onEnd = () {};

  @override
  bool isPointerAllowed(PointerDownEvent event) => false;

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      claims() && super.isPointerPanZoomAllowed(event);

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      onUpdate(event);
    } else if (event is PointerPanZoomEndEvent) {
      onEnd();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    onEnd();
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'inner page pan';
}

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
    widget.onLink(link, _suspicious(doc, link));
  }

  /// The text a suspicious link shows, by its address as the engine read
  /// it from the `href`; the web view hands back the browser's form of it
  /// (`a.href`: a trailing slash, another case, percent-encoding), so both
  /// are compared normalized.
  String? _suspicious(OriginalDoc doc, String link) {
    if (doc.suspicious[link] case final shown?) return shown;
    final wanted = normalizeLink(link);
    for (final e in doc.suspicious.entries) {
      if (normalizeLink(e.key) == wanted) return e.value;
    }
    return null;
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
    final clamped = height.clamp(120.0, _tallestPaper);
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
    // Kept under what the screen's web view can draw, also after the
    // window moves to a screen with another scale.
    final measured = _height;
    final height = measured == null
        ? null
        : math.min(
            measured,
            paperMaxHeight(
              defaultTargetPlatform,
              MediaQuery.devicePixelRatioOf(context),
            ),
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
        height: height ?? fallback,
        child: _EdgeToEdge(child: sheet),
      );
    }
    const pad = 24.0;
    return Container(
      height: height != null ? height + pad * 2 : fallback,
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
