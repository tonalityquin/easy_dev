import 'package:flutter/material.dart';
import '../../../widgets/navigation/minor_top_navigation.dart';
import '../type_package/common_widgets/dashboard_bottom_sheet/minor_hq_dash_board_page.dart';

class MinorDashBoard extends StatelessWidget {
  const MinorDashBoard({super.key});

  static const String screenTag = 'MinorHeadQuarter'; // 화면 식별 태그

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async => false, // 뒤로가기 차단(기존 동작 유지)
      child: Scaffold(
        appBar: AppBar(
          title: const MinorTopNavigation(),
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1),
          ),

          // ⬇️ 좌측 상단(11시 방향)에 screenTag 텍스트 고정
          flexibleSpace: SafeArea(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Semantics(
                    label: 'screen_tag: MinorDashBoard C',
                    child: Text(
                      screenTag,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ) ??
                          TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: const MinorHqDashBoardPage(), // 단일 콘텐츠
      ),
    );
  }
}
