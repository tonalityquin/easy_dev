import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../states/adjustment/adjustment_state.dart';
import '../../../states/area/area_state.dart'; // 🔥 지역 상태 추가
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import '../../../widgets/container/adjustment_custom_box.dart';
import 'adjustment_pages/adjustment_setting.dart';

class AdjustmentManagement extends StatefulWidget {
  const AdjustmentManagement({super.key});

  @override
  State<AdjustmentManagement> createState() => _AdjustmentManagementState();
}

class _AdjustmentManagementState extends State<AdjustmentManagement> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Future.delayed(Duration.zero, () {
      if (context.mounted) {
        // ignore: use_build_context_synchronously
        context.read<AdjustmentState>().syncWithAreaAdjustmentState();
      }
    });
  }

  List<String> _getSelectedIds(AdjustmentState state) {
    return state.selectedAdjustments.entries.where((entry) => entry.value).map((entry) => entry.key).toList();
  }

  void _showAdjustmentSettingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: AdjustmentSetting(
            onSave: (adjustmentData) async {
              try {
                await context.read<AdjustmentState>().addAdjustments(
                      adjustmentData['CountType'],
                      adjustmentData['area'],
                      adjustmentData['basicStandard'].toString(), // 숫자값을 문자열로 변환하여 전달
                      adjustmentData['basicAmount'].toString(),
                      adjustmentData['addStandard'].toString(),
                      adjustmentData['addAmount'].toString(),
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

  Future<void> _deleteSelectedAdjustments(BuildContext context) async {
    final adjustmentState = context.read<AdjustmentState>();
    final selectedIds = _getSelectedIds(adjustmentState);

    if (selectedIds.isEmpty) {
      if (context.mounted) {
        showFailedSnackbar(context, '삭제할 항목을 선택하세요.');
      }
      return;
    }

    try {
      await adjustmentState.deleteAdjustments(selectedIds);
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
      body: Consumer<AdjustmentState>(
        builder: (context, state, child) {
          final currentArea = context.watch<AreaState>().currentArea.trim();
          final adjustments = state.adjustments.where((adj) => adj.area.trim() == currentArea).toList();
          if (adjustments.isEmpty) {
            return const Center(child: Text('현재 지역에 해당하는 정산 데이터가 없습니다.'));
          }
          return ListView.builder(
            itemCount: adjustments.length,
            itemBuilder: (context, index) {
              final adjustment = adjustments[index];
              final id = adjustment.id;
              final countType = adjustment.countType;
              final basicStandard = adjustment.basicStandard.toString();
              final basicAmount = adjustment.basicAmount.toString();
              final addStandard = adjustment.addStandard.toString();
              final addAmount = adjustment.addAmount.toString();
              final isSelected = state.selectedAdjustments[id] ?? false;

              return Column(
                children: [
                  AdjustmentCustomBox(
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
            _showAdjustmentSettingDialog(context);
          } else if (index == 1) {
            _deleteSelectedAdjustments(context);
          }
        },
      ),
    );
  }
}
