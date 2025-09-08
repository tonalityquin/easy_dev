import 'package:flutter/material.dart';
import '../../../repositories/area_user_repository.dart';

class AreaDetailScreen extends StatelessWidget {
  final String areaName;
  final AreaUserRepository _repo;

  AreaDetailScreen({
    super.key,
    required this.areaName,
    AreaUserRepository? repository,
  }) : _repo = repository ?? AreaUserRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text('$areaName 지역 근무자 현황'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: FutureBuilder<List<UserStatus>>(
        future: _repo.getUsersForArea(areaName),
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
                color: Colors.white,
                margin: const EdgeInsets.symmetric(vertical: 8),
                elevation: 2,
                child: ListTile(
                  leading: Icon(
                    user.isWorking ? Icons.check_circle : Icons.remove_circle_outline,
                    color: user.isWorking ? Colors.green : Colors.white,
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
