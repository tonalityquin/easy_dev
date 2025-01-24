import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/user_state.dart';
import '../../widgets/input_field/front_3_digit.dart';
import '../../widgets/input_field/middle_1_digit.dart';
import '../../widgets/input_field/back_4_digit.dart';
import '../../widgets/input_field/location_field.dart';
import '../../widgets/keypad/num_keypad.dart';
import '../../widgets/keypad/kor_keypad.dart';
import '../../widgets/container/location_container.dart';
import '../../widgets/navigation/bottom_navigation.dart';
import '../../states/plate_state.dart';
import '../../states/area_state.dart';
import '../../repositories/plate_repository.dart';

/// **Input3Digit**
/// 번호판 및 주차 구역 입력을 처리하는 화면
class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key});

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
  // 컨트롤러: 입력 필드 및 상태 관리
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

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

    try {
      if (!isLocationSelected) {
        await plateRepository.addRequestOrCompleted(
          collection: 'parking_requests',
          plateNumber: plateNumber,
          location: location,
          area: areaState.currentArea,
          userName: userState.name,
          type: '입차 요청',
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
                        onTap: _selectParkingLocation,
                        widthFactor: 0.7,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isLoading) const Center(child: CircularProgressIndicator()),
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
            ElevatedButton(
              onPressed: isLocationSelected ? _clearLocation : _selectParkingLocation,
              style: commonButtonStyle,
              child: Text(isLocationSelected ? '구역 초기화' : '주차 구역 선택'),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: isLoading ? null : _handleAction,
              style: commonButtonStyle,
              child: Text(isLocationSelected ? '입차 완료' : '입차 요청'),
            ),
          ],
        ),
      ),
    );
  }
}
