import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../states/bill/bill_state.dart';
import '../../../states/area/area_state.dart'; // 🔥 지역 상태 추가
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import '../../../widgets/container/bill_container.dart';
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
        // ignore: use_build_context_synchronously
        context.read<BillState>().manualBillRefresh();
      }
    });
  }

  List<String> _getSelectedIds(BillState state) {
    return state.selecteBill.entries.where((entry) => entry.value).map((entry) => entry.key).toList();
  }

  void _showBillSettingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: BillSetting(
            onSave: (billData) async {
              try {
                await context.read<BillState>().addBill(
                  billData['CountType'],
                  billData['area'],
                  billData['basicStandard'].toString(), // 숫자값을 문자열로 변환하여 전달
                  billData['basicAmount'].toString(),
                  billData['addStandard'].toString(),
                  billData['addAmount'].toString(),
                    );
                if (context.mounted) {
                  showSuccessSnackbar(context, '✅ 정산 데이터가 성공적으로 추가되었습니다. 앱을 재실행하세요.');
                }
              } catch (e) {
                debugPrint("🔥 데이터 추가 중 예외 발생: $e");
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
    final selectedIds = _getSelectedIds(billState);

    if (selectedIds.isEmpty) {
      if (context.mounted) {
        showFailedSnackbar(context, '삭제할 항목을 선택하세요.');
      }
      return;
    }

    try {
      await billState.deleteBill(selectedIds);
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '정산유형',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Consumer<BillState>(
        builder: (context, state, child) {
          final currentArea = context.watch<AreaState>().currentArea.trim();
          final bills = state.bills.where((bill) => bill.area.trim() == currentArea).toList();
          if (bills.isEmpty) {
            return const Center(child: Text('현재 지역에 해당하는 정산 데이터가 없습니다.'));
          }
          return ListView.builder(
            itemCount: bills.length,
            itemBuilder: (context, index) {
              final bill = bills[index];
              final id = bill.id;
              final countType = bill.countType;
              final basicStandard = bill.basicStandard.toString();
              final basicAmount = bill.basicAmount.toString();
              final addStandard = bill.addStandard.toString();
              final addAmount = bill.addAmount.toString();
              final isSelected = state.selecteBill[id] ?? false;

              return Column(
                children: [
                  BillContainer(
                    leftText: countType,
                    centerTopText: "기본 기준: $basicStandard",
                    centerBottomText: "기본 금액: $basicAmount",
                    rightTopText: "추가 기준: $addStandard",
                    rightBottomText: "추가 금액: $addAmount",
                    onTap: () {
                      state.toggleSelection(id);
                    },
                    isSelected: isSelected,
                  ),
                  const Divider(height: 1.0, color: Colors.grey),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: [
          Icons.add,
          Icons.delete,
        ],
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
