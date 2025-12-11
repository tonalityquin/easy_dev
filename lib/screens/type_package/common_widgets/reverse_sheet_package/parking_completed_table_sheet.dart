// lib/screens/type_package/parking_completed_package/ui/parking_completed_table_sheet.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../utils/snackbar_helper.dart';
import 'models/parking_completed_record.dart';
import 'repositories/parking_completed_repository.dart';
import 'ui/reverse_page_top_sheet.dart';



/// 👉 역 Top Sheet로 "Parking Completed 로컬 테이블" 열기 헬퍼
///
/// 기존에는 ReversePage(Live 모드)로 전환하기 위한 콜백을 받았지만,
/// 이제는 단순 테이블 뷰만 열도록 API를 단순화했다.
Future<void> showParkingCompletedTableTopSheet(BuildContext context) async {
  await showReversePageTopSheet(
    context: context,
    maxHeightFactor: 0.95,
    builder: (_) => const ParkingCompletedTableSheet(),
  );
}

/// 로컬 SQLite `parking_completed_records` 테이블 뷰(SQL-like)
///
/// - 번호판/주차 구역 텍스트 검색
/// - createdAt 기준 정렬(오래된 순 / 최신 순 토글)
/// - 출차 완료(isDepartureCompleted) 숨김 토글
/// - 전체 삭제
class ParkingCompletedTableSheet extends StatefulWidget {
  const ParkingCompletedTableSheet({super.key});

  @override
  State<ParkingCompletedTableSheet> createState() => _ParkingCompletedTableSheetState();
}

/// Deep Blue 팔레트(서비스 전반에서 사용하는 컬러와 동일 계열)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
}

class _ParkingCompletedTableSheetState extends State<ParkingCompletedTableSheet> {
  final _repo = ParkingCompletedRepository();
  bool _loading = true;

  /// 전체 로우(필터 전)
  List<ParkingCompletedRecord> _allRows = [];

  /// 화면에 표시되는 로우(필터/정렬 후)
  List<ParkingCompletedRecord> _rows = [];

  final TextEditingController _searchCtrl = TextEditingController();

  // 디바운스 타이머
  Timer? _debounce;
  static const int _debounceMs = 300;

  // 세로 스크롤 컨트롤러(Top Sheet에서 직접 사용)
  final ScrollController _scrollCtrl = ScrollController();

  // 테이블 최소 너비(좁은 폰에선 가로 스크롤)
  static const double _tableMinWidth = 720; // 출차 완료 컬럼 추가로 약간 확장
  static const double _headerHeight = 44;

  // 정렬 상태: true = 오래된 순(ASC), false = 최신 순(DESC)
  bool _sortOldFirst = true;

  // 출차 완료 숨김 필터: true면 isDepartureCompleted == true 행을 숨김
  bool _hideDepartureCompleted = false;

