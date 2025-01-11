import 'package:flutter/material.dart';

/// **KorKeypadUtils 클래스**
/// - 한글 키패드 레이아웃을 생성하는 유틸리티 클래스
class KorKeypadUtils {
  /// **키패드 하위 레이아웃 빌드**
  /// - [keyRows]: 키 값들의 리스트 (각 행을 나타냄)
  /// - [onKeyTap]: 키가 눌렸을 때 호출되는 콜백 함수
  /// - 반환값: 키패드 레이아웃 위젯
  static Widget buildSubLayout(List<List<String>> keyRows, Function(String) onKeyTap) {
    return Column(
      mainAxisSize: MainAxisSize.min, // 레이아웃 크기를 최소화
      children: keyRows.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 각 행의 키를 균등하게 배치
          children: row.map((key) {
            // 각 키에 대한 버튼 생성
            return buildKeyButton(
              key,
              key.isNotEmpty ? () => onKeyTap(key) : null, // 빈 키는 동작하지 않음
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  /// **개별 키 버튼 빌드**
  /// - [key]: 버튼에 표시될 텍스트
  /// - [onTap]: 버튼이 눌렸을 때 호출되는 콜백 함수 (없을 경우 null)
  /// - 반환값: 버튼 위젯
  static Widget buildKeyButton(String key, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap, // 버튼이 눌렸을 때의 동작
        child: Container(
          margin: const EdgeInsets.all(4.0), // 버튼 간격 설정
          padding: const EdgeInsets.all(16.0), // 버튼 내부 여백
          decoration: BoxDecoration(
            color: Colors.grey[200], // 버튼 배경색
            borderRadius: BorderRadius.circular(8.0), // 둥근 테두리
            border: Border.all(color: Colors.black, width: 2.0), // 테두리 스타일
          ),
          child: Center(
            child: Text(
              key, // 버튼에 표시될 텍스트
              style: const TextStyle(
                fontSize: 24, // 텍스트 크기
                fontWeight: FontWeight.bold, // 텍스트 굵기
              ),
            ),
          ),
        ),
      ),
    );
  }
}
