import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/area/area_state.dart';

import '../../../../common_package/memo_package/dash_memo.dart';
import '../../../../common_package/sheet_tool/fielder_document_box_sheet.dart';
import '../../../../common_package/sheet_tool/leader_document_box_sheet.dart';
import 'widgets/minor_dashboard_punch_recorder_section.dart';

import 'package:easydev/screens/common_package/camera_package/photo_transfer_mail_page.dart';
import 'package:easydev/screens/secondary_page.dart';

// ✅ [추가] 전역 테마 컨트롤러 + 브랜드 프리셋/테마모드 스펙
import '../../../../../../theme_prefs_controller.dart';
import '../../../../../../selector_hubs_package/brand_theme.dart';

class MinorHomeDashBoardBottomSheet extends StatefulWidget {
  const MinorHomeDashBoardBottomSheet({super.key});

  @override
  State<MinorHomeDashBoardBottomSheet> createState() => _MinorHomeDashBoardBottomSheetState();
}

class _MinorHomeDashBoardBottomSheetState extends State<MinorHomeDashBoardBottomSheet> {
  static const String screenTag = 'DashBoard B';

  bool _layerHidden = true;

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
        TextStyle(
          fontSize: 11,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ))
        .copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Semantics(
            label: 'screen_tag: $screenTag',
            child: Text(screenTag, style: style),
          ),
        ),
      ),
    );
  }

  bool _isFieldCommon(UserState userState) {
    final dynamic rawRole = userState.user?.role;
    final String role = rawRole is String ? rawRole.trim() : (rawRole?.toString().trim() ?? '');
    return role == 'fieldCommon';
  }

  void _onPhotoTransferPressed(BuildContext context) {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();

    rootNav.push(MaterialPageRoute(builder: (_) => const PhotoTransferMailPage()));
  }

  void _onOpenSecondaryPressed(BuildContext context) {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();

    rootNav.push(MaterialPageRoute(builder: (_) => const SecondaryPage()));
  }

  String _themeModeLabel(String id) {
    return themeModeSpecs()
        .firstWhere((m) => m.id == id, orElse: () => themeModeSpecs().first)
        .label;
  }

  /// ✅ [추가] 테마 설정(모드 + 색상 프리셋) 다이얼로그
  Future<void> _openThemeSettingsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true, // ✅ 바텀시트 위로 중앙 다이얼로그를 확실히 올림
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
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.70)),
          ),
          child: Consumer<UserState>(
            builder: (context, userState, _) {
              final areaState = context.read<AreaState>();
              final bool isFieldCommon = _isFieldCommon(userState);

              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 60,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildScreenTag(context),
                    const SizedBox(height: 16),

                    MinorDashboardPunchRecorderSection(
                      userId: userState.name,
                      userName: userState.name,
                      area: areaState.currentArea,
                      division: areaState.currentDivision,
                    ),

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(_layerHidden ? Icons.layers : Icons.layers_clear),
                        label: Text(_layerHidden ? '작업 버튼 펼치기' : '작업 버튼 숨기기'),
                        style: _outlinedSurfaceBtnStyle(context, height: 48),
                        onPressed: () => setState(() => _layerHidden = !_layerHidden),
                      ),
                    ),
                    const SizedBox(height: 16),

                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _layerHidden ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.sticky_note_2_rounded),
                              label: const Text('메모'),
                              style: _outlinedSurfaceBtnStyle(context),
                              onPressed: () async {
                                await DashMemo.init();
                                DashMemo.mountIfNeeded();
                                await DashMemo.togglePanel();
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ✅ [추가] 테마 설정(다크/색상) 버튼
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.palette_outlined),
                              label: const Text('테마 설정(다크/색상)'),
                              style: _outlinedSurfaceBtnStyle(
                                context,
                                borderColor: cs.primary.withOpacity(0.85),
                                pressedOverlayColor: cs.primary.withOpacity(0.10),
                              ),
                              onPressed: () => _openThemeSettingsDialog(context),
                            ),
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.photo_camera_back_rounded),
                              label: const Text('사진 전송'),
                              style: _outlinedSurfaceBtnStyle(context),
                              onPressed: () => _onPhotoTransferPressed(context),
                            ),
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('서류함 열기'),
                              style: _outlinedSurfaceBtnStyle(context),
                              onPressed: () {
                                if (isFieldCommon) {
                                  openFielderDocumentBox(context);
                                } else {
                                  openLeaderDocumentBox(context);
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('보조 페이지 열기'),
                              style: _outlinedSurfaceBtnStyle(context),
                              onPressed: () => _onOpenSecondaryPressed(context),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    if (_layerHidden) const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

ButtonStyle _outlinedSurfaceBtnStyle(
    BuildContext context, {
      double height = 55,
      Color? borderColor,
      Color? pressedOverlayColor,
    }) {
  final cs = Theme.of(context).colorScheme;

  final Color effectiveBorder = borderColor ?? cs.outlineVariant.withOpacity(0.85);
  final Color effectiveOverlay = pressedOverlayColor ?? cs.outlineVariant.withOpacity(0.12);

  return ElevatedButton.styleFrom(
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    minimumSize: Size.fromHeight(height),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(color: effectiveBorder, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
          (states) => states.contains(MaterialState.pressed) ? effectiveOverlay : null,
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
