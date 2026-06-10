import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../app/init/logout_helper.dart';
import '../../../../../app/init/work_schedule_prefs.dart';
import '../../../../../app/utils/ops_delayed_refresh_gate.dart';
import '../../../../account/applications/user_state.dart';
import '../../../../dev/application/area_state.dart';
import '../../../../location/applications/location_state.dart';
import '../../../../payment/applications/bill_state.dart';

Future<void> showMyInfoDialog({required BuildContext context}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const MyInfoDialog(),
  );
}

class MyInfoDialog extends StatefulWidget {
  const MyInfoDialog({super.key});

  @override
  State<MyInfoDialog> createState() => _MyInfoDialogState();
}

class _MyInfoDialogState extends State<MyInfoDialog> {
  static const List<String> _days = WorkSchedulePrefs.days;
  static const String _kStartMapKey = WorkSchedulePrefs.startMapKey;
  static const String _kEndMapKey = WorkSchedulePrefs.endMapKey;
  static const String _prefsHasMonthlyKey = 'has_monthly_parking';

  bool _loading = true;
  String? _savingDay;
  bool _refreshing = false;
  bool? _hasMonthlyParking;
  DateTime? _lastRefreshAt;

  String _name = '';
  String _phone = '';
  String _area = '';
  String _division = '';
  String _role = '';
  String _position = '';

