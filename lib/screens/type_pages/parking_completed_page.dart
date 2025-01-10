import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';

/// ParkingCompletedPage 클래스
/// 입차 완료 리스트를 표시하는 Stateful 위젯
class ParkingCompletedPage extends StatefulWidget {
  const ParkingCompletedPage({super.key});

  @override
  State<ParkingCompletedPage> createState() => _ParkingCompletedPageState();
}

class _ParkingCompletedPageState extends State<ParkingCompletedPage> {
  String? _activePlate; // 눌림 상태 관리

  void _handlePlateTap(String plateNumber) {
    setState(() {
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }

  void _handleDepartureRequested(BuildContext context) {
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final plateNumber = _activePlate;

      // 출차 요청 처리
      context.read<PlateState>().setDepartureRequested(plateNumber!);
      setState(() {
        _activePlate = null; // 출차 요청 후 활성 상태 해제
      });

      print('Departure requested for plate: $plateNumber');
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
          final parkingCompleted = plateState.parkingCompleted;

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingCompleted,
                filterCondition: (_) => true,
                activePlate: _activePlate, // 활성 상태 전달
                onPlateTap: _handlePlateTap, // 눌림 동작 콜백 전달
                drivingPlate: _activePlate, // 상태 변경 반영
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            // 아이콘 상태에 따른 변경
            icon: _activePlate == null
                ? const Icon(Icons.search) // 기본 아이콘
                : const Icon(Icons.highlight_alt), // 선택된 상태 아이콘
            label: _activePlate == null ? '검색' : '정보 수정',
          ),
          BottomNavigationBarItem(
            // 아이콘 상태에 따른 변경
            icon: _activePlate == null
                ? const Icon(Icons.local_parking) // 기본 아이콘
                : const Icon(Icons.check_circle), // 선택된 상태 아이콘
            // 상태에 따른 레이블 변경
            label: _activePlate == null ? '주차 구역' : '입차 완료',
          ),
          BottomNavigationBarItem(
            // 아이콘 상태에 따른 변경
            icon: _activePlate == null
                ? const Icon(Icons.sort) // 기본 아이콘
                : const Icon(Icons.sort_by_alpha), // 선택된 상태 아이콘
            label: _activePlate == null ? '정렬' : '뭘 넣지?',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            // '입차 완료' 버튼 클릭 시 동작
            _handleDepartureRequested(context);
          }
        },
      ),
    );
  }
}
