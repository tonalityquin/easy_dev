import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/adjustment_state.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바
import '../../../widgets/container/adjustment_custom_box.dart'; // CustomBox 사용
import 'adjustment_pages/adjustment_setting.dart'; // AdjustmentSetting 페이지 추가

class AdjustmentManagement extends StatelessWidget {
  const AdjustmentManagement({Key? key}) : super(key: key);

  /// SnackBar 메시지 표시 헬퍼 함수
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 선택된 Adjustment ID 목록 반환
  List<String> _getSelectedIds(AdjustmentState state) {
    return state.selectedAdjustments.entries
        .where((entry) => entry.value) // 선택된 항목만 필터링
        .map((entry) => entry.key)
        .toList();
  }

  /// Add 아이콘 클릭 시 AdjustmentSetting 페이지를 팝업으로 열기
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
                _showSnackBar(context, '정산 데이터가 성공적으로 추가되었습니다.');
              } catch (e) {
                _showSnackBar(context, '데이터 추가 중 오류가 발생했습니다.');
              }
            },
          ),
        );
      },
    );
  }

  /// 선택된 Adjustment를 Firestore에서 삭제
  Future<void> _deleteSelectedAdjustments(BuildContext context) async {
    final adjustmentState = context.read<AdjustmentState>();
    final selectedIds = _getSelectedIds(adjustmentState);

    if (selectedIds.isEmpty) {
      _showSnackBar(context, '삭제할 항목을 선택하세요.');
      return;
    }

    try {
      await adjustmentState.deleteAdjustments(selectedIds);
      _showSnackBar(context, '선택된 항목이 삭제되었습니다.');
    } catch (e) {
      _showSnackBar(context, '삭제 중 오류가 발생했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: context.watch<AdjustmentState>().adjustmentsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('Error: ${snapshot.error}');
            return const Center(child: Text('Error loading data'));
          }

          final adjustments = snapshot.data ?? [];
          if (adjustments.isEmpty) {
            return const Center(child: Text('No adjustments found'));
          }

          return ListView.builder(
            itemCount: adjustments.length,
            itemBuilder: (context, index) {
              final adjustment = adjustments[index];

              final countType = adjustment['CountType'] ?? 'Unknown';
              final basicStandard = adjustment['basicStandard'] ?? 'Unknown';
              final basicAmount = adjustment['basicAmount'] ?? '0';
              final addStandard = adjustment['addStandard'] ?? 'Unknown';
              final addAmount = adjustment['addAmount'] ?? '0';
              final isSelected = adjustment['isSelected'] ?? false;

              return Column(
                children: [
                  AdjustmentCustomBox(
                    leftText: countType,
                    centerTopText: "기본 기준: $basicStandard",
                    centerBottomText: "기본 금액: $basicAmount",
                    rightTopText: "추가 기준: $addStandard",
                    rightBottomText: "추가 금액: $addAmount",
                    onTap: () async {
                      try {
                        // ID 검증 추가
                        if (adjustment['id'] == null) {
                          throw Exception('Invalid data: ID is null');
                        }

                        await context.read<AdjustmentState>().toggleSelection(adjustment['id']);
                        _showSnackBar(
                          context,
                          isSelected ? '선택 해제되었습니다.' : '선택되었습니다.',
                        );
                      } catch (e) {
                        _showSnackBar(context, '선택 상태 변경 중 오류가 발생했습니다.');
                      }
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
          Icons.tire_repair,
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