  Map<String, TimeOfDay?> _startByDay = <String, TimeOfDay?>{};
  Map<String, TimeOfDay?> _endByDay = <String, TimeOfDay?>{};
  Set<String> _breakDays = <String>{};

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  String _formatTime(TimeOfDay? t) {
    if (t == null) return '-';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  TimeOfDay? _parseHHmm(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  List<String> _readStringList(dynamic raw) {
    if (raw is Iterable) {
      return WorkSchedulePrefs.normalizeDayList(raw.map((value) => value.toString()));
    }
    if (raw is Map) {
      final out = <String>[];
      for (final day in _days) {
        if (raw[day] == true) out.add(day);
      }
      return out;
    }
    return const <String>[];
  }

  Map<String, TimeOfDay?> _readDayTimeMapFromPrefs(SharedPreferences prefs, String key) {
    final raw = (prefs.getString(key) ?? '').trim();
    if (raw.isEmpty) return <String, TimeOfDay?>{};
    final decoded = _decodeJsonMap(raw);
    final out = <String, TimeOfDay?>{};
    for (final d in _days) {
      final v = decoded[d];
      if (v is String) {
        out[d] = _parseHHmm(v);
      } else {
        out[d] = null;
      }
    }
    return out;
  }

  Map<String, TimeOfDay?> _fillAllDays(TimeOfDay? t, {Iterable<String> excludedDays = const <String>[]}) {
    final excluded = excludedDays.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    final out = <String, TimeOfDay?>{};
    for (final d in _days) {
      out[d] = excluded.contains(d) ? null : t;
    }
    return out;
  }

  Set<String> _workingDaySet(Map<String, TimeOfDay?> startMap, Map<String, TimeOfDay?> endMap) {
    final out = <String>{};
    for (final day in _days) {
      if (startMap[day] != null && endMap[day] != null) {
        out.add(day);
      }
    }
    return out;
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

  Future<void> _manualRefreshAll() async {
    if (_refreshing) return;

    setState(() => _refreshing = true);
    try {
      final shouldRefresh = await OpsDelayedRefreshGate.waitIfNeeded(
        context: context,
        title: '운영 데이터 동기화',
        message: '주차 구역, 정산 타입, 월정기 사용 여부를 새로고침하기 전 요청을 준비하고 있습니다.',
      );
      if (!shouldRefresh || !mounted) return;

      final locationState = context.read<LocationState>();
      final billState = context.read<BillState>();

      await locationState.manualLocationRefresh();
      await billState.manualBillRefresh();
      final monthlyFlag = await _syncHasMonthlyParkingFlag();

      if (mounted) {
        setState(() {
          _lastRefreshAt = DateTime.now();
          _hasMonthlyParking = monthlyFlag;
        });
        _showSnack('운영 데이터를 새로고침했습니다.');
      }
    } catch (e) {
      debugPrint('수동 새로고침 실패: $e');
      if (!mounted) return;
      _showSnack('운영 데이터 새로고침에 실패했습니다.');
    } finally {
      if (!mounted) return;
      setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(seconds: 1),
    );
  }

  Future<void> _loadPrefs() async {
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString('cachedUserJson') ?? '';
    final cached = _decodeJsonMap(cachedJson);

    final prefsPhone = (prefs.getString('phone') ?? '').trim();
    final prefsArea = (prefs.getString('selectedArea') ?? '').trim();
    final prefsDivision = (prefs.getString('division') ?? '').trim();
    final prefsRole = (prefs.getString('role') ?? '').trim();
    final prefsPosition = (prefs.getString('position') ?? '').trim();
    final hasMonthlyParking = prefs.getBool(_prefsHasMonthlyKey);

    final name = ((cached['name'] as String?) ?? '').trim();
    final phoneFromCached = ((cached['phone'] as String?) ?? '').trim();
    final phone = prefsPhone.isNotEmpty ? prefsPhone : phoneFromCached;
    final fixedHolidays = prefs.getStringList('fixedHolidays') ?? _readStringList(cached['fixedHolidays']);

    var startMap = _readDayTimeMapFromPrefs(prefs, _kStartMapKey);
    var endMap = _readDayTimeMapFromPrefs(prefs, _kEndMapKey);

    if (startMap.isEmpty) {
      final legacyStart = (prefs.getString('startTime') ?? '').trim();
      startMap = _fillAllDays(_parseHHmm(legacyStart), excludedDays: fixedHolidays);
    } else {
      for (final d in _days) {
        startMap.putIfAbsent(d, () => null);
      }
    }

    if (endMap.isEmpty) {
      final legacyEnd = (prefs.getString('endTime') ?? '').trim();
      endMap = _fillAllDays(_parseHHmm(legacyEnd), excludedDays: fixedHolidays);
    } else {
      for (final d in _days) {
        endMap.putIfAbsent(d, () => null);
      }
    }

    final workingDays = _workingDaySet(startMap, endMap);
    final cachedBreakDays = _readStringList(cached['breakDays']);
    final breakDays = prefs.containsKey(WorkSchedulePrefs.breakDaysKey)
        ? WorkSchedulePrefs.readBreakDaysFromPrefs(prefs)
        : (cached.containsKey('breakDays') ? cachedBreakDays : workingDays.toList(growable: false));
    final normalizedBreakDays = WorkSchedulePrefs.normalizeDayList(breakDays).where(workingDays.contains).toSet();

    if (!mounted) return;

    setState(() {
      _name = name;
      _phone = phone;
      _area = prefsArea;
      _division = prefsDivision;
      _role = prefsRole;
      _position = prefsPosition;
      _startByDay = startMap;
      _endByDay = endMap;
      _breakDays = normalizedBreakDays;
      _hasMonthlyParking = hasMonthlyParking;
      _loading = false;
    });
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveWeeklyTime({
    required String day,
    required TimeOfDay? startTime,
    required TimeOfDay? endTime,
  }) async {
    if ((startTime == null) != (endTime == null)) {
      _showSnack('출근/퇴근 시간을 모두 입력하거나 모두 비워 주세요.');
      return;
    }

    final wasHoliday = _startByDay[day] == null && _endByDay[day] == null;
    setState(() => _savingDay = day);

    final ok = await context.read<UserState>().setCurrentUserWeekdayWorkTimeLocalOnly(
      day: day,
      startTime: startTime,
      endTime: endTime,
    );

    if (!mounted) return;

    if (ok) {
      setState(() {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = startTime;
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = endTime;
        final nextBreakDays = <String>{..._breakDays};
        if (startTime == null && endTime == null) {
          nextBreakDays.remove(day);
        } else if (wasHoliday) {
          nextBreakDays.add(day);
        }
        _breakDays = nextBreakDays;
        _savingDay = null;
      });
      _showSnack(startTime == null && endTime == null ? '$day요일이 휴무로 저장되었습니다.' : '$day요일 근무 시간이 저장되었습니다.');
      return;
    }

    setState(() => _savingDay = null);
    await _loadPrefs();
    if (!mounted) return;
    _showSnack('근무 시간 저장에 실패했습니다.');
  }

  Future<void> _setHoliday(String day, bool value) async {
    if (_savingDay != null) return;
    if (value) {
      await _saveWeeklyTime(day: day, startTime: null, endTime: null);
    } else {
      await _saveWeeklyTime(
        day: day,
        startTime: _startByDay[day] ?? const TimeOfDay(hour: 9, minute: 0),
        endTime: _endByDay[day] ?? const TimeOfDay(hour: 18, minute: 0),
      );
    }
  }

  Future<void> _toggleBreakDay(String day, bool value) async {
    if (_savingDay != null) return;
    if (_startByDay[day] == null || _endByDay[day] == null) {
      _showSnack('근무 시간이 있는 요일만 휴게를 설정할 수 있습니다.');
      return;
    }

    setState(() => _savingDay = day);

    final ok = await context.read<UserState>().setCurrentUserBreakDayLocalOnly(
      day: day,
      hasBreak: value,
    );

    if (!mounted) return;

    if (ok) {
      setState(() {
        final next = <String>{..._breakDays};
        if (value) {
          next.add(day);
        } else {
          next.remove(day);
        }
        _breakDays = next;
        _savingDay = null;
      });
      _showSnack(value ? '$day요일 휴게가 설정되었습니다.' : '$day요일 휴게가 해제되었습니다.');
      return;
    }

    setState(() => _savingDay = null);
    await _loadPrefs();
    if (!mounted) return;
    _showSnack('휴게 설정 저장에 실패했습니다.');
  }

  Future<void> _pickWeeklyTime({
    required String day,
    required bool isStart,
  }) async {
    if (_savingDay != null) return;

    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ?? (isStart ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 18, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? '출근 시간 선택 ($day)' : '퇴근 시간 선택 ($day)',
      confirmText: '확인',
      cancelText: '취소',
    );

    if (!mounted) return;
    if (picked == null) return;

    final currentStart = _startByDay[day];
    final currentEnd = _endByDay[day];
    final nextStart = isStart ? picked : currentStart ?? const TimeOfDay(hour: 9, minute: 0);
    final nextEnd = isStart ? currentEnd ?? const TimeOfDay(hour: 18, minute: 0) : picked;

    await _saveWeeklyTime(day: day, startTime: nextStart, endTime: nextEnd);
  }

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final height = MediaQuery.of(context).size.height;

    Widget loadingBody() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 42),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(palette.action),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '근무자 정보를 불러오는 중입니다.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final content = _loading
        ? loadingBody()
        : Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _UserInfoCard(
          name: _name,
          position: _position,
          role: _role,
          phone: _phone,
          area: _area,
          division: _division,
        ),
        const SizedBox(height: 12),
        _OperationalDataSyncCard(
          refreshing: _refreshing,
          lastRefreshAt: _lastRefreshAt,
          hasMonthlyParking: _hasMonthlyParking,
          formatLastSync: _formatLastSync,
          onRefresh: _loading || _refreshing ? null : _manualRefreshAll,
        ),
        const SizedBox(height: 12),
        _SessionLogoutCard(
          onLogout: _loading ? null : _logout,
        ),
        const SizedBox(height: 12),
        _WeeklyWorkTimeCard(
          days: _days,
          startByDay: _startByDay,
          endByDay: _endByDay,
          breakDays: _breakDays,
          savingDay: _savingDay,
          formatTime: _formatTime,
          onPickStart: (d) => _pickWeeklyTime(day: d, isStart: true),
          onPickEnd: (d) => _pickWeeklyTime(day: d, isStart: false),
          onHolidayChanged: _setHoliday,
          onBreakChanged: _toggleBreakDay,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.ink,
              side: BorderSide(color: palette.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              backgroundColor: palette.panel,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: const Text('닫기'),
          ),
        ),
      ],
    );

    return Dialog(
      backgroundColor: palette.canvas,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogConsoleHeader(
              area: _area,
              loading: _loading,
              onClose: () => Navigator.of(context).pop(),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpsPalette {
  final Color ink;
  final Color muted;
  final Color canvas;
  final Color panel;
  final Color line;
  final Color action;
  final Color green;
  final Color amber;
  final Color red;
  final Color slate;
  final Color softLabel;
  final Color headerCard;
  final Color headerBorder;

  const _OpsPalette({
    required this.ink,
    required this.muted,
    required this.canvas,
    required this.panel,
    required this.line,
    required this.action,
    required this.green,
    required this.amber,
    required this.red,
    required this.slate,
    required this.softLabel,
    required this.headerCard,
    required this.headerBorder,
  });

  factory _OpsPalette.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseCanvas = cs.brightness == Brightness.dark ? cs.surface : const Color(0xFFF3F6FA);
    return _OpsPalette(
      ink: const Color(0xFF101828),
      muted: const Color(0xFF667085),
      canvas: Color.alphaBlend(cs.primary.withOpacity(cs.brightness == Brightness.dark ? .08 : .03), baseCanvas),
      panel: cs.surface,
      line: Color.alphaBlend(cs.primary.withOpacity(.04), cs.outlineVariant),
      action: cs.primary,
      green: const Color(0xFF059669),
      amber: const Color(0xFFD97706),
      red: cs.error,
      slate: const Color(0xFF334155),
      softLabel: const Color(0xFFB8C2D6),
      headerCard: const Color(0xFF182230),
      headerBorder: const Color(0xFF2B3A4F),
    );
  }
}

class _DialogConsoleHeader extends StatelessWidget {
  final String area;
  final bool loading;
  final VoidCallback onClose;

  const _DialogConsoleHeader({
    required this.area,
    required this.loading,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final cs = Theme.of(context).colorScheme;
    final areaLabel = area.trim().isEmpty ? '운영 지점 미설정' : '${area.trim()} 운영 콘솔';

    return Container(
      width: double.infinity,
      color: palette.ink,
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.24),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.action,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(.14)),
                ),
                child: Icon(Icons.badge_rounded, color: cs.onPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '내 정보',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loading ? '근무자 프로필을 준비하고 있습니다.' : areaLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: palette.softLabel,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                tooltip: '닫기',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserInfoCard extends StatelessWidget {
  final String name;
  final String position;
  final String role;
  final String phone;
  final String area;
  final String division;

  const _UserInfoCard({
    required this.name,
    required this.position,
    required this.role,
    required this.phone,
    required this.area,
    required this.division,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final safeName = _safeText(name);
    final positionLabel = _safeText(position);
    final roleLabel = _safeText(role);

    return _OpsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            icon: Icons.assignment_ind_rounded,
            title: '근무자 정보',
            subtitle: '계정과 현장 배정 정보를 확인합니다.',
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: palette.ink,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.headerBorder),
                ),
                child: Icon(Icons.person_rounded, color: palette.softLabel, size: 28),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      safeName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.3,
                        color: palette.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _InfoPill(icon: Icons.workspace_premium_rounded, label: '직책', value: positionLabel),
                        _InfoPill(icon: Icons.admin_panel_settings_rounded, label: '권한', value: roleLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: palette.line,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(icon: Icons.phone_rounded, label: '연락처', value: _safeText(phone), expanded: true),
              _InfoPill(icon: Icons.location_on_rounded, label: '지역', value: _safeText(area), expanded: true),
              _InfoPill(icon: Icons.apartment_rounded, label: '구역', value: _safeText(division), expanded: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _OperationalDataSyncCard extends StatelessWidget {
  final bool refreshing;
  final DateTime? lastRefreshAt;
  final bool? hasMonthlyParking;
  final String Function(DateTime dt) formatLastSync;
  final Future<void> Function()? onRefresh;

  const _OperationalDataSyncCard({
    required this.refreshing,
    required this.lastRefreshAt,
    required this.hasMonthlyParking,
    required this.formatLastSync,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final cs = Theme.of(context).colorScheme;
    final monthlyLabel = hasMonthlyParking == null ? '대기' : (hasMonthlyParking! ? '사용 중' : '미사용');
    final monthlyColor = hasMonthlyParking == null ? palette.slate : (hasMonthlyParking! ? palette.green : palette.amber);
    final lastSync = lastRefreshAt == null ? '아직 새로고침 없음' : formatLastSync(lastRefreshAt!);

    return _OpsPanel(
      accentColor: palette.action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _SectionHeading(
                  icon: Icons.sync_rounded,
                  title: '운영 데이터 동기화',
                  subtitle: '주차 구역, 정산 타입, 월정기 사용 여부를 재조회합니다.',
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(label: monthlyLabel, color: monthlyColor),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: '구역',
                  value: '재조회',
                  icon: Icons.local_parking_rounded,
                  color: palette.action,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: '정산',
                  value: '재조회',
                  icon: Icons.receipt_long_rounded,
                  color: palette.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: '월정기',
                  value: monthlyLabel,
                  icon: Icons.event_available_rounded,
                  color: monthlyColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InlineMetaRow(
            icon: Icons.schedule_rounded,
            label: '마지막 동기화',
            value: lastSync,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: onRefresh,
              icon: refreshing
                  ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
                ),
              )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(refreshing ? '새로고침 중' : '지금 새로고침'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: palette.action,
                foregroundColor: cs.onPrimary,
                disabledBackgroundColor: cs.surfaceVariant,
                disabledForegroundColor: cs.onSurfaceVariant.withOpacity(.58),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionLogoutCard extends StatelessWidget {
  final Future<void> Function()? onLogout;

  const _SessionLogoutCard({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final cs = Theme.of(context).colorScheme;

    return _OpsPanel(
      accentColor: palette.red,
      borderColor: palette.red.withOpacity(.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _SectionHeading(
                  icon: Icons.logout_rounded,
                  title: '세션 종료',
                  subtitle: '포그라운드 서비스를 중지하고 로그인 화면으로 이동합니다.',
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(label: '위험 액션', color: palette.red),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.red.withOpacity(.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.red.withOpacity(.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: palette.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '현재 작업 세션을 종료하고 인증 정보를 정리합니다.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: palette.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('로그아웃'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: palette.red,
                foregroundColor: cs.onError,
                disabledBackgroundColor: cs.surfaceVariant,
                disabledForegroundColor: cs.onSurfaceVariant.withOpacity(.58),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyWorkTimeCard extends StatelessWidget {
  final List<String> days;
  final Map<String, TimeOfDay?> startByDay;
  final Map<String, TimeOfDay?> endByDay;
  final Set<String> breakDays;
  final String? savingDay;
  final String Function(TimeOfDay? t) formatTime;
  final Future<void> Function(String day) onPickStart;
  final Future<void> Function(String day) onPickEnd;
  final Future<void> Function(String day, bool value) onHolidayChanged;
  final Future<void> Function(String day, bool value) onBreakChanged;

  const _WeeklyWorkTimeCard({
    required this.days,
    required this.startByDay,
    required this.endByDay,
    required this.breakDays,
    required this.savingDay,
    required this.formatTime,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onHolidayChanged,
    required this.onBreakChanged,
  });

  int get _workingCount {
    var count = 0;
    for (final day in days) {
      if (startByDay[day] != null && endByDay[day] != null) count++;
    }
    return count;
  }

  int get _holidayCount => days.length - _workingCount;

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);

    return _OpsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            icon: Icons.schedule_rounded,
            title: '근무 시간(요일별)',
            subtitle: '휴무와 휴게 여부를 요일 단위로 관리합니다.',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: '근무',
                  value: '$_workingCount일',
                  icon: Icons.work_history_rounded,
                  color: palette.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: '휴무',
                  value: '$_holidayCount일',
                  icon: Icons.event_busy_rounded,
                  color: palette.slate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: '휴게',
                  value: '${breakDays.length}일',
                  icon: Icons.coffee_rounded,
                  color: palette.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final day in days) ...[
            _WorkDayRow(
              day: day,
              startTime: startByDay[day],
              endTime: endByDay[day],
              hasBreak: breakDays.contains(day),
              isSaving: savingDay == day,
              formatTime: formatTime,
              onPickStart: () => onPickStart(day),
              onPickEnd: () => onPickEnd(day),
              onHolidayChanged: (value) => onHolidayChanged(day, value),
              onBreakChanged: (value) => onBreakChanged(day, value),
            ),
            if (day != days.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _WorkDayRow extends StatelessWidget {
  final String day;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final bool hasBreak;
  final bool isSaving;
  final String Function(TimeOfDay? t) formatTime;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final Future<void> Function(bool value) onHolidayChanged;
  final Future<void> Function(bool value) onBreakChanged;

  const _WorkDayRow({
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.hasBreak,
    required this.isSaving,
    required this.formatTime,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onHolidayChanged,
    required this.onBreakChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final isHoliday = startTime == null && endTime == null;
    final hasPartial = (startTime == null) != (endTime == null);
    final effectiveBreak = hasBreak && !isHoliday && !hasPartial;
    final statusColor = hasPartial ? palette.red : (isHoliday ? palette.slate : palette.green);
    final statusLabel = hasPartial ? '확인 필요' : (isHoliday ? '휴무' : '근무');
    final timeLabel = hasPartial
        ? '출근/퇴근 시간을 모두 입력해 주세요.'
        : isHoliday
        ? '근무 시간 없음'
        : '${formatTime(startTime)} ~ ${formatTime(endTime)} · ${effectiveBreak ? '휴게 있음' : '휴게 없음'}';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hasPartial ? palette.red.withOpacity(.45) : palette.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: statusColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor.withOpacity(.25)),
                          ),
                          child: Text(
                            day,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: palette.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                timeLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  fontWeight: FontWeight.w800,
                                  color: hasPartial ? palette.red : palette.muted,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isSaving)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.3,
                              valueColor: AlwaysStoppedAnimation<Color>(palette.action),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TimeActionButton(
                            label: '출근',
                            value: formatTime(startTime),
                            enabled: !isSaving,
                            onPressed: onPickStart,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TimeActionButton(
                            label: '퇴근',
                            value: formatTime(endTime),
                            enabled: !isSaving,
                            onPressed: onPickEnd,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: _OpsTogglePill(
                            label: '휴무',
                            icon: Icons.event_busy_rounded,
                            selected: isHoliday,
                            enabled: !isSaving,
                            color: palette.slate,
                            onChanged: onHolidayChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _OpsTogglePill(
                            label: '휴게',
                            icon: Icons.coffee_rounded,
                            selected: effectiveBreak,
                            enabled: !isSaving && !isHoliday && !hasPartial,
                            color: palette.amber,
                            onChanged: onBreakChanged,
                          ),
                        ),
                      ],
                    ),
                    if (hasPartial) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: palette.red.withOpacity(.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.red.withOpacity(.18)),
                        ),
                        child: Text(
                          '출근/퇴근 시간을 모두 입력하거나 휴무로 설정해 주세요.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: palette.red,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpsPanel extends StatelessWidget {
  final Widget child;
  final Color? accentColor;
  final Color? borderColor;

  const _OpsPanel({
    required this.child,
    this.accentColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? palette.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accentColor != null) Container(width: 6, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: palette.ink,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: palette.softLabel),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.2,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF182230),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2B3A4F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: palette.softLabel,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool expanded;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(palette.action.withOpacity(.025), palette.panel),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: palette.slate),
          const SizedBox(width: 7),
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: palette.muted,
            ),
          ),
          Flexible(
            child: Text(
              _safeText(value),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: palette.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (!expanded) return content;
    return SizedBox(
      width: 170,
      child: content,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _InlineMetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InlineMetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(palette.action.withOpacity(.025), palette.panel),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.slate, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: palette.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: palette.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeActionButton extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onPressed;

  const _TimeActionButton({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          disabledForegroundColor: palette.muted.withOpacity(.55),
          backgroundColor: palette.panel,
          side: BorderSide(color: palette.line),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpsTogglePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final Color color;
  final Future<void> Function(bool value) onChanged;

  const _OpsTogglePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _OpsPalette.of(context);
    final fg = selected ? color : palette.muted;
    final bg = selected ? color.withOpacity(.10) : palette.panel;
    final border = selected ? color.withOpacity(.25) : palette.line;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () async { await onChanged(!selected); } : null,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: enabled ? bg : Color.alphaBlend(palette.muted.withOpacity(.06), palette.panel),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: enabled ? border : palette.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: enabled ? fg : palette.muted.withOpacity(.55)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: enabled ? fg : palette.muted.withOpacity(.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _safeText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '-' : trimmed;
}
