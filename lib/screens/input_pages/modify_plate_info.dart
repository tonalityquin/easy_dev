import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easydev/states/adjustment/adjustment_state.dart';
import 'package:easydev/states/status/status_state.dart';
import 'package:easydev/states/user/user_state.dart';
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
import 'package:easydev/states/plate/input_plate.dart';
import 'package:easydev/models/plate_model.dart';

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
    '서울',
    '경기',
    '부산',
    '인천',
    '대전',
    '대구',
    '울산',
    '광주',
    '강원',
    '충북',
    '충남',
    '경북',
    '경남',
    '전북',
    '전남',
    '제주',
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
  final CameraHelper _cameraHelper = CameraHelper();
  String? selectedAdjustment;
  final ButtonStyle commonButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.grey[300],
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 150.0, vertical: 15.0),
  );

  @override
  void initState() {
    super.initState();

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
    Future.delayed(Duration(milliseconds: 100), () async {
      try {
        await Future.wait([
          _initializeStatuses().timeout(Duration(seconds: 3)),
          _initializeCamera().timeout(Duration(seconds: 3)),
        ]);
      } catch (e) {
        debugPrint("초기화 오류 발생: $e");
      }

      if (mounted) {
        setState(() {});
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

  Future<void> _initializeCamera() async {
    await _cameraHelper.initializeCamera();
  }

  Future<void> _showCameraPreviewDialog() async {
    final bool? isUpdated = await showDialog(
      context: context,
      builder: (BuildContext context) => CameraPreviewDialog(cameraHelper: _cameraHelper),
    );

    if (isUpdated == true) {
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
    final String plateNumber = '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';
    final inputState = context.read<InputPlate>();
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();

    await inputState.updatePlateInfo(
      context: context,
      plate: widget.plate,
      newPlateNumber: plateNumber,
      location: locationController.text,
      areaState: areaState,
      userState: userState,
      collectionKey: widget.collectionKey,
      adjustmentType: selectedAdjustment,
      statusList: selectedStatuses,
      basicStandard: selectedBasicStandard,
      basicAmount: selectedBasicAmount,
      addStandard: selectedAddStandard,
      addAmount: selectedAddAmount,
      region: dropdownValue,
    );

    clearInput();
    _clearLocation();
    Navigator.pop(context);
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
        backgroundColor: Colors.blueAccent,
      ),
      body: !_cameraHelper.isCameraInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
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
                          child: _cameraHelper.capturedImages.isEmpty
                              ? const Center(child: Text('촬영된 사진 없음'))
                              : ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _cameraHelper.capturedImages.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Image.file(
                                        File(_cameraHelper.capturedImages[index].path),
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
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
                          future: _refreshAdjustments().timeout(Duration(seconds: 3), onTimeout: () => false),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (snapshot.data == false) {
                              return const Text('정산 유형 정보를 불러오지 못했습니다.');
                            }
                            final adjustmentState = context.watch<AdjustmentState>();
                            final adjustmentList = adjustmentState.adjustments;
                            if (adjustmentList.isEmpty) {
                              return const Text('등록된 정산 유형이 없습니다.');
                            }
                            return DropdownButtonFormField<String>(
                              value: selectedAdjustment,
                              onChanged: (newValue) {
                                setState(() {
                                  selectedAdjustment = newValue;
                                });
                              },
                              items: adjustmentList.map((adj) {
                                return DropdownMenuItem<String>(
                                  value: adj.countType, // ✅ 클래스 속성 방식으로 변경
                                  child: Text(adj.countType), // ✅ 클래스 속성 방식으로 변경
                                );
                              }).toList(),
                              decoration: const InputDecoration(
                                labelText: '정산 유형 선택',
                                border: OutlineInputBorder(),
                              ),
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
                  child: ElevatedButton(
                    onPressed: _showCameraPreviewDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15.0),
                    ),
                    child: const Text(
                      '사진 촬영',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // ✅ 1. 주차 구역 선택 버튼 (초기화 제거)
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectParkingLocation, // 항상 선택만 허용
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15.0),
                    ),
                    child: const Text(
                      '주차 구역 선택',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            // ✅ 2. 수정 완료 버튼
            ElevatedButton(
              onPressed: isLoading ? null : _handleAction, // 기존 입차 로직 재사용 가능
              style: commonButtonStyle,
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '수정 완료',
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
