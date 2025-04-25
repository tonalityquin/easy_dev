import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async'; // ← 추가
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../utils/snackbar_helper.dart';
import 'attendance_document_body.dart';

class WorkerAttendanceDocument extends StatefulWidget {
  const WorkerAttendanceDocument({super.key});

  @override
  State<WorkerAttendanceDocument> createState() => _WorkerAttendanceDocumentState();
}

class _WorkerAttendanceDocumentState extends State<WorkerAttendanceDocument> {
  final TextEditingController _controller = TextEditingController();
  bool _menuOpen = false;

  int? selectedRow;
  int? selectedCol;

  late int selectedYear;
  late int selectedMonth;

  Map<String, Map<int, String>> cellData = {};
  List<UserModel> users = [];

  String currentArea = '';
  late StreamSubscription _userStreamSub; // 🔁 사용자 실시간 구독

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
        _subscribeToUsers(currentArea); // ✅ 실시간 구독
      }
    });
  }

  void _subscribeToUsers(String area) {
    _userStreamSub = FirebaseFirestore.instance
        .collection('user_accounts')
        .where('currentArea', isEqualTo: area)
        .snapshots()
        .listen((snapshot) {
      final updatedUsers = snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
      setState(() {
        users = updatedUsers;
      });
      _saveUsersToPrefs();
    });
  }

  @override
  void dispose() {
    _userStreamSub.cancel(); // ✅ 메모리 누수 방지
    _controller.dispose();
    super.dispose();
  }

  String get cellDataKey => 'attendance_cell_data_${selectedYear}_$selectedMonth';

  String get userCacheKey => 'user_list_$currentArea';

  Future<void> _saveUsersToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final userJsonList = users.where((u) => u.id.isNotEmpty).map((u) => u.toJson()).toList();
    await prefs.setString(userCacheKey, jsonEncode(userJsonList));
  }

  Future<List<UserModel>> getUsersByArea(String area) async {
    final snapshot =
        await FirebaseFirestore.instance.collection('user_accounts').where('currentArea', isEqualTo: area).get();

    return snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> _reloadUsers(String area) async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('user_accounts').where('currentArea', isEqualTo: area).get();
      final updatedUsers = snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();

      final currentIds = users.map((u) => u.id).toSet();
      final newIds = updatedUsers.map((u) => u.id).toSet();
      final hasChanged = currentIds.length != newIds.length || !currentIds.containsAll(newIds);

      if (hasChanged) {
        setState(() {
          users = updatedUsers;
        });
        await _saveUsersToPrefs();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            showSuccessSnackbar(context, '최신 사용자 목록으로 갱신되었습니다');
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            showSuccessSnackbar(context, '변경 사항 없음');
          }
        });
      }
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          showFailedSnackbar(context, '사용자 목록을 불러오지 못했습니다');
        }
      });
    }
  }

  Future<void> _appendText(String rowKey) async {
    final value = _controller.text.trim();
    if (value.isEmpty || selectedRow == null || selectedCol == null) return;

    setState(() {
      cellData[rowKey] ??= {};
      cellData[rowKey]![selectedCol!] = value;
      _controller.clear();
      _menuOpen = false;
    });

    await _saveCellDataToPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) showSuccessSnackbar(context, '저장 완료');
    });
  }

  Future<void> _clearText(String rowKey) async {
    if (selectedRow == null || selectedCol == null) return;

    setState(() {
      cellData[rowKey]?.remove(selectedCol);
      _menuOpen = false;
    });

    await _saveCellDataToPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) showSuccessSnackbar(context, '삭제 완료');
    });
  }

  Future<void> _saveCellDataToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stringified = cellData.map(
      (rowKey, colMap) => MapEntry(rowKey, colMap.map((colIndex, value) => MapEntry(colIndex.toString(), value))),
    );
    final encoded = jsonEncode(stringified);
    await prefs.setString(cellDataKey, encoded);
  }

  Future<void> _loadCellDataFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(cellDataKey);

    if (jsonStr != null) {
      final decoded = jsonDecode(jsonStr);
      setState(() {
        cellData = {};

        decoded.forEach((rowKey, colMap) {
          final parsedMap = Map<int, String>.from(
            (colMap as Map).map((k, v) => MapEntry(int.parse(k.toString()), v.toString())),
          );

          if (!rowKey.endsWith('_out')) {
            for (final entry in parsedMap.entries) {
              final day = entry.key;
              final value = entry.value;
              final parts = value.split('\n');

              if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
                cellData[rowKey] ??= {};
                cellData[rowKey]![day] = parts[0].trim();
              }

              if (parts.length > 1 && parts[1].trim().isNotEmpty) {
                final outKey = '${rowKey}_out';
                cellData[outKey] ??= {};
                cellData[outKey]![day] = parts[1].trim();
              }
            }
          } else {
            cellData[rowKey] = parsedMap;
          }
        });
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

  @override
  Widget build(BuildContext context) {
    currentArea = context.watch<AreaState>().currentArea;

    return AttendanceDocumentBody(
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
      getUsersByArea: (area) => getUsersByArea(area),
      reloadUsers: _reloadUsers,
    );
  }
}
