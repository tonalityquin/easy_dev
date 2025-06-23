import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../break_cell.dart';
import '../../../secondary_pages/field_mode_pages/dash_board/break_log_uploader.dart';
import '../../../secondary_pages/field_mode_pages/dash_board/break_log_downloader.dart'; // ✅ 추가

class BreakUi extends StatefulWidget {
  const BreakUi({super.key});

  @override
  State<BreakUi> createState() => _BreakUiState();
}

class _BreakUiState extends State<BreakUi> {
  final TextEditingController _controller = TextEditingController();
  bool _menuOpen = false;

  int? selectedRow;
  int? selectedCol;
  Set<String> selectedCells = {};

  late int selectedYear;
  late int selectedMonth;

  Map<String, Map<int, String>> cellData = {};
  List<UserModel> users = [];

  String selectedArea = '';
  late StreamSubscription _userStreamSub;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedYear = now.year;
    selectedMonth = now.month;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final area = context.read<AreaState>().selectedArea; // ✅ selectedArea 참조
      if (area.isNotEmpty) {
        selectedArea = area;
        _subscribeToUsers(selectedArea); // ✅
      }
    });
  }

  void _subscribeToUsers(String area) {
    _userStreamSub = FirebaseFirestore.instance
        .collection('user_accounts')
        .where('selectedArea', isEqualTo: area) // ✅ selectedArea 기준
        .snapshots()
        .listen((snapshot) {
      final updatedUsers = snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
      setState(() {
        users = updatedUsers;
      });
    });
  }

  @override
  void dispose() {
    _userStreamSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<List<UserModel>> getUsersByArea(String area) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('user_accounts')
        .where('selectedArea', isEqualTo: area) // ✅ selectedArea 기준
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
        showSuccessSnackbar(context, '최신 사용자 목록으로 갱신되었습니다');
      } else {
        showSuccessSnackbar(context, '변경 사항 없음');
      }
    } catch (e) {
      if (mounted) showFailedSnackbar(context, '사용자 목록을 불러오지 못했습니다');
    }
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

    showSuccessSnackbar(context, '삭제 완료');
  }

  void _onChangeYear(int year) {
    setState(() {
      selectedYear = year;
    });
  }

  void _onChangeMonth(int month) {
    setState(() {
      selectedMonth = month;
    });
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

  Future<void> _onLoadJson() async {
    try {
      final areaState = context.read<AreaState>();
      final division = areaState.currentDivision;

      final Map<String, Map<int, String>> merged = {};

      for (final user in users) {
        final userId = user.id;

        final url = BreakLogUploader.getDownloadPath(
          division: division,
          area: user.englishSelectedAreaName ?? '', // ✅ 영어 이름 참조
          userId: userId,
        );

        final jsonData = await downloadBreakJsonFromGcs(
          publicUrl: url,
          selectedYear: selectedYear,
          selectedMonth: selectedMonth,
        );

        if (jsonData != null && jsonData.isNotEmpty) {
          merged.addAll(jsonData);
        }
      }

      if (merged.isEmpty) {
        showFailedSnackbar(context, '❌ 휴게시간 데이터 없음');
      } else {
        setState(() {
          cellData = merged;
        });
        showSuccessSnackbar(context, '✅ 휴게시간 데이터 불러오기 완료');
      }
    } catch (e) {
      showFailedSnackbar(context, '❌ 휴게시간 데이터 로딩 중 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    selectedArea = context.watch<AreaState>().selectedArea; // ✅ selectedArea 참조

    return BreakCell(
      controller: _controller,
      menuOpen: _menuOpen,
      selectedRow: selectedRow,
      selectedCol: selectedCol,
      selectedCells: selectedCells,
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
      onLoadJson: (_) => _onLoadJson(),
    );
  }
}
