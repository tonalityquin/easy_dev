import 'dart:async'; // ✅ 추가됨
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../../../models/user_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../utils/snackbar_helper.dart';
import 'human_resource_pages/today_field.dart';
import 'human_resource_pages/break_cell.dart';
import 'human_resource_pages/attendance_cell.dart';

class HumanResource extends StatefulWidget {
  const HumanResource({super.key});

  @override
  State<HumanResource> createState() => _HumanResourceState();
}

class _HumanResourceState extends State<HumanResource> {
  int _selectedIndex = 0;

  final TextEditingController _controller = TextEditingController();
  bool _menuOpen = false;
  int? _selectedRow;
  int? _selectedCol;
  Set<String> _selectedCells = {};
  late int _selectedYear;
  late int _selectedMonth;
  Map<String, Map<int, String>> _cellData = {};
  List<UserModel> _users = [];

  StreamSubscription? _userSubscription; // ✅ Firestore 구독 저장용

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;

    final area = context.read<AreaState>().currentArea;
    if (area.isNotEmpty) {
      _subscribeToUsers(area);
    }
  }

  void _subscribeToUsers(String area) {
    _userSubscription = FirebaseFirestore.instance
        .collection('user_accounts')
        .where('selectedArea', isEqualTo: area)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final updatedUsers = snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
      setState(() {
        _users = updatedUsers;
      });
    });
  }

  Future<void> _mergeJsonData(Map<String, Map<int, String>> newData) async {
    setState(() {
      for (final entry in newData.entries) {
        _cellData[entry.key] = entry.value;
      }
    });
    showSuccessSnackbar(context, '출근 기록 불러오기 완료');
  }

  Future<List<UserModel>> _getUsersByArea(String area) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('user_accounts')
        .where('selectedArea', isEqualTo: area)
        .get();
    return snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> _reloadUsers(String area) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('user_accounts')
          .where('selectedArea', isEqualTo: area)
          .get();

      final updatedUsers = snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();

      final currentIds = _users.map((u) => u.id).toSet();
      final newIds = updatedUsers.map((u) => u.id).toSet();
      final hasChanged = currentIds.length != newIds.length || !currentIds.containsAll(newIds);

      if (hasChanged) {
        if (!mounted) return;
        setState(() {
          _users = updatedUsers;
        });
        showSuccessSnackbar(context, '최신 사용자 목록으로 갱신되었습니다');
      } else {
        if (!mounted) return;
        showSuccessSnackbar(context, '변경 사항 없음');
      }
    } catch (_) {
      if (!mounted) return;
      showFailedSnackbar(context, '사용자 목록을 불러오지 못했습니다');
    }
  }

  Future<void> _appendText(String rowKey) async {
    final value = _controller.text.trim();
    if (value.isEmpty || _selectedRow == null || _selectedCol == null) return;

    setState(() {
      _cellData[rowKey] ??= {};
      _cellData[rowKey]![_selectedCol!] = value;
      _controller.clear();
      _menuOpen = false;
    });
    showSuccessSnackbar(context, '저장 완료');
  }

  Future<void> _clearText(String rowKey, [List<int>? colIndices]) async {
    if (colIndices != null && colIndices.isNotEmpty) {
      setState(() {
        for (final col in colIndices) {
          _cellData[rowKey]?.remove(col);
        }
        _menuOpen = false;
        _selectedCells.removeWhere((e) => e.startsWith('$rowKey:'));
      });
    } else if (_selectedCol != null) {
      setState(() {
        _cellData[rowKey]?.remove(_selectedCol);
        _menuOpen = false;
        _selectedCells.remove('$rowKey:$_selectedCol');
      });
    }
    showSuccessSnackbar(context, '삭제 완료');
  }

  void _onCellTapped(int rowIndex, int colIndex, String rowKey) {
    if (colIndex == 0 || colIndex == 33) return;
    final key = '$rowKey:${colIndex - 1}';
    setState(() {
      if (_selectedCells.contains(key)) {
        _selectedCells.remove(key);
      } else {
        _selectedCells.add(key);
      }
    });
  }

  void _onChangeYear(int year) {
    setState(() {
      _selectedYear = year;
    });
  }

  void _onChangeMonth(int month) {
    setState(() {
      _selectedMonth = month;
    });
  }

  @override
  void dispose() {
    _userSubscription?.cancel(); // ✅ 리소스 해제
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _selectedIndex == 0
            ? AttendanceCell(
          controller: _controller,
          menuOpen: _menuOpen,
          selectedRow: _selectedRow,
          selectedCol: _selectedCol,
          cellData: _cellData,
          selectedYear: _selectedYear,
          selectedMonth: _selectedMonth,
          onYearChanged: _onChangeYear,
          onMonthChanged: _onChangeMonth,
          onCellTapped: _onCellTapped,
          appendText: _appendText,
          clearText: _clearText,
          toggleMenu: () => setState(() => _menuOpen = !_menuOpen),
          getUsersByArea: _getUsersByArea,
          reloadUsers: _reloadUsers,
          onLoadJson: _mergeJsonData, // ✅ 출근/퇴근 병합 데이터 적용
        )
            : _selectedIndex == 1
            ? const TodayField()
            : BreakCell(
          controller: _controller,
          menuOpen: _menuOpen,
          selectedRow: _selectedRow,
          selectedCol: _selectedCol,
          selectedCells: _selectedCells,
          cellData: _cellData,
          selectedYear: _selectedYear,
          selectedMonth: _selectedMonth,
          onYearChanged: _onChangeYear,
          onMonthChanged: _onChangeMonth,
          onCellTapped: _onCellTapped,
          appendText: _appendText,
          clearText: _clearText,
          toggleMenu: () => setState(() => _menuOpen = !_menuOpen),
          getUsersByArea: _getUsersByArea,
          reloadUsers: _reloadUsers,
          onLoadJson: _mergeJsonData,
        ),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.how_to_reg,
            Icons.today,
            Icons.self_improvement,
          ],
          labels: const [
            'ATT',
            'Today Field',
            'Brk',
          ],
          onIconTapped: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }
}
