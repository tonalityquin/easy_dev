import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../dev/application/area_state.dart';
import '../../tablet/applications/tablet_work_session_state.dart';
import 'panels/personal_home_panel.dart';
import 'widgets/personal_side_menu.dart';
import 'widgets/personal_top_navigation.dart';

class PersonalPage extends StatefulWidget {
  const PersonalPage({super.key});

  @override
  State<PersonalPage> createState() => _PersonalPageState();
}

class _PersonalPageState extends State<PersonalPage> {
  final GlobalKey<PersonalHomePanelState> _homeKey = GlobalKey<PersonalHomePanelState>();
  bool _menuOpen = false;

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
  }

  void _closeMenu() {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final area = context.select<AreaState, String?>((s) => s.currentArea) ?? '';
    final workState = context.watch<TabletWorkSessionState>();
    final workStateReady = workState.isReady;
    final workActive = workState.isActive;
    final canRenderWorkingContent = workStateReady && workActive;
    final size = MediaQuery.of(context).size;
    final menuWidth = size.width < 420 ? size.width * .86 : 360.0;

    final scaffold = Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            PersonalTopNavigation(
              menuOpen: _menuOpen,
              enabled: true,
              onMenuPressed: _toggleMenu,
            ),
            Expanded(
              child: Stack(
                children: [
                  canRenderWorkingContent
                      ? ColoredBox(
                          color: cs.surface,
                          child: PersonalHomePanel(
                            key: _homeKey,
                            area: area,
                          ),
                        )
                      : const SizedBox.expand(),
                  if (!workStateReady)
                    const Positioned.fill(
                      child: _PersonalWorkSessionLoadingOverlay(),
                    )
                  else if (!workActive)
                    const Positioned.fill(
                      child: _PersonalWorkSessionInactiveOverlay(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_menuOpen) {
          _closeMenu();
        }
      },
      child: Stack(
        children: [
          scaffold,
          if (_menuOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  color: Colors.black.withOpacity(.24),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            top: 0,
            bottom: 0,
            right: _menuOpen ? 0 : -menuWidth,
            width: menuWidth,
            child: PersonalSideMenu(
              onClose: _closeMenu,
              onAddVehicle: () async {
                await _homeKey.currentState?.addVehicleFromMenu();
              },
              onRefreshContent: () async {
                await _homeKey.currentState?.refreshEverythingFromMenu();
              },
              onOpenTodo: () async {
                await _homeKey.currentState?.openTodoDialogFromMenu();
              },
              onOpenCalendar: () async {
                await _homeKey.currentState?.openCalendarDialogFromMenu();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalWorkSessionLoadingOverlay extends StatelessWidget {
  const _PersonalWorkSessionLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withOpacity(0.28),
        ),
        Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(.14),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '개인형 사용 상태를 확인하는 중입니다.',
                  textAlign: TextAlign.center,
                  style: (text.bodyMedium ?? const TextStyle()).copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonalWorkSessionInactiveOverlay extends StatelessWidget {
  const _PersonalWorkSessionInactiveOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withOpacity(0.34),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant.withOpacity(.80)),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(.18),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.pause_circle_outline,
                          color: cs.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '개인형 사용이 종료된 상태입니다.',
                          style: (text.titleMedium ?? const TextStyle()).copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '앱 사용 시작 버튼을 누르면 개인형 홈이 다시 활성화되고 내 차량 상태 확인과 출차 요청 기능을 다시 사용할 수 있습니다.',
                    style: (text.bodyMedium ?? const TextStyle()).copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      await context.read<TabletWorkSessionState>().startWork();
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('앱 사용 시작'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
