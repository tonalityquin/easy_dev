import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../utils/init/work_schedule_prefs.dart';

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


  String _weekdayLabelFromNow() {
    final w = DateTime.now().weekday;
    switch (w) {
      case DateTime.monday:
        return '월';
      case DateTime.tuesday:
        return '화';
      case DateTime.wednesday:
        return '수';
      case DateTime.thursday:
        return '목';
      case DateTime.friday:
        return '금';
      case DateTime.saturday:
        return '토';
      case DateTime.sunday:
        return '일';
      default:
        return '월';
    }
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

  String _encodeDayTimeMap(Map<String, TimeOfDay?> m) {
    final out = <String, String>{};
    for (final d in _days) {
      final v = m[d];
      if (v == null) continue;
      out[d] = _formatTime(v);
    }
    return jsonEncode(out);
  }

  Map<String, TimeOfDay?> _readDayTimeMapFromPrefs(SharedPreferences prefs, String key) {
    final raw = (prefs.getString(key) ?? '').trim();
    if (raw.isEmpty) return <String, TimeOfDay?>{};
    final decoded = _decodeJsonMap(raw);
    final out = <String, TimeOfDay?>{};
    for (final d in _days) {
      final v = decoded[d];
      if (v is String) out[d] = _parseHHmm(v);
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

  Map<String, int>? _timeToMap(TimeOfDay? t) {
    if (t == null) return null;
    return <String, int>{'hour': t.hour, 'minute': t.minute};
  }

  TimeOfDay? _pickLegacyValue(Map<String, TimeOfDay?> m) {
    final today = _weekdayLabelFromNow();
    final t = m[today];
    if (t != null) return t;
    final mon = m['월'];
    if (mon != null) return mon;
    for (final d in _days) {
      final v = m[d];
      if (v != null) return v;
    }
    return null;
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

  Future<void> _refreshReminderUsingPrefs(SharedPreferences prefs) async {
    await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
  }

  Future<void> _persistDayTimeMaps({
    required SharedPreferences prefs,
    required Map<String, TimeOfDay?> startMap,
    required Map<String, TimeOfDay?> endMap,
  }) async {
    final startJson = _encodeDayTimeMap(startMap);
    final endJson = _encodeDayTimeMap(endMap);

    await WorkSchedulePrefs.saveScheduleToPrefs(
      prefs: prefs,
      startByDay: startMap,
      endByDay: endMap,
      fixedHolidays: const <String>[],
    );

    final legacyStart = _pickLegacyValue(startMap);
    final legacyEnd = _pickLegacyValue(endMap);

    final cachedJson = prefs.getString('cachedUserJson') ?? '';
    final cached = _decodeJsonMap(cachedJson);

    cached['startTimeByWeekday'] = jsonDecode(startJson);
    cached['endTimeByWeekday'] = jsonDecode(endJson);
    cached['startTime'] = _timeToMap(legacyStart);
    cached['endTime'] = _timeToMap(legacyEnd);
    cached['fixedHolidays'] = const <String>[];

    await prefs.setString('cachedUserJson', jsonEncode(cached));
  }

  Future<void> _pickWeeklyTime({
    required String day,
    required bool isStart,
  }) async {
    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ??
        (isStart ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 18, minute: 0));

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? '출근 시간 선택 ($day)' : '퇴근 시간 선택 ($day)',
      confirmText: '확인',
      cancelText: '취소',
    );

    if (!mounted) return;
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = picked;
      } else {
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = picked;
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await _persistDayTimeMaps(prefs: prefs, startMap: _startByDay, endMap: _endByDay);

    if (!isStart) {
      await _refreshReminderUsingPrefs(prefs);
    }
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
              style: (tt.titleMedium ?? const TextStyle(fontSize: 16))
                  .copyWith(fontWeight: FontWeight.w800, color: cs.onSurface),
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
          formatTime: _formatTime,
          onPickStart: (d) => _pickWeeklyTime(day: d, isStart: true),
          onPickEnd: (d) => _pickWeeklyTime(day: d, isStart: false),
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
              textStyle: (tt.labelLarge ?? const TextStyle(fontSize: 14))
                  .copyWith(fontWeight: FontWeight.w800),
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
  final String Function(TimeOfDay? t) formatTime;
  final Future<void> Function(String day) onPickStart;
  final Future<void> Function(String day) onPickEnd;

  const _WeeklyWorkTimeCard({
    required this.days,
    required this.startByDay,
    required this.endByDay,
    required this.formatTime,
    required this.onPickStart,
    required this.onPickEnd,
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

      final badgeBg = cs.surfaceContainerHigh.withOpacity(0.55);
      final badgeFg = cs.onSurface.withOpacity(0.78);
      final badgeBorder = cs.outlineVariant.withOpacity(0.55);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
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
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: OutlinedButton(
                        onPressed: () => onPickStart(d),
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
                        onPressed: () => onPickEnd(d),
                        style: btnStyle,
                        child: Text('퇴근  ${formatTime(et)}'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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