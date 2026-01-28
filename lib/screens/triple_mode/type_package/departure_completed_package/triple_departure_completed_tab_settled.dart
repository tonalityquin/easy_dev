import 'package:flutter/material.dart';

import '../../../../models/plate_log_model.dart';
import '../../../../models/plate_model.dart';
import '../../../../repositories/plate_repo_services/firestore_plate_repository.dart';

// ⛔️ GCS 직접 로드는 MergedLogSection 내부에서 처리
import '../departure_completed_package/widgets/triple_departure_completed_page_merge_log.dart';
import '../departure_completed_package/widgets/triple_departure_completed_page_today_log.dart';
import '../../../../utils/snackbar_helper.dart';

class TripleDepartureCompletedSettledTab extends StatefulWidget {
  const TripleDepartureCompletedSettledTab({
    super.key,
    required this.area,
    required this.division,
    required this.selectedDate,
    required this.plateNumber,
  });

  final String area;
  final String division;
  final DateTime selectedDate;
  final String plateNumber;

  @override
  State<TripleDepartureCompletedSettledTab> createState() =>
      _TripleDepartureCompletedSettledTabState();
}

class _TripleDepartureCompletedSettledTabState
    extends State<TripleDepartureCompletedSettledTab> {
  // ===== 아코디언 상태: 최대 1개만 열림 =====
  bool _openToday = true;
  bool _openMerged = false;

  void _toggleToday() {
    setState(() {
      if (_openToday) {
        _openToday = false;
        _openMerged = false;
      } else {
        _openToday = true;
        _openMerged = false;
      }
    });
  }

  void _toggleMerged() {
    setState(() {
      if (_openMerged) {
        _openMerged = false;
        _openToday = false;
      } else {
        _openMerged = true;
        _openToday = false;
      }
    });
  }

  // ===== Firestore 검색 상태 (오늘 로그용) =====
  final TextEditingController _fourDigitCtrl = TextEditingController();
  bool _isLoading = false;
  bool _hasSearched = false;
  List<PlateModel> _results = <PlateModel>[];
  int _selectedResultIndex = 0;

  TabController? _tabController;
  static const int _settledTabIndex = 1;

  bool _isValidFourDigit(String v) => RegExp(r'^\d{4}$').hasMatch(v);

  String _shortPlateLabel(String plate) {
    final idx = plate.indexOf('_');
    return idx == -1 ? plate : plate.substring(0, idx);
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onTabChange() {
    final tc = _tabController;
    if (tc == null) return;

    if (tc.indexIsChanging) {
      final from = tc.previousIndex;
      final to = tc.index;
      if (from == _settledTabIndex && to != _settledTabIndex) {
        _resetSearchState();
      }
    }
  }

  void _resetSearchState() {
    if (!mounted) return;
    setState(() {
      _fourDigitCtrl.clear();
      _results = <PlateModel>[];
      _hasSearched = false;
      _isLoading = false;
      _selectedResultIndex = 0;
    });
  }

  Future<void> _runSearch() async {
    final q = _fourDigitCtrl.text.trim();
    if (!_isValidFourDigit(q)) return;

    setState(() => _isLoading = true);

    try {
      final repo = FirestorePlateRepository();

      final items = await repo.fourDigitDepartureCompletedQuery(
        plateFourDigit: q,
        area: widget.area,
      );

      if (!mounted) return;

      int initialIndex = 0;
      for (int i = 0; i < items.length; i++) {
        final l = items[i].logs ?? const <PlateLogModel>[];
        if (l.isNotEmpty) {
          initialIndex = i;
          break;
        }
      }

      setState(() {
        _results = items;
        _hasSearched = true;
        _isLoading = false;
        _selectedResultIndex = initialIndex;
        // 검색하면 자연스럽게 '오늘' 섹션이 열리도록 유도
        _openToday = true;
        _openMerged = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFailedSnackbar(context, '검색 중 오류가 발생했습니다: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _fourDigitCtrl.addListener(_onTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tabController = DefaultTabController.of(context);
      _tabController?.addListener(_onTabChange);
    });
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChange);
    _fourDigitCtrl.removeListener(_onTextChanged);
    _fourDigitCtrl.dispose();
    super.dispose();
  }

  // ===== 섹션 본문 위젯 빌더들 =====
  Widget _buildTodaySectionBody() {
    final cs = Theme.of(context).colorScheme;

    if (!_hasSearched) {
      return Center(
        child: Text(
          '번호판 4자리를 입력 후 검색하세요.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          '검색 결과가 없습니다.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    // 다건 결과 칩
    final chips = _results.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      final selected = _selectedResultIndex == i;

      return Padding(
        padding: const EdgeInsets.only(right: 6.0),
        child: ChoiceChip(
          label: Text(_shortPlateLabel(p.plateNumber)),
          selected: selected,
          selectedColor: cs.primaryContainer,
          backgroundColor: cs.surfaceContainerLow,
          labelStyle: TextStyle(
            color: selected ? cs.onPrimaryContainer : cs.onSurface,
            fontWeight: FontWeight.w800,
          ),
          side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
          onSelected: (v) {
            if (!v) return;
            if (!mounted) return;
            setState(() => _selectedResultIndex = i);
          },
        ),
      );
    }).toList();

    final safeIndex = _selectedResultIndex.clamp(0, _results.length - 1);
    final target = _results[safeIndex];

    final String plate = target.plateNumber;
    final List<dynamic> logsRaw =
        (target.logs?.map((e) => e.toMap()).toList()) ?? const <dynamic>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_results.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
        // TodayLogSection 내부에 Expanded가 있으므로, 여기서는 Expanded로 감싸서 공간 할당
        Expanded(
          child: TripleTodayLogSection(
            plateNumber: plate,
            logsRaw: logsRaw,
          ),
        ),
      ],
    );
  }

  Widget _buildMergedSectionBody() {
    // 리팩토링된 MergedLogSection은 내부에서 날짜 선택/불러오기/검색을 모두 처리
    return TripleMergedLogSection(
      mergedLogs: const <Map<String, dynamic>>[], // 시그니처 호환용, 내부 미사용
      division: widget.division,
      area: widget.area,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bool canSearch =
        !_isLoading && _isValidFourDigit(_fourDigitCtrl.text.trim());

    // 오늘 검색바 (오늘 섹션과 연동)
    final searchBar = SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _fourDigitCtrl,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                counterText: '',
                labelText: '번호판 4자리',
                hintText: '예) 1234',
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                  BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: cs.primary, width: 1.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: cs.surface,
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canSearch ? _runSearch : null,
            icon: _isLoading
                ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
              ),
            )
                : const Icon(Icons.search),
            label: const Text('검색'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // === (1) 오늘 헤더 — 항상 보임 ===
          _SectionHeader(
            key: const ValueKey('today-header'),
            icon: Icons.receipt_long,
            title: '오늘 입차 로그',
            isOpen: _openToday,
            onTap: _toggleToday,
          ),
          const SizedBox(height: 6),

          // === (2) 오늘 본문 — 열렸을 때만 Expanded 로 표시 ===
          if (_openToday) Expanded(child: _buildTodaySectionBody()),

          const SizedBox(height: 6),

          // === (3) 과거 헤더 — 항상 보임 ===
          _SectionHeader(
            key: const ValueKey('merged-header'),
            icon: Icons.merge_type,
            title: '과거 입차 로그',
            isOpen: _openMerged,
            onTap: _toggleMerged,
          ),
          const SizedBox(height: 6),

          // === (4) 과거 본문 — 열렸을 때만 Expanded 로 표시 ===
          if (_openMerged) Expanded(child: _buildMergedSectionBody()),

          const SizedBox(height: 8),

          // === (5) 오늘 검색 입력 — 하단 고정 ===
          searchBar,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  // 아코디언 제어용
  final bool? isOpen;
  final VoidCallback? onTap;

  const _SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.isOpen,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final chevron =
    (onTap != null) ? (isOpen == true ? Icons.expand_less : Icons.expand_more) : null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          if (chevron != null) ...[
            const SizedBox(width: 8),
            Icon(chevron, size: 20, color: cs.onSurfaceVariant),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        overlayColor: MaterialStateProperty.all(
          cs.outlineVariant.withOpacity(0.12),
        ),
        child: content,
      ),
    );
  }
}
