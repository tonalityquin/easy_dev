import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_rail.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/account/domain/models/tablet/tablet_model.dart';
import '../../../features/account/domain/models/user/user_model.dart';
import '../../../features/account/pages/tablet/sheets/tablet_setting.dart';
import '../../../features/account/pages/user/sheets/user_setting.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/payment/pages/sheets/bill_bottom_sheet.dart';
import '../../../features/monthly/page/sheets/monthly_payment_setting.dart';
import '../../../features/monthly/page/sheets/monthly_plate_setting.dart';
import '../../../features/sector/applications/sector_state.dart';
import '../../../features/sector/domain/models/sector_model.dart';
import '../../../features/sector/pages/sheets/sector_setting.dart';
import '../../../features/location/applications/location_state.dart';
import '../../../features/location/domain/models/location_model.dart';
import '../../../features/location/pages/location_management.dart';
import '../../../features/location/pages/sheets/location_child_setting.dart';
import '../../../features/location/pages/sheets/location_parent_setting.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../application/secondary_account_workspace_state.dart';
import '../application/secondary_bill_workspace_state.dart';
import '../application/secondary_info.dart';
import '../application/secondary_location_workspace_state.dart';
import '../application/secondary_monthly_workspace_state.dart';
import '../application/secondary_sector_workspace_state.dart';
import '../application/secondary_tablet_workspace_state.dart';
import '../application/secondary_state.dart';
import '../widgets/ops_console_widgets.dart';
import '../widgets/secondary_debug_scope.dart';

enum SecondaryDockRequest { open }

Future<T?> showSecondarySideDock<T>({
  required BuildContext context,
  String barrierLabel = '운영 관리',
  bool useRootNavigator = false,
  Section initialSection = Section.local,
}) {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[SecondarySideDock] route_push label=$barrierLabel initial=${initialSection.name} reduceMotion=$reduceMotion motion=common_operations',
  );
  return showOperationsRightSideDock<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierLabel: barrierLabel,
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: true,
    builder: (_) => SecondarySideDock(initialSection: initialSection),
  );
}

class SecondarySideDock extends StatefulWidget {
  const SecondarySideDock({
    super.key,
    this.initialSection = Section.local,
  });

  final Section initialSection;

  @override
  State<SecondarySideDock> createState() => _SecondarySideDockState();
}

class _SecondarySideDockState extends State<SecondarySideDock> {
  static const List<_SecondaryRailItem> _primaryItems = <_SecondaryRailItem>[
    _SecondaryRailItem(
      section: Section.local,
      label: '설정',
      icon: Icons.tune_rounded,
    ),
    _SecondaryRailItem(
      section: Section.user,
      label: '계정',
      icon: Icons.manage_accounts_rounded,
    ),
    _SecondaryRailItem(
      section: Section.sector,
      label: '섹터',
      icon: Icons.hub_rounded,
    ),
    _SecondaryRailItem(
      section: Section.location,
      label: '구역',
      icon: Icons.location_on_rounded,
    ),
    _SecondaryRailItem(
      section: Section.tablet,
      label: '태블릿',
      icon: Icons.tablet_mac_rounded,
    ),
    _SecondaryRailItem(
      section: Section.monthly,
      label: '정기',
      icon: Icons.local_parking_rounded,
    ),
    _SecondaryRailItem(
      section: Section.bill,
      label: '정산',
      icon: Icons.receipt_long_rounded,
    ),
  ];

  static const List<_SecondaryRailItem> _bottomItems = <_SecondaryRailItem>[
    _SecondaryRailItem(
      section: Section.backend,
      label: '백엔드',
      icon: Icons.settings_ethernet_rounded,
    ),
    _SecondaryRailItem(
      section: Section.area,
      label: '지역 추가',
      displayLabel: '지역',
      icon: Icons.add_location_alt_rounded,
    ),
  ];

