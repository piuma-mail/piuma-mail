import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/notify/notifier.dart';
import 'package:piuma_mail/widgets/links.dart';

import 'support/fake_notifier.dart';
import 'support/linux_goldens.dart';

/// Loads Geist in tests, so golden screenshots show the real font instead
/// of the test font's boxes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  compareGoldensOnLinuxOnly();
  // Tests never reach the system's notifications.
  notifier = FakeNotifier();
  // Tests run without the engine's library: hosts are read without UTS #46
  // (links_test checks it with the library when it is built).
  linkHostAscii = (_) => null;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load('Geist', [
    'Geist-Regular.ttf',
    'Geist-Medium.ttf',
    'Geist-SemiBold.ttf',
  ]);
  await load('Geist Mono', ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf']);
  await testMain();
}
