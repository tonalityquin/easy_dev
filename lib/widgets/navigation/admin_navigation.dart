import 'package:flutter/material.dart';

/// **_AdminNavigation 위젯**
/// - PlateContainer와 연계된 추가 네비게이션 바
/// - 아이콘 클릭과 정렬 상태 변경 기능 제공
///
/// **매개변수**:
/// - [height]: 네비게이션 바의 세로 높이 (기본값: 40.0)
/// - [icons]: 표시할 아이콘 목록 (필수)
/// - [onSortToggle]: 정렬 상태 변경 시 호출되는 콜백 함수 (선택적)
class AdminNavigation extends StatefulWidget {
  /// **세로 높이**
  /// - 네비게이션 바의 높이를 조절
  final double height;

  /// **아이콘 목록**
  /// - 네비게이션 바에 표시될 아이콘들
  final List<IconData> icons;

  /// **정렬 상태 변경 콜백** (선택적)
  /// - 오름차순/내림차순 상태 변경 시 호출
  final Function(bool isAscending)? onSortToggle;

  /// **PlateNavigation 생성자**
  /// - [height]: 네비게이션 바의 세로 높이 (옵션, 기본값: 40.0)
  /// - [icons]: 네비게이션 바에 표시할 아이콘 목록 (필수)
  /// - [onSortToggle]: 정렬 상태 변경 콜백 (옵션)
  const AdminNavigation({
    super.key,
    this.height = 40.0,
    required this.icons,
    this.onSortToggle,
  });

  @override
  _AdminNavigation createState() => _AdminNavigation();
}

class _AdminNavigation extends State<AdminNavigation> {
  /// **정렬 상태**
  /// - `true`: 오름차순
  /// - `false`: 내림차순
  bool isAscending = true;

  /// **정렬 상태 토글**
  /// - 정렬 상태를 변경하고 콜백 함수 호출
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
        // **PlateNavigationBar**
        Container(
          color: Colors.white, // 배경색
          height: widget.height, // 세로 높이 설정
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround, // 아이콘 간격 균등 분배
            children: widget.icons.map((iconData) {
              return IconButton(
                /// **아이콘 렌더링**
                /// - 정렬 아이콘의 경우 상태에 따라 방향 반전
                icon: iconData == Icons.sort
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationX(isAscending ? 0 : 3.14159), // 아이콘 상하 반전
                        child: Icon(Icons.sort),
                      )
                    : Icon(iconData),
                // 기본 아이콘
                /// **아이콘 클릭 이벤트**
                /// - 정렬 아이콘 클릭 시 상태 토글
                /// - 다른 아이콘 클릭 시 디버그 출력
                onPressed: () {
                  if (iconData == Icons.sort) {
                    toggleSortOrder(); // 정렬 상태 변경
                  } else {
                    print("아이콘 클릭: $iconData");
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
