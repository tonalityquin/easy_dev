import 'package:flutter/material.dart';

import '../utils/buttons/normal_input_animated_action_button.dart';
import '../utils/buttons/normal_input_animated_parking_button.dart';
import '../utils/buttons/normal_input_animated_photo_button.dart';
import '../utils/normal_input_camera_helper.dart';
import '../widgets/normal_input_camera_preview_dialog.dart';
import '../widgets/normal_input_location_bottom_sheet.dart';
import '../normal_input_plate_controller.dart';

class NormalInputBottomActionSection extends StatefulWidget {
  final NormalInputPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const NormalInputBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<NormalInputBottomActionSection> createState() => _NormalInputBottomActionSectionState();
}

class _NormalInputBottomActionSectionState extends State<NormalInputBottomActionSection> {
  late final NormalInputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = NormalInputCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => NormalInputCameraPreviewDialog(
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
      builder: (_) => NormalInputLocationBottomSheet(
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
            Expanded(child: NormalInputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
            const SizedBox(width: 10),
            Expanded(
              child: NormalInputAnimatedParkingButton(
                isLocationSelected: widget.controller.isLocationSelected,
                onPressed: _selectParkingLocation,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        NormalInputAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: widget.controller.isLocationSelected,
          onPressed: () => widget.controller.normalSubmitPlateEntry(
            context,
            widget.onStateRefresh,
          ),
        ),
      ],
    );
  }
}
