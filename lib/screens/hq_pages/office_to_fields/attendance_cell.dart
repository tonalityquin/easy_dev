import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../models/user_model.dart';
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
    final snapshot = await FirebaseFirestore.instance.collection('areas').get();
    final areas = snapshot.docs.map((doc) => doc['name'] as String).toList();
    setState(() {
      _areaList = areas;
      if (areas.isNotEmpty) {
        _selectedArea = areas.first;
        _reloadUsersForArea(_selectedArea!);
      }
    });
  }

  Future<void> _reloadUsersForArea(String area) async {
    final users = await widget.getUsersByArea(area);
    setState(() {
      _localUsers = users;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  items: _areaList.map((area) {
                    return DropdownMenuItem(
                      value: area,
                      child: Text(area),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedArea = value;
                      });
                      _reloadUsersForArea(value);
                    }
                  },
                ),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: widget.selectedYear,
                      items: yearList
                          .map((y) => DropdownMenuItem(value: y, child: Text('$y년')))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) widget.onYearChanged(value);
                      },
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: widget.selectedMonth,
                      items: monthList
                          .map((m) => DropdownMenuItem(value: m, child: Text('$m월')))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) widget.onMonthChanged(value);
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.menuOpen)
            Column(
              children: [
                FloatingActionButton(
                  heroTag: 'saveBtn',
                  mini: true,
                  onPressed: () {
                    final sr = widget.selectedRow;
                    if (sr != null && sr ~/ 2 < _localUsers.length) {
                      final userId = _localUsers[sr ~/ 2].id;
                      final fullKey = sr % 2 == 0 ? userId : '${userId}_out';
                      widget.appendText(fullKey);
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
                    final sr = widget.selectedRow;
                    if (sr != null && sr ~/ 2 < _localUsers.length) {
                      final userId = _localUsers[sr ~/ 2].id;
                      final fullKey = sr % 2 == 0 ? userId : '${userId}_out';
                      widget.clearText(fullKey);
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
            onPressed: widget.toggleMenu,
            backgroundColor: Colors.blueAccent,
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 300),
              turns: widget.menuOpen ? 0.25 : 0.0,
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
