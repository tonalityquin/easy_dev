import 'package:flutter/material.dart';

class SecondaryMiniNavigation extends StatefulWidget {
  final double height;

  final List<IconData> icons;

  final Function(bool isAscending)? onSortToggle;

  final void Function(int index)? onIconTapped;

  const SecondaryMiniNavigation({
    super.key,
    this.height = 40.0,
    required this.icons,
    this.onSortToggle,
    this.onIconTapped,
  });

  @override
  _SecondaryMiniNavigation createState() => _SecondaryMiniNavigation();
}

class _SecondaryMiniNavigation extends State<SecondaryMiniNavigation> {
  bool isAscending = true;

  void toggleSortOrder() {
    setState(() {
      isAscending = !isAscending; // 상태 변경
    });
    if (widget.onSortToggle != null) {
      widget.onSortToggle!(isAscending); // 정렬 상태 변경 콜백 호출
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, // 최소 높이로 조절
      children: [
        Container(
          color: Colors.white, // 배경색
          height: widget.height, // 세로 높이 설정
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround, // 아이콘 간격 균등 분배
            children: widget.icons.asMap().entries.map((entry) {
              final index = entry.key;
              final iconData = entry.value;

              return IconButton(
                icon: iconData == Icons.sort
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationX(isAscending ? 0 : 3.14159), // 아이콘 상하 반전
                        child: Icon(Icons.sort),
                      )
                    : Icon(iconData),
                // 기본 아이콘
                onPressed: () {
                  if (iconData == Icons.sort) {
                    toggleSortOrder(); // 정렬 상태 변경
                  } else {
                    if (widget.onIconTapped != null) {
                      widget.onIconTapped!(index); // 아이콘 클릭 콜백 호출
                    }
                  }
                },
                padding: EdgeInsets.zero,
                // 기본 패딩 제거
                constraints: const BoxConstraints(),
                // 기본 크기 제한 제거
                iconSize: widget.height * 0.6, // 아이콘 크기 조정
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
