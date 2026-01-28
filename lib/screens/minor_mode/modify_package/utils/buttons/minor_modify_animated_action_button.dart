import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MinorModifyAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final bool isLocationSelected;
  final Future<void> Function() onPressed;
  final String? buttonLabel;

  const MinorModifyAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.onPressed,
    this.buttonLabel,
  });

  @override
  State<MinorModifyAnimatedActionButton> createState() =>
      _MinorModifyAnimatedActionButtonState();
}

class _MinorModifyAnimatedActionButtonState
    extends State<MinorModifyAnimatedActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  bool _tapBusy = false;

  @override
  void initState() {
    super.initState();

    // ✅ 초기 스케일이 0.95로 보이는 문제 방지: value=1.0로 시작
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
    )..value = 1.0;

    _scale = CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_tapBusy || widget.isLoading) return;

    setState(() => _tapBusy = true);

    try {
      HapticFeedback.lightImpact();

      await _pressCtrl.reverse();
      await _pressCtrl.forward();

      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _tapBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bool loading = widget.isLoading || _tapBusy;

    // ✅ MinorModify의 기본 액션은 "수정 완료"가 자연스러움
    final String label = (widget.buttonLabel ?? '수정 완료').trim().isEmpty
        ? '수정 완료'
        : (widget.buttonLabel ?? '수정 완료').trim();

    // ✅ location 선택 여부는 "색감 톤"에만 반영(기존 시그니처 유지)
    final bool toneSelected = widget.isLocationSelected;

    final Color bg =
    toneSelected ? cs.primaryContainer : cs.surfaceVariant.withOpacity(0.55);
    final Color fg = toneSelected ? cs.onPrimaryContainer : cs.onSurface;
    final Color border =
    toneSelected ? cs.primary.withOpacity(0.65) : cs.outlineVariant.withOpacity(0.65);

    final Color spinnerColor = fg;

    return ScaleTransition(
      scale: _scale,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: loading ? null : _handleTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: border, width: 1.4),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: loading
                ? SizedBox(
              key: const ValueKey('loading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: spinnerColor,
              ),
            )
                : Text(
              key: const ValueKey('buttonText'),
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}
