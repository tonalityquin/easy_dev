import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../models/capability.dart';
import '../../../../../../states/area/area_state.dart';
import 'user_role_type_section.dart'; // RoleType 정의

// ✅ AppCardPalette 정의 파일을 프로젝트 경로에 맞게 import 하세요.
// 예) import 'package:your_app/theme/app_card_palette.dart';
import '../../../../../../theme.dart';

class UserRoleDropdownSection extends StatelessWidget {
  /// 현재 선택된 역할(부모 상태)
  final RoleType selectedRole;

  /// 선택 변경 콜백(부모 상태 갱신)
  final ValueChanged<RoleType> onChanged;

  /// 1차 허용 목록(기본: 모든 역할)
  final List<RoleType> allowedRoles;

  /// 폼 검증기(선택)
  final String? Function(RoleType?)? validator;

  /// 자동 검증 모드(선택)
  final AutovalidateMode autovalidateMode;

  /// 라벨 텍스트(선택)
  final String label;

  /// 지역 capability 힌트 표시 여부
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

  // ⬇️ 역할별 "최소 요구 capability" 정의
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
      // 개발자는 정책상 어디서든 설정 가능하게(지역 기능 요구 X)
        return const <Capability>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;
    final dark = palette.serviceDark;
    final light = palette.serviceLight;

    // 현재 지역 capability 조회
    final CapSet areaCaps =
    context.select<AreaState, CapSet>((s) => s.capabilitiesOfCurrentArea);

    // 1차: 외부 allowedRoles → 2차: 지역 capability로 필터링
    final List<RoleType> effectiveRoles = allowedRoles
        .where((r) => Cap.supports(areaCaps, _requiredCapsForRole(r)))
        .toList(growable: false);

    // 드롭다운 value는 items에 반드시 포함되어야 함
    final RoleType safeValue = effectiveRoles.contains(selectedRole)
        ? selectedRole
        : (effectiveRoles.isNotEmpty ? effectiveRoles.first : selectedRole);

    // 부모 상태와 불일치 시 프레임 종료 후 동기화
    if (safeValue != selectedRole && effectiveRoles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(safeValue);
      });
    }

    // Dropdown 팝업 배경색
    final Color dropdownBgColor = colorScheme.surface;

    final String capsHuman = showAreaCapabilityHint ? Cap.human(areaCaps) : '';
    final String helper = showAreaCapabilityHint
        ? '현재 지역 기능: $capsHuman (해당 기능에 맞는 권한만 표시됩니다)'
        : '';

    // 선택 가능한 역할이 없다면 안내만 출력
    if (effectiveRoles.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          floatingLabelStyle: TextStyle(
            color: dark,
            fontWeight: FontWeight.w700,
          ),
          helperText: showAreaCapabilityHint ? helper : null,
          helperMaxLines: 2,
          isDense: true,
          contentPadding:
          const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          filled: true,
          fillColor: light.withOpacity(.06),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: light.withOpacity(.45)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: base, width: 1.2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          '현재 지역 기능으로 선택 가능한 권한이 없습니다.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      );
    }

    return DropdownButtonFormField<RoleType>(
      value: safeValue,
      isExpanded: true,
      autovalidateMode: autovalidateMode,
      validator: validator,
      iconEnabledColor: base,
      dropdownColor: dropdownBgColor,
      menuMaxHeight: 360,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelStyle: TextStyle(
          color: dark,
          fontWeight: FontWeight.w700,
        ),
        helperText: showAreaCapabilityHint ? helper : null,
        helperMaxLines: 2,
        filled: true,
        fillColor: light.withOpacity(.06),
        isDense: true,
        contentPadding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: light.withOpacity(.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: base, width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      items: effectiveRoles
          .map(
            (role) => DropdownMenuItem<RoleType>(
          value: role,
          child: Text(
            role.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: dark),
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
