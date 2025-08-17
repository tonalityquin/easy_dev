import 'package:flutter/material.dart';

import '../../../models/plate_log_model.dart';
import '../../../models/plate_model.dart';
import '../../../repositories/plate/firestore_plate_repository.dart';
import '../../../utils/gcs_json_uploader.dart';
import '../departure_completed_pages/widgets/departure_completed_page_merge_log.dart';
import '../departure_completed_pages/widgets/departure_completed_page_today_log.dart';

class DepartureCompletedSettledTab extends StatefulWidget {
  const DepartureCompletedSettledTab({
    super.key,
    required this.area,
    required this.division,
    required this.selectedDate,
    required this.plateNumber, // 선택된 번호판(없으면 빈 문자열)
  });

  final String area;
  final String division;
  final DateTime selectedDate;
  final String plateNumber;

  @override
  State<DepartureCompletedSettledTab> createState() => _DepartureCompletedSettledTabState();
}

class _DepartureCompletedSettledTabState extends State<DepartureCompletedSettledTab> {
  final TextEditingController _fourDigitCtrl = TextEditingController();
  bool _isLoading = false;
  bool _hasSearched = false;
  List<PlateModel> _results = [];

  // 정산 탭을 떠날 때 검색 상태 초기화용
  TabController? _tabController;
  static const int _settledTabIndex = 1; // TabBar: [미정산(0), 정산(1)]

  bool _isValidFourDigit(String v) => RegExp(r'^\d{4}$').hasMatch(v);

  // 텍스트 변경 시 즉시 버튼 활성/비활성 반영
  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  // 탭 전환 시 정산 탭을 떠나면 검색 상태 초기화
  void _onTabChange() {
    if (_tabController == null) return;
    // indexIsChanging 동안 from -> to 전환, 떠날 때 초기화
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
      setState(() {
        _results = items;
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('검색 중 오류가 발생했습니다: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _fourDigitCtrl.addListener(_onTextChanged);
    // DefaultTabController는 빌드 이후 접근 가능
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          _SectionHeader(
            key: const ValueKey('today-header'),
            icon: Icons.receipt_long,
            title: '오늘 입차 로그',
            // trailing: _hasSearched && _results.isNotEmpty ? '총 $todayLogCount건' : null,
            trailing: '', // 필요 시 위 주석 라인으로 교체
          ),
          const SizedBox(height: 6),

          /// ── 상단: TodayLogSection (검색 결과 기반)
          Expanded(
            child: Builder(
              builder: (context) {
                if (!_hasSearched) {
                  return Center(
                    child: Text('번호판 4자리를 입력 후 검색하세요.', style: TextStyle(color: Colors.grey[600])),
                  );
                }
                if (_isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_results.isEmpty) {
                  return Center(
                    child: Text('검색 결과가 없습니다.', style: TextStyle(color: Colors.grey[600])),
                  );
                }

                // logs가 비어있지 않은 결과 우선 선택
                PlateModel target = _results.first;
                for (final p in _results) {
                  final l = p.logs ?? const <PlateLogModel>[];
                  if (l.isNotEmpty) {
                    target = p;
                    break;
                  }
                }

                final String plate = target.plateNumber;

                // PlateLogModel -> Map 변환 (TodayLogSection은 Map 형태 기대)
                final List<dynamic> logsRaw =
                    (target.logs?.map((e) => e.toMap()).toList()) ?? const <dynamic>[];

                return TodayLogSection(
                  plateNumber: plate,
                  logsRaw: logsRaw,
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          _SectionHeader(
            key: const ValueKey('merged-header'),
            icon: Icons.merge_type,
            title: '과거 입차 로그',
            trailing: widget.plateNumber.isEmpty ? '' : '선택: ${widget.plateNumber}',
          ),
          const SizedBox(height: 6),

          /// ── 중간: MergedLogSection (선택된 번호판 기준)
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: widget.plateNumber.isEmpty
                  ? Future.value(<Map<String, dynamic>>[])
                  : GcsJsonUploader().loadPlateLogs(
                plateNumber: widget.plateNumber,
                division: widget.division,
                area: widget.area,
                date: widget.selectedDate,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text("병합 로그 로딩 실패"));
                }
                final mergedLogs = snapshot.data ?? [];
                return ClipRect(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: MergedLogSection(
                        mergedLogs: mergedLogs,
                        division: widget.division,
                        area: widget.area,
                        selectedDate: widget.selectedDate,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          SafeArea(
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
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;

  const _SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = (trailing ?? '').trim(); // ← 빈 문자열 처리
    return Container(
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
          if (t.isNotEmpty) // ← 빈 문자열이면 표시 안 함
            Text(
              t,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }
}
