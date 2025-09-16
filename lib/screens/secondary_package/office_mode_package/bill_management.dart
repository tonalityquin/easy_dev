// lib/screens/secondary_package/office_mode_package/bill_management.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../states/bill/bill_state.dart';
import '../../../states/area/area_state.dart';
// import '../../../widgets/navigation/secondary_mini_navigation.dart'; // ❌ 미사용
import 'bill_management_package/bill_bottom_sheet.dart';

class BillManagement extends StatefulWidget {
  const BillManagement({super.key});

  @override
  State<BillManagement> createState() => _BillManagementState();
}

class _BillManagementState extends State<BillManagement> {
  // didChangeDependencies가 여러 번 불리는 문제를 피하기 위해 initState에서 1회만 새로고침
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 선택 상태가 지워지는 문제가 있었다면, manualBillRefresh 내부에서 보존/복원하도록 개선하는 것이 베스트
      context.read<BillState>().manualBillRefresh();
    });
  }

  // ▼ FAB 위치/간격 조절
  static const double _fabBottomGap = 48.0; // 하단에서 띄우는 여백
  static const double _fabSpacing = 10.0;   // 버튼 간 간격

  void _showBillSettingBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,                    // ✅ 안전영역 반영
      backgroundColor: Colors.transparent,  // ✅ 내부 컨테이너가 배경/라운드 담당
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 1, // ✅ 화면 높이 100% → 최상단까지
          child: BillSettingBottomSheet(
            onSave: (billData) async {
              try {
                await context.read<BillState>().addBillFromMap(billData);
                if (context.mounted) {
                  showSuccessSnackbar(context, '✅ 정산 데이터가 추가되었습니다. 목록이 곧 반영됩니다.');
                }
              } catch (e) {
                if (context.mounted) {
                  showFailedSnackbar(context, '🚨 데이터 추가 중 오류가 발생했습니다: $e');
                }
              }
            },
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('선택한 항목을 삭제하시겠어요?'),
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
  }

  Future<void> _deleteSelectedBill(BuildContext context) async {
    final billState = context.read<BillState>();
    final selectedId = billState.selectedBillId;

    if (selectedId == null) {
      if (context.mounted) showFailedSnackbar(context, '삭제할 항목을 선택하세요.');
      return;
    }

    // ✅ 삭제 전 확인 다이얼로그
    final ok = await _confirmDelete(context);
    if (!ok) return;

    try {
      await billState.deleteBill([selectedId]);

      // 삭제 후 선택 해제
      if (context.mounted) {
        billState.toggleBillSelection(selectedId); // 또는 billState.clearSelection();
        showSuccessSnackbar(context, '선택된 항목이 삭제되었습니다.');
      }
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '삭제 중 오류가 발생했습니다.');
      }
    }
  }

  Future<void> _handleEdit(BuildContext context) async {
    // 기존 동작: 준비 중 안내
    showSelectedSnackbar(context, '수정 기능은 준비 중입니다.');
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final hasSelection = context.select<BillState, bool>((s) => s.selectedBillId != null);

    final won = NumberFormat.decimalPattern();

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('정산유형', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Consumer<BillState>(
        builder: (context, state, child) {
          final generalBills =
          state.generalBills.where((bill) => bill.area.trim() == currentArea).toList();
          final regularBills =
          state.regularBills.where((bill) => bill.area.trim() == currentArea).toList();

          if (generalBills.isEmpty && regularBills.isEmpty) {
            return const Center(child: Text('현재 지역에 해당하는 정산 데이터가 없습니다.'));
          }

          return ListView(
            children: [
              if (generalBills.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('변동 정산', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1.0),
                ...generalBills.map((bill) => _buildGeneralBillTile(context, state, bill, won)),
              ],
              if (regularBills.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text('고정 정산', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1.0),
                ...regularBills.map((bill) => _buildRegularBillTile(context, state, bill, won)),
              ],
              const SizedBox(height: 12),
            ],
          );
        },
      ),

      // ▼ FAB 세트(현대적 알약형 버튼 + 하단 여백으로 위치 조절)
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: hasSelection,
        onAdd: () => _showBillSettingBottomSheet(context),
        onEdit: hasSelection ? () => _handleEdit(context) : null,
        onDelete: hasSelection ? () => _deleteSelectedBill(context) : null,
        cs: cs,
      ),
    );
  }

  Widget _buildGeneralBillTile(
      BuildContext context,
      BillState state,
      dynamic bill,
      NumberFormat won,
      ) {
    final isSelected = state.selectedBillId == bill.id;

    return ListTile(
      key: ValueKey(bill.id),
      selected: isSelected,
      selectedTileColor: Colors.green[50],
      tileColor: isSelected ? Colors.green[50] : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(
        bill.countType,
        style: const TextStyle(fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('기본 기준: ${bill.basicStandard}, 기본 금액: ₩${won.format(bill.basicAmount)}'),
          Text('추가 기준: ${bill.addStandard}, 추가 금액: ₩${won.format(bill.addAmount)}'),
        ],
      ),
      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
      onTap: () => state.toggleBillSelection(bill.id),
    );
  }

  Widget _buildRegularBillTile(
      BuildContext context,
      BillState state,
      dynamic bill,
      NumberFormat won,
      ) {
    final isSelected = state.selectedBillId == bill.id;

    return ListTile(
      key: ValueKey(bill.id),
      selected: isSelected,
      selectedTileColor: Colors.green[50],
      tileColor: isSelected ? Colors.green[50] : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(
        bill.countType,
        style: const TextStyle(fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('고정 유형: ${bill.regularType}'),
          Text('요금: ₩${won.format(bill.regularAmount)} · 이용 시간: ${won.format(bill.regularDurationHours)}시간'),
        ],
      ),
      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
      onTap: () => state.toggleBillSelection(bill.id),
    );
  }
}

