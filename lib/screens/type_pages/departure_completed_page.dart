import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../states/plate_state.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DepartureCompletedPage extends StatelessWidget {
  const DepartureCompletedPage({super.key});

  // Firestore의 모든 관련 데이터를 삭제하는 메서드
  Future<void> _deleteAllData(BuildContext context) async {
    try {
      // Firestore 컬렉션 삭제
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

      // UI 업데이트
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 데이터가 삭제되었습니다.')),
      );
    } catch (e) {
      // 오류 처리
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터 삭제 실패: $e')),
      );
    }
  }

  // 로그아웃 메서드
  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut(); // Firebase 로그아웃
      Navigator.pushReplacementNamed(context, '/login'); // 로그인 페이지로 이동
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그아웃 실패: $e')),
      );
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
            icon: const Icon(Icons.delete),
            onPressed: () async {
              // 확인 다이얼로그 표시
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

              // 확인되면 데이터 삭제
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

          if (departureCompleted.isEmpty) {
            return const Center(
              child: Text(
                '완료된 출차가 없습니다.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: departureCompleted.length,
            itemBuilder: (context, index) {
              final request = departureCompleted[index];
              final DateTime requestTime = request['request_time'].toDate();
              final Duration duration = DateTime.now().difference(requestTime);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 50,
                        color: Colors.blueGrey,
                      ),
                    ),
                    Expanded(
                      flex: 8,
                      child: ListTile(
                        title: Text(
                          '[${request['plate_number']}]',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '요청 시간: ${requestTime.toString().substring(0, 19)}\n'
                              '누적 시간: ${duration.inMinutes}분 ${duration.inSeconds % 60}초\n'
                              '위치: ${request['location']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
