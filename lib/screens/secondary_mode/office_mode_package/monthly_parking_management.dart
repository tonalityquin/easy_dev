// lib/screens/secondary_package/office_mode_package/monthly_parking_management.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import 'monthly_management_package/monthly_plate_bottom_sheet.dart';
import '../../../../utils/snackbar_helper.dart';

// ✅ AppCardPalette 사용 (프로젝트 경로에 맞게 수정)
import '../../../../../theme.dart';

enum _ListFilter { all, expiringSoon, expired, hasMemo }
enum _SortMode { updatedDesc, endDateAsc, plateAsc }

class MonthlyParkingManagement extends StatefulWidget {
  const MonthlyParkingManagement({super.key});

  @override
  State<MonthlyParkingManagement> createState() => _MonthlyParkingManagementState();
}

class _MonthlyParkingManagementState extends State<MonthlyParkingManagement> {
  static const String _screenTag = 'monthly management';

  final ScrollController _scrollController = ScrollController();

  // 검색/필터/정렬
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _ListFilter _filter = _ListFilter.all;
  _SortMode _sort = _SortMode.updatedDesc;

  // 선택 하이라이트(리스트에서 어떤 항목을 보고 있었는지 표시)
  String? _selectedDocId;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Utils
  // ─────────────────────────────────────────────────────────────────────────────

  DateTime? _tryParseDate(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  int? _daysLeft(String endDateText) {
    final end = _tryParseDate(endDateText);
    if (end == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return endDay.difference(today).inDays;
  }

  bool _hasMemo(Map<String, dynamic> data) {
    final cs = (data['customStatus'] ?? '').toString().trim();
    if (cs.isNotEmpty && cs != '없음') return true;
    final list = data['statusList'];
    if (list is List && list.isNotEmpty) return true;
    return false;
  }

  Timestamp? _asTimestamp(dynamic v) {
    if (v is Timestamp) return v;
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Sheets / Actions
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _openAddSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FractionallySizedBox(
        heightFactor: 1,
        child: MonthlyPlateBottomSheet(),
      ),
    );
  }

  Future<void> _openEditSheet({
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 1,
        child: MonthlyPlateBottomSheet(
          isEditMode: true,
          initialDocId: docId,
          initialData: data,
        ),
      ),
    );
  }

