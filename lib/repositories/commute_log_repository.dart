import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/dev_package/debug_package/debug_database_logger.dart';

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
      // 여기서 에러난다고 해서 출근/퇴근 버튼 자체를 막고 싶지는 않으니
      // 조용히 로그만 남기고 false(없다고 간주) 리턴 → addLog 쪽에서 새 로그 작성.
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
  /// - 컬렉션: commute_user_logs
  /// - 문서 ID: "{userId}_clock_in" / "{userId}_break" / "{userId}_clock_out"
  /// - logs.{dateStr} 에 해당 날짜의 로그 1건을 저장
  ///
  /// (중복 체크는 호출 측에서 hasLogForDate(...)로 선행하는 구조)
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
          'userId': userId, // 문서 메타로 userId만 유지
          'logs': {
            dateStr: logEntry,
          },
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      // Firestore 기록 실패는 "보조 기능"이므로
      // 호출 측(출근/퇴근/휴게 업로더)에 예외를 다시 던지지 않고 여기서만 처리.
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
      } catch (_) {
        // 로거 실패는 완전히 무시
      }
    }
  }
}
