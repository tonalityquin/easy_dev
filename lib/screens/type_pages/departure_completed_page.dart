import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../states/plate_state.dart'; // PlateState 상태 관리 클래스
import '../../widgets/container/plate_container.dart'; // 번호판 컨테이너 위젯
import '../../widgets/navigation/plate_navigation.dart'; // 하단 내비게이션 바 위젯

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
  /// [plateNumber]: 클릭된 번호판
  void _handlePlateTap(BuildContext context, String plateNumber) {
    setState(() {
      // 현재 선택된 번호판과 동일하면 비활성화, 그렇지 않으면 활성화
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    // 디버깅 로그
    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }

  /// 모든 컬렉션의 데이터를 삭제
  /// [context]: BuildContext를 사용하여 UI에 메시지 표시
  Future<void> _deleteAllData(BuildContext context) async {
    try {
      // 삭제 대상 컬렉션 목록
      final collections = [
        'parking_requests',
        'parking_completed',
        'departure_requests',
        'departure_completed',
      ];

      for (final collection in collections) {
        // 각 컬렉션의 문서 스냅샷 가져오기
        final snapshot = await FirebaseFirestore.instance.collection(collection).get();

        for (final doc in snapshot.docs) {
          // 각 문서 삭제
          await doc.reference.delete();
        }
      }

      // 성공 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 문서가 삭제되었습니다. 컬렉션은 유지됩니다.')),
        );
      }
    } catch (e) {
      // 에러 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('문서 삭제 실패: $e')),
        );
      }
    }
  }

  /// 로그아웃 처리 메서드
  /// [context]: BuildContext를 사용하여 로그아웃 후 화면 전환
  Future<void> _logout(BuildContext context) async {
    try {
      // FirebaseAuth 로그아웃
      await FirebaseAuth.instance.signOut();

      // 로그인 페이지로 이동
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      // 로그아웃 실패 메시지 표시
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
      // 상단 앱바
      appBar: AppBar(
        backgroundColor: Colors.blue, // 앱바 배경색
        centerTitle: true, // 타이틀 가운데 정렬
        title: const Text('섹션'), // 페이지 타이틀
        actions: [
          // 로그아웃 버튼
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context), // 로그아웃 호출
          ),
          // 모든 데이터 삭제 버튼
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              // 삭제 확인 다이얼로그 표시
              final confirm = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('모든 데이터 삭제'),
                    content: const Text('정말로 모든 데이터를 삭제하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false), // 취소
                        child: const Text('취소'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true), // 확인
                        child: const Text('확인'),
                      ),
                    ],
                  );
                },
              );

              if (confirm == true) {
                // 사용자가 확인을 선택한 경우 데이터 삭제
                if (context.mounted) {
                  await _deleteAllData(context);
                }
              }
            },
          ),
        ],
      ),
      // 본문: 출차 완료된 번호판 리스트
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final departureCompleted = plateState.departureCompleted; // 출차 완료된 차량 데이터

          return ListView(
            padding: const EdgeInsets.all(8.0), // 리스트 아이템 여백
            children: [
              PlateContainer(
                data: departureCompleted, // PlateState의 데이터
                filterCondition: (_) => true, // 모든 데이터 표시
                activePlate: _activePlate, // 현재 활성화된 번호판
                onPlateTap: (plateNumber) {
                  _handlePlateTap(context, plateNumber); // 번호판 클릭 처리
                },
              ),
            ],
          );
        },
      ),
      // 하단 내비게이션 바
      bottomNavigationBar: const PlateNavigation(
        icons: [
          Icons.search, // 검색 아이콘
          Icons.person, // 프로필 아이콘
          Icons.sort, // 정렬 아이콘
        ],
      ),
    );
  }
}
