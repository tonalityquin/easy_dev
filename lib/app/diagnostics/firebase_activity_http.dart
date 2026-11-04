import 'package:http/http.dart' as http;

import 'firebase_activity_meter.dart';

class FirebaseActivityHttp {
  FirebaseActivityHttp._();

  static Future<http.Response> get(
    Uri uri, {
    required String source,
  }) async {
    if (uri.scheme != 'https' || uri.host != 'storage.googleapis.com') {
      throw ArgumentError.value(uri.host, 'uri', '지원하지 않는 GCS 요청 대상입니다.');
    }
    final watch = Stopwatch()..start();
    try {
      final response = await http.get(uri);
      watch.stop();
      FirebaseActivityMeter.instance.record(
        service: 'storage',
        operation: 'URL_ACCESS',
        source: source,
        result: response.statusCode >= 200 && response.statusCode < 300
            ? 'success'
            : 'error',
        elapsedMs: watch.elapsedMilliseconds,
        bytes: response.bodyBytes.length,
        detail: 'httpStatus=${response.statusCode}',
      );
      return response;
    } catch (error, stack) {
      watch.stop();
      FirebaseActivityMeter.instance.record(
        service: 'storage',
        operation: 'URL_ACCESS',
        source: source,
        result: 'error',
        elapsedMs: watch.elapsedMilliseconds,
        detail: error.runtimeType.toString(),
      );
      Error.throwWithStackTrace(error, stack);
    }
  }
}
