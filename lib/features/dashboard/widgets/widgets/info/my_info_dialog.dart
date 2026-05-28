import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../account/applications/user_state.dart';

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
  static const List<String> _days = ['월', '화', '수', '목', '금', '토', '일'];
  static const String _kStartMapKey = 'startTimeByWeekday';
  static const String _kEndMapKey = 'endTimeByWeekday';

  bool _loading = true;
  String? _savingDay;

  String _name = '';
  String _phone = '';
  String _area = '';
  String _division = '';
  String _role = '';
  String _position = '';

  Map<String, TimeOfDay?> _startByDay = <String, TimeOfDay?>{};
  Map<String, TimeOfDay?> _endByDay = <String, TimeOfDay?>{};

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

  Map<String, TimeOfDay?> _fillAllDays(TimeOfDay? t) {
    final out = <String, TimeOfDay?>{};
    for (final d in _days) {
      out[d] = t;
    }
    return out;
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

    final name = ((cached['name'] as String?) ?? '').trim();
    final phoneFromCached = ((cached['phone'] as String?) ?? '').trim();
    final phone = prefsPhone.isNotEmpty ? prefsPhone : phoneFromCached;

    var startMap = _readDayTimeMapFromPrefs(prefs, _kStartMapKey);
    var endMap = _readDayTimeMapFromPrefs(prefs, _kEndMapKey);

    if (startMap.isEmpty) {
      final legacyStart = (prefs.getString('startTime') ?? '').trim();
      startMap = _fillAllDays(_parseHHmm(legacyStart));
    } else {
      for (final d in _days) {
        startMap.putIfAbsent(d, () => null);
      }
    }

    if (endMap.isEmpty) {
      final legacyEnd = (prefs.getString('endTime') ?? '').trim();
      endMap = _fillAllDays(_parseHHmm(legacyEnd));
    } else {
      for (final d in _days) {
        endMap.putIfAbsent(d, () => null);
      }
    }

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

  Future<void> _clearWeeklyTime(String day) async {
    if (_savingDay != null) return;
    await _saveWeeklyTime(day: day, startTime: null, endTime: null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget header() {
      return Row(
        children: [
          Icon(Icons.person_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '내 정보',
              style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
          ),
        ],
      );
    }

    final body = _loading
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
            ),
          )
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
              _WeeklyWorkTimeCard(
                days: _days,
                startByDay: _startByDay,
                endByDay: _endByDay,
                savingDay: _savingDay,
                formatTime: _formatTime,
                onPickStart: (d) => _pickWeeklyTime(day: d, isStart: true),
                onPickEnd: (d) => _pickWeeklyTime(day: d, isStart: false),
                onClearDay: _clearWeeklyTime,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    backgroundColor: cs.surface.withOpacity(0.22),
                    textStyle: (tt.labelLarge ?? const TextStyle(fontSize: 14)).copyWith(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('닫기'),
                ),
              ),
            ],
          );

    return Dialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                header(),
                const SizedBox(height: 10),
                body,
              ],
            ),
          ),
        ),
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
    final cs = Theme.of(context).colorScheme;

    String safe(String v) => v.trim().isEmpty ? '-' : v.trim();
    final title = safe(name);
    final sub = position.trim().isNotEmpty ? position.trim() : safe(role);

    return Card(
      elevation: 0,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.85)),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '근무자 정보',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: cs.primary,
                  child: Icon(Icons.person, color: cs.onPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.qr_code, color: cs.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: cs.outlineVariant.withOpacity(.85), height: 1),
            const SizedBox(height: 12),
            _InfoRow(icon: Icons.phone, value: phone),
            _InfoRow(icon: Icons.location_on, value: area),
            _InfoRow(icon: Icons.apartment_rounded, value: division),
          ],
        ),
      ),
    );
  }
}

class _WeeklyWorkTimeCard extends StatelessWidget {
  final List<String> days;
  final Map<String, TimeOfDay?> startByDay;
  final Map<String, TimeOfDay?> endByDay;
  final String? savingDay;
  final String Function(TimeOfDay? t) formatTime;
  final Future<void> Function(String day) onPickStart;
  final Future<void> Function(String day) onPickEnd;
  final Future<void> Function(String day) onClearDay;

  const _WeeklyWorkTimeCard({
    required this.days,
    required this.startByDay,
    required this.endByDay,
    required this.savingDay,
    required this.formatTime,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onClearDay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final btnStyle = OutlinedButton.styleFrom(
      foregroundColor: cs.onSurface,
      side: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      backgroundColor: cs.surface.withOpacity(0.22),
      textStyle: (tt.labelLarge ?? const TextStyle(fontSize: 14)).copyWith(fontWeight: FontWeight.w800),
    );

    Widget dayRow(String d) {
      final st = startByDay[d];
      final et = endByDay[d];
      final isSaving = savingDay == d;
      final isHoliday = st == null && et == null;
      final hasPartial = (st == null) != (et == null);
      final badgeBg = isHoliday ? cs.secondaryContainer.withOpacity(0.55) : cs.surfaceContainerHigh.withOpacity(0.55);
      final badgeFg = isHoliday ? cs.onSecondaryContainer : cs.onSurface.withOpacity(0.78);
      final badgeBorder = hasPartial ? cs.error.withOpacity(0.75) : cs.outlineVariant.withOpacity(0.55);
      final status = hasPartial ? '시간 확인 필요' : isHoliday ? '휴무' : '${formatTime(st)} ~ ${formatTime(et)}';
      final clearVisible = !isHoliday || hasPartial;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    d,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: badgeFg,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: hasPartial ? cs.error : cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSaving)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton(
                      onPressed: isSaving ? null : () => onPickStart(d),
                      style: btnStyle,
                      child: Text('출근  ${formatTime(st)}'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton(
                      onPressed: isSaving ? null : () => onPickEnd(d),
                      style: btnStyle,
                      child: Text('퇴근  ${formatTime(et)}'),
                    ),
                  ),
                ),
                if (clearVisible) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 38,
                    child: TextButton.icon(
                      onPressed: isSaving ? null : () => onClearDay(d),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('휴무'),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.error,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: (tt.labelMedium ?? const TextStyle(fontSize: 12)).copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (hasPartial) ...[
              const SizedBox(height: 6),
              Text(
                '출근/퇴근 시간을 모두 입력하거나 휴무로 설정해 주세요.',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.error,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.85)),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '근무 시간(요일별)',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '휴무 요일은 출근/퇴근 시간을 모두 비워 저장할 수 있습니다.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final d in days) dayRow(d),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String value;

  const _InfoRow({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = value.trim().isNotEmpty ? value.trim() : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
