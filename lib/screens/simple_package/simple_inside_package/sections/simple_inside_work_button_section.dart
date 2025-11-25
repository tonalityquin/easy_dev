import 'package:flutter/material.dart';

// 전체 화면 바텀 시트를 띄우는 헬퍼 함수 import
import '../widgets/simple_inside_work_bottom_sheet.dart';

class SimpleInsideWorkButtonSection extends StatelessWidget {
  /// 필요하다면 보고 버튼처럼 비활성화 플래그도 쓸 수 있게 확장
  final bool isDisabled;

  const SimpleInsideWorkButtonSection({
    super.key,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(
        Icons.access_time,
      ),
      label: const Text(
        '출근하기',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Colors.grey, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      // 여기서 직접 헬퍼 함수 호출 (Report 버튼과 동일 패턴)
      onPressed:
      isDisabled ? null : () => showSimpleInsideWorkFullScreenBottomSheet(context),
    );
  }
}
