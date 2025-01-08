import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../states/plate_state.dart';
import '../../widgets/container/plate_container.dart';
import '../../widgets/navigation/plate_navigation.dart';

/// 출차 완료 페이지
/// 출차 완료된 차량 리스트를 보여주며, 데이터 삭제 및 로그아웃 기능을 제공합니다.
class DepartureCompletedPage extends StatefulWidget {
  const DepartureCompletedPage({super.key});

  @override
  State<DepartureCompletedPage> createState() => _DepartureCompletedPageState();
}

class _DepartureCompletedPageState extends State<DepartureCompletedPage> {
  String? _activePlate; // 눌림 상태 관리

  void _handlePlateTap(BuildContext context, String plateNumber) {
    setState(() {
      _activePlate = _activePlate == plateNumber ? null : plateNumber;
    });

    print('Tapped Plate: $plateNumber');
    print('Active Plate after tap: $_activePlate');
  }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모든 데이터가 삭제되었습니다.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 삭제 실패: $e')),
        );
      }
    }
  }

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
        backgroundColor: Colors.blue,
        centerTitle: true,
        title: const Text('섹션'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
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
                if (context.mounted) {
                  await _deleteAllData(context);
                }
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
                }, // 눌림 동작 콜백 전달
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const PlateNavigation(
        icons: [
          Icons.search,
          Icons.person,
          Icons.sort,
        ],
      ),
    );
  }
}
