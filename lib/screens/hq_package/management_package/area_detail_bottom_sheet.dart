// File: lib/screens/area/area_detail_bottom_sheet.dart
import 'package:flutter/material.dart';
import '../../../repositories/area_user_repository.dart';

/// 호출 예시:
/// await showAreaDetailBottomSheet(context: context, areaName: 'belivus');
Future<void> showAreaDetailBottomSheet({
  required BuildContext context,
  required String areaName,
  AreaUserRepository? repository,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent, // 시트에서 라운드/배경 처리
    builder: (_) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        snap: true,
        builder: (context, scrollController) {
          return AreaDetailBottomSheet(
            areaName: areaName,
            repository: repository,
            externalScrollController: scrollController, // 내부 스크롤 연결
          );
        },
      );
    },
  );
}

class AreaDetailBottomSheet extends StatefulWidget {
  final String areaName;
  final AreaUserRepository _repo;
  final ScrollController? externalScrollController;

  AreaDetailBottomSheet({
    super.key,
    required this.areaName,
    AreaUserRepository? repository,
    this.externalScrollController,
  }) : _repo = repository ?? AreaUserRepository();

  @override
  State<AreaDetailBottomSheet> createState() => _AreaDetailBottomSheetState();
}

enum _FilterTab { all, working, off }

class _AreaDetailBottomSheetState extends State<AreaDetailBottomSheet> {
  late Future<List<UserStatus>> _future;

  _FilterTab _tab = _FilterTab.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget._repo.getUsersForArea(widget.areaName);
  }

  void _reload() {
    setState(() {
      _future = widget._repo.getUsersForArea(widget.areaName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, // ✅ 바텀시트 배경 하얀색
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Grip
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${widget.areaName} 지역 근무자 현황',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '새로고침',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant),

            // 필터 + 검색
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                children: [
                  SegmentedButton<_FilterTab>(
                    segments: const [
                      ButtonSegment(value: _FilterTab.all, label: Text('전체')),
                      ButtonSegment(value: _FilterTab.working, label: Text('출근 중')),
                      ButtonSegment(value: _FilterTab.off, label: Text('퇴근')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) {
                      setState(() => _tab = s.first);
                    },
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SearchField(
                    hintText: '이름으로 검색…',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: FutureBuilder<List<UserStatus>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _BodySkeleton();
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '❌ 데이터를 불러오는 중 오류 발생\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    );
                  }

                  final users = snapshot.data ?? [];
                  final filtered = _applyFilter(users);

                  if (users.isEmpty) {
                    return const Center(child: Text('📭 해당 지역에 근무자가 없습니다.'));
                  }

                  if (filtered.isEmpty) {
                    return const Center(child: Text('검색/필터 결과가 없습니다.'));
                  }

                  final summary = _buildSummary(users, cs);

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: summary,
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.builder(
                          controller: widget.externalScrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final user = filtered[index];
                            return _UserTile(user: user);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<UserStatus> _applyFilter(List<UserStatus> users) {
    Iterable<UserStatus> r = users;
    switch (_tab) {
      case _FilterTab.working:
        r = r.where((u) => u.isWorking);
        break;
      case _FilterTab.off:
        r = r.where((u) => !u.isWorking);
        break;
      case _FilterTab.all:
        break;
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      r = r.where((u) => u.name.toLowerCase().contains(q));
    }
    return r.toList();
  }

  Widget _buildSummary(List<UserStatus> users, ColorScheme cs) {
    final total = users.length;
    final on = users.where((u) => u.isWorking).length;
    final off = total - on;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ChipBadge(
          label: '전체 $total명',
          color: cs.secondaryContainer,
          textColor: cs.onSecondaryContainer,
        ),
        _ChipBadge(
          label: '출근 $on명',
          color: Colors.green.withOpacity(.15),
          borderColor: Colors.green.withOpacity(.4),
          textColor: Colors.green[800]!,
        ),
        _ChipBadge(
          label: '퇴근 $off명',
          color: cs.surfaceVariant.withOpacity(.5),
          textColor: cs.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final UserStatus user;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final leadingColor = user.isWorking ? Colors.green : cs.outline;
    final statusText = user.isWorking ? '🟢 출근' : '⚪ 퇴근';
    final statusColor = user.isWorking ? Colors.green[800]! : cs.onSurfaceVariant;

    return Card(
      color: Colors.white, // ✅ 카드 배경 하얀색
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.6)),
      ),
      child: ListTile(
        leading: Icon(
          user.isWorking ? Icons.check_circle : Icons.remove_circle_outline,
          color: leadingColor,
        ),
        title: const Text(
          ' ',
          style: TextStyle(height: 0), // (ListTile 타이틀 높이 안정화용 빈 라인)
        ),
        // 타이틀에 이름 굵게 표시
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.name,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.3),
            ),
            Text(user.isWorking ? '출근 중' : '퇴근'),
          ],
        ),
        trailing: Text(
          statusText,
          style: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ChipBadge extends StatelessWidget {
  const _ChipBadge({
    required this.label,
    required this.color,
    this.textColor,
    this.borderColor,
  });

  final String label;
  final Color color;
  final Color? textColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor ?? cs.outlineVariant.withOpacity(.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? cs.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.onChanged, this.hintText});
  final ValueChanged<String> onChanged;
  final String? hintText;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _c = TextEditingController();

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
        fillColor: Colors.white, // ✅ 입력창 배경 하얀색
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

class _BodySkeleton extends StatelessWidget {
  const _BodySkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemBuilder: (_, __) => Container(
        height: 64,
        decoration: BoxDecoration(
          color: cs.outlineVariant.withOpacity(.2),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: 8,
    );
  }
}
