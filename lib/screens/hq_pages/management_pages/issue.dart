import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../states/user/user_state.dart';

class Issue extends StatefulWidget {
  const Issue({super.key});

  @override
  State<Issue> createState() => _IssueState();
}

class _IssueState extends State<Issue> {
  final TextEditingController _issueController = TextEditingController();
  List<Map<String, dynamic>> _answers = [];

  @override
  void initState() {
    super.initState();
    _fetchAnswers();
  }

  Future<void> _fetchAnswers() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final user = context.read<UserState>().user;
      if (user == null || user.divisions.isEmpty) return;

      final division = user.divisions.first;

      final snapshot = await firestore
          .collection('tasks')
          .where('division', isEqualTo: division)
          .get();

      final filtered = snapshot.docs.where((doc) => doc.data().containsKey('answer'));

      final fetched = filtered.map((doc) {
        final data = doc.data();
        return {
          'answer': data['answer'] ?? '',
          'createdAt': data['createdAt'] ?? '',
        };
      }).toList();

      fetched.sort((a, b) {
        final aDate = DateTime.tryParse(a['createdAt']) ?? DateTime(0);
        final bDate = DateTime.tryParse(b['createdAt']) ?? DateTime(0);
        return aDate.compareTo(bDate);
      });

      setState(() {
        _answers = fetched;
      });
    } catch (e) {
      debugPrint('❌ 응답 불러오기 실패: $e');
    }
  }

  Future<void> _handleSubmit() async {
    final content = _issueController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내용을 입력해주세요.')),
      );
      return;
    }

    try {
      final user = context.read<UserState>().user;
      final firestore = FirebaseFirestore.instance;

      await firestore.collection('tasks').add({
        'issue': {
          'id': DateTime.now().microsecondsSinceEpoch,
          'title': content,
          'description': content,
          'isCompleted': false,
        },
        'createdAt': DateTime.now().toIso8601String(),
        if (user != null) ...{
          'creator': user.id,
          'division': user.divisions.isNotEmpty ? user.divisions.first : 'default',
        },
      });

      debugPrint('📨 이슈 저장 완료: $content');
      _issueController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('보고가 제출되었습니다.')),
      );

      _fetchAnswers();
    } catch (e) {
      debugPrint('❌ 이슈 저장 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 중 오류 발생: $e')),
      );
    }
  }

  Future<void> _deleteNonTaskDocuments() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore.collection('tasks').get();

      final deletableDocs = snapshot.docs.where((doc) => !doc.data().containsKey('task'));

      for (final doc in deletableDocs) {
        await doc.reference.delete();
        debugPrint('🗑️ 삭제됨: ${doc.id}');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이슈가 성공적으로 내려졌습니다.')),
      );

      _fetchAnswers();
    } catch (e) {
      debugPrint('❌ 이슈 삭제 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이슈 내리기 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('본사 이슈 입력'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('HQ 이슈 보고란', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _issueController,
              decoration: const InputDecoration(
                labelText: '보고란 내용',
                hintText: '예: 특별 상황, 민원, 기타 보고 사항 입력',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: _deleteNonTaskDocuments,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                  child: const Text('이슈 내리기'),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _issueController.clear(),
                      child: const Text('지우기'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('제출'),
                      onPressed: _handleSubmit,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            Text(
              '응답 목록 (${_answers.length}개)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _answers.isEmpty
                  ? const Text('응답이 없습니다.')
                  : ListView.builder(
                itemCount: _answers.length,
                itemBuilder: (context, index) {
                  final answer = _answers[index];
                  return ListTile(
                    title: Text(answer['answer']),
                    subtitle: Text(answer['createdAt'].toString().split('T').first),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
