import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/plate_navigation.dart';

/// ParkingRequestPage 위젯
/// 입차 요청 데이터를 표시하는 화면
class ParkingRequestPage extends StatelessWidget {
  const ParkingRequestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 앱바 설정
      appBar: AppBar(
        backgroundColor: Colors.blue, // 앱바 배경색 (파란색)
        centerTitle: true, // 제목 중앙 정렬
        title: const Text('섹션'), // 화면 제목
      ),

      // 본문 영역
      body: Consumer<PlateState>(
        // PlateState 상태 관리 객체를 구독하여 상태 변화에 따라 UI 업데이트
        builder: (context, plateState, child) {
          return ListView(
            padding: const EdgeInsets.all(8.0), // 리스트뷰 내부 여백 설정
            children: [
              // PlateContainer 위젯 사용
              // 입차 요청 데이터를 필터링하여 리스트로 표시
              PlateContainer(
                data: plateState.parkingRequests, // PlateState의 입차 요청 데이터
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                // 필터 조건: '입차 요청' 또는 '입차 중'인 데이터만 표시
              ),
            ],
          );
        },
      ),
      // 하단 PlateNavigation 추가
      bottomNavigationBar: PlateNavigation(
        icons: [
          Icons.search, // 돋보기 아이콘
          Icons.person, // 사람 아이콘
          Icons.sort, // 오름/내림차순 아이콘
        ],
      ),
    );
  }
}
