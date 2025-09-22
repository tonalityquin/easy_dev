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
  Future<void>? _initFuture;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    var id = sp.getString('installId');
    if (id == null) {
      id = const Uuid().v4();
      await sp.setString('installId', id);
    }
    _installId = id;
  }

  Future<void> ensureInitialized() {
    return _initFuture ??= init();
  }

  Future<String> getInstallId() async {
    await ensureInitialized();
    final id = _installId;
    if (id == null) {
      throw StateError('UsageReporter 초기화 실패');
    }
    return id;
  }

  String get installId {
    final id = _installId;
    if (id == null) {
      throw StateError('UsageReporter.init()을 먼저 호출하세요.');
    }
    return id;
  }

  /// 메서드/화면명을 slug로 변환해 문서 ID로 안전하게 사용
  String _slug(String s) {
    final lower = s.trim().toLowerCase();
    // 영문/숫자/언더스코어/하이픈/점만 남기고 나머지는 하이픈으로
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9_\-\.]+'), '-');
    // 길이 과도 방지(문서 ID 제한 충분히 넉넉하지만 안전 차원)
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  /// 사용량 보고
  /// [area]: 테넌트/기업 식별자
  /// [action]: "read"|"write"|"delete"
  /// [n]: 문서/연산 개수
  /// [source]: 비용 발생 지점(메서드/화면명). 예) "PlateQueryService.getPlate"
  ///
  /// 보고 경로:
  /// usage_daily/{YYYY-MM-DD}/tenants/{area}/users/{installId__[slug(source)]}
  Future<void> report({
    required String area,
    required String action,
    int n = 1,
    String? source,
  }) async {
    assert(action == 'read' || action == 'write' || action == 'delete');

    await ensureInitialized();
    final baseId = installId;
    final userKey = (source == null || source.trim().isEmpty)
        ? baseId
        : '${baseId}__${_slug(source)}';

    final date = DateTime.now().toUtc().toIso8601String().substring(0, 10); // YYYY-MM-DD
    final eventId = const Uuid().v4();

    final countRef = _db
        .collection('usage_daily').doc(date)
        .collection('tenants').doc(area)
        .collection('users').doc(userKey);

    final eventRef = countRef.collection('events').doc(eventId);

    await _db.runTransaction((tx) async {
      final evt = await tx.get(eventRef);
      if (evt.exists) return; // 멱등

      // 이벤트 기록(규칙상 허용 키만)
      tx.set(eventRef, {
        'action': action,
        'n': n,
        'at': FieldValue.serverTimestamp(),
      });

      final incField = '${action}s'; // reads/writes/deletes
      tx.set(countRef, {
        'date': date,
        'tenantId': area,
        'userId': userKey,
        incField: FieldValue.increment(n),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}

