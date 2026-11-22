import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/original_view.dart';

void main() {
  test('a page scaled down to fit a phone reports its height in points', () {
    // A 600-pixel layout drawn 360 points wide: 1500 CSS pixels tall
    // take 900 points.
    expect(paperHeight('1500,600', 360), 900);
  });

  test('an unscaled page keeps its height', () {
    expect(paperHeight('1200,680', 680), 1200);
  });

  test('a report without a usable width keeps the CSS height', () {
    expect(paperHeight('1200,0', 360), 1200);
    expect(paperHeight('1200,600', 0), 1200);
  });

  test('broken reports are ignored', () {
    expect(paperHeight('', 360), isNull);
    expect(paperHeight('abc,600', 360), isNull);
    expect(paperHeight('0,600', 360), isNull);
    expect(paperHeight('1200', 360), isNull);
  });

  test('the channel takes two numbers and nothing else', () {
    expect(paperHeight('1200,600;alert(1)', 360), isNull);
    expect(paperHeight('https://x.example,600', 360), isNull);
    expect(paperHeight('1e9,600', 360), isNull);
    expect(paperHeight(' 1200,600', 360), isNull);
    expect(paperHeight('1200.5,600', 600), 1200.5);
  });

  test('on Windows the paper stays under what Direct3D 11 can draw', () {
    // 16384 pixels is the tallest texture: at 150% that is 10922 points.
    for (final scale in [1.0, 1.25, 1.5, 2.0, 3.0]) {
      final points = paperMaxHeight(TargetPlatform.windows, scale);
      expect(points * scale, lessThanOrEqualTo(16384), reason: '$scale');
    }
    expect(paperMaxHeight(TargetPlatform.windows, 1.5), closeTo(10666, 1));
    expect(paperMaxHeight(TargetPlatform.windows, 0), 16000);
    expect(paperMaxHeight(TargetPlatform.windows, double.nan), 16000);
  });

  test('elsewhere the paper takes the whole email, as before', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    ]) {
      expect(paperMaxHeight(platform, 2), 20000);
    }
  });

  test('a wheel turn goes to a page longer than its paper first', () {
    // A page that fits its paper leaves every turn to the reader.
    expect(innerScrollTakes(0, 0, 40), isFalse);
    expect(innerScrollTakes(0, 1, 40), isFalse);
    // Down while there is more below, up while there is more above.
    expect(innerScrollTakes(0, 1200, 40), isTrue);
    expect(innerScrollTakes(0, 1200, -40), isFalse);
    expect(innerScrollTakes(1200, 1200, 40), isFalse);
    expect(innerScrollTakes(1200, 1200, -40), isTrue);
    expect(innerScrollTakes(600, 1200, 0), isFalse);
  });

  testWidgets('the reader keeps still while the web view scrolls', (
    tester,
  ) async {
    var inner = true;
    final outer = ScrollController();
    addTearDown(outer.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          controller: outer,
          children: [
            SizedBox(
              height: 2000,
              child: InnerScrollFirst(
                position: () => InnerScrollPosition(0, inner ? 1000 : 0),
                child: const ColoredBox(
                  key: ValueKey('web view'),
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Over the web view, which is taller than the screen.
    final at =
        tester.getTopLeft(find.byKey(const ValueKey('web view'))) +
        const Offset(100, 100);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(outer.offset, 0);
    // At the end of the page the reader scrolls on.
    inner = false;
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(outer.offset, 120);
  });
}
