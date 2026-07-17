import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalPrefsBottomSheet extends StatefulWidget {
  const LocalPrefsBottomSheet({super.key});

  @override
  State<LocalPrefsBottomSheet> createState() => _LocalPrefsBottomSheetState();
}

class _LocalPrefsBottomSheetState extends State<LocalPrefsBottomSheet> {
  bool _loading = true;
  Map<String, Object?> _data = {};

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<String> _allKeys = [];
  List<String> _filteredKeys = [];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList()..sort();
    final map = <String, Object?>{};
    for (final k in keys) {
      map[k] = prefs.get(k);
    }
    setState(() {
      _data = map;
      _allKeys = keys;
      _filteredKeys = List.from(_allKeys);
      _loading = false;
    });
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filteredKeys = List.from(_allKeys));
      return;
    }
    final filtered = _allKeys.where((k) {
      final v = _data[k];
      final keyHit = k.toLowerCase().contains(q);
      final valueHit = _valuePreview(v).toLowerCase().contains(q);
      return keyHit || valueHit;
    }).toList();
    setState(() => _filteredKeys = filtered);
  }

  String _typeLabel(Object? v) {
    if (v is String) return 'String';
    if (v is bool) return 'bool';
    if (v is int) return 'int';
    if (v is double) return 'double';
    if (v is List<String>) return 'List<String>';
    if (v == null) return 'null';
    return v.runtimeType.toString();
  }

  String _valuePreview(Object? v) {
    if (v is List) return jsonEncode(v);
    return '$v';
  }

  Future<void> _setPref(String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();
    bool ok = false;

    if (value == null) {
      ok = await prefs.remove(key);
      if (ok) {
        _data.remove(key);
        _allKeys.remove(key);
      }
    } else if (value is String) {
      ok = await prefs.setString(key, value);
      if (ok) _data[key] = value;
    } else if (value is bool) {
      ok = await prefs.setBool(key, value);
      if (ok) _data[key] = value;
    } else if (value is int) {
      ok = await prefs.setInt(key, value);
      if (ok) _data[key] = value;
    } else if (value is double) {
      ok = await prefs.setDouble(key, value);
      if (ok) _data[key] = value;
    } else if (value is List<String>) {
      ok = await prefs.setStringList(key, value);
      if (ok) _data[key] = value;
    }

    if (!mounted || !ok) return;

    setState(() {
      if (!_allKeys.contains(key) && value != null) {
        _allKeys.add(key);
        _allKeys.sort();
      }
    });
    _applyFilter();
  }

  Future<void> _copyAll() async {
    final encoded = jsonEncode(_data.map((k, v) => MapEntry(k, v)));
    await Clipboard.setData(ClipboardData(text: encoded));
  }

  Future<void> _copyEntry(String key, Object? value) async {
    final encoded = jsonEncode({key: value});
    await Clipboard.setData(ClipboardData(text: encoded));
  }

  Future<void> _deleteKey(String key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('“$key” 항목을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    ) ??
        false;
    if (ok != true) return;
    await _setPref(key, null);
  }

  Future<void> _editString(String key, String current) async {
    final ctrl = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('문자열 편집\n$key'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '값 (String)'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    await _setPref(key, saved);
  }

  Future<void> _editNumber<T extends num>(String key, T current) async {
    final ctrl = TextEditingController(text: '$current');
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${T == int ? '정수' : '실수'} 편집\n$key'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: '값 (${T == int ? 'int' : 'double'})',
            helperText: T == int ? '예: 42' : '예: 3.14',
          ),
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (saved == null) return;

    if (T == int) {
      final v = int.tryParse(saved);
      if (v == null) return;
      await _setPref(key, v);
    } else {
      final v = double.tryParse(saved);
      if (v == null) return;
      await _setPref(key, v);
    }
  }

  Future<void> _editStringList(String key, List<String> current) async {
    final ctrl = TextEditingController(text: current.join('\n'));
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('문자열 리스트 편집\n$key'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: '값 (줄마다 1개 항목)',
              alignLabelWithHint: true,
            ),
            minLines: 6,
            maxLines: 12,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    final list = saved
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    await _setPref(key, list);
  }

  Future<void> _addKeyDialog() async {
    final keyCtrl = TextEditingController();
    String type = 'String';
    final valCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('새 항목 추가'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyCtrl,
                decoration: const InputDecoration(labelText: '키'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type,
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
                onChanged: (v) => type = v ?? 'String',
                decoration: const InputDecoration(labelText: '타입'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valCtrl,
                decoration: const InputDecoration(
                  labelText: '값 (List<String>는 줄마다 1개, bool은 true/false)',
                  alignLabelWithHint: true,
                ),
                minLines: 1,
                maxLines: 8,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final key = keyCtrl.text.trim();
    if (key.isEmpty) return;

    switch (type) {
      case 'String':
        await _setPref(key, valCtrl.text);
        break;
      case 'bool':
        final v = valCtrl.text.trim().toLowerCase() == 'true';
        await _setPref(key, v);
        break;
      case 'int':
        final v = int.tryParse(valCtrl.text.trim());
        if (v == null) return;
        await _setPref(key, v);
        break;
      case 'double':
        final v = double.tryParse(valCtrl.text.trim());
        if (v == null) return;
        await _setPref(key, v);
        break;
      case 'List<String>':
        final list = valCtrl.text
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
        await _setPref(key, list);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      color: Colors.black.withOpacity(0.2),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollCtrl) {
          return Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.computer_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'SharedPreferences',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '추가',
                          onPressed: _addKeyDialog,
                          icon: const Icon(Icons.add_rounded),
                        ),
                        IconButton(
                          tooltip: '새로고침',
                          onPressed: _loadPrefs,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        IconButton(
                          tooltip: '전체 복사',
                          onPressed: _data.isEmpty ? null : _copyAll,
                          icon: const Icon(Icons.copy_all_rounded),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      decoration: InputDecoration(

                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            _applyFilter();
                            _searchFocus.requestFocus();
                          },
                        ),
                        filled: true,
                        fillColor: cs.surfaceVariant.withOpacity(0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _filteredKeys.isEmpty
                        ? const Center(child: Text('일치하는 항목이 없습니다.'))
                        : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _filteredKeys.length,
                      itemBuilder: (context, idx) {
                        final key = _filteredKeys[idx];
                        final value = _data[key];

                        final leading = Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _typeLabel(value),
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        );

                        Widget trailing;
                        VoidCallback? onTap;

                        if (value is bool) {
                          trailing = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: value,
                                onChanged: (v) => _setPref(key, v),
                              ),
                              _moreMenu(key, value),
                            ],
                          );
                        } else if (value is String) {
                          trailing = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '편집',
                                icon: const Icon(Icons.edit_rounded),
                                onPressed: () => _editString(key, value),
                              ),
                              _moreMenu(key, value),
                            ],
                          );
                        } else if (value is int) {
                          trailing = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '편집',
                                icon: const Icon(Icons.exposure_rounded),
                                onPressed: () => _editNumber<int>(key, value),
                              ),
                              _moreMenu(key, value),
                            ],
                          );
                        } else if (value is double) {
                          trailing = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '편집',
                                icon: const Icon(Icons.exposure_plus_1_rounded),
                                onPressed: () => _editNumber<double>(key, value),
                              ),
                              _moreMenu(key, value),
                            ],
                          );
                        } else if (value is List<String>) {
                          trailing = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '편집',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editStringList(key, value),
                              ),
                              _moreMenu(key, value),
                            ],
                          );
                        } else {
                          trailing = _moreMenu(key, value);
                        }

                        onTap ??= () {
                          if (value is String) {
                            _editString(key, value);
                          } else if (value is int) {
                            _editNumber<int>(key, value);
                          } else if (value is double) {
                            _editNumber<double>(key, value);
                          } else if (value is List<String>) {
                            _editStringList(key, value);
                          }
                        };

                        return ListTile(
                          dense: true,
                          title: Text(
                            key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(_valuePreview(value)),
                          leading: leading,
                          trailing: trailing,
                          onTap: onTap,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _moreMenu(String key, Object? value) {
    return PopupMenuButton<String>(
      tooltip: '더보기',
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'copy', child: Text('복사')),
        PopupMenuItem(value: 'delete', child: Text('삭제')),
      ],
      onSelected: (v) {
        switch (v) {
          case 'copy':
            _copyEntry(key, value);
            break;
          case 'delete':
            _deleteKey(key);
            break;
        }
      },
      icon: const Icon(Icons.more_vert_rounded),
    );
  }
}
