import 'package:flutter/material.dart';

/// 주차 구역 선택 모달 위젯
class LocationSelect extends StatelessWidget {
  final Function(String) onSelect; // 선택한 옵션을 처리하는 콜백 함수

  // 주차 구역 옵션 리스트 (LocationModal 내부에서 관리)
  final List<String> options = const ['지역 A', '지역 B', '지역 C'];

  const LocationSelect({
    super.key,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: options.map((String option) {
        return ListTile(
          title: Text(option, style: const TextStyle(fontSize: 16.0)),
          onTap: () {
            Navigator.pop(context); // 모달 닫기
            onSelect(option); // 선택한 옵션 전달
          },
        );
      }).toList(),
    );
  }
}
