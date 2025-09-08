import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final primary = Theme.of(context).colorScheme.primary;

    return TextField(
      controller: controller,
      readOnly: true,            // 읽기 전용 유지
      enableSuggestions: false,  // 불필요한 제안/자동수정 비활성화
      autocorrect: false,
      enableInteractiveSelection: true, // 평문 표시이므로 선택/복사 허용
      style: TextStyle(
        // 숫자 가독성 향상(선택)
        fontFeatures: enableMonospace ? const [FontFeature.tabularFigures()] : null,
        letterSpacing: 0.5,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: allowCopy
            ? IconButton(
          tooltip: '복사',
          onPressed: () => _copyToClipboard(context),
          icon: const Icon(Icons.copy),
        )
            : null,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primary), // 테마 컬러 사용
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
