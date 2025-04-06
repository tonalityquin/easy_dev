import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart' as excel;
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/user_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/excel_helper.dart';
import '../../../../utils/snackbar_helper.dart';

class AttendanceDocumentBody extends StatelessWidget {
  final TextEditingController controller;
  final bool menuOpen;
  final int? selectedRow;
  final int? selectedCol;
  final List<UserModel> users;
  final Map<String, Map<int, String>> cellData;
  final int selectedYear;
  final int selectedMonth;
  final void Function(int rowIndex, int colIndex, String rowKey) onCellTapped;
  final Future<void> Function(String rowKey) appendText;
  final Future<void> Function(String rowKey) clearText;
  final VoidCallback toggleMenu;
  final Future<List<UserModel>> Function(String area) getUsersByArea;
  final Future<void> Function(String area) reloadUsers;
  final void Function(int year) onYearChanged;
  final void Function(int month) onMonthChanged;

  const AttendanceDocumentBody({
    super.key,
    required this.controller,
    required this.menuOpen,
    required this.selectedRow,
    required this.selectedCol,
    required this.users,
    required this.cellData,
    required this.selectedYear,
    required this.selectedMonth,
    required this.onCellTapped,
    required this.appendText,
    required this.clearText,
    required this.toggleMenu,
    required this.getUsersByArea,
    required this.reloadUsers,
    required this.onYearChanged,
    required this.onMonthChanged,
  });