  final _SecondaryDockDebugLog _debugLog = _SecondaryDockDebugLog();
  late final SecondaryAccountWorkspaceState _accountWorkspace;
  late final SecondaryTabletWorkspaceState _tabletWorkspace;
  late final SecondaryBillWorkspaceState _billWorkspace;
  late final SecondaryMonthlyWorkspaceState _monthlyWorkspace;
  late final SecondarySectorWorkspaceState _sectorWorkspace;
  late final SecondaryLocationWorkspaceState _locationWorkspace;
  late Section _selectedSection;
  bool _devModeEnabled = false;
  bool _fallbackScheduled = false;
  String? _lastArea;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
    _accountWorkspace = SecondaryAccountWorkspaceState(onDebug: _debugLog.log);
    _tabletWorkspace = SecondaryTabletWorkspaceState(onDebug: _debugLog.log);
    _billWorkspace = SecondaryBillWorkspaceState(onDebug: _debugLog.log);
    _monthlyWorkspace = SecondaryMonthlyWorkspaceState(onDebug: _debugLog.log);
    _sectorWorkspace = SecondarySectorWorkspaceState(onDebug: _debugLog.log);
    _locationWorkspace = SecondaryLocationWorkspaceState(onDebug: _debugLog.log);
    _debugLog.log('mounted selected=${_selectedSection.name} initial=${widget.initialSection.name}');
    DevAuth.devModeEnabled.addListener(_handleDevModeNotifier);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final state = context.read<SecondaryState>();
      await state.refreshDeveloperLogin();
      final enabled = await DevAuth.isDevModeEnabled();
      if (!mounted) return;
      setState(() => _devModeEnabled = enabled);
      _debugLog.log(
        'developer_mode_resolved enabled=$enabled devLoggedIn=${state.devLoggedIn}',
      );
      _logAccessSnapshot(state);
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDevModeNotifier);
    _debugLog.log('disposed selected=${_selectedSection.name}');
    _accountWorkspace.dispose();
    _tabletWorkspace.dispose();
    _billWorkspace.dispose();
    _monthlyWorkspace.dispose();
    _sectorWorkspace.dispose();
    _locationWorkspace.dispose();
    super.dispose();
  }

  void _handleDevModeNotifier() {
    if (!mounted) return;
    final enabled = DevAuth.devModeEnabled.value;
    if (_devModeEnabled == enabled) return;
    setState(() => _devModeEnabled = enabled);
    _debugLog.log('developer_mode_changed enabled=$enabled');
  }

  void _logAccessSnapshot(SecondaryState state) {
    final access = <String>[];
    for (final item in <_SecondaryRailItem>[..._primaryItems, ..._bottomItems]) {
      final allowed = state.canAccess(item.section);
      final reason = allowed ? 'allowed' : state.accessDebugReason(item.section);
      access.add('${item.section.name}:$allowed:$reason');
    }
    _debugLog.log(
      'access_snapshot role=${state.role.name} devLoggedIn=${state.devLoggedIn} ${access.join('|')}',
    );
  }

  Section _effectiveSection(SecondaryState state) {
    if (state.canAccess(_selectedSection)) return _selectedSection;
    for (final item in <_SecondaryRailItem>[..._primaryItems, ..._bottomItems]) {
      if (state.canAccess(item.section)) {
        if (_selectedSection != item.section && !_fallbackScheduled) {
          _fallbackScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _fallbackScheduled = false;
            if (!mounted) return;
            _accountWorkspace.reset(source: 'selection_fallback');
            _tabletWorkspace.reset(source: 'selection_fallback');
            _billWorkspace.reset(source: 'selection_fallback');
            _monthlyWorkspace.reset(source: 'selection_fallback');
            _sectorWorkspace.reset(source: 'selection_fallback');
            _locationWorkspace.reset(source: 'selection_fallback');
            setState(() => _selectedSection = item.section);
            _debugLog.log(
              'selection_fallback target=${item.section.name}',
            );
          });
        }
        return item.section;
      }
    }
    return Section.local;
  }

  Future<void> _selectSection(SecondaryState state, Section section) async {
    final allowed = state.canAccess(section);
    final debugReason = state.accessDebugReason(section);
    _debugLog.log(
      'rail_tap section=${section.name} allowed=$allowed current=${_selectedSection.name} reason=$debugReason',
    );
    if (!allowed) {
      final reason = state.disabledReason(section);
      _debugLog.log(
        'rail_blocked section=${section.name} reason=$reason debug=$debugReason',
      );
      await HapticFeedback.lightImpact();
      if (!mounted) return;
      await StatusDialog.showFailure(
        context,
        title: '${_sectionDisplayTitle(section)} 사용 불가',
        description: reason,
        copyText: _devModeEnabled ? _debugLog.debugPrintCode : null,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: _devModeEnabled
            ? const Duration(seconds: 60)
            : const Duration(seconds: 4),
        useCommonUi: true,
      );
      return;
    }
    if (_selectedSection == section) {
      if (section == Section.location && _locationWorkspace.isParentFocus) {
        await HapticFeedback.selectionClick();
        context.read<LocationState>().clearSelection();
        _locationWorkspace.closeParent(source: 'rail_reselect');
        _debugLog.log('rail_reselected_location_focus_closed');
        return;
      }
      _debugLog.log('rail_reselected section=${section.name}');
      return;
    }
    if (_selectedSection == Section.user ||
        _selectedSection == Section.tablet ||
        section == Section.user ||
        section == Section.tablet) {
      final userState = context.read<UserState>();
      final selectedId = userState.selectedUserId;
      if (selectedId != null) {
        unawaited(userState.toggleUserCard(selectedId));
        _debugLog.log('shared_account_selection_cleared id=$selectedId');
      }
    }
    final accountContextChanged =
        _selectedSection != section &&
        (_selectedSection == Section.user ||
            _selectedSection == Section.tablet ||
            section == Section.user ||
            section == Section.tablet);
    if (accountContextChanged) {
      _accountWorkspace.reset(
        source: 'section_change_${_selectedSection.name}_to_${section.name}',
      );
      _tabletWorkspace.reset(
        source: 'section_change_${_selectedSection.name}_to_${section.name}',
      );
    }
    if (_selectedSection == Section.bill || section == Section.bill) {
      _billWorkspace.reset(
        source: 'section_change_${_selectedSection.name}_to_${section.name}',
      );
    }
    if (_selectedSection == Section.monthly || section == Section.monthly) {
      _monthlyWorkspace.reset(
        source: 'section_change_${_selectedSection.name}_to_${section.name}',
      );
    }
    if (_selectedSection == Section.sector || section == Section.sector) {
      _sectorWorkspace.reset(
        source: 'section_change_${_selectedSection.name}_to_${section.name}',
      );
    }
    if (_selectedSection == Section.location || section == Section.location) {
      context.read<LocationState>().clearSelection();
      _locationWorkspace.reset(
        source: 'section_change_${_selectedSection.name}_to_${section.name}',
      );
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _selectedSection = section);
    _debugLog.log('rail_selected section=${section.name}');
  }

  Future<void> _selectAccountMode(SecondaryAccountMode mode) async {
    final supported =
        _selectedSection == Section.user || _selectedSection == Section.tablet;
    if (!supported) {
      _debugLog.log('account_mode_blocked mode=${mode.name} section=${_selectedSection.name}');
      return;
    }
    if (_accountWorkspace.mode == mode) {
      await HapticFeedback.selectionClick();
      _accountWorkspace.setMode(mode, source: 'rail');
      return;
    }
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId != null) {
      unawaited(userState.toggleUserCard(selectedId));
      _debugLog.log('account_mode_selection_cleared target=${mode.name}');
    }
    if (mode == SecondaryAccountMode.delete) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.selectionClick();
    }
    if (!mounted) return;
    _accountWorkspace.setMode(mode, source: 'rail');
  }

  Future<void> _selectSettingsSection(UserSettingsSection section) async {
    if (!_accountWorkspace.isSettingsView || _accountWorkspace.settingsSaving) {
      _debugLog.log(
        'settings_section_rail_blocked section=${section.name} saving=${_accountWorkspace.settingsSaving}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _accountWorkspace.requestSettingsSection(
      section,
      source: 'secondary_settings_rail',
    );
  }

  Future<void> _selectTabletSettingsSection(TabletSettingsSection section) async {
    if (!_tabletWorkspace.isSettingsView || _tabletWorkspace.settingsSaving) {
      _debugLog.log(
        'tablet_settings_section_rail_blocked section=${section.name} saving=${_tabletWorkspace.settingsSaving}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _tabletWorkspace.requestSettingsSection(
      section,
      source: 'secondary_tablet_settings_rail',
    );
  }

  Future<void> _selectBillSettingsSection(BillSettingsSection section) async {
    if (!_billWorkspace.isSettingsView || _billWorkspace.settingsSaving) {
      _debugLog.log(
        'bill_settings_section_rail_blocked section=${section.name} saving=${_billWorkspace.settingsSaving}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _billWorkspace.requestSettingsSection(
      section,
      source: 'secondary_bill_settings_rail',
    );
  }

  Future<void> _selectMonthlySettingsSection(
    MonthlyWorkspaceSection section,
  ) async {
    if (_monthlyWorkspace.isManagementView || _monthlyWorkspace.saving) {
      _debugLog.log(
        'monthly_settings_section_rail_blocked section=${section.name} saving=${_monthlyWorkspace.saving}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _monthlyWorkspace.requestSection(
      section,
      source: 'secondary_monthly_settings_rail',
    );
  }

  Future<void> _selectSectorSettingsSection(
    SectorSettingsSection section,
  ) async {
    if (!_sectorWorkspace.isSettingsView || _sectorWorkspace.settingsSaving) {
      _debugLog.log(
        'sector_settings_section_rail_blocked section=${section.name} saving=${_sectorWorkspace.settingsSaving}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _sectorWorkspace.requestSettingsSection(
      section,
      source: 'secondary_sector_settings_rail',
    );
  }

  Future<void> _selectLocationParentSettingsSection(
    LocationParentSettingsSection section,
  ) async {
    if (!_locationWorkspace.isParentSettingsView ||
        _locationWorkspace.settingsSaving) {
      _debugLog.log(
        'location_parent_settings_section_rail_blocked section=${section.name} saving=${_locationWorkspace.settingsSaving}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _locationWorkspace.requestSettingsSection(
      section,
      source: 'secondary_location_parent_settings_rail',
    );
  }

  Future<void> _selectLocationChildSettingsSection(
    LocationChildSettingsSection section,
  ) async {
    if (!_locationWorkspace.isChildSettingsView ||
        _locationWorkspace.settingsSaving) {
      _debugLog.log(
        'location_child_settings_section_rail_blocked section=${section.name} saving=${_locationWorkspace.settingsSaving}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _locationWorkspace.requestChildSettingsSection(
      section,
      source: 'secondary_location_child_settings_rail',
    );
  }

  void _backAccountSettingsWorkspace({String source = 'header_back'}) {
    if (!_accountWorkspace.isSettingsView || _accountWorkspace.settingsSaving) {
      return;
    }
    _debugLog.log('account_settings_back source=$source');
    HapticFeedback.selectionClick();
    _accountWorkspace.returnToManagement(source: source);
  }

  void _backTabletSettingsWorkspace({String source = 'header_back'}) {
    if (!_tabletWorkspace.isSettingsView || _tabletWorkspace.settingsSaving) {
      return;
    }
    _debugLog.log('tablet_settings_back source=$source');
    HapticFeedback.selectionClick();
    _tabletWorkspace.returnToManagement(source: source);
  }

  void _backBillSettingsWorkspace({String source = 'header_back'}) {
    if (!_billWorkspace.isSettingsView || _billWorkspace.settingsSaving) {
      return;
    }
    _debugLog.log('bill_settings_back source=$source');
    HapticFeedback.selectionClick();
    _billWorkspace.returnToManagement(source: source);
  }

  void _backMonthlySettingsWorkspace({String source = 'header_back'}) {
    if (_monthlyWorkspace.isManagementView || _monthlyWorkspace.saving) {
      return;
    }
    _debugLog.log('monthly_settings_back source=$source');
    HapticFeedback.selectionClick();
    _monthlyWorkspace.returnToManagement(source: source);
  }

  void _backSectorSettingsWorkspace({String source = 'header_back'}) {
    if (!_sectorWorkspace.isSettingsView || _sectorWorkspace.settingsSaving) {
      return;
    }
    _debugLog.log('sector_settings_back source=$source');
    HapticFeedback.selectionClick();
    _sectorWorkspace.returnToManagement(source: source);
  }

  void _backLocationParentSettingsWorkspace({String source = 'header_back'}) {
    if (!_locationWorkspace.isParentSettingsView ||
        _locationWorkspace.settingsSaving) {
      return;
    }
    _debugLog.log('location_parent_settings_back source=$source');
    HapticFeedback.selectionClick();
    context.read<LocationState>().clearSelection();
    _locationWorkspace.returnToManagement(source: source);
  }

  void _backLocationChildSettingsWorkspace({String source = 'header_back'}) {
    if (!_locationWorkspace.isChildSettingsView ||
        _locationWorkspace.settingsSaving) {
      return;
    }
    _debugLog.log('location_child_settings_back source=$source');
    HapticFeedback.selectionClick();
    context.read<LocationState>().clearSelection();
    _locationWorkspace.returnToManagement(source: source);
  }

  UserModel? _editingUser(UserState state) {
    final id = _accountWorkspace.editingUserId;
    if (id == null || id.isEmpty) return null;
    for (final user in state.users) {
      if (user.id == id) return user;
    }
    return null;
  }

  TabletModel? _editingTablet(UserState state) {
    final id = _tabletWorkspace.editingTabletId;
    if (id == null || id.isEmpty) return null;
    for (final tablet in state.tabletUsers) {
      if (tablet.id == id) return tablet;
    }
    return null;
  }

  SectorModel? _editingSector(SectorState state) {
    final id = _sectorWorkspace.editingSectorId;
    if (id == null || id.isEmpty) return null;
    for (final sector in state.sectors) {
      if (sector.id == id) return sector;
    }
    return null;
  }

  LocationModel? _editingLocationParent(LocationState state) {
    final id = _locationWorkspace.editingParentId;
    if (id == null || id.isEmpty) return null;
    for (final location in state.locations) {
      if (location.id == id && location.isCompositeParent) return location;
    }
    return null;
  }

  LocationModel? _editingLocationChild(LocationState state) {
    final id = _locationWorkspace.editingChildId;
    if (id == null || id.isEmpty) return null;
    for (final location in state.locations) {
      if (location.id == id && location.isCompositeChild) return location;
    }
    return null;
  }

  LocationModel? _childSettingsParent(LocationState state) {
    final parentId = _locationWorkspace.childParentId?.trim() ?? '';
    if (parentId.isEmpty) return null;
    for (final location in state.locations) {
      if (location.id == parentId &&
          location.isCompositeParent &&
          location.parkingGrid != null) {
        return location;
      }
    }
    return null;
  }

  Future<void> _showDeveloperStatus() async {
    if (!_devModeEnabled) return;
    _logAccessSnapshot(context.read<SecondaryState>());
    if (_accountWorkspace.isSettingsView) {
      final sectionStates = UserSettingsSection.values
          .map(
            (section) =>
                '${section.name}:${_accountWorkspace.stateFor(section).name}',
          )
          .join('|');
      _debugLog.log(
        'settings_snapshot mode=${_accountWorkspace.settingsMode.name} active=${_accountWorkspace.activeSettingsSection.name} dirty=${_accountWorkspace.settingsDirty} saving=${_accountWorkspace.settingsSaving} userId=${_accountWorkspace.editingUserId ?? '-'} states=$sectionStates',
      );
    }
    if (_tabletWorkspace.isSettingsView) {
      final sectionStates = TabletSettingsSection.values
          .map(
            (section) =>
                '${section.name}:${_tabletWorkspace.stateFor(section).name}',
          )
          .join('|');
      _debugLog.log(
        'tablet_settings_snapshot mode=${_tabletWorkspace.settingsMode.name} active=${_tabletWorkspace.activeSettingsSection.name} dirty=${_tabletWorkspace.settingsDirty} saving=${_tabletWorkspace.settingsSaving} states=$sectionStates',
      );
    }
    if (_billWorkspace.isSettingsView) {
      final sectionStates = BillSettingsSection.values
          .map(
            (section) =>
                '${section.name}:${_billWorkspace.stateFor(section).name}',
          )
          .join('|');
      _debugLog.log(
        'bill_settings_snapshot active=${_billWorkspace.activeSettingsSection.name} dirty=${_billWorkspace.settingsDirty} saving=${_billWorkspace.settingsSaving} states=$sectionStates',
      );
    }
    if (!_monthlyWorkspace.isManagementView) {
      final sectionStates = _monthlyWorkspace.visibleSections
          .map(
            (section) =>
                '${section.name}:${_monthlyWorkspace.stateFor(section).name}',
          )
          .join('|');
      _debugLog.log(
        'monthly_settings_snapshot view=${_monthlyWorkspace.view.name} active=${_monthlyWorkspace.activeSection.name} dirty=${_monthlyWorkspace.dirty} saving=${_monthlyWorkspace.saving} editDoc=${_monthlyWorkspace.editingDocId ?? '-'} paymentDoc=${_monthlyWorkspace.paymentDocId ?? '-'} states=$sectionStates',
      );
    }
    if (_sectorWorkspace.isSettingsView) {
      final sectionStates = SectorSettingsSection.values
          .map(
            (section) =>
                '${section.name}:${_sectorWorkspace.stateFor(section).name}',
          )
          .join('|');
      _debugLog.log(
        'sector_settings_snapshot mode=${_sectorWorkspace.settingsMode.name} active=${_sectorWorkspace.activeSettingsSection.name} dirty=${_sectorWorkspace.settingsDirty} saving=${_sectorWorkspace.settingsSaving} sectorId=${_sectorWorkspace.editingSectorId ?? '-'} states=$sectionStates',
      );
    }

    if (_locationWorkspace.isParentSettingsView) {
      final sectionStates = LocationParentSettingsSection.values
          .map(
            (section) =>
                '${section.name}:${_locationWorkspace.stateFor(section).name}',
          )
          .join('|');
      _debugLog.log(
        'location_parent_settings_snapshot mode=${_locationWorkspace.settingsMode.name} active=${_locationWorkspace.activeSettingsSection.name} dirty=${_locationWorkspace.settingsDirty} saving=${_locationWorkspace.settingsSaving} parentId=${_locationWorkspace.editingParentId ?? '-'} states=$sectionStates',
      );
    }
    if (_locationWorkspace.isChildSettingsView) {
      final sectionStates = LocationChildSettingsSection.values
          .map(
            (section) =>
                '${section.name}:${_locationWorkspace.childStateFor(section).name}',
          )
          .join('|');
      _debugLog.log(
        'location_child_settings_snapshot mode=${_locationWorkspace.childSettingsMode.name} active=${_locationWorkspace.activeChildSettingsSection.name} dirty=${_locationWorkspace.settingsDirty} saving=${_locationWorkspace.settingsSaving} childId=${_locationWorkspace.editingChildId ?? '-'} parentId=${_locationWorkspace.childParentId ?? '-'} states=$sectionStates',
      );
    }
    _debugLog.log('status_dialog_open');
    await _debugLog.showStatus(context);
  }

  void _close() {
    _debugLog.log('close_button selected=${_selectedSection.name}');
    if (_selectedSection == Section.user && _accountWorkspace.isSettingsView) {
      if (_accountWorkspace.settingsSaving) {
        _debugLog.log('account_settings_minimize_blocked saving=true');
        return;
      }
      HapticFeedback.lightImpact();
      _accountWorkspace.returnToManagement(source: 'header_minimize');
      return;
    }
    if (_selectedSection == Section.tablet && _tabletWorkspace.isSettingsView) {
      if (_tabletWorkspace.settingsSaving) {
        _debugLog.log('tablet_settings_minimize_blocked saving=true');
        return;
      }
      HapticFeedback.lightImpact();
      _tabletWorkspace.returnToManagement(source: 'header_minimize');
      return;
    }
    if (_selectedSection == Section.bill && _billWorkspace.isSettingsView) {
      if (_billWorkspace.settingsSaving) {
        _debugLog.log('bill_settings_minimize_blocked saving=true');
        return;
      }
      HapticFeedback.lightImpact();
      _billWorkspace.returnToManagement(source: 'header_minimize');
      return;
    }
    if (_selectedSection == Section.monthly &&
        !_monthlyWorkspace.isManagementView) {
      if (_monthlyWorkspace.saving) {
        _debugLog.log('monthly_settings_minimize_blocked saving=true');
        return;
      }
      HapticFeedback.lightImpact();
      _monthlyWorkspace.returnToManagement(source: 'header_minimize');
      return;
    }
    if (_selectedSection == Section.sector && _sectorWorkspace.isSettingsView) {
      if (_sectorWorkspace.settingsSaving) {
        _debugLog.log('sector_settings_minimize_blocked saving=true');
        return;
      }
      HapticFeedback.lightImpact();
      _sectorWorkspace.returnToManagement(source: 'header_minimize');
      return;
    }

    if (_selectedSection == Section.location &&
        _locationWorkspace.isParentSettingsView) {
      if (_locationWorkspace.settingsSaving) {
        _debugLog.log('location_parent_settings_minimize_blocked saving=true');
        return;
      }
      HapticFeedback.lightImpact();
      context.read<LocationState>().clearSelection();
      _locationWorkspace.returnToManagement(source: 'header_minimize');
      return;
    }
    if (_selectedSection == Section.location &&
        _locationWorkspace.isChildSettingsView) {
      if (_locationWorkspace.settingsSaving) {
        _debugLog.log('location_child_settings_minimize_blocked saving=true');
        return;
      }
      HapticFeedback.lightImpact();
      context.read<LocationState>().clearSelection();
      _locationWorkspace.returnToManagement(source: 'header_minimize');
      return;
    }
    HapticFeedback.lightImpact();
    if (_selectedSection == Section.location && _locationWorkspace.isParentFocus) {
      context.read<LocationState>().clearSelection();
      _locationWorkspace.reset(source: 'dock_close');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
      });
      return;
    }
    Navigator.of(context).pop();
  }

  void _backLocationWorkspace() {
    if (_selectedSection != Section.location || !_locationWorkspace.isParentFocus) {
      return;
    }
    _debugLog.log('location_header_back');
    HapticFeedback.selectionClick();
    context.read<LocationState>().clearSelection();
    _locationWorkspace.closeParent(source: 'header_back');
  }

  String _locationNameKey(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  List<LocationModel> _focusedLocationChildren(
    LocationState state,
    String area,
  ) {
    if (!_locationWorkspace.isParentFocus) return const <LocationModel>[];
    final focusedParentId = _locationWorkspace.focusedParentId?.trim() ?? '';
    final focusedParentTitle =
        _locationWorkspace.focusedParentTitle?.trim() ?? '';
    final focusedParentNameKey = _locationNameKey(focusedParentTitle);
    final out = state.locations.where((location) {
      if (!location.isCompositeChild) return false;
      if (area.isNotEmpty && location.area.trim() != area) return false;
      final childParentId = location.parentId?.trim() ?? '';
      if (focusedParentId.isNotEmpty && childParentId.isNotEmpty) {
        return childParentId == focusedParentId;
      }
      final legacyParent = location.parent?.trim() ?? '';
      return focusedParentNameKey.isNotEmpty &&
          _locationNameKey(legacyParent) == focusedParentNameKey;
    }).toList();
    out.sort((a, b) => a.locationName.compareTo(b.locationName));
    return out;
  }

  Future<void> _selectLocationChildFromRail(LocationModel child) async {
    if (_selectedSection != Section.location ||
        !_locationWorkspace.isParentFocus) {
      _locationWorkspace.log(
        'child_rail_tap_ignored id=${child.id} reason=workspace_inactive',
      );
      return;
    }
    final state = context.read<LocationState>();
    if (state.selectedLocationId == child.id) {
      await HapticFeedback.selectionClick();
      _locationWorkspace.log('child_rail_reselected id=${child.id}');
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    state.selectLocation(child.id);
    _locationWorkspace.log('child_selected id=${child.id} source=rail');
  }

  String _sectionDisplayTitle(Section section) {
    switch (section) {
      case Section.local:
        return '설정';
      case Section.user:
        return '계정 관리';
      case Section.sector:
        return '섹터 관리';
      case Section.location:
        return '구역 관리';
      case Section.tablet:
        return '태블릿 관리';
      case Section.bill:
        return '정산 관리';
      case Section.backend:
        return '백엔드 컨트롤러';
      case Section.area:
        return '지역 및 회사 관리';
      case Section.monthly:
        return '정기 주차 관리';
    }
  }

  Widget _contentFor(
    Section section,
    SecondaryAccountWorkspaceState accountWorkspace,
    SecondaryTabletWorkspaceState tabletWorkspace,
    SecondaryBillWorkspaceState billWorkspace,
    SecondarySectorWorkspaceState sectorWorkspace,
  ) {
    if (section == Section.user) {
      if (accountWorkspace.isSettingsView) {
        final userState = context.watch<UserState>();
        final initialUser = accountWorkspace.isEditingSettings
            ? _editingUser(userState)
            : null;
        if (accountWorkspace.isEditingSettings && initialUser == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !accountWorkspace.isSettingsView) return;
            _debugLog.log('account_settings_edit_target_missing');
            accountWorkspace.returnToManagement(
              source: 'edit_target_missing',
            );
          });
        }
        return OpsConsolePresentationScope(
          key: const ValueKey<String>('secondary-account-settings'),
          embedded: true,
          child: _SecondaryOperationsWorkspaceMotion(
            child: initialUser == null && accountWorkspace.isEditingSettings
                ? const OpsEmptyState(
                    icon: Icons.person_off_rounded,
                    title: '수정할 계정을 찾을 수 없습니다',
                    message: '계정 목록으로 돌아가 다시 선택해 주세요.',
                  )
                : UserSettingWorkspace(initialUser: initialUser),
          ),
        );
      }
      final info = kSectionTab[section];
      return OpsConsolePresentationScope(
        key: const ValueKey<String>('secondary-account-management'),
        embedded: true,
        child: _SecondaryOperationsWorkspaceMotion(
          child: info?.page ?? const SizedBox.shrink(),
        ),
      );
    }

    if (section == Section.tablet) {
      if (tabletWorkspace.isSettingsView) {
        final userState = context.watch<UserState>();
        final initialTablet = tabletWorkspace.isEditingSettings
            ? _editingTablet(userState)
            : null;
        if (tabletWorkspace.isEditingSettings &&
            initialTablet == null &&
            !tabletWorkspace.settingsSaving) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !tabletWorkspace.isSettingsView ||
                tabletWorkspace.settingsSaving) {
              return;
            }
            _debugLog.log('tablet_settings_edit_target_missing');
            tabletWorkspace.returnToManagement(
              source: 'edit_target_missing',
            );
          });
        }
        return OpsConsolePresentationScope(
          key: const ValueKey<String>('secondary-tablet-settings'),
          embedded: true,
          child: _SecondaryOperationsWorkspaceMotion(
            child: initialTablet == null &&
                    tabletWorkspace.isEditingSettings &&
                    !tabletWorkspace.settingsSaving
                ? const OpsEmptyState(
                    icon: Icons.tablet_android_rounded,
                    title: '수정할 태블릿을 찾을 수 없습니다',
                    message: '태블릿 목록으로 돌아가 다시 선택해 주세요.',
                  )
                : TabletSettingWorkspace(initialTablet: initialTablet),
          ),
        );
      }
      final info = kSectionTab[section];
      return OpsConsolePresentationScope(
        key: const ValueKey<String>('secondary-tablet-management'),
        embedded: true,
        child: _SecondaryOperationsWorkspaceMotion(
          child: info?.page ?? const SizedBox.shrink(),
        ),
      );
    }

    if (section == Section.sector) {
      if (sectorWorkspace.isSettingsView) {
        final sectorState = context.watch<SectorState>();
        final initialSector = sectorWorkspace.isEditingSettings
            ? _editingSector(sectorState)
            : null;
        if (sectorWorkspace.isEditingSettings &&
            initialSector == null &&
            !sectorWorkspace.settingsSaving) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !sectorWorkspace.isSettingsView ||
                sectorWorkspace.settingsSaving) {
              return;
            }
            _debugLog.log('sector_settings_edit_target_missing');
            sectorWorkspace.returnToManagement(
              source: 'edit_target_missing',
            );
          });
        }
        return OpsConsolePresentationScope(
          key: const ValueKey<String>('secondary-sector-settings'),
          embedded: true,
          child: _SecondaryOperationsWorkspaceMotion(
            child: initialSector == null &&
                    sectorWorkspace.isEditingSettings &&
                    !sectorWorkspace.settingsSaving
                ? const OpsEmptyState(
                    icon: Icons.hub_rounded,
                    title: '수정할 섹터를 찾을 수 없습니다',
                    message: '섹터 목록으로 돌아가 다시 선택해 주세요.',
                  )
                : SectorSettingWorkspace(initialSector: initialSector),
          ),
        );
      }
      final info = kSectionTab[section];
      return OpsConsolePresentationScope(
        key: const ValueKey<String>('secondary-sector-management'),
        embedded: true,
        child: _SecondaryOperationsWorkspaceMotion(
          child: info?.page ?? const SizedBox.shrink(),
        ),
      );
    }

    if (section == Section.monthly) {
      if (_monthlyWorkspace.isSettingsView) {
        final initialData = _monthlyWorkspace.initialData;
        final isEditMode = _monthlyWorkspace.isEditingSettings;
        final missingTarget = isEditMode &&
            (_monthlyWorkspace.editingDocId == null || initialData == null);
        if (missingTarget && !_monthlyWorkspace.saving) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !_monthlyWorkspace.isSettingsView ||
                _monthlyWorkspace.saving) {
              return;
            }
            _debugLog.log('monthly_settings_edit_target_missing');
            _monthlyWorkspace.returnToManagement(
              source: 'edit_target_missing',
            );
          });
        }
        return OpsConsolePresentationScope(
          key: const ValueKey<String>('secondary-monthly-settings'),
          embedded: true,
          child: _SecondaryOperationsWorkspaceMotion(
            child: missingTarget
                ? const OpsEmptyState(
                    icon: Icons.local_parking_rounded,
                    title: '수정할 정기권을 찾을 수 없습니다',
                    message: '정기 주차 관리로 돌아가 다시 선택해 주세요.',
                  )
                : MonthlyPlateSettingWorkspace(
                    isEditMode: isEditMode,
                    initialDocId: _monthlyWorkspace.editingDocId,
                    initialData: initialData,
                  ),
          ),
        );
      }
      if (_monthlyWorkspace.isPaymentView) {
        final initialData = _monthlyWorkspace.initialData;
        final docId = _monthlyWorkspace.paymentDocId;
        final missingTarget = docId == null || initialData == null;
        if (missingTarget && !_monthlyWorkspace.saving) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !_monthlyWorkspace.isPaymentView ||
                _monthlyWorkspace.saving) {
              return;
            }
            _debugLog.log('monthly_payment_target_missing');
            _monthlyWorkspace.returnToManagement(
              source: 'payment_target_missing',
            );
          });
        }
        return OpsConsolePresentationScope(
          key: const ValueKey<String>('secondary-monthly-payment'),
          embedded: true,
          child: _SecondaryOperationsWorkspaceMotion(
            child: missingTarget
                ? const OpsEmptyState(
                    icon: Icons.payments_outlined,
                    title: '결제할 정기권을 찾을 수 없습니다',
                    message: '정기 주차 관리로 돌아가 다시 선택해 주세요.',
                  )
                : MonthlyPaymentSettingWorkspace(
                    docId: docId,
                    initialData: initialData,
                  ),
          ),
        );
      }
      final info = kSectionTab[section];
      return OpsConsolePresentationScope(
        key: ValueKey<String>(
          'secondary-monthly-management-${_monthlyWorkspace.managementRevision}',
        ),
        embedded: true,
        child: _SecondaryOperationsWorkspaceMotion(
          child: info?.page ?? const SizedBox.shrink(),
        ),
      );
    }

    if (section == Section.bill) {
      if (billWorkspace.isSettingsView) {
        return const OpsConsolePresentationScope(
          key: ValueKey<String>('secondary-bill-settings'),
          embedded: true,
          child: _SecondaryOperationsWorkspaceMotion(
            child: BillSettingWorkspace(),
          ),
        );
      }
      final info = kSectionTab[section];
      return OpsConsolePresentationScope(
        key: const ValueKey<String>('secondary-bill-management'),
        embedded: true,
        child: _SecondaryOperationsWorkspaceMotion(
          child: info?.page ?? const SizedBox.shrink(),
        ),
      );
    }

    if (section == Section.location) {
      if (_locationWorkspace.isParentSettingsView) {
        final locationState = context.watch<LocationState>();
        final initialParent = _locationWorkspace.isEditingParentSettings
            ? _editingLocationParent(locationState)
            : null;
        if (_locationWorkspace.isEditingParentSettings &&
            initialParent == null &&
            !_locationWorkspace.settingsSaving) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !_locationWorkspace.isParentSettingsView ||
                _locationWorkspace.settingsSaving) {
              return;
            }
            _debugLog.log('location_parent_settings_edit_target_missing');
            _locationWorkspace.returnToManagement(
              source: 'edit_target_missing',
            );
          });
        }
        return OpsConsolePresentationScope(
          key: const ValueKey<String>('secondary-location-parent-settings'),
          embedded: true,
          child: _SecondaryOperationsWorkspaceMotion(
            child: initialParent == null &&
                    _locationWorkspace.isEditingParentSettings &&
                    !_locationWorkspace.settingsSaving
                ? const OpsEmptyState(
                    icon: Icons.location_off_rounded,
                    title: '수정할 부모구역을 찾을 수 없습니다',
                    message: '구역 관리로 돌아가 다시 선택해 주세요.',
                  )
                : LocationParentSettingWorkspace(
                    initialParent: initialParent,
                  ),
          ),
        );
      }
      if (_locationWorkspace.isChildSettingsView) {
        final locationState = context.watch<LocationState>();
        final parent = _childSettingsParent(locationState);
        final initialChild = _locationWorkspace.isEditingChildSettings
            ? _editingLocationChild(locationState)
            : null;
        final missingTarget = parent == null ||
            (_locationWorkspace.isEditingChildSettings && initialChild == null);
        if (missingTarget && !_locationWorkspace.settingsSaving) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !_locationWorkspace.isChildSettingsView ||
                _locationWorkspace.settingsSaving) {
              return;
            }
            _debugLog.log('location_child_settings_target_missing');
            _locationWorkspace.returnToManagement(
              source: 'child_edit_target_missing',
            );
          });
        }
        return OpsConsolePresentationScope(
          key: const ValueKey<String>('secondary-location-child-settings'),
          embedded: true,
          child: _SecondaryOperationsWorkspaceMotion(
            child: missingTarget
                ? const OpsEmptyState(
                    icon: Icons.location_off_rounded,
                    title: '자식구역 설정 대상을 찾을 수 없습니다',
                    message: '구역 관리로 돌아가 다시 선택해 주세요.',
                  )
                : LocationChildSettingWorkspace(
                    parent: parent,
                    initialChild: initialChild,
                  ),
          ),
        );
      }
      return OpsConsolePresentationScope(
        key: const ValueKey<String>('secondary-location-management'),
        embedded: true,
        child: _SecondaryOperationsWorkspaceMotion(
          child: LocationManagement(workspace: _locationWorkspace),
        ),
      );
    }

    final info = kSectionTab[section];
    if (info == null) {
      return const SizedBox.shrink();
    }
    return OpsConsolePresentationScope(
      key: ValueKey<Section>(section),
      embedded: true,
      child: info.page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final area = context.select<AreaState, String>(
      (state) => state.currentArea.trim(),
    );
    final previousArea = _lastArea;
    if (previousArea == null) {
      _lastArea = area;
    } else if (previousArea != area) {
      _lastArea = area;
      if (_locationWorkspace.isParentFocus ||
          _locationWorkspace.isParentSettingsView ||
          _locationWorkspace.isChildSettingsView) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _locationWorkspace.reset(source: 'area_changed_${previousArea}_to_$area');
        });
      }
      if (_sectorWorkspace.isSettingsView) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_sectorWorkspace.isSettingsView) return;
          _sectorWorkspace.reset(
            source: 'area_changed_${previousArea}_to_$area',
          );
        });
      }
      if (!_monthlyWorkspace.isManagementView) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _monthlyWorkspace.isManagementView) return;
          _monthlyWorkspace.reset(
            source: 'area_changed_${previousArea}_to_$area',
          );
        });
      }
    }

    return SecondaryDebugScope(
      onLog: _debugLog.log,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<SecondaryAccountWorkspaceState>.value(
            value: _accountWorkspace,
          ),
          ChangeNotifierProvider<SecondaryTabletWorkspaceState>.value(
            value: _tabletWorkspace,
          ),
          ChangeNotifierProvider<SecondaryBillWorkspaceState>.value(
            value: _billWorkspace,
          ),
          ChangeNotifierProvider<SecondaryMonthlyWorkspaceState>.value(
            value: _monthlyWorkspace,
          ),
          ChangeNotifierProvider<SecondarySectorWorkspaceState>.value(
            value: _sectorWorkspace,
          ),
          ChangeNotifierProvider<SecondaryLocationWorkspaceState>.value(
            value: _locationWorkspace,
          ),
        ],
        child: AnimatedBuilder(
          animation: _locationWorkspace,
          builder: (context, _) => Consumer4<
              SecondaryState,
              SecondaryAccountWorkspaceState,
              SecondaryTabletWorkspaceState,
              SecondaryBillWorkspaceState>(
            builder: (context, state, accountWorkspace, tabletWorkspace,
                billWorkspace, _) {
          final sectorWorkspace = context.watch<SecondarySectorWorkspaceState>();
          final monthlyWorkspace = context.watch<SecondaryMonthlyWorkspaceState>();
          final selected = _effectiveSection(state);
          final selectedTitle = _sectionDisplayTitle(selected);
          final locationFocus =
              selected == Section.location && _locationWorkspace.isParentFocus;
          final locationParentSettingsFocus = selected == Section.location &&
              _locationWorkspace.isParentSettingsView;
          final locationChildSettingsFocus = selected == Section.location &&
              _locationWorkspace.isChildSettingsView;
          final locationAnySettingsFocus =
              locationParentSettingsFocus || locationChildSettingsFocus;
          final accountSettingsFocus =
              selected == Section.user && accountWorkspace.isSettingsView;
          final tabletSettingsFocus =
              selected == Section.tablet && tabletWorkspace.isSettingsView;
          final billSettingsFocus =
              selected == Section.bill && billWorkspace.isSettingsView;
          final monthlySettingsFocus =
              selected == Section.monthly && !monthlyWorkspace.isManagementView;
          final sectorSettingsFocus =
              selected == Section.sector && sectorWorkspace.isSettingsView;
          final settingsFocus = accountSettingsFocus ||
              tabletSettingsFocus ||
              billSettingsFocus ||
              monthlySettingsFocus ||
              sectorSettingsFocus ||
              locationParentSettingsFocus ||
              locationChildSettingsFocus;
          final settingsSaving =
              (accountSettingsFocus && accountWorkspace.settingsSaving) ||
              (tabletSettingsFocus && tabletWorkspace.settingsSaving) ||
              (billSettingsFocus && billWorkspace.settingsSaving) ||
              (monthlySettingsFocus && monthlyWorkspace.saving) ||
              (sectorSettingsFocus && sectorWorkspace.settingsSaving) ||
              ((locationParentSettingsFocus || locationChildSettingsFocus) &&
                  _locationWorkspace.settingsSaving);
          final locationState = context.watch<LocationState>();
          final locationChildren = locationFocus
              ? _focusedLocationChildren(locationState, area)
              : const <LocationModel>[];
          final locationTitle = _locationWorkspace.focusedParentTitle?.trim() ?? '';
          final accountSettingsTitle = accountWorkspace.isEditingSettings
              ? '계정 수정'
              : '신규 계정 등록';
          final tabletSettingsTitle = tabletWorkspace.isEditingSettings
              ? '태블릿 수정'
              : '신규 태블릿 등록';
          const billSettingsTitle = '신규 정산 유형';
          final monthlySettingsTitle = monthlyWorkspace.isPaymentView
              ? '정기권 결제'
              : monthlyWorkspace.isEditingSettings
                  ? '정기권 수정'
                  : '정기권 등록';
          final sectorSettingsTitle = sectorWorkspace.isEditingSettings
              ? '섹터 수정'
              : '신규 섹터';
          final locationParentSettingsTitle =
              _locationWorkspace.isEditingParentSettings
                  ? '부모구역 수정'
                  : '신규 부모구역';
          final locationChildSettingsTitle =
              _locationWorkspace.isEditingChildSettings
                  ? '자식구역 수정'
                  : '신규 자식구역';
          final contextTitle = locationFocus && locationTitle.isNotEmpty
              ? locationTitle
              : accountSettingsFocus
                  ? accountSettingsTitle
                  : tabletSettingsFocus
                      ? tabletSettingsTitle
                      : billSettingsFocus
                          ? billSettingsTitle
                          : monthlySettingsFocus
                              ? monthlySettingsTitle
                              : sectorSettingsFocus
                              ? sectorSettingsTitle
                              : locationParentSettingsFocus
                                  ? locationParentSettingsTitle
                                  : locationChildSettingsFocus
                                      ? locationChildSettingsTitle
                                      : selectedTitle;
          final subtitle = area.isEmpty ? contextTitle : '$area · $contextTitle';

          return PopScope(
            canPop: !settingsFocus,
            onPopInvoked: (didPop) {
              if (didPop || !settingsFocus) return;
              if (settingsSaving) {
                _debugLog.log(
                  'settings_route_pop_blocked saving=true section=${selected.name}',
                );
                return;
              }
              FocusManager.instance.primaryFocus?.unfocus();
              _debugLog.log(
                'settings_route_pop_intercepted section=${selected.name}',
              );
              if (accountSettingsFocus) {
                _backAccountSettingsWorkspace(source: 'settings_system_back');
                return;
              }
              if (tabletSettingsFocus) {
                _backTabletSettingsWorkspace(source: 'settings_system_back');
                return;
              }
              if (billSettingsFocus) {
                _backBillSettingsWorkspace(source: 'settings_system_back');
                return;
              }
              if (monthlySettingsFocus) {
                _backMonthlySettingsWorkspace(source: 'settings_system_back');
                return;
              }
              if (sectorSettingsFocus) {
                _backSectorSettingsWorkspace(source: 'settings_system_back');
                return;
              }
              if (locationParentSettingsFocus) {
                _backLocationParentSettingsWorkspace(
                  source: 'settings_system_back',
                );
                return;
              }
              if (locationChildSettingsFocus) {
                _backLocationChildSettingsWorkspace(
                  source: 'settings_system_back',
                );
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
              final dockHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : media?.size.height ?? 720.0;
              final dockWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : media?.size.width ?? 360.0;
              final railMetrics = CommonSideRailMetrics.resolve(
                dockHeight: dockHeight,
                textScale: textScale,
              );
              final effectiveRailWidth =
                  railMetrics.effectiveRailWidth(dockWidth);
              final effectiveRailGap = railMetrics.effectiveRailGap(dockWidth);

              return Column(
                children: [
                  _SecondaryDockHeader(
                    subtitle: subtitle,
                    loading: state.isLoading ||
                        accountWorkspace.settingsSaving ||
                        tabletWorkspace.settingsSaving ||
                        billWorkspace.settingsSaving ||
                        monthlyWorkspace.saving ||
                        sectorWorkspace.settingsSaving ||
                        _locationWorkspace.settingsSaving,
                    showBack: locationFocus ||
                        locationAnySettingsFocus ||
                        accountSettingsFocus ||
                        tabletSettingsFocus ||
                        billSettingsFocus ||
                        monthlySettingsFocus ||
                        sectorSettingsFocus,
                    onBack: accountSettingsFocus && accountWorkspace.settingsSaving
                        ? null
                        : tabletSettingsFocus && tabletWorkspace.settingsSaving
                            ? null
                            : billSettingsFocus && billWorkspace.settingsSaving
                                ? null
                                : monthlySettingsFocus && monthlyWorkspace.saving
                                    ? null
                                    : sectorSettingsFocus && sectorWorkspace.settingsSaving
                                    ? null
                                    : locationAnySettingsFocus &&
                                            _locationWorkspace.settingsSaving
                                        ? null
                                        : accountSettingsFocus
                                            ? () => _backAccountSettingsWorkspace(source: 'header_back')
                                            : tabletSettingsFocus
                                                ? () => _backTabletSettingsWorkspace(source: 'header_back')
                                                : billSettingsFocus
                                                    ? () => _backBillSettingsWorkspace(source: 'header_back')
                                                    : monthlySettingsFocus
                                                        ? () => _backMonthlySettingsWorkspace(source: 'header_back')
                                                        : sectorSettingsFocus
                                                        ? () => _backSectorSettingsWorkspace(source: 'header_back')
                                                        : locationParentSettingsFocus
                                                            ? () => _backLocationParentSettingsWorkspace(source: 'header_back')
                                                            : locationChildSettingsFocus
                                                                ? () => _backLocationChildSettingsWorkspace(source: 'header_back')
                                                                : _backLocationWorkspace,
                    backTooltip: accountSettingsFocus
                        ? '계정 목록으로'
                        : tabletSettingsFocus
                            ? '태블릿 목록으로'
                            : billSettingsFocus
                                ? '정산 목록으로'
                                : monthlySettingsFocus
                                    ? '정기 주차 관리로'
                                    : sectorSettingsFocus
                                    ? '섹터 목록으로'
                                    : locationAnySettingsFocus
                                        ? '구역 관리로'
                                        : '구역 목록으로',
                    showDeveloperStatus: _devModeEnabled,
                    onDeveloperStatus: _showDeveloperStatus,
                    closeIcon: accountSettingsFocus ||
                            tabletSettingsFocus ||
                            billSettingsFocus ||
                            monthlySettingsFocus ||
                            sectorSettingsFocus ||
                            locationAnySettingsFocus
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.close_rounded,
                    closeTooltip: accountSettingsFocus
                        ? '계정 목록으로 최소화'
                        : tabletSettingsFocus
                            ? '태블릿 목록으로 최소화'
                            : billSettingsFocus
                                ? '정산 목록으로 최소화'
                                : monthlySettingsFocus
                                    ? '정기 주차 관리로 최소화'
                                    : sectorSettingsFocus
                                    ? '섹터 목록으로 최소화'
                                    : locationAnySettingsFocus
                                        ? '구역 관리로 최소화'
                                        : '닫기',
                    onClose: accountSettingsFocus && accountWorkspace.settingsSaving
                        ? null
                        : tabletSettingsFocus && tabletWorkspace.settingsSaving
                            ? null
                            : billSettingsFocus && billWorkspace.settingsSaving
                                ? null
                                : monthlySettingsFocus && monthlyWorkspace.saving
                                    ? null
                                    : sectorSettingsFocus && sectorWorkspace.settingsSaving
                                    ? null
                                    : locationAnySettingsFocus &&
                                            _locationWorkspace.settingsSaving
                                        ? null
                                        : _close,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: effectiveRailWidth,
                          child: ClipRect(
                            child: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                if (reduceMotion) return child;
                                final enteringSettings = child.key ==
                                        const ValueKey<String>('secondary-user-settings-rail') ||
                                    child.key ==
                                        const ValueKey<String>('secondary-tablet-settings-rail') ||
                                    child.key ==
                                        const ValueKey<String>('secondary-bill-settings-rail') ||
                                    child.key ==
                                        const ValueKey<String>('secondary-monthly-settings-rail') ||
                                    child.key ==
                                        const ValueKey<String>('secondary-sector-settings-rail') ||
                                    child.key ==
                                        const ValueKey<String>('secondary-location-parent-settings-rail') ||
                                    child.key ==
                                        const ValueKey<String>('secondary-location-child-settings-rail');
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: enteringSettings
                                          ? const Offset(.08, 0)
                                          : const Offset(-.05, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: KeyedSubtree(
                                key: ValueKey<String>(
                                  accountSettingsFocus
                                      ? 'secondary-user-settings-rail'
                                      : tabletSettingsFocus
                                          ? 'secondary-tablet-settings-rail'
                                          : billSettingsFocus
                                              ? 'secondary-bill-settings-rail'
                                              : monthlySettingsFocus
                                                  ? 'secondary-monthly-settings-rail'
                                                  : sectorSettingsFocus
                                                  ? 'secondary-sector-settings-rail'
                                                  : locationParentSettingsFocus
                                                      ? 'secondary-location-parent-settings-rail'
                                                      : locationChildSettingsFocus
                                                          ? 'secondary-location-child-settings-rail'
                                                          : 'secondary-global-rail',
                                ),
                                child: _SecondaryQuickActionRail(
                                  primaryItems: _primaryItems,
                                  bottomItems: _bottomItems,
                                  selectedSection: selected,
                                  accountMode: accountWorkspace.mode,
                                  showAccountModes: !accountSettingsFocus &&
                                      !tabletSettingsFocus &&
                                      !billSettingsFocus &&
                                      !monthlySettingsFocus &&
                                      !sectorSettingsFocus &&
                                      (selected == Section.user ||
                                          selected == Section.tablet),
                                  locationChildMode: locationFocus,
                                  userSettingsMode: accountSettingsFocus,
                                  tabletSettingsMode: tabletSettingsFocus,
                                  billSettingsMode: billSettingsFocus,
                                  monthlySettingsMode: monthlySettingsFocus,
                                  sectorSettingsMode: sectorSettingsFocus,
                                  locationParentSettingsMode:
                                      locationParentSettingsFocus,
                                  locationChildSettingsMode:
                                      locationChildSettingsFocus,
                                  settingsSection:
                                      accountWorkspace.activeSettingsSection,
                                  settingsSectionStates:
                                      accountWorkspace.sectionStates,
                                  settingsSaving: accountWorkspace.settingsSaving,
                                  tabletSettingsSection:
                                      tabletWorkspace.activeSettingsSection,
                                  tabletSettingsSectionStates:
                                      tabletWorkspace.sectionStates,
                                  tabletSettingsSaving:
                                      tabletWorkspace.settingsSaving,
                                  billSettingsSection:
                                      billWorkspace.activeSettingsSection,
                                  billSettingsSectionStates:
                                      billWorkspace.sectionStates,
                                  billSettingsSaving:
                                      billWorkspace.settingsSaving,
                                  monthlySettingsSection:
                                      monthlyWorkspace.activeSection,
                                  monthlySettingsSectionStates:
                                      monthlyWorkspace.sectionStates,
                                  monthlySettingsSaving: monthlyWorkspace.saving,
                                  monthlyPaymentMode: monthlyWorkspace.isPaymentView,
                                  sectorSettingsSection:
                                      sectorWorkspace.activeSettingsSection,
                                  sectorSettingsSectionStates:
                                      sectorWorkspace.sectionStates,
                                  sectorSettingsSaving:
                                      sectorWorkspace.settingsSaving,
                                  locationParentSettingsSection:
                                      _locationWorkspace.activeSettingsSection,
                                  locationParentSettingsSectionStates:
                                      _locationWorkspace.sectionStates,
                                  locationParentSettingsSaving:
                                      _locationWorkspace.settingsSaving,
                                  locationChildSettingsSection:
                                      _locationWorkspace.activeChildSettingsSection,
                                  locationChildSettingsSectionStates:
                                      _locationWorkspace.childSectionStates,
                                  locationChildSettingsSaving:
                                      _locationWorkspace.settingsSaving,
                                  locationChildren: locationChildren,
                                  selectedLocationId:
                                      locationState.selectedLocationId,
                                  isEnabled: state.canAccess,
                                  disabledReason: state.disabledReason,
                                  metrics: railMetrics,
                                  fullDockHeight: dockHeight,
                                  dockWidth: dockWidth,
                                  effectiveRailWidth: effectiveRailWidth,
                                  effectiveRailGap: effectiveRailGap,
                                  onDebug: _debugLog.log,
                                  onSelect: (section) {
                                    unawaited(_selectSection(state, section));
                                  },
                                  onSelectAccountMode: (mode) {
                                    unawaited(_selectAccountMode(mode));
                                  },
                                  onSelectLocationChild: (child) {
                                    unawaited(_selectLocationChildFromRail(child));
                                  },
                                  onSelectSettingsSection: (section) {
                                    unawaited(_selectSettingsSection(section));
                                  },
                                  onSelectTabletSettingsSection: (section) {
                                    unawaited(_selectTabletSettingsSection(section));
                                  },
                                  onSelectBillSettingsSection: (section) {
                                    unawaited(_selectBillSettingsSection(section));
                                  },
                                  onSelectMonthlySettingsSection: (section) {
                                    unawaited(_selectMonthlySettingsSection(section));
                                  },
                                  onSelectSectorSettingsSection: (section) {
                                    unawaited(_selectSectorSettingsSection(section));
                                  },
                                  onSelectLocationParentSettingsSection: (section) {
                                    unawaited(
                                      _selectLocationParentSettingsSection(section),
                                    );
                                  },
                                  onSelectLocationChildSettingsSection: (section) {
                                    unawaited(
                                      _selectLocationChildSettingsSection(section),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: effectiveRailGap,
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(CommonUiShapes.card),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: tokens.canvas,
                                border: Border.all(color: tokens.borderSubtle),
                                borderRadius:
                                    BorderRadius.circular(CommonUiShapes.card),
                              ),
                              child: Stack(
                                children: [
                                  AnimatedSwitcher(
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : CommonUiMotion.component,
                                    switchInCurve: CommonUiMotion.enter,
                                    switchOutCurve: CommonUiMotion.exit,
                                    transitionBuilder: (child, animation) {
                                      if (reduceMotion) return child;
                                      final isOperationsWorkspace =
                                          child.key == const ValueKey<String>('secondary-account-management') ||
                                          child.key == const ValueKey<String>('secondary-account-settings') ||
                                          child.key == const ValueKey<String>('secondary-tablet-management') ||
                                          child.key == const ValueKey<String>('secondary-tablet-settings') ||
                                          child.key == const ValueKey<String>('secondary-monthly-settings') ||
                                          child.key == const ValueKey<String>('secondary-monthly-payment') ||
                                          (child.key is ValueKey<String> &&
                                              (child.key as ValueKey<String>).value.startsWith('secondary-monthly-management-')) ||
                                          child.key == const ValueKey<String>('secondary-bill-management') ||
                                          child.key == const ValueKey<String>('secondary-bill-settings') ||
                                          child.key == const ValueKey<String>('secondary-sector-management') ||
                                          child.key == const ValueKey<String>('secondary-sector-settings') ||
                                          child.key == const ValueKey<String>('secondary-location-management') ||
                                          child.key == const ValueKey<String>('secondary-location-parent-settings') ||
                                          child.key == const ValueKey<String>('secondary-location-child-settings');
                                      if (isOperationsWorkspace) return child;
                                      final curved = CurvedAnimation(
                                        parent: animation,
                                        curve: CommonUiMotion.enter,
                                        reverseCurve: CommonUiMotion.exit,
                                      );
                                      return FadeTransition(
                                        opacity: curved,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(.035, 0),
                                            end: Offset.zero,
                                          ).animate(curved),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: _contentFor(
                                      selected,
                                      accountWorkspace,
                                      tabletWorkspace,
                                      billWorkspace,
                                      sectorWorkspace,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: !state.isLoading,
                                      child: AnimatedOpacity(
                                        opacity: state.isLoading ? 1 : 0,
                                        duration: reduceMotion
                                            ? Duration.zero
                                            : CommonUiMotion.selection,
                                        child: ColoredBox(
                                          color: tokens.scrim.withOpacity(.12),
                                          child: Center(
                                            child: Container(
                                              width: 46,
                                              height: 46,
                                              decoration: BoxDecoration(
                                                color: tokens.surfaceRaised,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  CommonUiShapes.control,
                                                ),
                                                border: Border.all(
                                                  color: tokens.borderSubtle,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  color: tokens.accent,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              },
            ),
          );
          },
        ),
        ),
      ),
    );
  }
}

class _SecondaryDockHeader extends StatelessWidget {
  const _SecondaryDockHeader({
    required this.subtitle,
    required this.loading,
    required this.showBack,
    required this.onBack,
    required this.backTooltip,
    required this.showDeveloperStatus,
    required this.onDeveloperStatus,
    required this.closeIcon,
    required this.closeTooltip,
    required this.onClose,
  });

  final String subtitle;
  final bool loading;
  final bool showBack;
  final VoidCallback? onBack;
  final String backTooltip;
  final bool showDeveloperStatus;
  final VoidCallback onDeveloperStatus;
  final IconData closeIcon;
  final String closeTooltip;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        if (showBack)
          CommonIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: backTooltip,
            onPressed: onBack,
            haptic: CommonHaptic.selection,
            size: 40,
            iconSize: 21,
          )
        else
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.admin_panel_settings_rounded,
              size: 21,
              color: tokens.onAccentContainer,
            ),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '운영 관리',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (loading) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: tokens.accent,
            ),
          ),
        ],
        if (showDeveloperStatus) ...[
          const SizedBox(width: 6),
          CommonIconButton(
            icon: Icons.bug_report_rounded,
            tooltip: '상태',
            onPressed: onDeveloperStatus,
            haptic: CommonHaptic.selection,
          ),
        ],
        const SizedBox(width: 4),
        CommonIconButton(
          icon: closeIcon,
          tooltip: closeTooltip,
          onPressed: onClose,
          haptic: CommonHaptic.light,
        ),
      ],
    );
  }
}

class _SecondaryQuickActionRail extends StatefulWidget {
  const _SecondaryQuickActionRail({
    required this.primaryItems,
    required this.bottomItems,
    required this.selectedSection,
    required this.accountMode,
    required this.showAccountModes,
    required this.locationChildMode,
    required this.userSettingsMode,
    required this.tabletSettingsMode,
    required this.billSettingsMode,
    required this.monthlySettingsMode,
    required this.sectorSettingsMode,
    required this.locationParentSettingsMode,
    required this.locationChildSettingsMode,
    required this.settingsSection,
    required this.settingsSectionStates,
    required this.settingsSaving,
    required this.tabletSettingsSection,
    required this.tabletSettingsSectionStates,
    required this.tabletSettingsSaving,
    required this.billSettingsSection,
    required this.billSettingsSectionStates,
    required this.billSettingsSaving,
    required this.monthlySettingsSection,
    required this.monthlySettingsSectionStates,
    required this.monthlySettingsSaving,
    required this.monthlyPaymentMode,
    required this.sectorSettingsSection,
    required this.sectorSettingsSectionStates,
    required this.sectorSettingsSaving,
    required this.locationParentSettingsSection,
    required this.locationParentSettingsSectionStates,
    required this.locationParentSettingsSaving,
    required this.locationChildSettingsSection,
    required this.locationChildSettingsSectionStates,
    required this.locationChildSettingsSaving,
    required this.locationChildren,
    required this.selectedLocationId,
    required this.isEnabled,
    required this.disabledReason,
    required this.metrics,
    required this.fullDockHeight,
    required this.dockWidth,
    required this.effectiveRailWidth,
    required this.effectiveRailGap,
    required this.onDebug,
    required this.onSelect,
    required this.onSelectAccountMode,
    required this.onSelectLocationChild,
    required this.onSelectSettingsSection,
    required this.onSelectTabletSettingsSection,
    required this.onSelectBillSettingsSection,
    required this.onSelectMonthlySettingsSection,
    required this.onSelectSectorSettingsSection,
    required this.onSelectLocationParentSettingsSection,
    required this.onSelectLocationChildSettingsSection,
  });

  final List<_SecondaryRailItem> primaryItems;
  final List<_SecondaryRailItem> bottomItems;
  final Section selectedSection;
  final SecondaryAccountMode accountMode;
  final bool showAccountModes;
  final bool locationChildMode;
  final bool userSettingsMode;
  final bool tabletSettingsMode;
  final bool billSettingsMode;
  final bool monthlySettingsMode;
  final bool sectorSettingsMode;
  final bool locationParentSettingsMode;
  final bool locationChildSettingsMode;
  final UserSettingsSection settingsSection;
  final Map<UserSettingsSection, UserSettingsSectionState> settingsSectionStates;
  final bool settingsSaving;
  final TabletSettingsSection tabletSettingsSection;
  final Map<TabletSettingsSection, TabletSettingsSectionState>
      tabletSettingsSectionStates;
  final bool tabletSettingsSaving;
  final BillSettingsSection billSettingsSection;
  final Map<BillSettingsSection, BillSettingsSectionState>
      billSettingsSectionStates;
  final bool billSettingsSaving;
  final MonthlyWorkspaceSection monthlySettingsSection;
  final Map<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>
      monthlySettingsSectionStates;
  final bool monthlySettingsSaving;
  final bool monthlyPaymentMode;
  final SectorSettingsSection sectorSettingsSection;
  final Map<SectorSettingsSection, SectorSettingsSectionState>
      sectorSettingsSectionStates;
  final bool sectorSettingsSaving;
  final LocationParentSettingsSection locationParentSettingsSection;
  final Map<LocationParentSettingsSection, LocationParentSettingsSectionState>
      locationParentSettingsSectionStates;
  final bool locationParentSettingsSaving;
  final LocationChildSettingsSection locationChildSettingsSection;
  final Map<LocationChildSettingsSection, LocationChildSettingsSectionState>
      locationChildSettingsSectionStates;
  final bool locationChildSettingsSaving;
  final List<LocationModel> locationChildren;
  final String? selectedLocationId;
  final bool Function(Section section) isEnabled;
  final String Function(Section section) disabledReason;
  final CommonSideRailMetrics metrics;
  final double fullDockHeight;
  final double dockWidth;
  final double effectiveRailWidth;
  final double effectiveRailGap;
  final ValueChanged<String> onDebug;
  final ValueChanged<Section> onSelect;
  final ValueChanged<SecondaryAccountMode> onSelectAccountMode;
  final ValueChanged<LocationModel> onSelectLocationChild;
  final ValueChanged<UserSettingsSection> onSelectSettingsSection;
  final ValueChanged<TabletSettingsSection> onSelectTabletSettingsSection;
  final ValueChanged<BillSettingsSection> onSelectBillSettingsSection;
  final ValueChanged<MonthlyWorkspaceSection> onSelectMonthlySettingsSection;
  final ValueChanged<SectorSettingsSection> onSelectSectorSettingsSection;
  final ValueChanged<LocationParentSettingsSection>
      onSelectLocationParentSettingsSection;
  final ValueChanged<LocationChildSettingsSection>
      onSelectLocationChildSettingsSection;

  @override
  State<_SecondaryQuickActionRail> createState() =>
      _SecondaryQuickActionRailState();
}

class _SecondaryQuickActionRailState extends State<_SecondaryQuickActionRail> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _childScrollController = ScrollController();
  String? _lastLayoutSignature;
  bool? _lastLocationChildMode;
  String? _lastChildSelectionId;

  @override
  void dispose() {
    _scrollController.dispose();
    _childScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final metrics = widget.metrics;
    if (widget.userSettingsMode) {
      return _UserSettingsTableOfContentsRail(
        metrics: metrics,
        selectedSection: widget.settingsSection,
        sectionStates: widget.settingsSectionStates,
        saving: widget.settingsSaving,
        onSelect: widget.onSelectSettingsSection,
      );
    }
    if (widget.tabletSettingsMode) {
      return _TabletSettingsTableOfContentsRail(
        metrics: metrics,
        selectedSection: widget.tabletSettingsSection,
        sectionStates: widget.tabletSettingsSectionStates,
        saving: widget.tabletSettingsSaving,
        onSelect: widget.onSelectTabletSettingsSection,
      );
    }
    if (widget.billSettingsMode) {
      return _BillSettingsTableOfContentsRail(
        metrics: metrics,
        selectedSection: widget.billSettingsSection,
        sectionStates: widget.billSettingsSectionStates,
        saving: widget.billSettingsSaving,
        onSelect: widget.onSelectBillSettingsSection,
      );
    }
    if (widget.monthlySettingsMode) {
      return _MonthlySettingsTableOfContentsRail(
        metrics: metrics,
        selectedSection: widget.monthlySettingsSection,
        sectionStates: widget.monthlySettingsSectionStates,
        saving: widget.monthlySettingsSaving,
        paymentMode: widget.monthlyPaymentMode,
        onSelect: widget.onSelectMonthlySettingsSection,
      );
    }
    if (widget.sectorSettingsMode) {
      return _SectorSettingsTableOfContentsRail(
        metrics: metrics,
        selectedSection: widget.sectorSettingsSection,
        sectionStates: widget.sectorSettingsSectionStates,
        saving: widget.sectorSettingsSaving,
        onSelect: widget.onSelectSectorSettingsSection,
      );
    }
    if (widget.locationParentSettingsMode) {
      return _LocationParentSettingsTableOfContentsRail(
        metrics: metrics,
        selectedSection: widget.locationParentSettingsSection,
        sectionStates: widget.locationParentSettingsSectionStates,
        saving: widget.locationParentSettingsSaving,
        onSelect: widget.onSelectLocationParentSettingsSection,
      );
    }
    if (widget.locationChildSettingsMode) {
      return _LocationChildSettingsTableOfContentsRail(
        metrics: metrics,
        selectedSection: widget.locationChildSettingsSection,
        sectionStates: widget.locationChildSettingsSectionStates,
        saving: widget.locationChildSettingsSaving,
        onSelect: widget.onSelectLocationChildSettingsSection,
      );
    }
    final items = <_SecondaryRailItem>[
      ...widget.primaryItems,
      ...widget.bottomItems,
    ];

    Widget railButton(
      _SecondaryRailItem item, {
      required double extent,
    }) {
      return _SecondaryRailButton(
        key: ValueKey<Section>(item.section),
        item: item,
        selected: widget.selectedSection == item.section,
        enabled: widget.isEnabled(item.section),
        disabledReason: widget.disabledReason(item.section),
        compact: metrics.compact,
        extent: extent,
        onTap: () => widget.onSelect(item.section),
      );
    }

    Widget childRailButton(
      LocationModel child, {
      required double extent,
    }) {
      return _SecondaryLocationChildRailButton(
        key: ValueKey<String>('location-child-rail-${child.id}'),
        child: child,
        selected: widget.selectedLocationId == child.id,
        compact: metrics.compact,
        extent: extent,
        onTap: () => widget.onSelectLocationChild(child),
      );
    }

    Widget accountModeZone({required double buttonExtent}) {
      return _SecondaryAccountModeZone(
        visible: widget.showAccountModes,
        mode: widget.accountMode,
        compact: metrics.compact,
        buttonExtent: buttonExtent,
        horizontalInset: metrics.actionInsetHorizontal,
        verticalInset: metrics.actionInsetVertical,
        reduceMotion: reduceMotion,
        onSelect: widget.onSelectAccountMode,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 720.0;
        final globalActionCount = items.length;
        final globalEnabledCount =
            items.where((item) => widget.isEnabled(item.section)).length;
        final availableListHeight = math.max(
          0.0,
          railHeight -
              metrics.outerVertical * 2 -
              metrics.headerHeight -
              metrics.headerGap,
        );
        final minimumSlotExtent =
            metrics.minimumButtonExtent + metrics.actionInsetVertical * 2;
        final contextSeparatorExtent = metrics.headerGap + 1;
        final contextAreaExtent = minimumSlotExtent * 2 + contextSeparatorExtent;
        final availableNavigationHeight =
            math.max(0.0, availableListHeight - contextAreaExtent);
        final globalEqualSlotExtent = globalActionCount == 0
            ? 0.0
            : availableNavigationHeight / globalActionCount;
        final globalScrollable = globalActionCount > 0 &&
            (globalEqualSlotExtent + .5 < minimumSlotExtent ||
                availableListHeight <
                    globalActionCount * minimumSlotExtent + contextAreaExtent);
        final referenceButtonExtent = globalScrollable
            ? metrics.minimumButtonExtent
            : math.max(
                0.0,
                globalEqualSlotExtent - metrics.actionInsetVertical * 2,
              );
        final childCount = widget.locationChildren.length;
        final childSlotExtent =
            referenceButtonExtent + metrics.actionInsetVertical * 2;
        final childScrollable = widget.locationChildMode &&
            childCount > 0 &&
            childCount * childSlotExtent > availableListHeight + .5;
        final actionCount =
            widget.locationChildMode ? childCount : globalActionCount;
        final enabledCount =
            widget.locationChildMode ? childCount : globalEnabledCount;
        final distribution = widget.locationChildMode
            ? childCount == 0
                ? 'location_child_empty'
                : childScrollable
                    ? 'location_child_scroll'
                    : 'location_child_fixed'
            : globalActionCount == 0
                ? 'empty'
                : globalScrollable
                    ? 'scroll_fallback'
                    : 'equal_fill_with_context';
        final effectiveSlotExtent = widget.locationChildMode
            ? childSlotExtent
            : globalEqualSlotExtent;
        final effectiveButtonExtent = widget.locationChildMode
            ? referenceButtonExtent
            : globalScrollable
                ? metrics.minimumButtonExtent
                : referenceButtonExtent;
        if (_lastLocationChildMode != widget.locationChildMode) {
          final previousMode = _lastLocationChildMode;
          _lastLocationChildMode = widget.locationChildMode;
          _lastChildSelectionId = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final controller = widget.locationChildMode
                ? _childScrollController
                : _scrollController;
            if (controller.hasClients) {
              controller.jumpTo(0);
            }
            widget.onDebug(
              'secondary_rail_mode_changed from=${previousMode == null ? 'initial' : previousMode ? 'location_child' : 'global'} to=${widget.locationChildMode ? 'location_child' : 'global'} actions=$actionCount',
            );
          });
        }
        final currentChildSelection = widget.locationChildMode
            ? widget.selectedLocationId
            : null;
        if (_lastChildSelectionId != currentChildSelection) {
          _lastChildSelectionId = currentChildSelection;
          if (widget.locationChildMode &&
              childScrollable &&
              currentChildSelection != null) {
            final selectedIndex = widget.locationChildren.indexWhere(
              (child) => child.id == currentChildSelection,
            );
            if (selectedIndex >= 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !_childScrollController.hasClients) return;
                final position = _childScrollController.position;
                final top = selectedIndex * childSlotExtent;
                final bottom = top + childSlotExtent;
                final currentTop = position.pixels;
                final currentBottom = currentTop + position.viewportDimension;
                double? target;
                if (top < currentTop) {
                  target = top;
                } else if (bottom > currentBottom) {
                  target = bottom - position.viewportDimension;
                }
                if (target == null) return;
                final clamped = target.clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                ).toDouble();
                if (reduceMotion) {
                  _childScrollController.jumpTo(clamped);
                } else {
                  unawaited(
                    _childScrollController.animateTo(
                      clamped,
                      duration: CommonUiMotion.selection,
                      curve: CommonUiMotion.enter,
                    ),
                  );
                }
                widget.onDebug(
                  'secondary_rail_child_scrolled_to_selection id=$currentChildSelection index=$selectedIndex offset=${clamped.toStringAsFixed(1)}',
                );
              });
            }
          }
        }
        final signature = <Object>[
          metrics.variantName,
          widget.fullDockHeight.toStringAsFixed(0),
          widget.dockWidth.toStringAsFixed(0),
          widget.effectiveRailWidth.toStringAsFixed(1),
          widget.effectiveRailGap.toStringAsFixed(1),
          railHeight.toStringAsFixed(0),
          widget.locationChildMode,
          actionCount,
          enabledCount,
          distribution,
          effectiveSlotExtent.toStringAsFixed(1),
          effectiveButtonExtent.toStringAsFixed(1),
          widget.selectedSection.name,
          widget.accountMode.name,
          widget.showAccountModes,
        ].join('|');
        if (_lastLayoutSignature != signature) {
          _lastLayoutSignature = signature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onDebug(
              'secondary_rail_layout railDesign=common_operations railMetricsSource=CommonSideRailMetrics mode=${widget.locationChildMode ? 'location_child' : 'global'} dock_width=${widget.dockWidth.toStringAsFixed(1)} dock_height=${widget.fullDockHeight.toStringAsFixed(1)} rail_height=${railHeight.toStringAsFixed(1)} base_width=${metrics.railWidth.toStringAsFixed(1)} width=${widget.effectiveRailWidth.toStringAsFixed(1)} base_gap=${metrics.railGap.toStringAsFixed(1)} gap=${widget.effectiveRailGap.toStringAsFixed(1)} navigation_actions=$actionCount enabled=$enabledCount reference_actions=$globalActionCount context_actions=${widget.locationChildMode ? 0 : 2} context_visible=${widget.locationChildMode ? false : widget.showAccountModes} account_mode=${widget.accountMode.name} distribution=$distribution scroll=${widget.locationChildMode ? childScrollable : globalScrollable} navigation_slot=${effectiveSlotExtent.toStringAsFixed(1)} button_extent=${effectiveButtonExtent.toStringAsFixed(1)} context_extent=${widget.locationChildMode ? '0.0' : contextAreaExtent.toStringAsFixed(1)} inset_x=${metrics.actionInsetHorizontal.toStringAsFixed(0)} inset_y=${metrics.actionInsetVertical.toStringAsFixed(0)} variant=${metrics.variantName}',
            );
          });
        }

        Widget contextSeparator() {
          return SizedBox(
            height: contextSeparatorExtent,
            child: AnimatedOpacity(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              opacity: widget.showAccountModes ? 1 : 0,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  height: 1,
                  margin: EdgeInsets.symmetric(
                    horizontal: metrics.actionInsetHorizontal + 2,
                  ),
                  color: tokens.borderSubtle,
                ),
              ),
            ),
          );
        }

        Widget fixedChildColumn() {
          return Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in widget.locationChildren)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.actionInsetHorizontal,
                      vertical: metrics.actionInsetVertical,
                    ),
                    child: childRailButton(
                      child,
                      extent: referenceButtonExtent,
                    ),
                  ),
              ],
            ),
          );
        }

        Widget scrollableChildColumn() {
          return Scrollbar(
            controller: _childScrollController,
            thumbVisibility: true,
            thickness: 2,
            radius: const Radius.circular(2),
            child: SingleChildScrollView(
              controller: _childScrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final child in widget.locationChildren)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.actionInsetHorizontal,
                          vertical: metrics.actionInsetVertical,
                        ),
                        child: childRailButton(
                          child,
                          extent: referenceButtonExtent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        final Widget actionArea;
        if (widget.locationChildMode) {
          actionArea = childCount == 0
              ? const SizedBox.expand()
              : childScrollable
                  ? scrollableChildColumn()
                  : fixedChildColumn();
        } else if (globalActionCount == 0) {
          actionArea = const SizedBox.expand();
        } else if (globalScrollable) {
          actionArea = Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            thickness: 2,
            radius: const Radius.circular(2),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: metrics.actionInsetHorizontal,
                          vertical: metrics.actionInsetVertical,
                        ),
                        child: railButton(
                          item,
                          extent: metrics.minimumButtonExtent,
                        ),
                      ),
                    contextSeparator(),
                    accountModeZone(
                      buttonExtent: metrics.minimumButtonExtent,
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          actionArea = Column(
            key: ValueKey<String>(
              'equal_context|${metrics.variantName}|$globalActionCount',
            ),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in items)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.actionInsetHorizontal,
                            vertical: metrics.actionInsetVertical,
                          ),
                          child: railButton(
                            item,
                            extent: referenceButtonExtent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              contextSeparator(),
              accountModeZone(
                buttonExtent: metrics.minimumButtonExtent,
              ),
            ],
          );
        }

        return CommonSideRailSurface(
          title: '운영 관리',
          semanticsLabel:
              widget.locationChildMode ? '자식 주차 구역' : '운영 관리',
          metrics: metrics,
          child: AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              final begin = widget.locationChildMode
                  ? const Offset(.08, 0)
                  : const Offset(-.05, 0);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: begin,
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<String>(
                '${widget.locationChildMode ? 'location_child' : 'global'}|$distribution|${metrics.variantName}|$actionCount',
              ),
              child: actionArea,
            ),
          ),
        );
      },
    );
  }
}

