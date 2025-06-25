import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../../states/area/spot_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../attendance_cell.dart';

class AttendanceUi extends StatefulWidget {
  const AttendanceUi({super.key});

  @override
  State<AttendanceUi> createState() => _AttendanceUiState();
}

class _AttendanceUiState extends State<AttendanceUi> {
  final TextEditingController _controller = TextEditingController();
  bool _menuOpen = false;

  int? selectedRow;
  int? selectedCol;

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
      final area = context.read<AreaState>().selectedArea; // ✅ 수정됨
      if (area.isNotEmpty) {
        selectedArea = area;
        _subscribeToUsers(selectedArea); // ✅ 수정됨
      }
    });
  }

  void _subscribeToUsers(String area) {
    _userStreamSub = FirebaseFirestore.instance
        .collection('user_accounts')
        .where('selectedArea', isEqualTo: area) // ✅ selectedArea 기준
        .snapshots()
        .listen((snapshot) {
      final updatedUsers = snapshot.docs
          .map((doc) => UserModel.fromMap(doc.id, doc.data()))
          .toList();
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

    return snapshot.docs
        .map((doc) => UserModel.fromMap(doc.id, doc.data()))
        .toList();
  }

  Future<void> _reloadUsers(String area) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('user_accounts')
          .where('selectedArea', isEqualTo: area) // ✅ selectedArea 기준
          .get();

      final updatedUsers = snapshot.docs
          .map((doc) => UserModel.fromMap(doc.id, doc.data()))
          .toList();

      final currentIds = users.map((u) => u.id).toSet();
      final newIds = updatedUsers.map((u) => u.id).toSet();
      final hasChanged =
          currentIds.length != newIds.length || !currentIds.containsAll(newIds);

      if (hasChanged) {
        setState(() {
          users = updatedUsers;
        });

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) showSuccessSnackbar(context, '삭제 완료');
    });
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

  Future<void> _mergeJsonData(Map<String, Map<int, String>> newData) async {
    setState(() {
      for (final entry in newData.entries) {
        cellData[entry.key] ??= {};
        entry.value.forEach((day, time) {
          cellData[entry.key]![day] = time;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        showSuccessSnackbar(context, '출퇴근 기록 불러오기 완료');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    selectedArea = context.watch<AreaState>().selectedArea; // ✅ 수정됨

    return AttendanceCell(
      controller: _controller,
      menuOpen: _menuOpen,
      selectedRow: selectedRow,
      selectedCol: selectedCol,
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
      onLoadJson: _mergeJsonData,
    );
  }
}
