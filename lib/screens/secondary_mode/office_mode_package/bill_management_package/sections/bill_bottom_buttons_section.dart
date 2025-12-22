// lib/screens/secondary_package/office_mode_package/bill_management_package/sections/bill_bottom_buttons_section.dart
import 'package:flutter/material.dart';

import '../../../../../../theme.dart'; // ✅ AppCardPalette 사용 (프로젝트 경로에 맞게 조정)

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
    // ✅ Service 팔레트: ThemeExtension(AppCardPalette)에서 획득
    final palette = AppCardPalette.of(context);
    final serviceBase = palette.serviceBase;
    final serviceDark = palette.serviceDark;
    final serviceLight = palette.serviceLight;

    // 기존 상수의 의미 유지(전경/배경)
    const fg = Colors.white;

    return SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : onCancel,
              icon: Icon(cancelIcon ?? Icons.close, color: serviceBase),
              label: Text(
                cancelLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: serviceBase,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: serviceBase,
                side: BorderSide(color: serviceBase, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ).copyWith(
                // ↓ overlay는 styleFrom이 아닌 copyWith로 지정
                overlayColor: WidgetStatePropertyAll(
                  serviceLight.withOpacity(0.08),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (!isSaveEnabled || isBusy) ? null : onSave,
              icon: isBusy
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
                  : Icon(saveIcon ?? Icons.check, color: fg),
              label: Text(
                isBusy ? '저장 중...' : saveLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: serviceBase,
                foregroundColor: fg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
                shadowColor: serviceDark.withOpacity(0.25),
              ).copyWith(
                // ↓ overlay는 styleFrom이 아닌 copyWith로 지정
                overlayColor: WidgetStatePropertyAll(
                  serviceLight.withOpacity(0.08),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
