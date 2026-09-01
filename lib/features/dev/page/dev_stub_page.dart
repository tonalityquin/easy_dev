import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../application/debug_session_controller.dart';
import '../presentation/debug_tool_shell.dart';
import 'sheets/dev_quick_actions.dart';

const Color _debugAccent = Color(0xFF6D5DFB);

class DevStubPage extends StatelessWidget {
  const DevStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DebugSessionController.enabled,
      builder: (context, enabled, _) {
        final reduceMotion = MediaQuery.of(context).disableAnimations;
        return Scaffold(
          body: AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            child: enabled
                ? _DebugHub(
                    key: const ValueKey<String>('debug_hub_active'),
                    reduceMotion: reduceMotion,
                  )
                : const _DebugInactive(
                    key: ValueKey<String>('debug_hub_inactive'),
                  ),
          ),
        );
      },
    );
  }
}

class _DebugHub extends StatelessWidget {
  const _DebugHub({super.key, required this.reduceMotion});

  final bool reduceMotion;

  Future<void> _showStatus(BuildContext context) async {
    await DebugSessionController.showStatus(
      context,
      source: 'developer_hub',
      description: const <String>[
        'DEBUG session: ACTIVE',
        'Route: Developer Hub',
        'SharedPreferences: available',
        'SQLite Explorer: available',
      ].join('\n'),
    );
  }

  Future<void> _exitDebug(BuildContext context) async {
    HapticFeedback.mediumImpact();
    DebugSessionController.record(
      'debug_exit_from_tool',
      source: 'developer_hub',
    );
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.modeLauncher,
      (route) => false,
    );
    if (!reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    await DebugSessionController.disable(source: 'developer_hub');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Column(
        children: [
          DebugToolHeader(
            title: 'Developer Hub',
            breadcrumb: 'Developer / Hub',
            meta: 'DEBUG session active',
            onClose: () => Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.modeLauncher,
              (route) => false,
            ),
            onStatus: () => _showStatus(context),
            onDebugExit: () => _exitDebug(context),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 680;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          _debugAccent.withOpacity(0.09),
                          cs.surfaceContainerLow,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _debugAccent.withOpacity(0.32),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _debugAccent.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.terminal_rounded,
                              color: _debugAccent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DEBUG ACTIVE',
                                  style: text.titleMedium?.copyWith(
                                    color: _debugAccent,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '로컬 상태와 데이터베이스를 검사하는 개발자 세션입니다.',
                                  style: text.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '검사',
                      style: text.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (compact) ...[
                      _DebugHubAction(
                        index: 0,
                        reduceMotion: reduceMotion,
                        icon: Icons.tune_rounded,
                        title: 'SharedPreferences',
                        description: '로컬 설정 값을 검색하고 수정합니다.',
                        onTap: () => DevQuickActions.openSheetExclusively(
                          (ctx) => DevQuickActions.showLocalPrefsSheet(ctx),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _DebugHubAction(
                        index: 1,
                        reduceMotion: reduceMotion,
                        icon: Icons.storage_rounded,
                        title: 'SQLite Explorer',
                        description: 'DB, 테이블, 행과 스키마를 검사합니다.',
                        onTap: () => DevQuickActions.openSheetExclusively(
                          (ctx) => DevQuickActions.showSQLiteExplorerSheet(ctx),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _DebugHubAction(
                        index: 2,
                        reduceMotion: reduceMotion,
                        icon: Icons.monitor_heart_outlined,
                        title: 'Status',
                        description: 'debugPrint 로그를 확인하고 코드를 복사합니다.',
                        onTap: () => _showStatus(context),
                      ),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _DebugHubAction(
                              index: 0,
                              reduceMotion: reduceMotion,
                              icon: Icons.tune_rounded,
                              title: 'SharedPreferences',
                              description: '로컬 설정 값을 검색하고 수정합니다.',
                              onTap: () => DevQuickActions.openSheetExclusively(
                                (ctx) => DevQuickActions.showLocalPrefsSheet(ctx),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DebugHubAction(
                              index: 1,
                              reduceMotion: reduceMotion,
                              icon: Icons.storage_rounded,
                              title: 'SQLite Explorer',
                              description: 'DB, 테이블, 행과 스키마를 검사합니다.',
                              onTap: () => DevQuickActions.openSheetExclusively(
                                (ctx) => DevQuickActions.showSQLiteExplorerSheet(ctx),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DebugHubAction(
                              index: 2,
                              reduceMotion: reduceMotion,
                              icon: Icons.monitor_heart_outlined,
                              title: 'Status',
                              description: 'debugPrint 로그를 확인하고 코드를 복사합니다.',
                              onTap: () => _showStatus(context),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Text(
                      '세션',
                      style: text.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 9),
                    OutlinedButton.icon(
                      onPressed: () => _exitDebug(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('DEBUG 종료'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugHubAction extends StatelessWidget {
  const _DebugHubAction({
    required this.index,
    required this.reduceMotion,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final int index;
  final bool reduceMotion;
  final IconData icon;
  final String title;
  final String description;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 124),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _debugAccent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: _debugAccent, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    if (reduceMotion) return card;
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 180 + index * 35),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 7 * (1 - value)),
            child: child,
          ),
        );
      },
      child: card,
    );
  }
}

class _DebugInactive extends StatelessWidget {
  const _DebugInactive({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.terminal_outlined,
                size: 40,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                'DEBUG 세션이 비활성 상태입니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 7),
              Text(
                '파킨워킨 터미널에서 debug 명령으로 활성화할 수 있습니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.modeLauncher,
                  (route) => false,
                ),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
