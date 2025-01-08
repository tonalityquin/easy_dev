import 'package:flutter/material.dart';

/// PlateNavigationBar 위젯
/// PlateContainer와 연계될 추가 네비게이션 바
class PlateNavigation extends StatefulWidget {
  final double height; // 세로 폭 조절을 위한 속성
  final List<IconData> icons; // 동적으로 설정할 아이콘 목록
  final Function(bool isAscending)? onSortToggle; // 정렬 상태 변경 콜백 (선택적)

  const PlateNavigation({
    super.key,
    this.height = 40.0, // 기본 세로 폭 설정
    required this.icons, // 아이콘 목록을 필수로 받음
    this.onSortToggle, // 정렬 상태 변경 콜백
  });

  @override
  _PlateNavigationState createState() => _PlateNavigationState();
}

class _PlateNavigationState extends State<PlateNavigation> {
  bool isAscending = true; // 오름차순/내림차순 상태(긴 게 위에 있으면 오름, 긴 게 아래에 있으면 내림)

  void toggleSortOrder() {
    setState(() {
      isAscending = !isAscending; // 정렬 상태 토글
    });
    if (widget.onSortToggle != null) {
      widget.onSortToggle!(isAscending); // 정렬 상태 변경 콜백 호출
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PlateNavigationBar
        Container(
          color: Colors.blue[200], // PlateNavigationBar 배경색
          height: widget.height, // 세로 폭 설정
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround, // 아이콘 수평 배치
            children: widget.icons.map((iconData) {
              return IconButton(
                icon: iconData == Icons.sort
                    ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationX(isAscending ? 0 : 3.14159),
                  child: Icon(Icons.sort),
                ) // 아이콘 상하 반전
                    : Icon(iconData),
                onPressed: () {
                  // 차순 아이콘 클릭 시 정렬 상태 토글
                  if (iconData == Icons.sort) {
                    toggleSortOrder();
                  } else {
                    print("아이콘 클릭: $iconData");
                  }
                },
                padding: EdgeInsets.zero,
                // 기본 패딩 제거
                constraints: const BoxConstraints(),
                // 기본 크기 제한 제거
                iconSize: widget.height * 0.6, // 아이콘 크기를 컨테이너 높이에 맞춤
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
