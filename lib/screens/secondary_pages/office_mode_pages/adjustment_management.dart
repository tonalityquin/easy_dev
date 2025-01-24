import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/adjustment_state.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바
import '../../../widgets/container/adjustment_custom_box.dart'; // CustomBox 사용
import 'adjustment_pages/adjustment_setting.dart'; // AdjustmentSetting 페이지 추가

class AdjustmentManagement extends StatelessWidget {
  const AdjustmentManagement({Key? key}) : super(key: key);

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
              // Firestore에 데이터 저장
              await context.read<AdjustmentState>().addAdjustments(
                adjustmentData['CountType'],
                adjustmentData['area'],
                adjustmentData['basicStandard'],
                adjustmentData['basicAmount'],
                adjustmentData['addStandard'],
                adjustmentData['addAmount'],
              );
            },
          ),
        );
      },
    );
  }

  /// 선택된 Adjustment를 Firestore에서 삭제
  Future<void> _deleteSelectedAdjustments(BuildContext context) async {
    final adjustmentState = context.read<AdjustmentState>();
    final selectedIds = adjustmentState.selectedAdjustments.entries
        .where((entry) => entry.value) // 선택된 항목만 필터링
        .map((entry) => entry.key)
        .toList();

    if (selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제할 항목을 선택하세요.')),
      );
      return;
    }

    try {
      await adjustmentState.deleteAdjustments(selectedIds); // 선택된 항목 삭제
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택된 항목이 삭제되었습니다.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제 중 오류가 발생했습니다.')),
      );
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
          debugPrint('Adjustment 데이터를 UI에서 수신: $adjustments'); // 로그 추가

          if (adjustments.isEmpty) {
            return const Center(child: Text('No adjustments found'));
          }

          return ListView.builder(
            itemCount: adjustments.length,
            itemBuilder: (context, index) {
              final adjustment = adjustments[index];

              // 값이 누락되었을 경우 기본값 설정
              final countType = adjustment['CountType'] ?? 'Unknown';
              final basicStandard = adjustment['basicStandard'] ?? 'Unknown';
              final basicAmount = adjustment['basicAmount'] ?? '0';
              final addStandard = adjustment['addStandard'] ?? 'Unknown';
              final addAmount = adjustment['addAmount'] ?? '0';
              final isSelected = adjustment['isSelected'] ?? false;

              return Column(
                children: [
                  AdjustmentCustomBox(
                    leftText: countType, // CountType 표시
                    centerTopText: "기본 기준: $basicStandard", // 기본 기준
                    centerBottomText: "기본 금액: $basicAmount", // 기본 금액
                    rightTopText: "추가 기준: $addStandard", // 추가 기준
                    rightBottomText: "추가 금액: $addAmount", // 추가 금액
                    onTap: () {
                      context
                          .read<AdjustmentState>()
                          .toggleSelection(adjustment['id']); // 선택 상태 토글
                    },
                    backgroundColor: isSelected ? Colors.greenAccent : Colors.white,
                  ),
                  const Divider(height: 1.0, color: Colors.grey), // Divider 추가
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        // 하단 내비게이션
        icons: [
          Icons.add, // 정산 유형 추가 아이콘
          Icons.delete, // 정산 유형 삭제 아이콘
          Icons.tire_repair, // 정산 유형 수정 아이콘
        ],
        onIconTapped: (index) {
          if (index == 0) {
            _showAdjustmentSettingDialog(context); // Add 아이콘 클릭 시 AdjustmentSetting 페이지 팝업 열기
          } else if (index == 1) {
            _deleteSelectedAdjustments(context); // Delete 아이콘 클릭 시 선택된 Adjustment 삭제
          }
          // 추가로 다른 아이콘들에 대한 동작도 정의할 수 있음
        },
      ),
    );
  }
}
