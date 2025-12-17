import 'package:flutter/material.dart';
import 'tablet_role_type.dart';

/// 서비스 로그인 카드와 같은 계열 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

class TabletRoleDropdownSection extends StatelessWidget {
  final TabletRoleType selectedRole;
  final ValueChanged<TabletRoleType> onChanged;

  final List<TabletRoleType> allowedRoles;
  final String? Function(TabletRoleType?)? validator;
  final AutovalidateMode autovalidateMode;
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
    return theme.dropdownMenuTheme.menuStyle?.backgroundColor
        ?.resolve(const <MaterialState>{}) ??
        cs.surface;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final TabletRoleType safeValue =
    allowedRoles.contains(selectedRole) ? selectedRole : allowedRoles.first;

    return DropdownButtonFormField<TabletRoleType>(
      value: safeValue,
      isExpanded: true,
      autovalidateMode: autovalidateMode,
      validator: validator,
      dropdownColor: _resolveDropdownBg(context),
      menuMaxHeight: 360,
      iconEnabledColor: _SvcColors.base,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelStyle: const TextStyle(
          color: _SvcColors.dark,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: _SvcColors.light.withOpacity(.06),
        isDense: true,
        contentPadding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _SvcColors.light.withOpacity(.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _SvcColors.base, width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      items: allowedRoles
          .map(
            (role) => DropdownMenuItem<TabletRoleType>(
          value: role,
          child: Text(
            role.label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _SvcColors.dark,
              fontWeight: FontWeight.w600,
            ),
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
