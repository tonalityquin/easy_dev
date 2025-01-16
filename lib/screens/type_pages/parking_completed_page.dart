import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리 클래스
import '../../states/area_state.dart'; // AreaState 상태 관리 클래스
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// ParkingCompletedPage 클래스
/// 입차 완료 리스트를 표시하는 Stateful 위젯
class ParkingCompletedPage extends StatefulWidget {
  const ParkingCompletedPage({super.key});

  @override
  State<ParkingCompletedPage> createState() => _ParkingCompletedPageState();
}

class _ParkingCompletedPageState extends State<ParkingCompletedPage> {
  String? _activePlate; // 현재 활성화된 번호판 상태 관리

  /// SnackBar 메시지 출력 함수
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 번호판 선택 여부 확인
  bool _isPlateSelected() {
    return _activePlate != null && _activePlate!.isNotEmpty;
  }

  /// 번호판 클릭 시 호출되는 메서드
  void _handlePlateTap(String plateNumber, String area) {
    final String activeKey = '${plateNumber}_$area';

    setState(() {
      _activePlate = (_activePlate == activeKey) ? null : activeKey;
    });
  }

  /// 출차 요청 처리 메서드
  void _handleDepartureRequested(BuildContext context) {
    if (_isPlateSelected()) {
      final activeParts = _activePlate!.split('_');
      final plateNumber = activeParts[0];
      final currentArea = context.read<AreaState>().currentArea;

      context.read<PlateState>().setDepartureRequested(plateNumber, currentArea);

      setState(() {
        _activePlate = null;
      });

      _showSnackBar('출차 요청이 완료되었습니다.');
    } else {
      _showSnackBar('먼저 차량을 선택하세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(),
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea;
          final parkingCompleted = plateState.getPlatesByArea('parking_completed', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingCompleted,
                filterCondition: (_) => true,
                activePlate: _activePlate,
                onPlateTap: _handlePlateTap,
                drivingPlate: _activePlate,
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
            label: _isPlateSelected() ? '출차 요청' : '주차 구역',
          ),
          BottomNavigationBarItem(
            icon: Icon(_isPlateSelected() ? Icons.sort_by_alpha : Icons.sort),
            label: _isPlateSelected() ? '정렬 완료' : '정렬',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            _handleDepartureRequested(context);
          }
        },
      ),
    );
  }
}
