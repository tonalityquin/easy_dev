import 'package:flutter/material.dart';

import '../../../../../../app/models/account_role.dart';
export '../../../../../../app/models/account_role.dart';

extension UserRolePresentation on RoleType {
  Color badgeBackground(ColorScheme cs) {
    if (isHeadOffice) return cs.tertiaryContainer;
    if (canManageAccounts) return cs.primaryContainer;
    if (this == RoleType.branchProStaff) return cs.secondaryContainer;
    return cs.surfaceVariant;
  }

  Color badgeForeground(ColorScheme cs) {
    if (isHeadOffice) return cs.onTertiaryContainer;
    if (canManageAccounts) return cs.onPrimaryContainer;
    if (this == RoleType.branchProStaff) return cs.onSecondaryContainer;
    return cs.onSurfaceVariant;
  }
}
