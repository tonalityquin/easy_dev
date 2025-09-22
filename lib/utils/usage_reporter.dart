// lib/utils/usage_reporter.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 설치 단위 사용량(읽기/쓰기/삭제)을 Firestore에 자가-보고.
/// - 인증 없이 동작 (자가 보고 특성상 조작 방지 한계)
/// - events/{eventId}로 멱등 처리(중복 방지)
class UsageReporter {
  UsageReporter._();
  static final UsageReporter instance = UsageReporter._();

  final _db = FirebaseFirestore.instance;

  String? _installId;
  Future<void>? _initFuture; // ✅ hot restart/중복 초기화 대비

  /// 내부 초기화: installId 생성·보관
  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    var id = sp.getString('installId');
    if (id == null) {
      id = const Uuid().v4();
      await sp.setString('installId', id);
    }
    _installId = id;
  }

  /// ✅ 안전 초기화: 중복 호출 시 동일 Future 반환
  Future<void> ensureInitialized() {
    return _initFuture ??= init();
  }

  /// ✅ 비동기로 installId 얻기 (ensure 포함)
  Future<String> getInstallId() async {
    await ensureInitialized();
    final id = _installId;
    if (id == null) {
      throw StateError('UsageReporter 초기화 실패');
    }
    return id;
  }

  /// (동기) installId 접근 — 초기화 전이면 예외
  String get installId {
    final id = _installId;
    if (id == null) {
      throw StateError('UsageReporter.init()을 먼저 호출하세요.');
    }
    return id;
  }

  /// 사용량 보고
  /// [area]: 테넌트/기업 식별자, [action]: "read"|"write"|"delete", [n]: 문서 개수
  Future<void> report({
    required String area,
    required String action,
    int n = 1,
  }) async {
    assert(action == 'read' || action == 'write' || action == 'delete');

    // ✅ 항상 초기화 보장
    await ensureInitialized();
    final id = installId;

    final date = DateTime.now().toUtc().toIso8601String().substring(0, 10); // YYYY-MM-DD
    final eventId = const Uuid().v4();

    final countRef = _db
        .collection('usage_daily').doc(date)
        .collection('tenants').doc(area)
        .collection('users').doc(id);

    final eventRef = countRef.collection('events').doc(eventId);

    await _db.runTransaction((tx) async {
      final evt = await tx.get(eventRef);
      if (evt.exists) {
        return; // 멱등: 이미 처리됨
      }

      // 1) 이벤트 기록
      tx.set(eventRef, {
        'action': action,
        'n': n,
        'at': FieldValue.serverTimestamp(),
      });

      // 2) 카운터 증가
      final incField = '${action}s'; // reads/writes/deletes
      tx.set(countRef, {
        'date': date,
        'tenantId': area,
        'userId': id,
        incField: FieldValue.increment(n),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}
