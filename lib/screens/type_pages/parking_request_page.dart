import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리 클래스
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
  void _handlePlateTap(BuildContext context, String plateNumber) {
    setState(() {
      // 같은 번호판을 클릭하면 비활성화, 다른 번호판을 클릭하면 활성화
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    // PlateState에 운전 중인 차량 번호판을 설정
    context.read<PlateState>().setDrivingPlate(_activePlate ?? '');

    // 디버깅 로그
    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }

  /// '입차 완료' 버튼 클릭 시 호출되는 메서드
  /// 선택된 차량 번호판을 주차 완료 상태로 업데이트
  void _handleParkingCompleted(BuildContext context) {
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final plateNumber = _activePlate;

      // PlateState에 주차 완료 상태로 설정
      context.read<PlateState>().setParkingCompleted(plateNumber!);

      // 상태 초기화
      setState(() {
        _activePlate = null; // 주차 완료 후 활성화 상태 초기화
      });

      print('Parking completed for plate: $plateNumber');
    } else {
      // 번호판이 선택되지 않았을 경우 경고 메시지 표시
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
      appBar: const TopNavigation(),
      // 본문: 입차 요청 리스트 표시
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          return ListView(
            padding: const EdgeInsets.all(8.0), // 리스트뷰의 여백 설정
            children: [
              PlateContainer(
                data: plateState.parkingRequests, // PlateState의 입차 요청 데이터 전달
                filterCondition: (request) =>
                request.type == '입차 요청' || request.type == '입차 중', // 특정 조건에 맞는 데이터만 표시
                activePlate: _activePlate, // 현재 활성화된 차량 번호판 전달
                onPlateTap: (plateNumber) {
                  _handlePlateTap(context, plateNumber); // 번호판 클릭 시 호출
                },
                drivingPlate: plateState.isDrivingPlate, // 현재 운전 중 상태 전달
              ),
            ],
          );
        },
      ),
      // 하단 내비게이션 바
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            // 아이콘 및 레이블 변경 (번호판 선택 여부에 따라)
            icon: _activePlate == null
                ? const Icon(Icons.search) // 기본 상태 아이콘
                : const Icon(Icons.highlight_alt), // 선택된 상태 아이콘
            label: _activePlate == null ? '번호판 검색' : '정보 수정',
          ),
          BottomNavigationBarItem(
            // 아이콘 및 레이블 변경 (번호판 선택 여부에 따라)
            icon: _activePlate == null
                ? const Icon(Icons.local_parking) // 기본 상태 아이콘
                : const Icon(Icons.check_circle), // 선택된 상태 아이콘
            label: _activePlate == null ? '구역별 검색' : '입차 완료',
          ),
          BottomNavigationBarItem(
            // 아이콘 및 레이블 변경 (번호판 선택 여부에 따라)
            icon: _activePlate == null
                ? const Icon(Icons.sort) // 기본 상태 아이콘
                : const Icon(Icons.sort_by_alpha), // 선택된 상태 아이콘
            label: _activePlate == null ? '정렬' : '뭘 넣지?',
          ),
        ],
        onTap: (index) {
          if (index == 1) {
            // '입차 완료' 버튼 클릭 시 동작
            _handleParkingCompleted(context);
          }
        },
      ),
    );
  }
}
