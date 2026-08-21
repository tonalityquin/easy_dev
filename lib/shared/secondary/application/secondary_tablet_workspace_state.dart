import 'package:flutter/foundation.dart';

enum SecondaryTabletView { management, settings }

enum TabletSettingsMode { create, edit }

enum TabletSettingsSection { identity, permission, password }

enum TabletSettingsSectionState { complete, incomplete, error }

class SecondaryTabletWorkspaceState extends ChangeNotifier {
  SecondaryTabletWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  SecondaryTabletView _view = SecondaryTabletView.management;
  TabletSettingsMode _settingsMode = TabletSettingsMode.create;
  TabletSettingsSection _activeSettingsSection = TabletSettingsSection.identity;
  String? _editingTabletId;
  bool _settingsSaving = false;
  bool _settingsDirty = false;
  int _settingsNavigationRequestId = 0;
  final Map<TabletSettingsSection, TabletSettingsSectionState> _sectionStates =
      <TabletSettingsSection, TabletSettingsSectionState>{
    TabletSettingsSection.identity: TabletSettingsSectionState.incomplete,
    TabletSettingsSection.permission: TabletSettingsSectionState.complete,
    TabletSettingsSection.password: TabletSettingsSectionState.complete,
  };

  SecondaryTabletView get view => _view;
  TabletSettingsMode get settingsMode => _settingsMode;
  TabletSettingsSection get activeSettingsSection => _activeSettingsSection;
  String? get editingTabletId => _editingTabletId;
  bool get isManagementView => _view == SecondaryTabletView.management;
  bool get isSettingsView => _view == SecondaryTabletView.settings;
  bool get isEditingSettings => _settingsMode == TabletSettingsMode.edit;
  bool get settingsSaving => _settingsSaving;
  bool get settingsDirty => _settingsDirty;
  int get settingsNavigationRequestId => _settingsNavigationRequestId;
  Map<TabletSettingsSection, TabletSettingsSectionState> get sectionStates =>
      Map<TabletSettingsSection, TabletSettingsSectionState>.unmodifiable(
        _sectionStates,
      );

  TabletSettingsSectionState stateFor(TabletSettingsSection section) {
    return _sectionStates[section] ?? TabletSettingsSectionState.incomplete;
  }

  int get incompleteSectionCount {
    return _sectionStates.values.where((state) {
      return state == TabletSettingsSectionState.incomplete ||
          state == TabletSettingsSectionState.error;
    }).length;
  }

  void openCreate({required String source}) {
    _view = SecondaryTabletView.settings;
    _settingsMode = TabletSettingsMode.create;
    _editingTabletId = null;
    _activeSettingsSection = TabletSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates(create: true);
    log('settings_opened mode=create source=$source');
    notifyListeners();
  }

  void openEdit(
    String tabletId, {
    required String source,
  }) {
    final normalized = tabletId.trim();
    if (normalized.isEmpty) {
      log('settings_edit_blocked reason=empty_tablet_id source=$source');
      return;
    }
    _view = SecondaryTabletView.settings;
    _settingsMode = TabletSettingsMode.edit;
    _editingTabletId = normalized;
    _activeSettingsSection = TabletSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates(create: false);
    log('settings_opened mode=edit source=$source');
    notifyListeners();
  }

  void returnToManagement({required String source}) {
    if (_view == SecondaryTabletView.management) {
      log('management_reselected source=$source');
      return;
    }
    final previousMode = _settingsMode;
    _view = SecondaryTabletView.management;
    _settingsMode = TabletSettingsMode.create;
    _editingTabletId = null;
    _activeSettingsSection = TabletSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates(create: true);
    log('settings_closed previousMode=${previousMode.name} source=$source');
    notifyListeners();
  }

  void requestSettingsSection(
    TabletSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondaryTabletView.settings || _settingsSaving) return;
    _settingsNavigationRequestId += 1;
    final previous = _activeSettingsSection;
    _activeSettingsSection = section;
    log(
      'settings_section_requested from=${previous.name} to=${section.name} request=$_settingsNavigationRequestId source=$source',
    );
    notifyListeners();
  }

  void selectSettingsSection(
    TabletSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondaryTabletView.settings) return;
    if (_activeSettingsSection == section) {
      log('settings_section_reselected section=${section.name} source=$source');
      return;
    }
    final previous = _activeSettingsSection;
    _activeSettingsSection = section;
    log(
      'settings_section_changed from=${previous.name} to=${section.name} source=$source',
    );
    notifyListeners();
  }

  void updateSectionStates(
    Map<TabletSettingsSection, TabletSettingsSectionState> states, {
    required String source,
  }) {
    var changed = false;
    for (final section in TabletSettingsSection.values) {
      final next = states[section];
      if (next == null || _sectionStates[section] == next) continue;
      _sectionStates[section] = next;
      changed = true;
    }
    if (!changed) return;
    final summary = TabletSettingsSection.values
        .map((section) => '${section.name}:${stateFor(section).name}')
        .join('|');
    log('settings_section_states source=$source $summary');
    notifyListeners();
  }

  void setSettingsSaving(
    bool value, {
    required String source,
  }) {
    if (_settingsSaving == value) return;
    _settingsSaving = value;
    log('settings_saving value=$value source=$source');
    notifyListeners();
  }

  void setSettingsDirty(
    bool value, {
    required String source,
  }) {
    if (_settingsDirty == value) return;
    _settingsDirty = value;
    log('settings_dirty value=$value source=$source');
    notifyListeners();
  }

  void reset({required String source}) {
    final changed = _view != SecondaryTabletView.management ||
        _editingTabletId != null ||
        _settingsSaving ||
        _settingsDirty;
    _view = SecondaryTabletView.management;
    _settingsMode = TabletSettingsMode.create;
    _editingTabletId = null;
    _activeSettingsSection = TabletSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates(create: true);
    log('workspace_reset source=$source changed=$changed');
    if (changed) notifyListeners();
  }

  void _resetSectionStates({required bool create}) {
    _sectionStates
      ..clear()
      ..addAll(<TabletSettingsSection, TabletSettingsSectionState>{
        TabletSettingsSection.identity: create
            ? TabletSettingsSectionState.incomplete
            : TabletSettingsSectionState.complete,
        TabletSettingsSection.permission: TabletSettingsSectionState.complete,
        TabletSettingsSection.password: TabletSettingsSectionState.complete,
      });
  }

  void log(String message) {
    final output = 'tablet_workspace $message';
    final logger = _onDebug;
    if (logger != null) {
      logger(output);
      return;
    }
    debugPrint('[SecondaryTabletWorkspace] $output');
  }
}
