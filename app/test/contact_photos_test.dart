import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/contact_photos.dart';

void main() {
  final photo = Uint8List.fromList([1, 2, 3]);

  test('a contact is matched by address, whatever the case', () async {
    var reads = 0;
    final photos = ContactPhotos(
      read: () async {
        reads++;
        return {'giulia@example.com': photo};
      },
    );
    expect(await photos.of(' Giulia@Example.com'), photo);
    expect(await photos.of('marco@example.com'), isNull);
    expect(reads, 1);
    photos.forget();
    await photos.of('giulia@example.com');
    expect(reads, 2);
  });

  test('a refusal is not asked again', () async {
    var reads = 0;
    final photos = ContactPhotos(
      read: () async {
        reads++;
        return null;
      },
    );
    expect(await photos.of('giulia@example.com'), isNull);
    photos.forget();
    expect(await photos.of('giulia@example.com'), isNull);
    expect(reads, 1);
  });

  test('a failing contacts book keeps the letters', () async {
    final photos = ContactPhotos(read: () async => throw StateError('no'));
    expect(await photos.of('giulia@example.com'), isNull);
  });
}
