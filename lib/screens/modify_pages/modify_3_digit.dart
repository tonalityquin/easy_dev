import 'package:camera/camera.dart';
import 'package:easydev/screens/modify_pages/sections/adjustment_modify_section.dart';
import 'package:easydev/screens/modify_pages/sections/parking_location_modify_section.dart';
import 'package:easydev/screens/modify_pages/sections/photo_modify_section.dart';
import 'package:easydev/screens/modify_pages/sections/plate_modify_section.dart';
import 'package:easydev/screens/modify_pages/sections/status_chip_modify_section.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easydev/states/adjustment/adjustment_state.dart';
import 'package:easydev/states/status/status_state.dart';
import 'package:easydev/screens/input_pages/keypad/num_keypad.dart';
import 'package:easydev/screens/input_pages/keypad/kor_keypad.dart';
import 'package:easydev/widgets/navigation/bottom_navigation.dart';
import 'package:easydev/states/area/area_state.dart';
import 'package:easydev/utils/snackbar_helper.dart';
import 'package:easydev/widgets/dialog/parking_location_dialog.dart';
import 'package:easydev/utils/camera_helper.dart';
import 'package:easydev/widgets/dialog/camera_preview_dialog.dart';
import 'package:easydev/models/plate_model.dart';

import 'package:easydev/screens/modify_pages/modify_plate_service.dart';

import 'package:easydev/utils/button/animated_parking_button.dart';
import 'package:easydev/utils/button/animated_photo_button.dart';
import 'package:easydev/utils/button/animated_action_button.dart';

import 'package:easydev/states/plate/plate_state.dart';
import 'package:easydev/enums/plate_type.dart';

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
  late TextEditingController activeController;
  bool showKeypad = false;
  bool isLoading = false;
  bool isLocationSelected = false;
  String? selectedAdjustment;

  final ButtonStyle commonButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.grey[300],
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 150.0, vertical: 15.0),
  );
  late CameraHelper _cameraHelper;
  final List<XFile> _capturedImages = [];
  final List<String> _existingImageUrls = [];

  @override
  void initState() {
    super.initState();
    isLoading = true;
    if (widget.plate.imageUrls != null) {
      _existingImageUrls.addAll(widget.plate.imageUrls!);
    }
    _cameraHelper = CameraHelper();
    _cameraHelper.initializeInputCamera().then((_) {
      if (mounted) setState(() {}); // 초기화 완료 후 UI 갱신
    });
    // ✅ 차량 정보 반영: 텍스트필드 및 드롭다운 등
    final plate = widget.plate;
    final plateNum = widget.plate.plateNumber.replaceAll('-', '');

    // 번호판 분해: 123 가 4567 → 앞 3, 가운데 1, 뒤 4자리로 나누기
    if (plateNum.length >= 8) {
      controller3digit.text = plateNum.substring(0, 3);
      controller1digit.text = plateNum.substring(3, 4);
      controller4digit.text = plateNum.substring(4);
    }

    // 지역 세팅
    dropdownValue = plate.region ?? '전국';

    // 위치
    locationController.text = plate.location;

    // 정산
    selectedAdjustment = plate.adjustmentType;
    selectedBasicStandard = plate.basicStandard ?? 0;
    selectedBasicAmount = plate.basicAmount ?? 0;
    selectedAddStandard = plate.addStandard ?? 0;
    selectedAddAmount = plate.addAmount ?? 0;

    // 상태 목록은 이후 fetch 후 반영
    selectedStatuses = List<String>.from(plate.statusList);

    activeController = controller3digit;
    _addInputListeners();
    isLocationSelected = locationController.text.isNotEmpty;

    // 비동기 초기화
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
        .where((status) => status.area == currentArea && status.isActive) // ✅ 수정됨
        .map((status) => status.name) // ✅ 수정됨
        .toList();

    setState(() {
      statuses = fetchedStatuses;
      isSelected = statuses.map((s) => selectedStatuses.contains(s)).toList();
    });
  }

  void _addInputListeners() {
    controller3digit.addListener(_handleInputChange);
    controller1digit.addListener(_handleInputChange);
    controller4digit.addListener(_handleInputChange);
  }

  void _removeInputListeners() {
    controller3digit.removeListener(_handleInputChange);
    controller1digit.removeListener(_handleInputChange);
    controller4digit.removeListener(_handleInputChange);
  }

  void _handleInputChange() {
    if (controller3digit.text.isEmpty && controller1digit.text.isEmpty && controller4digit.text.isEmpty) {
      return;
    }
    if (!_validateField(controller3digit, 3) ||
        !_validateField(controller1digit, 1) ||
        !_validateField(controller4digit, 4)) {
      showFailedSnackbar(context, '입력값이 유효하지 않습니다. 다시 확인해주세요.');
      return;
    }
    if (controller3digit.text.length == 3 && controller1digit.text.length == 1 && controller4digit.text.length == 4) {
      setState(() {
        showKeypad = false;
      });
      return;
    }
    if (activeController == controller3digit && controller3digit.text.length == 3) {
      _setActiveController(controller1digit);
    } else if (activeController == controller1digit && controller1digit.text.length == 1) {
      _setActiveController(controller4digit);
    }
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

  void _setActiveController(TextEditingController controller) {
    setState(() {
      activeController = controller;
      showKeypad = true;
    });
  }

  bool _validateField(TextEditingController controller, int maxLength) {
    return controller.text.length <= maxLength;
  }

  void clearInput() {
    setState(() {
      controller3digit.clear();
      controller1digit.clear();
      controller4digit.clear();
      activeController = controller3digit;
      showKeypad = true;
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

    // ✅ 정산 타입이 존재하는데 선택 안 한 경우 → 중단 + 스낵바 알림
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
    _removeInputListeners();
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
      bottomNavigationBar: BottomNavigation(
        showKeypad: showKeypad,
        keypad: activeController == controller3digit
            ? NumKeypad(
                controller: controller3digit,
                maxLength: 3,
                onComplete: () => _setActiveController(controller1digit),
              )
            : activeController == controller1digit
                ? KorKeypad(
                    controller: controller1digit,
                    onComplete: () => _setActiveController(controller4digit),
                  )
                : NumKeypad(
                    controller: controller4digit,
                    maxLength: 4,
                    onComplete: () => setState(() => showKeypad = false),
                  ),
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
                    isLocationSelected: true,
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

                // 비동기 작업을 처리
                await _handleAction();

                // 비동기 작업 후, mounted 체크 후 UI 업데이트
                if (!mounted) return;

                setState(() => isLoading = false); // 비동기 작업 후 로딩 상태 해제

                // 비동기 작업 완료 후 스낵바 표시
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
