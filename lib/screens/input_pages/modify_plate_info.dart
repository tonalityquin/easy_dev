import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easydev/states/adjustment/adjustment_state.dart';
import 'package:easydev/states/status/status_state.dart';
import 'package:easydev/widgets/input_field/modify_plate_field.dart';
import 'package:easydev/widgets/input_field/location_field.dart';
import 'package:easydev/widgets/keypad/num_keypad.dart';
import 'package:easydev/widgets/keypad/kor_keypad.dart';
import 'package:easydev/widgets/navigation/bottom_navigation.dart';
import 'package:easydev/states/area/area_state.dart';
import 'package:easydev/utils/show_snackbar.dart';
import 'package:easydev/widgets/dialog/parking_location_dialog.dart';
import 'package:easydev/utils/camera_helper.dart';
import 'package:easydev/widgets/dialog/camera_preview_dialog.dart';
import 'package:easydev/widgets/dialog/region_picker_dialog.dart';
import 'package:easydev/models/plate_model.dart';
import 'package:easydev/utils/fullscreen_viewer.dart';
import 'package:easydev/utils/button/custom_adjustment_dropdown.dart';

import 'package:easydev/services/modify_plate_service.dart';

import 'package:easydev/utils/button/animated_parking_button.dart';
import 'package:easydev/utils/button/animated_photo_button.dart';
import 'package:easydev/utils/button/animated_action_button.dart';

import 'package:easydev/states/plate/plate_state.dart';

import 'package:easydev/models/adjustment_model.dart';

class ModifyPlateInfo extends StatefulWidget {
  final PlateModel plate; // ✅ plate 파라미터 추가
  final String collectionKey; // ✅ 추가

  const ModifyPlateInfo({
    super.key,
    required this.plate,
    required this.collectionKey,
  }); // ✅ 생성자에 추가
  @override
  State<ModifyPlateInfo> createState() => _ModifyPlateInfo();
}

