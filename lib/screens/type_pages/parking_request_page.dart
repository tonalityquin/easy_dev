import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리
import '../../states/area_state.dart'; // AreaState 상태 관리
import '../../widgets/container/plate_container.dart'; // 번호판 데이터를 표시하는 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 입차 요청 데이터를 표시하는 화면
class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  String? _activePlate; // 현재 선택된 차량 번호판 상태

  /// SnackBar로 메시지 출력
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 차량 번호판 클릭 시 선택 상태 변경
  void _handlePlateTap(String plateNumber, String area) {
    final String activeKey = '${plateNumber}_$area';

    setState(() {
      _activePlate = (_activePlate == activeKey) ? null : activeKey;
    });
  }

  /// 선택된 번호판 여부 확인
  bool _isPlateSelected() {
    return _activePlate != null && _activePlate!.isNotEmpty;
  }

  /// 선택된 차량 번호판을 입차 완료 상태로 업데이트
  void _handleParkingCompleted() {
    if (_isPlateSelected()) {
      final activeParts = _activePlate!.split('_');
      final plateNumber = activeParts[0];
      final area = activeParts[1];

      context.read<PlateState>().setParkingCompleted(plateNumber, area);

      setState(() {
        _activePlate = null; // 선택된 번호판 초기화
      });
    } else {
      _showSnackBar('먼저 차량을 선택하세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(), // 상단 내비게이션
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea; // 현재 선택된 지역

          // 현재 지역의 입차 요청 데이터 가져오기
          final parkingRequests = plateState.getPlatesByArea('parking_requests', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingRequests, // 입차 요청 데이터
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                activePlate: _activePlate, // 선택된 번호판
                onPlateTap: (plateNumber, area) {
                  _handlePlateTap(plateNumber, currentArea); // 번호판 클릭 처리
                },
                drivingPlate: plateState.isDrivingPlate, // 운행 중인 번호판
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: Icon(_activePlate == null ? Icons.search : Icons.highlight_alt),
            label: _activePlate == null ? '번호판 검색' : '정보 수정',
          ),
          BottomNavigationBarItem(
            icon: Icon(_activePlate == null ? Icons.local_parking : Icons.check_circle),
            label: _activePlate == null ? '구역별 검색' : '입차 완료',
          ),
          BottomNavigationBarItem(
            icon: Icon(_activePlate == null ? Icons.sort : Icons.sort_by_alpha),
            label: _activePlate == null ? '정렬' : '정렬 완료',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            _handleParkingCompleted(); // 입차 완료 처리
          }
        },
      ),
    );
  }
}
