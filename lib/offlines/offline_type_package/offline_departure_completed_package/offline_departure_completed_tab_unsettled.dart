import 'package:flutter/material.dart';

import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

import '../../../utils/snackbar_helper.dart';

class OfflineDepartureCompletedTabUnsettled extends StatefulWidget {
  const OfflineDepartureCompletedTabUnsettled({
    super.key,
    required this.area,
    required this.selectedDate,
  });

  final String area;
  final DateTime selectedDate;

  @override
  State<OfflineDepartureCompletedTabUnsettled> createState() => _OfflineDepartureCompletedTabUnsettledState();
}

class _OfflineDepartureCompletedTabUnsettledState extends State<OfflineDepartureCompletedTabUnsettled> {
  bool _openCalendar = true;
  bool _openUnsettled = false;

  void _toggleCalendar() {
    setState(() {
      if (_openCalendar) {
        _openCalendar = false;
        _openUnsettled = false;
      } else {
        _openCalendar = true;
        _openUnsettled = false;
      }
    });
  }

  void _toggleUnsettled() {
    setState(() {
      if (_openUnsettled) {
        _openUnsettled = false;
        _openCalendar = false;
      } else {
        _openUnsettled = true;
        _openCalendar = false;
      }
    });
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const String _kStatusDepartured = 'departured';

  Future<List<Map<String, Object?>>> _loadDeparturedRows() async {
    final db = await OfflineAuthDb.instance.database;

    final d = widget.selectedDate;
    final from = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    final to = DateTime(d.year, d.month, d.day, 23, 59, 59, 999).millisecondsSinceEpoch;

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const [
        'id',
        'plate_number',
        'plate_four_digit',
        'location',
        'updated_at',
        'created_at',
        'is_selected',
      ],
      where: '''
        COALESCE(status_type,'') = ?
        AND LOWER(TRIM(area)) = LOWER(TRIM(?))
        AND COALESCE(updated_at, created_at, 0) BETWEEN ? AND ?
      ''',
      whereArgs: [_kStatusDepartured, widget.area, from, to],
      orderBy: 'COALESCE(updated_at, created_at) DESC',
      limit: 300,
    );

    return rows;
  }

  Future<void> _toggleSelect(int id) async {
    final db = await OfflineAuthDb.instance.database;
    final s = await OfflineAuthService.instance.currentSession();
    final uid = (s?.userId ?? '').trim();
    final uname = (s?.name ?? '').trim();

    await db.transaction((txn) async {
      final r = await txn.query(
        OfflineAuthDb.tablePlates,
        columns: const ['is_selected'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final curSel = r.isNotEmpty ? ((r.first['is_selected'] as int?) ?? 0) : 0;

      await txn.update(
        OfflineAuthDb.tablePlates,
        {'is_selected': 0},
        where: "COALESCE(status_type,'') = ? AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)",
        whereArgs: [_kStatusDepartured, uid, uname],
      );

      await txn.update(
        OfflineAuthDb.tablePlates,
        {
          'is_selected': curSel == 0 ? 1 : 0,
          'selected_by': uid,
          'user_name': uname,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _loadDeparturedRows(),
        builder: (context, snap) {
          final rows = snap.data ?? const <Map<String, Object?>>[];
          final total = rows.length;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                _SectionHeaderTile(
                  title: '선택한 날짜',
                  subtitle: _fmtDate(widget.selectedDate),
                  icon: Icons.calendar_month,
                  isOpen: _openCalendar,
                  onTap: _toggleCalendar,
                ),
                _CollapsibleCard(
                  isOpen: _openCalendar,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Text(
                      '상단 날짜는 상위 시트에서 선택되었습니다.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SectionHeaderTile(
                  title: '출차 완료 (정산 무관)',
                  subtitle: '선택한 날짜 · 현재 지역 기준',
                  icon: Icons.list_alt,
                  trailing: _CountBadge(count: total),
                  isOpen: _openUnsettled,
                  onTap: _toggleUnsettled,
                ),
                _CollapsibleCard(
                  isOpen: _openUnsettled,
                  child: (total == 0)
                      ? const _EmptyState(
                          icon: Icons.inbox_outlined,
                          title: '표시할 번호판이 없습니다',
                          message: '달력을 바꾸거나 번호판 검색을 사용해 보세요.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final id = r['id'] as int;
                            final pn = (r['plate_number'] as String?)?.trim();
                            final four = (r['plate_four_digit'] as String?)?.trim() ?? '';
                            final loc = (r['location'] as String?)?.trim() ?? '';
                            final selected = ((r['is_selected'] as int?) ?? 0) != 0;

                            final title = (pn != null && pn.isNotEmpty) ? pn : (four.isNotEmpty ? '****-$four' : '미상');

                            return ListTile(
                              dense: true,
                              leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined),
                              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: loc.isNotEmpty ? Text(loc) : null,
                              onTap: () => _toggleSelect(id),
                              onLongPress: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('삭제 확인'),
                                    content: Text('이 항목을 삭제할까요?\n\n$title'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                                      TextButton(
                                          onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  final db = await OfflineAuthDb.instance.database;
                                  await db.delete(
                                    OfflineAuthDb.tablePlates,
                                    where: 'id = ?',
                                    whereArgs: [id],
                                  );
                                  if (!mounted) return;
                                  showSuccessSnackbar(context, '삭제되었습니다.');
                                  setState(() {});
                                }
                              },
                            );
                          },
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemCount: rows.length,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeaderTile extends StatelessWidget {
  const _SectionHeaderTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isOpen,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isOpen;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final chevron = isOpen ? Icons.expand_less : Icons.expand_more;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
                const SizedBox(width: 6),
                Icon(chevron, size: 20, color: Colors.grey[700]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsibleCard extends StatelessWidget {
  const _CollapsibleCard({required this.isOpen, required this.child});

  final bool isOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: const SizedBox.shrink(),
      secondChild: Material(
        elevation: 1.5,
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
      crossFadeState: isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 200),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message});

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
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
