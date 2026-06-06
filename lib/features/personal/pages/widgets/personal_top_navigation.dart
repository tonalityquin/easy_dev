import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/init/app_exit_service.dart';
import '../../../../app/theme/brand_theme.dart';
import '../../../../app/theme/theme_prefs_controller.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../dev/application/area_state.dart';
import '../../../location/applications/location_state.dart';
import '../../../payment/applications/bill_state.dart';
import '../../../tablet/applications/tablet_work_session_state.dart';

class PersonalTopNavigation extends StatefulWidget {
  final bool isAreaSelectable;

  const PersonalTopNavigation({
    super.key,
    this.isAreaSelectable = true,
  });

  @override
  State<PersonalTopNavigation> createState() => _PersonalTopNavigationState();
}

class _PersonalTopNavigationState extends State<PersonalTopNavigation> {
  static const String _prefsHasMonthlyKey = 'has_monthly_parking';

  bool _refreshing = false;
  DateTime? _lastRefreshAt;

  Color _tintOnSurface(ColorScheme cs, double opacity) {
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  ButtonStyle _accentOutlinedBtnStyle(BuildContext context,
      {double minHeight = 48}) {
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

  String _formatLastSync(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<bool?> _syncHasMonthlyParkingFlag() async {
    final area = context.read<AreaState>().currentArea.trim();

    if (area.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsHasMonthlyKey, false);
      return false;
    }

    try {
      final repo = context.read<PlateRepository>();
      final exists = await repo.hasMonthlyParkingByArea(area: area);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsHasMonthlyKey, exists);

      return exists;
    } catch (e) {
      debugPrint('개인형 월주차 존재 여부 확인 실패: $e');
      return null;
    }
  }

  Future<void> _manualRefreshAll({
    StateSetter? setDialogState,
    BuildContext? dialogContext,
  }) async {
    if (_refreshing) return;

    void refreshDialog() {
      if (dialogContext != null && dialogContext.mounted) {
        setDialogState?.call(() {});
      }
    }

    setState(() => _refreshing = true);
    refreshDialog();

    try {
      final locationState = context.read<LocationState>();
      final billState = context.read<BillState>();

      await locationState.manualLocationRefresh();
      await billState.manualBillRefresh();
      await _syncHasMonthlyParkingFlag();

      if (!mounted) return;

      setState(() => _lastRefreshAt = DateTime.now());
      refreshDialog();
      debugPrint('개인형 데이터를 새로고침했습니다.');
    } catch (e) {
      debugPrint('개인형 수동 새로고침 실패: $e');
      if (!mounted) return;
      refreshDialog();
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
      refreshDialog();
    }
  }

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
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
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
                        '테마 모드와 색 프리셋을 선택하면 앱 전체에 즉시 적용됩니다.',
                        style: text.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
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
                      Divider(
                          height: 1, color: cs.outlineVariant.withOpacity(0.7)),
                      const SizedBox(height: 14),
                      Text(
                        '테마 색(프리셋)',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final accountId = (prefs.getString('personalAccountId') ?? '').trim();

    if (accountId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('personal_accounts').doc(accountId).set(
        <String, dynamic>{
          'isSaved': false,
          'lastLogoutAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await prefs.remove('mode');
    await prefs.remove('phone');
    await prefs.remove('selectedArea');
    await prefs.remove('division');
    await prefs.remove('role');
    await prefs.remove('position');
    await prefs.remove('personalAccountId');
    await prefs.remove('personalName');
    await prefs.remove('personalPhone');
    await prefs.remove('personalEmail');

    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
      (route) => false,
    );
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('개인형 로그아웃이 완료되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openTopNavDialog(BuildContext context) async {
    final selectedArea = context.read<AreaState>().currentArea.trim();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (innerCtx, setSB) {
            final cs = Theme.of(innerCtx).colorScheme;
            final text = Theme.of(innerCtx).textTheme;
            final workState = innerCtx.watch<TabletWorkSessionState>();
            final themeCtrl = innerCtx.watch<ThemePrefsController>();
            final area = selectedArea.trim();

            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: cs.surface,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.of(dialogCtx).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _tintOnSurface(cs, 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '개인형 메뉴',
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '현재 지역: ${area.isNotEmpty ? area : "지역 없음"}',
                                  style: text.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '닫기',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          final navigator = Navigator.of(dialogCtx);
                          final work = context.read<TabletWorkSessionState>();
                          HapticFeedback.selectionClick();
                          await work.stopWork();
                          navigator.pop();
                          await Future<void>.delayed(
                            const Duration(milliseconds: 32),
                          );
                          if (!context.mounted) return;
                          await AppExitService.exitApp(context);
                        },
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('업무 종료'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        workState.isActive
                            ? '개인형 사용 종료 상태를 저장한 뒤 앱 종료 절차를 실행합니다.'
                            : '현재 개인형 사용이 종료된 상태입니다.',
                        style: text.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
                      const SizedBox(height: 18),
                      Text(
                        '개인형 화면',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _tintOnSurface(cs, 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outline.withOpacity(.14)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.phone_iphone_rounded, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '모바일 단일 화면으로 번호판 검색과 출차 요청 기능만 사용합니다.',
                                style: text.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            Icon(Icons.check_circle_rounded, color: cs.primary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
                      const SizedBox(height: 18),
                      Text(
                        '테마',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: _accentOutlinedBtnStyle(context),
                        icon: const Icon(Icons.palette_outlined),
                        label: Text(
                          '테마 설정 · ${_themeModeLabel(themeCtrl.themeModeId)}',
                        ),
                        onPressed: () async {
                          Navigator.of(dialogCtx).pop();
                          await _openThemeSettingsDialog(context);
                        },
                      ),
                      const SizedBox(height: 18),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
                      const SizedBox(height: 18),
                      Text(
                        '데이터 새로고침',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _lastRefreshAt == null
                            ? '주차 구역/정산 데이터를 수동으로 동기화합니다.'
                            : '마지막 동기화: ${_formatLastSync(_lastRefreshAt!)}',
                        style: text.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _refreshing
                            ? null
                            : () => _manualRefreshAll(
                                  setDialogState: setSB,
                                  dialogContext: innerCtx,
                                ),
                        icon: _refreshing
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    cs.onPrimary,
                                  ),
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(_refreshing ? '새로고침 중...' : '지금 새로고침'),
                      ),
                      const SizedBox(height: 18),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        icon: Icon(Icons.logout, color: cs.primary),
                        label: Text(
                          '로그아웃',
                          style: text.labelLarge?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: cs.primary.withOpacity(.75)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.of(dialogCtx).pop();
                          await _logout(context);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedArea = context.select<AreaState, String>((s) => s.currentArea);
    final label = selectedArea.trim().isNotEmpty ? selectedArea.trim() : '지역 없음';

    return Material(
      color: cs.surface,
      child: InkWell(
        onTap: widget.isAreaSelectable ? () => _openTopNavDialog(context) : null,
        child: Container(
          height: kToolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _tintOnSurface(cs, 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.phone_iphone_rounded,
                  color: cs.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '개인형',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.isAreaSelectable) ...[
                          const SizedBox(width: 4),
                          Icon(CupertinoIcons.chevron_down,
                              size: 14, color: cs.onSurfaceVariant),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '개인형 메뉴',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: widget.isAreaSelectable
                    ? () => _openTopNavDialog(context)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetPreviewDots extends StatelessWidget {
  const _PresetPreviewDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = colors.isEmpty ? <Color>[cs.primary] : colors.take(3).toList();

    return SizedBox(
      width: 38,
      height: 16,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 11.0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: shown[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.8),
                    width: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
