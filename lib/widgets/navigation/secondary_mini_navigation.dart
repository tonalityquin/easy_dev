import 'package:flutter/material.dart';

/// **SecondaryMiniNavigation**
/// - 하단 미니 내비게이션 위젯
/// - 정렬 토글 및 아이콘 클릭 이벤트 처리
/// - 배경색과 아이콘 크기 설정 가능
class SecondaryMiniNavigation extends StatefulWidget {
  final double height; // 네비게이션 높이
  final List<IconData> icons; // 표시할 아이콘 리스트
  final Function(bool isAscending)? onSortToggle; // 정렬 상태 변경 콜백
  final void Function(int index)? onIconTapped; // 아이콘 클릭 콜백
  final Color? backgroundColor; // 배경색
  final double iconSize; // 아이콘 크기

  const SecondaryMiniNavigation({
    super.key,
    this.height = 40.0,
    required this.icons,
    this.onSortToggle,
    this.onIconTapped,
    this.backgroundColor = Colors.white,
    this.iconSize = 24.0,
  });

  @override
  _SecondaryMiniNavigation createState() => _SecondaryMiniNavigation();
}

class _SecondaryMiniNavigation extends State<SecondaryMiniNavigation> {
  bool isAscending = true; // 정렬 상태

  /// **정렬 상태 토글**
  /// - 정렬 상태를 변경하고 콜백 호출
  void toggleSortOrder() {
    setState(() {
      isAscending = !isAscending; // 정렬 상태 변경
    });
    widget.onSortToggle?.call(isAscending); // 콜백 호출
  }

  /// **아이콘 생성**
  /// - 정렬 아이콘을 포함한 일반 아이콘 생성
  Widget _buildIcon(IconData iconData, int index) {
    final isSortIcon = iconData == Icons.sort; // 정렬 아이콘 여부 확인

    return IconButton(
      icon: isSortIcon
          ? Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationX(isAscending ? 0 : 3.14159), // 정렬 방향 회전
        child: Icon(Icons.sort),
      )
          : Icon(iconData), // 일반 아이콘
      onPressed: () {
        if (isSortIcon) {
          toggleSortOrder(); // 정렬 상태 토글
        } else {
          widget.onIconTapped?.call(index); // 아이콘 클릭 콜백 호출
        }
      },
      padding: EdgeInsets.zero, // 아이콘 간격 최소화
      constraints: const BoxConstraints(), // 기본 크기 제한
      iconSize: widget.iconSize, // 아이콘 크기 설정
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, // 최소 크기로 설정
      children: [
        Container(
          color: widget.backgroundColor, // 배경색 설정
          height: widget.height, // 네비게이션 높이 설정
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround, // 아이콘 간격 균등 배치
            children: widget.icons.asMap().entries.map((entry) {
              return _buildIcon(entry.value, entry.key); // 아이콘 생성
            }).toList(),
          ),
        ),
      ],
    );
  }
}
