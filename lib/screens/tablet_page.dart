import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/area/area_state.dart';

// 🔗 왼쪽 패널: 로그아웃/컨트롤 UI
import 'tablet_pages/tablet_page_controller.dart';
import 'tablet_pages/widgets/tablet_plate_search_bottom_sheet.dart';

// 오른쪽 패널: 번호판 검색 바텀시트 임베드

class TabletPage extends StatelessWidget {
  const TabletPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Area 변경 시 우측 패널도 반응하도록 select 사용 (null 방지)
    final area = context.select<AreaState, String?>((s) => s.currentArea) ?? '';

    return Scaffold(
      backgroundColor: Colors.white,

      // ✅ 기존 본문(2열) 그대로 유지
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ⬅️ 왼쪽 패널: TabletPageController 사용(로그아웃 등)
            const Expanded(
              child: ColoredBox(
                color: Color(0xFFF7F8FA),
                child: Padding(
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
                  // 🔑 area가 바뀌면 우측 Navigator 자체가 재생성되도록 Key 부여
                  key: ValueKey('right-pane-$area'),
                  child: TabletPlateSearchBottomSheet(
                    // 🔑 초기 라우트(검색 시트)도 area 기준으로 재생성
                    key: ValueKey('sps-$area'),
                    onSearch: (_) {},
                    area: area,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // ✅ TypePage와 동일한 위치/로직으로 하단에 펠리컨 이미지를 배치
      // [채팅/대시보드] → [네비게이션 바] → [펠리컨] 구조에서
      // 이 페이지에는 상단 두 요소가 없으므로 '펠리컨'만 Column 마지막 요소로 둡니다.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // ⛔️ children: const [...]  → ✅ children: [...]
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 48,
                // Image.asset 은 const 아님
                child: Image.asset('assets/images/pelican.png'),
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

  const _RightPaneNavigator({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (RouteSettings settings) {
        // 최초 한 번 생성된 라우트가 고정되는 특성 때문에,
        // 상위에서 key를 활용해 이 위젯 자체를 재생성하도록 처리함.
        return MaterialPageRoute(builder: (_) => child);
      },
    );
  }
}
