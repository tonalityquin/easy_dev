import 'package:flutter/material.dart';
import '../offline_navigation/offline_top_navigation.dart';
import '../offline_type_package/common_widgets/dashboard_bottom_sheet/offline_hq_dash_board_page.dart';

class OfflineDashBoard extends StatelessWidget {
  const OfflineDashBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // 뒤로가기 차단(기존 동작 유지)
      child: Scaffold(
        appBar: AppBar(
          title: const OfflineTopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: const OfflineHqDashBoardPage(), // 단일 콘텐츠
      ),
    );
  }
}
