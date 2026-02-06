import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../utils/block_dialogs/work_end_duration_blocking_dialog.dart';
import '../../../../../utils/init/logout_helper.dart';
import '../../../../../utils/app_exit_flag.dart';

import '../../../../common_package/sheet_tool/leader_document_box_sheet.dart';
import '../../../../single_mode/utils/att_brk_repository.dart';
import 'minor_home_dash_board_controller.dart';
import 'widgets/minor_home_user_info_card.dart';
import 'widgets/minor_home_break_button_widget.dart';

import '../../../../hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

// ✅ 전역 테마 컨트롤러 + 브랜드 프리셋/테마모드 스펙
import '../../../../../../theme_prefs_controller.dart';
import '../../../../../../selector_hubs_package/brand_theme.dart';

class MinorHqDashBoardPage extends StatefulWidget {
  const MinorHqDashBoardPage({super.key});

  @override
  State<MinorHqDashBoardPage> createState() => _MinorHqDashBoardPageState();
}

class _MinorHqDashBoardPageState extends State<MinorHqDashBoardPage> {
  bool _layerHidden = true;

  late final MinorHomeDashBoardController _controller = MinorHomeDashBoardController();

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(context);
  }

  /// ✅ themeModeSpecs()에 independent가 없을 수도 있으므로 안전하게 확장(중복 제거)
  List<ThemeModeSpec> _themeModesExtended() {
    final base = themeModeSpecs();
    final ids = <String>{...base.map((e) => e.id)};

    if (!ids.contains('independent')) {
      return [
        ...base,
        const ThemeModeSpec(
          id: 'independent',
          label: '독립',
          icon: Icons.layers_rounded,
        ),
      ];
    }
    return base;
  }

  String _themeModeLabel(String id) {
    final modes = _themeModesExtended();
    return modes.firstWhere((m) => m.id == id, orElse: () => modes.first).label;
  }

  /// ✅ 모드에 따라 프리셋 리스트 분리:
  /// brand_theme.dart의 공식 필터(독립/일반 분리) 사용
  List<BrandPresetSpec> _presetsForMode(String themeModeId) {
    final filtered = brandPresetsForThemeMode(themeModeId);
    return filtered.isNotEmpty ? filtered : brandPresets();
  }

  /// ✅ 모드 전환 시 프리셋 호환성 자동 교정
  /// - independent 진입: 현재 프리셋이 독립이 아니면 첫 독립 프리셋으로 변경
  /// - independent 이탈: 현재 프리셋이 독립이면 system으로 교정
  Future<void> _setThemeModeWithPresetFix(
      ThemePrefsController themeCtrl,
      String nextModeId,
      ) async {
    final beforeMode = themeCtrl.themeModeId;
    final beforePreset = themeCtrl.presetId;

    if (beforeMode == nextModeId) return;

    await themeCtrl.setThemeModeId(nextModeId);

    if (nextModeId == 'independent') {
      final cur = presetById(themeCtrl.presetId);
      if (cur.independentTokens == null) {
        final candidates = brandPresetsForThemeMode('independent');
        if (candidates.isNotEmpty) {
          final fallback = candidates.first.id;
          await themeCtrl.setPresetId(fallback);

          _trace(
            '독립 모드 프리셋 자동 교정',
            meta: <String, dynamic>{
              'screen': 'minor_hq_dashboard',
              'action': 'preset_autofix_on_enter_independent',
              'presetIdBefore': beforePreset,
              'presetIdAfter': fallback,
            },
          );
        }
      }
    } else {
      final cur = presetById(themeCtrl.presetId);
      if (cur.independentTokens != null) {
        await themeCtrl.setPresetId('system');

        _trace(
          '일반 모드 프리셋 자동 교정',
          meta: <String, dynamic>{
            'screen': 'minor_hq_dashboard',
            'action': 'preset_autofix_on_exit_independent',
            'presetIdBefore': beforePreset,
            'presetIdAfter': 'system',
          },
        );
      }
    }

    _trace(
      '테마 모드 변경 완료',
      meta: <String, dynamic>{
        'screen': 'minor_hq_dashboard',
        'action': 'theme_mode_changed_done',
        'themeModeBefore': beforeMode,
        'themeModeAfter': nextModeId,
        'presetIdNow': themeCtrl.presetId,
      },
    );
  }

  /// ✅ 테마 설정(모드 + 색상 프리셋) 다이얼로그
  Future<void> _openThemeSettingsDialog(BuildContext context) async {
    _trace(
      '테마 설정 다이얼로그 오픈',
      meta: <String, dynamic>{
        'screen': 'minor_hq_dashboard',
        'action': 'open_theme_settings_dialog',
      },
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Consumer<ThemePrefsController>(
          builder: (ctx, themeCtrl, _) {
            final cs = Theme.of(ctx).colorScheme;
            final text = Theme.of(ctx).textTheme;

            final modes = _themeModesExtended();
            final presets = _presetsForMode(themeCtrl.themeModeId);

            final bool isIndependent = themeCtrl.themeModeId == 'independent';
            final String modeGuide = isIndependent
                ? '독립 모드는 색 패키지가 배경/텍스트/하이라이트를 직접 결정합니다.'
                : '컨셉 컬러는 포인트(primary)만 변경되고, 표면(surfaces)은 중립으로 유지됩니다.';

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              title: Row(
                children: [
                  const Icon(Icons.tune_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '테마 설정',
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '테마 모드(시스템/라이트/다크/독립)와 색 패키지를 선택하면 앱 전체에 즉시 적용됩니다.',
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),

                      // ─────────────────────────────────────────────
                      // ✅ 테마 모드 섹션
                      Text(
                        '테마 모드',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: modes.map((m) {
                          final selected = m.id == themeCtrl.themeModeId;
                          return ChoiceChip(
                            selected: selected,
                            onSelected: (_) async {
                              HapticFeedback.selectionClick();

                              _trace(
                                '테마 모드 변경',
                                meta: <String, dynamic>{
                                  'screen': 'minor_hq_dashboard',
                                  'action': 'theme_mode_changed',
                                  'themeModeBefore': themeCtrl.themeModeId,
                                  'themeModeAfter': m.id,
                                },
                              );

                              await _setThemeModeWithPresetFix(themeCtrl, m.id);
                            },
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(m.icon, size: 16),
                                const SizedBox(width: 6),
                                Text(m.label),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 14),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(0.7)),
                      const SizedBox(height: 14),

                      // ─────────────────────────────────────────────
                      // ✅ 프리셋 섹션
                      Text(
                        '색 패키지',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        modeGuide,
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: presets.map((p) {
                          final selected = p.id == themeCtrl.presetId;
                          return ChoiceChip(
                            selected: selected,
                            onSelected: (_) async {
                              HapticFeedback.selectionClick();

                              _trace(
                                '테마 프리셋 변경',
                                meta: <String, dynamic>{
                                  'screen': 'minor_hq_dashboard',
                                  'action': 'theme_preset_changed',
                                  'presetIdBefore': themeCtrl.presetId,
                                  'presetIdAfter': p.id,
                                  'themeModeId': themeCtrl.themeModeId,
                                },
                              );

                              await themeCtrl.setPresetId(p.id);
                            },
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _PresetPreviewDots(colors: p.preview),
                                const SizedBox(width: 8),
                                Text(p.label),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 12),

                      // ─────────────────────────────────────────────
                      // ✅ 현재 선택 요약
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '현재: ${_themeModeLabel(themeCtrl.themeModeId)} / ${presetById(themeCtrl.presetId).label}',
                                style: text.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    AppExitFlag.beginExit();

    try {
      if (DebugActionRecorder.instance.isRecording) {
        await DebugActionRecorder.instance.stopAndSave(
          titleOverride: 'auto:clockout_exit',
        );
      }
    } catch (_) {}

    try {
      if (Platform.isAndroid) {
        bool running = false;

        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {}

        if (running) {
          try {
            final stopped = await FlutterForegroundTask.stopService();
            if (stopped != true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('포그라운드 서비스 중지 실패(플러그인 반환값 false)'),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('포그라운드 서비스 중지 실패: $e')),
              );
            }
          }

          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      await SystemNavigator.pop();
    } catch (e) {
      AppExitFlag.reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('앱 종료 실패: $e')),
        );
      }
    }
  }

  Future<void> _handleClockOutFlow(BuildContext context, UserState userState) async {
    _trace(
      '퇴근 처리 시작',
      meta: <String, dynamic>{
        'screen': 'minor_hq_dashboard',
        'action': 'clockout_flow_start',
        'isWorkingBefore': userState.isWorking,
      },
    );

    await _controller.handleWorkStatus(userState, context);

    if (!mounted) return;

    _trace(
      '퇴근 상태 반영',
      meta: <String, dynamic>{
        'screen': 'minor_hq_dashboard',
        'action': 'clockout_state_updated',
        'isWorkingAfter': userState.isWorking,
      },
    );

    if (!userState.isWorking) {
      final user = userState.user;
      if (user != null) {
        final now = DateTime.now();

        _trace(
          '퇴근 이벤트 기록',
          meta: <String, dynamic>{
            'screen': 'minor_hq_dashboard',
            'action': 'workout_event_insert_and_upload',
            'area': userState.currentArea,
            'division': userState.division,
            'at': now.toIso8601String(),
          },
        );

        await AttBrkRepository.instance.insertEventAndUpload(
          dateTime: now,
          type: AttBrkModeType.workOut,
          userId: user.id,
          userName: user.name,
          area: userState.currentArea,
          division: userState.division,
        );
      }

      _trace(
        '앱 종료 진행',
        meta: <String, dynamic>{
          'screen': 'minor_hq_dashboard',
          'action': 'exit_after_clockout',
        },
      );

      await _exitAppAfterClockOut(context);
    } else {
      _trace(
        '퇴근 처리 미완료',
        meta: <String, dynamic>{
          'screen': 'minor_hq_dashboard',
          'action': 'clockout_not_completed',
          'reason': 'userState.isWorking_still_true',
        },
      );
    }
  }

  Future<void> _onClockOutPressed(BuildContext context, UserState userState) async {
    _trace(
      '퇴근하기 버튼',
      meta: <String, dynamic>{
        'screen': 'minor_hq_dashboard',
        'action': 'clockout_tap',
        'isWorking': userState.isWorking,
      },
    );

    if (userState.isWorking) {
      final bool confirmed = await showWorkEndDurationBlockingDialog(
        context,
        message: '지금 퇴근 처리하시겠습니까?\n5초 안에 취소하지 않으면 자동으로 진행됩니다.',
        duration: const Duration(seconds: 5),
      );

      _trace(
        '퇴근 다이얼로그 결과',
        meta: <String, dynamic>{
          'screen': 'minor_hq_dashboard',
          'action': 'clockout_dialog_result',
          'confirmed': confirmed,
          'durationSeconds': 5,
        },
      );

      if (!confirmed) {
        _trace(
          '퇴근 처리 취소',
          meta: <String, dynamic>{
            'screen': 'minor_hq_dashboard',
            'action': 'clockout_aborted',
            'reason': 'user_cancelled_dialog',
          },
        );
        return;
      }
    }

    await _handleClockOutFlow(context, userState);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      // ✅ 독립 테마의 배경(background)이 살아나도록 background 사용
      backgroundColor: cs.background,
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MinorHomeUserInfoCard(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(_layerHidden ? Icons.layers : Icons.layers_clear),
                    label: Text(_layerHidden ? '작업 버튼 펼치기' : '작업 버튼 숨기기'),
                    style: _outlinedSurfaceBtnStyle(context, minHeight: 48),
                    onPressed: () => setState(() => _layerHidden = !_layerHidden),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _layerHidden ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MinorHomeBreakButtonWidget(controller: _controller),
                      const SizedBox(height: 16),

                      // ✅ 테마 설정 버튼
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.palette_outlined),
                          label: const Text('테마 설정(모드/색상)'),
                          style: _accentOutlinedBtnStyle(context),
                          onPressed: () => _openThemeSettingsDialog(context),
                        ),
                      ),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('퇴근하기'),
                          style: _dangerOutlinedBtnStyle(context),
                          onPressed: () => _onClockOutPressed(context, userState),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('로그아웃'),
                          style: _outlinedSurfaceBtnStyle(context),
                          onPressed: () => _handleLogout(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('서류함 열기'),
                          style: _outlinedSurfaceBtnStyle(context),
                          onPressed: () => openLeaderDocumentBox(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_layerHidden) const SizedBox(height: 16),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

ButtonStyle _outlinedSurfaceBtnStyle(BuildContext context, {double minHeight = 55}) {
  final cs = Theme.of(context).colorScheme;

  return ElevatedButton.styleFrom(
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    minimumSize: Size.fromHeight(minHeight),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
          (states) => states.contains(MaterialState.pressed) ? cs.outlineVariant.withOpacity(0.12) : null,
    ),
  );
}

/// ✅ primary 기반 아웃라인 버튼 스타일(배경 surface 유지)
ButtonStyle _accentOutlinedBtnStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;

  return ElevatedButton.styleFrom(
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(color: cs.primary.withOpacity(0.85), width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
          (states) => states.contains(MaterialState.pressed) ? cs.primary.withOpacity(0.10) : null,
    ),
  );
}

ButtonStyle _dangerOutlinedBtnStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;

  return ElevatedButton.styleFrom(
    backgroundColor: cs.surface,
    foregroundColor: cs.error,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(color: cs.error.withOpacity(0.65), width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
          (states) => states.contains(MaterialState.pressed) ? cs.error.withOpacity(0.10) : null,
    ),
  );
}

/// ✅ 프리셋 UI 미리보기(3색 점)
class _PresetPreviewDots extends StatelessWidget {
  const _PresetPreviewDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final dots = colors.take(3).toList();
    final outline = Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(dots.length, (i) {
        final c = dots[i];
        return Container(
          width: 10,
          height: 10,
          margin: EdgeInsets.only(right: i == dots.length - 1 ? 0 : 4),
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: outline),
          ),
        );
      }),
    );
  }
}
