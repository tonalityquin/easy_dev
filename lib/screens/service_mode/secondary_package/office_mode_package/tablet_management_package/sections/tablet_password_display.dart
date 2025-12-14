import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 서비스 로그인 카드와 동일 계열 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1); // Deep Blue (서비스 카드 primary)
}

class TabletPasswordDisplay extends StatelessWidget {
  final TextEditingController controller;

  /// 라벨 커스터마이즈(기본: '비밀번호')
  final String label;

  /// 복사 버튼 노출/동작 여부
  final bool allowCopy;

  /// 숫자 가독성을 위한 고정폭(탭룰러) 사용 여부
  final bool enableMonospace;

  const TabletPasswordDisplay({
    super.key,
    required this.controller,
    this.label = '비밀번호',
    this.allowCopy = true,
    this.enableMonospace = false,
  });

  Future<void> _copyToClipboard(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: controller.text));
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      const SnackBar(content: Text('비밀번호가 복사되었습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const base = _SvcColors.base;

    return TextField(
      controller: controller,
      readOnly: true,                  // 읽기 전용 유지
      enableSuggestions: false,        // 불필요한 제안/자동수정 비활성화
      autocorrect: false,
      enableInteractiveSelection: true, // 평문 표시이므로 선택/복사 허용
      cursorColor: base,
      style: TextStyle(
        // 숫자 가독성 향상(선택)
        fontFeatures: enableMonospace ? const [FontFeature.tabularFigures()] : null,
        letterSpacing: 0.5,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock),
        prefixIconColor: base.withOpacity(.85),
        suffixIcon: allowCopy
            ? IconButton(
          tooltip: '복사',
          onPressed: () => _copyToClipboard(context),
          icon: const Icon(Icons.copy),
          color: base.withOpacity(.85),
        )
            : null,
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: base), // 서비스 팔레트 컬러
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: base.withOpacity(.28)),
          borderRadius: BorderRadius.circular(8),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
    );
  }
}
