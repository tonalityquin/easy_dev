import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// snackbar_helper 경로는 현재 파일(…/sections/…) 기준으로 계산
import '../../../../../utils/snackbar_helper.dart';

/// 서비스 로그인 카드와 동일 톤의 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1);  // primary
  static const dark = Color(0xFF09367D);  // 진한 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 라이트 톤/보더
}

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
    return TextField(
      controller: controller,
      readOnly: true,            // 읽기 전용 유지
      enableSuggestions: false,  // 불필요한 제안/자동수정 비활성화
      autocorrect: false,
      enableInteractiveSelection: true, // 평문 표시이므로 선택/복사 허용
      style: TextStyle(
        // 숫자 가독성 향상(선택)
        // ⚠️ 리스트에 const 사용하지 않음(컴파일타임 상수 이슈 방지)
        fontFeatures: enableMonospace ? [FontFeature.tabularFigures()] : null,
        letterSpacing: 0.5,
      ),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelStyle: const TextStyle(
          color: _SvcColors.dark,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: const Icon(Icons.lock, color: _SvcColors.dark),
        suffixIcon: allowCopy
            ? IconButton(
          tooltip: '복사',
          onPressed: () => _copyToClipboard(context),
          icon: const Icon(Icons.copy, color: _SvcColors.dark),
        )
            : null,

        // 토널 느낌
        filled: true,
        fillColor: _SvcColors.light.withOpacity(.06),

        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),

        // 보더 톤 정리(라이트/포커스/에러)
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _SvcColors.light.withOpacity(.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _SvcColors.base, width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
