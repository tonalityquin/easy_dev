import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BuildOptimizationDiagnostics {
  const BuildOptimizationDiagnostics._();

  static const MethodChannel _channel =
      MethodChannel('com.quintus.dev/build_optimization');
  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[BUILD_OPTIMIZATION] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> refresh({required String source}) async {
    final startedAt = DateTime.now();
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('getBuildOptimizationStatus')
          .timeout(const Duration(seconds: 2));
      final values = result ?? const <String, dynamic>{};
      _record(
        'status',
        <String, Object?>{
          'source': source,
          'applicationId': values['applicationId'],
          'buildType': values['buildType'],
          'debug': values['debug'],
          'versionName': values['versionName'],
          'versionCode': values['versionCode'],
          'minifyEnabled': values['minifyEnabled'],
          'optimizeRulesEnabled': values['optimizeRulesEnabled'],
          'resourceShrinkEnabled': values['resourceShrinkEnabled'],
          'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error) {
      _record(
        'status_failed',
        <String, Object?>{
          'source': source,
          'error': error,
          'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    }
  }

  static void _record(String event, Map<String, Object?> meta) {
    final fields = <String>[
      '[BUILD_OPTIMIZATION]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'event=$event',
    ];
    for (final entry in meta.entries) {
      fields.add('${entry.key}=${entry.value}');
    }
    final line = fields.join(' ');
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 40) {
      _lines.removeRange(0, _lines.length - 40);
    }
  }
}
