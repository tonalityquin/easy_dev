import 'package:flutter/material.dart';

import '../utils/buttons/triple_input_animated_action_button.dart';
import '../utils/buttons/triple_input_animated_parking_button.dart';
import '../utils/buttons/triple_input_animated_photo_button.dart';
import '../utils/triple_input_camera_helper.dart';
import '../widgets/triple_input_camera_preview_dialog.dart';
import '../widgets/triple_input_location_bottom_sheet.dart';
import '../triple_input_plate_controller.dart';

class TripleInputBottomActionSection extends StatefulWidget {
  final TripleInputPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const TripleInputBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<TripleInputBottomActionSection> createState() => _TripleInputBottomActionSectionState();
}

class _TripleInputBottomActionSectionState extends State<TripleInputBottomActionSection> {
  late final TripleInputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = TripleInputCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => TripleInputCameraPreviewDialog(
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
      builder: (_) => TripleInputLocationBottomSheet(
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
            Expanded(child: TripleInputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
            const SizedBox(width: 10),
            Expanded(
              child: TripleInputAnimatedParkingButton(
                isLocationSelected: widget.controller.isLocationSelected,
                onPressed: _selectParkingLocation,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        TripleInputAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: widget.controller.isLocationSelected,
          onPressed: () => widget.controller.tripleSubmitPlateEntry(
            context,
            widget.onStateRefresh,
          ),
        ),
      ],
    );
  }
}
