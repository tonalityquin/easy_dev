import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';

Future<bool?> showTabletPageStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function() onRequestEntry,
  required VoidCallback onDelete,
}) {
  return showPromptOverlayBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SizedBox.expand(
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: true,
          builder: (context, scrollController) {
            return _TabletStatusSheet(
              plate: plate,
              scrollController: scrollController,
            );
          },
        ),
      );
    },
  );
}

class _TabletStatusSheet extends StatefulWidget {
  const _TabletStatusSheet({
    required this.plate,
    required this.scrollController,
  });

  final PlateModel plate;
  final ScrollController scrollController;

  @override
  State<_TabletStatusSheet> createState() => _TabletStatusSheetState();
}

class _TabletStatusSheetState extends State<_TabletStatusSheet> {
  bool _submitting = false;

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final movementPlate = context.read<MovementPlate>();
      await movementPlate.setDepartureRequested(
        widget.plate.plateNumber,
        widget.plate.area,
        widget.plate.location,
        forceViewSync: true,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return PromptSheetScaffold(
      title: '출차 요청 확인',
      icon: Icons.directions_car_rounded,
      onClose: _submitting ? () {} : () => Navigator.pop(context),
      body: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: <Widget>[
          PromptAnimatedReveal(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.card),
                  border: Border.all(color: tokens.accent),
                ),
                child: Text(
                  widget.plate.plateNumber,
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: tokens.onAccentContainer,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          PromptAnimatedReveal(
            delay: const Duration(milliseconds: 70),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.statusDepartureRequestedContainer,
                borderRadius: BorderRadius.circular(PromptUiShapes.card),
                border: Border.all(color: tokens.statusDepartureRequested),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.exit_to_app_rounded,
                    color: tokens.statusDepartureRequested,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '선택한 차량을 출차 요청 상태로 변경합니다.',
                      style: text.bodyLarge?.copyWith(
                        color: tokens.onStatusDepartureRequestedContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: PromptButton(
                    label: '아니요',
                    icon: Icons.close_rounded,
                    variant: PromptButtonVariant.secondary,
                    expand: true,
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context, false),
                    haptic: PromptHaptic.selection,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PromptButton(
                    label: _submitting ? '처리 중' : '네, 출차 요청',
                    icon: Icons.exit_to_app_rounded,
                    expand: true,
                    loading: _submitting,
                    onPressed: _submitting ? null : _confirm,
                    haptic: PromptHaptic.medium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
