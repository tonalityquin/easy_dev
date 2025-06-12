import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';

class HeadQuarterCalendar extends StatefulWidget {
  const HeadQuarterCalendar({super.key});

  @override
  State<HeadQuarterCalendar> createState() => _HeadQuarterCalendarState();
}

class Task {
  final int id;
  String title;
  String? description;
  bool isCompleted;
  DateTime startDate;
  DateTime dueDate;
  bool isShared;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.startDate,
    required this.dueDate,
    this.isCompleted = false,
    this.isShared = false,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final dueDate = DateTime.parse(json['dueDate']);
    final startDate = json['startDate'] != null ? DateTime.parse(json['startDate']) : dueDate;

    return Task(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      isCompleted: json['isCompleted'],
      startDate: startDate,
      dueDate: dueDate,
      isShared: json['isShared'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'isCompleted': isCompleted,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'isShared': isShared,
      };
}

class _HeadQuarterCalendarState extends State<HeadQuarterCalendar> {
  DateTime _focusedMonth = DateTime.now();
  Map<DateTime, List<Task>> _tasksByDate = {};
  final String _taskKey = 'headquarter_tasks';

  @override
  void initState() {
    super.initState();
    _loadTasksFromPrefs();
    _loadSharedTasks();
  }

  Future<void> _loadTasksFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_taskKey);
    if (raw != null) {
      final List decoded = jsonDecode(raw);
      final tasks = decoded.map((e) => Task.fromJson(e)).toList();
      _groupTasks(tasks);
    }
  }

  Future<void> _loadSharedTasks() async {
    try {
      final user = context.read<UserState>().user;
      if (user == null || user.divisions.isEmpty) return;

      final division = user.divisions.first;
      final firestore = FirebaseFirestore.instance;

      final snapshot = await firestore.collection('tasks').where('division', isEqualTo: division).get();

      final sharedTasks = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final taskData = data['task'] as Map<String, dynamic>?;

            if (taskData == null) return null;

            final dueDate = DateTime.parse(taskData['dueDate']);
            final startDate = taskData['startDate'] != null ? DateTime.parse(taskData['startDate']) : dueDate;

            return Task(
              id: taskData['id'],
              title: taskData['title'],
              description: taskData['description'],
              isCompleted: taskData['isCompleted'],
              startDate: startDate,
              dueDate: dueDate,
              isShared: true,
            );
          })
          .whereType<Task>()
          .toList();

      _groupTasks(sharedTasks);
    } catch (e) {
      debugPrint('❌ 공유된 캘린더 작업 로드 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유된 캘린더 작업 로드 중 오류 발생')),
      );
    }
  }

  void _groupTasks(List<Task> tasks) {
    final Map<DateTime, List<Task>> grouped = {};

    for (var task in tasks) {
      final dateKey = DateTime(task.startDate.year, task.startDate.month, task.startDate.day);
      grouped.putIfAbsent(dateKey, () => []).add(task);
    }

    setState(() {
      for (var entry in grouped.entries) {
        _tasksByDate.putIfAbsent(entry.key, () => []).addAll(entry.value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _generateDays(_focusedMonth);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_focusedMonth.year}년 ${_focusedMonth.month}월'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['월', '화', '수', '목', '금', '토', '일']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ))
                .toList(),
          ),
          Expanded(
            child: GridView.builder(
              itemCount: days.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.3,
              ),
              itemBuilder: (context, index) {
                final date = days[index];
                final isThisMonth = date.month == _focusedMonth.month;
                final taskList = _tasksByDate[date] ?? [];

                return GestureDetector(
                  onTap: () => _showTaskDetailsModal(context, date, taskList),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      color: _isToday(date) ? Colors.blue.shade50 : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isThisMonth ? Colors.black : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (taskList.isNotEmpty)
                          Row(
                            children: List.generate(
                              taskList.length > 3 ? 3 : taskList.length,
                              (i) => Padding(
                                padding: const EdgeInsets.only(right: 2.0),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: Colors.blueAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showTaskDetailsModal(BuildContext context, DateTime date, List<Task> tasks) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${date.year}년 ${date.month}월 ${date.day}일 일정',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            Expanded(
              child: tasks.isEmpty
                  ? const Center(child: Text('등록된 일정이 없습니다.'))
                  : ListView.builder(
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return ListTile(
                          title: Text(task.title),
                          subtitle:
                              task.description != null && task.description!.isNotEmpty ? Text(task.description!) : null,
                          trailing: task.isShared ? const Icon(Icons.group, size: 16, color: Colors.green) : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<DateTime> _generateDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final firstWeekday = (first.weekday + 6) % 7;
    final totalGrid = 42;
    final prevMonth = DateTime(month.year, month.month - 1);
    final prevLastDay = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;

    final List<DateTime> days = [];
    for (int i = 0; i < totalGrid; i++) {
      final offset = i - firstWeekday;
      final date = offset < 0
          ? DateTime(month.year, month.month - 1, prevLastDay + offset + 1)
          : offset >= last.day
              ? DateTime(month.year, month.month + 1, offset - last.day + 1)
              : DateTime(month.year, month.month, offset + 1);
      days.add(DateTime(date.year, date.month, date.day));
    }
    return days;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }
}
