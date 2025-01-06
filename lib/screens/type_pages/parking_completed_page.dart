import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart'; // PlateContainer import

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
          return PlateContainer(
            data: plateState.completed,
            filterCondition: (_) => true, // 모든 완료된 요청 표시
          );
        },
      ),
    );
  }
}
