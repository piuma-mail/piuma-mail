import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/design/theme.dart';
import 'package:piuma_mail/engine/api/links.dart' as engine;
import 'package:piuma_mail/engine/frb_generated.dart';
import 'package:piuma_mail/inbox/original_view.dart';
import 'package:piuma_mail/widgets/link_target.dart';
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

  test('a web address with a user name before its host never opens', () {
    for (final link in [
      'https://bank.example@evil.example/',
      'https://bank.example:443@evil.example/login',
      'https://user:pass@shop.example/',
    ]) {
      expect(isMailLinkAllowed(Uri.parse(link)), isFalse, reason: link);
    }
    // An @ in the query is no user name: the host is the one before it.
    expect(
      isMailLinkAllowed(Uri.parse('https://bank.example/login?x=a@b.example')),
      isTrue,
    );
  });

  test('the target shows its real host and the end of a padded address', () {
    final padded =
        'https://evil.example/${'bank.example/login/' * 30}finish?id=7';
    final parts = describeLink(padded)!;
    expect(parts.host, 'evil.example');
    expect(parts.registrable, 'evil.example');
    final shown = elideMiddle(parts.rest, 56);
    expect(shown.runes.length, 56);
    expect(shown, contains('…'));
    expect(shown, endsWith('finish?id=7'));
    expect(
      describeLink('https://login.bank.co.uk/x')!.registrable,
      'bank.co.uk',
    );
  });

  test('a host with other letters shows its ASCII form too', () {
    // Cyrillic letters that look like "paypal".
    expect(punycodeHost('раураl.com'), 'xn--l-7sba6dbr.com');
    expect(punycodeHost('bücher.de'), 'xn--bcher-kva.de');
    expect(punycodeHost('shop.example'), isNull);
  });

  test('an href and the browser\'s form of it compare equal', () {
    expect(
      normalizeLink('HTTPS://Lume-Login.Example'),
      normalizeLink('https://lume-login.example/'),
    );
    expect(
      normalizeLink('https://a.example/x/../y'),
      normalizeLink('https://a.example/y'),
    );
  });

  test('an IDN host compares in the ASCII form the browser hands back', () {
    expect(
      normalizeLink('https://Bücher.de/x'),
      normalizeLink('https://xn--bcher-kva.de/x'),
    );
    expect(
      normalizeLink('https://раураl.com/login'),
      normalizeLink('https://xn--l-7sba6dbr.com/login'),
    );
  });

  test('a link written in punycode shows both forms of its host', () {
    for (final url in [
      'https://xn--l-7sba6dbr.com/login',
      'https://раураl.com/login',
    ]) {
      final parts = describeLink(url)!;
      expect(parts.host, 'раураl.com', reason: url);
      expect(parts.ascii, 'xn--l-7sba6dbr.com', reason: url);
      expect(parts.rest, '/login', reason: url);
    }
    expect(unicodeHost('xn--bcher-kva.de'), 'bücher.de');
    // Not really punycode, or ASCII only: left as it is.
    expect(unicodeHost('xn--zz.example'), 'xn--zz.example');
    expect(unicodeHost('xn--abc-.example'), 'xn--abc-.example');
    expect(describeLink('https://shop.example/')!.ascii, isNull);
  });

  test('a user name before the host never takes the host\'s place', () {
    final parts = describeLink('https://bank.it@evil.example/login')!;
    expect(parts.host, 'evil.example');
    expect(parts.registrable, 'evil.example');
    expect(parts.rest, '/login');
  });

  test('an uppercase IDN host is the same host as its lowercase form', () {
    // [Uri] lowercases only ASCII letters: `Ü` stays percent-encoded.
    for (final url in ['https://BÜCHER.de/x', 'https://XN--BCHER-KVA.DE/x']) {
      expect(normalizeLink(url), 'https://xn--bcher-kva.de/x', reason: url);
      final parts = describeLink(url)!;
      expect(parts.host, 'bücher.de', reason: url);
      expect(parts.ascii, 'xn--bcher-kva.de', reason: url);
    }
  });

  test('an @ hidden in a host\'s percent-encoding never opens', () {
    for (final link in [
      'https://bank.example%40evil.example/',
      'https://bank.example%2540evil.example/',
      'https://BANK.example%40evil.example/login',
    ]) {
      expect(isMailLinkAllowed(Uri.parse(link)), isFalse, reason: link);
      // Still compared and shown, without throwing.
      expect(normalizeLink(link), isNotEmpty, reason: link);
    }
    final parts = describeLink('https://bank.example%40evil.example/login')!;
    expect(parts.host, 'bank.example@evil.example');
    expect(parts.registrable, 'evil.example');
    expect(parts.rest, '/login');
  });

  test(
    'a host whose percent-encoding isn\'t UTF-8 never opens, and never throws',
    () {
      for (final link in ['https://a%ff.example/', 'https://a%C3.example/x']) {
        expect(isMailLinkAllowed(Uri.parse(link)), isFalse, reason: link);
        expect(normalizeLink(link), isNotEmpty, reason: link);
        expect(describeLink(link), isNotNull, reason: link);
      }
      expect(describeLink('mailto:%ff@x.example')!.registrable, 'x.example');
    },
  );

  test('a trailing dot doesn\'t hide the registrable part', () {
    expect(registrableDomain('login.evil.example.'), 'evil.example.');
    expect(registrableDomain('bank.co.uk.'), 'bank.co.uk.');
    expect(describeLink('https://paypal.evil.com./')!.registrable, 'evil.com.');
  });

  test('an IPv6 host with a port reads apart from its port', () {
    final uri = Uri.parse('http://[::1]:8080/a?b=c');
    expect(isMailLinkAllowed(uri), isTrue);
    final parts = describeLink('http://[::1]:8080/a?b=c')!;
    expect(parts.host, '[::1]');
    expect(parts.registrable, '[::1]');
    expect(parts.ascii, isNull);
    expect(parts.rest, ':8080/a?b=c');
    expect(describeLink('http://[FE80::1]/')!.host, '[fe80::1]');
    expect(
      normalizeLink('HTTP://[FE80::1]:8080'),
      normalizeLink('http://[fe80::1]:8080/'),
    );
    expect(normalizeLink('http://[::1]:8080/'), 'http://[::1]:8080/');
    // An IPv4 address has no registrable part either.
    expect(
      describeLink('http://192.168.1.10:81/')!.registrable,
      '192.168.1.10',
    );
  });

  testWidgets('the status line keeps the whole host, whatever the path', (
    tester,
  ) async {
    Future<String> shown(String url) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPiumaTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: LinkTargetLine(url: url),
            ),
          ),
        ),
      );
      final text = tester.widget<RichText>(
        find.descendant(
          of: find.byType(LinkTargetLine),
          matching: find.byType(RichText),
        ),
      );
      expect(tester.takeException(), isNull, reason: url);
      return text.text.toPlainText();
    }

    final padded = await shown(
      'https://bank.it@evil.example/${'bank.it/login/' * 40}end',
    );
    expect(padded, startsWith('evil.example/'));
    expect(padded, endsWith('end'));
    expect(padded.runes.length, lessThanOrEqualTo(72));
    // A host longer than the line: all of it, the path cut instead.
    final label = 'secure-login-${'a' * 50}';
    final long = await shown('https://$label.example/${'x/' * 60}');
    expect(long, startsWith('$label.example'));
    final idn = await shown('https://xn--l-7sba6dbr.com/${'p/' * 60}');
    expect(idn, startsWith('раураl.com  xn--l-7sba6dbr.com/'));
    final ipv6 = await shown('http://[::1]:8080/admin');
    expect(ipv6, '[::1]:8080/admin');
  });

  test('hosts go through UTS #46 before they are compared or shown', () {
    final before = linkHostAscii;
    addTearDown(() => linkHostAscii = before);
    final asked = <String>[];
    linkHostAscii = (host) {
      asked.add(host);
      return host == 'example。com' ? 'example.com' : null;
    };
    expect(normalizeLink('https://example。com/x'), 'https://example.com/x');
    final parts = describeLink('https://example。com/x')!;
    expect(parts.host, 'example.com');
    expect(parts.registrable, 'example.com');
    expect(parts.ascii, isNull);
    // Decoded, as written: the mapping folds case itself.
    expect(asked, everyElement('example。com'));
    // Refused by UTS #46: read as before.
    expect(normalizeLink('https://BÜCHER.de/x'), 'https://xn--bcher-kva.de/x');
  });

  group('with the engine\'s UTS #46', () {
    // The engine's library, when it is built (`cargo build -p
    // piuma_bridge`). CI builds it, and there a missing library fails the
    // tests instead of skipping them.
    final root = Directory.current.parent.path;
    final name = Platform.isWindows
        ? 'piuma_bridge.dll'
        : Platform.isMacOS
        ? 'libpiuma_bridge.dylib'
        : 'libpiuma_bridge.so';
    final lib = File('$root/target/debug/$name');
    final inCi = Platform.environment['CI'] == 'true';
    final skip = lib.existsSync() || inCi ? false : 'build piuma_bridge to run';
    late String? Function(String) before;

    setUpAll(() async {
      if (!lib.existsSync()) {
        if (inCi) fail('CI must build piuma_bridge first: ${lib.path}');
        return;
      }
      await RustLib.init(externalLibrary: ExternalLibrary.open(lib.path));
    });
    setUp(() {
      before = linkHostAscii;
      linkHostAscii = (host) => engine.linkHostAscii(host: host);
    });
    tearDown(() => linkHostAscii = before);

    test('the other dots read as "."', () {
      for (final dot in ['。', '．', '｡']) {
        final url = 'https://login.example${dot}com/x';
        expect(normalizeLink(url), 'https://login.example.com/x', reason: url);
        final parts = describeLink(url)!;
        expect(parts.host, 'login.example.com', reason: url);
        expect(parts.registrable, 'example.com', reason: url);
        expect(parts.ascii, isNull, reason: url);
      }
      expect(
        describeLink('mailto:a@bank。example')!.registrable,
        'bank.example',
      );
    }, skip: skip);

    test('full-width letters read as ASCII', () {
      const url = 'https://ｅｘａｍｐｌｅ.com/a';
      expect(normalizeLink(url), 'https://example.com/a');
      expect(normalizeLink('https://ＢＡＮＫ.example/'), 'https://bank.example/');
      final parts = describeLink(url)!;
      expect(parts.host, 'example.com');
      expect(parts.ascii, isNull);
    }, skip: skip);

    test('a mixed-case IDN host is one host', () {
      for (final url in [
        'https://BÜcher.De/x',
        'https://bÜCHER.de/x',
        'https://Xn--Bcher-Kva.dE/x',
      ]) {
        expect(normalizeLink(url), 'https://xn--bcher-kva.de/x', reason: url);
        final parts = describeLink(url)!;
        expect(parts.host, 'bücher.de', reason: url);
        expect(parts.ascii, 'xn--bcher-kva.de', reason: url);
      }
    }, skip: skip);

    test('the hosts of #99 read as they did', () {
      expect(
        normalizeLink('https://раураl.com/login'),
        'https://xn--l-7sba6dbr.com/login',
      );
      final idn = describeLink('https://xn--l-7sba6dbr.com/login')!;
      expect(idn.host, 'раураl.com');
      expect(idn.ascii, 'xn--l-7sba6dbr.com');
      final hidden = describeLink('https://bank.example%40evil.example/login')!;
      expect(hidden.host, 'bank.example@evil.example');
      expect(hidden.registrable, 'evil.example');
      expect(
        isMailLinkAllowed(Uri.parse('https://bank.example%40evil.example/')),
        isFalse,
      );
      expect(describeLink('https://a%ff.example/'), isNotNull);
      expect(
        describeLink('https://paypal.evil.com./')!.registrable,
        'evil.com.',
      );
      expect(
        describeLink('http://192.168.1.10:81/')!.registrable,
        '192.168.1.10',
      );
      expect(describeLink('http://[FE80::1]/')!.host, '[fe80::1]');
      expect(normalizeLink('http://[::1]:8080/'), 'http://[::1]:8080/');
      expect(describeLink('https://shop.example/')!.ascii, isNull);
      expect(
        normalizeLink('HTTPS://Lume-Login.Example'),
        'https://lume-login.example/',
      );
    }, skip: skip);

    test('a host is percent-decoded once, as the browser does', () {
      // `%25` decodes to a `%`, which stays: never a second `.`.
      const url = 'https://bank%252eexample/login';
      final parts = describeLink(url)!;
      expect(parts.host, 'bank%2eexample');
      expect(parts.registrable, isNot('bank.example'));
      expect(isMailLinkAllowed(Uri.parse(url)), isFalse);
    }, skip: skip);
  });
}
