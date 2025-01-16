import 'package:flutter/material.dart';

class LocationContainer extends StatelessWidget {
  final String location; // 위치 정보
  final bool isSelected; // 선택 여부
  final VoidCallback onTap; // 탭 이벤트

  const LocationContainer({
    Key? key,
    required this.location,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // 탭 이벤트
      child: Container(
        width: double.infinity, // 가로 길이를 부모에 맞춤
        height: 80, // 고정된 높이
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white, // 선택 여부에 따른 배경색
          border: Border.all(color: Colors.black, width: 2.0), // 테두리 스타일
          borderRadius: BorderRadius.circular(8), // 모서리 둥글기
        ),
        alignment: Alignment.center, // 텍스트 중앙 정렬
        child: Text(
          location,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
