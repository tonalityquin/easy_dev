import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리 클래스
import '../../states/area_state.dart'; // AreaState 상태 관리 클래스
import '../../widgets/container/plate_container.dart'; // 번호판 데이터를 표시하는 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// ParkingRequestPage 위젯
/// 입차 요청 데이터를 표시하는 Stateful 위젯
class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  String? _activePlate; // 현재 선택된 차량 번호판 상태를 관리하는 변수

  /// 차량 번호판을 탭할 때 호출되는 메서드
  /// [plateNumber]: 탭된 차량 번호판 번호
  void _handlePlateTap(BuildContext context, String plateNumber, String area) {
    final String activeKey = '${plateNumber}_$area'; // plateNumber + area 조합

    setState(() {
      _activePlate = _activePlate == activeKey ? null : activeKey;
    });

    // Driving 상태 업데이트
    context.read<PlateState>().setDrivingPlate(plateNumber, area);
  }

  /// '입차 완료' 버튼 클릭 시 호출되는 메서드
  /// 선택된 차량 번호판을 주차 완료 상태로 업데이트
  void _handleParkingCompleted(BuildContext context) {
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final activeParts = _activePlate!.split('_');
      final plateNumber = activeParts[0];
      final area = activeParts[1];

      context.read<PlateState>().setParkingCompleted(plateNumber, area);

      setState(() {
        _activePlate = null;
      });
    } else {
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
      appBar: const TopNavigation(),
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, cild) {
          final currentArea = context.read<AreaState>().currentArea;

          if (currentArea == null) {
            return const Center(
              child: Text('지역을 선택해주세요.'),
            );
          }

          // 현재 지역의 입차 요청 데이터를 필터링
          final parkingRequests = plateState.getPlatesByArea('parking_requests', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingRequests,
                // 필터링된 데이터 전달
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                activePlate: _activePlate,
                onPlateTap: (plateNumber, area) {
                  _handlePlateTap(context, plateNumber, currentArea!); // 지역 정보 전달
                },
                drivingPlate: plateState.isDrivingPlate,
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: _activePlate == null ? const Icon(Icons.search) : const Icon(Icons.highlight_alt),
            label: _activePlate == null ? '번호판 검색' : '정보 수정',
          ),
          BottomNavigationBarItem(
            icon: _activePlate == null ? const Icon(Icons.local_parking) : const Icon(Icons.check_circle),
            label: _activePlate == null ? '구역별 검색' : '입차 완료',
          ),
          BottomNavigationBarItem(
            icon: _activePlate == null ? const Icon(Icons.sort) : const Icon(Icons.sort_by_alpha),
            label: _activePlate == null ? '정렬' : '뭘 넣지?',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            _handleParkingCompleted(context);
          }
        },
      ),
    );
  }
}
