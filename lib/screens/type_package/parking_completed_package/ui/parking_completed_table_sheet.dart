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

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _load());
  }

  @override
  void dispose() {
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

  Future<void> _delete(int id) async {
    await _repo.deleteById(id);
    if (!mounted) return;
    showSuccessSnackbar(context, '삭제되었습니다.');
    _load();
  }

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
                    width: 42, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.table_chart_outlined, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('Parking Completed 테이블',
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
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
                  // 검색창
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _searchCtrl,
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
                  // 리스트
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _rows.isEmpty
                        ? const Center(child: Text('기록이 없습니다.'))
                        : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _rows.length,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(child: Text((r.id ?? 0).toString())),
                          title: Text(
                            '${r.plateNumber} (${r.area})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            r.createdAt != null ? r.createdAt.toString() : '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: '삭제',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: r.id == null ? null : () => _delete(r.id!),
                          ),
                        );
                      },
                    ),
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
