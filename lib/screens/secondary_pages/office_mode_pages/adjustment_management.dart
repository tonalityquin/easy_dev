import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바
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
          elevation: 16,
          child: AdjustmentSetting(
            onSave: (adjustment) {
              // AdjustmentSetting에서 저장 버튼 클릭 후 할 작업을 처리
              // 예를 들어, 저장된 값을 처리할 수 있습니다.
              Navigator.of(context).pop(); // 팝업 닫기
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: const Center(
        child: Text('Adjustment Page'), // 본문
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        // 하단 내비게이션
        icons: [
          Icons.add, // 정산 유형 추가 아이콘
          Icons.delete, // 정산 유형 삭제 아이콘
          Icons.tire_repair, // 정산 유형 수정 아이콘
        ],
        onIconTapped: (index) {
          // 하단 내비게이션 아이콘 클릭 시의 동작 정의
          if (index == 0) {
            _showAdjustmentSettingDialog(context); // Add 아이콘 클릭 시 AdjustmentSetting 페이지 팝업 열기
          }
          // 추가로 다른 아이콘들에 대한 동작도 정의할 수 있음
        },
      ),
    );
  }
}
