import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../states/plate_state.dart';
import '../../states/area_state.dart';
import '../../states/user_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/top_navigation.dart';

class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  String? _activePlate;

  /// SnackBar 메시지 출력 함수
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 번호판 선택 여부 확인
  bool _isPlateSelected() {
    return _activePlate != null && _activePlate!.isNotEmpty;
  }

  /// 번호판 클릭 시 호출되는 메서드
  void _handlePlateTap(String plateNumber, String area) {
    final String activeKey = '${plateNumber}_$area';
    setState(() {
      _activePlate = (_activePlate == activeKey) ? null : activeKey;
    });
  }

  /// 모든 데이터 삭제
  Future<void> _deleteAllData(BuildContext context) async {
    try {
      final collections = [
        'parking_requests',
        'parking_completed',
        'departure_requests',
        'departure_completed',
      ];
      for (final collection in collections) {
        final snapshot = await FirebaseFirestore.instance.collection(collection).get();
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
        }
      }
      _showSnackBar(context, '모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.');
    } catch (e) {
      _showSnackBar(context, '문서 삭제 실패: $e');
    }
  }

  /// 로그아웃 처리
  Future<void> _logout(BuildContext context) async {
    try {
      // Firebase Auth 로그아웃
      await FirebaseAuth.instance.signOut();

      // UserState 초기화
      final userState = Provider.of<UserState>(context, listen: false);
      await userState.clearUser();

      // 로그인 페이지로 이동
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      _showSnackBar(context, '로그아웃 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(),
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
          final currentArea = areaState.currentArea;
          final departureCompleted = plateState.getPlatesByArea('departure_completed', currentArea);

          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureCompleted,
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
