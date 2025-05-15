import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../models/user_model.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/excel_helper.dart';

class GoToWorkController {
  void initialize(BuildContext context) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final prefs = await SharedPreferences.getInstance();
      final storedArea = prefs.getString('area');

      final areaToInit = (storedArea != null && storedArea.isNotEmpty) ? storedArea : userState.area;

      await areaState.initializeArea(areaToInit);

      debugPrint('[GoToWork] SharedPreferences에서 불러온 area: $storedArea');
      debugPrint('[GoToWork] 최종 초기화 area: $areaToInit');
      debugPrint('[GoToWork] 초기화 후 currentArea: ${areaState.currentArea}');
    });
  }

  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final division = userState.user?.divisions.first ?? '';
      final area = userState.area;
      final doc = await FirebaseFirestore.instance.collection('areas').doc('$division-$area').get();

      if (!context.mounted) return;

      if (doc.exists && doc['isHeadquarter'] == true) {
        Navigator.pushReplacementNamed(context, AppRoutes.headquarterPage);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.typePage);
      }
    });
  }

  Future<void> handleWorkStatus(BuildContext context, UserState userState, VoidCallback onLoadingChanged) async {
    onLoadingChanged.call();

    try {
      if (!userState.isWorking) {
        await _recordAttendance(context);
      }

      await userState.isHeWorking();

      if (userState.isWorking) {
        await _navigateToProperPageIfWorking(context, userState);
      } else {
        await _uploadAttendanceSilently(context);
      }
    } catch (e) {
      _showWorkError(context);
    } finally {
      onLoadingChanged.call();
    }
  }

  Future<void> _navigateToProperPageIfWorking(BuildContext context, UserState userState) async {
    if (!userState.isWorking || !context.mounted) return;

    final division = userState.user?.divisions.first ?? '';
    final area = userState.area;
    final doc = await FirebaseFirestore.instance.collection('areas').doc('$division-$area').get();

    if (!context.mounted) return;

    final isHq = doc.exists && doc['isHeadquarter'] == true;
    Navigator.pushReplacementNamed(context, isHq ? AppRoutes.headquarterPage : AppRoutes.typePage);
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;

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
}
