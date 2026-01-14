// lib/screens/secondary_mode/dev_mode_package/dash_board_setting.dart
//
// 최신 트렌드(UI/UX)로 깔끔하게 리팩터링 + '서비스 로그인' 팔레트 적용:
// - 상단 Large 스타일 헤더 느낌(섹션 배너) + 얇은 구분선
// - 토널 카드(tonal)와 라운딩, 여백 정리, 더 읽기 쉬운 섹션 타이틀
// - RefreshIndicator(끌어내려 새로고침) + 마지막 동기화 시각 뱃지
// - 스위치 토글, 액션 버튼 일관된 높이/패딩
// - 스낵바는 snackbar_helper 사용
// - 잠금(LOCK) 시 시각적 오버레이, 입력 차단 유지
// - 토글 연타 방지, 비동기 예외 처리 보강
//
// ✅ 변경: "업로드 스프레드시트" / "업무 종료 보고 스프레드시트" 섹션 및 관련 로직 삭제
//
// ✅ 추가 변경(요청 반영):
// - 데이터 새로고침 시 monthly_plate_status 컬렉션에서 "현재 지역(area) 문서가 하나라도 존재하는지" 확인
// - SharedPreferences에는 지역별로 저장하지 않고, 단일 boolean 키(has_monthly_parking)만 저장
// - 문서가 없으면 false로 갱신됨(조회 성공 기준). 조회 실패 시에는 기존 값 유지(덮어쓰기 방지).
//
// ✅ 추가(이번 요청):
// - 태블릿 TTS(= 태블릿 상단 메뉴의 '출차 요청 구독' 음성 알림 토글)도 대시보드에서 같이 제어

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../states/area/area_state.dart';
import '../../../../../states/location/location_state.dart';
import '../../../../states/bill/bill_state.dart';

import '../../../../utils/tts/tts_user_filters.dart';
import '../../../../utils/tts/tts_sync_helper.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/init/logout_helper.dart';

// ✅ 태블릿 출차 요청 "구독" 토글을 대시보드에서 제어하기 위해 추가
import '../../../../states/plate/plate_state.dart';
import '../../../../enums/plate_type.dart';

/// 서비스 로그인 카드 팔레트 (일관된 브랜드 톤 적용)
class _SvcColors {
  static const base = Color(0xFF0D47A1); // primary (버튼/강조)
  static const dark = Color(0xFF09367D); // 텍스트 강조/보더
  static const light = Color(0xFF5472D3); // 톤 다운 surface
  static const fg = Color(0xFFFFFFFF); // 포그라운드
}

/// 대시보드 설정: 이 페이지에서 TTS 알림 및 각종 제어를 직접 조절합니다.
/// 잠금 스위치가 켜진 상태(true)면 본문 조작이 차단됩니다.
class DashboardSetting extends StatefulWidget {
  const DashboardSetting({super.key});

  @override
  State<DashboardSetting> createState() => _DashboardSettingState();
}

class _DashboardSettingState extends State<DashboardSetting> {
  static const _prefsLockedKey = 'dashboard_setting_locked';

  // ✅ 지역별이 아닌 "월주차 문서 존재 여부" 단일 boolean 키
  static const _prefsHasMonthlyKey = 'has_monthly_parking';

  TtsUserFilters _filters = TtsUserFilters.defaults();
  bool _loading = true;

  // TTS 적용 중(토글 연타 방지용)
  bool _applying = false;

  // 새로고침 로딩 상태
  bool _refreshing = false;

  // 화면 잠금(기본값 true)
  bool _locked = true;

  // 마지막 새로고침 시각
  DateTime? _lastRefreshAt;

