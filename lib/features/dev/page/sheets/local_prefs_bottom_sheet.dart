import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/debug_session_controller.dart';
import '../../presentation/debug_tool_shell.dart';

class LocalPrefsBottomSheet extends StatefulWidget {
  const LocalPrefsBottomSheet({super.key});

  @override
  State<LocalPrefsBottomSheet> createState() => _LocalPrefsBottomSheetState();
}

enum _PrefFilter { all, boolean, string, number, list }

class _LocalPrefsBottomSheetState extends State<LocalPrefsBottomSheet> {
  bool _loading = true;
  Map<String, Object?> _data = <String, Object?>{};
  List<String> _allKeys = <String>[];
  List<String> _filteredKeys = <String>[];
  _PrefFilter _filter = _PrefFilter.all;
  String? _recentlyChangedKey;
  Timer? _highlightTimer;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applyFilter);
    _loadPrefs();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    if (mounted) setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList()..sort();
      final map = <String, Object?>{};
      for (final key in keys) {
        map[key] = prefs.get(key);
      }
      if (!mounted) return;
      setState(() {
        _data = map;
        _allKeys = keys;
        _loading = false;
      });
      _applyFilter();
      DebugSessionController.record(
        'shared_preferences_loaded',
        source: 'shared_preferences',
        meta: <String, Object?>{'keys': keys.length},
      );
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      DebugSessionController.record(
        'shared_preferences_load_failed',
        source: 'shared_preferences',
        meta: <String, Object?>{'error': error.toString()},
      );
    }
  }

  void _applyFilter() {
    if (!mounted) return;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _allKeys.where((key) {
      final value = _data[key];
      final matchesType = _matchesFilter(value);
      if (!matchesType) return false;
      if (query.isEmpty) return true;
      return key.toLowerCase().contains(query) ||
          _valuePreview(value).toLowerCase().contains(query);
    }).toList(growable: false);
    setState(() => _filteredKeys = filtered);
  }

  bool _matchesFilter(Object? value) {
    switch (_filter) {
      case _PrefFilter.all:
        return true;
      case _PrefFilter.boolean:
        return value is bool;
      case _PrefFilter.string:
        return value is String;
      case _PrefFilter.number:
        return value is int || value is double;
      case _PrefFilter.list:
        return value is List<String>;
    }
  }

  String _filterLabel(_PrefFilter value) {
    switch (value) {
      case _PrefFilter.all:
        return 'All';
      case _PrefFilter.boolean:
        return 'Bool';
      case _PrefFilter.string:
        return 'String';
      case _PrefFilter.number:
        return 'Number';
      case _PrefFilter.list:
        return 'List';
    }
  }

  String _typeLabel(Object? value) {
    if (value is bool) return 'BOOL';
    if (value is String) return 'STRING';
    if (value is int) return 'INT';
    if (value is double) return 'DOUBLE';
    if (value is List<String>) return 'LIST';
    if (value == null) return 'NULL';
    return value.runtimeType.toString().toUpperCase();
  }

  String _valuePreview(Object? value) {
    if (value is List) return jsonEncode(value);
    if (value == null) return 'null';
    return value.toString();
  }

  Future<void> _setPref(String key, Object? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool ok = false;
      if (value == null) {
        ok = await prefs.remove(key);
      } else if (value is String) {
        ok = await prefs.setString(key, value);
      } else if (value is bool) {
        ok = await prefs.setBool(key, value);
      } else if (value is int) {
        ok = await prefs.setInt(key, value);
      } else if (value is double) {
        ok = await prefs.setDouble(key, value);
      } else if (value is List<String>) {
        ok = await prefs.setStringList(key, value);
      }
      if (!ok || !mounted) return;
      setState(() {
        if (value == null) {
          _data.remove(key);
          _allKeys.remove(key);
        } else {
          _data[key] = value;
          if (!_allKeys.contains(key)) {
            _allKeys.add(key);
            _allKeys.sort();
          }
          _recentlyChangedKey = key;
        }
      });
      _applyFilter();
      _highlightTimer?.cancel();
      if (value != null) {
        _highlightTimer = Timer(const Duration(milliseconds: 620), () {
          if (mounted && _recentlyChangedKey == key) {
            setState(() => _recentlyChangedKey = null);
          }
        });
      }
      DebugSessionController.record(
        value == null ? 'shared_preferences_delete' : 'shared_preferences_write',
        source: 'shared_preferences',
        meta: <String, Object?>{
          'key': key,
          'type': value == null ? 'removed' : _typeLabel(value),
        },
      );
    } catch (error) {
      DebugSessionController.record(
        'shared_preferences_write_failed',
        source: 'shared_preferences',
        meta: <String, Object?>{'key': key, 'error': error.toString()},
      );
      if (mounted) _showMessage('저장하지 못했습니다.');
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: jsonEncode(_data)));
    DebugSessionController.record(
      'shared_preferences_copy_all',
      source: 'shared_preferences',
      meta: <String, Object?>{'keys': _data.length},
    );
    if (mounted) _showMessage('전체 값을 복사했습니다.');
  }

  Future<void> _copyEntry(String key, Object? value) async {
    await Clipboard.setData(ClipboardData(text: jsonEncode(<String, Object?>{key: value})));
    DebugSessionController.record(
      'shared_preferences_copy_entry',
      source: 'shared_preferences',
      meta: <String, Object?>{'key': key},
    );
    if (mounted) _showMessage('항목을 복사했습니다.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  Future<void> _deleteKey(String key) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => _DebugConfirmDialog(
            title: 'SharedPreferences 삭제',
            description: key,
            confirmLabel: '삭제',
          ),
        ) ??
        false;
    if (!ok) return;
    await _setPref(key, null);
  }

  Future<void> _editValue(String key, Object? value) async {
    if (value is bool) {
      await _setPref(key, !value);
      return;
    }
    if (value is String) {
      final saved = await _showTextEditor(
        title: 'String 편집',
        keyName: key,
        current: value,
      );
      if (saved != null) await _setPref(key, saved);
      return;
    }
    if (value is int) {
      final saved = await _showTextEditor(
        title: 'int 편집',
        keyName: key,
        current: value.toString(),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: false,
          signed: true,
        ),
      );
      if (saved == null) return;
      final parsed = int.tryParse(saved.trim());
      if (parsed == null) {
        _showMessage('정수 값을 확인해 주세요.');
        return;
      }
      await _setPref(key, parsed);
      return;
    }
    if (value is double) {
      final saved = await _showTextEditor(
        title: 'double 편집',
        keyName: key,
        current: value.toString(),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
      );
      if (saved == null) return;
      final parsed = double.tryParse(saved.trim());
      if (parsed == null) {
        _showMessage('실수 값을 확인해 주세요.');
        return;
      }
      await _setPref(key, parsed);
      return;
    }
    if (value is List<String>) {
      final saved = await _showTextEditor(
        title: 'List<String> 편집',
        keyName: key,
        current: value.join('\n'),
        minLines: 6,
        maxLines: 12,
      );
      if (saved == null) return;
      final list = saved
          .split('\n')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
      await _setPref(key, list);
    }
  }

  Future<String?> _showTextEditor({
    required String title,
    required String keyName,
    required String current,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 6,
  }) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _DebugValueEditorDialog(
        title: title,
        keyName: keyName,
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _addKeyDialog() async {
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    var type = 'String';
    final result = await showDialog<_NewPreferenceValue>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const _DebugDialogTitle(
              title: '새 SharedPreferences 항목',
              route: 'Developer / SharedPreferences / Add',
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: keyController,
                    decoration: const InputDecoration(labelText: '키'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: '타입'),
                    items: const [
                      DropdownMenuItem(value: 'String', child: Text('String')),
                      DropdownMenuItem(value: 'bool', child: Text('bool')),
                      DropdownMenuItem(value: 'int', child: Text('int')),
                      DropdownMenuItem(value: 'double', child: Text('double')),
                      DropdownMenuItem(
                        value: 'List<String>',
                        child: Text('List<String>'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueController,
                    decoration: const InputDecoration(labelText: '값'),
                    minLines: type == 'List<String>' ? 4 : 1,
                    maxLines: type == 'List<String>' ? 8 : 3,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    _NewPreferenceValue(
                      key: keyController.text.trim(),
                      type: type,
                      rawValue: valueController.text,
                    ),
                  );
                },
                child: const Text('추가'),
              ),
            ],
          );
        },
      ),
    );
    keyController.dispose();
    valueController.dispose();
    if (result == null || result.key.isEmpty) return;
    final raw = result.rawValue;
    switch (result.type) {
      case 'String':
        await _setPref(result.key, raw);
        return;
      case 'bool':
        final normalized = raw.trim().toLowerCase();
        if (normalized != 'true' && normalized != 'false') {
          _showMessage('bool 값은 true 또는 false를 입력해 주세요.');
          return;
        }
        await _setPref(result.key, normalized == 'true');
        return;
      case 'int':
        final parsed = int.tryParse(raw.trim());
        if (parsed == null) {
          _showMessage('정수 값을 확인해 주세요.');
          return;
        }
        await _setPref(result.key, parsed);
        return;
      case 'double':
        final parsed = double.tryParse(raw.trim());
        if (parsed == null) {
          _showMessage('실수 값을 확인해 주세요.');
          return;
        }
        await _setPref(result.key, parsed);
        return;
      case 'List<String>':
        await _setPref(
          result.key,
          raw
              .split('\n')
              .map((entry) => entry.trim())
              .where((entry) => entry.isNotEmpty)
              .toList(growable: false),
        );
        return;
    }
  }

  Future<void> _showStatus() async {
    await DebugSessionController.showStatus(
      context,
      source: 'shared_preferences',
      description: <String>[
        'DEBUG session: ACTIVE',
        'Tool: SharedPreferences',
        'Total keys: ${_allKeys.length}',
        'Visible keys: ${_filteredKeys.length}',
        'Filter: ${_filterLabel(_filter)}',
        'Search: ${_searchCtrl.text.trim().isEmpty ? '-' : _searchCtrl.text.trim()}',
      ].join('\n'),
    );
  }

  Future<void> _exitDebug() async {
    final reduceMotion = _reduceMotion;
    DebugSessionController.record(
      'debug_exit_from_tool',
      source: 'shared_preferences',
    );
    if (mounted) Navigator.of(context).pop();
    if (!reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    await DebugSessionController.disable(source: 'shared_preferences');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 190);
    return Container(
      color: Colors.black.withOpacity(0.18),
      child: DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.48,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Material(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 4),
                DebugToolHeader(
                  title: 'SharedPreferences',
                  breadcrumb: 'Developer / SharedPreferences',
                  meta: '${_allKeys.length} keys · ${_filteredKeys.length} visible',
                  onClose: () => Navigator.of(context).pop(),
                  onStatus: _showStatus,
                  onDebugExit: _exitDebug,
                  actions: [
                    IconButton(
                      tooltip: '새 항목',
                      onPressed: _addKeyDialog,
                      icon: const Icon(Icons.add_rounded),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '도구',
                      onSelected: (value) {
                        if (value == 'refresh') _loadPrefs();
                        if (value == 'copy') _copyAll();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Text('새로고침'),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          enabled: _data.isNotEmpty,
                          child: const Text('전체 복사'),
                        ),
                      ],
                      icon: const Icon(Icons.build_outlined),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      labelText: '검색',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '검색 지우기',
                              onPressed: () {
                                _searchCtrl.clear();
                                _searchFocus.requestFocus();
                              },
                              icon: const Icon(Icons.clear_rounded),
                            ),
                      filled: true,
                      fillColor: cs.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _PrefFilter.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (context, index) {
                      final value = _PrefFilter.values[index];
                      return ChoiceChip(
                        label: Text(_filterLabel(value)),
                        selected: _filter == value,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _filter = value);
                          _applyFilter();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: _loading
                        ? const Center(
                            key: ValueKey<String>('prefs_loading'),
                            child: CircularProgressIndicator(),
                          )
                        : _filteredKeys.isEmpty
                            ? const Center(
                                key: ValueKey<String>('prefs_empty'),
                                child: Text('표시할 항목이 없습니다.'),
                              )
                            : ListView.builder(
                                key: ValueKey<String>(
                                  'prefs_${_filter.name}_${_searchCtrl.text}_${_filteredKeys.length}',
                                ),
                                controller: scrollController,
                                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                                itemCount: _filteredKeys.length,
                                itemBuilder: (context, index) {
                                  final key = _filteredKeys[index];
                                  final value = _data[key];
                                  return _PreferenceReveal(
                                    index: index,
                                    reduceMotion: _reduceMotion,
                                    child: _PreferenceTile(
                                      keyName: key,
                                      type: _typeLabel(value),
                                      value: _valuePreview(value),
                                      rawValue: value,
                                      highlighted: _recentlyChangedKey == key,
                                      onTap: () => _editValue(key, value),
                                      onToggle: value is bool
                                          ? (next) => _setPref(key, next)
                                          : null,
                                      onCopy: () => _copyEntry(key, value),
                                      onDelete: () => _deleteKey(key),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PreferenceReveal extends StatelessWidget {
  const _PreferenceReveal({
    required this.index,
    required this.reduceMotion,
    required this.child,
  });

  final int index;
  final bool reduceMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 150 + index.clamp(0, 8).toInt() * 18),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 5 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.keyName,
    required this.type,
    required this.value,
    required this.rawValue,
    required this.highlighted,
    required this.onTap,
    required this.onToggle,
    required this.onCopy,
    required this.onDelete,
  });

  static const Color _debugAccent = Color(0xFF6D5DFB);

  final String keyName;
  final String type;
  final String value;
  final Object? rawValue;
  final bool highlighted;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? Color.alphaBlend(
                _debugAccent.withOpacity(0.10),
                cs.surfaceContainerLow,
              )
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? _debugAccent.withOpacity(0.45)
              : cs.outlineVariant.withOpacity(0.78),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _debugAccent.withOpacity(0.09),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          type,
                          style: const TextStyle(
                            color: _debugAccent,
                            fontFamily: 'monospace',
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        keyName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                      ),
                    ],
                  ),
                ),
                if (onToggle != null)
                  Switch.adaptive(
                    value: rawValue as bool,
                    onChanged: onToggle,
                  )
                else
                  IconButton(
                    tooltip: '편집',
                    onPressed: onTap,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                PopupMenuButton<String>(
                  tooltip: '항목 메뉴',
                  onSelected: (selected) {
                    if (selected == 'copy') onCopy();
                    if (selected == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy', child: Text('복사')),
                    PopupMenuItem(value: 'delete', child: Text('삭제')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebugDialogTitle extends StatelessWidget {
  const _DebugDialogTitle({required this.title, required this.route});

  static const Color _debugAccent = Color(0xFF6D5DFB);

  final String title;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DEBUG',
          style: TextStyle(
            color: _debugAccent,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 5),
        Text(title),
        const SizedBox(height: 3),
        Text(
          route,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
        ),
      ],
    );
  }
}

class _DebugValueEditorDialog extends StatelessWidget {
  const _DebugValueEditorDialog({
    required this.title,
    required this.keyName,
    required this.controller,
    required this.minLines,
    required this.maxLines,
    this.keyboardType,
  });

  final String title;
  final String keyName;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _DebugDialogTitle(
        title: title,
        route: 'Developer / SharedPreferences / $keyName',
      ),
      content: SizedBox(
        width: 500,
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          autofocus: true,
          decoration: const InputDecoration(labelText: '값'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class _DebugConfirmDialog extends StatelessWidget {
  const _DebugConfirmDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
  });

  final String title;
  final String description;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _DebugDialogTitle(
        title: title,
        route: 'Developer / SharedPreferences',
      ),
      content: Text(description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

class _NewPreferenceValue {
  const _NewPreferenceValue({
    required this.key,
    required this.type,
    required this.rawValue,
  });

  final String key;
  final String type;
  final String rawValue;
}
