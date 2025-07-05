import 'dart:io';
import 'dart:convert'; // Utf8Decoder
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class FirestoreLogger {
  // 싱글턴 인스턴스
  static final FirestoreLogger _instance = FirestoreLogger._internal();
  factory FirestoreLogger() => _instance;

  FirestoreLogger._internal();

  File? _logFile;

  /// 앱 실행 시 초기화 (파일 생성)
  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/firestore_log.txt');
      if (!await _logFile!.exists()) {
        await _logFile!.create();
      }
      await log('FirestoreLogger initialized at ${_logFile!.path}', level: 'info');
    } catch (e) {
      debugPrint('❌ FirestoreLogger init 실패: $e');
    }
  }

  /// 로그 메시지를 파일에 Append
  ///
  /// [level]은 다음 중 하나를 권장:
  ///   - success
  ///   - error
  ///   - called
  ///   - info (기본값)
  Future<void> log(
      Object? message, { // 🔹 null 허용
        String level = 'info',
      }) async {
    if (_logFile == null) {
      debugPrint('⚠️ FirestoreLogger not initialized. init() 먼저 호출하세요.');
      return;
    }

    final timestamp = DateTime.now().toIso8601String();
    final upperLevel = level.toUpperCase();

    // null 안전 변환 + JSON stringify
    String safeMessage;
    try {
      if (message == null) {
        safeMessage = 'null';
      } else if (message is String) {
        safeMessage = message;
      } else {
        safeMessage = const JsonEncoder.withIndent('  ').convert(message);
      }
    } catch (_) {
      safeMessage = message.toString();
    }

    final formatted = '$timestamp: [$upperLevel] $safeMessage\n';

    try {
      await _logFile!.writeAsString(
        formatted,
        mode: FileMode.append,
        encoding: utf8,
      );
    } catch (e) {
      debugPrint('❌ 로그 기록 실패: $e');
    }
  }

  /// 전체 로그 파일 읽기 (깨진 UTF-8 안전 처리)
  Future<String> readLog() async {
    if (_logFile == null) {
      debugPrint('⚠️ FirestoreLogger not initialized.');
      return '';
    }
    if (!await _logFile!.exists()) {
      debugPrint('⚠️ 로그 파일이 존재하지 않습니다.');
      return '';
    }

    try {
      final lines = await _logFile!
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .toList();
      return lines.join('\n');
    } catch (e) {
      debugPrint('❌ 로그 읽기 실패: $e');
      return '';
    }
  }

  /// 로그 파일 삭제 (전체)
  Future<void> clearLog() async {
    if (_logFile == null) {
      debugPrint('⚠️ FirestoreLogger not initialized.');
      return;
    }
    if (await _logFile!.exists()) {
      try {
        await _logFile!.delete();
        await _logFile!.create();
        await log('로그 파일 초기화됨', level: 'info');
      } catch (e) {
        debugPrint('❌ 로그 초기화 실패: $e');
      }
    }
  }

  /// 특정 시각 이전 로그만 삭제
  Future<void> deleteLogsBefore(DateTime cutoff) async {
    if (_logFile == null) {
      debugPrint('⚠️ FirestoreLogger not initialized.');
      return;
    }
    if (!await _logFile!.exists()) {
      debugPrint('⚠️ 로그 파일이 존재하지 않습니다.');
      return;
    }

    try {
      final allLines = await _logFile!
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .toList();

      final retainedLines = allLines.where((line) {
        final parts = line.split(': ');
        if (parts.isEmpty) return true;
        try {
          final dt = DateTime.parse(parts.first);
          return dt.isAfter(cutoff);
        } catch (_) {
          return true;
        }
      }).toList();

      await _logFile!.writeAsString(
        retainedLines.join('\n') + '\n',
        encoding: utf8,
      );
    } catch (e) {
      debugPrint('❌ 로그 삭제 실패: $e');
    }
  }
}
