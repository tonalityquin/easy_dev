import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';

/// ParkingRequestPage 위젯
/// 입차 요청 데이터를 표시하는 화면
class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  String? _activePlate; // 현재 선택된 차량 번호판 상태를 관리하는 변수

  /// 차량 번호판을 탭할 때 호출되는 메서드
  /// - 눌린 차량 번호판의 상태를 활성화/비활성화
  /// - `PlateState`를 업데이트하여 운전 중 상태를 설정
  void _handlePlateTap(BuildContext context, String plateNumber) {
    setState(() {
      // 현재 눌린 번호판이 이미 활성 상태면 비활성화, 아니면 활성화
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    // PlateState에 운전 중 상태를 업데이트
    context.read<PlateState>().setDrivingPlate(_activePlate ?? '');

    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }

  /// '입차 완료' 버튼 클릭 시 호출되는 메서드
  /// - 선택된 차량을 주차 완료 상태로 업데이트
  /// - 활성 상태를 초기화
  void _handleParkingCompleted(BuildContext context) {
    // 활성화된 차량 번호판이 있는지 확인
    if (_activePlate != null && _activePlate!.isNotEmpty) {
      final plateNumber = _activePlate;

      // PlateState에 주차 완료 상태를 설정
      context.read<PlateState>().setParkingCompleted(plateNumber!);
      setState(() {
        _activePlate = null; // 완료 후 활성화 상태 초기화
      });

      print('Parking completed for plate: $plateNumber');
    } else {
      print('No active plate selected.');
      // 차량 번호판이 선택되지 않은 경우 경고 메시지 표시
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
        backgroundColor: Colors.blue, // AppBar의 배경색 설정
        centerTitle: true, // 제목을 중앙 정렬
        title: const Text('섹션'), // AppBar의 제목
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          return ListView(
            padding: const EdgeInsets.all(8.0), // 리스트뷰의 패딩 설정
            children: [
              PlateContainer(
                data: plateState.parkingRequests,
                // PlateState의 주차 요청 데이터 전달
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                // '입차 요청'과 '입차 중' 상태만 표시
                activePlate: _activePlate,
                // 현재 활성화된 차량 번호판 전달
                onPlateTap: (plateNumber) {
                  // 차량 번호판을 클릭했을 때의 동작 설정
                  _handlePlateTap(context, plateNumber);
                },
                drivingPlate: plateState.isDrivingPlate, // 현재 운전 중 상태 전달
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
            label: _activePlate == null ? '번호판 검색' : '정보 수정',
          ),
          BottomNavigationBarItem(
            // 아이콘 상태에 따른 변경
            icon: _activePlate == null
                ? const Icon(Icons.local_parking) // 기본 아이콘
                : const Icon(Icons.check_circle), // 선택된 상태 아이콘
            // 상태에 따른 레이블 변경
            label: _activePlate == null ? '구역별 검색' : '구역 선택',
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
            _handleParkingCompleted(context);
          }
        },
      ),
    );
  }
}
