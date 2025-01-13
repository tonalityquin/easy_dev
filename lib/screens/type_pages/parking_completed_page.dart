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

  /// 번호판 클릭 시 호출되는 메서드
  void _handlePlateTap(String plateNumber, String area) {
    final String activeKey = '${plateNumber}_$area'; // plateNumber + area 조합

    setState(() {
      _activePlate = _activePlate == activeKey ? null : activeKey; // 상태 토글
    });

    print('Tapped Plate: $plateNumber in $area');
    print('Active Plate after tap: $_activePlate');
  }

  /// 출차 요청 처리 메서드
  void _handleDepartureRequested(BuildContext context) {
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final currentArea = context.read<AreaState>().currentArea;

      if (currentArea == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('지역을 선택해주세요.')),
        );
        return;
      }

      final plateNumber = _activePlate!.split('_')[0]; // plateNumber 추출
      context.read<PlateState>().setDepartureRequested(plateNumber, currentArea);

      setState(() {
        _activePlate = null; // 상태 초기화
      });

      print('Departure requested for plate: $plateNumber in $currentArea');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 차량을 선택하세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 내비게이션 바
      appBar: const TopNavigation(), // TopNavigation 위젯 사용
      // 본문: 입차 완료된 번호판 목록 표시
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea; // 현재 선택된 지역

          if (currentArea == null) {
            return const Center(
              child: Text('지역을 선택해주세요.'), // 지역 선택 안내 메시지
            );
          }

          final parkingCompleted = plateState.getPlatesByArea('parking_completed', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0), // 리스트 아이템 여백
            children: [
              PlateContainer(
                data: parkingCompleted,
                filterCondition: (_) => true,
                activePlate: _activePlate,
                onPlateTap: (plateNumber, area) {
                  _handlePlateTap(plateNumber, area); // 지역 정보 전달
                },
                drivingPlate: _activePlate,
              ),
            ],
          );
        },
      ),
      // 하단 내비게이션 바
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: _activePlate == null
                ? const Icon(Icons.search) // 기본 상태 아이콘
                : const Icon(Icons.highlight_alt), // 선택된 상태 아이콘
            label: _activePlate == null ? '검색' : '정보 수정', // 상태에 따른 레이블
          ),
          BottomNavigationBarItem(
            icon: _activePlate == null
                ? const Icon(Icons.local_parking) // 기본 상태 아이콘
                : const Icon(Icons.check_circle), // 선택된 상태 아이콘
            label: _activePlate == null ? '주차 구역' : '출차 요청', // 상태에 따른 레이블
          ),
          BottomNavigationBarItem(
            icon: _activePlate == null
                ? const Icon(Icons.sort) // 기본 상태 아이콘
                : const Icon(Icons.sort_by_alpha), // 선택된 상태 아이콘
            label: _activePlate == null ? '정렬' : '뭘 넣지?', // 상태에 따른 레이블
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            // '출차 요청' 버튼 클릭 시 동작
            _handleDepartureRequested(context);
          }
        },
      ),
    );
  }
}
