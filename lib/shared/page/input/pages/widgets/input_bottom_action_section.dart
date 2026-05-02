import 'package:flutter/material.dart';
import '../../../../plate/widgets/action_trace_dialog.dart';
import '../../application/input_camera_helper.dart';
import '../../controllers/input_plate_controller.dart';
import '../sheets/input_camera_preview_dialog.dart';
import '../sheets/input_location_bottom_sheet.dart';
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
  State<InputBottomActionSection> createState() => _InputBottomActionSectionState();
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
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => InputCameraPreviewDialog(
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

  void _selectParkingLocation() {
    showDialog(
      context: context,
      builder: (_) => InputLocationBottomSheet(
        locationController: widget.controller.locationController,
        preferredParkingAreas: widget.controller.selectedParkingPriorities,
        onLocationSelected: (location) {
          setState(() {
            final trimmed = location.trim();
            widget.controller.locationController.text = trimmed;
            widget.controller.isLocationSelected = trimmed.isNotEmpty;
          });
          widget.onStateRefresh();
        },
      ),
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

    if (success && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _handleParkingButtonPressed() {
    final bool isMinor = widget.controller.isMinorMode;
    final bool selected = widget.controller.isLocationSelected;

    if (isMinor) {
      if (selected) {
        setState(() {
          widget.controller.clearLocation();
        });
        widget.onStateRefresh();
        return;
      }

      _selectParkingLocation();
      return;
    }

    _selectParkingLocation();
  }

  @override
  void dispose() {
    _cameraHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMinor = widget.controller.isMinorMode;
    final bool selected = widget.controller.isLocationSelected;
    final String? parkingButtonLabel = (!isMinor && selected) ? '구역 변경' : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: InputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
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
        const SizedBox(height: 15),
        InputAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: selected,
          isMinorMode: isMinor,
          onPressed: _handleSubmit,
        ),
      ],
    );
  }
}
