import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HeadQuarterTask extends StatefulWidget {
  const HeadQuarterTask({super.key});

  @override
  State<HeadQuarterTask> createState() => _HeadQuarterTaskState();
}

class Task {
  final int id;
  String title;
  String? description;
  bool isCompleted;
  DateTime dueDate;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.dueDate,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'isCompleted': isCompleted,
    'dueDate': dueDate.toIso8601String(),
  };

  static Task fromJson(Map<String, dynamic> json) => Task(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    isCompleted: json['isCompleted'],
    dueDate: DateTime.parse(json['dueDate']),
  );
}

class _HeadQuarterTaskState extends State<HeadQuarterTask> {
  final List<Task> _tasks = [];
  bool _hideCompleted = false;
  final String _storageKey = 'headquarter_tasks';

  @override
  void initState() {
    super.initState();
    _loadTasksFromPrefs();
  }

  Future<void> _loadTasksFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved != null) {
      final decoded = jsonDecode(saved) as List;
      setState(() {
        _tasks.clear();
        _tasks.addAll(decoded.map((e) => Task.fromJson(e)));
      });
    }
  }

  Future<void> _saveTasksToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_tasks.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }

  @override
  Widget build(BuildContext context) {
    final visibleTasks = _hideCompleted
        ? _tasks.where((t) => !t.isCompleted).toList()
        : _tasks;

    visibleTasks.sort((a, b) {
      if (a.isCompleted && !b.isCompleted) return 1;
      if (!a.isCompleted && b.isCompleted) return -1;
      return 0;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        centerTitle: false,
        elevation: 0,
        actions: [
          Row(
            children: [
              const Text('완료 숨김', style: TextStyle(fontSize: 14)),
              Switch(
                value: _hideCompleted,
                onChanged: (val) {
                  setState(() {
                    _hideCompleted = val;
                  });
                },
              ),
            ],
          ),
        ],
      ),
      body: visibleTasks.isEmpty
          ? const Center(
        child: Text(
          '할 일이 없습니다',
          style: TextStyle(color: Colors.grey),
        ),
      )
          : ListView.builder(
        itemCount: visibleTasks.length,
        itemBuilder: (context, index) {
          final task = visibleTasks[index];
          return Dismissible(
            key: Key(task.id.toString()),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) {
              setState(() => _tasks.removeWhere((t) => t.id == task.id));
              _saveTasksToPrefs();
            },
            child: ListTile(
              leading: Checkbox(
                value: task.isCompleted,
                onChanged: (val) {
                  setState(() {
                    task.isCompleted = val ?? false;
                  });
                  _saveTasksToPrefs();
                },
              ),
              title: Text(
                task.title,
                style: TextStyle(
                  fontSize: 16,
                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  color: task.isCompleted ? Colors.grey : Colors.black,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (task.description != null && task.description!.trim().isNotEmpty)
                    Text(
                      task.description!,
                      style: TextStyle(
                        fontSize: 13,
                        color: task.isCompleted ? Colors.grey : Colors.black87,
                      ),
                    ),
                  Text(
                    '기한: ${task.dueDate.year}-${task.dueDate.month.toString().padLeft(2, '0')}-${task.dueDate.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () {
                  setState(() => _tasks.removeWhere((t) => t.id == task.id));
                  _saveTasksToPrefs();
                },
              ),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              dense: true,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddTaskDialog() {
    String title = '';
    String description = '';
    DateTime dueDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('새 작업 추가'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: '제목'),
                  onChanged: (value) => title = value,
                  autofocus: true,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: '설명 (선택)'),
                  onChanged: (value) => description = value,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('기한: '),
                    Text(
                      '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: dueDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => dueDate = picked);
                        }
                      },
                      child: const Text('날짜 선택'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                if (title.trim().isEmpty) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('제목은 필수입니다.')),
                  );
                  return;
                }
                setState(() {
                  _tasks.insert(
                    0,
                    Task(
                      id: DateTime.now().microsecondsSinceEpoch,
                      title: title.trim(),
                      description: description.trim(),
                      dueDate: dueDate,
                    ),
                  );
                });
                _saveTasksToPrefs();
                Navigator.pop(context);
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }
}
