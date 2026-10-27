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
}
