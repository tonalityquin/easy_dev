import 'package:flutter/material.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../type_package/common_widgets/dashboard_bottom_sheet/hq_dash_board_page.dart';

class DashBoard extends StatelessWidget {
  const DashBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // 뒤로가기 차단(기존 동작 유지)
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: const HqDashBoardPage(), // 단일 콘텐츠
      ),
    );
  }
}
