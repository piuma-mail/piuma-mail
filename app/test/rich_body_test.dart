import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/rich_body.dart';
import 'package:piuma_mail/mail/mail_source.dart';

/// Types [s] at the caret, one character at a time, as a keyboard does.
void _type(RichBodyController c, String s) {
  for (final ch in s.split('')) {
    final sel = c.selection;
    final t = c.text;
    c.value = TextEditingValue(
      text: t.replaceRange(sel.start, sel.end, ch),
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }
}

void _backspace(RichBodyController c) {
  final at = c.selection.baseOffset;
  c.value = TextEditingValue(
    text: c.text.replaceRange(at - 1, at, ''),
    selection: TextSelection.collapsed(offset: at - 1),
  );
}

RichBodyController _at(String text, [int? caret]) =>
    RichBodyController(text: text)
      ..selection = TextSelection.collapsed(offset: caret ?? text.length);

void main() {
  test('bold over a selection, and typing at its end goes on in bold', () {
    final c = _at('Friday works')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    c.toggle(BodyMarkKind.bold);
    expect(c.marks, [const BodyMark(BodyMarkKind.bold, 0, 6)]);
    expect(c.isOn(BodyMarkKind.bold), isTrue);
    c.selection = const TextSelection.collapsed(offset: 6);
    _type(c, '!');
    expect(c.text, 'Friday! works');
    expect(c.marks, [const BodyMark(BodyMarkKind.bold, 0, 7)]);
    // Words typed before it push it along.
    c.selection = const TextSelection.collapsed(offset: 0);
    _type(c, 'So ');
    expect(c.marks, [const BodyMark(BodyMarkKind.bold, 3, 10)]);
    // Off again over part of it.
    c.selection = const TextSelection(baseOffset: 3, extentOffset: 5);
    c.toggle(BodyMarkKind.bold);
    expect(c.marks, [const BodyMark(BodyMarkKind.bold, 5, 10)]);
  });

  test('at the caret, bold is for what is typed next', () {
    final c = _at('Hi ');
    c.toggle(BodyMarkKind.bold);
    expect(c.isOn(BodyMarkKind.bold), isTrue);
    _type(c, 'there');
    expect(c.marks, [const BodyMark(BodyMarkKind.bold, 3, 8)]);
    c.toggle(BodyMarkKind.bold);
    _type(c, ' you');
    expect(c.marks, [const BodyMark(BodyMarkKind.bold, 3, 8)]);
  });

  test('deleting words takes their marks along', () {
    final c = RichBodyController(
      text: 'one two three',
      marks: const [BodyMark(BodyMarkKind.italic, 4, 13)],
    );
    c.value = const TextEditingValue(
      text: 'one three',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(c.marks, [const BodyMark(BodyMarkKind.italic, 4, 9)]);
  });

  test('a link, and an address pasted over words', () {
    final c = _at('the menu')
      ..selection = const TextSelection(baseOffset: 4, extentOffset: 8);
    c.link('https://trattoria.it/menu');
    expect(c.linkAt(), 'https://trattoria.it/menu');
    // Typing after a link doesn't extend it.
    c.selection = const TextSelection.collapsed(offset: 8);
    _type(c, '!');
    expect(c.marks.single.end, 8);

    final d = _at('see this')
      ..selection = const TextSelection(baseOffset: 4, extentOffset: 8);
    d.value = const TextEditingValue(
      text: 'see https://a.it',
      selection: TextSelection.collapsed(offset: 16),
    );
    expect(d.text, 'see this');
    expect(d.marks, [const BodyMark(BodyMarkKind.link, 4, 8, 'https://a.it')]);
  });

  test('"- " starts a list, Enter carries it on, Enter again ends it', () {
    final c = _at('Three things:\n');
    _type(c, '- terrace\nMarco\n');
    expect(c.text, 'Three things:\n• terrace\n• Marco\n• ');
    _type(c, '\n');
    expect(c.text, 'Three things:\n• terrace\n• Marco\n');
  });

  test('numbers count up, and backspace takes the number away', () {
    final c = _at('');
    _type(c, '1. eight\nhalf past');
    expect(c.text, '1. eight\n2. half past');
    c.selection = const TextSelection.collapsed(offset: 12);
    _backspace(c);
    expect(c.text, '1. eight\nhalf past');
  });

  test('"> " starts a quote', () {
    final c = _at('');
    _type(c, '> as you said');
    expect(c.text, '│ as you said');
  });

  test('the bar turns lines into a list and back', () {
    final c = _at('terrace\nMarco\ntime')
      ..selection = const TextSelection(baseOffset: 2, extentOffset: 10);
    c.toggleBlock(LineBlock.numbers);
    expect(c.text, '1. terrace\n2. Marco\ntime');
    expect(c.blockHere(), LineBlock.numbers);
    c.toggleBlock(LineBlock.bullets);
    expect(c.text, '• terrace\n• Marco\ntime');
    c.toggleBlock(LineBlock.bullets);
    expect(c.text, 'terrace\nMarco\ntime');
  });

  test('marks stay on their words when a list starts above them', () {
    final c = RichBodyController(
      text: 'terrace',
      marks: const [BodyMark(BodyMarkKind.bold, 0, 7)],
    )..selection = const TextSelection.collapsed(offset: 3);
    c.toggleBlock(LineBlock.quote);
    expect(c.text, '│ terrace');
    expect(c.marks, [const BodyMark(BodyMarkKind.bold, 2, 9)]);
  });
}
