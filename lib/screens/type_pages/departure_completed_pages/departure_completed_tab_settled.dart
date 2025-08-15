// 동일 경로: departure_completed_tab_settled.dart
import 'package:flutter/material.dart';

import '../../../models/plate_model.dart';
import '../../../utils/gcs_json_uploader.dart';
import '../departure_completed_pages/widgets/departure_completed_page_merge_log.dart';
import '../departure_completed_pages/widgets/departure_completed_page_today_log.dart';

class DepartureCompletedSettledTab extends StatelessWidget {
  const DepartureCompletedSettledTab({
    super.key,
    required this.baseList, // 날짜(자정~자정) 필터가 적용된 리스트
    required this.area,
    required this.division,
    required this.selectedDate,
    required this.plateNumber, // 선택된 번호판(없으면 빈 문자열)
  });

  final List<PlateModel> baseList;
  final String area;
  final String division;
  final DateTime selectedDate;
  final String plateNumber;

  bool _areaEquals(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    // 지역 필터 적용
    final todayPlates = baseList.where((p) => _areaEquals(p.area, area)).toList();

    // Firestore 문서 → TodayLogSection이 기대하는 맵 형태로 변환
    final todayMergedItems = todayPlates.map<Map<String, dynamic>>((p) {
      final List<dynamic> logsDyn = (p.logs as List?) ?? const <dynamic>[];

      // mergedAt 후보: 로그 최신 timestamp → 없으면 endTime → updatedAt → requestTime
      DateTime? newestFromLogs;
      for (final l in logsDyn.whereType<Map<String, dynamic>>()) {
        final ts = DateTime.tryParse((l['timestamp'] ?? '').toString());
        if (ts != null && (newestFromLogs == null || ts.isAfter(newestFromLogs))) {
          newestFromLogs = ts;
        }
      }
      final mergedAt = (newestFromLogs ?? p.endTime ?? p.updatedAt ?? p.requestTime);

      return {
        'plateNumber': p.plateNumber,
        'mergedAt': mergedAt.toIso8601String(),
        'logs': logsDyn,
      };
    }).toList()
      ..sort((a, b) {
        final aT = DateTime.tryParse(a['mergedAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT = DateTime.tryParse(b['mergedAt'] ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bT.compareTo(aT);
      });

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // 상단 1/2: TodayLogSection
          Expanded(
            child: ClipRect(
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: TodayLogSection(
                    mergedLogs: todayMergedItems,
                    division: division,
                    area: area,
                    selectedDate: selectedDate,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 하단 1/2: MergedLogSection (선택된 번호판 기준)
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: plateNumber.isEmpty
                  ? Future.value(<Map<String, dynamic>>[])
                  : GcsJsonUploader().loadPlateLogs(
                      plateNumber: plateNumber,
                      division: division,
                      area: area,
                      date: selectedDate,
                    ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text("병합 로그 로딩 실패"));
                }
                final mergedLogs = snapshot.data ?? [];
                return ClipRect(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (plateNumber.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8.0),
                              child: Center(
                                child: Text('번호판을 선택하면 상세 병합 로그를 불러옵니다.'),
                              ),
                            ),
                          MergedLogSection(
                            mergedLogs: mergedLogs,
                            division: division,
                            area: area,
                            selectedDate: selectedDate,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
