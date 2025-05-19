import 'package:flutter/material.dart';

class LocationContainer extends StatelessWidget {
  final String location;
  final bool isSelected;
  final VoidCallback onTap;

  // 🔹 추가 필드: 구역 타입 및 상위 구역 이름
  final String? type;   // 'single' 또는 'composite'
  final String? parent;

  const LocationContainer({
    super.key,
    required this.location,
    required this.isSelected,
    required this.onTap,
    this.type,
    this.parent,
  });

  @override
  Widget build(BuildContext context) {
    final isComposite = type == 'composite';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: double.infinity,
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        transformAlignment: Alignment.center,
        transform: isSelected
            ? (Matrix4.identity()..scale(0.97))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: isComposite ? Colors.grey.shade100 : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.black87,
            width: 2.0,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isComposite ? Icons.layers : Icons.place,
              color: isComposite ? Colors.blueAccent : Colors.grey,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (isComposite && parent != null)
                    Text(
                      '복합 주차 구역 (상위: $parent)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
