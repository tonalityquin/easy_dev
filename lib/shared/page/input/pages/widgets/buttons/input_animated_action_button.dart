import 'package:flutter/material.dart';

import '../../../../../../design_system/common_ui/common_ui_components.dart';

class InputAnimatedActionButton extends StatelessWidget {
  final bool isLoading;
  final bool isLocationSelected;
  final bool isMinorMode;
  final bool isStatusLookupInProgress;
  final Future<void> Function() onPressed;

  const InputAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.isMinorMode,
    required this.isStatusLookupInProgress,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final requestMode = isMinorMode && !isLocationSelected;
    final disabled = isLoading ||
        isStatusLookupInProgress ||
        (!isMinorMode && !isLocationSelected);
    return CommonButton(
      label: isStatusLookupInProgress
          ? '상태 확인 중'
          : requestMode
              ? '입차 요청'
              : '입차 완료',
      icon: isStatusLookupInProgress
          ? Icons.sync_rounded
          : requestMode
              ? Icons.outbox_rounded
              : Icons.check_circle_outline_rounded,
      loading: isLoading || isStatusLookupInProgress,
      expand: true,
      haptic: CommonHaptic.medium,
      onPressed: disabled ? null : onPressed,
    );
  }
}
