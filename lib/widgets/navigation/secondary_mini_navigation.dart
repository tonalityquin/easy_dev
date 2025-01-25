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
  bool isAscending = true;

  /// 정렬 상태를 변경하고 콜백 호출
  void toggleSortOrder() {
    setState(() {
      isAscending = !isAscending;
    });
    widget.onSortToggle?.call(isAscending);
  }

  /// 정렬 아이콘 포함 일반 아이콘 생성
  Widget _buildIcon(IconData iconData, int index) {
    final isSortIcon = iconData == Icons.sort;

    return IconButton(
      icon: isSortIcon
          ? Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationX(isAscending ? 0 : 3.14159),
        child: Icon(Icons.sort),
      )
          : Icon(iconData),
      onPressed: () {
        if (isSortIcon) {
          toggleSortOrder();
        } else {
          widget.onIconTapped?.call(index);
        }
      },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      iconSize: widget.iconSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: widget.backgroundColor,
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: widget.icons.asMap().entries.map((entry) {
              return _buildIcon(entry.value, entry.key);
            }).toList(),
          ),
        ),
      ],
    );
  }
}
