// lib/screens/head_package/mgmt_package/field.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/area_counts_repository.dart';
import '../../../states/user/user_state.dart';

// ▶︎ 동일 폴더의 바텀시트 참조
import './area_detail_bottom_sheet.dart';

class Field extends StatefulWidget {
  const Field({super.key});

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  bool _isLoading = true;
  String? _errorMessage;
  List<AreaCount> _areaCounts = [];
  late final AreaCountsRepository _repo;

  String _query = '';

  @override
  void initState() {
    super.initState();
    _repo = AreaCountsRepository();
    _fetchAreaCounts();
  }

  Future<void> _fetchAreaCounts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userState = context.read<UserState>();

      // ✅ 안전 접근 (빈 배열 대비)
      final divisions = userState.user?.divisions;
      final division = (divisions != null && divisions.isNotEmpty) ? divisions.first : null;

      if (division == null || division.isEmpty) {
        throw Exception('division 정보가 없습니다.');
      }

      final results = await _repo.fetchAreaCountsByDivision(division);

      if (!mounted) return;
      setState(() {
        _areaCounts = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '데이터를 불러오지 못했습니다.\n${e.toString()}';
        _isLoading = false;
      });
    }
  }

  List<AreaCount> get _filteredAreas {
    if (_query.trim().isEmpty) return _areaCounts;
    final q = _query.trim().toLowerCase();
    return _areaCounts.where((a) => a.area.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('필드 별 업무/근퇴 현황'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _fetchAreaCounts,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(8),
          child: Container(height: 1, color: cs.outlineVariant.withOpacity(.4)),
        ),
      ),
      body: _isLoading
          ? const _SkeletonList()
          : _errorMessage != null
          ? _ErrorView(message: _errorMessage!, onRetry: _fetchAreaCounts)
          : RefreshIndicator(
        onRefresh: _fetchAreaCounts,
        edgeOffset: 100,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: _SearchBar(
                  initialText: _query,
                  onChanged: (v) => setState(() => _query = v),
                  hintText: '지역 이름으로 검색…',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _SummaryChips(areaCounts: _filteredAreas),
              ),
            ),
            if (_filteredAreas.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('검색 결과가 없습니다.'),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final areaCount = _filteredAreas[index];
                    return _AreaCard(
                      areaCount: areaCount,
                      onTap: () => showAreaDetailBottomSheet(
                        context: context,
                        areaName: areaCount.area,
                      ),
                    );
                  },
                  childCount: _filteredAreas.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({
    required this.areaCount,
    required this.onTap,
  });

  final AreaCount areaCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    int total = 0;
    for (final t in PlateType.values) {
      total += areaCount.counts[t] ?? 0;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('📍', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        areaCount.area,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Badge(text: '$total건'),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: PlateType.values.map((type) {
                    final count = areaCount.counts[type] ?? 0;
                    return _StatChip(
                      label: type.label,
                      count: count,
                      color: _colorByCount(count, cs),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _colorByCount(int count, ColorScheme cs) {
    if (count == 0) return cs.outline;
    if (count < 3) return Colors.blue;
    if (count < 5) return Colors.orange;
    return Colors.redAccent;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            count > 0 ? Icons.circle : Icons.remove_circle_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count건',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.onChanged,
    this.initialText = '',
    this.hintText,
  });

  final ValueChanged<String> onChanged;
  final String initialText;
  final String? hintText;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hintText ?? '검색…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
          onPressed: () {
            _c.clear();
            widget.onChanged('');
            setState(() {});
          },
          icon: const Icon(Icons.clear),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 1.6),
        ),
      ),
    );
  }
}

class _SummaryChips extends StatelessWidget {
  const _SummaryChips({required this.areaCounts});
  final List<AreaCount> areaCounts;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    int totalAreas = areaCounts.length;
    int totalTasks = areaCounts.fold(0, (sum, a) {
      for (final t in PlateType.values) {
        sum += a.counts[t] ?? 0;
      }
      return sum;
    });

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Badge(text: '지역 ${totalAreas}곳'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.secondary.withOpacity(.25)),
          ),
          child: Text(
            '총 ${totalTasks}건',
            style: TextStyle(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error, fontSize: 16),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemBuilder: (_, __) => _SkeletonCard(color: cs.outlineVariant),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: 6,
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 94,
      decoration: BoxDecoration(
        color: color.withOpacity(.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.4)),
      ),
    );
  }
}
