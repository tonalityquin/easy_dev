// lib/screens/secondary_package/office_mode_package/bill_management_package/sections/bill_bottom_buttons_section.dart
import 'package:flutter/material.dart';

/// 서비스 로그인 카드 팔레트(리팩터링 공통 색)
const serviceCardBase  = Color(0xFF0D47A1);
const serviceCardDark  = Color(0xFF09367D);
const serviceCardLight = Color(0xFF5472D3);
const serviceCardFg    = Colors.white; // 버튼/아이콘 전경
const serviceCardBg    = Colors.white; // 카드/시트 배경

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
    return SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : onCancel,
              icon: Icon(cancelIcon ?? Icons.close, color: serviceCardBase),
              label: Text(
                cancelLabel,
                style: const TextStyle(fontWeight: FontWeight.w600, color: serviceCardBase),
              ),
              style: OutlinedButton
                  .styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: serviceCardBase,
                side: const BorderSide(color: serviceCardBase, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              )
                  .copyWith(
                // ↓ overlay는 styleFrom이 아닌 copyWith로 지정
                overlayColor: WidgetStatePropertyAll(
                  serviceCardLight.withOpacity(0.08),
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
                child: CircularProgressIndicator(strokeWidth: 2, color: serviceCardFg),
              )
                  : Icon(saveIcon ?? Icons.check, color: serviceCardFg),
              label: Text(
                isBusy ? '저장 중...' : saveLabel,
                style: const TextStyle(fontWeight: FontWeight.w700, color: serviceCardFg),
              ),
              style: ElevatedButton
                  .styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: serviceCardBase,
                foregroundColor: serviceCardFg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
                shadowColor: serviceCardDark.withOpacity(0.25),
              )
                  .copyWith(
                // ↓ overlay는 styleFrom이 아닌 copyWith로 지정
                overlayColor: WidgetStatePropertyAll(
                  serviceCardLight.withOpacity(0.08),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
