import 'package:flutter/material.dart';

import '../utils/buttons/monthly_animated_action_button.dart';
import '../utils/buttons/monthly_animated_parking_button.dart';
import '../utils/buttons/monthly_animated_photo_button.dart';
import '../utils/monthly_camera_helper.dart';
import '../widgets/monthly_camera_preview_dialog.dart';
import '../widgets/monthly_location_bottom_sheet.dart';
import '../monthly_plate_controller.dart';

class MonthlyBottomActionSection extends StatefulWidget {
  final MonthlyPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const MonthlyBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<MonthlyBottomActionSection> createState() => _MonthlyBottomActionSectionState();
}

class _MonthlyBottomActionSectionState extends State<MonthlyBottomActionSection> {
  late final MonthlyCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = MonthlyCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => MonthlyCameraPreviewDialog(
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
      builder: (_) => MonthlyLocationBottomSheet(
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
            Expanded(child: MonthlyAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
            const SizedBox(width: 10),
            Expanded(
              child: MonthlyAnimatedParkingButton(
                isLocationSelected: widget.controller.isLocationSelected,
                onPressed: _buildLocationAction(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        MonthlyAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: widget.controller.isLocationSelected,
          onPressed: () => widget.controller.submitPlateEntry(
            context,
            widget.mountedContext,
            widget.onStateRefresh,
          ),
        ),
      ],
    );
  }
}
