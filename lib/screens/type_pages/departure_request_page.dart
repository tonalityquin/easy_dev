import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // 번호판 상태 관리 클래스
import '../../states/area_state.dart'; // 지역 상태 관리 클래스
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// DepartureRequestPage 클래스
/// 출차 요청 목록을 화면에 표시하는 Stateful 위젯
class DepartureRequestPage extends StatefulWidget {
  const DepartureRequestPage({super.key});

  @override
  State<DepartureRequestPage> createState() => _DepartureRequestPageState();
}

class _DepartureRequestPageState extends State<DepartureRequestPage> {
  String? _activePlate; // 현재 활성화된 번호판 상태 관리

  /// 번호판 클릭 시 호출되는 메서드
  void _handlePlateTap(BuildContext context, String plateNumber, String area) {
    final String activeKey = '${plateNumber}_$area'; // plateNumber와 area 조합으로 고유 키 생성

    setState(() {
      _activePlate = _activePlate == activeKey ? null : activeKey; // 활성화 상태 토글
    });

    // PlateState에 주행 중인 차량 상태 업데이트
    context.read<PlateState>().setDrivingPlate(plateNumber, area);

    // 디버깅 로그
    print('Tapped Plate: $plateNumber in $area');
    print('Active Plate after tap: $_activePlate');
  }

  /// 출차 완료 처리 메서드
  void _handleDepartureCompleted(BuildContext context) {
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final activeParts = _activePlate!.split('_');
      final plateNumber = activeParts[0];
      final area = activeParts[1];

      // 출차 완료 처리: PlateState 갱신
      context.read<PlateState>().setDepartureCompleted(plateNumber, area);

      // 상태 초기화
      setState(() {
        _activePlate = null; // 출차 완료 후 활성 상태 해제
      });

      print('Departure completed for plate: $plateNumber in area: $area');
    } else {
      // 번호판이 선택되지 않은 경우 경고 메시지 표시
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
      // 상단 내비게이션 바
      appBar: const TopNavigation(), // TopNavigation 위젯 사용
      // 본문: 출차 요청 목록 표시
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = context.read<AreaState>().currentArea;

          // 현재 지역에 해당하는 출차 요청 데이터 필터링
          final departureRequests = plateState.getPlatesByArea('departure_requests', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0), // 아이템 여백
            children: [
              PlateContainer(
                data: departureRequests,
                // 필터링된 데이터 전달
                filterCondition: (request) => request.type == '출차 요청' || request.type == '출차 중',
                // 특정 타입만 필터링
                activePlate: _activePlate,
                // 현재 활성화된 번호판 전달
                onPlateTap: (plateNumber, area) {
                  _handlePlateTap(context, plateNumber, currentArea); // 번호판 클릭 처리
                },
                drivingPlate: plateState.isDrivingPlate, // 현재 주행 중 차량 정보 전달
              ),
            ],
          );
        },
      ),
      // 하단 내비게이션 바
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            // 번호판 선택 여부에 따라 아이콘 및 레이블 변경
            icon: _activePlate == null
                ? const Icon(Icons.search) // 기본 상태 아이콘
                : const Icon(Icons.highlight_alt), // 선택된 상태 아이콘
            label: _activePlate == null ? '검색' : '정보 수정', // 상태에 따른 레이블
          ),
          BottomNavigationBarItem(
            // 번호판 선택 여부에 따라 아이콘 및 레이블 변경
            icon: _activePlate == null
                ? const Icon(Icons.local_parking) // 기본 상태 아이콘
                : const Icon(Icons.check_circle), // 선택된 상태 아이콘
            label: _activePlate == null ? '주차 구역' : '출차 완료', // 상태에 따른 레이블
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.sort),
            label: '정렬',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            // '출차 완료' 버튼 클릭 시 동작
            _handleDepartureCompleted(context);
          }
        },
      ),
    );
  }
}
