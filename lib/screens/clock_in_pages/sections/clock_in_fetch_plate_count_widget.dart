import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';
import '../../../states/user/user_state.dart';
import '../debugs/clock_in_debug_firestore_logger.dart';

class ClockInFetchPlateCountWidget extends StatefulWidget {
  const ClockInFetchPlateCountWidget({super.key});

  @override
  State<ClockInFetchPlateCountWidget> createState() => _ClockInFetchPlateCountWidgetState();
}

class _ClockInFetchPlateCountWidgetState extends State<ClockInFetchPlateCountWidget> {
  Future<Map<PlateType, int>>? _futureCounts;

  final _logger = ClockInDebugFirestoreLogger();

  // 👇 한 곳에서 재사용 가능하도록 상수로 선언
  static const List<PlateType> _relevantTypes = [
    PlateType.parkingRequests,
    PlateType.departureRequests,
  ];

  Future<Map<PlateType, int>> _clockInFetchCounts() async {
    _logger.log('🚀 현황 데이터 로드 시작', level: 'info');

    final repo = context.read<PlateRepository>();
    final userState = context.read<UserState>();
    final area = userState.area;

    final Map<PlateType, int> result = {};

    for (var type in _relevantTypes) {
      try {
        _logger.log('📦 ${type.label} 데이터 조회 요청 시작', level: 'info');

        final count = await repo.getPlateCountForClockInPage(
          type,
          selectedDate: null,
          area: area,
        );

        result[type] = count;
        _logger.log('✅ ${type.label} 조회 완료: $count건', level: 'success');
      } catch (e) {
        _logger.log('🔥 ${type.label} 조회 실패: $e', level: 'error');
        result[type] = 0;
      }
    }

    _logger.log('✅ 현황 데이터 로드 완료', level: 'success');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_futureCounts == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('현황 불러오기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Colors.grey),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              _logger.log('🧲 [UI] 현황 불러오기 버튼 클릭됨', level: 'called');
              setState(() {
                _futureCounts = _clockInFetchCounts();
              });
            },
          ),
        ),
      );
    }

    return FutureBuilder<Map<PlateType, int>>(
      future: _futureCounts,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          _logger.log('🔥 FutureBuilder 에러: ${snapshot.error}', level: 'error');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '데이터 로드 실패: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          _logger.log('⚠️ FutureBuilder 데이터 없음 (null)', level: 'info');
          return const SizedBox();
        }

        final counts = snapshot.data!;
        _logger.log('📊 UI에 현황 데이터 렌더링 시작', level: 'called');

        return Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: _relevantTypes.map((type) {
                  return Column(
                    children: [
                      Text(
                        type.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${counts[type] ?? 0}건',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const Divider(height: 32, thickness: 1),
            ],
          ),
        );
      },
    );
  }
}
