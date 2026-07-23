import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/init/app_exit_service.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../app/theme/brand_theme.dart';
import '../../../../app/utils/ops_delayed_refresh_gate.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../app/theme/theme_prefs_controller.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../dev/application/area_state.dart';
import '../../../location/applications/location_state.dart';
import '../../../payment/applications/bill_state.dart';
import '../../../tablet/applications/tablet_work_session_state.dart';
import 'personal_prompt_components.dart';

class PersonalSideMenu extends StatefulWidget {
  const PersonalSideMenu({
    super.key,
    required this.onClose,
    required this.onAddVehicle,
    required this.onRefreshContent,
    required this.onOpenTodo,
    required this.onOpenCalendar,
  });

  final VoidCallback onClose;
  final Future<void> Function() onAddVehicle;
  final Future<void> Function() onRefreshContent;
  final Future<void> Function() onOpenTodo;
  final Future<void> Function() onOpenCalendar;

  @override
  State<PersonalSideMenu> createState() => _PersonalSideMenuState();
}

class _PersonalSideMenuState extends State<PersonalSideMenu> {
  static const String _prefsHasMonthlyKey = 'has_monthly_parking';

  bool _refreshing = false;
  DateTime? _lastRefreshAt;

  Future<void> _runAfterClose(Future<void> Function() action) async {
    widget.onClose();
    await Future<void>.delayed(
      personalPromptDuration(context, PromptUiMotion.selection),
    );
    await action();
  }

