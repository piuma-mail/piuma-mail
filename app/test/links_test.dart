import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/original_view.dart';
import 'package:piuma_mail/widgets/links.dart';

void main() {
  group('links from an email', () {
    late List<Uri> external;
    late List<Uri> mailto;
    late Future<void> Function(Uri) beforeExternal;
    late Future<void> Function(Uri) beforeMailto;

    setUp(() {
      external = [];
      mailto = [];
      beforeExternal = openExternalLink;
      beforeMailto = openMailtoLink;
      openExternalLink = (uri) async => external.add(uri);
      openMailtoLink = (uri) async => mailto.add(uri);
    });
    tearDown(() {
      openExternalLink = beforeExternal;
      openMailtoLink = beforeMailto;
    });

    test('only web pages and addresses open', () async {
      for (final ok in [
        'https://shop.example/a',
        'HTTP://shop.example/',
        'mailto:help@shop.example?subject=Hi',
      ]) {
        expect(isMailLinkAllowed(Uri.parse(ok)), isTrue, reason: ok);
      }
      for (final no in [
        'file:///etc/passwd',
        'intent://scan/#Intent;scheme=zxing;end',
        'javascript:alert(1)',
        'tel:+390000000',
        'sms:+390000000',
        'ms-settings:privacy',
        'piuma://account/1',
        'data:text/html,<b>x</b>',
        'https:///no-host',
        'mailto:',
      ]) {
        expect(await openMailLink(Uri.parse(no)), isFalse, reason: no);
      }
      expect(external, isEmpty);
      expect(mailto, isEmpty);
    });

    test('mailto goes through its own door, pages to the browser', () async {
      expect(await openMailLink(Uri.parse('https://shop.example/a')), isTrue);
      expect(await openMailLink(Uri.parse('mailto:help@shop.example')), isTrue);
      expect(external, [Uri.parse('https://shop.example/a')]);
      expect(mailto, [Uri.parse('mailto:help@shop.example')]);
    });
  });

  test('a navigation opens only right after a press', () {
    var now = DateTime(2026, 11, 18, 9);
    final gate = ClickGate(clock: () => now);
    // Nothing pressed: a refresh or a script.
    expect(gate.take(), isFalse);
    gate.pressed();
    now = now.add(const Duration(milliseconds: 300));
    expect(gate.take(), isTrue);
    // One press, one navigation.
    expect(gate.take(), isFalse);
    gate.pressed();
    now = now.add(const Duration(seconds: 5));
    expect(gate.take(), isFalse);
  });
}
