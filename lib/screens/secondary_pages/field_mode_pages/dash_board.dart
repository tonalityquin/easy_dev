import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import '../../../states/user/user_state.dart';

class DashBoard extends StatelessWidget {
  const DashBoard({super.key});

  /// ✅ 퇴근 시간 기록 함수 (두 번째 줄만 허용)
  Future<void> _recordLeaveTime(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final int dayColumn = now.day;
      final String currentTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final userState = Provider.of<UserState>(context, listen: false);
      final String userId = userState.user?.id ?? "unknown";
      final String cellDataKey = 'attendance_cell_data_${now.year}_${now.month}';

      final jsonStr = prefs.getString(cellDataKey);
      Map<String, Map<int, String>> cellData = {};

      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr);
        cellData = Map<String, Map<int, String>>.from(
          decoded.map((rowKey, colMap) => MapEntry(
            rowKey,
            Map<int, String>.from(
              (colMap as Map).map((k, v) => MapEntry(int.parse(k), v)),
            ),
          )),
        );
      }

      final existing = cellData[userId]?[dayColumn];
      if (existing == null || existing.trim().isEmpty) {
        showFailedSnackbar(context, '출근 기록이 없습니다. 먼저 출근하세요.');
        return;
      } else if (existing.split('\n').length >= 2) {
        showFailedSnackbar(context, '이미 퇴근 기록이 존재합니다.');
        return;
      }

      // 두 번째 줄로 퇴근 시간 추가
      cellData[userId]![dayColumn] = '$existing\n$currentTime';

      final encoded = jsonEncode(
        cellData.map((rowKey, colMap) => MapEntry(
          rowKey,
          colMap.map((col, v) => MapEntry(col.toString(), v)),
        )),
      );
      await prefs.setString(cellDataKey, encoded);

      showSuccessSnackbar(context, '퇴근 시간 기록 완료: $currentTime');
    } catch (e) {
      showFailedSnackbar(context, '퇴근 시간 저장 실패: $e');
    }
  }

  /// 🔹 출근 / 퇴근 처리 + 퇴근 시간 기록
  Future<void> _handleWorkStatus(UserState userState, BuildContext context) async {
    if (userState.isWorking) {
      await _recordLeaveTime(context); // ✅ 퇴근 시간 기록 먼저 시도
      await userState.isHeWorking();
      await Future.delayed(const Duration(seconds: 1));
      exit(0);
    } else {
      await userState.isHeWorking();
    }
  }

  /// 🔹 로그아웃 처리
  Future<void> _logout(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);

      await userState.isHeWorking();
      await Future.delayed(const Duration(seconds: 1));
      await userState.clearUserToPhone();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('phone');
      await prefs.remove('area');
      await prefs.setBool('isLoggedIn', false);

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      showFailedSnackbar(context, '로그아웃 실패: $e');
    }

    SystemChannels.platform.invokeMethod('SystemNavigator.pop');
  }

  /// 🔹 사용자 정보 출력
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(value, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  /// ✅ 휴게 시간 기록 함수
  Future<void> _recordBreakTime(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final dayColumn = now.day;
      final currentTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final userState = Provider.of<UserState>(context, listen: false);
      final userId = userState.user?.id ?? "unknown";

      final cellDataKey = 'break_cell_data_${now.year}_${now.month}';
      final jsonStr = prefs.getString(cellDataKey);

      Map<String, Map<int, String>> cellData = {};

      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr);
        cellData = Map<String, Map<int, String>>.from(
          decoded.map((rowKey, colMap) => MapEntry(
            rowKey,
            Map<int, String>.from(
              (colMap as Map).map((k, v) => MapEntry(int.parse(k), v)),
            ),
          )),
        );
      }

      // ✅ 이미 값이 존재하는지 확인
      final existing = cellData[userId]?[dayColumn];
      if (existing != null && existing.trim().isNotEmpty) {
        showFailedSnackbar(context, '이미 기록된 휴게 시간이 있습니다.');
        return;
      }

      // 시간 기록
      cellData[userId] ??= {};
      cellData[userId]![dayColumn] = currentTime;

      final encoded = jsonEncode(
        cellData.map((rowKey, colMap) => MapEntry(
          rowKey,
          colMap.map((col, v) => MapEntry(col.toString(), v)),
        )),
      );
      await prefs.setString(cellDataKey, encoded);

      showSuccessSnackbar(context, '휴게 시간 저장 완료: $currentTime');
    } catch (e) {
      showFailedSnackbar(context, '휴게 시간 저장 실패: $e');
    }
  }

  /// 🔹 휴게 인증 버튼
  Widget _buildBreakButton(BuildContext context) {
    return InkWell(
      onTap: () async {
        await _recordBreakTime(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 55,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF90CAF9), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.coffee, color: Colors.white),
              SizedBox(width: 8),
              Text(
                '휴게 사용 확인',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔹 출근 / 퇴근 버튼
  Widget _buildWorkButton(UserState userState, BuildContext context) {
    final isWorking = userState.isWorking;
    final label = isWorking ? '퇴근하기' : '출근하기';
    final icon = isWorking ? Icons.logout : Icons.login;
    final colors = isWorking ? [Colors.redAccent, Colors.deepOrange] : [Colors.green.shade400, Colors.teal];

    return InkWell(
      onTap: () => _handleWorkStatus(userState, context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 55,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '대시보드',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _logout(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('로그아웃'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          )
        ],
      ),
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Text(
                      '사용자 정보',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow('이름', userState.name),
                            _infoRow('전화번호', userState.phone),
                            _infoRow('역할', userState.role),
                            _infoRow('지역', userState.area),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildBreakButton(context),
                    const SizedBox(height: 16),
                    _buildWorkButton(userState, context),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: const SecondaryMiniNavigation(
        icons: [
          Icons.search,
          Icons.person,
          Icons.sort,
        ],
      ),
    );
  }
}
