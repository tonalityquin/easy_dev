import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/user_model.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';

class WorkerDocument extends StatefulWidget {
  const WorkerDocument({Key? key}) : super(key: key);

  @override
  State<WorkerDocument> createState() => _WorkerDocumentState();
}

class _WorkerDocumentState extends State<WorkerDocument>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  String _savedText = '';
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _loadSavedText();
  }

  Future<void> _loadSavedText() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedText = prefs.getString('worker_text') ?? '';
    });
  }

  Future<void> _appendText() async {
    final prefs = await SharedPreferences.getInstance();
    final newText = _controller.text.trim();
    if (newText.isEmpty) return;

    final updatedText = (_savedText + '  ' + newText).trim();
    await prefs.setString('worker_text', updatedText);
    setState(() {
      _savedText = updatedText;
      _controller.clear();
      _menuOpen = false;
    });

    showSuccessSnackbar(context, '저장 완료');
  }

  Future<void> _clearText() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('worker_text');
    setState(() {
      _savedText = '';
      _menuOpen = false;
    });

    showSuccessSnackbar(context, '전체 삭제 완료');
  }

  /// Firestore에서 선택된 지역에 해당하는 직원 목록 가져오기
  Future<List<UserModel>> getUsersByArea(String area) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('user_accounts')
        .where('area', isEqualTo: area)
        .get();

    return snapshot.docs
        .map((doc) => UserModel.fromMap(doc.id, doc.data()))
        .toList();
  }

  /// 셀 위젯 생성
  Widget _buildCell(String text, {bool isHeader = false}) {
    return Container(
      width: 60,
      height: 40,
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        color: isHeader ? Colors.grey.shade200 : Colors.white,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedArea = context.watch<AreaState>().currentArea;

    return Scaffold(
      appBar: AppBar(
        title: const Text('직원 문서'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              maxLines: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '추가할 문구 입력',
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '저장된 내용 미리보기 (좌→우 스크롤 가능):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      _savedText,
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '직원 근무 테이블 (${selectedArea.isNotEmpty ? selectedArea : "지역 미선택"})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<UserModel>>(
              future: getUsersByArea(selectedArea),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return Text('에러 발생: ${snapshot.error}');
                }

                final users = snapshot.data ?? [];

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: [
                      // 날짜 헤더
                      Row(
                        children: List.generate(33, (index) {
                          if (index == 0 || index == 32) {
                            return _buildCell('');
                          } else {
                            return _buildCell('$index', isHeader: true);
                          }
                        }),
                      ),
                      const SizedBox(height: 8),
                      // 사용자별 행 생성
                      ...users.map((user) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: List.generate(33, (index) {
                              if (index == 0) {
                                return _buildCell(user.name, isHeader: true);
                              } else {
                                return _buildCell('');
                              }
                            }),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _menuOpen
                ? Column(
              key: const ValueKey(true),
              children: [
                FloatingActionButton(
                  heroTag: 'saveBtn',
                  mini: true,
                  onPressed: _appendText,
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.save),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'clearBtn',
                  mini: true,
                  onPressed: _clearText,
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.delete),
                ),
                const SizedBox(height: 12),
              ],
            )
                : const SizedBox.shrink(key: ValueKey(false)),
          ),
          FloatingActionButton(
            heroTag: 'mainFab',
            onPressed: () {
              setState(() {
                _menuOpen = !_menuOpen;
              });
            },
            backgroundColor: Colors.blueAccent,
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 300),
              turns: _menuOpen ? 0.25 : 0.0,
              child: const Icon(Icons.more_vert),
            ),
          ),
        ],
      ),
    );
  }
}
