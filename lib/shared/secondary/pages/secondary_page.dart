import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/secondary_info.dart';
import '../application/secondary_state.dart';

class SecondaryPage extends StatefulWidget {
  const SecondaryPage({super.key});

  @override
  State<SecondaryPage> createState() => _SecondaryPageState();
}

class _SecondaryPageState extends State<SecondaryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SecondaryState>().refreshDeveloperLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _SecondaryConsoleRoot(key: ValueKey('secondary_console_root'));
  }
}

class _SecondaryConsoleRoot extends StatelessWidget {
  const _SecondaryConsoleRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SecondaryState>(
      builder: (context, state, _) {
        final cs = Theme.of(context).colorScheme;
        if (state.pages.isEmpty) {
          return Scaffold(
            backgroundColor: cs.surfaceVariant.withOpacity(.22),
            body: const Center(child: Text('표시할 관리 항목이 없습니다')),
          );
        }

        final safeIndex = state.selectedIndex.clamp(0, state.pages.length - 1);
        final selectedPage = state.pages[safeIndex];

        return Scaffold(
          backgroundColor: cs.surfaceVariant.withOpacity(.22),
          body: Column(
            children: [
              SafeArea(
                bottom: false,
                child: _SecondaryNavBar(
                  pages: state.pages,
                  selectedIndex: safeIndex,
                  isLoading: state.isLoading,
                  onSelect: state.onItemTapped,
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey<String>('secondary_page_${selectedPage.title}_$safeIndex'),
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          child: selectedPage.page,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !state.isLoading,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: state.isLoading ? const _LoadingOverlay() : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SecondaryNavBar extends StatelessWidget {
  final List<SecondaryInfo> pages;
  final int selectedIndex;
  final bool isLoading;
  final ValueChanged<int> onSelect;

  const _SecondaryNavBar({
    required this.pages,
    required this.selectedIndex,
    required this.isLoading,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(.28))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.admin_panel_settings_rounded, color: cs.onPrimary, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '보조 운영 콘솔',
                      style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '설정·계정·구역·태블릿·정산 관리',
                      style: (tt.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
                        color: cs.onInverseSurface.withOpacity(.70),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = pages[index];
                final selected = index == selectedIndex;
                return _NavChip(
                  title: item.title,
                  icon: item.icon.icon ?? Icons.circle,
                  selected: selected,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavChip({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.onInverseSurface : cs.onInverseSurface.withOpacity(.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? cs.onInverseSurface : cs.onInverseSurface.withOpacity(.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? cs.inverseSurface : cs.onInverseSurface.withOpacity(.74)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: selected ? cs.inverseSurface : cs.onInverseSurface.withOpacity(.78),
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ],
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