  Widget _buildCell({
    required String text,
    required bool isHeader,
    required bool isSelected,
    VoidCallback? onTap,
    double width = 60,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 40,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          color: isHeader
              ? Colors.grey.shade200
              : isSelected
                  ? Colors.lightBlue.shade100
                  : Colors.white,
        ),
        child: text.contains('\n')
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: text.split('\n').map((line) {
                  return Text(
                    line,
                    style: TextStyle(
                      fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                      height: 1.3,
                    ),
                    textAlign: TextAlign.center,
                  );
                }).toList(),
              )
            : Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedArea = context.watch<AreaState>().currentArea;
    final now = DateTime.now();
    final yearList = List.generate(20, (i) => now.year - 5 + i);
    final monthList = List.generate(12, (i) => i + 1);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('근무자 출퇴근 테이블', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: '출근부 불러오기',
            onPressed: () async {
              if (selectedArea.isEmpty) {
                showFailedSnackbar(context, '지역을 먼저 선택하세요');
                return;
              }

              showSuccessSnackbar(context, '출근부 불러오는 중...');

              try {
                final safeArea = selectedArea.replaceAll(' ', '_');
                final Map<String, Map<int, String>> newData = {};

                for (final user in users) {
                  final safeName = user.name.replaceAll(' ', '_');
                  final fileName = '출근부_${safeName}_${safeArea}_${selectedYear}년_${selectedMonth}월.xlsx';
                  final fileUrl = 'https://storage.googleapis.com/easydev-image/exports/$fileName';

                  debugPrint('🧾 파일 요청: $fileUrl');

                  final response = await http.get(Uri.parse(fileUrl));
                  if (response.statusCode != 200) {
                    debugPrint('❌ 파일 없음: $fileName');
                    continue;
                  }

                  final workbook = excel.Excel.decodeBytes(response.bodyBytes);
                  final sheet = workbook['출근부'];

                  for (int row = 1; row < sheet.maxRows; row += 2) {
                    String? userId =
                        sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value?.toString();

                    if (userId == null || userId.isEmpty || !users.any((u) => u.id == userId)) {
                      final nameFromCell = sheet
                          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
                          .value
                          ?.toString()
                          .trim();
                      final matchedUser = users.firstWhereOrNull((u) => u.name.trim() == nameFromCell);
                      if (matchedUser == null) {
                        debugPrint('⚠️ 이름으로도 매칭 실패: $nameFromCell');
                        continue;
                      }
                      userId = matchedUser.id;
                    }

                    final startRow = sheet.row(row);
                    final endRow = sheet.row(row + 1);
                    final startMap = <int, String>{};
                    final endMap = <int, String>{};

                    for (int day = 0; day < 31; day++) {
                      final col = day + 3;
                      final start = startRow[col]?.value?.toString() ?? '';
                      final end = endRow[col]?.value?.toString() ?? '';
                      if (start.isNotEmpty) startMap[day + 1] = start;
                      if (end.isNotEmpty) endMap[day + 1] = end;
                    }

                    newData[userId] = startMap;
                    newData['${userId}_out'] = endMap;
                  }
                }

                // ✅ 기존 데이터와 병합
                final prefs = await SharedPreferences.getInstance();
                final existingJson = prefs.getString('attendance_cell_data_${selectedYear}_${selectedMonth}');
                Map<String, Map<int, String>> mergedData = {};

                if (existingJson != null) {
                  final decoded = jsonDecode(existingJson);
                  mergedData = Map<String, Map<int, String>>.from(
                    decoded.map((key, val) => MapEntry(
                          key,
                          Map<int, String>.from((val as Map).map((k, v) => MapEntry(int.parse(k), v))),
                        )),
                  );
                }

                // ✅ newData를 기존 데이터에 덮어쓰기 방식으로 병합
                for (final entry in newData.entries) {
                  mergedData[entry.key] ??= {};
                  mergedData[entry.key]!.addAll(entry.value);
                }

                // ✅ 메모리 반영
                cellData.clear();
                cellData.addAll(mergedData);

                // ✅ SharedPreferences 저장
                final encoded = jsonEncode(
                  mergedData.map((key, map) => MapEntry(key, map.map((day, val) => MapEntry(day.toString(), val)))),
                );
                await prefs.setString('attendance_cell_data_${selectedYear}_${selectedMonth}', encoded);
                debugPrint('✅ SharedPreferences 병합 저장 완료');

                showSuccessSnackbar(context, '출근부 불러오기 완료!');
              } catch (e) {
                showFailedSnackbar(context, '불러오기 중 오류 발생: $e');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '사용자 목록 새로고침',
            onPressed: () async {
              if (selectedArea.isNotEmpty) {
                await reloadUsers(selectedArea);
              } else {
                showFailedSnackbar(context, '지역을 먼저 선택하세요');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '출근부 내려받기',
            onPressed: () async {
              if (selectedArea.isEmpty) {
                showFailedSnackbar(context, '지역을 먼저 선택하세요');
                return;
              }

              showSuccessSnackbar(context, '출근부 생성 중...');

              try {
                final prefs = await SharedPreferences.getInstance();
                final raw = prefs.getString('attendance_cell_data_${selectedYear}_${selectedMonth}');
                if (raw == null) {
                  showFailedSnackbar(context, '출근부 데이터가 없습니다.');
                  return;
                }

                final userIdToName = {for (var u in users) u.id: u.name};
                final userIdsInOrder = users.map((u) => u.id).toList();

                final uploader = ExcelUploader();
                final urls = await uploader.uploadAttendanceAndBreakExcel(
                  userIdsInOrder: userIdsInOrder,
                  userIdToName: userIdToName,
                  year: selectedYear,
                  month: selectedMonth,
                  generatedByName: context.read<UserState>().name,
                  generatedByArea: selectedArea,
                );

                if (urls['출근부'] != null) {
                  debugPrint('📁 생성 완료: ${urls['출근부']}');
                  showSuccessSnackbar(context, '출근부 다운로드 링크가 생성되었습니다.');
                } else {
                  showFailedSnackbar(context, '출근부 생성 실패');
                }
              } catch (e) {
                showFailedSnackbar(context, '다운로드 중 오류: $e');
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '직원 근무 테이블 (${selectedArea.isNotEmpty ? selectedArea : "지역 미선택"})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: selectedYear,
                      items: yearList.map((y) => DropdownMenuItem(value: y, child: Text('$y년'))).toList(),
                      onChanged: (value) {
                        if (value != null) onYearChanged(value);
                      },
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: selectedMonth,
                      items: monthList.map((m) => DropdownMenuItem(value: m, child: Text('$m월'))).toList(),
                      onChanged: (value) {
                        if (value != null) onMonthChanged(value);
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: [
                      Row(
                        children: List.generate(34, (index) {
                          if (index == 0) {
                            return _buildCell(text: '', isHeader: true, isSelected: false);
                          } else if (index == 1) {
                            return _buildCell(text: '출근/퇴근', isHeader: true, isSelected: false);
                          } else if (index == 33) {
                            return _buildCell(text: '사인란', isHeader: true, isSelected: false, width: 120);
                          }
                          return _buildCell(text: '${index - 1}', isHeader: true, isSelected: false);
                        }),
                      ),
                      const SizedBox(height: 8),
                      ...users.asMap().entries.expand((entry) sync* {
                        final rowIndex = entry.key;
                        final user = entry.value;
                        final rowKey = user.id;

                        for (int i = 0; i < 2; i++) {
                          final isCheckIn = i == 0;
                          final label = isCheckIn ? '출근' : '퇴근';
                          final logicalRow = rowIndex * 2 + i;

                          yield Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: List.generate(34, (colIndex) {
                                if (colIndex == 0) {
                                  return _buildCell(text: user.name, isHeader: true, isSelected: false);
                                } else if (colIndex == 1) {
                                  return _buildCell(text: label, isHeader: false, isSelected: false);
                                } else if (colIndex == 33) {
                                  return _buildCell(text: '', isHeader: false, isSelected: false, width: 120);
                                }

                                final dateCol = colIndex - 1;
                                final fullKey = isCheckIn ? rowKey : '${rowKey}_out';
                                final isSel = selectedRow == logicalRow && selectedCol == colIndex;
                                final text = cellData[fullKey]?[dateCol] ?? '';

                                return _buildCell(
                                  text: text,
                                  isHeader: false,
                                  isSelected: isSel,
                                  onTap: () => onCellTapped(logicalRow, colIndex, fullKey),
                                );
                              }),
                            ),
                          );
                        }
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (menuOpen)
            Column(
              children: [
                FloatingActionButton(
                  heroTag: 'saveBtn',
                  mini: true,
                  onPressed: () {
                    if (selectedRow != null && (selectedRow! ~/ 2) < users.length) {
                      final userId = users[selectedRow! ~/ 2].id;
                      final fullKey = selectedRow! % 2 == 0 ? userId : '${userId}_out';
                      appendText(fullKey);
                    }
                  },
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.save),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'clearBtn',
                  mini: true,
                  onPressed: () {
                    if (selectedRow != null && (selectedRow! ~/ 2) < users.length) {
                      final userId = users[selectedRow! ~/ 2].id;
                      final fullKey = selectedRow! % 2 == 0 ? userId : '${userId}_out';
                      clearText(fullKey);
                    }
                  },
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.delete),
                ),
                const SizedBox(height: 12),
              ],
            ),
          FloatingActionButton(
            heroTag: 'attendanceFab',
            onPressed: toggleMenu,
            backgroundColor: Colors.blueAccent,
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 300),
              turns: menuOpen ? 0.25 : 0.0,
              child: const Icon(Icons.more_vert),
            ),
          ),
        ],
      ),
    );
  }
}
