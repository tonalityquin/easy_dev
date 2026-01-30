import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../states/area/area_state.dart';
import '../../../widgets/tts_filter_sheet.dart';
import '../../../utils/tts/tts_sync_helper.dart';
import '../states/tablet_pad_mode_state.dart';

// ⬇️ 로그아웃 공통 헬퍼
import '../../../utils/init/logout_helper.dart';

// ✅ 출차 요청 구독 토글을 위해 PlateState/PlateType/스낵바
import '../../../states/plate/plate_state.dart';
import '../../../enums/plate_type.dart';
import '../../../utils/snackbar_helper.dart';

// ✅ 전역 테마 컨트롤러 + 브랜드 프리셋/테마모드 스펙
import '../../../theme_prefs_controller.dart';
import '../../../selector_hubs_package/brand_theme.dart';

class TabletTopNavigation extends StatelessWidget {
  final bool isAreaSelectable;

  const TabletTopNavigation({
    super.key,
    this.isAreaSelectable = true,
  });

  Color _tintOnSurface(ColorScheme cs, double opacity) {
    // primary를 surface 위에 얇게 얹어 브랜드 톤 “힌트”를 주는 용도
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  ButtonStyle _accentOutlinedBtnStyle(BuildContext context, {double minHeight = 48}) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton.styleFrom(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      minimumSize: Size(double.infinity, minHeight),
      padding: EdgeInsets.zero,
      elevation: 0,
      side: BorderSide(color: cs.primary.withOpacity(0.85), width: 1.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
            ? cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.12 : 0.08)
            : null,
      ),
    );
  }

  String _themeModeLabel(String id) {
    return themeModeSpecs()
        .firstWhere((m) => m.id == id, orElse: () => themeModeSpecs().first)
        .label;
  }

  /// ✅ 동일 UI/로직: MinorHqDashBoardPage의 "테마 설정" 다이얼로그를 이 메뉴에서도 재사용
  Future<void> _openThemeSettingsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Consumer<ThemePrefsController>(
          builder: (ctx, themeCtrl, _) {
            final cs = Theme.of(ctx).colorScheme;
            final text = Theme.of(ctx).textTheme;

            final modes = themeModeSpecs();
            final presets = brandPresets();

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
                        '테마 모드(시스템/라이트/다크)와 색 프리셋을 선택하면 앱 전체에 즉시 적용됩니다.',
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
                              await themeCtrl.setThemeModeId(m.id);
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
                        '테마 색(프리셋)',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '컨셉 컬러는 포인트(primary)만 변경되고, 표면(surfaces)은 중립으로 유지됩니다.',
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

  @override
  Widget build(BuildContext context) {
    final selectedArea = context.watch<AreaState>().currentArea;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final overlay = MaterialStateProperty.resolveWith<Color?>(
          (states) {
        if (states.contains(MaterialState.pressed)) {
          return cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.14 : 0.10);
        }
        if (states.contains(MaterialState.hovered) || states.contains(MaterialState.focused)) {
          return cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.10 : 0.06);
        }
        return null;
      },
    );

    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: isAreaSelectable ? () => _openTopNavDialog(context) : null,
        overlayColor: overlay,
        child: SizedBox(
          width: double.infinity,
          height: kToolbarHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.car, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                (selectedArea.trim().isNotEmpty) ? selectedArea : '지역 없음',
                style: (text.titleMedium ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              if (isAreaSelectable) ...[
                const SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_down, size: 14, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTopNavDialog(BuildContext context) async {
    final area = context.read<AreaState>().currentArea;
    final padMode = context.read<TabletPadModeState>().mode;

    final depBusy = ValueNotifier<bool>(false);

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) {
          final cs = Theme.of(dialogCtx).colorScheme;
          final text = Theme.of(dialogCtx).textTheme;

          Color tint(double opacity) => _tintOnSurface(cs, opacity);

          // 모드별 "구분감"을 주되, 브랜드 테마 토큰만 사용:
          // - 전부 surface 기반 + primary 아주 얕은 블렌딩 정도만 다르게
          Color bgForMode(PadMode m) {
            final dark = cs.brightness == Brightness.dark;
            switch (m) {
              case PadMode.big:
                return tint(dark ? 0.10 : 0.05);
              case PadMode.small:
                return tint(dark ? 0.14 : 0.07);
              case PadMode.show:
                return tint(dark ? 0.08 : 0.04);
              case PadMode.mobile:
                return tint(dark ? 0.12 : 0.06);
            }
          }

          Widget modeButton({
            required PadMode target,
            required String title,
            required String subtitle,
            required IconData icon,
          }) {
            final bool selected = padMode == target;

            final sideColor = selected ? cs.primary : cs.outlineVariant;
            final bg = bgForMode(target);

            return SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  dialogCtx.read<TabletPadModeState>().setMode(target);
                  Navigator.of(dialogCtx, rootNavigator: true).pop();
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  side: BorderSide(
                    color: sideColor.withOpacity(selected ? 0.95 : 0.85),
                    width: selected ? 1.5 : 1.0,
                  ),
                  backgroundColor: bg,
                  foregroundColor: cs.onSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ).copyWith(
                  overlayColor: MaterialStateProperty.resolveWith<Color?>(
                        (states) => states.contains(MaterialState.pressed)
                        ? cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.14 : 0.10)
                        : null,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: (text.bodyLarge ?? const TextStyle()).copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: (text.bodySmall ?? const TextStyle()).copyWith(
                              fontSize: 12.5,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_circle, color: cs.primary),
                    ],
                  ],
                ),
              ),
            );
          }

          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: cs.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: MediaQuery.of(dialogCtx).size.height * 0.85,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: StatefulBuilder(
                  builder: (innerCtx, setSB) {
                    final plateState = innerCtx.watch<PlateState>();

                    Future<void> _toggleDepartureSubscribe() async {
                      if (depBusy.value) return;
                      depBusy.value = true;
                      try {
                        final isSubscribedDeparture =
                        plateState.isSubscribed(PlateType.departureRequests);

                        if (!isSubscribedDeparture) {
                          await Future.sync(() => plateState.tabletSubscribeDeparture());
                          final currentArea = plateState.currentArea;
                          showSuccessSnackbar(
                            innerCtx,
                            '✅ [출차 요청] 구독 시작됨\n지역: ${currentArea.isEmpty ? "미지정" : currentArea}',
                          );
                        } else {
                          await Future.sync(() => plateState.tabletUnsubscribeDeparture());
                          final unsubscribedArea =
                              plateState.getSubscribedArea(PlateType.departureRequests) ?? '알 수 없음';
                          showSelectedSnackbar(
                            innerCtx,
                            '⏹ [출차 요청] 구독 해제됨\n지역: $unsubscribedArea',
                          );
                        }
                      } catch (e) {
                        showFailedSnackbar(innerCtx, '작업 실패: $e');
                      } finally {
                        depBusy.value = false;
                      }
                    }

                    final headerIconBg = tint(cs.brightness == Brightness.dark ? 0.18 : 0.10);

                    final infoBg = tint(cs.brightness == Brightness.dark ? 0.12 : 0.06);
                    final infoBorder = cs.primary.withOpacity(
                      cs.brightness == Brightness.dark ? 0.28 : 0.20,
                    );

                    final sectionTitleStyle = (text.labelLarge ?? const TextStyle()).copyWith(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: headerIconBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: cs.outline.withOpacity(.10)),
                              ),
                              child: Icon(CupertinoIcons.car, color: cs.primary, size: 18),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '상단 메뉴',
                              style: (text.titleMedium ?? const TextStyle()).copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              tooltip: '닫기',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: infoBg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: infoBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.map, size: 18, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '현재 지역: ${(area.trim().isNotEmpty) ? area : "지역 없음"}',
                                          style: (text.bodyMedium ?? const TextStyle()).copyWith(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('화면 모드', style: sectionTitleStyle),
                                ),
                                const SizedBox(height: 8),

                                modeButton(
                                  target: PadMode.big,
                                  title: 'Big Pad (기본)',
                                  subtitle: '왼쪽: 출차 요청 / 오른쪽: 검색 + 키패드(하단 45%)',
                                  icon: Icons.dashboard_customize_outlined,
                                ),
                                const SizedBox(height: 8),

                                modeButton(
                                  target: PadMode.small,
                                  title: 'Small Pad',
                                  subtitle: '왼쪽 유지 / 오른쪽: 키패드가 패널 높이 100%',
                                  icon: Icons.keyboard_alt_outlined,
                                ),
                                const SizedBox(height: 8),

                                modeButton(
                                  target: PadMode.show,
                                  title: 'Show',
                                  subtitle: '왼쪽 패널만 전체 화면(출차 요청 차량만 표시)',
                                  icon: Icons.view_list_outlined,
                                ),
                                const SizedBox(height: 8),

                                // ✅ 추가: Mobile 모드
                                modeButton(
                                  target: PadMode.mobile,
                                  title: 'Mobile',
                                  subtitle: '단일 화면: 상단 입력 표시 + 하단 키패드(좌/우 패널 분할 없음)',
                                  icon: Icons.phone_iphone_outlined,
                                ),

                                const SizedBox(height: 20),

                                // ✅ [추가] 브랜드 테마 설정 버튼 (동일 버튼/로직 재사용)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('테마', style: sectionTitleStyle),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.palette_outlined),
                                    label: const Text('테마 설정(다크/색상)'),
                                    style: _accentOutlinedBtnStyle(innerCtx, minHeight: 48),
                                    onPressed: () async {
                                      Navigator.of(dialogCtx).pop();
                                      await _openThemeSettingsDialog(context);
                                    },
                                  ),
                                ),

                                const SizedBox(height: 20),

                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('음성 알림', style: sectionTitleStyle),
                                ),
                                const SizedBox(height: 8),

                                Selector<PlateState, bool>(
                                  selector: (_, s) => s.isSubscribed(PlateType.departureRequests),
                                  builder: (ctx, isSubscribedDeparture, __) {
                                    return ValueListenableBuilder<bool>(
                                      valueListenable: depBusy,
                                      builder: (_, busy, __) {
                                        final border = (isSubscribedDeparture
                                            ? cs.primary
                                            : cs.outlineVariant)
                                            .withOpacity(.85);

                                        return SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton(
                                            onPressed: busy ? null : _toggleDepartureSubscribe,
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(double.infinity, 48),
                                              backgroundColor: cs.surface,
                                              foregroundColor: cs.onSurface,
                                              side: BorderSide(color: border, width: 1.0),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ).copyWith(
                                              overlayColor: MaterialStateProperty.resolveWith<Color?>(
                                                    (states) => states.contains(MaterialState.pressed)
                                                    ? cs.primary.withOpacity(
                                                  cs.brightness == Brightness.dark ? 0.12 : 0.08,
                                                )
                                                    : null,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                if (busy)
                                                  SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        cs.primary,
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  Icon(
                                                    isSubscribedDeparture
                                                        ? Icons.notifications_active_outlined
                                                        : Icons.notifications_off_outlined,
                                                    color: cs.primary,
                                                  ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  isSubscribedDeparture ? '출차 요청 구독 해제' : '출차 요청 구독 시작',
                                                  style: (text.labelLarge ?? const TextStyle()).copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    color: cs.onSurface,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),

                                const SizedBox(height: 8),

                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: Icon(Icons.volume_up_outlined, color: cs.primary),
                                    label: Text(
                                      'TTS 설정',
                                      style: (text.labelLarge ?? const TextStyle()).copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 48),
                                      backgroundColor: cs.surface,
                                      foregroundColor: cs.onSurface,
                                      side: BorderSide(color: cs.outlineVariant.withOpacity(.85)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ).copyWith(
                                      overlayColor: MaterialStateProperty.resolveWith<Color?>(
                                            (states) => states.contains(MaterialState.pressed)
                                            ? cs.primary.withOpacity(
                                          cs.brightness == Brightness.dark ? 0.12 : 0.08,
                                        )
                                            : null,
                                      ),
                                    ),
                                    onPressed: () async {
                                      Navigator.of(dialogCtx).pop();
                                      await _openTtsFilterSheet(context);

                                      // ✅ 시트에서 토글 변경 즉시(실시간) 저장/앱/FG 동기화가 수행됩니다.
                                      // 아래는 혹시 모를 상태 불일치(예: 중간 예외) 대비용 보수적 재동기화(무음)입니다.
                                      try {
                                        await TtsSyncHelper.loadAndSync(context, showSnackbar: false);
                                      } catch (_) {}
                                    },
                                  ),
                                ),

                                const SizedBox(height: 20),

                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: Icon(Icons.logout, color: cs.primary),
                                    label: Text(
                                      '로그아웃',
                                      style: (text.labelLarge ?? const TextStyle()).copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    onPressed: () async {
                                      Navigator.of(dialogCtx).pop();
                                      await _logout(context);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 48),
                                      backgroundColor: cs.surface,
                                      foregroundColor: cs.onSurface,
                                      side: BorderSide(color: cs.outlineVariant.withOpacity(.85)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ).copyWith(
                                      overlayColor: MaterialStateProperty.resolveWith<Color?>(
                                            (states) => states.contains(MaterialState.pressed)
                                            ? cs.primary.withOpacity(
                                          cs.brightness == Brightness.dark ? 0.12 : 0.08,
                                        )
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: Text(
                              '닫기',
                              style: (text.labelLarge ?? const TextStyle()).copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    } finally {
      depBusy.dispose();
    }
  }

  Future<void> _openTtsFilterSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const TtsFilterSheet(),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: true,
      delay: const Duration(seconds: 1),
    );
  }
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
