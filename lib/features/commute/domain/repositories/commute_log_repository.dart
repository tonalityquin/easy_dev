import '../../../../app/diagnostics/firebase_activity_meter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CommuteLogRepository {
  final FirebaseFirestore _firestore;

  CommuteLogRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _collectionName = 'commute_user_logs';
  static const String _source = 'features/commute/domain/repositories/commute_log_repository.dart';
  static final Expando<Map<String, Future<Map<String, dynamic>>>>
      _pendingMonthReadsByFirestore =
      Expando<Map<String, Future<Map<String, dynamic>>>>();

  String _buildRootDocId({
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

  String _toYearMonth(int year, int month) {
    return '$year${month.toString().padLeft(2, '0')}';
  }

  String _toYearMonthFromDateStr(String dateStr) {
    final dt = _parseYmd(dateStr);
    if (dt == null) {
      throw ArgumentError('invalid dateStr: $dateStr');
    }
    return _toYearMonth(dt.year, dt.month);
  }

  DocumentReference<Map<String, dynamic>> _rootDocRef({
    required String userId,
    required String status,
  }) {
    final rootDocId = _buildRootDocId(userId: userId, status: status);
    return _firestore.collection(_collectionName).doc(rootDocId);
  }

  DocumentReference<Map<String, dynamic>> _monthDocRef({
    required String userId,
    required String status,
    required String yearMonth,
  }) {
    return _rootDocRef(userId: userId, status: status)
        .collection('months')
        .doc(yearMonth);
  }

  Map<String, dynamic> _extractLogsMap(Map<String, dynamic>? data) {
    if (data == null) return <String, dynamic>{};
    final logs = data['logs'];
    if (logs is! Map) return <String, dynamic>{};

    final result = <String, dynamic>{};
    for (final entry in logs.entries) {
      result[entry.key.toString()] = entry.value;
    }
    return result;
  }

  Map<String, dynamic> _buildLogEntry({
    required String userId,
    required String userName,
    required String dateStr,
    required String recordedTime,
  }) {
    return <String, dynamic>{
      'userId': userId,
      'userName': userName,
      'date': dateStr,
      'recordedTime': recordedTime,
    };
  }

  Future<void> _ensureRootDoc({
    required String userId,
    required String userName,
    required String status,
    required String yearMonth,
  }) async {
    await _rootDocRef(userId: userId, status: status).set(
      <String, dynamic>{
        'userId': userId,
        'userName': userName,
        'status': status,
        'latestYearMonth': yearMonth,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    ).trackFirestore('SET', 'features/commute/domain/repositories/commute_log_repository.dart', collection: 'commute_user_logs');
  }

  void _recordOptimization(
    String operation,
    String reason, {
    required String method,
  }) {
    FirebaseActivityMeter.instance.record(
      service: 'optimization',
      operation: operation,
      source: '$_source.$method',
      result: 'skipped',
      detail: 'reason=$reason',
    );
  }

  Future<Map<String, dynamic>> _readMonthLogs({
    required String status,
    required String userId,
    required String yearMonth,
  }) async {
    final reads = _pendingMonthReadsByFirestore[_firestore] ??=
        <String, Future<Map<String, dynamic>>>{};
    final key = '${_buildRootDocId(userId: userId, status: status)}/$yearMonth';
    final pending = reads[key];
    if (pending != null) {
      _recordOptimization(
        'MONTH_GET_COALESCED',
        'identical_inflight',
        method: 'readMonthLogs',
      );
      return await pending;
    }
    final task = _readMonthLogsOnce(
      status: status,
      userId: userId,
      yearMonth: yearMonth,
    );
    reads[key] = task;
    try {
      return await task;
    } finally {
      if (identical(reads[key], task)) {
        reads.remove(key);
      }
    }
  }

  Future<Map<String, dynamic>> _readMonthLogsOnce({
    required String status,
    required String userId,
    required String yearMonth,
  }) async {
    final snap = await _monthDocRef(
      userId: userId,
      status: status,
      yearMonth: yearMonth,
    ).get().trackFirestore('GET', '$_source.readMonthLogs', collection: 'commute_user_logs', readPurpose: 'COMMUTE_MONTH_LOG_FETCH');
    if (!snap.exists) return <String, dynamic>{};
    return _extractLogsMap(snap.data());
  }

  Future<bool> hasLogForDate({
    required String status,
    required String userId,
    required String dateStr,
  }) async {
    final yearMonth = _toYearMonthFromDateStr(dateStr);
    final monthLogs = await _readMonthLogs(
      status: status,
      userId: userId,
      yearMonth: yearMonth,
    );
    if (monthLogs[dateStr] != null) return true;
    _recordOptimization(
      'LEGACY_GET_SKIPPED',
      'legacy_storage_not_used',
      method: 'hasLogForDate',
    );
    return false;
  }

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
    await upsertLogsForDates(
      status: status,
      userId: userId,
      userName: userName,
      area: area,
      division: division,
      dateToTime: <String, String>{
        dateStr: recordedTime,
      },
    );
  }

  Future<Map<int, String>> getMonthlyTimes({
    required String status,
    required String userId,
    required int year,
    required int month,
  }) async {
    final yearMonth = _toYearMonth(year, month);

    final monthLogs = await _readMonthLogs(
      status: status,
      userId: userId,
      yearMonth: yearMonth,
    );
    _recordOptimization(
      'LEGACY_GET_SKIPPED',
      'legacy_storage_not_used',
      method: 'getMonthlyTimes',
    );

    final result = <int, String>{};
    for (final entry in monthLogs.entries) {
      final dateStr = entry.key;
      final dt = _parseYmd(dateStr);
      if (dt == null || dt.year != year || dt.month != month) continue;
      final logEntry = entry.value;
      if (logEntry is! Map) continue;
      final recordedTime = logEntry['recordedTime']?.toString().trim() ?? '';
      if (recordedTime.isEmpty) continue;
      result[dt.day] = recordedTime;
    }

    return result;
  }

  Future<void> upsertLogsForDates({
    required String status,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required Map<String, String> dateToTime,
  }) async {
    if (dateToTime.isEmpty) return;

    final logsByMonth = <String, Map<String, dynamic>>{};

    for (final entry in dateToTime.entries) {
      final dateStr = entry.key.trim();
      final time = entry.value.trim();

      if (dateStr.isEmpty || time.isEmpty) continue;

      final dt = _parseYmd(dateStr);
      if (dt == null) continue;

      final yearMonth = _toYearMonth(dt.year, dt.month);
      final monthLogs = logsByMonth.putIfAbsent(
        yearMonth,
        () => <String, dynamic>{},
      );

      monthLogs[dateStr] = _buildLogEntry(
        userId: userId,
        userName: userName,
        dateStr: dateStr,
        recordedTime: time,
      );
    }

    for (final entry in logsByMonth.entries) {
      final yearMonth = entry.key;
      final logsPayload = entry.value;
      if (logsPayload.isEmpty) continue;

      await _ensureRootDoc(
        userId: userId,
        userName: userName,
        status: status,
        yearMonth: yearMonth,
      );

      await _monthDocRef(
        userId: userId,
        status: status,
        yearMonth: yearMonth,
      ).set(
        <String, dynamic>{
          'userId': userId,
          'userName': userName,
          'status': status,
          'yearMonth': yearMonth,
          'updatedAt': FieldValue.serverTimestamp(),
          'logs': logsPayload,
        },
        SetOptions(merge: true),
      ).trackFirestore('SET', 'features/commute/domain/repositories/commute_log_repository.dart', collection: 'commute_user_logs');
    }
  }

  Future<void> deleteLogsForDates({
    required String status,
    required String userId,
    required Iterable<String> dateStrs,
  }) async {
    final normalizedDates = dateStrs
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedDates.isEmpty) return;

    final datesByMonth = <String, List<String>>{};
    for (final dateStr in normalizedDates) {
      final dt = _parseYmd(dateStr);
      if (dt == null) continue;
      final yearMonth = _toYearMonth(dt.year, dt.month);
      datesByMonth.putIfAbsent(yearMonth, () => <String>[]).add(dateStr);
    }

    for (final entry in datesByMonth.entries) {
      final yearMonth = entry.key;
      final dates = entry.value;
      final logsPayload = <String, dynamic>{};
      for (final dateStr in dates) {
        logsPayload[dateStr] = FieldValue.delete();
      }

      await _monthDocRef(
        userId: userId,
        status: status,
        yearMonth: yearMonth,
      ).set(
        <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
          'logs': logsPayload,
        },
        SetOptions(merge: true),
      ).trackFirestore('SET', 'features/commute/domain/repositories/commute_log_repository.dart', collection: 'commute_user_logs');

      await _deleteMonthDocIfEmpty(
        status: status,
        userId: userId,
        yearMonth: yearMonth,
      );
    }

    _recordOptimization(
      'LEGACY_WRITE_SKIPPED',
      'legacy_storage_not_used',
      method: 'deleteLogsForDates',
    );
  }

  Future<void> _deleteMonthDocIfEmpty({
    required String status,
    required String userId,
    required String yearMonth,
  }) async {
    final docRef = _monthDocRef(
      userId: userId,
      status: status,
      yearMonth: yearMonth,
    );
    final snap = await docRef.get().trackFirestore('GET', 'features/commute/domain/repositories/commute_log_repository.dart', collection: 'commute_user_logs', readPurpose: 'COMMUTE_MONTH_EMPTY_DOCUMENT_RECHECK');
    if (!snap.exists) return;

    final logs = _extractLogsMap(snap.data());
    if (logs.isEmpty) {
      await docRef.delete().trackFirestore('DELETE', 'features/commute/domain/repositories/commute_log_repository.dart', collection: 'commute_user_logs');
    }
  }

  Future<void> deleteLogForDate({
    required String status,
    required String userId,
    required String dateStr,
  }) async {
    await deleteLogsForDates(
      status: status,
      userId: userId,
      dateStrs: <String>[dateStr],
    );
  }
}
