import 'package:flutter/material.dart';
import 'package:easydev/widgets/keypad/mini_num_keypad.dart'; // NumKeypad 경로

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
  bool isKeypadVisible = false; // num_keypad 활성화 상태
  bool isAscending = true; // 오름차순/내림차순 상태(긴 게 위에 있으면 오름, 긴 게 아래에 있으면 내림)
  final TextEditingController _controller = TextEditingController(); // 키패드 입력값

  void toggleKeypadVisibility() {
    setState(() {
      isKeypadVisible = !isKeypadVisible; // 키패드 표시 상태 토글
    });
  }

  void hideKeypad() {
    if (isKeypadVisible) {
      setState(() {
        isKeypadVisible = false; // 키패드 비활성화
      });
    }
  }

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
    return WillPopScope(
      onWillPop: () async {
        if (isKeypadVisible) {
          hideKeypad(); // 키패드 비활성화
          return false; // 뒤로가기 버튼 이벤트를 소비
        }
        return true; // 뒤로가기 버튼 동작 허용
      },
      child: GestureDetector(
        // 다른 공간을 누르면 키패드 비활성화
        onTap: hideKeypad,
        child: Column(
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
                      }
                      // 돋보기 아이콘인 경우 키패드 활성화 토글
                      else if (iconData == Icons.search) {
                        toggleKeypadVisibility();
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
            // NumKeypad 표시
            if (isKeypadVisible)
              MiniNumKeypad(
                controller: _controller,
                maxLength: 5,
                // 최대 입력 길이 설정
                onComplete: () {
                  print('입력이 완료되었습니다: ${_controller.text}');
                },
                onReset: () {
                  _controller.clear();
                  print('입력이 리셋되었습니다.');
                },
                backgroundColor: Colors.grey[300],
              ),
          ],
        ),
      ),
    );
  }
}
