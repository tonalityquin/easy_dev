import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmailConfig {
  final String to;

  const EmailConfig({required this.to});

  static const _kMailToKey = 'mail.to';

  static String _defaultTo() => '';

  static Future<EmailConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final to = (prefs.getString(_kMailToKey) ?? _defaultTo()).trim();
    return EmailConfig(to: to);
  }

  static Future<void> save(EmailConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMailToKey, cfg.to.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMailToKey, _defaultTo());
  }

  static Future<void> replaceRecipient(String value) async {
    final normalized = value.trim();
    if (!isValidToList(normalized)) {
      throw FormatException('유효하지 않은 수신자 이메일입니다.');
    }

    final prefs = await SharedPreferences.getInstance();
    final previous = (prefs.getString(_kMailToKey) ?? '').trim();

    debugPrint(
      '[EmailConfig] 수신자 이메일 교체 시작: previousPresent=${previous.isNotEmpty} previousLength=${previous.length} nextLength=${normalized.length}',
    );

    try {
      final removed = await prefs.remove(_kMailToKey);
      await prefs.reload();

      if (prefs.containsKey(_kMailToKey)) {
        throw StateError('기존 수신자 이메일 로컬값 삭제 검증 실패');
      }

      debugPrint(
        '[EmailConfig] 기존 수신자 이메일 삭제 완료: removed=$removed',
      );

      final saved = await prefs.setString(_kMailToKey, normalized);
      if (!saved) {
        throw StateError('새 수신자 이메일 로컬 저장 실패');
      }

      await prefs.reload();
      final verified = (prefs.getString(_kMailToKey) ?? '').trim();
      if (verified != normalized) {
        throw StateError('새 수신자 이메일 로컬 저장 검증 실패');
      }

      debugPrint(
        '[EmailConfig] 새 수신자 이메일 저장 및 검증 완료: length=${verified.length}',
      );
    } catch (error) {
      try {
        if (previous.isEmpty) {
          await prefs.remove(_kMailToKey);
        } else {
          await prefs.setString(_kMailToKey, previous);
        }
        await prefs.reload();
        final rollbackValue = (prefs.getString(_kMailToKey) ?? '').trim();
        if (rollbackValue != previous) {
          throw StateError('수신자 이메일 교체 롤백 검증 실패');
        }
        debugPrint(
          '[EmailConfig] 수신자 이메일 교체 실패로 기존 값 복구 완료: restoredPresent=${previous.isNotEmpty} restoredLength=${previous.length}',
        );
      } catch (rollbackError) {
        debugPrint(
          '[EmailConfig] 수신자 이메일 교체 롤백 실패: $rollbackError',
        );
      }
      rethrow;
    }
  }

  static Future<void> restoreRecipient(String value) async {
    final normalized = value.trim();
    final prefs = await SharedPreferences.getInstance();

    if (normalized.isEmpty) {
      await prefs.remove(_kMailToKey);
    } else {
      final saved = await prefs.setString(_kMailToKey, normalized);
      if (!saved) {
        throw StateError('수신자 이메일 롤백 저장 실패');
      }
    }

    await prefs.reload();
    final verified = (prefs.getString(_kMailToKey) ?? '').trim();
    if (verified != normalized) {
      throw StateError('수신자 이메일 롤백 검증 실패');
    }

    debugPrint(
      '[EmailConfig] 수신자 이메일 롤백 값 복원 완료: restoredPresent=${normalized.isNotEmpty} restoredLength=${normalized.length}',
    );
  }

  static bool isValidToList(String csv) {
    final list = csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    if (list.isEmpty) return false;
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    for (final addr in list) {
      if (!regex.hasMatch(addr)) return false;
    }
    return true;
  }
}
