// lib/screens/secondary_package/office_mode_package/back_end_controller.dart
//
// UI/UX 리팩터링 + '서비스 로그인' 팔레트 컬러 반영:
// - 헤더 배너 추가(브랜드 톤)
// - 토널(tonal) 카드 느낌의 컨테이너 + 라운딩/보더 정리
// - 스위치 activeColor/아이콘/보조 텍스트 컬러 일치
// - 토글 중에는 스피너로 상태 표시(중복 동작 방지)
// - 잠금(LOCK) 시 입력 차단 + 오버레이 유지
// - ⬅️ 11시 라벨 추가: "subscribe"
//
// 동작은 기존과 동일합니다.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../utils/snackbar_helper.dart';

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

  @override
  void initState() {
    super.initState();
    _loadLockState();
  }

  Future<void> _loadLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = prefs.getBool(_prefsLockedKey);
    if (mounted) setState(() => _locked = locked ?? true);
  }

  Future<void> _saveLockState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLockedKey, value);
  }

  bool _isBusy(PlateType t) => _busy.contains(t);
  void _setBusy(PlateType t, bool v) {
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
      child: IgnorePointer( // 제스처 간섭 방지
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

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();

    // 구독 대상에서 '입차 완료' 제거
    final List<PlateType> subscribableTypes =
    PlateType.values.where((t) => t != PlateType.parkingCompleted).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '실시간 컨트롤러',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        // ⬅️ 11시 라벨을 AppBar 영역에 고정
        flexibleSpace: _buildScreenTag(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
        actions: [
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
              ],
            ),
          ),
        ],
      ),
      body: Stack(
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
                          // subscribeType 이 동기/비동기 모두 안전하게 감싸기
                          await Future.sync(() => plateState.subscribeType(type));
                          final currentArea = plateState.currentArea;
                          showSuccessSnackbar(
                            context,
                            '✅ [$typeLabel] 구독 시작됨\n지역: $currentArea',
                          );
                        } else {
                          final unsubscribedArea =
                              plateState.getSubscribedArea(type) ?? '알 수 없음';
                          await Future.sync(() => plateState.unsubscribeType(type));
                          // 안내성(중립) 메시지로 노란 스낵바
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
      ),
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
