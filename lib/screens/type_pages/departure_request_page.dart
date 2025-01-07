import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';

class DepartureRequestPage extends StatelessWidget {
  const DepartureRequestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('출차 요청 리스트'),
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          // 데이터를 가져와 필요한 필터링 적용
          final departureRequests = plateState.departureRequests;

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureRequests, // 필터링된 데이터 전달
                filterCondition: (request) => true, // 기본 조건: 모든 요청 표시
              ),
            ],
          );
        },
      ),
    );
  }
}