class _SecondaryOperationsWorkspaceMotion extends StatelessWidget {
  const _SecondaryOperationsWorkspaceMotion({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 210),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, animatedChild) {
        return Transform.translate(
          offset: Offset(22 * (1 - value), 0),
          child: Opacity(
            opacity: .90 + (.10 * value),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }
}

class _UserSettingsTableOfContentsRail extends StatelessWidget {
  const _UserSettingsTableOfContentsRail({
    required this.metrics,
    required this.selectedSection,
    required this.sectionStates,
    required this.saving,
    required this.onSelect,
  });

  final CommonSideRailMetrics metrics;
  final UserSettingsSection selectedSection;
  final Map<UserSettingsSection, UserSettingsSectionState> sectionStates;
  final bool saving;
  final ValueChanged<UserSettingsSection> onSelect;

  static const List<_UserSettingsTocItem> _items = <_UserSettingsTocItem>[
    _UserSettingsTocItem(
      section: UserSettingsSection.identity,
      label: '기본',
      icon: Icons.badge_rounded,
    ),
    _UserSettingsTocItem(
      section: UserSettingsSection.permission,
      label: '권한',
      icon: Icons.verified_user_rounded,
    ),
    _UserSettingsTocItem(
      section: UserSettingsSection.position,
      label: '직책',
      icon: Icons.work_rounded,
    ),
    _UserSettingsTocItem(
      section: UserSettingsSection.password,
      label: '암호',
      icon: Icons.lock_rounded,
    ),
    _UserSettingsTocItem(
      section: UserSettingsSection.schedule,
      label: '일정',
      icon: Icons.schedule_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CommonSideRailSurface(
      title: '계정 설정',
      semanticsLabel: '계정 설정 입력 목차',
      metrics: metrics,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 420.0;
          final slot = available / _items.length;
          final scrollable = slot + .5 < metrics.minimumButtonExtent;
          final extent = scrollable
              ? metrics.minimumButtonExtent
              : math.max(
                  metrics.minimumButtonExtent,
                  slot - metrics.actionInsetVertical * 2,
                );
          final buttons = <Widget>[
            for (final item in _items)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.actionInsetHorizontal,
                  vertical: metrics.actionInsetVertical,
                ),
                child: _UserSettingsTocButton(
                  item: item,
                  state: sectionStates[item.section] ??
                      UserSettingsSectionState.incomplete,
                  selected: selectedSection == item.section,
                  enabled: !saving,
                  compact: metrics.compact,
                  extent: extent,
                  onTap: () => onSelect(item.section),
                ),
              ),
          ];
          if (scrollable) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buttons,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final button in buttons) Expanded(child: button),
            ],
          );
        },
      ),
    );
  }
}

