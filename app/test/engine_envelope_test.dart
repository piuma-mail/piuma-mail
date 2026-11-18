import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/engine/api/reply.dart' as rep;
import 'package:piuma_mail/mail/engine_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';

void main() {
  test('the engine’s envelope reaches the app whole', () {
    final e = EngineMailSource.envelopeOf(
      const rep.MessageEnvelope(
        to: [
          rep.MailAddress(name: 'Matteo', email: 'me+x@studio.it', you: true),
          rep.MailAddress(name: 'Carla', email: 'carla@x.it', you: false),
        ],
        cc: [rep.MailAddress(name: '', email: 'dan@x.it', you: false)],
        bccYou: false,
        replyTo: ['Anna <anna@x.it>'],
        replyAllTo: ['Anna <anna@x.it>', 'Carla <carla@x.it>'],
        replyAllCc: ['dan@x.it'],
        listPost: 'dev@l.org',
        muted: true,
        replyAllReview: true,
      ),
    );
    expect(e.to, const [
      MailPerson('Matteo', 'me+x@studio.it', you: true),
      MailPerson('Carla', 'carla@x.it'),
    ]);
    expect(e.cc.single.email, 'dan@x.it');
    expect(e.replyTo, ['Anna <anna@x.it>']);
    expect(e.replyAllTo, ['Anna <anna@x.it>', 'Carla <carla@x.it>']);
    expect(e.replyAllCc, ['dan@x.it']);
    expect(e.listPost, 'dev@l.org');
    expect(e.muted, isTrue);
    expect(e.replyAllReview, isTrue);
    expect(e.others, 2);
  });
}
