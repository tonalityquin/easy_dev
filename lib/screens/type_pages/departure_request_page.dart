import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';

/// DepartureRequestPage 클래스
/// 출차 요청 목록을 화면에 표시하는 Stateless 위젯
class DepartureRequestPage extends StatelessWidget {
  /// 생성자: key 통해 식별
  const DepartureRequestPage({super.key});

  /// 메인 빌드 메서드
  /// @param context - 위젯 트리의 컨텍스트
  /// @return Widget - 출차 요청 리스트 화면
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 AppBar
      appBar: AppBar(
        backgroundColor: Colors.blue, // AppBar 배경색
        title: const Text('출차 요청 리스트'), // AppBar 제목
      ),
      // Body 영역
      body: Consumer<PlateState>(
        // Provider PlateState 구독
        builder: (context, plateState, child) {
          // 출차 요청 데이터를 PlateState에서 가져옴
          final departureRequests = plateState.departureRequests;

          // ListView로 출차 요청 리스트를 출력
          return ListView(
            padding: const EdgeInsets.all(8.0), // 리스트 뷰의 패딩 설정
            children: [
              PlateContainer(
                // PlateContainer: 출차 요청 데이터를 표시하는 위젯
                data: departureRequests, // PlateState의 출차 요청 데이터 전달
                filterCondition: (_) => true, // 필터 조건 설정 (현재는 모든 데이터 표시)
              ),
            ],
          );
        },
      ),
    );
  }
}
