import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'tasks/todo_model.dart';
import 'tasks/list_management.dart';
import 'tasks/list_selector.dart';

class TodoTaskScreen extends StatefulWidget {
  const TodoTaskScreen({super.key});

  @override
  State<TodoTaskScreen> createState() => _TodoTaskScreenState();
}

class _TodoTaskScreenState extends State<TodoTaskScreen>
    with ListManagement<TodoTaskScreen, Todo> {
  final TextEditingController _controller = TextEditingController();
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    loadAllLists('todos_', (e) => Todo.fromJson(json.decode(e)));
  }

  void _save() {
    saveCurrentList('todos_', (e) => json.encode(e.toJson()));
  }

  void _addTodo() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      getCurrentListItems().add(
        Todo(title: _controller.text.trim(), dueDate: _selectedDate),
      );
      _controller.clear();
      _selectedDate = null;
    });
    _save();
  }

  void _toggleDone(int index) {
    setState(() {
      final todos = getCurrentListItems();
      todos[index].isDone = !todos[index].isDone;
    });
    _save();
  }

  void _deleteTodo(int index) {
    setState(() {
      getCurrentListItems().removeAt(index);
    });
    _save();
  }

  void _editTodo(int index) {
    final todos = getCurrentListItems();
    final todo = todos[index];
    _controller.text = todo.title;
    _selectedDate = todo.dueDate;

    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: '할 일 수정'),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(_selectedDate == null
                      ? '날짜 미지정'
                      : DateFormat('yyyy년 M월 d일').format(_selectedDate!)),
                ),
                TextButton(
                  onPressed: _pickDate,
                  child: const Text('날짜 선택'),
                ),
              ],
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  todos[index] = Todo(
                    title: _controller.text.trim(),
                    isDone: todo.isDone,
                    dueDate: _selectedDate,
                  );
                  _controller.clear();
                  _selectedDate = null;
                });
                _save();
                Navigator.pop(context);
              },
              child: const Text('수정 완료'),
            ),
          ],
        ),
      ),
    );
  }

  void _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final todos = getCurrentListItems();
    final sortedTodos = [...todos]..sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      return b.dueDate?.compareTo(a.dueDate ?? DateTime.now()) ?? 0;
    });

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: buildListSelector(
          todoLists: todoLists,
          currentList: currentList,
          onSelected: (val) => setState(() => currentList = val),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => editListName(_save),
            tooltip: '목록 이름 수정',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => deleteCurrentList('todos_', _save),
            tooltip: '목록 삭제',
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            onPressed: () => showCreateListDialog(_save),
            tooltip: '새 목록 추가',
          ),
        ],
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: sortedTodos.isEmpty
                ? const Center(
                child: Text('using to sharepreference',
                    style: TextStyle(fontSize: 16)))
                : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: sortedTodos.length,
              itemBuilder: (context, index) {
                final todo = sortedTodos[index];
                final realIndex = todos.indexOf(todo);
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.symmetric(
                      vertical: 6, horizontal: 10),
                  child: ListTile(
                    onTap: () => _editTodo(realIndex),
                    leading: Checkbox(
                      value: todo.isDone,
                      onChanged: (_) => _toggleDone(realIndex),
                    ),
                    title: Text(
                      todo.title,
                      style: TextStyle(
                        decoration: todo.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: todo.dueDate != null
                        ? Text(DateFormat('yyyy년 M월 d일 예정')
                        .format(todo.dueDate!))
                        : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteTodo(realIndex),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 6),
                        ],
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'typing text to phone keyboard',
                        ),
                        onSubmitted: (_) => _addTodo(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.date_range),
                    onPressed: _pickDate,
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _addTodo,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        color: Colors.blueAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
