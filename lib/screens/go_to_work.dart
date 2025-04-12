import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../states/user/user_state.dart';
import '../../../models/user_model.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/excel_helper.dart';

class GoToWork extends StatefulWidget {
  const GoToWork({super.key});

  @override
  State<GoToWork> createState() => _GoToWorkState();
}

class _GoToWorkState extends State<GoToWork> {
  bool _isLoading = false;

  void _handleWorkStatus(BuildContext context, UserState userState) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // ✅ 출근 시 출석 시간 기록
      if (!userState.isWorking) {
        await _recordAttendance(context);
      }

      await userState.isHeWorking();

      if (!userState.isWorking) {
        await _uploadAttendanceSilently(context);
      }

      if (userState.isWorking && mounted) {
        Navigator.pushReplacementNamed(context, '/type_page');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _recordAttendance(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final int dayColumn = now.day;
    final userState = Provider.of<UserState>(context, listen: false);
    final String userId = userState.user?.id ?? "unknown";
    final String time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
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
    if (existing != null && existing.trim().isNotEmpty) {
      showFailedSnackbar(context, '이미 출근 기록이 있습니다.');
      return;
    }

    cellData[userId] ??= {};
    cellData[userId]![dayColumn] = time;

    final encoded = jsonEncode(
      cellData.map((rowKey, colMap) => MapEntry(
            rowKey,
            colMap.map((col, v) => MapEntry(col.toString(), v)),
          )),
    );
    await prefs.setString(cellDataKey, encoded);

    showSuccessSnackbar(context, '출근 시간 기록 완료: $time');
  }

  Future<void> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) return;

    final now = DateTime.now();
    final selectedYear = now.year;
    final selectedMonth = now.month;

    final prefs = await SharedPreferences.getInstance();
    final key = 'user_list_$area';
    final jsonStr = prefs.getString(key);
    if (jsonStr == null) return;

    final List<dynamic> jsonList = jsonDecode(jsonStr);
    final users = jsonList
        .where((map) => map['id'] != null)
        .map((map) => UserModel.fromJson(Map<String, dynamic>.from(map)))
        .toList();

    final userIds = users.map((u) => u.id).toList();
    final idToName = {for (var u in users) u.id: u.name};

    final uploader = ExcelUploader();
    await uploader.uploadAttendanceAndBreakExcel(
      userIdsInOrder: userIds,
      userIdToName: idToName,
      year: selectedYear,
      month: selectedMonth,
      generatedByName: name,
      generatedByArea: area,
    );
  }

  Widget _buildWorkButton(UserState userState) {
    final isWorking = userState.isWorking;

    final label = isWorking ? '출근 중' : '출근하기';
    final icon = Icons.login;
    final colors = isWorking ? [Colors.grey.shade400, Colors.grey.shade600] : [Colors.green.shade400, Colors.teal];

    return InkWell(
      onTap: _isLoading || isWorking ? null : () => _handleWorkStatus(context, userState),
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
              color: Colors.black.withAlpha(30),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              : Row(
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
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          if (userState.isWorking) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/type_page');
            });
          }

          return SafeArea(
            child: SingleChildScrollView(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 96),
                      SizedBox(
                        height: 120,
                        child: Image.asset('assets/images/belivus_logo.PNG'),
                      ),
                      const SizedBox(height: 96),
                      Text(
                        '출근 전 사용자 정보 확인',
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
                      _buildWorkButton(userState),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
