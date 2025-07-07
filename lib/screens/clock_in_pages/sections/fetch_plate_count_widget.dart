import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';
import '../../../states/user/user_state.dart';

class FetchPlateCountWidget extends StatefulWidget {
  const FetchPlateCountWidget({super.key});

  @override
  State<FetchPlateCountWidget> createState() => _FetchPlateCountWidgetState();
}

class _FetchPlateCountWidgetState extends State<FetchPlateCountWidget> {
  Future<Map<PlateType, int>>? _futureCounts;

  Future<Map<PlateType, int>> _fetchCounts() async {
    final repo = context.read<PlateRepository>();
    final userState = context.read<UserState>();
    final area = userState.area;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final Map<PlateType, int> result = {};
    for (var type in PlateType.values) {
      final count = await repo.getPlateCountForClockInPage(
        type,
        selectedDate: type == PlateType.departureCompleted ? today : null,
        area: area,
      );
      result[type] = count;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    // 초기 상태: 아직 버튼만 보임
    if (_futureCounts == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('현황 불러오기'),
            onPressed: () {
              setState(() {
                _futureCounts = _fetchCounts();
              });
            },
          ),
        ),
      );
    }

    // 버튼을 누르면 FutureBuilder가 실행됨
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
          return const SizedBox();
        }

        final counts = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: PlateType.values.map((type) {
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
