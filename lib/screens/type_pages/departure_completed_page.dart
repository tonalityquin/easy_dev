import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/plate_navigation.dart'; // PlateNavigation 추가

/// 출차 완료 페이지
/// 출차 완료된 차량 리스트를 보여주며, 데이터 삭제 및 로그아웃 기능을 제공합니다.
class DepartureCompletedPage extends StatelessWidget {
  const DepartureCompletedPage({super.key});

  /// Firestorm 모든 데이터를 삭제하는 비동기 함수
  Future<void> _deleteAllData(BuildContext context) async {
    try {
      // 각각의 Firestore 컬렉션에서 모든 문서를 가져와 삭제
      await FirebaseFirestore.instance.collection('parking_requests').get().then((snapshot) {
        for (var doc in snapshot.docs) {
          doc.reference.delete();
        }
      });

      await FirebaseFirestore.instance.collection('parking_completed').get().then((snapshot) {
        for (var doc in snapshot.docs) {
          doc.reference.delete();
        }
      });

      await FirebaseFirestore.instance.collection('departure_requests').get().then((snapshot) {
        for (var doc in snapshot.docs) {
          doc.reference.delete();
        }
      });

      await FirebaseFirestore.instance.collection('departure_completed').get().then((snapshot) {
        for (var doc in snapshot.docs) {
          doc.reference.delete();
        }
      });

      // 삭제 성공 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 데이터가 삭제되었습니다.')),
        );
      }
    } catch (e) {
      // 삭제 실패 시 오류 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 삭제 실패: $e')),
        );
      }
    }
  }

  /// Firebase 인증 로그아웃 처리
  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut(); // 로그아웃 수행
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login'); // 로그인 페이지로 리다이렉트
      }
    } catch (e) {
      // 로그아웃 실패 시 오류 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃 실패: $e')),
        );
      }
    }
  }

  /// 페이지 빌드 메서드
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 상단 앱바 구성
      appBar: AppBar(
        backgroundColor: Colors.blue, // 앱바 배경색
        centerTitle: true, // 제목 중앙 정렬
        title: const Text('섹션'),
        actions: [
          // 로그아웃 버튼
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
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
                      // 취소 버튼
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('취소'),
                      ),
                      // 확인 버튼
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('확인'),
                      ),
                    ],
                  );
                },
              );

              // 삭제 확정 시 데이터 삭제
              if (confirm == true) {
                if (context.mounted) {
                  await _deleteAllData(context);
                }
              }
            },
          ),
        ],
      ),
      // 출차 완료 데이터 표시
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              // PlateContainer 위젯을 사용해 데이터를 렌더링
              PlateContainer(
                data: plateState.departureCompleted, // 출차 완료 데이터
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
          Icons.person, // 사람 모양 아이콘
          Icons.sort, // 차순 아이콘
        ],
      ),
    );
  }
}
