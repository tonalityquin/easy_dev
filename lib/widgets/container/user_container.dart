import 'package:flutter/material.dart';

/// **UserContainer**
/// - 사용자 정보를 표시하는 컨테이너 위젯
/// - 사용자 이름, 전화번호, 이메일, 역할, 접근 권한 등을 표시
/// - 선택 여부에 따라 스타일 변경 및 탭 이벤트 처리
class UserContainer extends StatelessWidget {
  final String name; // 사용자 이름
  final String phone; // 전화번호
  final String email; // 이메일 주소
  final String role; // 사용자 역할
  final String access; // 접근 권한
  final bool isSelected; // 선택 여부
  final VoidCallback onTap; // 탭 이벤트 콜백

  const UserContainer({
    Key? key,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.access,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  /// **_buildTextRow**
  /// - 레이블과 값을 한 줄에 표시하는 텍스트 위젯 생성
  /// - [label]: 레이블 텍스트
  /// - [value]: 값 텍스트
  Widget _buildTextRow(String label, String value) {
    return Text('$label: $value'); // 텍스트 형식으로 반환
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // 탭 이벤트 처리
      child: Container(
        padding: const EdgeInsets.all(16), // 내부 여백
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white, // 선택 여부에 따른 배경색
          border: Border.all(color: Colors.grey), // 테두리 색상 및 스타일
          borderRadius: BorderRadius.circular(8), // 둥근 모서리 처리
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
          children: [
            _buildTextRow('Name', name), // 이름 표시
            _buildTextRow('Phone', phone), // 전화번호 표시
            _buildTextRow('Email', email), // 이메일 표시
            _buildTextRow('Role', role), // 역할 표시
            _buildTextRow('Access', access), // 접근 권한 표시
          ],
        ),
      ),
    );
  }
}
