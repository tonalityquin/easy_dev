import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/secondary_role_state.dart';
import '../../states/user_state.dart';

/// **SecondaryRoleNavigation 위젯**
/// - 모드 선택 및 전환 기능을 제공하는 AppBar
/// - 사용자의 Role에 따라 드롭다운 활성/비활성 상태를 제어
class SecondaryRoleNavigation extends StatelessWidget implements PreferredSizeWidget {
  /// **AppBar 높이**
  final double height;

  /// **생성자**
  const SecondaryRoleNavigation({super.key, this.height = kToolbarHeight});

  /// **AppBar 크기 반환**
  @override
  Size get preferredSize => Size.fromHeight(height);

  /// **UI 구성**
  @override
  Widget build(BuildContext context) {
    final manageState = context.watch<SecondaryRoleState>();
    final userState = context.watch<UserState>();

    final userRole = userState.role.toLowerCase(); // role 값을 소문자로 변환
    final selectMode = userRole == 'user' ? 'Field Mode' : manageState.currentStatus; // User는 Field Mode 고정

    if (userRole == 'user' && manageState.currentStatus != 'Field Mode') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        manageState.updateManage('Field Mode'); // 강제로 Field Mode로 설정
      });
    }

    return AppBar(
      title: IgnorePointer(
        ignoring: userRole == 'User', // User Role인 경우 선택 비활성화
        child: DropdownButton<String>(
          value: selectMode,
          // 현재 선택된 모드
          underline: Container(),
          // 드롭다운 아래 선 제거
          dropdownColor: Colors.white,
          // 드롭다운 메뉴 배경색
          items: manageState.availableStatus.map((mode) {
            return DropdownMenuItem<String>(
              value: mode, // 각 모드의 값
              child: Text(
                mode, // 모드 이름 표시
                style: TextStyle(
                  color: userRole == 'User' ? Colors.black : Colors.black, // User Role이면 회색 처리
                ),
              ),
            );
          }).toList(),
          onChanged: userRole == 'User'
              ? null // Role이 User면 드롭다운 변경 불가
              : (newManage) {
                  if (newManage != null) {
                    manageState.updateManage(newManage); // 모드 상태 업데이트
                  }
                },
        ),
      ),
      centerTitle: true, // 제목 가운데 정렬
      backgroundColor: Colors.green, // AppBar 배경색
    );
  }
}
