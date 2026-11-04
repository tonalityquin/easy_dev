import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/init/work_schedule_prefs.dart';
import '../../../shared/operational_cache/data/local/operational_cache_database.dart';
import '../../../shared/operational_cache/data/repositories/sqlite_operational_local_repository.dart';
import '../../../shared/parking_spatial/parking_spatial_hierarchy.dart';
import '../../rule/applications/work_rule_report_loader.dart';
import '../page/hot_keys/single_inside_hot_key_content.dart';
import 'single_attendance_submission_summary_service.dart';
import 'single_inside_diagnostics.dart';

class SingleInsideHotKeySummary {
  const SingleInsideHotKeySummary({
    required this.status,
    required this.primary,
    required this.secondary,
  });

  final String status;
  final String primary;
  final String secondary;
}

class SingleInsideHotKeySummaryLoader {
  SingleInsideHotKeySummaryLoader._();

  static const String _startSpecialKey = 'start_report_draft_has_special_note';
  static const String _startContentKey = 'start_report_draft_content';
  static const String _endVehicleKey =
      'single_inside_end_report_draft_vehicle_count';
  static const String _endSpecialKey =
      'single_inside_end_report_draft_has_special_note';
  static const String _endContentKey =
      'single_inside_end_report_draft_content';

  static Future<SingleInsideHotKeySummary> load({
    required SingleInsideHotKeyContent content,
    required String division,
    required String area,
  }) async {
    try {
      late final SingleInsideHotKeySummary summary;
      switch (content) {
        case SingleInsideHotKeyContent.parkingArea:
          summary = await _loadParkingArea(area: area);
          break;
        case SingleInsideHotKeyContent.workSchedule:
          summary = await _loadWorkSchedule();
          break;
        case SingleInsideHotKeyContent.workRules:
          summary = await _loadRule(
            division: division,
            area: area,
            manual: false,
          );
          break;
        case SingleInsideHotKeyContent.workManual:
          summary = await _loadRule(
            division: division,
            area: area,
            manual: true,
          );
          break;
        case SingleInsideHotKeyContent.workStartReport:
          summary = await _loadStartReport();
          break;
        case SingleInsideHotKeyContent.workEndReport:
          summary = await _loadEndReport();
          break;
        case SingleInsideHotKeyContent.commuteSubmit:
          summary = await _loadSubmission(
            SingleAttendanceSubmissionKind.commute,
          );
          break;
        case SingleInsideHotKeyContent.restTimeSubmit:
          summary = await _loadSubmission(
            SingleAttendanceSubmissionKind.restTime,
          );
          break;
      }
      SingleInsideDiagnostics.log(
        'hotkey',
        'summary_loaded content=${content.name} status=${summary.status} primary=${summary.primary.replaceAll(' ', '_')} secondaryLength=${summary.secondary.length}',
      );
      return summary;
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'hotkey',
        'summary_failure content=${content.name} error=$error stack=$stackTrace',
      );
      return const SingleInsideHotKeySummary(
        status: '확인 필요',
        primary: '상태를 불러오지 못했습니다',
        secondary: '카드를 눌러 상세 내용을 확인할 수 있습니다.',
      );
    }
  }

  static Future<SingleInsideHotKeySummary> _loadParkingArea({
    required String area,
  }) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) {
      return const SingleInsideHotKeySummary(
        status: '확인 필요',
        primary: '현재 근무지 정보 없음',
        secondary: '근무지 정보를 확인해 주세요.',
      );
    }
    final locations = await SqliteOperationalLocalRepository(
      OperationalCacheDatabase.instance,
    ).readLocations(normalizedArea);
    final hierarchy = resolveParkingSpatialHierarchy(locations);
    var parentCount = 0;
    var childCount = 0;
    var capacity = 0;
    for (final group in hierarchy) {
      final parent = group.parentSource;
      final grid = parent?.parkingGrid;
      if (parent == null || grid == null || grid.rows <= 0 || grid.cols <= 0) {
        continue;
      }
      parentCount++;
      childCount += group.children.length;
      for (final child in group.children) {
        capacity += parkingSpatialCapacityForChild(child);
      }
    }
    if (parentCount == 0) {
      return const SingleInsideHotKeySummary(
        status: '미등록',
        primary: '등록된 주차 구역 없음',
        secondary: '주차 구역에서 상세 내용을 확인할 수 있습니다.',
      );
    }
    return SingleInsideHotKeySummary(
      status: '준비됨',
      primary: '구역 $parentCount개',
      secondary: childCount > 0
          ? '세부 $childCount곳 · 주차면 $capacity개'
          : '세부 주차 구역 없음',
    );
  }

  static Future<SingleInsideHotKeySummary> _loadWorkSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final hadStored = WorkSchedulePrefs.hasStoredSchedulePrefs(prefs);
    if (hadStored) {
      await WorkSchedulePrefs.migrateLegacySchedulePrefs(prefs);
    }
    final startByDay = WorkSchedulePrefs.readDayTimeMapFromPrefs(
      prefs,
      WorkSchedulePrefs.startMapKey,
    );
    final endByDay = WorkSchedulePrefs.readDayTimeMapFromPrefs(
      prefs,
      WorkSchedulePrefs.endMapKey,
    );
    var workingDays = 0;
    for (final day in WorkSchedulePrefs.days) {
      if (startByDay[day] != null && endByDay[day] != null) {
        workingDays++;
      }
    }
    final now = DateTime.now();
    final today = WorkSchedulePrefs.days[now.weekday - 1];
    final start = startByDay[today];
    final end = endByDay[today];
    final secondary = start != null && end != null
        ? '오늘 ${WorkSchedulePrefs.formatTime(start)}~${WorkSchedulePrefs.formatTime(end)}'
        : start == null && end == null
            ? '오늘 휴무'
            : '오늘 일정 확인 필요';
    return SingleInsideHotKeySummary(
      status: hadStored ? '설정됨' : '미설정',
      primary: workingDays > 0 ? '주 $workingDays일' : '근무일 없음',
      secondary: secondary,
    );
  }

  static Future<SingleInsideHotKeySummary> _loadRule({
    required String division,
    required String area,
    required bool manual,
  }) async {
    final result = await WorkRuleReportLoader.load(
      localRepository: SqliteOperationalLocalRepository(
        OperationalCacheDatabase.instance,
      ),
      division: division,
      area: area,
      onDebug: (message) => SingleInsideDiagnostics.log('hotkey', message),
    );
    final updated = result.updatedAt == null
        ? '갱신 정보 없음'
        : '최근 갱신 ${DateFormat('MM.dd').format(result.updatedAt!)}';
    if (manual) {
      final count = result.responseManualPages.length;
      return SingleInsideHotKeySummary(
        status: count > 0 ? '준비됨' : '미등록',
        primary: count > 0 ? '$count 페이지' : '등록된 메뉴얼 없음',
        secondary: updated,
      );
    }
    final items = _splitNoticeItems(result.content);
    final first = items.isEmpty ? '' : items.first;
    return SingleInsideHotKeySummary(
      status: result.contentAvailable ? '등록됨' : '미등록',
      primary: result.contentAvailable ? '안내 ${items.length}개' : '등록된 규칙 없음',
      secondary: first.isNotEmpty ? first : updated,
    );
  }

  static Future<SingleInsideHotKeySummary> _loadStartReport() async {
    final prefs = await SharedPreferences.getInstance();
    final special = prefs.getBool(_startSpecialKey);
    final content = (prefs.getString(_startContentKey) ?? '').trim();
    final hasDraft = special != null || content.isNotEmpty;
    final secondary = special == true
        ? '특이사항 있음 · 내용 ${content.length}자'
        : special == false
            ? '특이사항 없음'
            : content.isNotEmpty
                ? '내용 ${content.length}자 저장됨'
                : '저장된 초안 없음';
    return SingleInsideHotKeySummary(
      status: hasDraft ? '초안 있음' : '대기',
      primary: hasDraft ? '작성 중' : '새 보고서',
      secondary: secondary,
    );
  }

  static Future<SingleInsideHotKeySummary> _loadEndReport() async {
    final prefs = await SharedPreferences.getInstance();
    final vehicle = (prefs.getString(_endVehicleKey) ?? '').trim();
    final specialRaw = (prefs.getString(_endSpecialKey) ?? '').trim();
    final content = (prefs.getString(_endContentKey) ?? '').trim();
    final hasDraft = vehicle.isNotEmpty || specialRaw.isNotEmpty || content.isNotEmpty;
    final primary = RegExp(r'^\d+$').hasMatch(vehicle)
        ? '출차 ${int.parse(vehicle)}대'
        : hasDraft
            ? '작성 중'
            : '작성 대기';
    final special = specialRaw == 'true';
    final secondary = special
        ? '특이사항 있음 · 내용 ${content.length}자'
        : content.isNotEmpty
            ? '내용 ${content.length}자 저장됨'
            : '저장된 초안 없음';
    return SingleInsideHotKeySummary(
      status: hasDraft ? '초안 있음' : '대기',
      primary: primary,
      secondary: secondary,
    );
  }

  static Future<SingleInsideHotKeySummary> _loadSubmission(
    SingleAttendanceSubmissionKind kind,
  ) async {
    final summary = await SingleAttendanceSubmissionSummaryService.loadKind(kind);
    if (kind == SingleAttendanceSubmissionKind.commute) {
      final workIn = summary.countEligible('출근');
      final workOut = summary.countEligible('퇴근');
      return SingleInsideHotKeySummary(
        status: summary.eligibleCount > 0 ? '대기' : '완료',
        primary: summary.eligibleCount > 0
            ? '${summary.eligibleCount}건 제출 대기'
            : '제출 대기 없음',
        secondary: '출근 $workIn · 퇴근 $workOut',
      );
    }
    final cutoff = summary.eligibleCount == 0 || summary.cutoffDay == null
        ? '제출 가능한 기록 없음'
        : '${DateFormat('MM.dd').format(summary.cutoffDay!)}까지 제출 가능';
    return SingleInsideHotKeySummary(
      status: summary.eligibleCount > 0 ? '대기' : '완료',
      primary: summary.eligibleCount > 0
          ? '${summary.eligibleCount}건 제출 대기'
          : '제출 대기 없음',
      secondary: cutoff,
    );
  }
  static List<String> _splitNoticeItems(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

}
