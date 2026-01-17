import 'package:flutter/material.dart';

import '../utils/buttons/double_input_animated_action_button.dart';
import '../utils/buttons/double_input_animated_parking_button.dart';
import '../utils/buttons/double_input_animated_photo_button.dart';
import '../utils/double_input_camera_helper.dart';
import '../widgets/double_input_camera_preview_dialog.dart';
import '../widgets/double_input_location_bottom_sheet.dart';
import '../double_input_plate_controller.dart';

class DoubleInputBottomActionSection extends StatefulWidget {
  final DoubleInputPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const DoubleInputBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<DoubleInputBottomActionSection> createState() => _DoubleInputBottomActionSectionState();
}

class _DoubleInputBottomActionSectionState extends State<DoubleInputBottomActionSection> {
  late final DoubleInputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = DoubleInputCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => DoubleInputCameraPreviewDialog(
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
      builder: (_) => DoubleInputLocationBottomSheet(
        locationController: widget.controller.locationController,
        onLocationSelected: (location) {
          setState(() {
            final trimmed = location.trim();
            widget.controller.locationController.text = trimmed;
            widget.controller.isLocationSelected = trimmed.isNotEmpty;
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _cameraHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: DoubleInputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
            const SizedBox(width: 10),
            Expanded(
              child: DoubleInputAnimatedParkingButton(
                isLocationSelected: widget.controller.isLocationSelected,
                onPressed: _selectParkingLocation,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        DoubleInputAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: widget.controller.isLocationSelected,
          onPressed: () => widget.controller.doubleSubmitPlateEntry(
            context,
            widget.onStateRefresh,
          ),
        ),
      ],
    );
  }
}
