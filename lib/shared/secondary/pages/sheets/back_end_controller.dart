import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/snackbar_helper.dart';
import '../../../../features/dev/page/sheets/dev_quick_actions.dart';
import '../../../../features/selector/application/dev_auth.dart';
import '../../../../features/selector/sheets/service_bottom_sheet.dart';
import '../../application/secondary_state.dart';
import '../../../plate/domain/repositories/plate_repository.dart';

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

    await ServiceBottomSheet.show(
      context: context,
    );

    if (!mounted) return;
    await _loadDevAuth();
    if (!mounted) return;

    final state = context.read<SecondaryState>();
    await state.refreshDeveloperLogin();
    if (!mounted) return;

    if (!before && _devAuthorized) {
      showSuccessSnackbar(context, '개발자 모드가 활성화되었습니다.');
    }
  }

  Future<void> _resetDevAuthInline() async {
    await DevQuickActions.disableDeveloperMode();

    if (!mounted) return;
    setState(() {
      _devAuthorized = false;
      _checkingDevAuth = false;
    });
    showSelectedSnackbar(context, '개발자 모드가 비활성화되었습니다.');

    final state = context.read<SecondaryState>();
    await state.refreshDeveloperLogin();
  }

  Future<void> _rebuildMonthlyPlateStatusViews() async {
    if (_rebuildingMonthlyView) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('정기 주차 View 전체 재생성'),
            content: const Text(
              'monthly_plate_status 원본 기준으로 monthly_plate_status_view 지역별 문서를 생성하거나 덮어씁니다. 계속하시겠습니까?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('실행'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok || !mounted) return;

    setState(() {
      _rebuildingMonthlyView = true;
    });

    try {
      final result = await context.read<PlateRepository>().rebuildAllMonthlyPlateStatusViews();
      if (!mounted) return;
      showSuccessSnackbar(
        context,
        '정기 주차 View 재생성 완료: 지역 ${result.areaCount}개 / 정기권 ${result.itemCount}건 / 건너뜀 ${result.skippedCount}건 / 삭제 ${result.deletedViewCount}건',
      );
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '정기 주차 View 재생성에 실패했습니다. ${e.toString()}');
    } finally {
      if (!mounted) return;
      setState(() {
        _rebuildingMonthlyView = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: const Text(
          '실시간 컨트롤러',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PlateState(스냅샷 구독) 기능 제거됨',
                    style: (tt.titleMedium ?? const TextStyle(fontSize: 16))
                        .copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '요구사항에 따라 Firestore QuerySnapshot 기반 실시간 구독 로직을 완전히 제거했습니다.\n이 화면은 개발자 인증/설정 진입만 제공합니다.',
                    style: (tt.bodyMedium ?? const TextStyle(fontSize: 14))
                        .copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
              ),
              child: Row(
                children: [
                  Icon(
                    _devAuthorized ? Icons.verified_user : Icons.lock_outline,
                    color: _devAuthorized ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _checkingDevAuth
                          ? '개발자 모드 확인 중...'
                          : (_devAuthorized ? '개발자 모드: 활성' : '개발자 모드: 비활성'),
                      style: (tt.bodyLarge ?? const TextStyle(fontSize: 15))
                          .copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _checkingDevAuth ? null : _openServiceSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('서비스 설정'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checkingDevAuth ? null : _resetDevAuthInline,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('개발자 모드 초기화'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _checkingDevAuth || !_devAuthorized || _rebuildingMonthlyView
                    ? null
                    : _rebuildMonthlyPlateStatusViews,
                icon: _rebuildingMonthlyView
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_alt_rounded),
                label: Text(
                  _rebuildingMonthlyView ? '정기 주차 View 재생성 중...' : '정기 주차 View 전체 재생성',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
