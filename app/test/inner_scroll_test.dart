import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/original_view.dart';

/// A web view stand-in that scrolls like WebView2 under webview_windows:
/// it receives every pan and wheel event over it, stops at its ends, and
/// reports where it got to only later ([report]), with the last scroll
/// command it had applied, as the page's script does.
class _Inner {
  _Inner(this.extent);

  final double extent;
  double offset = 0;
  double reported = 0;
  int ack = 0;
  // The last command that reached it.
  int seq = 0;
  final keys = <InnerScrollKey>[];
  final steps = <int>[];

  InnerScrollPosition position() => InnerScrollPosition(reported, extent, ack);

  void scroll(double dy) => offset = (offset + dy).clamp(0, extent);

  void key(InnerScrollKey key, int seq) {
    keys.add(key);
    this.seq = seq;
  }

  void step(int seq) {
    steps.add(seq);
    this.seq = seq;
  }

  void report() {
    reported = offset;
    ack = seq;
  }
}

const _paper = ValueKey('paper');

Future<ScrollController> _pump(
  WidgetTester tester,
  _Inner inner, {
  FocusNode? readerFocus,
  Widget? side,
}) async {
  final outer = ScrollController();
  addTearDown(outer.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _reader(outer, inner, readerFocus)),
            ?side,
          ],
        ),
      ),
    ),
  );
  return outer;
}

Widget _reader(ScrollController outer, _Inner inner, FocusNode? readerFocus) =>
    ListView(
      controller: outer,
      children: [
        SizedBox(
          height: 400,
          child: InnerScrollFirst(
            position: inner.position,
            onKey: inner.key,
            onPanStep: inner.step,
            child: Listener(
              key: _paper,
              behavior: HitTestBehavior.opaque,
              onPointerPanZoomUpdate: (e) => inner.scroll(-e.panDelta.dy),
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) inner.scroll(e.scrollDelta.dy);
              },
            ),
          ),
        ),
        Focus(focusNode: readerFocus, child: const SizedBox(height: 3000)),
      ],
    );

Offset _onPaper(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(_paper)) + const Offset(100, 100);

