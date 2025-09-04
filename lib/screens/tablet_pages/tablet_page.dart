import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 현재 선택된 에리어 값을 얻기 위해 (필요시 경로 조정)
import '../../states/area/area_state.dart';

// 🔗 왼쪽 패널: 로그아웃/컨트롤 UI
import 'tablet_page_controller.dart';

// 오른쪽 패널: 번호판 검색 바텀시트 임베드
import '../type_pages/parking_completed_pages/widgets/signature_plate_search_bottom_sheet/signature_plate_search_bottom_sheet.dart';

class TabletPage extends StatelessWidget {
  const TabletPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Area 변경 시 우측 패널도 반응하도록 select 사용 (null 방지)
    final area = context.select<AreaState, String?>((s) => s.currentArea) ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ⬅️ 왼쪽 패널: TabletPageController 사용(로그아웃 등)
            Expanded(
              child: Container(
                color: const Color(0xFFF7F8FA),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: TabletPageController(),
                ),
              ),
            ),

            const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFEBEDF0)),

            // ➡️ 오른쪽 패널: SignaturePlateSearchBottomSheet 임베드
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                ),
                child: _RightPaneNavigator(
                  child: SignaturePlateSearchBottomSheet(
                    onSearch: (_) {},
                    area: area,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 우측 패널에 중첩 네비게이터를 두어, 내부 위젯에서 Navigator.pop(context) 호출 시
/// 전체 라우트가 아닌 **우측 패널** 내에서만 pop 되도록 합니다.
class _RightPaneNavigator extends StatelessWidget {
  final Widget child;

  const _RightPaneNavigator({required this.child});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute(builder: (_) => child);
      },
    );
  }
}
