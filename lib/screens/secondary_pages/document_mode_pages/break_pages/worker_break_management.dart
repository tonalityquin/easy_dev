import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../utils/snackbar_helper.dart';
import 'break_document_body.dart';

class WorkerBreakManagement extends StatefulWidget {
  const WorkerBreakManagement({super.key});

  @override
  State<WorkerBreakManagement> createState() => _WorkerBreakManagementState();
}

class _WorkerBreakManagementState extends State<WorkerBreakManagement> {
  final TextEditingController _controller = TextEditingController();
  bool _menuOpen = false;

  int? selectedRow;
  int? selectedCol;

  late int selectedYear;
  late int selectedMonth;

  Map<String, Map<int, String>> cellData = {};
  List<UserModel> users = [];

  String currentArea = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedYear = now.year;
    selectedMonth = now.month;
    _loadCellDataFromPrefs();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final area = context.read<AreaState>().currentArea;
      if (area.isNotEmpty) {
        currentArea = area;
        _loadUsersFromPrefs();
      }
    });
  }

  String get cellDataKey => 'break_cell_data_${selectedYear}_${selectedMonth}';
  String get userCacheKey => 'user_list_$currentArea';

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

      final currentIds = users.map((u) => u.id).toSet();
      final newIds = updatedUsers.map((u) => u.id).toSet();

      final hasChanged = currentIds.length != newIds.length || !currentIds.containsAll(newIds);

      if (hasChanged) {
        setState(() {
          users = updatedUsers;
        });
        await _saveUsersToPrefs();
        showSuccessSnackbar(context, '최신 사용자 목록으로 갱신되었습니다');
      } else {
        showSuccessSnackbar(context, '변경 사항 없음');
      }
    } catch (e) {
      showFailedSnackbar(context, '사용자 목록을 불러오지 못했습니다');
    }
  }

  Future<void> _saveUsersToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final userJsonList = users
        .where((u) => u.id.isNotEmpty)
        .map((u) => u.toJson())
        .toList();
    await prefs.setString(userCacheKey, jsonEncode(userJsonList));
  }

  Future<void> _loadUsersFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(userCacheKey);
    if (jsonStr != null) {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      setState(() {
        users = jsonList
            .where((map) => map['id'] != null && map['id'] is String)
            .map((map) => UserModel.fromJson(Map<String, dynamic>.from(map)))
            .toList();
      });
    } else {
      setState(() {
        users = [];
      });
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
    await prefs.setString(cellDataKey, encoded);
  }

  Future<void> _loadCellDataFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(cellDataKey);
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
    } else {
      setState(() {
        cellData = {};
      });
    }
  }

  void _onChangeYear(int year) {
    setState(() {
      selectedYear = year;
    });
    _loadCellDataFromPrefs();
  }

  void _onChangeMonth(int month) {
    setState(() {
      selectedMonth = month;
    });
    _loadCellDataFromPrefs();
  }

  @override
  Widget build(BuildContext context) {
    currentArea = context.watch<AreaState>().currentArea;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsersFromPrefs();
      _loadCellDataFromPrefs(); // ✅ 휴게시간 데이터 새로 로드
    });
    return BreakDocumentBody(
      controller: _controller,
      menuOpen: _menuOpen,
      selectedRow: selectedRow,
      selectedCol: selectedCol,
      users: users,
      cellData: cellData,
      selectedYear: selectedYear,
      selectedMonth: selectedMonth,
      onYearChanged: _onChangeYear,
      onMonthChanged: _onChangeMonth,
      onCellTapped: _onCellTapped,
      appendText: _appendText,
      clearText: _clearText,
      toggleMenu: () => setState(() => _menuOpen = !_menuOpen),
      getUsersByArea: getUsersByArea,
      reloadUsers: _reloadUsers,
    );
  }
}
