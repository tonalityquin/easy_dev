import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../../../models/user_model.dart';
import '../../../../utils/snackbar_helper.dart';
import 'attendance_document_body.dart';

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

  Map<String, Map<int, String>> cellData = {};
  List<UserModel> users = [];

  @override
  void initState() {
    super.initState();
    _loadCellDataFromPrefs();
  }

  Future<List<UserModel>> getUsersByArea(String area) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('user_accounts')
        .where('area', isEqualTo: area)
        .get();
    return snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> _reloadUsers(String area) async {
    try {
      final updatedUsers = await getUsersByArea(area);
      setState(() {
        users = updatedUsers;
      });
      showSuccessSnackbar(context, '최신 사용자 목록으로 갱신되었습니다');
    } catch (e) {
      showFailedSnackbar(context, '사용자 목록을 불러오지 못했습니다');
    }
  }

  void _onCellTapped(int rowIndex, int colIndex, String rowKey) {
    if (colIndex == 0 || colIndex == 32) return;
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
        cellData[rowKey]![selectedCol!] = "$existing\n$value";
      } else {
        cellData[rowKey]![selectedCol!] = value;
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

  @override
  Widget build(BuildContext context) {
    return AttendanceDocumentBody(
      controller: _controller,
      menuOpen: _menuOpen,
      selectedRow: selectedRow,
      selectedCol: selectedCol,
      users: users,
      cellData: cellData,
      onCellTapped: _onCellTapped,
      appendText: _appendText,
      clearText: _clearText,
      toggleMenu: () => setState(() => _menuOpen = !_menuOpen),
      getUsersByArea: getUsersByArea,
      reloadUsers: _reloadUsers, // ✅ 수동 새로고침 전달
    );
  }
}
