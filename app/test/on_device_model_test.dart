import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/on_device_model.dart';
import 'package:piuma_mail/mail/readable.dart';

void main() {
  const transcript =
      'You: Could I get a quote for 500 catalogs?\n'
      'Sara: With the 120 g paper it comes to €640, delivered on the 28th.';

  test('the model reads the rules\' points and the conversation', () {
    final prompt = OnDeviceModel.prompt(
      const ThreadBrief(points: ['It comes to €640.'], transcript: transcript),
    );
    expect(prompt, contains('- It comes to €640.'));
    expect(prompt, endsWith(transcript));
    expect(prompt, contains('same language'));
  });

  test('bullets become points', () {
    expect(
      OnDeviceModel.parse(
        '- **500 catalogs** on 120 g paper.\n\n• €640, delivered the 28th.\n',
        transcript,
      ),
      ['500 catalogs on 120 g paper.', '€640, delivered the 28th.'],
    );
    expect(OnDeviceModel.parse('1. Sara quoted €640.', transcript), [
      'Sara quoted €640.',
    ]);
  });

  test('an invented number, an empty or long answer keep the rules', () {
    expect(OnDeviceModel.parse('- It comes to €680.', transcript), isNull);
    expect(OnDeviceModel.parse('  \n', transcript), isNull);
    expect(OnDeviceModel.parse('- a\n- b\n- c\n- d', transcript), isNull);
    expect(OnDeviceModel.parse('- ${'x' * 201}', transcript), isNull);
  });

  test('a day moved to another month keeps the rules', () {
    const booking =
        'Studio7: The studio is yours on April 28-29th.\n'
        'You: May I bring 7 more bags? Confirmed for 28 aprile.';
    expect(OnDeviceModel.parse('- Studio7 confirmed April 28-29th.', booking), [
      'Studio7 confirmed April 28-29th.',
    ]);
    expect(OnDeviceModel.parse('- Booked for 28 aprile.', booking), [
      'Booked for 28 aprile.',
    ]);
    // Its numbers are all there, but not "May" with a day.
    expect(
      OnDeviceModel.parse('- Studio7 confirmed May 7th and 29th.', booking),
      isNull,
    );
  });

  test('without a model on this system nothing is rewritten', () async {
    expect(
      await OnDeviceModel.instance.rewrite(
        const ThreadBrief(points: ['a'], transcript: transcript),
      ),
      isNull,
    );
  });
}
