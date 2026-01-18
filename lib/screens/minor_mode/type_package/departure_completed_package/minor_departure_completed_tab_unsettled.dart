import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../models/plate_model.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/plate/minor_plate_state.dart';
import '../../../../utils/init/date_utils.dart';
import 'departure_completed_plate_search_bottom_sheet/minor_departure_completed_search_bottom_sheet.dart';

/// Minor / 출차완료 / 미정산 탭
///
/// 정책/기능
/// - 미정산(isLockedFee == false)만 표시
/// - 정렬/그룹핑 기준: requestTime 고정
/// - 오래된 순(오름차순)
/// - 날짜 그룹 헤더: Divider 가운데 라벨 `YYYY.MM.DD (요일) · N건`
/// - 상단 안내 배너:
///   - 정산은 "번호판 검색"으로 진행 안내
///   - 마지막 갱신 시간 표시 + 색상 정책
///     - 날짜가 오늘과 다르면 빨간색
///     - 오늘이지만 1시간 이상 경과하면 주황색
/// - 하단: "데이터 갱신" + "번호판 검색"
/// - Pull-to-refresh 지원
class MinorDepartureCompletedUnsettledTab extends StatefulWidget {
  const MinorDepartureCompletedUnsettledTab({
    super.key,
    required this.firestorePlates, // 시그니처 호환(실제 렌더링은 MinorPlateState 최신 데이터 사용)
    required this.userName,
  });

  final List<PlateModel> firestorePlates;
  final String userName;

  @override
  State<MinorDepartureCompletedUnsettledTab> createState() => _MinorDepartureCompletedUnsettledTabState();
}

class _MinorDepartureCompletedUnsettledTabState extends State<MinorDepartureCompletedUnsettledTab> {
  // ✅ 날짜/정렬 기준을 requestTime으로 고정
  DateTime _sortTime(PlateModel p) => p.requestTime;

  DateTime _ymd(DateTime t) => DateTime(t.year, t.month, t.day);

  static const List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String _formatYmdWithWeekday(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final w = _weekdays[d.weekday - 1];
    return '${d.year}.$mm.$dd ($w)';
  }

  String _formatDateTimeForBanner(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    return '${t.year}.$mm.$dd $hh:$mi';
  }

  @override
  void initState() {
    super.initState();

    // ✅ 화면 최초 진입 시에도 한 번 갱신 트리거(상위에서 이미 로드했더라도 무해)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final plateState = context.read<MinorPlateState>();
      final area = context.read<AreaState>().currentArea.trim();
      if (area.isEmpty) return;

      // 이미 로딩 중이면 중복 호출 방지
      if (!plateState.isLoadingType(PlateType.departureCompleted)) {
        await plateState.minorRefreshType(PlateType.departureCompleted);
      }
    });
  }

  Future<void> _openPlateSearchBottomSheet() async {
    final area = context.read<AreaState>().currentArea.trim();

    if (area.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 지역(area)이 설정되지 않아 검색을 열 수 없습니다.')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MinorDepartureCompletedSearchBottomSheet(
        area: area,
        // 이 탭은 "검색 결과 선택/상태토글" 로직을 제거했으므로 no-op
        onSearch: (_) {},
      ),
    );
  }

  /// ✅ 데이터 갱신 로직: MinorPlateState에 출차완료 1회 재조회 요청
  Future<void> _refreshUnsettled() async {
    final plateState = context.read<MinorPlateState>();
    final area = context.read<AreaState>().currentArea.trim();

    if (area.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 지역(area)이 설정되지 않아 갱신할 수 없습니다.')),
      );
      return;
    }

    await plateState.minorRefreshType(PlateType.departureCompleted);

    if (!mounted) return;
    final lastAt = plateState.minorLastRefreshAtOf(PlateType.departureCompleted);
    final sourceLabel = plateState.minorLastRefreshSourceLabelOf(PlateType.departureCompleted);

    final text = (lastAt == null)
        ? '데이터를 갱신했습니다.'
        : '데이터를 갱신했습니다. (${_formatDateTimeForBanner(lastAt)} · $sourceLabel)';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<MinorPlateState>();

    // ✅ 이 탭은 "state의 최신 데이터"를 기준으로 렌더링 (갱신 반영 보장)
    final raw = plateState.dataOfType(PlateType.departureCompleted);

    // departureCompleted는 state 쿼리에서 이미 isLockedFee=false로 제한하지만,
    // 방어적으로 한 번 더 필터링
    final plates = raw.where((p) => p.isLockedFee == false).toList()
      ..sort((a, b) => _sortTime(a).compareTo(_sortTime(b))); // 오래된 순

    final lastRefreshAt = plateState.minorLastRefreshAtOf(PlateType.departureCompleted);
    final sourceLabel = plateState.minorLastRefreshSourceLabelOf(PlateType.departureCompleted);

    final bool isRefreshing = plateState.isLoadingType(PlateType.departureCompleted);

    // ✅ 날짜별(YYYY-MM-DD) 미정산 건수 사전 계산
    final Map<DateTime, int> dateCounts = <DateTime, int>{};
    for (final p in plates) {
      final d = _ymd(_sortTime(p));
      dateCounts[d] = (dateCounts[d] ?? 0) + 1;
    }

    final listChildren = <Widget>[
      _TopNoticeBanner(
        lastRefreshAt: lastRefreshAt,
        sourceLabel: sourceLabel,
        isRefreshing: isRefreshing,
        format: _formatDateTimeForBanner,
      ),
      const SizedBox(height: 10),
      if (plates.isEmpty)
        const _EmptyState(
          icon: Icons.inbox_outlined,
          title: '표시할 미정산 번호판이 없습니다',
          message: '데이터 갱신 또는 번호판 검색을 사용해 보세요.',
        )
      else
        ..._buildGroupedList(plates, dateCounts),
      const SizedBox(height: 12),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _refreshUnsettled,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          children: listChildren,
        ),
      ),
      bottomNavigationBar: _BottomBar(
        isRefreshing: isRefreshing,
        onRefreshPressed: isRefreshing ? null : _refreshUnsettled,
        onSearchPressed: _openPlateSearchBottomSheet,
      ),
    );
  }

  List<Widget> _buildGroupedList(List<PlateModel> plates, Map<DateTime, int> dateCounts) {
    final widgets = <Widget>[];
    DateTime? currentDate;

    for (final p in plates) {
      final t = _sortTime(p);
      final d = _ymd(t);

      if (currentDate == null || currentDate != d) {
        currentDate = d;

        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 10));
        }

        final count = dateCounts[d] ?? 0;
        widgets.add(
          _DateDivider(
            label: _formatYmdWithWeekday(d),
            count: count,
          ),
        );
        widgets.add(const SizedBox(height: 10));
      }

      widgets.add(_UnsettledPlateCard(plate: p, requestTime: t));
      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }
}

