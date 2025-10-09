import 'package:flutter/material.dart';

import '../utils/buttons/offline_input_animated_action_button.dart';
import '../utils/buttons/offline_input_animated_parking_button.dart';
import '../utils/buttons/offline_input_animated_photo_button.dart';
import '../utils/offline_input_camera_helper.dart';
import '../widgets/offline_input_camera_preview_dialog.dart';
import '../widgets/offline_input_location_bottom_sheet.dart';
import '../offline_input_plate_controller.dart';

class OfflineInputBottomActionSection extends StatefulWidget {
  final OfflineInputPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const OfflineInputBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<OfflineInputBottomActionSection> createState() => _OfflineInputBottomActionSectionState();
}

class _OfflineInputBottomActionSectionState extends State<OfflineInputBottomActionSection> {
  late final OfflineInputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = OfflineInputCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => OfflineInputCameraPreviewDialog(
        onImageCaptured: (image) {
          setState(() {
            widget.controller.capturedImages.add(image);
          });
        },
      ),
    );

    await _cameraHelper.dispose();
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() {});
  }

  void _selectParkingLocation() {
    showDialog(
      context: context,
      builder: (_) => OfflineInputLocationBottomSheet(
        locationController: widget.controller.locationController,
        onLocationSelected: (location) {
          setState(() {
            widget.controller.locationController.text = location;
            widget.controller.isLocationSelected = true;
          });
        },
      ),
    );
  }

  VoidCallback _buildLocationAction() {
    return widget.controller.isLocationSelected
        ? () => setState(() => widget.controller.clearLocation())
        : _selectParkingLocation;
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
            Expanded(child: OfflineInputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
            const SizedBox(width: 10),
            Expanded(
              child: OfflineInputAnimatedParkingButton(
                isLocationSelected: widget.controller.isLocationSelected,
                onPressed: _buildLocationAction(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        OfflineInputAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: widget.controller.isLocationSelected,
          onPressed: () => widget.controller.submitPlateEntry(
            context,
            widget.onStateRefresh, // ✅ bool 제거, 2개만 전달
          ),
        ),
      ],
    );
  }
}
