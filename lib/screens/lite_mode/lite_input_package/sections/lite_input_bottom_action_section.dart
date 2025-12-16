import 'package:flutter/material.dart';

import '../utils/buttons/lite_input_animated_action_button.dart';
import '../utils/buttons/lite_input_animated_parking_button.dart';
import '../utils/buttons/lite_input_animated_photo_button.dart';
import '../utils/lite_input_camera_helper.dart';
import '../widgets/lite_input_camera_preview_dialog.dart';
import '../widgets/lite_input_location_bottom_sheet.dart';
import '../lite_input_plate_controller.dart';

class LiteInputBottomActionSection extends StatefulWidget {
  final LiteInputPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const LiteInputBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<LiteInputBottomActionSection> createState() => _LiteInputBottomActionSectionState();
}

class _LiteInputBottomActionSectionState extends State<LiteInputBottomActionSection> {
  late final LiteInputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = LiteInputCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => LiteInputCameraPreviewDialog(
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
      builder: (_) => LiteInputLocationBottomSheet(
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
            Expanded(child: LiteInputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
            const SizedBox(width: 10),
            Expanded(
              child: LiteInputAnimatedParkingButton(
                isLocationSelected: widget.controller.isLocationSelected,
                onPressed: _selectParkingLocation,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        LiteInputAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: widget.controller.isLocationSelected,
          onPressed: () => widget.controller.submitPlateEntry(
            context,
            widget.onStateRefresh,
          ),
        ),
      ],
    );
  }
}
