import 'package:flutter/material.dart';

/// **MiniNavigation**
/// - 작고 간결한 하단 네비게이션 위젯
/// - 정렬 상태를 관리하며 아이콘 클릭 이벤트를 처리
class MiniNavigation extends StatefulWidget {
  final double height; // 네비게이션 높이
  final List<IconData> icons; // 표시할 아이콘 리스트
  final Function(bool isAscending)? onSortToggle; // 정렬 상태 변경 콜백
  final void Function(int index)? onIconTapped; // 아이콘 클릭 콜백

  const MiniNavigation({
    super.key,
    this.height = 40.0,
    required this.icons,
    this.onSortToggle,
    this.onIconTapped,
  });

  @override
  _MiniNavigationState createState() => _MiniNavigationState();
}

class _MiniNavigationState extends State<MiniNavigation> {
  bool isAscending = true; // 정렬 상태

  /// **정렬 상태 토글**
  /// - `isAscending` 값을 변경하고 콜백 호출
  void toggleSortOrder() {
    setState(() {
      isAscending = !isAscending; // 정렬 상태 토글
    });
    widget.onSortToggle?.call(isAscending); // 콜백 호출
  }

  /// **아이콘 클릭 핸들러**
  /// - 정렬 아이콘 클릭 시 정렬 상태 변경
  /// - 다른 아이콘 클릭 시 해당 인덱스 전달
  void _handleIconTap(int index, IconData iconData) {
    if (iconData == Icons.sort) {
      toggleSortOrder(); // 정렬 상태 변경
    } else {
      widget.onIconTapped?.call(index); // 콜백 호출
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, // 네비게이션 높이 최소화
      children: [
        Container(
          color: Colors.blue[200], // 배경색
          height: widget.height, // 지정된 높이 설정
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround, // 아이콘 간격 균등 배치
            children: widget.icons.asMap().entries.map((entry) {
              final index = entry.key; // 아이콘 인덱스
              final iconData = entry.value; // 아이콘 데이터

              return IconButton(
                icon: iconData == Icons.sort
                    ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationX(isAscending ? 0 : 3.14159), // 정렬 방향 회전
                  child: Icon(iconData),
                )
                    : Icon(iconData), // 기본 아이콘
                onPressed: () => _handleIconTap(index, iconData), // 클릭 이벤트
                padding: EdgeInsets.zero, // 아이콘 패딩 제거
                constraints: const BoxConstraints(), // 기본 크기 제한
                iconSize: widget.height * 0.6, // 아이콘 크기 조정
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
