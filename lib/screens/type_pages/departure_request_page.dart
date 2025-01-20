import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // 번호판 상태 관리
import '../../states/area_state.dart'; // 지역 상태 관리
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// 출차 요청 페이지
/// - 출차 요청된 차량 목록을 표시하고 출차 완료 처리
class DepartureRequestPage extends StatefulWidget {
  const DepartureRequestPage({super.key});

  @override
  State<DepartureRequestPage> createState() => _DepartureRequestPageState();
}

class _DepartureRequestPageState extends State<DepartureRequestPage> {
  String? _activePlate; // 현재 선택된 번호판

  /// 메시지를 SnackBar로 출력
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 번호판 선택 여부 확인
  bool _isPlateSelected() {
    return _activePlate != null && _activePlate!.isNotEmpty;
  }

  /// 번호판 선택 상태 토글
  void _handlePlateTap(String plateNumber, String area) {
    final String activeKey = '${plateNumber}_$area';

    setState(() {
      _activePlate = (_activePlate == activeKey) ? null : activeKey;
    });
  }

  /// 출차 완료 처리
  void _handleDepartureCompleted(BuildContext context) {
    if (_isPlateSelected()) {
      final activeParts = _activePlate!.split('_');
      final plateNumber = activeParts[0];
      final area = activeParts[1];

      // 출차 완료 처리
      context.read<PlateState>().setDepartureCompleted(plateNumber, area);

      setState(() {
        _activePlate = null; // 선택된 번호판 초기화
      });

      _showSnackBar(context, '출차 완료가 완료되었습니다.');
    } else {
      _showSnackBar(context, '먼저 차량을 선택하세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(), // 상단 내비게이션
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea; // 현재 지역
          final departureRequests = plateState.getPlatesByArea('departure_requests', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureRequests, // 출차 요청 데이터
                filterCondition: (request) => request.type == '출차 요청' || request.type == '출차 중',
                activePlate: _activePlate, // 선택된 번호판
                onPlateTap: _handlePlateTap, // 번호판 클릭 처리
                drivingPlate: plateState.isDrivingPlate, // 차량 운행 여부
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: Icon(_isPlateSelected() ? Icons.highlight_alt : Icons.search),
            label: _isPlateSelected() ? '정보 수정' : '검색',
          ),
          BottomNavigationBarItem(
            icon: Icon(_isPlateSelected() ? Icons.check_circle : Icons.local_parking),
            label: _isPlateSelected() ? '출차 완료' : '주차 구역',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.sort),
            label: '정렬',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            _handleDepartureCompleted(context); // 출차 완료 처리
          }
        },
      ),
    );
  }
}
