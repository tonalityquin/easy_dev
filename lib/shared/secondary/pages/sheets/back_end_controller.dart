import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/snackbar_helper.dart';
import '../../../../features/dev/page/sheets/dev_quick_actions.dart';
import '../../../../features/selector/application/dev_auth.dart';
import '../../../../features/selector/sheets/service_bottom_sheet.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../application/secondary_state.dart';
import '../../widgets/ops_console_dialogs.dart';
import '../../widgets/ops_console_widgets.dart';

class BackEndController extends StatefulWidget {
  const BackEndController({super.key});

  @override
  State<BackEndController> createState() => _BackEndControllerState();
}

class _BackEndControllerState extends State<BackEndController> {
  bool _checkingDevAuth = true;
  bool _devAuthorized = false;
  bool _rebuildingMonthlyView = false;

  @override
  void initState() {
    super.initState();
    _loadDevAuth();
  }

  Future<void> _loadDevAuth() async {
    final devAuthorized = await DevAuth.isDeveloperLoggedIn();
    if (!mounted) return;
    setState(() {
      _devAuthorized = devAuthorized;
      _checkingDevAuth = false;
    });
  }

  Future<void> _openServiceSettings() async {
    final before = _devAuthorized;
    await ServiceBottomSheet.show(context: context);
    if (!mounted) return;
    await _loadDevAuth();
    if (!mounted) return;
    final state = context.read<SecondaryState>();
    await state.refreshDeveloperLogin();
    if (!mounted) return;
    if (!before && _devAuthorized) {
      showSuccessSnackbar(
        context,
        '개발자 모드가 활성화되었습니다.',
        usePromptUi: true,
      );
    }
  }

  Future<void> _resetDevAuthInline() async {
    await DevQuickActions.disableDeveloperMode();
    if (!mounted) return;
    setState(() {
      _devAuthorized = false;
      _checkingDevAuth = false;
    });
    showSelectedSnackbar(
      context,
      '개발자 모드가 비활성화되었습니다.',
      usePromptUi: true,
    );
    final state = context.read<SecondaryState>();
    await state.refreshDeveloperLogin();
  }

  Future<void> _rebuildMonthlyPlateStatusViews() async {
    if (_rebuildingMonthlyView) return;
    final ok = await showOpsConfirmDialog(
      context: context,
      title: '정기 주차 View 전체 재생성',
      message:
          'monthly_plate_status 원본 기준으로 monthly_plate_status_view 지역별 문서를 생성하거나 덮어씁니다. 계속하시겠습니까?',
      confirmLabel: '실행',
      icon: Icons.sync_alt_rounded,
    );
    if (!ok || !mounted) return;

    setState(() => _rebuildingMonthlyView = true);
    try {
      final result = await context
          .read<PlateRepository>()
          .rebuildAllMonthlyPlateStatusViews();
      if (!mounted) return;
      showSuccessSnackbar(
        context,
        '정기 주차 View 재생성 완료: 지역 ${result.areaCount}개 / 정기권 ${result.itemCount}건 / 건너뜀 ${result.skippedCount}건 / 삭제 ${result.deletedViewCount}건',
        usePromptUi: true,
      );
    } catch (error) {
      if (!mounted) return;
      showFailedSnackbar(
        context,
        '정기 주차 View 재생성에 실패했습니다. ${error.toString()}',
        usePromptUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _rebuildingMonthlyView = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).colorScheme;
    final statusColor = _devAuthorized ? tokens.primary : tokens.error;
    return OpsConsoleScaffold(
      title: '실시간 컨트롤러',
      subtitle: '개발자 인증과 운영 데이터 유지보수 기능을 관리합니다.',
      icon: Icons.settings_ethernet_rounded,
      loading: _checkingDevAuth || _rebuildingMonthlyView,
      metrics: [
        OpsMetric(
          label: '개발자 모드',
          value: _checkingDevAuth
              ? '확인 중'
              : _devAuthorized
                  ? '활성'
                  : '비활성',
          icon: _devAuthorized
              ? Icons.verified_user_rounded
              : Icons.lock_outline_rounded,
          color: statusColor,
        ),
        OpsMetric(
          label: 'View 작업',
          value: _rebuildingMonthlyView ? '실행 중' : '대기',
          icon: Icons.sync_alt_rounded,
          color: _rebuildingMonthlyView ? tokens.primary : tokens.onSurfaceVariant,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          OpsWorkSection(
            title: '실시간 구독 상태',
            subtitle: 'PlateState 스냅샷 구독 기능은 제거된 상태입니다.',
            icon: Icons.cloud_off_rounded,
            child: const Text(
              'Firestore QuerySnapshot 기반 실시간 구독 로직을 사용하지 않습니다. 이 화면은 개발자 인증과 관리 작업만 제공합니다.',
            ),
          ),
          OpsWorkSection(
            title: '개발자 모드',
            subtitle: '서비스 설정 접근 권한과 개발 도구 표시 상태를 제어합니다.',
            icon: _devAuthorized
                ? Icons.verified_user_rounded
                : Icons.lock_outline_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OpsInlineMessage(
                  message: _checkingDevAuth
                      ? '개발자 모드를 확인하고 있습니다.'
                      : _devAuthorized
                          ? '개발자 모드가 활성화되어 있습니다.'
                          : '개발자 모드가 비활성화되어 있습니다.',
                  danger: false,
                  icon: _devAuthorized
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                ),
                Row(
                  children: [
                    Expanded(
                      child: OpsActionButton(
                        label: '서비스 설정',
                        icon: Icons.settings_outlined,
                        onPressed: _checkingDevAuth ? null : _openServiceSettings,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OpsActionButton(
                        label: '개발자 모드 초기화',
                        icon: Icons.restart_alt_rounded,
                        onPressed: _checkingDevAuth ? null : _resetDevAuthInline,
                        tonal: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OpsWorkSection(
            title: '정기 주차 View',
            subtitle: '원본 컬렉션을 기준으로 지역별 View 문서를 다시 생성합니다.',
            icon: Icons.view_carousel_rounded,
            child: OpsActionButton(
              label: _rebuildingMonthlyView
                  ? '정기 주차 View 재생성 중'
                  : '정기 주차 View 전체 재생성',
              icon: Icons.sync_alt_rounded,
              onPressed: _checkingDevAuth ||
                      !_devAuthorized ||
                      _rebuildingMonthlyView
                  ? null
                  : _rebuildMonthlyPlateStatusViews,
            ),
          ),
        ],
      ),
    );
  }
}
