import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../type_pages/debugs/firestore_logger.dart';

class AreaDetailScreen extends StatelessWidget {
  final String areaName;

  const AreaDetailScreen({super.key, required this.areaName});

  static final Map<String, List<UserStatus>> _cachedUsers = {};
  static final Map<String, DateTime> _lastFetchedTime = {};

  Future<List<UserStatus>> _fetchUsersForArea(String area) async {
    final now = DateTime.now();

    // ✅ 1. 캐시 유효성 검사 (5분 이내 재사용)
    if (_cachedUsers.containsKey(area)) {
      final lastTime = _lastFetchedTime[area];
      if (lastTime != null && now.difference(lastTime) < const Duration(minutes: 5)) {
        await FirestoreLogger().log(
          '📦 $area 캐시 데이터 사용',
          level: 'info',
        );
        return _cachedUsers[area]!;
      }
    }

    try {
      await FirestoreLogger().log(
        '🔍 Firestore 쿼리 시작: currentArea=$area',
        level: 'called',
      );

      // ✅ 2. Firestore 쿼리
      final snapshot =
          await FirebaseFirestore.instance.collection('user_accounts').where('currentArea', isEqualTo: area).get();

      final result = snapshot.docs.map((doc) {
        final data = doc.data();
        return UserStatus(
          name: data['name'] ?? '이름 없음',
          isWorking: data['isWorking'] == true,
        );
      }).toList();

      await FirestoreLogger().log(
        '✅ Firestore 쿼리 완료: $area - ${result.length}명',
        level: 'success',
      );

      // ✅ 3. 캐시 저장
      _cachedUsers[area] = result;
      _lastFetchedTime[area] = now;

      return result;
    } catch (e) {
      await FirestoreLogger().log(
        '❌ Firestore 쿼리 실패: $e',
        level: 'error',
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$areaName 지역 근무자 현황'),
      ),
      body: FutureBuilder<List<UserStatus>>(
        future: _fetchUsersForArea(areaName),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('❌ 데이터를 불러오는 중 오류 발생\n${snapshot.error}'),
            );
          }

          final users = snapshot.data ?? [];

          if (users.isEmpty) {
            return const Center(child: Text('📭 해당 지역에 근무자가 없습니다.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                elevation: 2,
                child: ListTile(
                  leading: Icon(
                    user.isWorking ? Icons.check_circle : Icons.remove_circle_outline,
                    color: user.isWorking ? Colors.green : Colors.grey,
                  ),
                  title: Text(user.name),
                  subtitle: Text(user.isWorking ? '출근 중' : '퇴근'),
                  trailing: Text(
                    user.isWorking ? '🟢 출근' : '⚪ 퇴근',
                    style: TextStyle(
                      color: user.isWorking ? Colors.green : Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class UserStatus {
  final String name;
  final bool isWorking;

  UserStatus({
    required this.name,
    required this.isWorking,
  });
}
