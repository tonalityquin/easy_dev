import 'package:easydev/screens/modify_pages/widgets/modify_location_dialog.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import 'modify_plate_controller.dart';
import 'sections/modify_adjustment_section.dart';
import 'sections/modify_parking_location_section.dart';
import 'sections/modify_photo_section.dart';
import 'sections/modify_plate_section.dart';
import 'sections/modify_status_on_tap_section.dart';

import 'utils/buttons/modify_animated_action_button.dart';
import 'utils/buttons/modify_animated_parking_button.dart';
import 'utils/buttons/modify_animated_photo_button.dart';

import 'widgets/modify_bottom_navigation.dart';
import '../../utils/snackbar_helper.dart';
import 'widgets/modify_camera_preview_dialog.dart';
import 'utils/modify_camera_helper.dart';

class ModifyPlateScreen extends StatefulWidget {
  final PlateModel plate;
  final PlateType collectionKey;

  const ModifyPlateScreen({
    super.key,
    required this.plate,
    required this.collectionKey,
  });

  @override
  State<ModifyPlateScreen> createState() => _ModifyPlateScreenState();
}

class _ModifyPlateScreenState extends State<ModifyPlateScreen> {
  late ModifyPlateController _controller;
  late ModifyCameraHelper _cameraHelper;

  final TextEditingController controllerFrontdigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  final List<XFile> _capturedImages = [];
  final List<String> _existingImageUrls = [];

  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = ModifyPlateController(
      context: context,
      plate: widget.plate,
      collectionKey: widget.collectionKey,
      controllerFrontdigit: controllerFrontdigit,
      controllerMidDigit: controllerMidDigit,
      controllerBackDigit: controllerBackDigit,
      locationController: locationController,
      capturedImages: _capturedImages,
      existingImageUrls: _existingImageUrls,
    );

    _cameraHelper = ModifyCameraHelper();
    _cameraHelper.initializeInputCamera().then((_) => setState(() {}));

    _controller.initializePlate();
    _controller.initializeFieldValues();
    _controller.initializeStatuses().then((_) {
      if (mounted) setState(() => isLoading = false);
    });
  }

  void _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => ModifyCameraPreviewDialog(
        onImageCaptured: (image) {
          setState(() {
            _controller.capturedImages.add(image);
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
      builder: (_) => ModifyLocationDialog(
        locationController: _controller.locationController,
        onLocationSelected: (location) {
          setState(() {
            _controller.locationController.text = location;
            _controller.isLocationSelected = true;
          });
        },
      ),
    );
  }

  VoidCallback _buildLocationAction() {
    return _controller.isLocationSelected
        ? () => setState(() => _controller.clearLocation())
        : _selectParkingLocation;
  }

  @override
  void dispose() {
    _controller.dispose();
    _cameraHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModifyPlateSection(
              dropdownValue: _controller.dropdownValue,
              regions: _controller.regions,
              controllerFrontdigit: controllerFrontdigit,
              controllerMidDigit: controllerMidDigit,
              controllerBackDigit: controllerBackDigit,
              isEditable: false,
              onRegionChanged: (region) {
                setState(() => _controller.dropdownValue = region);
              },
            ),
            const SizedBox(height: 32.0),
            ModifyParkingLocationSection(locationController: locationController),
            const SizedBox(height: 32.0),
            ModifyPhotoSection(
              capturedImages: _controller.capturedImages,
            ),
            const SizedBox(height: 32.0),
            ModifyAdjustmentSection(
              collectionKey: widget.collectionKey,
              selectedAdjustment: _controller.selectedAdjustment,
              onChanged: (value) => setState(() => _controller.selectedAdjustment = value),
              onRefresh: _controller.refreshAdjustments,
              onAutoFill: (adj) {
                setState(() {
                  _controller.selectedBasicStandard = adj.basicStandard;
                  _controller.selectedBasicAmount = adj.basicAmount;
                  _controller.selectedAddStandard = adj.addStandard;
                  _controller.selectedAddAmount = adj.addAmount;
                });
              },
            ),
            const SizedBox(height: 32.0),
            ModifyStatusOnTapSection(
              statuses: _controller.statuses,
              isSelected: _controller.isSelected,
              onToggle: (index) {
                setState(() {
                  _controller.isSelected[index] = !_controller.isSelected[index];
                  final status = _controller.statuses[index];
                  _controller.isSelected[index]
                      ? _controller.selectedStatuses.add(status)
                      : _controller.selectedStatuses.remove(status);
                });
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: ModifyBottomNavigation(
        actionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ModifyAnimatedPhotoButton(onPressed: _showCameraPreviewDialog),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ModifyAnimatedParkingButton(
                    isLocationSelected: _controller.isLocationSelected,
                    onPressed: _buildLocationAction(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            ModifyAnimatedActionButton(
              isLoading: isLoading,
              isLocationSelected: _controller.isLocationSelected,
              buttonLabel: '수정 완료',
              onPressed: () async {
                setState(() => isLoading = true);
                await _controller.handleAction(() {
                  if (mounted) {
                    Navigator.pop(context);
                    showSuccessSnackbar(context, "수정이 완료되었습니다!");
                  }
                });
                if (mounted) setState(() => isLoading = false);
              },
            )
          ],
        ),
      ),
    );
  }
}
