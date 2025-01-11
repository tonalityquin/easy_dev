import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // 번호판 상태 관리 클래스
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
  /// [context]: BuildContext, [plateNumber]: 클릭된 번호판 번호
  void _handlePlateTap(BuildContext context, String plateNumber) {
    setState(() {
      // 동일 번호판을 다시 클릭하면 비활성화
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    // PlateState에 현재 주행 중인 번호판 상태 업데이트
    context.read<PlateState>().setDrivingPlate(_activePlate ?? '');

    // 디버깅 로그
    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }

  /// 출차 완료 처리 메서드
  /// [context]: BuildContext
  void _handleDepartureCompleted(BuildContext context) {
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final plateNumber = _activePlate;

      // 출차 완료 처리: PlateState 갱신
      context.read<PlateState>().setDepartureCompleted(plateNumber!);

      // 상태 초기화
      setState(() {
        _activePlate = null; // 출차 완료 후 활성 상태 해제
      });

      print('Departure completed for plate: $plateNumber');
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
      // 본문: 출차 요청 목록 표시
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final departureRequests = plateState.departureRequests; // 출차 요청 데이터

          return ListView(
            padding: const EdgeInsets.all(8.0), // 아이템 여백
            children: [
              PlateContainer(
                data: departureRequests, // PlateState에서 전달된 데이터
                filterCondition: (request) =>
                request.type == '출차 요청' || request.type == '출차 중', // 특정 타입만 필터링
                activePlate: _activePlate, // 현재 활성화된 번호판 전달
                onPlateTap: (plateNumber) {
                  _handlePlateTap(context, plateNumber); // 번호판 클릭 처리
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
            label: _activePlate == null ? '주차 구역' : '입차 완료', // 상태에 따른 레이블
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
            // '입차 완료' 버튼 클릭 시 동작
            _handleDepartureCompleted(context);
          }
        },
      ),
    );
  }
}
