import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Font credit line, for the About screen.
const fontCredit =
    'Geist and Geist Mono © 2023 Vercel, in collaboration with basement.studio, '
    'SIL Open Font License 1.1';

/// Shows the Geist license on the app's licenses screen.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL-Geist.txt');
    yield LicenseEntryWithLineBreaks(const ['Geist', 'Geist Mono'], text);
  });
}
