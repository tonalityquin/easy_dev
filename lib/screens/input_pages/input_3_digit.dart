import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/adjustment/adjustment_state.dart';
import '../../states/status/status_state.dart';
import '../../states/user/user_state.dart';
import '../../utils/fullscreen_viewer.dart';
import '../../widgets/input_field/common_plate_field.dart';
import '../../widgets/input_field/location_field.dart';
import '../../widgets/keypad/num_keypad.dart';
import '../../widgets/keypad/kor_keypad.dart';
import '../../widgets/navigation/bottom_navigation.dart';
import '../../states/area/area_state.dart';
import '../../utils/show_snackbar.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../utils/camera_helper.dart';
import '../../widgets/dialog/camera_preview_dialog.dart';
import '../../widgets/dialog/region_picker_dialog.dart';
import 'package:camera/camera.dart';
import '../../services/input_plate_service.dart';
import '../../utils/button/animated_parking_button.dart';
import '../../utils/button/animated_photo_button.dart';
import '../../utils/button/animated_action_button.dart';
import '../../utils/button/custom_adjustment_dropdown.dart';

class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key});

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
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
  bool showKeypad = true;
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

  @override
  void initState() {
    super.initState();
    _cameraHelper = CameraHelper();
    _cameraHelper.initializeCamera().then((_) {
      if (mounted) setState(() {}); // 초기화 완료 후 UI 갱신
    });
    activeController = controller3digit;
    _addInputListeners();
    isLocationSelected = locationController.text.isNotEmpty;

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

    final fetchedStatuses = statusState.statuses
        .where((status) => status.area == currentArea && status.isActive) // ✅ 수정됨
        .map((status) => status.name) // ✅ 수정됨
        .toList();

    setState(() {
      statuses = fetchedStatuses;
      isSelected = List.generate(statuses.length, (index) => false);
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
      builder: (context) =>
          CameraPreviewDialog(
            onImageCaptured: (image) {
              setState(() {
                _capturedImages.add(image);
                debugPrint('📸 이미지 1장 실시간 반영됨: ${image.path}');
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

  String _buildPlateNumber() {
    return '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';
  }

  void _resetInputForm() {
    clearInput();
    _clearLocation();
    _capturedImages.clear();
    setState(() {});
  }

  Future<void> _handleAction() async {
    final plateNumber = _buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final userName = context.read<UserState>().name;

    final uploadedImageUrls = await InputPlateService.uploadCapturedImages(
      _capturedImages,
      plateNumber,
      area,
      userName,
    );


    await InputPlateService.savePlateEntry(
      context: context,
      plateNumber: plateNumber,
      location: locationController.text,
      isLocationSelected: isLocationSelected,
      imageUrls: uploadedImageUrls,
      selectedAdjustment: selectedAdjustment,
      selectedStatuses: selectedStatuses,
      basicStandard: selectedBasicStandard,
      basicAmount: selectedBasicAmount,
      addStandard: selectedAddStandard,
      addAmount: selectedAddAmount,
      region: dropdownValue,
    );

    _resetInputForm();
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
            Icon(Icons.arrow_back_ios, size: 16, color: Colors.grey),
            SizedBox(width: 4),
            Text(
              " 번호 등록 | 업무 현황 ",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
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
                          child: CommonPlateInput(
                            frontDigitCount: 3,
                            hasMiddleChar: true,
                            backDigitCount: 4,
                            frontController: controller3digit,
                            middleController: controller1digit,
                            backController: controller4digit,
                            activeController: activeController,
                            onKeypadStateChanged: (TextEditingController newController) {
                              setState(() {
                                activeController = newController;
                                showKeypad = true;
                              });
                            },
                          ),
                        ),
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
                    child: _capturedImages.isEmpty
                        ? const Center(child: Text('촬영된 사진 없음'))
                        : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _capturedImages.length,
                      itemBuilder: (context, index) {
                        final imageFile = _capturedImages[index];
                        return GestureDetector(
                          onTap: () => showFullScreenImageViewer(context, _capturedImages, index),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              transitionBuilder: (child, animation) {
                                return ScaleTransition(
                                  scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                                  child: FadeTransition(opacity: animation, child: child),
                                );
                              },
                              child: Image.file(
                                File(imageFile.path),
                                key: ValueKey(imageFile.path),
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        );
                      },
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
                          child: Center(
                            child: Text(
                              '설정된 정산 유형이 없어 무료입니다.',
                              style: TextStyle(color: Colors.green),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      final adjustmentState = context.watch<AdjustmentState>();
                      final adjustmentList = adjustmentState.adjustments;
                      if (adjustmentList.isEmpty) {
                        return const Text('등록된 정산 유형이 없습니다.');
                      }

                      final dropdownItems = adjustmentList.map((adj) => adj.countType).toList();

                      return CustomAdjustmentDropdown(
                        items: dropdownItems,
                        selectedValue: selectedAdjustment,
                        onChanged: (newValue) {
                          setState(() {
                            selectedAdjustment = newValue;
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
                Expanded(
                  child: AnimatedParkingButton(
                    isLocationSelected: isLocationSelected,
                    onPressed: isLocationSelected ? _clearLocation : _selectParkingLocation,
                  ),

                ),
              ],
            ),
            const SizedBox(height: 15),
            AnimatedActionButton(
              isLoading: isLoading,
              isLocationSelected: isLocationSelected,
              onPressed: () async {
                setState(() => isLoading = true);
                await _handleAction();
                if (!mounted) return;
                setState(() => isLoading = false);
              },
            ),
          ],
        ),
      ),
    );
  }
}
