// lib/screens/secondary_page.dart
//
// ModeStatus 제거 + 상단 TabBar/TabBarView 전환 버전(심플 타이틀, 칩 없음).
// - 상단 AppBar: 고정 텍스트 타이틀 + TabBar
// - 탭 계산은 전역 provider(stateProviders)에서 수행하여 SecondaryState를 주입
// - 이 파일은 SecondaryState만 소비(Consumer)함
//
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/secondary/secondary_state.dart';

class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔁 전역에서 이미 SecondaryState가 주입됨: 바로 스캐폴드로 렌더
    return const _SecondaryScaffold(key: ValueKey('secondary_scaffold'));
  }
}

class _SecondaryScaffold extends StatelessWidget {
  const _SecondaryScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SecondaryState>(
      builder: (context, state, _) {
        // DefaultTabController를 pages/selectedIndex 기준으로 교체되도록 key 부여
        final controllerKey = ValueKey('tabs-${state.pages.length}-${state.selectedIndex}');

        // 현재 인덱스 방어
        final safeIndex = state.selectedIndex.clamp(
          0,
          (state.pages.length - 1).clamp(0, 999),
        );

        return DefaultTabController(
          key: controllerKey,
          length: state.pages.length,
          initialIndex: safeIndex,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 1,
              centerTitle: true,
              // 심플 타이틀
              title: const Text(
                '보조 페이지',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              bottom: TabBar(
                isScrollable: true,
                onTap: state.onItemTapped, // 탭 탭 → 상태 반영
                tabs: state.pages.map((p) => Tab(text: p.title, icon: p.icon)).toList(),
              ),
            ),
            body: Stack(
              children: [
                TabBarView(
                  // 스와이프 시에도 인덱스 연동 필요 → _TabSync로 처리
                  children: state.pages
                      .map(
                        (pageInfo) => _TabSync(
                          index: state.pages.indexOf(pageInfo),
                          onPageBecameVisible: (i) {
                            if (state.selectedIndex != i) {
                              state.onItemTapped(i);
                            }
                          },
                          child: KeyedSubtree(
                            key: PageStorageKey<String>('secondary_${pageInfo.title}'),
                            child: pageInfo.page,
                          ),
                        ),
                      )
                      .toList(),
                ),
                // 로딩 오버레이
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !state.isLoading,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child:
                          state.isLoading ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// TabBarView 페이지 전환 시 현재 보이는 인덱스를 SecondaryState와 동기화하기 위한 헬퍼
class _TabSync extends StatefulWidget {
  final int index;
  final Widget child;
  final ValueChanged<int> onPageBecameVisible;

  const _TabSync({
    required this.index,
    required this.child,
    required this.onPageBecameVisible,
  });

  @override
  State<_TabSync> createState() => _TabSyncState();
}

class _TabSyncState extends State<_TabSync> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 탭 상태 유지

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 탭 전환 스와이프 감지 → 보이게 될 때 콜백
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // PageView 내부 스크롤이 완료되어 이 위젯이 "완전히 보이는" 시점 감지
        if (n is ScrollEndNotification) {
          final controller = DefaultTabController.of(context);
          if (controller.index == widget.index) {
            widget.onPageBecameVisible(widget.index);
          }
        }
        return false;
      },
      child: widget.child,
    );
  }
}
