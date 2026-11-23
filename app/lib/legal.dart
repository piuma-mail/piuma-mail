import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Font credit line, for the About screen.
const fontCredit =
    'Geist and Geist Mono © 2023 Vercel, in collaboration with basement.studio, '
    'SIL Open Font License 1.1';

/// The license and notice texts of the Rust crates built into the engine,
/// written by `tools/gen_rust_licenses.py` (CI checks it is up to date).
const rustLicensesAsset = 'assets/licenses/rust_crates.json';

/// The Unicode License v3, for the Unicode Character Database data in
/// `lib/widgets/bidi_table.g.dart` (`tools/gen_bidi_table.py`).
const unicodeLicenseAsset = 'assets/licenses/Unicode-3.0.txt';

/// Shows the Geist license, the Unicode data's and every Rust crate's
/// license on the app's licenses screen. The Dart packages' licenses are
/// added by Flutter.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL-Geist.txt');
    yield LicenseEntryWithLineBreaks(const ['Geist', 'Geist Mono'], text);
  });
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(unicodeLicenseAsset);
    yield LicenseEntryWithLineBreaks(const [
      'Unicode Character Database',
    ], text);
  });
  LicenseRegistry.addLicense(() async* {
    final json = await rootBundle.loadString(rustLicensesAsset);
    for (final entry in jsonDecode(json) as List<dynamic>) {
      final e = entry as Map<String, dynamic>;
      yield LicenseEntryWithLineBreaks(
        (e['crates'] as List<dynamic>).cast<String>(),
        e['text'] as String,
      );
    }
  });
}