class _UserSettingsTocButton extends StatelessWidget {
  const _UserSettingsTocButton({
    required this.item,
    required this.state,
    required this.selected,
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final _UserSettingsTocItem item;
  final UserSettingsSectionState state;
  final bool selected;
  final bool enabled;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = switch (state) {
      UserSettingsSectionState.complete => tokens.success,
      UserSettingsSectionState.incomplete => tokens.warning,
      UserSettingsSectionState.error => tokens.danger,
      UserSettingsSectionState.optional => tokens.textSecondary,
    };
    final statusIcon = switch (state) {
      UserSettingsSectionState.complete => Icons.check_rounded,
      UserSettingsSectionState.incomplete => Icons.priority_high_rounded,
      UserSettingsSectionState.error => Icons.error_outline_rounded,
      UserSettingsSectionState.optional => Icons.remove_rounded,
    };
    final stateLabel = switch (state) {
      UserSettingsSectionState.complete => '입력 완료',
      UserSettingsSectionState.incomplete => '입력 필요',
      UserSettingsSectionState.error => '입력 오류',
      UserSettingsSectionState.optional => '선택 입력',
    };

    return CommonSideRailActionButton(
      semanticLabel: '${item.label}, $stateLabel',
      visualLabel: item.label,
      selected: selected,
      enabled: enabled,
      disabledReason: enabled ? '' : '저장 중에는 목차를 이동할 수 없습니다.',
      compact: compact,
      extent: extent,
      tooltip: '${item.label} · $stateLabel',
      onTap: onTap,
      iconChild: SizedBox(
        width: compact ? 21 : 23,
        height: compact ? 21 : 23,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                item.icon,
                size: compact ? 18 : 19,
                color: selected ? tokens.accent : tokens.iconPrimary,
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: AnimatedScale(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                scale: 1,
                child: AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: tokens.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor, width: 1.4),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: Icon(
                      statusIcon,
                      key: ValueKey<UserSettingsSectionState>(state),
                      size: 9,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSettingsTocItem {
  const _UserSettingsTocItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final UserSettingsSection section;
  final String label;
  final IconData icon;
}

class _TabletSettingsTableOfContentsRail extends StatelessWidget {
  const _TabletSettingsTableOfContentsRail({
    required this.metrics,
    required this.selectedSection,
    required this.sectionStates,
    required this.saving,
    required this.onSelect,
  });

  final CommonSideRailMetrics metrics;
  final TabletSettingsSection selectedSection;
  final Map<TabletSettingsSection, TabletSettingsSectionState> sectionStates;
  final bool saving;
  final ValueChanged<TabletSettingsSection> onSelect;

  static const List<_TabletSettingsTocItem> _items = <_TabletSettingsTocItem>[
    _TabletSettingsTocItem(
      section: TabletSettingsSection.identity,
      label: '식별',
      icon: Icons.tablet_mac_rounded,
    ),
    _TabletSettingsTocItem(
      section: TabletSettingsSection.permission,
      label: '권한',
      icon: Icons.verified_user_rounded,
    ),
    _TabletSettingsTocItem(
      section: TabletSettingsSection.password,
      label: '암호',
      icon: Icons.lock_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CommonSideRailSurface(
      title: '태블릿 설정',
      semanticsLabel: '태블릿 설정 입력 목차',
      metrics: metrics,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 420.0;
          final slot = available / _items.length;
          final scrollable = slot + .5 < metrics.minimumButtonExtent;
          final extent = scrollable
              ? metrics.minimumButtonExtent
              : math.max(
                  metrics.minimumButtonExtent,
                  slot - metrics.actionInsetVertical * 2,
                );
          final buttons = <Widget>[
            for (final item in _items)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.actionInsetHorizontal,
                  vertical: metrics.actionInsetVertical,
                ),
                child: _TabletSettingsTocButton(
                  item: item,
                  state: sectionStates[item.section] ??
                      TabletSettingsSectionState.incomplete,
                  selected: selectedSection == item.section,
                  enabled: !saving,
                  compact: metrics.compact,
                  extent: extent,
                  onTap: () => onSelect(item.section),
                ),
              ),
          ];
          if (scrollable) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buttons,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final button in buttons) Expanded(child: button),
            ],
          );
        },
      ),
    );
  }
}

