// lib/screens/simple_package/simple_inside_package/sections/simple_inside_report_button_section.dart
import 'package:flutter/material.dart';

class SimpleInsideReportButtonSection extends StatelessWidget {
  final bool isDisabled;

  const SimpleInsideReportButtonSection({
    super.key,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.report),
      label: const Text(
        '출근 보고',
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
      onPressed: isDisabled
          ? null
          : () => _showFullScreenBottomSheet(context),
    );
  }
}

void _showFullScreenBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (sheetCtx) {
      final height = MediaQuery.of(sheetCtx).size.height;

      return SafeArea(
        child: SizedBox(
          height: height, // 🔹 기기 전체 높이만큼 바텀 시트
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 헤더 + 닫기 버튼
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '출근 보고 바텀 시트',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 임의의 텍스트 영역 (더미 내용)
                const Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      '여기는 임의의 텍스트 영역입니다.\n\n'
                          '• 더미 텍스트 1: 출근 관련 안내 문구\n'
                          '• 더미 텍스트 2: 회사 규칙 또는 공지\n'
                          '• 더미 텍스트 3: 기타 설명 텍스트\n\n'
                          '이 영역의 내용은 나중에 실제 출근 보고 UI나 '
                          '폼으로 교체해서 사용하면 됩니다.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
