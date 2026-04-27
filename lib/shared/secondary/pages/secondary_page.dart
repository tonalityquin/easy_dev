
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/secondary_info.dart';
import '../application/secondary_state.dart';

class SecondaryPage extends StatelessWidget {
  const SecondaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    
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
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: _appBar(context),
            body: const Center(child: Text('표시할 탭이 없습니다')),
          );
        }

        
        final int safeIndex = state.selectedIndex.clamp(0, state.pages.length - 1);

        return _ChunkedTabsRoot(
          pages: state.pages,
          selectedIndex: safeIndex,
          isLoading: state.isLoading,
          onSelect: state.onItemTapped,
        );
      },
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(
        '보조 페이지',
        style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      iconTheme: IconThemeData(color: cs.onSurface),
      actionsIconTheme: IconThemeData(color: cs.onSurface),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: cs.outlineVariant.withOpacity(.75), 
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

  int get _chunkCount => (widget.pages.length / _chunkSize).ceil().clamp(1, 9999);

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

    
    final desiredChunk = _chunkOf(widget.selectedIndex);
    if (desiredChunk != _currentChunk && _chunkController.hasClients) {
      _currentChunk = desiredChunk;

      
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
    final cs = Theme.of(context).colorScheme;

    final tabLabelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
    );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: _appBar(context),
      body: Stack(
        children: [
          PageView.builder(
            controller: _chunkController,
            itemCount: _chunkCount,
            onPageChanged: (page) {
              _currentChunk = page;
              final firstIndexOfChunk = page * _chunkSize;

              
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
                    
                    Material(
                      color: cs.surface,
                      elevation: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: cs.outlineVariant.withOpacity(.75),
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
                          labelColor: cs.primary,
                          unselectedLabelColor: cs.onSurfaceVariant.withOpacity(.75),
                          labelStyle: tabLabelStyle,
                          indicator: UnderlineTabIndicator(
                            borderSide: BorderSide(
                              color: cs.primary,
                              width: 2.5,
                            ),
                          ),
                          dividerColor: Colors.transparent, 
                          tabs: [
                            for (final p in items) Tab(text: p.title, icon: p.icon),
                          ],
                        ),
                      ),
                    ),
                    
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

          
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !widget.isLoading,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.isLoading ? const _LoadingOverlay() : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      title: Text(
        '보조 페이지',
        style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      iconTheme: IconThemeData(color: cs.onSurface),
      actionsIconTheme: IconThemeData(color: cs.onSurface),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: cs.outlineVariant.withOpacity(.75),
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.scrim.withOpacity(.10),
      alignment: Alignment.center,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      ),
    );
  }
}
