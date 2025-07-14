// 생략 없이 import 포함
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../states/user/user_state.dart';
import '../../type_pages/debugs/firestore_logger.dart';
import '../../clock_in_pages/utils/clock_in_log_downloader.dart';
import '../../secondary_pages/field_leader_pages/utils/clock_out_log_downloader.dart';
import 'attendances/attendance_table_row.dart';

class AttendanceCell extends StatefulWidget {
  final TextEditingController controller;
  final bool menuOpen;
  final int? selectedRow;
  final int? selectedCol;
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
  final Future<void> Function(Map<String, Map<int, String>> newData) onLoadJson;

  const AttendanceCell({
    super.key,
    required this.controller,
    required this.menuOpen,
    required this.selectedRow,
    required this.selectedCol,
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
    required this.onLoadJson,
  });

  @override
  State<AttendanceCell> createState() => _AttendanceCellState();
}

class _AttendanceCellState extends State<AttendanceCell> {
  List<String> _areaList = [];
  String? _selectedArea;
  List<UserModel> _localUsers = [];

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    final userState = context.read<UserState>();
    final userAreas = userState.user?.areas ?? [];

    if (userAreas.isEmpty) {
      await FirestoreLogger().log('⚠️ 사용자 소속 지역 없음', level: 'error');
    }

    final snapshot = await FirebaseFirestore.instance.collection('areas').get();
    final allAreas = snapshot.docs.map((doc) => doc['name'] as String).toList();
    final filtered = allAreas.where((area) => userAreas.contains(area)).toList();

    setState(() {
      _areaList = filtered;
      if (filtered.isNotEmpty) {
        _selectedArea = filtered.first;
        _reloadUsersForArea(_selectedArea!);
      }
    });
  }

  Future<void> _reloadUsersForArea(String area) async {
    final users = await widget.getUsersByArea(area);
    if (!mounted) return;
    setState(() => _localUsers = users);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final yearList = List.generate(20, (i) => now.year - 5 + i);
    final monthList = List.generate(12, (i) => i + 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('근무자 출퇴근 테이블', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '사용자 목록 새로고침',
            onPressed: () {
              if (_selectedArea != null) {
                _reloadUsersForArea(_selectedArea!);
              }
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
                DropdownButton<String>(
                  value: _selectedArea,
                  hint: const Text('지역 선택'),
                  items: _areaList.map((area) => DropdownMenuItem(value: area, child: Text(area))).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedArea = value);
                      _reloadUsersForArea(value);
                    }
                  },
                ),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: widget.selectedYear,
                      items: yearList.map((y) => DropdownMenuItem(value: y, child: Text('$y년'))).toList(),
                      onChanged: (value) => value != null ? widget.onYearChanged(value) : null,
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: widget.selectedMonth,
                      items: monthList.map((m) => DropdownMenuItem(value: m, child: Text('$m월'))).toList(),
                      onChanged: (value) => value != null ? widget.onMonthChanged(value) : null,
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
                      ..._localUsers.asMap().entries.expand((entry) sync* {
                        final rowIndex = entry.key;
                        final user = entry.value;
                        yield AttendanceTableRow(
                          user: user,
                          rowIndex: rowIndex,
                          selectedRow: widget.selectedRow,
                          selectedCol: widget.selectedCol,
                          cellData: widget.cellData,
                          onCellTapped: widget.onCellTapped,
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
      floatingActionButton: _buildFloatingButtons(context),
    );
  }

  Widget _buildFloatingButtons(BuildContext context) {
    final sr = widget.selectedRow;
    final rowUserId = (sr != null && sr ~/ 2 < _localUsers.length)
        ? (sr % 2 == 0 ? _localUsers[sr ~/ 2].id : '${_localUsers[sr ~/ 2].id}_out')
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (widget.menuOpen)
          Row(
            children: [
              const SizedBox(width: 12),
              FloatingActionButton(
                heroTag: 'loadJsonBtn',
                mini: true,
                onPressed: _loadAttendanceFromCloud,
                child: const Icon(Icons.download),
              ),
              const SizedBox(width: 12),
              FloatingActionButton(
                heroTag: 'saveBtn',
                mini: true,
                onPressed: () {
                  if (rowUserId != null) widget.appendText(rowUserId);
                },
                backgroundColor: Colors.green,
                child: const Icon(Icons.save),
              ),
              const SizedBox(width: 12),
              FloatingActionButton(
                heroTag: 'clearBtn',
                mini: true,
                onPressed: () {
                  if (rowUserId != null) widget.clearText(rowUserId);
                },
                backgroundColor: Colors.redAccent,
                child: const Icon(Icons.delete),
              ),
            ],
          ),
        const SizedBox(width: 12),
        FloatingActionButton(
          heroTag: 'attendanceFab',
          onPressed: widget.toggleMenu,
          backgroundColor: Colors.blueAccent,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 300),
            turns: widget.menuOpen ? 0.25 : 0.0,
            child: const Icon(Icons.more_vert),
          ),
        ),
      ],
    );
  }

  Future<void> _loadAttendanceFromCloud() async {
    try {
      final mergedData = <String, Map<int, String>>{};

      final clockInData = await downloadAttendanceJsonFromSheets(
        selectedYear: widget.selectedYear,
        selectedMonth: widget.selectedMonth,
      );

      final clockOutData = await downloadLeaveJsonFromSheets(
        selectedYear: widget.selectedYear,
        selectedMonth: widget.selectedMonth,
      );

      if (clockInData != null) mergedData.addAll(clockInData);
      if (clockOutData != null) mergedData.addAll(clockOutData);

      if (mergedData.isNotEmpty) {
        await widget.onLoadJson(mergedData);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 출근/퇴근 데이터 불러오기 성공')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📭 불러올 데이터가 없습니다')));
      }
    } catch (e) {
      await FirestoreLogger().log('출퇴근 JSON 로딩 오류: $e', level: 'error');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ 오류 발생: $e')));
    }
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
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.3)),
    );
  }
}