class _ModifyPlateInfo extends State<ModifyPlateInfo> {
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
    '충북'
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
    _cameraHelper.initializeCamera().then((_) {
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
      showSnackbar(context, '입력값이 유효하지 않습니다. 다시 확인해주세요.');
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

    await _cameraHelper.initializeCamera(); // 🔸 여기까지 정상 실행됨

    await showDialog(
      context: context,
      builder: (context) => CameraPreviewDialog(
        onImageCaptured: (image) {
          setState(() {
            _capturedImages.add(image);
            debugPrint('📸 이미지 1장이 실시간 반영됨: ${image.path}');
          });
        },
      ),
    );

    debugPrint('📸 다이얼로그 닫힘 → dispose() 호출 전');
    await _cameraHelper.dispose();
    debugPrint('📸 dispose 완료 후 200ms 지연');
    await Future.delayed(const Duration(milliseconds: 200));
    setState(() {});
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
      showSnackbar(context, '정산 유형을 선택해주세요');
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
    final oldLocation = widget.plate.location;
    final oldAdjustmentType = widget.plate.adjustmentType;

    final newLocation = locationController.text;
    final newAdjustmentType = selectedAdjustment;

    final locationChanged = oldLocation != newLocation;
    final adjustmentChanged = oldAdjustmentType != newAdjustmentType;

    final mergedImageUrls = await service.uploadAndMergeImages(plateNumber);

    final success = await service.updatePlateInfo(
      plateNumber: plateNumber,
      imageUrls: mergedImageUrls,
      newLocation: newLocation,
      newAdjustmentType: newAdjustmentType,
    );

    if (success && (locationChanged || adjustmentChanged)) {
      await service.logPlateChange(
        plateNumber: plateNumber,
        from: locationChanged ? oldLocation : (adjustmentChanged ? oldAdjustmentType ?? '-' : '-'),
        to: locationChanged ? newLocation : (adjustmentChanged ? newAdjustmentType ?? '-' : '-'),
        action: locationChanged && adjustmentChanged
            ? '위치/할인 수정'
            : locationChanged
                ? '위치 수정'
                : '할인 수정',
      );
    }

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

      Navigator.pop(context);
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
      adjustmentState.syncWithAreaState();
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
            Text(
              " 번호판 수정 ",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
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
                  const Text(
                    '번호 입력',
                    style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center, // 🔹 중앙 정렬로 변경
                    children: [
                      // 드롭다운 버튼
                      GestureDetector(
                        onTap: () {
                          showRegionPickerDialog(
                            context: context,
                            selectedRegion: dropdownValue,
                            regions: regions,
                            onConfirm: (selected) {
                              setState(() {
                                dropdownValue = selected;
                              });
                            },
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), // 🔸 높이 맞춤
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.transparent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                dropdownValue,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold, // 🔹 굵게 설정
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // 번호판 입력창
                      Expanded(
                        child: Align(
                            alignment: Alignment.center,
                            child: ModifyPlateInput(
                              frontDigitCount: 3,
                              hasMiddleChar: true,
                              backDigitCount: 4,
                              frontController: controller3digit,
                              middleController: controller1digit,
                              backController: controller4digit,
                              isEditable: false, // 이 값으로 번호판 수정 불가 설정
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32.0),
                  const Text(
                    '주차 구역',
                    style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LocationField(
                          controller: locationController,
                          widthFactor: 0.7,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32.0),
                  const Text(
                    '촬영 사진',
                    style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  SizedBox(
                    height: 100,
                    child: _capturedImages.isEmpty && _existingImageUrls.isEmpty
                        ? const Center(child: Text('촬영된 사진 없음'))
                        : ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              // ✅ 기존 GCS 이미지 (URL)
                              ..._existingImageUrls.asMap().entries.map((entry) {
                                final index = entry.key;
                                final url = entry.value;
                                return GestureDetector(
                                  onTap: () => showFullScreenImageViewerFromUrls(context, _existingImageUrls, index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Image.network(
                                      url,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const Icon(Icons.broken_image, size: 50),
                                    ),
                                  ),
                                );
                              }),
                              // ✅ 새로 촬영한 로컬 이미지 (File)
                              ..._capturedImages.asMap().entries.map((entry) {
                                final index = entry.key;
                                final image = entry.value;
                                return GestureDetector(
                                  onTap: () => showFullScreenImageViewer(context, _capturedImages, index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Image.file(
                                      File(image.path),
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),
                  const SizedBox(height: 32.0),
                  const Text(
                    '정산 유형',
                    style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  FutureBuilder<bool>(
                    future: _refreshAdjustments().timeout(const Duration(seconds: 3), onTimeout: () => false),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data == false) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '정산 유형 정보를 불러오지 못했습니다.',
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      final adjustmentState = context.watch<AdjustmentState>();
                      final adjustmentList = adjustmentState.adjustments;

                      if (adjustmentList.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '등록된 정산 유형이 없습니다.',
                            style: TextStyle(color: Colors.green),
                          ),
                        );
                      }

                      final dropdownItems = adjustmentList.map((adj) => adj.countType).toList();

                      return CustomAdjustmentDropdown(
                        items: dropdownItems,
                        selectedValue: selectedAdjustment,
                        onChanged: (newValue) {
                          final adjustment = adjustmentList.firstWhere(
                            (adj) => adj.countType == newValue,
                            orElse: () => AdjustmentModel(
                              id: 'empty',
                              countType: '',
                              area: '',
                              basicStandard: 0,
                              basicAmount: 0,
                              addStandard: 0,
                              addAmount: 0,
                            ),
                          );

                          setState(() {
                            selectedAdjustment = newValue;

                            if (adjustment.countType.isNotEmpty) {
                              selectedBasicStandard = adjustment.basicStandard;
                              selectedBasicAmount = adjustment.basicAmount;
                              selectedAddStandard = adjustment.addStandard;
                              selectedAddAmount = adjustment.addAmount;

                              debugPrint("✅ 정산 타입 변경됨: $selectedAdjustment");
                              debugPrint("→ 기본 ${selectedBasicStandard}분 / ${selectedBasicAmount}원");
                              debugPrint("→ 추가 ${selectedAddStandard}분 / ${selectedAddAmount}원");
                            }
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 32.0),
                  const Text(
                    '차량 상태',
                    style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8.0),
                  statuses.isEmpty
                      ? const Text('등록된 차량 상태가 없습니다.')
                      : Wrap(
                          spacing: 8.0,
                          children: List.generate(statuses.length, (index) {
                            return ChoiceChip(
                              label: Text(statuses[index]),
                              selected: isSelected[index],
                              onSelected: (selected) {
                                setState(() {
                                  isSelected[index] = selected;
                                  if (selected) {
                                    selectedStatuses.add(statuses[index]);
                                  } else {
                                    selectedStatuses.remove(statuses[index]);
                                  }
                                });
                              },
                            );
                          }),
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
                  child: AnimatedPhotoButton(
                    onPressed: _showCameraPreviewDialog,
                  ),
                ),
                const SizedBox(width: 10),
                // ✅ 1. 주차 구역 선택 버튼 (초기화 제거)
                Expanded(
                  // ✅ 폭 동일하게 설정
                  child: AnimatedParkingButton(
                    isLocationSelected: true,
                    onPressed: _selectParkingLocation,
                    buttonLabel: '구역 수정',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            // ✅ 2. 수정 완료 버튼
            AnimatedActionButton(
              isLoading: isLoading,
              isLocationSelected: isLocationSelected, // 필요 시 false 고정 가능
              buttonLabel: '수정 완료',
              onPressed: () async {
                setState(() => isLoading = true);
                await _handleAction();
                if (!mounted) return;
                setState(() => isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: Colors.white),
                        SizedBox(width: 12),
                        Text("수정이 완료되었습니다!", style: TextStyle(fontSize: 15)),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
