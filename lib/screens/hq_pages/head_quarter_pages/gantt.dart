import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MaterialApp(home: Gantt()));
}

class Gantt extends StatefulWidget {
  const Gantt({super.key});

  @override
  State<Gantt> createState() => _GanttState();
}

class _GanttState extends State<Gantt> {
  List<Task> tasks = [];
  final Map<String, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('tasks');
    if (jsonString != null) {
      final jsonList = json.decode(jsonString) as List;
      setState(() {
        tasks = jsonList.map((e) => Task.fromJson(e)).toList();
      });
      for (final task in tasks) {
        for (final sub in task.subtasks) {
          final key = '${task.name}_${sub.name}';
          sub.isDone = prefs.getBool(key) ?? false;
        }
      }
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = tasks.map((e) => e.toJson()).toList();
    await prefs.setString('tasks', json.encode(jsonList));
    for (final task in tasks) {
      for (final sub in task.subtasks) {
        final key = '${task.name}_${sub.name}';
        await prefs.setBool(key, sub.isDone);
      }
    }
  }

  void _addTask() async {
    final result = await _showTaskInputDialog(title: '상위 테스크 추가');
    if (result == null) return;
    setState(() {
      tasks.add(Task(name: result['name'], priority: result['priority'], subtasks: []));
    });
    _saveTasks();
  }

  void _addSubTask(Task task) async {
    final result = await _showTaskInputDialog(title: '하위 테스크 추가');
    if (result == null) return;
    setState(() {
      task.subtasks.add(SubTask(name: result['name'], priority: result['priority']));
    });
    _saveTasks();
  }

  void _deleteTask(Task task) {
    setState(() {
      tasks.remove(task);
    });
    _saveTasks();
  }

  void _deleteSubTask(Task task, SubTask sub) {
    setState(() {
      task.subtasks.remove(sub);
    });
    _saveTasks();
  }

  Future<Map<String, dynamic>?> _showTaskInputDialog({
    required String title,
    String? initialName,
    int? initialPriority,
  }) async {
    final nameController = TextEditingController(text: initialName ?? '');
    final priorityController = TextEditingController(text: (initialPriority ?? 0).toString());

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      // 중요!
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, // 키보드 높이만큼 패딩
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '이름'),
                  ),
                  TextField(
                    controller: priorityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '우선순위 (숫자)'),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final name = nameController.text.trim();
                          final priority = int.tryParse(priorityController.text) ?? 0;
                          if (name.isNotEmpty) {
                            Navigator.pop(context, {'name': name, 'priority': priority});
                          }
                        },
                        child: const Text('확인'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    tasks.sort((a, b) {
      final p = a.priority.compareTo(b.priority);
      return p != 0 ? p : b.progress.compareTo(a.progress);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gantt with 관리 기능'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addTask),
        ],
      ),
      body: ListView.builder(
        itemCount: tasks.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (context, index) {
          final task = tasks[index];
          final isExpanded = _expanded[task.name] ?? true;

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ExpansionTile(
              title: Row(
                children: [
                  Expanded(
                      child: Text('${task.name} (P${task.priority})',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  Text('${(task.progress * 100).round()}%'),
                ],
              ),
              initiallyExpanded: isExpanded,
              onExpansionChanged: (val) => setState(() => _expanded[task.name] = val),
              children: [
                LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 10,
                  color: Colors.blue,
                  backgroundColor: Colors.grey[300],
                ),
                const SizedBox(height: 10),
                ...task.subtasks.map((sub) {
                  return ListTile(
                    leading: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Checkbox(
                        key: ValueKey(sub.isDone),
                        value: sub.isDone,
                        onChanged: (value) {
                          setState(() => sub.isDone = value ?? false);
                          _saveTasks();
                        },
                      ),
                    ),
                    title: Text('${sub.name} (P${sub.priority})'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteSubTask(task, sub),
                    ),
                  );
                }),
                Row(
                  children: [
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _addSubTask(task),
                      icon: const Icon(Icons.add),
                      label: const Text('하위 테스크 추가'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _deleteTask(task),
                      icon: const Icon(Icons.delete),
                      label: const Text('상위 테스크 삭제'),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SubTask {
  final String name;
  bool isDone;
  int priority;

  SubTask({required this.name, this.isDone = false, this.priority = 0});

  factory SubTask.fromJson(Map<String, dynamic> json) => SubTask(
        name: json['name'],
        isDone: json['isDone'] ?? false,
        priority: json['priority'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'isDone': isDone,
        'priority': priority,
      };
}

class Task {
  final String name;
  final List<SubTask> subtasks;
  int priority;

  Task({required this.name, required this.subtasks, this.priority = 0});

  double get progress {
    if (subtasks.isEmpty) return 0;
    final doneCount = subtasks.where((s) => s.isDone).length;
    return doneCount / subtasks.length;
  }

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        name: json['name'],
        priority: json['priority'] ?? 0,
        subtasks: (json['subtasks'] as List).map((e) => SubTask.fromJson(e)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'priority': priority,
        'subtasks': subtasks.map((e) => e.toJson()).toList(),
      };
}
