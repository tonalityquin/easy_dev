import 'package:flutter/foundation.dart';

class SecondaryLocationWorkspaceState extends ChangeNotifier {
  SecondaryLocationWorkspaceState({ValueChanged<String>? onDebug})
      : _onDebug = onDebug;

  final ValueChanged<String>? _onDebug;
  String? _focusedParentKey;
  String? _focusedParentId;
  String? _focusedParentTitle;
  bool _showOnlySelectedChild = false;
  bool _showSelectedChildSlotNumbers = false;

  String? get focusedParentKey => _focusedParentKey;
  String? get focusedParentId => _focusedParentId;
  String? get focusedParentTitle => _focusedParentTitle;
  bool get isParentFocus => _focusedParentKey != null;
  bool get showOnlySelectedChild => _showOnlySelectedChild;
  bool get showSelectedChildSlotNumbers => _showSelectedChildSlotNumbers;

  void openParent({
    required String key,
    required String parentId,
    required String title,
    required String source,
  }) {
    final normalizedKey = key.trim();
    final normalizedParentId = parentId.trim();
    final resolvedParentId =
        normalizedParentId.isEmpty ? null : normalizedParentId;
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
    _focusedParentKey = null;
    _focusedParentId = null;
    _focusedParentTitle = null;
    _showOnlySelectedChild = false;
    _showSelectedChildSlotNumbers = false;
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
    final hadFocus = _focusedParentKey != null;
    final optionsChanged =
        _showOnlySelectedChild || _showSelectedChildSlotNumbers;
    final previous = _focusedParentKey;
    _focusedParentKey = null;
    _focusedParentId = null;
    _focusedParentTitle = null;
    _showOnlySelectedChild = false;
    _showSelectedChildSlotNumbers = false;
    log('workspace_reset previous=${previous ?? '-'} source=$source');
    if (hadFocus || optionsChanged) notifyListeners();
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
