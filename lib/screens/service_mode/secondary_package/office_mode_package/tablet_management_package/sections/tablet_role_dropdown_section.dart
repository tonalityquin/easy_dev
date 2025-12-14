// lib/screens/secondary_package/office_mode_package/tablet_management_package/sections/tablet_role_dropdown_section.dart
import 'package:flutter/material.dart';
import 'tablet_role_type.dart';

/// 서비스 로그인 카드와 같은 계열 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1); // Deep Blue
}

class TabletRoleDropdownSection extends StatelessWidget {
  /// 현재 선택된 역할
  final TabletRoleType selectedRole;

  /// 선택 변경 콜백
  final ValueChanged<TabletRoleType> onChanged;

  /// 선택 가능 역할 목록 (기본: 모든 역할)
  final List<TabletRoleType> allowedRoles;

  /// 폼 검증기(선택)
  final String? Function(TabletRoleType?)? validator;

  /// 자동 검증 모드(선택)
  final AutovalidateMode autovalidateMode;

  /// 라벨 텍스트(선택)
  final String label;

  const TabletRoleDropdownSection({
    super.key,
    required this.selectedRole,
    required this.onChanged,
    this.allowedRoles = TabletRoleType.values,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.label = '권한',
  }) : assert(allowedRoles.length > 0, 'allowedRoles는 비어 있을 수 없습니다.');

  Color _resolveDropdownBg(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return theme.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve(const <MaterialState>{}) ??
        cs.surface;
  }

  @override
  Widget build(BuildContext context) {
    const base = _SvcColors.base;
    final theme = Theme.of(context);

    // selectedRole이 allowedRoles에 없다면 안전한 폴백값 사용
    final TabletRoleType safeValue =
    allowedRoles.contains(selectedRole) ? selectedRole : allowedRoles.first;

    return DropdownButtonFormField<TabletRoleType>(
      value: safeValue,
      isExpanded: true,
      autovalidateMode: autovalidateMode,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: base),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: base.withOpacity(.28)),
          borderRadius: BorderRadius.circular(8),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      ),
      menuMaxHeight: 360,
      dropdownColor: _resolveDropdownBg(context),
      iconEnabledColor: base,
      items: allowedRoles
          .map(
            (role) => DropdownMenuItem<TabletRoleType>(
          value: role,
          child: Text(
            role.label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
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
