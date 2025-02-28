// ------------------- Input3Digit.dart -------------------
// [원본 코드에서 카메라 관련 로직 분리 후, CameraHelper 호출로 대체]

import 'package:camera/camera.dart'; // [추가] CameraPreview, XFile 사용을 위해 직접 import
import 'dart:io'; // [추가] 이미지 미리보기(File) 사용을 위해 import
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../states/adjustment_state.dart';
import '../../states/status_state.dart';
import '../../states/user_state.dart';
import '../../widgets/input_field/front_3_digit.dart';
import '../../widgets/input_field/middle_1_digit.dart';
import '../../widgets/input_field/back_4_digit.dart';
import '../../widgets/input_field/location_field.dart';
import '../../widgets/keypad/num_keypad.dart';
import '../../widgets/keypad/kor_keypad.dart';
import '../../widgets/navigation/bottom_navigation.dart';
import '../../states/plate_state.dart';
import '../../states/area_state.dart';
import '../../repositories/plate_repository.dart';
import '../../utils/show_snackbar.dart';
import '../../widgets/dialog/parking_location_dialog.dart';

// [새로운 코드 추가] camera_helper.dart 불러오기
import '../../utils/camera_helper.dart'; // CameraHelper를 사용하기 위한 import

/// 번호판 및 주차 구역 입력을 처리하는 화면
class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key});

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
  // ------------------- 멤버 변수 선언 -------------------
  List<String> selectedStatuses = [];
  List<bool> isSelected = [];
  List<String> statuses = [];

  // 정산 데이터를 저장할 변수
  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  // 입력 컨트롤러
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  // 현재 활성화된 입력 필드
  late TextEditingController activeController;

  bool showKeypad = true; // 키패드 표시 여부
  bool isLoading = false; // 로딩 상태
  bool isLocationSelected = false; // 주차 구역 선택 여부

  // [추가] CameraHelper 인스턴스 생성 (카메라 로직 담당)
  final CameraHelper _cameraHelper = CameraHelper();

  String? selectedAdjustment;

  final ButtonStyle commonButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.grey[300],
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 150.0, vertical: 15.0),
  );

  // ------------------- initState -------------------
  @override
  void initState() {
    super.initState();
    activeController = controller3digit;
    _addInputListeners();
    isLocationSelected = locationController.text.isNotEmpty;
    _initializeStatuses();
    _initializeCamera(); // [추가] 카메라 헬퍼 초기화
  }

  // ------------------- 주차 구역 상태 목록 불러오기 -------------------
  Future<void> _initializeStatuses() async {
    final statusState = context.read<StatusState>();
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;

    final fetchedStatuses = statusState.statuses
        .where((status) => status['area'] == currentArea)
        .map((status) => (status['name'] ?? '') as String)
        .toList();

    setState(() {
      statuses = fetchedStatuses;
      isSelected = List.generate(statuses.length, (index) => false);
    });
  }

  // ------------------- 입력 리스너 관련 메서드 -------------------
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
    if (!_validateField(controller3digit, 3) ||
        !_validateField(controller1digit, 1) ||
        !_validateField(controller4digit, 4)) {
      showSnackbar(context, '입력값이 유효하지 않습니다. 다시 확인해주세요.');
      clearInput();
      return;
    }

    // 모든 필드가 채워졌을 경우 키패드 숨김
    if (controller3digit.text.length == 3 && controller1digit.text.length == 1 && controller4digit.text.length == 4) {
      setState(() {
        showKeypad = false;
      });
      return;
    }

    // 다음 입력 필드로 포커스 이동
    if (activeController == controller3digit && controller3digit.text.length == 3) {
      _setActiveController(controller1digit);
    } else if (activeController == controller1digit && controller1digit.text.length == 1) {
      _setActiveController(controller4digit);
    }
  }

  // ------------------- 카메라 관련 메서드 -------------------
  Future<void> _initializeCamera() async {
    // CameraHelper를 통해 카메라 초기화
    await _cameraHelper.initializeCamera();
    setState(() {});
  }

  /// 카메라 팝업 표시 (카메라 미리보기 + 촬영 버튼)
  Future<void> _showCameraPreviewDialog() async {
    if (!_cameraHelper.isCameraInitialized) {
      showSnackbar(context, '카메라가 아직 초기화되지 않았습니다.');
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Column(
            children: [
              Expanded(
                // CameraPreview는 camera 패키지에 정의
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: CameraPreview(_cameraHelper.cameraController!),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await _cameraHelper.captureImage();
                      // 팝업은 닫지 않음
                      setState(() {});
                    },
                    child: const Text('촬영'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // 팝업 닫기
                    },
                    child: const Text('완료'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 사진 삭제 (CameraHelper에서 관리하는 리스트에서 제거)
  void _removeImage(int index) {
    _cameraHelper.removeImage(index);
    setState(() {});
  }

  /// 큰 팝업(Dialog)으로 전체 사진 보기
  void _showFullPreviewDialog(XFile imageFile) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Image.file(
            File(imageFile.path),
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }

  // ------------------- 기타 주요 메서드 -------------------
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

  // ------------------- 입차 요청/입차 완료 처리 -------------------
  Future<void> _handleAction() async {
    final String plateNumber = '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';
    final plateRepository = context.read<PlateRepository>();
    final plateState = context.read<PlateState>();
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();
    String location = locationController.text;

    // 번호판 중복 체크
    if (plateState.isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
      showSnackbar(context, '이미 등록된 번호판입니다: $plateNumber');
      return;
    }

    if (location.isEmpty) {
      location = '미지정';
    }

    setState(() {
      isLoading = true;
    });

    // 선택된 상태 업데이트
    selectedStatuses = [];
    for (int i = 0; i < isSelected.length; i++) {
      if (isSelected[i]) {
        selectedStatuses.add(statuses[i]);
      }
    }

    try {
      if (!isLocationSelected) {
        // 입차 요청
        await plateRepository.addRequestOrCompleted(
          collection: 'parking_requests',
          plateNumber: plateNumber,
          location: location,
          area: areaState.currentArea,
          userName: userState.name,
          type: '입차 요청',
          adjustmentType: selectedAdjustment,
          statusList: selectedStatuses.isNotEmpty ? selectedStatuses : [],
          basicStandard: selectedBasicStandard,
          basicAmount: selectedBasicAmount,
          addStandard: selectedAddStandard,
          addAmount: selectedAddAmount,
        );
        showSnackbar(context, '입차 요청 완료');
      } else {
        // 입차 완료
        await plateRepository.addRequestOrCompleted(
          collection: 'parking_completed',
          plateNumber: plateNumber,
          location: location,
          area: areaState.currentArea,
          userName: userState.name,
          type: '입차 완료',
          adjustmentType: selectedAdjustment,
          statusList: selectedStatuses.isNotEmpty ? selectedStatuses : [],
          basicStandard: selectedBasicStandard,
          basicAmount: selectedBasicAmount,
          addStandard: selectedAddStandard,
          addAmount: selectedAddAmount,
        );
        showSnackbar(context, '입차 완료');
      }
      clearInput();
      _clearLocation();
    } catch (error) {
      showSnackbar(context, '오류 발생: $error');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // ------------------- 주차 구역 선택 팝업 -------------------
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

  // ------------------- Firestore 정산 유형 반영 -------------------
  Future<void> _refreshAdjustments() async {
    final adjustmentState = context.read<AdjustmentState>();
    await Future.delayed(const Duration(milliseconds: 300)); // Firestore 데이터 로드 대기
    adjustmentState.syncWithAreaState(); // 지역 상태와 강제 동기화
  }

  // ------------------- dispose -------------------
  @override
  void dispose() {
    _removeInputListeners();
    controller3digit.dispose();
    controller1digit.dispose();
    controller4digit.dispose();
    locationController.dispose();
    // CameraHelper 자원 해제
    _cameraHelper.dispose();
    super.dispose();
  }

  // ------------------- build -------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
      ),
      // 카메라 초기화 여부 체크
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            NumFieldFront3(
                              controller: controller3digit,
                              readOnly: true,
                              onTap: () => _setActiveController(controller3digit),
                            ),
                            KorFieldMiddle1(
                              controller: controller1digit,
                              readOnly: true,
                              onTap: () => _setActiveController(controller1digit),
                            ),
                            NumFieldBack4(
                              controller: controller4digit,
                              readOnly: true,
                              onTap: () => _setActiveController(controller4digit),
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
                                    return Stack(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: GestureDetector(
                                            onTap: () {
                                              // 전체 화면(팝업)으로 확대
                                              _showFullPreviewDialog(
                                                _cameraHelper.capturedImages[index],
                                              );
                                            },
                                            child: Image.file(
                                              File(_cameraHelper.capturedImages[index].path),
                                              width: 100,
                                              height: 100,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: GestureDetector(
                                            onTap: () => _removeImage(index),
                                            child: Container(
                                              padding: const EdgeInsets.all(4.0),
                                              decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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
                        FutureBuilder(
                          future: _refreshAdjustments(),
                          builder: (context, snapshot) {
                            final adjustmentState = context.watch<AdjustmentState>();
                            final currentArea = context.watch<AreaState>().currentArea.trim();
                            final adjustmentsForArea = adjustmentState.adjustments
                                .where((adj) => adj['area'].toString().trim() == currentArea)
                                .map<String>((adj) => adj['countType']?.toString().trim() ?? '')
                                .where((type) => type.isNotEmpty)
                                .toList();

                            if (adjustmentsForArea.isEmpty) {
                              return const Text('등록된 정산 유형이 없습니다.');
                            }

                            if (selectedAdjustment == null || !adjustmentsForArea.contains(selectedAdjustment)) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                setState(() {
                                  selectedAdjustment = adjustmentsForArea.first;
                                });
                              });
                            }

                            return DropdownButtonFormField<String>(
                              value: selectedAdjustment,
                              onChanged: (newValue) {
                                setState(() {
                                  selectedAdjustment = newValue;
                                });
                              },
                              items: adjustmentsForArea.map((type) {
                                return DropdownMenuItem<String>(
                                  value: type,
                                  child: Text(type),
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
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLocationSelected ? _clearLocation : _selectParkingLocation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15.0),
                    ),
                    child: Text(
                      isLocationSelected ? '구역 초기화' : '주차 구역 선택',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: isLoading ? null : _handleAction,
              style: commonButtonStyle,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isLocationSelected ? '입차 완료' : '입차 요청',
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
