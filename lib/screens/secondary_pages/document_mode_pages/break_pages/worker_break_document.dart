import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async'; // ✅ 추가
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../utils/snackbar_helper.dart';
import 'break_document_body.dart';

class WorkerBreakDocument extends StatefulWidget {
  const WorkerBreakDocument({super.key});

  @override
  State<WorkerBreakDocument> createState() => _WorkerBreakDocumentState();
}

class _WorkerBreakDocumentState extends State<WorkerBreakDocument> {
  final TextEditingController _controller = TextEditingController();
  bool _menuOpen = false;

  int? selectedRow;
  int? selectedCol;

  Set<String> selectedCells = {};

  late int selectedYear;
  late int selectedMonth;

  Map<String, Map<int, String>> cellData = {};
  List<UserModel> users = [];

  String currentArea = '';
  late StreamSubscription _userStreamSub; // ✅ 실시간 사용자 구독

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
        _subscribeToUsers(currentArea); // ✅ 실시간 스트림 시작
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
      _saveUsersToPrefs(); // 캐시에 저장
    });
  }

  @override
  void dispose() {
    _userStreamSub.cancel(); // ✅ 구독 해제
    _controller.dispose();
    super.dispose();
  }

  String get cellDataKey => 'break_cell_data_${selectedYear}_$selectedMonth';
  String get userCacheKey => 'user_list_$currentArea';

  Future<List<UserModel>> getUsersByArea(String area) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('user_accounts')
        .where('currentArea', isEqualTo: area)
        .get();

    return snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> _reloadUsers(String area) async {
    try {
      final updatedUsers = await getUsersByArea(area);

      final currentIds = users.map((u) => u.id).toSet();
      final newIds = updatedUsers.map((u) => u.id).toSet();
      final hasChanged = currentIds.length != newIds.length || !currentIds.containsAll(newIds);

      if (!mounted) return;

      if (hasChanged) {
        setState(() {
          users = updatedUsers;
        });
        await _saveUsersToPrefs();
        if (mounted) showSuccessSnackbar(context, '최신 사용자 목록으로 갱신되었습니다');
      } else {
        if (mounted) showSuccessSnackbar(context, '변경 사항 없음');
      }
    } catch (e) {
      if (mounted) showFailedSnackbar(context, '사용자 목록을 불러오지 못했습니다');
    }
  }

  Future<void> _saveUsersToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final userJsonList = users.where((u) => u.id.isNotEmpty).map((u) => u.toJson()).toList();
    await prefs.setString(userCacheKey, jsonEncode(userJsonList));
  }

  Future<void> _appendText(String rowKey) async {
    final value = _controller.text.trim();
    if (value.isEmpty || selectedRow == null || selectedCol == null) return;

    if (selectedRow! % 2 != 0) {
      if (!mounted) return;
      showFailedSnackbar(context, '휴게시간 종료는 앱에서 자동으로 처리됩니다');
      return;
    }

    setState(() {
      cellData[rowKey] ??= {};
      cellData[rowKey]![selectedCol!] = value;
      _controller.clear();
      _menuOpen = false;
    });

    await _saveCellDataToPrefs();
    if (!mounted) return;
    showSuccessSnackbar(context, '시작 시간 저장 완료');
  }

  Future<void> _clearText(String rowKey, [List<int>? colIndices]) async {
    if (colIndices != null && colIndices.isNotEmpty) {
      setState(() {
        for (final col in colIndices) {
          cellData[rowKey]?.remove(col);
        }
        _menuOpen = false;
        selectedCells.removeWhere((e) => e.startsWith('$rowKey:'));
      });
    } else if (selectedCol != null) {
      setState(() {
        cellData[rowKey]?.remove(selectedCol);
        _menuOpen = false;
        selectedCells.remove('$rowKey:${selectedCol!}');
      });
    }

    await _saveCellDataToPrefs();
    if (!mounted) return;
    showSuccessSnackbar(context, '삭제 완료');
  }

  Future<void> _saveCellDataToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stringified = cellData.map((rowKey, colMap) =>
        MapEntry(rowKey, colMap.map((colIndex, value) => MapEntry(colIndex.toString(), value))));
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
            Map<int, String>.from((colMap as Map).map((k, v) => MapEntry(int.parse(k), v))),
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

  void _onCellTapped(int rowIndex, int colIndex, String rowKey) {
    if (colIndex == 0 || colIndex == 33) return;
    final key = '$rowKey:${colIndex - 1}';
    setState(() {
      if (selectedCells.contains(key)) {
        selectedCells.remove(key);
      } else {
        selectedCells.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    currentArea = context.watch<AreaState>().currentArea;

    return BreakDocumentBody(
      controller: _controller,
      menuOpen: _menuOpen,
      selectedRow: selectedRow,
      selectedCol: selectedCol,
      selectedCells: selectedCells,
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
