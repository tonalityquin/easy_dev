import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../../models/user_model.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';

class WorkerAttendanceDocument extends StatefulWidget {
  const WorkerAttendanceDocument({super.key});

  @override
  State<WorkerAttendanceDocument> createState() => _WorkerDocumentState();
}

class _WorkerDocumentState extends State<WorkerAttendanceDocument> {
  final TextEditingController _controller = TextEditingController();
  bool _menuOpen = false;

  int? selectedRow;
  int? selectedCol;

  Map<String, Map<int, String>> cellData = {}; // rowName -> colIndex -> value
  List<UserModel> users = []; // ✅ 상태로 유지

  @override
  void initState() {
    super.initState();
    _loadCellDataFromPrefs();
  }

  Future<List<UserModel>> getUsersByArea(String area) async {
    final snapshot = await FirebaseFirestore.instance.collection('user_accounts').where('area', isEqualTo: area).get();

    return snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
  }

  void _onCellTapped(int rowIndex, int colIndex, String rowKey) {
    if (colIndex == 0 || colIndex == 32) return; // 이름, 마지막 칸 클릭 불가
    setState(() {
      if (selectedRow == rowIndex && selectedCol == colIndex) {
        selectedRow = null;
        selectedCol = null;
      } else {
        selectedRow = rowIndex;
        selectedCol = colIndex;
      }
    });
  }

  Future<void> _appendText(String rowKey) async {
    final value = _controller.text.trim();
    if (value.isEmpty || selectedRow == null || selectedCol == null) return;

    setState(() {
      cellData[rowKey] ??= {};
      final existing = cellData[rowKey]![selectedCol!];
      if (existing != null && existing.split('\n').length < 2) {
        cellData[rowKey]![selectedCol!] = "$existing\n$value"; // 두 번째 줄
      } else {
        cellData[rowKey]![selectedCol!] = value; // 첫 번째 줄
      }
      _controller.clear();
      _menuOpen = false;
    });

    await _saveCellDataToPrefs();
    showSuccessSnackbar(context, '저장 완료');
  }

  Future<void> _clearText(String rowKey) async {
    if (selectedRow == null || selectedCol == null) return;

    setState(() {
      cellData[rowKey]?.remove(selectedCol);
      _menuOpen = false;
    });

    await _saveCellDataToPrefs();
    showSuccessSnackbar(context, '삭제 완료');
  }

  Future<void> _saveCellDataToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stringified = cellData.map((rowKey, colMap) => MapEntry(
          rowKey,
          colMap.map((colIndex, value) => MapEntry(colIndex.toString(), value)),
        ));
    final encoded = jsonEncode(stringified);
    await prefs.setString('cell_data', encoded);
  }

  Future<void> _loadCellDataFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('cell_data');
    if (jsonStr != null) {
      final decoded = jsonDecode(jsonStr);
      setState(() {
        cellData = Map<String, Map<int, String>>.from(
          decoded.map((rowKey, colMap) => MapEntry(
                rowKey,
                Map<int, String>.from(
                  (colMap as Map).map((key, value) => MapEntry(int.parse(key), value)),
                ),
              )),
        );
      });
    }
  }

  Widget _buildCell({
    required String text,
    required bool isHeader,
    required bool isSelected,
    VoidCallback? onTap,
    double width = 60, // ← 기본값 설정
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
        child: Text(
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '근무자 출퇴근 테이블',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '추가할 문구 입력',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '직원 근무 테이블 (${selectedArea.isNotEmpty ? selectedArea : "지역 미선택"})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<UserModel>>(
              future: getUsersByArea(selectedArea),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Text('에러: ${snapshot.error}');
                }

                users = snapshot.data ?? [];

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: [
                      Row(
                        children: List.generate(33, (index) {
                          if (index == 0) return _buildCell(text: '', isHeader: true, isSelected: false);
                          if (index == 32) {
                            return _buildCell(text: '사인란', isHeader: true, isSelected: false, width: 120);
                          }
                          return _buildCell(text: '$index', isHeader: true, isSelected: false);
                        }),
                      ),
                      const SizedBox(height: 8),
                      ...users.asMap().entries.map((entry) {
                        final rowIndex = entry.key;
                        final user = entry.value;
                        final rowKey = user.id;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: List.generate(33, (colIndex) {
                              if (colIndex == 0) {
                                return _buildCell(text: user.name, isHeader: true, isSelected: false);
                              }

                              if (colIndex == 32) {
                                return _buildCell(
                                  text: '',
                                  isHeader: false,
                                  isSelected: false,
                                  onTap: null,
                                  width: 120,
                                );
                              }

                              final isSel = selectedRow == rowIndex && selectedCol == colIndex;
                              final text = cellData[rowKey]?[colIndex] ?? '';

                              return _buildCell(
                                text: text,
                                isHeader: false,
                                isSelected: isSel,
                                onTap: () => _onCellTapped(rowIndex, colIndex, rowKey),
                              );
                            }),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_menuOpen)
            Column(
              children: [
                FloatingActionButton(
                  heroTag: 'saveBtn',
                  mini: true,
                  onPressed: () {
                    if (selectedRow != null && selectedRow! < users.length) {
                      final rowKey = users[selectedRow!].id;
                      _appendText(rowKey);
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
                    if (selectedRow != null && selectedRow! < users.length) {
                      final rowKey = users[selectedRow!].id;
                      _clearText(rowKey);
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
            onPressed: () {
              setState(() {
                _menuOpen = !_menuOpen;
              });
            },
            backgroundColor: Colors.blueAccent,
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 300),
              turns: _menuOpen ? 0.25 : 0.0,
              child: const Icon(Icons.more_vert),
            ),
          ),
        ],
      ),
    );
  }
}
