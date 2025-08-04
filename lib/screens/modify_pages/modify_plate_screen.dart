import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import 'debugs/modify_debug_bottom_sheet.dart';
import 'modify_plate_controller.dart';
import 'sections/modify_bill_section.dart';
import 'sections/modify_location_section.dart';
import 'sections/modify_photo_section.dart';
import 'sections/modify_plate_section.dart';
import 'sections/modify_status_custom_section.dart';
import 'sections/modify_status_on_tap_section.dart';

import 'utils/buttons/modify_animated_action_button.dart';
import 'utils/buttons/modify_animated_parking_button.dart';
import 'utils/buttons/modify_animated_photo_button.dart';

import 'modify_bottom_navigation.dart';
import 'widgets/modify_camera_preview_dialog.dart';
import 'widgets/modify_location_bottom_sheet.dart';
import '../../utils/snackbar_helper.dart';
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

  bool isLoading = false;
  late List<String> selectedStatusNames;

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

    selectedStatusNames = List<String>.from(widget.plate.statusList);
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
      builder: (_) => ModifyLocationBottomSheet(
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
    return _selectParkingLocation;
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
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        title: const Text(
          "번호판 수정",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
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
            ModifyLocationSection(locationController: _controller.locationController),
            const SizedBox(height: 32.0),
            ModifyPhotoSection(
              capturedImages: _controller.capturedImages,
              imageUrls: widget.plate.imageUrls ?? [],
              plateNumber: widget.plate.plateNumber,
            ),
            const SizedBox(height: 32.0),
            ModifyBillSection(
              selectedBill: _controller.selectedBillCountType,
              selectedBillType: _controller.selectedBillType,
              onChanged: (bill) {
                setState(() {
                  _controller.applyBillDefaults(bill); // ✅ 모델 전체 전달
                });
              },
              onTypeChanged: (type) {
                setState(() {
                  _controller.onBillTypeChanged(type); // ✅ controller에서 처리
                });
              },
            ),
            const SizedBox(height: 32.0),
            ModifyStatusOnTapSection(
              initialSelectedStatuses: selectedStatusNames,
              onSelectionChanged: (selected) {
                setState(() {
                  selectedStatusNames = selected;
                });
              },
            ),
            const SizedBox(height: 32.0),
            const Text(
              '추가 상태 메모 (최대 10자)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller.customStatusController,
              maxLength: 20,
              decoration: InputDecoration(
                hintText: '예: 뒷범퍼 손상',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            if (_controller.fetchedCustomStatus != null)
              ModifyStatusCustomSection(
                customStatus: _controller.fetchedCustomStatus!,
                onDelete: () async {
                  try {
                    await _controller.deleteCustomStatusFromFirestore(context);
                    setState(() {
                      _controller.fetchedCustomStatus = null;
                      _controller.customStatusController.clear();
                      selectedStatusNames = [];
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('자동 메모가 삭제되었습니다')),
                    );
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('삭제 실패. 다시 시도해주세요')),
                    );
                  }
                },
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ModifyBottomNavigation(
            actionButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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
                    }, selectedStatusNames);
                    if (mounted) setState(() => isLoading = false);
                  },
                ),
              ],
            ),
          ),
          const ModifyDebugTriggerBar(),
        ],
      ),
    );
  }
}

class ModifyDebugTriggerBar extends StatelessWidget {
  const ModifyDebugTriggerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const ModifyDebugBottomSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        color: Colors.transparent,
        child: const Icon(
          Icons.bug_report,
          size: 20,
          color: Colors.grey,
        ),
      ),
    );
  }
}
