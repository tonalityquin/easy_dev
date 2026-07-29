import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../plate/widgets/action_trace_dialog.dart';
import '../../application/input_camera_helper.dart';
import '../../controllers/input_plate_controller.dart';
import '../sheets/input_camera_preview_dialog.dart';
import '../sheets/input_location_bottom_sheet.dart';
import '../prompt_input_ui.dart';
import 'buttons/input_animated_action_button.dart';
import 'buttons/input_animated_parking_button.dart';
import 'buttons/input_animated_photo_button.dart';

class InputBottomActionSection extends StatefulWidget {
  final InputPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const InputBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<InputBottomActionSection> createState() =>
      _InputBottomActionSectionState();
}

class _InputBottomActionSectionState extends State<InputBottomActionSection> {
  static const bool _kShowActionTrace =
      bool.fromEnvironment('PW_SHOW_ACTION_TRACE', defaultValue: false);

  late final InputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = InputCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext || !mounted) return;
    await showPromptOverlayDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => InputCameraPreviewDialog(
        onImageCaptured: (image) {
          widget.controller.capturedImages.add(image);
          widget.onStateRefresh();
          if (mounted) setState(() {});
        },
      ),
    );
    await _cameraHelper.dispose();
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() {});
    widget.onStateRefresh();
  }

  Future<void> _selectParkingLocation() async {
    await InputLocationBottomSheet.show(
      context,
      widget.controller.locationController,
      (location) {
        if (!mounted) return;
        setState(() {
          final trimmed = location.trim();
          widget.controller.locationController.text = trimmed;
          widget.controller.isLocationSelected = trimmed.isNotEmpty;
        });
        widget.onStateRefresh();
      },
      preferredParkingAreas: widget.controller.selectedParkingPriorities,
      usePromptUi: true,
    );
  }

  Future<void> _handleSubmit() async {
    if (widget.controller.isLoading) return;
    if (_kShowActionTrace) {
      await ActionTraceDialog.showAndRun(
        context,
        title: '입차 버튼 실행 로그',
        task: (trace) async {
          final success = await widget.controller.submitPlateEntry(
            context,
            widget.onStateRefresh,
            trace: trace,
          );
          trace.add('submit result=$success');
        },
      );
      return;
    }
    final success = await widget.controller.submitPlateEntry(
      context,
      widget.onStateRefresh,
    );
    if (success && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _handleParkingButtonPressed() async {
    final isMinor = widget.controller.isMinorMode;
    final selected = widget.controller.isLocationSelected;
    if (isMinor && selected) {
      setState(widget.controller.clearLocation);
      widget.onStateRefresh();
      return;
    }
    await _selectParkingLocation();
  }

  @override
  void dispose() {
    _cameraHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMinor = widget.controller.isMinorMode;
    final selected = widget.controller.isLocationSelected;
    final parkingButtonLabel = !isMinor && selected ? '구역 변경' : null;
    final lookupInProgress = widget.controller.statusLookupInProgress;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    return PromptAnimatedReveal(
      delay: const Duration(milliseconds: 120),
      child: PromptInputSectionCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InputAnimatedPhotoButton(
                    onPressed: _showCameraPreviewDialog,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InputAnimatedParkingButton(
                    isLocationSelected: selected,
                    buttonLabel: parkingButtonLabel,
                    onPressed: _handleParkingButtonPressed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: transitionDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: lookupInProgress
                  ? Container(
                      key: const ValueKey<String>('status-lookup-progress'),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withOpacity(.46),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('상태 정보를 확인한 뒤 입차할 수 있습니다.'),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey<String>('status-lookup-ready'),
                    ),
            ),
            AnimatedSwitcher(
              duration: transitionDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: InputAnimatedActionButton(
                key: ValueKey<String>(
                  'entry-${widget.controller.isLoading}-$lookupInProgress',
                ),
                isLoading: widget.controller.isLoading,
                isLocationSelected: selected,
                isMinorMode: isMinor,
                isStatusLookupInProgress: lookupInProgress,
                onPressed: _handleSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
