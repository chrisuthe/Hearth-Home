import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/config/hub_config.dart';
import 'package:hearth/services/immich_service.dart';
import 'package:hearth/services/immich_sources.dart';

/// Records every outgoing request and answers with an empty 200 so the
/// source's parsing path stays out of the way. Immich itself rejects a
/// `for` value carrying a time component with a 400, so these tests assert
/// on the value Hearth *sends* rather than on a simulated rejection.
class _RecordingInterceptor extends Interceptor {
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    handler.resolve(Response<List<dynamic>>(
      requestOptions: options,
      statusCode: 200,
      data: const [],
    ));
  }
}

Dio _dioWith(_RecordingInterceptor interceptor, {String baseUrl = 'https://immich.example'}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  dio.interceptors.add(interceptor);
  return dio;
}

void main() {
  group('MemoriesSource `for` parameter', () {
    test('sends a bare calendar date, not a date-time', () async {
      final interceptor = _RecordingInterceptor();
      final source = MemoriesSource(
        dio: _dioWith(interceptor),
        baseUrl: 'https://immich.example',
        now: () => DateTime(2026, 8, 17, 14, 40, 2, 861),
      );

      await source.fetch(limit: 50);

      expect(interceptor.requests, hasLength(1));
      expect(interceptor.requests.single.queryParameters['for'], '2026-08-17');
    });

    test('zero-pads single-digit months and days', () async {
      final interceptor = _RecordingInterceptor();
      final source = MemoriesSource(
        dio: _dioWith(interceptor),
        baseUrl: 'https://immich.example',
        now: () => DateTime(2026, 1, 5, 9, 3),
      );

      await source.fetch(limit: 50);

      expect(interceptor.requests.single.queryParameters['for'], '2026-01-05');
    });
  });

  group('ImmichService.refresh guard', () {
    const config = PhotoSourcesConfig(memoriesEnabled: true);

    test('issues no request when the base URL is empty', () async {
      final interceptor = _RecordingInterceptor();
      final service = ImmichService(
        baseUrl: '',
        apiKey: 'key-123',
        dio: _dioWith(interceptor, baseUrl: ''),
      );

      await service.refresh(config);

      expect(interceptor.requests, isEmpty);
    });

    test('issues no request when the API key is empty', () async {
      final interceptor = _RecordingInterceptor();
      final service = ImmichService(
        baseUrl: 'https://immich.example',
        apiKey: '',
        dio: _dioWith(interceptor),
      );

      await service.refresh(config);

      expect(interceptor.requests, isEmpty);
    });

    test('still issues requests when both are configured', () async {
      final interceptor = _RecordingInterceptor();
      final service = ImmichService(
        baseUrl: 'https://immich.example',
        apiKey: 'key-123',
        dio: _dioWith(interceptor),
      );

      await service.refresh(config);

      expect(interceptor.requests, hasLength(1));
    });
  });
}
