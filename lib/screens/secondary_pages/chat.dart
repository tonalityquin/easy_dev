import 'package:flutter/material.dart';
import '../../widgets/navigation/management_navigation.dart'; // 상단 내비게이션 바


class Chat extends StatelessWidget {
  const Chat({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ManagementNavigation(),

      body: const Center(
        child: Text('Chat Page'),
      ),
    );
  }
}
