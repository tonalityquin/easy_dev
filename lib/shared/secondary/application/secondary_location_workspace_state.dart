import 'package:flutter/foundation.dart';

enum SecondaryLocationView { management, plainSettings, parentSettings, childSettings }

enum LocationPlainSettingsMode { create, edit }

enum LocationPlainSettingsSection { identity, capacity }

enum LocationPlainSettingsSectionState { complete, incomplete, error }

enum LocationParentSettingsMode { create, edit }

enum LocationParentSettingsSection { identity, size, layout }

enum LocationParentSettingsSectionState { complete, incomplete, error }

enum LocationChildSettingsMode { create, edit }

enum LocationChildSettingsSection { identity, area, exclusion, slots }

enum LocationChildSettingsSectionState { complete, incomplete, error }

class SecondaryLocationWorkspaceState extends ChangeNotifier {
  SecondaryLocationWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  SecondaryLocationView _view = SecondaryLocationView.management;
  LocationPlainSettingsMode _plainSettingsMode = LocationPlainSettingsMode.create;
  LocationPlainSettingsSection _activePlainSettingsSection =
      LocationPlainSettingsSection.identity;
  LocationParentSettingsMode _settingsMode = LocationParentSettingsMode.create;
  LocationParentSettingsSection _activeSettingsSection =
      LocationParentSettingsSection.identity;
  LocationChildSettingsMode _childSettingsMode =
      LocationChildSettingsMode.create;
  LocationChildSettingsSection _activeChildSettingsSection =
      LocationChildSettingsSection.identity;
  String? _editingPlainLocationId;
  String? _editingParentId;
  String? _editingChildId;
  String? _childParentId;
  bool _settingsSaving = false;
  bool _settingsDirty = false;
  int _plainSettingsNavigationRequestId = 0;
  int _settingsNavigationRequestId = 0;
  int _childSettingsNavigationRequestId = 0;
  final Map<LocationPlainSettingsSection, LocationPlainSettingsSectionState>
      _plainSectionStates =
      <LocationPlainSettingsSection, LocationPlainSettingsSectionState>{
    LocationPlainSettingsSection.identity:
        LocationPlainSettingsSectionState.incomplete,
    LocationPlainSettingsSection.capacity:
        LocationPlainSettingsSectionState.complete,
  };
  final Map<LocationParentSettingsSection, LocationParentSettingsSectionState>
      _sectionStates =
      <LocationParentSettingsSection, LocationParentSettingsSectionState>{
    LocationParentSettingsSection.identity:
        LocationParentSettingsSectionState.incomplete,
    LocationParentSettingsSection.size:
        LocationParentSettingsSectionState.complete,
    LocationParentSettingsSection.layout:
        LocationParentSettingsSectionState.complete,
  };
  final Map<LocationChildSettingsSection, LocationChildSettingsSectionState>
      _childSectionStates =
      <LocationChildSettingsSection, LocationChildSettingsSectionState>{
    LocationChildSettingsSection.identity:
        LocationChildSettingsSectionState.incomplete,
    LocationChildSettingsSection.area:
        LocationChildSettingsSectionState.incomplete,
    LocationChildSettingsSection.exclusion:
        LocationChildSettingsSectionState.complete,
    LocationChildSettingsSection.slots:
        LocationChildSettingsSectionState.incomplete,
  };
  String? _focusedParentKey;
  String? _focusedParentId;
  String? _focusedParentTitle;
  bool _showOnlySelectedChild = false;
  bool _showSelectedChildSlotNumbers = false;