void main() {
  test('the room left in the page, each way', () {
    expect(innerScrollRoom(0, 0, 40), 0);
    expect(innerScrollRoom(0, 1, 40), 0);
    expect(innerScrollRoom(0, 1200, 40), 1200);
    expect(innerScrollRoom(0, 1200, -40), 0);
    expect(innerScrollRoom(1000, 1200, 40), 200);
    expect(innerScrollRoom(1000, 1200, -40), 1000);
    expect(innerScrollRoom(1200, 1200, 40), 0);
    expect(innerScrollRoom(600, 1200, 0), 0);
  });

  group('pan tracker', () {
    test('adds the steps the report has not acknowledged', () {
      final t = InnerPanTracker();
      expect(t.offset(const InnerScrollPosition(0, 100)), 0);
      t
        ..sent(1, 60, 100)
        ..sent(2, 60, 100)
        ..sent(3, 60, 100);
      // Nothing reported yet: every step, stopping at the end.
      expect(t.offset(const InnerScrollPosition(0, 100)), 100);
      // Step 1 applied, the page on its way to 100.
      expect(t.offset(const InnerScrollPosition(80, 100, 1)), 100);
      expect(t.pending, 2);
      t.sent(4, -90, 100);
      expect(t.offset(const InnerScrollPosition(80, 100, 1)), 10);
      // All of them.
      expect(t.offset(const InnerScrollPosition(10, 100, 4)), 10);
      expect(t.pending, 0);
    });

    test('a late report out of order changes nothing', () {
      final t = InnerPanTracker()
        ..offset(const InnerScrollPosition(0, 100))
        ..sent(1, 60, 100)
        ..sent(2, 60, 100);
      expect(t.offset(const InnerScrollPosition(100, 100, 2)), 100);
      expect(t.offset(const InnerScrollPosition(60, 100, 1)), 100);
      t.sent(3, -30, 100);
      expect(t.offset(const InnerScrollPosition(60, 100, 1)), 70);
    });

    test('the same report twice counts once', () {
      final t = InnerPanTracker()
        ..offset(const InnerScrollPosition(0, 100))
        ..sent(1, 40, 100)
        ..sent(2, 40, 100);
      expect(t.offset(const InnerScrollPosition(40, 100, 1)), 80);
      expect(t.offset(const InnerScrollPosition(40, 100, 1)), 80);
      expect(t.pending, 1);
    });

    test('a page that moved on its own is taken as it says', () {
      final t = InnerPanTracker()
        ..offset(const InnerScrollPosition(0, 1000))
        ..sent(1, 40, 1000);
      // Step 1 applied, and a link inside the page jumped further.
      expect(t.offset(const InnerScrollPosition(500, 1000, 1)), 500);
    });

    test('a long pan with no reports stays bounded', () {
      final t = InnerPanTracker()..offset(const InnerScrollPosition(0, 1000));
      for (var i = 1; i <= 1000; i++) {
        t.sent(i, i <= 600 ? 3 : -1, 1000);
        expect(t.pending, lessThanOrEqualTo(InnerPanTracker.maxPending));
      }
      // 600 × 3 stops at 1000, then 400 back up.
      expect(t.offset(const InnerScrollPosition(0, 1000)), 600);
      // A report older than what was folded away is ignored.
      expect(t.offset(const InnerScrollPosition(0, 1000, 5)), 600);
      expect(t.offset(const InnerScrollPosition(620, 1000, 1000)), 620);
      expect(t.pending, 0);
    });
  });

  group('touchpad pan', () {
    testWidgets('scrolls the page first, then the reader with the rest', (
      tester,
    ) async {
      final inner = _Inner(100);
      final outer = await _pump(tester, inner);
      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = _onPaper(tester);
      await tester.sendEventToBinding(pad.panZoomStart(at));
      // 60 down: all of it inside the page.
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -60)),
      );
      await tester.pump();
      expect(inner.offset, 60);
      expect(outer.offset, 0);
      inner.report();
      // 60 more: 40 reach the page's end, 20 go to the reader.
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -120)),
      );
      await tester.pump();
      expect(inner.offset, 100);
      expect(outer.offset, 20);
      inner.report();
      // At the end of the page the reader takes it all.
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -180)),
      );
      await tester.pump();
      expect(inner.offset, 100);
      expect(outer.offset, 80);
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pumpAndSettle();
      expect(outer.offset, 80);
    });

    testWidgets('counts what the page took before it reports again', (
      tester,
    ) async {
      final inner = _Inner(100);
      final outer = await _pump(tester, inner);
      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = _onPaper(tester);
      await tester.sendEventToBinding(pad.panZoomStart(at));
      for (final y in [-60.0, -120.0, -180.0]) {
        await tester.sendEventToBinding(
          pad.panZoomUpdate(at, pan: Offset(0, y)),
        );
      }
      await tester.pump();
      // No report in between: 100 for the page, the other 80 for the reader.
      expect(inner.offset, 100);
      expect(outer.offset, 80);
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pumpAndSettle();
    });

    testWidgets('going back up, the page moves before the reader', (
      tester,
    ) async {
      final inner = _Inner(100)
        ..offset = 100
        ..report();
      final outer = await _pump(tester, inner);
      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = _onPaper(tester);
      await tester.sendEventToBinding(pad.panZoomStart(at));
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -50)),
      );
      await tester.pump();
      expect(outer.offset, 50);
      // Same gesture, the other way: the page is not at its top.
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -20)),
      );
      await tester.pump();
      expect(inner.offset, 70);
      expect(outer.offset, 50);
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pumpAndSettle();
    });

    testWidgets('turning back after a fast pan, with a late report', (
      tester,
    ) async {
      final inner = _Inner(100);
      final outer = await _pump(tester, inner);
      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = _onPaper(tester);
      await tester.sendEventToBinding(pad.panZoomStart(at));
      for (final y in [-60.0, -120.0, -180.0]) {
        await tester.sendEventToBinding(
          pad.panZoomUpdate(at, pan: Offset(0, y)),
        );
      }
      await tester.pump();
      expect(inner.offset, 100);
      expect(outer.offset, 80);
      // The page reports only the first step.
      inner.reported = 60;
      // Back up 80: the page is really at 100, so it takes it all.
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -100)),
      );
      await tester.pump();
      expect(inner.offset, 20);
      expect(outer.offset, 80);
      // A later report catches up with all of it.
      inner.report();
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -70)),
      );
      await tester.pump();
      expect(inner.offset, 0);
      expect(outer.offset, 70);
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pumpAndSettle();
    });

    testWidgets('a report from the middle of a step does not move the reader', (
      tester,
    ) async {
      final inner = _Inner(100);
      final outer = await _pump(tester, inner);
      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = _onPaper(tester);
      await tester.sendEventToBinding(pad.panZoomStart(at));
      for (final y in [-60.0, -120.0, -180.0]) {
        await tester.sendEventToBinding(
          pad.panZoomUpdate(at, pan: Offset(0, y)),
        );
      }
      await tester.pump();
      expect(inner.offset, 100);
      expect(outer.offset, 80);
      expect(inner.steps, [1, 2, 3]);
      // The page reports 80 on its way to 100, with only step 1 applied.
      inner
        ..reported = 80
        ..ack = 1;
      // Back up 90: the page is at 100, so it takes it all.
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -90)),
      );
      await tester.pump();
      expect(inner.offset, 10);
      expect(outer.offset, 80);
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pumpAndSettle();
    });

    testWidgets('a page that fits its paper leaves the pan to the reader', (
      tester,
    ) async {
      final inner = _Inner(0);
      final outer = await _pump(tester, inner);
      final pad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = _onPaper(tester);
      await tester.sendEventToBinding(pad.panZoomStart(at));
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -60)),
      );
      await tester.sendEventToBinding(
        pad.panZoomUpdate(at, pan: const Offset(0, -120)),
      );
      await tester.pump();
      await tester.sendEventToBinding(pad.panZoomEnd());
      await tester.pumpAndSettle();
      expect(inner.offset, 0);
      // The reader's own drag, past its start threshold.
      expect(outer.offset, greaterThan(0));
    });
  });

  group('keys', () {
    testWidgets('page keys over the page scroll it, then the reader', (
      tester,
    ) async {
      final inner = _Inner(1000);
      final outer = await _pump(tester, inner);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      // Nothing to go up to yet.
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      expect(inner.keys, [
        InnerScrollKey.pageDown,
        InnerScrollKey.pageDown,
        InnerScrollKey.bottom,
      ]);
      inner
        ..offset = 500
        ..report();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(inner.keys.skip(3), [InnerScrollKey.pageUp, InnerScrollKey.top]);
      expect(outer.offset, 0);
    });

    testWidgets('with the focus on the page, at its end the reader scrolls', (
      tester,
    ) async {
      final inner = _Inner(1000);
      final outer = await _pump(tester, inner);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
      await tester.sendEventToBinding(mouse.down(_onPaper(tester)));
      await tester.sendEventToBinding(mouse.up());
      // The pointer leaves the page; the focus stays.
      await tester.sendEventToBinding(mouse.hover(const Offset(10, 500)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(inner.keys, [InnerScrollKey.pageDown]);
      expect(outer.offset, 0);
      inner
        ..offset = 1000
        ..report();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(inner.keys, [InnerScrollKey.pageDown]);
      expect(outer.offset, greaterThan(0));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('a page that fits its paper leaves the keys to the reader', (
      tester,
    ) async {
      final inner = _Inner(0);
      final outer = await _pump(tester, inner);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
      await tester.sendEventToBinding(mouse.down(_onPaper(tester)));
      await tester.sendEventToBinding(mouse.up());
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(inner.keys, isEmpty);
      expect(outer.offset, greaterThan(0));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
      'with the focus elsewhere in the reader, the reader keeps its keys',
      (tester) async {
        final inner = _Inner(1000);
        final readerFocus = FocusNode();
        addTearDown(readerFocus.dispose);
        final outer = await _pump(tester, inner, readerFocus: readerFocus);
        readerFocus.requestFocus();
        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        // One of the two, never both.
        expect(inner.keys, isEmpty);
        expect(outer.offset, greaterThan(0));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('with the focus in another list, only that list scrolls', (
      tester,
    ) async {
      final inner = _Inner(1000);
      final list = ScrollController();
      addTearDown(list.dispose);
      final listFocus = FocusNode();
      addTearDown(listFocus.dispose);
      final outer = await _pump(
        tester,
        inner,
        side: SizedBox(
          width: 200,
          height: 600,
          child: ListView(
            controller: list,
            children: [
              Focus(focusNode: listFocus, child: const SizedBox(height: 40)),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      );
      listFocus.requestFocus();
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(inner.keys, isEmpty);
      expect(outer.offset, 0);
      expect(list.offset, greaterThan(0));
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('with a menu open, the page keeps still', (tester) async {
      final inner = _Inner(1000);
      final menu = MenuController();
      final itemFocus = FocusNode();
      addTearDown(itemFocus.dispose);
      final outer = await _pump(
        tester,
        inner,
        side: SizedBox(
          width: 200,
          child: MenuAnchor(
            controller: menu,
            menuChildren: [
              for (var i = 0; i < 60; i++)
                MenuItemButton(
                  focusNode: i == 0 ? itemFocus : null,
                  onPressed: () {},
                  child: Text('Folder $i'),
                ),
            ],
            child: const SizedBox(height: 40, child: Text('Move to')),
          ),
        ),
      );
      menu.open();
      await tester.pumpAndSettle();
      itemFocus.requestFocus();
      await tester.pump();
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(inner.keys, isEmpty);
      expect(outer.offset, 0);
      // The anchor's own button, with its menu open, keeps the keys too.
      FocusManager.instance.primaryFocus?.unfocus();
      final button = Focus.of(tester.element(find.text('Move to')));
      button.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(inner.keys, isEmpty);
      expect(outer.offset, 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('with the focus on nothing that scrolls, the page takes them', (
      tester,
    ) async {
      final inner = _Inner(1000);
      final buttonFocus = FocusNode();
      addTearDown(buttonFocus.dispose);
      final outer = await _pump(
        tester,
        inner,
        side: SizedBox(
          width: 200,
          child: Focus(focusNode: buttonFocus, child: const Text('Archive')),
        ),
      );
      buttonFocus.requestFocus();
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(inner.keys, [InnerScrollKey.pageDown]);
      expect(outer.offset, 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
      'with the focus on nothing that scrolls, at the page end the reader '
      'takes them',
      (tester) async {
        final inner = _Inner(1000)
          ..offset = 1000
          ..report();
        final buttonFocus = FocusNode();
        addTearDown(buttonFocus.dispose);
        final outer = await _pump(
          tester,
          inner,
          side: SizedBox(
            width: 200,
            child: Focus(focusNode: buttonFocus, child: const Text('Archive')),
          ),
        );
        buttonFocus.requestFocus();
        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        expect(inner.keys, isEmpty);
        expect(outer.offset, greaterThan(0));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('away from the page the keys stay with the reader', (
      tester,
    ) async {
      final inner = _Inner(1000);
      await _pump(tester, inner);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(10, 500)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(inner.keys, isEmpty);
    });
  });

  testWidgets('the wheel still goes to the page first', (tester) async {
    final inner = _Inner(100);
    final outer = await _pump(tester, inner);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(_onPaper(tester)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(inner.offset, 100);
    expect(outer.offset, 0);
    inner.report();
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(outer.offset, 120);
  });
}
