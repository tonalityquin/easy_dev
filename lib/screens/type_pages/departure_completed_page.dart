import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart'; // PlateContainer import

class DepartureCompletedPage extends StatelessWidget {
  const DepartureCompletedPage({super.key});

  // Firestore의 모든 관련 데이터를 삭제하는 메서드
  Future<void> _deleteAllData(BuildContext context) async {
    try {
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

      if (context.mounted) {
        // 안전하게 BuildContext 사용
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 데이터가 삭제되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        // 안전하게 BuildContext 사용
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 삭제 실패: $e')),
        );
      }
    }
  }

  // 로그아웃 메서드
  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        // 안전하게 BuildContext 사용
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      if (context.mounted) {
        // 안전하게 BuildContext 사용
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
        backgroundColor: Colors.blue,
        title: const Text('출차 완료 리스트'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout), // 로그아웃 버튼
            onPressed: () => _logout(context), // 로그아웃 메서드 호출
          ),
          IconButton(
            icon: const Icon(Icons.delete), // 삭제 버튼
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

              // 비동기 작업 전 confirm 값 확인
              if (confirm == true) {
                if (context.mounted) {
                  // BuildContext 사용 안전 확인
                  await _deleteAllData(context);
                }
              }
            },
          ),
        ],
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          return PlateContainer(
            data: plateState.departureCompleted,
            filterCondition: (_) => true, // 모든 완료된 출차 표시
          );
        },
      ),
    );
  }
}
