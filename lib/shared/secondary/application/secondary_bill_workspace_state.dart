import 'package:flutter/foundation.dart';

enum SecondaryBillView { management, settings }

enum BillSettingsSection { identity, pricing }

enum BillSettingsSectionState { complete, incomplete, error }

class SecondaryBillWorkspaceState extends ChangeNotifier {
  SecondaryBillWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  SecondaryBillView _view = SecondaryBillView.management;
  BillSettingsSection _activeSettingsSection = BillSettingsSection.identity;
  bool _settingsSaving = false;
  bool _settingsDirty = false;
  int _settingsNavigationRequestId = 0;
  final Map<BillSettingsSection, BillSettingsSectionState> _sectionStates =
      <BillSettingsSection, BillSettingsSectionState>{
    BillSettingsSection.identity: BillSettingsSectionState.incomplete,
    BillSettingsSection.pricing: BillSettingsSectionState.incomplete,
  };

  SecondaryBillView get view => _view;
  BillSettingsSection get activeSettingsSection => _activeSettingsSection;
  bool get isManagementView => _view == SecondaryBillView.management;
  bool get isSettingsView => _view == SecondaryBillView.settings;
  bool get settingsSaving => _settingsSaving;
  bool get settingsDirty => _settingsDirty;
  int get settingsNavigationRequestId => _settingsNavigationRequestId;
  Map<BillSettingsSection, BillSettingsSectionState> get sectionStates =>
      Map<BillSettingsSection, BillSettingsSectionState>.unmodifiable(
        _sectionStates,
      );

  BillSettingsSectionState stateFor(BillSettingsSection section) {
    return _sectionStates[section] ?? BillSettingsSectionState.incomplete;
  }

  int get incompleteSectionCount {
    return _sectionStates.values.where((state) {
      return state == BillSettingsSectionState.incomplete ||
          state == BillSettingsSectionState.error;
    }).length;
  }

  void openCreate({required String source}) {
    _view = SecondaryBillView.settings;
    _activeSettingsSection = BillSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('settings_opened mode=create source=$source');
    notifyListeners();
  }

  void returnToManagement({required String source}) {
    if (_view == SecondaryBillView.management) {
      log('management_reselected source=$source');
      return;
    }
    _view = SecondaryBillView.management;
    _activeSettingsSection = BillSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('settings_closed source=$source');
    notifyListeners();
  }

  void requestSettingsSection(
    BillSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondaryBillView.settings || _settingsSaving) return;
    _settingsNavigationRequestId += 1;
    final previous = _activeSettingsSection;
    _activeSettingsSection = section;
    log(
      'settings_section_requested from=${previous.name} to=${section.name} request=$_settingsNavigationRequestId source=$source',
    );
    notifyListeners();
  }

  void selectSettingsSection(
    BillSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondaryBillView.settings) return;
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
    Map<BillSettingsSection, BillSettingsSectionState> states, {
    required String source,
  }) {
    var changed = false;
    for (final section in BillSettingsSection.values) {
      final next = states[section];
      if (next == null || _sectionStates[section] == next) continue;
      _sectionStates[section] = next;
      changed = true;
    }
    if (!changed) return;
    final summary = BillSettingsSection.values
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
    final changed = _view != SecondaryBillView.management ||
        _settingsSaving ||
        _settingsDirty;
    _view = SecondaryBillView.management;
    _activeSettingsSection = BillSettingsSection.identity;
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
      ..addAll(<BillSettingsSection, BillSettingsSectionState>{
        BillSettingsSection.identity: BillSettingsSectionState.incomplete,
        BillSettingsSection.pricing: BillSettingsSectionState.incomplete,
      });
  }

  void log(String message) {
    final output = 'bill_workspace $message';
    final logger = _onDebug;
    if (logger != null) {
      logger(output);
      return;
    }
    debugPrint('[SecondaryBillWorkspace] $output');
  }
}
