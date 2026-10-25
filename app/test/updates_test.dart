import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/updates/updates.dart';

void main() {
  test('updates stay off until the installer started them', () async {
    final u = Updates.instance;
    expect(u.available, isFalse);
    expect(u.updatedTo, isNull);
    await u.check();
    expect(u.state.value, isA<UpdateIdle>());
  });
  test('a fake shows its state and never reaches the engine', () async {
    final ready = UpdateReady(
      UpdateRelease(
        version: '0.1.0-beta.612',
        notes: '- Faster',
        size: BigInt.one,
      ),
    );
    final u = Updates.fake(state: ready);
    Updates.use(u);
    addTearDown(() => Updates.use(null));
    expect(Updates.instance, same(u));
    await u.check();
    await u.restart();
    expect(u.state.value, same(ready));
  });
}
