import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';

import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';

import '../../states/plate/plate_state.dart';
import '../../states/adjustment/adjustment_state.dart';
import '../../states/status/status_state.dart';
import '../../states/area/area_state.dart';

import '../../screens/modify_pages/modify_plate_service.dart';
import '../../screens/modify_pages/sections/adjustment_modify_section.dart';
import '../../screens/modify_pages/sections/parking_location_modify_section.dart';
import '../../screens/modify_pages/sections/photo_modify_section.dart';
import '../../screens/modify_pages/sections/plate_modify_section.dart';
import '../../screens/modify_pages/sections/status_chip_modify_section.dart';

import '../../utils/button/animated_action_button.dart';
import '../../utils/button/animated_parking_button.dart';
import '../../utils/button/animated_photo_button.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/camera_helper.dart';

import '../../widgets/dialog/camera_preview_dialog.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../widgets/navigation/modify_bottom_navigation.dart';

class Modify3Digit extends StatefulWidget {
  final PlateModel plate; // ✅ plate 파라미터 추가
  final PlateType collectionKey; // ✅ 추가

  const Modify3Digit({
    super.key,
    required this.plate,
    required this.collectionKey,
  }); // ✅ 생성자에 추가
  @override
  State<Modify3Digit> createState() => _Modify3Digit();
}

class _Modify3Digit extends State<Modify3Digit> {
  final List<String> regions = [
    '전국',
    '강원',
    '경기',
    '경남',
    '경북',
    '광주',
    '대구',
    '대전',
    '부산',
    '서울',
    '울산',
    '인천',
    '전남',
    '전북',
    '제주',
    '충남',
    '충북',
    '국기',
    '대표',
    '영사',
    '외교',
    '임시',
    '준영',
    '준외',
    '협정'
  ];
  String dropdownValue = '전국'; // ✅ 드롭다운 값 상태 변수
  List<String> selectedStatuses = [];
  List<bool> isSelected = [];
  List<String> statuses = [];
  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  bool isLoading = false;
  bool isLocationSelected = false;
  String? selectedAdjustment;
  late CameraHelper _cameraHelper;
  final List<XFile> _capturedImages = [];
  final List<String> _existingImageUrls = [];

  @override
  void initState() {
    super.initState();
    _initializePlate();
    _initializeCamera();
    _initializeFieldValues();
    _initializeAsyncData();
  }

  void _initializePlate() {
    isLoading = true;
    if (widget.plate.imageUrls != null) {
      _existingImageUrls.addAll(widget.plate.imageUrls!);
    }
  }

  void _initializeCamera() {
    _cameraHelper = CameraHelper();
    _cameraHelper.initializeInputCamera().then((_) {
      if (mounted) setState(() {}); // 초기화 완료 후 UI 갱신
    });
  }

  void _initializeFieldValues() {
    final plate = widget.plate;
    final plateNum = plate.plateNumber.replaceAll('-', '');

    // ✅ 앞자리가 2~3자리, 중간은 한글 0~1글자, 뒤 4자리
    final regExp = RegExp(r'^(\d{2,3})([가-힣]?)(\d{4})$');
    final match = regExp.firstMatch(plateNum);

    if (match != null) {
      controller3digit.text = match.group(1) ?? '';
      controller1digit.text = match.group(2) ?? '';
      controller4digit.text = match.group(3) ?? '';
    } else {
      // ⚠️ 파싱 실패 시 로그 출력 (디버깅용)
      debugPrint('번호판 형식을 파싱하지 못했습니다: $plateNum');
    }

    dropdownValue = plate.region ?? '전국';
    locationController.text = plate.location;

    selectedAdjustment = plate.adjustmentType;
    selectedBasicStandard = plate.basicStandard ?? 0;
    selectedBasicAmount = plate.basicAmount ?? 0;
    selectedAddStandard = plate.addStandard ?? 0;
    selectedAddAmount = plate.addAmount ?? 0;

    selectedStatuses = List<String>.from(plate.statusList);
    isLocationSelected = locationController.text.isNotEmpty;
  }

