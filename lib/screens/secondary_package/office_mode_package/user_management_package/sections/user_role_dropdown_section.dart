// lib/widgets/.../user_role_dropdown_section.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/capability.dart';
import '../../../../../states/area/area_state.dart';
import 'user_role_type_section.dart'; // RoleType 정의

class UserRoleDropdownSection extends StatelessWidget {
  /// 현재 선택된 역할(부모 상태)
  final RoleType selectedRole;

  /// 선택 변경 콜백(부모 상태 갱신)
  final ValueChanged<RoleType> onChanged;

  /// 1차 허용 목록(기본: 모든 역할) — 예: 관리자 화면이면 user 계열 제외 등
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

  // ⬇️ 역할별 "최소 요구 capability" 정의
  // - tablet이 붙은 관리자 역할은 tablet 필요
  // - bill이 포함된 관리자 역할은 bill 필요
  // - monthly가 포함된 역할은 monthly 필요
  // - user*, fieldCommon, adminCommon, dev(개발)는 area capability 요구 없음(역할 권한의 성격)
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

    // 현재 지역 capability 조회
    final CapSet areaCaps = context.select<AreaState, CapSet>((s) => s.capabilitiesOfCurrentArea);

    // 1차: 외부 allowedRoles
    // 2차: 지역 capability로 필터링
    final List<RoleType> effectiveRoles =
        allowedRoles.where((r) => Cap.supports(areaCaps, _requiredCapsForRole(r))).toList(growable: false);

    // 드롭다운 value는 items에 반드시 포함되어야 함
    // selectedRole이 필터 후 목록에 없으면 안전한 폴백을 사용
    final RoleType safeValue = effectiveRoles.contains(selectedRole)
        ? selectedRole
        : (effectiveRoles.isNotEmpty ? effectiveRoles.first : selectedRole);

    // ⚠️ 부모 상태(selectedRole)와 드롭다운 value 불일치 시, 프레임 종료 후 동기화
    // (드롭다운은 safeValue를 보여주지만, 부모 상태는 이전 값을 유지할 수 있으므로)
    if (safeValue != selectedRole && effectiveRoles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(safeValue);
      });
    }

    // Dropdown의 배경색: MenuStyle의 MaterialStateProperty에서 실제 Color로 해석
    final Color dropdownBgColor =
        theme.dropdownMenuTheme.menuStyle?.backgroundColor?.resolve(const <MaterialState>{}) ?? colorScheme.surface;

    // 선택 가능한 역할이 하나도 없다면(예외적) 안내만 출력
    if (effectiveRoles.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
        child: Text(
          '현재 지역 기능(${Cap.human(areaCaps)})으로 선택 가능한 권한이 없습니다.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      );
    }

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
      iconEnabledColor: colorScheme.primary,
      items: effectiveRoles
          .map(
            (role) => DropdownMenuItem<RoleType>(
              value: role,
              child: Text(role.label, overflow: TextOverflow.ellipsis),
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
