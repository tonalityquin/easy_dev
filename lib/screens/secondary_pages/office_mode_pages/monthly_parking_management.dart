import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'monthly_parking_pages/monthly_plate_bottom_sheet.dart'; // 하단 내비게이션 바

class MonthlyParkingManagement extends StatelessWidget {
  const MonthlyParkingManagement({super.key});

  void _handleIconTap(BuildContext context, int index) {
    switch (index) {
      case 0:
      // ➕ Add 버튼
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (context) => const MonthlyPlateBottomSheet(),
        );
        break;

      case 1:
      // 👤 Person 버튼
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자 관리 기능은 준비 중입니다.')),
        );
        break;

      case 2:
      // ↕️ Sort 버튼 (정렬 동작은 SecondaryMiniNavigation 내에서 처리됨)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정렬 기능은 준비 중입니다.')),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '정기 주차 관리 페이지',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: const Center(
        child: Text('Monthly parking page'),
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: const [
          Icons.add,
          Icons.person,
          Icons.sort,
        ],
        onIconTapped: (index) => _handleIconTap(context, index),
      ),
    );
  }
}
