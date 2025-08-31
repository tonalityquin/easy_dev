import 'package:flutter/material.dart';

class BottomButtons extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;

  // 옵션: 상태/라벨/아이콘/활성화 제어
  final bool isBusy;
  final bool isSaveEnabled;
  final String cancelLabel;
  final String saveLabel;
  final IconData? cancelIcon;
  final IconData? saveIcon;

  const BottomButtons({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.isBusy = false,
    this.isSaveEnabled = true,
    this.cancelLabel = '취소',
    this.saveLabel = '저장',
    this.cancelIcon,
    this.saveIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea( // 바텀 인셋 보호
      top: false,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : onCancel,
              icon: Icon(cancelIcon ?? Icons.close),
              label: Text(cancelLabel),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48), // 접근성
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (!isSaveEnabled || isBusy) ? null : onSave,
              icon: isBusy
                  ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Icon(saveIcon ?? Icons.check),
              label: Text(isBusy ? '저장 중...' : saveLabel),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: cs.primary,     // 테마 기반
                foregroundColor: cs.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
