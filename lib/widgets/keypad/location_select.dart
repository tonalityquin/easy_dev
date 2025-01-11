import 'package:flutter/material.dart';

/// **LocationSelect 위젯**
/// - 주차 구역 선택 모달을 구성하는 리스트뷰
/// - 사용자가 주차 구역을 선택할 수 있는 기능 제공
///
/// **매개변수**:
/// - [onSelect]: 선택한 옵션을 처리하는 콜백 함수 (필수)
class LocationSelect extends StatelessWidget {
  /// **옵션 리스트**
  /// - 사용자가 선택할 수 있는 주차 구역 이름들
  final List<String> options = const ['지역 A', '지역 B', '지역 C'];

  /// **선택 콜백 함수**
  /// - 사용자가 선택한 옵션 값을 전달
  final Function(String) onSelect;

  /// **LocationSelect 생성자**
  /// - [onSelect]: 선택된 옵션 값을 처리하는 콜백 (필수)
  const LocationSelect({
    super.key,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: options.map((String option) {
        return ListTile(
          /// **옵션 텍스트**
          /// - 주차 구역 이름을 표시
          title: Text(
            option,
            style: const TextStyle(fontSize: 16.0), // 텍스트 스타일 설정
          ),
          /// **옵션 클릭 이벤트**
          /// - 모달 닫기 및 선택된 값 전달
          onTap: () {
            Navigator.pop(context); // 모달 닫기
            onSelect(option); // 선택된 옵션 값을 콜백 함수에 전달
          },
        );
      }).toList(),
    );
  }
}
