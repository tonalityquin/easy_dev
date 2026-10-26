import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../app/models/capability.dart';
import '../../../../../dev/application/area_state.dart';
import 'user_role_type_section.dart';

class UserRoleDropdownSection extends StatelessWidget {
  final RoleType selectedRole;

  final ValueChanged<RoleType> onChanged;

  final List<RoleType> allowedRoles;

  final String? Function(RoleType?)? validator;

  final AutovalidateMode autovalidateMode;

  final String label;

  final bool showAreaCapabilityHint;

  const UserRoleDropdownSection({
    super.key,
    required this.selectedRole,
    required this.onChanged,
    this.allowedRoles = RoleType.values,
    this.validator,
    this.autovalidateMode = AutovalidateMode.disabled,
    this.label = '권한',
    this.showAreaCapabilityHint = true,
  }) : assert(allowedRoles.length > 0, 'allowedRoles는 비어 있을 수 없습니다.');

  CapSet _requiredCapsForRole(RoleType role) {
    switch (role) {
      case RoleType.adminBillMonthlyTablet:
        return const {Capability.bill, Capability.monthly, Capability.tablet};
      case RoleType.adminBillMonthly:
        return const {Capability.bill, Capability.monthly};

      case RoleType.adminBillTablet:
        return const {Capability.bill, Capability.tablet};
      case RoleType.adminBill:
        return const {Capability.bill};

      case RoleType.adminCommonTablet:
        return const {Capability.tablet};
      case RoleType.adminCommon:
        return const <Capability>{};

      case RoleType.userLocationMonthly:
        return const {Capability.monthly};
      case RoleType.userMonthly:
        return const {Capability.monthly};

      case RoleType.userCommon:
      case RoleType.fieldCommon:
        return const <Capability>{};

      case RoleType.dev:
      case RoleType.areaManager:
      case RoleType.divisionManager:
      case RoleType.superAdmin:
      case RoleType.specialist:
        return const <Capability>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final CapSet areaCaps =
        context.select<AreaState, CapSet>((s) => s.capabilitiesOfCurrentArea);

    final List<RoleType> effectiveRoles = <RoleType>{
      selectedRole,
      ...allowedRoles.where(
        (role) => role != RoleType.superAdmin && role != RoleType.dev &&
            Cap.supports(areaCaps, _requiredCapsForRole(role)),
      ),
    }.toList(growable: false);

    final RoleType safeValue = selectedRole;

    final Color dropdownBgColor = cs.surface;

    final decoration = InputDecoration(
      labelText: label,
      floatingLabelStyle: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: cs.surfaceVariant.withOpacity(.45),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.primary, width: 1.3),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );

    if (effectiveRoles.isEmpty) {
      return InputDecorator(
        decoration: decoration,
        child: Text(
          '현재 지역 기능으로 선택 가능한 권한이 없습니다.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant.withOpacity(.75)),
        ),
      );
    }

    return DropdownButtonFormField<RoleType>(
      value: safeValue,
      isExpanded: true,
      autovalidateMode: autovalidateMode,
      validator: validator,
      iconEnabledColor: cs.primary,
      dropdownColor: dropdownBgColor,
      menuMaxHeight: 360,
      decoration: decoration,
      items: effectiveRoles
          .map(
            (role) => DropdownMenuItem<RoleType>(
              value: role,
              child: Text(
                role.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface),
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
