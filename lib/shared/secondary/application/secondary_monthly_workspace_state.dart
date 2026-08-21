import 'package:flutter/foundation.dart';

enum SecondaryMonthlyView { management, settings, payment }

enum MonthlySettingsMode { create, edit }

enum MonthlyWorkspaceSection {
  vehicle,
  product,
  period,
  memo,
  paymentAmount,
  paymentExtension,
  paymentNote,
}

enum MonthlyWorkspaceSectionState { complete, incomplete, error, optional }

class SecondaryMonthlyWorkspaceState extends ChangeNotifier {
  SecondaryMonthlyWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  SecondaryMonthlyView _view = SecondaryMonthlyView.management;
  MonthlySettingsMode _settingsMode = MonthlySettingsMode.create;
  MonthlyWorkspaceSection _activeSection = MonthlyWorkspaceSection.vehicle;
  bool _saving = false;
  bool _dirty = false;
  int _navigationRequestId = 0;
  int _managementRevision = 0;
  String? _editingDocId;
  String? _paymentDocId;
  Map<String, dynamic>? _initialData;
  final Map<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState> _states =
      <MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>{};

  SecondaryMonthlyView get view => _view;
  MonthlySettingsMode get settingsMode => _settingsMode;
  MonthlyWorkspaceSection get activeSection => _activeSection;
  bool get isManagementView => _view == SecondaryMonthlyView.management;
  bool get isSettingsView => _view == SecondaryMonthlyView.settings;
  bool get isPaymentView => _view == SecondaryMonthlyView.payment;
  bool get isEditingSettings =>
      isSettingsView && _settingsMode == MonthlySettingsMode.edit;
  bool get saving => _saving;
  bool get dirty => _dirty;
  int get navigationRequestId => _navigationRequestId;
  int get managementRevision => _managementRevision;
  String? get editingDocId => _editingDocId;
  String? get paymentDocId => _paymentDocId;
  Map<String, dynamic>? get initialData => _initialData == null
      ? null
      : Map<String, dynamic>.unmodifiable(_initialData!);
  Map<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState> get sectionStates =>
      Map<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>.unmodifiable(
        _states,
      );

  MonthlyWorkspaceSectionState stateFor(MonthlyWorkspaceSection section) {
    return _states[section] ?? MonthlyWorkspaceSectionState.incomplete;
  }

  List<MonthlyWorkspaceSection> get visibleSections {
    if (isPaymentView) {
      return const <MonthlyWorkspaceSection>[
        MonthlyWorkspaceSection.paymentAmount,
        MonthlyWorkspaceSection.paymentExtension,
        MonthlyWorkspaceSection.paymentNote,
      ];
    }
    return const <MonthlyWorkspaceSection>[
      MonthlyWorkspaceSection.vehicle,
      MonthlyWorkspaceSection.product,
      MonthlyWorkspaceSection.period,
      MonthlyWorkspaceSection.memo,
    ];
  }

  int get incompleteSectionCount {
    return visibleSections.where((section) {
      final state = stateFor(section);
      return state == MonthlyWorkspaceSectionState.incomplete ||
          state == MonthlyWorkspaceSectionState.error;
    }).length;
  }

  void openCreate({required String source}) {
    _view = SecondaryMonthlyView.settings;
    _settingsMode = MonthlySettingsMode.create;
    _editingDocId = null;
    _paymentDocId = null;
    _initialData = null;
    _activeSection = MonthlyWorkspaceSection.vehicle;
    _saving = false;
    _dirty = false;
    _navigationRequestId = 0;
    _resetSettingsStates();
    log('settings_opened mode=create source=$source');
    notifyListeners();
  }

  void openEdit({
    required String docId,
    required Map<String, dynamic> initialData,
    required String source,
  }) {
    _view = SecondaryMonthlyView.settings;
    _settingsMode = MonthlySettingsMode.edit;
    _editingDocId = docId;
    _paymentDocId = null;
    _initialData = Map<String, dynamic>.from(initialData);
    _activeSection = MonthlyWorkspaceSection.vehicle;
    _saving = false;
    _dirty = false;
    _navigationRequestId = 0;
    _resetSettingsStates();
    log('settings_opened mode=edit doc=$docId source=$source');
    notifyListeners();
  }