  SecondaryLocationView get view => _view;
  LocationPlainSettingsMode get plainSettingsMode => _plainSettingsMode;
  LocationPlainSettingsSection get activePlainSettingsSection =>
      _activePlainSettingsSection;
  LocationParentSettingsMode get settingsMode => _settingsMode;
  LocationParentSettingsSection get activeSettingsSection =>
      _activeSettingsSection;
  LocationChildSettingsMode get childSettingsMode => _childSettingsMode;
  LocationChildSettingsSection get activeChildSettingsSection =>
      _activeChildSettingsSection;
  String? get editingPlainLocationId => _editingPlainLocationId;
  String? get editingParentId => _editingParentId;
  String? get editingChildId => _editingChildId;
  String? get childParentId => _childParentId;
  bool get isManagementView => _view == SecondaryLocationView.management;
  bool get isPlainSettingsView => _view == SecondaryLocationView.plainSettings;
  bool get isParentSettingsView =>
      _view == SecondaryLocationView.parentSettings;
  bool get isChildSettingsView => _view == SecondaryLocationView.childSettings;
  bool get isEditingPlainSettings =>
      _plainSettingsMode == LocationPlainSettingsMode.edit;
  bool get isEditingParentSettings =>
      _settingsMode == LocationParentSettingsMode.edit;
  bool get isEditingChildSettings =>
      _childSettingsMode == LocationChildSettingsMode.edit;
  bool get settingsSaving => _settingsSaving;
  bool get settingsDirty => _settingsDirty;
  int get plainSettingsNavigationRequestId =>
      _plainSettingsNavigationRequestId;
  int get settingsNavigationRequestId => _settingsNavigationRequestId;
  int get childSettingsNavigationRequestId =>
      _childSettingsNavigationRequestId;
  Map<LocationPlainSettingsSection, LocationPlainSettingsSectionState>
      get plainSectionStates => Map<LocationPlainSettingsSection,
          LocationPlainSettingsSectionState>.unmodifiable(_plainSectionStates);
  Map<LocationParentSettingsSection, LocationParentSettingsSectionState>
      get sectionStates => Map<LocationParentSettingsSection,
          LocationParentSettingsSectionState>.unmodifiable(_sectionStates);
  Map<LocationChildSettingsSection, LocationChildSettingsSectionState>
      get childSectionStates => Map<LocationChildSettingsSection,
          LocationChildSettingsSectionState>.unmodifiable(_childSectionStates);
  String? get focusedParentKey => _focusedParentKey;
  String? get focusedParentId => _focusedParentId;
  String? get focusedParentTitle => _focusedParentTitle;
  bool get isParentFocus => _focusedParentKey != null;
  bool get showOnlySelectedChild => _showOnlySelectedChild;
  bool get showSelectedChildSlotNumbers => _showSelectedChildSlotNumbers;


  LocationPlainSettingsSectionState plainStateFor(
    LocationPlainSettingsSection section,
  ) {
    return _plainSectionStates[section] ??
        LocationPlainSettingsSectionState.incomplete;
  }

  LocationParentSettingsSectionState stateFor(
    LocationParentSettingsSection section,
  ) {
    return _sectionStates[section] ??
        LocationParentSettingsSectionState.incomplete;
  }

  LocationChildSettingsSectionState childStateFor(
    LocationChildSettingsSection section,
  ) {
    return _childSectionStates[section] ??
        LocationChildSettingsSectionState.incomplete;
  }

  int get incompletePlainSectionCount {
    return _plainSectionStates.values.where((state) {
      return state == LocationPlainSettingsSectionState.incomplete ||
          state == LocationPlainSettingsSectionState.error;
    }).length;
  }

  int get incompleteSectionCount {
    return _sectionStates.values.where((state) {
      return state == LocationParentSettingsSectionState.incomplete ||
          state == LocationParentSettingsSectionState.error;
    }).length;
  }

  int get incompleteChildSectionCount {
    return _childSectionStates.values.where((state) {
      return state == LocationChildSettingsSectionState.incomplete ||
          state == LocationChildSettingsSectionState.error;
    }).length;
  }


  void openCreatePlain({required String source}) {
    _clearParentFocus();
    _view = SecondaryLocationView.plainSettings;
    _plainSettingsMode = LocationPlainSettingsMode.create;
    _settingsMode = LocationParentSettingsMode.create;
    _childSettingsMode = LocationChildSettingsMode.create;
    _activePlainSettingsSection = LocationPlainSettingsSection.identity;
    _activeSettingsSection = LocationParentSettingsSection.identity;
    _activeChildSettingsSection = LocationChildSettingsSection.identity;
    _editingPlainLocationId = null;
    _editingParentId = null;
    _editingChildId = null;
    _childParentId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _plainSettingsNavigationRequestId = 0;
    _settingsNavigationRequestId = 0;
    _childSettingsNavigationRequestId = 0;
    _resetPlainSectionStates(create: true);
    log('plain_settings_opened mode=create source=$source');
    notifyListeners();
  }

