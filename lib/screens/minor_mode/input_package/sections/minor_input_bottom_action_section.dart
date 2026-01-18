import 'package:flutter/material.dart';

import '../utils/buttons/minor_input_animated_action_button.dart';
import '../utils/buttons/minor_input_animated_parking_button.dart';
import '../utils/buttons/minor_input_animated_photo_button.dart';
import '../utils/minor_input_camera_helper.dart';
import '../widgets/minor_input_camera_preview_dialog.dart';
import '../widgets/minor_input_location_bottom_sheet.dart';
import '../minor_input_plate_controller.dart';

class MinorInputBottomActionSection extends StatefulWidget {
  final MinorInputPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const MinorInputBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<MinorInputBottomActionSection> createState() => _MinorInputBottomActionSectionState();
}

class _MinorInputBottomActionSectionState extends State<MinorInputBottomActionSection> {
  late final MinorInputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = MinorInputCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => MinorInputCameraPreviewDialog(
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
      builder: (_) => MinorInputLocationBottomSheet(
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
            Expanded(child: MinorInputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
            const SizedBox(width: 10),
            Expanded(
              child: MinorInputAnimatedParkingButton(
                isLocationSelected: widget.controller.isLocationSelected,
                onPressed: _selectParkingLocation,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        MinorInputAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: widget.controller.isLocationSelected,
          onPressed: () => widget.controller.minorSubmitPlateEntry(
            context,
            widget.onStateRefresh,
          ),
        ),
      ],
    );
  }
}
