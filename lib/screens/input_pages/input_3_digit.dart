import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/input_field/front_3_digit.dart';
import '../../widgets/input_field/middle_1_digit.dart';
import '../../widgets/input_field/back_4_digit.dart';
import '../../widgets/keypad/num_keypad.dart';
import '../../widgets/keypad/kor_keypad.dart';
import '../../widgets/navigation/bottom_navigation.dart';
import '../../states/plate_state.dart';

class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key});

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();

  late TextEditingController activeController;
  bool showKeypad = true;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    activeController = controller3digit;

    controller3digit.addListener(_handleInputChange);
    controller1digit.addListener(_handleInputChange);
    controller4digit.addListener(_handleInputChange);
  }

  @override
  void dispose() {
    controller3digit.dispose();
    controller1digit.dispose();
    controller4digit.dispose();
    super.dispose();
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

  void _handleInputChange() {
    if (!_validateField(controller3digit, 3) ||
        !_validateField(controller1digit, 1) ||
        !_validateField(controller4digit, 4)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입력값이 유효하지 않습니다. 다시 확인해주세요.')),
      );
      clearInput();
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

  void clearInput() {
    setState(() {
      controller3digit.clear();
      controller1digit.clear();
      controller4digit.clear();
      activeController = controller3digit;
      showKeypad = true;
    });
  }

  Future<void> _submitParkingRequest() async {
    final String plateNumber = '${controller3digit.text}-${controller1digit.text}-${controller4digit.text}';

    if (!_validatePlateNumber(plateNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('번호판 형식이 올바르지 않습니다.')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await context.read<PlateState>().addRequest(plateNumber);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('입차 요청 성공')),
        );
      }
      clearInput();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('입차 요청 실패: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

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
              ],
            ),
          ),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(),
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
          onPressed: isLoading ? null : _submitParkingRequest,
          child: const Text('입차 요청'),
        ),
      ),
    );
  }
}
