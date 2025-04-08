import 'dart:io';
import 'dart:convert';
import 'package:excel/excel.dart';
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
      final attendanceRaw = prefs.getString('attendance_cell_data_${year}_${month}');
      final breakRaw = prefs.getString('break_cell_data_${year}_${month}');
      final attendanceData = _parseCellData(attendanceRaw);
      final breakData = _parseCellData(breakRaw);

      final urls = <String, String?>{};
      final centerStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      // ✅ 출근부 엑셀 생성
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
        final rowMap = attendanceData[userId] ?? {};

        final startRow = [
          TextCellValue(name),
          TextCellValue(userId),
          TextCellValue('출근'),
          ...List.generate(31, (i) {
            final cell = rowMap[i + 1] ?? '';
            return TextCellValue(cell
                .split('\n')
                .firstOrNull ?? '');
          }),
          TextCellValue(''),
        ];

        final endRow = [
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue('퇴근'),
          ...List.generate(31, (i) {
            final cell = rowMap[i + 1] ?? '';
            return TextCellValue(cell
                .split('\n')
                .length > 1 ? cell.split('\n')[1] : '');
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

      final attendanceFileName = '출근부_${safeName}_${safeArea}_${year}년_${month}월.xlsx';
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
        final rowMap = breakData[userId] ?? {};

        final startRow = [
          TextCellValue(name),
          TextCellValue(userId),
          TextCellValue('시작'),
          ...List.generate(31, (i) {
            final cell = rowMap[i + 1] ?? '';
            return TextCellValue(cell
                .split('\n')
                .firstOrNull ?? '');
          }),
          TextCellValue(''),
        ];

        final endRow = [
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue('종료'),
          ...List.generate(31, (i) {
            final cell = rowMap[i + 1] ?? '';
            return TextCellValue(cell
                .split('\n')
                .length > 1 ? cell.split('\n')[1] : '');
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

      final breakFileName = '휴게시간_${safeName}_${safeArea}_${year}년_${month}월.xlsx';
      final breakPath = '${dir.path}/$breakFileName';
      final breakFile = File(breakPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(breakExcel.encode()!);
      urls['휴게시간'] = await _uploadToGCS(breakFile, 'exports/$breakFileName');

      return urls;
    } catch (e) {
      print('❌ 엑셀 생성 또는 업로드 실패: $e');
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
      print('❌ JSON 파싱 오류: $e');
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
