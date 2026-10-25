import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/design/tokens.g.dart';
import 'package:piuma_mail/inbox/swipe.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/progress.dart';

/// [child] alone on a 400px wide screen.
Future<void> _show(
  WidgetTester tester,
  Widget child, {
  bool reduce = false,
}) async {
  tester.view.physicalSize = const Size(400, 300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(tester.view)
          .copyWith(disableAnimations: reduce),
      child: PiumaApp(
        home: (_, _) => Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  );
}

/// How far the row's face has moved.
double _dx(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey('face'))).dx;

void main() {
  group('a sticky swipe', () {
    late int archived;
    late int snoozed;

    Widget row() => SizedBox(
      height: 72,
      child: SwipeToArchive(
        label: 'Archive',
        snoozeLabel: 'Snooze',
        onArchive: () => archived++,
        onSnooze: () => snoozed++,
        child: const SizedBox.expand(key: ValueKey('face')),
      ),
    );

    setUp(() {
      archived = 0;
      snoozed = 0;
    });

    testWidgets('holds back before the point where it acts', (tester) async {
      await _show(tester, row());
      final g = await tester.startGesture(const Offset(100, 36));
      await g.moveBy(const Offset(20, 0));
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      // 80px of finger, short of a quarter, shown at the resisted share.
      expect(_dx(tester), closeTo(80 * PiumaMotion.swipeResist, 1));
      await g.up();
      await tester.pumpAndSettle();
      expect(_dx(tester), 0);
      expect(archived, 0);
    });

    testWidgets('snaps to the finger past it, and archives on release', (
      tester,
    ) async {
      await _show(tester, row());
      final g = await tester.startGesture(const Offset(100, 36));
      await g.moveBy(const Offset(20, 0));
      await g.moveBy(const Offset(160, 0));
      await tester.pump();
      await tester.pump(PiumaMotion.fast);
      expect(_dx(tester), closeTo(180, 2));
      await g.up();
      await tester.pumpAndSettle();
      expect(archived, 1);
    });

    testWidgets('lets go again when the finger goes back', (tester) async {
      await _show(tester, row());
      final g = await tester.startGesture(const Offset(300, 36));
      await g.moveBy(const Offset(-20, 0));
      await g.moveBy(const Offset(-160, 0));
      await tester.pump();
      await tester.pump(PiumaMotion.fast);
      expect(_dx(tester), closeTo(-180, 2));
      await g.moveBy(const Offset(120, 0));
      await tester.pump();
      await tester.pump(PiumaMotion.fast);
      expect(_dx(tester), closeTo(-60 * PiumaMotion.swipeResist, 1));
      await g.up();
      await tester.pumpAndSettle();
      expect(snoozed, 0);
      expect(_dx(tester), 0);
    });

    testWidgets('a slow drag left past the point snoozes', (tester) async {
      await _show(tester, row());
      await tester.timedDrag(
        find.byType(SwipeToArchive),
        const Offset(-200, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(snoozed, 1);
    });

    testWidgets('with reduce motion the snap is instant', (tester) async {
      await _show(tester, row(), reduce: true);
      final g = await tester.startGesture(const Offset(100, 36));
      await g.moveBy(const Offset(20, 0));
      await g.moveBy(const Offset(160, 0));
      await tester.pump();
      expect(_dx(tester), closeTo(180, 1));
      await g.up();
      await tester.pump();
      expect(archived, 1);
    });
  });

  group('a wavy progress line', () {
    testWidgets('runs while filling and rests once done', (tester) async {
      await _show(tester, const PiumaProgress(value: 0.4));
      await tester.pump(PiumaMotion.wave ~/ 2);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await _show(tester, const PiumaProgress(value: 1));
      // The wave flattens and the line stops drawing.
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('is still with reduce motion', (tester) async {
      await _show(tester, const PiumaProgress(), reduce: true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('makes room for its wave', (tester) async {
      await _show(tester, const PiumaProgress(value: 0.5, thickness: 3));
      expect(
        tester.getSize(find.byType(PiumaProgress)).height,
        3 + 2 * PiumaMotion.waveAmplitudePx,
      );
    });

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('progress golden $mode', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _show(
          tester,
          const Padding(
            padding: EdgeInsets.all(PiumaSpace.s16),
            child: Column(
              children: [
                PiumaProgress(value: 0),
                SizedBox(height: 16),
                PiumaProgress(value: 0.35, track: Color(0x22000000)),
                SizedBox(height: 16),
                PiumaProgress(
                  value: 0.7,
                  track: Color(0x22000000),
                  thickness: 4,
                ),
                SizedBox(height: 16),
                PiumaProgress(value: 1, track: Color(0x22000000)),
              ],
            ),
          ),
        );
        await tester.pump(PiumaMotion.move);
        await expectLater(
          find.byType(Column),
          matchesGoldenFile('goldens/progress_$mode.png'),
        );
      }, tags: ['golden']);
    }
  });
}
