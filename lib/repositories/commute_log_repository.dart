import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/hubs_mode/dev_package/debug_package/debug_database_logger.dart';

/// 출근/퇴근/휴게 공통 Firestore 로그 저장 레포지토리
///
/// - 컬렉션: commute_user_logs
/// - 문서: {userId}_clock_in / {userId}_break / {userId}_clock_out
/// - 필드:
///   - userId (메타)
///   - logs: {
///       "2025-11-19": {
///         "userId": "...",
///         "userName": "...",
///         "date": "2025-11-19",
///         "recordedTime": "18:27",
///       },
///       ...
///     }
class CommuteLogRepository {
  final FirebaseFirestore _firestore;

  CommuteLogRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _collectionName = 'commute_user_logs';

  /// 유저 + 상태에 따른 문서 ID 생성
  ///
  /// - "출근" → "{userId}_clock_in"
  /// - "휴게" → "{userId}_break"
  /// - "퇴근" → "{userId}_clock_out"
  /// - 그 외(status가 다른 문자열이면) "{userId}_etc"
  String _buildDocId({
    required String userId,
    required String status,
  }) {
    final suffix = _statusToSuffix(status);
    return '${userId}_$suffix';
  }

  String _statusToSuffix(String status) {
    switch (status) {
      case '출근':
        return 'clock_in';
      case '휴게':
        return 'break';
      case '퇴근':
        return 'clock_out';
      default:
        return 'etc';
    }
  }

  DateTime? _parseYmd(String s) {
    final parts = s.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// 해당 유저/상태/날짜에 이미 로그가 있는지 확인
  ///
  /// - true  → logs.{dateStr} 가 이미 존재
  /// - false → 없거나, 에러/파싱 문제로 확인 실패(이 경우 새로 작성 허용)
  Future<bool> hasLogForDate({
    required String status,
    required String userId,
    required String dateStr,
  }) async {
    try {
      final docId = _buildDocId(userId: userId, status: status);
      final docRef = _firestore.collection(_collectionName).doc(docId);
      final snap = await docRef.get();

      if (!snap.exists) return false;
      final data = snap.data();
      if (data == null) return false;

      final logs = data['logs'];
      if (logs is Map<String, dynamic>) {
        final exists = logs[dateStr] != null;
        return exists;
      }
      return false;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log(
          {
            'op': 'commute_user_logs.hasLogForDate',
            'status': status,
            'userId': userId,
            'date': dateStr,
            'error': e.toString(),
            'stack': st.toString(),
          },
          level: 'error',
          tags: ['firestore', 'commute_user_logs', 'check_duplicate'],
        );
      } catch (_) {}
      return false;
    }
  }

  /// 유저 당 출근/휴게/퇴근 문서 1개에 날짜별 로그를 쌓는 메서드
  ///
  /// - logs.{dateStr} 에 해당 날짜의 로그 1건을 저장 (merge)
  Future<void> addLog({
    required String status,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required String dateStr,
    required String recordedTime,
    required DateTime dateTime,
  }) async {
    try {
      final docId = _buildDocId(userId: userId, status: status);
      final docRef = _firestore.collection(_collectionName).doc(docId);

      // 🔹 Firestore에는 요구하신 4개 필드만 저장
      final logEntry = <String, dynamic>{
        'userId': userId,
        'userName': userName,
        'date': dateStr,
        'recordedTime': recordedTime,
      };

      await docRef.set(
        {
          'userId': userId,
          'logs': {
            dateStr: logEntry,
          },
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log(
          {
            'op': 'commute_user_logs.set',
            'status': status,
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'date': dateStr,
            'recordedTime': recordedTime,
            'eventDateTime': dateTime.toIso8601String(),
            'error': e.toString(),
            'stack': st.toString(),
          },
          level: 'error',
          tags: ['firestore', 'commute_user_logs', status],
        );
      } catch (_) {}
    }
  }

  /// (신규) 월 단위 조회: 특정 유저/상태 문서의 logs 중 year/month만 골라 day->HH:mm 반환
  Future<Map<int, String>> getMonthlyTimes({
    required String status,
    required String userId,
    required int year,
    required int month,
  }) async {
    final docId = _buildDocId(userId: userId, status: status);
    final docRef = _firestore.collection(_collectionName).doc(docId);

    final snap = await docRef.get();
    if (!snap.exists) return {};

    final data = snap.data();
    if (data == null) return {};

    final logs = data['logs'];
    if (logs is! Map) return {};

    final result = <int, String>{};

    for (final e in logs.entries) {
      final dateStr = e.key.toString();
      final dt = _parseYmd(dateStr);
      if (dt == null) continue;
      if (dt.year != year || dt.month != month) continue;

      final entry = e.value;
      if (entry is Map) {
        final recordedTime = entry['recordedTime']?.toString() ?? '';
        final t = recordedTime.trim();
        if (t.isNotEmpty) {
          result[dt.day] = t;
        }
      }
    }

    return result;
  }

  /// (신규) 배치 업서트: logs.{dateStr}들에 기록을 merge로 저장
  ///
  /// - dateToTime: key=yyyy-MM-dd, value=HH:mm
  /// - time이 비어있으면 해당 날짜는 저장하지 않음(삭제는 deleteLogsForDates 사용)
  Future<void> upsertLogsForDates({
    required String status,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required Map<String, String> dateToTime,
  }) async {
    if (dateToTime.isEmpty) return;

    final docId = _buildDocId(userId: userId, status: status);
    final docRef = _firestore.collection(_collectionName).doc(docId);

    final logsPayload = <String, dynamic>{};
    dateToTime.forEach((dateStr, time) {
      final t = time.trim();
      if (t.isEmpty) return;

      logsPayload[dateStr] = <String, dynamic>{
        'userId': userId,
        'userName': userName,
        'date': dateStr,
        'recordedTime': t,
      };
    });

    if (logsPayload.isEmpty) return;

    await docRef.set(
      {
        'userId': userId,
        'logs': logsPayload,
      },
      SetOptions(merge: true),
    );
  }

  /// (신규) 배치 삭제: logs.{dateStr} 키들을 FieldValue.delete로 제거 (merge set)
  ///
  /// - 문서가 없어도 set(merge)이므로 안전하게 처리되며,
  ///   삭제 대상이 없어도 no-op에 가깝게 동작합니다.
  Future<void> deleteLogsForDates({
    required String status,
    required String userId,
    required Iterable<String> dateStrs,
  }) async {
    final dates = dateStrs.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (dates.isEmpty) return;

    final docId = _buildDocId(userId: userId, status: status);
    final docRef = _firestore.collection(_collectionName).doc(docId);

    final logsPayload = <String, dynamic>{};
    for (final d in dates) {
      logsPayload[d] = FieldValue.delete();
    }

    await docRef.set(
      {
        'userId': userId,
        'logs': logsPayload,
      },
      SetOptions(merge: true),
    );
  }

  /// (신규) 단일 삭제(필요 시)
  Future<void> deleteLogForDate({
    required String status,
    required String userId,
    required String dateStr,
  }) async {
    await deleteLogsForDates(status: status, userId: userId, dateStrs: [dateStr]);
  }
}
