import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 로그 레벨
enum DebugLogLevel { info, success, error, called, warn }

/// 파일 기반 디버그 로거 (싱글턴)
/// - JSON Lines 포맷 권장(라인별 {"ts","level","message","tags":[...]})
/// - 기존 "ISO: [LEVEL] message" 문자열 라인도 읽기 호환
/// - 파일이 커지면 회전(분할 저장): base + .1 ~ .N
/// - tail-only 읽기 제공: 아주 큰 파일에서도 초고속 진입
class DebugFirestoreLogger {
  static final DebugFirestoreLogger _instance = DebugFirestoreLogger._internal();
  factory DebugFirestoreLogger() => _instance;
  DebugFirestoreLogger._internal();

  // ---------- 설정 ----------
  // 회전 기준 크기(바이트)
  static const int _maxFileBytes = 5 * 1024 * 1024; // 5MB
  // 회전 파일 개수 (base + 1.._maxRotations)
  static const int _maxRotations = 5;
  // 테일 읽기 기본 바이트 윈도(대략 최근 1MB 근처)
  static const int _defaultTailBytes = 1024 * 1024;

  File? _baseFile; // firestore_log.txt
  bool _initialized = false;

  // I/O 직렬화 큐
  Future<void> _op = Future.value();
  bool _rotating = false;

