import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
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
    return const PromptUiScope(
      child: _SecondaryConsoleRoot(
        key: ValueKey<String>('secondary_console_root'),
      ),
    );
  }
}

class _SecondaryConsoleRoot extends StatelessWidget {
  const _SecondaryConsoleRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final brightness = Theme.of(context).brightness;
    final overlayStyle = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(
        statusBarColor: tokens.surfaceRaised,
        systemNavigationBarColor: tokens.canvas,
        systemNavigationBarDividerColor: tokens.borderSubtle,
      ),
      child: Consumer<SecondaryState>(
        builder: (context, state, _) {
          if (state.pages.isEmpty) {
            return Scaffold(
              backgroundColor: tokens.canvas,
              body: SafeArea(
                child: Center(
                  child: PromptAnimatedReveal(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: tokens.surfaceOverlay,
                            borderRadius: BorderRadius.circular(
                              PromptUiShapes.card,
                            ),
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.inbox_outlined,
                            color: tokens.iconSecondary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '표시할 관리 항목이 없습니다',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final safeIndex = state.selectedIndex.clamp(
            0,
            state.pages.length - 1,
          );
          final selectedPage = state.pages[safeIndex];

          return Scaffold(
            backgroundColor: tokens.canvas,
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
                        duration: reduceMotion
                            ? Duration.zero
                            : PromptUiMotion.component,
                        switchInCurve: PromptUiMotion.enter,
                        switchOutCurve: PromptUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          final curved = CurvedAnimation(
                            parent: animation,
                            curve: PromptUiMotion.enter,
                            reverseCurve: PromptUiMotion.exit,
                          );
                          return FadeTransition(
                            opacity: curved,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(.025, 0),
                                end: Offset.zero,
                              ).animate(curved),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey<String>(
                            'secondary_page_${selectedPage.title}_$safeIndex',
                          ),
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
                          child: AnimatedOpacity(
                            opacity: state.isLoading ? 1 : 0,
                            duration: reduceMotion
                                ? Duration.zero
                                : PromptUiMotion.selection,
                            child: ColoredBox(
                              color: tokens.scrim.withOpacity(.12),
                              child: Center(
                                child: Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: tokens.surfaceRaised,
                                    borderRadius: BorderRadius.circular(
                                      PromptUiShapes.control,
                                    ),
                                    border: Border.all(
                                      color: tokens.borderSubtle,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: tokens.shadow,
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: 25,
                                    height: 25,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.7,
                                      color: tokens.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
      ),
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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: tokens.onAccentContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '보조 운영 콘솔',
                      style: textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '설정·계정·구역·태블릿·정산 관리',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                    ? Duration.zero
                    : PromptUiMotion.selection,
                child: isLoading
                    ? SizedBox(
                        key: const ValueKey<String>('secondary_loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: tokens.accent,
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey<String>('secondary_idle'),
                        width: 22,
                        height: 22,
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
                return _NavChip(
                  title: item.title,
                  icon: item.icon.icon ?? Icons.circle,
                  selected: index == selectedIndex,
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = selected ? tokens.onAccentContainer : tokens.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        decoration: BoxDecoration(
          color: selected ? tokens.accentContainer : tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(PromptUiShapes.pill),
          border: Border.all(
            color: selected ? tokens.accent : tokens.borderSubtle,
          ),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.pill),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            borderRadius: BorderRadius.circular(PromptUiShapes.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
