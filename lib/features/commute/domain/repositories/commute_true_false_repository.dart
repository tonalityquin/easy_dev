import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';


















class CommuteTrueFalseRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  
  
  
  
  
  
  
  
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

    
    if (trimmedArea.contains('.') || trimmedWorkerName.contains('.')) {
      debugPrint(
        '[CommuteTrueFalseRepository] area/workerName 에 "." 포함 → 필드 경로 충돌 가능. 업데이트 스킵 '
            '(area="$trimmedArea", workerName="$trimmedWorkerName")',
      );
      return;
    }

    
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


  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Map<String, Map<String, Object?>> _normalizeByArea(Map<String, dynamic> raw) {
    final Map<String, Map<String, Object?>> grouped = {};

    void put(String area, String worker, Object? value) {
      final a = area.trim();
      final w = worker.trim();
      if (a.isEmpty || w.isEmpty) return;
      grouped.putIfAbsent(a, () => <String, Object?>{});
      grouped[a]![w] = value;
    }

    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      final maybeMap = _asMap(value);
      if (maybeMap != null) {
        for (final w in maybeMap.entries) {
          put(key, w.key.toString(), w.value);
        }
        continue;
      }

      final dot = key.indexOf('.');
      if (dot > 0 && dot < key.length - 1) {
        final area = key.substring(0, dot);
        final worker = key.substring(dot + 1);
        put(area, worker, value);
        continue;
      }

      put('(기타)', key, value);
    }

    return grouped;
  }

  Future<Map<String, Map<String, Object?>>> loadGroupedByDivision(String division) async {
    final trimmedDivision = division.trim();
    if (trimmedDivision.isEmpty) return <String, Map<String, Object?>>{};

    final doc = await _firestore.collection('commute_true_false').doc(trimmedDivision).get();
    if (!doc.exists) return <String, Map<String, Object?>>{};
    return _normalizeByArea(doc.data() ?? <String, dynamic>{});
  }

  Future<void> deleteWorker({
    required String division,
    required String area,
    required String worker,
  }) async {
    final trimmedDivision = division.trim();
    final trimmedArea = area.trim();
    final trimmedWorker = worker.trim();
    if (trimmedDivision.isEmpty || trimmedArea.isEmpty || trimmedWorker.isEmpty) {
      return;
    }

    final docRef = _firestore.collection('commute_true_false').doc(trimmedDivision);
    await docRef.update(<Object, Object?>{
      FieldPath(<String>[trimmedArea, trimmedWorker]): FieldValue.delete(),
      FieldPath(<String>['$trimmedArea.$trimmedWorker']): FieldValue.delete(),
    });
  }

}
