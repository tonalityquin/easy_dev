import 'dart:io'; // [추가] 이미지 미리보기(File) 사용을 위해 import
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/adjustment_state.dart';
import '../../states/memo_state.dart';
import '../../states/user_state.dart';
import '../../widgets/input_field/common_plate_field.dart';
import '../../widgets/input_field/location_field.dart';
import '../../widgets/keypad/num_keypad.dart';
import '../../widgets/keypad/kor_keypad.dart';
import '../../widgets/navigation/bottom_navigation.dart';
import '../../states/plate_state.dart';
import '../../states/area_state.dart';
import '../../repositories/plate_repository.dart';
import '../../utils/show_snackbar.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../utils/camera_helper.dart'; // CameraHelper를 사용하기 위한 import
import '../../widgets/dialog/camera_preview_dialog.dart';

/// 번호판 및 주차 구역 입력을 처리하는 화면
class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key}); // const 키워드를 사용하여 Input3Digit 위젯을 상수(constant)로 선언한다, key = 위젯 트리에서의 변경 감지 및 최적화 지원용

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
  /// UI 및 입력 데이터 관련 변수
  List<String> toggleMemo = [];
  List<bool> isSelected = [];
  List<String> memo = [];
  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  /// 텍스트 입력 컨트롤러
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  late TextEditingController activeController;

  /// UI 상태 및 로딩 관련 변수
  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;

  /// 카메라 관련 변수
  final CameraHelper _cameraHelper = CameraHelper();

  /// 정산 유형 관련 변수
  String? selectedAdjustment;

  /// 버튼 스타일 상수 선언
  final ButtonStyle commonButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.grey[300],
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 150.0, vertical: 15.0),
  );

  /// initState()에서 초기화 작업 수행
  @override
  void initState() {
    super.initState();
    activeController = controller3digit; // 초기 입력 필드 = 번호판 앞 3자리
    _addInputListeners(); // 입력을 감지하는 이벤트 리스너 추가
    isLocationSelected =
        locationController.text.isNotEmpty; // locationController의 값이 비어있지 않다면 isLocationSelected를 true로 설정한다.

    /// UI 프레임을 블로킹하지 않고 자연스럽게 실행되기 위한 딜레이 코드
    Future.delayed(Duration(milliseconds: 100), () async {
      try {
        await Future.wait([
          _initializeMemo().timeout(Duration(seconds: 3)), // 3초 후 강제 종료
          _initializeCamera().timeout(Duration(seconds: 3)), // 3초 후 강제 종료
        ]);
      } catch (e) {
        debugPrint("초기화 오류 발생: $e"); // 초기화 오류 로그 출력
      }

      // mounted를 확인하여 위젯이 아직 존재하는 경우에만 setState() 호출한다,  초기화가 끝난 후 UI가 정상적으로 갱신을 위한 것이다.
      if (mounted) {
        setState(() {});
      }
    });
  }

  /// 차량 상태 정보(Memo) 초기화
  Future<void> _initializeMemo() async {
    final memoState = context.read<MemoState>();
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;

    final fetchedMemo = memoState.memo
        .where((memo) => memo['area'] == currentArea && memo['isActive'] == true) // isActive가 true인 Memo만 데이터 가져오기
        .map((memo) => (memo['name'] ?? '') as String)
        .toList();

    setState(() {
      memo = fetchedMemo;
      isSelected = List.generate(memo.length, (index) => false);
    });
  }

  /// 카메라 초기화
  Future<void> _initializeCamera() async {
    await _cameraHelper.initializeCamera();
  }

  /// 차량 입차 요청 또는 입차 완료를 처리하는 함수
  Future<void> _handleAction() async {
    final String plateNumber =
        '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}'; // 세 개의 입력 필드에서 차량 번호판 정보를 조합하여 문자열로 생성
    final plateRepository = context.read<PlateRepository>(); // PlateRepository를 읽어와 데이터 저장소에 접근
    final plateState = context.read<PlateState>(); // PlateState를 읽어와 차량 번호판 관련 상태를 관리
    final areaState = context.read<AreaState>(); // AreaState를 읽어와 현재 선택된 지역 정보 확인
    final userState = context.read<UserState>(); // UserState를 읽어와 현재 사용자 정보 확인
    String location = locationController.text;

    /// 현재 지역에서 입력된 차량 번호판이 중복 확인 함수
    if (plateState.isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
      showSnackbar(context, '이미 등록된 번호판입니다: $plateNumber');
      return;
    }

    /// locaion은 미지정 기본값
    if (location.isEmpty) {
      location = '미지정';
    }

    setState(() {
      isLoading = true;
    });

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
          memoList: toggleMemo.isNotEmpty ? toggleMemo : [],
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
          memoList: toggleMemo.isNotEmpty ? toggleMemo : [],
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

  /// 지역 상태(AreaState)와 동기화하여 조정 정보(Adjustment)를 갱신하는 함수
  Future<bool> _refreshAdjustments() async {
    final adjustmentState = context.read<AdjustmentState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      adjustmentState.syncWithAreaState();
    });

    // 상태 반영이 끝날 시간을 확보하기 위해 약간의 지연 추가
    await Future.delayed(const Duration(milliseconds: 500));

    return adjustmentState.adjustments.isNotEmpty;
  }

  /// isActive가 true인 MemoList 호출하는 함수
  List<Map<String, dynamic>> get activeMemos {
    final memoState = context.read<MemoState>(); // MemoState 인스턴스 가져오기
    return memoState.memo.where((memo) => memo['isActive'] == true).toList();
  }

  /// 입력 및 이벤트 핸들링
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

  /// 컨트롤러 변경 조건 메서드
  void _handleInputChange() {
    if (controller3digit.text.isEmpty && controller1digit.text.isEmpty && controller4digit.text.isEmpty) {
      return;
    } // 모든 입력 필드가 비어 있으면 setState 호출을 방지하여 불필요한 UI 업데이트

    if (!_validateField(controller3digit, 3) ||
        !_validateField(controller1digit, 1) ||
        !_validateField(controller4digit, 4)) {
      showSnackbar(context, '입력값이 유효하지 않습니다. 다시 확인해주세요.');
      return;
    } // 각 입력 필드가 지정된 길이와 유효성 검사를 통과하지 못하면 오류 메시지를 표시

    if (controller3digit.text.length == 3 && controller1digit.text.length == 1 && controller4digit.text.length == 4) {
      setState(() {
        showKeypad = false;
      });
      return;
    } // 모든 입력 필드가 올바른 길이(3자리-1자리-4자리)를 충족하면 키패드 숨김

    if (activeController == controller3digit && controller3digit.text.length == 3) {
      _setActiveController(controller1digit);
    } // 현재 활성화된 입력 필드가 controller3digit이고 3자리가 모두 입력되면 다음 필드(controller1digit)로 이동
    else if (activeController == controller1digit && controller1digit.text.length == 1) {
      _setActiveController(controller4digit);
    }
  } // 현재 활성화된 입력 필드가 controller1digit이고 1자리가 입력되면 다음 필드(controller4digit)로 이동

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

  /// 카메라 UI 빌드 관련 함수
  Future<void> _showCameraPreviewDialog() async {
    final bool? isUpdated = await showDialog(
      context: context,
      builder: (BuildContext context) => CameraPreviewDialog(cameraHelper: _cameraHelper),
    );

    if (isUpdated == true) {
      setState(() {}); // ✅ 촬영된 이미지가 업데이트되었으므로 화면 갱신
    }
  }

  /// 자원 해제
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

  /// build() 및 전체 UI 조합
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
                        // 번호판 입력 UI
                        const Text(
                          '번호 입력',
                          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                        ),
                        CommonPlateInput(
                          frontDigitCount: 3,
                          hasMiddleChar: true,
                          backDigitCount: 4,
                          frontController: controller3digit,
                          middleController: controller1digit,
                          backController: controller4digit,
                          onKeypadStateChanged: (TextEditingController activeController) {
                            setState(() {
                              this.activeController = controller3digit; // ✅ 항상 3-digit부터 시작
                              showKeypad = true;
                            });
                          },
                        ),
                        const SizedBox(height: 32.0),
                        // 주차 구역 입력
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
                        // 촬영 사진 표시
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
                        // 정산 유형 선택 (Firestore 데이터 연동)
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

                            // 🔥 Firestore에서 정산 유형 데이터 가져오기
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
                              // 🔥 Firestore에서 가져온 데이터로 Dropdown 리스트 생성
                              items: adjustmentList.map((adj) {
                                return DropdownMenuItem<String>(
                                  value: adj['countType'], // Firestore의 countType 필드 사용
                                  child: Text(adj['countType']),
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
                        // 차량 상태 선택
                        const Text(
                          '차량 상태',
                          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8.0),
                        memo.isEmpty
                            ? const Text('등록된 차량 상태가 없습니다.')
                            : Wrap(
                                spacing: 8.0,
                                children: List.generate(memo.length, (index) {
                                  return ChoiceChip(
                                    label: Text(memo[index]),
                                    selected: isSelected[index],
                                    onSelected: (selected) {
                                      setState(() {
                                        isSelected[index] = selected;
                                        if (selected) {
                                          toggleMemo.add(memo[index]);
                                        } else {
                                          toggleMemo.remove(memo[index]);
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
      // 하단 키패드 및 버튼 영역
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
            // 사진 촬영 & 주차 구역 선택 버튼
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
                // 구역 초기화/주차 구역 선택 버튼
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
            // 입차 요청/완료 버튼
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
