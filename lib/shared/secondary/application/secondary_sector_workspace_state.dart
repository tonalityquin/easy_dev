import 'package:flutter/foundation.dart';

enum SecondarySectorView { management, settings }

enum SectorSettingsMode { create, edit }

enum SectorSettingsSection { identity }

enum SectorSettingsSectionState { complete, incomplete, error }

class SecondarySectorWorkspaceState extends ChangeNotifier {
  SecondarySectorWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  SecondarySectorView _view = SecondarySectorView.management;
  SectorSettingsMode _settingsMode = SectorSettingsMode.create;
  SectorSettingsSection _activeSettingsSection = SectorSettingsSection.identity;
  String? _editingSectorId;
  bool _settingsSaving = false;
  bool _settingsDirty = false;
  int _settingsNavigationRequestId = 0;
  final Map<SectorSettingsSection, SectorSettingsSectionState> _sectionStates =
      <SectorSettingsSection, SectorSettingsSectionState>{
    SectorSettingsSection.identity: SectorSettingsSectionState.incomplete,
  };

  SecondarySectorView get view => _view;
  SectorSettingsMode get settingsMode => _settingsMode;
  SectorSettingsSection get activeSettingsSection => _activeSettingsSection;
  String? get editingSectorId => _editingSectorId;
  bool get isManagementView => _view == SecondarySectorView.management;
  bool get isSettingsView => _view == SecondarySectorView.settings;
  bool get isEditingSettings => _settingsMode == SectorSettingsMode.edit;
  bool get settingsSaving => _settingsSaving;
  bool get settingsDirty => _settingsDirty;
  int get settingsNavigationRequestId => _settingsNavigationRequestId;
  Map<SectorSettingsSection, SectorSettingsSectionState> get sectionStates =>
      Map<SectorSettingsSection, SectorSettingsSectionState>.unmodifiable(
        _sectionStates,
      );

  SectorSettingsSectionState stateFor(SectorSettingsSection section) {
    return _sectionStates[section] ?? SectorSettingsSectionState.incomplete;
  }

  int get incompleteSectionCount {
    return _sectionStates.values.where((state) {
      return state == SectorSettingsSectionState.incomplete ||
          state == SectorSettingsSectionState.error;
    }).length;
  }

  void openCreate({required String source}) {
    _view = SecondarySectorView.settings;
    _settingsMode = SectorSettingsMode.create;
    _activeSettingsSection = SectorSettingsSection.identity;
    _editingSectorId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('settings_opened mode=create source=$source');
    notifyListeners();
  }

  void openEdit(
    String sectorId, {
    required String source,
  }) {
    final normalizedId = sectorId.trim();
    if (normalizedId.isEmpty) {
      log('settings_open_edit_ignored reason=empty_sector_id source=$source');
      return;
    }
    _view = SecondarySectorView.settings;
    _settingsMode = SectorSettingsMode.edit;
    _activeSettingsSection = SectorSettingsSection.identity;
    _editingSectorId = normalizedId;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('settings_opened mode=edit sectorId=$normalizedId source=$source');
    notifyListeners();
  }

  void returnToManagement({required String source}) {
    if (_view == SecondarySectorView.management) {
      log('management_reselected source=$source');
      return;
    }
    _view = SecondarySectorView.management;
    _settingsMode = SectorSettingsMode.create;
    _activeSettingsSection = SectorSettingsSection.identity;
    _editingSectorId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('settings_closed source=$source');
    notifyListeners();
  }

  void requestSettingsSection(
    SectorSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondarySectorView.settings || _settingsSaving) return;
    _settingsNavigationRequestId += 1;
    _activeSettingsSection = section;
    log(
      'settings_section_requested section=${section.name} request=$_settingsNavigationRequestId source=$source',
    );
    notifyListeners();
  }

  void selectSettingsSection(
    SectorSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondarySectorView.settings) return;
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
    Map<SectorSettingsSection, SectorSettingsSectionState> states, {
    required String source,
  }) {
    var changed = false;
    for (final section in SectorSettingsSection.values) {
      final next = states[section];
      if (next == null || _sectionStates[section] == next) continue;
      _sectionStates[section] = next;
      changed = true;
    }
    if (!changed) return;
    final summary = SectorSettingsSection.values
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
    final changed = _view != SecondarySectorView.management ||
        _editingSectorId != null ||
        _settingsSaving ||
        _settingsDirty;
    _view = SecondarySectorView.management;
    _settingsMode = SectorSettingsMode.create;
    _activeSettingsSection = SectorSettingsSection.identity;
    _editingSectorId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('workspace_reset source=$source changed=$changed');
    if (changed) notifyListeners();
  }

  void _resetSectionStates() {
    _sectionStates
      ..clear()
      ..addAll(<SectorSettingsSection, SectorSettingsSectionState>{
        SectorSettingsSection.identity: SectorSettingsSectionState.incomplete,
      });
  }

  void log(String message) {
    final output = 'sector_workspace $message';
    final logger = _onDebug;
    if (logger != null) {
      logger(output);
      return;
    }
    debugPrint('[SecondarySectorWorkspace] $output');
  }
}