  Future<bool?> _syncHasMonthlyParkingFlag() async {
    final area = context.read<AreaState>().currentArea.trim();
    final prefs = await SharedPreferences.getInstance();
    if (area.isEmpty) {
      await prefs.setBool(_prefsHasMonthlyKey, false);
      return false;
    }
    try {
      final repo = context.read<PlateRepository>();
      final exists = await repo.hasMonthlyParkingByArea(area: area);
      await prefs.setBool(_prefsHasMonthlyKey, exists);
      return exists;
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal.monthly_plate_status.exists',
        error: e,
        stackTrace: st,
        usePromptUi: true,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'area': area,
          'query': 'where(area == $area).limit(1)',
          'filters': 'area == $area',
          'orderBy': 'none',
          'limit': 1,
          'queryShape': 'single-field-equality-with-limit',
          'compositeIndex': 'not-required-for-this-shape-unless-console-error-requires-it',
        },
      );
      return null;
    }
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    final debugArea = context.read<AreaState>().currentArea.trim();
    setState(() => _refreshing = true);
    try {
      final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
        context: context,
        title: '데이터 갱신',
        message: '내 차량, 위치, 정산 데이터를 다시 불러오기 전 요청을 준비하고 있습니다.',
        usePromptUi: true,
      );
      if (!shouldRefresh || !mounted) return;

      await context.read<LocationState>().manualLocationRefresh();
      await context.read<BillState>().manualBillRefresh();
      await _syncHasMonthlyParkingFlag();
      await widget.onRefreshContent();
      if (!mounted) return;
      setState(() => _lastRefreshAt = DateTime.now());
      _showSnack('데이터를 갱신했습니다.', success: true);
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal.sideMenu.refreshAll',
        error: e,
        stackTrace: st,
        usePromptUi: true,
        details: <String, Object?>{
          'area': debugArea,
          'steps': 'locations.manualLocationRefresh, bill.manualBillRefresh, monthly_plate_status.exists, onRefreshContent',
        },
      );
      if (!mounted) return;
      _showSnack('데이터 갱신 중 오류가 발생했습니다.', success: false);
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
    }
  }

  Future<void> _openThemeSettingsDialog() async {
    await showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Consumer<ThemePrefsController>(
          builder: (ctx, themeCtrl, _) {
            final cs = Theme.of(ctx).colorScheme;
            final tokens = PromptUiTheme.of(ctx);
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
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
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
                        '브랜드 테마 컬러를 개인형 화면 전체에 적용합니다.',
                        style: text.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '테마 모드',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: modes.map((m) {
                          final selected = m.id == themeCtrl.themeModeId;
                          return AnimatedScale(
                            scale: selected ? 1.03 : 1,
                            duration: personalPromptDuration(
                              ctx,
                              PromptUiMotion.selection,
                            ),
                            curve: PromptUiMotion.standard,
                            child: ChoiceChip(
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
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
                      const SizedBox(height: 14),
                      Text(
                        '테마 색',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: presets.map((p) {
                          final selected = p.id == themeCtrl.presetId;
                          return AnimatedScale(
                            scale: selected ? 1.03 : 1,
                            duration: personalPromptDuration(
                              ctx,
                              PromptUiMotion.selection,
                            ),
                            curve: PromptUiMotion.standard,
                            child: ChoiceChip(
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
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                PromptButton(
                  label: '닫기',
                  variant: PromptButtonVariant.tertiary,
                  minHeight: 40,
                  haptic: PromptHaptic.selection,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    var accountId = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      accountId = (prefs.getString('personalAccountId') ?? '').trim();
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

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.selector, (route) => false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('개인형 로그아웃이 완료되었습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal.sideMenu.logout',
        error: e,
        stackTrace: st,
        usePromptUi: true,
        details: <String, Object?>{
          'collection': 'personal_accounts',
          'accountId': accountId,
          'write': 'doc(accountId).set(isSaved=false,lastLogoutAt,updatedAt,merge)',
          'queryShape': 'direct-document-write',
          'compositeIndex': 'not-required',
        },
      );
      if (!mounted) return;
      _showSnack('로그아웃 중 오류가 발생했습니다.', success: false);
    }
  }

  Future<void> _exitApp() async {
    final work = context.read<TabletWorkSessionState>();
    await work.stopWork();
    if (!mounted) return;
    await AppExitService.exitApp(context, usePromptUi: true);
  }

  void _showSnack(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final tokens = PromptUiTheme.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? tokens.success : tokens.danger,
      ),
    );
  }

  String _formatLastSync(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final area = context.select<AreaState, String>(
      (state) => state.currentArea,
    ).trim();
    final themeCtrl = context.watch<ThemePrefsController>();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      elevation: 0,
      shadowColor: tokens.shadow,
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius: BorderRadius.circular(
                        PromptUiShapes.control,
                      ),
                      border: Border.all(
                        color: tokens.accent.withOpacity(.24),
                      ),
                    ),
                    child: Icon(
                      Icons.dashboard_customize_rounded,
                      color: tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '메뉴',
                          style: textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AnimatedSwitcher(
                          duration: personalPromptDuration(
                            context,
                            PromptUiMotion.selection,
                          ),
                          child: Text(
                            area.isEmpty ? '이용 지점 확인 중' : area,
                            key: ValueKey<String>(area),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PromptIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '메뉴 닫기',
                    onPressed: widget.onClose,
                    haptic: PromptHaptic.selection,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.borderSubtle),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(14, 14, 14, 18 + bottom),
                children: <Widget>[
                  PromptButton(
                    label: '차량 추가',
                    icon: Icons.add_rounded,
                    expand: true,
                    haptic: PromptHaptic.light,
                    onPressed: () => _runAfterClose(widget.onAddVehicle),
                  ),
                  const SizedBox(height: 10),
                  _MenuTile(
                    icon: Icons.refresh_rounded,
                    title: _refreshing ? '데이터 갱신 중' : '데이터 갱신',
                    subtitle: _lastRefreshAt == null
                        ? '내 차량, 위치, 정산 데이터를 다시 불러옵니다'
                        : '마지막 동기화 ${_formatLastSync(_lastRefreshAt!)}',
                    trailing: _refreshing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.statusSynchronized,
                            ),
                          )
                        : null,
                    onTap: _refreshing ? null : _refreshAll,
                  ),
                  const SizedBox(height: 8),
                  const _MenuSectionLabel(label: '바로가기'),
                  _MenuTile(
                    icon: Icons.checklist_rounded,
                    title: '할 일 관리',
                    subtitle: '오늘 할 일과 차량 메모를 관리',
                    onTap: () => _runAfterClose(widget.onOpenTodo),
                  ),
                  _MenuTile(
                    icon: Icons.calendar_month_rounded,
                    title: '달력 관리',
                    subtitle: '일정과 날짜별 할 일을 함께 확인',
                    onTap: () => _runAfterClose(widget.onOpenCalendar),
                  ),
                  const SizedBox(height: 12),
                  const _MenuSectionLabel(label: '설정'),
                  _MenuTile(
                    icon: Icons.palette_outlined,
                    title: '테마 설정',
                    subtitle: '현재 ${_themeModeLabel(themeCtrl.themeModeId)}',
                    onTap: () => _runAfterClose(_openThemeSettingsDialog),
                  ),
                  _MenuTile(
                    icon: Icons.power_settings_new_rounded,
                    title: '앱 사용 종료',
                    subtitle: '개인형 홈을 종료 상태로 저장',
                    onTap: () => _runAfterClose(_exitApp),
                  ),
                  _MenuTile(
                    icon: Icons.logout_rounded,
                    title: '로그아웃',
                    subtitle: '개인형 계정을 이 기기에서 해제',
                    danger: true,
                    onTap: () => _runAfterClose(_logout),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _themeModeLabel(String id) {
    return themeModeSpecs().firstWhere((m) => m.id == id, orElse: () => themeModeSpecs().first).label;
  }
}

class _MenuSectionLabel extends StatelessWidget {
  const _MenuSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: PromptAnimatedReveal(
        duration: personalPromptDuration(
          context,
          PromptUiMotion.selection,
        ),
        offset: const Offset(0, 0.08),
        child: Text(
          label,
          style: text.labelLarge?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final fg = danger ? tokens.danger : tokens.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: personalPromptDuration(context),
          curve: PromptUiMotion.standard,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: danger ? tokens.dangerContainer : tokens.accentContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: fg, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyMedium?.copyWith(
                        color: danger ? tokens.danger : tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ?? Icon(Icons.chevron_right_rounded, color: tokens.iconSecondary),
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
      width: 34,
      height: 16,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 9.0,
              top: 2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: shown[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
