// lib/time_record/work_day_summary.dart

/// 하루 단위 근무 요약.
/// - date: 'YYYY-MM-DD' 형식(로컬 날짜)
/// - foregroundSeconds: 앱이 화면에 떠 있을 때(포그라운드) 누적 초
/// - backgroundSeconds: 앱이 백그라운드/다른 앱 사용하는 동안 누적 초
class WorkDaySummary {
  final String date; // e.g. '2025-02-16'
  final int foregroundSeconds;
  final int backgroundSeconds;

  const WorkDaySummary({
    required this.date,
    required this.foregroundSeconds,
    required this.backgroundSeconds,
  });

  int get totalSeconds => foregroundSeconds + backgroundSeconds;

  /// 포그라운드 HH:MM:SS
  String get foregroundHms => _formatHms(foregroundSeconds);

  /// 백그라운드 HH:MM:SS
  String get backgroundHms => _formatHms(backgroundSeconds);

  /// 전체 HH:MM:SS
  String get totalHms => _formatHms(totalSeconds);

  WorkDaySummary copyWith({
    String? date,
    int? foregroundSeconds,
    int? backgroundSeconds,
  }) {
    return WorkDaySummary(
      date: date ?? this.date,
      foregroundSeconds: foregroundSeconds ?? this.foregroundSeconds,
      backgroundSeconds: backgroundSeconds ?? this.backgroundSeconds,
    );
  }

  factory WorkDaySummary.fromMap(Map<String, Object?> map) {
    return WorkDaySummary(
      date: map['date'] as String,
      foregroundSeconds: (map['fg_secs'] as int?) ?? 0,
      backgroundSeconds: (map['bg_secs'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    final nowIso = DateTime.now().toIso8601String();
    return {
      'date': date,
      'fg_secs': foregroundSeconds,
      'bg_secs': backgroundSeconds,
      'created_at': nowIso,
      'updated_at': nowIso,
    };
  }

  @override
  String toString() {
    return 'WorkDaySummary(date=$date, fg=$foregroundSeconds, bg=$backgroundSeconds)';
  }
}

/// seconds → HH:MM:SS
String _formatHms(int secs) {
  if (secs <= 0) return '00:00:00';
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  final s = secs % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}
