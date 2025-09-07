import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../states/bill/bill_state.dart';
import '../../../states/area/area_state.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
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

  void _showBillSettingBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return BillSettingBottomSheet(
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

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final hasSelection = context.select<BillState, bool>((s) => s.selectedBillId != null);

    final won = NumberFormat.decimalPattern();

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
          final generalBills = state.generalBills.where((bill) => bill.area.trim() == currentArea).toList();
          final regularBills = state.regularBills.where((bill) => bill.area.trim() == currentArea).toList();

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
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: hasSelection ? const [Icons.edit, Icons.delete] : const [Icons.add, Icons.delete],
        onIconTapped: (index) async {
          if (!hasSelection) {
            if (index == 0) {
              _showBillSettingBottomSheet(context);
            } else if (index == 1) {
              showFailedSnackbar(context, '삭제할 항목을 선택하세요.');
            }
          } else {
            if (index == 0) {
              showSelectedSnackbar(context, '수정 기능은 준비 중입니다.');
            } else if (index == 1) {
              await _deleteSelectedBill(context);
            }
          }
        },
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
