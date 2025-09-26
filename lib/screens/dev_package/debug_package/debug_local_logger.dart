import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DebugLocalLogger {
  // ---- Singleton ----
  static final DebugLocalLogger _instance = DebugLocalLogger._internal();

  factory DebugLocalLogger() => _instance;

  DebugLocalLogger._internal();

  // ---- Config ----
  static const String _baseName = 'local_log.txt';
  static const int _maxFileBytes = 2 * 1024 * 1024; // 2MB 넘으면 회전
  static const int _maxTailBytes = 1024 * 1024; // tail 읽기 1MB
  static const int _maxTailLines = 1500;
  static const int _rotateKeep = 2; // .1, .2 까지 유지

  File? _logFile;
  Directory? _dir;

  // 간단한 쓰기 체이닝(동시성 제어)
  Future<void> _pending = Future.value();

  // ---- Init ----
  Future<void> init() async {
    try {
      _dir ??= await getApplicationDocumentsDirectory();
      _logFile ??= File('${_dir!.path}/$_baseName');

      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }

      /*
      await log({
        'ts': DateTime.now().toIso8601String(),
        'level': 'info',
        'message': 'logger initialized',
        'tags': ['init']
      }, level: 'info');
      */
    } catch (e) {
      debugPrint('❌ DebugLocalLogger init 실패: $e');
    }
  }

  File? getLogFile() => _logFile;

  // ---- Public: Logging ----
  Future<void> log(Object? message, {String level = 'info', List<String>? tags}) async {
    // 실패(에러) 로그만 기록
    if (level.toLowerCase() != 'error') return;

    _pending = _pending.then((_) => _doLog(message, level: level, tags: tags));
    return _pending;
  }

  Future<void> _doLog(Object? message, {required String level, List<String>? tags}) async {
    try {
      if (_logFile == null) {
        await init();
        if (_logFile == null) return;
      }

      final now = DateTime.now().toIso8601String();
      final entry = _toLine(message, level: level, ts: now, tags: tags);
      await _rotateIfNeeded();
      await _logFile!.writeAsString(entry, mode: FileMode.append, encoding: utf8);
    } catch (e) {
      debugPrint('❌ 로그 기록 실패: $e');
    }
  }

  String _toLine(Object? message, {required String level, required String ts, List<String>? tags}) {
    // JSON 라인으로 통일(파서가 JSON 우선)
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

    final m = <String, Object?>{
      'ts': ts,
      'level': level,
      'message': safeMessage,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
    };
    return '${jsonEncode(m)}\n';
  }

  // ---- Rotation ----
  Future<void> _rotateIfNeeded() async {
    if (_logFile == null || _dir == null) return;
    try {
      final size = await _logFile!.length();
      if (size < _maxFileBytes) return;

      final f0 = _logFile!;
      final f1 = File('${_dir!.path}/local_log.1.txt');
      final f2 = File('${_dir!.path}/local_log.2.txt');

      // 오래된 순서로 삭제/이동
      if (_rotateKeep >= 2) {
        try {
          if (await f2.exists()) {
            await f2.delete();
          }
        } catch (_) {}
        try {
          if (await f1.exists()) {
            await f1.rename(f2.path);
          }
        } catch (_) {}
      }
      try {
        if (await f0.exists()) {
          await f0.rename(f1.path);
        }
      } catch (_) {}

      // 새 로그 파일 생성
      _logFile = File('${_dir!.path}/$_baseName');
      await _logFile!.create(recursive: true);
      await _logFile!.writeAsString(
        '${jsonEncode({'ts': DateTime.now().toIso8601String(), 'level': 'info', 'message': 'log rotated'})}\n',
        mode: FileMode.append,
        encoding: utf8,
      );
    } catch (e) {
      debugPrint('❌ rotateIfNeeded 실패: $e');
    }
  }

  // ---- Read: Tail only (빠름) ----
  Future<List<String>> readTailLines({int maxLines = _maxTailLines, int maxBytes = _maxTailBytes}) async {
    try {
      if (_logFile == null) await init();
      if (_logFile == null || !await _logFile!.exists()) return const [];

      final length = await _logFile!.length();
      final start = length > maxBytes ? length - maxBytes : 0;

      final raf = await _logFile!.open();
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(length - start);
        final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
        var lines = const LineSplitter().convert(text);
        // start > 0 이면 첫 줄은 중간에서 잘린 라인일 수 있으니 버림(옵션)
        if (start > 0 && lines.isNotEmpty) {
          lines = lines.sublist(1);
        }
        if (lines.length > maxLines) {
          lines = lines.sublist(lines.length - maxLines);
        }
        return lines;
      } finally {
        await raf.close();
      }
    } catch (e) {
      debugPrint('❌ readTailLines 실패: $e');
      return const [];
    }
  }

  // ---- Read: 전체(회전 포함) ----
  Future<List<String>> readAllLinesCombined() async {
    try {
      if (_logFile == null) await init();
      final files = await getAllLogFilesExisting(orderedOldestFirst: true);
      final all = <String>[];

      for (final f in files) {
        final lines = await f
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .toList();
        all.addAll(lines);
      }
      return all;
    } catch (e) {
      debugPrint('❌ readAllLinesCombined 실패: $e');
      return const [];
    }
  }

  // ---- Export용: 존재하는 모든 로그 파일 반환 ----
  Future<List<File>> getAllLogFilesExisting({bool orderedOldestFirst = false}) async {
    if (_dir == null) await init();
    if (_dir == null) return const [];

    final f0 = File('${_dir!.path}/$_baseName');
    final f1 = File('${_dir!.path}/local_log.1.txt');
    final f2 = File('${_dir!.path}/local_log.2.txt');

    final list = <File>[];
    if (orderedOldestFirst) {
      if (await f2.exists()) list.add(f2);
      if (await f1.exists()) list.add(f1);
      if (await f0.exists()) list.add(f0);
    } else {
      if (await f0.exists()) list.add(f0);
      if (await f1.exists()) list.add(f1);
      if (await f2.exists()) list.add(f2);
    }
    return list;
  }

  // ---- Clear: 전체 삭제 후 재생성 ----
  Future<void> clearLog() async {
    try {
      if (_dir == null) await init();
      if (_dir == null) return;

      final files = await getAllLogFilesExisting();
      for (final f in files) {
        try {
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }

      _logFile = File('${_dir!.path}/$_baseName');
      await _logFile!.create(recursive: true);
      await _logFile!.writeAsString(
        '${jsonEncode({'ts': DateTime.now().toIso8601String(), 'level': 'info', 'message': 'log cleared'})}\n',
        mode: FileMode.append,
        encoding: utf8,
      );
    } catch (e) {
      debugPrint('❌ clearLog 실패: $e');
    }
  }
}
