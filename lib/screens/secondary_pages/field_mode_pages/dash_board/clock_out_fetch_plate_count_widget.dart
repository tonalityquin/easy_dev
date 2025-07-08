import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../repositories/plate/plate_repository.dart';
import '../../../../states/user/user_state.dart';

class ClockOutFetchPlateCountWidget extends StatefulWidget {
  const ClockOutFetchPlateCountWidget({super.key});

  @override
  State<ClockOutFetchPlateCountWidget> createState() => _ClockOutFetchPlateCountWidgetState();
}

class _ClockOutFetchPlateCountWidgetState extends State<ClockOutFetchPlateCountWidget> {
  Future<Map<PlateType, int>>? _futureCounts;

  Future<Map<PlateType, int>> _fetchCounts() async {
    final repo = context.read<PlateRepository>();
    final userState = context.read<UserState>();
    final area = userState.area;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final Map<PlateType, int> result = {};

    for (var type in PlateType.values) {
      try {
        final count = await repo.getPlateCountForClockInPage(
          type,
          selectedDate: type == PlateType.departureCompleted ? today : null,
          area: area,
        );

        result[type] = count;
      } catch (e) {
        result[type] = 0;
      }
    }

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
              setState(() {
                _futureCounts = _fetchCounts();
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
