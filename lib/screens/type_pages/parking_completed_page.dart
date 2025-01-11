import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리 클래스
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
  /// [plateNumber]: 클릭된 번호판
  void _handlePlateTap(String plateNumber) {
    setState(() {
      // 동일 번호판을 다시 클릭하면 비활성화
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    // 디버깅 로그
    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }

  /// 출차 요청 처리 메서드
  /// 선택된 번호판에 대해 출차 요청 상태로 변경
  void _handleDepartureRequested(BuildContext context) {
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final plateNumber = _activePlate;

      // 출차 요청 상태로 PlateState 갱신
      context.read<PlateState>().setDepartureRequested(plateNumber!);

      // 상태 초기화
      setState(() {
        _activePlate = null; // 출차 요청 후 활성 상태 해제
      });

      print('Departure requested for plate: $plateNumber');
    } else {
      // 번호판이 선택되지 않은 경우 경고 메시지 표시
      print('No active plate selected.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('먼저 차량을 선택하세요.'), // 경고 메시지
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 내비게이션 바
      appBar: const TopNavigation(), // TopNavigation 위젯 사용
      // 본문: 입차 완료된 번호판 목록 표시
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final parkingCompleted = plateState.parkingCompleted; // 입차 완료 데이터

          return ListView(
            padding: const EdgeInsets.all(8.0), // 리스트 아이템 여백
            children: [
              PlateContainer(
                data: parkingCompleted, // PlateState에서 전달된 데이터
                filterCondition: (_) => true, // 모든 데이터를 필터링 없이 표시
                activePlate: _activePlate, // 현재 활성화된 번호판 전달
                onPlateTap: _handlePlateTap, // 번호판 클릭 처리
                drivingPlate: _activePlate, // 상태 변경 반영
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
            label: _activePlate == null ? '주차 구역' : '출차 요청', // 상태에 따른 레이블
          ),
          BottomNavigationBarItem(
            // 번호판 선택 여부에 따라 아이콘 및 레이블 변경
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