  @override
  void initState() {
    super.initState();
    _load();

    // 입력마다 바로 _load() 호출 대신 디바운스
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: _debounceMs), _load);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _repo.listAll(search: _searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _allRows = List.of(rows);
      _applyFilterAndSort(); // 현재 필터/정렬 상태에 맞춰 적용
      _loading = false;
    });
  }

  /// 필터 + 정렬 동시에 적용
  void _applyFilterAndSort() {
    // 1) 필터: 출차 완료 숨김 여부
    _rows = _allRows.where((r) {
      if (!_hideDepartureCompleted) return true;
      return !r.isDepartureCompleted;
    }).toList();

    // 2) 정렬
    _sortRows();
  }

  /// createdAt 기준 정렬
  void _sortRows() {
    _rows.sort((a, b) {
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca == null && cb == null) return 0;
      if (ca == null) return _sortOldFirst ? 1 : -1;
      if (cb == null) return _sortOldFirst ? -1 : 1;
      final cmp = ca.compareTo(cb);
      return _sortOldFirst ? cmp : -cmp;
    });
  }

  /// 헤더 클릭 시 정렬 토글
  void _toggleSortByCreatedAt() {
    setState(() {
      _sortOldFirst = !_sortOldFirst;
      _applyFilterAndSort();
    });
    showSelectedSnackbar(
      context,
      _sortOldFirst ? '입차 시각: 오래된 순으로 정렬' : '입차 시각: 최신 순으로 정렬',
    );
  }

  /// 출차 완료 숨김 토글 버튼
  void _toggleHideDepartureCompleted() {
    setState(() {
      _hideDepartureCompleted = !_hideDepartureCompleted;
      _applyFilterAndSort();
    });
    showSelectedSnackbar(
      context,
      _hideDepartureCompleted ? '출차 완료 건을 숨깁니다.' : '출차 완료 건을 다시 표시합니다.',
    );
  }

  /// 전체 삭제
  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('테이블 비우기'),
        content: const Text('모든 기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.clearAll();
    if (!mounted) return;
    showSuccessSnackbar(context, '전체 삭제되었습니다.');
    _load();
  }

  // ────────────────── UI Helpers (SQL-like cells) ──────────────────
  TextStyle get _headStyle => Theme.of(context).textTheme.labelMedium!.copyWith(
    fontWeight: FontWeight.w700,
    letterSpacing: .2,
    color: _Palette.dark,
  );

  TextStyle get _cellStyle => Theme.of(context).textTheme.bodyMedium!.copyWith(
    height: 1.25,
    color: _Palette.dark.withOpacity(.9),
  );

  TextStyle get _monoStyle => _cellStyle.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()], // 자리 고정 숫자
    fontFamilyFallback: const ['monospace'],
  );

  Widget _th(
      String label, {
        double? width,
        int flex = 0,
        TextAlign align = TextAlign.left,
        bool sortable = false,
        bool sortAsc = true,
        VoidCallback? onTap,
      }) {
    final sortIcon = sortable
        ? Icon(
      sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
      size: 14,
      color: _Palette.dark.withOpacity(.8),
    )
        : null;

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            style: _headStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (sortIcon != null) ...[
          const SizedBox(width: 4),
          sortIcon,
        ],
      ],
    );

    Widget content = Align(
      alignment: _alignTo(align),
      child: labelRow,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      );
    }

    final cell = Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        border: Border(
          bottom: BorderSide(color: _Palette.light.withOpacity(.5)),
        ),
      ),
      child: content,
    );
    if (flex > 0) return Expanded(flex: flex, child: cell);
    return SizedBox(width: width, child: cell);
  }

  Widget _td(
      Widget child, {
        double? width,
        int flex = 0,
        TextAlign align = TextAlign.left,
        Color? bg,
        bool showRightBorder = false,
      }) {
    final cell = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      alignment: _alignTo(align),
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        border: Border(
          bottom: BorderSide(
            color: _Palette.light.withOpacity(.25),
            width: .7,
          ),
          right: showRightBorder
              ? BorderSide(
            color: _Palette.light.withOpacity(.25),
            width: .7,
          )
              : BorderSide.none,
        ),
      ),
      child: child,
    );
    if (flex > 0) return Expanded(flex: flex, child: cell);
    return SizedBox(width: width, child: cell);
  }

  Alignment _alignTo(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
        return Alignment.centerRight;
      case TextAlign.left:
      default:
        return Alignment.centerLeft;
    }
  }

  String _fmtDate(DateTime? v) {
    if (v == null) return '';
    final y = v.year.toString().padLeft(4, '0');
    final mo = v.month.toString().padLeft(2, '0');
    final d = v.day.toString().padLeft(2, '0');
    final h = v.hour.toString().padLeft(2, '0');
    final mi = v.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  /// pinned header + 세로/가로 스크롤 테이블
  Widget _buildTable(ScrollController scrollCtrl) {
    if (_loading) return const ExpandedLoading();
    if (_rows.isEmpty) return const ExpandedEmpty(message: '기록이 없습니다.');

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(_tableMinWidth, constraints.maxWidth);

        return Scrollbar(
          controller: scrollCtrl,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: tableWidth,
                maxWidth: tableWidth,
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: CustomScrollView(
                  controller: scrollCtrl,
                  slivers: [
                    // ── 고정 헤더 (Pinned) ───────────────────────────────
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _HeaderDelegate(
                        height: _headerHeight,
                        child: Row(
                          children: [
                            _th('Plate Number', flex: 2),
                            _th('Location', flex: 2),
                            _th(
                              'Entry Time', // 컬럼명 영어
                              flex: 3,
                              sortable: true,
                              sortAsc: _sortOldFirst,
                              onTap: _toggleSortByCreatedAt,
                            ),
                            _th(
                              'Departure',
                              width: 110,
                              align: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── 바디 (행 리스트) ───────────────────────────────
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, i) {
                          final r = _rows[i];
                          final plate = r.plateNumber;
                          final location = r.location;
                          final created = _fmtDate(r.createdAt);
                          final departed = r.isDepartureCompleted;
                          final isEven = i.isEven;

                          // 출차 완료면 연한 초록색 배경, 아니면 기존 번갈아 색
                          Color rowBg;
                          if (departed) {
                            rowBg = Colors.green.withOpacity(.06);
                          } else {
                            rowBg = isEven ? Colors.white : _Palette.base.withOpacity(.02);
                          }

                          return Row(
                            children: [
                              _td(
                                Text(
                                  plate,
                                  style: _cellStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                flex: 2,
                                bg: rowBg,
                              ),
                              _td(
                                Text(
                                  location,
                                  style: _cellStyle,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                flex: 2,
                                bg: rowBg,
                              ),
                              _td(
                                Text(
                                  created,
                                  style: _monoStyle,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                flex: 3,
                                bg: rowBg,
                              ),
                              _td(
                                Icon(
                                  departed ? Icons.check_circle : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: departed ? Colors.teal : Colors.grey.shade400,
                                ),
                                width: 110,
                                align: TextAlign.center,
                                bg: rowBg,
                              ),
                            ],
                          );
                        },
                        childCount: _rows.length,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: true,
      left: false,
      right: false,
      bottom: false,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            const SizedBox(height: 4),
            // ─────────────── 상단 툴바(타이틀 + 액션) ───────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1행: 아이콘 + 타이틀 + 배지 + 닫기
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _Palette.base.withOpacity(.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.table_chart_outlined,
                          color: _Palette.base,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '입차 완료 테이블',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _Palette.dark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '로컬에 저장된 입차/출차 완료 내역입니다.',
                              style: text.bodySmall?.copyWith(
                                color: cs.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 2행: Rows + 출차완료 숨김 토글 + 전체 비우기
                  Row(
                    children: [
                      if (!_loading)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _Palette.base.withOpacity(.06),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.list_alt_outlined,
                                  size: 16,
                                  color: _Palette.base,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Rows: ${_rows.length}',
                                  style: text.labelMedium?.copyWith(
                                    color: _Palette.base,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Spacer(),
                      // 출차 완료 숨김 토글 버튼
                      IconButton(
                        tooltip: _hideDepartureCompleted ? '출차 완료 포함하여 보기' : '출차 완료 숨기기',
                        onPressed: _allRows.isEmpty && !_hideDepartureCompleted ? null : _toggleHideDepartureCompleted,
                        icon: Icon(
                          _hideDepartureCompleted ? Icons.visibility_off : Icons.visibility,
                          color: _hideDepartureCompleted ? Colors.teal : cs.outline,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        tooltip: '전체 비우기',
                        style: IconButton.styleFrom(
                          backgroundColor: cs.errorContainer.withOpacity(
                            _rows.isEmpty ? 0.12 : 0.2,
                          ),
                        ),
                        onPressed: _rows.isEmpty ? null : _clearAll,
                        icon: Icon(
                          Icons.delete_sweep,
                          color: _rows.isEmpty ? cs.outline : cs.error,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 검색창
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '번호판 또는 주차 구역으로 검색',
                  prefixIcon: Icon(
                    Icons.search,
                    color: _Palette.dark.withOpacity(.7),
                  ),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                    icon: Icon(
                      Icons.clear,
                      color: _Palette.dark.withOpacity(.7),
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      _load();
                    },
                  ),
                  filled: true,
                  fillColor: _Palette.base.withOpacity(.03),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),

            // ──────────────── SQL-like 테이블 (Pinned Header) ────────────────
            Expanded(
              child: _buildTable(_scrollCtrl),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── SliverPinned Header Delegate ─────────────────────────
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _HeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context,
      double shrinkOffset,
      bool overlapsContent,
      ) {
    final showShadow = overlapsContent || shrinkOffset > 0;
    return Material(
      elevation: showShadow ? 1.5 : 0,
      shadowColor: Colors.black26,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

// ───────────────────────── helper widgets ─────────────────────────

class ExpandedLoading extends StatelessWidget {
  const ExpandedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_Palette.base),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '데이터를 불러오는 중입니다…',
            style: text.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

class ExpandedEmpty extends StatelessWidget {
  final String message;

  const ExpandedEmpty({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: cs.outline,
            ),
            const SizedBox(height: 10),
            Text(
              '기록이 없습니다',
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: _Palette.dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: cs.outline,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