  void openEditPlain(
    String locationId, {
    required String source,
  }) {
    final normalizedId = locationId.trim();
    if (normalizedId.isEmpty) {
      log('plain_settings_open_edit_ignored reason=empty_location_id source=$source');
      return;
    }
    _clearParentFocus();
    _view = SecondaryLocationView.plainSettings;
    _plainSettingsMode = LocationPlainSettingsMode.edit;
    _settingsMode = LocationParentSettingsMode.create;
    _childSettingsMode = LocationChildSettingsMode.create;
    _activePlainSettingsSection = LocationPlainSettingsSection.identity;
    _activeSettingsSection = LocationParentSettingsSection.identity;
    _activeChildSettingsSection = LocationChildSettingsSection.identity;
    _editingPlainLocationId = normalizedId;
    _editingParentId = null;
    _editingChildId = null;
    _childParentId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _plainSettingsNavigationRequestId = 0;
    _settingsNavigationRequestId = 0;
    _childSettingsNavigationRequestId = 0;
    _resetPlainSectionStates(create: false);
    log('plain_settings_opened mode=edit locationId=$normalizedId source=$source');
    notifyListeners();
  }

  void openCreateParent({required String source}) {
    _clearParentFocus();
    _view = SecondaryLocationView.parentSettings;
    _settingsMode = LocationParentSettingsMode.create;
    _activeSettingsSection = LocationParentSettingsSection.identity;
    _editingPlainLocationId = null;
    _editingParentId = null;
    _editingChildId = null;
    _childParentId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _plainSettingsNavigationRequestId = 0;
    _settingsNavigationRequestId = 0;
    _childSettingsNavigationRequestId = 0;
    _resetPlainSectionStates(create: true);
    _resetSectionStates(create: true);
    log('parent_settings_opened mode=create source=$source');
    notifyListeners();
  }

  void openEditParent(
    String parentId, {
    required String source,
  }) {
    final normalizedId = parentId.trim();
    if (normalizedId.isEmpty) {
      log('parent_settings_open_edit_ignored reason=empty_parent_id source=$source');
      return;
    }
    _clearParentFocus();
    _view = SecondaryLocationView.parentSettings;
    _settingsMode = LocationParentSettingsMode.edit;
    _activeSettingsSection = LocationParentSettingsSection.identity;
    _editingPlainLocationId = null;
    _editingParentId = normalizedId;
    _editingChildId = null;
    _childParentId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _plainSettingsNavigationRequestId = 0;
    _settingsNavigationRequestId = 0;
    _childSettingsNavigationRequestId = 0;
    _resetPlainSectionStates(create: true);
    _resetSectionStates(create: false);
    log('parent_settings_opened mode=edit parentId=$normalizedId source=$source');
    notifyListeners();
  }

  void openCreateChild({
    required String parentId,
    required String source,
  }) {
    final normalizedParentId = parentId.trim();
    if (normalizedParentId.isEmpty) {
      log('child_settings_open_create_ignored reason=empty_parent_id source=$source');
      return;
    }
    _clearParentFocus();
    _view = SecondaryLocationView.childSettings;
    _childSettingsMode = LocationChildSettingsMode.create;
    _activeChildSettingsSection = LocationChildSettingsSection.identity;
    _editingPlainLocationId = null;
    _editingParentId = null;
    _editingChildId = null;
    _childParentId = normalizedParentId;
    _settingsSaving = false;
    _settingsDirty = false;
    _plainSettingsNavigationRequestId = 0;
    _settingsNavigationRequestId = 0;
    _childSettingsNavigationRequestId = 0;
    _resetPlainSectionStates(create: true);
    _resetChildSectionStates(create: true);
    log('child_settings_opened mode=create parentId=$normalizedParentId source=$source');
    notifyListeners();
  }

