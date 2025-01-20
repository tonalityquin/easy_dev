import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate_repository.dart';
import '../../states/plate_state.dart';
import '../../states/area_state.dart';
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/top_navigation.dart';

/// 출차 완료 페이지
/// - 출차 완료된 차량 데이터를 관리
/// - 로그아웃 및 데이터 삭제 기능 포함
class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  String? _activePlate; // 현재 활성화된 번호판

  /// 메시지를 SnackBar로 출력
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 번호판 선택 여부 확인
  bool _isPlateSelected() {
    return _activePlate != null && _activePlate!.isNotEmpty;
  }

  /// 번호판 클릭 시 활성화 상태 토글
  void _handlePlateTap(String plateNumber, String area) {
    final String activeKey = '${plateNumber}_$area';
    setState(() {
      _activePlate = (_activePlate == activeKey) ? null : activeKey;
    });
  }

  /// 모든 데이터 삭제
  Future<void> _deleteAllData(BuildContext context) async {
    final plateRepository = Provider.of<PlateRepository>(context, listen: false);
    try {
      await plateRepository.deleteAllData();
      _showSnackBar(context, '모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.');
    } catch (e) {
      _showSnackBar(context, '문서 삭제 실패: $e');
    }
  }

  /// 로그아웃 처리
  Future<void> _logout(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);
      await userState.clearUser();

      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login'); // 로그인 페이지로 이동
      }
    } catch (e) {
      _showSnackBar(context, '로그아웃 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(), // 상단 내비게이션
        backgroundColor: Colors.blue,
        actions: [
          // 로그아웃 버튼
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
          // 데이터 삭제 버튼
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('모든 데이터 삭제'),
                    content: const Text('정말로 모든 데이터를 삭제하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('확인'),
                      ),
                    ],
                  );
                },
              );
              if (confirm == true) {
                await _deleteAllData(context);
              }
            },
          ),
        ],
      ),
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea; // 현재 선택된 지역
          final departureCompleted = plateState.getPlatesByArea('departure_completed', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureCompleted, // 출차 완료된 차량 데이터
                filterCondition: (_) => true,
                activePlate: _activePlate,
                onPlateTap: _handlePlateTap,
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
            label: _isPlateSelected() ? '출차 완료' : '주차 구역',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.sort),
            label: '정렬',
          ),
        ],
      ),
    );
  }
}
