import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../../states/area/area_state.dart';
import 'attendance_table_row.dart';

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
            icon: const Icon(Icons.refresh),
            tooltip: '사용자 목록 새로고침',
            onPressed: () {
              // TODO: 사용자 목록 새로고침 기능 구현 예정
            },
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: '출근부 불러오기',
            onPressed: () {
              // TODO: 출근부 불러오기 기능 구현 예정
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '출근부 내려받기',
            onPressed: () {
              // TODO: 출근부 내려받기 기능 구현 예정
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
                    '직원 근무 테이블 (${selectedArea.isNotEmpty ? selectedArea : "지역 미선택"})',
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
                          if (index == 0) return _buildHeaderCell('');
                          if (index == 1) return _buildHeaderCell('출근/퇴근');
                          if (index == 33) return _buildHeaderCell('사인란', width: 120);
                          return _buildHeaderCell('${index - 1}');
                        }),
                      ),
                      const SizedBox(height: 8),
                      ...users.asMap().entries.expand((entry) sync* {
                        final rowIndex = entry.key;
                        final user = entry.value;
                        yield AttendanceTableRow(
                          user: user,
                          rowIndex: rowIndex,
                          selectedRow: selectedRow,
                          selectedCol: selectedCol,
                          cellData: cellData,
                          onCellTapped: onCellTapped,
                        );
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
                    if (selectedRow != null && selectedRow! ~/ 2 < users.length) {
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

  Widget _buildHeaderCell(String text, {double width = 60}) {
    return Container(
      width: width,
      height: 40,
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.grey.shade200,
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.3),
        textAlign: TextAlign.center,
      ),
    );
  }
}
