import 'package:flutter/foundation.dart';

enum SecondaryRuleView { management, settings }

enum RuleSettingsMode { create, edit }

enum RuleSettingsSection { checklist, content }

enum RuleSettingsSectionState { complete, unused, incomplete, error }

class SecondaryRuleWorkspaceState extends ChangeNotifier {
  SecondaryRuleWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  SecondaryRuleView _view = SecondaryRuleView.management;
  RuleSettingsMode _settingsMode = RuleSettingsMode.create;
  RuleSettingsSection _activeSettingsSection = RuleSettingsSection.checklist;
  bool _settingsSaving = false;
  bool _settingsDirty = false;
  int _settingsNavigationRequestId = 0;
  final Map<RuleSettingsSection, RuleSettingsSectionState> _sectionStates =
      <RuleSettingsSection, RuleSettingsSectionState>{
    RuleSettingsSection.checklist: RuleSettingsSectionState.unused,
    RuleSettingsSection.content: RuleSettingsSectionState.unused,
  };

  SecondaryRuleView get view => _view;
  RuleSettingsMode get settingsMode => _settingsMode;
  RuleSettingsSection get activeSettingsSection => _activeSettingsSection;
  bool get isManagementView => _view == SecondaryRuleView.management;
  bool get isSettingsView => _view == SecondaryRuleView.settings;
  bool get isEditingSettings => _settingsMode == RuleSettingsMode.edit;
  bool get settingsSaving => _settingsSaving;
  bool get settingsDirty => _settingsDirty;
  int get settingsNavigationRequestId => _settingsNavigationRequestId;
  Map<RuleSettingsSection, RuleSettingsSectionState> get sectionStates =>
      Map<RuleSettingsSection, RuleSettingsSectionState>.unmodifiable(
        _sectionStates,
      );

  RuleSettingsSectionState stateFor(RuleSettingsSection section) {
    return _sectionStates[section] ?? RuleSettingsSectionState.unused;
  }

  int get incompleteSectionCount => _sectionStates.values.where((state) {
        return state == RuleSettingsSectionState.incomplete ||
            state == RuleSettingsSectionState.error;
      }).length;

  void openCreate({required String source}) {
    _view = SecondaryRuleView.settings;
    _settingsMode = RuleSettingsMode.create;
    _activeSettingsSection = RuleSettingsSection.checklist;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('settings_opened mode=create source=$source');
    notifyListeners();
  }

  void openEdit({required String source}) {
    _view = SecondaryRuleView.settings;
    _settingsMode = RuleSettingsMode.edit;
    _activeSettingsSection = RuleSettingsSection.checklist;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('settings_opened mode=edit source=$source');
    notifyListeners();
  }

  void returnToManagement({required String source}) {
    if (_view == SecondaryRuleView.management) {
      log('management_reselected source=$source');
      return;
    }
    _view = SecondaryRuleView.management;
    _settingsMode = RuleSettingsMode.create;
    _activeSettingsSection = RuleSettingsSection.checklist;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates();
    log('settings_closed source=$source');
    notifyListeners();
  }

  void requestSettingsSection(
    RuleSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondaryRuleView.settings || _settingsSaving) return;
    _settingsNavigationRequestId += 1;
    _activeSettingsSection = section;
    log(
      'settings_section_requested section=${section.name} request=$_settingsNavigationRequestId source=$source',
    );
    notifyListeners();
  }

  void selectSettingsSection(
    RuleSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondaryRuleView.settings) return;
    if (_activeSettingsSection == section) return;
    final previous = _activeSettingsSection;
    _activeSettingsSection = section;
    log(
      'settings_section_changed from=${previous.name} to=${section.name} source=$source',
    );
    notifyListeners();
  }

  void updateSectionStates(
    Map<RuleSettingsSection, RuleSettingsSectionState> states, {
    required String source,
  }) {
    var changed = false;
    for (final section in RuleSettingsSection.values) {
      final next = states[section];
      if (next == null || _sectionStates[section] == next) continue;
      _sectionStates[section] = next;
      changed = true;
    }
    if (!changed) return;
    log(
      'settings_section_states source=$source ${RuleSettingsSection.values.map((section) => '${section.name}:${stateFor(section).name}').join('|')}',
    );
    notifyListeners();
  }

  void setSettingsSaving(bool value, {required String source}) {
    if (_settingsSaving == value) return;
    _settingsSaving = value;
    log('settings_saving value=$value source=$source');
    notifyListeners();
  }

  void setSettingsDirty(bool value, {required String source}) {
    if (_settingsDirty == value) return;
    _settingsDirty = value;
    log('settings_dirty value=$value source=$source');
    notifyListeners();
  }

  void reset({required String source}) {
    final changed = _view != SecondaryRuleView.management ||
        _settingsSaving ||
        _settingsDirty;
    _view = SecondaryRuleView.management;
    _settingsMode = RuleSettingsMode.create;
    _activeSettingsSection = RuleSettingsSection.checklist;
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
      ..addAll(<RuleSettingsSection, RuleSettingsSectionState>{
        RuleSettingsSection.checklist: RuleSettingsSectionState.unused,
        RuleSettingsSection.content: RuleSettingsSectionState.unused,
      });
  }

  void log(String message) {
    final output = 'rule_workspace $message';
    final logger = _onDebug;
    if (logger != null) {
      logger(output);
      return;
    }
    debugPrint('[SecondaryRuleWorkspace] $output');
  }
}
