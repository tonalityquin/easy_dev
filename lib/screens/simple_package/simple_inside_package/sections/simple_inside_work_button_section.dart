import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../states/user/user_state.dart';

class SimpleInsideWorkButtonSection extends StatelessWidget {
  const SimpleInsideWorkButtonSection({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;
    final label = isWorking ? '출근 중' : '출근하기';

    return ElevatedButton.icon(
      icon: const Icon(Icons.access_time),
      label: Text(
        label,
        style: const TextStyle(
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
      // 🔹 isWorking 이면 기존처럼 비활성화
      onPressed: isWorking
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
          height: height, // 🔹 기기 전체 높이 사용
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
                        '출근하기 바텀 시트',
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

                // 임의의 텍스트 영역
                const Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      '여기는 출근하기 버튼용 임의의 텍스트 영역입니다.\n\n'
                          '• 더미 텍스트 A: 출근 시 안내 문구\n'
                          '• 더미 텍스트 B: 근무 수칙 또는 공지\n'
                          '• 더미 텍스트 C: 기타 설명 텍스트\n\n'
                          '나중에 이 영역을 실제 출근 처리 UI(시간 표시, 메모 입력, '
                          '확인 버튼 등)로 교체해서 사용할 수 있습니다.',
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
