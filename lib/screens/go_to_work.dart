import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../models/user_model.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/excel_helper.dart';
import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';

class GoToWork extends StatefulWidget {
  const GoToWork({super.key});

  @override
  State<GoToWork> createState() => _GoToWorkState();
}

class _GoToWorkState extends State<GoToWork> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final prefs = await SharedPreferences.getInstance();
      final storedArea = prefs.getString('area');

      final areaToInit = (storedArea != null && storedArea.isNotEmpty) ? storedArea : userState.area;

      await areaState.initializeArea(userState.area);

      debugPrint('[GoToWork] SharedPreferences에서 불러온 area: $storedArea');
      debugPrint('[GoToWork] 최종 초기화 area: $areaToInit');
      debugPrint('[GoToWork] 초기화 후 currentArea: ${areaState.currentArea}');
    });
  }

  void _handleWorkStatus(BuildContext context, UserState userState) async {
    setState(() => _isLoading = true);

    try {
      await _prepareAttendanceIfNeeded(context, userState);
      await _navigateToProperPageIfWorking(context, userState);
    } catch (e) {
      _showWorkError(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _prepareAttendanceIfNeeded(BuildContext context, UserState userState) async {
    if (!userState.isWorking) {
      await _recordAttendance(context);
    }

    await userState.isHeWorking();

    if (!userState.isWorking) {
      await _uploadAttendanceSilently(context);
    }
  }

  Future<void> _navigateToProperPageIfWorking(BuildContext context, UserState userState) async {
    if (!userState.isWorking || !mounted) return;

    final division = userState.user?.divisions.first ?? '';
    final area = userState.area;
    final doc = await FirebaseFirestore.instance.collection('areas').doc('$division-$area').get();

    if (!mounted) return;

    final isHq = doc.exists && doc['isHeadquarter'] == true;
    Navigator.pushReplacementNamed(context, isHq ? AppRoutes.headquarterPage : AppRoutes.typePage);
  }

  void _showWorkError(BuildContext context) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
      ),
    );
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
              Map<int, String>.from((colMap as Map).map((k, v) => MapEntry(int.parse(k), v))),
            )),
      );
    }

    final existing = cellData[userId]?[dayColumn];

    final yesterday = now.subtract(const Duration(days: 1));
    final int yCol = yesterday.day;
    final existingYesterday = cellData[userId]?[yCol];
    if (existingYesterday != null && existingYesterday.split('\n').length == 1) {
      cellData.putIfAbsent(userId, () => {});
      cellData[userId]![yCol] = '$existingYesterday\n03:00';
    }

    if (existing != null && existing.trim().isNotEmpty) {
      showFailedSnackbar(context, '이미 출근 기록이 있습니다.');
      return;
    }

    cellData.putIfAbsent(userId, () => {});
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

  Future<Map<PlateType, int>> _fetchCounts(BuildContext context) async {
    final repo = context.read<PlateRepository>();
    final userState = context.read<UserState>();
    final area = userState.area; // ✅ 사용자 지역 추출

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final Map<PlateType, int> result = {};
    for (var type in PlateType.values) {
      final count = await repo.getPlateCountByType(
        type,
        selectedDate: type == PlateType.departureCompleted ? today : null,
        area: area, // ✅ 전달
      );
      result[type] = count;
    }
    return result;
  }

  Widget _buildPlateCountsAsync(BuildContext context) {
    return FutureBuilder<Map<PlateType, int>>(
      future: _fetchCounts(context),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final counts = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: PlateType.values.map((type) {
                  return Column(
                    children: [
                      Text(type.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text('${counts[type] ?? 0}건', style: const TextStyle(fontSize: 16, color: Colors.blueAccent)),
                    ],
                  );
                }).toList(),
              ),
              const Divider(height: 32, thickness: 1),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          if (userState.isWorking) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final division = userState.user?.divisions.first ?? '';
              final area = userState.area;

              final doc = await FirebaseFirestore.instance.collection('areas').doc('$division-$area').get();

              if (!mounted) return;

              if (doc.exists && doc['isHeadquarter'] == true) {
                Navigator.pushReplacementNamed(context, '/headquarter_page');
              } else {
                Navigator.pushReplacementNamed(context, '/type_page');
              }
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      _buildPlateCountsAsync(context),
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
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
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
