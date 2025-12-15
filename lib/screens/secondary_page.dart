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
