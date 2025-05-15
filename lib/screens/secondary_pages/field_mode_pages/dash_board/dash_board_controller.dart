import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/excel_helper.dart';

class DashBoardController {
  Future<void> handleWorkStatus(UserState userState, BuildContext context) async {
    if (userState.isWorking) {
      await _recordLeaveTime(context);

      try {
        final now = DateTime.now();
        final prefs = await SharedPreferences.getInstance();

        final cellDataStr = prefs.getString('attendance_cell_data_${now.year}_${now.month}');
        if (cellDataStr == null) return;

        final uploader = ExcelUploader();
        final userId = userState.user?.id ?? "unknown";
        final userName = userState.name;
        final userArea = userState.area;

        final urls = await uploader.uploadAttendanceAndBreakExcel(
          userIdsInOrder: [userId],
          userIdToName: {userId: userName},
          year: now.year,
          month: now.month,
          generatedByName: userName,
          generatedByArea: userArea,
        );

        final attUrl = urls['출근부'];
        final breakUrl = urls['휴게시간'];

        if (attUrl != null && breakUrl != null) {
          debugPrint('✅ 엑셀 업로드 완료');
          debugPrint('📎 출근부: $attUrl');
          debugPrint('📎 휴게시간: $breakUrl');
        } else {
          debugPrint('❌ 일부 또는 전체 엑셀 업로드 실패');
        }
      } catch (e) {
        debugPrint('❌ 엑셀 업로드 중 오류 발생: $e');
      }

      await userState.isHeWorking();
      await Future.delayed(const Duration(seconds: 1));
      exit(0);
    } else {
      await userState.isHeWorking();
    }
  }

  /// ✅ 퇴근 시간 기록 (두 번째 줄만 허용)
  Future<void> _recordLeaveTime(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final int dayColumn = now.day;
      final String currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

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
                Map<int, String>.from((colMap as Map).map((k, v) => MapEntry(int.parse(k), v))),
              )),
        );
      }

      final existing = cellData[userId]?[dayColumn];

      if (!context.mounted) return;

      if (existing == null || existing.trim().isEmpty) {
        showFailedSnackbar(context, '출근 기록이 없습니다. 먼저 출근하세요.');
        return;
      } else if (existing.split('\n').length >= 2) {
        showFailedSnackbar(context, '이미 퇴근 기록이 존재합니다.');
        return;
      }

      cellData[userId]![dayColumn] = '$existing\n$currentTime';

      final encoded = jsonEncode(
        cellData.map((rowKey, colMap) => MapEntry(
              rowKey,
              colMap.map((col, v) => MapEntry(col.toString(), v)),
            )),
      );
      await prefs.setString(cellDataKey, encoded);

      if (context.mounted) {
        showSuccessSnackbar(context, '퇴근 시간 기록 완료: $currentTime');
      }
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '퇴근 시간 저장 실패: $e');
      }
    }
  }

  /// ✅ 휴게 시간 기록
  Future<void> recordBreakTime(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final dayColumn = now.day;
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      if (!context.mounted) return;
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
                Map<int, String>.from((colMap as Map).map((k, v) => MapEntry(int.parse(k), v))),
              )),
        );
      }

      final existing = cellData[userId]?[dayColumn];
      if (existing != null && existing.trim().isNotEmpty) {
        if (!context.mounted) return;
        showFailedSnackbar(context, '이미 기록된 휴게 시간이 있습니다.');
        return;
      }

      cellData[userId] ??= {};
      cellData[userId]![dayColumn] = currentTime;

      final encoded = jsonEncode(
        cellData.map((rowKey, colMap) => MapEntry(
              rowKey,
              colMap.map((col, v) => MapEntry(col.toString(), v)),
            )),
      );
      await prefs.setString(cellDataKey, encoded);

      if (!context.mounted) return;
      showSuccessSnackbar(context, '휴게 시간 저장 완료: $currentTime');
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '휴게 시간 저장 실패: $e');
      }
    }
  }

  /// ✅ 로그아웃
  Future<void> logout(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);

      await userState.isHeWorking();
      await Future.delayed(const Duration(seconds: 1));
      await userState.clearUserToPhone();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('phone');
      await prefs.remove('area');
      await prefs.setBool('isLoggedIn', false);

      if (!context.mounted) return;

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그아웃 실패: $e');
      }
    }

    SystemChannels.platform.invokeMethod('SystemNavigator.pop');
  }
}
