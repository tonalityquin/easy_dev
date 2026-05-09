import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'ocr_learning_db.dart';

class OcrLearningSummary {
  final int committedCount;
  final int pendingCount;
  final int dynamicMidMapCount;
  final int? preferredFrontLen;
  final int? lastCommittedAtMs;

  const OcrLearningSummary({
    required this.committedCount,
    required this.pendingCount,
    required this.dynamicMidMapCount,
    required this.preferredFrontLen,
    required this.lastCommittedAtMs,
  });
}

class OcrLearningRepository {
  OcrLearningRepository._internal();

  static final OcrLearningRepository instance =
      OcrLearningRepository._internal();

  static const int defaultMinCount = 5;
  static const double defaultMinRatio = 0.80;
  static const int defaultCandidateMinCount = 3;
  static const double defaultCandidateMinRatio = 0.80;

  Future<void> upsertPending({
    required String sessionId,
    String? lastText,
    List<String>? candidates,
    String? selectedCandidate,
    int? attemptCount,
    bool torchOn = false,
    bool forceInsertOn = false,
    bool usedLearningMid = false,
    bool usedLearningRank = false,
  }) async {
    final db = await OcrLearningDb.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'ocr_session',
      {
        'session_id': sessionId,
        'created_at_ms': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.update(
      'ocr_session',
      {
        if (lastText != null) 'last_text': lastText,
        if (candidates != null) 'candidates_json': jsonEncode(candidates),
        if (selectedCandidate != null) 'selected_candidate': selectedCandidate,
        if (attemptCount != null) 'attempt_count': attemptCount,
        'torch_on': torchOn ? 1 : 0,
        'force_insert_on': forceInsertOn ? 1 : 0,
        'used_learning_mid': usedLearningMid ? 1 : 0,
        'used_learning_rank': usedLearningRank ? 1 : 0,
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> commit({
    required String sessionId,
    required String finalPlate,
    required String front,
    required String mid,
    required String back,
    int editFrontCnt = 0,
    int editMidCnt = 0,
    int editBackCnt = 0,
  }) async {
    final db = await OcrLearningDb.instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'ocr_session',
        columns: ['selected_candidate'],
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

      final String? selectedCandidate =
          rows.isEmpty ? null : (rows.first['selected_candidate'] as String?);

      final int totalEdits = editFrontCnt + editMidCnt + editBackCnt;

      await txn.update(
        'ocr_session',
        {
          'final_plate': finalPlate,
          'final_front': front,
          'final_mid': mid,
          'final_back': back,
          'edit_front_cnt': editFrontCnt,
          'edit_mid_cnt': editMidCnt,
          'edit_back_cnt': editBackCnt,
          'edit_total_cnt': totalEdits,
          'committed_at_ms': now,
        },
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );

      await _upsertFrontLenStat(txn, front.length, now);

      final rawMid = _extractRawMid(selectedCandidate);
      if (rawMid != null && rawMid.isNotEmpty) {
        await _upsertMidCorrectionStat(txn, rawMid, mid, now);
      }

      final rawCandidate =
          selectedCandidate == null ? '' : _normalizeKey(selectedCandidate);
      final finalKey = _normalizeKey(finalPlate);
      if (rawCandidate.isNotEmpty &&
          finalKey.isNotEmpty &&
          rawCandidate != finalKey) {
        await _upsertCandidateCorrectionStat(txn, rawCandidate, finalKey, now);
      }
    });
  }

  String? _extractRawMid(String? selectedCandidate) {
    if (selectedCandidate == null || selectedCandidate.isEmpty) return null;
    final s = selectedCandidate.replaceAll(RegExp(r'\s+'), '');
    final m = RegExp(r'^(\d{2,3})(.)(\d{4})$').firstMatch(s);
    if (m == null) return null;
    return m.group(2);
  }

  String _normalizeKey(String s) {
    var t = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    t = t.replaceAll(RegExp(r'[\s\.\-·•_]+'), '');
    return t.trim();
  }

  Future<void> _upsertCandidateCorrectionStat(
    DatabaseExecutor txn,
    String rawCandidate,
    String finalPlate,
    int now,
  ) async {
    await txn.insert(
      'candidate_correction_stat',
      {
        'raw_candidate': rawCandidate,
        'final_plate': finalPlate,
        'cnt': 1,
        'last_seen_ms': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await txn.rawUpdate(
      'UPDATE candidate_correction_stat '
      'SET cnt = cnt + 1, last_seen_ms = ? '
      'WHERE raw_candidate = ? AND final_plate = ?',
      [now, rawCandidate, finalPlate],
    );
  }

  Future<void> _upsertFrontLenStat(
      DatabaseExecutor txn, int len, int now) async {
    await txn.insert(
      'front_len_stat',
      {'len': len, 'cnt': 1, 'last_seen_ms': now},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await txn.rawUpdate(
      'UPDATE front_len_stat SET cnt = cnt + 1, last_seen_ms = ? WHERE len = ?',
      [now, len],
    );
  }

  Future<void> _upsertMidCorrectionStat(
    DatabaseExecutor txn,
    String rawMid,
    String finalMid,
    int now,
  ) async {
    await txn.insert(
      'mid_correction_stat',
      {
        'raw_mid': rawMid,
        'final_mid': finalMid,
        'cnt': 1,
        'last_seen_ms': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await txn.rawUpdate(
      'UPDATE mid_correction_stat '
      'SET cnt = cnt + 1, last_seen_ms = ? '
      'WHERE raw_mid = ? AND final_mid = ?',
      [now, rawMid, finalMid],
    );
  }

  Future<Map<String, String>> loadDynamicMidMap({
    int minCount = defaultMinCount,
    double minRatio = defaultMinRatio,
  }) async {
    final db = await OcrLearningDb.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        s.raw_mid AS raw_mid,
        s.final_mid AS final_mid,
        s.cnt AS cnt,
        (
          SELECT SUM(cnt)
          FROM mid_correction_stat t
          WHERE t.raw_mid = s.raw_mid
        ) AS total
      FROM mid_correction_stat s
      WHERE s.cnt >= ?
      ORDER BY s.raw_mid, s.cnt DESC
    ''', [minCount]);

    final out = <String, String>{};
    final bestCnt = <String, int>{};
    final totalCnt = <String, int>{};

    for (final r in rows) {
      final raw = r['raw_mid'] as String;
      final cnt = (r['cnt'] as int?) ?? 0;
      final total = (r['total'] as int?) ?? 0;
      totalCnt[raw] = total;
      if (out.containsKey(raw)) continue;
      out[raw] = r['final_mid'] as String;
      bestCnt[raw] = cnt;
    }

    final filtered = <String, String>{};
    out.forEach((raw, fin) {
      final b = bestCnt[raw] ?? 0;
      final t = totalCnt[raw] ?? 0;
      final ratio = (t <= 0) ? 0.0 : (b / t);
      if (b >= minCount && ratio >= minRatio) filtered[raw] = fin;
    });

    return filtered;
  }

  Future<Map<String, String>> loadDynamicCandidateMap({
    int minCount = defaultCandidateMinCount,
    double minRatio = defaultCandidateMinRatio,
  }) async {
    final db = await OcrLearningDb.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        s.raw_candidate AS raw_candidate,
        s.final_plate AS final_plate,
        s.cnt AS cnt,
        (
          SELECT SUM(cnt)
          FROM candidate_correction_stat t
          WHERE t.raw_candidate = s.raw_candidate
        ) AS total
      FROM candidate_correction_stat s
      WHERE s.cnt >= ?
      ORDER BY s.raw_candidate, s.cnt DESC
    ''', [minCount]);

    final out = <String, String>{};
    final bestCnt = <String, int>{};
    final totalCnt = <String, int>{};

    for (final r in rows) {
      final raw = r['raw_candidate'] as String;
      final cnt = (r['cnt'] as int?) ?? 0;
      final total = (r['total'] as int?) ?? 0;
      totalCnt[raw] = total;
      if (out.containsKey(raw)) continue;
      out[raw] = r['final_plate'] as String;
      bestCnt[raw] = cnt;
    }

    final filtered = <String, String>{};
    out.forEach((raw, fin) {
      final b = bestCnt[raw] ?? 0;
      final t = totalCnt[raw] ?? 0;
      final ratio = (t <= 0) ? 0.0 : (b / t);
      if (b >= minCount && ratio >= minRatio) filtered[raw] = fin;
    });

    return filtered;
  }

  Future<int?> getPreferredFrontLen() async {
    final db = await OcrLearningDb.instance.database;
    final rows = await db.rawQuery(
      'SELECT len, cnt FROM front_len_stat ORDER BY cnt DESC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    return rows.first['len'] as int?;
  }

  Future<OcrLearningSummary> getSummary({
    int minCount = defaultMinCount,
    double minRatio = defaultMinRatio,
  }) async {
    final db = await OcrLearningDb.instance.database;

    final committed = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM ocr_session WHERE committed_at_ms IS NOT NULL',
          ),
        ) ??
        0;

    final pending = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM ocr_session WHERE committed_at_ms IS NULL',
          ),
        ) ??
        0;

    final lastCommitted = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT MAX(committed_at_ms) FROM ocr_session WHERE committed_at_ms IS NOT NULL',
      ),
    );

    final dynMap =
        await loadDynamicMidMap(minCount: minCount, minRatio: minRatio);
    final preferredFrontLen = await getPreferredFrontLen();

    return OcrLearningSummary(
      committedCount: committed,
      pendingCount: pending,
      dynamicMidMapCount: dynMap.length,
      preferredFrontLen: preferredFrontLen,
      lastCommittedAtMs: lastCommitted,
    );
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      final db = await OcrLearningDb.instance.database;
      await db.delete('ocr_session',
          where: 'session_id = ?', whereArgs: [sessionId]);
    } catch (e) {
      debugPrint('[OcrLearningRepository] deleteSession err: $e');
    }
  }
}
