import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MinorModifyAnimatedPhotoButton extends StatefulWidget {
  final VoidCallback onPressed;

  const MinorModifyAnimatedPhotoButton({
    super.key,
    required this.onPressed,
  });

  @override
  State<MinorModifyAnimatedPhotoButton> createState() =>
      _MinorModifyAnimatedPhotoButtonState();
}

class _MinorModifyAnimatedPhotoButtonState
    extends State<MinorModifyAnimatedPhotoButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  bool _tapBusy = false;

  @override
  void initState() {
    super.initState();
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
    if (_tapBusy) return;
    setState(() => _tapBusy = true);

    try {
      HapticFeedback.selectionClick();

      await _pressCtrl.reverse();
      await _pressCtrl.forward();

      widget.onPressed();
    } finally {
      if (mounted) setState(() => _tapBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ 사진 계열은 tertiary 톤으로(프로젝트 테마가 없으면 기본 tertiary 제공)
    final Color bg = cs.tertiaryContainer;
    final Color fg = cs.onTertiaryContainer;
    final Color border = cs.tertiary.withOpacity(0.65);

    return ScaleTransition(
      scale: _scale,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _tapBusy ? null : _handleTap,
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
          child: const Text(
            '사진 촬영',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
