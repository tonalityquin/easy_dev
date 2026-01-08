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

  static const warnBg = Color(0xFFFFF3E0);
  static const warnBorder = Color(0xFFFFB74D);
  static const okBg = Color(0xFFE8F5E9);
  static const okBorder = Color(0xFF81C784);
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
          ? _DevAuthGate(onLogin: _openDevLogin)
          : _buildControllerBody(context, subscribableTypes),
    );
  }

  Widget _buildControllerBody(BuildContext context, List<PlateType> subscribableTypes) {
    final plateState = context.watch<PlateState>();
    final enabled = plateState.isEnabled;

    return Stack(
      children: [
        // 잠금 시 입력 차단
        IgnorePointer(
          ignoring: _locked,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const _HeaderBanner(),
              const SizedBox(height: 10),

              _EngineStatusBanner(
                enabled: enabled,
                desiredCount: plateState.desiredSubscriptionCount,
                activeCount: plateState.activeSubscriptionCount,
                currentArea: plateState.currentArea,
              ),
              const SizedBox(height: 12),

              // 타입별 구독 카드
              for (final type in subscribableTypes)
                _SubscribeTile(
                  title: _getTypeLabel(type),
                  subtitle: _buildTileSubtitle(plateState, type),
                  icon: _iconForType(type),

                  // ✅ “실제 구독(Active)” 기준으로 스위치 표시
                  active: plateState.isActivelySubscribed(type),

                  busy: _isBusy(type),

                  // ✅ 엔진 OFF면 토글 자체를 비활성화(혼선 제거)
                  onChanged: !enabled
                      ? null
                      : (value) async {
                    final typeLabel = _getTypeLabel(type);
                    _setBusy(type, true);
                    try {
                      if (value) {
                        await Future.sync(() => plateState.subscribeType(type));

                        // subscribeType이 실제로 구독을 열지 못한 경우(비정상/경계 상황) 방어
                        if (!plateState.isActivelySubscribed(type)) {
                          showFailedSnackbar(
                            context,
                            '[$typeLabel] 구독을 시작할 수 없습니다.\n(현재 상태/지역을 확인해 주세요)',
                          );
                          return;
                        }

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
              child: const Center(child: _LockedBanner()),
            ),
          ),
      ],
    );
  }

  Widget? _buildTileSubtitle(PlateState plateState, PlateType type) {
    final enabled = plateState.isEnabled;
    final active = plateState.isActivelySubscribed(type);
    final area = plateState.getSubscribedArea(type);

    if (!enabled) {
      return const Text(
        '현재 PlateState 엔진이 OFF 입니다.\n(Lite/본사 화면에서는 실시간 구독이 중지됩니다.)',
        style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.25),
      );
    }

    if (active) {
      return Text(
        '지역: ${area ?? "알 수 없음"}',
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      );
    }

    return const Text(
      '미구독',
      style: TextStyle(fontSize: 13, color: Colors.black54),
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

class _EngineStatusBanner extends StatelessWidget {
  const _EngineStatusBanner({
    required this.enabled,
    required this.desiredCount,
    required this.activeCount,
    required this.currentArea,
  });

  final bool enabled;
  final int desiredCount;
  final int activeCount;
  final String currentArea;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? _SvcColors.okBg : _SvcColors.warnBg;
    final border = enabled ? _SvcColors.okBorder : _SvcColors.warnBorder;
    final icon = enabled ? Icons.play_circle_fill : Icons.pause_circle_filled;
    final title = enabled ? 'PlateState 엔진: ON' : 'PlateState 엔진: OFF';
    final desc = enabled
        ? '실제 구독(Stream listen)이 실행됩니다.'
        : 'Lite/본사 화면에서는 실시간 구독이 중지됩니다.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _SvcColors.dark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _SvcColors.dark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.25),
                ),
                const SizedBox(height: 6),
                Text(
                  '원하는 구독: $desiredCount개 · 실제 활성 구독: $activeCount개 · area: $currentArea',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
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

  /// ✅ null이면 스위치 비활성화
  final ValueChanged<bool>? onChanged;

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
