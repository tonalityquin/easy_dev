import 'package:flutter/material.dart';

class LocationContainer extends StatelessWidget {
  final String location;
  final bool isSelected;
  final VoidCallback onTap;

  const LocationContainer({
    Key? key,
    required this.location,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300), // ✅ 애니메이션 지속 시간
        curve: Curves.easeInOut, // ✅ 부드러운 전환 애니메이션
        width: double.infinity,
        height: 80,
        alignment: Alignment.center, // ✅ 중앙 기준으로 정렬
        transformAlignment: Alignment.center, // ✅ 축소 시 중앙 기준 유지
        transform: isSelected
            ? (Matrix4.identity()..scale(0.95)) // ✅ 선택되면 95% 크기로 축소
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.white, // ✅ 선택 시 배경색 변경
          border: Border.all(color: Colors.black, width: 2.0),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
          ],
        ),
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
