import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/plate_navigation.dart'; // PlateNavigation 추가

/// 입차 완료 리스트를 표시하는 페이지
/// 사용자는 입차 완료된 항목을 볼 수 있음
class ParkingCompletedPage extends StatelessWidget {
  const ParkingCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 앱바: 제목과 배경색 지정
      appBar: AppBar(
        backgroundColor: Colors.blue, // 앱바 배경색 (파란색)
        centerTitle: true, // 제목 중앙 정렬
        title: const Text('섹션'), // 화면 제목
      ),
      // 본문 영역
      body: Consumer<PlateState>(
        // PlateState 데이터를 구독하여 상태 변화 반영
        builder: (context, plateState, child) {
          // PlateState에서 입차 완료된 항목 가져오기
          final parkingCompleted = plateState.parkingCompleted;

          return ListView(
            padding: const EdgeInsets.all(8.0), // 리스트 아이템 간격
            children: [
              // PlateContainer 위젯: 데이터 목록과 필터 조건 전달
              PlateContainer(
                data: parkingCompleted, // 입차 완료된 데이터 전달
                filterCondition: (_) => true, // 필터 조건: 모든 데이터 표시
              ),
            ],
          );
        },
      ),
      // 하단 PlateNavigation 추가
      bottomNavigationBar: PlateNavigation(
        icons: [
          Icons.search, // 돋보기 아이콘
          Icons.local_parking, // 주차 구역 아이콘
          Icons.sort, // 오름/내림차순 아이콘
        ],
      ),
    );
  }
}
