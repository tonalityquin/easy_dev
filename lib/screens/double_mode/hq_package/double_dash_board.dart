import 'package:flutter/material.dart';
import '../../../widgets/navigation/double_top_navigation.dart';
import '../type_package/common_widgets/dashboard_bottom_sheet/double_hq_dash_board_page.dart';

class DoubleDashBoard extends StatelessWidget {
  const DoubleDashBoard({super.key});

  static const String screenTag = 'DoubleHeadQuarter'; // 화면 식별 태그

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // 뒤로가기 차단(기존 동작 유지)
      child: Scaffold(
        appBar: AppBar(
          title: const DoubleTopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,

          // ⬇️ 좌측 상단(11시 방향)에 HeadQuarter 텍스트 고정
          flexibleSpace: SafeArea(
            child: IgnorePointer(
              // 탭 이벤트 간섭 방지
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Semantics(
                    // 접근성/로그 수집에 유용
                    label: 'screen_tag: DoubleDashBoard C',
                    child: Text(
                      screenTag,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ) ??
                          const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: const DoubleHqDashBoardPage(), // 단일 콘텐츠
      ),
    );
  }
}
