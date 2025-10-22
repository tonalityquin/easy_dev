import 'package:flutter/material.dart';

import '../utils/buttons/input_animated_action_button.dart';
import '../utils/buttons/input_animated_parking_button.dart';
import '../utils/buttons/input_animated_photo_button.dart';
import '../utils/input_camera_helper.dart';
import '../widgets/input_camera_preview_dialog.dart';
import '../widgets/input_location_bottom_sheet.dart';
import '../input_plate_controller.dart';

class InputBottomActionSection extends StatefulWidget {
  final InputPlateController controller;
  final bool mountedContext;
  final VoidCallback onStateRefresh;

  const InputBottomActionSection({
    super.key,
    required this.controller,
    required this.mountedContext,
    required this.onStateRefresh,
  });

  @override
  State<InputBottomActionSection> createState() => _InputBottomActionSectionState();
}

class _InputBottomActionSectionState extends State<InputBottomActionSection> {
  late final InputCameraHelper _cameraHelper;

  @override
  void initState() {
    super.initState();
    _cameraHelper = InputCameraHelper();
  }

  Future<void> _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!widget.mountedContext) return;

    await showDialog(
      context: context,
      builder: (context) => InputCameraPreviewDialog(
        onImageCaptured: (image) {
          // ✅ 1) 컨트롤러 리스트에 추가
          widget.controller.capturedImages.add(image);
          // ✅ 2) 부모(메인 화면) 리빌드 → InputPhotoSection 즉시 갱신
          widget.onStateRefresh();
          // (선택) 3) 현재 섹션도 리빌드하여 로컬 UI 반영
          if (mounted) setState(() {});
        },
      ),
    );

    await _cameraHelper.dispose();
    await Future.delayed(const Duration(milliseconds: 200));

    // (선택) 이 섹션도 갱신
    if (mounted) setState(() {});
    // ✅ 다이얼로그 종료 후에도 부모를 한 번 더 갱신해 썸네일 노출을 보장
    widget.onStateRefresh();
  }

  void _selectParkingLocation() {
    showDialog(
      context: context,
      builder: (_) => InputLocationBottomSheet(
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
            Expanded(child: InputAnimatedPhotoButton(onPressed: _showCameraPreviewDialog)),
            const SizedBox(width: 10),
            Expanded(
              child: InputAnimatedParkingButton(
                isLocationSelected: widget.controller.isLocationSelected,
                onPressed: _buildLocationAction(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        InputAnimatedActionButton(
          isLoading: widget.controller.isLoading,
          isLocationSelected: widget.controller.isLocationSelected,
          onPressed: () => widget.controller.submitPlateEntry(
            context,
            widget.onStateRefresh, // ✅ 기존 구조 유지
          ),
        ),
      ],
    );
  }
}
