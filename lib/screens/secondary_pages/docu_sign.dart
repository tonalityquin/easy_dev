import 'package:flutter/material.dart';
import '../../widgets/navigation/management_navigation.dart'; // 상단 내비게이션 바

class DocuSign extends StatelessWidget {
  const DocuSign({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ManagementNavigation(),
      body: const Center(
        child: Text('DocuSign Page'),
      ),
    );
  }
}
