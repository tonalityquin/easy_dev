import 'package:flutter/material.dart';

class BillBottomButtonsSection extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSave;

  // 옵션: 상태/라벨/아이콘/활성화 제어
  final bool isBusy;
  final bool isSaveEnabled;
  final String cancelLabel;
  final String saveLabel;
  final IconData? cancelIcon;
  final IconData? saveIcon;

  const BillBottomButtonsSection({
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

    return SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : onCancel,
              icon: Icon(cancelIcon ?? Icons.close, color: cs.primary),
              label: Text(
                cancelLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary.withOpacity(.85), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ).copyWith(
                overlayColor: WidgetStatePropertyAll(
                  cs.primary.withOpacity(0.08),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (!isSaveEnabled || isBusy) ? null : onSave,
              icon: isBusy
                  ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onPrimary,
                ),
              )
                  : Icon(saveIcon ?? Icons.check, color: cs.onPrimary),
              label: Text(
                isBusy ? '저장 중...' : saveLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onPrimary,
                ),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
                shadowColor: cs.shadow.withOpacity(0.20),
              ).copyWith(
                overlayColor: WidgetStatePropertyAll(
                  cs.onPrimary.withOpacity(0.08),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
