// lib/widgets/offline_input/offline_input_bill_section.dart
//
// - SQLite(offline_bills)에서 현 지역(area) + 유형(type='변동'|'고정') 목록 조회
// - '정기'는 자유 입력(TextField)
// - 기존 API(프로퍼티/콜백) 유지
//
import 'package:flutter/material.dart';

// 경로는 프로젝트 구조에 맞게 조정하세요.
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

class OfflineInputBillSection extends StatelessWidget {
  final String? selectedBill;                // 선택된 countType
  final String selectedBillType;             // '변동' | '고정' | '정기'
  final ValueChanged<String?> onChanged;     // countType 선택/입력 결과
  final ValueChanged<String> onTypeChanged;  // 정산유형 탭 전환
  final TextEditingController? countTypeController; // 정기만 사용

  const OfflineInputBillSection({
    super.key,
    required this.selectedBill,
    required this.selectedBillType,
    required this.onChanged,
    required this.onTypeChanged,
    this.countTypeController,
  });

  bool get _isGeneral => selectedBillType == '변동';
  bool get _isFixed   => selectedBillType == '고정';
  bool get _isMonthly => selectedBillType == '정기';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정산 유형',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12.0),

        Row(
          children: [
            _buildTypeButton(
              label: '변동',
              isSelected: _isGeneral,
              onTap: () => onTypeChanged('변동'),
            ),
            const SizedBox(width: 8),
            _buildTypeButton(
              label: '고정',
              isSelected: _isFixed,
              onTap: () => onTypeChanged('고정'),
            ),
            const SizedBox(width: 8),
            _buildTypeButton(
              label: '정기',
              isSelected: _isMonthly,
              onTap: () => onTypeChanged('정기'),
            ),
          ],
        ),
        const SizedBox(height: 12.0),

        if (_isMonthly)
          _buildMonthlyInput()
        else
          _buildSqlitePickerButton(context),
      ],
    );
  }

  Widget _buildMonthlyInput() {
    return TextField(
      controller: countTypeController,
      onChanged: (v) => onChanged(v),
      decoration: const InputDecoration(
        labelText: '정기 - 호실/구분(=countType)',
        hintText: '예: 1901호',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildSqlitePickerButton(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        side: const BorderSide(color: Colors.black),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) {
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: FutureBuilder<_BillsResult>(
                    future: _loadBillsForCurrentArea(selectedBillType),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              '정산 유형을 불러오지 못했습니다.\n${snap.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        );
                      }

                      final data = snap.data!;
                      final items = data.items;

                      return ListView(
                        controller: scrollController,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Text(
                            '${data.typeLabel} 정산 선택',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),

                          if (items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Text(
                                  '${data.typeLabel} 정산 유형이 없습니다.',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          else
                            ...items.map((e) {
                              final isSelected = e.countType == selectedBill;
                              final subtitle = _buildBillSubtitle(e);

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                title: Text(e.countType),
                                subtitle: subtitle,
                                trailing: isSelected
                                    ? const Icon(Icons.check, color: Colors.green)
                                    : const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.pop(context);
                                  onChanged(e.countType);
                                },
                              );
                            }),
                        ],
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(selectedBill ?? '정산 선택'),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  Widget? _buildBillSubtitle(_BillItem e) {
    // 예) 기본 2000원 / 5분, 추가 1000원 / 1분
    final hasGeneral =
        (e.basicAmount ?? 0) != 0 || (e.addAmount ?? 0) != 0 || (e.basicStd ?? 0) != 0 || (e.addStd ?? 0) != 0;
    if (!hasGeneral) return null;

    final parts = <String>[];
    if ((e.basicAmount ?? 0) > 0) {
      final std = (e.basicStd ?? 0) > 0 ? ' / ${e.basicStd}분' : '';
      parts.add('기본 ${e.basicAmount}원$std');
    }
    if ((e.addAmount ?? 0) > 0) {
      final std = (e.addStd ?? 0) > 0 ? ' / ${e.addStd}분' : '';
      parts.add('추가 ${e.addAmount}원$std');
    }

    if (parts.isEmpty) return null;
    return Text(parts.join(', '), style: TextStyle(color: Colors.grey.shade700));
  }

  // ─────────────────────────────────────────────────────────────
  // SQLite helpers
  // ─────────────────────────────────────────────────────────────
  Future<_BillsResult> _loadBillsForCurrentArea(String typeLabel) async {
    final db = await OfflineAuthDb.instance.database;

    // 현재 세션 사용자 area 조회
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    String area = '';
    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) {
        area = ((r1.first['currentArea'] as String?) ?? (r1.first['selectedArea'] as String?) ?? '').trim();
      }
    }
    if (area.isEmpty) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) {
        area = ((r2.first['currentArea'] as String?) ?? (r2.first['selectedArea'] as String?) ?? '').trim();
      }
    }

    // '정기'는 DB 조회 대상 아님(자유 입력)
    if (typeLabel == '정기' || area.isEmpty) {
      return _BillsResult(typeLabel: typeLabel, items: const []);
    }

    // ✅ offline_bills 실제 스키마에 맞춰 컬럼 선택 (regular_amount 제거)
    final rows = await db.query(
      OfflineAuthDb.tableBills,
      columns: const [
        'count_type',
        'type',
        'basic_amount',
        'basic_standard',
        'add_amount',
        'add_standard',
        'updated_at',
      ],
      where: 'area = ? AND type = ?',
      whereArgs: [area, typeLabel],
      orderBy: 'count_type ASC',
      limit: 500,
    );

    final items = rows.map((r) {
      return _BillItem(
        countType: (r['count_type'] as String?)?.trim() ?? '',
        type: (r['type'] as String?)?.trim() ?? '',
        basicAmount: r['basic_amount'] as int?,
        basicStd: r['basic_standard'] as int?,
        addAmount: r['add_amount'] as int?,
        addStd: r['add_standard'] as int?,
        updatedAtMs: r['updated_at'] as int?,
      );
    }).where((e) => e.countType.isNotEmpty).toList();

    return _BillsResult(typeLabel: typeLabel, items: items);
  }

  Widget _buildTypeButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.white,
            border: Border.all(color: Colors.black),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 로컬 모델 (offline_bills 스키마 준수)
// ─────────────────────────────────────────────────────────────
class _BillsResult {
  final String typeLabel; // '변동' | '고정'
  final List<_BillItem> items;
  const _BillsResult({required this.typeLabel, required this.items});
}

class _BillItem {
  final String countType;     // 예: '무료', '일반주차'
  final String type;          // '변동' | '고정'
  final int? basicAmount;
  final int? basicStd;
  final int? addAmount;
  final int? addStd;
  final int? updatedAtMs;

  const _BillItem({
    required this.countType,
    required this.type,
    this.basicAmount,
    this.basicStd,
    this.addAmount,
    this.addStd,
    this.updatedAtMs,
  });
}