  // ✅ 태블릿 출차 요청 구독 토글 연타 방지
  final ValueNotifier<bool> _tabletDepBusy = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _tabletDepBusy.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadLockState(), _load()]);
  }

  Future<void> _loadLockState() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = prefs.getBool(_prefsLockedKey);
    if (mounted) {
      setState(() => _locked = locked ?? true);
    }
  }

  Future<void> _saveLockState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsLockedKey, value);
  }

  Future<void> _load() async {
    final loaded = await TtsUserFilters.load();

    // ✅ DashboardSetting 기준: 저장 없이 앱 isolate + FG isolate 동기화만 수행
    try {
      await TtsSyncHelper.apply(
        context,
        loaded,
        save: false,
        showSnackbar: false,
      );
    } catch (e) {
      debugPrint('TTS 초기 동기화 실패: $e');
    }

    if (!mounted) return;
    setState(() {
      _filters = loaded;
      _loading = false;
    });
  }

  Future<void> _apply(TtsUserFilters next) async {
    if (_applying) return;

    setState(() {
      _filters = next;
      _applying = true;
    });

    try {
      await TtsSyncHelper.apply(
        context,
        next,
        save: true,
        showSnackbar: true,
        successMessage: 'TTS 설정이 적용되었습니다.',
      );
    } catch (e) {
      debugPrint('TTS 적용 실패: $e');
      // 실패 스낵바는 helper가 처리합니다.
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _resendToForeground() async {
    try {
      // ✅ 저장 없이 현재 메모리 필터를 앱/FG에 재동기화
      await TtsSyncHelper.apply(
        context,
        _filters,
        save: false,
        showSnackbar: false,
      );
      if (mounted) {
        showSuccessSnackbar(context, '현재 TTS 설정을 포그라운드 서비스에 재전송했습니다.');
      }
    } catch (e) {
      debugPrint('FG 재전송 실패: $e');
      if (mounted) {
        showFailedSnackbar(context, '재전송 실패: $e');
      }
    }
  }

  /// ✅ 태블릿 "출차 요청" 구독(음성 알림) 토글
  /// - TabletTopNavigation에서 제공하던 로직을 대시보드로 동일 이식
  Future<void> _setTabletDepartureSubscribe(bool enable) async {
    if (_tabletDepBusy.value) return;

    final plateState = context.read<PlateState>();
    final isSubscribed = plateState.isSubscribed(PlateType.departureRequests);

    // 이미 원하는 상태면 no-op
    if (enable == isSubscribed) return;

    _tabletDepBusy.value = true;
    try {
      if (enable) {
        await Future.sync(() => plateState.tabletSubscribeDeparture());
        final currentArea = plateState.currentArea;
        if (mounted) {
          showSuccessSnackbar(
            context,
            '✅ [출차 요청] 구독 시작됨\n지역: ${currentArea.isEmpty ? "미지정" : currentArea}',
          );
        }
      } else {
        await Future.sync(() => plateState.tabletUnsubscribeDeparture());
        final unsubscribedArea = plateState.getSubscribedArea(PlateType.departureRequests) ?? '알 수 없음';
        if (mounted) {
          showSelectedSnackbar(
            context,
            '⏹ [출차 요청] 구독 해제됨\n지역: $unsubscribedArea',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showFailedSnackbar(context, '작업 실패: $e');
      }
    } finally {
      _tabletDepBusy.value = false;
    }
  }

  /// ✅ 월주차 문서 존재 여부를 확인하고, SharedPreferences에 단일 bool로 저장
  ///
  /// - 기준: monthly_plate_status where('area' == currentArea) limit(1)
  /// - 결과:
  ///   - 조회 성공 + 문서 존재 -> true 저장
  ///   - 조회 성공 + 문서 없음 -> false 저장
  ///   - 조회 실패 -> null 반환, SharedPreferences 값은 "기존 값 유지"(덮어쓰기 방지)
  Future<bool?> _syncHasMonthlyParkingFlag() async {
    final area = context.read<AreaState>().currentArea.trim();

    // 지역이 비어있으면 "없음"으로 저장
    if (area.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsHasMonthlyKey, false);
      return false;
    }

    try {
      final qs = await FirebaseFirestore.instance
          .collection('monthly_plate_status')
          .where('area', isEqualTo: area)
          .limit(1)
          .get();

      final exists = qs.docs.isNotEmpty;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsHasMonthlyKey, exists);

      return exists;
    } catch (e) {
      debugPrint('월주차 존재 여부 확인 실패: $e');
      return null;
    }
  }

  // 주차 구역/정산 수동 새로고침
  Future<void> _manualRefreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final locationState = context.read<LocationState>();
      final billState = context.read<BillState>();

      await locationState.manualLocationRefresh();
      await billState.manualBillRefresh();

      // ✅ 추가: 새로고침 시점에 월주차 문서 존재 여부를 SharedPreferences 단일 bool로 갱신
      await _syncHasMonthlyParkingFlag();

      if (mounted) {
        setState(() => _lastRefreshAt = DateTime.now());
        showSuccessSnackbar(context, '데이터를 새로고침했습니다.');
      }
    } catch (e) {
      debugPrint('수동 새로고침 실패: $e');
      if (mounted) {
        showFailedSnackbar(context, '새로고침 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // 로그아웃
  Future<void> _logout() async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(seconds: 1),
    );
  }

  String _formatLastSync(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  // ⬇️ 좌측 상단(11시) 고정 라벨: 'Setting'
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
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: Setting',
              child: Text('Setting', style: style),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleLock() async {
    final next = !_locked;
    setState(() => _locked = next);
    await _saveLockState(next);

    if (!mounted) return;
    if (next) {
      showSelectedSnackbar(context, '화면이 잠겼습니다. (LOCK)');
    } else {
      showSuccessSnackbar(context, '잠금이 해제되었습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.select<AreaState, String>((s) => s.currentArea);

    final bodyList = <Widget>[
      const _HeaderBanner(),
      const SizedBox(height: 12),

      if (currentArea.isEmpty)
        const _Section(
          title: '지역 설정 필요',
          icon: Icons.info_outline,
          tone: _Tone.warning,
          child: Text(
            '현재 지역 정보가 비어 있습니다. FG 서비스에서 지역 기반 구독을 사용하는 경우, '
                '지역 설정 완료 후 다시 적용하세요.',
          ),
        ),

      _Section(
        title: 'TTS 알림 설정',
        icon: Icons.record_voice_over_rounded,
        subtitle: '스위치를 변경하면 즉시 저장되고 FG 서비스에 적용됩니다.',
        trailing: _applying
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
        child: Column(
          children: [
            _SwitchTile(
              title: '입차 요청',
              value: _filters.parking,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(parking: v)),
              icon: Icons.local_parking_rounded,
            ),
            const Divider(height: 1),
            _SwitchTile(
              title: '출차 요청',
              value: _filters.departure,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(departure: v)),
              icon: Icons.exit_to_app_rounded,
            ),
            const Divider(height: 1),
            _SwitchTile(
              title: '출차 완료(2회)',
              value: _filters.completed,
              onChanged: _applying ? null : (v) => _apply(_filters.copyWith(completed: v)),
              icon: Icons.done_all_rounded,
            ),
          ],
        ),
      ),

      // ✅ 추가: 태블릿 출차 요청 "구독" 음성 알림 토글을 대시보드에서도 제어
      _Section(
        title: '태블릿 음성 알림',
        icon: Icons.tablet_android_outlined,
        subtitle: '태블릿 상단 메뉴의 [출차 요청] 구독 토글과 동일한 기능입니다.',
        child: Selector<PlateState, bool>(
          selector: (_, s) => s.isSubscribed(PlateType.departureRequests),
          builder: (ctx, isSubscribedDeparture, __) {
            return ValueListenableBuilder<bool>(
              valueListenable: _tabletDepBusy,
              builder: (_, busy, __) {
                return Column(
                  children: [
                    _BusySwitchTile(
                      title: '출차 요청 구독',
                      subtitle: '태블릿에서 출차 요청을 음성으로 안내합니다.',
                      icon: isSubscribedDeparture
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      value: isSubscribedDeparture,
                      busy: busy,
                      onChanged: busy ? null : (v) => _setTabletDepartureSubscribe(v),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),

      _Section(
        title: '현재 지역',
        icon: Icons.place_outlined,
        child: Row(
          children: [
            Expanded(
              child: Text(
                currentArea.isEmpty ? '(미설정)' : currentArea,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),

            // ✅ 디자인은 FilledButton.tonalIcon 그대로 유지
            // ✅ 안정화: 버튼만 M3 컨텍스트로 보정 + width=0(minSize) edge-case 회피
            Theme(
              data: Theme.of(context).copyWith(useMaterial3: true),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: _SvcColors.light.withOpacity(.20),
                  foregroundColor: _SvcColors.dark,
                  // 기존: Size.fromHeight(44) == Size(0,44) -> 일부 환경에서 edge case 유발 가능
                  minimumSize: const Size(1, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _loading ? null : _resendToForeground,
                icon: const Icon(Icons.send),
                label: const Text('재적용'),
              ),
            ),
          ],
        ),
      ),

      _Section(
        title: '데이터 새로고침',
        icon: Icons.refresh_rounded,
        subtitle: '주차 구역/정산 데이터를 수동으로 동기화합니다.',
        trailing: _refreshing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : (_lastRefreshAt != null ? _Pill(text: '마지막: ${_formatLastSync(_lastRefreshAt!)}') : null),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loading || _refreshing ? null : _manualRefreshAll,
                icon: _refreshing
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_SvcColors.fg),
                  ),
                )
                    : const Icon(Icons.sync),
                label: const Text('지금 새로고침'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: _SvcColors.base,
                  foregroundColor: _SvcColors.fg,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),

      _Section(
        title: '로그아웃',
        icon: Icons.logout_rounded,
        tone: _Tone.danger,
        subtitle: '포그라운드 서비스를 중지하고 로그인 화면(허브 선택 경유)으로 이동합니다.',
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _logout,
                icon: const Icon(Icons.logout, color: Colors.black87),
                label: const Text('로그아웃', style: TextStyle(color: Colors.black87)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.black.withOpacity(.22)),
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ];

    final listView = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
      onRefresh: _manualRefreshAll,
      edgeOffset: 80,
      color: _SvcColors.base,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: bodyList,
      ),
    );

    final content = Stack(
      children: [
        AbsorbPointer(
          absorbing: _locked,
          child: listView,
        ),
        if (_locked)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.08),
              alignment: Alignment.center,
              child: _LockOverlay(onUnlock: _toggleLock),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('대시보드 설정'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        flexibleSpace: _buildScreenTag(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
        actions: [
          IconButton(
            tooltip: _locked ? '잠금 해제' : '잠금',
            onPressed: _loading ? null : _toggleLock,
            icon: Icon(_locked ? Icons.lock_rounded : Icons.lock_open_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: content,
    );
  }
}

enum _Tone { neutral, warning, danger }

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: _SvcColors.light.withOpacity(.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _SvcColors.light.withOpacity(.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _SvcColors.base.withOpacity(.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.tune_rounded, color: _SvcColors.dark),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '설정',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'TTS 및 주요 동기화/세션 기능을 제어합니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final _Tone tone;

  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.tone = _Tone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    Color border;
    Color bg;

    switch (tone) {
      case _Tone.warning:
        border = Colors.orange.withOpacity(.25);
        bg = Colors.orange.withOpacity(.08);
        break;
      case _Tone.danger:
        border = Colors.red.withOpacity(.22);
        bg = Colors.red.withOpacity(.06);
        break;
      case _Tone.neutral:
      default:
        border = Colors.black.withOpacity(.08);
        bg = Colors.black.withOpacity(.03);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: _SvcColors.dark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.25),
              ),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;

  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      minLeadingWidth: 24,
      leading: Icon(icon, color: Colors.black87),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
      ),
      subtitle: (subtitle == null)
          ? null
          : Text(
        subtitle!,
        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
      ),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

/// ✅ 태블릿 구독 토글용: busy 시 스피너 + 스위치 입력 차단
class _BusySwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final bool busy;
  final ValueChanged<bool>? onChanged;
  final IconData icon;

  const _BusySwitchTile({
    required this.title,
    required this.value,
    required this.busy,
    required this.onChanged,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      minLeadingWidth: 24,
      leading: Icon(icon, color: Colors.black87),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
      ),
      subtitle: (subtitle == null)
          ? null
          : Text(
        subtitle!,
        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Switch.adaptive(
            value: value,
            onChanged: busy ? null : onChanged,
          ),
        ],
      ),
      onTap: (busy || onChanged == null) ? null : () => onChanged!(!value),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(.08)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LockOverlay extends StatelessWidget {
  final VoidCallback onUnlock;

  const _LockOverlay({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withOpacity(.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.12),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _SvcColors.base.withOpacity(.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.lock_rounded, color: _SvcColors.dark),
            ),
            const SizedBox(height: 10),
            const Text(
              '잠금 상태',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            const Text(
              '설정 변경을 막기 위해 화면이 잠겨 있습니다.\n오른쪽 상단의 잠금 버튼 또는 아래 버튼으로 해제할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.25),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('잠금 해제'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: _SvcColors.base,
                  foregroundColor: _SvcColors.fg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
