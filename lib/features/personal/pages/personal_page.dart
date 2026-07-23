import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../dev/application/area_state.dart';
import '../../tablet/applications/tablet_work_session_state.dart';
import 'panels/personal_home_panel.dart';
import 'widgets/personal_prompt_components.dart';
import 'widgets/personal_side_menu.dart';
import 'widgets/personal_top_navigation.dart';

class PersonalPage extends StatefulWidget {
  const PersonalPage({super.key});

  @override
  State<PersonalPage> createState() => _PersonalPageState();
}

class _PersonalPageState extends State<PersonalPage> {
  final GlobalKey<PersonalHomePanelState> _homeKey =
      GlobalKey<PersonalHomePanelState>();
  bool _menuOpen = false;

  void _toggleMenu() {
    HapticFeedback.selectionClick();
    setState(() => _menuOpen = !_menuOpen);
  }

  void _closeMenu() {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (scopedContext) {
          final tokens = PromptUiTheme.of(scopedContext);
          final area = scopedContext.select<AreaState, String?>(
                (state) => state.currentArea,
              ) ??
              '';
          final workState = scopedContext.watch<TabletWorkSessionState>();
          final workStateReady = workState.isReady;
          final workActive = workState.isActive;
          final canRenderWorkingContent = workStateReady && workActive;
          final size = MediaQuery.sizeOf(scopedContext);
          final menuWidth = size.width < 420 ? size.width * .86 : 360.0;
          final duration = personalPromptDuration(
            scopedContext,
            PromptUiMotion.overlay,
          );

          final scaffold = Scaffold(
            backgroundColor: tokens.canvas,
            body: SafeArea(
              top: false,
              bottom: true,
              child: Column(
                children: <Widget>[
                  PersonalTopNavigation(
                    menuOpen: _menuOpen,
                    enabled: true,
                    onMenuPressed: _toggleMenu,
                  ),
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: PersonalPromptAnimatedSwap(
                            stateKey: canRenderWorkingContent,
                            child: canRenderWorkingContent
                                ? ColoredBox(
                                    color: tokens.canvas,
                                    child: PersonalHomePanel(
                                      key: _homeKey,
                                      area: area,
                                    ),
                                  )
                                : const SizedBox.expand(),
                          ),
                        ),
                        Positioned.fill(
                          child: PersonalPromptAnimatedSwap(
                            stateKey: workStateReady
                                ? workActive
                                    ? 'active'
                                    : 'inactive'
                                : 'loading',
                            child: !workStateReady
                                ? const _PersonalWorkSessionLoadingOverlay()
                                : !workActive
                                    ? const _PersonalWorkSessionInactiveOverlay()
                                    : const SizedBox.shrink(),
                          ),
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
              if (_menuOpen) _closeMenu();
            },
            child: Stack(
              children: <Widget>[
                scaffold,
                IgnorePointer(
                  ignoring: !_menuOpen,
                  child: AnimatedOpacity(
                    duration: duration,
                    curve: PromptUiMotion.standard,
                    opacity: _menuOpen ? 1 : 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeMenu,
                      child: ColoredBox(color: tokens.scrim),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: duration,
                  curve: PromptUiMotion.enter,
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
        },
      ),
    );
  }
}

class _PersonalWorkSessionLoadingOverlay extends StatelessWidget {
  const _PersonalWorkSessionLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Stack(
      children: <Widget>[
        ModalBarrier(dismissible: false, color: tokens.scrim),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: const PersonalPromptLoadingState(
                label: '개인형 사용 상태를 확인하는 중입니다.',
              ),
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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workState = context.read<TabletWorkSessionState>();

    return Stack(
      children: <Widget>[
        ModalBarrier(dismissible: false, color: tokens.scrim),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: PromptAnimatedReveal(
                child: PersonalPromptPanel(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tokens.statusOfflineContainer,
                              borderRadius: BorderRadius.circular(
                                PromptUiShapes.control,
                              ),
                              border: Border.all(
                                color: tokens.statusOffline.withOpacity(.28),
                              ),
                            ),
                            child: Icon(
                              Icons.pause_circle_outline_rounded,
                              color: tokens.statusOffline,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '개인형 사용이 종료된 상태입니다.',
                              style: textTheme.titleMedium?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '앱 사용 시작 버튼을 누르면 개인형 홈이 다시 활성화되고 내 차량 상태 확인과 출차 요청 기능을 다시 사용할 수 있습니다.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      PromptButton(
                        label: '앱 사용 시작',
                        icon: Icons.play_arrow_rounded,
                        expand: true,
                        haptic: PromptHaptic.medium,
                        onPressed: workState.startWork,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