class _TabletSettingsTocButton extends StatelessWidget {
  const _TabletSettingsTocButton({
    required this.item,
    required this.state,
    required this.selected,
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final _TabletSettingsTocItem item;
  final TabletSettingsSectionState state;
  final bool selected;
  final bool enabled;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = switch (state) {
      TabletSettingsSectionState.complete => tokens.success,
      TabletSettingsSectionState.incomplete => tokens.warning,
      TabletSettingsSectionState.error => tokens.danger,
    };
    final statusIcon = switch (state) {
      TabletSettingsSectionState.complete => Icons.check_rounded,
      TabletSettingsSectionState.incomplete => Icons.priority_high_rounded,
      TabletSettingsSectionState.error => Icons.error_outline_rounded,
    };
    final stateLabel = switch (state) {
      TabletSettingsSectionState.complete => '입력 완료',
      TabletSettingsSectionState.incomplete => '입력 필요',
      TabletSettingsSectionState.error => '입력 오류',
    };

    return CommonSideRailActionButton(
      semanticLabel: '${item.label}, $stateLabel',
      visualLabel: item.label,
      selected: selected,
      enabled: enabled,
      disabledReason: enabled ? '' : '저장 중에는 목차를 이동할 수 없습니다.',
      compact: compact,
      extent: extent,
      tooltip: '${item.label} · $stateLabel',
      onTap: onTap,
      iconChild: SizedBox(
        width: compact ? 21 : 23,
        height: compact ? 21 : 23,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                item.icon,
                size: compact ? 18 : 19,
                color: selected ? tokens.accent : tokens.iconPrimary,
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: AnimatedScale(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                scale: 1,
                child: AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: tokens.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor, width: 1.4),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: Icon(
                      statusIcon,
                      key: ValueKey<TabletSettingsSectionState>(state),
                      size: 9,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletSettingsTocItem {
  const _TabletSettingsTocItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final TabletSettingsSection section;
  final String label;
  final IconData icon;
}

class _MonthlySettingsTableOfContentsRail extends StatelessWidget {
  const _MonthlySettingsTableOfContentsRail({
    required this.metrics,
    required this.selectedSection,
    required this.sectionStates,
    required this.saving,
    required this.paymentMode,
    required this.onSelect,
  });

  final CommonSideRailMetrics metrics;
  final MonthlyWorkspaceSection selectedSection;
  final Map<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState> sectionStates;
  final bool saving;
  final bool paymentMode;
  final ValueChanged<MonthlyWorkspaceSection> onSelect;

  List<_MonthlySettingsTocItem> get _items {
    if (paymentMode) {
      return const <_MonthlySettingsTocItem>[
        _MonthlySettingsTocItem(
          section: MonthlyWorkspaceSection.paymentAmount,
          label: '금액',
          icon: Icons.payments_rounded,
        ),
        _MonthlySettingsTocItem(
          section: MonthlyWorkspaceSection.paymentExtension,
          label: '연장',
          icon: Icons.update_rounded,
        ),
        _MonthlySettingsTocItem(
          section: MonthlyWorkspaceSection.paymentNote,
          label: '메모',
          icon: Icons.edit_note_rounded,
        ),
      ];
    }
    return const <_MonthlySettingsTocItem>[
      _MonthlySettingsTocItem(
        section: MonthlyWorkspaceSection.vehicle,
        label: '차량',
        icon: Icons.directions_car_rounded,
      ),
      _MonthlySettingsTocItem(
        section: MonthlyWorkspaceSection.product,
        label: '상품',
        icon: Icons.receipt_long_rounded,
      ),
      _MonthlySettingsTocItem(
        section: MonthlyWorkspaceSection.period,
        label: '기간',
        icon: Icons.event_available_rounded,
      ),
      _MonthlySettingsTocItem(
        section: MonthlyWorkspaceSection.memo,
        label: '메모',
        icon: Icons.edit_note_rounded,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return CommonSideRailSurface(
      title: paymentMode ? '정기권 결제' : '정기권 설정',
      semanticsLabel: paymentMode ? '정기권 결제 입력 목차' : '정기권 설정 입력 목차',
      metrics: metrics,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 420.0;
          final slot = available / items.length;
          final scrollable = slot + .5 < metrics.minimumButtonExtent;
          final extent = scrollable
              ? metrics.minimumButtonExtent
              : math.max(
                  metrics.minimumButtonExtent,
                  slot - metrics.actionInsetVertical * 2,
                );
          final buttons = <Widget>[
            for (final item in items)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.actionInsetHorizontal,
                  vertical: metrics.actionInsetVertical,
                ),
                child: _MonthlySettingsTocButton(
                  item: item,
                  state: sectionStates[item.section] ??
                      MonthlyWorkspaceSectionState.incomplete,
                  selected: selectedSection == item.section,
                  enabled: !saving,
                  compact: metrics.compact,
                  extent: extent,
                  onTap: () => onSelect(item.section),
                ),
              ),
          ];
          if (scrollable) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buttons,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final button in buttons) Expanded(child: button),
            ],
          );
        },
      ),
    );
  }
}

class _MonthlySettingsTocButton extends StatelessWidget {
  const _MonthlySettingsTocButton({
    required this.item,
    required this.state,
    required this.selected,
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final _MonthlySettingsTocItem item;
  final MonthlyWorkspaceSectionState state;
  final bool selected;
  final bool enabled;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = switch (state) {
      MonthlyWorkspaceSectionState.complete => tokens.success,
      MonthlyWorkspaceSectionState.incomplete => tokens.warning,
      MonthlyWorkspaceSectionState.error => tokens.danger,
      MonthlyWorkspaceSectionState.optional => tokens.info,
    };
    final statusIcon = switch (state) {
      MonthlyWorkspaceSectionState.complete => Icons.check_rounded,
      MonthlyWorkspaceSectionState.incomplete => Icons.priority_high_rounded,
      MonthlyWorkspaceSectionState.error => Icons.error_outline_rounded,
      MonthlyWorkspaceSectionState.optional => Icons.remove_rounded,
    };
    final stateLabel = switch (state) {
      MonthlyWorkspaceSectionState.complete => '입력 완료',
      MonthlyWorkspaceSectionState.incomplete => '입력 필요',
      MonthlyWorkspaceSectionState.error => '입력 오류',
      MonthlyWorkspaceSectionState.optional => '선택 입력',
    };
    return CommonSideRailActionButton(
      semanticLabel: '${item.label}, $stateLabel',
      visualLabel: item.label,
      selected: selected,
      enabled: enabled,
      disabledReason: enabled ? '' : '저장 중에는 목차를 이동할 수 없습니다.',
      compact: compact,
      extent: extent,
      tooltip: '${item.label} · $stateLabel',
      onTap: onTap,
      iconChild: SizedBox(
        width: compact ? 21 : 23,
        height: compact ? 21 : 23,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                item.icon,
                size: compact ? 18 : 19,
                color: selected ? tokens.accent : tokens.iconPrimary,
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 1.4),
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: Icon(
                    statusIcon,
                    key: ValueKey<MonthlyWorkspaceSectionState>(state),
                    size: 9,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlySettingsTocItem {
  const _MonthlySettingsTocItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final MonthlyWorkspaceSection section;
  final String label;
  final IconData icon;
}

class _BillSettingsTableOfContentsRail extends StatelessWidget {
  const _BillSettingsTableOfContentsRail({
    required this.metrics,
    required this.selectedSection,
    required this.sectionStates,
    required this.saving,
    required this.onSelect,
  });

  final CommonSideRailMetrics metrics;
  final BillSettingsSection selectedSection;
  final Map<BillSettingsSection, BillSettingsSectionState> sectionStates;
  final bool saving;
  final ValueChanged<BillSettingsSection> onSelect;

  static const List<_BillSettingsTocItem> _items = <_BillSettingsTocItem>[
    _BillSettingsTocItem(
      section: BillSettingsSection.identity,
      label: '유형',
      icon: Icons.receipt_long_rounded,
    ),
    _BillSettingsTocItem(
      section: BillSettingsSection.pricing,
      label: '요금',
      icon: Icons.calculate_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CommonSideRailSurface(
      title: '정산 설정',
      semanticsLabel: '정산 유형 설정 입력 목차',
      metrics: metrics,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 420.0;
          final slot = available / _items.length;
          final scrollable = slot + .5 < metrics.minimumButtonExtent;
          final extent = scrollable
              ? metrics.minimumButtonExtent
              : math.max(
                  metrics.minimumButtonExtent,
                  slot - metrics.actionInsetVertical * 2,
                );
          final buttons = <Widget>[
            for (final item in _items)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.actionInsetHorizontal,
                  vertical: metrics.actionInsetVertical,
                ),
                child: _BillSettingsTocButton(
                  item: item,
                  state: sectionStates[item.section] ??
                      BillSettingsSectionState.incomplete,
                  selected: selectedSection == item.section,
                  enabled: !saving,
                  compact: metrics.compact,
                  extent: extent,
                  onTap: () => onSelect(item.section),
                ),
              ),
          ];
          if (scrollable) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buttons,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final button in buttons) Expanded(child: button),
            ],
          );
        },
      ),
    );
  }
}

