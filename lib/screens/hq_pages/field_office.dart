import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바

class FieldOffice extends StatelessWidget {
  const FieldOffice({super.key});

  void _handleMenuSelection(BuildContext context, String value) {
    if (value == 'logout') {
      // 로그아웃 로직 연결 필요 시 여기에 구현
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그아웃 기능 미구현')),
      );
    }
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
      body: const Center(
        child: Text('Chat Page'),
      ),
      bottomNavigationBar: const SecondaryMiniNavigation(
        icons: [
          Icons.search,
          Icons.person,
          Icons.sort,
        ],
      ),
    );
  }
}
