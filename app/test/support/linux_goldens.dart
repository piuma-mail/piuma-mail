import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Compares golden screenshots only on Linux, where the references are
/// rendered (CI or WSL): other systems draw text slightly differently, so
/// there the comparison passes without looking. `--update-goldens` still
/// writes the files, and `PIUMA_GOLDENS=compare` forces the comparison.
void compareGoldensOnLinuxOnly() {
  if (Platform.isLinux || Platform.environment['PIUMA_GOLDENS'] == 'compare') {
    return;
  }
  goldenFileComparator = _Skipping(goldenFileComparator);
}

class _Skipping extends GoldenFileComparator {
  _Skipping(this._inner);

  final GoldenFileComparator _inner;
  static bool _told = false;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    if (!_told) {
      _told = true;
      // ignore: avoid_print
      print(
        'Golden screenshots are compared only on Linux (CI or WSL); '
        'skipping them on ${Platform.operatingSystem}.',
      );
    }
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      _inner.update(golden, imageBytes);

  @override
  Uri getTestUri(Uri key, int? version) => _inner.getTestUri(key, version);
}
