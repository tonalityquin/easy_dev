import 'package:flutter/material.dart';

class LocationSelect extends StatelessWidget {
  final List<String> options = const ['지역 A', '지역 B', '지역 C'];

  final Function(String) onSelect;

  const LocationSelect({
    super.key,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: options.map((String option) {
        return ListTile(
          title: Text(
            option,
            style: const TextStyle(fontSize: 16.0), // 텍스트 스타일 설정
          ),
          onTap: () {
            Navigator.pop(context); // 모달 닫기
            onSelect(option); // 선택된 옵션 값을 콜백 함수에 전달
          },
        );
      }).toList(),
    );
  }
}
