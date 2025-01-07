import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/input_field/front_3_digit.dart';
import '../../widgets/input_field/middle_1_digit.dart';
import '../../widgets/input_field/back_4_digit.dart';
import '../../widgets/keypad/num_keypad.dart';
import '../../widgets/keypad/kor_keypad.dart';
import '../../widgets/navigation/bottom_navigation.dart';
import '../../states/plate_state.dart';

/// 3자리 번호판 입력 페이지
/// 번호판 입력을 위해 여러 TextField와 키패드가 상호작용하며,
/// 유효성 검사 및 입차 요청 기능을 포함합니다.
class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key});

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
  /// 각 번호판 입력 필드에 대한 컨트롤러
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();

  /// 현재 활성화된 입력 필드의 컨트롤러
  late TextEditingController activeController;

  /// 키패드 표시 여부
  bool showKeypad = true;

  /// 입차 요청 중 로딩 상태 관리
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // 초기 활성 컨트롤러 설정
    activeController = controller3digit;

    // 각 컨트롤러에 입력 변경 리스너 추가
    controller3digit.addListener(_handleInputChange);
    controller1digit.addListener(_handleInputChange);
    controller4digit.addListener(_handleInputChange);
  }

  @override
  void dispose() {
    // 컨트롤러 리소스 해제
    controller3digit.dispose();
    controller1digit.dispose();
    controller4digit.dispose();
    super.dispose();
  }

  /// 활성화된 컨트롤러를 변경
  void _setActiveController(TextEditingController controller) {
    setState(() {
      activeController = controller;
      showKeypad = true;
    });
  }

  /// 입력 값이 최대 길이를 초과하지 않는지 검증
  bool _validateField(TextEditingController controller, int maxLength) {
    return controller.text.length <= maxLength;
  }

  /// 입력값 변경 시 호출되어 유효성 검사 및 활성 컨트롤러 전환
  void _handleInputChange() {
    // 각 필드 유효성 검사
    if (!_validateField(controller3digit, 3) ||
        !_validateField(controller1digit, 1) ||
        !_validateField(controller4digit, 4)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입력값이 유효하지 않습니다. 다시 확인해주세요.')),
      );
      clearInput(); // 입력값 초기화
      return;
    }

    // 모든 필드가 완전히 입력되면 키패드 숨기기
    if (controller3digit.text.length == 3 && controller1digit.text.length == 1 && controller4digit.text.length == 4) {
      setState(() {
        showKeypad = false;
      });
      return;
    }

    // 입력 길이에 따라 활성 컨트롤러 전환
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
      activeController = controller3digit; // 초기 컨트롤러로 재설정
      showKeypad = true;
    });
  }

  /// 입차 요청 전송
  Future<void> _submitParkingRequest() async {
    final String plateNumber = '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';

    // 번호판 형식 검증
    if (!_validatePlateNumber(plateNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('번호판 형식이 올바르지 않습니다.')),
      );
      return;
    }

    setState(() {
      isLoading = true; // 로딩 상태 시작
    });

    try {
      // 입차 요청 전송
      await context.read<PlateState>().addRequest(plateNumber);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('입차 요청 성공')),
        );
      }
      clearInput(); // 입력 초기화
    } catch (error) {
      // 에러 처리
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('입차 요청 실패: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false; // 로딩 상태 종료
        });
      }
    }
  }

  /// 번호판 형식 유효성 검사
  bool _validatePlateNumber(String plateNumber) {
    final RegExp platePattern = RegExp(r'^\d{3}-[가-힣]-\d{4}$');
    return platePattern.hasMatch(plateNumber);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('번호판 입력'),
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
                  '번호판 입력',
                  style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 앞 3자리 숫자 필드
                    NumFieldFront3(
                      controller: controller3digit,
                      readOnly: true,
                      onTap: () => _setActiveController(controller3digit),
                    ),
                    // 중간 1자리 한글 필드
                    KorFieldMiddle1(
                      controller: controller1digit,
                      readOnly: true,
                      onTap: () => _setActiveController(controller1digit),
                    ),
                    // 뒤 4자리 숫자 필드
                    NumFieldBack4(
                      controller: controller4digit,
                      readOnly: true,
                      onTap: () => _setActiveController(controller4digit),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(), // 로딩 인디케이터
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigation(
        showKeypad: showKeypad,
        keypad: activeController == controller3digit
            ? NumKeypad(
                controller: controller3digit,
                maxLength: 3,
                onComplete: () {
                  _setActiveController(controller1digit);
                },
              )
            : activeController == controller1digit
                ? KorKeypad(
                    controller: controller1digit,
                    onComplete: () {
                      _setActiveController(controller4digit);
                    },
                  )
                : NumKeypad(
                    controller: controller4digit,
                    maxLength: 4,
                    onComplete: () {
                      setState(() {
                        showKeypad = false;
                      });
                    },
                  ),
        actionButton: ElevatedButton(
          onPressed: isLoading ? null : _submitParkingRequest, // 입차 요청 버튼
          child: const Text('입차 요청'),
        ),
      ),
    );
  }
}
