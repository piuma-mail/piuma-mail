import 'package:flutter_test/flutter_test.dart';

extension SettleBesideWaves on WidgetTester {
  /// pumpAndSettle for screens with a running progress line, whose wave
  /// never settles: pumps [time] in small steps instead.
  Future<void> settleBesideWaves([
    Duration time = const Duration(milliseconds: 1500),
  ]) async {
    const step = Duration(milliseconds: 50);
    for (var t = Duration.zero; t < time; t += step) {
      await pump(step);
    }
  }
}
