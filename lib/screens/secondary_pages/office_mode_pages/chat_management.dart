import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../../../states/area/area_state.dart';

class ChatManagement extends StatefulWidget {
  const ChatManagement({super.key});

  @override
  State<ChatManagement> createState() => _ChatManagementState();
}

class _ChatManagementState extends State<ChatManagement> {
  final _firestore = FirebaseFirestore.instance;
  final List<_ChatItem> _chatItems = [];
  bool _loading = true;

  static const List<String> purposes = [
    'team',
    'clockin',
    'personal',
    'headquarter',
  ];

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

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

  void _handleMenuSelection(BuildContext context, String value) {
    if (value == 'logout') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃 기능 미구현')),
      );
    }
  }

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
          title: const Text('새 채팅방 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: prefixController,
                  decoration: const InputDecoration(
                    labelText: 'Prefix',
                    hintText: '예: 팀1',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Division: $division\nCurrent Area: $currentArea',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 12),
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

                if (prefix.isEmpty || selectedPurpose == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('모든 항목을 입력해주세요.')),
                  );
                  return;
                }

                final docId = '${prefix}_${division}_$currentArea';

                await _firestore.collection('export_link').doc(docId).set({
                  'name': '$prefix - $division - $currentArea',
                  'prefix': prefix,
                  'division': division,
                  'area': currentArea,
                  'purpose': selectedPurpose,
                  'url': '',
                });

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

  void _editItem(int index) {
    final item = _chatItems[index];
    final nameController = TextEditingController(text: item.name);
    final urlController = TextEditingController(text: item.url);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('채팅방 정보 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '채팅방 이름',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: '오픈카톡 URL',
                ),
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

                await _firestore
                    .collection('export_link')
                    .doc(item.id)
                    .update({'name': updatedName, 'url': updatedUrl});

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
          '채팅',
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chatItems.isEmpty
          ? const Center(child: Text('추가된 채팅방이 없습니다.'))
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
                IconButton(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () async {
                    if (item.url.isNotEmpty) {
                      final uri = Uri.parse(item.url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('링크를 열 수 없습니다.'),
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewItem,
        child: const Icon(Icons.add),
      ),
    );
  }
}

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
