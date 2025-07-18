import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../widgets/navigation/navigation_hq_mini.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'human_resource_pages/today_field.dart';
import 'human_resource_pages/break_cell.dart';
import 'human_resource_pages/attendance_cell.dart';
import 'human_resource_pages/google_drive.dart';

class HumanResource extends StatefulWidget {
  const HumanResource({super.key});

  @override
  State<HumanResource> createState() => _HumanResourceState();
}

class _HumanResourceState extends State<HumanResource> {
  int _selectedIndex = 0;
  String? _selectedArea;
  bool _isLoading = true;
  StreamSubscription? _userSubscription;

  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSelectedArea();
  }

  Future<void> _loadSelectedArea() async {
    final prefs = await SharedPreferences.getInstance();
    final area = prefs.getString('selectedArea') ?? 'belivus'; // 기본값 설정
    _subscribeToUsers(area);
    setState(() {
      _selectedArea = area;
      _isLoading = false;
    });
  }

  void _subscribeToUsers(String area) {
    _userSubscription = FirebaseFirestore.instance
        .collection('user_accounts')
        .where('selectedArea', isEqualTo: area)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
    });
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _selectedArea == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
            ? AttendanceCell(selectedArea: _selectedArea!)
            : _selectedIndex == 1
            ? const TodayField()
            : _selectedIndex == 2
            ? GoogleDrive(selectedArea: _selectedArea!) // ✅ 안전한 selectedArea 전달
            : BreakCell(selectedArea: _selectedArea!),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.how_to_reg,
            Icons.today,
            Icons.cloud,
            Icons.self_improvement,
          ],
          labels: const [
            'ATT',
            'Today Field',
            'Drive',
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
