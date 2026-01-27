import 'package:flutter/material.dart';

import '../../../../models/plate_log_model.dart';
import '../../../../models/plate_model.dart';
import '../../../../repositories/plate_repo_services/firestore_plate_repository.dart';

import '../departure_completed_package/widgets/double_departure_completed_page_merge_log.dart';
import '../departure_completed_package/widgets/double_departure_completed_page_today_log.dart';
import '../../../../utils/snackbar_helper.dart';

class DoubleDepartureCompletedSettledTab extends StatefulWidget {
  const DoubleDepartureCompletedSettledTab({
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
  State<DoubleDepartureCompletedSettledTab> createState() => _DoubleDepartureCompletedSettledTabState();
}

class _DoubleDepartureCompletedSettledTabState extends State<DoubleDepartureCompletedSettledTab> {
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
  List<PlateModel> _results = [];
  int _selectedResultIndex = 0;

  TabController? _tabController;
  static const int _settledTabIndex = 1;

  bool _isValidFourDigit(String v) => RegExp(r'^\d{4}$').hasMatch(v);

  String _shortPlateLabel(String plate) {
    final idx = plate.indexOf('_');
    return idx == -1 ? plate : plate.substring(0, idx);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onTabChange() {
    if (_tabController == null) return;
    if (_tabController!.indexIsChanging) {
      final from = _tabController!.previousIndex;
      final to = _tabController!.index;
      if (from == _settledTabIndex && to != _settledTabIndex) {
        _resetSearchState();
      }
    }
  }

  void _resetSearchState() {
    if (!mounted) return;
    setState(() {
      _fourDigitCtrl.clear();
      _results = [];
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

    final chips = _results.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      final selected = _selectedResultIndex == i;

      return Padding(
        padding: const EdgeInsets.only(right: 6.0),
        child: ChoiceChip(
          label: Text(_shortPlateLabel(p.plateNumber)),
          selected: selected,
          onSelected: (v) {
            if (v) setState(() => _selectedResultIndex = i);
          },
          selectedColor: cs.primary.withOpacity(0.14),
          backgroundColor: cs.surfaceContainerLow,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? cs.primary : cs.onSurface,
          ),
          side: BorderSide(
            color: selected ? cs.primary.withOpacity(0.45) : cs.outlineVariant.withOpacity(0.85),
          ),
        ),
      );
    }).toList();

    final safeIndex = _selectedResultIndex.clamp(0, _results.length - 1);
    final target = _results[safeIndex];

    final String plate = target.plateNumber;
    final List<dynamic> logsRaw = (target.logs?.map((e) => e.toMap()).toList()) ?? const <dynamic>[];

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
        Expanded(
          child: DoubleTodayLogSection(
            plateNumber: plate,
            logsRaw: logsRaw,
          ),
        ),
      ],
    );
  }

  Widget _buildMergedSectionBody() {
    return DoubleMergedLogSection(
      mergedLogs: const <Map<String, dynamic>>[],
      division: widget.division,
      area: widget.area,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                filled: true,
                fillColor: cs.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary, width: 1.4),
                ),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isLoading || !_isValidFourDigit(_fourDigitCtrl.text) ? null : _runSearch,
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
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          _SectionHeader(
            key: const ValueKey('today-header'),
            icon: Icons.receipt_long,
            title: '오늘 입차 로그',
            isOpen: _openToday,
            onTap: _toggleToday,
          ),
          const SizedBox(height: 6),

          if (_openToday)
            Expanded(
              child: _buildTodaySectionBody(),
            ),

          const SizedBox(height: 6),

          _SectionHeader(
            key: const ValueKey('merged-header'),
            icon: Icons.merge_type,
            title: '과거 입차 로그',
            isOpen: _openMerged,
            onTap: _toggleMerged,
          ),
          const SizedBox(height: 6),

          if (_openMerged)
            Expanded(
              child: _buildMergedSectionBody(),
            ),

          const SizedBox(height: 8),

          searchBar,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final chevron = (onTap != null) ? (isOpen == true ? Icons.expand_less : Icons.expand_more) : null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
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
        borderRadius: BorderRadius.circular(8),
        child: content,
      ),
    );
  }
}
