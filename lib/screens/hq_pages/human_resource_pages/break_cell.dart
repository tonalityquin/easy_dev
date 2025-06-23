// 생략 없는 전체 코드
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../secondary_pages/field_mode_pages/dash_board/break_log_downloader.dart';
import '../../secondary_pages/field_mode_pages/dash_board/break_log_uploader.dart';
import 'breaks/break_table_row.dart';

class BreakCell extends StatefulWidget {
  final TextEditingController controller;
  final bool menuOpen;
  final int? selectedRow;
  final int? selectedCol;
  final Set<String> selectedCells;
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
  final Future<void> Function(Map<String, Map<int, String>> newData) onLoadJson; // ✅ 추가

  const BreakCell({
    super.key,
    required this.controller,
    required this.menuOpen,
    required this.selectedRow,
    required this.selectedCol,
    required this.selectedCells,
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
    required this.onLoadJson, // ✅ 필수
  });

  @override
  State<BreakCell> createState() => _BreakCellState();
}

class _BreakCellState extends State<BreakCell> {
  List<String> _areaList = [];
  String? _selectedArea;
  List<UserModel> _users = [];

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    final userState = context.read<UserState>();
    final userAreas = userState.user?.areas ?? [];

    if (userAreas.isEmpty) {
      debugPrint('⚠️ 사용자 소속 지역 없음');
    }

    final snapshot = await FirebaseFirestore.instance.collection('areas').get();
    final allAreas = snapshot.docs.map((doc) => doc['name'] as String).toList();
    final filteredAreas = allAreas.where((area) => userAreas.contains(area)).toList();

    setState(() {
      _areaList = filteredAreas;
      if (filteredAreas.isNotEmpty) {
        _selectedArea = filteredAreas.first;
        _reloadUsersForArea(_selectedArea!);
      }
    });
  }

  Future<void> _reloadUsersForArea(String area) async {
    final users = await widget.getUsersByArea(area);
    setState(() {
      _users = users;
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
        title: const Text('근무자 휴게시간 테이블', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          if (index == 1) return _buildHeaderCell('시작/종료');
                          if (index == 33) return _buildHeaderCell('사인란', width: 120);
                          return _buildHeaderCell('${index - 1}');
                        }),
                      ),
                      const SizedBox(height: 8),
                      ..._users.asMap().entries.expand((entry) {
                        final user = entry.value;
                        final rowKey = user.id;
                        return [
                          BreakTableRow(
                            user: user,
                            label: '시작',
                            rowIndex: entry.key * 2,
                            rowKey: rowKey,
                            selectedCells: widget.selectedCells,
                            cellData: widget.cellData,
                            onCellTapped: widget.onCellTapped,
                          ),
                          BreakTableRow(
                            user: user,
                            label: '종료',
                            rowIndex: entry.key * 2 + 1,
                            rowKey: rowKey,
                            selectedCells: widget.selectedCells,
                            cellData: widget.cellData,
                            onCellTapped: widget.onCellTapped,
                            isStart: false,
                          ),
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
      floatingActionButton: Row(
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
                  onPressed: () async {
                    final areaState = context.read<AreaState>();
                    final division = areaState.currentDivision;

                    final Map<String, Map<int, String>> merged = {};

                    for (final user in _users) {
                      final userId = user.id;

                      // ✅ 업로드 경로와 동일하게 englishSelectedAreaName 사용
                      final url = BreakLogUploader.getDownloadPath(
                        division: division,
                        area: user.englishSelectedAreaName ?? '',
                        userId: userId,
                        dateTime: DateTime(widget.selectedYear, widget.selectedMonth),
                      );

                      final data = await downloadBreakJsonFromGcs(
                        publicUrl: url,
                        selectedYear: widget.selectedYear,
                        selectedMonth: widget.selectedMonth,
                      );

                      if (data != null && data.isNotEmpty) {
                        merged.addAll(data);
                      }
                    }

                    if (merged.isNotEmpty) {
                      await widget.onLoadJson(merged); // ✅ 실제 병합 데이터 전달
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('✅ 휴게시간 데이터 불러오기 완료')),
                        );
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('📭 불러올 휴게시간 데이터가 없습니다')),
                        );
                      }
                    }
                  },
                  backgroundColor: Colors.orange,
                  child: const Icon(Icons.cloud_download),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  heroTag: 'saveBtn',
                  mini: true,
                  onPressed: () {
                    final sr = widget.selectedRow;
                    if (sr != null && sr ~/ 2 < _users.length) {
                      final rowKey = _users[sr ~/ 2].id;
                      widget.appendText(rowKey);
                    }
                  },
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.save),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  heroTag: 'clearBtn',
                  mini: true,
                  onPressed: () {
                    final Map<String, List<int>> rows = {};
                    for (final cell in widget.selectedCells) {
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
                      widget.clearText(entry.key, entry.value);
                    }
                  },
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.delete),
                ),
              ],
            ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'menuFab',
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
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}