class _BillSettingsTocButton extends StatelessWidget {
  const _BillSettingsTocButton({
    required this.item,
    required this.state,
    required this.selected,
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final _BillSettingsTocItem item;
  final BillSettingsSectionState state;
  final bool selected;
  final bool enabled;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = switch (state) {
      BillSettingsSectionState.complete => tokens.success,
      BillSettingsSectionState.incomplete => tokens.warning,
      BillSettingsSectionState.error => tokens.danger,
    };
    final statusIcon = switch (state) {
      BillSettingsSectionState.complete => Icons.check_rounded,
      BillSettingsSectionState.incomplete => Icons.priority_high_rounded,
      BillSettingsSectionState.error => Icons.error_outline_rounded,
    };
    final stateLabel = switch (state) {
      BillSettingsSectionState.complete => '입력 완료',
      BillSettingsSectionState.incomplete => '입력 필요',
      BillSettingsSectionState.error => '입력 오류',
    };

    return CommonSideRailActionButton(
      semanticLabel: '${item.label}, $stateLabel',
      visualLabel: item.label,
      selected: selected,
      enabled: enabled,
      disabledReason: enabled ? '' : '저장 중에는 목차를 이동할 수 없습니다.',
      compact: compact,
      extent: extent,
      tooltip: '${item.label} · $stateLabel',
      onTap: onTap,
      iconChild: SizedBox(
        width: compact ? 21 : 23,
        height: compact ? 21 : 23,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                item.icon,
                size: compact ? 18 : 19,
                color: selected ? tokens.accent : tokens.iconPrimary,
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: AnimatedScale(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                scale: 1,
                child: AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: tokens.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor, width: 1.4),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    child: Icon(
                      statusIcon,
                      key: ValueKey<BillSettingsSectionState>(state),
                      size: 9,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillSettingsTocItem {
  const _BillSettingsTocItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final BillSettingsSection section;
  final String label;
  final IconData icon;
}

class _SectorSettingsTableOfContentsRail extends StatelessWidget {
  const _SectorSettingsTableOfContentsRail({
    required this.metrics,
    required this.selectedSection,
    required this.sectionStates,
    required this.saving,
    required this.onSelect,
  });

  final CommonSideRailMetrics metrics;
  final SectorSettingsSection selectedSection;
  final Map<SectorSettingsSection, SectorSettingsSectionState> sectionStates;
  final bool saving;
  final ValueChanged<SectorSettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final section = SectorSettingsSection.identity;
    return CommonSideRailSurface(
      title: '섹터 설정',
      semanticsLabel: '섹터 설정 입력 목차',
      metrics: metrics,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.actionInsetHorizontal,
          vertical: metrics.actionInsetVertical,
        ),
        child: _SectorSettingsTocButton(
          state: sectionStates[section] ?? SectorSettingsSectionState.incomplete,
          selected: selectedSection == section,
          enabled: !saving,
          compact: metrics.compact,
          extent: metrics.minimumButtonExtent,
          onTap: () => onSelect(section),
        ),
      ),
    );
  }
}

class _SectorSettingsTocButton extends StatelessWidget {
  const _SectorSettingsTocButton({
    required this.state,
    required this.selected,
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final SectorSettingsSectionState state;
  final bool selected;
  final bool enabled;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = switch (state) {
      SectorSettingsSectionState.complete => tokens.success,
      SectorSettingsSectionState.incomplete => tokens.warning,
      SectorSettingsSectionState.error => tokens.danger,
    };
    final statusIcon = switch (state) {
      SectorSettingsSectionState.complete => Icons.check_rounded,
      SectorSettingsSectionState.incomplete => Icons.priority_high_rounded,
      SectorSettingsSectionState.error => Icons.error_outline_rounded,
    };
    final stateLabel = switch (state) {
      SectorSettingsSectionState.complete => '입력 완료',
      SectorSettingsSectionState.incomplete => '입력 필요',
      SectorSettingsSectionState.error => '입력 오류',
    };

    return CommonSideRailActionButton(
      semanticLabel: '기본, $stateLabel',
      visualLabel: '기본',
      selected: selected,
      enabled: enabled,
      disabledReason: enabled ? '' : '저장 중에는 목차를 이동할 수 없습니다.',
      compact: compact,
      extent: extent,
      tooltip: '기본 · $stateLabel',
      onTap: onTap,
      iconChild: SizedBox(
        width: compact ? 21 : 23,
        height: compact ? 21 : 23,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.hub_rounded,
                size: compact ? 18 : 19,
                color: selected ? tokens.accent : tokens.iconPrimary,
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 1.4),
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  child: Icon(
                    statusIcon,
                    key: ValueKey<SectorSettingsSectionState>(state),
                    size: 8.5,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationParentSettingsTableOfContentsRail extends StatelessWidget {
  const _LocationParentSettingsTableOfContentsRail({
    required this.metrics,
    required this.selectedSection,
    required this.sectionStates,
    required this.saving,
    required this.onSelect,
  });

  final CommonSideRailMetrics metrics;
  final LocationParentSettingsSection selectedSection;
  final Map<LocationParentSettingsSection, LocationParentSettingsSectionState>
      sectionStates;
  final bool saving;
  final ValueChanged<LocationParentSettingsSection> onSelect;

  static const List<_LocationParentSettingsTocItem> _items =
      <_LocationParentSettingsTocItem>[
    _LocationParentSettingsTocItem(
      section: LocationParentSettingsSection.identity,
      label: '기본',
      icon: Icons.location_on_rounded,
    ),
    _LocationParentSettingsTocItem(
      section: LocationParentSettingsSection.size,
      label: '크기',
      icon: Icons.aspect_ratio_rounded,
    ),
    _LocationParentSettingsTocItem(
      section: LocationParentSettingsSection.layout,
      label: '도면',
      icon: Icons.architecture_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CommonSideRailSurface(
      title: '부모구역 설정',
      semanticsLabel: '부모구역 설정 입력 목차',
      metrics: metrics,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.actionInsetHorizontal,
          vertical: metrics.actionInsetVertical,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              _LocationParentSettingsTocButton(
                item: _items[i],
                state: sectionStates[_items[i].section] ??
                    LocationParentSettingsSectionState.incomplete,
                selected: selectedSection == _items[i].section,
                enabled: !saving,
                compact: metrics.compact,
                extent: metrics.minimumButtonExtent,
                onTap: () => onSelect(_items[i].section),
              ),
              if (i != _items.length - 1)
                SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationParentSettingsTocItem {
  const _LocationParentSettingsTocItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final LocationParentSettingsSection section;
  final String label;
  final IconData icon;
}

class _LocationParentSettingsTocButton extends StatelessWidget {
  const _LocationParentSettingsTocButton({
    required this.item,
    required this.state,
    required this.selected,
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final _LocationParentSettingsTocItem item;
  final LocationParentSettingsSectionState state;
  final bool selected;
  final bool enabled;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = switch (state) {
      LocationParentSettingsSectionState.complete => tokens.success,
      LocationParentSettingsSectionState.incomplete => tokens.warning,
      LocationParentSettingsSectionState.error => tokens.danger,
    };
    final statusIcon = switch (state) {
      LocationParentSettingsSectionState.complete => Icons.check_rounded,
      LocationParentSettingsSectionState.incomplete =>
        Icons.priority_high_rounded,
      LocationParentSettingsSectionState.error => Icons.error_outline_rounded,
    };
    final stateLabel = switch (state) {
      LocationParentSettingsSectionState.complete => '입력 완료',
      LocationParentSettingsSectionState.incomplete => '입력 필요',
      LocationParentSettingsSectionState.error => '입력 오류',
    };
    return CommonSideRailActionButton(
      semanticLabel: '${item.label}, $stateLabel',
      visualLabel: item.label,
      selected: selected,
      enabled: enabled,
      disabledReason: enabled ? '' : '저장 중에는 목차를 이동할 수 없습니다.',
      compact: compact,
      extent: extent,
      tooltip: '${item.label} · $stateLabel',
      onTap: onTap,
      iconChild: SizedBox(
        width: compact ? 21 : 23,
        height: compact ? 21 : 23,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                item.icon,
                size: compact ? 18 : 19,
                color: selected ? tokens.accent : tokens.iconPrimary,
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 1.4),
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  child: Icon(
                    statusIcon,
                    key: ValueKey<LocationParentSettingsSectionState>(state),
                    size: 8.5,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationChildSettingsTableOfContentsRail extends StatelessWidget {
  const _LocationChildSettingsTableOfContentsRail({
    required this.metrics,
    required this.selectedSection,
    required this.sectionStates,
    required this.saving,
    required this.onSelect,
  });

  final CommonSideRailMetrics metrics;
  final LocationChildSettingsSection selectedSection;
  final Map<LocationChildSettingsSection, LocationChildSettingsSectionState>
      sectionStates;
  final bool saving;
  final ValueChanged<LocationChildSettingsSection> onSelect;

  static const List<_LocationChildSettingsTocItem> _items =
      <_LocationChildSettingsTocItem>[
    _LocationChildSettingsTocItem(
      section: LocationChildSettingsSection.identity,
      label: '기본',
      icon: Icons.location_on_outlined,
    ),
    _LocationChildSettingsTocItem(
      section: LocationChildSettingsSection.area,
      label: '영역',
      icon: Icons.aspect_ratio_rounded,
    ),
    _LocationChildSettingsTocItem(
      section: LocationChildSettingsSection.exclusion,
      label: '제외',
      icon: Icons.content_cut_rounded,
    ),
    _LocationChildSettingsTocItem(
      section: LocationChildSettingsSection.slots,
      label: '번호',
      icon: Icons.format_list_numbered_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return CommonSideRailSurface(
      title: '자식구역 설정',
      semanticsLabel: '자식구역 설정 입력 목차',
      metrics: metrics,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.actionInsetHorizontal,
          vertical: metrics.actionInsetVertical,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              _LocationChildSettingsTocButton(
                item: _items[i],
                state: sectionStates[_items[i].section] ??
                    LocationChildSettingsSectionState.incomplete,
                selected: selectedSection == _items[i].section,
                enabled: !saving,
                compact: metrics.compact,
                extent: metrics.minimumButtonExtent,
                onTap: () => onSelect(_items[i].section),
              ),
              if (i != _items.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationChildSettingsTocItem {
  const _LocationChildSettingsTocItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final LocationChildSettingsSection section;
  final String label;
  final IconData icon;
}

class _LocationChildSettingsTocButton extends StatelessWidget {
  const _LocationChildSettingsTocButton({
    required this.item,
    required this.state,
    required this.selected,
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final _LocationChildSettingsTocItem item;
  final LocationChildSettingsSectionState state;
  final bool selected;
  final bool enabled;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusColor = switch (state) {
      LocationChildSettingsSectionState.complete => tokens.success,
      LocationChildSettingsSectionState.incomplete => tokens.warning,
      LocationChildSettingsSectionState.error => tokens.danger,
    };
    final statusIcon = switch (state) {
      LocationChildSettingsSectionState.complete => Icons.check_rounded,
      LocationChildSettingsSectionState.incomplete =>
        Icons.priority_high_rounded,
      LocationChildSettingsSectionState.error => Icons.error_outline_rounded,
    };
    final stateLabel = switch (state) {
      LocationChildSettingsSectionState.complete => '입력 완료',
      LocationChildSettingsSectionState.incomplete => '입력 필요',
      LocationChildSettingsSectionState.error => '입력 오류',
    };
    return CommonSideRailActionButton(
      semanticLabel: '${item.label}, $stateLabel',
      visualLabel: item.label,
      selected: selected,
      enabled: enabled,
      disabledReason: enabled ? '' : '저장 중에는 목차를 이동할 수 없습니다.',
      compact: compact,
      extent: extent,
      tooltip: '${item.label} · $stateLabel',
      onTap: onTap,
      iconChild: SizedBox(
        width: compact ? 21 : 23,
        height: compact ? 21 : 23,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Icon(
                item.icon,
                size: compact ? 18 : 19,
                color: selected ? tokens.accent : tokens.iconPrimary,
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 1.4),
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  child: Icon(
                    statusIcon,
                    key: ValueKey<LocationChildSettingsSectionState>(state),
                    size: 8.5,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryAccountModeZone extends StatelessWidget {
  const _SecondaryAccountModeZone({
    required this.visible,
    required this.mode,
    required this.compact,
    required this.buttonExtent,
    required this.horizontalInset,
    required this.verticalInset,
    required this.reduceMotion,
    required this.onSelect,
  });

  final bool visible;
  final SecondaryAccountMode mode;
  final bool compact;
  final double buttonExtent;
  final double horizontalInset;
  final double verticalInset;
  final bool reduceMotion;
  final ValueChanged<SecondaryAccountMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.enter,
        opacity: visible ? 1 : 0,
        child: AnimatedSlide(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          offset: visible ? Offset.zero : const Offset(0, .06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalInset,
                  vertical: verticalInset,
                ),
                child: _SecondaryAccountModeButton(
                  mode: SecondaryAccountMode.operation,
                  selected: mode == SecondaryAccountMode.operation,
                  compact: compact,
                  extent: buttonExtent,
                  onTap: () => onSelect(SecondaryAccountMode.operation),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalInset,
                  vertical: verticalInset,
                ),
                child: _SecondaryAccountModeButton(
                  mode: SecondaryAccountMode.delete,
                  selected: mode == SecondaryAccountMode.delete,
                  compact: compact,
                  extent: buttonExtent,
                  onTap: () => onSelect(SecondaryAccountMode.delete),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryAccountModeButton extends StatefulWidget {
  const _SecondaryAccountModeButton({
    required this.mode,
    required this.selected,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final SecondaryAccountMode mode;
  final bool selected;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  State<_SecondaryAccountModeButton> createState() =>
      _SecondaryAccountModeButtonState();
}

class _SecondaryAccountModeButtonState
    extends State<_SecondaryAccountModeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final deleteMode = widget.mode == SecondaryAccountMode.delete;
    final base = deleteMode ? tokens.danger : tokens.success;
    final container =
        deleteMode ? tokens.dangerContainer : tokens.successContainer;
    final onBase = deleteMode ? tokens.onDanger : tokens.onSuccess;
    final onContainer =
        deleteMode ? tokens.onDangerContainer : tokens.onSuccessContainer;
    final background = widget.selected
        ? base.withOpacity(_pressed ? .88 : 1)
        : container.withOpacity(_pressed ? .92 : .72);
    final foreground = widget.selected ? onBase : onContainer;
    final border = widget.selected ? base : base.withOpacity(.32);
    final icon = deleteMode
        ? Icons.delete_forever_rounded
        : Icons.admin_panel_settings_rounded;
    final label = deleteMode ? '삭제' : '운영';

    return Semantics(
      button: true,
      selected: widget.selected,
      label: '$label 모드',
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        scale: _pressed ? .97 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() => _pressed = value);
            },
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              height: widget.extent,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    scale: widget.selected ? 1.06 : 1,
                    child: Icon(
                      icon,
                      size: widget.compact ? 19 : 20,
                      color: foreground,
                    ),
                  ),
                  SizedBox(height: widget.compact ? 2 : 3),
                  AnimatedDefaultTextStyle(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    curve: CommonUiMotion.standard,
                    style: textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ) ??
                        TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryRailButton extends StatelessWidget {
  const _SecondaryRailButton({
    super.key,
    required this.item,
    required this.selected,
    required this.enabled,
    required this.disabledReason,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final _SecondaryRailItem item;
  final bool selected;
  final bool enabled;
  final String disabledReason;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SecondaryRailActionButton(
      semanticLabel: item.label,
      visualLabel: item.visualLabel,
      icon: item.icon,
      selected: selected,
      enabled: enabled,
      disabledReason: disabledReason,
      compact: compact,
      extent: extent,
      onTap: onTap,
    );
  }
}

class _SecondaryLocationChildRailButton extends StatelessWidget {
  const _SecondaryLocationChildRailButton({
    super.key,
    required this.child,
    required this.selected,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final LocationModel child;
  final bool selected;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: child.locationName,
      child: _SecondaryRailActionButton(
        semanticLabel: '${child.locationName} 자식 주차 구역',
        visualLabel: child.locationName,
        icon: child.isTowerChild
            ? Icons.apartment_rounded
            : Icons.local_parking_rounded,
        selected: selected,
        enabled: true,
        disabledReason: '',
        compact: compact,
        extent: extent,
        onTap: onTap,
      ),
    );
  }
}

class _SecondaryRailActionButton extends StatelessWidget {
  const _SecondaryRailActionButton({
    required this.semanticLabel,
    required this.visualLabel,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.disabledReason,
    required this.compact,
    required this.extent,
    required this.onTap,
  });

  final String semanticLabel;
  final String visualLabel;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final String disabledReason;
  final bool compact;
  final double extent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CommonSideRailActionButton(
      semanticLabel: semanticLabel,
      visualLabel: visualLabel,
      icon: icon,
      selected: selected,
      enabled: enabled,
      disabledReason: disabledReason,
      compact: compact,
      extent: extent,
      onTap: onTap,
    );
  }
}

class _SecondaryRailItem {
  const _SecondaryRailItem({
    required this.section,
    required this.label,
    required this.icon,
    this.displayLabel = '',
  });

  final Section section;
  final String label;
  final String displayLabel;
  final IconData icon;

  String get visualLabel {
    final value = displayLabel.trim();
    return value.isEmpty ? label.trim() : value;
  }
}

class _SecondaryDockDebugLog {
  final List<String> _lines = <String>[];

  void log(String message) {
    final line =
        '[SecondarySideDock][${DateTime.now().toIso8601String()}] $message';
    _lines.add(line);
    if (_lines.length > 200) {
      _lines.removeRange(0, _lines.length - 200);
    }
    debugPrint(line);
  }

  String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  Future<void> showStatus(BuildContext context) async {
    final visible = _lines.length > 40
        ? _lines.sublist(_lines.length - 40)
        : List<String>.from(_lines);
    await StatusDialog.showSuccess(
      context,
      title: '운영 관리 상태',
      description: visible.join('\n'),
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