  void openEditChild({
    required String childId,
    required String parentId,
    required String source,
  }) {
    final normalizedChildId = childId.trim();
    final normalizedParentId = parentId.trim();
    if (normalizedChildId.isEmpty || normalizedParentId.isEmpty) {
      log('child_settings_open_edit_ignored childId=$normalizedChildId parentId=$normalizedParentId source=$source');
      return;
    }
    _clearParentFocus();
    _view = SecondaryLocationView.childSettings;
    _childSettingsMode = LocationChildSettingsMode.edit;
    _activeChildSettingsSection = LocationChildSettingsSection.identity;
    _editingPlainLocationId = null;
    _editingParentId = null;
    _editingChildId = normalizedChildId;
    _childParentId = normalizedParentId;
    _settingsSaving = false;
    _settingsDirty = false;
    _plainSettingsNavigationRequestId = 0;
    _settingsNavigationRequestId = 0;
    _childSettingsNavigationRequestId = 0;
    _resetPlainSectionStates(create: true);
    _resetChildSectionStates(create: false);
    log('child_settings_opened mode=edit childId=$normalizedChildId parentId=$normalizedParentId source=$source');
    notifyListeners();
  }

  void returnToManagement({required String source}) {
    if (_view == SecondaryLocationView.management) {
      log('management_reselected source=$source');
      return;
    }
    final previousView = _view;
    _view = SecondaryLocationView.management;
    _plainSettingsMode = LocationPlainSettingsMode.create;
    _settingsMode = LocationParentSettingsMode.create;
    _childSettingsMode = LocationChildSettingsMode.create;
    _activePlainSettingsSection = LocationPlainSettingsSection.identity;
    _activeSettingsSection = LocationParentSettingsSection.identity;
    _activeChildSettingsSection = LocationChildSettingsSection.identity;
    _editingPlainLocationId = null;
    _editingParentId = null;
    _editingChildId = null;
    _childParentId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _plainSettingsNavigationRequestId = 0;
    _settingsNavigationRequestId = 0;
    _childSettingsNavigationRequestId = 0;
    _resetPlainSectionStates(create: true);
    _resetSectionStates(create: true);
    _resetChildSectionStates(create: true);
    log('settings_closed view=${previousView.name} source=$source');
    notifyListeners();
  }


  void requestPlainSettingsSection(
    LocationPlainSettingsSection section, {
    required String source,
  }) {
    if (!isPlainSettingsView || _settingsSaving) return;
    _plainSettingsNavigationRequestId += 1;
    _activePlainSettingsSection = section;
    log('plain_settings_section_requested section=${section.name} request=$_plainSettingsNavigationRequestId source=$source');
    notifyListeners();
  }

  void selectPlainSettingsSection(
    LocationPlainSettingsSection section, {
    required String source,
  }) {
    if (!isPlainSettingsView) return;
    if (_activePlainSettingsSection == section) {
      log('plain_settings_section_reselected section=${section.name} source=$source');
      return;
    }
    final previous = _activePlainSettingsSection;
    _activePlainSettingsSection = section;
    log('plain_settings_section_changed from=${previous.name} to=${section.name} source=$source');
    notifyListeners();
  }

  void requestSettingsSection(
    LocationParentSettingsSection section, {
    required String source,
  }) {
    if (!isParentSettingsView || _settingsSaving) return;
    _settingsNavigationRequestId += 1;
    _activeSettingsSection = section;
    log('parent_settings_section_requested section=${section.name} request=$_settingsNavigationRequestId source=$source');
    notifyListeners();
  }

  void selectSettingsSection(
    LocationParentSettingsSection section, {
    required String source,
  }) {
    if (!isParentSettingsView) return;
    if (_activeSettingsSection == section) {
      log('parent_settings_section_reselected section=${section.name} source=$source');
      return;
    }
    final previous = _activeSettingsSection;
    _activeSettingsSection = section;
    log('parent_settings_section_changed from=${previous.name} to=${section.name} source=$source');
    notifyListeners();
  }

  void requestChildSettingsSection(
    LocationChildSettingsSection section, {
    required String source,
  }) {
    if (!isChildSettingsView || _settingsSaving) return;
    _childSettingsNavigationRequestId += 1;
    _activeChildSettingsSection = section;
    log('child_settings_section_requested section=${section.name} request=$_childSettingsNavigationRequestId source=$source');
    notifyListeners();
  }

  void selectChildSettingsSection(
    LocationChildSettingsSection section, {
    required String source,
  }) {
    if (!isChildSettingsView) return;
    if (_activeChildSettingsSection == section) {
      log('child_settings_section_reselected section=${section.name} source=$source');
      return;
    }
    final previous = _activeChildSettingsSection;
    _activeChildSettingsSection = section;
    log('child_settings_section_changed from=${previous.name} to=${section.name} source=$source');
    notifyListeners();
  }


