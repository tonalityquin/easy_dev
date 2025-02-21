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

/// 사진 촬영
import 'dart:io';
import 'package:image_picker/image_picker.dart';

/// **Input3Digit**
/// 번호판 및 주차 구역 입력을 처리하는 화면
class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key});

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
  List<String> selectedStatuses = [];
  List<bool> isSelected = [];
  List<String> statuses = [];

  // 🔹 정산 데이터를 저장할 변수 추가
  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  // 컨트롤러: 입력 필드 및 상태 관리
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  String? selectedAdjustment;

  late TextEditingController activeController; // 현재 활성화된 입력 필드
  bool showKeypad = true; // 키패드 표시 여부
  bool isLoading = false; // 로딩 상태
  bool isLocationSelected = false; // 주차 구역 선택 여부

  final ButtonStyle commonButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.grey[300],
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 150.0, vertical: 15.0),
  );

  @override
  void initState() {
    super.initState();
    activeController = controller3digit;
    _addInputListeners();
    isLocationSelected = locationController.text.isNotEmpty;

    // 🔹 상태 목록을 초기화하는 함수 호출
    _initializeStatuses();
  }

  // 🔹 상태 목록을 불러오는 함수
  Future<void> _initializeStatuses() async {
    final statusState = context.read<StatusState>();
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;

    final fetchedStatuses = statusState.statuses
        .where((status) => status['area'] == currentArea)
        .map((status) => (status['name'] ?? '') as String)
        .toList();

    // 🔹 상태 업데이트 (setState 사용)
    setState(() {
      statuses = fetchedStatuses;
      isSelected = List.generate(statuses.length, (index) => false);
    });
  }

  /// 사진 촬영 관련
  List<File> _selectedImages = []; // 🔥 여러 장 저장 가능하도록 리스트로 변경

  Future<void> _captureImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image == null) return; // 사용자가 촬영을 취소한 경우

    setState(() {
      _selectedImages.add(File(image.path)); // 🔥 리스트에 추가하여 여러 장 저장
    });
  }

  /// 사진 삭제 기능 추가
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  @override
  void dispose() {
    _removeInputListeners();
    controller3digit.dispose();
    controller1digit.dispose();
    controller4digit.dispose();
    locationController.dispose();
    super.dispose();
  }

  // 입력 필드의 변화 감지
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

  // 현재 활성화된 입력 필드 설정
  void _setActiveController(TextEditingController controller) {
    setState(() {
      activeController = controller;
      showKeypad = true;
    });
  }

  // 입력값 유효성 검사
  bool _validateField(TextEditingController controller, int maxLength) {
    return controller.text.length <= maxLength;
  }

  // 입력값 변화 처리
  void _handleInputChange() {
    if (!_validateField(controller3digit, 3) ||
        !_validateField(controller1digit, 1) ||
        !_validateField(controller4digit, 4)) {
      _showSnackBar('입력값이 유효하지 않습니다. 다시 확인해주세요.');
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

  // 알림 메시지 표시
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // 입력값 초기화
  void clearInput() {
    setState(() {
      controller3digit.clear();
      controller1digit.clear();
      controller4digit.clear();
      activeController = controller3digit;
      showKeypad = true;
    });
  }

  // 주차 구역 초기화
  void _clearLocation() {
    setState(() {
      locationController.clear();
      isLocationSelected = false;
    });
  }

  // 입차 요청 또는 완료 처리
  Future<void> _handleAction() async {
    final String plateNumber = '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';
    final plateRepository = context.read<PlateRepository>();
    final plateState = context.read<PlateState>();
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();
    String location = locationController.text;

    if (plateState.isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
      _showSnackBar('이미 등록된 번호판입니다: $plateNumber');
      return;
    }

    if (location.isEmpty) {
      location = '미지정';
    }

    setState(() {
      isLoading = true;
    });

    // 🔹 isSelected를 반영하여 선택된 상태 목록을 업데이트
    selectedStatuses = [];
    for (int i = 0; i < isSelected.length; i++) {
      if (isSelected[i]) {
        selectedStatuses.add(statuses[i]); // 🔹 statuses가 선언되었으므로 오류 해결
      }
    }

    // 🔹 선택된 상태 리스트를 출력하여 디버깅
    debugPrint('선택된 상태: $selectedStatuses');

    try {
      if (!isLocationSelected) {
        await plateRepository.addRequestOrCompleted(
          collection: 'parking_requests',
          plateNumber: plateNumber,
          location: location,
          area: areaState.currentArea,
          userName: userState.name,
          type: '입차 요청',
          adjustmentType: selectedAdjustment,
          statusList: selectedStatuses.isNotEmpty ? selectedStatuses : [],
          // 🔹 비어 있으면 [] 저장
          basicStandard: selectedBasicStandard,
          // ✅ 상태에서 가져온 데이터 저장
          basicAmount: selectedBasicAmount,
          addStandard: selectedAddStandard,
          addAmount: selectedAddAmount,
        );
        _showSnackBar('입차 요청 완료');
      } else {
        await plateRepository.addRequestOrCompleted(
          collection: 'parking_completed',
          plateNumber: plateNumber,
          location: location,
          area: areaState.currentArea,
          userName: userState.name,
          type: '입차 완료',
          adjustmentType: selectedAdjustment,
          statusList: selectedStatuses.isNotEmpty ? selectedStatuses : [],
          // 🔹 비어 있으면 [] 저장
          basicStandard: selectedBasicStandard,
          // ✅ 상태에서 가져온 데이터 저장
          basicAmount: selectedBasicAmount,
          addStandard: selectedAddStandard,
          addAmount: selectedAddAmount,
        );
        _showSnackBar('입차 완료');
      }
      clearInput();
      _clearLocation();
    } catch (error) {
      _showSnackBar('오류 발생: $error');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 주차 구역 선택
  void _selectParkingLocation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final currentArea = context.watch<AreaState>().currentArea;

        return AlertDialog(
          title: const Text('주차 구역 선택'),
          content: FutureBuilder<List<String>>(
            future: context.read<PlateRepository>().getAvailableLocations(currentArea),
            builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('사용 가능한 주차 구역이 없습니다.'));
              }

              final locations = snapshot.data!;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: locations.map((location) {
                    return ListTile(
                      title: Text(location),
                      onTap: () {
                        setState(() {
                          locationController.text = location;
                          isLocationSelected = true;
                        });
                        Navigator.pop(context);
                      },
                    );
                  }).toList(),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _refreshAdjustments() async {
    final adjustmentState = context.read<AdjustmentState>();
    await Future.delayed(const Duration(milliseconds: 300)); // 🔥 Firestore 데이터 로드 대기
    adjustmentState.syncWithAreaState(); // 🔥 강제 동기화 트리거
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              // ✅ 스크롤 가능하도록 감싸줌
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
                  Container(
                    height: 100, // 🔥 높이 조정 (여러 장을 보기 좋게 배치)
                    child: _selectedImages.isEmpty
                        ? const Center(child: Text('촬영된 사진 없음'))
                        : ListView.builder(
                            scrollDirection: Axis.horizontal, // 🔥 가로 스크롤 가능하도록 설정
                            itemCount: _selectedImages.length,
                            itemBuilder: (context, index) {
                              return Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Image.file(
                                      _selectedImages[index],
                                      width: 100, // 🔥 사진 크기 조정
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => _removeImage(index), // 🔥 삭제 기능 추가
                                      child: Container(
                                        padding: const EdgeInsets.all(4.0),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, size: 16, color: Colors.white),
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
                    future: _refreshAdjustments(), // 🔥 지역 변경 후 강제 업데이트
                    builder: (context, snapshot) {
                      final adjustmentState = context.watch<AdjustmentState>();
                      final currentArea = context.watch<AreaState>().currentArea.trim();
                      final adjustmentsForArea = adjustmentState.adjustments
                          .where((adj) => adj['area'].toString().trim() == currentArea)
                          .map<String>((adj) => adj['countType']?.toString().trim() ?? '')
                          .where((type) => type.isNotEmpty)
                          .toList();

                      debugPrint('🔥 현재 지역($currentArea)에 대한 필터링된 정산 유형: $adjustmentsForArea');

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
                controller: controller3digit, maxLength: 3, onComplete: () => _setActiveController(controller1digit))
            : activeController == controller1digit
                ? KorKeypad(controller: controller1digit, onComplete: () => _setActiveController(controller4digit))
                : NumKeypad(
                    controller: controller4digit, maxLength: 4, onComplete: () => setState(() => showKeypad = false)),
        actionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _captureImage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black, // 🔥 글자 색상 명확하게 설정
                      padding: const EdgeInsets.symmetric(vertical: 15.0), // 🔥 버튼 크기 조절
                    ),
                    child: Text(
                      '사진 촬영',
                      textAlign: TextAlign.center, // 🔥 텍스트 중앙 정렬
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isLocationSelected ? _clearLocation : _selectParkingLocation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black, // 🔥 글자 색상 명확하게 설정
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
            const SizedBox(height: 15), // 버튼 간 간격 추가
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
