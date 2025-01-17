import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

class Input3Digit extends StatefulWidget {
  const Input3Digit({super.key});

  @override
  State<Input3Digit> createState() => _Input3DigitState();
}

class _Input3DigitState extends State<Input3Digit> {
  final TextEditingController controller3digit = TextEditingController();
  final TextEditingController controller1digit = TextEditingController();
  final TextEditingController controller4digit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  late TextEditingController activeController;
  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;

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
      _showSnackBar('입력값이 유효하지 않습니다. 다시 확인해주세요.');
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    final plateRepository = context.read<PlateRepository>();
    final plateState = context.read<PlateState>();
    final areaState = context.read<AreaState>();
    String location = locationController.text;

    // 중복 번호판 확인
    if (plateState.isPlateNumberDuplicated(plateNumber, areaState.currentArea)) {
      _showSnackBar('이미 등록된 번호판입니다: $plateNumber');
      return;
    }

    // 주차 구역이 비어 있으면 "미지정"으로 처리
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
          type: '입차 요청',
        );
        _showSnackBar('입차 요청 완료');
      } else {
        await plateRepository.addRequestOrCompleted(
          collection: 'parking_completed',
          plateNumber: plateNumber,
          location: location,
          area: areaState.currentArea,
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

  void _selectParkingLocation() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        final currentArea = context.watch<AreaState>().currentArea;

        return FutureBuilder<List<String>>(
          future: context.read<PlateRepository>().getAvailableLocations(currentArea),
          builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('사용 가능한 주차 구역이 없습니다.'));
            }

            final locations = snapshot.data!;
            return ListView.builder(
              itemCount: locations.length,
              itemBuilder: (BuildContext context, int index) {
                final location = locations[index];
                return LocationContainer(
                  location: location,
                  isSelected: locationController.text == location,
                  onTap: () {
                    setState(() {
                      locationController.text = location;
                      isLocationSelected = true;
                    });
                    Navigator.pop(context);
                  },
                );
              },
            );
          },
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
