import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/adjustment/adjustment_state.dart';
import '../../states/status/status_state.dart';
import '../../states/user/user_state.dart';
import '../../widgets/keypad/num_keypad.dart';
import '../../widgets/keypad/kor_keypad.dart';
import '../../widgets/navigation/bottom_navigation.dart';
import '../../states/area/area_state.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../utils/camera_helper.dart';
import '../../widgets/dialog/camera_preview_dialog.dart';
import 'package:camera/camera.dart';
import '../../services/input_plate_service.dart';
import '../../utils/button/animated_parking_button.dart';
import '../../utils/button/animated_photo_button.dart';
import '../../utils/button/animated_action_button.dart';
import 'sections/adjustment_section.dart';
import 'sections/parking_location_section.dart';
import 'sections/photo_section.dart';
import 'sections/plate_input_section.dart';
import 'sections/status_chip_section.dart';

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
    final adjustmentList = context.read<AdjustmentState>().adjustments;

    if (adjustmentList.isNotEmpty && selectedAdjustment == null) {
      showFailedSnackbar(context, '정산 유형을 선택해주세요');
      return;
    }

    setState(() => isLoading = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 📸 Step 1. 이미지 업로드 (전체 실패 처리)
      final uploadedImageUrls = await InputPlateService.uploadCapturedImages(
        _capturedImages,
        plateNumber,
        area,
        userName,
      );

      // 📝 Step 2. plate 데이터 등록
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

      Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
      showSuccessSnackbar(context, '차량 정보 등록 완료');
      _resetInputForm();

    } catch (e) {
      Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
      showFailedSnackbar(context, '등록 실패: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
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
        automaticallyImplyLeading: false,
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
                  PlateInputSection(
                    dropdownValue: dropdownValue,
                    regions: regions,
                    controller3digit: controller3digit,
                    controller1digit: controller1digit,
                    controller4digit: controller4digit,
                    activeController: activeController,
                    onKeypadStateChanged: (controller) {
                      setState(() {
                        activeController = controller;
                        showKeypad = true;
                      });
                    },
                    onRegionChanged: (region) {
                      setState(() {
                        dropdownValue = region;
                      });
                    },
                  ),
                  const SizedBox(height: 32.0),
                  ParkingLocationSection(locationController: locationController),
                  const SizedBox(height: 32.0),
                  PhotoSection(capturedImages: _capturedImages),
                  const SizedBox(height: 32.0),
                  AdjustmentSection(
                    selectedAdjustment: selectedAdjustment,
                    onChanged: (value) => setState(() => selectedAdjustment = value),
                    onRefresh: _refreshAdjustments,
                  ),
                  const SizedBox(height: 32.0),
                  StatusChipSection(
                    statuses: statuses,
                    isSelected: isSelected,
                    onToggle: (index) {
                      setState(() {
                        isSelected[index] = !isSelected[index];
                        final status = statuses[index];
                        if (isSelected[index]) {
                          selectedStatuses.add(status);
                        } else {
                          selectedStatuses.remove(status);
                        }
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
                  child: AnimatedPhotoButton(
                    onPressed: _showCameraPreviewDialog,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedParkingButton(
                    isLocationSelected: isLocationSelected,
                    onPressed:
                    isLocationSelected ? _clearLocation : _selectParkingLocation,
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
