import 'package:flutter/material.dart';

/// 특정 위치를 표시하는 컨테이너 위젯
/// - 선택 여부에 따라 스타일 변경
/// - 탭 이벤트 처리 가능
class LocationContainer extends StatelessWidget {
  final String location; // 표시할 위치 이름
  final bool isSelected; // 선택 여부
  final VoidCallback onTap; // 탭 이벤트 처리 콜백

  const LocationContainer({
    Key? key,
    required this.location,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // 탭 이벤트 처리
      child: Container(
        width: double.infinity, // 부모의 가로 길이에 맞춤
        height: 80, // 고정된 높이
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white, // 선택 여부에 따른 배경색
          border: Border.all(color: Colors.black, width: 2.0), // 테두리 스타일
          borderRadius: BorderRadius.circular(8), // 둥근 모서리 처리
        ),
        alignment: Alignment.center, // 텍스트 중앙 정렬
        child: Text(
          location, // 위치 이름 표시
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black, // 텍스트 색상
          ),
        ),
      ),
    );
  }
}
