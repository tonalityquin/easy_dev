import 'package:flutter/material.dart';

class MinorInputAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final bool isLocationSelected;
  final Future<void> Function() onPressed;

  const MinorInputAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.onPressed,
  });

  @override
  State<MinorInputAnimatedActionButton> createState() => _MinorInputAnimatedActionButtonState();
}

class _MinorInputAnimatedActionButtonState extends State<MinorInputAnimatedActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  Future<void> _handleTap() async {
    await _controller.reverse();
    await _controller.forward();

    await widget.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoading = widget.isLoading;
    final bool isLocationSelected = widget.isLocationSelected;

    // ✅ Minor 모드도 Service 모드와 동일하게
    // - 위치 선택 시: "입차 완료"
    // - 위치 미선택 시: "입차 요청"
    final String label = isLocationSelected ? '입차 완료' : '입차 요청';

    // ✅ 위치 미선택이어도 "입차 요청"으로 제출 가능해야 함
    // (로딩 중일 때만 비활성화)
    final bool isDisabled = isLoading;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: isDisabled ? null : _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isLocationSelected ? Colors.indigo[50] : Colors.blueGrey[50],
          foregroundColor: isLocationSelected ? Colors.indigo[800] : Colors.blueGrey[800],
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isLocationSelected ? Colors.indigo : Colors.blueGrey,
              width: 1.5,
            ),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: isLoading
              ? const SizedBox(
            key: ValueKey('loading'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.black,
            ),
          )
              : Text(
            key: const ValueKey('buttonText'),
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
