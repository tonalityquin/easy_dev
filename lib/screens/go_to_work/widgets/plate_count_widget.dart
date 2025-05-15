import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';
import '../../../states/user/user_state.dart';

class PlateCountWidget extends StatelessWidget {
  const PlateCountWidget({super.key});

  Future<Map<PlateType, int>> _fetchCounts(BuildContext context) async {
    final repo = context.read<PlateRepository>();
    final userState = context.read<UserState>();
    final area = userState.area;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final Map<PlateType, int> result = {};
    for (var type in PlateType.values) {
      final count = await repo.getPlateCountByType(
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
    return FutureBuilder<Map<PlateType, int>>(
      future: _fetchCounts(context),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
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
