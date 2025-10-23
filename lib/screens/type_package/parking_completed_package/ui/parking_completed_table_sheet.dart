import 'dart:math' as math;
import 'dart:async'; // ✅ 디바운스용
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

import '../../../../utils/snackbar_helper.dart';
import '../repositories/parking_completed_repository.dart';
import '../models/parking_completed_record.dart';

class ParkingCompletedTableSheet extends StatefulWidget {
  const ParkingCompletedTableSheet({super.key});

  @override
  State<ParkingCompletedTableSheet> createState() => _ParkingCompletedTableSheetState();
}

class _ParkingCompletedTableSheetState extends State<ParkingCompletedTableSheet> {
  final _repo = ParkingCompletedRepository();
  bool _loading = true;
  List<ParkingCompletedRecord> _rows = [];
  final _searchCtrl = TextEditingController();

  // ✅ 디바운스 타이머
  Timer? _debounce;
  static const _debounceMs = 300;

  // 테이블 최소 너비(좁은 폰에선 가로 스크롤)
  static const double _tableMinWidth = 640; // ID/Actions 제거로 살짝 줄임
  static const double _headerHeight = 44;

  @override
  void initState() {
    super.initState();
    _load();

    // ✅ 입력마다 바로 _load() 호출 대신 디바운스
    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: _debounceMs), _load);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel(); // ✅ 누수 방지
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _repo.listAll(search: _searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  /// 전체 삭제(정렬은 created_at ASC이므로 ID에 의존하지 않음)
  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('테이블 비우기'),
        content: const Text('모든 기록을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
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
  );

  TextStyle get _cellStyle => Theme.of(context).textTheme.bodyMedium!.copyWith(
    height: 1.2,
  );

  TextStyle get _monoStyle => _cellStyle.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()], // 자리 고정 숫자
    fontFamilyFallback: const ['monospace'],
  );

  Widget _th(String label, {double? width, int flex = 0, TextAlign align = TextAlign.left}) {
    final cell = Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: _alignTo(align),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.6),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Text(label, style: _headStyle),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      alignment: _alignTo(align),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.8), width: .8),
          right: showRightBorder
              ? BorderSide(color: Theme.of(context).dividerColor.withOpacity(.8), width: .8)
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
    // 보기 좋은 yyyy-MM-dd HH:mm
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
                          _th('Area', flex: 2),
                          _th('Created At (오래된 순)', flex: 3),
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
                        final area = r.area;
                        final created = _fmtDate(r.createdAt);
                        final bg = (i % 2 == 0) ? Colors.grey.shade50 : Colors.white;

                        return Row(
                          children: [
                            _td(
                              Text(
                                plate,
                                style: _cellStyle.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              flex: 2,
                              bg: bg,
                            ),
                            _td(
                              Text(area, style: _cellStyle, overflow: TextOverflow.ellipsis),
                              flex: 2,
                              bg: bg,
                            ),
                            _td(
                              Text(created, style: _monoStyle, overflow: TextOverflow.ellipsis),
                              flex: 3,
                              bg: bg,
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // 화면 최상단까지 올라오는 바텀 시트
    return Container(
      color: Colors.black.withOpacity(0.2),
      child: DraggableScrollableSheet(
        initialChildSize: 0.95,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (context, scrollCtrl) {
          return Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ─────────────── 상단 툴바(타이틀 1행 + 액션 2행) ───────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1행: 아이콘 + 타이틀(Expanded)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.table_chart_outlined, color: cs.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Parking Completed 테이블',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // 2행: 우측 정렬 가로 배열 액션들
                        Align(
                          alignment: Alignment.centerRight,
                          child: OverflowBar(
                            alignment: MainAxisAlignment.end,
                            spacing: 4,
                            overflowSpacing: 2,
                            children: [
                              if (!_loading)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    'Rows: ${_rows.length}',
                                    style: text.labelMedium?.copyWith(color: cs.outline),
                                  ),
                                ),
                              IconButton(
                                tooltip: '새로고침',
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                              ),
                              IconButton(
                                tooltip: '전체 비우기',
                                onPressed: _rows.isEmpty ? null : _clearAll,
                                icon: const Icon(Icons.delete_sweep),
                              ),
                              IconButton(
                                tooltip: '닫기',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 검색창
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '번호판/구역 검색…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _load();
                          },
                        ),
                        filled: true,
                        fillColor: cs.surfaceVariant.withOpacity(0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),

                  // ──────────────── SQL-like 테이블 (Pinned Header) ────────────────
                  Expanded(
                    child: _buildTable(scrollCtrl),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────── SliverPinned Header Delegate ─────────────────────────
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _HeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final showShadow = overlapsContent || shrinkOffset > 0;
    return Material(
      elevation: showShadow ? 1 : 0,
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
    return const Center(child: CircularProgressIndicator());
  }
}

class ExpandedEmpty extends StatelessWidget {
  final String message;
  const ExpandedEmpty({super.key, required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}
