import 'package:flutter_test/flutter_test.dart';
import 'package:focusflow_mobile/core/user_facing_errors.dart';

void main() {
  test('messageLooksLeakedOrTechnical catches config and network leaks', () {
    expect(
      messageLooksLeakedOrTechnical('set API_BASE_URL in mobile/.env'),
      isTrue,
    );
    expect(
      messageLooksLeakedOrTechnical('http://192.168.1.5:3000/v1/me'),
      isTrue,
    );
    expect(
      messageLooksLeakedOrTechnical('ECONNREFUSED 127.0.0.1:3000'),
      isTrue,
    );
    expect(messageLooksLeakedOrTechnical('fetch failed'), isTrue);
    expect(messageLooksLeakedOrTechnical('Something about your task'), isFalse);
  });

  test('userFacingError maps StateError API_BASE_URL to friendly copy', () {
    final msg = userFacingError(
      StateError('API_BASE_URL must be set in mobile/.env for release builds.'),
    );
    expect(msg.toLowerCase(), contains('internet'));
  });
}