  /// 앱 시작 시 호출 권장
  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      debugPrint('⚠️ DebugFirestoreLogger: Web에서는 파일 기반 로깅 비활성화.');
      _initialized = true;
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      _baseFile = File('${dir.path}/firestore_log.txt');
      if (!await _baseFile!.exists()) {
        await _baseFile!.create(recursive: true);
      }
      _initialized = true;
      await info('Logger initialized at ${_baseFile!.path}');
    } catch (e) {
      debugPrint('❌ FirestoreLogger init 실패: $e');
      _initialized = true;
    }
  }

  File? getLogFile() => _baseFile;

  // ---------- 편의 메서드 ----------
  Future<void> info(Object? m, {Iterable<String>? tags}) =>
      log(m, level: DebugLogLevel.info, tags: tags);
  Future<void> success(Object? m, {Iterable<String>? tags}) =>
      log(m, level: DebugLogLevel.success, tags: tags);
  Future<void> error(Object? m, {Iterable<String>? tags}) =>
      log(m, level: DebugLogLevel.error, tags: tags);
  Future<void> called(Object? m, {Iterable<String>? tags}) =>
      log(m, level: DebugLogLevel.called, tags: tags);
  Future<void> warn(Object? m, {Iterable<String>? tags}) =>
      log(m, level: DebugLogLevel.warn, tags: tags);

  /// 로그 기록 (JSONL 권장)
  Future<void> log(
      Object? message, {
        DebugLogLevel level = DebugLogLevel.info,
        Iterable<String>? tags,
      }) async {
    if (!_initialized) await init();
    if (kIsWeb || _baseFile == null) {
      debugPrint('[${DateTime.now().toIso8601String()}] [${level.name}] $message');
      return;
    }

    final ts = DateTime.now().toIso8601String();
    final map = <String, dynamic>{
      'ts': ts,
      'level': level.name,
      'message': _safeToString(message),
    };
    if (tags != null && tags.isNotEmpty) {
      map['tags'] = tags.toList();
    }
    final line = jsonEncode(map) + '\n';

    _op = _op.then((_) async {
      try {
        await _baseFile!.writeAsString(line, mode: FileMode.append, encoding: utf8);
        await _rotateIfNeeded();
      } catch (e) {
        debugPrint('❌ 로그 기록 실패: $e');
      }
    });
    await _op;
  }

  String _safeToString(Object? message) {
    if (message == null) return 'null';
    if (message is String) return message;
    try {
      return const JsonEncoder.withIndent('  ').convert(message);
    } catch (_) {
      return message.toString();
    }
  }

  /// 파일 크기가 임계값 초과 시 회전
  Future<void> _rotateIfNeeded() async {
    if (_rotating) return;
    if (_baseFile == null || !await _baseFile!.exists()) return;

    final size = await _baseFile!.length();
    if (size <= _maxFileBytes) return;

    _rotating = true;
    try {
      final dir = _baseFile!.parent.path;
      final base = _baseFile!.path;

      // .(max-1) -> .max, ..., .1 -> .2
      for (int i = _maxRotations - 1; i >= 1; i--) {
        final src = File('$dir/firestore_log.$i.txt');
        final dst = File('$dir/firestore_log.${i + 1}.txt');
        if (await src.exists()) {
          try {
            if (await dst.exists()) await dst.delete();
            await src.rename(dst.path);
          } catch (e) {
            debugPrint('⚠️ 회전 rename 실패: ${src.path} -> ${dst.path} ($e)');
          }
        }
      }

      // base -> .1
      final one = File('$dir/firestore_log.1.txt');
      try {
        if (await one.exists()) await one.delete();
        await _baseFile!.rename(one.path);
      } catch (e) {
        debugPrint('⚠️ base 회전 실패: $e');
      }

      // 새 base 파일 생성
      _baseFile = File(base);
      await _baseFile!.create(recursive: true);
      await info('log rotated'); // 회전 로그 남김(새 파일)

    } catch (e) {
      debugPrint('❌ rotate 실패: $e');
    } finally {
      _rotating = false;
    }
  }

  /// 전체 텍스트 읽기(현재 base만)
  Future<String> readLog() async {
    if (!_initialized) await init();
    if (kIsWeb) return '⚠️ Web 빌드에서는 파일 로그를 사용할 수 없습니다.';
    if (_baseFile == null || !await _baseFile!.exists()) return '';
    try {
      final stream = _baseFile!
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true));
      final buf = StringBuffer();
      await for (final chunk in stream) {
        buf.write(chunk);
      }
      return buf.toString();
    } catch (e) {
      debugPrint('❌ 로그 읽기 실패: $e');
      return '';
    }
  }

  /// 전체 라인(현재 base만)
  Future<List<String>> readLines() async {
    final text = await readLog();
    if (text.isEmpty) return const [];
    return const LineSplitter()
        .convert(text)
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  /// 테일 텍스트(마지막 maxBytes 근처만)
  Future<String> readTail({int maxBytes = _defaultTailBytes}) async {
    if (!_initialized) await init();
    if (kIsWeb || _baseFile == null || !await _baseFile!.exists()) return '';
    try {
      final raf = await _baseFile!.open();
      final len = await raf.length();
      final start = (len > maxBytes) ? (len - maxBytes) : 0;
      await raf.setPosition(start);
      final bytes = await raf.read(len - start);
      await raf.close();
      return const Utf8Decoder(allowMalformed: true).convert(bytes);
    } catch (e) {
      debugPrint('❌ tail 읽기 실패: $e');
      return '';
    }
  }

  /// 테일 라인(기본: 최대 1500줄 / ~1MB 범위)
  Future<List<String>> readTailLines({
    int maxLines = 1500,
    int maxBytes = _defaultTailBytes,
  }) async {
    final text = await readTail(maxBytes: maxBytes);
    if (text.isEmpty) return const [];
    final lines = const LineSplitter()
        .convert(text)
        .where((e) => e.trim().isNotEmpty)
        .toList();
    // 끝에서부터 maxLines만 취함
    if (lines.length <= maxLines) return lines;
    return lines.sublist(lines.length - maxLines);
  }

  /// 회전 포함 전체 라인 읽기(오래 걸릴 수 있음)
  Future<List<String>> readAllLinesCombined() async {
    if (!_initialized) await init();
    if (kIsWeb) return const [];

    final files = await getAllLogFilesExisting(); // oldest..newest 순서로 반환
    final out = <String>[];

    for (final f in files) {
      try {
        final text = await f
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .join();
        if (text.isEmpty) continue;
        out.addAll(const LineSplitter()
            .convert(text)
            .where((e) => e.trim().isNotEmpty));
      } catch (e) {
        debugPrint('⚠️ 읽기 실패: ${f.path} ($e)');
      }
    }
    return out;
  }

  /// 회전 파일 포함 존재하는 파일 목록을 "오래된 것 → 최신(base)" 순으로 반환
  Future<List<File>> getAllLogFilesExisting() async {
    if (_baseFile == null) return const [];
    final dir = _baseFile!.parent.path;
    final files = <File>[];

    // oldest..newest: .$_maxRotations ↓ .1 ↓ base
    for (int i = _maxRotations; i >= 1; i--) {
      final f = File('$dir/firestore_log.$i.txt');
      if (await f.exists()) files.add(f);
    }
    if (await _baseFile!.exists()) files.add(_baseFile!);
    return files;
  }

  /// 로그 초기화
  Future<void> clearLog() async {
    if (!_initialized) await init();
    if (kIsWeb || _baseFile == null) return;

    _op = _op.then((_) async {
      try {
        // 회전 파일도 함께 제거
        for (final f in await getAllLogFilesExisting()) {
          if (await f.exists()) await f.delete();
        }
        await _baseFile!.create(recursive: true);
        await info('로그 파일 초기화됨');
      } catch (e) {
        debugPrint('❌ 로그 초기화 실패: $e');
      }
    });
    await _op;
  }

  /// 특정 시각 이전 로그 삭제 (회전 포함)
  Future<void> deleteLogsBefore(DateTime cutoff) async {
    if (!_initialized) await init();
    if (kIsWeb || _baseFile == null) return;

    Future<void> _filterFile(File f) async {
      if (!await f.exists()) return;
      try {
        final text = await f
            .openRead()
            .transform(const Utf8Decoder(allowMalformed: true))
            .join();
        if (text.isEmpty) return;
        final lines = const LineSplitter().convert(text);
        final retained = <String>[];

        for (final line in lines) {
          final ts = _extractTimestamp(line);
          if (ts == null || ts.isAfter(cutoff)) {
            if (line.trim().isNotEmpty) retained.add(line);
          }
        }
        await f.writeAsString(retained.join('\n') + '\n', encoding: utf8);
      } catch (e) {
        debugPrint('❌ 로그 삭제 실패(${f.path}): $e');
      }
    }

    _op = _op.then((_) async {
      for (final f in await getAllLogFilesExisting()) {
        await _filterFile(f);
      }
    });
    await _op;
  }

  /// 타임스탬프 추출(JSON 우선 → 레거시)
  DateTime? _extractTimestamp(String line) {
    try {
      final m = jsonDecode(line);
      if (m is Map && m['ts'] is String) {
        return DateTime.tryParse(m['ts'] as String);
      }
    } catch (_) {}
    final idx = line.indexOf(': ');
    if (idx > 0) {
      final tsStr = line.substring(0, idx);
      return DateTime.tryParse(tsStr);
    }
    return null;
  }
}
