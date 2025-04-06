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

  Future<String?> uploadAttendanceAndBreakExcel({
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

      final excel = Excel.createExcel();
      excel.rename('Sheet1', '출석기록');

      final attendanceSheet = excel['출석기록'];
      final breakSheet = excel['휴게기록'];

      final centerStyle = CellStyle(
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center, // ✅ 추가
      );

      // 헤더 생성
      final header = <CellValue>[
        TextCellValue('이름'),
        TextCellValue('출근/퇴근'),
        ...List.generate(31, (i) => TextCellValue('${i + 1}일')),
        TextCellValue('사인란'),
      ];
      final breakHeader = <CellValue>[
        TextCellValue('이름'),
        TextCellValue('시작/종료'),
        ...List.generate(31, (i) => TextCellValue('${i + 1}일')),
        TextCellValue('사인란'),
      ];

      // 헤더 작성
      for (int col = 0; col < header.length; col++) {
        final index = CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0);
        attendanceSheet.updateCell(index, header[col], cellStyle: centerStyle);
        breakSheet.updateCell(index, breakHeader[col], cellStyle: centerStyle);
      }

      int currentRow = 1;

      for (final userId in userIdsInOrder) {
        final name = userIdToName[userId] ?? '(이름 없음)';
        final attRowMap = attendanceData[userId] ?? {};
        final breakRowMap = breakData[userId] ?? {};

        // 출석기록 - 출근/퇴근
        final attStartRow = [
          TextCellValue(name),
          TextCellValue('출근'),
          ...List.generate(31, (i) {
            final cell = attRowMap[i + 1] ?? '';
            return TextCellValue(cell.split('\n').firstOrNull ?? '');
          }),
          TextCellValue(''),
        ];
        final attEndRow = [
          TextCellValue(''),
          TextCellValue('퇴근'),
          ...List.generate(31, (i) {
            final cell = attRowMap[i + 1] ?? '';
            return TextCellValue(cell.split('\n').length > 1 ? cell.split('\n')[1] : '');
          }),
          TextCellValue(''),
        ];

        for (int col = 0; col < attStartRow.length; col++) {
          attendanceSheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: currentRow),
            attStartRow[col],
            cellStyle: centerStyle,
          );
          attendanceSheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: currentRow + 1),
            attEndRow[col],
            cellStyle: centerStyle,
          );
        }

        attendanceSheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow + 1),
        );

        // 휴게기록 - 시작/종료
        final breakStartRow = [
          TextCellValue(name),
          TextCellValue('시작'),
          ...List.generate(31, (i) {
            final cell = breakRowMap[i + 1] ?? '';
            return TextCellValue(cell.split('\n').firstOrNull ?? '');
          }),
          TextCellValue(''),
        ];
        final breakEndRow = [
          TextCellValue(''),
          TextCellValue('종료'),
          ...List.generate(31, (i) {
            final cell = breakRowMap[i + 1] ?? '';
            return TextCellValue(cell.split('\n').length > 1 ? cell.split('\n')[1] : '');
          }),
          TextCellValue(''),
        ];

        for (int col = 0; col < breakStartRow.length; col++) {
          breakSheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: currentRow),
            breakStartRow[col],
            cellStyle: centerStyle,
          );
          breakSheet.updateCell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: currentRow + 1),
            breakEndRow[col],
            cellStyle: centerStyle,
          );
        }

        breakSheet.merge(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow + 1),
        );

        currentRow += 2;
      }

      final dir = await getTemporaryDirectory();
      final safeName = generatedByName.replaceAll(' ', '_');
      final safeArea = generatedByArea.replaceAll(' ', '_');
      final fileName = '근태기록_${safeName}_${safeArea}_${year}년_${month}월.xlsx';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(excel.encode()!);

      return await _uploadToGCS(file, 'exports/$fileName');
    } catch (e) {
      print('❌ 엑셀 생성 또는 업로드 실패: $e');
      return null;
    }
  }

  Map<String, Map<int, String>> _parseCellData(String? jsonStr) {
    if (jsonStr == null) return {};
    try {
      final decoded = jsonDecode(jsonStr);
      return Map<String, Map<int, String>>.from(
        decoded.map((userId, colMap) => MapEntry(
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