  void _initializeAsyncData() {
    Future.delayed(const Duration(milliseconds: 100), () async {
      try {
        await Future.wait([
          _initializeStatuses().timeout(Duration(seconds: 3)),
        ]);
      } catch (e) {
        debugPrint("초기화 오류 발생: $e");
      }

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  Future<void> _initializeStatuses() async {
    final statusState = context.read<StatusState>();
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;

    int retry = 0;
    while (statusState.statuses.isEmpty && retry < 5) {
      await Future.delayed(const Duration(milliseconds: 500));
      retry++;
    }

    final fetchedStatuses = statusState.statuses
        .where((status) => status.area == currentArea && status.isActive)
        .map((status) => status.name)
        .toList();

    setState(() {
      statuses = fetchedStatuses;
      isSelected = statuses.map((s) => selectedStatuses.contains(s)).toList();
    });
  }

  Future<void> _showCameraPreviewDialog() async {
    debugPrint('📸 _showCameraPreviewDialog() 호출됨');

    // 카메라 초기화
    await _cameraHelper.initializeInputCamera();

    // showDialog 호출 전에 mounted 체크
    if (!context.mounted) return;

    // 다이얼로그 표시
    await showDialog(
      context: context,
      builder: (context) {
        return CameraPreviewDialog(
          onImageCaptured: (image) {
            // 다이얼로그에서 이미지를 캡처한 후 setState 호출 전에 mounted 체크
            if (context.mounted) {
              setState(() {
                _capturedImages.add(image);
                debugPrint('📸 이미지 1장이 실시간 반영됨: ${image.path}');
              });
            }
          },
        );
      },
    );

    debugPrint('📸 다이얼로그 닫힘 → dispose() 호출 전');

    // dispose 호출 전 mounted 체크
    if (context.mounted) {
      await _cameraHelper.dispose();
    }

    debugPrint('📸 dispose 완료 후 200ms 지연');
    // 200ms 지연 후 setState 호출
    await Future.delayed(const Duration(milliseconds: 200));

    // setState 호출 전에 여전히 위젯이 마운트되었는지 확인
    if (context.mounted) {
      setState(() {});
    }
  }

  void clearInput() {
    setState(() {
      controller3digit.clear();
      controller1digit.clear();
      controller4digit.clear();
    });
  }

  void _clearLocation() {
    setState(() {
      locationController.clear();
      isLocationSelected = false;
    });
  }

  Future<void> _handleAction() async {
    final adjustmentList = context.read<AdjustmentState>().adjustments;

    if (adjustmentList.isNotEmpty && (selectedAdjustment == null || selectedAdjustment!.isEmpty)) {
      showFailedSnackbar(context, '정산 유형을 선택해주세요');
      return;
    }

    final service = ModifyPlateService(
      context: context,
      capturedImages: _capturedImages,
      existingImageUrls: _existingImageUrls,
      collectionKey: widget.collectionKey,
      originalPlate: widget.plate,
      controller3digit: controller3digit,
      controller1digit: controller1digit,
      controller4digit: controller4digit,
      locationController: locationController,
      selectedStatuses: selectedStatuses,
      selectedBasicStandard: selectedBasicStandard,
      selectedBasicAmount: selectedBasicAmount,
      selectedAddStandard: selectedAddStandard,
      selectedAddAmount: selectedAddAmount,
      selectedAdjustment: selectedAdjustment,
      dropdownValue: dropdownValue,
    );

    final plateNumber = service.composePlateNumber();

    final newLocation = locationController.text;
    final newAdjustmentType = selectedAdjustment;

    final mergedImageUrls = await service.uploadAndMergeImages(plateNumber);

    final success = await service.updatePlateInfo(
      plateNumber: plateNumber,
      imageUrls: mergedImageUrls,
      newLocation: newLocation,
      newAdjustmentType: newAdjustmentType,
    );

    // ✅ 로그 저장은 정책상 제거 → logPlateChange 제거

    if (success) {
      final updatedPlate = widget.plate.copyWith(
        adjustmentType: newAdjustmentType,
        basicStandard: selectedBasicStandard,
        basicAmount: selectedBasicAmount,
        addStandard: selectedAddStandard,
        addAmount: selectedAddAmount,
        location: newLocation,
        statusList: selectedStatuses,
        region: dropdownValue,
        imageUrls: mergedImageUrls,
      );

      final plateState = context.read<PlateState>();
      await plateState.updatePlateLocally(widget.collectionKey, updatedPlate);

      if (mounted) {
        Navigator.pop(context);
      }
    }

    clearInput();
    _clearLocation();
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
              isLocationSelected = true;
            });
          },
        );
      },
    );
  }

  Future<bool> _refreshAdjustments() async {
    final adjustmentState = context.read<AdjustmentState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      adjustmentState.syncWithAreaAdjustmentState();
    });
    await Future.delayed(const Duration(milliseconds: 500));
    return adjustmentState.adjustments.isNotEmpty;
  }

  @override
  void dispose() {
    controller3digit.dispose();
    controller1digit.dispose();
    controller4digit.dispose();
    locationController.dispose();
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
                  PlateModifySection(
                    dropdownValue: dropdownValue,
                    regions: regions,
                    controller3digit: controller3digit,
                    controller1digit: controller1digit,
                    controller4digit: controller4digit,
                    isEditable: false,
                    onRegionChanged: (region) {
                      setState(() => dropdownValue = region);
                    },
                  ),
                  const SizedBox(height: 32.0),
                  ParkingLocationModifySection(locationController: locationController),
                  const SizedBox(height: 32.0),
                  PhotoModifySection(
                    capturedImages: _capturedImages,
                    existingImageUrls: _existingImageUrls,
                  ),
                  const SizedBox(height: 32.0),
                  AdjustmentModifySection(
                    collectionKey: widget.collectionKey,
                    selectedAdjustment: selectedAdjustment,
                    onChanged: (value) => setState(() => selectedAdjustment = value),
                    onRefresh: _refreshAdjustments,
                    onAutoFill: (adj) {
                      setState(() {
                        selectedBasicStandard = adj.basicStandard;
                        selectedBasicAmount = adj.basicAmount;
                        selectedAddStandard = adj.addStandard;
                        selectedAddAmount = adj.addAmount;
                      });
                    },
                  ),
                  const SizedBox(height: 32.0),
                  StatusChipModifySection(
                    statuses: statuses,
                    isSelected: isSelected,
                    onToggle: (index) {
                      setState(() {
                        isSelected[index] = !isSelected[index];
                        final status = statuses[index];
                        isSelected[index] ? selectedStatuses.add(status) : selectedStatuses.remove(status);
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
                  child: AnimatedPhotoButton(onPressed: _showCameraPreviewDialog),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedParkingButton(
                    isLocationSelected: isLocationSelected,
                    onPressed: _selectParkingLocation,
                    buttonLabel: '구역 수정',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            AnimatedActionButton(
              isLoading: isLoading,
              isLocationSelected: isLocationSelected,
              buttonLabel: '수정 완료',
              onPressed: () async {
                setState(() => isLoading = true); // 비동기 작업 전 로딩 상태 설정

                await _handleAction(); // 비동기 작업 처리

                if (!mounted) return;

                setState(() => isLoading = false); // 비동기 작업 후 로딩 해제

                if (mounted) {
                  showSuccessSnackbar(context, "수정이 완료되었습니다!");
                }
              },
            )
          ],
        ),
      ),
    );
  }
}
