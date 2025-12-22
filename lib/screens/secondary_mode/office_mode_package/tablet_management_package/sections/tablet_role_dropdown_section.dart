import 'package:flutter/material.dart';
import 'tablet_role_type.dart';

// ✅ AppCardPalette 정의가 있는 파일을 프로젝트 경로에 맞게 import 하세요.
// 예) import 'package:your_app/theme/app_theme.dart';
// 예) import 'package:your_app/theme/app_card_palette.dart';
import '../../../../../../theme.dart';

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
    final cs = theme.colorScheme;

    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;
    final dark = palette.serviceDark;
    final light = palette.serviceLight;

    final TabletRoleType safeValue =
    allowedRoles.contains(selectedRole) ? selectedRole : allowedRoles.first;

    return DropdownButtonFormField<TabletRoleType>(
      value: safeValue,
      isExpanded: true,
      autovalidateMode: autovalidateMode,
      validator: validator,
      dropdownColor: _resolveDropdownBg(context),
      menuMaxHeight: 360,
      iconEnabledColor: base,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelStyle: TextStyle(
          color: dark,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: light.withOpacity(.06),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: light.withOpacity(.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: base, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.error.withOpacity(.85)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.error, width: 1.3),
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
              color: dark,
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
