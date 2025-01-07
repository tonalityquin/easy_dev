import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';

class ParkingCompletedPage extends StatelessWidget {
  const ParkingCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('입차 완료 리스트'),
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          // PlateRequest 데이터 그대로 전달
          final parkingCompleted = plateState.parkingCompleted;

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingCompleted, // PlateRequest 타입으로 전달
                filterCondition: (_) => true, // 기본 필터 조건
              ),
            ],
          );
        },
      ),
    );
  }
}
