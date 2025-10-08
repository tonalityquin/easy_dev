import 'dart:convert';

import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../../sql/offline_auth_db.dart';

// ⛔️ GCS 직접 로드는 MergedLogSection 내부에서 처리
import 'widgets/departure_completed_page_merge_log.dart';
import 'widgets/departure_completed_page_today_log.dart';
import '../../../utils/snackbar_helper.dart'; // ✅ 커스텀 스낵바 헬퍼 추가

/// SQLite 전용: 정산(완료) 탭
/// - 오늘 로그: 번호판 4자리로 offline_plates 조회 (status_type='departureCompleted')
/// - 과거 로그: MergedLogSection 내부에서 처리(GCS/로컬 혼합 로직 그대로)
class DepartureCompletedSettledTab extends StatefulWidget {
  const DepartureCompletedSettledTab({
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
  State<DepartureCompletedSettledTab> createState() => _DepartureCompletedSettledTabState();
}

class _DepartureCompletedSettledTabState extends State<DepartureCompletedSettledTab> {
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

  // ===== 오늘 로그 검색 상태 (SQLite) =====
  final TextEditingController _fourDigitCtrl = TextEditingController();
  bool _isLoading = false;
  bool _hasSearched = false;

  // SQLite에서 읽어온 원시 row들을 그대로 보관
  List<Map<String, Object?>> _resultsRows = [];
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
      _resultsRows = [];
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
      final db = await OfflineAuthDb.instance.database;
      // status_type='departureCompleted' AND area=... AND plate_four_digit=...
      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        columns: const [
          'id',
          'plate_number',
          'plate_four_digit',
          'area',
          'logs', // JSON 문자열
          'request_time',
          'is_locked_fee',
        ],
        where: '''
          COALESCE(status_type,'') = ?
          AND LOWER(TRIM(area)) = LOWER(TRIM(?))
          AND COALESCE(plate_four_digit,'') = ?
        ''',
        whereArgs: ['departureCompleted', widget.area, q],
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 50,
      );

      // 첫 번째로 logs가 있는 항목을 기본 선택
      int initialIndex = 0;
      for (int i = 0; i < rows.length; i++) {
        final raw = rows[i]['logs'];
        if (raw is String && raw.trim().isNotEmpty) {
          try {
            final list = jsonDecode(raw);
            if (list is List && list.isNotEmpty) {
              initialIndex = i;
              break;
            }
          } catch (_) {/* ignore */}
        }
      }

      if (!mounted) return;
      setState(() {
        _resultsRows = rows;
        _hasSearched = true;
        _isLoading = false;
        _selectedResultIndex = rows.isEmpty ? 0 : initialIndex;
        // 검색하면 자연스럽게 '오늘' 섹션 열기
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
    if (!_hasSearched) {
      return Center(
        child: Text('번호판 4자리를 입력 후 검색하세요.', style: TextStyle(color: Colors.grey[600])),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_resultsRows.isEmpty) {
      return Center(
        child: Text('검색 결과가 없습니다.', style: TextStyle(color: Colors.grey[600])),
      );
    }

    // 다건 결과 칩
    final chips = _resultsRows.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      final selected = _selectedResultIndex == i;
      final pn = (p['plate_number'] as String?) ?? '';
      return Padding(
        padding: const EdgeInsets.only(right: 6.0),
        child: ChoiceChip(
          label: Text(_shortPlateLabel(pn)),
          selected: selected,
          onSelected: (v) {
            if (v) setState(() => _selectedResultIndex = i);
          },
        ),
      );
    }).toList();

    final safeIndex = _selectedResultIndex.clamp(0, _resultsRows.length - 1);
    final row = _resultsRows[safeIndex];

    final String plate = (row['plate_number'] as String?) ?? '';
    final List<dynamic> logsRaw = () {
      final raw = row['logs'];
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final list = jsonDecode(raw);
          if (list is List) return list;
        } catch (_) {}
      }
      return const <dynamic>[];
    }();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_resultsRows.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
        Expanded(
          child: TodayLogSection(
            plateNumber: plate,
            logsRaw: logsRaw,
          ),
        ),
      ],
    );
  }

  Widget _buildMergedSectionBody() {
    // MergedLogSection은 내부에서 날짜 선택/불러오기/검색을 모두 처리(GCS/로컬 로직 포함)
    return MergedLogSection(
      mergedLogs: const <Map<String, dynamic>>[], // 시그니처 호환용, 내부 미사용
      division: widget.division,
      area: widget.area,
    );
  }

  @override
  Widget build(BuildContext context) {
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
              decoration: const InputDecoration(
                counterText: '',
                labelText: '번호판 4자리',
                hintText: '예) 1234',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isLoading || !_isValidFourDigit(_fourDigitCtrl.text) ? null : _runSearch,
            icon: _isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: const Text('검색'),
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
    final chevron = (onTap != null) ? (isOpen == true ? Icons.expand_less : Icons.expand_more) : null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (chevron != null) ...[
            const SizedBox(width: 8),
            Icon(chevron, size: 20, color: Colors.grey[700]),
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
