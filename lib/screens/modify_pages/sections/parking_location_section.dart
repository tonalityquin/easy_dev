import 'package:flutter/material.dart';
import 'package:easydev/widgets/input_field/location_field.dart';

class ParkingLocationSection extends StatelessWidget {
  final TextEditingController locationController; // locationController를 필수 매개변수로 받음

  const ParkingLocationSection({
    super.key,
    required this.locationController, // locationController 매개변수를 필수로 받음
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
      children: [
        const Text(
          '주차 구역', // 주차 구역을 나타내는 텍스트
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold), // 텍스트 스타일 설정
        ),
        const SizedBox(height: 8.0), // 주차 구역 텍스트와 입력 필드 사이에 여백 추가
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, // 가로 정렬 중앙
            children: [
              LocationField(
                controller: locationController, // 입력 필드 컨트롤러 전달
                widthFactor: 0.7, // 입력 필드의 너비 비율 설정
              ),
            ],
          ),
        ),
      ],
    );
  }
}
