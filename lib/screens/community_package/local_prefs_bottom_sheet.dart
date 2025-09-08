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

  @override
  void initState() {
    super.initState();
    _loadPrefs();
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
      _loading = false;
    });
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

  Future<void> _copyAll() async {
    final encoded = jsonEncode(_data.map((k, v) => MapEntry(k, v)));
    await Clipboard.setData(ClipboardData(text: encoded));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('모든 항목을 클립보드에 복사했습니다.')),
    );
  }

  Future<void> _copyEntry(String key, Object? value) async {
    final encoded = jsonEncode({key: value});
    await Clipboard.setData(ClipboardData(text: encoded));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('복사됨: $key')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      // 반투명 배경
      color: Colors.black.withOpacity(0.2),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
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
                  // 그립바
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
                  // 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.computer_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('SharedPreferences', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
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
                  const Divider(height: 1),
                  // 바디
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _data.isEmpty
                        ? const Center(child: Text('저장된 항목이 없습니다.'))
                        : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _data.length,
                      itemBuilder: (context, idx) {
                        final key = _data.keys.elementAt(idx);
                        final value = _data[key];
                        return ListTile(
                          dense: true,
                          title: Text(key, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(_valuePreview(value)),
                          leading: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _typeLabel(value),
                              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: '복사',
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () => _copyEntry(key, value),
                          ),
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
}
