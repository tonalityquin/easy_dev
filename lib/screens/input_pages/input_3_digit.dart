import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/input_field/front_3_digit.dart'; // 앞 3자리 입력 필드 위젯
import '../../widgets/input_field/middle_1_digit.dart'; // 중간 1자리 입력 필드 위젯
import '../../widgets/input_field/back_4_digit.dart'; // 뒤 4자리 입력 필드 위젯
import '../../widgets/input_field/location_field.dart'; // 주차 구역 입력 필드
import '../../widgets/keypad/location_select.dart'; // 주차 구역 선택 키패드
import '../../widgets/keypad/num_keypad.dart'; // 숫자 키패드 위젯
import '../../widgets/keypad/kor_keypad.dart'; // 한글 키패드 위젯
import '../../widgets/navigation/bottom_navigation.dart'; // 하단 내비게이션 바
import '../../states/plate_state.dart'; // 번호판 상태 관리 클래스

/// Input3Digit 위젯
/// 번호판 입력 및 주차 구역 설정을 처리하는 화면
class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key});

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
  // 텍스트 입력 컨트롤러 선언
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  late TextEditingController activeController; // 현재 활성화된 입력 컨트롤러
  bool showKeypad = true; // 키패드 표시 여부
  bool isLoading = false; // 로딩 상태 관리
  bool isLocationSelected = false; // 주차 구역 선택 여부

  // 공통 버튼 스타일
  final ButtonStyle commonButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.grey[300],
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 150.0, vertical: 15.0),
  );

  @override
  void initState() {
    super.initState();
    activeController = controller3digit; // 초기 활성화 입력 컨트롤러 설정
    // 입력 값 변경 리스너 추가
    controller3digit.addListener(_handleInputChange);
    controller1digit.addListener(_handleInputChange);
    controller4digit.addListener(_handleInputChange);
    isLocationSelected = locationController.text.isNotEmpty; // 주차 구역 선택 상태 초기화
  }

  @override
  void dispose() {
    // 컨트롤러 해제
    controller3digit.dispose();
    controller1digit.dispose();
    controller4digit.dispose();
    locationController.dispose();
    super.dispose();
  }

  /// 활성화된 입력 컨트롤러를 설정
  void _setActiveController(TextEditingController controller) {
    setState(() {
      activeController = controller;
      showKeypad = true; // 키패드 표시
    });
  }

  /// 입력 필드 유효성 검사
  /// [controller]: 입력 컨트롤러, [maxLength]: 최대 입력 길이
  bool _validateField(TextEditingController controller, int maxLength) {
    return controller.text.length <= maxLength;
  }

  /// 입력 변경 시 호출되는 메서드
  void _handleInputChange() {
    // 유효하지 않은 입력 값이 있으면 초기화
    if (!_validateField(controller3digit, 3) ||
        !_validateField(controller1digit, 1) ||
        !_validateField(controller4digit, 4)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입력값이 유효하지 않습니다. 다시 확인해주세요.')),
      );
      clearInput();
      return;
    }

    // 모든 필드가 입력 완료된 경우 키패드 숨김
    if (controller3digit.text.length == 3 && controller1digit.text.length == 1 && controller4digit.text.length == 4) {
      setState(() {
        showKeypad = false;
      });
      return;
    }

    // 입력 완료 시 다음 필드로 이동
    if (activeController == controller3digit && controller3digit.text.length == 3) {
      _setActiveController(controller1digit);
    } else if (activeController == controller1digit && controller1digit.text.length == 1) {
      _setActiveController(controller4digit);
    }
  }

  /// 입력 필드 초기화
  void clearInput() {
    setState(() {
      controller3digit.clear();
      controller1digit.clear();
      controller4digit.clear();
      activeController = controller3digit;
      showKeypad = true;
    });
  }

  /// 주차 구역 초기화
  void _clearLocation() {
    setState(() {
      locationController.clear();
      isLocationSelected = false;
    });
  }

  /// 번호판 및 주차 구역 데이터를 처리하는 메서드
  Future<void> _handleAction() async {
    final String plateNumber = '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';
    final plateState = context.read<PlateState>();
    final String location = locationController.text;

    // 번호판 중복 검사
    if (plateState.isPlateNumberDuplicated(plateNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미 등록된 번호판입니다: $plateNumber')),
      );
      return;
    }

    // 번호판 형식 검사
    if (!_validatePlateNumber(plateNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('번호판 형식이 올바르지 않습니다.')),
      );
      return;
    }

    setState(() {
      isLoading = true; // 로딩 상태 활성화
    });

    try {
      if (!isLocationSelected) {
        // 입차 요청 처리
        await plateState.addRequest(plateNumber);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('입차 요청')),
        );
      } else {
        // 입차 완료 처리
        await plateState.addCompleted(plateNumber, location);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('입차 완료')),
        );

        // 주차 구역 초기화
        _clearLocation();
      }

      clearInput(); // 입력 필드 초기화
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류 발생: $error')),
      );
    } finally {
      setState(() {
        isLoading = false; // 로딩 상태 비활성화
      });
    }
  }

  /// 번호판 형식 유효성 검사
  /// [plateNumber]: 입력된 번호판
  bool _validatePlateNumber(String plateNumber) {
    final RegExp platePattern = RegExp(r'^\d{3}-[가-힣]-\d{4}$');
    return platePattern.hasMatch(plateNumber);
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
                    // 앞 3자리 번호 입력 필드
                    NumFieldFront3(
                      controller: controller3digit,
                      readOnly: true,
                      onTap: () => _setActiveController(controller3digit),
                    ),
                    // 중간 1자리 번호 입력 필드
                    KorFieldMiddle1(
                      controller: controller1digit,
                      readOnly: true,
                      onTap: () => _setActiveController(controller1digit),
                    ),
                    // 뒤 4자리 번호 입력 필드
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
                  child: LocationField(
                    controller: locationController,
                    onTap: () {
                      // 주차 구역 선택 바텀 시트 표시
                      showModalBottomSheet(
                        context: context,
                        builder: (BuildContext context) {
                          return LocationSelect(
                            onSelect: (String selectedLocation) {
                              setState(() {
                                locationController.text = selectedLocation;
                                isLocationSelected = true;
                              });
                            },
                          );
                        },
                      );
                    },
                    widthFactor: 0.7, // 필드 너비 비율
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(), // 로딩 상태 표시
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigation(
        showKeypad: showKeypad, // 키패드 표시 여부
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
            ElevatedButton(
              onPressed: isLocationSelected
                  ? _clearLocation
                  : () {
                      showModalBottomSheet(
                        context: context,
                        builder: (BuildContext context) {
                          return LocationSelect(
                            onSelect: (String selectedLocation) {
                              setState(() {
                                locationController.text = selectedLocation;
                                isLocationSelected = true;
                              });
                            },
                          );
                        },
                      );
                    },
              style: commonButtonStyle,
              child: Text(isLocationSelected ? '구역 초기화' : '주차 구역'),
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
