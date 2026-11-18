import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/outside/mailto.dart';

void main() {
  MailtoLink parse(String link) => MailtoLink.parse(link)!;

  test('reads every field a message is written with', () {
    final m = parse(
      'mailto:ada@example.com,Bob%20Moore%20%3Cbob@example.com%3E'
      '?cc=carol@example.com&bcc=dan@example.com'
      '&subject=Notes%20on%20the%20engine&body=Hi%20Bob%2C%0D%0Asee%20you'
      '&In-Reply-To=%3Cnote-1@example.com%3E',
    );
    expect(m.to, ['ada@example.com', 'Bob Moore <bob@example.com>']);
    expect(m.cc, ['carol@example.com']);
    expect(m.bcc, ['dan@example.com']);
    expect(m.subject, 'Notes on the engine');
    expect(m.body, 'Hi Bob,\nsee you');
    expect(m.inReplyTo, '<note-1@example.com>');
  });

  test('header names are case-insensitive; to= adds to the path', () {
    final m = parse('MAILTO:a@example.com?TO=b@example.com&Subject=Hi');
    expect(m.to, ['a@example.com', 'b@example.com']);
    expect(m.subject, 'Hi');
  });

  test('only mailto: links, of a sane length', () {
    expect(MailtoLink.parse('http://example.com'), isNull);
    expect(MailtoLink.parse('javascript:alert(1)'), isNull);
    expect(MailtoLink.parse('mailtox:a@example.com'), isNull);
    expect(MailtoLink.parse(''), isNull);
    final huge = 'mailto:a@example.com?body=${'x' * MailtoLink.maxLength}';
    expect(MailtoLink.parse(huge), isNull);
    expect(parse('mailto:').isEmpty, isTrue);
  });

  test('a link can neither pick the sender nor attach a file', () {
    final m = parse(
      'mailto:a@example.com?from=boss@example.com&reply-to=x@evil.example'
      '&sender=x@evil.example&attach=/etc/passwd&attachment=C:%5Csecret.txt'
      '&X-Anything=1&body=hi',
    );
    expect(m.to, ['a@example.com']);
    expect(m.cc, isEmpty);
    expect(m.bcc, isEmpty);
    expect(m.body, 'hi');
  });

  test('line breaks never reach a header', () {
    final m = parse(
      'mailto:a@example.com?subject=Hello%0D%0ABcc:%20victim@example.com'
      '&cc=c@example.com%0D%0ABcc:%20v@example.com',
    );
    expect(m.subject, 'Hello Bcc: victim@example.com');
    expect(m.subject, isNot(contains('\n')));
    // The address with a header smuggled in is no address at all.
    expect(m.cc, isEmpty);
    expect(m.bcc, isEmpty);
    // Unicode's own line and paragraph separators, and NEL, too.
    expect(
      parse('mailto:a@example.com?subject=a%E2%80%A8b%E2%80%A9c%C2%85d')
          .subject,
      'a b c d',
    );
    expect(MailtoLink.cleanSubject('a\u2028\u2029b'), 'a b');
  });

  test('addresses that are not addresses are dropped', () {
    final m = parse(
      'mailto:javascript:alert(1),%22%3E%3Cscript%3E@x,a@b,,'
      'not%20an%20address,ok@example.com,x@y@z.com,%0A',
    );
    expect(m.to, ['ok@example.com']);
  });

  test('a name cannot hide another address', () {
    final m = parse(
      'mailto:${Uri.encodeComponent('boss@example.com <x@evil.example>')}',
    );
    expect(m.to, ['x@evil.example']);
  });

  test('an encoded comma stays inside one address', () {
    final m = parse(
      'mailto:${Uri.encodeComponent('"Moore, Bob" <bob@example.com>')}',
    );
    expect(m.to, ['Moore, Bob <bob@example.com>']);
  });

  test('the same address once, and at most 100', () {
    final many = List.generate(500, (i) => 'p$i@example.com').join(',');
    final m = parse('mailto:A@example.com,a@EXAMPLE.com?cc=a@example.com');
    expect(m.to, ['A@example.com']);
    expect(m.cc, isEmpty);
    expect(parse('mailto:$many?cc=$many').to, hasLength(100));
  });

  test('the body stays text: scripts and links are only words', () {
    const body =
        '<script>alert(1)</script> javascript:alert(2) '
        '<a href="javascript:x">x</a> data:text/html,<b>';
    final m = parse('mailto:a@example.com?body=${Uri.encodeComponent(body)}');
    expect(m.body, body);
  });

  test('the first subject and body count; later ones are ignored', () {
    final m = parse(
      'mailto:a@example.com?subject=one&subject=two&body=first&body=second',
    );
    expect(m.subject, 'one');
    expect(m.body, 'first');
  });

  test('broken escapes and bad UTF-8 never throw', () {
    final m = parse(
      'mailto:a@example.com?subject=100%25%20sure%zz%&body=%FF%FEcaf%C3%A9%',
    );
    expect(m.subject, '100% sure%zz%');
    expect(m.body, '��café%');
    // + is a plus (RFC 6068), not a space.
    expect(parse('mailto:a+tag@example.com?subject=1+1').subject, '1+1');
    expect(parse('mailto:a+tag@example.com').to, ['a+tag@example.com']);
  });

  test('text that reorders itself on screen and controls are removed', () {
    final m = parse(
      'mailto:a@example.com?subject=${Uri.encodeComponent('Invoice \u202Efdp.exe\u0007')}'
      '&body=${Uri.encodeComponent('a\u0000b‏c\r\nd')}',
    );
    expect(m.subject, 'Invoice fdp.exe');
    expect(m.body, 'abc\nd');
  });

  test('every part has a length cap', () {
    final m = parse(
      'mailto:a@example.com?subject=${'s' * 5000}&body=${'b' * 150000}',
    );
    expect(m.subject.length, MailtoLink.maxSubject);
    expect(m.body.length, MailtoLink.maxBody);
    final long = '${'x' * 400}@example.com';
    expect(parse('mailto:$long').to, isEmpty);
  });

  test('In-Reply-To must be a message id', () {
    expect(parse('mailto:a@b.co?in-reply-to=nonsense').inReplyTo, isNull);
    expect(
      parse('mailto:a@b.co?in-reply-to=%3Ca@b%3E%0D%0AX:1').inReplyTo,
      isNull,
    );
    expect(parse('mailto:a@b.co?in-reply-to=id@host').inReplyTo, '<id@host>');
  });

  test('a fragment is no part of the link', () {
    final m = parse('mailto:a@example.com?subject=Hi#body=evil');
    expect(m.subject, 'Hi');
    expect(m.body, '');
  });
}
