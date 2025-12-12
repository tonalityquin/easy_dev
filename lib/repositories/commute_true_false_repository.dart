import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// commute_true_false 컬렉션에
/// - 문서: 회사명(company)
/// - 필드: 지역명(area) → Map<사용자명, Timestamp>
/// 형태로 "출근 버튼을 누른 시각"을 저장/업데이트하는 레포지토리.
///
/// Firestore 실제 구조 예시:
///
/// commute_true_false (컬렉션)
///   └─ belivus (doc: company)
///        └─ belivus (field: area, Map)
///             ├─ "Quintus Facere": <Timestamp>
///             └─ "admin111": <Timestamp>
///
/// ⚠️ 주의:
///   - 쓰기 시에는 `'$area.$workerName'` 같은 "필드 경로"를 사용해
///     해당 사용자만 업데이트하고, 같은 area 안의 다른 사용자 값은 보존합니다.
///   - 퇴근(workOut) 시에는 이 컬렉션을 건드리지 않는 정책입니다. (호출 금지)
class CommuteTrueFalseRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 출근 시각(버튼 클릭 시각)을 기록합니다.
  ///
  /// - 컬렉션: commute_true_false
  /// - 문서 ID: company
  /// - 필드 경로: "<area>.<workerName>" → Timestamp
  ///
  /// `SetOptions(merge: true)` + 필드 경로 사용으로,
  /// 같은 area 맵 내 다른 사용자 값은 절대 삭제되지 않습니다.
  Future<void> setClockInAt({
    required String company,
    required String area,
    required String workerName,
    required DateTime clockInAt,
  }) async {
    final trimmedCompany = company.trim();
    final trimmedArea = area.trim();
    final trimmedWorkerName = workerName.trim();

    if (trimmedCompany.isEmpty ||
        trimmedArea.isEmpty ||
        trimmedWorkerName.isEmpty) {
      debugPrint(
        '[CommuteTrueFalseRepository] 빈 값(company/area/workerName) → 업데이트 스킵 '
            '(company="$trimmedCompany", area="$trimmedArea", workerName="$trimmedWorkerName")',
      );
      return;
    }

    // dot-notation 필드 경로를 쓰므로 '.' 포함 시 경로 깨짐
    if (trimmedArea.contains('.') || trimmedWorkerName.contains('.')) {
      debugPrint(
        '[CommuteTrueFalseRepository] area/workerName 에 "." 포함 → 필드 경로 충돌 가능. 업데이트 스킵 '
            '(area="$trimmedArea", workerName="$trimmedWorkerName")',
      );
      return;
    }

    // Firestore 내부 예약 패턴 회피(안전장치)
    if (trimmedArea.startsWith('__') || trimmedWorkerName.startsWith('__')) {
      debugPrint(
        '[CommuteTrueFalseRepository] area/workerName 이 "__"로 시작 → 업데이트 스킵 '
            '(area="$trimmedArea", workerName="$trimmedWorkerName")',
      );
      return;
    }

    try {
      final docRef =
      _firestore.collection('commute_true_false').doc(trimmedCompany);

      await docRef.set(
        <String, Object?>{
          '$trimmedArea.$trimmedWorkerName': Timestamp.fromDate(clockInAt),
        },
        SetOptions(merge: true),
      );

      debugPrint(
        '[CommuteTrueFalseRepository] 출근 시각 업데이트 완료 '
            'company="$trimmedCompany", area="$trimmedArea", workerName="$trimmedWorkerName", '
            'clockInAt="$clockInAt"',
      );
    } catch (e, st) {
      debugPrint('[CommuteTrueFalseRepository] Firestore 업데이트 오류: $e\n$st');
    }
  }
}
