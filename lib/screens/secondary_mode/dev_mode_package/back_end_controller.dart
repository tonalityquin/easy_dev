// lib/screens/secondary_mode/dev_mode_package/back_end_controller.dart
//
// ✅ 변경 사항(Dev Auth Gate 추가)
// - BackEndController 진입 시 DevAuth.restorePrefs()로 개발자 인증 여부 확인
// - devAuthorized == false 이면, 컨트롤 UI 대신 "개발자 인증 필요" 게이트 화면 표시
// - 게이트 화면에서 DevLoginBottomSheet 호출 → 성공 시 DevAuth.setDevAuthorized(true) 저장 후 즉시 활성화
// - 초기화(Reset)도 동일하게 DevLoginBottomSheet의 onReset으로 처리 가능
//
// ✅ 추가 수정(요청 사항)
// - AppBar의 자동 뒤로가기(leading) 아이콘이 보이지 않도록:
//   automaticallyImplyLeading: false + leading/leadingWidth를 명시

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../utils/snackbar_helper.dart';

// ✅ Dev Auth / Dev Login BottomSheet
import '../../../../selector_hubs_package/dev_auth.dart';
import '../../../../selector_hubs_package/dev_login_bottom_sheet.dart';

/// 서비스 로그인 카드 팔레트 (일관된 브랜드 톤)
class _SvcColors {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 텍스트/아이콘 강조
  static const light = Color(0xFF5472D3); // 서브톤/보더
  static const fg = Color(0xFFFFFFFF);
}

class BackEndController extends StatefulWidget {
  const BackEndController({super.key});

  @override
  State<BackEndController> createState() => _BackEndControllerState();
}

class _BackEndControllerState extends State<BackEndController> {
  static const _prefsLockedKey = 'backend_controller_locked';

  // 기본값 true: 잠금 상태에서 시작
  bool _locked = true;

  // 타입별 Busy 상태(중복 토글 방지)
  final Set<PlateType> _busy = {};

