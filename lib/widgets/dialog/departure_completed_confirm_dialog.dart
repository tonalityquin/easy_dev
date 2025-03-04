import 'package:flutter/material.dart';

/// 출차 완료 확인 다이얼로그 위젯
class DepartureCompletedConfirmDialog extends StatelessWidget {
  final VoidCallback onConfirm; // 출차 완료 실행 함수

  const DepartureCompletedConfirmDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('출차 완료 확인'),
      content: const Text('정말로 출차 완료 처리를 하시겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // 취소: 다이얼로그 닫기
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context); // 다이얼로그 닫기
            onConfirm(); // ✅ 출차 완료 실행
          },
          child: const Text('확인', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

