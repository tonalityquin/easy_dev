import 'package:flutter/material.dart';
import 'user_role_type_section.dart';

class UserRoleDropdownSection extends StatelessWidget {
  /// 현재 선택된 역할
  final RoleType selectedRole;

  /// 선택 변경 콜백
  final ValueChanged<RoleType> onChanged;

  /// 선택 가능 역할 목록 (기본: 모든 역할)
  final List<RoleType> allowedRoles;

  /// 폼 검증기(선택)
  final String? Function(RoleType?)? validator;

  /// 자동 검증 모드(선택)
  final AutovalidateMode autovalidateMode;

  /// 라벨 텍스트(선택)
  final String label;

  const UserRoleDropdownSection({
    super.key,
    required this.selectedRole,
    required this.onChanged,
    this.allowedRoles = RoleType.values,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.label = '권한',
  }) : assert(allowedRoles.length > 0, 'allowedRoles는 비어 있을 수 없습니다.');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Dropdown의 배경색: MenuStyle의 MaterialStateProperty에서 실제 Color로 해석
    final Color dropdownBgColor =
        theme.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve(const <MaterialState>{}) ?? colorScheme.surface;

    // selectedRole이 allowedRoles에 없다면 안전한 폴백값 사용
    final RoleType safeValue = allowedRoles.contains(selectedRole) ? selectedRole : allowedRoles.first;

    return DropdownButtonFormField<RoleType>(
      value: safeValue,
      isExpanded: true,
      autovalidateMode: autovalidateMode,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
      menuMaxHeight: 360,
      dropdownColor: dropdownBgColor,
      // ✅ Color 로 전달
      iconEnabledColor: colorScheme.primary,
      items: allowedRoles
          .map(
            (role) => DropdownMenuItem<RoleType>(
              value: role,
              child: Text(
                role.label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),

      onChanged: (role) {
        if (role != null && role != selectedRole) {
          onChanged(role);
        }
      },
    );
  }
}