  // ✅ Dev Auth Gate
  bool _checkingDevAuth = true;
  bool _devAuthorized = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadLockState(),
      _loadDevAuth(),
    ]);
  }

  Future<void> _loadDevAuth() async {
    try {
      final restored = await DevAuth.restorePrefs(); // TTL 만료 처리 포함
      if (!mounted) return;
      setState(() {
        _devAuthorized = restored.devAuthorized;
        _checkingDevAuth = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _devAuthorized = false;
        _checkingDevAuth = false;
      });
    }
  }

  Future<void> _loadLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = prefs.getBool(_prefsLockedKey);
    if (!mounted) return;
    setState(() => _locked = locked ?? true);
  }

  Future<void> _saveLockState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLockedKey, value);
  }

  bool _isBusy(PlateType t) => _busy.contains(t);

  void _setBusy(PlateType t, bool v) {
    if (!mounted) return;
    setState(() {
      if (v) {
        _busy.add(t);
      } else {
        _busy.remove(t);
      }
    });
  }

  // ⬇️ 좌측 상단(11시) 고정 라벨: 'subscribe'
  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer(
        // 제스처 간섭 방지
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: subscribe',
              child: Text('subscribe', style: style),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDevLogin() async {
    bool success = false;
    bool didReset = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return DevLoginBottomSheet(
          onSuccess: (id, pw) async {
            await DevAuth.setDevAuthorized(true);
            success = true;
            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          },
          onReset: () async {
            await DevAuth.resetDevAuth();
            didReset = true;
            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          },
        );
      },
    );

    if (!mounted) return;

    // 상태 재반영(만료/정리 포함)
    await _loadDevAuth();

    if (!mounted) return;

    if (success) {
      showSuccessSnackbar(context, '개발자 인증이 완료되었습니다.');
    } else if (didReset) {
      showSelectedSnackbar(context, '개발자 인증이 초기화되었습니다.');
    }
  }

  Future<void> _resetDevAuthInline() async {
    await DevAuth.resetDevAuth();
    if (!mounted) return;
    await _loadDevAuth();
    if (!mounted) return;
    showSelectedSnackbar(context, '개발자 인증이 초기화되었습니다.');
  }

  @override
  Widget build(BuildContext context) {
    // 구독 대상에서 '입차 완료' 제거
    final List<PlateType> subscribableTypes =
    PlateType.values.where((t) => t != PlateType.parkingCompleted).toList();

    return Scaffold(
      appBar: AppBar(
        // ✅ 뒤로가기(leading) 자동 표시 방지
        automaticallyImplyLeading: false,
        leading: const SizedBox.shrink(),
        leadingWidth: 0,

        title: const Text(
          '실시간 컨트롤러',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        flexibleSpace: _buildScreenTag(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
        actions: [
          if (_checkingDevAuth)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (!_devAuthorized)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Dev 로그인',
                onPressed: _openDevLogin,
                icon: const Icon(Icons.admin_panel_settings),
                color: _SvcColors.dark,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Icon(_locked ? Icons.lock : Icons.lock_open, color: _SvcColors.dark),
                  Switch.adaptive(
                    activeColor: _SvcColors.base,
                    value: _locked, // true면 잠금
                    onChanged: (v) async {
                      setState(() => _locked = v);
                      await _saveLockState(v);
                    },
                  ),
                  PopupMenuButton<String>(
                    tooltip: '옵션',
                    onSelected: (v) async {
                      if (v == 'reset_dev_auth') {
                        await _resetDevAuthInline();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'reset_dev_auth',
                        child: Text('개발자 인증 해제'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),

      // ✅ Dev Auth Gate 적용
      body: _checkingDevAuth
          ? const Center(child: CircularProgressIndicator())
          : (!_devAuthorized)
          ? _DevAuthGate(
        onLogin: _openDevLogin,
      )
          : _buildControllerBody(context, subscribableTypes),
    );
  }

  Widget _buildControllerBody(BuildContext context, List<PlateType> subscribableTypes) {
    final plateState = context.watch<PlateState>();

    return Stack(
      children: [
        // 잠금 시 입력 차단
        IgnorePointer(
          ignoring: _locked,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const _HeaderBanner(),
              const SizedBox(height: 12),

              // 타입별 구독 카드
              for (final type in subscribableTypes)
                _SubscribeTile(
                  title: _getTypeLabel(type),
                  subtitle: _buildSubscribedAreaText(plateState, type),
                  icon: _iconForType(type),
                  active: plateState.isSubscribed(type),
                  busy: _isBusy(type),
                  onChanged: (value) async {
                    final typeLabel = _getTypeLabel(type);
                    _setBusy(type, true);
                    try {
                      if (value) {
                        await Future.sync(() => plateState.subscribeType(type));
                        final currentArea = plateState.currentArea;
                        showSuccessSnackbar(
                          context,
                          '✅ [$typeLabel] 구독 시작됨\n지역: $currentArea',
                        );
                      } else {
                        final unsubscribedArea = plateState.getSubscribedArea(type) ?? '알 수 없음';
                        await Future.sync(() => plateState.unsubscribeType(type));
                        showSelectedSnackbar(
                          context,
                          '⏹ [$typeLabel] 구독 해제됨\n지역: $unsubscribedArea',
                        );
                      }
                    } catch (e) {
                      showFailedSnackbar(context, '작업 실패: $e');
                    } finally {
                      _setBusy(type, false);
                    }
                  },
                ),
            ],
          ),
        ),

        // 잠금 상태 시 시각적 오버레이
        if (_locked)
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.6),
              child: const Center(
                child: _LockedBanner(),
              ),
            ),
          ),
      ],
    );
  }

  Widget? _buildSubscribedAreaText(PlateState plateState, PlateType type) {
    final subscribedArea = plateState.getSubscribedArea(type);
    if (subscribedArea == null) return null;
    return Text(
      '지역: $subscribedArea',
      style: const TextStyle(fontSize: 13, color: Colors.black54),
    );
  }

  IconData _iconForType(PlateType type) {
    switch (type) {
      case PlateType.parkingRequests:
        return Icons.local_parking_rounded;
      case PlateType.departureRequests:
        return Icons.exit_to_app_rounded;
      case PlateType.departureCompleted:
        return Icons.done_all_rounded;
      case PlateType.parkingCompleted:
        return Icons.check_circle_outline; // 사용 안 함(필터됨)
    }
  }

  String _getTypeLabel(PlateType type) {
    switch (type) {
      case PlateType.parkingRequests:
        return '입차 요청';
      case PlateType.parkingCompleted:
        return '입차 완료';
      case PlateType.departureRequests:
        return '출차 요청';
      case PlateType.departureCompleted:
        return '출차 완료 (미정산만)';
    }
  }
}

/// ===================================
/// Dev Auth Gate UI
/// ===================================

class _DevAuthGate extends StatelessWidget {
  const _DevAuthGate({required this.onLogin});

  final Future<void> Function() onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _SvcColors.light.withOpacity(.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _SvcColors.light.withOpacity(.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _SvcColors.light.withOpacity(.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.admin_panel_settings, color: _SvcColors.dark, size: 28),
                ),
                const SizedBox(height: 12),
                const Text(
                  '개발자 인증이 필요합니다',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _SvcColors.dark),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  '해당 페이지 사용은 제한되어 있습니다.',
                  style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.35),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onLogin,
                    icon: const Icon(Icons.login),
                    label: const Text('개발자 로그인', style: TextStyle(fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _SvcColors.base,
                      foregroundColor: _SvcColors.fg,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===================================
/// UI 파츠
/// ===================================

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _SvcColors.light.withOpacity(.95),
            _SvcColors.base.withOpacity(.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _SvcColors.dark.withOpacity(.18)),
      ),
      child: Row(
        children: const [
          Icon(Icons.cloud_sync_outlined, color: _SvcColors.fg),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '근태 문서 관련 알림을 타입별로 구독/해제할 수 있습니다.',
              style: TextStyle(
                color: _SvcColors.fg,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscribeTile extends StatelessWidget {
  const _SubscribeTile({
    required this.title,
    required this.icon,
    required this.active,
    required this.busy,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final bool active;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: _SvcColors.light.withOpacity(.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _SvcColors.light.withOpacity(.35)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _SvcColors.light.withOpacity(.22),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: _SvcColors.dark, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _SvcColors.dark,
          ),
        ),
        subtitle: subtitle,
        trailing: busy
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Switch.adaptive(
          value: active,
          activeColor: _SvcColors.base,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.lock, size: 48, color: Colors.black54),
        SizedBox(height: 8),
        Text(
          '화면이 잠금 상태입니다',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4),
        Text('오른쪽 상단 스위치를 끄면 조작할 수 있어요'),
      ],
    );
  }
}
