import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// snackbar_helper 경로는 현재 파일(…/sections/…) 기준으로 계산
import '../../../../../../utils/snackbar_helper.dart';

// ✅ AppCardPalette 정의 파일을 프로젝트 경로에 맞게 import 하세요.
// 예) import 'package:your_app/theme/app_card_palette.dart';
import '../../../../../../theme.dart';

class UserPasswordDisplaySection extends StatelessWidget {
  final TextEditingController controller;

  /// 라벨 커스터마이즈(기본: '비밀번호')
  final String label;

  /// 복사 버튼 노출/동작 여부
  final bool allowCopy;

  /// 숫자 가독성을 위한 고정폭(탭룰러) 사용 여부
  final bool enableMonospace;

  const UserPasswordDisplaySection({
    super.key,
    required this.controller,
    this.label = '비밀번호',
    this.allowCopy = true,
    this.enableMonospace = false,
  });

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: controller.text));
    // 일관된 토스트 스타일
    showSuccessSnackbar(context, '비밀번호가 복사되었습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;
    final dark = palette.serviceDark;
    final light = palette.serviceLight;

    return TextField(
      controller: controller,
      readOnly: true, // 읽기 전용 유지
      enableSuggestions: false,
      autocorrect: false,
      enableInteractiveSelection: true,
      style: TextStyle(
        fontFeatures: enableMonospace ? [FontFeature.tabularFigures()] : null,
        letterSpacing: 0.5,
      ),
      decoration: InputDecoration(
        labelText: label,
        helperText: '읽기 전용(자동 생성). 복사해서 전달하세요.',
        floatingLabelStyle: TextStyle(
          color: dark,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(Icons.lock, color: dark),
        suffixIcon: allowCopy
            ? IconButton(
          tooltip: '복사',
          onPressed: () => _copyToClipboard(context),
          icon: Icon(Icons.copy, color: dark),
        )
            : null,
        filled: true,
        fillColor: light.withOpacity(.06),
        isDense: true,
        contentPadding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: light.withOpacity(.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: base, width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