  void updatePlainSectionStates(
    Map<LocationPlainSettingsSection, LocationPlainSettingsSectionState> states, {
    required String source,
  }) {
    var changed = false;
    for (final section in LocationPlainSettingsSection.values) {
      final next = states[section];
      if (next == null || _plainSectionStates[section] == next) continue;
      _plainSectionStates[section] = next;
      changed = true;
    }
    if (!changed) return;
    final summary = LocationPlainSettingsSection.values
        .map((section) => '${section.name}:${plainStateFor(section).name}')
        .join('|');
    log('plain_settings_section_states source=$source $summary');
    notifyListeners();
  }

  void updateSectionStates(
    Map<LocationParentSettingsSection, LocationParentSettingsSectionState>
        states, {
    required String source,
  }) {
    var changed = false;
    for (final section in LocationParentSettingsSection.values) {
      final next = states[section];
      if (next == null || _sectionStates[section] == next) continue;
      _sectionStates[section] = next;
      changed = true;
    }
    if (!changed) return;
    final summary = LocationParentSettingsSection.values
        .map((section) => '${section.name}:${stateFor(section).name}')
        .join('|');
    log('parent_settings_section_states source=$source $summary');
    notifyListeners();
  }

  void updateChildSectionStates(
    Map<LocationChildSettingsSection, LocationChildSettingsSectionState>
        states, {
    required String source,
  }) {
    var changed = false;
    for (final section in LocationChildSettingsSection.values) {
      final next = states[section];
      if (next == null || _childSectionStates[section] == next) continue;
      _childSectionStates[section] = next;
      changed = true;
    }
    if (!changed) return;
    final summary = LocationChildSettingsSection.values
        .map((section) => '${section.name}:${childStateFor(section).name}')
        .join('|');
    log('child_settings_section_states source=$source $summary');
    notifyListeners();
  }

  void setSettingsSaving(
    bool value, {
    required String source,
  }) {
    if (_settingsSaving == value) return;
    _settingsSaving = value;
    log('location_settings_saving value=$value view=${_view.name} source=$source');
    notifyListeners();
  }

  void setSettingsDirty(
    bool value, {
    required String source,
  }) {
    if (_settingsDirty == value) return;
    _settingsDirty = value;
    log('location_settings_dirty value=$value view=${_view.name} source=$source');
    notifyListeners();
  }

  void openParent({
    required String key,
    required String parentId,
    required String title,
    required String source,
  }) {
    if (isPlainSettingsView || isParentSettingsView || isChildSettingsView) {
      log('parent_focus_open_ignored reason=settings_active source=$source');
      return;
    }
    final normalizedKey = key.trim();
    final normalizedParentId = parentId.trim();
    final resolvedParentId = normalizedParentId.isEmpty ? null : normalizedParentId;
    final normalizedTitle = title.trim();
    if (normalizedKey.isEmpty) return;
    final resolvedTitle = normalizedTitle.isEmpty ? normalizedKey : normalizedTitle;
    final changed = _focusedParentKey != normalizedKey ||
        _focusedParentId != resolvedParentId ||
        _focusedParentTitle != resolvedTitle;
    _focusedParentKey = normalizedKey;
    _focusedParentId = resolvedParentId;
    _focusedParentTitle = resolvedTitle;
    _showOnlySelectedChild = false;
    _showSelectedChildSlotNumbers = false;
    log('parent_focus_opened key=$normalizedKey parentId=${_focusedParentId ?? '-'} title=${_focusedParentTitle!} source=$source');
    if (changed) notifyListeners();
  }

  void closeParent({required String source}) {
    final previous = _focusedParentKey;
    if (previous == null) {
      log('parent_focus_close_ignored source=$source');
      return;
    }
    _clearParentFocus();
    log('parent_focus_closed key=$previous source=$source');
    notifyListeners();
  }

  void setShowOnlySelectedChild(bool value, {required String source}) {
    if (_showOnlySelectedChild == value) {
      log('selected_child_only_reselected enabled=$value source=$source');
      return;
    }
    _showOnlySelectedChild = value;
    log('selected_child_only_changed enabled=$value source=$source');
    notifyListeners();
  }

