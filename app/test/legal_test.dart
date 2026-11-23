import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/legal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the Geist, Unicode and Rust crate licenses are registered', () async {
    registerFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final geist = entries.where((e) => e.packages.contains('Geist'));
    expect(geist, isNotEmpty);
    final text = geist.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL Open Font License'));
    // Crates built into every engine, under Apache 2.0 and MIT.
    for (final crate in ['tokio', 'rustls', 'serde']) {
      final its = entries.where((e) => e.packages.contains(crate));
      expect(its, isNotEmpty, reason: crate);
      expect(
        its.expand((e) => e.paragraphs).map((p) => p.text).join('\n'),
        isNotEmpty,
        reason: crate,
      );
    }
    // The translation engine (MPL 2.0) and the code vendored inside it.
    final fx = entries
        .where((e) => e.packages.contains('fxtranslate'))
        .expand((e) => e.paragraphs)
        .map((p) => p.text)
        .join('\n');
    expect(fx, contains('Mozilla Public License'));
    // The Unicode data behind which way text reads.
    final ucd = entries
        .where((e) => e.packages.contains('Unicode Character Database'))
        .expand((e) => e.paragraphs)
        .map((p) => p.text)
        .join('\n');
    expect(ucd, contains('UNICODE LICENSE V3'));
  });
}
