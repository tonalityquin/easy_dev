import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';

/// ParkingRequestPage 위젯
/// 입차 요청 데이터를 표시하는 화면
class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  String? _activePlate; // 눌림 상태 관리

  void _handlePlateTap(BuildContext context, String plateNumber) {
    setState(() {
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    // PlateState의 운전 중 상태 업데이트
    context.read<PlateState>().setDrivingPlate(_activePlate ?? '');

    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }


  void _handleParkingCompleted(BuildContext context) {
    // _activePlate가 null이 아니고 빈 문자열이 아닌지 확인
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final plateNumber = _activePlate;

      // 주차 완료 처리
      context.read<PlateState>().setParkingCompleted(plateNumber!);
      setState(() {
        _activePlate = null; // 주차 완료 후 활성 상태 해제
      });

      print('Parking completed for plate: $plateNumber');
    } else {
      print('No active plate selected.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('먼저 차량을 선택하세요.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        centerTitle: true,
        title: const Text('섹션'),
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: plateState.parkingRequests,
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                activePlate: _activePlate,
                onPlateTap: (plateNumber) {
                  _handlePlateTap(context, plateNumber);
                },
                drivingPlate: plateState.isDrivingPlate, // 운전 중 상태 전달
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: '검색',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_parking),
            label: '입차 완료',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sort),
            label: '정렬',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            // local_parking 버튼 동작
            _handleParkingCompleted(context);
          }
        },
      ),
    );
  }
}
