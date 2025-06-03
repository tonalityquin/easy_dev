import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import 'modify_plate_controller.dart';
import 'sections/modify_adjustment_section.dart';
import 'sections/modify_parking_location_section.dart';
import 'sections/modify_photo_section.dart';
import 'sections/modify_plate_section.dart';
import 'sections/modify_status_chip_section.dart';

import 'utils/buttons/modify_animated_action_button.dart';
import 'utils/buttons/modify_animated_parking_button.dart';
import 'utils/buttons/modify_animated_photo_button.dart';

import 'widgets/modify_bottom_navigation.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../utils/snackbar_helper.dart';

class ModifyPlateScreen extends StatefulWidget {
  final PlateModel plate;
  final PlateType collectionKey;

  const ModifyPlateScreen({
    super.key,
    required this.plate,
    required this.collectionKey,
  });

  @override
  State<ModifyPlateScreen> createState() => _ModifyPlateScreen();
}

class _ModifyPlateScreen extends State<ModifyPlateScreen> {
  late ModifyPlateController _controller;

  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
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
      controller3digit: controller3digit,
      controller1digit: controller1digit,
      controller4digit: controller4digit,
      locationController: locationController,
      capturedImages: _capturedImages,
      existingImageUrls: _existingImageUrls,
    );

    _controller.initializePlate();
    _controller.initializeCamera().then((_) {
      if (mounted) setState(() {});
    });
    _controller.initializeFieldValues();
    _controller.initializeStatuses().then((_) {
      if (mounted) setState(() => isLoading = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectParkingLocation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ParkingLocationDialog(
          locationController: locationController,
          onLocationSelected: (String location) {
            setState(() {
              locationController.text = location;
              _controller.isLocationSelected = true;
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 4),
            Text(" 번호판 수정 ", style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(width: 4),
          ],
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ModifyPlateSection(
                    dropdownValue: _controller.dropdownValue,
                    regions: _controller.regions,
                    controller3digit: controller3digit,
                    controller1digit: controller1digit,
                    controller4digit: controller4digit,
                    isEditable: false,
                    onRegionChanged: (region) {
                      setState(() => _controller.dropdownValue = region);
                    },
                  ),
                  const SizedBox(height: 32.0),
                  ModifyParkingLocationSection(locationController: locationController),
                  const SizedBox(height: 32.0),
                  ModifyPhotoSection(
                    capturedImages: _capturedImages,
                    existingImageUrls: _existingImageUrls,
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
                  ModifyStatusChipSection(
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
          ),
        ],
      ),
      bottomNavigationBar: ModifyBottomNavigation(
        actionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ModifyAnimatedPhotoButton(
                    onPressed: () => _controller.cameraHelper.showCameraPreviewDialog(context, onCaptured: (image) {
                      setState(() {
                        _capturedImages.add(image);
                      });
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ModifyAnimatedParkingButton(
                    isLocationSelected: _controller.isLocationSelected,
                    onPressed: _selectParkingLocation,
                    buttonLabel: '구역 수정',
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