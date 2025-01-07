import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';

class ParkingRequestPage extends StatelessWidget {
  const ParkingRequestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('입차 요청 리스트'),
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: plateState.parkingRequests,
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
              ),
            ],
          );
        },
      ),
    );
  }
}
