// lib/screens/simple_package/simple_inside_package/sections/simple_inside_report_bottom_sheet.dart

import 'package:flutter/material.dart';

import 'sections/commute_inside_report_form_page.dart';

/// "업무 보고" 버튼에서 사용하는 전체 화면 바텀 시트 헬퍼 함수.
///
/// SelectorHubsPage의 DevLoginBottomSheet 패턴과 동일하게 구성.
void showCommuteInsideReportFullScreenBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const FractionallySizedBox(
      heightFactor: 1,
      child: CommuteInsideReportFormPage(),
    ),
  );
}
