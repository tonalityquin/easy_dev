import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExcelUploader {
  final String bucketName = 'easydev-image';
  final String projectId = 'easydev-97fb6';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  Future<Map<String, String?>> uploadAttendanceAndBreakExcel({
    required List<String> userIdsInOrder,
    required Map<String, String> userIdToName,
    required int year,
    required int month,
    required String generatedByName,
    required String generatedByArea,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final attendanceRaw = prefs.getString('attendance_cell_data_${year}_$month');
      final breakRaw = prefs.getString('break_cell_data_${year}_$month');
      final attendanceData = _parseCellData(attendanceRaw);
      final breakData = _parseCellData(breakRaw);

      final urls = <String, String?>{};
      final centerStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final attendanceExcel = Excel.createExcel();
      attendanceExcel.rename('Sheet1', '출근부');
      final attendanceSheet = attendanceExcel['출근부'];

      final header = <CellValue>[
        TextCellValue('이름'),
        TextCellValue('ID'),
        TextCellValue('출근/퇴근'),
        ...List.generate(31, (i) => TextCellValue('${i + 1}일')),
        TextCellValue('사인란'),
      ];

      for (int col = 0; col < header.length; col++) {
        attendanceSheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
          header[col],
          cellStyle: centerStyle,
        );
      }

      int row = 1;
      for (final userId in userIdsInOrder) {
        final name = userIdToName[userId] ?? '(이름 없음)';
        final rowMapIn = attendanceData[userId] ?? {};
        final rowMapOut = attendanceData['${userId}_out'] ?? {};

        final startRow = [
          TextCellValue(name),
          TextCellValue(userId),
          TextCellValue('출근'),
          ...List.generate(31, (i) {
            final value = rowMapIn[i + 1] ?? '';
            return TextCellValue(value);
          }),
          TextCellValue(''),
        ];

        final endRow = [
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue('퇴근'),
          ...List.generate(31, (i) {
            final value = rowMapOut[i + 1] ?? '';
            final displayValue = value == '03:00' ? '03:00*' : value;
            return TextCellValue(displayValue);
          }),
          TextCellValue(''),
        ];

        for (int col = 0; col < startRow.length; col++) {
          attendanceSheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
            startRow[col],
            cellStyle: centerStyle,
          );
          attendanceSheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1),
            endRow[col],
            cellStyle: centerStyle,
          );
        }

        attendanceSheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row + 1),
        );

        row += 2;
      }

      final dir = await getTemporaryDirectory();
      final safeName = generatedByName.replaceAll(' ', '_');
      final safeArea = generatedByArea.replaceAll(' ', '_');
      final isSingleUser = userIdsInOrder.length == 1;

      final attendanceFileName = isSingleUser
          ? '출근부_${safeName}_${safeArea}_$year년_$month월.xlsx'
          : '출근부_${safeArea}_$year년_$month월.xlsx';
      final attendancePath = '${dir.path}/$attendanceFileName';
      final attendanceFile = File(attendancePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(attendanceExcel.encode()!);
      urls['출근부'] = await _uploadToGCS(attendanceFile, 'exports/$attendanceFileName');

      // ✅ 휴게시간 엑셀 생성
      final breakExcel = Excel.createExcel();
      breakExcel.rename('Sheet1', '휴게시간');
      final breakSheet = breakExcel['휴게시간'];

      final breakHeader = <CellValue>[
        TextCellValue('이름'),
        TextCellValue('ID'),
        TextCellValue('시작/종료'),
        ...List.generate(31, (i) => TextCellValue('${i + 1}일')),
        TextCellValue('사인란'),
      ];

      for (int col = 0; col < breakHeader.length; col++) {
        breakSheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
          breakHeader[col],
          cellStyle: centerStyle,
        );
      }

      row = 1;
      for (final userId in userIdsInOrder) {
        final name = userIdToName[userId] ?? '(이름 없음)';
        final rowMapIn = breakData[userId] ?? {};
        final rowMapOut = breakData['${userId}_out'] ?? {};

        final startRow = [
          TextCellValue(name),
          TextCellValue(userId),
          TextCellValue('시작'),
          ...List.generate(31, (i) {
            final value = rowMapIn[i + 1] ?? '';
            return TextCellValue(value);
          }),
          TextCellValue(''),
        ];

        final endRow = [
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue('종료'),
          ...List.generate(31, (i) {
            final value = rowMapOut[i + 1] ?? '';
            return TextCellValue(value);
          }),
          TextCellValue(''),
        ];

        for (int col = 0; col < startRow.length; col++) {
          breakSheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
            startRow[col],
            cellStyle: centerStyle,
          );
          breakSheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1),
            endRow[col],
            cellStyle: centerStyle,
          );
        }

        breakSheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row + 1),
        );

        row += 2;
      }

      final breakFileName = isSingleUser
          ? '휴게시간_${safeName}_${safeArea}_$year년_$month월.xlsx'
          : '휴게시간_${safeArea}_$year년_$month월.xlsx';
      final breakPath = '${dir.path}/$breakFileName';
      final breakFile = File(breakPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(breakExcel.encode()!);
      urls['휴게시간'] = await _uploadToGCS(breakFile, 'exports/$breakFileName');

      return urls;
    } catch (e) {
      debugPrint('❌ 엑셀 생성 또는 업로드 실패: $e');
      return {};
    }
  }

  Map<String, Map<int, String>> _parseCellData(String? jsonStr) {
    if (jsonStr == null) return {};
    try {
      final decoded = jsonDecode(jsonStr);
      return Map<String, Map<int, String>>.from(
        decoded.map((userId, colMap) =>
            MapEntry(
              userId,
              Map<int, String>.from(
                (colMap as Map).map((k, v) => MapEntry(int.parse(k), v)),
              ),
            )),
      );
    } catch (e) {
      debugPrint('❌ JSON 파싱 오류: $e');
      return {};
    }
  }

  Future<String?> _uploadToGCS(File file, String destinationPath) async {
    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final scopes = [StorageApi.devstorageFullControlScope];

    final client = await clientViaServiceAccount(accountCredentials, scopes);
    final storage = StorageApi(client);

    final media = Media(file.openRead(), file.lengthSync());
    final object = await storage.objects.insert(
      Object()
        ..name = destinationPath
        ..acl = [
          ObjectAccessControl()
            ..entity = 'allUsers'
            ..role = 'READER'
        ],
      bucketName,
      uploadMedia: media,
    );

    client.close();
    return 'https://storage.googleapis.com/$bucketName/${object.name}';
  }
}
