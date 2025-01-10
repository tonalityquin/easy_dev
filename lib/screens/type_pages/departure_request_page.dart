import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';

/// DepartureRequestPage 클래스
/// 출차 요청 목록을 화면에 표시하는 Stateful 위젯
class DepartureRequestPage extends StatefulWidget {
  const DepartureRequestPage({super.key});

  @override
  State<DepartureRequestPage> createState() => _DepartureRequestPageState();
}

class _DepartureRequestPageState extends State<DepartureRequestPage> {
  String? _activePlate; // 눌림 상태 관리

  void _handlePlateTap(BuildContext context, String plateNumber) {
    setState(() {
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    // PlateState의 주행 상태 갱신
    context.read<PlateState>().setDrivingPlate(_activePlate ?? '');

    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }

  void _handleDepartureCompleted(BuildContext context) {
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final plateNumber = _activePlate;

      // 출차 완료 처리
      context.read<PlateState>().setDepartureCompleted(plateNumber!);
      setState(() {
        _activePlate = null; // 출차 완료 후 활성 상태 해제
      });

      print('Departure completed for plate: $plateNumber');
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
        title: const Text('출차 요청'),
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final departureRequests = plateState.departureRequests;

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureRequests,
                filterCondition: (request) => request.type == '출차 요청' || request.type == '출차 중',
                activePlate: _activePlate, // 활성 상태 전달
                onPlateTap: (plateNumber) {
                  _handlePlateTap(context, plateNumber);
                }, // 눌림 동작 콜백 전달
                drivingPlate: plateState.isDrivingPlate, // 현재 주행 중 차량 정보 전달
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
            _handleDepartureCompleted(context);
          }
        },
      ),
    );
  }
}
