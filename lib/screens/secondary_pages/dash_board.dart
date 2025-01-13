import 'package:flutter/material.dart';
import '../../widgets/navigation/management_navigation.dart'; // 상단 내비게이션 바

class DashBoard extends StatelessWidget {
  const DashBoard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ManagementNavigation(),
      body: const Center(
        child: Text('DashBoard Page'),
      ),
    );
  }
}
