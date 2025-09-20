// lib/screens/head_package/hr_package/widgets/time_edit_sheet.dart
import 'package:flutter/material.dart';

/// 단일 시간(HH:mm) 입력 필드 스펙
class TimeFieldSpec {
  final String id;        // 결과 map의 key
  final String label;     // 라벨
  final String initial;   // 초기값 'HH:mm'
  const TimeFieldSpec({
    required this.id,
    required this.label,
    required this.initial,
  });
}

/// 검증 함수 시그니처: 문제가 없으면 null, 에러 메시지면 String 반환
typedef TimeSheetValidator = String? Function(Map<String, String> values);

/// 공통 바텀시트 호출 (여러 개의 시간 필드를 한 번에 입력)
Future<Map<String, String>?> showTimeEditSheet({
  required BuildContext context,
  required DateTime date,
  required List<TimeFieldSpec> fields,
  List<TimeSheetValidator> validators = const [],
  String? title,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return _TimeEditSheet(
        date: date,
        fields: fields,
        validators: validators,
        title: title,
      );
    },
  );
}

class _TimeEditSheet extends StatefulWidget {
  final DateTime date;
  final List<TimeFieldSpec> fields;
  final List<TimeSheetValidator> validators;
  final String? title;
  const _TimeEditSheet({
    required this.date,
    required this.fields,
    required this.validators,
    required this.title,
  });

  @override
  State<_TimeEditSheet> createState() => _TimeEditSheetState();
}

class _TimeEditSheetState extends State<_TimeEditSheet> {
  late final Map<String, TextEditingController> _hhCtrls;
  late final Map<String, TextEditingController> _mmCtrls;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hhCtrls = {};
    _mmCtrls = {};
    for (final f in widget.fields) {
      final parts = (f.initial.isNotEmpty ? f.initial : '00:00').split(':');
      final hh = parts.isNotEmpty ? parts[0] : '00';
      final mm = parts.length > 1 ? parts[1] : '00';
      _hhCtrls[f.id] = TextEditingController(text: hh);
      _mmCtrls[f.id] = TextEditingController(text: mm);
    }
  }

  @override
  void dispose() {
    for (final c in _hhCtrls.values) c.dispose();
    for (final c in _mmCtrls.values) c.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? _basicValidate(Map<String, String> values) {
    for (final entry in values.entries) {
      final parts = entry.value.split(':');
      if (parts.length != 2) return '시간 형식은 HH:mm 이어야 합니다.';
      final hh = int.tryParse(parts[0]);
      final mm = int.tryParse(parts[1]);
      if (hh == null || mm == null) return '숫자만 입력해 주세요.';
      if (hh < 0 || hh > 23) return '시(0~23)를 확인해 주세요.';
      if (mm < 0 || mm > 59) return '분(0~59)을 확인해 주세요.';
    }
    return null;
  }

  Future<void> _onSave() async {
    final values = <String, String>{};
    for (final f in widget.fields) {
      final hh = _hhCtrls[f.id]!.text.padLeft(2, '0');
      final mm = _mmCtrls[f.id]!.text.padLeft(2, '0');
      values[f.id] = '$hh:$mm';
    }

    _error = _basicValidate(values);
    if (_error != null) {
      setState(() {});
      return;
    }
    for (final v in widget.validators) {
      final msg = v(values);
      if (msg != null) {
        setState(() => _error = msg);
        return;
      }
    }

    if (!mounted) return;
    Navigator.pop<Map<String, String>>(context, values);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title ?? _ymd(widget.date),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              const SizedBox(height: 6),
            ],

            for (final f in widget.fields) ...[
              _TimeInputRow(
                label: f.label,
                hourCtrl: _hhCtrls[f.id]!,
                minCtrl: _mmCtrls[f.id]!,
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 20),
              label: const Text('저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              onPressed: _onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _TimeInputRow extends StatelessWidget {
  final String label;
  final TextEditingController hourCtrl;
  final TextEditingController minCtrl;
  const _TimeInputRow({
    required this.label,
    required this.hourCtrl,
    required this.minCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: TextField(
                controller: hourCtrl,
                keyboardType: TextInputType.number,
                maxLength: 2,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'HH',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(':', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                maxLength: 2,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'MM',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// -------------------------
/// 얇은 래퍼 (출퇴근/휴게)
/// -------------------------

class AttendanceTimeResult {
  final String inTime;
  final String outTime;
  const AttendanceTimeResult(this.inTime, this.outTime);
}

/// 출근/퇴근용 래퍼: 2필드 + 관계검증(출근 <= 퇴근)
Future<AttendanceTimeResult?> showAttendanceTimeSheet({
  required BuildContext context,
  required DateTime date,
  required String initialInTime,
  required String initialOutTime,
}) async {
  final result = await showTimeEditSheet(
    context: context,
    date: date,
    title:
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    fields: [
      TimeFieldSpec(id: 'in', label: '출근 시간', initial: initialInTime),
      TimeFieldSpec(id: 'out', label: '퇴근 시간', initial: initialOutTime),
    ],
    validators: [
          (m) {
        final a = m['in']!;
        final b = m['out']!;
        // 문자열 비교는 '>'를 사용할 수 없으므로 compareTo 사용
        if (a.isNotEmpty && b.isNotEmpty && a.compareTo(b) > 0) {
          return '퇴근 시간이 출근 시간보다 빠를 수 없습니다.';
        }
        return null;
      }
    ],
  );

  if (result == null) return null;
  return AttendanceTimeResult(result['in']!, result['out']!);
}

/// 휴게용 래퍼: 1필드
Future<String?> showBreakTimeSheet({
  required BuildContext context,
  required DateTime date,
  required String initialTime,
}) async {
  final res = await showTimeEditSheet(
    context: context,
    date: date,
    fields: [
      TimeFieldSpec(id: 'break', label: '휴게 시간', initial: initialTime),
    ],
  );
  if (res == null) return null;
  return res['break'];
}
