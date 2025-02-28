import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/show_snackbar.dart';
import '../../../states/adjustment_state.dart';
import '../../../states/area_state.dart'; // 🔥 지역 상태 추가
import '../../../widgets/navigation/secondary_role_navigation.dart';
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
      context.read<AdjustmentState>().syncWithAreaState();
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
                      adjustmentData['basicStandard'],
                      adjustmentData['basicAmount'],
                      adjustmentData['addStandard'],
                      adjustmentData['addAmount'],
                    );
                showSnackbar(context, '정산 데이터가 성공적으로 추가되었습니다.'); // ✅ showSnackbar 적용
              } catch (e) {
                showSnackbar(context, '데이터 추가 중 오류가 발생했습니다.'); // ✅ showSnackbar 적용
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
      showSnackbar(context, '삭제할 항목을 선택하세요.'); // ✅ showSnackbar 적용
      return;
    }

    try {
      await adjustmentState.deleteAdjustments(selectedIds);
      showSnackbar(context, '선택된 항목이 삭제되었습니다.'); // ✅ showSnackbar 적용
    } catch (e) {
      showSnackbar(context, '삭제 중 오류가 발생했습니다.'); // ✅ showSnackbar 적용
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: Consumer<AdjustmentState>(
        builder: (context, state, child) {
          final currentArea = context.watch<AreaState>().currentArea.trim(); // 🔥 현재 지역 가져오기

          // 🔥 현재 지역과 일치하는 데이터만 필터링
          final adjustments = state.adjustments.where((adj) => adj['area'].toString().trim() == currentArea).toList();

          if (adjustments.isEmpty) {
            return const Center(child: Text('현재 지역에 해당하는 정산 데이터가 없습니다.'));
          }

          return ListView.builder(
            itemCount: adjustments.length,
            itemBuilder: (context, index) {
              final adjustment = adjustments[index];
              final id = adjustment['id'] ?? '';
              final countType = adjustment['countType'] ?? 'Unknown';
              final basicStandard = adjustment['basicStandard'] ?? 'Unknown';
              final basicAmount = adjustment['basicAmount'] ?? '0';
              final addStandard = adjustment['addStandard'] ?? 'Unknown';
              final addAmount = adjustment['addAmount'] ?? '0';
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
                    backgroundColor: isSelected ? Colors.greenAccent : Colors.white,
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
