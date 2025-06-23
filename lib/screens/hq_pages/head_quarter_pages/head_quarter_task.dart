import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../states/user/user_state.dart';

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
  DateTime startDate;
  DateTime dueDate;
  bool isShared;
  String? firestoreId;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.startDate,
    required this.dueDate,
    this.isShared = false,
    this.firestoreId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'isCompleted': isCompleted,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'isShared': isShared,
        'firestoreId': firestoreId,
      };

  static Task fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        isCompleted: json['isCompleted'],
        startDate: DateTime.parse(json['startDate']),
        dueDate: DateTime.parse(json['dueDate']),
        isShared: json['isShared'] ?? false,
        firestoreId: json['firestoreId'],
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
    _loadSharedTasks(); // 공유된 작업 로드
  }

  Future<void> _loadSharedTasks() async {
    try {
      final user = context.read<UserState>().user;
      if (user == null || user.divisions.isEmpty) return;

      final division = user.divisions.first;
      final firestore = FirebaseFirestore.instance;

      final snapshot = await firestore.collection('tasks').where('division', isEqualTo: division).get();

      if (!mounted) return;

      final sharedTasks = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final taskData = data['task'] as Map<String, dynamic>?;
            if (taskData == null) return null;

            return Task(
              id: taskData['id'],
              title: taskData['title'],
              description: taskData['description'],
              isCompleted: taskData['isCompleted'],
              startDate: taskData['startDate'] != null
                  ? DateTime.parse(taskData['startDate'])
                  : DateTime.parse(taskData['dueDate']),
              dueDate: DateTime.parse(taskData['dueDate']),
              isShared: true,
              firestoreId: doc.id,
            );
          })
          .whereType<Task>()
          .toList();

      if (!mounted) return;

      setState(() {
        for (final shared in sharedTasks) {
          final alreadyExists = _tasks.any((t) => t.firestoreId == shared.firestoreId);
          if (!alreadyExists) {
            _tasks.add(shared);
          }
        }
      });

      if (!mounted) return;
      _saveTasksToPrefs();
    } catch (e) {
      debugPrint('🔥 공유된 작업 로드 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유된 작업 로드 중 오류 발생: $e')),
      );
    }
  }

  Future<void> _loadTasksFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final saved = prefs.getString(_storageKey);
    if (saved != null) {
      final decoded = jsonDecode(saved) as List;
      if (!mounted) return;
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

  Future<void> _shareTask(Task task) async {
    try {
      final user = context.read<UserState>().user;

      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자 정보가 없습니다. 로그인 상태를 확인하세요.')),
        );
        return;
      }

      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('tasks').add({
        'division': user.divisions.isNotEmpty ? user.divisions.first : 'default',
        'creator': user.id,
        'createdAt': DateTime.now().toIso8601String(),
        'task': {
          'id': task.id,
          'title': task.title,
          'description': task.description,
          'startDate': task.startDate.toIso8601String(),
          'dueDate': task.dueDate.toIso8601String(),
          'isCompleted': task.isCompleted,
        }
      });

      if (!mounted) return;
      setState(() {
        task.isShared = true;
        task.firestoreId = doc.id;
      });

      if (!mounted) return;
      _saveTasksToPrefs();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유되었습니다')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유 실패: $e')),
      );
    }
  }

  Future<void> _unshareTask(Task task) async {
    if (task.firestoreId == null) return;

    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('tasks').doc(task.firestoreId).delete();

      if (!mounted) return;
      setState(() {
        task.isShared = false;
        task.firestoreId = null;
      });

      if (!mounted) return;
      _saveTasksToPrefs();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유 해제되었습니다')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유 해제 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleTasks = _hideCompleted ? _tasks.where((t) => !t.isCompleted).toList() : _tasks;

    visibleTasks.sort((a, b) {
      if (a.isCompleted && !b.isCompleted) return 1;
      if (!a.isCompleted && b.isCompleted) return -1;
      return 0;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        centerTitle: true,
        // 제목 중앙 정렬
        backgroundColor: Colors.white,
        // 배경 흰색
        foregroundColor: Colors.black,
        // 텍스트/아이콘 검정
        elevation: 0,
        // 그림자 제거
        actions: [
          Row(
            children: [
              const Text('완료 숨김', style: TextStyle(fontSize: 14)),
              Switch(
                value: _hideCompleted,
                onChanged: (val) {
                  setState(() => _hideCompleted = val);
                },
              ),
            ],
          ),
        ],
      ),
      body: visibleTasks.isEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: const Center(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      height: 1.6,
                    ),
                    children: [
                      const TextSpan(
                        text:
                        '2025.06.21 Patch'
                            '\n\n1. 출퇴근, 휴게시간 업로드 로직 개선'
                            '\n 업무 지역 선택 함수인 \'currentArea\' 기반으로 \n \'table_cell\'에 데이터를 삽입하던 문제를'
                            '\n 계정 생성 시 생성 지역 기반으로 고정값 함수 \'selectedArea\'를 추가하여 해당 함수의 값을 기반으로'
                            'user와 json 데이터를 \'table_cell\'에 삽입하여 안정성 강화'
                            '\n\n2. 입차 완료 페이지 UseCase 변화'
                            '\n 2.1. 입차 요청, 입차 완료, 출차 요청 페이지에'
                            '\n 렌더링되는 limit 해제'
                            '\n 2.2. 입차 완료 페이지 구성을 데이터 기반 -> 주차 구역 기반'
                            '\n 으로 출력 형태 변화'
                            '\n (유지 비용+번호판 검색 로직 개선 목적)'
                            '\n\n\n\n#####'
                            '\n입차 완료 페이지 사용법'
                            '\n 1. 주차 구역 생성 시 최대 입차 가능 대수 입력 추가'
                            '\n\n 2. 앱 실행 시 최초 1회 \'주차 구역 갱신\' 버튼 터치'
                            '\n 정원 : 주차 구역 별 지정한 최대 입차 가능 대수'
                            '\n 등록 : 실시간 주차 구역 별 차량 입차 중인 대수'
                            '\n - \'정원\'의 경우, 실제 등록 한도에 영향 없음'
                            '\n\n 3. \'구역 초기화\'버튼으로 주차 구역 선택 초기화'
                            '\n 주차 구역 선택 후, 다른 페이지 전환 후 입차 완료 페이지 돌아올 경우,'
                            '\n \'구역 초기화\'에서 다른 주차 구역 상세 입차 차량 확인 가능'
                            '\n#####'
                            '\n\n\n\n',
                      ),
                      const TextSpan(
                        text:
                        '4. 중복 번호판 생성 기능 개선'
                            '\n 출차 완료된 번호판이 당일 재입차할 경우'
                            '\n 정적인 더미 데이터를 추가 생성하여 번호판을 세는'
                            '\n counts() 메서드 계산 문제 개선',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const TextSpan(
                        text:
                        '\n\n5. 업무 보고 시 총 합계 보고 버튼 추가'
                            '\n \'업무 종료\' 탭의 \'최종 정산..\' 버튼을 누르면'
                            '\n 당일 매출 확인 가능(하루에 한 번)'
                            '\n 정산 금액의 정상 반영 안정성 확인 뒤,'
                            '\n 필드 유저 혹은 TL이 매출액 확인 못하도록 Hide 예정'
                            '\n statistcis 페이지에서 매출액 통계 기능 제공 기능 추가'
                            '\n -----'
                            '\n\n추적 관찰 중인 이슈'
                            '\n\n1. 출차 요청에서 출차 완료 데이터 이동 중 이슈'
                            '\n 실시간으로 관리하는 입차 요청, 입차 완료, 출차 요청과 달리'
                            '정적으로 관리하는 출차 완료 페이지로의 데이터 이동 중'
                            '불특정한 조건에 발생하는 이슈'
                            '\n\n2. 출근/퇴근/휴게시간 데이터 정상 반영 여부'
                            '\n \'GCS CDN cache\'로부터 앱이 받는 영향력 추적'
                            '\n 개선 여부 판단',
                      ),
                    ],
                  ),
                ),
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
                        setState(() => task.isCompleted = val ?? false);
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
                          Text(task.description!,
                              style: TextStyle(fontSize: 13, color: task.isCompleted ? Colors.grey : Colors.black87)),
                        Text(
                          '기한: ${task.dueDate.year}-${task.dueDate.month.toString().padLeft(2, '0')}-${task.dueDate.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            task.isShared ? Icons.link_off : Icons.share,
                            color: task.isShared ? Colors.orange : Colors.blue,
                          ),
                          tooltip: task.isShared ? '공유 해제' : '공유',
                          onPressed: () {
                            task.isShared ? _unshareTask(task) : _shareTask(task);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.grey),
                          onPressed: () async {
                            // Firestore에 공유된 작업이면 문서도 삭제
                            if (task.firestoreId != null) {
                              try {
                                await FirebaseFirestore.instance.collection('tasks').doc(task.firestoreId).delete();
                                debugPrint('✅ Firestore 문서 삭제 완료: ${task.firestoreId}');
                              } catch (e) {
                                debugPrint('❌ Firestore 삭제 실패: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Firestore 삭제 실패: $e')),
                                );
                              }
                            }

                            // 로컬 리스트에서도 제거
                            setState(() => _tasks.removeWhere((t) => t.id == task.id));
                            _saveTasksToPrefs();
                          },
                        ),
                      ],
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    DateTime startDate = DateTime.now();
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
                    const Text('시작일: '),
                    Text(
                      '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => startDate = picked);
                        }
                      },
                      child: const Text('선택'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('기한: '),
                    Text(
                      '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
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
                      child: const Text('선택'),
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
                      startDate: startDate,
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
