import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/legal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the Geist license is registered', () async {
    registerFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final geist = entries.where((e) => e.packages.contains('Geist'));
    expect(geist, isNotEmpty);
    final text = geist.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL Open Font License'));
  });
}
