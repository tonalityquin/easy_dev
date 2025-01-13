import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리 클래스
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바

/// DepartureCompletedPage
/// 출차 완료된 차량 리스트를 보여주는 페이지.
/// 데이터 삭제 및 로그아웃 기능 포함.
class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  String? _activePlate; // 현재 눌린 번호판의 상태 관리

  /// 번호판 클릭 시 호출되는 메서드
  void _handlePlateTap(BuildContext context, String plateNumber) {
    setState(() {
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });
  }

  /// 모든 컬렉션의 데이터를 삭제
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('문서 삭제 실패: $e')),
        );
      }
    }
  }

  /// 로그아웃 처리 메서드
  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TopNavigation(), // TopNavigation 추가
        backgroundColor: Colors.blue, // 배경색
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
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final departureCompleted = plateState.departureCompleted;
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: departureCompleted,
                filterCondition: (_) => true,
                activePlate: _activePlate,
                onPlateTap: (plateNumber) {
                  _handlePlateTap(context, plateNumber);
                },
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: _activePlate == null ? const Icon(Icons.search) : const Icon(Icons.highlight_alt),
            label: _activePlate == null ? '검색' : '정보 수정',
          ),
          BottomNavigationBarItem(
            icon: _activePlate == null ? const Icon(Icons.local_parking) : const Icon(Icons.check_circle),
            label: _activePlate == null ? '주차 구역' : '입차 완료',
          ),
          BottomNavigationBarItem(
            icon: _activePlate == null ? const Icon(Icons.sort) : const Icon(Icons.sort_by_alpha),
            label: _activePlate == null ? '정렬' : '뭘 넣지?',
          ),
        ],
      ),
    );
  }
}
