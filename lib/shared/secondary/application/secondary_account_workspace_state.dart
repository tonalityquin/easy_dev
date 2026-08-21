import 'package:flutter/foundation.dart';

enum SecondaryAccountMode { operation, delete }

enum SecondaryAccountView { management, settings }

enum UserSettingsMode { create, edit }

enum UserSettingsSection { identity, permission, position, password, schedule }

enum UserSettingsSectionState { complete, incomplete, error, optional }

class SecondaryAccountWorkspaceState extends ChangeNotifier {
  SecondaryAccountWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  SecondaryAccountMode _mode = SecondaryAccountMode.operation;
  SecondaryAccountView _view = SecondaryAccountView.management;
  UserSettingsMode _settingsMode = UserSettingsMode.create;
  UserSettingsSection _activeSettingsSection = UserSettingsSection.identity;
  String? _editingUserId;
  bool _settingsSaving = false;
  bool _settingsDirty = false;
  int _settingsNavigationRequestId = 0;
  final Map<UserSettingsSection, UserSettingsSectionState> _sectionStates =
      <UserSettingsSection, UserSettingsSectionState>{
    UserSettingsSection.identity: UserSettingsSectionState.incomplete,
    UserSettingsSection.permission: UserSettingsSectionState.complete,
    UserSettingsSection.position: UserSettingsSectionState.optional,
    UserSettingsSection.password: UserSettingsSectionState.complete,
    UserSettingsSection.schedule: UserSettingsSectionState.complete,
  };

  SecondaryAccountMode get mode => _mode;
  SecondaryAccountView get view => _view;
  UserSettingsMode get settingsMode => _settingsMode;
  UserSettingsSection get activeSettingsSection => _activeSettingsSection;
  String? get editingUserId => _editingUserId;
  bool get isDeleteMode => _mode == SecondaryAccountMode.delete;
  bool get isManagementView => _view == SecondaryAccountView.management;
  bool get isSettingsView => _view == SecondaryAccountView.settings;
  bool get isEditingSettings => _settingsMode == UserSettingsMode.edit;
  bool get settingsSaving => _settingsSaving;
  bool get settingsDirty => _settingsDirty;
  int get settingsNavigationRequestId => _settingsNavigationRequestId;
  Map<UserSettingsSection, UserSettingsSectionState> get sectionStates =>
      Map<UserSettingsSection, UserSettingsSectionState>.unmodifiable(
        _sectionStates,
      );

  UserSettingsSectionState stateFor(UserSettingsSection section) {
    return _sectionStates[section] ?? UserSettingsSectionState.incomplete;
  }

  int get incompleteSectionCount {
    return _sectionStates.values.where((state) {
      return state == UserSettingsSectionState.incomplete ||
          state == UserSettingsSectionState.error;
    }).length;
  }

  void setMode(
    SecondaryAccountMode mode, {
    required String source,
  }) {
    if (_view != SecondaryAccountView.management) {
      log('mode_change_blocked view=${_view.name} mode=${mode.name} source=$source');
      return;
    }
    if (_mode == mode) {
      log('mode_reselected mode=${mode.name} source=$source');
      return;
    }
    final previous = _mode;
    _mode = mode;
    log('mode_changed from=${previous.name} to=${mode.name} source=$source');
    notifyListeners();
  }

  void openCreate({required String source}) {
    _view = SecondaryAccountView.settings;
    _settingsMode = UserSettingsMode.create;
    _editingUserId = null;
    _activeSettingsSection = UserSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates(create: true);
    log('settings_opened mode=create source=$source');
    notifyListeners();
  }

  void openEdit(
    String userId, {
    required String source,
  }) {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      log('settings_edit_blocked reason=empty_user_id source=$source');
      return;
    }
    _view = SecondaryAccountView.settings;
    _settingsMode = UserSettingsMode.edit;
    _editingUserId = normalized;
    _activeSettingsSection = UserSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates(create: false);
    log('settings_opened mode=edit userId=$normalized source=$source');
    notifyListeners();
  }

  void returnToManagement({required String source}) {
    if (_view == SecondaryAccountView.management) {
      log('management_reselected source=$source');
      return;
    }
    final previousMode = _settingsMode;
    final previousUserId = _editingUserId;
    _view = SecondaryAccountView.management;
    _settingsMode = UserSettingsMode.create;
    _editingUserId = null;
    _activeSettingsSection = UserSettingsSection.identity;
    _settingsSaving = false;
    _settingsDirty = false;
    _settingsNavigationRequestId = 0;
    _resetSectionStates(create: true);
    log(
      'settings_closed previousMode=${previousMode.name} userId=${previousUserId ?? '-'} source=$source',
    );
    notifyListeners();
  }

  void requestSettingsSection(
    UserSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondaryAccountView.settings || _settingsSaving) return;
    _settingsNavigationRequestId += 1;
    final previous = _activeSettingsSection;
    _activeSettingsSection = section;
    log(
      'settings_section_requested from=${previous.name} to=${section.name} request=$_settingsNavigationRequestId source=$source',
    );
    notifyListeners();
  }

  void selectSettingsSection(
    UserSettingsSection section, {
    required String source,
  }) {
    if (_view != SecondaryAccountView.settings) return;
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

  void updateSectionState(
    UserSettingsSection section,
    UserSettingsSectionState state, {
    required String source,
  }) {
    if (_sectionStates[section] == state) return;
    final previous = _sectionStates[section];
    _sectionStates[section] = state;
    log(
      'settings_section_state section=${section.name} from=${previous?.name ?? '-'} to=${state.name} source=$source',
    );
    notifyListeners();
  }

  void updateSectionStates(
    Map<UserSettingsSection, UserSettingsSectionState> states, {
    required String source,
  }) {
    var changed = false;
    for (final section in UserSettingsSection.values) {
      final next = states[section];
      if (next == null || _sectionStates[section] == next) continue;
      _sectionStates[section] = next;
      changed = true;
    }
    if (!changed) return;
    final summary = UserSettingsSection.values
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
    final changed = _mode != SecondaryAccountMode.operation ||
        _view != SecondaryAccountView.management ||
        _editingUserId != null ||
        _settingsSaving ||
        _settingsDirty;
    _mode = SecondaryAccountMode.operation;
    _view = SecondaryAccountView.management;
    _settingsMode = UserSettingsMode.create;
    _editingUserId = null;
    _activeSettingsSection = UserSettingsSection.identity;
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
      ..addAll(<UserSettingsSection, UserSettingsSectionState>{
        UserSettingsSection.identity: create
            ? UserSettingsSectionState.incomplete
            : UserSettingsSectionState.complete,
        UserSettingsSection.permission: UserSettingsSectionState.complete,
        UserSettingsSection.position: UserSettingsSectionState.optional,
        UserSettingsSection.password: UserSettingsSectionState.complete,
        UserSettingsSection.schedule: UserSettingsSectionState.complete,
      });
  }

  void log(String message) {
    final output = 'account_workspace $message';
    final logger = _onDebug;
    if (logger != null) {
      logger(output);
      return;
    }
    debugPrint('[SecondaryAccountWorkspace] $output');
  }
}
