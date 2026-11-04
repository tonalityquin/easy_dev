import 'package:flutter/material.dart';

import 'user_role_type_section.dart';

class UserRoleDropdownSection extends StatelessWidget {
  const UserRoleDropdownSection({
    super.key,
    required this.selectedRole,
    required this.onChanged,
    this.allowedRoles = RoleType.values,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.label = '권한',
    this.showAreaCapabilityHint = false,
  });

  final RoleType selectedRole;
  final ValueChanged<RoleType> onChanged;
  final List<RoleType> allowedRoles;
  final String? Function(RoleType?)? validator;
  final AutovalidateMode autovalidateMode;
  final String label;
  final bool showAreaCapabilityHint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectedExists = allowedRoles.contains(selectedRole);
    final roles = selectedExists
        ? allowedRoles
        : <RoleType>[selectedRole, ...allowedRoles];
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: DropdownButtonFormField<RoleType>(
        value: selectedRole,
        isExpanded: true,
        autovalidateMode: autovalidateMode,
        validator: validator,
        iconEnabledColor: cs.primary,
        dropdownColor: cs.surface,
        menuMaxHeight: 360,
        decoration: InputDecoration(
          labelText: label,
          floatingLabelStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
          filled: true,
          fillColor: cs.surfaceVariant.withOpacity(0.45),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.primary, width: 1.3),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: roles.map((role) => DropdownMenuItem<RoleType>(
          value: role,
          child: AnimatedDefaultTextStyle(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            style: TextStyle(color: cs.onSurface, fontWeight: role == selectedRole ? FontWeight.w700 : FontWeight.w400),
            child: Text(role.label, overflow: TextOverflow.ellipsis),
          ),
        )).toList(growable: false),
        onChanged: (role) {
          if (role != null && role != selectedRole) onChanged(role);
        },
      ),
    );
  }
}