  void openPayment({
    required String docId,
    required Map<String, dynamic> initialData,
    required String source,
  }) {
    _view = SecondaryMonthlyView.payment;
    _settingsMode = MonthlySettingsMode.edit;
    _editingDocId = null;
    _paymentDocId = docId;
    _initialData = Map<String, dynamic>.from(initialData);
    _activeSection = MonthlyWorkspaceSection.paymentAmount;
    _saving = false;
    _dirty = false;
    _navigationRequestId = 0;
    _resetPaymentStates();
    log('payment_opened doc=$docId source=$source');
    notifyListeners();
  }

  void returnToManagement({
    required String source,
    bool refresh = false,
  }) {
    if (refresh) _managementRevision += 1;
    final previous = _view;
    _view = SecondaryMonthlyView.management;
    _settingsMode = MonthlySettingsMode.create;
    _editingDocId = null;
    _paymentDocId = null;
    _initialData = null;
    _activeSection = MonthlyWorkspaceSection.vehicle;
    _saving = false;
    _dirty = false;
    _navigationRequestId = 0;
    _states.clear();
    log(
      'workspace_closed from=${previous.name} refresh=$refresh revision=$_managementRevision source=$source',
    );
    notifyListeners();
  }

  void requestSection(
    MonthlyWorkspaceSection section, {
    required String source,
  }) {
    if (isManagementView || _saving || !visibleSections.contains(section)) {
      return;
    }
    _navigationRequestId += 1;
    final previous = _activeSection;
    _activeSection = section;
    log(
      'section_requested from=${previous.name} to=${section.name} request=$_navigationRequestId source=$source',
    );
    notifyListeners();
  }

  void selectSection(
    MonthlyWorkspaceSection section, {
    required String source,
  }) {
    if (isManagementView || !visibleSections.contains(section)) return;
    if (_activeSection == section) {
      log('section_reselected section=${section.name} source=$source');
      return;
    }
    final previous = _activeSection;
    _activeSection = section;
    log('section_changed from=${previous.name} to=${section.name} source=$source');
    notifyListeners();
  }

  void updateSectionStates(
    Map<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState> states, {
    required String source,
  }) {
    var changed = false;
    for (final section in visibleSections) {
      final next = states[section];
      if (next == null || _states[section] == next) continue;
      _states[section] = next;
      changed = true;
    }
    if (!changed) return;
    final summary = visibleSections
        .map((section) => '${section.name}:${stateFor(section).name}')
        .join('|');
    log('section_states source=$source $summary');
    notifyListeners();
  }

  void setSaving(bool value, {required String source}) {
    if (_saving == value) return;
    _saving = value;
    log('saving value=$value source=$source');
    notifyListeners();
  }

  void setDirty(bool value, {required String source}) {
    if (_dirty == value) return;
    _dirty = value;
    log('dirty value=$value source=$source');
    notifyListeners();
  }

  void reset({required String source}) {
    final changed = !isManagementView || _saving || _dirty;
    _view = SecondaryMonthlyView.management;
    _settingsMode = MonthlySettingsMode.create;
    _editingDocId = null;
    _paymentDocId = null;
    _initialData = null;
    _activeSection = MonthlyWorkspaceSection.vehicle;
    _saving = false;
    _dirty = false;
    _navigationRequestId = 0;
    _states.clear();
    log('workspace_reset source=$source changed=$changed');
    if (changed) notifyListeners();
  }

  void _resetSettingsStates() {
    _states
      ..clear()
      ..addAll(<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>{
        MonthlyWorkspaceSection.vehicle:
            MonthlyWorkspaceSectionState.incomplete,
        MonthlyWorkspaceSection.product:
            MonthlyWorkspaceSectionState.incomplete,
        MonthlyWorkspaceSection.period:
            MonthlyWorkspaceSectionState.incomplete,
        MonthlyWorkspaceSection.memo: MonthlyWorkspaceSectionState.optional,
      });
  }

  void _resetPaymentStates() {
    _states
      ..clear()
      ..addAll(<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>{
        MonthlyWorkspaceSection.paymentAmount:
            MonthlyWorkspaceSectionState.incomplete,
        MonthlyWorkspaceSection.paymentExtension:
            MonthlyWorkspaceSectionState.complete,
        MonthlyWorkspaceSection.paymentNote:
            MonthlyWorkspaceSectionState.optional,
      });
  }

  void log(String message) {
    final output = 'monthly_workspace $message';
    final logger = _onDebug;
    if (logger != null) {
      logger(output);
      return;
    }
    debugPrint('[SecondaryMonthlyWorkspace] $output');
  }
}