/// 현대적인 FAB 세트(라운드 필 버튼 + 하단 spacer로 위치 조절)
class _FabStack extends StatelessWidget {
  const _FabStack({
    required this.bottomGap,
    required this.spacing,
    required this.hasSelection,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.cs,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;
  final VoidCallback onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 3,
      shadowColor: cs.shadow.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle editStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      elevation: 3,
      shadowColor: cs.secondary.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle deleteStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.error,
      foregroundColor: cs.onError,
      elevation: 3,
      shadowColor: cs.error.withOpacity(0.35),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Column(
      mainAxisSize: MainAxisSize.min, // ✅ 소문자 min
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 선택 없음 → '추가'만 표시
        if (!hasSelection) ...[
          _ElevatedPillButton.icon(
            icon: Icons.add,
            label: '추가',
            style: primaryStyle,
            onPressed: onAdd,
          ),
        ] else ...[
          // 선택 있음 → '수정'·'삭제' 표시
          _ElevatedPillButton.icon(
            icon: Icons.edit,
            label: '수정',
            style: editStyle,
            onPressed: onEdit!,
          ),
          SizedBox(height: spacing),
          _ElevatedPillButton.icon(
            icon: Icons.delete,
            label: '삭제',
            style: deleteStyle,
            onPressed: onDelete!,
          ),
        ],
        SizedBox(height: bottomGap), // ▼ 하단 여백으로 버튼 위치 올리기
      ],
    );
  }
}

/// 둥근 알약 형태의 현대적 버튼 래퍼 (ElevatedButton 기반)
class _ElevatedPillButton extends StatelessWidget {
  const _ElevatedPillButton({
    required this.child,
    required this.onPressed,
    required this.style,
    Key? key,
  }) : super(key: key);

  // ✅ const 생성자 대신 factory로 위임하여 상수 제약(Invalid constant value) 회피
  factory _ElevatedPillButton.icon({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required ButtonStyle style,
    Key? key,
  }) {
    return _ElevatedPillButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: _FabLabel(icon: icon, label: label),
    );
  }

  final Widget child;
  final VoidCallback onPressed;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

/// 아이콘 + 라벨(간격/정렬 최적화)
class _FabLabel extends StatelessWidget {
  const _FabLabel({required this.icon, required this.label, Key? key}) : super(key: key);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
