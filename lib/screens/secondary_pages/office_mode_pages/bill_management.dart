import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../utils/snackbar_helper.dart';
import '../../../states/bill/bill_state.dart';
import '../../../states/area/area_state.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'bill_pages/bill_setting.dart';

class BillManagement extends StatefulWidget {
  const BillManagement({super.key});

  @override
  State<BillManagement> createState() => _BillManagementState();
}

class _BillManagementState extends State<BillManagement> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Future.delayed(Duration.zero, () {
      if (context.mounted) {
        context.read<BillState>().manualBillRefresh();
      }
    });
  }

  void _showBillSettingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: BillSetting(
            onSave: (billData) async {
              try {
                await context.read<BillState>().addBill(
                  billData['CountType'],
                  billData['area'],
                  billData['basicStandard'].toString(),
                  billData['basicAmount'].toString(),
                  billData['addStandard'].toString(),
                  billData['addAmount'].toString(),
                );
                if (context.mounted) {
                  showSuccessSnackbar(context, '✅ 정산 데이터가 성공적으로 추가되었습니다. 앱을 재실행하세요.');
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

  Future<void> _deleteSelectedBill(BuildContext context) async {
    final billState = context.read<BillState>();
    final selectedId = billState.selectedBillId;

    if (selectedId == null) {
      if (context.mounted) {
        showFailedSnackbar(context, '삭제할 항목을 선택하세요.');
      }
      return;
    }

    try {
      await billState.deleteBill([selectedId]);
      if (context.mounted) {
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
          final bills = state.bills.where((bill) => bill.area.trim() == currentArea).toList();

          if (bills.isEmpty) {
            return const Center(child: Text('현재 지역에 해당하는 정산 데이터가 없습니다.'));
          }

          return ListView.separated(
            itemCount: bills.length,
            separatorBuilder: (_, __) => const Divider(height: 1.0, color: Colors.grey),
            itemBuilder: (context, index) {
              final bill = bills[index];
              final isSelected = state.selectedBillId == bill.id;

              return ListTile(
                tileColor: isSelected ? Colors.green[50] : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                title: Text(
                  bill.countType,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('기본 기준: ${bill.basicStandard}, 기본 금액: ${bill.basicAmount}'),
                    Text('추가 기준: ${bill.addStandard}, 추가 금액: ${bill.addAmount}'),
                  ],
                ),
                trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () => state.toggleBillSelection(bill.id),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: [Icons.add, Icons.delete],
        onIconTapped: (index) {
          if (index == 0) {
            _showBillSettingDialog(context);
          } else if (index == 1) {
            _deleteSelectedBill(context);
          }
        },
      ),
    );
  }
}
