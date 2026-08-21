import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../shared/page/application/common/type_auto_transition_guard.dart';

class DoubleParkingCompletedControlButtons extends StatelessWidget {
  const DoubleParkingCompletedControlButtons({
    super.key,
    required this.showSearchDialog,
  });

  final Future<void> Function() showSearchDialog;

  Future<void> _openSearch(BuildContext context) async {
    final guard = context.read<TypeAutoTransitionGuard>();
    await guard.runBlocked<void>(
      '검색',
      showSearchDialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonButton(
      label: '검색',
      icon: Icons.manage_search_rounded,
      onPressed: () => _openSearch(context),
      variant: CommonButtonVariant.secondary,
      expand: true,
      minHeight: 48,
      haptic: CommonHaptic.selection,
    );
  }
}