  void setShowSelectedChildSlotNumbers(bool value, {required String source}) {
    if (_showSelectedChildSlotNumbers == value) {
      log('slot_numbers_reselected enabled=$value source=$source');
      return;
    }
    _showSelectedChildSlotNumbers = value;
    log('slot_numbers_changed enabled=$value source=$source');
    notifyListeners();
  }

  void clearChildInspection({required String source}) {
    final changed = _showOnlySelectedChild || _showSelectedChildSlotNumbers;
    _showOnlySelectedChild = false;
    _showSelectedChildSlotNumbers = false;
    log('child_inspection_cleared source=$source');
    if (changed) notifyListeners();
  }

  void reset({required String source}) {
    final changed = _view != SecondaryLocationView.management ||
        _editingPlainLocationId != null ||
        _editingParentId != null ||
        _editingChildId != null ||
        _childParentId != null ||
        _settingsSaving ||
        _settingsDirty ||
        _focusedParentKey != null ||
        _showOnlySelectedChild ||
        _showSelectedChildSlotNumbers;
    final previous = _focusedParentKey;
    _view = SecondaryLocationView.management;
    _plainSettingsMode = LocationPlainSettingsMode.create;
    _settingsMode = LocationParentSettingsMode.create;
    _childSettingsMode = LocationChildSettingsMode.create;
    _activePlainSettingsSection = LocationPlainSettingsSection.identity;
    _activeSettingsSection = LocationParentSettingsSection.identity;
    _activeChildSettingsSection = LocationChildSettingsSection.identity;
    _editingPlainLocationId = null;
    _editingParentId = null;
    _editingChildId = null;
    _childParentId = null;
    _settingsSaving = false;
    _settingsDirty = false;
    _plainSettingsNavigationRequestId = 0;
    _settingsNavigationRequestId = 0;
    _childSettingsNavigationRequestId = 0;
    _clearParentFocus();
    _resetPlainSectionStates(create: true);
    _resetSectionStates(create: true);
    _resetChildSectionStates(create: true);
    log('workspace_reset previous=${previous ?? '-'} source=$source changed=$changed');
    if (changed) notifyListeners();
  }

  void _clearParentFocus() {
    _focusedParentKey = null;
    _focusedParentId = null;
    _focusedParentTitle = null;
    _showOnlySelectedChild = false;
    _showSelectedChildSlotNumbers = false;
  }


  void _resetPlainSectionStates({required bool create}) {
    _plainSectionStates
      ..clear()
      ..addAll(<LocationPlainSettingsSection, LocationPlainSettingsSectionState>{
        LocationPlainSettingsSection.identity: create
            ? LocationPlainSettingsSectionState.incomplete
            : LocationPlainSettingsSectionState.complete,
        LocationPlainSettingsSection.capacity:
            LocationPlainSettingsSectionState.complete,
      });
  }

  void _resetSectionStates({required bool create}) {
    _sectionStates
      ..clear()
      ..addAll(<LocationParentSettingsSection, LocationParentSettingsSectionState>{
        LocationParentSettingsSection.identity: create
            ? LocationParentSettingsSectionState.incomplete
            : LocationParentSettingsSectionState.complete,
        LocationParentSettingsSection.size:
            LocationParentSettingsSectionState.complete,
        LocationParentSettingsSection.layout:
            LocationParentSettingsSectionState.complete,
      });
  }

  void _resetChildSectionStates({required bool create}) {
    _childSectionStates
      ..clear()
      ..addAll(<LocationChildSettingsSection, LocationChildSettingsSectionState>{
        LocationChildSettingsSection.identity: create
            ? LocationChildSettingsSectionState.incomplete
            : LocationChildSettingsSectionState.complete,
        LocationChildSettingsSection.area: create
            ? LocationChildSettingsSectionState.incomplete
            : LocationChildSettingsSectionState.complete,
        LocationChildSettingsSection.exclusion:
            LocationChildSettingsSectionState.complete,
        LocationChildSettingsSection.slots: create
            ? LocationChildSettingsSectionState.incomplete
            : LocationChildSettingsSectionState.complete,
      });
  }

  void log(String message) {
    final output = 'location_workspace $message';
    final logger = _onDebug;
    if (logger != null) {
      logger(output);
      return;
    }
    debugPrint('[SecondaryLocationWorkspace] $output');
  }
}
