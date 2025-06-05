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
import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/excel_helper.dart';

class BreakDocumentBody extends StatelessWidget {
  final TextEditingController controller;
  final bool menuOpen;
  final int? selectedRow;
  final int? selectedCol;
  final Set<String> selectedCells;
  final List<UserModel> users;
  final Map<String, Map<int, String>> cellData;
  final int selectedYear;
  final int selectedMonth;
  final void Function(int rowIndex, int colIndex, String rowKey) onCellTapped;
  final Future<void> Function(String rowKey) appendText;
  final Future<void> Function(String rowKey, [List<int>? colIndices]) clearText;
  final VoidCallback toggleMenu;
  final Future<List<UserModel>> Function(String area) getUsersByArea;
  final Future<void> Function(String area) reloadUsers;
  final void Function(int year) onYearChanged;
  final void Function(int month) onMonthChanged;

  const BreakDocumentBody({
    super.key,
    required this.controller,
    required this.menuOpen,
    required this.selectedRow,
    required this.selectedCol,
    required this.selectedCells,
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
                children: text
                    .split('\n')
                    .map((line) => Text(
                          line,
                          style: TextStyle(
                            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ))
                    .toList(),
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
        title: const Text('근무자 휴게시간 테이블', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '사용자 목록 새로고침',
            onPressed: () {
              // 기능 제거됨
            },
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: '휴게시간 불러오기',
            onPressed: () {
              // 기능 제거됨
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '휴게시간 내려받기',
            onPressed: () {
              // 기능 제거됨
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '직원 휴게 테이블 (${selectedArea.isNotEmpty ? selectedArea : "지역 미선택"})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
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
                          } else {
                            return _buildCell(text: '${index - 1}', isHeader: true, isSelected: false);
                          }
                        }),
                      ),
                      const SizedBox(height: 8),
                      ...users.asMap().entries.expand((entry) {
                        final user = entry.value;
                        final rowKey = user.id;
                        return [
                          _buildDataRow(user.name, '시작', rowKey, 0),
                          _buildDataRow('', '종료', rowKey, 1),
                        ];
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
                    if (selectedRow != null && selectedRow! ~/ 2 < users.length) {
                      final rowKey = users[selectedRow! ~/ 2].id;
                      appendText(rowKey);
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
                    final Map<String, List<int>> rows = {};
                    for (final cell in selectedCells) {
                      final parts = cell.split(':');
                      if (parts.length == 2) {
                        final key = parts[0];
                        final col = int.tryParse(parts[1]);
                        if (col != null) {
                          rows.putIfAbsent(key, () => []).add(col);
                        }
                      }
                    }
                    for (final entry in rows.entries) {
                      clearText(entry.key, entry.value);
                    }
                  },
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.delete),
                ),
                const SizedBox(height: 12),
              ],
            ),
          FloatingActionButton(
            heroTag: 'breakFab',
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

  Widget _buildDataRow(String name, String label, String rowKey, int offset) {
    final rowIndex = users.indexWhere((u) => u.id == rowKey) * 2 + offset;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: List.generate(34, (colIndex) {
          if (colIndex == 0) {
            return _buildCell(text: name, isHeader: offset == 0, isSelected: false);
          }
          if (colIndex == 1) {
            return _buildCell(text: label, isHeader: false, isSelected: false);
          }
          if (colIndex == 33) {
            return _buildCell(text: '', isHeader: false, isSelected: false, width: 120);
          }

          final day = colIndex - 1;
          final key = '$rowKey:$day';
          final text = cellData[rowKey]?[day] ?? '';
          final isSel = selectedCells.contains(key);

          return _buildCell(
            text: text,
            isHeader: false,
            isSelected: isSel,
            onTap: offset == 0 ? () => onCellTapped(rowIndex, colIndex, rowKey) : null,
          );
        }),
      ),
    );
  }
}
