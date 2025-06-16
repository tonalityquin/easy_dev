import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../widgets/navigation/secondary_mini_navigation.dart';

class LocalData extends StatefulWidget {
  const LocalData({super.key});

  @override
  State<LocalData> createState() => _LocalDataState();
}

class _LocalDataState extends State<LocalData> {
  Map<String, Object> prefsData = {};
  String searchKeyword = '';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    final Map<String, Object> loadedData = {
      for (var key in keys) key: prefs.get(key) ?? 'null',
    };

    setState(() {
      prefsData = loadedData;
    });
  }

  String _formatValue(Object value) {
    try {
      final decoded = json.decode(value.toString());
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      if (value is List) {
        return '[${value.join(', ')}]';
      }
      return value.toString();
    }
  }

  Future<void> _editPreference(String key, Object value) async {
    String selectedType = _inferType(value);
    final controller = TextEditingController(text: value.toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SharedPreferences 값 수정',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              key,
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '타입 선택',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (newType) {
                if (newType != null) {
                  setState(() {
                    selectedType = newType;
                  });
                  Navigator.pop(context);
                  _editPreference(key, value); // reopen dialog
                }
              },
              items: [
                'String',
                'int',
                'double',
                'bool',
                'List<String>',
              ].map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      Icon(Icons.code, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(type),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '새 값 입력',
                hintText: '값을 입력하세요',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.only(right: 8, bottom: 4),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final input = controller.text;

              switch (selectedType) {
                case 'int':
                  prefs.setInt(key, int.tryParse(input) ?? 0);
                  break;
                case 'double':
                  prefs.setDouble(key, double.tryParse(input) ?? 0.0);
                  break;
                case 'bool':
                  prefs.setBool(key, input.toLowerCase() == 'true');
                  break;
                case 'List<String>':
                  prefs.setStringList(key, input.split(',').map((e) => e.trim()).toList());
                  break;
                default:
                  prefs.setString(key, input);
              }

              Navigator.pop(context);
              _loadPreferences();
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  String _inferType(Object value) {
    if (value is int) return 'int';
    if (value is double) return 'double';
    if (value is bool) return 'bool';
    if (value is List<String>) return 'List<String>';
    return 'String';
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = prefsData.entries.where((entry) => entry.key.contains(searchKeyword)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SharedPreferences',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPreferences,
            tooltip: '새로고침',
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '키워드로 검색',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  searchKeyword = value;
                });
              },
            ),
          ),
          Expanded(
            child: filteredEntries.isEmpty
                ? const Center(child: Text('일치하는 데이터가 없습니다.'))
                : ListView.builder(
                    itemCount: filteredEntries.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (_, index) {
                      final entry = filteredEntries[index];
                      return ListTile(
                        title: Text(entry.key),
                        subtitle: Text(
                          _formatValue(entry.value),
                          softWrap: true,
                          maxLines: null,
                          overflow: TextOverflow.visible,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editPreference(entry.key, entry.value),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const SecondaryMiniNavigation(
        icons: [
          Icons.search,
          Icons.person,
          Icons.sort,
        ],
      ),
    );
  }
}
