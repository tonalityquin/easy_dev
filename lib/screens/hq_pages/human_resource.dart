import 'dart:async'; // ✅ 추가됨
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../widgets/navigation/navigation_hq_mini.dart';
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

  List<UserModel> _users = [];

  StreamSubscription? _userSubscription; // ✅ Firestore 구독 저장용

  @override
  void initState() {
    super.initState();

    final area = context.read<AreaState>().selectedArea;
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

  Future<List<UserModel>> _getUsersByArea(String area) async {
    final snapshot =
        await FirebaseFirestore.instance.collection('user_accounts').where('selectedArea', isEqualTo: area).get();
    return snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> _reloadUsers(String area) async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('user_accounts').where('selectedArea', isEqualTo: area).get();

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
            ? AttendanceCell()
            : _selectedIndex == 1
                ? const TodayField()
                : BreakCell(),
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
