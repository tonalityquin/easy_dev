// lib/screens/secondary_page.dart
//
// 요구사항: "한 번에 두 개의 탭만 보이고, 가로로 스와이프할 때마다 다른 두 개의 탭"이 보이도록.
// 구현 요약:
// - 상단 AppBar는 고정 타이틀만 표시.
// - 본문은 PageView(=청크 페이저)로, 탭들을 2개씩 묶어 페이지화한다(청크 크기 = 2).
// - 각 청크 페이지 안에는 DefaultTabController + TabBar(최대 2개 탭) + TabBarView(스크롤 비활성)로 구성.
// - TabBarView는 스와이프 충돌을 방지하기 위해 NeverScrollableScrollPhysics 사용(탭 전환은 탭 클릭으로만).
// - PageView를 좌우 스와이프하면 다음(또는 이전) 2개 탭 묶음으로 이동.
// - 외부 SecondaryState.selectedIndex와 양방향 동기화.
//
// 팔레트(서비스 카드 색상계열) 반영:
// - base(Primary), dark(텍스트/아이콘 강조), light(보더/톤 변화), fg(전경 흰색)
// - AppBar 타이틀/아이콘 색은 dark, 하단 헤어라인은 light
// - TabBar 라벨/인디케이터는 base, 비선택 라벨은 dark의 0.6
// - 로딩 인디케이터도 base 컬러로 고정
//
// 안전 가드:
// - 탭이 하나도 없을 때 안내 문구 표시
// - selectedIndex를 pages 길이에 맞게 clamp
// - PageStorageKey로 각 실제 탭 콘텐츠 상태 보존

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../states/secondary/secondary_info.dart';
import '../states/secondary/secondary_state.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 톤)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
}

class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 전역에서 이미 SecondaryState가 주입됨
    return const _SecondaryScaffold(key: ValueKey('secondary_scaffold'));
  }
}

class _SecondaryScaffold extends StatelessWidget {
  const _SecondaryScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SecondaryState>(
      builder: (context, state, _) {
        if (state.pages.isEmpty) {
          return Scaffold(
            appBar: _appBar(),
            body: const Center(child: Text('표시할 탭이 없습니다')),
          );
        }
        // selectedIndex 안전화
        final int safeIndex =
        state.selectedIndex.clamp(0, state.pages.length - 1);

        return _ChunkedTabsRoot(
          pages: state.pages,
          selectedIndex: safeIndex,
          isLoading: state.isLoading,
          onSelect: state.onItemTapped,
        );
      },
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      foregroundColor: _Palette.dark,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        '보조 페이지',
        style: TextStyle(fontWeight: FontWeight.w600, color: _Palette.dark),
      ),
      iconTheme: const IconThemeData(color: _Palette.dark),
      actionsIconTheme: const IconThemeData(color: _Palette.dark),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: _Palette.light.withOpacity(.18), // 헤어라인
        ),
      ),
    );
  }
}

class _ChunkedTabsRoot extends StatefulWidget {
  final List<SecondaryInfo> pages;
  final int selectedIndex;
  final bool isLoading;
  final ValueChanged<int> onSelect;

  const _ChunkedTabsRoot({
    required this.pages,
    required this.selectedIndex,
    required this.isLoading,
    required this.onSelect,
  });

  @override
  State<_ChunkedTabsRoot> createState() => _ChunkedTabsRootState();
}

class _ChunkedTabsRootState extends State<_ChunkedTabsRoot> {
  static const int _chunkSize = 2;
  late final PageController _chunkController;
  int _currentChunk = 0;

  int get _chunkCount =>
      (widget.pages.length / _chunkSize).ceil().clamp(1, 9999);

  int _chunkOf(int globalIndex) => globalIndex ~/ _chunkSize;

  @override
  void initState() {
    super.initState();
    _currentChunk = _chunkOf(widget.selectedIndex);
    _chunkController = PageController(initialPage: _currentChunk);
  }

  @override
  void didUpdateWidget(covariant _ChunkedTabsRoot oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 선택 인덱스가 바뀌었으면, 해당하는 청크로 이동
    final desiredChunk = _chunkOf(widget.selectedIndex);
    if (desiredChunk != _currentChunk && _chunkController.hasClients) {
      _currentChunk = desiredChunk;
      // 애니메이션 이동(컨트롤러가 첫 빌드 중일 수 있으므로 post-frame 보장)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_chunkController.hasClients) return;
        _chunkController.animateToPage(
          _currentChunk,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _chunkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabLabelStyle = Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(fontWeight: FontWeight.w700);

    return Scaffold(
      appBar: _appBar(),
      body: Stack(
        children: [
          PageView.builder(
            controller: _chunkController,
            itemCount: _chunkCount,
            onPageChanged: (page) {
              _currentChunk = page;
              final firstIndexOfChunk = page * _chunkSize;
              // 현재 선택이 이 청크가 아니면, 청크의 첫 탭으로 선택 전환
              if (widget.selectedIndex < firstIndexOfChunk ||
                  widget.selectedIndex >= firstIndexOfChunk + _chunkSize) {
                widget.onSelect(firstIndexOfChunk);
              }
            },
            itemBuilder: (context, chunk) {
              final start = chunk * _chunkSize;
              final end = math.min(start + _chunkSize, widget.pages.length);
              final items = widget.pages.sublist(start, end);
              final localInitial =
              (widget.selectedIndex >= start && widget.selectedIndex < end)
                  ? widget.selectedIndex - start
                  : 0;

              return DefaultTabController(
                length: items.length,
                initialIndex: localInitial,
                child: Column(
                  children: [
                    // 청크별 탭바 (항상 1~2개만 표시)
                    Material(
                      color: Colors.white,
                      elevation: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _Palette.light.withOpacity(.18),
                              width: 1,
                            ),
                          ),
                        ),
                        child: TabBar(
                          isScrollable: false,
                          onTap: (localIdx) {
                            final globalIdx = start + localIdx;
                            if (globalIdx != widget.selectedIndex) {
                              widget.onSelect(globalIdx);
                            }
                          },
                          labelColor: _Palette.base,
                          unselectedLabelColor: _Palette.dark.withOpacity(.6),
                          labelStyle: tabLabelStyle,
                          indicator: UnderlineTabIndicator(
                            borderSide: const BorderSide(
                              color: _Palette.base,
                              width: 2.5,
                            ),
                          ),
                          tabs: [
                            for (final p in items) Tab(text: p.title, icon: p.icon)
                          ],
                        ),
                      ),
                    ),
                    // 콘텐츠: 스와이프 방지(제스처 충돌 방지), 탭 클릭으로만 전환
                    Expanded(
                      child: TabBarView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          for (var i = 0; i < items.length; i++)
                            KeyedSubtree(
                              key: PageStorageKey<String>('secondary_${start + i}'),
                              child: items[i].page,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // 로딩 오버레이
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !widget.isLoading,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.isLoading
                    ? const _LoadingOverlay()
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      foregroundColor: _Palette.dark,
      elevation: 0,
      centerTitle: true,
      title: const Text(
        '보조 페이지',
        style: TextStyle(fontWeight: FontWeight.w600, color: _Palette.dark),
      ),
      iconTheme: const IconThemeData(color: _Palette.dark),
      actionsIconTheme: const IconThemeData(color: _Palette.dark),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: _Palette.light.withOpacity(.18),
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withOpacity(.35),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(_Palette.base),
        ),
      ),
    );
  }
}
