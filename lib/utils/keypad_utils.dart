import 'package:flutter/material.dart';

/// KorKeypadUtils 클래스
/// 한글 키패드 레이아웃을 생성하는 유틸리티 클래스
class KorKeypadUtils {
  /// 키패드의 하위 레이아웃을 빌드합니다.
  /// @param keyRows: 키 값들의 리스트 (각 행을 나타냄)
  /// @param onKeyTap: 키가 눌렸을 때 호출되는 콜백 함수
  /// @return Widget: 키패드 레이아웃
  static Widget buildSubLayout(List<List<String>> keyRows, Function(String) onKeyTap) {
    return Column(
      mainAxisSize: MainAxisSize.min, // 레이아웃 크기 최소화
      children: keyRows.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly, // 키를 균등하게 배치
          children: row.map((key) {
            // 각 키에 대한 버튼 생성
            return buildKeyButton(key, key.isNotEmpty ? () => onKeyTap(key) : null);
          }).toList(),
        );
      }).toList(),
    );
  }

  /// 개별 키 버튼을 빌드합니다.
  /// @param key: 버튼에 표시될 텍스트
  /// @param onTap: 버튼을 눌렀을 때 호출되는 콜백 함수 (없을 경우 null)
  /// @return Widget: 버튼 위젯
  static Widget buildKeyButton(String key, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap, // 키가 눌렸을 때 동작
        child: Container(
          margin: const EdgeInsets.all(4.0), // 버튼 간격 설정
          padding: const EdgeInsets.all(16.0), // 버튼 내부 여백
          decoration: BoxDecoration(
            color: Colors.grey[200], // 버튼 배경색
            borderRadius: BorderRadius.circular(8.0), // 둥근 테두리
            border: Border.all(color: Colors.black, width: 2.0), // 검은색 테두리
          ),
          child: Center(
            child: Text(
              key, // 버튼 텍스트
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), // 텍스트 스타일
            ),
          ),
        ),
      ),
    );
  }
}