/// ✅ 상단 안내 + 마지막 갱신 시간 표시 배너
///
/// 색상 정책:
/// - lastRefreshAt == null: 빨간색(갱신 이력 없음)
/// - 오늘 날짜와 다름: 빨간색
/// - 오늘이지만 1시간 이상 경과: 주황색
/// - 그 외: 기본 회색
class _TopNoticeBanner extends StatelessWidget {
  const _TopNoticeBanner({
    required this.lastRefreshAt,
    required this.sourceLabel,
    required this.isRefreshing,
    required this.format,
  });

  final DateTime? lastRefreshAt;
  final String sourceLabel;
  final bool isRefreshing;
  final String Function(DateTime) format;

  bool _isSameYmd(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final bool hasValue = lastRefreshAt != null;

    final bool isNotToday = hasValue ? !_isSameYmd(lastRefreshAt!, now) : true;

    final bool over1Hour = hasValue ? now.difference(lastRefreshAt!).inMinutes >= 60 : true;

    // ✅ 우선순위: 날짜 다름/없음(빨강) > 오늘이지만 1시간 경과(주황) > 기본
    final Color dataColor = isNotToday
        ? Colors.redAccent
        : (over1Hour ? Colors.orange.shade700 : Colors.black54);

    final Color borderColor = isNotToday
        ? Colors.redAccent.withOpacity(0.35)
        : (over1Hour ? Colors.orange.shade700.withOpacity(0.35) : Colors.black12);

    final IconData icon = isRefreshing
        ? Icons.sync
        : (isNotToday
        ? Icons.warning_amber_rounded
        : (over1Hour ? Icons.error_outline : Icons.access_time));

    final String dataText = !hasValue
        ? '데이터 기준: -'
        : '데이터 기준: ${format(lastRefreshAt!)} ($sourceLabel)';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.black54),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '정산은 하단의 “번호판 검색”을 눌러 진행해 주세요.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, size: 16, color: dataColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dataText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: dataColor,
                  ),
                ),
              ),
              if (isRefreshing) ...[
                const SizedBox(width: 8),
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isRefreshing,
    required this.onRefreshPressed,
    required this.onSearchPressed,
  });

  final bool isRefreshing;
  final VoidCallback? onRefreshPressed;
  final VoidCallback onSearchPressed;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Colors.white,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onRefreshPressed,
                    icon: isRefreshing
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Icon(Icons.refresh, color: Colors.grey[800]),
                    label: Text(
                      isRefreshing ? '갱신 중' : '데이터 갱신',
                      style: TextStyle(
                        color: onRefreshPressed == null ? Colors.grey[500] : Colors.grey[800],
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onSearchPressed,
                    icon: Icon(Icons.search, color: Colors.grey[800]),
                    label: Text(
                      '번호판 검색',
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

class _DateDivider extends StatelessWidget {
  const _DateDivider({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w900,
      color: Colors.black54,
    );

    final text = '$label · ${count}건';

    return Row(
      children: [
        const Expanded(child: Divider(height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(text, style: style),
        ),
        const Expanded(child: Divider(height: 1)),
      ],
    );
  }
}

class _UnsettledPlateCard extends StatelessWidget {
  const _UnsettledPlateCard({
    required this.plate,
    required this.requestTime,
  });

  final PlateModel plate;
  final DateTime requestTime;

  String _safe(String v, {String fallback = '-'}) {
    final t = v.trim();
    return t.isEmpty ? fallback : t;
  }

  @override
  Widget build(BuildContext context) {
    final plateNo = _safe(plate.plateNumber);
    final location = _safe(plate.location, fallback: '미지정');
    final area = _safe(plate.area);

    return Material(
      color: Colors.white,
      elevation: 1.2,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.directions_car, size: 18, color: Colors.black54),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plateNo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        CustomDateUtils.formatTimeForUI(requestTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '지역: $area',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '위치: $location',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Colors.grey[500]),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
