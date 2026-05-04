import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusflow_mobile/core/error_telemetry.dart';

void main() {
  test('describeErrorForAdmin includes method path and status', () {
    final err = DioException(
      requestOptions: RequestOptions(
        path: '/v1/me',
        method: 'GET',
        baseUrl: 'https://api.example.com',
      ),
      response: Response(
        requestOptions: RequestOptions(path: '/v1/me'),
        statusCode: 503,
        data: {'message': 'maintenance'},
      ),
      type: DioExceptionType.badResponse,
      message: 'oops',
    );
    final s = describeErrorForAdmin(err);
    expect(s, contains('GET'));
    expect(s, contains('/v1/me'));
    expect(s, contains('503'));
    expect(s, contains('maintenance'));
  });
}
