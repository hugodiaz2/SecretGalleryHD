import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_gallery/core/security/attempt_limiter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('los primeros fallos no bloquean y luego la espera se duplica',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final limiter = AttemptLimiter.instance;
    await limiter.reset();

    for (var i = 1; i < AttemptLimiter.freeAttempts; i++) {
      expect(await limiter.recordFailure(), Duration.zero);
    }
    expect(await limiter.remaining(), Duration.zero);

    expect(await limiter.recordFailure(), const Duration(seconds: 30));
    expect(await limiter.remaining(), greaterThan(Duration.zero));
    expect(await limiter.recordFailure(), const Duration(minutes: 1));
    expect(await limiter.recordFailure(), const Duration(minutes: 2));

    for (var i = 0; i < 20; i++) {
      await limiter.recordFailure();
    }
    expect(await limiter.recordFailure(), const Duration(minutes: 15));

    await limiter.reset();
    expect(await limiter.remaining(), Duration.zero);
    expect(await limiter.recordFailure(), Duration.zero);
    await limiter.reset();
  });

  test('formato legible de la espera', () {
    expect(AttemptLimiter.format(const Duration(seconds: 30)), '30 s');
    expect(AttemptLimiter.format(const Duration(milliseconds: 29100)), '30 s');
    expect(AttemptLimiter.format(const Duration(minutes: 2)), '2 min');
    expect(AttemptLimiter.format(const Duration(seconds: 90)), '1 min 30 s');
  });
}