  Future<void> _deleteDoc(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('선택한 항목을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    ) ??
        false;

    if (!ok) return;

    try {
      await FirebaseFirestore.instance.collection('monthly_plate_status').doc(docId).delete();
      if (!mounted) return;

      setState(() {
        if (_selectedDocId == docId) _selectedDocId = null;
      });
      showSuccessSnackbar(context, '삭제되었습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '삭제 실패: $e');
    }
  }

  Future<void> _openDetailSheet({
    required String docId,
    required Map<String, dynamic> data,
    required NumberFormat won,
  }) async {
    FocusScope.of(context).unfocus();

    setState(() => _selectedDocId = docId);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _MonthlyPlateDetailSheet(
          docId: docId,
          data: data,
          won: won,
          onEdit: () async {
            Navigator.of(ctx).pop();
            await _openEditSheet(docId: docId, data: data);
          },
          onPay: () async {
            // ✅ 결제는 “수정 시트 내부의 결제 버튼” 흐름을 그대로 사용 가능
            Navigator.of(ctx).pop();
            await _openEditSheet(docId: docId, data: data);
          },
          onDelete: () async {
            Navigator.of(ctx).pop();
            await _deleteDoc(docId);
          },
        );
      },
    );

    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // UI pieces
  // ─────────────────────────────────────────────────────────────────────────────

  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: $_screenTag',
              child: Text(_screenTag, style: style),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSearchBar(ColorScheme cs) {
    final palette = AppCardPalette.of(context);
    final serviceBase = palette.serviceBase;

    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withOpacity(.45), width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: '번호판/정산이름 검색',
                  isDense: true,
                  filled: true,
                  fillColor: cs.surfaceVariant.withOpacity(.55),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                    tooltip: '지우기',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.clear),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.45)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: serviceBase, width: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: '검색 닫기',
              onPressed: () {
                FocusScope.of(context).unfocus();
                setState(() {
                  _showSearch = false;
                  _searchController.clear();
                  _query = '';
                });
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme cs, int totalCount, int filteredCount) {
    final palette = AppCardPalette.of(context);
    final serviceBase = palette.serviceBase;

    Widget chip({
      required String label,
      required _ListFilter value,
      required IconData icon,
    }) {
      final active = _filter == value;
      return ChoiceChip(
        selected: active,
        onSelected: (_) => setState(() => _filter = value),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : serviceBase),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w900,
          color: active ? Colors.white : serviceBase,
          letterSpacing: .2,
        ),
        selectedColor: serviceBase,
        backgroundColor: cs.surface,
        side: BorderSide(
          color: active ? serviceBase : serviceBase.withOpacity(.28),
          width: 1.2,
        ),
        shape: const StadiumBorder(),
      );
    }

    String sortLabel(_SortMode m) {
      switch (m) {
        case _SortMode.updatedDesc:
          return '최근 업데이트';
        case _SortMode.endDateAsc:
          return '종료일 빠른순';
        case _SortMode.plateAsc:
          return '번호판 오름차순';
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(.45), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 상태 줄(개수/정렬)
          Row(
            children: [
              Expanded(
                child: Text(
                  '전체 $totalCount건 · 표시 $filteredCount건',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface.withOpacity(.78),
                    letterSpacing: .2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(.55),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                ),
                child: DropdownButton<_SortMode>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  icon: Icon(Icons.swap_vert, size: 18, color: cs.onSurface.withOpacity(.65)),
                  borderRadius: BorderRadius.circular(12),
                  items: _SortMode.values
                      .map(
                        (m) => DropdownMenuItem<_SortMode>(
                      value: m,
                      child: Text(
                        sortLabel(m),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface.withOpacity(.85),
                        ),
                      ),
                    ),
                  )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _sort = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 필터 칩
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip(label: '전체', value: _ListFilter.all, icon: Icons.all_inbox_outlined),
                const SizedBox(width: 8),
                chip(label: '만료 임박', value: _ListFilter.expiringSoon, icon: Icons.timer_outlined),
                const SizedBox(width: 8),
                chip(label: '만료', value: _ListFilter.expired, icon: Icons.warning_amber_rounded),
                const SizedBox(width: 8),
                chip(label: '메모', value: _ListFilter.hasMemo, icon: Icons.sticky_note_2_outlined),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_MonthlyPlateVM> _buildFilteredSorted(List<QueryDocumentSnapshot> docs) {
    final items = docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final docId = doc.id;

      final plateNumber = docId.split('_').first;
      final countType = (data['countType'] ?? '').toString();

      final endDate = (data['endDate'] ?? '').toString();
      final left = _daysLeft(endDate);

      final updatedAt = _asTimestamp(data['updatedAt']);

      return _MonthlyPlateVM(
        docId: docId,
        plateNumber: plateNumber,
        countType: countType,
        data: data,
        daysLeft: left,
        updatedAt: updatedAt,
        hasMemo: _hasMemo(data),
      );
    }).toList();

    // search
    final q = _query.trim().toLowerCase();
    var filtered = items.where((it) {
      if (q.isEmpty) return true;
      return it.plateNumber.toLowerCase().contains(q) || it.countType.toLowerCase().contains(q);
    }).toList();

    // filter
    filtered = filtered.where((it) {
      switch (_filter) {
        case _ListFilter.all:
          return true;
        case _ListFilter.expiringSoon:
          if (it.daysLeft == null) return false;
          return it.daysLeft! >= 0 && it.daysLeft! <= 7;
        case _ListFilter.expired:
          if (it.daysLeft == null) return false;
          return it.daysLeft! < 0;
        case _ListFilter.hasMemo:
          return it.hasMemo;
      }
    }).toList();

    // sort
    switch (_sort) {
      case _SortMode.updatedDesc:
        filtered.sort((a, b) {
          final at = a.updatedAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.updatedAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        });
        break;
      case _SortMode.endDateAsc:
        filtered.sort((a, b) {
          final ad = a.daysLeft ?? (1 << 30);
          final bd = b.daysLeft ?? (1 << 30);
          return ad.compareTo(bd);
        });
        break;
      case _SortMode.plateAsc:
        filtered.sort((a, b) => a.plateNumber.compareTo(b.plateNumber));
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);
    final serviceBase = palette.serviceBase;

    final currentArea = context.read<UserState>().currentArea.trim();
    final won = NumberFormat.decimalPattern('ko_KR');
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        foregroundColor: cs.onSurface,
        flexibleSpace: _buildScreenTag(context),
        title: const Text(
          '정기 주차 관리',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: _showSearch ? '검색 닫기' : '검색',
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  _query = '';
                }
              });
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: _showSearch ? _buildSearchBar(cs) : null,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('monthly_plate_status')
            .where('type', isEqualTo: '정기')
            .where('area', isEqualTo: currentArea)
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('등록된 정기 주차 정보가 없습니다.'));
          }

          final docs = snapshot.data!.docs;
          final items = _buildFilteredSorted(docs);

          return Column(
            children: [
              _buildToolbar(cs, docs.length, items.length),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final it = items[index];
                    final data = it.data;

                    final amount = (data['regularAmount'] ?? 0) as int;
                    final endDate = (data['endDate'] ?? '').toString();
                    final periodUnit = (data['periodUnit'] ?? '월').toString();

                    final isSelected = it.docId == _selectedDocId;

                    return _MonthlyPlateCompactCard(
                      selected: isSelected,
                      plateNumber: it.plateNumber,
                      countType: it.countType,
                      amount: amount,
                      endDate: endDate,
                      periodUnit: periodUnit,
                      daysLeft: it.daysLeft,
                      hasMemo: it.hasMemo,
                      onTap: () async {
                        await _openDetailSheet(
                          docId: it.docId,
                          data: data,
                          won: won,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        backgroundColor: serviceBase,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('추가', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// View Model
// ─────────────────────────────────────────────────────────────────────────────
class _MonthlyPlateVM {
  final String docId;
  final String plateNumber;
  final String countType;
  final Map<String, dynamic> data;
  final int? daysLeft;
  final Timestamp? updatedAt;
  final bool hasMemo;

  const _MonthlyPlateVM({
    required this.docId,
    required this.plateNumber,
    required this.countType,
    required this.data,
    required this.daysLeft,
    required this.updatedAt,
    required this.hasMemo,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact list card (한눈에 보기용)
// ─────────────────────────────────────────────────────────────────────────────
class _MonthlyPlateCompactCard extends StatelessWidget {
  const _MonthlyPlateCompactCard({
    required this.selected,
    required this.plateNumber,
    required this.countType,
    required this.amount,
    required this.endDate,
    required this.periodUnit,
    required this.daysLeft,
    required this.hasMemo,
    required this.onTap,
  });

  final bool selected;
  final String plateNumber;
  final String countType;
  final int amount;
  final String endDate;
  final String periodUnit;
  final int? daysLeft;
  final bool hasMemo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);
    final serviceBase = palette.serviceBase;
    final serviceDark = palette.serviceDark;
    final serviceLight = palette.serviceLight;

    final cs = Theme.of(context).colorScheme;
    final won = NumberFormat.decimalPattern('ko_KR');

    final Color border = selected ? serviceBase : cs.outlineVariant.withOpacity(.45);
    final Color bg = cs.surface;
    final Color title = cs.onSurface;

    return Material(
      color: bg,
      elevation: selected ? 3 : 0,
      shadowColor: Colors.black.withOpacity(.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.8 : 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // leading
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: serviceLight.withOpacity(.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: serviceLight.withOpacity(.28)),
                ),
                child: Icon(
                  Icons.directions_car_outlined,
                  color: serviceDark,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // main
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1st line: plate + memo dot
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plateNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: title,
                              letterSpacing: .2,
                            ),
                          ),
                        ),
                        if (hasMemo) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: serviceBase,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    // 2nd line: countType + amount + endDate
                    Text(
                      '$countType · ₩${won.format(amount)} · 종료 $endDate',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.62),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // trailing chip
              _DdayChip(daysLeft: daysLeft, periodUnit: periodUnit),
            ],
          ),
        ),
      ),
    );
  }
}

class _DdayChip extends StatelessWidget {
  const _DdayChip({required this.daysLeft, required this.periodUnit});

  final int? daysLeft;
  final String periodUnit;

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);
    final serviceDark = palette.serviceDark;
    final serviceLight = palette.serviceLight;

    final cs = Theme.of(context).colorScheme;

    String text;
    Color bg;
    Color fg;
    Color br;

    if (daysLeft == null) {
      text = '기간 ?';
      bg = cs.surfaceVariant.withOpacity(.55);
      fg = cs.onSurface.withOpacity(.75);
      br = cs.outlineVariant.withOpacity(.55);
    } else if (daysLeft! < 0) {
      text = '만료';
      bg = cs.errorContainer.withOpacity(.90);
      fg = cs.onErrorContainer;
      br = cs.error.withOpacity(.45);
    } else if (daysLeft! <= 7) {
      text = 'D-$daysLeft';
      bg = serviceLight.withOpacity(.18);
      fg = serviceDark;
      br = serviceLight.withOpacity(.45);
    } else {
      text = 'D-$daysLeft';
      bg = cs.surfaceVariant.withOpacity(.55);
      fg = cs.onSurface.withOpacity(.78);
      br = cs.outlineVariant.withOpacity(.55);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: br),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: fg,
          letterSpacing: .2,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Focused detail sheet (집중형 상세 보기)
// ─────────────────────────────────────────────────────────────────────────────
class _MonthlyPlateDetailSheet extends StatelessWidget {
  const _MonthlyPlateDetailSheet({
    required this.docId,
    required this.data,
    required this.won,
    required this.onEdit,
    required this.onPay,
    required this.onDelete,
  });

  final String docId;
  final Map<String, dynamic> data;
  final NumberFormat won;

  final VoidCallback onEdit;
  final VoidCallback onPay;
  final VoidCallback onDelete;

  ButtonStyle _pillOutlineStyle(ColorScheme cs, Color serviceBase) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: const StadiumBorder(),
      foregroundColor: serviceBase,
      side: BorderSide(color: serviceBase.withOpacity(.45), width: 1.4),
      backgroundColor: cs.surface,
      textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .2),
    ).copyWith(
      overlayColor: MaterialStatePropertyAll(serviceBase.withOpacity(.06)),
    );
  }

  ButtonStyle _pillFilledDangerStyle(ColorScheme cs) {
    return FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: const StadiumBorder(),
      backgroundColor: cs.error,
      foregroundColor: cs.onError,
      textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);
    final serviceBase = palette.serviceBase;
    final serviceDark = palette.serviceDark;
    final serviceLight = palette.serviceLight;

    final cs = Theme.of(context).colorScheme;

    final plateNumber = docId.split('_').first;

    final countType = (data['countType'] ?? '').toString();
    final regularType = (data['regularType'] ?? '').toString();
    final amount = data['regularAmount'] ?? 0;
    final duration = data['regularDurationHours'] ?? 0;
    final periodUnit = (data['periodUnit'] ?? '월').toString();
    final startDate = (data['startDate'] ?? '').toString();
    final endDate = (data['endDate'] ?? '').toString();
    final customStatus = (data['customStatus'] ?? '없음').toString();

    final paymentHistoryRaw = data['payment_history'];
    final List<Map<String, dynamic>> paymentHistory =
    (paymentHistoryRaw is List) ? List<Map<String, dynamic>>.from(paymentHistoryRaw) : <Map<String, dynamic>>[];

    final reversed = paymentHistory.reversed.toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      builder: (ctx, sc) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.10),
                  blurRadius: 16,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withOpacity(.65),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 10),

                // header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: serviceLight.withOpacity(.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: serviceLight.withOpacity(.28)),
                        ),
                        child: Icon(Icons.assignment_outlined, color: serviceDark),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plateNumber,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: cs.onSurface,
                                letterSpacing: .2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              countType.isEmpty ? '정기 주차' : countType,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface.withOpacity(.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(.5)),

                Expanded(
                  child: ListView(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    children: [
                      _detailCard(
                        context,
                        title: '기본 정보',
                        icon: Icons.info_outline,
                        serviceDark: serviceDark,
                        serviceLight: serviceLight,
                        children: [
                          _kv(context, '주차 타입', regularType.isEmpty ? '-' : regularType, serviceDark),
                          _kv(context, '요금', '₩${won.format(amount)}', serviceDark),
                          _kv(context, '주차 시간', '$duration$periodUnit', serviceDark),
                          _kv(context, '기간', '$startDate ~ $endDate', serviceDark),
                          _kv(context, '상태 메시지', customStatus, serviceDark),
                        ],
                      ),
                      const SizedBox(height: 12),

                      _detailCard(
                        context,
                        title: '결제 내역',
                        icon: Icons.payments_outlined,
                        serviceDark: serviceDark,
                        serviceLight: serviceLight,
                        children: [
                          if (reversed.isEmpty)
                            Text(
                              '결제 내역이 없습니다.',
                              style: TextStyle(
                                color: cs.onSurface.withOpacity(.60),
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else
                            ...reversed.map((p) {
                              final paidAtRaw = (p['paidAt'] ?? '').toString();
                              String paidAt;
                              try {
                                paidAt = DateFormat('yyyy.MM.dd HH:mm').format(DateTime.parse(paidAtRaw));
                              } catch (_) {
                                paidAt = paidAtRaw;
                              }

                              final amount = p['amount'] ?? 0;
                              final paidBy = (p['paidBy'] ?? '').toString();
                              final note = (p['note'] ?? '').toString();
                              final extended = p['extended'] == true;

                              return _paymentTile(
                                context,
                                paidAt: paidAt,
                                amountText: '₩${won.format(amount)}',
                                paidBy: paidBy,
                                note: note,
                                extended: extended,
                                serviceBase: serviceBase,
                                serviceDark: serviceDark,
                                serviceLight: serviceLight,
                              );
                            }),
                        ],
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),

                // bottom actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('수정'),
                          style: _pillOutlineStyle(cs, serviceBase),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPay,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('결제'),
                          style: _pillOutlineStyle(cs, serviceBase),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('삭제'),
                          style: _pillFilledDangerStyle(cs),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailCard(
      BuildContext context, {
        required String title,
        required IconData icon,
        required Color serviceDark,
        required Color serviceLight,
        required List<Widget> children,
      }) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: serviceLight.withOpacity(.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: serviceLight.withOpacity(.28)),
                ),
                child: Icon(icon, color: serviceDark, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: serviceDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, Color serviceDark) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: text.bodySmall?.copyWith(
                color: Colors.black.withOpacity(.55),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: serviceDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(
      BuildContext context, {
        required String paidAt,
        required String amountText,
        required String paidBy,
        required String note,
        required bool extended,
        required Color serviceBase,
        required Color serviceDark,
        required Color serviceLight,
      }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: cs.onSurface.withOpacity(.60)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  paidAt,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(.60),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (extended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: serviceLight.withOpacity(.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: serviceLight.withOpacity(.35)),
                  ),
                  child: Text(
                    '연장',
                    style: TextStyle(
                      fontSize: 12,
                      color: serviceDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person, size: 16, color: serviceBase),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '결제자: $paidBy',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withOpacity(.80),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.attach_money, size: 16, color: serviceBase),
              const SizedBox(width: 6),
              Text(
                amountText,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if (note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.note_outlined, size: 16, color: cs.onSurface.withOpacity(.60)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withOpacity(.80),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
