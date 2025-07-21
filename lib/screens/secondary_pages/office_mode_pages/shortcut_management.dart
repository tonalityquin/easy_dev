import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../../../states/area/area_state.dart';

class ShortcutManagement extends StatefulWidget {
  const ShortcutManagement({super.key});

  @override
  State<ShortcutManagement> createState() => _ShortcutManagementState();
}

class _ShortcutManagementState extends State<ShortcutManagement> {
  final _firestore = FirebaseFirestore.instance;
  final List<_ChatItem> _chatItems = [];
  bool _loading = true;

  // 쇼트컷 목적(purpose) 종류 정의
  static const List<String> purposes = [
    'team',
    'clockin',
    'personal',
    'headquarter',
  ];

  @override
  void initState() {
    super.initState();
    _loadChats(); // Firestore 데이터 불러오기
  }

  /// Firestore에서 export_link 데이터를 로드하여 리스트에 세팅
  Future<void> _loadChats() async {
    final snapshot = await _firestore.collection('export_link').get();
    final items = snapshot.docs.map((doc) {
      return _ChatItem(
        id: doc.id,
        name: doc['name'] ?? '이름 없음',
        url: doc['url'] ?? '',
        purpose: doc['purpose'] ?? '',
      );
    }).toList();

    setState(() {
      _chatItems
        ..clear()
        ..addAll(items);
      _loading = false;
    });
  }

  /// 메뉴 항목 선택 핸들러 (예: 로그아웃)
  void _handleMenuSelection(BuildContext context, String value) {
    if (value == 'logout') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃 기능 미구현')),
      );
    }
  }

  /// 새로운 쇼트컷 추가 다이얼로그 표시 및 저장 처리
  void _addNewItem() {
    final prefixController = TextEditingController();
    String? selectedPurpose;

    showDialog(
      context: context,
      builder: (context) {
        final areaState = context.read<AreaState>();
        final division = areaState.currentDivision;
        final currentArea = areaState.currentArea;

        return AlertDialog(
          title: const Text('새 쇼트컷 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Prefix 입력
                TextField(
                  controller: prefixController,
                  decoration: const InputDecoration(
                    labelText: 'Prefix',
                    hintText: '예: 팀1',
                  ),
                ),
                const SizedBox(height: 8),
                // Division, Area 표시 (읽기 전용)
                Text(
                  'Division: $division\nCurrent Area: $currentArea',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                // 목적 선택
                DropdownButtonFormField<String>(
                  value: selectedPurpose,
                  decoration: const InputDecoration(
                    labelText: '사용 목적',
                    border: OutlineInputBorder(),
                  ),
                  items: purposes
                      .map((p) => DropdownMenuItem(
                    value: p,
                    child: Text(p),
                  ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedPurpose = value;
                    });
                  },
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
              onPressed: () async {
                final prefix = prefixController.text.trim();

                // 필수값 확인
                if (prefix.isEmpty || selectedPurpose == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('모든 항목을 입력해주세요.')),
                  );
                  return;
                }

                final docId = '${prefix}_${division}_$currentArea';

                // Firestore에 문서 저장
                await _firestore.collection('export_link').doc(docId).set({
                  'name': '$prefix - $division - $currentArea',
                  'prefix': prefix,
                  'division': division,
                  'area': currentArea,
                  'purpose': selectedPurpose,
                  'url': '',
                });

                // UI에 추가
                setState(() {
                  _chatItems.add(
                    _ChatItem(
                      id: docId,
                      name: '$prefix - $division - $currentArea',
                      url: '',
                      purpose: selectedPurpose!,
                    ),
                  );
                });

                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('추가'),
            ),
          ],
        );
      },
    );
  }

  /// 쇼트컷 정보 수정 다이얼로그
  void _editItem(int index) {
    final item = _chatItems[index];
    final nameController = TextEditingController(text: item.name);
    final urlController = TextEditingController(text: item.url);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('쇼트컷 정보 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '쇼트컷 이름'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: '오픈카톡 URL'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updatedName = nameController.text.trim();
                final updatedUrl = urlController.text.trim();

                // Firestore 문서 업데이트
                await _firestore
                    .collection('export_link')
                    .doc(item.id)
                    .update({'name': updatedName, 'url': updatedUrl});

                // UI 업데이트
                setState(() {
                  _chatItems[index] = _ChatItem(
                    id: item.id,
                    name: updatedName,
                    url: updatedUrl,
                    purpose: item.purpose,
                  );
                });

                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
  }

  /// 선택한 쇼트컷 삭제 처리
  Future<void> _deleteItem(int index) async {
    final item = _chatItems[index];

    await _firestore.collection('export_link').doc(item.id).delete();

    setState(() {
      _chatItems.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.name} 삭제 완료')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '쇼트컷',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuSelection(context, value),
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('로그아웃'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),

      // 본문 영역
      body: _loading
          ? const Center(child: CircularProgressIndicator()) // 로딩 중
          : _chatItems.isEmpty
          ? const Center(child: Text('추가된 쇼트컷이 없습니다.')) // 데이터 없음
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _chatItems.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final item = _chatItems[index];

          return ListTile(
            title: Text(item.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.url.isEmpty ? 'URL 미입력' : item.url),
                Text('목적: ${item.purpose}', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            onTap: () => _editItem(index),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 외부 URL 열기
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () async {
                    if (item.url.isNotEmpty) {
                      final uri = Uri.parse(item.url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('링크를 열 수 없습니다.')),
                          );
                        }
                      }
                    }
                  },
                ),
                // 삭제 아이콘
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('삭제 확인'),
                        content: Text('${item.name}을(를) 삭제하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('취소'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('삭제'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await _deleteItem(index);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),

      // 새 항목 추가 버튼
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: _addNewItem,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 쇼트컷 항목 데이터 클래스
class _ChatItem {
  final String id;
  final String name;
  final String url;
  final String purpose;

  _ChatItem({
    required this.id,
    required this.name,
    required this.url,
    required this.purpose,
  });
}
