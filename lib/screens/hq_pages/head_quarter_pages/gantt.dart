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
  bool _hideCompleted = false;

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

  void _addOrEditTask({dynamic task, bool isSub = false, Task? parent}) async {
    final initial = task != null
        ? {'name': task.name, 'priority': task.priority}
        : null;
    final result = await _showTaskInputDialog(
      title: task == null
          ? (isSub ? '하위 테스크 추가' : '상위 테스크 추가')
          : '테스크 수정',
      initial: initial,
    );
    if (result == null) return;

    setState(() {
      if (task != null) {
        task.name = result['name'];
        task.priority = result['priority'];
      } else if (isSub && parent != null) {
        parent.subtasks
            .add(SubTask(name: result['name'], priority: result['priority']));
      } else {
        tasks.add(Task(
            name: result['name'],
            priority: result['priority'],
            subtasks: []));
      }
    });
    _saveTasks();
  }

  void _deleteTask(Task task) {
    setState(() => tasks.remove(task));
    _saveTasks();
  }

  void _deleteSubTask(Task task, SubTask sub) {
    setState(() => task.subtasks.remove(sub));
    _saveTasks();
  }

  Future<Map<String, dynamic>?> _showTaskInputDialog({
    required String title,
    Map<String, dynamic>? initial,
  }) async {
    final nameController = TextEditingController(text: initial?['name'] ?? '');
    final priorityController =
    TextEditingController(text: (initial?['priority'] ?? 0).toString());

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '이름')),
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
                        child: const Text('취소')),
                    ElevatedButton(
                      onPressed: () {
                        final name = nameController.text.trim();
                        final priority =
                            int.tryParse(priorityController.text) ?? 0;
                        if (name.isNotEmpty) {
                          Navigator.pop(
                              context, {'name': name, 'priority': priority});
                        }
                      },
                      child: const Text('확인'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    tasks.sort((a, b) => a.priority.compareTo(b.priority));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gantt'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _addOrEditTask()),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            value: _hideCompleted,
            onChanged: (v) => setState(() => _hideCompleted = v),
            title: const Text('완료된 항목 숨기기'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tasks.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final task = tasks[index];
                if (_hideCompleted && task.progress == 1) return const SizedBox();

                task.subtasks.sort((a, b) => a.priority.compareTo(b.priority));
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
                    onExpansionChanged: (val) =>
                        setState(() => _expanded[task.name] = val),
                    children: [
                      LinearProgressIndicator(
                        value: task.progress,
                        minHeight: 10,
                        color: Colors.blue,
                        backgroundColor: Colors.grey[300],
                      ),
                      const SizedBox(height: 10),
                      ...task.subtasks.map((sub) {
                        if (_hideCompleted && sub.isDone) return const SizedBox();
                        return ListTile(
                          leading: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _addOrEditTask(
                                    task: sub, isSub: true, parent: task),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _deleteSubTask(task, sub),
                              ),
                            ],
                          ),
                        );
                      }),
                      Row(
                        children: [
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () =>
                                _addOrEditTask(isSub: true, parent: task),
                            icon: const Icon(Icons.add),
                            label: const Text('하위 테스크 추가'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _addOrEditTask(task: task),
                            icon: const Icon(Icons.edit),
                            label: const Text('수정'),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _deleteTask(task),
                            icon: const Icon(Icons.delete),
                            label: const Text('삭제'),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SubTask {
  String name;
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
  String name;
  List<SubTask> subtasks;
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
    subtasks: (json['subtasks'] as List)
        .map((e) => SubTask.fromJson(e))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'priority': priority,
    'subtasks': subtasks.map((e) => e.toJson()).toList(),
  };
}
